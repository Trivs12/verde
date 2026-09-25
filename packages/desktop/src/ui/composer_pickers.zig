//! Renders the composer-owned popovers: the model & settings menu with its
//! Effort / Access / Model submenus, the rich model picker, the working
//! directory picker, and the run-configuration panel (reasoning / speed /
//! access steppers).

const std = @import("std");

const palette = @import("palette");

const native_state = @import("../state.zig");
const theme = @import("theme.zig");

const log = std.log.scoped(.composer_pickers);

const AppState = native_state.AppState;

pub fn render(state: *AppState) void {
    renderComposerSettingsMenu(state);
    renderSettingsOptionPicker(state);
    renderModelPicker(state);
    renderDirectoryPicker(state);
    renderRuntimePicker(state);
    renderRunConfigPopover(state);
}

/// codicon-chevron-right: trailing affordance on submenu rows.
const NF_COD_CHEVRON_RIGHT = "\u{EAB6}";
const SETTINGS_MENU_FONT_SIZE: f32 = 14.5;
const SETTINGS_MENU_CORNER_RADIUS: f32 = 12.0;
const SETTINGS_MENU_ROW_RADIUS: f32 = 8.0;
const SETTINGS_MENU_ROW_PAD_X: f32 = 10.0;
const SETTINGS_MENU_CHEVRON_SIZE: f32 = 12.0;
/// Gap between a row's muted value text and its chevron.
const SETTINGS_MENU_VALUE_GAP: f32 = 6.0;
/// Fast row switch: track and knob inset.
const SETTINGS_SWITCH_WIDTH: f32 = 30.0;
const SETTINGS_SWITCH_HEIGHT: f32 = 18.0;
const SETTINGS_SWITCH_KNOB_INSET: f32 = 2.0;

// Renders the model & settings menu above the merged model label: row
// titles on the left, muted current values and chevrons (or the Fast
// switch) on the right, and a hairline before the Model row.
fn renderComposerSettingsMenu(state: *AppState) void {
    if (!state.composer_controller.settings_open) return;
    const layout = state.layoutComposerSettingsMenu();
    if (layout.count == 0 or layout.panel.w <= 0.0) return;

    const batch = &state.palette_overlay_batch;
    const previous_z = batch.setZIndex(native_state.COMPOSER_SETTINGS_MENU_Z);
    defer batch.restoreZIndex(previous_z);
    const allocator = state.allocator;
    const radius = theme.scaledUi(SETTINGS_MENU_CORNER_RADIUS);

    // The renderer has no blur; two offset translucent rounded rects give
    // the panel a soft drop shadow.
    const shadow_steps = [_]struct { grow: f32, drop: f32, alpha: f32 }{
        .{ .grow = 6.0, .drop = 6.0, .alpha = 0.10 },
        .{ .grow = 2.0, .drop = 3.0, .alpha = 0.14 },
    };
    for (shadow_steps) |step| {
        const grow = theme.scaledUi(step.grow);
        batch.roundedRect(allocator, .{
            .x = layout.panel.x - grow,
            .y = layout.panel.y - grow + theme.scaledUi(step.drop),
            .w = layout.panel.w + grow * 2.0,
            .h = layout.panel.h + grow * 2.0,
        }, .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = step.alpha }, radius + grow) catch {};
    }
    batch.panel(
        allocator,
        layout.panel,
        paletteColor(theme.COLOR_PANEL_ALT),
        paletteColor(theme.restingEdge()),
        radius,
        @max(theme.scaledUi(1.0), 1.0),
    ) catch |err| {
        log.warn("failed to render settings menu panel: {s}", .{@errorName(err)});
        return;
    };
    if (layout.divider.h > 0.0) batch.rect(allocator, layout.divider, paletteColor(theme.restingEdge())) catch {};

    const font_size = theme.scaledUi(SETTINGS_MENU_FONT_SIZE);
    const line_h = font_size * 1.25;
    const pad_x = theme.scaledUi(SETTINGS_MENU_ROW_PAD_X);
    const thread = state.currentThread();
    for (layout.kinds[0..layout.count], 0..) |kind, index| {
        const row = layout.rows[index];
        const submenu_row = if (kind.submenu()) |submenu| state.composer_controller.settings_submenu == submenu else false;
        if (state.composer_controller.settings_focused_row == index or submenu_row) {
            batch.roundedRect(allocator, row, paletteColor(theme.withAlpha(theme.COLOR_WHITE, 16)), theme.scaledUi(SETTINGS_MENU_ROW_RADIUS)) catch {};
        }
        const text_y = row.y + (row.h - line_h) * 0.5;
        const title = settingsRowTitle(kind);
        const title_w = native_state.paletteUiTextPrefixWidth(title, font_size, title.len);
        // Titles are static literals, so they outlive the batch.
        batch.roleText(allocator, .{ .x = row.x + pad_x, .y = text_y, .w = title_w + theme.scaledUi(2.0), .h = line_h }, title, paletteColor(theme.COLOR_WHITE), font_size, .ui, null, row) catch {};

        const right = row.x + row.w - pad_x;
        if (kind == .fast) {
            renderSettingsSwitch(state, row, right, thread.fast_mode == .on);
            continue;
        }
        const chevron = theme.scaledUi(SETTINGS_MENU_CHEVRON_SIZE);
        const chevron_rect: palette.Rect = .{ .x = @round(right - chevron), .y = @round(row.y + (row.h - chevron) * 0.5), .w = chevron, .h = chevron };
        batch.roleText(allocator, chevron_rect, NF_COD_CHEVRON_RIGHT, paletteColor(theme.COLOR_TEXT_MUTED), chevron, .icon, null, row) catch {};

        // Current value, right-aligned before the chevron; a long model name
        // keeps its start visible and clips at the title.
        const value = switch (kind) {
            .effort => state.currentComposerReasoningLabel(),
            .access => state.currentComposerAccessLabel(),
            .model => state.currentComposerModelLabel(),
            .fast => unreachable,
        };
        const value_right = chevron_rect.x - theme.scaledUi(SETTINGS_MENU_VALUE_GAP);
        const value_left = row.x + pad_x + title_w + pad_x;
        if (value.len == 0 or value_right <= value_left) continue;
        const value_w = native_state.paletteUiTextPrefixWidth(value, font_size, value.len);
        const value_x = @max(value_right - value_w, value_left);
        const value_clip: palette.Rect = .{ .x = value_left, .y = row.y, .w = value_right - value_left, .h = row.h };
        batch.roleText(allocator, .{ .x = value_x, .y = text_y, .w = value_w + theme.scaledUi(2.0), .h = line_h }, stableText(state, value), paletteColor(theme.COLOR_TEXT_SUBTLE), font_size, .ui, null, value_clip) catch {};
    }
}

