//! Settings modal for viewing and editing `verde.json` app config.

const std = @import("std");
const build_options = @import("build_options");
const palette = @import("palette");
const sdl = @import("zsdl3");
const app_config = @import("../app/config.zig");
const provider_cli_version = @import("../providers/cli_version.zig");
const settings_controller = @import("../state/settings_controller.zig");
const updater = @import("../app/updater.zig");
const theme = @import("theme.zig");
const runtime = @import("runtime.zig");
const text_measure = @import("text_measure.zig");
const utils = @import("../utils.zig");
const runtime_connections = @import("../state/runtime_connections_controller.zig");

pub const Control = enum(u8) {
    ui_font_dec,
    ui_font_inc,
    terminal_font_dec,
    terminal_font_inc,
    workspace_pane_gap_dec,
    workspace_pane_gap_inc,
    workspace_panes_per_view_dec,
    workspace_panes_per_view_inc,
    workspace_unzoom_on_navigation,
    workspace_scroll_use_global,
    workspace_scroll_override,
    workspace_scroll_mode_automatic,
    workspace_scroll_mode_always,
    workspace_scroll_mode_disabled,
    workspace_scroll_threshold_dec,
    workspace_scroll_threshold_inc,
    workspace_scroll_horizontal,
    workspace_scroll_vertical,
    theme_dropdown,
    reduced_motion,
    reduced_motion_pane_scroll,
    reduced_motion_pane_layout,
    reduced_motion_status_pulse,
    reduced_motion_chat,
    reduced_motion_chrome,
    workspace_tabs_automatic,
    workspace_tabs_always,
    workspace_tabs_disabled,
    companion_character_dropdown,
    ui_font_family_dropdown,
    tool_groups_collapsed,
    tool_groups_expanded,
    tool_groups_remember_last,
    diff_layout_stacked,
    diff_layout_split,
    automatic_chat_titles,
    chat_title_provider_dropdown,
    chat_title_model_dropdown,
    new_chat_provider_dropdown,
    new_chat_model_dropdown,
    new_chat_reasoning_dropdown,
    new_chat_new_pane,
    new_chat_replace_pane,
    workspace_split_default_chat,
    workspace_split_default_terminal,
    workspace_new_tab_chat,
    workspace_new_tab_terminal,
    open_folder,
    open_editor,
    open_cursor,
    open_vscode,
    open_zed,
    open_action_dropdown,
    file_links_neovim_pane,
    links_verde_browser,
    links_system_browser,
    chat_links_global,
    chat_links_verde_browser,
    chat_links_system_browser,
    terminal_links_global,
    terminal_links_verde_browser,
    terminal_links_system_browser,
    browser_scroll_speed,
    companion_toggle,
    mcp_tools,
    hooks_claude,
    hooks_codex,
    hooks_cursor,
    hooks_opencode,
    hooks_grok,
    hooks_amp,
    hooks_pi,
    updates_check,
    updates_download,
    updates_automatic,
    updates_notes_toggle,
    updates_release_page,
    notifications_toggle,
    providers_recheck,
    // One per settings_controller.PROVIDER_OPTIONS row. Each group stays contiguous.
    provider_update_first,
    provider_update_1,
    provider_update_2,
    provider_update_3,
    provider_update_4,
    provider_update_5,
    provider_update_6,
    provider_update_last,
    provider_row_first,
    provider_row_1,
    provider_row_2,
    provider_row_3,
    provider_row_4,
    provider_row_5,
    provider_row_6,
    provider_row_last,
};

const PROVIDER_ROW_COUNT = settings_controller.PROVIDER_OPTIONS.len;

comptime {
    std.debug.assert(@intFromEnum(Control.provider_row_last) - @intFromEnum(Control.provider_row_first) + 1 == PROVIDER_ROW_COUNT);
    std.debug.assert(@intFromEnum(Control.provider_update_last) - @intFromEnum(Control.provider_update_first) + 1 == PROVIDER_ROW_COUNT);
}

fn providerRowControl(row: usize) Control {
    return @enumFromInt(@intFromEnum(Control.provider_row_first) + @as(u8, @intCast(row)));
}

fn providerUpdateControl(row: usize) Control {
    return @enumFromInt(@intFromEnum(Control.provider_update_first) + @as(u8, @intCast(row)));
}

fn providerUpdateRowForControl(control: Control) ?usize {
    const index = @intFromEnum(control);
    if (index < @intFromEnum(Control.provider_update_first) or index > @intFromEnum(Control.provider_update_last)) return null;
    return index - @intFromEnum(Control.provider_update_first);
}

fn providerRowForControl(control: Control) ?usize {
    const index = @intFromEnum(control);
    if (index < @intFromEnum(Control.provider_row_first) or index > @intFromEnum(Control.provider_row_last)) return null;
    return index - @intFromEnum(Control.provider_row_first);
}

const OpenChoice = struct {
    label: []const u8,
    control: Control,
};

const OPEN_CHOICES = [_]OpenChoice{
    .{ .label = "Folder", .control = .open_folder },
    .{ .label = "Editor", .control = .open_editor },
    .{ .label = "Cursor", .control = .open_cursor },
    .{ .label = "VS Code", .control = .open_vscode },
    .{ .label = "Zed", .control = .open_zed },
};

const THEME_MENU_MAX_ROWS: usize = 6;
const TITLE_MENU_MAX_ROWS: usize = 6;
const COMPANION_CHARACTER_OPTIONS = [_]app_config.CompanionCharacter{ .sprout, .moss, .vireo };
const COMPANION_CHARACTER_LABELS = [_][]const u8{ "Sprout", "Moss", "Vireo" };
const UI_FONT_FAMILY_OPTIONS = std.enums.values(app_config.UiFontFamily);
// Lucide (ISC) glyphs drawn through the `icon_alt` role.
const LU_CHEVRON_DOWN = "\u{E06D}";
const LU_CHEVRON_UP = "\u{E070}";
const LU_CHECK = "\u{E06C}";
const LU_X = "\u{E1B2}";
const LU_PLUS = "\u{E13D}";
const LU_MINUS = "\u{E11C}";
/// Lucide has more internal padding than the Codicons it replaced; icons
/// are drawn this much larger about their slot's centre.
const LUCIDE_OPTICAL_SCALE: f32 = 1.08;

/// The Settings artboard is specified in CSS px; app UI units are design px
/// × 1.2 (design body 15px = app 18 units), matching the sidebar's factor.
const DESIGN_SCALE: f32 = 18.0 / 15.0;

fn designUi(px: f32) f32 {
    return theme.scaledUi(px * DESIGN_SCALE);
}

// Dialog shell (design px).
const DIALOG_W: f32 = 920.0;
const DIALOG_H: f32 = 700.0;
const DIALOG_RADIUS: f32 = 18.0;
/// Smallest gap kept between the dialog and the window edge on small windows.
const DIALOG_MIN_MARGIN: f32 = 16.0;
/// Scrim strength behind the dialog: enough to separate it, soft enough that
/// the workspace stays legible while settings live-apply.
const SHELL_SCRIM_ALPHA: f32 = 0.22;

// Left section nav.
const NAV_W: f32 = 210.0;
const NAV_PAD_X: f32 = 10.0;
const NAV_PAD_TOP: f32 = 18.0;
const NAV_TITLE_FONT: f32 = 15.0;
const NAV_TITLE_GAP: f32 = 14.0;
const NAV_ROW_H: f32 = 34.0;
const NAV_ROW_GAP: f32 = 1.0;
const NAV_ROW_RADIUS: f32 = 8.0;
const NAV_ROW_PAD_X: f32 = 10.0;
const NAV_FONT: f32 = 14.0;

// Section header above the scrolling body.
const HEADER_H: f32 = 58.0;
const HEADER_PAD_LEFT: f32 = 32.0;
const HEADER_PAD_RIGHT: f32 = 14.0;
const HEADER_TITLE_FONT: f32 = 17.0;
const CLOSE_SIZE: f32 = 32.0;
const CLOSE_ICON: f32 = 16.0;

// Scrolling body.
const BODY_PAD_TOP: f32 = 4.0;
const BODY_PAD_X: f32 = 32.0;
const BODY_PAD_BOTTOM: f32 = 24.0;
const GROUP_GAP: f32 = 22.0;
const CAPTION_FONT: f32 = 12.0;
const CAPTION_H: f32 = 16.0;
const CAPTION_GAP: f32 = 8.0;

// Grouped cards and their rows.
const CARD_RADIUS: f32 = 12.0;
const ROW_H: f32 = 56.0;
const SUB_ROW_H: f32 = 44.0;
const ROW_PAD_X: f32 = 16.0;
/// Extra left inset of the per-area rows under a master switch.
const SUB_ROW_INDENT: f32 = 16.0;
const ROW_LABEL_FONT: f32 = 14.0;
const SUB_ROW_LABEL_FONT: f32 = 13.5;
const ROW_DESCRIPTION_FONT: f32 = 12.5;
/// Minimum gap between a row's label column and its control.
const ROW_CONTROL_GAP: f32 = 16.0;
/// Share of the row a right-aligned control may take on narrow windows.
const ROW_CONTROL_MAX_FRACTION: f32 = 0.6;

// Row controls.
const CONTROL_H: f32 = 32.0;
const CONTROL_RADIUS: f32 = 8.0;
const CONTROL_FONT: f32 = 13.0;
const CONTROL_PAD_X: f32 = 10.0;
const DROPDOWN_W: f32 = 170.0;
const DROPDOWN_WIDE_W: f32 = 220.0;
const CHEVRON_SIZE: f32 = 12.0;
const MENU_ROW_H: f32 = 30.0;
const MENU_MIN_W: f32 = 200.0;
const MENU_GAP: f32 = 4.0;
const MENU_PAD: f32 = 4.0;
const STEP_W: f32 = 34.0;
const STEP_VALUE_W: f32 = 48.0;
const SWITCH_W: f32 = 38.0;
const SWITCH_H: f32 = 22.0;
const SWITCH_KNOB_PAD: f32 = 2.0;
const SEGMENT_PAD_X: f32 = 12.0;
const SEGMENT_INSET: f32 = 2.0;
const SLIDER_W: f32 = 200.0;
const SLIDER_VALUE_W: f32 = 52.0;
const BUTTON_PAD_X: f32 = 12.0;

/// Shared vertical rhythm for the free-form blocks (providers footer,
/// connection rows, release notes) that do not use the fixed row grid.
const Metrics = struct {
    card_pad: f32,
    label_h: f32,
    row_h: f32,
    row_gap: f32,
    inner_gap: f32,

    fn init() Metrics {
        return .{
            .card_pad = designUi(ROW_PAD_X),
            .label_h = designUi(16.0),
            .row_h = designUi(CONTROL_H),
            .row_gap = designUi(12.0),
            .inner_gap = designUi(8.0),
        };
    }
};

const OFFSCREEN: palette.Rect = .{ .x = -10000.0, .y = -10000.0, .w = 0.0, .h = 0.0 };
const OFFSCREEN_Y: f32 = -10000.0;

const MAX_PAGE_GROUPS: usize = 8;
const MAX_PAGE_ROWS: usize = 24;

const RowStyle = enum { normal, sub, custom };

/// One settings row inside a group card. Labels and static descriptions are
/// drawn by `drawPageChrome`; the page draws the row's control.
const PageRow = struct {
    rect: palette.Rect,
    label: []const u8,
    description: []const u8,
    /// Label sits on the upper line; a (possibly dynamic) description below.
    two_line: bool,
    style: RowStyle,
    /// Inset hairline above this row (every row but a card's first).
    divider: bool,
    /// Width of the right-aligned control, so the label column stops short.
    control_w: f32,
};

/// A captioned card holding consecutive rows.
const PageGroup = struct {
    caption: []const u8,
    caption_y: f32,
    card: palette.Rect,
};

const PagePlan = struct {
    groups: [MAX_PAGE_GROUPS]PageGroup = undefined,
    group_count: usize = 0,
    rows: [MAX_PAGE_ROWS]PageRow = undefined,
    row_count: usize = 0,
};

const StepperRects = struct { dec: palette.Rect, inc: palette.Rect };

/// Lays out one settings page top-down: caption, card, rows, next group.
const PageBuilder = struct {
    plan: *PagePlan,
    x: f32,
    w: f32,
    top: f32,
    y: f32,

    fn init(plan: *PagePlan, x: f32, w: f32, top: f32) PageBuilder {
        return .{ .plan = plan, .x = x, .w = w, .top = top, .y = top };
    }

    fn group(self: *PageBuilder, caption: []const u8) void {
        std.debug.assert(self.plan.group_count < MAX_PAGE_GROUPS);
        if (self.y > self.top) self.y += designUi(GROUP_GAP);
        const caption_y = self.y;
        if (caption.len > 0) self.y += designUi(CAPTION_H + CAPTION_GAP);
        self.plan.groups[self.plan.group_count] = .{
            .caption = caption,
            .caption_y = caption_y,
            .card = .{ .x = self.x, .y = self.y, .w = self.w, .h = 0.0 },
        };
        self.plan.group_count += 1;
    }

    fn rowWith(self: *PageBuilder, label: []const u8, description: []const u8, two_line: bool, style: RowStyle, h: f32, control_w: f32) palette.Rect {
        std.debug.assert(self.plan.group_count > 0 and self.plan.row_count < MAX_PAGE_ROWS);
        const card = &self.plan.groups[self.plan.group_count - 1].card;
        const rect: palette.Rect = .{ .x = self.x, .y = self.y, .w = self.w, .h = h };
        self.plan.rows[self.plan.row_count] = .{
            .rect = rect,
            .label = label,
            .description = description,
            .two_line = two_line,
            .style = style,
            .divider = self.y > card.y,
            .control_w = control_w,
        };
        self.plan.row_count += 1;
        self.y += h;
        card.h = self.y - card.y;
        return rect;
    }

    /// Switch row; the whole row is the hit target.
    fn switchRow(self: *PageBuilder, label: []const u8) palette.Rect {
        return self.rowWith(label, "", false, .normal, designUi(ROW_H), designUi(SWITCH_W));
    }

    fn switchRowDescribed(self: *PageBuilder, label: []const u8, description: []const u8) palette.Rect {
        return self.rowWith(label, description, true, .normal, designUi(ROW_H), designUi(SWITCH_W));
    }

    fn subSwitchRow(self: *PageBuilder, label: []const u8) palette.Rect {
        return self.rowWith(label, "", false, .sub, designUi(SUB_ROW_H), designUi(SWITCH_W));
    }

    /// Row with a right-aligned dropdown; returns the dropdown rect.
    fn dropdownRow(self: *PageBuilder, label: []const u8, design_w: f32) palette.Rect {
        const row = self.rowWith(label, "", false, .normal, designUi(ROW_H), 0.0);
        const control = rowControl(row, designUi(design_w), designUi(CONTROL_H));
        self.plan.rows[self.plan.row_count - 1].control_w = control.w;
        return control;
    }

    fn stepperRow(self: *PageBuilder, label: []const u8) StepperRects {
        const pill_w = designUi(STEP_W * 2.0 + STEP_VALUE_W);
        const row = self.rowWith(label, "", false, .normal, designUi(ROW_H), pill_w);
        const pill = rowControl(row, pill_w, designUi(CONTROL_H));
        const step_w = designUi(STEP_W);
        return .{
            .dec = .{ .x = pill.x, .y = pill.y, .w = step_w, .h = pill.h },
            .inc = .{ .x = pill.x + pill.w - step_w, .y = pill.y, .w = step_w, .h = pill.h },
        };
    }

    /// Row with a right-aligned segmented control of equal-width segments.
    fn segmentRow(self: *PageBuilder, comptime n: usize, label: []const u8, labels: [n][]const u8) [n]palette.Rect {
        var seg_w: f32 = 0.0;
        for (labels) |value| seg_w = @max(seg_w, text_measure.textWidth(.ui, designUi(CONTROL_FONT), value));
        seg_w += designUi(SEGMENT_PAD_X) * 2.0;
        const inset = designUi(SEGMENT_INSET);
        const want_w = seg_w * @as(f32, @floatFromInt(n)) + inset * 2.0;
        const row = self.rowWith(label, "", false, .normal, designUi(ROW_H), 0.0);
        const track = rowControl(row, want_w, designUi(CONTROL_H));
        self.plan.rows[self.plan.row_count - 1].control_w = track.w;
        const each = (track.w - inset * 2.0) / @as(f32, @floatFromInt(n));
        var rects: [n]palette.Rect = undefined;
        for (&rects, 0..) |*rect, index| {
            rect.* = .{
                .x = track.x + inset + each * @as(f32, @floatFromInt(index)),
                .y = track.y + inset,
                .w = each,
                .h = track.h - inset * 2.0,
            };
        }
        return rects;
    }

    /// Full-width row whose content the page draws itself.
    fn customRow(self: *PageBuilder, h: f32) palette.Rect {
        return self.rowWith("", "", false, .custom, h, 0.0);
    }

    /// Advances past free content below the last card.
    fn space(self: *PageBuilder, h: f32) void {
        self.y += h;
    }

    fn height(self: *const PageBuilder) f32 {
        return self.y - self.top;
    }
};

/// Right-aligned control rect inside `row`, vertically centred.
fn rowControl(row: palette.Rect, w: f32, h: f32) palette.Rect {
    const cw = @min(w, row.w * ROW_CONTROL_MAX_FRACTION);
    return .{
        .x = row.x + row.w - designUi(ROW_PAD_X) - cw,
        .y = row.y + (row.h - h) * 0.5,
        .w = cw,
        .h = h,
    };
}

const SettingsLayout = struct {
    modal: palette.Rect,
    nav_panel: palette.Rect,
    header: palette.Rect,
    body_clip: palette.Rect,
    max_scroll_y: f32 = 0.0,
    page_h: f32 = 0.0,
    close: palette.Rect,
    nav: [settings_controller.Category.all.len]palette.Rect,
    page: PagePlan = .{},
    // Appearance
    theme_dropdown: palette.Rect = OFFSCREEN,
    ui_font_family_dropdown: palette.Rect = OFFSCREEN,
    ui_font_dec: palette.Rect = OFFSCREEN,
    ui_font_inc: palette.Rect = OFFSCREEN,
    reduced_motion: palette.Rect = OFFSCREEN,
    reduced_motion_parts: [REDUCED_MOTION_PARTS.len]palette.Rect = [_]palette.Rect{OFFSCREEN} ** REDUCED_MOTION_PARTS.len,
    companion_toggle: palette.Rect = OFFSCREEN,
    companion_character_dropdown: palette.Rect = OFFSCREEN,
    // Workspace
    open_action_dropdown: palette.Rect = OFFSCREEN,
    workspace_tabs_automatic: palette.Rect = OFFSCREEN,
    workspace_tabs_always: palette.Rect = OFFSCREEN,
    workspace_tabs_disabled: palette.Rect = OFFSCREEN,
    new_chat_new_pane: palette.Rect = OFFSCREEN,
    new_chat_replace_pane: palette.Rect = OFFSCREEN,
    workspace_split_default_chat: palette.Rect = OFFSCREEN,
    workspace_split_default_terminal: palette.Rect = OFFSCREEN,
    workspace_new_tab_chat: palette.Rect = OFFSCREEN,
    workspace_new_tab_terminal: palette.Rect = OFFSCREEN,
    workspace_unzoom_on_navigation: palette.Rect = OFFSCREEN,
    workspace_pane_gap_dec: palette.Rect = OFFSCREEN,
    workspace_pane_gap_inc: palette.Rect = OFFSCREEN,
    workspace_panes_per_view_dec: palette.Rect = OFFSCREEN,
    workspace_panes_per_view_inc: palette.Rect = OFFSCREEN,
    workspace_scroll_mode_automatic: palette.Rect = OFFSCREEN,
    workspace_scroll_mode_always: palette.Rect = OFFSCREEN,
    workspace_scroll_mode_disabled: palette.Rect = OFFSCREEN,
    workspace_scroll_threshold_dec: palette.Rect = OFFSCREEN,
    workspace_scroll_threshold_inc: palette.Rect = OFFSCREEN,
    workspace_scroll_horizontal: palette.Rect = OFFSCREEN,
    workspace_scroll_vertical: palette.Rect = OFFSCREEN,
    // Chat
    tool_groups_collapsed: palette.Rect = OFFSCREEN,
    tool_groups_expanded: palette.Rect = OFFSCREEN,
    tool_groups_remember_last: palette.Rect = OFFSCREEN,
    diff_layout_stacked: palette.Rect = OFFSCREEN,
    diff_layout_split: palette.Rect = OFFSCREEN,
    automatic_chat_titles: palette.Rect = OFFSCREEN,
    chat_title_provider_dropdown: palette.Rect = OFFSCREEN,
    chat_title_model_dropdown: palette.Rect = OFFSCREEN,
    new_chat_provider_dropdown: palette.Rect = OFFSCREEN,
    new_chat_model_dropdown: palette.Rect = OFFSCREEN,
    new_chat_reasoning_dropdown: palette.Rect = OFFSCREEN,
    file_links_neovim_pane: palette.Rect = OFFSCREEN,
    // Terminal
    terminal_font_dec: palette.Rect = OFFSCREEN,
    terminal_font_inc: palette.Rect = OFFSCREEN,
    // Browser
    links_verde_browser: palette.Rect = OFFSCREEN,
    links_system_browser: palette.Rect = OFFSCREEN,
    chat_links_global: palette.Rect = OFFSCREEN,
    chat_links_verde_browser: palette.Rect = OFFSCREEN,
    chat_links_system_browser: palette.Rect = OFFSCREEN,
    terminal_links_global: palette.Rect = OFFSCREEN,
    terminal_links_verde_browser: palette.Rect = OFFSCREEN,
    terminal_links_system_browser: palette.Rect = OFFSCREEN,
    browser_scroll_speed: palette.Rect = OFFSCREEN,
    // Providers
    provider_rows: [PROVIDER_ROW_COUNT]palette.Rect = [_]palette.Rect{OFFSCREEN} ** PROVIDER_ROW_COUNT,
    provider_updates: [PROVIDER_ROW_COUNT]palette.Rect = [_]palette.Rect{OFFSCREEN} ** PROVIDER_ROW_COUNT,
    providers_hint_y: f32 = OFFSCREEN_Y,
    providers_update_hint_y: f32 = OFFSCREEN_Y,
    providers_recheck: palette.Rect = OFFSCREEN,
    // Connections
    runtimes: RuntimeCardPlan = .{},
    // Agents
    mcp_tools: palette.Rect = OFFSCREEN,
    hooks_claude: palette.Rect = OFFSCREEN,
    hooks_codex: palette.Rect = OFFSCREEN,
    hooks_cursor: palette.Rect = OFFSCREEN,
    hooks_opencode: palette.Rect = OFFSCREEN,
    hooks_grok: palette.Rect = OFFSCREEN,
    hooks_amp: palette.Rect = OFFSCREEN,
    hooks_pi: palette.Rect = OFFSCREEN,
    // App
    updates_version_row: palette.Rect = OFFSCREEN,
    updates_check: palette.Rect = OFFSCREEN,
    updates_download: palette.Rect = OFFSCREEN,
    updates_automatic: palette.Rect = OFFSCREEN,
    updates_notes_row: palette.Rect = OFFSCREEN,
    updates_package_hint_y: f32 = OFFSCREEN_Y,
    updates_notes_y: f32 = OFFSCREEN_Y,
    updates_notes_toggle: ?palette.Rect = null,
    updates_release_page: palette.Rect = OFFSCREEN,
    notifications_toggle: palette.Rect = OFFSCREEN,
};

const log = std.log.scoped(.native_ui_settings);

// Frame-wide fade multiplier applied by paletteColor; set from the modal's
// animation progress at the top of render.
var current_fade_alpha: f32 = 1.0;

/// Primary copy: row labels, values, titles.
fn textPrimary() [4]f32 {
    return theme.COLOR_WHITE;
}

/// Secondary copy: captions, unselected nav rows, sub-row labels, chevrons.
fn textLabel() [4]f32 {
    return theme.COLOR_TEXT_MUTED;
}

/// Tertiary copy: descriptions, hints, version strings.
fn textHint() [4]f32 {
    return theme.COLOR_TEXT_SUBTLE;
}

// Fills mix from the window background toward the text colour so they keep
// their relationship on light, dark and Omarchy palettes (whose panel_alt /
// panel_muted may be unsuitable as opaque fills).
fn inkTint(amount: f32) [4]f32 {
    return theme.mix(theme.background(), theme.COLOR_WHITE, amount);
}

/// Dialog body behind the cards.
fn sheetSurface() [4]f32 {
    return theme.background();
}

/// Left section nav column.
fn navSurface() [4]f32 {
    return inkTint(0.03);
}

fn navHoverSurface() [4]f32 {
    return inkTint(0.055);
}

fn navSelectedSurface() [4]f32 {
    return inkTint(0.085);
}

/// Group cards: white on light palettes, a step above the sheet on dark ones.
fn cardSurface() [4]f32 {
    return if (theme.isLightPalette()) theme.COLOR_PANEL else inkTint(0.045);
}

/// Card and nav-column edge.
fn cardEdge() [4]f32 {
    return inkTint(0.08);
}

/// Inset hairline between rows of one card.
fn rowHairline() [4]f32 {
    return inkTint(0.05);
}

/// Resting fill for dropdowns, steppers, menus and buttons (sits on a card).
fn controlSurface() [4]f32 {
    return cardSurface();
}

/// Soft hover fill shared by rows, controls and ghost buttons.
fn controlHoverSurface() [4]f32 {
    return theme.mix(cardSurface(), theme.COLOR_WHITE, 0.045);
}

/// Neutral selected fill (menu option).
fn selectedSurface() [4]f32 {
    return theme.mix(cardSurface(), theme.COLOR_WHITE, 0.075);
}

/// Opaque popup surface for dropdown menus.
fn menuSurface() [4]f32 {
    return cardSurface();
}

/// Segmented-control track and the raised selected segment on it.
fn segmentTrack() [4]f32 {
    return theme.mix(cardSurface(), theme.COLOR_WHITE, 0.05);
}

fn segmentRaised() [4]f32 {
    return if (theme.isLightPalette()) theme.COLOR_PANEL else theme.mix(cardSurface(), theme.COLOR_WHITE, 0.14);
}

/// Hairline edge for resting controls and menus.
fn controlEdge() [4]f32 {
    return theme.restingEdge();
}

/// Neutral outline for an open dropdown.
fn controlOpenEdge() [4]f32 {
    return theme.focusRing();
}

/// Solid "on" fill: switch tracks, slider fill and primary buttons use the
/// text colour (dark on light palettes) rather than the accent.
fn strongFill() [4]f32 {
    return theme.COLOR_WHITE;
}

fn metrics() Metrics {
    return Metrics.init();
}

// Centred dialog at the artboard size, shrunk to fit small windows.
fn layoutDialog(width: f32, height: f32) palette.Rect {
    const margin = designUi(DIALOG_MIN_MARGIN);
    const w = @max(@min(designUi(DIALOG_W), width - margin * 2.0), @min(width, designUi(320.0)));
    const h = @max(@min(designUi(DIALOG_H), height - margin * 2.0), @min(height, designUi(240.0)));
    return .{
        .x = @round((width - w) * 0.5),
        .y = @round((height - h) * 0.5),
        .w = w,
        .h = h,
    };
}

fn consumePendingRuntimesScroll(state: *runtime.AppState, layout: SettingsLayout) bool {
    _ = state;
    _ = layout;
    return false;
}

