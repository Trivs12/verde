//! Composer widget, focus, picker, attachment-hit, run-config, and model &
//! settings menu state.

const std = @import("std");
const palette = @import("palette");
const provider_models = @import("provider_models.zig");

const Provider = provider_models.Provider;

/// Rows of the model & settings menu anchored above the composer's merged
/// model label, in display order. Fast and Effort appear only when the
/// current provider/model supports them.
pub const SettingsRow = enum {
    fast,
    effort,
    access,
    model,

    /// The cascading submenu this row opens; Fast toggles in place.
    pub fn submenu(self: SettingsRow) ?SettingsSubmenu {
        return switch (self) {
            .fast => null,
            .effort => .effort,
            .access => .access,
            .model => .model,
        };
    }
};

/// Cascading submenus of the settings menu: Effort and Access use the small
/// option picker, Model reuses the rich model picker.
pub const SettingsSubmenu = enum {
    effort,
    access,
    model,
};

/// Fills `out` with the settings rows that apply, in display order: Fast
/// only when the provider has a speed tier, Effort only when the model
/// exposes reasoning levels; Access and Model always show.
pub fn settingsRows(show_fast: bool, effort_option_count: usize, out: *[4]SettingsRow) usize {
    var count: usize = 0;
    if (show_fast) {
        out[count] = .fast;
        count += 1;
    }
    if (effort_option_count > 0) {
        out[count] = .effort;
        count += 1;
    }
    out[count] = .access;
    count += 1;
    out[count] = .model;
    count += 1;
    return count;
}

/// What activating (click, Enter, Space, Right) a settings row does.
pub const SettingsActivation = union(enum) {
    /// Flip fast mode; the payload is the new state for `.fast_changed`.
    fast_changed: bool,
    open_submenu: SettingsSubmenu,
};

pub fn settingsRowActivation(row: SettingsRow, fast_on: bool) SettingsActivation {
    if (row.submenu()) |submenu| return .{ .open_submenu = submenu };
    return .{ .fast_changed = !fast_on };
}

pub const SettingsKey = enum { up, down, left, right, enter, space, escape };

/// Menu-level key handling once no submenu owns the key: Escape / Left
/// close an open submenu first and the menu second.
pub const SettingsKeyAction = union(enum) {
    close_submenu,
    close_menu,
    focus_row: usize,
    activate_row: usize,
};

pub fn settingsKeyAction(key: SettingsKey, focused_row: usize, row_count: usize, submenu_open: bool) SettingsKeyAction {
    if (row_count == 0) return .close_menu;
    const row = @min(focused_row, row_count - 1);
    return switch (key) {
        .escape, .left => if (submenu_open) .close_submenu else .close_menu,
        .up => .{ .focus_row = (row + row_count - 1) % row_count },
        .down => .{ .focus_row = (row + 1) % row_count },
        .right, .enter, .space => .{ .activate_row = row },
    };
}

/// How long the pointer must rest on a settings row before hover opens (or
/// switches to) its submenu. Clicks and keys open immediately. This is a
/// hover-intent delay, not motion, so reduced-motion settings keep it.
pub const SETTINGS_HOVER_OPEN_DELAY_MS: i64 = 150;

/// What a pointer move over the settings menu means for the row highlight.
pub const SettingsHoverMove = enum {
    /// Hovering the row changes nothing (no row, or its submenu is showing).
    idle,
    /// A submenu switch is pending; the highlight follows the pointer.
    waiting,
    /// The pointer is heading into the open submenu across other rows; the
    /// highlight stays on the open submenu's row.
    aiming,
};