// Draws the Fast row's on/off switch right-aligned at `right`.
fn renderSettingsSwitch(state: *AppState, row: palette.Rect, right: f32, on: bool) void {
    const batch = &state.palette_overlay_batch;
    const w = theme.scaledUi(SETTINGS_SWITCH_WIDTH);
    const h = theme.scaledUi(SETTINGS_SWITCH_HEIGHT);
    const track: palette.Rect = .{ .x = @round(right - w), .y = @round(row.y + (row.h - h) * 0.5), .w = @round(w), .h = @round(h) };
    const track_color = if (on) theme.COLOR_GREEN else theme.withAlpha(theme.COLOR_WHITE, 40);
    batch.roundedRect(state.allocator, track, paletteColor(track_color), track.h * 0.5) catch {};
    const inset = theme.scaledUi(SETTINGS_SWITCH_KNOB_INSET);
    const knob = track.h - inset * 2.0;
    const knob_x = if (on) track.x + track.w - inset - knob else track.x + inset;
    const knob_color = if (on) theme.foregroundOn(theme.COLOR_GREEN) else theme.COLOR_TEXT_MUTED;
    batch.roundedRect(state.allocator, .{ .x = knob_x, .y = track.y + inset, .w = knob, .h = knob }, paletteColor(knob_color), knob * 0.5) catch {};
}

fn settingsRowTitle(kind: native_state.ComposerSettingsRow) []const u8 {
    return switch (kind) {
        .fast => "Fast",
        .effort => "Effort",
        .access => "Access",
        .model => "Model",
    };
}

fn stableText(state: *AppState, value: []const u8) []const u8 {
    return state.palette_frame_text_arena.allocator().dupe(u8, value) catch "";
}