fn computeLayout(state: *runtime.AppState, width: f32, height: f32) SettingsLayout {
    const modal = layoutDialog(width, height);
    const nav_w = @min(designUi(NAV_W), modal.w * 0.28);
    const nav_panel: palette.Rect = .{ .x = modal.x, .y = modal.y, .w = nav_w, .h = modal.h };
    var nav: [settings_controller.Category.all.len]palette.Rect = undefined;
    const nav_top = modal.y + designUi(NAV_PAD_TOP) + designUi(NAV_TITLE_FONT * 1.25) + designUi(NAV_TITLE_GAP);
    // Short windows compress the section rows so all nine stay inside.
    const nav_room = modal.y + modal.h - designUi(NAV_PAD_X) - nav_top;
    const nav_count: f32 = @floatFromInt(settings_controller.Category.all.len);
    const nav_row_h = theme.clampf(nav_room / nav_count - designUi(NAV_ROW_GAP), designUi(22.0), designUi(NAV_ROW_H));
    for (&nav, 0..) |*rect, index| {
        rect.* = .{
            .x = nav_panel.x + designUi(NAV_PAD_X),
            .y = nav_top + @as(f32, @floatFromInt(index)) * (nav_row_h + designUi(NAV_ROW_GAP)),
            .w = nav_panel.w - designUi(NAV_PAD_X) * 2.0,
            .h = nav_row_h,
        };
    }

    const header: palette.Rect = .{ .x = modal.x + nav_w, .y = modal.y, .w = modal.w - nav_w, .h = designUi(HEADER_H) };
    const close_size = designUi(CLOSE_SIZE);
    const close: palette.Rect = .{
        .x = header.x + header.w - designUi(HEADER_PAD_RIGHT) - close_size,
        .y = header.y + (header.h - close_size) * 0.5,
        .w = close_size,
        .h = close_size,
    };
    const body_clip: palette.Rect = .{
        .x = header.x,
        .y = header.y + header.h,
        .w = header.w,
        .h = @max(modal.y + modal.h - (header.y + header.h), 0.0),
    };

    var layout: SettingsLayout = .{
        .modal = modal,
        .nav_panel = nav_panel,
        .header = header,
        .body_clip = body_clip,
        .close = close,
        .nav = nav,
    };
    // Build once unscrolled to learn the page height, then again at the
    // clamped scroll offset.
    buildPage(state, &layout, 0.0);
    const body_h = layout.page_h + designUi(BODY_PAD_TOP + BODY_PAD_BOTTOM);
    const max_scroll_y = @max(body_h - body_clip.h, 0.0);
    const scroll_y = theme.clampf(state.settings_controller.scroll_y, 0.0, max_scroll_y);
    if (scroll_y != 0.0) {
        const fresh: SettingsLayout = .{
            .modal = modal,
            .nav_panel = nav_panel,
            .header = header,
            .body_clip = body_clip,
            .close = close,
            .nav = nav,
        };
        layout = fresh;
        buildPage(state, &layout, scroll_y);
    }
    layout.max_scroll_y = max_scroll_y;
    return layout;
}

// Places the active category's groups, rows and controls.
fn buildPage(state: *runtime.AppState, layout: *SettingsLayout, scroll_y: f32) void {
    const pad_x = @min(designUi(BODY_PAD_X), layout.body_clip.w * 0.06);
    const content_x = layout.body_clip.x + pad_x;
    const content_w = @max(layout.body_clip.w - pad_x * 2.0, designUi(160.0));
    const top = layout.body_clip.y + designUi(BODY_PAD_TOP) - scroll_y;
    var b = PageBuilder.init(&layout.page, content_x, content_w, top);
    const draft = &state.settings_controller.draft;

    switch (state.settings_controller.active_category) {
        .appearance => {
            b.group("Look");
            layout.theme_dropdown = b.dropdownRow("Theme", DROPDOWN_W + 20.0);
            layout.ui_font_family_dropdown = b.dropdownRow("Font family", DROPDOWN_W);
            const ui_font = b.stepperRow("UI font size");
            layout.ui_font_dec = ui_font.dec;
            layout.ui_font_inc = ui_font.inc;

            b.group("Motion");
            layout.reduced_motion = b.switchRowDescribed("Reduce motion", "Turn off animation everywhere, or pick areas below");
            for (REDUCED_MOTION_PARTS, &layout.reduced_motion_parts) |part, *rect| {
                rect.* = b.subSwitchRow(part.label);
            }

            b.group("Companion");
            layout.companion_toggle = b.switchRow("Companion");
            if (draft.companion_enabled) {
                layout.companion_character_dropdown = b.dropdownRow("Character", DROPDOWN_W - 50.0);
            }
        },
        .workspace => {
            b.group("General");
            layout.open_action_dropdown = b.dropdownRow("Open with", DROPDOWN_W - 30.0);
            const tabs = b.segmentRow(3, "Tabs", .{ "Auto", "Always", "Off" });
            layout.workspace_tabs_automatic = tabs[0];
            layout.workspace_tabs_always = tabs[1];
            layout.workspace_tabs_disabled = tabs[2];

            b.group("Panes");
            const new_chat = b.segmentRow(2, "New chat", .{ "New pane", "Replace" });
            layout.new_chat_new_pane = new_chat[0];
            layout.new_chat_replace_pane = new_chat[1];
            const split = b.segmentRow(2, "Split", .{ "Chat", "Terminal" });
            layout.workspace_split_default_chat = split[0];
            layout.workspace_split_default_terminal = split[1];
            const new_tab = b.segmentRow(2, "New tab", .{ "Chat", "Terminal" });
            layout.workspace_new_tab_chat = new_tab[0];
            layout.workspace_new_tab_terminal = new_tab[1];
            layout.workspace_unzoom_on_navigation = b.switchRow("Unzoom on navigate");
            const gap = b.stepperRow("Pane gap");
            layout.workspace_pane_gap_dec = gap.dec;
            layout.workspace_pane_gap_inc = gap.inc;
            const per_view = b.stepperRow("Panes per view");
            layout.workspace_panes_per_view_dec = per_view.dec;
            layout.workspace_panes_per_view_inc = per_view.inc;

            b.group("Scrolling");
            const mode = b.segmentRow(3, "Scrolling", .{ "Auto", "Always", "Off" });
            layout.workspace_scroll_mode_automatic = mode[0];
            layout.workspace_scroll_mode_always = mode[1];
            layout.workspace_scroll_mode_disabled = mode[2];
            if (draft.workspace_scroll_mode == .automatic) {
                const threshold = b.stepperRow("Start after");
                layout.workspace_scroll_threshold_dec = threshold.dec;
                layout.workspace_scroll_threshold_inc = threshold.inc;
            }
            const direction = b.segmentRow(2, "Direction", .{ "Horizontal", "Vertical" });
            layout.workspace_scroll_horizontal = direction[0];
            layout.workspace_scroll_vertical = direction[1];
        },
        .chat => {
            b.group("Transcript");
            const groups = b.segmentRow(3, "Tool groups", .{ "Collapse", "Expand", "Remember" });
            layout.tool_groups_collapsed = groups[0];
            layout.tool_groups_expanded = groups[1];
            layout.tool_groups_remember_last = groups[2];
            const diff = b.segmentRow(2, "Diff", .{ "Stacked", "Split" });
            layout.diff_layout_stacked = diff[0];
            layout.diff_layout_split = diff[1];

            b.group("Chat titles");
            layout.automatic_chat_titles = b.switchRow("Auto-name chats");
            if (draft.automatic_chat_titles_enabled) {
                layout.chat_title_provider_dropdown = b.dropdownRow("Provider", DROPDOWN_W);
                layout.chat_title_model_dropdown = b.dropdownRow("Model", DROPDOWN_WIDE_W);
            }

            b.group("New chat");
            layout.new_chat_provider_dropdown = b.dropdownRow("Provider", DROPDOWN_W);
            layout.new_chat_model_dropdown = b.dropdownRow("Model", DROPDOWN_WIDE_W);
            layout.new_chat_reasoning_dropdown = b.dropdownRow("Reasoning", DROPDOWN_W);

            b.group("Links");
            layout.file_links_neovim_pane = b.switchRow("File links in Neovim");
        },
        .terminal => {
            b.group("Text");
            const font = b.stepperRow("Font size");
            layout.terminal_font_dec = font.dec;
            layout.terminal_font_inc = font.inc;
        },
        .browser => {
            b.group("Links");
            const web = b.segmentRow(2, "Web links", .{ "Verde", "System" });
            layout.links_verde_browser = web[0];
            layout.links_system_browser = web[1];
            const chat = b.segmentRow(3, "Chat links", .{ "Global", "Verde", "System" });
            layout.chat_links_global = chat[0];
            layout.chat_links_verde_browser = chat[1];
            layout.chat_links_system_browser = chat[2];
            const terminal = b.segmentRow(3, "Terminal links", .{ "Global", "Verde", "System" });
            layout.terminal_links_global = terminal[0];
            layout.terminal_links_verde_browser = terminal[1];
            layout.terminal_links_system_browser = terminal[2];

            b.group("Scrolling");
            layout.browser_scroll_speed = b.rowWith("Wheel speed", "", false, .normal, designUi(ROW_H), designUi(SLIDER_W + SLIDER_VALUE_W));
        },
        .providers => {
            const m = metrics();
            b.group("Model providers");
            const action_w = providerActionWidth();
            const badge_w = providerBadgeColumnWidth();
            for (&layout.provider_rows, &layout.provider_updates) |*row, *update| {
                row.* = b.customRow(designUi(ROW_H));
                const badge_x = row.x + row.w - providerSwitchReserve() - badge_w;
                const update_h = designUi(26.0);
                update.* = .{
                    .x = badge_x - providerDotSize() - designUi(6.0 + 10.0) - action_w,
                    .y = row.y + (row.h - update_h) * 0.5,
                    .w = action_w,
                    .h = update_h,
                };
            }
            b.space(designUi(10.0));
            layout.providers_hint_y = b.y;
            layout.providers_update_hint_y = b.y + m.label_h;
            layout.providers_recheck = .{
                .x = content_x,
                .y = layout.providers_update_hint_y + m.label_h + m.row_gap,
                .w = buttonWidth(PROVIDERS_RECHECK_LABEL),
                .h = m.row_h,
            };
            b.space(m.label_h * 2.0 + m.row_gap + m.row_h);
        },
        .connections => {
            layout.runtimes = planRuntimeCard(state, content_x, top, content_w, metrics());
            b.space(layout.runtimes.height);
        },
        .agents => {
            b.group("Verde MCP");
            layout.mcp_tools = b.switchRowDescribed("Enable Verde MCP", "");

            b.group("Status hooks");
            layout.hooks_claude = b.switchRow("Claude");
            layout.hooks_codex = b.switchRow("Codex");
            layout.hooks_cursor = b.switchRow("Cursor");
            layout.hooks_opencode = b.switchRow("OpenCode");
            layout.hooks_grok = b.switchRow("Grok");
            layout.hooks_amp = b.switchRow("Amp");
            layout.hooks_pi = b.switchRow("Pi");
        },
        .app => {
            const m = metrics();
            b.group("Updates");
            const check_label = if (state.settings_controller.update.status == .checking) "Checking…" else "Check now";
            const check_w = buttonWidth(check_label);
            const download_w = buttonWidth(state.updateInstallerButtonLabel());
            const buttons_w = check_w + m.inner_gap + download_w;
            const version_row = b.rowWith("Verde", "", true, .normal, designUi(ROW_H), buttons_w);
            layout.updates_version_row = version_row;
            const buttons = rowControl(version_row, buttons_w, designUi(CONTROL_H));
            layout.updates_check = .{ .x = buttons.x, .y = buttons.y, .w = check_w, .h = buttons.h };
            layout.updates_download = .{ .x = buttons.x + buttons.w - download_w, .y = buttons.y, .w = download_w, .h = buttons.h };
            layout.updates_automatic = b.switchRow("Check automatically");

            const notes_w = @max(content_w - m.card_pad * 2.0, designUi(80.0));
            const notes_h = notesBlockHeight(state, notes_w, m);
            const package_hint_h = if (state.settings_controller.package_update_command != null)
                wrappedNotesRows(PACKAGE_UPDATE_HINT, notes_w) * notesLineHeight() + m.label_h + m.inner_gap
            else
                0.0;
            const notes_pad = designUi(14.0);
            const notes_row = b.customRow(notes_pad * 2.0 + package_hint_h + notes_h + m.inner_gap + m.label_h);
            layout.updates_notes_row = notes_row;
            layout.updates_package_hint_y = notes_row.y + notes_pad;
            layout.updates_notes_y = notes_row.y + notes_pad + package_hint_h;
            const links_y = layout.updates_notes_y + notes_h + m.inner_gap;
            const notes_x = notes_row.x + m.card_pad;
            if (state.settings_controller.update.release != null) {
                layout.updates_notes_toggle = .{
                    .x = notes_x,
                    .y = links_y,
                    .w = text_measure.textWidth(.ui, designUi(NOTES_LINK_FONT_SIZE), notesToggleLabel(state)),
                    .h = m.label_h,
                };
            }
            const release_page_x = if (layout.updates_notes_toggle) |toggle| toggle.x + toggle.w + m.row_gap * 2.0 else notes_x;
            layout.updates_release_page = .{
                .x = release_page_x,
                .y = links_y,
                .w = text_measure.textWidth(.ui, designUi(NOTES_LINK_FONT_SIZE), RELEASE_PAGE_LABEL),
                .h = m.label_h,
            };

            b.group("Notifications");
            layout.notifications_toggle = b.switchRow("Agent status");
        },
    }
    layout.page_h = b.height();
}

fn isControlHovered(state: *const runtime.AppState, control: Control) bool {
    return state.settings_controller.hover_control != null and state.settings_controller.hover_control.? == @intFromEnum(control);
}

fn openActionSelectedIndex(state: *const runtime.AppState) usize {
    const action = state.settings_controller.draft.open_action;
    inline for (OPEN_CHOICES, 0..) |choice, index| {
        const selected = switch (choice.control) {
            .open_folder => action == .folder,
            .open_editor => action == .editor,
            .open_cursor => action == .cursor,
            .open_vscode => action == .vscode,
            .open_zed => action == .zed,
            else => false,
        };
        if (selected) return index;
    }
    return 0;
}

fn handleOpenActionKeyDown(state: *runtime.AppState, key: sdl.Keycode) bool {
    const count = OPEN_CHOICES.len;
    const current = state.settings_controller.open_action_hover_index orelse openActionSelectedIndex(state);
    const next = switch (key) {
        .up => current -| 1,
        .down => @min(current + 1, count - 1),
        .home => 0,
        .end => count - 1,
        .escape => {
            state.settings_controller.open_action_dropdown_open = false;
            state.settings_controller.open_action_hover_index = null;
            state.markDirty();
            return true;
        },
        .@"return", .kp_enter => {
            applyOpenActionOption(state, current);
            return true;
        },
        else => return false,
    };
    state.settings_controller.open_action_hover_index = next;
    state.markDirty();
    return true;
}

fn openActionSelected(state: *const runtime.AppState, control: Control) bool {
    return switch (control) {
        .open_folder => state.settings_controller.draft.open_action == .folder,
        .open_editor => state.settings_controller.draft.open_action == .editor,
        .open_cursor => state.settings_controller.draft.open_action == .cursor,
        .open_vscode => state.settings_controller.draft.open_action == .vscode,
        .open_zed => state.settings_controller.draft.open_action == .zed,
        else => false,
    };
}

fn queueControlHit(
    state: *runtime.AppState,
    rect: palette.Rect,
    clip: palette.Rect,
    control: Control,
    queue_hit: *const fn (*runtime.AppState, palette.Rect, runtime.PaletteModalAction, usize) void,
) void {
    const visible = intersectRect(rect, clip) orelse return;
    queue_hit(state, visible, .settings_control, @intFromEnum(control));
}

fn themeMenuVisibleCount(state: *const runtime.AppState) usize {
    return @min(state.settingsThemeChoiceCount(), THEME_MENU_MAX_ROWS);
}

fn themeMenuMaxScroll(state: *const runtime.AppState) usize {
    return state.settingsThemeChoiceCount() - themeMenuVisibleCount(state);
}

fn themeMenuRect(state: *const runtime.AppState, layout: SettingsLayout) palette.Rect {
    return dropdownMenuRect(layout, layout.theme_dropdown, themeMenuVisibleCount(state));
}

fn themeOptionRect(state: *const runtime.AppState, layout: SettingsLayout, visible_index: usize) palette.Rect {
    return dropdownOptionRect(themeMenuRect(state, layout), visible_index);
}

fn companionCharacterCount() usize {
    return COMPANION_CHARACTER_OPTIONS.len;
}

fn companionCharacterLabel(choice_index: usize) []const u8 {
    if (choice_index >= COMPANION_CHARACTER_LABELS.len) return "Unknown companion";
    return COMPANION_CHARACTER_LABELS[choice_index];
}

fn companionCharacterIndex(character: app_config.CompanionCharacter) usize {
    inline for (COMPANION_CHARACTER_OPTIONS, 0..) |option, index| {
        if (option == character) return index;
    }
    return 0;
}

fn companionCharacterMenuRect(layout: SettingsLayout) palette.Rect {
    return dropdownMenuRect(layout, layout.companion_character_dropdown, companionCharacterCount());
}

fn companionCharacterOptionRect(layout: SettingsLayout, choice_index: usize) palette.Rect {
    return dropdownOptionRect(companionCharacterMenuRect(layout), choice_index);
}

fn uiFontFamilyCount() usize {
    return UI_FONT_FAMILY_OPTIONS.len;
}

fn uiFontFamilyLabel(choice_index: usize) []const u8 {
    if (choice_index >= UI_FONT_FAMILY_OPTIONS.len) return "Unknown font";
    return UI_FONT_FAMILY_OPTIONS[choice_index].label();
}

fn uiFontFamilyIndex(family: app_config.UiFontFamily) usize {
    for (UI_FONT_FAMILY_OPTIONS, 0..) |option, index| {
        if (option == family) return index;
    }
    return 0;
}

fn uiFontFamilyMenuRect(layout: SettingsLayout) palette.Rect {
    return dropdownMenuRect(layout, layout.ui_font_family_dropdown, uiFontFamilyCount());
}

fn uiFontFamilyOptionRect(layout: SettingsLayout, choice_index: usize) palette.Rect {
    return dropdownOptionRect(uiFontFamilyMenuRect(layout), choice_index);
}

fn registerThemeOptionHits(
    state: *runtime.AppState,
    layout: SettingsLayout,
    queue_hit: *const fn (*runtime.AppState, palette.Rect, runtime.PaletteModalAction, usize) void,
) void {
    if (!state.settings_controller.theme_dropdown_open) return;
    state.settings_controller.theme_menu_scroll = @min(state.settings_controller.theme_menu_scroll, themeMenuMaxScroll(state));
    for (0..themeMenuVisibleCount(state)) |visible_index| {
        const rect = intersectRect(themeOptionRect(state, layout, visible_index), layout.body_clip) orelse continue;
        queue_hit(state, rect, .settings_theme_option, state.settings_controller.theme_menu_scroll + visible_index);
    }
}

fn registerCompanionCharacterOptionHits(
    state: *runtime.AppState,
    layout: SettingsLayout,
    queue_hit: *const fn (*runtime.AppState, palette.Rect, runtime.PaletteModalAction, usize) void,
) void {
    if (!state.settings_controller.companion_character_dropdown_open) return;
    // Fixed Sprout/Moss/Vireo list — reuse the theme option action channel with
    // the choice index; applyThemeOption is only invoked when the theme menu
    // is open, so companion selection routes through applyCompanionCharacterOption.
    for (0..companionCharacterCount()) |choice_index| {
        const rect = intersectRect(companionCharacterOptionRect(layout, choice_index), layout.body_clip) orelse continue;
        queue_hit(state, rect, .settings_theme_option, choice_index);
    }
}

fn registerUiFontFamilyOptionHits(
    state: *runtime.AppState,
    layout: SettingsLayout,
    queue_hit: *const fn (*runtime.AppState, palette.Rect, runtime.PaletteModalAction, usize) void,
) void {
    if (!state.settings_controller.ui_font_family_dropdown_open) return;
    // Shares the theme option channel like the companion menu;
    // applyThemeOption routes to the font family while this menu is open.
    for (0..uiFontFamilyCount()) |choice_index| {
        const rect = intersectRect(uiFontFamilyOptionRect(layout, choice_index), layout.body_clip) orelse continue;
        queue_hit(state, rect, .settings_theme_option, choice_index);
    }
}

/// Popup under (or, when the body has no room below, above) a dropdown,
/// right-aligned to it and at least `MENU_MIN_W` wide for long model names.
fn dropdownMenuRect(layout: SettingsLayout, dropdown: palette.Rect, row_count: usize) palette.Rect {
    const w = @max(dropdown.w, @min(designUi(MENU_MIN_W), layout.body_clip.w - designUi(ROW_PAD_X) * 2.0));
    const h = @as(f32, @floatFromInt(row_count)) * designUi(MENU_ROW_H) + designUi(MENU_PAD) * 2.0;
    const gap = designUi(MENU_GAP);
    const below_y = dropdown.y + dropdown.h + gap;
    const above_y = dropdown.y - gap - h;
    const clip_bottom = layout.body_clip.y + layout.body_clip.h;
    const flip = below_y + h > clip_bottom and above_y >= layout.body_clip.y;
    return .{
        .x = @max(dropdown.x + dropdown.w - w, layout.body_clip.x + designUi(ROW_PAD_X)),
        .y = if (flip) above_y else below_y,
        .w = w,
        .h = h,
    };
}

fn dropdownOptionRect(menu: palette.Rect, visible_index: usize) palette.Rect {
    const pad = designUi(MENU_PAD);
    const row_h = designUi(MENU_ROW_H);
    return .{
        .x = menu.x + pad,
        .y = menu.y + pad + @as(f32, @floatFromInt(visible_index)) * row_h,
        .w = menu.w - pad * 2.0,
        .h = row_h,
    };
}

fn titleProviderMenuRect(state: *const runtime.AppState, layout: SettingsLayout) palette.Rect {
    return dropdownMenuRect(layout, layout.chat_title_provider_dropdown, state.settingsChatTitleProviderCount());
}

fn titleModelMenuVisibleCount(state: *const runtime.AppState) usize {
    return @min(state.settingsChatTitleModelCount(), TITLE_MENU_MAX_ROWS);
}

fn titleModelMenuMaxScroll(state: *const runtime.AppState) usize {
    return state.settingsChatTitleModelCount() - titleModelMenuVisibleCount(state);
}

fn titleModelMenuRect(state: *const runtime.AppState, layout: SettingsLayout) palette.Rect {
    return dropdownMenuRect(layout, layout.chat_title_model_dropdown, titleModelMenuVisibleCount(state));
}

fn registerTitleOptionHits(
    state: *runtime.AppState,
    layout: SettingsLayout,
    queue_hit: *const fn (*runtime.AppState, palette.Rect, runtime.PaletteModalAction, usize) void,
) void {
    if (state.settings_controller.title_provider_dropdown_open) {
        const menu = titleProviderMenuRect(state, layout);
        for (0..state.settingsChatTitleProviderCount()) |option_index| {
            const rect = intersectRect(dropdownOptionRect(menu, option_index), layout.body_clip) orelse continue;
            queue_hit(state, rect, .settings_title_provider_option, option_index);
        }
    }
    if (state.settings_controller.title_model_dropdown_open) {
        state.settings_controller.title_model_menu_scroll = @min(state.settings_controller.title_model_menu_scroll, titleModelMenuMaxScroll(state));
        const menu = titleModelMenuRect(state, layout);
        for (0..titleModelMenuVisibleCount(state)) |visible_index| {
            const rect = intersectRect(dropdownOptionRect(menu, visible_index), layout.body_clip) orelse continue;
            queue_hit(state, rect, .settings_title_model_option, state.settings_controller.title_model_menu_scroll + visible_index);
        }
    }
}

const NewChatMenuKind = enum { provider, model, reasoning };

fn newChatMenuCount(state: *const runtime.AppState, kind: NewChatMenuKind) usize {
    return switch (kind) {
        .provider => state.settingsNewChatProviderCount(),
        .model => state.settingsNewChatModelCount(),
        .reasoning => state.settingsNewChatReasoningCount(),
    };
}

fn newChatModelMenuVisibleCount(state: *const runtime.AppState) usize {
    return @min(state.settingsNewChatModelCount(), TITLE_MENU_MAX_ROWS);
}

fn newChatModelMenuMaxScroll(state: *const runtime.AppState) usize {
    return state.settingsNewChatModelCount() - newChatModelMenuVisibleCount(state);
}

fn newChatMenuRect(state: *const runtime.AppState, layout: SettingsLayout, kind: NewChatMenuKind) palette.Rect {
    const dropdown = switch (kind) {
        .provider => layout.new_chat_provider_dropdown,
        .model => layout.new_chat_model_dropdown,
        .reasoning => layout.new_chat_reasoning_dropdown,
    };
    const count = if (kind == .model) newChatModelMenuVisibleCount(state) else @min(newChatMenuCount(state, kind), TITLE_MENU_MAX_ROWS);
    return dropdownMenuRect(layout, dropdown, count);
}

fn registerNewChatOptionHits(
    state: *runtime.AppState,
    layout: SettingsLayout,
    queue_hit: *const fn (*runtime.AppState, palette.Rect, runtime.PaletteModalAction, usize) void,
) void {
    const kinds = [_]NewChatMenuKind{ .provider, .model, .reasoning };
    for (kinds) |kind| {
        const open = switch (kind) {
            .provider => state.settings_controller.new_chat_provider_dropdown_open,
            .model => state.settings_controller.new_chat_model_dropdown_open,
            .reasoning => state.settings_controller.new_chat_reasoning_dropdown_open,
        };
        if (!open) continue;
        if (kind == .model) state.settings_controller.new_chat_model_menu_scroll = @min(state.settings_controller.new_chat_model_menu_scroll, newChatModelMenuMaxScroll(state));
        const scroll = if (kind == .model) state.settings_controller.new_chat_model_menu_scroll else 0;
        const visible_count = if (kind == .model) newChatModelMenuVisibleCount(state) else @min(newChatMenuCount(state, kind), TITLE_MENU_MAX_ROWS);
        const action: runtime.PaletteModalAction = switch (kind) {
            .provider => .settings_new_chat_provider_option,
            .model => .settings_new_chat_model_option,
            .reasoning => .settings_new_chat_reasoning_option,
        };
        const menu = newChatMenuRect(state, layout, kind);
        for (0..visible_count) |visible_index| {
            const rect = intersectRect(dropdownOptionRect(menu, visible_index), layout.body_clip) orelse continue;
            queue_hit(state, rect, action, scroll + visible_index);
        }
    }
}

fn openActionMenuRect(layout: SettingsLayout) palette.Rect {
    return dropdownMenuRect(layout, layout.open_action_dropdown, OPEN_CHOICES.len);
}

fn registerOpenActionOptionHits(
    state: *runtime.AppState,
    layout: SettingsLayout,
    queue_hit: *const fn (*runtime.AppState, palette.Rect, runtime.PaletteModalAction, usize) void,
) void {
    if (!state.settings_controller.open_action_dropdown_open) return;
    const menu = openActionMenuRect(layout);
    for (0..OPEN_CHOICES.len) |option_index| {
        const rect = intersectRect(dropdownOptionRect(menu, option_index), layout.body_clip) orelse continue;
        queue_hit(state, rect, .settings_open_option, option_index);
    }
}

