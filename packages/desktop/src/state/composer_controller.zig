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