/// Hover intent for the settings menu: hovering a row schedules its
/// submenu instead of opening it, so sweeping up from the label across the
/// Model row, or diagonally toward an open submenu, does not flicker lists.
/// Palette has no timers; the host polls `takeDue` and caps its event wait
/// on `wakeMs`.
pub const SettingsHoverIntent = struct {
    pending_row: ?usize = null,
    deadline_ms: i64 = 0,
    last_point: ?palette.draw.Vec2 = null,

    pub fn reset(self: *SettingsHoverIntent) void {
        self.* = .{};
    }

    /// Pointer at `point` over settings row `row` (null off the rows).
    /// `needs_switch` is whether resting there would change the open
    /// submenu; `submenu_rect` is the open submenu's bounds, if any.
    pub fn noteMove(
        self: *SettingsHoverIntent,
        point: palette.draw.Vec2,
        row: ?usize,
        needs_switch: bool,
        submenu_rect: ?palette.Rect,
        now_ms: i64,
    ) SettingsHoverMove {
        const previous = self.last_point;
        self.last_point = point;
        const target = row orelse {
            self.pending_row = null;
            return .idle;
        };
        if (!needs_switch) {
            self.pending_row = null;
            return .idle;
        }
        const aiming = if (submenu_rect) |rect|
            if (previous) |from| movingTowardRect(from, point, rect) else false
        else
            false;
        // Motion toward the open submenu is not resting: keep pushing the
        // deadline so the switch waits until the pointer settles.
        if (aiming or self.pending_row != target) {
            self.pending_row = target;
            self.deadline_ms = now_ms + SETTINGS_HOVER_OPEN_DELAY_MS;
        }
        return if (aiming) .aiming else .waiting;
    }

    /// The row whose delay elapsed by `now_ms`, clearing it.
    pub fn takeDue(self: *SettingsHoverIntent, now_ms: i64) ?usize {
        const row = self.pending_row orelse return null;
        if (now_ms < self.deadline_ms) return null;
        self.pending_row = null;
        return row;
    }

    /// Milliseconds until the pending row is due (0 when overdue).
    pub fn wakeMs(self: SettingsHoverIntent, now_ms: i64) ?i64 {
        if (self.pending_row == null) return null;
        return @max(self.deadline_ms - now_ms, 0);
    }
};

/// True when moving `from` -> `to` heads into `rect`: `to` lies inside the
/// triangle spanned by `from` and the rect's near vertical edge (the
/// classic submenu "safe triangle").
pub fn movingTowardRect(from: palette.draw.Vec2, to: palette.draw.Vec2, rect: palette.Rect) bool {
    if (from.x == to.x and from.y == to.y) return false;
    const near_x = if (rect.x >= from.x) rect.x else rect.x + rect.w;
    const top: palette.draw.Vec2 = .{ .x = near_x, .y = rect.y };
    const bottom: palette.draw.Vec2 = .{ .x = near_x, .y = rect.y + rect.h };
    const d1 = cross(from, top, to);
    const d2 = cross(top, bottom, to);
    const d3 = cross(bottom, from, to);
    const has_neg = d1 < 0.0 or d2 < 0.0 or d3 < 0.0;
    const has_pos = d1 > 0.0 or d2 > 0.0 or d3 > 0.0;
    return !(has_neg and has_pos);
}