/// Registers palette hit targets for the settings modal.
pub fn registerHits(state: *runtime.AppState, width: f32, height: f32, queue_hit: *const fn (*runtime.AppState, palette.Rect, runtime.PaletteModalAction, usize) void) void {
    if (!state.settings_controller.modal_visible) return;
    if (state.settings_controller.modal_closing) {
        // Swallow input during the fade-out; the controls are already gone.
        queue_hit(state, .{ .x = 0.0, .y = 0.0, .w = width, .h = height }, .modal_block, 0);
        return;
    }

    var layout = computeLayout(state, width, height);
    if (consumePendingRuntimesScroll(state, layout)) layout = computeLayout(state, width, height);
    state.settings_controller.scroll_y = theme.clampf(state.settings_controller.scroll_y, 0.0, layout.max_scroll_y);
    // Full-window dismiss so a click on the sidebar or workspace closes the
    // dialog. Dialog chrome stays modal_block so empty space there does
    // not dismiss (and still closes open dropdowns).
    queue_hit(state, .{ .x = 0.0, .y = 0.0, .w = width, .h = height }, .modal_dismiss, 0);
    queue_hit(state, layout.modal, .modal_block, 0);
    queue_hit(state, layout.close, .settings_close, 0);
    for (settings_controller.Category.all, 0..) |_, index| {
        queue_hit(state, layout.nav[index], .settings_category, index);
    }
    const category = state.settings_controller.active_category;
    if (category == .appearance) {
        queueControlHit(state, layout.theme_dropdown, layout.body_clip, .theme_dropdown, queue_hit);
        if (state.settings_controller.draft.companion_enabled) {
            queueControlHit(state, layout.companion_character_dropdown, layout.body_clip, .companion_character_dropdown, queue_hit);
        }
        queueControlHit(state, layout.ui_font_dec, layout.body_clip, .ui_font_dec, queue_hit);
        queueControlHit(state, layout.ui_font_inc, layout.body_clip, .ui_font_inc, queue_hit);
        queueControlHit(state, layout.ui_font_family_dropdown, layout.body_clip, .ui_font_family_dropdown, queue_hit);
        queueControlHit(state, layout.reduced_motion, layout.body_clip, .reduced_motion, queue_hit);
        for (REDUCED_MOTION_PARTS, layout.reduced_motion_parts) |part, rect| {
            queueControlHit(state, rect, layout.body_clip, part.control, queue_hit);
        }
        queueControlHit(state, layout.companion_toggle, layout.body_clip, .companion_toggle, queue_hit);
    }
    if (category == .workspace) {
        queueControlHit(state, layout.workspace_tabs_automatic, layout.body_clip, .workspace_tabs_automatic, queue_hit);
        queueControlHit(state, layout.workspace_tabs_always, layout.body_clip, .workspace_tabs_always, queue_hit);
        queueControlHit(state, layout.workspace_tabs_disabled, layout.body_clip, .workspace_tabs_disabled, queue_hit);
        queueControlHit(state, layout.open_action_dropdown, layout.body_clip, .open_action_dropdown, queue_hit);
        queueControlHit(state, layout.new_chat_new_pane, layout.body_clip, .new_chat_new_pane, queue_hit);
        queueControlHit(state, layout.new_chat_replace_pane, layout.body_clip, .new_chat_replace_pane, queue_hit);
        queueControlHit(state, layout.workspace_split_default_chat, layout.body_clip, .workspace_split_default_chat, queue_hit);
        queueControlHit(state, layout.workspace_split_default_terminal, layout.body_clip, .workspace_split_default_terminal, queue_hit);
        queueControlHit(state, layout.workspace_new_tab_chat, layout.body_clip, .workspace_new_tab_chat, queue_hit);
        queueControlHit(state, layout.workspace_new_tab_terminal, layout.body_clip, .workspace_new_tab_terminal, queue_hit);
        queueControlHit(state, layout.workspace_unzoom_on_navigation, layout.body_clip, .workspace_unzoom_on_navigation, queue_hit);
        queueControlHit(state, layout.workspace_scroll_mode_automatic, layout.body_clip, .workspace_scroll_mode_automatic, queue_hit);
        queueControlHit(state, layout.workspace_scroll_mode_always, layout.body_clip, .workspace_scroll_mode_always, queue_hit);
        queueControlHit(state, layout.workspace_scroll_mode_disabled, layout.body_clip, .workspace_scroll_mode_disabled, queue_hit);
        if (state.settings_controller.draft.workspace_scroll_mode == .automatic) {
            queueControlHit(state, layout.workspace_scroll_threshold_dec, layout.body_clip, .workspace_scroll_threshold_dec, queue_hit);
            queueControlHit(state, layout.workspace_scroll_threshold_inc, layout.body_clip, .workspace_scroll_threshold_inc, queue_hit);
        }
        queueControlHit(state, layout.workspace_pane_gap_dec, layout.body_clip, .workspace_pane_gap_dec, queue_hit);
        queueControlHit(state, layout.workspace_pane_gap_inc, layout.body_clip, .workspace_pane_gap_inc, queue_hit);
        queueControlHit(state, layout.workspace_panes_per_view_dec, layout.body_clip, .workspace_panes_per_view_dec, queue_hit);
        queueControlHit(state, layout.workspace_panes_per_view_inc, layout.body_clip, .workspace_panes_per_view_inc, queue_hit);
        queueControlHit(state, layout.workspace_scroll_horizontal, layout.body_clip, .workspace_scroll_horizontal, queue_hit);
        queueControlHit(state, layout.workspace_scroll_vertical, layout.body_clip, .workspace_scroll_vertical, queue_hit);
    }
    if (category == .chat) {
        queueControlHit(state, layout.tool_groups_collapsed, layout.body_clip, .tool_groups_collapsed, queue_hit);
        queueControlHit(state, layout.tool_groups_expanded, layout.body_clip, .tool_groups_expanded, queue_hit);
        queueControlHit(state, layout.tool_groups_remember_last, layout.body_clip, .tool_groups_remember_last, queue_hit);
        queueControlHit(state, layout.diff_layout_stacked, layout.body_clip, .diff_layout_stacked, queue_hit);
        queueControlHit(state, layout.diff_layout_split, layout.body_clip, .diff_layout_split, queue_hit);
        queueControlHit(state, layout.automatic_chat_titles, layout.body_clip, .automatic_chat_titles, queue_hit);
        if (state.settings_controller.draft.automatic_chat_titles_enabled) {
            queueControlHit(state, layout.chat_title_provider_dropdown, layout.body_clip, .chat_title_provider_dropdown, queue_hit);
            queueControlHit(state, layout.chat_title_model_dropdown, layout.body_clip, .chat_title_model_dropdown, queue_hit);
        }
        queueControlHit(state, layout.new_chat_provider_dropdown, layout.body_clip, .new_chat_provider_dropdown, queue_hit);
        queueControlHit(state, layout.new_chat_model_dropdown, layout.body_clip, .new_chat_model_dropdown, queue_hit);
        queueControlHit(state, layout.new_chat_reasoning_dropdown, layout.body_clip, .new_chat_reasoning_dropdown, queue_hit);
        queueControlHit(state, layout.file_links_neovim_pane, layout.body_clip, .file_links_neovim_pane, queue_hit);
    }
    if (category == .terminal) {
        queueControlHit(state, layout.terminal_font_dec, layout.body_clip, .terminal_font_dec, queue_hit);
        queueControlHit(state, layout.terminal_font_inc, layout.body_clip, .terminal_font_inc, queue_hit);
    }
    if (category == .browser) {
        queueControlHit(state, layout.links_verde_browser, layout.body_clip, .links_verde_browser, queue_hit);
        queueControlHit(state, layout.links_system_browser, layout.body_clip, .links_system_browser, queue_hit);
        queueControlHit(state, layout.chat_links_global, layout.body_clip, .chat_links_global, queue_hit);
        queueControlHit(state, layout.chat_links_verde_browser, layout.body_clip, .chat_links_verde_browser, queue_hit);
        queueControlHit(state, layout.chat_links_system_browser, layout.body_clip, .chat_links_system_browser, queue_hit);
        queueControlHit(state, layout.terminal_links_global, layout.body_clip, .terminal_links_global, queue_hit);
        queueControlHit(state, layout.terminal_links_verde_browser, layout.body_clip, .terminal_links_verde_browser, queue_hit);
        queueControlHit(state, layout.terminal_links_system_browser, layout.body_clip, .terminal_links_system_browser, queue_hit);
        queueControlHit(state, browserScrollSliderHitRect(layout.browser_scroll_speed), layout.body_clip, .browser_scroll_speed, queue_hit);
    }
    if (category == .providers) {
        for (layout.provider_rows, 0..) |row, index| {
            queueControlHit(state, row, layout.body_clip, providerRowControl(index), queue_hit);
        }
        // Registered after the row so Install/Update wins the overlap.
        // Latest and an unfinished check are labels, not buttons.
        const provider_snapshot = state.providerReadinessSnapshot();
        for (layout.provider_updates, 0..) |update, index| {
            const provider = settings_controller.settingsProviderForRow(index);
            switch (providerAction(provider_snapshot.forProvider(provider), provider_snapshot.releaseForProvider(provider))) {
                .install, .update, .sign_in => queueControlHit(state, update, layout.body_clip, providerUpdateControl(index), queue_hit),
                .latest, .pending, .none => {},
            }
        }
        queueControlHit(state, layout.providers_recheck, layout.body_clip, .providers_recheck, queue_hit);
    }
    if (category == .agents) {
        queueControlHit(state, layout.mcp_tools, layout.body_clip, .mcp_tools, queue_hit);
        queueControlHit(state, layout.hooks_claude, layout.body_clip, .hooks_claude, queue_hit);
        queueControlHit(state, layout.hooks_codex, layout.body_clip, .hooks_codex, queue_hit);
        queueControlHit(state, layout.hooks_cursor, layout.body_clip, .hooks_cursor, queue_hit);
        queueControlHit(state, layout.hooks_opencode, layout.body_clip, .hooks_opencode, queue_hit);
        queueControlHit(state, layout.hooks_grok, layout.body_clip, .hooks_grok, queue_hit);
        queueControlHit(state, layout.hooks_amp, layout.body_clip, .hooks_amp, queue_hit);
        queueControlHit(state, layout.hooks_pi, layout.body_clip, .hooks_pi, queue_hit);
    }
    if (category == .app) {
        if (state.settings_controller.update.status != .checking) {
            queueControlHit(state, layout.updates_check, layout.body_clip, .updates_check, queue_hit);
        }
        if (state.updateInstallerButtonEnabled()) {
            queueControlHit(state, layout.updates_download, layout.body_clip, .updates_download, queue_hit);
        }
        queueControlHit(state, layout.updates_automatic, layout.body_clip, .updates_automatic, queue_hit);
        if (layout.updates_notes_toggle) |toggle| {
            queueControlHit(state, toggle, layout.body_clip, .updates_notes_toggle, queue_hit);
        }
        queueControlHit(state, layout.updates_release_page, layout.body_clip, .updates_release_page, queue_hit);
        queueControlHit(state, layout.notifications_toggle, layout.body_clip, .notifications_toggle, queue_hit);
    }
    if (category == .connections) {
        registerRuntimeCardHits(state, layout, queue_hit);
    }
    registerThemeOptionHits(state, layout, queue_hit);
    registerCompanionCharacterOptionHits(state, layout, queue_hit);
    registerUiFontFamilyOptionHits(state, layout, queue_hit);
    registerTitleOptionHits(state, layout, queue_hit);
    registerNewChatOptionHits(state, layout, queue_hit);
    registerOpenActionOptionHits(state, layout, queue_hit);
}

pub fn applySettingsCategory(state: *runtime.AppState, index: usize) void {
    if (index >= settings_controller.Category.all.len) return;
    state.selectSettingsCategory(settings_controller.Category.all[index]);
}

fn openActionDraftLabel(state: *const runtime.AppState) []const u8 {
    if (state.settings_controller.draft.open_action == .custom) return "Custom";
    return OPEN_CHOICES[openActionSelectedIndex(state)].label;
}

/// Renders the centred settings dialog over the workspace.
pub fn render(state: *runtime.AppState, width: f32, height: f32) void {
    if (!state.settings_controller.modal_visible) return;
    state.tickSettingsModalAnimation();
    if (!state.settings_controller.modal_visible) return;
    const fade_t = theme.clampf(state.settings_controller.modal_anim_progress, 0.0, 1.0);
    current_fade_alpha = fade_t * fade_t * (3.0 - 2.0 * fade_t);
    defer current_fade_alpha = 1.0;

    const m = metrics();
    var layout = computeLayout(state, width, height);
    if (consumePendingRuntimesScroll(state, layout)) layout = computeLayout(state, width, height);
    state.settings_controller.scroll_y = theme.clampf(state.settings_controller.scroll_y, 0.0, layout.max_scroll_y);
    drawModalChrome(state, width, height, layout);
    drawCategoryNav(state, layout);
    drawHeaderBar(state, layout);
    drawPageChrome(state, layout);

    const clip = layout.body_clip;
    const draft = &state.settings_controller.draft;
    switch (state.settings_controller.active_category) {
        .appearance => {
            const selected_theme = @min(draft.theme_choice, state.settingsThemeChoiceCount() - 1);
            drawDropdown(state, layout.theme_dropdown, state.settingsThemeChoiceLabel(selected_theme), .theme_dropdown, state.settings_controller.theme_dropdown_open, clip);
            drawDropdown(state, layout.ui_font_family_dropdown, draft.ui_font_family.label(), .ui_font_family_dropdown, state.settings_controller.ui_font_family_dropdown_open, clip);
            drawStepper(state, draft.font_size, app_config.MIN_FONT_SIZE, app_config.MAX_FONT_SIZE, .ui_font_dec, .ui_font_inc, layout.ui_font_dec, layout.ui_font_inc, clip);
            const motion = draft.reduced_motion;
            drawSwitchRow(state, layout.reduced_motion, motion.all(), isControlHovered(state, .reduced_motion), clip);
            for (REDUCED_MOTION_PARTS, layout.reduced_motion_parts) |part, rect| {
                drawSwitchRow(state, rect, reducedMotionPart(motion, part.part), isControlHovered(state, part.control), clip);
            }
            drawCompanionExperimentalRow(state, layout.companion_toggle, draft.companion_enabled, isControlHovered(state, .companion_toggle), clip);
            if (draft.companion_enabled) {
                drawDropdown(state, layout.companion_character_dropdown, companionCharacterLabel(companionCharacterIndex(draft.companion_character)), .companion_character_dropdown, state.settings_controller.companion_character_dropdown_open, clip);
            }
        },
        .workspace => {
            drawDropdown(state, layout.open_action_dropdown, openActionDraftLabel(state), .open_action_dropdown, state.settings_controller.open_action_dropdown_open, clip);
            drawSegmented(state, &.{ layout.workspace_tabs_automatic, layout.workspace_tabs_always, layout.workspace_tabs_disabled }, &.{ "Auto", "Always", "Off" }, @intFromEnum(draft.workspace_tabs), &.{ .workspace_tabs_automatic, .workspace_tabs_always, .workspace_tabs_disabled }, clip);
            drawSegmented(state, &.{ layout.new_chat_new_pane, layout.new_chat_replace_pane }, &.{ "New pane", "Replace" }, if (draft.new_chat_pane_behavior == .new_pane) 0 else 1, &.{ .new_chat_new_pane, .new_chat_replace_pane }, clip);
            drawSegmented(state, &.{ layout.workspace_split_default_chat, layout.workspace_split_default_terminal }, &.{ "Chat", "Terminal" }, if (draft.workspace_split_default_pane == .chat) 0 else 1, &.{ .workspace_split_default_chat, .workspace_split_default_terminal }, clip);
            drawSegmented(state, &.{ layout.workspace_new_tab_chat, layout.workspace_new_tab_terminal }, &.{ "Chat", "Terminal" }, if (draft.workspace_new_tab_pane == .chat) 0 else 1, &.{ .workspace_new_tab_chat, .workspace_new_tab_terminal }, clip);
            drawSwitchRow(state, layout.workspace_unzoom_on_navigation, draft.unzoom_on_pane_navigation, isControlHovered(state, .workspace_unzoom_on_navigation), clip);
            drawStepper(state, draft.workspace_pane_gap, app_config.MIN_WORKSPACE_PANE_GAP, app_config.MAX_WORKSPACE_PANE_GAP, .workspace_pane_gap_dec, .workspace_pane_gap_inc, layout.workspace_pane_gap_dec, layout.workspace_pane_gap_inc, clip);
            drawStepper(state, @floatFromInt(draft.workspace_panes_per_view), @floatFromInt(app_config.MIN_WORKSPACE_PANES_PER_VIEW), @floatFromInt(app_config.MAX_WORKSPACE_PANES_PER_VIEW), .workspace_panes_per_view_dec, .workspace_panes_per_view_inc, layout.workspace_panes_per_view_dec, layout.workspace_panes_per_view_inc, clip);
            drawSegmented(state, &.{ layout.workspace_scroll_mode_automatic, layout.workspace_scroll_mode_always, layout.workspace_scroll_mode_disabled }, &.{ "Auto", "Always", "Off" }, @intFromEnum(draft.workspace_scroll_mode), &.{ .workspace_scroll_mode_automatic, .workspace_scroll_mode_always, .workspace_scroll_mode_disabled }, clip);
            if (draft.workspace_scroll_mode == .automatic) {
                drawStepper(state, @floatFromInt(draft.workspace_scroll_threshold), @floatFromInt(app_config.MIN_WORKSPACE_SCROLL_THRESHOLD), @floatFromInt(app_config.MAX_WORKSPACE_SCROLL_THRESHOLD), .workspace_scroll_threshold_dec, .workspace_scroll_threshold_inc, layout.workspace_scroll_threshold_dec, layout.workspace_scroll_threshold_inc, clip);
            }
            drawSegmented(state, &.{ layout.workspace_scroll_horizontal, layout.workspace_scroll_vertical }, &.{ "Horizontal", "Vertical" }, if (draft.workspace_scroll_direction == .horizontal) 0 else 1, &.{ .workspace_scroll_horizontal, .workspace_scroll_vertical }, clip);
        },
        .chat => {
            drawSegmented(state, &.{ layout.tool_groups_collapsed, layout.tool_groups_expanded, layout.tool_groups_remember_last }, &.{ "Collapse", "Expand", "Remember" }, switch (draft.tool_call_group_preference) {
                .collapsed => 0,
                .expanded => 1,
                .remember_last => 2,
            }, &.{ .tool_groups_collapsed, .tool_groups_expanded, .tool_groups_remember_last }, clip);
            drawSegmented(state, &.{ layout.diff_layout_stacked, layout.diff_layout_split }, &.{ "Stacked", "Split" }, if (draft.diff_layout_preference == .stacked) 0 else 1, &.{ .diff_layout_stacked, .diff_layout_split }, clip);
            drawSwitchRow(state, layout.automatic_chat_titles, draft.automatic_chat_titles_enabled, isControlHovered(state, .automatic_chat_titles), clip);
            if (draft.automatic_chat_titles_enabled) {
                drawDropdown(state, layout.chat_title_provider_dropdown, state.settingsChatTitleProviderLabel(state.settingsChatTitleProviderSelectedIndex()), .chat_title_provider_dropdown, state.settings_controller.title_provider_dropdown_open, clip);
                drawDropdown(state, layout.chat_title_model_dropdown, state.settingsChatTitleModelSelectedLabel(), .chat_title_model_dropdown, state.settings_controller.title_model_dropdown_open, clip);
            }
            drawDropdown(state, layout.new_chat_provider_dropdown, state.settingsNewChatProviderLabel(state.settingsNewChatProviderSelectedIndex()), .new_chat_provider_dropdown, state.settings_controller.new_chat_provider_dropdown_open, clip);
            drawDropdown(state, layout.new_chat_model_dropdown, state.settingsNewChatModelSelectedLabel(), .new_chat_model_dropdown, state.settings_controller.new_chat_model_dropdown_open, clip);
            drawDropdown(state, layout.new_chat_reasoning_dropdown, state.settingsNewChatReasoningSelectedLabel(), .new_chat_reasoning_dropdown, state.settings_controller.new_chat_reasoning_dropdown_open, clip);
            drawSwitchRow(state, layout.file_links_neovim_pane, draft.file_links_in_neovim_pane, isControlHovered(state, .file_links_neovim_pane), clip);
        },
        .terminal => {
            drawStepper(state, draft.terminal_font_size, app_config.MIN_TERMINAL_FONT_SIZE, app_config.MAX_TERMINAL_FONT_SIZE, .terminal_font_dec, .terminal_font_inc, layout.terminal_font_dec, layout.terminal_font_inc, clip);
        },
        .browser => {
            drawSegmented(state, &.{ layout.links_verde_browser, layout.links_system_browser }, &.{ "Verde", "System" }, if (draft.link_open_target == .verde_browser) 0 else 1, &.{ .links_verde_browser, .links_system_browser }, clip);
            drawSegmented(state, &.{ layout.chat_links_global, layout.chat_links_verde_browser, layout.chat_links_system_browser }, &.{ "Global", "Verde", "System" }, @intFromEnum(draft.chat_link_open_override), &.{ .chat_links_global, .chat_links_verde_browser, .chat_links_system_browser }, clip);
            drawSegmented(state, &.{ layout.terminal_links_global, layout.terminal_links_verde_browser, layout.terminal_links_system_browser }, &.{ "Global", "Verde", "System" }, @intFromEnum(draft.terminal_link_open_override), &.{ .terminal_links_global, .terminal_links_verde_browser, .terminal_links_system_browser }, clip);
            drawBrowserScrollSpeedSlider(state, layout.browser_scroll_speed, draft.browser_scroll_speed, isControlHovered(state, .browser_scroll_speed), clip);
        },
        .providers => drawProvidersCard(state, layout, m),
        .connections => drawRuntimeCard(state, layout),
        .agents => {
            const mcp_installed = state.settings_controller.mcp_summary.installedCount() > 0;
            drawSwitchRow(state, layout.mcp_tools, mcp_installed, isControlHovered(state, .mcp_tools), clip);
            var mcp_status_buf: [120]u8 = undefined;
            const mcp_status = if (state.settings_controller.mcp_summary.detectedCount() == 0)
                "No supported providers detected"
            else if (state.settings_controller.mcp_summary.failedCount() > 0)
                std.fmt.bufPrint(&mcp_status_buf, "Installed for {d} · {d} failed", .{ state.settings_controller.mcp_summary.installedCount(), state.settings_controller.mcp_summary.failedCount() }) catch "Some provider configs could not be updated"
            else if (state.settings_controller.mcp_summary.conflictCount() > 0)
                std.fmt.bufPrint(&mcp_status_buf, "Installed for {d} · {d} conflict(s) kept", .{ state.settings_controller.mcp_summary.installedCount(), state.settings_controller.mcp_summary.conflictCount() }) catch "Some existing verde entries were preserved"
            else
                std.fmt.bufPrint(&mcp_status_buf, "Installed for {d} of {d} detected", .{ state.settings_controller.mcp_summary.installedCount(), state.settings_controller.mcp_summary.detectedCount() }) catch "Workspace-aware in Verde panes";
            drawRowDescription(state, layout.mcp_tools, designUi(SWITCH_W), mcp_status, clip);
            drawSwitchRow(state, layout.hooks_claude, state.settings_controller.hook_claude_installed, isControlHovered(state, .hooks_claude), clip);
            drawSwitchRow(state, layout.hooks_codex, state.settings_controller.hook_codex_installed, isControlHovered(state, .hooks_codex), clip);
            drawSwitchRow(state, layout.hooks_cursor, state.settings_controller.hook_cursor_installed, isControlHovered(state, .hooks_cursor), clip);
            drawSwitchRow(state, layout.hooks_opencode, state.settings_controller.hook_opencode_installed, isControlHovered(state, .hooks_opencode), clip);
            drawSwitchRow(state, layout.hooks_grok, state.settings_controller.hook_grok_installed, isControlHovered(state, .hooks_grok), clip);
            drawSwitchRow(state, layout.hooks_amp, state.settings_controller.hook_amp_installed, isControlHovered(state, .hooks_amp), clip);
            drawSwitchRow(state, layout.hooks_pi, state.settings_controller.hook_pi_installed, isControlHovered(state, .hooks_pi), clip);
        },
        .app => drawUpdatesPage(state, layout, m),
    }

    drawBodyScrollbar(state, layout);
    drawThemeDropdownMenu(state, layout);
    drawCompanionCharacterDropdownMenu(state, layout);
    drawUiFontFamilyDropdownMenu(state, layout);
    drawChatTitleDropdownMenu(state, layout, true);
    drawChatTitleDropdownMenu(state, layout, false);
    drawNewChatDropdownMenu(state, layout, .provider);
    drawNewChatDropdownMenu(state, layout, .model);
    drawNewChatDropdownMenu(state, layout, .reasoning);
    drawOpenActionDropdownMenu(state, layout);
}

// App page controls: version row buttons, auto-check switch, release notes
// block and the notifications switch. Row labels come from the page chrome.
fn drawUpdatesPage(state: *runtime.AppState, layout: SettingsLayout, m: Metrics) void {
    const clip = layout.body_clip;
    var version_buf: [96]u8 = undefined;
    const update_status = switch (state.settings_controller.update.status) {
        .idle => std.fmt.bufPrint(&version_buf, "Installed {s}", .{build_options.version}) catch "Installed version unavailable",
        .checking => std.fmt.bufPrint(&version_buf, "Installed {s} · Checking…", .{build_options.version}) catch "Checking for updates…",
        .up_to_date => std.fmt.bufPrint(&version_buf, "Installed {s} · Up to date", .{build_options.version}) catch "Verde is up to date",
        .update_available => if (state.settings_controller.update.release) |release|
            std.fmt.bufPrint(&version_buf, "Installed {s} · {s} available", .{ build_options.version, release.version }) catch "Update available"
        else
            "Update available",
        .failed => std.fmt.bufPrint(&version_buf, "Installed {s} · Check failed", .{build_options.version}) catch "Update check failed",
    };
    drawRowDescription(state, layout.updates_version_row, layout.updates_download.x + layout.updates_download.w - layout.updates_check.x, update_status, clip);
    const check_style: ButtonStyle = if (state.settings_controller.update.status == .checking) .disabled else .secondary;
    drawActionButton(state, layout.updates_check, if (state.settings_controller.update.status == .checking) "Checking…" else "Check now", check_style, isControlHovered(state, .updates_check), clip);
    const update_button_enabled = state.updateInstallerButtonEnabled();
    const update_button_style: ButtonStyle = if (!update_button_enabled)
        .disabled
    else if (state.settings_controller.update_installer_started)
        .secondary
    else
        .primary;
    drawActionButton(state, layout.updates_download, state.updateInstallerButtonLabel(), update_button_style, isControlHovered(state, .updates_download), clip);
    drawSwitchRow(state, layout.updates_automatic, state.settings_controller.draft.check_for_updates_automatically, isControlHovered(state, .updates_automatic), clip);

    const notes_x = layout.updates_notes_row.x + m.card_pad;
    const notes_w = layout.updates_notes_row.w - m.card_pad * 2.0;
    if (state.settings_controller.package_update_command) |command| {
        const hint_y = layout.updates_package_hint_y;
        const hint_h = wrappedNotesRows(PACKAGE_UPDATE_HINT, notes_w) * notesLineHeight();
        queueWrappedText(state, .{ .x = notes_x, .y = hint_y, .w = notes_w, .h = hint_h }, PACKAGE_UPDATE_HINT, paletteColor(textHint()), designUi(NOTES_FONT_SIZE), clip);
        queueText(state, .{ .x = notes_x, .y = hint_y + hint_h, .w = notes_w, .h = m.label_h }, command, paletteColor(textLabel()), designUi(ROW_DESCRIPTION_FONT), clip);
    }
    if (state.settings_controller.update_notes_expanded and state.settings_controller.update.release != null) {
        var iter = NotesLineIterator.init(state.settings_controller.update.release.?.notes);
        var line_y = layout.updates_notes_y;
        while (iter.next()) |line| {
            const line_h = wrappedNotesRows(line.text, notes_w) * notesLineHeight();
            const line_rect: palette.Rect = .{ .x = notes_x, .y = line_y, .w = notes_w, .h = line_h };
            if (intersectRect(line_rect, clip)) |line_clip| {
                const line_color = if (line.heading) textLabel() else textHint();
                queueWrappedText(state, line_rect, line.text, paletteColor(line_color), designUi(NOTES_FONT_SIZE), line_clip);
            }
            line_y += line_h;
        }
    } else {
        const notes = if (state.settings_controller.update.release) |release| releaseNotesPreview(release.notes) else "Release notes appear here when a release is found.";
        const notes_rect: palette.Rect = .{ .x = notes_x, .y = layout.updates_notes_y, .w = notes_w, .h = m.label_h * 2.0 };
        if (intersectRect(notes_rect, clip)) |notes_clip| {
            queueWrappedText(state, notes_rect, notes, paletteColor(textHint()), designUi(NOTES_FONT_SIZE), notes_clip);
        }
    }
    if (layout.updates_notes_toggle) |toggle_rect| {
        const toggle_color = if (isControlHovered(state, .updates_notes_toggle)) textPrimary() else textLabel();
        queueRoleText(state, toggle_rect, notesToggleLabel(state), paletteColor(toggle_color), designUi(NOTES_LINK_FONT_SIZE), .ui_medium, clip);
    }
    const release_page_color = if (isControlHovered(state, .updates_release_page)) textPrimary() else textLabel();
    queueRoleText(state, layout.updates_release_page, RELEASE_PAGE_LABEL, paletteColor(release_page_color), designUi(NOTES_LINK_FONT_SIZE), .ui_medium, clip);

    drawSwitchRow(state, layout.notifications_toggle, state.settings_controller.draft.notifications_enabled, isControlHovered(state, .notifications_toggle), clip);
}