// Renders the Effort / Access submenu beside the settings menu.
fn renderSettingsOptionPicker(state: *AppState) void {
    if (!state.composer_controller.settings_option_picker.isOpen()) return;
    state.syncSettingsOptionPicker();
    state.composer_controller.settings_option_picker.render(state.allocator, &state.palette_overlay_batch) catch |err| {
        log.warn("failed to render settings option picker: {s}", .{@errorName(err)});
    };
}

// Renders the retained working-directory picker anchored to the composer
// directory pill. Entries are rebuilt once on open; only the anchor tracks
// the toolbar while the popover stays up.
fn renderRuntimePicker(state: *AppState) void {
    if (!state.composer_controller.runtime_picker.isOpen()) return;
    state.setPaletteRuntimePickerBoundsFromToolbar();
    state.composer_controller.runtime_picker.render(state.allocator, &state.palette_overlay_batch) catch |err| {
        log.warn("failed to render runtime picker: {s}", .{@errorName(err)});
    };
}

fn renderDirectoryPicker(state: *AppState) void {
    if (!state.composer_controller.directory_picker.isOpen()) return;
    state.setPaletteDirectoryPickerBoundsFromToolbar();
    state.composer_controller.directory_picker.render(state.allocator, &state.palette_overlay_batch) catch |err| {
        log.warn("failed to render composer directory picker: {s}", .{@errorName(err)});
    };
}

// Renders the retained rich model picker anchored to the composer model pill.
fn renderModelPicker(state: *AppState) void {
    // Syncing rebuilds the entry list; skip the work entirely while closed
    // (openPaletteModelPicker syncs before opening).
    if (!state.composer_controller.model_picker.isOpen()) return;
    state.syncPaletteModelPicker();
    state.composer_controller.model_picker.render(state.allocator, &state.palette_overlay_batch) catch |err| {
        log.warn("failed to render composer model picker: {s}", .{@errorName(err)});
    };
}

fn paletteColor(color: [4]f32) palette.Color {
    return .{ .r = color[0], .g = color[1], .b = color[2], .a = color[3] };
}

fn runConfigRowTitle(layout: AppState.RunConfigLayout, index: usize) []const u8 {
    return switch (layout.row_kinds[index]) {
        .reasoning => "Reasoning",
        .speed => "Speed",
        .access => "Access",
    };
}

// Renders the run-configuration popover above the composer run pill: a panel
// of stepped controls consolidating reasoning effort, speed, and access.
fn renderRunConfigPopover(state: *AppState) void {
    if (!state.composer_controller.run_config_open) return;
    state.syncRunConfigSteppers();
    state.tickRunConfigSteppers();
    const layout = state.layoutRunConfigPopover();
    if (layout.row_count == 0 or layout.panel.w <= 0.0) return;

    const batch = &state.palette_overlay_batch;
    const previous_z = batch.setZIndex(native_state.COMPOSER_RUN_CONFIG_Z);
    defer batch.restoreZIndex(previous_z);

    batch.panel(
        state.allocator,
        layout.panel,
        paletteColor(theme.COLOR_PANEL_ALT),
        paletteColor(theme.COLOR_PANEL_MUTED),
        theme.scaledUi(14.0),
        @max(theme.scaledUi(1.0), 1.0),
    ) catch |err| {
        log.warn("failed to render run config panel: {s}", .{@errorName(err)});
        return;
    };

    var index: usize = 0;
    while (index < layout.row_count) : (index += 1) {
        const title_rect = layout.title_rects[index];
        const focused = index == state.composer_controller.run_config_focused_row;
        // The focused row title brightens so keyboard users can tell which
        // stepper left/right arrows will adjust.
        const title_color = if (focused) theme.COLOR_WHITE else theme.COLOR_TEXT_MUTED;
        // Row titles are static literals, so they outlive the batch without a
        // frame-arena copy.
        batch.roleText(
            state.allocator,
            title_rect,
            runConfigRowTitle(layout, index),
            paletteColor(title_color),
            theme.scaledUi(12.5),
            .ui,
            null,
            layout.panel,
        ) catch {};
        const stepper = &state.composer_controller.run_steppers[@intFromEnum(layout.row_kinds[index])];
        stepper.render(state.allocator, batch) catch |err| {
            log.warn("failed to render run config stepper: {s}", .{@errorName(err)});
        };
    }
}