fn cross(a: palette.draw.Vec2, b: palette.draw.Vec2, p: palette.draw.Vec2) f32 {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

/// CSS-unit geometry of the settings menu (scaled by the caller's factor).
pub const SETTINGS_MENU_WIDTH: f32 = 260.0;
pub const SETTINGS_MENU_PADDING: f32 = 6.0;
pub const SETTINGS_MENU_ROW_HEIGHT: f32 = 32.0;
/// Vertical room for the hairline above the Model row (line + air).
pub const SETTINGS_MENU_DIVIDER_SPAN: f32 = 9.0;
/// Gap between the menu and the label it opens from.
pub const SETTINGS_MENU_ANCHOR_GAP: f32 = 8.0;
/// Closest the menu may come to the top of the window.
pub const SETTINGS_MENU_TOP_INSET: f32 = 8.0;

pub const SettingsMenuLayout = struct {
    panel: palette.Rect,
    rows: [4]palette.Rect,
    kinds: [4]SettingsRow,
    count: usize,
    /// Hairline above the Model row; zero height when Model leads the menu.
    divider: palette.Rect,

    pub fn rowAt(self: SettingsMenuLayout, point: palette.draw.Vec2) ?usize {
        for (self.rows[0..self.count], 0..) |row, index| {
            if (row.contains(point)) return index;
        }
        return null;
    }

    pub fn indexOf(self: SettingsMenuLayout, kind: SettingsRow) ?usize {
        for (self.kinds[0..self.count], 0..) |row_kind, index| {
            if (row_kind == kind) return index;
        }
        return null;
    }
};

/// Places the settings menu above `anchor` (the merged model label),
/// right-aligned to it and clamped inside `bounds` horizontally and below
/// the window top.
pub fn layoutSettingsMenu(anchor: palette.Rect, bounds: palette.Rect, kinds: []const SettingsRow, scale: f32) SettingsMenuLayout {
    const zero: palette.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    var layout: SettingsMenuLayout = .{
        .panel = zero,
        .rows = .{ zero, zero, zero, zero },
        .kinds = .{ .fast, .effort, .access, .model },
        .count = @min(kinds.len, 4),
        .divider = zero,
    };
    const pad = SETTINGS_MENU_PADDING * scale;
    const row_h = SETTINGS_MENU_ROW_HEIGHT * scale;
    const divider_span = SETTINGS_MENU_DIVIDER_SPAN * scale;
    var height = pad * 2.0 + row_h * @as(f32, @floatFromInt(layout.count));
    for (kinds[0..layout.count], 0..) |kind, index| {
        layout.kinds[index] = kind;
        if (kind == .model and index > 0) height += divider_span;
    }
    const width = @min(SETTINGS_MENU_WIDTH * scale, @max(bounds.w, 0.0));
    const right = anchor.x + anchor.w;
    const x = @max(bounds.x, @min(right - width, bounds.x + bounds.w - width));
    const y = @max(anchor.y - SETTINGS_MENU_ANCHOR_GAP * scale - height, SETTINGS_MENU_TOP_INSET * scale);
    layout.panel = .{ .x = @round(x), .y = @round(y), .w = @round(width), .h = @round(height) };

    var cursor_y = layout.panel.y + pad;
    for (layout.kinds[0..layout.count], 0..) |kind, index| {
        if (kind == .model and index > 0) {
            layout.divider = .{ .x = layout.panel.x + pad * 2.0, .y = @round(cursor_y + divider_span * 0.5), .w = @max(layout.panel.w - pad * 4.0, 0.0), .h = @max(@round(scale), 1.0) };
            cursor_y += divider_span;
        }
        layout.rows[index] = .{ .x = layout.panel.x + pad, .y = @round(cursor_y), .w = @max(layout.panel.w - pad * 2.0, 0.0), .h = @round(row_h) };
        cursor_y += row_h;
    }
    return layout;
}

pub fn State(
    comptime ComposerPrompt: type,
    comptime ModelPicker: type,
    comptime ModelPickerEntry: type,
    comptime DirectoryPicker: type,
    comptime DirectoryPickerEntry: type,
    comptime RuntimePicker: type,
    comptime RunStepper: type,
    comptime RunStepperContext: type,
    comptime SettingsOptionPicker: type,
) type {
    return struct {
        focused: bool = false,
        bang_history_message_index: ?usize = null,
        input_nonce: u32 = 0,
        input_bounds_valid: bool = false,
        input_min: [2]f32 = .{ 0.0, 0.0 },
        input_max: [2]f32 = .{ 0.0, 0.0 },
        send_bounds_valid: bool = false,
        send_min: [2]f32 = .{ 0.0, 0.0 },
        send_max: [2]f32 = .{ 0.0, 0.0 },
        send_pressed: bool = false,
        send_hovered: bool = false,
        draft_image_clear_valid: bool = false,
        draft_image_clear_rect: palette.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        draft_image_clear_index: usize = 0,
        draft_image_clear_count: usize = 0,
        draft_image_clear_rects: [16]palette.Rect = [_]palette.Rect{.{ .x = 0, .y = 0, .w = 0, .h = 0 }} ** 16,
        draft_image_clear_indices: [16]usize = [_]usize{0} ** 16,
        overlay_scroll_y: f32 = 0.0,
        overlay_follow_cursor: bool = true,
        overlay_last_cursor_pos: usize = 0,
        overlay_last_draft_len: usize = 0,
        toolbar_overlay_valid: bool = false,
        toolbar_directory_rect: palette.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        toolbar_runtime_rect: palette.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        toolbar_model_rect: palette.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        toolbar_reasoning_rect: palette.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        toolbar_fast_rect: palette.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        toolbar_access_rect: palette.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        composer: ComposerPrompt,
        model_picker: ModelPicker,
        model_picker_entries: std.ArrayList(ModelPickerEntry) = .empty,
        directory_picker: DirectoryPicker,
        directory_picker_entries: std.ArrayList(DirectoryPickerEntry) = .empty,
        /// Per-thread runtime chooser on the directory strip. Local is built
        /// in; configured remote rows and their statuses come from Service.
        runtime_picker: RuntimePicker,
        /// Set while the shared folder dialog was opened from the directory
        /// picker's Browse row, so `pollPicker` routes the result to the
        /// current thread instead of the workspace importer.
        browse_for_chat_directory: bool = false,
        /// Lazily resolved absolute paths behind the Home / Scratch rows and
        /// the matching pill labels.
        home_path: ?[]const u8 = null,
        scratch_path: ?[]const u8 = null,
        run_config_open: bool = false,
        popover_restore_focus: bool = false,
        run_config_focused_row: usize = 0,
        run_config_last_tick_ms: i64 = 0,
        run_steppers: [3]RunStepper,
        run_stepper_contexts: [3]RunStepperContext = .{ .{}, .{}, .{} },
        /// Model & settings menu (the merged label's popover).
        settings_open: bool = false,
        /// Highlighted menu row (hover or arrows); null until either.
        settings_focused_row: ?usize = null,
        settings_submenu: ?SettingsSubmenu = null,
        settings_hover: SettingsHoverIntent = .{},
        /// Effort / Access submenu list; the Model submenu is `model_picker`.
        settings_option_picker: SettingsOptionPicker,
        picker_provider: ?Provider = null,
        slash_selected: usize = 0,
        locked_model_picker_open: bool = false,

        const Self = @This();

        pub fn init() Self {
            return .{
                .composer = ComposerPrompt.init(),
                .model_picker = ModelPicker.init(0),
                .directory_picker = DirectoryPicker.init(0),
                .runtime_picker = RuntimePicker.init(0),
                .run_steppers = .{ RunStepper.init(0), RunStepper.init(2), RunStepper.init(2) },
                .settings_option_picker = SettingsOptionPicker.init(0),
            };
        }
    };
}

pub fn requestComposerFocus(self: anytype) void {
    _ = self.acknowledgeFocusedChatCompletion();
    restoreComposerFocus(self);
}

pub fn restoreComposerFocus(self: anytype) void {
    self.composer_controller.composer.focused = true;
    self.composer_controller.focused = true;
    self.terminal_controller.focused = false;
    self.unfocusBrowserPane();
    self.browser_controller.address_focused = false;
}

test "settings rows follow provider capabilities" {
    var rows: [4]SettingsRow = undefined;
    // Codex-like: speed tier and reasoning levels.
    try std.testing.expectEqualSlices(SettingsRow, &.{ .fast, .effort, .access, .model }, rows[0..settingsRows(true, 5, &rows)]);
    // Reasoning but no speed tier.
    try std.testing.expectEqualSlices(SettingsRow, &.{ .effort, .access, .model }, rows[0..settingsRows(false, 3, &rows)]);
    // Neither (e.g. fx): Access and Model always remain.
    try std.testing.expectEqualSlices(SettingsRow, &.{ .access, .model }, rows[0..settingsRows(false, 0, &rows)]);
}

test "settings fast row toggles in place and other rows open submenus" {
    try std.testing.expectEqual(SettingsActivation{ .fast_changed = true }, settingsRowActivation(.fast, false));
    try std.testing.expectEqual(SettingsActivation{ .fast_changed = false }, settingsRowActivation(.fast, true));
    try std.testing.expectEqual(SettingsActivation{ .open_submenu = .effort }, settingsRowActivation(.effort, false));
    try std.testing.expectEqual(SettingsActivation{ .open_submenu = .access }, settingsRowActivation(.access, false));
    try std.testing.expectEqual(SettingsActivation{ .open_submenu = .model }, settingsRowActivation(.model, true));
}

test "settings escape and left close the submenu before the menu" {
    try std.testing.expectEqual(SettingsKeyAction.close_submenu, settingsKeyAction(.escape, 1, 4, true));
    try std.testing.expectEqual(SettingsKeyAction.close_menu, settingsKeyAction(.escape, 1, 4, false));
    try std.testing.expectEqual(SettingsKeyAction.close_submenu, settingsKeyAction(.left, 0, 4, true));
    try std.testing.expectEqual(SettingsKeyAction.close_menu, settingsKeyAction(.left, 0, 4, false));
    // Up/Down wrap; Right/Enter/Space activate the focused row.
    try std.testing.expectEqual(SettingsKeyAction{ .focus_row = 3 }, settingsKeyAction(.up, 0, 4, false));
    try std.testing.expectEqual(SettingsKeyAction{ .focus_row = 0 }, settingsKeyAction(.down, 3, 4, false));
    try std.testing.expectEqual(SettingsKeyAction{ .activate_row = 2 }, settingsKeyAction(.space, 2, 4, false));
    try std.testing.expectEqual(SettingsKeyAction{ .activate_row = 1 }, settingsKeyAction(.enter, 9, 2, false));
}

test "settings menu sits above the label right-aligned and inside the pane" {
    const kinds = [_]SettingsRow{ .fast, .effort, .access, .model };
    const anchor: palette.Rect = .{ .x = 700, .y = 600, .w = 140, .h = 30 };
    const bounds: palette.Rect = .{ .x = 100, .y = 560, .w = 760, .h = 110 };
    const layout = layoutSettingsMenu(anchor, bounds, &kinds, 1.0);
    try std.testing.expectEqual(anchor.x + anchor.w, layout.panel.x + layout.panel.w);
    try std.testing.expect(layout.panel.y + layout.panel.h <= anchor.y);
    try std.testing.expectEqual(@as(usize, 4), layout.count);
    // Rows stack without overlap and the divider sits between Access and Model.
    var index: usize = 1;
    while (index < layout.count) : (index += 1) {
        try std.testing.expect(layout.rows[index - 1].y + layout.rows[index - 1].h <= layout.rows[index].y);
    }
    try std.testing.expect(layout.divider.y >= layout.rows[2].y + layout.rows[2].h and layout.divider.y < layout.rows[3].y);
    try std.testing.expectEqual(@as(?usize, 3), layout.rowAt(.{ .x = layout.rows[3].x + 4, .y = layout.rows[3].y + 4 }));
    try std.testing.expectEqual(@as(?usize, 3), layout.indexOf(.model));

    // A label near the pane's left edge keeps the menu inside the pane.
    const left = layoutSettingsMenu(.{ .x = 110, .y = 600, .w = 60, .h = 30 }, bounds, kinds[2..], 1.0);
    try std.testing.expectEqual(bounds.x, left.panel.x);
    try std.testing.expect(left.divider.w > 0.0 and left.divider.h >= 1.0);
    // Model alone would lead the menu without a divider.
    try std.testing.expectEqual(@as(f32, 0.0), layoutSettingsMenu(anchor, bounds, kinds[3..], 1.0).divider.h);
}

test "settings hover opens a row's submenu only after it rests for the delay" {
    var intent: SettingsHoverIntent = .{};
    // Crossing the Model row on the way up schedules it...
    try std.testing.expectEqual(SettingsHoverMove.waiting, intent.noteMove(.{ .x = 50, .y = 130 }, 3, true, null, 1000));
    try std.testing.expectEqual(@as(?i64, SETTINGS_HOVER_OPEN_DELAY_MS), intent.wakeMs(1000));
    try std.testing.expectEqual(@as(?usize, null), intent.takeDue(1100));
    // ...but reaching another row restarts the delay for that row.
    try std.testing.expectEqual(SettingsHoverMove.waiting, intent.noteMove(.{ .x = 50, .y = 90 }, 2, true, null, 1100));
    try std.testing.expectEqual(@as(?usize, null), intent.takeDue(1000 + SETTINGS_HOVER_OPEN_DELAY_MS));
    // Small moves within the row do not restart it.
    _ = intent.noteMove(.{ .x = 60, .y = 92 }, 2, true, null, 1200);
    try std.testing.expectEqual(@as(?i64, 50), intent.wakeMs(1200));
    try std.testing.expectEqual(@as(?usize, 2), intent.takeDue(1100 + SETTINGS_HOVER_OPEN_DELAY_MS));
    try std.testing.expectEqual(@as(?usize, null), intent.takeDue(2000));
    try std.testing.expectEqual(@as(?i64, null), intent.wakeMs(2000));

    // Leaving the rows, or resting where nothing would change, cancels.
    _ = intent.noteMove(.{ .x = 50, .y = 60 }, 1, true, null, 3000);
    try std.testing.expectEqual(SettingsHoverMove.idle, intent.noteMove(.{ .x = 50, .y = 10 }, null, true, null, 3010));
    try std.testing.expectEqual(@as(?usize, null), intent.takeDue(4000));
    _ = intent.noteMove(.{ .x = 50, .y = 60 }, 1, true, null, 4000);
    try std.testing.expectEqual(SettingsHoverMove.idle, intent.noteMove(.{ .x = 50, .y = 62 }, 1, false, null, 4010));
    try std.testing.expectEqual(@as(?usize, null), intent.takeDue(5000));
}

test "settings hover keeps the open submenu while the pointer aims at it" {
    // Menu rows span x 0..260; the open Model list sits to the right and
    // reaches up from the Model row.
    const submenu: palette.Rect = .{ .x = 270, .y = 0, .w = 200, .h = 160 };
    var intent: SettingsHoverIntent = .{};
    _ = intent.noteMove(.{ .x = 100, .y = 150 }, 3, false, submenu, 0);
    // Diagonal motion up-right across the Access row toward the list.
    try std.testing.expectEqual(SettingsHoverMove.aiming, intent.noteMove(.{ .x = 140, .y = 120 }, 2, true, submenu, 10));
    try std.testing.expectEqual(SettingsHoverMove.aiming, intent.noteMove(.{ .x = 180, .y = 100 }, 2, true, submenu, 100));
    // Still aiming on the same row keeps pushing the switch out.
    try std.testing.expectEqual(SettingsHoverMove.aiming, intent.noteMove(.{ .x = 220, .y = 90 }, 2, true, submenu, 200));
    try std.testing.expectEqual(@as(?usize, null), intent.takeDue(200 + SETTINGS_HOVER_OPEN_DELAY_MS - 1));
    // Settling on the row switches after the delay from the last aimed move.
    try std.testing.expectEqual(@as(?usize, 2), intent.takeDue(200 + SETTINGS_HOVER_OPEN_DELAY_MS));

    // Moving away from the submenu is an ordinary delayed hover.
    intent.reset();
    _ = intent.noteMove(.{ .x = 200, .y = 50 }, 1, false, submenu, 0);
    try std.testing.expectEqual(SettingsHoverMove.waiting, intent.noteMove(.{ .x = 150, .y = 90 }, 2, true, submenu, 10));
    try std.testing.expectEqual(SettingsHoverMove.waiting, intent.noteMove(.{ .x = 140, .y = 95 }, 2, true, submenu, 20));
    try std.testing.expectEqual(@as(?usize, 2), intent.takeDue(10 + SETTINGS_HOVER_OPEN_DELAY_MS));
}

test "safe triangle uses the submenu's near edge on either side" {
    const right: palette.Rect = .{ .x = 300, .y = 0, .w = 100, .h = 100 };
    try std.testing.expect(movingTowardRect(.{ .x = 100, .y = 150 }, .{ .x = 120, .y = 140 }, right));
    try std.testing.expect(!movingTowardRect(.{ .x = 100, .y = 150 }, .{ .x = 100, .y = 170 }, right));
    try std.testing.expect(!movingTowardRect(.{ .x = 100, .y = 150 }, .{ .x = 80, .y = 140 }, right));
    try std.testing.expect(!movingTowardRect(.{ .x = 100, .y = 150 }, .{ .x = 100, .y = 150 }, right));
    const left: palette.Rect = .{ .x = 0, .y = 0, .w = 100, .h = 100 };
    try std.testing.expect(movingTowardRect(.{ .x = 300, .y = 150 }, .{ .x = 280, .y = 140 }, left));
    try std.testing.expect(!movingTowardRect(.{ .x = 300, .y = 150 }, .{ .x = 320, .y = 140 }, left));
}