/// Scrolls settings modal content within the fixed header/footer chrome.
pub fn handleWheel(state: *runtime.AppState, width: f32, height: f32, x: f32, y: f32, wheel_y: f32) bool {
    if (!state.settings_controller.modal_visible) return false;
    if (state.settings_controller.modal_closing) return true;

    const layout = computeLayout(state, width, height);
    if (!rectContains(layout.modal, x, y)) return false;
    if (state.settings_controller.theme_dropdown_open and rectContains(themeMenuRect(state, layout), x, y)) {
        const max_scroll = themeMenuMaxScroll(state);
        const next = if (wheel_y < 0.0)
            @min(state.settings_controller.theme_menu_scroll + 1, max_scroll)
        else if (wheel_y > 0.0)
            state.settings_controller.theme_menu_scroll -| 1
        else
            state.settings_controller.theme_menu_scroll;
        if (next != state.settings_controller.theme_menu_scroll) {
            state.settings_controller.theme_menu_scroll = next;
            state.markDirty();
        }
        return true;
    }
    // Fixed three-row companion menu: consume wheel so the body does not scroll under it.
    if (state.settings_controller.companion_character_dropdown_open and rectContains(companionCharacterMenuRect(layout), x, y)) return true;
    if (state.settings_controller.ui_font_family_dropdown_open and rectContains(uiFontFamilyMenuRect(layout), x, y)) return true;
    if (state.settings_controller.open_action_dropdown_open and rectContains(openActionMenuRect(layout), x, y)) return true;
    if (state.settings_controller.title_provider_dropdown_open and rectContains(titleProviderMenuRect(state, layout), x, y)) return true;
    if (state.settings_controller.title_model_dropdown_open and rectContains(titleModelMenuRect(state, layout), x, y)) {
        const max_scroll = titleModelMenuMaxScroll(state);
        const next = if (wheel_y < 0.0)
            @min(state.settings_controller.title_model_menu_scroll + 1, max_scroll)
        else if (wheel_y > 0.0)
            state.settings_controller.title_model_menu_scroll -| 1
        else
            state.settings_controller.title_model_menu_scroll;
        if (next != state.settings_controller.title_model_menu_scroll) {
            state.settings_controller.title_model_menu_scroll = next;
            state.markDirty();
        }
        return true;
    }
    if (state.settings_controller.new_chat_model_dropdown_open and rectContains(newChatMenuRect(state, layout, .model), x, y)) {
        const max_scroll = newChatModelMenuMaxScroll(state);
        const next = if (wheel_y < 0.0)
            @min(state.settings_controller.new_chat_model_menu_scroll + 1, max_scroll)
        else if (wheel_y > 0.0)
            state.settings_controller.new_chat_model_menu_scroll -| 1
        else
            state.settings_controller.new_chat_model_menu_scroll;
        if (next != state.settings_controller.new_chat_model_menu_scroll) {
            state.settings_controller.new_chat_model_menu_scroll = next;
            state.markDirty();
        }
        return true;
    }
    if (layout.max_scroll_y <= 0.0) return true;
    if (!rectContains(layout.body_clip, x, y)) return true;

    const delta = -wheel_y * theme.scaledUi(72.0);
    const next = theme.clampf(state.settings_controller.scroll_y + delta, 0.0, layout.max_scroll_y);
    if (next != state.settings_controller.scroll_y) {
        state.settings_controller.scroll_y = next;
        state.markDirty();
    }
    return true;
}

/// Updates settings-modal hover using hits from `refreshPaletteModalHits`.
pub fn updateHover(state: *runtime.AppState, x: f32, y: f32) void {
    if (!state.settings_controller.modal_visible) {
        if (state.settings_controller.hover_control != null or state.settings_controller.hover_runtime_action != null or state.settings_controller.close_hovered or state.settings_controller.hover_category != null or state.settings_controller.open_action_hover_index != null or state.settings_controller.theme_hover_index != null or state.settings_controller.companion_character_hover_index != null or state.settings_controller.ui_font_family_hover_index != null or state.settings_controller.title_menu_hover_index != null or state.settings_controller.new_chat_menu_hover_index != null) {
            state.settings_controller.hover_control = null;
            state.settings_controller.hover_runtime_action = null;
            state.settings_controller.close_hovered = false;
            state.settings_controller.hover_category = null;
            state.settings_controller.open_action_hover_index = null;
            state.settings_controller.theme_hover_index = null;
            state.settings_controller.companion_character_hover_index = null;
            state.settings_controller.ui_font_family_hover_index = null;
            state.settings_controller.title_menu_hover_index = null;
            state.settings_controller.new_chat_menu_hover_index = null;
            state.markDirty();
        }
        return;
    }

    var new_hover: ?u8 = null;
    var runtime_hover: ?usize = null;
    var theme_hover: ?usize = null;
    var companion_hover: ?usize = null;
    var ui_font_family_hover: ?usize = null;
    var title_hover: ?usize = null;
    var new_chat_hover: ?usize = null;
    var category_hover: ?u8 = null;
    var open_action_hover: ?usize = null;
    var close_hovered = false;
    var i = state.palette_modal_hits.items.len;
    while (i > 0) {
        i -= 1;
        const hit = state.palette_modal_hits.items[i];
        if (hit.action == .settings_close) {
            if (rectContains(hit.rect, x, y)) close_hovered = true;
            continue;
        }
        if (hit.action == .settings_category and rectContains(hit.rect, x, y)) {
            category_hover = @intCast(hit.index);
            break;
        }
        if (hit.action == .settings_open_option and rectContains(hit.rect, x, y)) {
            open_action_hover = hit.index;
            break;
        }
        if (hit.action == .settings_theme_option and rectContains(hit.rect, x, y)) {
            if (state.settings_controller.companion_character_dropdown_open) {
                companion_hover = hit.index;
            } else if (state.settings_controller.ui_font_family_dropdown_open) {
                ui_font_family_hover = hit.index;
            } else {
                theme_hover = hit.index;
            }
            break;
        }
        if ((hit.action == .settings_title_provider_option or hit.action == .settings_title_model_option) and rectContains(hit.rect, x, y)) {
            title_hover = hit.index;
            break;
        }
        if ((hit.action == .settings_new_chat_provider_option or hit.action == .settings_new_chat_model_option or hit.action == .settings_new_chat_reasoning_option) and rectContains(hit.rect, x, y)) {
            new_chat_hover = hit.index;
            break;
        }
        if (hit.action == .settings_runtime_action and rectContains(hit.rect, x, y)) {
            runtime_hover = hit.index;
            break;
        }
        if (hit.action != .settings_control) continue;
        if (!rectContains(hit.rect, x, y)) continue;
        new_hover = @intCast(hit.index);
        break;
    }

    if (state.settings_controller.hover_control == new_hover and state.settings_controller.hover_runtime_action == runtime_hover and state.settings_controller.close_hovered == close_hovered and state.settings_controller.hover_category == category_hover and state.settings_controller.open_action_hover_index == open_action_hover and state.settings_controller.theme_hover_index == theme_hover and state.settings_controller.companion_character_hover_index == companion_hover and state.settings_controller.ui_font_family_hover_index == ui_font_family_hover and state.settings_controller.title_menu_hover_index == title_hover and state.settings_controller.new_chat_menu_hover_index == new_chat_hover) return;
    state.settings_controller.hover_control = new_hover;
    state.settings_controller.hover_runtime_action = runtime_hover;
    state.settings_controller.close_hovered = close_hovered;
    state.settings_controller.hover_category = category_hover;
    state.settings_controller.open_action_hover_index = open_action_hover;
    state.settings_controller.theme_hover_index = theme_hover;
    state.settings_controller.companion_character_hover_index = companion_hover;
    state.settings_controller.ui_font_family_hover_index = ui_font_family_hover;
    state.settings_controller.title_menu_hover_index = title_hover;
    state.settings_controller.new_chat_menu_hover_index = new_chat_hover;
    state.markDirty();
}

/// Applies a settings control interaction to the in-modal draft.
pub fn applyControlAt(state: *runtime.AppState, control_index: usize, rect: palette.Rect, x: f32) void {
    applyControl(state, control_index);
    const control: Control = @enumFromInt(control_index);
    if (control != .browser_scroll_speed) return;
    state.settings_controller.browser_scroll_speed_drag_active = true;
    state.settings_controller.browser_scroll_speed_drag_x = rect.x;
    state.settings_controller.browser_scroll_speed_drag_w = rect.w;
    _ = updateBrowserScrollSpeedDrag(state, x);
}

/// Updates the browser scroll-speed draft while its settings slider owns the pointer.
pub fn updateBrowserScrollSpeedDrag(state: *runtime.AppState, x: f32) bool {
    if (!state.settings_controller.browser_scroll_speed_drag_active) return false;
    const track: palette.Rect = .{
        .x = state.settings_controller.browser_scroll_speed_drag_x,
        .y = 0.0,
        .w = state.settings_controller.browser_scroll_speed_drag_w,
        .h = 1.0,
    };
    const next = browserScrollSpeedFromPoint(track, x);
    if (next != state.settings_controller.draft.browser_scroll_speed) {
        state.settings_controller.draft.browser_scroll_speed = next;
        state.markDirty();
    }
    return true;
}

/// Releases any pointer capture held by the browser scroll-speed slider.
pub fn endBrowserScrollSpeedDrag(state: *runtime.AppState) void {
    if (!state.settings_controller.browser_scroll_speed_drag_active) return;
    state.settings_controller.browser_scroll_speed_drag_active = false;
    state.commitSettingsPreference();
}

/// Applies a settings control that does not require pointer geometry.
pub fn applyControl(state: *runtime.AppState, control_index: usize) void {
    const control: Control = @enumFromInt(control_index);
    if (control != .theme_dropdown) {
        state.settings_controller.theme_dropdown_open = false;
        state.settings_controller.theme_hover_index = null;
    }
    if (control != .companion_character_dropdown) {
        state.settings_controller.companion_character_dropdown_open = false;
        state.settings_controller.companion_character_hover_index = null;
    }
    if (control != .ui_font_family_dropdown) {
        state.settings_controller.ui_font_family_dropdown_open = false;
        state.settings_controller.ui_font_family_hover_index = null;
    }
    if (control != .chat_title_provider_dropdown) state.settings_controller.title_provider_dropdown_open = false;
    if (control != .chat_title_model_dropdown) state.settings_controller.title_model_dropdown_open = false;
    if (control != .chat_title_provider_dropdown and control != .chat_title_model_dropdown) state.settings_controller.title_menu_hover_index = null;
    if (control != .new_chat_provider_dropdown) state.settings_controller.new_chat_provider_dropdown_open = false;
    if (control != .new_chat_model_dropdown) state.settings_controller.new_chat_model_dropdown_open = false;
    if (control != .new_chat_reasoning_dropdown) state.settings_controller.new_chat_reasoning_dropdown_open = false;
    if (control != .open_action_dropdown) {
        state.settings_controller.open_action_dropdown_open = false;
        state.settings_controller.open_action_hover_index = null;
    }
    switch (control) {
        .ui_font_dec => state.settings_controller.draft.font_size = theme.clampf(state.settings_controller.draft.font_size - 1.0, app_config.MIN_FONT_SIZE, app_config.MAX_FONT_SIZE),
        .ui_font_inc => state.settings_controller.draft.font_size = theme.clampf(state.settings_controller.draft.font_size + 1.0, app_config.MIN_FONT_SIZE, app_config.MAX_FONT_SIZE),
        .terminal_font_dec => state.settings_controller.draft.terminal_font_size = theme.clampf(state.settings_controller.draft.terminal_font_size - 1.0, app_config.MIN_TERMINAL_FONT_SIZE, app_config.MAX_TERMINAL_FONT_SIZE),
        .terminal_font_inc => state.settings_controller.draft.terminal_font_size = theme.clampf(state.settings_controller.draft.terminal_font_size + 1.0, app_config.MIN_TERMINAL_FONT_SIZE, app_config.MAX_TERMINAL_FONT_SIZE),
        .workspace_pane_gap_dec => state.settings_controller.draft.workspace_pane_gap = theme.clampf(state.settings_controller.draft.workspace_pane_gap - 1.0, app_config.MIN_WORKSPACE_PANE_GAP, app_config.MAX_WORKSPACE_PANE_GAP),
        .workspace_pane_gap_inc => state.settings_controller.draft.workspace_pane_gap = theme.clampf(state.settings_controller.draft.workspace_pane_gap + 1.0, app_config.MIN_WORKSPACE_PANE_GAP, app_config.MAX_WORKSPACE_PANE_GAP),
        .workspace_panes_per_view_dec => {
            if (state.settings_controller.draft.workspace_panes_per_view > app_config.MIN_WORKSPACE_PANES_PER_VIEW) state.settings_controller.draft.workspace_panes_per_view -= 1;
        },
        .workspace_panes_per_view_inc => {
            if (state.settings_controller.draft.workspace_panes_per_view < app_config.MAX_WORKSPACE_PANES_PER_VIEW) state.settings_controller.draft.workspace_panes_per_view += 1;
        },
        .workspace_split_default_chat => state.settings_controller.draft.workspace_split_default_pane = .chat,
        .workspace_split_default_terminal => state.settings_controller.draft.workspace_split_default_pane = .terminal,
        .workspace_new_tab_chat => state.settings_controller.draft.workspace_new_tab_pane = .chat,
        .workspace_new_tab_terminal => state.settings_controller.draft.workspace_new_tab_pane = .terminal,
        .workspace_scroll_use_global => {
            state.settings_controller.draft.workspace_scroll_override_enabled = false;
            state.settings_controller.draft.workspace_scroll_mode = state.app_config.workspace_scroll_mode;
            state.settings_controller.draft.workspace_scroll_threshold = state.app_config.workspace_scroll_threshold;
        },
        .workspace_scroll_override => state.settings_controller.draft.workspace_scroll_override_enabled = true,
        .workspace_scroll_mode_automatic => state.settings_controller.draft.workspace_scroll_mode = .automatic,
        .workspace_scroll_mode_always => state.settings_controller.draft.workspace_scroll_mode = .always,
        .workspace_scroll_mode_disabled => state.settings_controller.draft.workspace_scroll_mode = .disabled,
        .workspace_scroll_threshold_dec => {
            if (state.settings_controller.draft.workspace_scroll_threshold > app_config.MIN_WORKSPACE_SCROLL_THRESHOLD) state.settings_controller.draft.workspace_scroll_threshold -= 1;
        },
        .workspace_scroll_threshold_inc => {
            if (state.settings_controller.draft.workspace_scroll_threshold < app_config.MAX_WORKSPACE_SCROLL_THRESHOLD) state.settings_controller.draft.workspace_scroll_threshold += 1;
        },
        .workspace_scroll_horizontal => state.settings_controller.draft.workspace_scroll_direction = .horizontal,
        .workspace_scroll_vertical => state.settings_controller.draft.workspace_scroll_direction = .vertical,
        .reduced_motion => {
            const motion = &state.settings_controller.draft.reduced_motion;
            motion.setAll(!motion.all());
        },
        .reduced_motion_pane_scroll,
        .reduced_motion_pane_layout,
        .reduced_motion_status_pulse,
        .reduced_motion_chat,
        .reduced_motion_chrome,
        => {
            const motion = &state.settings_controller.draft.reduced_motion;
            for (REDUCED_MOTION_PARTS) |part| {
                if (part.control == control) toggleReducedMotionPart(motion, part.part);
            }
        },
        .workspace_tabs_automatic => state.settings_controller.draft.workspace_tabs = .automatic,
        .workspace_tabs_always => state.settings_controller.draft.workspace_tabs = .always,
        .workspace_tabs_disabled => state.settings_controller.draft.workspace_tabs = .disabled,
        .theme_dropdown => {
            state.settings_controller.theme_dropdown_open = !state.settings_controller.theme_dropdown_open;
            if (state.settings_controller.theme_dropdown_open) {
                state.settings_controller.companion_character_dropdown_open = false;
                state.settings_controller.companion_character_hover_index = null;
                state.settings_controller.theme_hover_index = state.settings_controller.draft.theme_choice;
                ensureThemeChoiceVisible(state, state.settings_controller.draft.theme_choice);
            } else {
                state.settings_controller.theme_hover_index = null;
            }
        },
        .companion_character_dropdown => {
            state.settings_controller.companion_character_dropdown_open = !state.settings_controller.companion_character_dropdown_open;
            if (state.settings_controller.companion_character_dropdown_open) {
                state.settings_controller.theme_dropdown_open = false;
                state.settings_controller.theme_hover_index = null;
                state.settings_controller.companion_character_hover_index = companionCharacterIndex(state.settings_controller.draft.companion_character);
            } else {
                state.settings_controller.companion_character_hover_index = null;
            }
        },
        .ui_font_family_dropdown => {
            state.settings_controller.ui_font_family_dropdown_open = !state.settings_controller.ui_font_family_dropdown_open;
            state.settings_controller.ui_font_family_hover_index = if (state.settings_controller.ui_font_family_dropdown_open)
                uiFontFamilyIndex(state.settings_controller.draft.ui_font_family)
            else
                null;
        },
        .tool_groups_collapsed => state.settings_controller.draft.tool_call_group_preference = .collapsed,
        .tool_groups_expanded => state.settings_controller.draft.tool_call_group_preference = .expanded,
        .tool_groups_remember_last => state.settings_controller.draft.tool_call_group_preference = .remember_last,
        .diff_layout_stacked => state.settings_controller.draft.diff_layout_preference = .stacked,
        .diff_layout_split => state.settings_controller.draft.diff_layout_preference = .split,
        .automatic_chat_titles => state.settings_controller.draft.automatic_chat_titles_enabled = !state.settings_controller.draft.automatic_chat_titles_enabled,
        .chat_title_provider_dropdown => {
            state.settings_controller.title_provider_dropdown_open = !state.settings_controller.title_provider_dropdown_open;
            if (state.settings_controller.title_provider_dropdown_open) {
                state.settings_controller.title_menu_hover_index = state.settingsChatTitleProviderSelectedIndex();
            } else {
                state.settings_controller.title_menu_hover_index = null;
            }
        },
        .chat_title_model_dropdown => {
            state.settings_controller.title_model_dropdown_open = !state.settings_controller.title_model_dropdown_open;
            if (state.settings_controller.title_model_dropdown_open) {
                const selected = state.settingsChatTitleModelSelectedIndex() orelse 0;
                state.settings_controller.title_menu_hover_index = selected;
                ensureTitleModelChoiceVisible(state, selected);
            } else {
                state.settings_controller.title_menu_hover_index = null;
            }
        },
        .new_chat_provider_dropdown => {
            state.settings_controller.new_chat_provider_dropdown_open = !state.settings_controller.new_chat_provider_dropdown_open;
            state.settings_controller.new_chat_menu_hover_index = if (state.settings_controller.new_chat_provider_dropdown_open) state.settingsNewChatProviderSelectedIndex() else null;
        },
        .new_chat_model_dropdown => {
            state.settings_controller.new_chat_model_dropdown_open = !state.settings_controller.new_chat_model_dropdown_open;
            if (state.settings_controller.new_chat_model_dropdown_open) {
                const selected = state.settingsNewChatModelSelectedIndex() orelse 0;
                state.settings_controller.new_chat_menu_hover_index = selected;
                ensureNewChatModelChoiceVisible(state, selected);
            } else state.settings_controller.new_chat_menu_hover_index = null;
        },
        .new_chat_reasoning_dropdown => {
            state.settings_controller.new_chat_reasoning_dropdown_open = !state.settings_controller.new_chat_reasoning_dropdown_open;
            state.settings_controller.new_chat_menu_hover_index = if (state.settings_controller.new_chat_reasoning_dropdown_open) state.settingsNewChatReasoningSelectedIndex() else null;
        },
        .new_chat_new_pane => state.settings_controller.draft.new_chat_pane_behavior = .new_pane,
        .new_chat_replace_pane => state.settings_controller.draft.new_chat_pane_behavior = .replace_pane,
        .open_folder => state.settings_controller.draft.open_action = .folder,
        .open_editor => state.settings_controller.draft.open_action = .editor,
        .open_cursor => state.settings_controller.draft.open_action = .cursor,
        .open_vscode => state.settings_controller.draft.open_action = .vscode,
        .open_zed => state.settings_controller.draft.open_action = .zed,
        .open_action_dropdown => {
            state.settings_controller.open_action_dropdown_open = !state.settings_controller.open_action_dropdown_open;
            state.settings_controller.open_action_hover_index = if (state.settings_controller.open_action_dropdown_open)
                openActionSelectedIndex(state)
            else
                null;
            state.markDirty();
            return;
        },
        .file_links_neovim_pane => state.settings_controller.draft.file_links_in_neovim_pane = !state.settings_controller.draft.file_links_in_neovim_pane,
        .workspace_unzoom_on_navigation => state.settings_controller.draft.unzoom_on_pane_navigation = !state.settings_controller.draft.unzoom_on_pane_navigation,
        .links_verde_browser => state.settings_controller.draft.link_open_target = .verde_browser,
        .links_system_browser => state.settings_controller.draft.link_open_target = .system_browser,
        .chat_links_global => state.settings_controller.draft.chat_link_open_override = .global,
        .chat_links_verde_browser => state.settings_controller.draft.chat_link_open_override = .verde_browser,
        .chat_links_system_browser => state.settings_controller.draft.chat_link_open_override = .system_browser,
        .terminal_links_global => state.settings_controller.draft.terminal_link_open_override = .global,
        .terminal_links_verde_browser => state.settings_controller.draft.terminal_link_open_override = .verde_browser,
        .terminal_links_system_browser => state.settings_controller.draft.terminal_link_open_override = .system_browser,
        .browser_scroll_speed => {
            state.markDirty();
            return;
        },
        .companion_toggle => {
            state.settings_controller.draft.companion_enabled = !state.settings_controller.draft.companion_enabled;
            if (!state.settings_controller.draft.companion_enabled) {
                state.settings_controller.companion_character_dropdown_open = false;
                state.settings_controller.companion_character_hover_index = null;
            }
        },
        // Acts immediately (filesystem side effect), independent of Save/Cancel.
        .mcp_tools => {
            state.toggleGlobalMcpIntegration();
            return;
        },
        .hooks_claude => {
            state.toggleClaudeGlobalHooks();
            return;
        },
        .hooks_codex => {
            state.toggleCodexGlobalHooks();
            return;
        },
        .hooks_cursor => {
            state.toggleCursorGlobalHooks();
            return;
        },
        .hooks_opencode => {
            state.toggleOpencodeGlobalHooks();
            return;
        },
        .hooks_grok => {
            state.toggleGrokGlobalHooks();
            return;
        },
        .hooks_amp => {
            state.toggleAmpGlobalHooks();
            return;
        },
        .hooks_pi => {
            state.togglePiGlobalHooks();
            return;
        },
        .updates_check => {
            state.startUpdateCheck();
            return;
        },
        .updates_download => {
            if (state.updateInstallerButtonEnabled()) state.installAvailableUpdate();
            return;
        },
        .updates_automatic => state.settings_controller.draft.check_for_updates_automatically = !state.settings_controller.draft.check_for_updates_automatically,
        // View-only disclosure, not part of the Save/Cancel draft.
        .updates_notes_toggle => {
            state.settings_controller.update_notes_expanded = !state.settings_controller.update_notes_expanded;
            state.markDirty();
            return;
        },
        .updates_release_page => {
            const url = if (state.settings_controller.update.release) |release| release.page_url else updater.State.releasesUrl();
            state.openConfiguredWebLink(url);
            return;
        },
        // Draft toggle: persisted to verde.json on Save, like the other fields.
        .notifications_toggle => state.settings_controller.draft.notifications_enabled = !state.settings_controller.draft.notifications_enabled,
        .providers_recheck => {
            state.startProviderReadinessCheck();
            state.markDirty();
            return;
        },
        .provider_update_first, .provider_update_1, .provider_update_2, .provider_update_3, .provider_update_4, .provider_update_5, .provider_update_6, .provider_update_last => {
            const row = providerUpdateRowForControl(control).?;
            const provider = settings_controller.settingsProviderForRow(row);
            const provider_snapshot = state.providerReadinessSnapshot();
            switch (providerAction(provider_snapshot.forProvider(provider), provider_snapshot.releaseForProvider(provider))) {
                .install, .update => state.installSettingsProvider(row),
                .sign_in => state.loginSettingsProvider(row),
                .latest, .pending, .none => {},
            }
            return;
        },
        .provider_row_first, .provider_row_1, .provider_row_2, .provider_row_3, .provider_row_4, .provider_row_5, .provider_row_6, .provider_row_last => {
            // Commits on its own; it may also move the new-chat default.
            state.toggleSettingsProviderEnabled(providerRowForControl(control).?);
            return;
        },
    }
    state.commitSettingsPreference();
}

/// Selects a built-in or installed theme, or a Default companion choice when that menu owns the hit channel.
pub fn applyThemeOption(state: *runtime.AppState, choice_index: usize) void {
    if (state.settings_controller.companion_character_dropdown_open) {
        applyCompanionCharacterOption(state, choice_index);
        return;
    }
    if (state.settings_controller.ui_font_family_dropdown_open) {
        applyUiFontFamilyOption(state, choice_index);
        return;
    }
    state.selectSettingsThemeChoice(choice_index);
}

/// Selects the UI font family and applies it immediately; the main loop
/// reloads the renderer's faces when the committed config changes.
pub fn applyUiFontFamilyOption(state: *runtime.AppState, choice_index: usize) void {
    if (choice_index >= uiFontFamilyCount()) return;
    const family = UI_FONT_FAMILY_OPTIONS[choice_index];
    state.settings_controller.ui_font_family_dropdown_open = false;
    state.settings_controller.ui_font_family_hover_index = null;
    if (family == state.settings_controller.draft.ui_font_family) {
        state.markDirty();
        return;
    }
    state.settings_controller.draft.ui_font_family = family;
    state.commitSettingsPreference();
}

/// Selects the companion character and applies it immediately.
pub fn applyCompanionCharacterOption(state: *runtime.AppState, choice_index: usize) void {
    if (choice_index >= companionCharacterCount()) return;
    const character = COMPANION_CHARACTER_OPTIONS[choice_index];
    if (character == state.settings_controller.draft.companion_character) {
        state.settings_controller.companion_character_dropdown_open = false;
        state.settings_controller.companion_character_hover_index = null;
        state.markDirty();
        return;
    }
    state.settings_controller.draft.companion_character = character;
    state.settings_controller.companion_character_dropdown_open = false;
    state.settings_controller.companion_character_hover_index = null;
    state.commitSettingsPreference();
}

pub fn applyOpenActionOption(state: *runtime.AppState, option_index: usize) void {
    if (option_index >= OPEN_CHOICES.len) return;
    state.settings_controller.draft.open_action = switch (OPEN_CHOICES[option_index].control) {
        .open_folder => .folder,
        .open_editor => .editor,
        .open_cursor => .cursor,
        .open_vscode => .vscode,
        .open_zed => .zed,
        else => return,
    };
    state.settings_controller.open_action_dropdown_open = false;
    state.settings_controller.open_action_hover_index = null;
    state.commitSettingsPreference();
}

pub fn applyChatTitleProviderOption(state: *runtime.AppState, option_index: usize) void {
    state.selectSettingsChatTitleProvider(option_index);
}

pub fn applyChatTitleModelOption(state: *runtime.AppState, option_index: usize) void {
    state.selectSettingsChatTitleModel(option_index);
}

pub fn applyNewChatProviderOption(state: *runtime.AppState, option_index: usize) void {
    state.selectSettingsNewChatProvider(option_index);
}

pub fn applyNewChatModelOption(state: *runtime.AppState, option_index: usize) void {
    state.selectSettingsNewChatModel(option_index);
}

pub fn applyNewChatReasoningOption(state: *runtime.AppState, option_index: usize) void {
    state.selectSettingsNewChatReasoning(option_index);
}

/// Handles navigation while a settings dropdown owns keyboard focus.
pub fn handleKeyDown(state: *runtime.AppState, key: sdl.Keycode) bool {
    if (!state.settings_controller.modal_visible) return false;
    if (state.settings_controller.theme_dropdown_open) return handleThemeKeyDown(state, key);
    if (state.settings_controller.companion_character_dropdown_open) return handleCompanionCharacterKeyDown(state, key);
    if (state.settings_controller.ui_font_family_dropdown_open) return handleUiFontFamilyKeyDown(state, key);
    if (state.settings_controller.title_provider_dropdown_open) return handleTitleProviderKeyDown(state, key);
    if (state.settings_controller.title_model_dropdown_open) return handleTitleModelKeyDown(state, key);
    if (state.settings_controller.new_chat_provider_dropdown_open) return handleNewChatMenuKeyDown(state, key, .provider);
    if (state.settings_controller.new_chat_model_dropdown_open) return handleNewChatMenuKeyDown(state, key, .model);
    if (state.settings_controller.new_chat_reasoning_dropdown_open) return handleNewChatMenuKeyDown(state, key, .reasoning);
    if (state.settings_controller.open_action_dropdown_open) return handleOpenActionKeyDown(state, key);
    return false;
}

fn handleThemeKeyDown(state: *runtime.AppState, key: sdl.Keycode) bool {
    const count = state.settingsThemeChoiceCount();
    if (count == 0) return false;
    const current = state.settings_controller.theme_hover_index orelse state.settings_controller.draft.theme_choice;
    const next = switch (key) {
        .up => current -| 1,
        .down => @min(current + 1, count - 1),
        .home => 0,
        .end => count - 1,
        .escape => {
            state.settings_controller.theme_dropdown_open = false;
            state.settings_controller.theme_hover_index = null;
            state.markDirty();
            return true;
        },
        .@"return", .kp_enter => {
            state.selectSettingsThemeChoice(current);
            return true;
        },
        else => return false,
    };
    state.settings_controller.theme_hover_index = next;
    ensureThemeChoiceVisible(state, next);
    state.markDirty();
    return true;
}

fn handleCompanionCharacterKeyDown(state: *runtime.AppState, key: sdl.Keycode) bool {
    const count = companionCharacterCount();
    if (count == 0) return false;
    const current = state.settings_controller.companion_character_hover_index orelse companionCharacterIndex(state.settings_controller.draft.companion_character);
    const next = switch (key) {
        .up => current -| 1,
        .down => @min(current + 1, count - 1),
        .home => 0,
        .end => count - 1,
        .escape => {
            state.settings_controller.companion_character_dropdown_open = false;
            state.settings_controller.companion_character_hover_index = null;
            state.markDirty();
            return true;
        },
        .@"return", .kp_enter => {
            applyCompanionCharacterOption(state, current);
            return true;
        },
        else => return false,
    };
    state.settings_controller.companion_character_hover_index = next;
    state.markDirty();
    return true;
}

fn handleUiFontFamilyKeyDown(state: *runtime.AppState, key: sdl.Keycode) bool {
    const count = uiFontFamilyCount();
    const current = state.settings_controller.ui_font_family_hover_index orelse uiFontFamilyIndex(state.settings_controller.draft.ui_font_family);
    const next = switch (key) {
        .up => current -| 1,
        .down => @min(current + 1, count - 1),
        .home => 0,
        .end => count - 1,
        .escape => {
            state.settings_controller.ui_font_family_dropdown_open = false;
            state.settings_controller.ui_font_family_hover_index = null;
            state.markDirty();
            return true;
        },
        .@"return", .kp_enter => {
            applyUiFontFamilyOption(state, current);
            return true;
        },
        else => return false,
    };
    state.settings_controller.ui_font_family_hover_index = next;
    state.markDirty();
    return true;
}

fn handleTitleProviderKeyDown(state: *runtime.AppState, key: sdl.Keycode) bool {
    const count = state.settingsChatTitleProviderCount();
    if (count == 0) return false;
    const current = state.settings_controller.title_menu_hover_index orelse state.settingsChatTitleProviderSelectedIndex();
    const next = switch (key) {
        .up => current -| 1,
        .down => @min(current + 1, count - 1),
        .home => 0,
        .end => count - 1,
        .escape => {
            state.settings_controller.title_provider_dropdown_open = false;
            state.settings_controller.title_menu_hover_index = null;
            state.markDirty();
            return true;
        },
        .@"return", .kp_enter => {
            state.selectSettingsChatTitleProvider(current);
            return true;
        },
        else => return false,
    };
    state.settings_controller.title_menu_hover_index = next;
    state.markDirty();
    return true;
}

fn handleTitleModelKeyDown(state: *runtime.AppState, key: sdl.Keycode) bool {
    const count = state.settingsChatTitleModelCount();
    if (count == 0) return false;
    const current = @min(state.settings_controller.title_menu_hover_index orelse state.settingsChatTitleModelSelectedIndex() orelse 0, count - 1);
    const next = switch (key) {
        .up => current -| 1,
        .down => @min(current + 1, count - 1),
        .home => 0,
        .end => count - 1,
        .escape => {
            state.settings_controller.title_model_dropdown_open = false;
            state.settings_controller.title_menu_hover_index = null;
            state.markDirty();
            return true;
        },
        .@"return", .kp_enter => {
            state.selectSettingsChatTitleModel(current);
            return true;
        },
        else => return false,
    };
    state.settings_controller.title_menu_hover_index = next;
    ensureTitleModelChoiceVisible(state, next);
    state.markDirty();
    return true;
}

fn ensureThemeChoiceVisible(state: *runtime.AppState, choice_index: usize) void {
    if (choice_index < state.settings_controller.theme_menu_scroll) {
        state.settings_controller.theme_menu_scroll = choice_index;
    } else {
        const visible_count = themeMenuVisibleCount(state);
        if (choice_index >= state.settings_controller.theme_menu_scroll + visible_count) {
            state.settings_controller.theme_menu_scroll = choice_index - visible_count + 1;
        }
    }
    state.settings_controller.theme_menu_scroll = @min(state.settings_controller.theme_menu_scroll, themeMenuMaxScroll(state));
}

fn ensureTitleModelChoiceVisible(state: *runtime.AppState, option_index: usize) void {
    if (option_index < state.settings_controller.title_model_menu_scroll) {
        state.settings_controller.title_model_menu_scroll = option_index;
    } else {
        const visible_count = titleModelMenuVisibleCount(state);
        if (option_index >= state.settings_controller.title_model_menu_scroll + visible_count) {
            state.settings_controller.title_model_menu_scroll = option_index - visible_count + 1;
        }
    }
    state.settings_controller.title_model_menu_scroll = @min(state.settings_controller.title_model_menu_scroll, titleModelMenuMaxScroll(state));
}

fn handleNewChatMenuKeyDown(state: *runtime.AppState, key: sdl.Keycode, kind: NewChatMenuKind) bool {
    const count = newChatMenuCount(state, kind);
    if (count == 0) return false;
    const selected = switch (kind) {
        .provider => state.settingsNewChatProviderSelectedIndex(),
        .model => state.settingsNewChatModelSelectedIndex() orelse 0,
        .reasoning => state.settingsNewChatReasoningSelectedIndex(),
    };
    const current = @min(state.settings_controller.new_chat_menu_hover_index orelse selected, count - 1);
    const next = switch (key) {
        .up => current -| 1,
        .down => @min(current + 1, count - 1),
        .home => 0,
        .end => count - 1,
        .escape => {
            state.settings_controller.new_chat_provider_dropdown_open = false;
            state.settings_controller.new_chat_model_dropdown_open = false;
            state.settings_controller.new_chat_reasoning_dropdown_open = false;
            state.settings_controller.new_chat_menu_hover_index = null;
            state.markDirty();
            return true;
        },
        .@"return", .kp_enter => {
            switch (kind) {
                .provider => state.selectSettingsNewChatProvider(current),
                .model => state.selectSettingsNewChatModel(current),
                .reasoning => state.selectSettingsNewChatReasoning(current),
            }
            return true;
        },
        else => return false,
    };
    state.settings_controller.new_chat_menu_hover_index = next;
    if (kind == .model) ensureNewChatModelChoiceVisible(state, next);
    state.markDirty();
    return true;
}

fn ensureNewChatModelChoiceVisible(state: *runtime.AppState, option_index: usize) void {
    if (option_index < state.settings_controller.new_chat_model_menu_scroll) {
        state.settings_controller.new_chat_model_menu_scroll = option_index;
    } else {
        const visible_count = newChatModelMenuVisibleCount(state);
        if (option_index >= state.settings_controller.new_chat_model_menu_scroll + visible_count) {
            state.settings_controller.new_chat_model_menu_scroll = option_index - visible_count + 1;
        }
    }
    state.settings_controller.new_chat_model_menu_scroll = @min(state.settings_controller.new_chat_model_menu_scroll, newChatModelMenuMaxScroll(state));
}

const NOTES_FONT_SIZE = 12.0;
const NOTES_LINK_FONT_SIZE = 12.5;
const RELEASE_PAGE_LABEL = "Open release page";
const PACKAGE_UPDATE_HINT = "Update with your package manager. AUR packages need yay or paru.";
// Keeps a pathological release body from producing an unbounded card; the
// release-page link below the notes covers the tail.
const MAX_EXPANDED_NOTES_LINES: usize = 60;

const NotesLine = struct {
    text: []const u8,
    heading: bool,
};

/// Yields trimmed, non-empty release-note lines with markdown heading
/// markers stripped, capped at MAX_EXPANDED_NOTES_LINES.
const NotesLineIterator = struct {
    remaining: []const u8,
    emitted: usize = 0,

    fn init(notes: []const u8) NotesLineIterator {
        return .{ .remaining = std.mem.trim(u8, notes, &std.ascii.whitespace) };
    }

    fn next(self: *NotesLineIterator) ?NotesLine {
        while (self.remaining.len > 0 and self.emitted < MAX_EXPANDED_NOTES_LINES) {
            const line_end = std.mem.indexOfAny(u8, self.remaining, "\r\n") orelse self.remaining.len;
            var line = std.mem.trim(u8, self.remaining[0..line_end], &std.ascii.whitespace);
            self.remaining = std.mem.trimStart(u8, self.remaining[line_end..], &std.ascii.whitespace);
            const heading = line.len > 0 and line[0] == '#';
            line = std.mem.trimStart(u8, std.mem.trimStart(u8, line, "#"), " ");
            if (line.len == 0) continue;
            self.emitted += 1;
            return .{ .text = line, .heading = heading };
        }
        return null;
    }
};

fn notesLineHeight() f32 {
    return designUi(NOTES_FONT_SIZE * 1.25);
}

/// Estimated wrapped-row count for one note line. The width bias reserves
/// slack for ragged word-wrap edges so estimates err toward an extra row
/// instead of clipping the last one.
fn wrappedNotesRows(line: []const u8, usable_w: f32) f32 {
    const width = text_measure.textWidth(.ui, designUi(NOTES_FONT_SIZE), line);
    const rows = @ceil(width / @max(usable_w * 0.94, 1.0));
    return theme.clampf(rows, 1.0, 6.0);
}

/// Height of the release-notes block inside the Updates card: a two-line
/// preview when collapsed, the full (capped) note lines when expanded.
fn notesBlockHeight(state: *const runtime.AppState, usable_w: f32, m: Metrics) f32 {
    const collapsed_h = m.label_h * 2.0;
    if (!state.settings_controller.update_notes_expanded) return collapsed_h;
    const release = state.settings_controller.update.release orelse return collapsed_h;
    var iter = NotesLineIterator.init(release.notes);
    var total: f32 = 0.0;
    while (iter.next()) |line| total += wrappedNotesRows(line.text, usable_w) * notesLineHeight();
    return @max(total, collapsed_h);
}

fn notesToggleLabel(state: *const runtime.AppState) []const u8 {
    return if (state.settings_controller.update_notes_expanded) "Show less" else "Show full notes";
}

fn releaseNotesPreview(notes: []const u8) []const u8 {
    var remaining = std.mem.trim(u8, notes, &std.ascii.whitespace);
    while (remaining.len > 0) {
        const line_end = std.mem.indexOfAny(u8, remaining, "\r\n") orelse remaining.len;
        var line = std.mem.trim(u8, remaining[0..line_end], &std.ascii.whitespace);
        if (line.len > 0 and line[0] != '#') {
            if (std.mem.startsWith(u8, line, "* ") or std.mem.startsWith(u8, line, "- ")) line = line[2..];
            return line[0..@min(line.len, 220)];
        }
        remaining = std.mem.trimStart(u8, remaining[line_end..], &std.ascii.whitespace);
    }
    return "No release notes were provided.";
}

// Settings shell: soft scrim over the app, a layered drop shadow, then the
// rounded dialog with its tinted section-nav column on the left.
fn drawModalChrome(state: *runtime.AppState, width: f32, height: f32, layout: SettingsLayout) void {
    const modal = layout.modal;
    const radius = designUi(DIALOG_RADIUS);
    queueRoundedRect(state, .{ .x = 0.0, .y = 0.0, .w = width, .h = height }, paletteColor(theme.scrim(SHELL_SCRIM_ALPHA)), 0.0);
    // Approximates `0 24px 64px rgba(20,20,18,.22)` with a few soft layers.
    const ShadowLayer = struct { spread: f32, offset: f32, alpha: f32 };
    const layers = [_]ShadowLayer{
        .{ .spread = 28.0, .offset = 22.0, .alpha = 0.035 },
        .{ .spread = 16.0, .offset = 16.0, .alpha = 0.045 },
        .{ .spread = 8.0, .offset = 10.0, .alpha = 0.06 },
        .{ .spread = 2.0, .offset = 3.0, .alpha = 0.06 },
    };
    for (layers) |layer| {
        const spread = designUi(layer.spread);
        queueRoundedRect(state, .{
            .x = modal.x - spread,
            .y = modal.y - spread + designUi(layer.offset),
            .w = modal.w + spread * 2.0,
            .h = modal.h + spread * 2.0,
        }, paletteColor(theme.scrim(layer.alpha)), radius + spread);
    }
    queueRoundedRect(state, modal, paletteColor(sheetSurface()), radius);
    // Nav column: rounded on the dialog's left corners only, so paint a
    // rounded rect and square off its right edge with a plain strip.
    const nav = layout.nav_panel;
    queueRoundedRect(state, nav, paletteColor(navSurface()), radius);
    queueRoundedRect(state, .{ .x = nav.x + nav.w - radius, .y = nav.y, .w = radius, .h = nav.h }, paletteColor(navSurface()), 0.0);
    queueRoundedRect(state, .{ .x = nav.x + nav.w - 1.0, .y = nav.y, .w = 1.0, .h = nav.h }, paletteColor(cardEdge()), 0.0);
    queueBorder(state, modal, paletteColor(controlEdge()), radius, 1.0);
}

// Section header: current section title and a quiet close button. No rule
// underneath; the grouped cards start just below.
fn drawHeaderBar(state: *runtime.AppState, layout: SettingsLayout) void {
    const header = layout.header;
    const category = state.settings_controller.active_category;
    const title_size = designUi(HEADER_TITLE_FONT);
    // Same inset as the body so the title lines up with the cards.
    const pad_left = @min(designUi(HEADER_PAD_LEFT), header.w * 0.06);
    queueRoleText(state, .{
        .x = header.x + pad_left,
        .y = header.y + (header.h - title_size * 1.25) * 0.5,
        .w = @max(layout.close.x - header.x - pad_left - designUi(8.0), 0.0),
        .h = title_size * 1.25,
    }, category.label(), paletteColor(textPrimary()), title_size, .ui_medium, layout.modal);

    const hovered = state.settings_controller.close_hovered;
    if (hovered) queueRoundedRect(state, layout.close, paletteColor(navHoverSurface()), designUi(CONTROL_RADIUS));
    queueCenteredIcon(state, layout.close, LU_X, paletteColor(if (hovered) textPrimary() else textLabel()), designUi(CLOSE_ICON), layout.close);
}

// Left nav: "Settings" title, then one rounded row per section with a soft
// neutral fill for the selected and hovered rows.
fn drawCategoryNav(state: *runtime.AppState, layout: SettingsLayout) void {
    const title_size = designUi(NAV_TITLE_FONT);
    queueRoleText(state, .{
        .x = layout.nav_panel.x + designUi(NAV_PAD_X + NAV_ROW_PAD_X),
        .y = layout.nav_panel.y + designUi(NAV_PAD_TOP),
        .w = layout.nav_panel.w - designUi(NAV_PAD_X + NAV_ROW_PAD_X) * 2.0,
        .h = title_size * 1.25,
    }, "Settings", paletteColor(textPrimary()), title_size, .ui_medium, layout.nav_panel);

    const active = @intFromEnum(state.settings_controller.active_category);
    const font = designUi(NAV_FONT);
    for (settings_controller.Category.all, 0..) |category, index| {
        const rect = layout.nav[index];
        const selected = index == active;
        const hovered = state.settings_controller.hover_category == @as(u8, @intCast(index));
        if (selected) {
            queueRoundedRect(state, rect, paletteColor(navSelectedSurface()), designUi(NAV_ROW_RADIUS));
        } else if (hovered) {
            queueRoundedRect(state, rect, paletteColor(navHoverSurface()), designUi(NAV_ROW_RADIUS));
        }
        queueRoleText(state, .{
            .x = rect.x + designUi(NAV_ROW_PAD_X),
            .y = rect.y + (rect.h - font * 1.25) * 0.5,
            .w = rect.w - designUi(NAV_ROW_PAD_X) * 2.0,
            .h = font * 1.25,
        }, category.label(), paletteColor(if (selected or hovered) textPrimary() else textLabel()), font, if (selected) .ui_medium else .ui, layout.nav_panel);
    }
}

// Group captions, card surfaces, inset row hairlines and row labels for the
// active page. Controls are drawn on top by `render`.
fn drawPageChrome(state: *runtime.AppState, layout: SettingsLayout) void {
    const clip = layout.body_clip;
    const plan = &layout.page;
    const radius = designUi(CARD_RADIUS);
    const pad = designUi(ROW_PAD_X);
    for (plan.groups[0..plan.group_count]) |group| {
        if (group.caption.len > 0) {
            queueRoleText(state, .{
                .x = group.card.x,
                .y = group.caption_y,
                .w = group.card.w,
                .h = designUi(CAPTION_H),
            }, group.caption, paletteColor(textLabel()), designUi(CAPTION_FONT), .ui_medium, clip);
        }
        if (group.card.h <= 0.0) continue;
        queueRoundedRectClipped(state, group.card, paletteColor(cardSurface()), radius, clip);
        queueBorderClipped(state, group.card, paletteColor(cardEdge()), radius, 1.0, clip);
    }
    for (plan.rows[0..plan.row_count]) |row| {
        const rect = row.rect;
        if (row.divider) {
            queueRoundedRectClipped(state, .{ .x = rect.x + pad, .y = rect.y, .w = rect.w - pad * 2.0, .h = 1.0 }, paletteColor(rowHairline()), 0.0, clip);
        }
        if (row.style == .custom or row.label.len == 0) continue;
        const sub = row.style == .sub;
        const label_x = rect.x + pad + (if (sub) designUi(SUB_ROW_INDENT) else 0.0);
        const label_w = @max(rect.x + rect.w - pad - row.control_w - designUi(ROW_CONTROL_GAP) - label_x, 0.0);
        const label_size = designUi(if (sub) SUB_ROW_LABEL_FONT else ROW_LABEL_FONT);
        const label_h = label_size * 1.25;
        const desc_h = designUi(ROW_DESCRIPTION_FONT) * 1.25;
        const label_y = if (row.two_line)
            rect.y + (rect.h - label_h - desc_h) * 0.5
        else
            rect.y + (rect.h - label_h) * 0.5;
        queueText(state, .{ .x = label_x, .y = label_y, .w = label_w, .h = label_h }, row.label, paletteColor(if (sub) textLabel() else textPrimary()), label_size, clip);
        if (row.description.len > 0) drawRowDescription(state, rect, row.control_w, row.description, clip);
    }
}

/// Second line under a two-line row's label (static or live status copy).
fn drawRowDescription(state: *runtime.AppState, row: palette.Rect, control_w: f32, text: []const u8, clip: palette.Rect) void {
    const pad = designUi(ROW_PAD_X);
    const label_h = designUi(ROW_LABEL_FONT) * 1.25;
    const desc_size = designUi(ROW_DESCRIPTION_FONT);
    const desc_h = desc_size * 1.25;
    queueText(state, .{
        .x = row.x + pad,
        .y = row.y + (row.h - label_h - desc_h) * 0.5 + label_h,
        .w = @max(row.w - pad * 2.0 - control_w - designUi(ROW_CONTROL_GAP), 0.0),
        .h = desc_h,
    }, text, paletteColor(textLabel()), desc_size, clip);
}

const PROVIDERS_RECHECK_LABEL = "Check again";
const PROVIDERS_UPDATE_HINT = "Update uses the tool that installed that copy, such as mise.";
const PROVIDER_BADGE_FONT: f32 = 12.0;

fn providerBadgeColumnWidth() f32 {
    const badge_font = designUi(PROVIDER_BADGE_FONT);
    var badge_col_w: f32 = 0.0;
    for ([_]runtime.ProviderReadiness{ .checking, .missing, .signed_out, .ready, .unavailable }) |value| {
        badge_col_w = @max(badge_col_w, text_measure.textWidth(.ui, badge_font, providerReadinessBadge(value)));
    }
    return badge_col_w + designUi(4.0);
}

/// Right edge reserved for the enable switch and its gap to the badge.
fn providerSwitchReserve() f32 {
    return designUi(ROW_PAD_X + SWITCH_W + 18.0);
}

fn providerDotSize() f32 {
    return designUi(7.0);
}

fn providerActionWidth() f32 {
    return @max(
        @max(@max(buttonWidth("Install"), buttonWidth("Update")), buttonWidth("Sign in")),
        @max(buttonWidth("Latest"), buttonWidth("Checking…")),
    );
}

const ProviderAction = enum { install, sign_in, update, latest, pending, none };

fn providerAction(readiness: runtime.ProviderReadiness, release: runtime.ProviderRelease) ProviderAction {
    if (readiness == .missing) return .install;
    // Installed but not authenticated (or auth could not be confirmed): sign-in
    // is the step that unblocks chats, so it takes the slot over Update.
    if (readiness == .signed_out or readiness == .unavailable) return .sign_in;
    return switch (release) {
        .available => .update,
        .current => .latest,
        .unknown => if (readiness == .checking) .pending else .none,
    };
}

fn providerReadinessColor(readiness: runtime.ProviderReadiness) [4]f32 {
    return switch (readiness) {
        .ready => theme.success(),
        .signed_out => theme.warning(),
        .missing, .unavailable => theme.danger(),
        .checking => theme.COLOR_TEXT_SUBTLE,
    };
}

fn providerReadinessBadge(readiness: runtime.ProviderReadiness) []const u8 {
    return switch (readiness) {
        .checking => "Checking…",
        .missing => "Not installed",
        .signed_out => "Signed out",
        .ready => "Authenticated",
        .unavailable => "Unavailable",
    };
}

fn drawProvidersCard(state: *runtime.AppState, layout: SettingsLayout, m: Metrics) void {
    // Providers page: one card row per provider with logo, name,
    // daemon-reported CLI version, installer button, auth badge and switch.
    const clip = layout.body_clip;
    const snapshot = state.providerReadinessSnapshot();
    const badge_font = designUi(PROVIDER_BADGE_FONT);
    const name_font = designUi(ROW_LABEL_FONT);
    const version_font = designUi(ROW_DESCRIPTION_FONT - 0.5);
    const dot = providerDotSize();
    const inset = designUi(ROW_PAD_X);
    const logo = designUi(20.0);
    const logo_gap = designUi(12.0);
    const badge_col_w = providerBadgeColumnWidth();
    for (layout.provider_rows, layout.provider_updates, 0..) |row, update, index| {
        const enabled = state.settingsProviderEnabled(index);
        const provider = settings_controller.settingsProviderForRow(index);
        const readiness = snapshot.forProvider(provider);
        const version = snapshot.versionForProvider(provider);
        const action = providerAction(readiness, snapshot.releaseForProvider(provider));
        drawSwitchRow(state, row, enabled, isControlHovered(state, providerRowControl(index)), clip);

        const logo_rect: palette.Rect = .{ .x = row.x + inset, .y = row.y + (row.h - logo) * 0.5, .w = logo, .h = logo };
        const label = state.settingsNewChatProviderLabel(index);
        const texture = state.providerLogoTexture(provider);
        if (texture != null and texture.?.valid and texture.?.texture_id != 0) {
            const cached = texture.?;
            const r = utils.snapImageRectToPixels(utils.imageRectContain(cached.width, cached.height, logo_rect.x, logo_rect.y, logo_rect.w, logo_rect.h));
            const alpha: f32 = (if (enabled) @as(f32, 1.0) else 0.45) * current_fade_alpha;
            const tint = theme.providerLogoTint(@tagName(provider));
            state.palette_overlay_batch.image(state.allocator, .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, palette.TextureId.init(cached.texture_id), .{ .x = 0.0, .y = 0.0, .w = 1.0, .h = 1.0 }, .{ .r = tint[0], .g = tint[1], .b = tint[2], .a = tint[3] * alpha }, clip) catch |err| {
                log.warn("failed to queue provider logo: {s}", .{@errorName(err)});
            };
        } else {
            queueCenteredText(state, logo_rect, label[0..1], paletteColor(textLabel()), designUi(11.0), clip);
        }

        const badge_x = row.x + row.w - providerSwitchReserve() - badge_col_w;
        const dot_x = badge_x - dot - designUi(6.0);
        const name_x = logo_rect.x + logo + logo_gap;
        const name_h = name_font * 1.25;
        const version_h = version_font * 1.25;
        const name_y = row.y + (row.h - name_h - version_h) * 0.5;
        queueText(state, .{
            .x = name_x,
            .y = name_y,
            .w = @max(update.x - designUi(8.0) - name_x, 0.0),
            .h = name_h,
        }, label, paletteColor(if (enabled) textPrimary() else textLabel()), name_font, clip);
        const version_label = if (version.len > 0)
            provider_cli_version.shortVersion(version)
        else if (readiness == .checking)
            "Checking…"
        else
            "—";
        queueText(state, .{
            .x = name_x,
            .y = name_y + name_h,
            .w = @max(update.x - designUi(8.0) - name_x, 0.0),
            .h = version_h,
        }, version_label, paletteColor(textHint()), version_font, clip);

        const color = if (enabled) providerReadinessColor(readiness) else theme.COLOR_TEXT_SUBTLE;
        queueRoundedRectClipped(state, .{ .x = dot_x, .y = row.y + (row.h - dot) * 0.5, .w = dot, .h = dot }, paletteColor(color), dot * 0.5, clip);
        queueText(state, .{
            .x = badge_x,
            .y = row.y + (row.h - badge_font * 1.25) * 0.5,
            .w = badge_col_w,
            .h = badge_font * 1.25,
        }, providerReadinessBadge(readiness), paletteColor(if (enabled) textLabel() else textHint()), badge_font, clip);
        switch (action) {
            .install => drawActionButton(state, update, "Install", .secondary, isControlHovered(state, providerUpdateControl(index)), clip),
            .update => drawActionButton(state, update, "Update", .secondary, isControlHovered(state, providerUpdateControl(index)), clip),
            .sign_in => drawActionButton(state, update, "Sign in", .primary, isControlHovered(state, providerUpdateControl(index)), clip),
            .pending => drawActionButton(state, update, "Checking…", .disabled, false, clip),
            .latest => queueCenteredText(state, update, "Latest", paletteColor(textHint()), badge_font, clip),
            .none => {},
        }
    }
    const content_x = layout.provider_rows[0].x;
    const content_w = layout.provider_rows[0].w;
    queueText(state, .{
        .x = content_x,
        .y = layout.providers_hint_y,
        .w = content_w,
        .h = m.label_h,
    }, "Disabled providers are hidden from the model picker and new chats.", paletteColor(textHint()), designUi(CAPTION_FONT), clip);
    queueText(state, .{
        .x = content_x,
        .y = layout.providers_update_hint_y,
        .w = content_w,
        .h = m.label_h,
    }, PROVIDERS_UPDATE_HINT, paletteColor(textHint()), designUi(CAPTION_FONT), clip);
    drawActionButton(state, layout.providers_recheck, PROVIDERS_RECHECK_LABEL, .secondary, isControlHovered(state, .providers_recheck), clip);
}

// ---------------------------------------------------------------------------
// Runtimes & connections card
// ---------------------------------------------------------------------------

/// Local plus every configured profile.
const MAX_RUNTIME_ROWS: usize = 65;
/// Upper bound of `planRuntimeRowButtons` for one profile row: primary
/// recovery, Disconnect, Show server setup, Forget token/device, Edit,
/// Confirm remove + Keep, Copy diagnostics, workspace default. `pushButton`
/// asserts rather than silently dropping a planned action.
const MAX_ROW_BUTTONS: usize = 9;
/// Bounded detail block: repository rows + provider rows + status lines.
const MAX_DETAIL_LINES: usize = 40;
const DETAIL_LINE_BYTES: usize = 240;
const RowAction = runtime_connections.RowAction;

const RuntimeRowPlan = struct {
    /// Clickable header (title, badge, description) that expands the row.
    header: palette.Rect,
    buttons: [MAX_ROW_BUTTONS]palette.Rect,
    button_actions: [MAX_ROW_BUTTONS]RowAction,
    button_labels: [MAX_ROW_BUTTONS][]const u8,
    button_styles: [MAX_ROW_BUTTONS]ButtonStyle,
    button_count: usize,
    detail_y: f32,
    detail_line_count: usize,
    expanded: bool,
    bottom: f32,
};

const RuntimeCardPlan = struct {
    rows: [MAX_RUNTIME_ROWS]RuntimeRowPlan = undefined,
    row_count: usize = 0,
    caption_y: f32 = OFFSCREEN_Y,
    /// Card holding the connection rows, below the caption.
    card: palette.Rect = OFFSCREEN,
    add_button: palette.Rect = OFFSCREEN,
    notice_y: f32 = OFFSCREEN_Y,
    explainer_y: f32 = OFFSCREEN_Y,
    hint_y: f32 = OFFSCREEN_Y,
    height: f32 = 0.0,
};

const DetailLine = struct {
    text: []const u8,
    tone: enum { normal, muted, warning, good },
};

const DetailBuffer = struct {
    lines: [MAX_DETAIL_LINES]DetailLine = undefined,
    scratch: [MAX_DETAIL_LINES][DETAIL_LINE_BYTES]u8 = undefined,
    count: usize = 0,

    fn push(self: *DetailBuffer, tone: @FieldType(DetailLine, "tone"), comptime fmt: []const u8, args: anytype) void {
        if (self.count >= MAX_DETAIL_LINES) return;
        const text = std.fmt.bufPrint(&self.scratch[self.count], fmt, args) catch blk: {
            // Truncate rather than drop: the row must still show that a
            // value exists even when it does not fit the line budget.
            break :blk self.scratch[self.count][0..];
        };
        self.lines[self.count] = .{ .text = text, .tone = tone };
        self.count += 1;
    }
};

fn runtimeRowProfileId(state: *const runtime.AppState, row: usize) ?[]const u8 {
    if (row == 0) return null;
    const index = row - 1;
    if (index >= state.runtime_picker_profiles.items.len) return null;
    return state.runtime_picker_profiles.items[index].profile_id;
}

fn runtimeRowIsWorkspaceDefault(state: *const runtime.AppState, profile_id: ?[]const u8) bool {
    const workspace_id = state.currentWorkspaceIdForRuntimeDefault() orelse return profile_id == null;
    const default_id = state.workspaceRuntimeDefaultProfile(workspace_id);
    if (profile_id) |value| return std.mem.eql(u8, default_id, value);
    return std.mem.eql(u8, default_id, "local");
}

fn buttonWidth(label: []const u8) f32 {
    // Measured label plus a fixed horizontal pad so short verbs keep a
    // comfortable click target and long ones never clip.
    return text_measure.textWidth(.ui, designUi(CONTROL_FONT), label) + designUi(BUTTON_PAD_X) * 2.0;
}

/// Lays out one row's buttons left-to-right, wrapping to a new line when the
/// content width is exhausted. Returns the y after the last line.
fn packRowButtons(plan: *RuntimeRowPlan, x: f32, y_start: f32, w: f32, m: Metrics) f32 {
    var y = y_start;
    var cursor_x = x;
    var placed_any = false;
    for (0..plan.button_count) |index| {
        const bw = @min(buttonWidth(plan.button_labels[index]), w);
        if (placed_any and cursor_x + bw > x + w) {
            cursor_x = x;
            y += m.row_h + m.inner_gap;
        }
        plan.buttons[index] = .{ .x = cursor_x, .y = y, .w = bw, .h = m.row_h };
        cursor_x += bw + m.inner_gap;
        placed_any = true;
    }
    return if (plan.button_count == 0) y_start else y + m.row_h;
}

fn pushButton(plan: *RuntimeRowPlan, action: RowAction, label: []const u8, style: ButtonStyle) void {
    std.debug.assert(plan.button_count < MAX_ROW_BUTTONS);
    plan.button_actions[plan.button_count] = action;
    plan.button_labels[plan.button_count] = label;
    plan.button_styles[plan.button_count] = style;
    plan.button_count += 1;
}

fn planRuntimeRowButtons(state: *const runtime.AppState, plan: *RuntimeRowPlan, profile_id: ?[]const u8) void {
    plan.button_count = 0;
    const is_default = runtimeRowIsWorkspaceDefault(state, profile_id);
    const id = profile_id orelse {
        pushButton(plan, .set_workspace_default, if (is_default) "Workspace default" else "Use as workspace default", if (is_default) .disabled else .secondary);
        return;
    };
    const snapshot = state.runtimeProfileSnapshot(id);
    const status = state.runtimeProfileStatus(id);
    // Primary action follows the shared recovery mapping so the picker,
    // wizard, and composer banner agree. Re-pair is never offered unless the
    // status is a credential/revocation state.
    const recovery = runtime.runtimeStatusRecovery(status);
    const primary_label = runtime.runtimeRecoveryLabel(recovery, status);
    switch (recovery) {
        .retry => pushButton(plan, if (status == .offline or status == .paired_offline) .connect else .retry, primary_label, .primary),
        .reconnect => pushButton(plan, .reconnect, primary_label, .primary),
        .credential => pushButton(plan, .connect, primary_label, .primary),
        .repair => pushButton(plan, .pair_device, primary_label, .primary),
        .review_trust => pushButton(plan, .review_trust, primary_label, .primary),
        .edit_endpoint => pushButton(plan, .edit, primary_label, .primary),
        .choose_runtime => pushButton(plan, .choose_runtime, primary_label, .primary),
        .server_setup => pushButton(plan, .show_server_setup, primary_label, .primary),
        .none => switch (status) {
            .connecting, .handshaking, .trust_required, .ready, .reconnecting => pushButton(plan, .disable, "Disconnect", .secondary),
            else => {},
        },
    }
    // Readiness failures happen on an authenticated open session. Keep an
    // explicit Disconnect alongside the corrective action and fresh-session
    // retry so users are never trapped in a connected-but-blocked state.
    if (snapshot) |live| {
        if (live.phase == .ready and recovery != .none) pushButton(plan, .disable, "Disconnect", .secondary);
        // Reconnecting rows now surface "Retry now" as the primary; keep the
        // explicit way out of the retry loop.
        if (live.phase == .reconnecting) pushButton(plan, .disable, "Disconnect", .secondary);
    }
    if (recovery != .server_setup and runtime.runtimeStatusOffersServerSetup(status)) {
        pushButton(plan, .show_server_setup, "Show server setup", .secondary);
    }
    if (snapshot) |live| switch (live.access) {
        .admin_token => if (live.credential_held) pushButton(plan, .forget_token, "Forget token", .secondary),
        .paired_device => if (live.device_id != null or live.credential_held) {
            pushButton(plan, .forget_device, "Forget device", .secondary);
        },
        .connect => {},
    };
    pushButton(plan, .edit, "Edit", .secondary);
    if (state.runtime_connections.isRemoveConfirming(id)) {
        pushButton(plan, .remove_confirm, "Confirm remove", .primary);
        pushButton(plan, .remove_cancel, "Keep", .secondary);
    } else {
        pushButton(plan, .remove, "Remove", .secondary);
    }
    pushButton(plan, .copy_diagnostics, "Copy diagnostics", .secondary);
    pushButton(plan, .set_workspace_default, if (is_default) "Workspace default" else "Use as default", if (is_default) .disabled else .secondary);
}

fn localProviderReadinessLabel(readiness: runtime.ProviderReadiness) []const u8 {
    return switch (readiness) {
        .checking => "checking",
        .missing => "not installed",
        .signed_out => "signed out",
        .ready => "ready",
        .unavailable => "unavailable",
    };
}

/// Builds the expanded detail block. Local reads the workspace folder and the
/// desktop's own provider probe; remote rows read only daemon-reported data.
fn collectRuntimeDetailLines(state: *const runtime.AppState, profile_id: ?[]const u8, out: *DetailBuffer) void {
    out.count = 0;
    const rc = &state.runtime_connections;
    if (profile_id == null) {
        if (state.project_controller.selected_index < state.project_controller.projects.items.len) {
            const project = state.project_controller.projects.items[state.project_controller.selected_index];
            out.push(.normal, "Repository  {s}", .{project.path});
        } else {
            out.push(.muted, "Repository  no workspace selected", .{});
        }
        out.push(.muted, "Providers on this machine", .{});
        const snapshot = state.provider_controller.readiness.snapshot;
        inline for (.{ .codex, .claude, .cursor, .opencode, .pi, .fx, .grok }) |provider| {
            const readiness = snapshot.forProvider(provider);
            out.push(if (readiness == .ready) .good else if (readiness == .checking) .muted else .warning, "{s} · {s}", .{ runtime.providerLabel(provider), localProviderReadinessLabel(readiness) });
        }
        return;
    }
    const id = profile_id.?;
    pushRuntimeAccessDetailLines(state, id, out);
    const tracking = rc.readiness_profile_id != null and std.mem.eql(u8, rc.readiness_profile_id.?, id);
    const manifest_state = if (tracking) rc.manifest_state else .idle;
    const providers_state = if (tracking) rc.providers_state else .idle;
    switch (manifest_state) {
        .idle, .loading => out.push(.muted, "Repository bindings · checking…", .{}),
        .not_ready => out.push(.muted, "Repository bindings · connect and verify this runtime first", .{}),
        .unsupported => out.push(.warning, "Repository bindings · this daemon does not advertise repository manifests", .{}),
        .failed => out.push(.warning, "Repository bindings · could not be read from the daemon", .{}),
        .loaded => {
            if (rc.repositories.items.len == 0) {
                out.push(.warning, "Repository bindings · none registered for this workspace on the daemon", .{});
            } else {
                out.push(.muted, "Repository bindings on this runtime", .{});
            }
            for (rc.repositories.items) |repo| {
                if (repo.root_path) |root| {
                    if (std.mem.eql(u8, repo.availability, "available")) {
                        out.push(.good, "{s}{s} · {s}", .{ repo.label, if (repo.is_default) " (default)" else "", root });
                    } else {
                        out.push(.warning, "{s}{s} · {s} · {s}", .{ repo.label, if (repo.is_default) " (default)" else "", root, repo.availability });
                    }
                } else {
                    out.push(.warning, "{s}{s} · not bound on this runtime — bind or clone it on the host (no remote clone from the desktop yet)", .{ repo.label, if (repo.is_default) " (default)" else "" });
                }
            }
            if (rc.repositories_truncated > 0) out.push(.muted, "+{d} more repositories", .{rc.repositories_truncated});
        },
    }
    switch (providers_state) {
        .idle, .loading => out.push(.muted, "Providers · checking…", .{}),
        .not_ready => out.push(.muted, "Providers · available after the runtime is verified", .{}),
        .unsupported => out.push(.warning, "Providers · not reported by this daemon", .{}),
        .failed => out.push(.warning, "Providers · inventory could not be read", .{}),
        .loaded => {
            out.push(.muted, "Providers on this runtime", .{});
            var needs_remote_setup = false;
            for (rc.providers.items) |row| {
                const ready = std.mem.eql(u8, row.state, "ready");
                out.push(if (ready) .good else .warning, "{s} · {s} · {s}{s}{s}{s}{s}", .{
                    row.label,
                    row.state,
                    row.authentication,
                    if (row.native_chat) " · chat" else "",
                    if (row.terminal_tui) " · terminal" else "",
                    if (row.mcp) " · mcp" else "",
                    if (row.lifecycle) " · hooks" else "",
                });
                if (!ready) {
                    if (row.remediation_command) |command| {
                        out.push(.muted, "    {s}: {s}", .{ row.remediation_label orelse "Setup", command });
                    } else if (row.remediation_label) |label| {
                        out.push(.muted, "    {s}", .{label});
                    }
                    needs_remote_setup = true;
                }
            }
            if (rc.providers_truncated > 0) out.push(.muted, "+{d} more providers", .{rc.providers_truncated});
            if (needs_remote_setup) out.push(.muted, "Run setup commands on the runtime host; the desktop has no remote shell and cannot sign in for you.", .{});
        },
    }
}

/// Method-specific, secret-free access details for Pair and Connect. Never
/// prints a credential, token, or expiry secret.
fn pushRuntimeAccessDetailLines(state: *const runtime.AppState, profile_id: []const u8, out: *DetailBuffer) void {
    const service = state.runtime_service orelse return;
    const snapshot = service.snapshot(profile_id) orelse return;
    const configured = service.runtime_manager.profileConst(profile_id) orelse return;
    switch (configured.access) {
        .admin_token => out.push(.muted, "Access · administrator token, entered each session and kept in memory only", .{}),
        .paired_device => |device| {
            if (device.device_id) |device_id| {
                out.push(.good, "Access · paired device {s}", .{device_id});
            } else {
                out.push(.warning, "Access · not paired yet — redeem a one-time grant from the runtime host", .{});
            }
            const backend = service.credentialBackend();
            if (backend.durable()) {
                out.push(.muted, "Device credential · stored by reference in the OS credential store ({s})", .{@tagName(backend)});
            } else {
                out.push(.warning, "Device credential · memory only on this platform; pair again after relaunch", .{});
            }
            switch (snapshot.pairing_state) {
                .none => {},
                .exchanging => out.push(.muted, "Pairing · exchanging the one-time grant with the runtime", .{}),
                .awaiting_confirmation => out.push(.warning, "Pairing · runtime identity awaits your confirmation in the wizard", .{}),
            }
            if (snapshot.access_token_expires_at_ms) |expires| {
                const now = state.runtimeNowMs();
                const remaining_s: u64 = if (expires > 0 and @as(u64, @intCast(expires)) > now) (@as(u64, @intCast(expires)) - now) / 1000 else 0;
                out.push(.muted, "Access token · renews via /auth/access-token, {d}s left", .{remaining_s});
            }
        },
        .connect => |link| {
            out.push(.muted, "Control plane · {s}", .{link.control_plane_url});
            if (link.link_id) |link_id| out.push(.muted, "Link · {s}", .{link_id});
            switch (configured.transport) {
                .connect => |endpoint| {
                    if (endpoint.https_url) |https| out.push(.muted, "Endpoint · {s}", .{https});
                    if (endpoint.wss_url) |wss| out.push(.muted, "WebSocket · {s}", .{wss});
                    if (endpoint.spki_sha256) |spki| out.push(.muted, "TLS SPKI sha256 · {s}", .{spki});
                },
                else => {},
            }
            if (configured.expected_runtime_id) |runtime_id| out.push(.muted, "Runtime · {s} / {s}", .{ runtime_id, configured.expected_instance_id orelse "?" });
            if (link.device_id) |device_id| out.push(.muted, "Runtime-local device · {s}", .{device_id});
            if (link.credential_ref != null and !snapshot.device_credential_held) {
                out.push(.warning, "Runtime-local credential is not loaded; sign in to Connect and bootstrap again", .{});
            }
        },
    }
}

fn runtimeDetailLineCount(state: *const runtime.AppState, profile_id: ?[]const u8) usize {
    var buffer: DetailBuffer = .{};
    collectRuntimeDetailLines(state, profile_id, &buffer);
    return buffer.count;
}

/// Connection row headers are inset from the card edge so their hover fill
/// reads as a soft pill; header text still lines up with `ROW_PAD_X`.
const RUNTIME_ROW_INSET: f32 = 6.0;
const RUNTIME_CARD_PAD_Y: f32 = 6.0;
/// Space between connection rows; the separating hairline sits mid-gap.
const RUNTIME_ROW_GAP: f32 = 14.0;

fn planRuntimeCard(state: *const runtime.AppState, x: f32, y: f32, w: f32, m: Metrics) RuntimeCardPlan {
    var plan: RuntimeCardPlan = .{};
    plan.caption_y = y;
    const card_y = y + designUi(CAPTION_H + CAPTION_GAP);
    const row_inset = designUi(RUNTIME_ROW_INSET);
    const inner_x = x + m.card_pad;
    const inner_w = w - m.card_pad * 2.0;
    const row_gap = designUi(RUNTIME_ROW_GAP);
    var cursor_y = card_y + designUi(RUNTIME_CARD_PAD_Y);
    var last_bottom = cursor_y;
    const total_rows = @min(1 + state.runtime_picker_profiles.items.len, MAX_RUNTIME_ROWS);
    for (0..total_rows) |row| {
        const profile_id = runtimeRowProfileId(state, row);
        var row_plan: RuntimeRowPlan = undefined;
        row_plan.expanded = state.runtime_connections.isExpanded(profile_id);
        // Title line plus description line.
        row_plan.header = .{ .x = x + row_inset, .y = cursor_y, .w = w - row_inset * 2.0, .h = m.row_h + m.label_h };
        var next_y = row_plan.header.y + row_plan.header.h + m.inner_gap;
        planRuntimeRowButtons(state, &row_plan, profile_id);
        next_y = packRowButtons(&row_plan, inner_x, next_y, inner_w, m);
        row_plan.detail_y = next_y + m.inner_gap;
        row_plan.detail_line_count = if (row_plan.expanded) runtimeDetailLineCount(state, profile_id) else 0;
        if (row_plan.expanded) next_y = row_plan.detail_y + @as(f32, @floatFromInt(row_plan.detail_line_count)) * m.label_h;
        row_plan.bottom = next_y + m.inner_gap;
        plan.rows[plan.row_count] = row_plan;
        plan.row_count += 1;
        last_bottom = row_plan.bottom;
        cursor_y = row_plan.bottom + row_gap;
    }
    plan.card = .{ .x = x, .y = card_y, .w = w, .h = last_bottom + designUi(RUNTIME_CARD_PAD_Y) - card_y };
    plan.add_button = .{ .x = x, .y = plan.card.y + plan.card.h + m.row_gap, .w = @min(buttonWidth("Add connection…"), w), .h = m.row_h };
    plan.notice_y = plan.add_button.y + m.row_h + m.inner_gap;
    plan.explainer_y = plan.notice_y + m.label_h;
    plan.hint_y = plan.explainer_y + m.label_h;
    plan.height = (plan.hint_y + m.label_h) - y;
    return plan;
}

fn registerRuntimeCardHits(state: *runtime.AppState, layout: SettingsLayout, queue_hit: *const fn (*runtime.AppState, palette.Rect, runtime.PaletteModalAction, usize) void) void {
    const plan = &layout.runtimes;
    for (0..plan.row_count) |row| {
        const row_plan = &plan.rows[row];
        if (intersectRect(row_plan.header, layout.body_clip)) |visible| {
            queue_hit(state, visible, .settings_runtime_action, runtime_connections.encodeRowAction(row, .expand));
        }
        for (0..row_plan.button_count) |index| {
            if (row_plan.button_styles[index] == .disabled) continue;
            if (intersectRect(row_plan.buttons[index], layout.body_clip)) |visible| {
                queue_hit(state, visible, .settings_runtime_action, runtime_connections.encodeRowAction(row, row_plan.button_actions[index]));
            }
        }
    }
    if (intersectRect(plan.add_button, layout.body_clip)) |visible| {
        queue_hit(state, visible, .settings_runtime_action, runtime_connections.encodeRowAction(0, .add_connection));
    }
}

fn isRuntimeActionHovered(state: *const runtime.AppState, index: usize) bool {
    const hovered = state.settings_controller.hover_runtime_action orelse return false;
    return hovered == index;
}

fn runtimeStatusColor(status: runtime.RuntimePickerStatus) [4]f32 {
    return runtime.runtimeStatusTone(status).color();
}

// Runtimes & connections: Local plus saved runtimes with live state, per-row
// actions, and readiness details for the expanded row.
fn drawRuntimeCard(state: *runtime.AppState, layout: SettingsLayout) void {
    const m = metrics();
    const plan = &layout.runtimes;
    const card = plan.card;
    const clip = layout.body_clip;
    queueRoleText(state, .{ .x = card.x, .y = plan.caption_y, .w = card.w, .h = designUi(CAPTION_H) }, "Runtimes & connections", paletteColor(textLabel()), designUi(CAPTION_FONT), .ui_medium, clip);
    queueRoundedRectClipped(state, card, paletteColor(cardSurface()), designUi(CARD_RADIUS), clip);
    queueBorderClipped(state, card, paletteColor(cardEdge()), designUi(CARD_RADIUS), 1.0, clip);

    for (0..plan.row_count) |row| {
        const row_plan = &plan.rows[row];
        const profile_id = runtimeRowProfileId(state, row);
        const header = row_plan.header;
        const header_hovered = isRuntimeActionHovered(state, runtime_connections.encodeRowAction(row, .expand));
        if (row > 0) {
            const line_y = header.y - designUi(RUNTIME_ROW_GAP) * 0.5;
            queueRoundedRectClipped(state, .{ .x = card.x + m.card_pad, .y = line_y, .w = card.w - m.card_pad * 2.0, .h = 1.0 }, paletteColor(rowHairline()), 0.0, clip);
        }
        if (row_plan.expanded) {
            queueRoundedRectClipped(state, .{ .x = header.x, .y = header.y, .w = header.w, .h = row_plan.bottom - header.y }, paletteColor(controlHoverSurface()), designUi(CONTROL_RADIUS), clip);
        } else if (header_hovered) {
            queueRoundedRectClipped(state, header, paletteColor(controlHoverSurface()), designUi(CONTROL_RADIUS), clip);
        }

        var title: []const u8 = "Local";
        var description: []const u8 = "Runs on this machine";
        var badge: []const u8 = "";
        var badge_color = theme.COLOR_TEXT_MUTED;
        var description_buf: [320]u8 = undefined;
        if (profile_id) |id| {
            const status = state.runtimeProfileStatus(id);
            badge = runtime.runtimePickerStatusBadge(status);
            badge_color = runtimeStatusColor(status);
            if (state.runtimeProfileSnapshot(id)) |snapshot| {
                title = snapshot.label;
                if (state.runtime_service.?.runtime_manager.profileConst(id)) |configured| {
                    switch (configured.transport) {
                        .ssh_tunnel => |ssh| {
                            description = std.fmt.bufPrint(&description_buf, "{s} · ssh {s}{s}{s}:{d} → gateway {d}", .{
                                runtime.runtimePickerStatusDescription(status),
                                ssh.user orelse "",
                                if (ssh.user != null) "@" else "",
                                ssh.host,
                                ssh.port,
                                ssh.remote_gateway_port,
                            }) catch runtime.runtimePickerStatusDescription(status);
                        },
                        .local_socket => description = runtime.runtimePickerStatusDescription(status),
                        .direct_https => |endpoint| {
                            description = std.fmt.bufPrint(&description_buf, "{s} · Direct / Tailnet {s}", .{
                                runtime.runtimePickerStatusDescription(status),
                                endpoint.https_url orelse "(missing endpoint)",
                            }) catch runtime.runtimePickerStatusDescription(status);
                        },
                        .connect => |endpoint| {
                            description = std.fmt.bufPrint(&description_buf, "{s} · Connect {s}", .{
                                runtime.runtimePickerStatusDescription(status),
                                endpoint.https_url orelse "(no runtime selected)",
                            }) catch runtime.runtimePickerStatusDescription(status);
                        },
                    }
                } else {
                    description = runtime.runtimePickerStatusDescription(status);
                }
            } else {
                title = "Unavailable runtime";
                description = runtime.runtimePickerStatusDescription(.unavailable);
            }
        }
        const is_default = runtimeRowIsWorkspaceDefault(state, profile_id);
        const pad_x = designUi(10.0);
        const badge_w = if (badge.len > 0) text_measure.textWidth(.ui, designUi(11.5), badge) + designUi(16.0) else 0.0;
        queueText(state, .{
            .x = header.x + pad_x,
            .y = header.y + (m.row_h - designUi(16.0)) * 0.5,
            .w = header.w - pad_x * 2.0 - badge_w - m.inner_gap,
            .h = designUi(16.0),
        }, title, paletteColor(theme.COLOR_WHITE), designUi(14.0), clip);
        if (badge.len > 0) {
            const badge_rect: palette.Rect = .{
                .x = header.x + header.w - pad_x - badge_w,
                .y = header.y + (m.row_h - designUi(22.0)) * 0.5,
                .w = badge_w,
                .h = designUi(22.0),
            };
            queueRoundedRectClipped(state, badge_rect, paletteColor(theme.withAlpha(badge_color, 40)), designUi(CONTROL_RADIUS), clip);
            queueCenteredText(state, badge_rect, badge, paletteColor(badge_color), designUi(11.5), clip);
        }
        var desc_buf: [360]u8 = undefined;
        const description_text = if (is_default)
            std.fmt.bufPrint(&desc_buf, "{s} · workspace default", .{description}) catch description
        else
            description;
        queueText(state, .{
            .x = header.x + pad_x,
            .y = header.y + m.row_h,
            .w = header.w - pad_x * 2.0,
            .h = m.label_h,
        }, description_text, paletteColor(textHint()), designUi(12.0), clip);

        for (0..row_plan.button_count) |index| {
            const action_index = runtime_connections.encodeRowAction(row, row_plan.button_actions[index]);
            drawActionButton(state, row_plan.buttons[index], row_plan.button_labels[index], row_plan.button_styles[index], isRuntimeActionHovered(state, action_index), clip);
        }

        if (row_plan.expanded) {
            var buffer: DetailBuffer = .{};
            collectRuntimeDetailLines(state, profile_id, &buffer);
            for (buffer.lines[0..buffer.count], 0..) |line, line_index| {
                const color = switch (line.tone) {
                    .normal => theme.COLOR_WHITE,
                    .muted => textHint(),
                    .warning => theme.warning(),
                    .good => theme.success(),
                };
                queueText(state, .{
                    .x = header.x + pad_x,
                    .y = row_plan.detail_y + @as(f32, @floatFromInt(line_index)) * m.label_h,
                    .w = header.w - pad_x * 2.0,
                    .h = m.label_h,
                }, line.text, paletteColor(color), designUi(12.0), clip);
            }
        }
    }

    drawActionButton(state, plan.add_button, "Add connection…", .secondary, isRuntimeActionHovered(state, runtime_connections.encodeRowAction(0, .add_connection)), clip);
    const notice = state.runtime_connections.cardNotice();
    if (notice.len > 0) {
        queueText(state, .{ .x = card.x, .y = plan.notice_y, .w = card.w, .h = m.label_h }, notice, paletteColor(theme.COLOR_YELLOW), designUi(CAPTION_FONT), clip);
    }
    queueText(state, .{ .x = card.x, .y = plan.explainer_y, .w = card.w, .h = m.label_h }, "Where chats run. Select a row for repository and provider readiness · Local, SSH, Direct / Tailnet, or Connect", paletteColor(textHint()), designUi(CAPTION_FONT), clip);
    queueText(state, .{ .x = card.x, .y = plan.hint_y, .w = card.w, .h = m.label_h }, "Tokens stay in memory only · started chats keep their pinned runtime · defaults apply to new chats in the selected workspace", paletteColor(textHint()), designUi(CAPTION_FONT), clip);
}

// Dropdown button: value on the left, chevron on the right, 1px edge.
fn drawDropdown(
    state: *runtime.AppState,
    rect: palette.Rect,
    label: []const u8,
    control: Control,
    open: bool,
    clip: palette.Rect,
) void {
    const radius = designUi(CONTROL_RADIUS);
    const background = if (open or isControlHovered(state, control)) controlHoverSurface() else controlSurface();
    queueRoundedRectClipped(state, rect, paletteColor(background), radius, clip);
    queueBorderClipped(state, rect, paletteColor(if (open) controlOpenEdge() else controlEdge()), radius, 1.0, clip);
    const pad = designUi(CONTROL_PAD_X);
    const chevron = designUi(CHEVRON_SIZE);
    const font = designUi(CONTROL_FONT);
    queueText(state, .{
        .x = rect.x + pad,
        .y = rect.y + (rect.h - font * 1.25) * 0.5,
        .w = @max(rect.w - pad * 2.0 - chevron - designUi(8.0), 0.0),
        .h = font * 1.25,
    }, label, paletteColor(textPrimary()), font, clip);
    queueIconText(state, .{
        .x = rect.x + rect.w - pad - chevron,
        .y = rect.y + (rect.h - chevron) * 0.5,
        .w = chevron,
        .h = chevron,
    }, if (open) LU_CHEVRON_UP else LU_CHEVRON_DOWN, paletteColor(textHint()), chevron, clip);
}

// Popup surface shared by every settings dropdown menu.
fn drawMenuFrame(state: *runtime.AppState, menu: palette.Rect, clip: palette.Rect) void {
    const radius = designUi(CONTROL_RADIUS);
    // One soft layer lifts the popup off the card beneath it.
    queueRoundedRectClipped(state, .{ .x = menu.x - 1.0, .y = menu.y + designUi(2.0), .w = menu.w + 2.0, .h = menu.h + designUi(2.0) }, paletteColor(theme.scrim(0.06)), radius + 1.0, clip);
    queueRoundedRectClipped(state, menu, paletteColor(menuSurface()), radius, clip);
    queueBorderClipped(state, menu, paletteColor(controlEdge()), radius, 1.0, clip);
}

// One menu option: soft fill on hover/selection, check mark on the selection.
fn drawMenuOption(state: *runtime.AppState, row: palette.Rect, label: []const u8, selected: bool, hovered: bool, clip: palette.Rect) void {
    if (selected or hovered) {
        queueRoundedRectClipped(state, row, paletteColor(if (hovered) selectedSurface() else controlHoverSurface()), designUi(6.0), clip);
    }
    const pad = designUi(8.0);
    const check = designUi(CHEVRON_SIZE);
    const font = designUi(CONTROL_FONT);
    queueText(state, .{
        .x = row.x + pad,
        .y = row.y + (row.h - font * 1.25) * 0.5,
        .w = @max(row.w - pad * 2.0 - check - designUi(6.0), 0.0),
        .h = font * 1.25,
    }, label, paletteColor(if (selected or hovered) textPrimary() else textLabel()), font, clip);
    if (selected) {
        queueIconText(state, .{
            .x = row.x + row.w - pad - check,
            .y = row.y + (row.h - check) * 0.5,
            .w = check,
            .h = check,
        }, LU_CHECK, paletteColor(textPrimary()), check, clip);
    }
}

// Thin scroll thumb for menus that show a window of a longer list.
fn drawMenuScrollThumb(state: *runtime.AppState, menu: palette.Rect, count: usize, visible_count: usize, scroll: usize, clip: palette.Rect) void {
    if (count <= visible_count) return;
    const track: palette.Rect = .{
        .x = menu.x + menu.w - designUi(4.0),
        .y = menu.y + designUi(6.0),
        .w = designUi(2.0),
        .h = menu.h - designUi(12.0),
    };
    const thumb_h = track.h * @as(f32, @floatFromInt(visible_count)) / @as(f32, @floatFromInt(count));
    const travel = track.h - thumb_h;
    const progress = @as(f32, @floatFromInt(scroll)) / @as(f32, @floatFromInt(count - visible_count));
    queueRoundedRectClipped(state, .{ .x = track.x, .y = track.y + travel * progress, .w = track.w, .h = thumb_h }, paletteColor(theme.withAlpha(theme.COLOR_TEXT_SUBTLE, 150)), track.w * 0.5, clip);
}

// Appearance Default companion selector popup rows.
fn drawCompanionCharacterDropdownMenu(state: *runtime.AppState, layout: SettingsLayout) void {
    if (!state.settings_controller.companion_character_dropdown_open) return;
    drawMenuFrame(state, companionCharacterMenuRect(layout), layout.body_clip);
    const selected = companionCharacterIndex(state.settings_controller.draft.companion_character);
    for (0..companionCharacterCount()) |choice_index| {
        drawMenuOption(state, companionCharacterOptionRect(layout, choice_index), companionCharacterLabel(choice_index), choice_index == selected, state.settings_controller.companion_character_hover_index == choice_index, layout.body_clip);
    }
}

// Appearance UI font family selector popup rows.
fn drawUiFontFamilyDropdownMenu(state: *runtime.AppState, layout: SettingsLayout) void {
    if (!state.settings_controller.ui_font_family_dropdown_open) return;
    drawMenuFrame(state, uiFontFamilyMenuRect(layout), layout.body_clip);
    const selected = uiFontFamilyIndex(state.settings_controller.draft.ui_font_family);
    for (0..uiFontFamilyCount()) |choice_index| {
        drawMenuOption(state, uiFontFamilyOptionRect(layout, choice_index), uiFontFamilyLabel(choice_index), choice_index == selected, state.settings_controller.ui_font_family_hover_index == choice_index, layout.body_clip);
    }
}

// Appearance theme selector popup rows.
fn drawThemeDropdownMenu(state: *runtime.AppState, layout: SettingsLayout) void {
    if (!state.settings_controller.theme_dropdown_open) return;
    const menu = themeMenuRect(state, layout);
    drawMenuFrame(state, menu, layout.body_clip);
    const scroll = state.settings_controller.theme_menu_scroll;
    for (0..themeMenuVisibleCount(state)) |visible_index| {
        const choice_index = scroll + visible_index;
        drawMenuOption(state, themeOptionRect(state, layout, visible_index), state.settingsThemeChoiceLabel(choice_index), choice_index == state.settings_controller.draft.theme_choice, state.settings_controller.theme_hover_index == choice_index, layout.body_clip);
    }
    drawMenuScrollThumb(state, menu, state.settingsThemeChoiceCount(), themeMenuVisibleCount(state), scroll, layout.body_clip);
}

// Chat title provider/model popup rows.
fn drawChatTitleDropdownMenu(state: *runtime.AppState, layout: SettingsLayout, provider_menu: bool) void {
    const open = if (provider_menu) state.settings_controller.title_provider_dropdown_open else state.settings_controller.title_model_dropdown_open;
    if (!open) return;
    const count = if (provider_menu) state.settingsChatTitleProviderCount() else state.settingsChatTitleModelCount();
    const visible_count = if (provider_menu) count else titleModelMenuVisibleCount(state);
    const scroll = if (provider_menu) 0 else state.settings_controller.title_model_menu_scroll;
    const menu = if (provider_menu) titleProviderMenuRect(state, layout) else titleModelMenuRect(state, layout);
    drawMenuFrame(state, menu, layout.body_clip);
    const selected_index = if (provider_menu) state.settingsChatTitleProviderSelectedIndex() else state.settingsChatTitleModelSelectedIndex() orelse std.math.maxInt(usize);
    for (0..visible_count) |visible_index| {
        const option_index = scroll + visible_index;
        const label = if (provider_menu) state.settingsChatTitleProviderLabel(option_index) else state.settingsChatTitleModelLabel(option_index);
        drawMenuOption(state, dropdownOptionRect(menu, visible_index), label, option_index == selected_index, state.settings_controller.title_menu_hover_index == option_index, layout.body_clip);
    }
    if (!provider_menu) drawMenuScrollThumb(state, menu, count, visible_count, scroll, layout.body_clip);
}

// Renders one new-chat default dropdown menu over the Chat settings card.
fn drawNewChatDropdownMenu(state: *runtime.AppState, layout: SettingsLayout, kind: NewChatMenuKind) void {
    const open = switch (kind) {
        .provider => state.settings_controller.new_chat_provider_dropdown_open,
        .model => state.settings_controller.new_chat_model_dropdown_open,
        .reasoning => state.settings_controller.new_chat_reasoning_dropdown_open,
    };
    if (!open) return;
    const count = newChatMenuCount(state, kind);
    const visible_count = if (kind == .model) newChatModelMenuVisibleCount(state) else @min(count, TITLE_MENU_MAX_ROWS);
    const scroll = if (kind == .model) state.settings_controller.new_chat_model_menu_scroll else 0;
    const menu = newChatMenuRect(state, layout, kind);
    drawMenuFrame(state, menu, layout.body_clip);
    const selected_index = switch (kind) {
        .provider => state.settingsNewChatProviderSelectedIndex(),
        .model => state.settingsNewChatModelSelectedIndex() orelse std.math.maxInt(usize),
        .reasoning => state.settingsNewChatReasoningSelectedIndex(),
    };
    for (0..visible_count) |visible_index| {
        const option_index = scroll + visible_index;
        const label = switch (kind) {
            .provider => state.settingsNewChatProviderLabel(option_index),
            .model => state.settingsNewChatModelLabel(option_index),
            .reasoning => state.settingsNewChatReasoningLabel(option_index),
        };
        drawMenuOption(state, dropdownOptionRect(menu, visible_index), label, option_index == selected_index, state.settings_controller.new_chat_menu_hover_index == option_index, layout.body_clip);
    }
    if (kind == .model) drawMenuScrollThumb(state, menu, count, visible_count, scroll, layout.body_clip);
}

fn drawOpenActionDropdownMenu(state: *runtime.AppState, layout: SettingsLayout) void {
    if (!state.settings_controller.open_action_dropdown_open) return;
    const menu = openActionMenuRect(layout);
    drawMenuFrame(state, menu, layout.body_clip);
    const selected_index = openActionSelectedIndex(state);
    for (OPEN_CHOICES, 0..) |choice, option_index| {
        drawMenuOption(state, dropdownOptionRect(menu, option_index), choice.label, option_index == selected_index, state.settings_controller.open_action_hover_index == option_index, layout.body_clip);
    }
}

const ReducedMotionRow = struct {
    part: app_config.ReducedMotion.Part,
    control: Control,
    label: []const u8,
};

/// Sub-switches under "Reduce motion", in display order.
const REDUCED_MOTION_PARTS = [_]ReducedMotionRow{
    .{ .part = .pane_scroll, .control = .reduced_motion_pane_scroll, .label = "Pane scrolling" },
    .{ .part = .pane_layout, .control = .reduced_motion_pane_layout, .label = "Pane resize & focus" },
    .{ .part = .status_pulse, .control = .reduced_motion_status_pulse, .label = "Status pulses" },
    .{ .part = .chat, .control = .reduced_motion_chat, .label = "Chat animations" },
    .{ .part = .chrome, .control = .reduced_motion_chrome, .label = "Sidebar & dialogs" },
};

fn reducedMotionPart(motion: app_config.ReducedMotion, part: app_config.ReducedMotion.Part) bool {
    return switch (part) {
        inline else => |tag| @field(motion, @tagName(tag)),
    };
}

fn toggleReducedMotionPart(motion: *app_config.ReducedMotion, part: app_config.ReducedMotion.Part) void {
    switch (part) {
        inline else => |tag| @field(motion, @tagName(tag)) = !@field(motion, @tagName(tag)),
    }
}

// Switch row: the row (label drawn by the page chrome) is the hit target;
// hover lays a soft inset fill, and the pill switch sits at the right edge.
fn drawSwitchRow(state: *runtime.AppState, rect: palette.Rect, on: bool, hovered: bool, clip: palette.Rect) void {
    if (hovered) {
        const inset = designUi(4.0);
        queueRoundedRectClipped(state, .{ .x = rect.x + inset, .y = rect.y + inset, .w = rect.w - inset * 2.0, .h = rect.h - inset * 2.0 }, paletteColor(controlHoverSurface()), designUi(CONTROL_RADIUS), clip);
    }
    const track_w = designUi(SWITCH_W);
    const track_h = designUi(SWITCH_H);
    const track: palette.Rect = .{
        .x = rect.x + rect.w - designUi(ROW_PAD_X) - track_w,
        .y = rect.y + (rect.h - track_h) * 0.5,
        .w = track_w,
        .h = track_h,
    };
    drawSwitch(state, track, on, hovered, clip);
}

// Pill switch: dark (text-coloured) track when on, soft neutral when off.
fn drawSwitch(state: *runtime.AppState, track: palette.Rect, on: bool, hovered: bool, clip: palette.Rect) void {
    const off_track = inkTint(if (hovered) 0.2 else 0.16);
    const on_track = if (hovered) theme.mix(strongFill(), cardSurface(), 0.12) else strongFill();
    queueRoundedRectClipped(state, track, paletteColor(if (on) on_track else off_track), track.h * 0.5, clip);
    const knob_pad = designUi(SWITCH_KNOB_PAD);
    const knob = track.h - knob_pad * 2.0;
    const knob_x = if (on) track.x + track.w - knob_pad - knob else track.x + knob_pad;
    const knob_rect: palette.Rect = .{ .x = knob_x, .y = track.y + knob_pad, .w = knob, .h = knob };
    // Light palettes keep a white knob either way; on dark ones the knob
    // contrasts with its track (dark on the light "on" track).
    const knob_color = if (theme.isLightPalette())
        theme.COLOR_PANEL
    else if (on)
        cardSurface()
    else
        inkTint(0.6);
    queueRoundedRectClipped(state, .{ .x = knob_rect.x, .y = knob_rect.y + designUi(0.8), .w = knob, .h = knob }, paletteColor(theme.scrim(0.12)), knob * 0.5, clip);
    queueRoundedRectClipped(state, knob_rect, paletteColor(knob_color), knob * 0.5, clip);
}

fn browserScrollSliderHitRect(row: palette.Rect) palette.Rect {
    const value_w = designUi(SLIDER_VALUE_W);
    const track_w = @min(designUi(SLIDER_W), row.w * 0.45);
    return .{
        .x = row.x + row.w - designUi(ROW_PAD_X) - value_w - track_w,
        .y = row.y,
        .w = @max(track_w, 1.0),
        .h = row.h,
    };
}

fn browserScrollSpeedFromPoint(track: palette.Rect, x: f32) f32 {
    const progress = theme.clampf((x - track.x) / @max(track.w, 1.0), 0.0, 1.0);
    const span = app_config.MAX_BROWSER_SCROLL_SPEED - app_config.MIN_BROWSER_SCROLL_SPEED;
    const raw = app_config.MIN_BROWSER_SCROLL_SPEED + progress * span;
    const steps = @round((raw - app_config.MIN_BROWSER_SCROLL_SPEED) / app_config.BROWSER_SCROLL_SPEED_STEP);
    return app_config.MIN_BROWSER_SCROLL_SPEED + steps * app_config.BROWSER_SCROLL_SPEED_STEP;
}

// Browser settings row: right-aligned wheel-speed slider and its multiplier.
fn drawBrowserScrollSpeedSlider(state: *runtime.AppState, row: palette.Rect, value: f32, hovered: bool, clip: palette.Rect) void {
    const hit = browserScrollSliderHitRect(row);
    const knob_size = designUi(16.0);
    // Inset the track by the knob radius so the knob stays inside the hit.
    const track_h = designUi(4.0);
    const track: palette.Rect = .{ .x = hit.x + knob_size * 0.5, .y = row.y + (row.h - track_h) * 0.5, .w = @max(hit.w - knob_size, 1.0), .h = track_h };
    const progress = (theme.clampf(value, app_config.MIN_BROWSER_SCROLL_SPEED, app_config.MAX_BROWSER_SCROLL_SPEED) - app_config.MIN_BROWSER_SCROLL_SPEED) /
        (app_config.MAX_BROWSER_SCROLL_SPEED - app_config.MIN_BROWSER_SCROLL_SPEED);
    queueRoundedRectClipped(state, track, paletteColor(inkTint(if (hovered) 0.2 else 0.16)), track_h * 0.5, clip);
    queueRoundedRectClipped(state, .{ .x = track.x, .y = track.y, .w = track.w * progress, .h = track.h }, paletteColor(strongFill()), track_h * 0.5, clip);

    const knob: palette.Rect = .{ .x = track.x + track.w * progress - knob_size * 0.5, .y = row.y + (row.h - knob_size) * 0.5, .w = knob_size, .h = knob_size };
    queueRoundedRectClipped(state, knob, paletteColor(controlSurface()), knob_size * 0.5, clip);
    queueBorderClipped(state, knob, paletteColor(if (hovered) controlOpenEdge() else controlEdge()), knob_size * 0.5, 1.0, clip);

    var value_buf: [16]u8 = undefined;
    const value_text = std.fmt.bufPrint(&value_buf, "{d:.2}×", .{value}) catch "?×";
    const font = designUi(CONTROL_FONT);
    const value_w = text_measure.textWidth(.ui, font, value_text);
    const value_right = row.x + row.w - designUi(ROW_PAD_X);
    queueText(state, .{ .x = value_right - value_w, .y = row.y + (row.h - font * 1.25) * 0.5, .w = value_w + designUi(2.0), .h = font * 1.25 }, value_text, paletteColor(textPrimary()), font, clip);
}

// Companion row: "Experimental" tag after the chrome-drawn label, switch.
fn drawCompanionExperimentalRow(state: *runtime.AppState, rect: palette.Rect, on: bool, hovered: bool, clip: palette.Rect) void {
    drawSwitchRow(state, rect, on, hovered, clip);
    const label_w = text_measure.textWidth(.ui, designUi(ROW_LABEL_FONT), "Companion");
    const badge_font_size = designUi(11.0);
    const badge_h = designUi(18.0);
    const badge_pad_x = designUi(6.0);
    const badge_text_w = text_measure.textWidth(.ui, badge_font_size, "Experimental");
    const badge: palette.Rect = .{
        .x = rect.x + designUi(ROW_PAD_X) + label_w + designUi(10.0),
        .y = rect.y + (rect.h - badge_h) * 0.5,
        .w = badge_text_w + badge_pad_x * 2.0,
        .h = badge_h,
    };
    queueBorderClipped(state, badge, paletteColor(controlEdge()), designUi(5.0), 1.0, clip);
    queueCenteredText(state, badge, "Experimental", paletteColor(textLabel()), badge_font_size, clip);
}

// Exclusive choice as a segmented control: soft track, raised selection.
fn drawSegmented(
    state: *runtime.AppState,
    segments: []const palette.Rect,
    labels: []const []const u8,
    selected_index: usize,
    controls: []const Control,
    clip: palette.Rect,
) void {
    if (segments.len == 0) return;
    const inset = designUi(SEGMENT_INSET);
    const first = segments[0];
    const last = segments[segments.len - 1];
    const track: palette.Rect = .{ .x = first.x - inset, .y = first.y - inset, .w = last.x + last.w - first.x + inset * 2.0, .h = first.h + inset * 2.0 };
    const radius = designUi(CONTROL_RADIUS);
    queueRoundedRectClipped(state, track, paletteColor(segmentTrack()), radius, clip);
    const selected = @min(selected_index, segments.len - 1);
    const seg_radius = radius - inset;
    queueRoundedRectClipped(state, segments[selected], paletteColor(segmentRaised()), seg_radius, clip);
    queueBorderClipped(state, segments[selected], paletteColor(controlEdge()), seg_radius, 1.0, clip);
    const font = designUi(CONTROL_FONT);
    for (segments, labels, controls, 0..) |segment, label, control, index| {
        const is_selected = index == selected;
        const hovered = isControlHovered(state, control);
        const color = if (is_selected or hovered) textPrimary() else textLabel();
        const text_w = @min(text_measure.textWidth(.ui, font, label), segment.w);
        const rect: palette.Rect = .{ .x = segment.x + (segment.w - text_w) * 0.5, .y = segment.y + (segment.h - font * 1.25) * 0.5, .w = text_w + designUi(2.0), .h = font * 1.25 };
        queueRoleText(state, rect, label, paletteColor(color), font, if (is_selected) .ui_medium else .ui, clip);
    }
}

const ButtonStyle = enum { primary, secondary, disabled };

// Push button for immediate actions (update check/install), with a real
// disabled look so inert states don't read as clickable.
fn drawActionButton(state: *runtime.AppState, rect: palette.Rect, label: []const u8, style: ButtonStyle, hovered: bool, clip: palette.Rect) void {
    const radius = designUi(CONTROL_RADIUS);
    var text_color = textPrimary();
    switch (style) {
        .primary => {
            const fill = if (hovered) theme.mix(strongFill(), cardSurface(), 0.14) else strongFill();
            queueRoundedRectClipped(state, rect, paletteColor(fill), radius, clip);
            text_color = theme.foregroundOn(fill);
        },
        .secondary => {
            queueRoundedRectClipped(state, rect, paletteColor(if (hovered) controlHoverSurface() else controlSurface()), radius, clip);
            queueBorderClipped(state, rect, paletteColor(controlEdge()), radius, 1.0, clip);
        },
        .disabled => {
            queueBorderClipped(state, rect, paletteColor(inkTint(0.08)), radius, 1.0, clip);
            text_color = textHint();
        },
    }
    queueCenteredText(state, rect, label, paletteColor(text_color), designUi(CONTROL_FONT), clip);
}

// Thin overlay scrollbar so overflow in the modal body is discoverable.
fn drawBodyScrollbar(state: *runtime.AppState, layout: SettingsLayout) void {
    if (layout.max_scroll_y <= 0.0) return;
    const track: palette.Rect = .{
        .x = layout.body_clip.x + layout.body_clip.w - designUi(8.0),
        .y = layout.body_clip.y + designUi(4.0),
        .w = designUi(3.0),
        .h = layout.body_clip.h - designUi(16.0),
    };
    if (track.h <= 0.0) return;
    const view_ratio = layout.body_clip.h / (layout.body_clip.h + layout.max_scroll_y);
    const thumb_h = @max(track.h * view_ratio, designUi(24.0));
    const travel = @max(track.h - thumb_h, 0.0);
    const progress = state.settings_controller.scroll_y / layout.max_scroll_y;
    queueRoundedRect(state, .{ .x = track.x, .y = track.y + travel * progress, .w = track.w, .h = thumb_h }, paletteColor(theme.withAlpha(theme.COLOR_TEXT_SUBTLE, 110)), track.w * 0.5);
}

// Stepper: [−] value [+] in one bordered pill.
fn drawStepper(
    state: *runtime.AppState,
    value: f32,
    min_value: f32,
    max_value: f32,
    dec_control: Control,
    inc_control: Control,
    dec_rect: palette.Rect,
    inc_rect: palette.Rect,
    clip: palette.Rect,
) void {
    const pill: palette.Rect = .{ .x = dec_rect.x, .y = dec_rect.y, .w = inc_rect.x + inc_rect.w - dec_rect.x, .h = dec_rect.h };
    const radius = designUi(CONTROL_RADIUS);
    queueRoundedRectClipped(state, pill, paletteColor(controlSurface()), radius, clip);
    const at_min = value <= min_value;
    const at_max = value >= max_value;
    drawStepButton(state, dec_rect, LU_MINUS, !at_min, isControlHovered(state, dec_control), clip);
    drawStepButton(state, inc_rect, LU_PLUS, !at_max, isControlHovered(state, inc_control), clip);
    queueBorderClipped(state, pill, paletteColor(controlEdge()), radius, 1.0, clip);

    var value_buf: [8]u8 = undefined;
    const value_text = std.fmt.bufPrint(&value_buf, "{d:.0}", .{value}) catch "?";
    const value_rect: palette.Rect = .{ .x = dec_rect.x + dec_rect.w, .y = pill.y, .w = inc_rect.x - (dec_rect.x + dec_rect.w), .h = pill.h };
    queueCenteredText(state, value_rect, value_text, paletteColor(textPrimary()), designUi(CONTROL_FONT), clip);
}

fn drawStepButton(state: *runtime.AppState, rect: palette.Rect, glyph: []const u8, enabled: bool, hovered: bool, clip: palette.Rect) void {
    if (hovered and enabled) {
        const inset = designUi(3.0);
        queueRoundedRectClipped(state, .{ .x = rect.x + inset, .y = rect.y + inset, .w = rect.w - inset * 2.0, .h = rect.h - inset * 2.0 }, paletteColor(controlHoverSurface()), designUi(5.0), clip);
    }
    const text_color = if (enabled) textLabel() else theme.withAlpha(theme.COLOR_TEXT_SUBTLE, 110);
    queueCenteredIcon(state, rect, glyph, paletteColor(text_color), designUi(13.0), clip);
}

/// Lucide glyph centred in `rect` (sizes are pre-optical-bump).
fn queueCenteredIcon(state: *runtime.AppState, rect: palette.Rect, glyph: []const u8, color: palette.Color, size: f32, clip: ?palette.Rect) void {
    queueIconText(state, .{
        .x = rect.x + (rect.w - size) * 0.5,
        .y = rect.y + (rect.h - size) * 0.5,
        .w = size,
        .h = size,
    }, glyph, color, size, clip);
}

fn queueCenteredText(state: *runtime.AppState, rect: palette.Rect, value: []const u8, color: palette.Color, font_size: f32, clip: ?palette.Rect) void {
    const text_w = @min(text_measure.textWidth(.ui, font_size, value), rect.w);
    queueText(state, .{
        .x = rect.x + (rect.w - text_w) * 0.5,
        .y = rect.y + (rect.h - font_size * 1.25) * 0.5,
        .w = text_w + theme.scaledUi(2.0),
        .h = font_size * 1.25,
    }, value, color, font_size, clip);
}

fn queueRoundedRect(state: *runtime.AppState, rect: palette.Rect, color: palette.Color, radius: f32) void {
    state.palette_overlay_batch.roundedRect(state.allocator, rect, color, radius) catch |err| {
        log.warn("failed to queue settings rounded rect: {s}", .{@errorName(err)});
    };
}

fn queueRoundedRectClipped(state: *runtime.AppState, rect: palette.Rect, color: palette.Color, radius: f32, clip: palette.Rect) void {
    if (intersectRect(rect, clip) == null) return;
    state.palette_overlay_batch.roundedRectClipped(state.allocator, rect, color, radius, clip) catch |err| {
        log.warn("failed to queue clipped settings rounded rect: {s}", .{@errorName(err)});
    };
}

fn queueBorder(state: *runtime.AppState, rect: palette.Rect, color: palette.Color, radius: f32, width: f32) void {
    state.palette_overlay_batch.rectBorder(state.allocator, rect, color, radius, width) catch |err| {
        log.warn("failed to queue settings border: {s}", .{@errorName(err)});
    };
}

fn queueBorderClipped(state: *runtime.AppState, rect: palette.Rect, color: palette.Color, radius: f32, width: f32, clip: palette.Rect) void {
    if (intersectRect(rect, clip) == null) return;
    state.palette_overlay_batch.rectBorderClipped(state.allocator, rect, color, radius, width, clip) catch |err| {
        log.warn("failed to queue clipped settings border: {s}", .{@errorName(err)});
    };
}

fn queueText(state: *runtime.AppState, rect: palette.Rect, value: []const u8, color: palette.Color, font_size: f32, clip: ?palette.Rect) void {
    const stable_value = state.palette_frame_text_arena.allocator().dupe(u8, value) catch |err| {
        log.warn("failed to retain settings text: {s}", .{@errorName(err)});
        return;
    };
    state.palette_overlay_batch.fixedRoleText(
        state.allocator,
        rect,
        stable_value,
        color,
        font_size,
        .ui,
        null,
        clip,
        .{},
        font_size * 0.55,
        font_size * 1.25,
        false,
    ) catch |err| {
        log.warn("failed to queue settings text: {s}", .{@errorName(err)});
    };
}

// Same as `queueText` with an explicit font role (e.g. `.ui_medium` titles).
fn queueRoleText(state: *runtime.AppState, rect: palette.Rect, value: []const u8, color: palette.Color, font_size: f32, role: palette.FontRole, clip: ?palette.Rect) void {
    const stable_value = state.palette_frame_text_arena.allocator().dupe(u8, value) catch |err| {
        log.warn("failed to retain settings text: {s}", .{@errorName(err)});
        return;
    };
    state.palette_overlay_batch.fixedRoleText(
        state.allocator,
        rect,
        stable_value,
        color,
        font_size,
        role,
        null,
        clip,
        .{},
        font_size * 0.55,
        font_size * 1.25,
        false,
    ) catch |err| {
        log.warn("failed to queue settings text: {s}", .{@errorName(err)});
    };
}

// Same as `queueText` but wraps at the rect width for multi-line hint copy.
fn queueWrappedText(state: *runtime.AppState, rect: palette.Rect, value: []const u8, color: palette.Color, font_size: f32, clip: ?palette.Rect) void {
    const stable_value = state.palette_frame_text_arena.allocator().dupe(u8, value) catch |err| {
        log.warn("failed to retain settings text: {s}", .{@errorName(err)});
        return;
    };
    state.palette_overlay_batch.fixedRoleText(
        state.allocator,
        rect,
        stable_value,
        color,
        font_size,
        .ui,
        null,
        clip,
        .{},
        font_size * 0.55,
        font_size * 1.25,
        true,
    ) catch |err| {
        log.warn("failed to queue settings text: {s}", .{@errorName(err)});
    };
}

fn queueIconText(state: *runtime.AppState, rect: palette.Rect, value: []const u8, color: palette.Color, font_size: f32, clip: ?palette.Rect) void {
    const stable_value = state.palette_frame_text_arena.allocator().dupe(u8, value) catch |err| {
        log.warn("failed to retain settings icon: {s}", .{@errorName(err)});
        return;
    };
    // Grow the glyph about the caller's centre so layout is unchanged.
    const grow_w = rect.w * (LUCIDE_OPTICAL_SCALE - 1.0);
    const grow_h = rect.h * (LUCIDE_OPTICAL_SCALE - 1.0);
    state.palette_overlay_batch.roleText(
        state.allocator,
        .{ .x = rect.x - grow_w * 0.5, .y = rect.y - grow_h * 0.5, .w = rect.w + grow_w, .h = rect.h + grow_h },
        stable_value,
        color,
        font_size * LUCIDE_OPTICAL_SCALE,
        .icon_alt,
        null,
        clip,
    ) catch |err| {
        log.warn("failed to queue settings icon: {s}", .{@errorName(err)});
    };
}

fn rectContains(rect: palette.Rect, x: f32, y: f32) bool {
    return x >= rect.x and y >= rect.y and x <= rect.x + rect.w and y <= rect.y + rect.h;
}

fn intersectRect(a: palette.Rect, b: palette.Rect) ?palette.Rect {
    const x0 = @max(a.x, b.x);
    const y0 = @max(a.y, b.y);
    const x1 = @min(a.x + a.w, b.x + b.w);
    const y1 = @min(a.y + a.h, b.y + b.h);
    if (x1 <= x0 or y1 <= y0) return null;
    return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
}

fn paletteColor(value: [4]f32) palette.Color {
    return .{ .r = value[0], .g = value[1], .b = value[2], .a = value[3] * current_fade_alpha };
}

fn testSettingsState(allocator: std.mem.Allocator) runtime.AppState {
    var state: runtime.AppState = undefined;
    state.allocator = allocator;
    state.app_config = .{};
    state.settings_controller = .{};
    state.project_controller = .{};
    state.project_controller.projects = .empty;
    state.project_controller.selected_index = 0;
    state.lifecycle = .{};
    state.palette_modal_text_focus = .none;
    state.palette_overlay_batch = .{};
    state.palette_frame_text_arena = std.heap.ArenaAllocator.init(allocator);
    state.palette_modal_hits = .empty;
    state.settings_controller.modal_visible = true;
    state.settings_controller.modal_anim_progress = 1.0;
    state.settings_controller.persist_to_disk = false;
    state.settings_controller.draft = .{};
    // The runtimes card reads these directly; a bare test state has no
    // service, so it renders only the Local row.
    state.runtime_picker_profiles = .empty;
    state.runtime_service = null;
    state.workspace_runtime_defaults = null;
    state.runtime_connections = .{};
    state.settings_controller.draft.theme_choice = state.app_config.themeChoiceIndex();
    state.settings_controller.draft.companion_character = state.app_config.companion_character;
    return state;
}

fn deinitTestSettingsState(state: *runtime.AppState, allocator: std.mem.Allocator) void {
    state.runtime_picker_profiles.deinit(allocator);
    state.palette_overlay_batch.deinit(allocator);
    state.palette_frame_text_arena.deinit();
    state.palette_modal_hits.deinit(allocator);
    state.app_config.deinit(allocator);
}

fn captureSettingsHit(
    state: *runtime.AppState,
    rect: palette.Rect,
    action: runtime.PaletteModalAction,
    index: usize,
) void {
    state.palette_modal_hits.append(state.allocator, .{
        .rect = rect,
        .action = action,
        .index = index,
    }) catch {};
}

fn topModalActionAt(state: *const runtime.AppState, x: f32, y: f32) ?runtime.PaletteModalAction {
    var found: ?runtime.PaletteModalAction = null;
    for (state.palette_modal_hits.items) |hit| {
        if (rectContains(hit.rect, x, y)) found = hit.action;
    }
    return found;
}

test "default companion dropdown render hits keyboard and live-applies" {
    const allocator = std.testing.allocator;
    defer theme.applyTheme(1.0);
    theme.applyTheme(1.0);

    var state = testSettingsState(allocator);
    defer deinitTestSettingsState(&state, allocator);

    const width: f32 = 1200.0;
    const height: f32 = 900.0;
    applyControl(&state, @intFromEnum(Control.companion_toggle));
    try std.testing.expect(state.settings_controller.draft.companion_enabled);
    try std.testing.expect(state.app_config.companion_enabled);

    const layout = computeLayout(&state, width, height);
    try std.testing.expect(layout.companion_character_dropdown.w > 0.0);
    try std.testing.expect(layout.companion_character_dropdown.h > 0.0);
    try std.testing.expect(layout.companion_character_dropdown.y > layout.theme_dropdown.y);

    state.palette_modal_hits.clearRetainingCapacity();
    registerHits(&state, width, height, captureSettingsHit);
    var saw_dropdown = false;
    for (state.palette_modal_hits.items) |hit| {
        if (hit.action == .settings_control and hit.index == @intFromEnum(Control.companion_character_dropdown)) {
            saw_dropdown = true;
            try std.testing.expect(rectContains(hit.rect, layout.companion_character_dropdown.x + 1.0, layout.companion_character_dropdown.y + 1.0));
        }
    }
    try std.testing.expect(saw_dropdown);

    applyControl(&state, @intFromEnum(Control.companion_character_dropdown));
    try std.testing.expect(state.settings_controller.companion_character_dropdown_open);
    try std.testing.expectEqual(@as(?usize, 0), state.settings_controller.companion_character_hover_index);

    state.palette_modal_hits.clearRetainingCapacity();
    registerHits(&state, width, height, captureSettingsHit);
    var option_hits: usize = 0;
    for (state.palette_modal_hits.items) |hit| {
        if (hit.action == .settings_theme_option) option_hits += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), option_hits);

    try std.testing.expect(handleKeyDown(&state, .down));
    try std.testing.expectEqual(@as(?usize, 1), state.settings_controller.companion_character_hover_index);
    try std.testing.expect(handleKeyDown(&state, .@"return"));
    try std.testing.expectEqual(app_config.CompanionCharacter.moss, state.settings_controller.draft.companion_character);
    try std.testing.expect(!state.settings_controller.companion_character_dropdown_open);
    try std.testing.expectEqual(app_config.CompanionCharacter.moss, state.app_config.companion_character);
    try std.testing.expect(!state.isSettingsDraftDirty());

    applyControl(&state, @intFromEnum(Control.companion_character_dropdown));
    try std.testing.expect(handleKeyDown(&state, .down));
    try std.testing.expect(handleKeyDown(&state, .down));
    try std.testing.expect(handleKeyDown(&state, .@"return"));
    try std.testing.expectEqual(app_config.CompanionCharacter.vireo, state.settings_controller.draft.companion_character);
    try std.testing.expectEqual(app_config.CompanionCharacter.vireo, state.app_config.companion_character);
    try std.testing.expect(!state.isSettingsDraftDirty());

    applyControl(&state, @intFromEnum(Control.companion_character_dropdown));
    try std.testing.expect(handleKeyDown(&state, .escape));
    try std.testing.expect(!state.settings_controller.companion_character_dropdown_open);

    state.palette_overlay_batch.clear();
    _ = state.palette_frame_text_arena.reset(.retain_capacity);
    state.settings_controller.companion_character_dropdown_open = true;
    render(&state, width, height);
    var saw_character_label = false;
    var saw_vireo = false;
    var saw_moss_option = false;
    for (state.palette_overlay_batch.commands.items) |command| {
        if (command.kind != .text) continue;
        if (std.mem.eql(u8, command.text, "Character")) saw_character_label = true;
        if (std.mem.eql(u8, command.text, "Vireo")) saw_vireo = true;
        if (std.mem.eql(u8, command.text, "Moss")) saw_moss_option = true;
    }
    try std.testing.expect(saw_character_label);
    try std.testing.expect(saw_vireo);
    try std.testing.expect(saw_moss_option);

    applyControl(&state, @intFromEnum(Control.theme_dropdown));
    try std.testing.expect(state.settings_controller.theme_dropdown_open);
    try std.testing.expect(!state.settings_controller.companion_character_dropdown_open);
    applyControl(&state, @intFromEnum(Control.companion_character_dropdown));
    try std.testing.expect(state.settings_controller.companion_character_dropdown_open);
    try std.testing.expect(!state.settings_controller.theme_dropdown_open);
}

test "UI font family dropdown sits between theme and font size and live-applies" {
    const allocator = std.testing.allocator;
    defer theme.applyTheme(1.0);
    theme.applyTheme(1.0);

    var state = testSettingsState(allocator);
    defer deinitTestSettingsState(&state, allocator);

    const width: f32 = 1200.0;
    const height: f32 = 900.0;
    const layout = computeLayout(&state, width, height);
    try std.testing.expect(layout.ui_font_family_dropdown.y > layout.theme_dropdown.y);
    try std.testing.expect(layout.ui_font_dec.y > layout.ui_font_family_dropdown.y);
    try std.testing.expect(layout.reduced_motion.y > layout.ui_font_dec.y + layout.ui_font_dec.h);
    const last_card = layout.page.groups[layout.page.group_count - 1].card;
    try std.testing.expect(last_card.y + last_card.h >= layout.companion_toggle.y + layout.companion_toggle.h);

    state.palette_modal_hits.clearRetainingCapacity();
    registerHits(&state, width, height, captureSettingsHit);
    var saw_dropdown = false;
    for (state.palette_modal_hits.items) |hit| {
        if (hit.action == .settings_control and hit.index == @intFromEnum(Control.ui_font_family_dropdown)) saw_dropdown = true;
    }
    try std.testing.expect(saw_dropdown);

    applyControl(&state, @intFromEnum(Control.ui_font_family_dropdown));
    try std.testing.expect(state.settings_controller.ui_font_family_dropdown_open);
    try std.testing.expectEqual(@as(?usize, 0), state.settings_controller.ui_font_family_hover_index);

    state.palette_modal_hits.clearRetainingCapacity();
    registerHits(&state, width, height, captureSettingsHit);
    var option_hits: usize = 0;
    for (state.palette_modal_hits.items) |hit| {
        if (hit.action == .settings_theme_option) option_hits += 1;
    }
    try std.testing.expectEqual(uiFontFamilyCount(), option_hits);

    try std.testing.expect(handleKeyDown(&state, .down));
    try std.testing.expect(handleKeyDown(&state, .@"return"));
    try std.testing.expectEqual(app_config.UiFontFamily.inter, state.app_config.ui_font_family);
    try std.testing.expect(!state.settings_controller.ui_font_family_dropdown_open);
    try std.testing.expect(!state.isSettingsDraftDirty());

    // The theme option channel routes to the font family while its menu is open.
    applyControl(&state, @intFromEnum(Control.ui_font_family_dropdown));
    applyThemeOption(&state, uiFontFamilyIndex(.ibm_plex));
    try std.testing.expectEqual(app_config.UiFontFamily.ibm_plex, state.app_config.ui_font_family);

    state.palette_overlay_batch.clear();
    _ = state.palette_frame_text_arena.reset(.retain_capacity);
    state.settings_controller.ui_font_family_dropdown_open = true;
    render(&state, width, height);
    var saw_label = false;
    var saw_system = false;
    for (state.palette_overlay_batch.commands.items) |command| {
        if (command.kind != .text) continue;
        if (std.mem.eql(u8, command.text, "Font family")) saw_label = true;
        if (std.mem.eql(u8, command.text, "System (macOS)")) saw_system = true;
    }
    try std.testing.expect(saw_label);
    try std.testing.expect(saw_system);

    applyControl(&state, @intFromEnum(Control.theme_dropdown));
    try std.testing.expect(!state.settings_controller.ui_font_family_dropdown_open);
}

test "UI font family options list classic first" {
    try std.testing.expectEqual(@as(usize, 5), uiFontFamilyCount());
    try std.testing.expectEqualStrings("Verde Classic", uiFontFamilyLabel(0));
    try std.testing.expectEqualStrings("Inter", uiFontFamilyLabel(1));
    try std.testing.expectEqualStrings("Geist", uiFontFamilyLabel(2));
    try std.testing.expectEqualStrings("IBM Plex", uiFontFamilyLabel(3));
    try std.testing.expectEqualStrings("System (macOS)", uiFontFamilyLabel(4));
}

test "companion character option order is Sprout Moss Vireo" {
    try std.testing.expectEqual(@as(usize, 3), companionCharacterCount());
    try std.testing.expectEqualStrings("Sprout", companionCharacterLabel(0));
    try std.testing.expectEqualStrings("Moss", companionCharacterLabel(1));
    try std.testing.expectEqualStrings("Vireo", companionCharacterLabel(2));
    try std.testing.expectEqual(app_config.CompanionCharacter.sprout, COMPANION_CHARACTER_OPTIONS[0]);
    try std.testing.expectEqual(app_config.CompanionCharacter.moss, COMPANION_CHARACTER_OPTIONS[1]);
    try std.testing.expectEqual(app_config.CompanionCharacter.vireo, COMPANION_CHARACTER_OPTIONS[2]);
}

test "pane navigation unzoom setting is a persisted draft toggle" {
    const allocator = std.testing.allocator;
    var state = testSettingsState(allocator);
    defer deinitTestSettingsState(&state, allocator);

    try std.testing.expect(!state.app_config.unzoom_on_pane_navigation);
    try std.testing.expect(!state.settings_controller.draft.unzoom_on_pane_navigation);
    applyControl(&state, @intFromEnum(Control.workspace_unzoom_on_navigation));
    try std.testing.expect(state.settings_controller.draft.unzoom_on_pane_navigation);
    try std.testing.expect(state.app_config.unzoom_on_pane_navigation);
    try std.testing.expect(!state.isSettingsDraftDirty());
}

test "reduced motion setting is a persisted draft toggle" {
    const allocator = std.testing.allocator;
    var state = testSettingsState(allocator);
    defer deinitTestSettingsState(&state, allocator);

    try std.testing.expect(!state.settings_controller.draft.reduced_motion.all());
    try std.testing.expect(!state.app_config.reduced_motion.all());
    applyControl(&state, @intFromEnum(Control.reduced_motion));
    try std.testing.expect(state.settings_controller.draft.reduced_motion.all());
    try std.testing.expect(state.app_config.reduced_motion.all());
    try std.testing.expect(!state.isSettingsDraftDirty());
}

test "reduced motion sub-switch toggles only its area" {
    const allocator = std.testing.allocator;
    var state = testSettingsState(allocator);
    defer deinitTestSettingsState(&state, allocator);

    // Default: only pane scrolling snaps.
    try std.testing.expect(state.app_config.reduced_motion.pane_scroll);
    applyControl(&state, @intFromEnum(Control.reduced_motion_pane_layout));
    try std.testing.expect(state.app_config.reduced_motion.pane_layout);
    try std.testing.expect(state.app_config.reduced_motion.pane_scroll);
    try std.testing.expect(!state.app_config.reduced_motion.chat);
    try std.testing.expect(!state.app_config.reduced_motion.all());
    try std.testing.expect(!state.isSettingsDraftDirty());

    // Master turns every area on; a second press clears them all.
    applyControl(&state, @intFromEnum(Control.reduced_motion));
    try std.testing.expect(state.app_config.reduced_motion.all());
    applyControl(&state, @intFromEnum(Control.reduced_motion));
    try std.testing.expect(!state.app_config.reduced_motion.pane_scroll);
}

test "browser scroll speed slider snaps across the supported range" {
    const allocator = std.testing.allocator;
    var state = testSettingsState(allocator);
    defer deinitTestSettingsState(&state, allocator);

    const track: palette.Rect = .{ .x = 100.0, .y = 20.0, .w = 400.0, .h = 36.0 };
    applyControlAt(&state, @intFromEnum(Control.browser_scroll_speed), track, track.x);
    try std.testing.expect(state.settings_controller.browser_scroll_speed_drag_active);
    try std.testing.expectEqual(app_config.MIN_BROWSER_SCROLL_SPEED, state.settings_controller.draft.browser_scroll_speed);

    try std.testing.expect(updateBrowserScrollSpeedDrag(&state, track.x + track.w * 0.5));
    try std.testing.expectEqual(@as(f32, 3.0), state.settings_controller.draft.browser_scroll_speed);
    try std.testing.expect(updateBrowserScrollSpeedDrag(&state, track.x + track.w));
    try std.testing.expectEqual(app_config.MAX_BROWSER_SCROLL_SPEED, state.settings_controller.draft.browser_scroll_speed);

    endBrowserScrollSpeedDrag(&state);
    try std.testing.expect(!state.settings_controller.browser_scroll_speed_drag_active);
    try std.testing.expect(!updateBrowserScrollSpeedDrag(&state, track.x));
}

test "Companion experimental setting renders one themed immutable toggle row" {
    const allocator = std.testing.allocator;
    defer theme.applyTheme(1.0);
    theme.applyTheme(1.0);

    var state = testSettingsState(allocator);
    defer deinitTestSettingsState(&state, allocator);

    const width: f32 = 1200.0;
    const height: f32 = 900.0;
    const layout = computeLayout(&state, width, height);
    try std.testing.expect(layout.companion_toggle.w > 0.0);
    try std.testing.expect(layout.companion_toggle.y > layout.theme_dropdown.y);
    try std.testing.expect(!state.settings_controller.draft.companion_enabled);

    registerHits(&state, width, height, captureSettingsHit);
    var companion_hit_count: usize = 0;
    for (state.palette_modal_hits.items) |hit| {
        if (hit.action == .settings_control and hit.index == @intFromEnum(Control.companion_toggle)) {
            companion_hit_count += 1;
            try std.testing.expect(rectContains(hit.rect, layout.companion_toggle.x + 1.0, layout.companion_toggle.y + 1.0));
        }
    }
    try std.testing.expectEqual(@as(usize, 1), companion_hit_count);

    applyControl(&state, @intFromEnum(Control.companion_toggle));
    try std.testing.expect(state.settings_controller.draft.companion_enabled);
    try std.testing.expect(state.app_config.companion_enabled);
    try std.testing.expect(!state.isSettingsDraftDirty());
    applyControl(&state, @intFromEnum(Control.companion_toggle));
    try std.testing.expect(!state.settings_controller.draft.companion_enabled);
    try std.testing.expect(!state.isSettingsDraftDirty());

    state.palette_overlay_batch.clear();
    _ = state.palette_frame_text_arena.reset(.retain_capacity);
    render(&state, width, height);
    var saw_companion = false;
    var saw_badge = false;
    for (state.palette_overlay_batch.commands.items) |command| {
        if (command.kind != .text) continue;
        if (std.mem.eql(u8, command.text, "Companion")) saw_companion = true;
        if (std.mem.eql(u8, command.text, "Experimental")) {
            saw_badge = true;
            try std.testing.expectEqual(paletteColor(textLabel()), command.color);
        }
    }
    try std.testing.expect(saw_companion);
    try std.testing.expect(saw_badge);
}

test "runtimes card registers local row and add-connection hits through settings_runtime_action" {
    const allocator = std.testing.allocator;
    defer theme.applyTheme(1.0);
    theme.applyTheme(1.0);

    var state = testSettingsState(allocator);
    defer deinitTestSettingsState(&state, allocator);

    const width: f32 = 1200.0;
    const height: f32 = 900.0;
    state.settings_controller.active_category = .connections;
    const layout = computeLayout(&state, width, height);
    try std.testing.expect(layout.runtimes.card.h > 0.0);
    try std.testing.expect(rectContains(layout.body_clip, layout.runtimes.add_button.x + 1.0, layout.runtimes.add_button.y + 1.0));
    try std.testing.expectEqual(@as(usize, 1), layout.runtimes.row_count);

    state.palette_modal_hits.clearRetainingCapacity();
    registerHits(&state, width, height, captureSettingsHit);
    var saw_local_expand = false;
    var saw_add = false;
    for (state.palette_modal_hits.items) |hit| {
        if (hit.action != .settings_runtime_action) continue;
        const decoded = runtime_connections.decodeRowAction(hit.index) orelse return error.TestUnexpectedResult;
        if (decoded.row == 0 and decoded.action == .expand) saw_local_expand = true;
        if (decoded.action == .add_connection) {
            saw_add = true;
            try std.testing.expect(rectContains(hit.rect, layout.runtimes.add_button.x + 1.0, layout.runtimes.add_button.y + 1.0));
        }
        // Local has no endpoint, token, or trust to edit, forget, or remove.
        try std.testing.expect(decoded.action != .edit and decoded.action != .remove and decoded.action != .forget_token);
    }
    try std.testing.expect(saw_local_expand);
    try std.testing.expect(saw_add);
}

test "clicking outside the settings dialog dismisses it" {
    const allocator = std.testing.allocator;
    defer theme.applyTheme(1.0);
    theme.applyTheme(1.0);

    var state = testSettingsState(allocator);
    defer deinitTestSettingsState(&state, allocator);
    state.sidebar_collapsed = false;
    state.sidebar_hidden = false;

    const width: f32 = 1200.0;
    const height: f32 = 900.0;
    const layout = computeLayout(&state, width, height);
    try std.testing.expect(layout.modal.x > 0.0);
    try std.testing.expect(layout.modal.x + layout.modal.w < width);

    registerHits(&state, width, height, captureSettingsHit);
    try std.testing.expectEqual(
        runtime.PaletteModalAction.modal_dismiss,
        topModalActionAt(&state, layout.modal.x * 0.5, height * 0.5).?,
    );
    try std.testing.expectEqual(
        runtime.PaletteModalAction.modal_dismiss,
        topModalActionAt(&state, layout.modal.x + layout.modal.w + 24.0, height * 0.5).?,
    );
    try std.testing.expect(topModalActionAt(&state, layout.modal.x + 8.0, layout.header.y + layout.header.h * 0.5).? != .modal_dismiss);
    try std.testing.expectEqual(runtime.PaletteModalAction.settings_close, topModalActionAt(&state, layout.close.x + 1.0, layout.close.y + 1.0).?);
}
