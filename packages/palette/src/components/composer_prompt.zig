//! Renderer-neutral command prompt/composer visual model.

const std = @import("std");

const draw = @import("../draw.zig");
const clipboard = @import("../input/clipboard.zig");
const key_input = @import("../input/key.zig");
const scroll = @import("../scroll.zig");
const selection_input = @import("../input/selection.zig");
const sdl = @import("../sdl.zig");
const text_layout = @import("../text_layout.zig");

pub const ComposerPromptConfig = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    width: f32 = 640.0,
    height: f32 = 172.0,
    padding_x: f32 = 18.0,
    padding_y: f32 = 16.0,
    toolbar_height: f32 = 36.0,
    toolbar_gap: f32 = 8.0,
    /// When set (and the directory pill is shown), the framed editor keeps
    /// the model/run/send toolbar inside it while the directory pill renders
    /// on its own strip underneath the frame, still within `bounds`.
    directory_outside: bool = false,
    /// Horizontal inset of the outside directory strip relative to the frame
    /// edge, in CSS units; keeps the pill from kissing the frame corner.
    directory_outside_inset_x: f32 = 4.0,
    /// Opt-in single-row layout: while the draft fits on one line (and holds
    /// no newline) the prompt text shares one slim bar with the right-aligned
    /// toolbar cluster. Longer drafts stack the text above a toolbar row that
    /// keeps the bar's bottom edge and control positions.
    inline_toolbar: bool = false,
    /// Frame corner radius while the single-row bar is active.
    inline_corner_radius: f32 = 22.0,
    /// Narrowest inline text column; narrower composers always stack.
    inline_min_text_width: f32 = 140.0,
    /// Draws the model and run pills as one right-aligned ghost label:
    /// `[icon] Model detail ⌄`. The name half still hit-tests as `.model` and
    /// the detail + chevron half as `.reasoning`, so hosts keep their popover
    /// anchors; with the reasoning toggle hidden the whole label is `.model`
    /// and no detail words draw. The fast/access pills are not drawn in this
    /// mode.
    merged_model_label: bool = false,
    /// Host-drawn leading icon cell and gap in the merged label; fall back to
    /// `pill_overlay_icon_reserve` / `pill_icon_gap`.
    merged_icon_reserve: ?f32 = null,
    merged_icon_gap: ?f32 = null,
    /// Renders the outside directory strip as small muted text chips instead
    /// of full toolbar pills.
    strip_chips: bool = false,
    /// Outside strip height; falls back to `toolbar_height`.
    strip_height: ?f32 = null,
    /// Strip chip label size; falls back to `toolbar_font_size`.
    strip_font_size: ?f32 = null,
    strip_padding_x: ?f32 = null,
    /// Host-drawn icon cell and gap in strip chips; fall back to
    /// `pill_overlay_icon_reserve` / `pill_icon_gap`.
    strip_icon_reserve: ?f32 = null,
    strip_icon_gap: ?f32 = null,
    strip_chevron: bool = true,
    /// `running_only` hides the send button while idle (Enter still
    /// submits) and shows it only as the stop / pending control; the
    /// toolbar reclaims its width.
    send_button: ComposerPromptSendButton = .always,
    control_gap: f32 = 8.0,
    separator_width: f32 = 1.0,
    corner_radius: f32 = 14.0,
    border_width: f32 = 1.0,
    background_color: draw.Color = .{ .r = 0.10, .g = 0.13, .b = 0.14, .a = 1.0 },
    border_color: draw.Color = .{ .r = 0.25, .g = 0.31, .b = 0.34, .a = 1.0 },
    /// Border color when the composer is focused. Falls back to `border_color`
    /// when null. Host wires this to the app's brand color so the prompt box
    /// glows in the brand hue while the user is typing.
    focus_border_color: ?draw.Color = null,
    focus_border_width: ?f32 = null,
    control_background_color: draw.Color = .{ .r = 0.07, .g = 0.09, .b = 0.10, .a = 0.0 },
    control_hover_color: draw.Color = .{ .r = 0.18, .g = 0.22, .b = 0.24, .a = 0.62 },
    separator_color: draw.Color = .{ .r = 0.48, .g = 0.52, .b = 0.58, .a = 0.35 },
    send_color: draw.Color = .{ .r = 0.32, .g = 0.54, .b = 0.39, .a = 1.0 },
    send_hover_color: draw.Color = .{ .r = 0.38, .g = 0.64, .b = 0.47, .a = 1.0 },
    send_foreground_color: draw.Color = draw.Color.white,
    stop_button_color: draw.Color = .{ .r = 0.78, .g = 0.58, .b = 0.10, .a = 1.0 },
    stop_button_hover_color: draw.Color = .{ .r = 0.90, .g = 0.68, .b = 0.14, .a = 1.0 },
    stop_foreground_color: draw.Color = draw.Color.white,
    text_color: draw.Color = draw.Color.white,
    placeholder_color: draw.Color = .{ .r = 0.58, .g = 0.62, .b = 0.68, .a = 0.82 },
    icon_color: draw.Color = .{ .r = 0.78, .g = 0.82, .b = 0.88, .a = 1.0 },
    /// Merged-label detail words; falls back to `icon_color`.
    muted_text_color: ?draw.Color = null,
    font_size: f32 = 16.0,
    toolbar_font_size: f32 = 14.0,
    icon_font_size: f32 = 16.0,
    fixed_advance: ?f32 = null,
    toolbar_fixed_advance: ?f32 = null,
    icon_fixed_advance: ?f32 = null,
    font_role: ?draw.FontRole = .ui,
    bold_font_role: ?draw.FontRole = .ui_bold,
    icon_font_role: ?draw.FontRole = .icon,
    font_id: ?u32 = null,
    icon_font_id: ?u32 = null,
    placeholder: []const u8 = "Ask anything, or use / to show available commands",
    /// Leading working-directory pill; hidden until the host opts in with
    /// `setShowDirectoryToggle` so non-chat composers keep their layout.
    /// Hosts that reserve a leading overlay cell draw the folder glyph
    /// themselves and leave this empty.
    directory_icon: []const u8 = "",
    directory_label: []const u8 = "Project",
    model_icon: []const u8 = "O",
    model_label: []const u8 = "GPT-5.5",
    reasoning_label: []const u8 = "Low",
    fast_icon: []const u8 = "~",
    fast_label: []const u8 = "Fast",
    access_icon: []const u8 = "L",
    access_label: []const u8 = "Full access",
    chevron_icon: []const u8 = ">",
    /// Draw `chevron_icon` from the icon font instead of the built-in filled
    /// disclosure triangle. Off by default so existing hosts keep the arrow.
    chevron_glyph: bool = false,
    /// Size of the `chevron_glyph` icon relative to `icon_font_size`.
    chevron_glyph_scale: f32 = 1.0,
    send_icon: []const u8 = "^",
    stop_icon: []const u8 = "x",
    pending_icon: []const u8 = ".",
    cursor_color: draw.Color = draw.Color.white,
    selection_color: draw.Color = .{ .r = 0.18, .g = 0.42, .b = 0.72, .a = 0.55 },
    scrollbar_track_color: draw.Color = .{ .r = 0.18, .g = 0.20, .b = 0.23, .a = 0.42 },
    scrollbar_thumb_color: draw.Color = .{ .r = 0.62, .g = 0.70, .b = 0.82, .a = 0.78 },
    scrollbar_width: f32 = 4.0,
    scroll_enabled: bool = true,
    menu_background_color: draw.Color = .{ .r = 0.07, .g = 0.09, .b = 0.10, .a = 0.98 },
    menu_border_color: draw.Color = .{ .r = 0.25, .g = 0.31, .b = 0.34, .a = 1.0 },
    menu_selected_color: draw.Color = .{ .r = 0.18, .g = 0.34, .b = 0.44, .a = 0.85 },
    menu_hover_color: draw.Color = .{ .r = 0.22, .g = 0.27, .b = 0.30, .a = 0.85 },
    /// Max rows shown for model/reasoning dropdowns before clipping.
    menu_max_visible_rows: f32 = 14.0,
    row_height: f32 = 28.0,
    pill_padding_x: f32 = 10.0,
    pill_icon_gap: f32 = 7.0,
    pill_chevron_gap: f32 = 8.0,
    directory_min_width: f32 = 0.0,
    directory_max_width: f32 = 160.0,
    /// Trailing runtime pill on the outside directory strip (Local/Remote);
    /// hidden until the host opts in with `setShowRuntimeToggle`.
    runtime_icon: []const u8 = "",
    runtime_label: []const u8 = "Local",
    runtime_min_width: f32 = 0.0,
    runtime_max_width: f32 = 160.0,
    model_min_width: f32 = 0.0,
    model_max_width: f32 = 180.0,
    reasoning_min_width: f32 = 0.0,
    reasoning_max_width: f32 = 150.0,
    fast_min_width: f32 = 0.0,
    fast_max_width: f32 = 120.0,
    access_min_width: f32 = 0.0,
    access_max_width: f32 = 170.0,
    /// When > 0, model / fast / access pills reserve this width (plus `pill_icon_gap`) for leading
    /// toolbar glyphs drawn outside text metrics (e.g. textures in the host). Skips rendering
    /// `model_icon` / `fast_icon` / `access_icon` text when those strings are empty.
    /// Should be about `toolbar_icon_drawn_width + gap_after_icon - pill_icon_gap` (see host overlay).
    pill_overlay_icon_reserve: f32 = 0.0,
    /// Extra horizontal room for toolbar pill labels (bold vs measured regular advances, shaping, etc.).
    pill_label_width_fudge: f32 = 0.0,
    z_index: i32 = 0,
};

pub const ComposerPromptStyle = struct {
    background_color: draw.Color,
    border_color: draw.Color,
    focus_border_color: ?draw.Color,
    focus_border_width: ?f32,
    control_background_color: draw.Color,
    control_hover_color: draw.Color,
    separator_color: draw.Color,
    send_color: draw.Color,
    send_hover_color: draw.Color,
    send_foreground_color: draw.Color,
    stop_button_color: draw.Color,
    stop_button_hover_color: draw.Color,
    stop_foreground_color: draw.Color,
    text_color: draw.Color,
    placeholder_color: draw.Color,
    icon_color: draw.Color,
    /// Merged-label detail words; null falls back to `icon_color`.
    muted_text_color: ?draw.Color = null,
    cursor_color: draw.Color,
    selection_color: draw.Color,
    scrollbar_track_color: draw.Color,
    scrollbar_thumb_color: draw.Color,
    menu_background_color: draw.Color,
    menu_border_color: draw.Color,
    menu_selected_color: draw.Color,
    menu_hover_color: draw.Color,
};

pub const ComposerPromptPart = enum {
    directory,
    runtime,
    model,
    reasoning,
    fast,
    access,
    send,
};

pub const ComposerPromptSendState = enum {
    send,
    stop,
    disabled,
    pending,
};

/// When the toolbar shows the round send/stop button; see
/// `ComposerPromptConfig.send_button`.
pub const ComposerPromptSendButton = enum {
    always,
    running_only,
};

pub const ComposerPromptOptionTarget = enum {
    model,
    reasoning,
};

pub const ComposerPromptOptionLabelFn = *const fn (context: ?*anyopaque, index: usize) []const u8;

/// Upper bound on host-reserved icon cells inside the reasoning/run pill
/// label; sized for one glyph per summary segment (speed, access, spare).
pub const MAX_PILL_ICON_SLOTS = 3;

/// One host-drawn glyph cell inside the reasoning/run pill label. The cell is
/// inserted before the label byte at `byte_offset`, so the glyph sits beside
/// the segment it describes instead of stacking at the front of the pill.
pub const ComposerPromptIconSlot = struct {
    byte_offset: usize,
    /// Cell width in the same units as `pill_overlay_icon_reserve`; includes
    /// the gap the host wants between the glyph and the following text.
    width: f32,
};

/// Resolved screen rects for the reserved icon cells, in the same coordinate
/// space as `reasoningRect()`. Cells clipped away with a truncated label are
/// omitted so hosts never draw glyphs outside the pill.
pub const ComposerPromptIconSlotRects = struct {
    rects: [MAX_PILL_ICON_SLOTS]draw.Rect = undefined,
    count: usize = 0,
};

/// Full resolved layout of a composer for a given bounds rect; see
/// `previewGeometry`. Zero-width rects mark controls that are not shown.
pub const ComposerPromptGeometry = struct {
    frame: draw.Rect,
    text: draw.Rect,
    toolbar: draw.Rect,
    strip: draw.Rect,
    directory: draw.Rect,
    runtime: draw.Rect,
    model: draw.Rect,
    reasoning: draw.Rect,
    fast: draw.Rect,
    access: draw.Rect,
    send: draw.Rect,
    /// Host-drawn leading icon cells (provider logo, folder, runtime).
    model_icon: draw.Rect,
    directory_icon: draw.Rect,
    runtime_icon: draw.Rect,
    /// Label cells: merged model name / detail words / chevron, and the
    /// strip chip labels. Zero width outside the matching mode.
    model_text: draw.Rect,
    detail_text: draw.Rect,
    chevron: draw.Rect,
    directory_text: draw.Rect,
    runtime_text: draw.Rect,
    corner_radius: f32,
    inline_active: bool,
};

/// Label overrides for `previewGeometry`, so an unfocused pane's preview is
/// laid out for its own thread's labels instead of the live composer's.
pub const ComposerPromptPreviewLabels = struct {
    model: ?[]const u8 = null,
    detail: ?[]const u8 = null,
    directory: ?[]const u8 = null,
    runtime: ?[]const u8 = null,
    /// The preview's own send state, so a `running_only` send button
    /// matches that pane's turn instead of the live composer's.
    send_state: ?ComposerPromptSendState = null,
};

pub const ComposerPromptInput = union(enum) {
    text: []const u8,
    key: key_input,
    mouse_move: draw.Vec2,
    mouse_down: draw.Vec2,
    mouse_drag: draw.Vec2,
    mouse_up: draw.Vec2,
    mouse_wheel: MouseWheel,
    focus: bool,
};

const SanitizedText = struct {
    value: []const u8,
    owned: []u8 = &.{},

    fn deinit(self: SanitizedText, allocator: std.mem.Allocator) void {
        if (self.owned.len > 0) allocator.free(self.owned);
    }

    fn items(self: SanitizedText) []const u8 {
        return if (self.owned.len > 0) self.owned else self.value;
    }
};

fn sanitizedText(allocator: std.mem.Allocator, value: []const u8, allow_newlines: bool) !SanitizedText {
    if (value.len == 0) return .{ .value = value };
    var sanitized: std.ArrayList(u8) = .empty;
    errdefer sanitized.deinit(allocator);
    var changed = false;
    var index: usize = 0;
    while (index < value.len) {
        const byte = value[index];
        if (byte == '\r' or (byte == '\n' and !allow_newlines) or (byte < 0x20 and byte != '\t' and byte != '\n')) {
            changed = true;
            index += 1;
            continue;
        }
        const len = std.unicode.utf8ByteSequenceLength(byte) catch {
            changed = true;
            index += 1;
            continue;
        };
        if (index + len > value.len) {
            changed = true;
            break;
        }
        const slice = value[index .. index + len];
        const cp = std.unicode.utf8Decode(slice) catch {
            changed = true;
            index += len;
            continue;
        };
        if (cp == 0xfffd or cp == 0x7f or (cp >= 0x80 and cp <= 0x9f)) {
            changed = true;
            index += len;
            continue;
        }
        try sanitized.appendSlice(allocator, slice);
        index += len;
    }
    if (!changed) {
        sanitized.deinit(allocator);
        return .{ .value = value };
    }
    return .{ .value = value, .owned = try sanitized.toOwnedSlice(allocator) };
}

pub const MouseWheel = struct {
    point: draw.Vec2,
    y: f32,
};

const MAX_EDIT_HISTORY = 64;

const EditSnapshot = struct {
    text: []u8,
    cursor: usize,
    selection_anchor: ?usize,
    selection_focus: ?usize,

    fn capture(allocator: std.mem.Allocator, component: anytype) !EditSnapshot {
        return .{
            .text = try allocator.dupe(u8, component.buffer.items),
            .cursor = component.cursor,
            .selection_anchor = component.selection_anchor,
            .selection_focus = component.selection_focus,
        };
    }

    fn deinit(self: EditSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
    }
};

pub const ComposerPromptEvent = union(enum) {
    text_changed: []const u8,
    submitted: []const u8,
    directory_clicked,
    runtime_clicked,
    model_clicked,
    model_changed: usize,
    reasoning_clicked,
    reasoning_changed: usize,
    fast_changed: bool,
    access_changed: bool,
    send_clicked,
    focus_changed: bool,
};

pub const ComposerPromptCallbacks = struct {
    context: ?*anyopaque = null,
    on_event: ?*const fn (context: ?*anyopaque, event: ComposerPromptEvent) void = null,
    set_clipboard: ?*const fn (context: ?*anyopaque, text: []const u8) bool = null,
    get_clipboard: ?*const fn (context: ?*anyopaque, allocator: std.mem.Allocator) ?[]u8 = null,

    fn clipboardProvider(self: ComposerPromptCallbacks) clipboard {
        return .{ .context = self.context, .set = self.set_clipboard, .get = self.get_clipboard };
    }
};

const Options = struct {
    context: ?*anyopaque = null,
    count: usize = 0,
    label: ?ComposerPromptOptionLabelFn = null,

    fn labelFor(self: Options, index: usize) ?[]const u8 {
        if (index >= self.count) return null;
        if (self.label) |callback| return callback(self.context, index);
        return null;
    }
};

pub fn ComposerPrompt(comptime config: ComposerPromptConfig) type {
    return struct {
        const Component = @This();
        pub const Style = ComposerPromptStyle;

        rect: draw.Rect = .{ .x = config.x, .y = config.y, .w = config.width, .h = config.height },
        style: Style = defaultStyle(),
        buffer: std.ArrayList(u8) = .empty,
        cursor: usize = 0,
        selection_anchor: ?usize = null,
        selection_focus: ?usize = null,
        scroll_y: f32 = 0.0,
        dragging_selection: bool = false,
        placeholder_buffer: std.ArrayList(u8) = .empty,
        directory_label_buffer: std.ArrayList(u8) = .empty,
        runtime_label_buffer: std.ArrayList(u8) = .empty,
        model_label_buffer: std.ArrayList(u8) = .empty,
        /// Muted variant words after the model name in the merged label.
        model_detail_label_buffer: std.ArrayList(u8) = .empty,
        reasoning_label_buffer: std.ArrayList(u8) = .empty,
        fast_label_buffer: std.ArrayList(u8) = .empty,
        access_label_buffer: std.ArrayList(u8) = .empty,
        model_options: Options = .{},
        reasoning_options: Options = .{},
        /// Only set on the throwaway copy `previewGeometry` lays out.
        preview_labels: ComposerPromptPreviewLabels = .{},
        model_index: ?usize = null,
        reasoning_index: ?usize = null,
        active_menu: ?ComposerPromptOptionTarget = null,
        hovered_menu_index: ?usize = null,
        menu_scroll_y: f32 = 0.0,
        hovered_part: ?ComposerPromptPart = null,
        focused: bool = false,
        show_directory_toggle: bool = false,
        show_runtime_toggle: bool = false,
        show_fast_toggle: bool = true,
        show_reasoning_toggle: bool = true,
        show_access_toggle: bool = true,
        /// When set, clicking the model / reasoning pill emits `model_clicked` /
        /// `reasoning_clicked` without opening the built-in dropdown, so hosts
        /// can attach richer popovers (rich picker, run-config panel) instead.
        external_model_menu: bool = false,
        external_reasoning_menu: bool = false,
        /// Host-drawn glyph cells embedded in the reasoning/run pill label
        /// (fast bolt beside the speed word, lock beside the access word).
        /// Sorted by byte offset; only the first `reasoning_icon_slot_count`
        /// entries are live.
        reasoning_icon_slots: [MAX_PILL_ICON_SLOTS]ComposerPromptIconSlot = undefined,
        reasoning_icon_slot_count: usize = 0,
        fast_enabled: bool = false,
        access_enabled: bool = false,
        send_state: ComposerPromptSendState = .send,
        /// Host-owned popover anchored to the merged label is open; keeps
        /// the label's hover fill while the pointer is over the popover.
        label_active: bool = false,
        stop_pulse_factor: f32 = 1.0,
        undo_stack: std.ArrayList(EditSnapshot) = .empty,
        redo_stack: std.ArrayList(EditSnapshot) = .empty,
        font_metrics: ?text_layout.FontMetrics = null,
        toolbar_font_metrics: ?text_layout.FontMetrics = null,
        icon_font_metrics: ?text_layout.FontMetrics = null,
        /// DPI multiplier applied to every geometry token in the config, so
        /// pill padding / icon reserves / min-max widths track the scaled
        /// font metrics and host-drawn glyphs instead of staying CSS-sized.
        ui_scale: f32 = 1.0,
        z_index: i32 = config.z_index,
        callbacks: ComposerPromptCallbacks = .{},

        pub fn setShowReasoningToggle(self: *Component, show: bool) void {
            self.show_reasoning_toggle = show;
            if (!show) {
                self.hovered_part = if (self.hovered_part == .reasoning) null else self.hovered_part;
                self.active_menu = if (self.active_menu == .reasoning) null else self.active_menu;
            }
        }

        pub fn showReasoningToggle(self: *const Component) bool {
            return self.show_reasoning_toggle;
        }

        /// Reserves host-drawn glyph cells inside the run pill label. Slots
        /// must be sorted by ascending byte offset; offsets past the current
        /// label clamp to its end when the cells are laid out.
        pub fn setReasoningIconSlots(self: *Component, slots: []const ComposerPromptIconSlot) void {
            const count = @min(slots.len, MAX_PILL_ICON_SLOTS);
            for (slots[0..count], 0..) |slot, index| {
                self.reasoning_icon_slots[index] = .{
                    .byte_offset = slot.byte_offset,
                    .width = @max(slot.width, 0.0),
                };
            }
            self.reasoning_icon_slot_count = count;
        }

        fn reasoningIconSlots(self: *const Component) []const ComposerPromptIconSlot {
            return self.reasoning_icon_slots[0..self.reasoning_icon_slot_count];
        }

        fn reasoningIconSlotsWidth(self: *const Component) f32 {
            // Slot widths arrive in the config's CSS units; scale them with
            // the rest of the pill geometry so host glyphs keep their cells.
            var total: f32 = 0.0;
            for (self.reasoningIconSlots()) |slot| total += self.scaled(slot.width);
            return total;
        }

        /// Screen rects of the reserved icon cells, mirroring the segment walk
        /// `renderPill` uses to place the label pieces, so host glyphs line up
        /// with the words they annotate even as the label or pill width change.
        pub fn reasoningIconSlotRects(self: *const Component) ComposerPromptIconSlotRects {
            var result: ComposerPromptIconSlotRects = .{};
            // The merged label carries no embedded glyph cells.
            if (!self.show_reasoning_toggle or config.merged_model_label) return result;
            const rect = self.toolbarGeometry().reasoning;
            if (rect.w <= 0.0 or rect.h <= 0.0) return result;
            const label = self.reasoningLabel();
            const metrics = self.toolbarMetrics();
            const label_area_right = rect.x + rect.w - self.scaled(config.pill_padding_x) - self.trailingChevronReserve(config.chevron_icon);
            var x = rect.x + self.scaled(config.pill_padding_x);
            var byte: usize = 0;
            for (self.reasoningIconSlots()) |slot| {
                const offset = @min(slot.byte_offset, label.len);
                if (offset > byte) {
                    x += metrics.measureSlice(label[byte..offset]);
                    byte = offset;
                }
                const cell_w = self.scaled(slot.width);
                // Mid-label cells sit before the separator's leading space
                // (e.g. "High[cell] · Full access"), so a cell-centered glyph
                // hugs its word and floats away from the separator. Nudge the
                // reported rect right by half the following space run so the
                // glyph lands midway between the surrounding ink; the label
                // walk itself is unchanged, this is presentation-only.
                var space_end = byte;
                while (space_end < label.len and label[space_end] == ' ') : (space_end += 1) {}
                const gap_shift = metrics.measureSlice(label[byte..space_end]) * 0.5;
                // A shrunken pill clips the label tail; drop the cells that
                // fall past the clip so the host does not draw over the chevron.
                if (x + gap_shift + cell_w > label_area_right) break;
                result.rects[result.count] = .{ .x = x + gap_shift, .y = rect.y, .w = cell_w, .h = rect.h };
                result.count += 1;
                x += cell_w;
            }
            return result;
        }

        pub fn setShowDirectoryToggle(self: *Component, show: bool) void {
            self.show_directory_toggle = show;
            if (!show) {
                self.hovered_part = if (self.hovered_part == .directory) null else self.hovered_part;
            }
        }

        pub fn showDirectoryToggle(self: *const Component) bool {
            return self.show_directory_toggle;
        }

        pub fn setShowRuntimeToggle(self: *Component, show: bool) void {
            self.show_runtime_toggle = show;
            if (!show) {
                self.hovered_part = if (self.hovered_part == .runtime) null else self.hovered_part;
            }
        }

        pub fn showRuntimeToggle(self: *const Component) bool {
            return self.show_runtime_toggle;
        }

        pub fn setShowFastToggle(self: *Component, show: bool) void {
            self.show_fast_toggle = show;
            if (!show) {
                self.hovered_part = if (self.hovered_part == .fast) null else self.hovered_part;
            }
        }

        pub fn showFastToggle(self: *const Component) bool {
            return self.show_fast_toggle;
        }

        pub fn setShowAccessToggle(self: *Component, show: bool) void {
            self.show_access_toggle = show;
            if (!show) {
                self.hovered_part = if (self.hovered_part == .access) null else self.hovered_part;
            }
        }

        pub fn showAccessToggle(self: *const Component) bool {
            return self.show_access_toggle;
        }

        pub fn setExternalModelMenu(self: *Component, external: bool) void {
            self.external_model_menu = external;
            if (external and self.active_menu == .model) {
                self.active_menu = null;
                self.hovered_menu_index = null;
            }
        }

        pub fn setExternalReasoningMenu(self: *Component, external: bool) void {
            self.external_reasoning_menu = external;
            if (external and self.active_menu == .reasoning) {
                self.active_menu = null;
                self.hovered_menu_index = null;
            }
        }

        pub fn init() Component {
            return .{};
        }

        pub fn defaultStyle() Style {
            return .{
                .background_color = config.background_color,
                .border_color = config.border_color,
                .focus_border_color = config.focus_border_color,
                .focus_border_width = config.focus_border_width,
                .control_background_color = config.control_background_color,
                .control_hover_color = config.control_hover_color,
                .separator_color = config.separator_color,
                .send_color = config.send_color,
                .send_hover_color = config.send_hover_color,
                .send_foreground_color = config.send_foreground_color,
                .stop_button_color = config.stop_button_color,
                .stop_button_hover_color = config.stop_button_hover_color,
                .stop_foreground_color = config.stop_foreground_color,
                .text_color = config.text_color,
                .placeholder_color = config.placeholder_color,
                .icon_color = config.icon_color,
                .muted_text_color = config.muted_text_color,
                .cursor_color = config.cursor_color,
                .selection_color = config.selection_color,
                .scrollbar_track_color = config.scrollbar_track_color,
                .scrollbar_thumb_color = config.scrollbar_thumb_color,
                .menu_background_color = config.menu_background_color,
                .menu_border_color = config.menu_border_color,
                .menu_selected_color = config.menu_selected_color,
                .menu_hover_color = config.menu_hover_color,
            };
        }

        pub fn setStyle(self: *Component, style: Style) void {
            self.style = style;
        }

        pub fn deinit(self: *Component, allocator: std.mem.Allocator) void {
            self.buffer.deinit(allocator);
            self.placeholder_buffer.deinit(allocator);
            self.model_label_buffer.deinit(allocator);
            self.model_detail_label_buffer.deinit(allocator);
            self.reasoning_label_buffer.deinit(allocator);
            self.fast_label_buffer.deinit(allocator);
            self.directory_label_buffer.deinit(allocator);
            self.runtime_label_buffer.deinit(allocator);
            self.access_label_buffer.deinit(allocator);
            self.clearEditHistory(allocator);
            self.undo_stack.deinit(allocator);
            self.redo_stack.deinit(allocator);
            self.* = undefined;
        }

        pub fn setBounds(self: *Component, rect: draw.Rect) void {
            self.rect = rect;
            self.setScrollY(self.scroll_y);
        }

        pub fn bounds(self: *const Component) draw.Rect {
            return self.rect;
        }

        pub fn setCallbacks(self: *Component, callbacks: ComposerPromptCallbacks) void {
            self.callbacks = callbacks;
        }

        /// DPI multiplier for the config's geometry constants; mirrors
        /// `RichPicker.setUiScale`. Hosts that pass display-scaled font
        /// metrics must set the same factor here or pills stay CSS-sized
        /// while their labels and overlay glyphs grow.
        pub fn setUiScale(self: *Component, scale: f32) void {
            self.ui_scale = @max(scale, 0.1);
        }

        fn scaled(self: *const Component, value: f32) f32 {
            return value * self.ui_scale;
        }

        pub fn setFontMetrics(self: *Component, metrics: text_layout.FontMetrics) void {
            self.font_metrics = metrics;
            self.setScrollY(self.scroll_y);
        }

        pub fn setToolbarFontMetrics(self: *Component, metrics: text_layout.FontMetrics) void {
            self.toolbar_font_metrics = metrics;
        }

        pub fn setIconFontMetrics(self: *Component, metrics: text_layout.FontMetrics) void {
            self.icon_font_metrics = metrics;
        }

        pub fn setText(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            const sanitized = try sanitizedText(allocator, value, true);
            defer sanitized.deinit(allocator);
            self.buffer.clearRetainingCapacity();
            try self.buffer.appendSlice(allocator, sanitized.items());
            self.cursor = self.buffer.items.len;
            self.selection_anchor = null;
            self.selection_focus = null;
            self.clearEditHistory(allocator);
            self.ensureCursorVisible();
            self.emit(.{ .text_changed = self.buffer.items });
        }

        pub fn text(self: *const Component) []const u8 {
            return self.buffer.items;
        }

        pub fn selection(self: *const Component) ?selection_input.Range {
            const state: selection_input = .{ .anchor = self.selection_anchor, .focus = self.selection_focus };
            return state.normalized(self.buffer.items.len);
        }

        pub fn scrollY(self: *const Component) f32 {
            return self.scroll_y;
        }

        pub fn setScrollY(self: *Component, value: f32) void {
            self.scroll_y = scroll.clampOffsetY(value, self.scrollMetrics());
        }

        pub fn contentHeight(self: *const Component) f32 {
            return text_layout.contentHeight(self.buffer.items, self.textMetrics(), self.textRect().w, true);
        }

        pub fn maxScrollY(self: *const Component) f32 {
            return scroll.maxOffsetY(self.scrollMetrics());
        }

        pub fn setPlaceholder(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            try setOwnedString(allocator, &self.placeholder_buffer, value);
        }

        pub fn setDirectoryLabel(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            try setOwnedString(allocator, &self.directory_label_buffer, value);
        }

        pub fn setRuntimeLabel(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            try setOwnedString(allocator, &self.runtime_label_buffer, value);
        }

        pub fn setModelLabel(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            try setOwnedString(allocator, &self.model_label_buffer, value);
        }

        /// Muted words shown after the model name in the merged label (e.g.
        /// "High Fast"); clicking them hit-tests as `.reasoning`.
        pub fn setModelDetailLabel(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            try setOwnedString(allocator, &self.model_detail_label_buffer, value);
        }

        pub fn setReasoningLabel(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            try setOwnedString(allocator, &self.reasoning_label_buffer, value);
        }

        pub fn setFastLabel(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            try setOwnedString(allocator, &self.fast_label_buffer, value);
        }

        pub fn setAccessLabel(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            try setOwnedString(allocator, &self.access_label_buffer, value);
        }

        pub fn setSendState(self: *Component, state: ComposerPromptSendState) void {
            self.send_state = state;
        }

        pub fn setLabelActive(self: *Component, active: bool) void {
            self.label_active = active;
        }

        /// Whether the send/stop button takes toolbar space right now.
        pub fn sendVisible(self: *const Component) bool {
            return switch (config.send_button) {
                .always => true,
                .running_only => self.send_state == .stop or self.send_state == .pending,
            };
        }

        /// Sets the host-driven 0..1 breathing emphasis for the stop control.
        pub fn setStopPulseFactor(self: *Component, factor: f32) void {
            self.stop_pulse_factor = @max(0.0, @min(factor, 1.0));
        }

        pub fn setModelOptions(self: *Component, context: ?*anyopaque, count: usize, label: ?ComposerPromptOptionLabelFn) void {
            self.model_options = .{ .context = context, .count = count, .label = label };
            if (self.model_index) |index| {
                if (index >= count) self.model_index = null;
            }
        }

        pub fn setReasoningOptions(self: *Component, context: ?*anyopaque, count: usize, label: ?ComposerPromptOptionLabelFn) void {
            self.reasoning_options = .{ .context = context, .count = count, .label = label };
            if (self.reasoning_index) |index| {
                if (index >= count) self.reasoning_index = null;
            }
        }

        pub fn setOptions(self: *Component, target: ComposerPromptOptionTarget, context: ?*anyopaque, count: usize, label: ?ComposerPromptOptionLabelFn) void {
            switch (target) {
                .model => self.setModelOptions(context, count, label),
                .reasoning => self.setReasoningOptions(context, count, label),
            }
        }

        pub fn handleInput(self: *Component, allocator: std.mem.Allocator, input: ComposerPromptInput) !bool {
            switch (input) {
                .text => |value| {
                    if (!self.focused) return false;
                    try self.insertTextInput(allocator, value);
                    return true;
                },
                .key => |key| return try self.handleKey(allocator, key),
                .mouse_move => |point| {
                    const changed = self.updateHover(point);
                    const previous_index = self.hovered_menu_index;
                    self.hovered_menu_index = self.menuIndexAtPoint(point);
                    return changed or previous_index != self.hovered_menu_index;
                },
                .mouse_down => |point| return try self.handleMouseDown(allocator, point),
                .mouse_drag => |point| return self.handleMouseDrag(point),
                .mouse_up => {
                    const was_dragging = self.dragging_selection;
                    self.dragging_selection = false;
                    return was_dragging;
                },
                .mouse_wheel => |wheel| {
                    if (self.active_menu) |target| {
                        if (self.menuRect(target).contains(wheel.point)) {
                            self.setMenuScrollY(target, self.menu_scroll_y - wheel.y * self.scaled(config.row_height) * 3.0);
                            self.hovered_menu_index = self.menuIndexAtPoint(wheel.point);
                            return true;
                        }
                    }
                    if (!self.textRect().contains(wheel.point)) return false;
                    self.scrollBy(-wheel.y * self.textMetrics().line_height * 3.0);
                    return true;
                },
                .focus => |focused| {
                    const changed = self.focused != focused;
                    self.setFocused(focused);
                    return changed;
                },
            }
        }

        pub fn update(self: *Component, allocator: std.mem.Allocator, event: *const sdl.Event) !bool {
            switch (event.type) {
                .text_input => return try self.handleInput(allocator, .{ .text = std.mem.span(event.text.text) }),
                .key_down => return try self.handleInput(allocator, .{ .key = key_input.fromSdl(event.key) orelse return false }),
                .mouse_motion => {
                    const point: draw.Vec2 = .{ .x = event.motion.x, .y = event.motion.y };
                    if (self.dragging_selection or event.motion.state.left) return try self.handleInput(allocator, .{ .mouse_drag = point });
                    return try self.handleInput(allocator, .{ .mouse_move = point });
                },
                .mouse_button_down => return try self.handleInput(allocator, .{ .mouse_down = .{ .x = event.button.x, .y = event.button.y } }),
                .mouse_button_up => return try self.handleInput(allocator, .{ .mouse_up = .{ .x = event.button.x, .y = event.button.y } }),
                .mouse_wheel => return try self.handleInput(allocator, .{ .mouse_wheel = .{ .point = .{ .x = event.wheel.mouse_x, .y = event.wheel.mouse_y }, .y = event.wheel.y } }),
                else => return false,
            }
        }

        pub fn setSendHovered(self: *Component, hovered: bool) void {
            self.hovered_part = if (hovered) .send else null;
        }

        pub fn setHoveredPart(self: *Component, part: ?ComposerPromptPart) void {
            self.hovered_part = part;
        }

        pub fn updateHover(self: *Component, point: draw.Vec2) bool {
            const previous = self.hovered_part;
            self.hovered_part = self.hitTest(point);
            return previous != self.hovered_part;
        }

        pub fn hitTest(self: *const Component, point: draw.Vec2) ?ComposerPromptPart {
            const geometry = self.toolbarGeometry();
            if (geometry.send.w > 0.0 and geometry.send.contains(point)) return .send;
            if (self.show_directory_toggle and geometry.directory.w > 0.0 and geometry.directory.contains(point)) return .directory;
            if (geometry.runtime.w > 0.0 and geometry.runtime.contains(point)) return .runtime;
            if (geometry.model.contains(point)) return .model;
            if (self.show_reasoning_toggle and geometry.reasoning.w > 0.0 and geometry.reasoning.contains(point)) return .reasoning;
            if (self.show_fast_toggle and geometry.fast.w > 0.0 and geometry.fast.contains(point)) return .fast;
            if (self.show_access_toggle and geometry.access.w > 0.0 and geometry.access.contains(point)) return .access;
            return null;
        }

        fn directoryOutside(self: *const Component) bool {
            return config.directory_outside and self.show_directory_toggle;
        }

        /// The bordered editor panel. Equals `bounds` unless the directory
        /// pill sits outside, in which case the frame stops above its strip.
        pub fn frameRect(self: *const Component) draw.Rect {
            const bounds_rect = self.bounds();
            if (!self.directoryOutside()) return bounds_rect;
            return snapRect(.{
                .x = bounds_rect.x,
                .y = bounds_rect.y,
                .w = bounds_rect.w,
                .h = @max(bounds_rect.h - self.stripReserve(), 0.0),
            });
        }

        /// Strip below the frame that hosts the outside directory pill; zero
        /// height when the pill renders inside the toolbar.
        pub fn directoryStripRect(self: *const Component) draw.Rect {
            const bounds_rect = self.bounds();
            if (!self.directoryOutside()) return snapRect(.{ .x = bounds_rect.x, .y = bounds_rect.y + bounds_rect.h, .w = bounds_rect.w, .h = 0.0 });
            const inset = self.scaled(config.directory_outside_inset_x);
            return snapRect(.{
                .x = bounds_rect.x + inset,
                .y = bounds_rect.y + bounds_rect.h - self.stripHeight(),
                .w = @max(bounds_rect.w - inset * 2.0, 0.0),
                .h = self.stripHeight(),
            });
        }

        /// Bounds height that fits the prompt at `width`, with the text area
        /// clamped to [min_lines, max_lines]. `empty` measures the placeholder
        /// instead of the buffer (inactive previews of this composer).
        pub fn preferredHeight(self: *const Component, width: f32, empty: bool, min_lines: f32, max_lines: f32) f32 {
            const metrics = self.textMetrics();
            const value = if (empty or self.buffer.items.len == 0) self.placeholderText() else self.buffer.items;
            if (config.inline_toolbar) {
                // Same decision as `inlineActive`; the placeholder never
                // forces stacking (it clips inside the inline column).
                if (self.inlineFitsAt(width, if (empty) "" else self.buffer.items)) return @ceil(self.inlineBarHeight() + self.stripReserve());
                const stacked_text_w = @max(width - self.scaled(config.padding_x) * 2.0, 1.0);
                const stacked_content = text_layout.contentHeight(value, metrics, stacked_text_w, true);
                return @ceil(self.scaled(config.padding_y) +
                    std.math.clamp(stacked_content, metrics.line_height * min_lines, metrics.line_height * max_lines) +
                    self.scaled(config.toolbar_gap) + self.scaled(config.toolbar_height) + self.controlInset() +
                    self.stripReserve());
            }
            const text_w = @max(width - self.scaled(config.padding_x) * 2.0, 1.0);
            const content = text_layout.contentHeight(value, metrics, text_w, true);
            const height = self.scaled(config.padding_y) * 2.0 +
                std.math.clamp(content, metrics.line_height * min_lines, metrics.line_height * max_lines) +
                self.scaled(config.toolbar_gap) + self.scaled(config.toolbar_height) +
                self.stripReserve();
            return @ceil(height);
        }

        /// True while the single-row bar is active. The one place the
        /// inline/stacked mode is decided: it reads only the bounds width,
        /// labels and draft (never the current height), so resizing the
        /// bounds to `preferredHeight` cannot flip it back and forth.
        pub fn inlineActive(self: *const Component) bool {
            return self.inlineFitsAt(self.rect.w, self.buffer.items);
        }

        pub fn textRect(self: *const Component) draw.Rect {
            if (config.inline_toolbar) return self.rowLayout(self.frameRect(), self.inlineActive()).text;
            const frame = self.frameRect();
            return snapRect(.{
                .x = frame.x + self.scaled(config.padding_x),
                .y = frame.y + self.scaled(config.padding_y),
                .w = @max(frame.w - self.scaled(config.padding_x) * 2.0, 0.0),
                .h = @max(frame.h - self.scaled(config.padding_y) * 2.0 - self.scaled(config.toolbar_height) - self.scaled(config.toolbar_gap), 0.0),
            });
        }

        pub fn toolbarRect(self: *const Component) draw.Rect {
            if (config.inline_toolbar) return self.rowLayout(self.frameRect(), self.inlineActive()).toolbar;
            const frame = self.frameRect();
            return snapRect(.{
                .x = frame.x + self.scaled(config.padding_x),
                .y = frame.y + frame.h - self.scaled(config.padding_y) - self.scaled(config.toolbar_height),
                .w = @max(frame.w - self.scaled(config.padding_x) * 2.0, 0.0),
                .h = self.scaled(config.toolbar_height),
            });
        }

        /// Frame corner radius for the current mode.
        pub fn cornerRadius(self: *const Component) f32 {
            return self.scaled(if (config.inline_toolbar and self.inlineActive()) config.inline_corner_radius else config.corner_radius);
        }

        /// Pure layout of this composer at `rect` with an empty draft, as the
        /// placeholder preview of an unfocused pane would show it (matches
        /// `preferredHeight(width, true, ...)`). Uses the current metrics and
        /// toggles, `labels` over the live ones, and never mutates the live
        /// component.
        pub fn previewGeometry(self: *const Component, rect: draw.Rect, labels: ComposerPromptPreviewLabels) ComposerPromptGeometry {
            var preview = self.*;
            preview.preview_labels = labels;
            if (labels.send_state) |send_state| preview.send_state = send_state;
            preview.rect = rect;
            preview.buffer = .empty;
            preview.scroll_y = 0.0;
            return preview.layoutGeometry();
        }

        /// Full resolved layout at the current bounds.
        pub fn layoutGeometry(self: *const Component) ComposerPromptGeometry {
            const toolbar = self.toolbarGeometry();
            const zero: draw.Rect = .{ .x = 0.0, .y = 0.0, .w = 0.0, .h = 0.0 };
            const merged = if (config.merged_model_label) self.mergedLabelCells(toolbar.model, toolbar.reasoning) else MergedLabelCells{ .name = zero, .detail = zero, .chevron = zero };
            const chips = config.strip_chips and self.directoryOutside();
            return .{
                .frame = self.frameRect(),
                .text = self.textRect(),
                .toolbar = toolbar.toolbar,
                .strip = self.directoryStripRect(),
                .directory = toolbar.directory,
                .runtime = toolbar.runtime,
                .model = toolbar.model,
                .reasoning = toolbar.reasoning,
                .fast = toolbar.fast,
                .access = toolbar.access,
                .send = toolbar.send,
                .model_icon = self.leadingIconCell(.model, toolbar.model),
                .directory_icon = self.leadingIconCell(.directory, toolbar.directory),
                .runtime_icon = self.leadingIconCell(.runtime, toolbar.runtime),
                .model_text = merged.name,
                .detail_text = merged.detail,
                .chevron = merged.chevron,
                .directory_text = if (chips) self.stripChipTextRect(toolbar.directory) else zero,
                .runtime_text = if (chips) self.stripChipTextRect(toolbar.runtime) else zero,
                .corner_radius = self.cornerRadius(),
                .inline_active = config.inline_toolbar and self.inlineActive(),
            };
        }

        /// Cell reserved for the host-drawn leading glyph of a toolbar
        /// control (provider logo, folder, runtime), centred vertically in it.
        pub fn leadingIconRect(self: *const Component, part: ComposerPromptPart) draw.Rect {
            const toolbar = self.toolbarGeometry();
            const rect = switch (part) {
                .directory => toolbar.directory,
                .runtime => toolbar.runtime,
                .model => toolbar.model,
                .reasoning => toolbar.reasoning,
                .fast => toolbar.fast,
                .access => toolbar.access,
                .send => toolbar.send,
            };
            return self.leadingIconCell(part, rect);
        }

        fn leadingIconCell(self: *const Component, part: ComposerPromptPart, rect: draw.Rect) draw.Rect {
            const chip = config.strip_chips and self.directoryOutside() and (part == .directory or part == .runtime);
            const merged = config.merged_model_label and part == .model;
            const pad = if (chip) self.stripPadX() else self.scaled(config.pill_padding_x);
            const reserve = if (chip) self.stripIconReserve() else if (merged) self.mergedIconReserve() else self.scaled(config.pill_overlay_icon_reserve);
            return .{ .x = rect.x + pad, .y = rect.y + (rect.h - reserve) * 0.5, .w = reserve, .h = reserve };
        }

        fn stripHeight(self: *const Component) f32 {
            return self.scaled(config.strip_height orelse config.toolbar_height);
        }

        /// Vertical room the outside strip takes under the frame, gap
        /// included; shared by `frameRect`, the strip rect and
        /// `preferredHeight` so the three can never disagree.
        fn stripReserve(self: *const Component) f32 {
            if (!self.directoryOutside()) return 0.0;
            return self.stripHeight() + self.scaled(config.toolbar_gap);
        }

        /// Single-row bar height: the taller of the toolbar row and one text
        /// line, with half `padding_y` of air above and below.
        fn inlineBarHeight(self: *const Component) f32 {
            return @max(self.scaled(config.toolbar_height), self.textMetrics().line_height) + self.scaled(config.padding_y);
        }

        /// Right/bottom inset of the toolbar row in `inline_toolbar` layouts.
        /// Stacked mode reuses the inline value so the controls stay put when
        /// the text grows above them.
        fn controlInset(self: *const Component) f32 {
            return @max((self.inlineBarHeight() - self.scaled(config.toolbar_height)) * 0.5, 0.0);
        }

        fn sendSize(self: *const Component, toolbar_h: f32) f32 {
            return @round(@min(toolbar_h, self.scaled(38.0)));
        }

        /// Gap between the send button and the pill it follows, beyond the
        /// shared `control_gap`; the merged label sits flush.
        fn sendOffset(self: *const Component) f32 {
            return if (config.merged_model_label) 0.0 else self.scaled(2.0);
        }

        /// Natural width of the right-aligned inline cluster (controls plus
        /// send button when shown), independent of the current mode.
        fn inlineClusterWidth(self: *const Component) f32 {
            const gap = self.scaled(config.control_gap);
            const send_visible = self.sendVisible();
            const send = if (send_visible) self.sendSize(self.scaled(config.toolbar_height)) + self.sendOffset() else 0.0;
            if (config.merged_model_label) return self.mergedLabelNaturalWidth() + if (send_visible) gap + send else 0.0;
            const model_w = self.pillWidth(true, 0.0, config.model_icon, self.modelLabel(), config.chevron_icon, config.model_min_width, config.model_max_width);
            const reasoning_w: f32 = if (self.show_reasoning_toggle)
                self.pillWidth(false, self.reasoningIconSlotsWidth(), "", self.reasoningLabel(), config.chevron_icon, config.reasoning_min_width, config.reasoning_max_width)
            else
                0.0;
            const fast_w: f32 = if (self.show_fast_toggle) self.pillWidth(true, 0.0, config.fast_icon, self.fastLabel(), "", config.fast_min_width, config.fast_max_width) else 0.0;
            const access_w: f32 = if (self.show_access_toggle) self.pillWidth(true, 0.0, config.access_icon, self.accessLabel(), "", config.access_min_width, config.access_max_width) else 0.0;
            var width = self.toolbarPillsTotalWidth(model_w, reasoning_w, fast_w, access_w) + if (send_visible) gap * 2.0 + send else 0.0;
            if (self.show_directory_toggle and !self.directoryOutside()) {
                width += self.pillWidth(true, 0.0, config.directory_icon, self.directoryLabel(), config.chevron_icon, config.directory_min_width, config.directory_max_width) + gap;
            }
            return width;
        }

        const RowLayout = struct { text: draw.Rect, toolbar: draw.Rect };

        /// Text and toolbar rows of an `inline_toolbar` frame. Inline: text
        /// vertically centred left of the right-aligned cluster. Stacked:
        /// text over the full inner width above a toolbar row that keeps the
        /// inline bar's bottom/right insets.
        fn rowLayout(self: *const Component, frame: draw.Rect, inline_mode: bool) RowLayout {
            const pad_x = self.scaled(config.padding_x);
            const toolbar_h = self.scaled(config.toolbar_height);
            const inset = self.controlInset();
            const line_h = self.textMetrics().line_height;
            if (inline_mode) {
                const cluster_w = self.inlineClusterWidth();
                const text_w = frame.w - pad_x - self.scaled(config.control_gap) - cluster_w - inset;
                return .{
                    .text = snapRect(.{
                        .x = frame.x + pad_x,
                        .y = frame.y + (frame.h - line_h) * 0.5,
                        .w = @max(text_w, 0.0),
                        .h = line_h,
                    }),
                    .toolbar = snapRect(.{
                        .x = frame.x + frame.w - inset - cluster_w,
                        .y = frame.y + (frame.h - toolbar_h) * 0.5,
                        .w = cluster_w,
                        .h = toolbar_h,
                    }),
                };
            }
            const toolbar_y = frame.y + frame.h - inset - toolbar_h;
            const text_y = frame.y + self.scaled(config.padding_y);
            return .{
                .text = snapRect(.{
                    .x = frame.x + pad_x,
                    .y = text_y,
                    .w = @max(frame.w - pad_x * 2.0, 0.0),
                    .h = @max(toolbar_y - self.scaled(config.toolbar_gap) - text_y, 0.0),
                }),
                .toolbar = snapRect(.{
                    .x = frame.x + pad_x,
                    .y = toolbar_y,
                    .w = @max(frame.w - pad_x - inset, 0.0),
                    .h = toolbar_h,
                }),
            };
        }

        /// Whether `value` fits the inline text column of a `width`-wide
        /// composer. Mirrors `text_layout` wrapping (a line breaks once the
        /// running advance exceeds the column) but stops at the first
        /// overflow, since this runs on every geometry query.
        fn inlineFitsAt(self: *const Component, width: f32, value: []const u8) bool {
            if (!config.inline_toolbar) return false;
            if (std.mem.findScalar(u8, value, '\n') != null) return false;
            // `frameRect` snaps its width only when the strip is outside;
            // match it so the probe column equals the rendered one exactly.
            const frame_w = if (self.directoryOutside()) @round(width) else width;
            const probe_frame: draw.Rect = .{ .x = 0.0, .y = 0.0, .w = frame_w, .h = self.inlineBarHeight() };
            const text_w = self.rowLayout(probe_frame, true).text.w;
            if (text_w < self.scaled(config.inline_min_text_width)) return false;
            const metrics = self.textMetrics();
            const max_w = @max(text_w, 1.0);
            var run_w: f32 = 0.0;
            var index: usize = 0;
            while (index < value.len) {
                const advance = metrics.nextAdvance(value, index);
                if (index > 0 and run_w + advance.width > max_w) return false;
                run_w += advance.width;
                index += @max(advance.byte_len, 1);
            }
            return true;
        }

        /// Click target that focuses the editor; inline mode widens it to
        /// the bar's full height left of the cluster so the slim bar's
        /// vertical padding still places the caret.
        fn textHitRect(self: *const Component) draw.Rect {
            const text_rect = self.textRect();
            if (!(config.inline_toolbar and self.inlineActive())) return text_rect;
            const frame = self.frameRect();
            return .{ .x = frame.x, .y = frame.y, .w = @max(text_rect.x + text_rect.w - frame.x, 0.0), .h = frame.h };
        }

        pub fn sendButtonRect(self: *const Component) draw.Rect {
            return self.toolbarGeometry().send;
        }

        pub fn modelRect(self: *const Component) draw.Rect {
            return self.toolbarGeometry().model;
        }

        pub fn directoryRect(self: *const Component) draw.Rect {
            return self.toolbarGeometry().directory;
        }

        /// Runtime pill rect; zero width unless it is shown on the outside
        /// directory strip.
        pub fn runtimeRect(self: *const Component) draw.Rect {
            return self.toolbarGeometry().runtime;
        }

        pub fn reasoningRect(self: *const Component) draw.Rect {
            return self.toolbarGeometry().reasoning;
        }

        pub fn fastRect(self: *const Component) draw.Rect {
            return self.toolbarGeometry().fast;
        }

        pub fn accessRect(self: *const Component) draw.Rect {
            return self.toolbarGeometry().access;
        }

        pub fn render(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch) !void {
            const previous_z = batch.setZIndex(self.z_index);
            defer batch.restoreZIndex(previous_z);

            const active_border_color = if (self.focused) (self.style.focus_border_color orelse self.style.border_color) else self.style.border_color;
            const active_border_width = self.scaled(if (self.focused) (self.style.focus_border_width orelse config.border_width) else config.border_width);
            try batch.panel(allocator, self.frameRect(), self.style.background_color, active_border_color, self.cornerRadius(), active_border_width);
            try self.renderPromptText(allocator, batch);
            try self.renderToolbar(allocator, batch);
            try self.renderMenu(allocator, batch);
            try self.renderScrollbar(allocator, batch);
        }

        fn renderPromptText(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch) !void {
            const rect = self.textRect();
            const placeholder = self.placeholderText();
            const value = if (self.buffer.items.len == 0) placeholder else self.buffer.items;
            const color = if (self.buffer.items.len == 0) self.style.placeholder_color else self.style.text_color;
            const metrics = self.textMetrics();
            var runs: std.ArrayList(draw.TextRun) = .empty;
            defer runs.deinit(allocator);
            try text_layout.appendRuns(allocator, self.textLayoutOptions(value, color), &runs);
            if (self.selection()) |range| try self.renderSelection(allocator, batch, range);
            try batch.textRuns(allocator, rect, value, runs.items, color, metrics.font_size, rect, metrics.line_height, metrics.fixedAdvance());
            if (self.focused) {
                // Render cursor on focus regardless of buffer state so users
                // get immediate visual feedback after clicking into the prompt.
                const cursor = self.cursorRect();
                if (clippedRect(cursor, rect)) |clipped| try batch.cursor(allocator, clipped, self.style.cursor_color);
            }
        }

        fn renderToolbar(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch) !void {
            const geometry = self.toolbarGeometry();
            const left_before_fast: draw.Rect = if (self.show_reasoning_toggle) geometry.reasoning else geometry.model;
            // Draw separators under pills so divider lines cannot cover trailing chevrons in the gap.
            if (self.show_directory_toggle and !self.directoryOutside()) {
                try self.renderSeparator(allocator, batch, separatorX(geometry.directory, geometry.model), geometry.toolbar);
            }
            if (!config.merged_model_label) {
                if (self.show_reasoning_toggle) {
                    try self.renderSeparator(allocator, batch, separatorX(geometry.model, geometry.reasoning), geometry.toolbar);
                }
                if (self.show_fast_toggle) {
                    try self.renderSeparator(allocator, batch, separatorX(left_before_fast, geometry.fast), geometry.toolbar);
                }
                if (self.show_access_toggle) {
                    const left_before_access: draw.Rect = if (self.show_fast_toggle) geometry.fast else left_before_fast;
                    try self.renderSeparator(allocator, batch, separatorX(left_before_access, geometry.access), geometry.toolbar);
                }
            }

            const strip_chips = config.strip_chips and self.directoryOutside();
            if (self.show_directory_toggle) {
                if (strip_chips) {
                    try self.renderStripChip(allocator, batch, geometry.directory, self.directoryLabel(), self.hovered_part == .directory);
                } else {
                    try self.renderPill(allocator, batch, true, &.{}, geometry.directory, config.directory_icon, self.directoryLabel(), config.chevron_icon, self.hovered_part == .directory);
                }
            }
            if (geometry.runtime.w > 0.0) {
                if (strip_chips) {
                    try self.renderStripChip(allocator, batch, geometry.runtime, self.runtimeLabel(), self.hovered_part == .runtime);
                } else {
                    try self.renderPill(allocator, batch, true, &.{}, geometry.runtime, config.runtime_icon, self.runtimeLabel(), config.chevron_icon, self.hovered_part == .runtime);
                }
            }
            if (config.merged_model_label) {
                try self.renderMergedLabel(allocator, batch, geometry);
            } else {
                try self.renderPill(allocator, batch, true, &.{}, geometry.model, config.model_icon, self.modelLabel(), config.chevron_icon, self.hovered_part == .model or self.active_menu == .model);
                if (self.show_reasoning_toggle) {
                    try self.renderPill(allocator, batch, false, self.reasoningIconSlots(), geometry.reasoning, "", self.reasoningLabel(), config.chevron_icon, self.hovered_part == .reasoning or self.active_menu == .reasoning);
                }
                if (self.show_fast_toggle) {
                    try self.renderPill(allocator, batch, true, &.{}, geometry.fast, config.fast_icon, self.fastLabel(), "", self.hovered_part == .fast or self.fast_enabled);
                }
                if (self.show_access_toggle) {
                    try self.renderPill(allocator, batch, true, &.{}, geometry.access, config.access_icon, self.accessLabel(), "", self.hovered_part == .access or self.access_enabled);
                }
            }

            if (geometry.send.w <= 0.0) return;
            const send_disabled = self.send_state == .disabled or self.send_state == .pending;
            const send_panel_color: draw.Color = blk: {
                if (send_disabled)
                    break :blk draw.Color{ .r = self.style.send_color.r, .g = self.style.send_color.g, .b = self.style.send_color.b, .a = 0.48 };
                if (self.send_state == .stop) {
                    if (self.hovered_part == .send) break :blk self.style.stop_button_hover_color;
                    const alpha = 0.76 + self.stop_pulse_factor * 0.24;
                    break :blk draw.Color{
                        .r = self.style.stop_button_color.r,
                        .g = self.style.stop_button_color.g,
                        .b = self.style.stop_button_color.b,
                        .a = self.style.stop_button_color.a * alpha,
                    };
                }
                if (self.hovered_part == .send) break :blk self.style.send_hover_color;
                break :blk self.style.send_color;
            };
            try batch.panel(allocator, geometry.send, send_panel_color, null, geometry.send.h * 0.5, 0.0);
            if (self.send_state == .stop) {
                try renderStopSquare(allocator, batch, geometry.send, self.style.stop_foreground_color, if (self.hovered_part == .send) 1.0 else self.stop_pulse_factor);
            } else if (self.send_state == .pending) {
                try self.renderCenteredIcon(allocator, batch, geometry.send, self.sendIcon(), self.style.send_foreground_color);
            } else {
                try renderSendArrow(allocator, batch, geometry.send, self.style.send_foreground_color);
            }
        }

        fn renderPill(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch, overlay_leading: bool, icon_slots: []const ComposerPromptIconSlot, rect: draw.Rect, left_icon: []const u8, label: []const u8, right_icon: []const u8, hovered: bool) !void {
            if (rect.w <= 0.0 or rect.h <= 0.0) return;
            try batch.panel(allocator, rect, if (hovered) self.style.control_hover_color else self.style.control_background_color, null, rect.h * 0.5, 0.0);
            const text_metrics = self.toolbarMetrics();
            const icon_metrics = self.iconMetrics();
            // Left icon + one label segment per icon slot + the closing segment.
            var runs: [2 + MAX_PILL_ICON_SLOTS]draw.TextRun = undefined;
            var count: usize = 0;
            var x = rect.x + self.scaled(config.pill_padding_x);
            if (overlay_leading and config.pill_overlay_icon_reserve > 0.0) {
                x += self.scaled(config.pill_overlay_icon_reserve) + self.scaled(config.pill_icon_gap);
            } else if (left_icon.len > 0) {
                runs[count] = iconRun(left_icon, x, rect, icon_metrics, self.style.icon_color);
                x += icon_metrics.measureSlice(left_icon) + self.scaled(config.pill_icon_gap);
                count += 1;
            }
            const label_area_right: f32 = if (right_icon.len > 0)
                rect.x + rect.w - self.scaled(config.pill_padding_x) - self.trailingChevronReserve(right_icon)
            else
                rect.x + rect.w - self.scaled(config.pill_padding_x);
            const label_strip: draw.Rect = .{
                .x = rect.x,
                .y = rect.y,
                .w = @max(label_area_right - rect.x, 0.0),
                .h = rect.h,
            };
            const label_clip = clippedRect(rect, label_strip) orelse label_strip;
            // Break the label around the reserved icon cells so each host
            // glyph lands beside the segment it describes (keep this walk in
            // sync with `reasoningIconSlotRects`).
            var byte: usize = 0;
            for (icon_slots) |slot| {
                const offset = @min(slot.byte_offset, label.len);
                if (offset > byte) {
                    runs[count] = self.pillLabelRun(label, byte, offset, x, rect, label_clip, text_metrics);
                    x += text_metrics.measureSlice(label[byte..offset]);
                    count += 1;
                    byte = offset;
                }
                x += self.scaled(slot.width);
            }
            runs[count] = self.pillLabelRun(label, byte, label.len, x, rect, label_clip, text_metrics);
            count += 1;
            if (right_icon.len > 0) {
                const reserve = self.trailingChevronReserve(right_icon);
                const cell = reserve - self.scaled(config.pill_chevron_gap);
                const cell_x = rect.x + rect.w - self.scaled(config.pill_padding_x) - cell;
                const cell_rect_full: draw.Rect = .{ .x = cell_x, .y = rect.y, .w = cell, .h = rect.h };
                const cell_rect = clippedRect(rect, cell_rect_full) orelse cell_rect_full;
                if (config.chevron_glyph) {
                    try self.renderCenteredIconScaled(allocator, batch, cell_rect, right_icon, self.style.icon_color, config.chevron_glyph_scale);
                } else {
                    try renderDisclosureArrow(allocator, batch, cell_rect, self.style.icon_color);
                }
            }
            try batch.textRuns(allocator, rect, label, runs[0..count], self.style.text_color, text_metrics.font_size, rect, text_metrics.line_height, text_metrics.fixedAdvance());
        }

        // Merged model label: one ghost control, `[logo] Name detail ⌄`. The
        // name and detail halves hover independently because they open
        // different host popovers (model picker vs run settings).
        fn renderMergedLabel(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch, geometry: ToolbarGeometry) !void {
            const model = geometry.model;
            if (model.w <= 0.0 or model.h <= 0.0) return;
            const has_detail = self.show_reasoning_toggle and geometry.reasoning.w > 0.0;
            if (self.hovered_part == .model or self.active_menu == .model or self.label_active) {
                try batch.panel(allocator, model, self.style.control_hover_color, null, model.h * 0.5, 0.0);
            } else if (has_detail and (self.hovered_part == .reasoning or self.active_menu == .reasoning)) {
                try batch.panel(allocator, geometry.reasoning, self.style.control_hover_color, null, geometry.reasoning.h * 0.5, 0.0);
            }
            const metrics = self.toolbarMetrics();
            const cells = self.mergedLabelCells(model, geometry.reasoning);
            const name = self.modelLabel();
            if (cells.name.w > 0.0) {
                const runs = [_]draw.TextRun{self.coloredLabelRun(name, 0, name.len, cells.name.x, cells.name, cells.name, metrics, self.style.text_color)};
                try batch.textRuns(allocator, cells.name, name, &runs, self.style.text_color, metrics.font_size, cells.name, metrics.line_height, metrics.fixedAdvance());
            }
            const detail = self.mergedDetailLabel();
            if (cells.detail.w > 0.0 and detail.len > 0) {
                const muted = self.style.muted_text_color orelse self.style.icon_color;
                const runs = [_]draw.TextRun{self.coloredLabelRun(detail, 0, detail.len, cells.detail.x, cells.detail, cells.detail, metrics, muted)};
                try batch.textRuns(allocator, cells.detail, detail, &runs, muted, metrics.font_size, cells.detail, metrics.line_height, metrics.fixedAdvance());
            }
            if (cells.chevron.w > 0.0) try self.renderChevron(allocator, batch, cells.chevron, config.chevron_icon);
        }

        // Strip chip: small muted `[icon] label` text control under the
        // frame, with a hover lift only (no resting fill).
        fn renderStripChip(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch, rect: draw.Rect, label: []const u8, hovered: bool) !void {
            if (rect.w <= 0.0 or rect.h <= 0.0) return;
            if (hovered) try batch.panel(allocator, rect, self.style.control_hover_color, null, rect.h * 0.5, 0.0);
            const metrics = self.stripMetrics();
            const color = if (hovered) self.style.text_color else self.style.icon_color;
            const text_rect = self.stripChipTextRect(rect);
            if (text_rect.w > 0.0) {
                const runs = [_]draw.TextRun{self.coloredLabelRun(label, 0, label.len, text_rect.x, rect, text_rect, metrics, color)};
                try batch.textRuns(allocator, rect, label, &runs, color, metrics.font_size, text_rect, metrics.line_height, metrics.fixedAdvance());
            }
            if (config.strip_chevron and config.chevron_icon.len > 0) {
                const cell = self.trailingChevronReserve(config.chevron_icon) - self.scaled(config.pill_chevron_gap);
                const cell_rect: draw.Rect = .{ .x = rect.x + rect.w - self.stripPadX() - cell, .y = rect.y, .w = cell, .h = rect.h };
                try self.renderChevron(allocator, batch, clippedRect(rect, cell_rect) orelse cell_rect, config.chevron_icon);
            }
        }

        fn renderChevron(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch, cell: draw.Rect, icon: []const u8) !void {
            if (config.chevron_glyph) {
                try self.renderCenteredIconScaled(allocator, batch, cell, icon, self.style.icon_color, config.chevron_glyph_scale);
            } else {
                try renderDisclosureArrow(allocator, batch, cell, self.style.icon_color);
            }
        }

        fn pillLabelRun(self: *const Component, label: []const u8, byte_start: usize, byte_end: usize, x: f32, rect: draw.Rect, clip: draw.Rect, metrics: text_layout.FontMetrics) draw.TextRun {
            return self.coloredLabelRun(label, byte_start, byte_end, x, rect, clip, metrics, self.style.text_color);
        }

        fn coloredLabelRun(self: *const Component, label: []const u8, byte_start: usize, byte_end: usize, x: f32, rect: draw.Rect, clip: draw.Rect, metrics: text_layout.FontMetrics, color: draw.Color) draw.TextRun {
            _ = self;
            return .{
                .text = label,
                .byte_start = byte_start,
                .byte_end = byte_end,
                .x = x,
                .y = rect.y + @max((rect.h - metrics.line_height) * 0.5, 0.0),
                .font_size = metrics.font_size,
                .line_height = metrics.line_height,
                .color = color,
                .clip = clip,
                .font_role = config.bold_font_role,
                .font_id = config.font_id,
            };
        }

        fn renderCenteredIcon(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch, rect: draw.Rect, icon: []const u8, color: draw.Color) !void {
            try self.renderCenteredIconScaled(allocator, batch, rect, icon, color, 1.0);
        }

        fn renderCenteredIconScaled(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch, rect: draw.Rect, icon: []const u8, color: draw.Color, scale: f32) !void {
            if (icon.len == 0) return;
            const metrics = self.iconMetrics();
            const width = metrics.measureSlice(icon) * scale;
            const font_size = metrics.font_size * scale;
            const line_height = metrics.line_height * scale;
            const runs = [_]draw.TextRun{.{
                .text = icon,
                .byte_start = 0,
                .byte_end = icon.len,
                .x = rect.x + (rect.w - width) * 0.5,
                .y = rect.y + (rect.h - line_height) * 0.5,
                .font_size = font_size,
                .line_height = line_height,
                .color = color,
                .clip = rect,
                .font_role = config.icon_font_role,
                .font_id = config.icon_font_id,
            }};
            try batch.textRuns(allocator, rect, icon, &runs, color, font_size, rect, line_height, metrics.fixedAdvance() * scale);
        }

        fn sendGlyphBounds(button: draw.Rect) draw.Rect {
            const m = @min(button.w, button.h);
            const inset = m * 0.125;
            return snapRect(.{
                .x = button.x + inset,
                .y = button.y + inset,
                .w = @max(button.w - 2.0 * inset, 1.0),
                .h = @max(button.h - 2.0 * inset, 1.0),
            });
        }

        fn renderStopSquare(allocator: std.mem.Allocator, batch: *draw.RenderBatch, button: draw.Rect, color: draw.Color, pulse: f32) !void {
            const inner = sendGlyphBounds(button);
            const m = @min(inner.w, inner.h);
            const side = m * (0.46 + pulse * 0.08);
            const cx = inner.x + inner.w * 0.5;
            const cy = inner.y + inner.h * 0.5;
            const cr = @max(side * 0.18, 1.5);
            try batch.roundedRectClipped(allocator, .{
                .x = cx - side * 0.5,
                .y = cy - side * 0.5,
                .w = side,
                .h = side,
            }, .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a * (0.72 + pulse * 0.28) }, cr, button);
        }

        /// Send: wide triangular head + narrow stem (same-width stem under an equilateral head reads as a "house").
        fn renderSendArrow(allocator: std.mem.Allocator, batch: *draw.RenderBatch, button: draw.Rect, color: draw.Color) !void {
            const inner = sendGlyphBounds(button);
            const m = @min(inner.w, inner.h);
            const cx = inner.x + inner.w * 0.5;
            const total_h = m * 0.56;
            const head_h = total_h * 0.52;
            const stem_h = total_h * 0.48;
            const half_w_head = m * 0.175;
            const half_w_stem = @max(m * 0.052, 1.25);
            const y0 = inner.y + (inner.h - total_h) * 0.5;
            // Stem under the head so the junction is a narrow shaft, not a full-width block.
            try batch.rectClipped(allocator, snapRect(.{
                .x = cx - half_w_stem,
                .y = y0 + head_h,
                .w = half_w_stem * 2.0,
                .h = stem_h,
            }), color, button);
            try batch.triangleClipped(
                allocator,
                snapPoint(.{ .x = cx, .y = y0 }),
                snapPoint(.{ .x = cx - half_w_head, .y = y0 + head_h }),
                snapPoint(.{ .x = cx + half_w_head, .y = y0 + head_h }),
                color,
                button,
            );
        }

        fn renderDisclosureArrow(allocator: std.mem.Allocator, batch: *draw.RenderBatch, rect: draw.Rect, color: draw.Color) !void {
            const m = @max(@min(rect.w, rect.h), 1.0);
            const cx = rect.x + rect.w * 0.5;
            const cy = rect.y + rect.h * 0.5;
            const half_h = m * 0.18;
            const half_w = m * 0.14;
            try batch.triangleClipped(
                allocator,
                .{ .x = cx - half_w, .y = cy - half_h },
                .{ .x = cx - half_w, .y = cy + half_h },
                .{ .x = cx + half_w, .y = cy },
                color,
                rect,
            );
        }

        fn renderSeparator(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch, x: f32, toolbar: draw.Rect) !void {
            const sx = @round(x);
            try batch.rect(allocator, .{
                .x = sx - config.separator_width * 0.5,
                .y = @round(toolbar.y + 9.0),
                .w = config.separator_width,
                .h = @round(@max(toolbar.h - 18.0, 0.0)),
            }, self.style.separator_color);
        }

        fn iconRun(value: []const u8, x: f32, rect: draw.Rect, metrics: text_layout.FontMetrics, color: draw.Color) draw.TextRun {
            return .{
                .text = value,
                .byte_start = 0,
                .byte_end = value.len,
                .x = x,
                .y = rect.y + @max((rect.h - metrics.line_height) * 0.5, 0.0),
                .font_size = metrics.font_size,
                .line_height = metrics.line_height,
                .color = color,
                .clip = rect,
                .font_role = config.icon_font_role,
                .font_id = config.icon_font_id,
            };
        }

        fn iconRunWithClip(value: []const u8, x: f32, clip: draw.Rect, metrics: text_layout.FontMetrics, color: draw.Color) draw.TextRun {
            return .{
                .text = value,
                .byte_start = 0,
                .byte_end = value.len,
                .x = x,
                .y = clip.y + @max((clip.h - metrics.line_height) * 0.5, 0.0),
                .font_size = metrics.font_size,
                .line_height = metrics.line_height,
                .color = color,
                .clip = clip,
                .font_role = config.icon_font_role,
                .font_id = config.icon_font_id,
            };
        }

        fn renderMenu(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch) !void {
            const target = self.active_menu orelse return;
            const options = self.optionsFor(target);
            if (options.count == 0) return;
            const rect = self.menuRect(target);
            const previous_z = batch.setZIndex(self.z_index + 1000);
            defer batch.restoreZIndex(previous_z);
            const menu_corner: f32 = self.scaled(14.0);
            // Rounded shell (avoid `panel` + rectBorder sharp outer frame on top of rounded fills).
            const inset = @max(1.0, 1.0);
            try batch.roundedRectClipped(allocator, rect, self.style.menu_border_color, menu_corner, rect);
            if (rect.w > inset * 2.0 and rect.h > inset * 2.0) {
                try batch.roundedRectClipped(allocator, .{
                    .x = rect.x + inset,
                    .y = rect.y + inset,
                    .w = rect.w - inset * 2.0,
                    .h = rect.h - inset * 2.0,
                }, self.style.menu_background_color, @max(menu_corner - inset, 0.0), rect);
            }
            const metrics = self.toolbarMetrics();
            const row_corner = @min(9.0, @max(4.0, metrics.line_height * 0.38));
            var index: usize = 0;
            while (index < options.count) : (index += 1) {
                const row = self.menuRowRect(target, index);
                if (row.y + row.h < rect.y or row.y > rect.y + rect.h) continue;
                if (self.selectedIndex(target) == index) {
                    try batch.roundedRectClipped(allocator, row, self.style.menu_selected_color, row_corner, rect);
                } else if (self.hovered_menu_index == index) {
                    try batch.roundedRectClipped(allocator, row, self.style.menu_hover_color, row_corner, rect);
                }
                const label = options.labelFor(index) orelse continue;
                const text_rect: draw.Rect = .{
                    .x = row.x + self.scaled(config.pill_padding_x),
                    .y = row.y + @max((row.h - metrics.line_height) * 0.5, 0.0),
                    .w = @max(row.w - self.scaled(config.pill_padding_x) * 2.0, 0.0),
                    .h = metrics.line_height,
                };
                const runs = [_]draw.TextRun{.{
                    .text = label,
                    .byte_start = 0,
                    .byte_end = label.len,
                    .x = text_rect.x,
                    .y = text_rect.y,
                    .font_size = metrics.font_size,
                    .line_height = metrics.line_height,
                    .color = self.style.text_color,
                    .clip = rect,
                    .font_role = config.font_role,
                    .font_id = config.font_id,
                }};
                try batch.textRuns(allocator, text_rect, label, &runs, self.style.text_color, metrics.font_size, rect, metrics.line_height, metrics.fixedAdvance());
            }
            try self.renderMenuScrollbar(allocator, batch, target);
        }

        fn handleKey(self: *Component, allocator: std.mem.Allocator, key: key_input) !bool {
            if (self.active_menu) |target| {
                if (key.code == .escape) {
                    self.active_menu = null;
                    self.hovered_menu_index = null;
                    return true;
                }
                if (key.code == .enter) {
                    if (self.hovered_menu_index) |index| {
                        try self.selectOption(allocator, target, index);
                        return true;
                    }
                }
            }
            if (!self.focused and key.code != .escape) return false;
            if (key.primary and key.code == .a) {
                self.selection_anchor = 0;
                self.selection_focus = self.buffer.items.len;
                self.cursor = self.buffer.items.len;
                self.ensureCursorVisible();
                return true;
            }
            if (key.primary and key.code == .c) {
                _ = self.copySelection();
                return true;
            }
            if (key.primary and key.code == .x) {
                _ = try self.cutSelection(allocator);
                return true;
            }
            switch (key.code) {
                .escape => {
                    self.active_menu = null;
                    self.setFocused(false);
                    return true;
                },
                .backspace => {
                    if (self.selection()) |_| {
                        try self.replaceSelection(allocator, "");
                        return true;
                    }
                    if (self.cursor == 0) return true;
                    const start = selection_input.previousOffset(self.buffer.items, self.cursor);
                    try self.replaceRange(allocator, start, self.cursor, "");
                    return true;
                },
                .delete => {
                    if (self.selection()) |_| {
                        try self.replaceSelection(allocator, "");
                        return true;
                    }
                    if (self.cursor >= self.buffer.items.len) return true;
                    try self.replaceRange(allocator, self.cursor, selection_input.nextOffset(self.buffer.items, self.cursor), "");
                    return true;
                },
                .left => {
                    self.moveCursor(selection_input.previousOffset(self.buffer.items, self.cursor), key.shift);
                    return true;
                },
                .right => {
                    self.moveCursor(selection_input.nextOffset(self.buffer.items, self.cursor), key.shift);
                    return true;
                },
                .home => {
                    self.moveCursor(selection_input.lineStart(self.buffer.items, self.cursor), key.shift);
                    return true;
                },
                .end => {
                    self.moveCursor(selection_input.lineEnd(self.buffer.items, self.cursor), key.shift);
                    return true;
                },
                .enter => {
                    if (key.primary) {
                        self.submit();
                    } else {
                        try self.insertText(allocator, "\n");
                    }
                    return true;
                },
                .v => {
                    if (!key.primary) return false;
                    return try self.pasteClipboard(allocator);
                },
                .z => {
                    if (!key.primary) return false;
                    if (key.shift) try self.redo(allocator) else try self.undo(allocator);
                    return true;
                },
                .y => {
                    if (!key.primary) return false;
                    try self.redo(allocator);
                    return true;
                },
                else => return false,
            }
        }

        fn handleMouseDown(self: *Component, allocator: std.mem.Allocator, point: draw.Vec2) !bool {
            if (self.active_menu) |target| {
                if (self.menuIndexAtPoint(point)) |index| {
                    try self.selectOption(allocator, target, index);
                    return true;
                }
                if (!self.menuRect(target).contains(point)) {
                    self.active_menu = null;
                    self.hovered_menu_index = null;
                }
            }
            if (self.textHitRect().contains(point)) {
                self.setFocused(true);
                self.cursor = text_layout.offsetForPoint(self.textLayoutOptions(self.buffer.items, self.style.text_color), point);
                self.selection_anchor = self.cursor;
                self.selection_focus = self.cursor;
                self.dragging_selection = true;
                return true;
            }
            if (self.hitTest(point)) |part| {
                self.setFocused(false);
                self.hovered_part = part;
                switch (part) {
                    .directory => self.emit(.directory_clicked),
                    .runtime => self.emit(.runtime_clicked),
                    .model => {
                        if (!self.external_model_menu) self.toggleMenu(.model);
                        self.emit(.model_clicked);
                    },
                    .reasoning => {
                        if (!self.external_reasoning_menu) self.toggleMenu(.reasoning);
                        self.emit(.reasoning_clicked);
                    },
                    .fast => {
                        self.fast_enabled = !self.fast_enabled;
                        self.emit(.{ .fast_changed = self.fast_enabled });
                    },
                    .access => {
                        self.access_enabled = !self.access_enabled;
                        self.emit(.{ .access_changed = self.access_enabled });
                    },
                    .send => {
                        if (self.send_state != .disabled and self.send_state != .pending) {
                            self.emit(.send_clicked);
                            if (self.send_state == .send) self.submit();
                        }
                    },
                }
                return true;
            }
            self.setFocused(false);
            self.hovered_part = null;
            return false;
        }

        fn handleMouseDrag(self: *Component, point: draw.Vec2) bool {
            if (!self.dragging_selection) return false;
            if (self.selection_anchor == null) self.selection_anchor = self.cursor;
            self.cursor = text_layout.offsetForPoint(self.textLayoutOptions(self.buffer.items, self.style.text_color), point);
            self.selection_focus = self.cursor;
            self.autoScrollForDrag(point);
            self.ensureCursorVisible();
            return true;
        }

        fn insertText(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            if (value.len == 0) return;
            if (self.selection()) |_| return self.replaceSelection(allocator, value);
            try self.replaceRange(allocator, self.cursor, self.cursor, value);
        }

        fn insertTextInput(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            if (value.len == 0) return;
            const sanitized = try sanitizedText(allocator, value, false);
            defer sanitized.deinit(allocator);
            return self.insertText(allocator, sanitized.items());
        }

        fn replaceSelection(self: *Component, allocator: std.mem.Allocator, value: []const u8) !void {
            const range = self.selection() orelse return self.replaceRange(allocator, self.cursor, self.cursor, value);
            try self.replaceRange(allocator, range.start, range.end, value);
        }

        fn pasteClipboard(self: *Component, allocator: std.mem.Allocator) !bool {
            const clipboard_text = self.callbacks.clipboardProvider().read(allocator) orelse return false;
            defer allocator.free(clipboard_text);
            if (clipboard_text.len == 0) return false;
            try self.replaceSelection(allocator, clipboard_text);
            return true;
        }

        fn copySelection(self: *Component) bool {
            const range = self.selection() orelse return false;
            return self.callbacks.clipboardProvider().write(self.buffer.items[range.start..range.end]);
        }

        fn cutSelection(self: *Component, allocator: std.mem.Allocator) !bool {
            if (!self.copySelection()) return false;
            try self.replaceSelection(allocator, "");
            return true;
        }

        fn replaceRange(self: *Component, allocator: std.mem.Allocator, start: usize, end: usize, value: []const u8) !void {
            const safe_start = @min(start, self.buffer.items.len);
            const safe_end = @min(@max(end, safe_start), self.buffer.items.len);
            const sanitized = try sanitizedText(allocator, value, true);
            defer sanitized.deinit(allocator);
            try self.recordUndoSnapshot(allocator);
            self.buffer.replaceRange(allocator, safe_start, safe_end - safe_start, sanitized.items()) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
            };
            self.clearRedoStack(allocator);
            self.cursor = safe_start + sanitized.items().len;
            self.selection_anchor = null;
            self.selection_focus = null;
            self.ensureCursorVisible();
            self.emit(.{ .text_changed = self.buffer.items });
        }

        fn undo(self: *Component, allocator: std.mem.Allocator) !void {
            const snapshot = self.undo_stack.pop() orelse return;
            defer snapshot.deinit(allocator);
            try self.redo_stack.append(allocator, try EditSnapshot.capture(allocator, self));
            try self.restoreSnapshot(allocator, snapshot);
        }

        fn redo(self: *Component, allocator: std.mem.Allocator) !void {
            const snapshot = self.redo_stack.pop() orelse return;
            defer snapshot.deinit(allocator);
            try self.undo_stack.append(allocator, try EditSnapshot.capture(allocator, self));
            try self.restoreSnapshot(allocator, snapshot);
        }

        fn restoreSnapshot(self: *Component, allocator: std.mem.Allocator, snapshot: EditSnapshot) !void {
            self.buffer.clearRetainingCapacity();
            try self.buffer.appendSlice(allocator, snapshot.text);
            self.cursor = @min(snapshot.cursor, self.buffer.items.len);
            self.selection_anchor = snapshot.selection_anchor;
            self.selection_focus = snapshot.selection_focus;
            self.ensureCursorVisible();
            self.emit(.{ .text_changed = self.buffer.items });
        }

        fn recordUndoSnapshot(self: *Component, allocator: std.mem.Allocator) !void {
            try self.undo_stack.append(allocator, try EditSnapshot.capture(allocator, self));
            while (self.undo_stack.items.len > MAX_EDIT_HISTORY) {
                const dropped = self.undo_stack.orderedRemove(0);
                dropped.deinit(allocator);
            }
        }

        fn clearEditHistory(self: *Component, allocator: std.mem.Allocator) void {
            self.clearUndoStack(allocator);
            self.clearRedoStack(allocator);
        }

        fn clearUndoStack(self: *Component, allocator: std.mem.Allocator) void {
            for (self.undo_stack.items) |snapshot| snapshot.deinit(allocator);
            self.undo_stack.clearRetainingCapacity();
        }

        fn clearRedoStack(self: *Component, allocator: std.mem.Allocator) void {
            for (self.redo_stack.items) |snapshot| snapshot.deinit(allocator);
            self.redo_stack.clearRetainingCapacity();
        }

        fn moveCursor(self: *Component, next: usize, extend_selection: bool) void {
            const old = self.cursor;
            self.cursor = @min(next, self.buffer.items.len);
            if (extend_selection) {
                if (self.selection_anchor == null) self.selection_anchor = old;
                self.selection_focus = self.cursor;
            } else {
                self.selection_anchor = null;
                self.selection_focus = null;
            }
            self.ensureCursorVisible();
        }

        fn autoScrollForDrag(self: *Component, point: draw.Vec2) void {
            const text_rect = self.textRect();
            if (point.y < text_rect.y) {
                self.scrollBy(-self.textMetrics().line_height);
            } else if (point.y > text_rect.y + text_rect.h) {
                self.scrollBy(self.textMetrics().line_height);
            }
        }

        fn submit(self: *Component) void {
            self.emit(.{ .submitted = self.buffer.items });
        }

        fn toggleMenu(self: *Component, target: ComposerPromptOptionTarget) void {
            if (self.active_menu == target) {
                self.active_menu = null;
                self.hovered_menu_index = null;
                self.menu_scroll_y = 0.0;
            } else {
                self.active_menu = target;
                self.hovered_menu_index = self.selectedIndex(target) orelse 0;
                self.menu_scroll_y = 0.0;
                self.ensureMenuIndexVisible(target, self.hovered_menu_index orelse 0);
            }
        }

        fn selectOption(self: *Component, allocator: std.mem.Allocator, target: ComposerPromptOptionTarget, index: usize) !void {
            const options = self.optionsFor(target);
            if (index >= options.count) return;
            switch (target) {
                .model => {
                    self.model_index = index;
                    if (options.labelFor(index)) |label| try self.setModelLabel(allocator, label);
                    self.emit(.{ .model_changed = index });
                },
                .reasoning => {
                    self.reasoning_index = index;
                    if (options.labelFor(index)) |label| try self.setReasoningLabel(allocator, label);
                    self.emit(.{ .reasoning_changed = index });
                },
            }
            self.active_menu = null;
            self.hovered_menu_index = null;
            self.menu_scroll_y = 0.0;
        }

        fn setFocused(self: *Component, focused: bool) void {
            const changed = self.focused != focused;
            self.focused = focused;
            if (!focused) {
                self.selection_anchor = null;
                self.selection_focus = null;
                self.dragging_selection = false;
                self.active_menu = null;
                self.hovered_menu_index = null;
            }
            if (changed) self.emit(.{ .focus_changed = focused });
        }

        pub fn cursorRect(self: *const Component) draw.Rect {
            const metrics = self.textMetrics();
            const pos = text_layout.positionForOffset(self.textLayoutOptions(self.buffer.items, self.style.text_color), self.cursor);
            return .{ .x = pos.x, .y = pos.y, .w = @max(self.scaled(1.5), 1.0), .h = metrics.line_height };
        }

        fn menuRect(self: *const Component, target: ComposerPromptOptionTarget) draw.Rect {
            const control = switch (target) {
                .model => self.modelRect(),
                .reasoning => self.reasoningRect(),
            };
            const options = self.optionsFor(target);
            const max_rows = @max(config.menu_max_visible_rows, 1.0);
            const height = @min(
                @as(f32, @floatFromInt(options.count)) * self.scaled(config.row_height),
                self.scaled(config.row_height) * max_rows,
            );
            return .{ .x = control.x, .y = control.y - height - self.scaled(6.0), .w = @max(control.w, self.menuContentWidth(target)), .h = height };
        }

        fn menuRowRect(self: *const Component, target: ComposerPromptOptionTarget, index: usize) draw.Rect {
            const menu = self.menuRect(target);
            return .{ .x = menu.x, .y = menu.y + @as(f32, @floatFromInt(index)) * self.scaled(config.row_height) - self.menu_scroll_y, .w = menu.w, .h = self.scaled(config.row_height) };
        }

        fn menuIndexAtPoint(self: *const Component, point: draw.Vec2) ?usize {
            const target = self.active_menu orelse return null;
            const menu = self.menuRect(target);
            if (!menu.contains(point)) return null;
            const index: usize = @intFromFloat(@floor((point.y - menu.y + self.menu_scroll_y) / self.scaled(config.row_height)));
            if (index >= self.optionsFor(target).count) return null;
            return index;
        }

        fn menuScrollMetrics(self: *const Component, target: ComposerPromptOptionTarget) scroll.Metrics {
            return .{
                .enabled = true,
                .content_height = @as(f32, @floatFromInt(self.optionsFor(target).count)) * self.scaled(config.row_height),
                .visible_height = self.menuRect(target).h,
                .line_height = self.scaled(config.row_height),
                .scrollbar_width = self.scaled(config.scrollbar_width),
            };
        }

        fn setMenuScrollY(self: *Component, target: ComposerPromptOptionTarget, value: f32) void {
            self.menu_scroll_y = scroll.clampOffsetY(value, self.menuScrollMetrics(target));
        }

        fn ensureMenuIndexVisible(self: *Component, target: ComposerPromptOptionTarget, index: usize) void {
            const top = @as(f32, @floatFromInt(index)) * self.scaled(config.row_height);
            const bottom = top + self.scaled(config.row_height);
            const visible_height = self.menuRect(target).h;
            if (top < self.menu_scroll_y) {
                self.menu_scroll_y = top;
            } else if (bottom > self.menu_scroll_y + visible_height) {
                self.menu_scroll_y = bottom - visible_height;
            }
            self.setMenuScrollY(target, self.menu_scroll_y);
        }

        fn menuScrollbarTrackRect(self: *const Component, target: ComposerPromptOptionTarget) draw.Rect {
            const menu = self.menuRect(target);
            const track_w = @min(self.scaled(config.scrollbar_width), menu.w);
            return .{
                .x = menu.x + menu.w - track_w - self.scaled(2.0),
                .y = menu.y + self.scaled(6.0),
                .w = track_w,
                .h = @max(menu.h - self.scaled(12.0), 0.0),
            };
        }

        fn renderMenuScrollbar(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch, target: ComposerPromptOptionTarget) !void {
            if (config.scrollbar_width <= 0.0) return;
            const metrics = self.menuScrollMetrics(target);
            if (scroll.maxOffsetY(metrics) <= 0.0) return;
            const track = self.menuScrollbarTrackRect(target);
            try batch.scrollbar(allocator, track, self.style.scrollbar_track_color);
            if (scroll.thumbRect(track, metrics, self.menu_scroll_y)) |thumb| {
                try batch.scrollbar(allocator, thumb, self.style.scrollbar_thumb_color);
            }
        }

        fn selectedIndex(self: *const Component, target: ComposerPromptOptionTarget) ?usize {
            return switch (target) {
                .model => self.model_index,
                .reasoning => self.reasoning_index,
            };
        }

        fn optionsFor(self: *const Component, target: ComposerPromptOptionTarget) Options {
            return switch (target) {
                .model => self.model_options,
                .reasoning => self.reasoning_options,
            };
        }

        fn placeholderText(self: *const Component) []const u8 {
            return if (self.placeholder_buffer.items.len > 0) self.placeholder_buffer.items else config.placeholder;
        }

        fn directoryLabel(self: *const Component) []const u8 {
            if (self.preview_labels.directory) |label| return label;
            return if (self.directory_label_buffer.items.len > 0) self.directory_label_buffer.items else config.directory_label;
        }

        fn runtimeLabel(self: *const Component) []const u8 {
            if (self.preview_labels.runtime) |label| return label;
            return if (self.runtime_label_buffer.items.len > 0) self.runtime_label_buffer.items else config.runtime_label;
        }

        fn modelLabel(self: *const Component) []const u8 {
            if (self.preview_labels.model) |label| return label;
            return if (self.model_label_buffer.items.len > 0) self.model_label_buffer.items else config.model_label;
        }

        fn reasoningLabel(self: *const Component) []const u8 {
            return if (self.reasoning_label_buffer.items.len > 0) self.reasoning_label_buffer.items else config.reasoning_label;
        }

        fn fastLabel(self: *const Component) []const u8 {
            return if (self.fast_label_buffer.items.len > 0) self.fast_label_buffer.items else config.fast_label;
        }

        fn accessLabel(self: *const Component) []const u8 {
            return if (self.access_label_buffer.items.len > 0) self.access_label_buffer.items else config.access_label;
        }

        fn sendIcon(self: *const Component) []const u8 {
            return switch (self.send_state) {
                .send, .disabled => config.send_icon,
                .stop => config.stop_icon,
                .pending => config.pending_icon,
            };
        }

        fn emit(self: *Component, event: ComposerPromptEvent) void {
            if (self.callbacks.on_event) |callback| callback(self.callbacks.context, event);
        }

        fn textMetrics(self: *const Component) text_layout.FontMetrics {
            if (self.font_metrics) |metrics| return metrics;
            return text_layout.FontMetrics.fixed(config.font_size, config.fixed_advance orelse config.font_size * 0.55, config.font_size * 1.25);
        }

        fn toolbarMetrics(self: *const Component) text_layout.FontMetrics {
            if (self.toolbar_font_metrics) |metrics| return metrics;
            return text_layout.FontMetrics.fixed(config.toolbar_font_size, config.toolbar_fixed_advance orelse config.toolbar_font_size * 0.55, config.toolbar_font_size * 1.25);
        }

        fn iconMetrics(self: *const Component) text_layout.FontMetrics {
            if (self.icon_font_metrics) |metrics| return metrics;
            return text_layout.FontMetrics.fixed(config.icon_font_size, config.icon_fixed_advance orelse config.icon_font_size * 0.55, config.icon_font_size * 1.25);
        }

        fn textLayoutOptions(self: *const Component, value: []const u8, color: draw.Color) text_layout.Options {
            return .{
                .rect = self.textRect(),
                .text = value,
                .color = color,
                .metrics = self.textMetrics(),
                .font_role = config.font_role,
                .font_id = config.font_id,
                .wrap = true,
                .scroll = .{ .y = self.scroll_y },
                .clip = self.textRect(),
            };
        }

        fn renderSelection(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch, range: selection_input.Range) !void {
            var rects: std.ArrayList(draw.Rect) = .empty;
            defer rects.deinit(allocator);
            try text_layout.appendSelectionRects(allocator, self.textLayoutOptions(self.buffer.items, self.style.text_color), range, &rects);
            for (rects.items) |rect| try batch.selection(allocator, rect, self.style.selection_color);
        }

        fn renderScrollbar(self: *const Component, allocator: std.mem.Allocator, batch: *draw.RenderBatch) !void {
            if (!config.scroll_enabled or config.scrollbar_width <= 0.0 or self.maxScrollY() <= 0.0) return;
            const track = self.scrollbarTrackRect();
            try batch.scrollbar(allocator, track, self.style.scrollbar_track_color);
            if (self.scrollbarThumbRect()) |thumb| try batch.scrollbar(allocator, thumb, self.style.scrollbar_thumb_color);
        }

        fn scrollbarTrackRect(self: *const Component) draw.Rect {
            const text_rect = self.textRect();
            const track_w = @min(self.scaled(config.scrollbar_width), text_rect.w);
            return .{
                .x = text_rect.x + text_rect.w - track_w,
                .y = text_rect.y,
                .w = track_w,
                .h = text_rect.h,
            };
        }

        fn scrollbarThumbRect(self: *const Component) ?draw.Rect {
            return scroll.thumbRect(self.scrollbarTrackRect(), self.scrollMetrics(), self.scroll_y);
        }

        fn scrollMetrics(self: *const Component) scroll.Metrics {
            return .{
                .enabled = config.scroll_enabled,
                .content_height = self.contentHeight(),
                .visible_height = self.textRect().h,
                .line_height = self.textMetrics().line_height,
                .scrollbar_width = self.scaled(config.scrollbar_width),
            };
        }

        fn scrollBy(self: *Component, delta_y: f32) void {
            self.setScrollY(self.scroll_y + delta_y);
        }

        fn ensureCursorVisible(self: *Component) void {
            if (!config.scroll_enabled) {
                self.scroll_y = 0.0;
                return;
            }
            const cell = text_layout.visualCellForOffset(self.buffer.items, self.cursor, self.textMetrics(), self.textRect().w, true);
            const cursor_top = @as(f32, @floatFromInt(cell.row)) * self.textMetrics().line_height;
            const cursor_bottom = cursor_top + self.textMetrics().line_height;
            const visible_height = self.textRect().h;
            if (cursor_top < self.scroll_y) {
                self.scroll_y = cursor_top;
            } else if (cursor_bottom > self.scroll_y + visible_height) {
                self.scroll_y = cursor_bottom - visible_height;
            }
            self.setScrollY(self.scroll_y);
        }

        fn trailingChevronReserve(self: *const Component, right_icon: []const u8) f32 {
            if (right_icon.len == 0) return 0.0;
            const icon_metrics = self.iconMetrics();
            const glyph_scale: f32 = if (config.chevron_glyph) config.chevron_glyph_scale else 1.0;
            const measured = icon_metrics.measureSlice(right_icon) * glyph_scale;
            // Measured advance for icon glyphs (e.g. ">") can be tighter than GPU text; reserve at least
            // a column so labels are not clipped and the chevron does not collide with the label.
            // The chevron inks only ~half its em, so the floor stays under the icon font size —
            // 21 read as a wide dead column once the floor scaled with display DPI.
            const min_cell = @max(icon_metrics.font_size * glyph_scale * 0.82, self.scaled(if (config.chevron_glyph) 12.0 else 16.0));
            return self.scaled(config.pill_chevron_gap) + @max(measured, min_cell);
        }

        fn toolbarLabelMeasureSlack(self: *const Component, text_metrics: text_layout.FontMetrics) f32 {
            return @max(self.scaled(8.0), text_metrics.font_size * 0.28);
        }

        /// Toolbar pills render with `bold_font_role`; measurement uses `toolbarMetrics` (often regular).
        fn pillToolbarLabelSlack(self: *const Component, text_metrics: text_layout.FontMetrics) f32 {
            var s = self.toolbarLabelMeasureSlack(text_metrics);
            if (config.bold_font_role != null and config.font_role != null and
                config.bold_font_role.? != config.font_role.?)
            {
                s *= 1.28;
            }
            return s;
        }

        /// `min_width` / `max_width` are CSS units (config values); everything
        /// else already carries the UI scale.
        fn pillWidth(self: *const Component, overlay_leading: bool, extra_leading: f32, left_icon: []const u8, label: []const u8, right_icon: []const u8, min_width: f32, max_width: f32) f32 {
            const text_metrics = self.toolbarMetrics();
            const icon_metrics = self.iconMetrics();
            var width = self.scaled(config.pill_padding_x) * 2.0 + extra_leading + text_metrics.measureSlice(label) + self.pillToolbarLabelSlack(text_metrics) + self.scaled(config.pill_label_width_fudge);
            if (overlay_leading and config.pill_overlay_icon_reserve > 0.0) {
                width += self.scaled(config.pill_overlay_icon_reserve) + self.scaled(config.pill_icon_gap);
            } else if (left_icon.len > 0) {
                width += icon_metrics.measureSlice(left_icon) + self.scaled(config.pill_icon_gap);
            }
            if (right_icon.len > 0) width += self.trailingChevronReserve(right_icon);
            return @min(@max(width, self.scaled(min_width)), self.scaled(max_width));
        }

        /// Unclamped width needed for the current label/icons (ignores configured min/max caps).
        fn pillNaturalNeedWidth(self: *const Component, overlay_leading: bool, extra_leading: f32, left_icon: []const u8, label: []const u8, right_icon: []const u8) f32 {
            return self.pillWidth(overlay_leading, extra_leading, left_icon, label, right_icon, 0.0, std.math.floatMax(f32));
        }

        fn menuContentWidth(self: *const Component, target: ComposerPromptOptionTarget) f32 {
            const options = self.optionsFor(target);
            const metrics = self.toolbarMetrics();
            var width: f32 = self.scaled(150.0);
            var index: usize = 0;
            while (index < options.count) : (index += 1) {
                if (options.labelFor(index)) |label| {
                    width = @max(width, metrics.measureSlice(label) + self.scaled(config.pill_padding_x) * 2.0);
                }
            }
            return width;
        }

        fn toolbarPillsTotalWidth(self: *const Component, model_w: f32, reasoning_w: f32, fast_w: f32, access_w: f32) f32 {
            const gap = self.scaled(config.control_gap);
            var total = model_w + gap;
            total += reasoning_w;
            if (self.show_fast_toggle) {
                total += gap + fast_w + gap;
            } else {
                total += gap;
            }
            total += access_w;
            return total;
        }

        /// When natural pill widths exceed the toolbar budget, shrink pills
        /// proportionally in two phases: first shed the padding that min-width
        /// clamps added over each pill's natural content width, then — if the
        /// toolbar is still over budget (narrow split panes) — keep shrinking
        /// down to the configured minimums so labels clip cleanly inside their
        /// pills instead of the pill row running under the send button.
        fn shrinkToolbarPillWidthsToFit(self: *const Component, avail: f32, model_w: *f32, reasoning_w: *f32, fast_w: *f32, access_w: *f32) void {
            const need_m = self.pillNaturalNeedWidth(true, 0.0, config.model_icon, self.modelLabel(), config.chevron_icon);
            const need_r = if (self.show_reasoning_toggle)
                self.pillNaturalNeedWidth(false, self.reasoningIconSlotsWidth(), "", self.reasoningLabel(), config.chevron_icon)
            else
                0.0;
            const need_f = if (self.show_fast_toggle)
                self.pillNaturalNeedWidth(true, 0.0, config.fast_icon, self.fastLabel(), "")
            else
                0.0;
            const need_a = if (self.show_access_toggle)
                self.pillNaturalNeedWidth(true, 0.0, config.access_icon, self.accessLabel(), "")
            else
                0.0;

            // Phase 1 floors: natural content width — nothing clips yet.
            const natural_m = @max(self.scaled(config.model_min_width), @min(need_m, self.scaled(config.model_max_width)));
            const natural_r = if (self.show_reasoning_toggle) @max(self.scaled(config.reasoning_min_width), @min(need_r, self.scaled(config.reasoning_max_width))) else 0.0;
            const natural_f = if (self.show_fast_toggle) @max(self.scaled(config.fast_min_width), @min(need_f, self.scaled(config.fast_max_width))) else 0.0;
            const natural_a = if (self.show_access_toggle) @max(self.scaled(config.access_min_width), @min(need_a, self.scaled(config.access_max_width))) else 0.0;
            self.shrinkPillsToward(avail, model_w, reasoning_w, fast_w, access_w, natural_m, natural_r, natural_f, natural_a);

            // Phase 2 floors: configured minimums — labels truncate (renderPill
            // clips label runs and reasoningIconSlotRects drops clipped cells).
            const floor_m = @min(natural_m, self.scaled(config.model_min_width));
            const floor_r = if (self.show_reasoning_toggle) @min(natural_r, self.scaled(config.reasoning_min_width)) else 0.0;
            const floor_f = if (self.show_fast_toggle) @min(natural_f, self.scaled(config.fast_min_width)) else 0.0;
            const floor_a = if (self.show_access_toggle) @min(natural_a, self.scaled(config.access_min_width)) else 0.0;
            self.shrinkPillsToward(avail, model_w, reasoning_w, fast_w, access_w, floor_m, floor_r, floor_f, floor_a);
        }

        /// One proportional-shrink pass: distributes the overflow across pills
        /// by how much slack each has above its floor.
        fn shrinkPillsToward(self: *const Component, avail: f32, model_w: *f32, reasoning_w: *f32, fast_w: *f32, access_w: *f32, min_m: f32, min_r: f32, min_f: f32, min_a: f32) void {
            var iter: u32 = 0;
            while (iter < 16) : (iter += 1) {
                const total = self.toolbarPillsTotalWidth(model_w.*, reasoning_w.*, fast_w.*, access_w.*);
                if (total <= avail + 0.5) return;
                const overflow = total - avail;

                const flex_m = @max(0.0, model_w.* - min_m);
                const flex_r = @max(0.0, reasoning_w.* - min_r);
                const flex_f = @max(0.0, fast_w.* - min_f);
                const flex_a = @max(0.0, access_w.* - min_a);
                const flex_sum = flex_m + flex_r + flex_f + flex_a;
                if (flex_sum <= 0.01) return;

                model_w.* -= overflow * (flex_m / flex_sum);
                reasoning_w.* -= overflow * (flex_r / flex_sum);
                fast_w.* -= overflow * (flex_f / flex_sum);
                access_w.* -= overflow * (flex_a / flex_sum);

                model_w.* = @max(model_w.*, min_m);
                reasoning_w.* = @max(reasoning_w.*, min_r);
                fast_w.* = @max(fast_w.*, min_f);
                access_w.* = @max(access_w.*, min_a);
            }
        }

        const ToolbarGeometry = struct {
            toolbar: draw.Rect,
            directory: draw.Rect,
            runtime: draw.Rect,
            model: draw.Rect,
            reasoning: draw.Rect,
            fast: draw.Rect,
            access: draw.Rect,
            send: draw.Rect,
        };

        fn toolbarGeometry(self: *const Component) ToolbarGeometry {
            const toolbar = self.toolbarRect();
            const control_h = @round(@min(toolbar.h, self.scaled(34.0)));
            const y = @round(toolbar.y + (toolbar.h - control_h) * 0.5);
            // A hidden send button collapses to a zero-width rect at the
            // toolbar's right edge so the controls extend to the edge.
            const send_size = self.sendSize(toolbar.h);
            const send_w: f32 = if (self.sendVisible()) send_size else 0.0;
            const send_offset: f32 = if (self.sendVisible()) self.sendOffset() else 0.0;
            const send: draw.Rect = snapRect(.{
                .x = toolbar.x + toolbar.w - send_w - send_offset,
                .y = toolbar.y + (toolbar.h - send_size) * 0.5,
                .w = send_w,
                .h = send_size,
            });
            if (config.merged_model_label) return self.mergedToolbarGeometry(toolbar, y, control_h, send);
            // Extra air before the send control so the rightmost pill is not visually glued to the button.
            const max_x = if (send.w > 0.0) send.x - self.scaled(config.control_gap) * 2.0 else send.x;
            const avail_total = @max(max_x - toolbar.x, 0.0);

            // The directory pill sits ahead of the shared four-pill budget: it
            // takes its natural width first and only gives ground once the
            // other pills have already collapsed to their floors.
            var directory_w: f32 = if (self.show_directory_toggle)
                self.pillWidth(true, 0.0, config.directory_icon, self.directoryLabel(), config.chevron_icon, config.directory_min_width, config.directory_max_width)
            else
                0.0;
            const directory_outside = self.directoryOutside();
            const directory_span = if (self.show_directory_toggle and !directory_outside) directory_w + self.scaled(config.control_gap) else 0.0;
            const avail = @max(avail_total - directory_span, 0.0);

            var model_w = self.pillWidth(true, 0.0, config.model_icon, self.modelLabel(), config.chevron_icon, config.model_min_width, config.model_max_width);
            var reasoning_w: f32 = if (self.show_reasoning_toggle)
                self.pillWidth(false, self.reasoningIconSlotsWidth(), "", self.reasoningLabel(), config.chevron_icon, config.reasoning_min_width, config.reasoning_max_width)
            else
                0.0;
            var fast_w: f32 = if (self.show_fast_toggle)
                self.pillWidth(true, 0.0, config.fast_icon, self.fastLabel(), "", config.fast_min_width, config.fast_max_width)
            else
                0.0;
            var access_w: f32 = if (self.show_access_toggle)
                self.pillWidth(true, 0.0, config.access_icon, self.accessLabel(), "", config.access_min_width, config.access_max_width)
            else
                0.0;

            self.shrinkToolbarPillWidthsToFit(avail, &model_w, &reasoning_w, &fast_w, &access_w);
            if (self.show_directory_toggle and !directory_outside) {
                const rest = self.toolbarPillsTotalWidth(model_w, reasoning_w, fast_w, access_w);
                const overflow = rest - avail;
                if (overflow > 0.5) {
                    directory_w = @max(directory_w - overflow, self.scaled(config.directory_min_width));
                }
            }

            var x = toolbar.x;
            var directory: draw.Rect = undefined;
            var runtime: draw.Rect = snapRect(.{ .x = toolbar.x + toolbar.w, .y = y, .w = 0.0, .h = control_h });
            if (directory_outside) {
                const strip = self.stripRects(directory_w);
                directory = strip.directory;
                runtime = strip.runtime;
            } else if (self.show_directory_toggle) {
                directory = snapRect(.{ .x = x, .y = y, .w = directory_w, .h = control_h });
                x += directory_w + self.scaled(config.control_gap);
            } else {
                directory = snapRect(.{ .x = x, .y = y, .w = 0.0, .h = control_h });
            }
            const model: draw.Rect = snapRect(.{ .x = x, .y = y, .w = model_w, .h = control_h });
            x += model_w + self.scaled(config.control_gap);

            const reasoning: draw.Rect = snapRect(.{ .x = x, .y = y, .w = reasoning_w, .h = control_h });
            x += reasoning_w;

            var fast: draw.Rect = undefined;
            if (self.show_fast_toggle) {
                x += self.scaled(config.control_gap);
                fast = snapRect(.{ .x = x, .y = y, .w = fast_w, .h = control_h });
                x += fast_w + self.scaled(config.control_gap);
            } else {
                fast = snapRect(.{ .x = x, .y = y, .w = 0.0, .h = control_h });
                x += self.scaled(config.control_gap);
            }

            // If widths still exceed the budget (all pills at mins), never let the access pill run under the send control.
            const access_max_fit = @max(0.0, max_x - x);
            access_w = @min(access_w, access_max_fit);
            const access: draw.Rect = snapRect(.{ .x = x, .y = y, .w = access_w, .h = control_h });

            return .{
                .toolbar = toolbar,
                .directory = directory,
                .runtime = runtime,
                .model = model,
                .reasoning = reasoning,
                .fast = fast,
                .access = access,
                .send = send,
            };
        }

        const StripRects = struct { directory: draw.Rect, runtime: draw.Rect };

        /// Controls on the strip under the frame: the directory control
        /// leads at its natural width and the runtime control trails at the
        /// far edge; the directory control yields first if both cannot fit.
        fn stripRects(self: *const Component, pill_directory_w: f32) StripRects {
            const strip = self.directoryStripRect();
            const strip_control_h = @round(@min(strip.h, self.scaled(34.0)));
            const strip_y = @round(strip.y + (strip.h - strip_control_h) * 0.5);
            const directory_w = if (config.strip_chips)
                @min(self.stripChipWidth(self.directoryLabel()), self.scaled(config.directory_max_width))
            else
                pill_directory_w;
            const natural_runtime_w: f32 = if (config.strip_chips)
                @min(self.stripChipWidth(self.runtimeLabel()), self.scaled(config.runtime_max_width))
            else
                self.pillWidth(true, 0.0, config.runtime_icon, self.runtimeLabel(), config.chevron_icon, config.runtime_min_width, config.runtime_max_width);
            var runtime_w: f32 = if (self.show_runtime_toggle) @min(natural_runtime_w, strip.w) else 0.0;
            const runtime_span = if (self.show_runtime_toggle) runtime_w + self.scaled(config.control_gap) else 0.0;
            const strip_directory_w = @min(directory_w, @max(strip.w - runtime_span, 0.0));
            var runtime: draw.Rect = snapRect(.{ .x = strip.x + strip.w, .y = strip_y, .w = 0.0, .h = strip_control_h });
            if (self.show_runtime_toggle) {
                runtime_w = @min(runtime_w, @max(strip.w - strip_directory_w - self.scaled(config.control_gap), 0.0));
                runtime = snapRect(.{
                    .x = strip.x + strip.w - runtime_w,
                    .y = strip_y,
                    .w = runtime_w,
                    .h = strip_control_h,
                });
            }
            return .{
                .directory = snapRect(.{ .x = strip.x, .y = strip_y, .w = strip_directory_w, .h = strip_control_h }),
                .runtime = runtime,
            };
        }

        /// Toolbar layout for `merged_model_label`: an optional inline
        /// directory pill on the left and the merged label flush against the
        /// send button (or the toolbar edge while it is hidden) on the right,
        /// split into the `.model` (logo + name)
        /// and `.reasoning` (detail + chevron) hit halves.
        fn mergedToolbarGeometry(self: *const Component, toolbar: draw.Rect, y: f32, control_h: f32, send: draw.Rect) ToolbarGeometry {
            const gap = self.scaled(config.control_gap);
            const label_right_edge = if (send.w > 0.0) send.x - gap else send.x;
            var left = toolbar.x;
            var directory: draw.Rect = snapRect(.{ .x = toolbar.x, .y = y, .w = 0.0, .h = control_h });
            var runtime: draw.Rect = snapRect(.{ .x = toolbar.x + toolbar.w, .y = y, .w = 0.0, .h = control_h });
            if (self.show_directory_toggle) {
                const directory_w = self.pillWidth(true, 0.0, config.directory_icon, self.directoryLabel(), config.chevron_icon, config.directory_min_width, config.directory_max_width);
                if (self.directoryOutside()) {
                    const strip = self.stripRects(directory_w);
                    directory = strip.directory;
                    runtime = strip.runtime;
                } else {
                    directory.w = @round(@min(directory_w, @max(send.x - gap - toolbar.x, 0.0)));
                    left += directory.w + gap;
                }
            }
            const label_right = @round(label_right_edge);
            const width = @round(@min(self.mergedLabelNaturalWidth(), @max(label_right - left, 0.0)));
            const label_x = label_right - width;
            const layout = self.mergedLabelLayout(width);
            const split_x = @round(label_x + layout.split);
            const rest: draw.Rect = snapRect(.{ .x = label_right, .y = y, .w = 0.0, .h = control_h });
            return .{
                .toolbar = toolbar,
                .directory = directory,
                .runtime = runtime,
                .model = snapRect(.{ .x = label_x, .y = y, .w = split_x - label_x, .h = control_h }),
                .reasoning = snapRect(.{ .x = split_x, .y = y, .w = label_right - split_x, .h = control_h }),
                .fast = rest,
                .access = rest,
                .send = send,
            };
        }

        const MergedLabelLayout = struct {
            name_x: f32,
            name_w: f32,
            detail_x: f32,
            detail_w: f32,
            /// Boundary between the `.model` and `.reasoning` hit halves.
            split: f32,
            /// End of the label text area, before the chevron reserve.
            area_right: f32,
            chevron_x: f32,
            chevron_w: f32,
        };

        /// Offsets (from the label's left edge) of the merged label parts at
        /// `width`. A short label clips the detail words first, then the name.
        fn mergedLabelLayout(self: *const Component, width: f32) MergedLabelLayout {
            const metrics = self.toolbarMetrics();
            const pad = self.scaled(config.pill_padding_x);
            const chevron_reserve = self.trailingChevronReserve(config.chevron_icon);
            const detail = self.mergedDetailLabel();
            const space_w = if (detail.len > 0) metrics.measureSlice(" ") else 0.0;
            const area_right = @max(width - pad - chevron_reserve, 0.0);
            const name_x = pad + self.mergedIconReserve() + self.mergedIconGap();
            const content = @max(area_right - name_x, 0.0);
            const name_w = @min(metrics.measureSlice(self.modelLabel()), content);
            const detail_w = if (detail.len > 0) @min(metrics.measureSlice(detail), @max(content - name_w - space_w, 0.0)) else 0.0;
            const chevron_w = if (chevron_reserve > 0.0) chevron_reserve - self.scaled(config.pill_chevron_gap) else 0.0;
            const split = if (!self.show_reasoning_toggle)
                width
            else if (detail_w > 0.0)
                name_x + name_w + space_w * 0.5
            else
                area_right;
            return .{
                .name_x = name_x,
                .name_w = name_w,
                .detail_x = name_x + name_w + space_w,
                .detail_w = detail_w,
                .split = split,
                .area_right = area_right,
                .chevron_x = width - pad - chevron_w,
                .chevron_w = chevron_w,
            };
        }

        fn mergedLabelNaturalWidth(self: *const Component) f32 {
            const metrics = self.toolbarMetrics();
            const detail = self.mergedDetailLabel();
            const detail_w = if (detail.len > 0) metrics.measureSlice(" ") + metrics.measureSlice(detail) else 0.0;
            return self.scaled(config.pill_padding_x) * 2.0 + self.mergedIconReserve() + self.mergedIconGap() +
                metrics.measureSlice(self.modelLabel()) + detail_w +
                self.pillToolbarLabelSlack(metrics) + self.scaled(config.pill_label_width_fudge) +
                self.trailingChevronReserve(config.chevron_icon);
        }

        const MergedLabelCells = struct { name: draw.Rect, detail: draw.Rect, chevron: draw.Rect };

        /// Absolute text/chevron cells of the merged label spanning the
        /// `.model` and `.reasoning` halves. Text cells run to the chevron
        /// reserve so measurement rounding never clips the last glyph.
        fn mergedLabelCells(self: *const Component, model: draw.Rect, reasoning: draw.Rect) MergedLabelCells {
            const right = if (reasoning.w > 0.0) reasoning.x + reasoning.w else model.x + model.w;
            const width = @max(right - model.x, 0.0);
            const layout = self.mergedLabelLayout(width);
            const area_right = model.x + layout.area_right;
            const name_x = model.x + layout.name_x;
            const detail_x = model.x + layout.detail_x;
            // With detail words the name stops at the hit split so each text
            // cell stays inside its own half.
            const name_right = if (layout.detail_w > 0.0) model.x + model.w else area_right;
            return .{
                .name = .{ .x = name_x, .y = model.y, .w = if (layout.name_w > 0.0) @max(name_right - name_x, 0.0) else 0.0, .h = model.h },
                .detail = .{ .x = detail_x, .y = model.y, .w = if (layout.detail_w > 0.0) @max(area_right - detail_x, 0.0) else 0.0, .h = model.h },
                .chevron = .{ .x = model.x + layout.chevron_x, .y = model.y, .w = layout.chevron_w, .h = model.h },
            };
        }

        fn mergedDetailLabel(self: *const Component) []const u8 {
            if (!self.show_reasoning_toggle) return "";
            return self.preview_labels.detail orelse self.model_detail_label_buffer.items;
        }

        fn mergedIconReserve(self: *const Component) f32 {
            return self.scaled(config.merged_icon_reserve orelse config.pill_overlay_icon_reserve);
        }

        fn mergedIconGap(self: *const Component) f32 {
            if (self.mergedIconReserve() <= 0.0) return 0.0;
            return self.scaled(config.merged_icon_gap orelse config.pill_icon_gap);
        }

        /// Toolbar metrics resized to `strip_font_size`; the advance callback
        /// receives the font size, so scaled metrics still measure shaped text.
        fn stripMetrics(self: *const Component) text_layout.FontMetrics {
            var metrics = self.toolbarMetrics();
            const size = config.strip_font_size orelse return metrics;
            const ratio = size / config.toolbar_font_size;
            metrics.font_size *= ratio;
            metrics.line_height *= ratio;
            if (metrics.fixed_advance) |advance| metrics.fixed_advance = advance * ratio;
            if (metrics.ascent) |ascent| metrics.ascent = ascent * ratio;
            if (metrics.descent) |descent| metrics.descent = descent * ratio;
            if (metrics.baseline) |baseline| metrics.baseline = baseline * ratio;
            return metrics;
        }

        fn stripPadX(self: *const Component) f32 {
            return self.scaled(config.strip_padding_x orelse config.pill_padding_x);
        }

        fn stripIconReserve(self: *const Component) f32 {
            return self.scaled(config.strip_icon_reserve orelse config.pill_overlay_icon_reserve);
        }

        fn stripIconGap(self: *const Component) f32 {
            if (self.stripIconReserve() <= 0.0) return 0.0;
            return self.scaled(config.strip_icon_gap orelse config.pill_icon_gap);
        }

        fn stripChevronReserve(self: *const Component) f32 {
            return if (config.strip_chevron) self.trailingChevronReserve(config.chevron_icon) else 0.0;
        }

        fn stripChipWidth(self: *const Component, label: []const u8) f32 {
            const metrics = self.stripMetrics();
            // Small slack covers renderer rounding; chips hug their label.
            const slack = self.scaled(config.pill_label_width_fudge) + metrics.font_size * 0.15;
            return self.stripPadX() * 2.0 + self.stripIconReserve() + self.stripIconGap() + metrics.measureSlice(label) + slack + self.stripChevronReserve();
        }

        fn stripChipTextRect(self: *const Component, chip: draw.Rect) draw.Rect {
            const x = chip.x + self.stripPadX() + self.stripIconReserve() + self.stripIconGap();
            return .{ .x = x, .y = chip.y, .w = @max(chip.x + chip.w - self.stripPadX() - self.stripChevronReserve() - x, 0.0), .h = chip.h };
        }

        fn separatorX(left: draw.Rect, right: draw.Rect) f32 {
            return (left.x + left.w + right.x) * 0.5;
        }

        fn snapPoint(point: draw.Vec2) draw.Vec2 {
            return .{ .x = @round(point.x), .y = @round(point.y) };
        }

        fn snapRect(rect: draw.Rect) draw.Rect {
            return .{
                .x = @round(rect.x),
                .y = @round(rect.y),
                .w = @round(rect.w),
                .h = @round(rect.h),
            };
        }
    };
}

fn setOwnedString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    out.clearRetainingCapacity();
    try out.appendSlice(allocator, value);
}

fn rectContainsY(rect: draw.Rect, y: f32, h: f32) bool {
    return y + h > rect.y and y < rect.y + rect.h;
}

fn clippedRect(rect: draw.Rect, clip: draw.Rect) ?draw.Rect {
    const x0 = @max(rect.x, clip.x);
    const y0 = @max(rect.y, clip.y);
    const x1 = @min(rect.x + rect.w, clip.x + clip.w);
    const y1 = @min(rect.y + rect.h, clip.y + clip.h);
    if (x1 <= x0 or y1 <= y0) return null;
    return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
}

test "composer prompt emits styled font-role commands" {
    const Prompt = ComposerPrompt(.{});
    var prompt = Prompt.init();
    var batch: draw.RenderBatch = .{};
    defer batch.deinit(std.testing.allocator);

    try prompt.render(std.testing.allocator, &batch);

    var icon_runs: usize = 0;
    var disclosure_arrows: usize = 0;
    var rounded_send = false;
    for (batch.commands.items) |command| {
        if (command.kind == .text) {
            for (command.text_runs) |run| {
                if (run.font_role == .icon) icon_runs += 1;
            }
        }
        if (command.kind == .triangle and command.color.a > 0.9 and command.color.r > 0.7) disclosure_arrows += 1;
        if (command.kind == .rect and command.radius >= 16.0 and command.color.g > 0.4) rounded_send = true;
    }
    try std.testing.expect(icon_runs >= 3);
    try std.testing.expect(disclosure_arrows >= 2);
    try std.testing.expect(rounded_send);
}

test "composer prompt hit tests toolbar controls" {
    const Prompt = ComposerPrompt(.{});
    var prompt = Prompt.init();

    try std.testing.expectEqual(@as(?ComposerPromptPart, .model), prompt.hitTest(.{ .x = prompt.modelRect().x + 2, .y = prompt.modelRect().y + 2 }));
    try std.testing.expectEqual(@as(?ComposerPromptPart, .reasoning), prompt.hitTest(.{ .x = prompt.reasoningRect().x + 2, .y = prompt.reasoningRect().y + 2 }));
    try std.testing.expectEqual(@as(?ComposerPromptPart, .fast), prompt.hitTest(.{ .x = prompt.fastRect().x + 2, .y = prompt.fastRect().y + 2 }));
    try std.testing.expectEqual(@as(?ComposerPromptPart, .access), prompt.hitTest(.{ .x = prompt.accessRect().x + 2, .y = prompt.accessRect().y + 2 }));
    try std.testing.expectEqual(@as(?ComposerPromptPart, .send), prompt.hitTest(.{ .x = prompt.sendButtonRect().x + 2, .y = prompt.sendButtonRect().y + 2 }));
}

test "composer prompt outside directory pill sits on a strip below the frame" {
    const Outside = ComposerPrompt(.{ .directory_outside = true, .toolbar_height = 36.0, .toolbar_gap = 8.0, .padding_y = 16.0 });
    var prompt = Outside.init();
    defer prompt.deinit(std.testing.allocator);
    prompt.setBounds(.{ .x = 0, .y = 0, .w = 600, .h = 200 });
    // Hidden pill: the frame fills the bounds and the toolbar stays inside.
    try std.testing.expectEqual(@as(f32, 200.0), prompt.frameRect().h);
    try std.testing.expectEqual(@as(f32, 0.0), prompt.directoryStripRect().h);
    prompt.setShowDirectoryToggle(true);
    const frame = prompt.frameRect();
    try std.testing.expectEqual(@as(f32, 156.0), frame.h);
    const toolbar = prompt.toolbarRect();
    try std.testing.expect(toolbar.y + toolbar.h <= frame.y + frame.h);
    try std.testing.expectEqual(toolbar.x, prompt.modelRect().x);
    const directory = prompt.directoryRect();
    try std.testing.expect(directory.y >= frame.y + frame.h);
    try std.testing.expect(directory.w > 0.0);
    try std.testing.expectEqual(@as(?ComposerPromptPart, .directory), prompt.hitTest(.{ .x = directory.x + 2, .y = directory.y + 2 }));
    // The runtime pill only exists on the strip and trails at the far edge.
    try std.testing.expectEqual(@as(f32, 0.0), prompt.runtimeRect().w);
    prompt.setShowRuntimeToggle(true);
    const runtime = prompt.runtimeRect();
    try std.testing.expect(runtime.w > 0.0);
    try std.testing.expectEqual(directory.y, runtime.y);
    try std.testing.expect(runtime.x > directory.x + directory.w);
    try std.testing.expectEqual(prompt.directoryStripRect().x + prompt.directoryStripRect().w, runtime.x + runtime.w);
    try std.testing.expectEqual(@as(?ComposerPromptPart, .runtime), prompt.hitTest(.{ .x = runtime.x + 2, .y = runtime.y + 2 }));
}

test "composer prompt directory pill is opt-in and leads the toolbar" {
    const Prompt = ComposerPrompt(.{});
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);

    // Hidden by default: nothing is reserved ahead of the model pill.
    try std.testing.expectEqual(@as(f32, 0.0), prompt.directoryRect().w);
    const model_without_directory = prompt.modelRect();

    prompt.setShowDirectoryToggle(true);
    try prompt.setDirectoryLabel(std.testing.allocator, "verde");
    const directory = prompt.directoryRect();
    try std.testing.expect(directory.w > 0.0);
    try std.testing.expect(prompt.modelRect().x > model_without_directory.x);
    try std.testing.expect(directory.x + directory.w <= prompt.modelRect().x);
    try std.testing.expectEqual(@as(?ComposerPromptPart, .directory), prompt.hitTest(.{ .x = directory.x + 2, .y = directory.y + 2 }));
    try std.testing.expectEqual(@as(?ComposerPromptPart, .model), prompt.hitTest(.{ .x = prompt.modelRect().x + 2, .y = prompt.modelRect().y + 2 }));

    var probe = ComposerProbe{};
    defer probe.clipboard.deinit(std.testing.allocator);
    prompt.setCallbacks(.{ .context = @ptrCast(&probe), .on_event = probeComposerEvent });
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = directory.x + 2, .y = directory.y + 2 } }));
    try std.testing.expectEqual(@as(usize, 1), probe.directory_clicked);
}

const ComposerProbe = struct {
    directory_clicked: usize = 0,
    text_changed: usize = 0,
    submitted: usize = 0,
    model_changed: usize = 0,
    fast_changed: usize = 0,
    access_changed: usize = 0,
    send_clicked: usize = 0,
    clipboard: std.ArrayList(u8) = .empty,
};

fn probeComposerEvent(context: ?*anyopaque, event: ComposerPromptEvent) void {
    const probe: *ComposerProbe = @ptrCast(@alignCast(context orelse return));
    switch (event) {
        .text_changed => probe.text_changed += 1,
        .submitted => probe.submitted += 1,
        .directory_clicked => probe.directory_clicked += 1,
        .runtime_clicked => {},
        .model_changed => probe.model_changed += 1,
        .fast_changed => probe.fast_changed += 1,
        .access_changed => probe.access_changed += 1,
        .send_clicked => probe.send_clicked += 1,
        else => {},
    }
}

fn probeSetClipboard(context: ?*anyopaque, text: []const u8) bool {
    const probe: *ComposerProbe = @ptrCast(@alignCast(context orelse return false));
    probe.clipboard.clearRetainingCapacity();
    probe.clipboard.appendSlice(std.testing.allocator, text) catch return false;
    return true;
}

fn probeGetClipboard(context: ?*anyopaque, allocator: std.mem.Allocator) ?[]u8 {
    const probe: *ComposerProbe = @ptrCast(@alignCast(context orelse return null));
    return allocator.dupe(u8, probe.clipboard.items) catch null;
}

fn testModelOption(_: ?*anyopaque, index: usize) []const u8 {
    return switch (index) {
        0 => "Default",
        1 => "Deep",
        else => "Fast",
    };
}

test "composer prompt owns text options toggles and send input" {
    const Prompt = ComposerPrompt(.{});
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);
    var probe: ComposerProbe = .{};
    prompt.setCallbacks(.{ .context = &probe, .on_event = probeComposerEvent });
    prompt.setModelOptions(null, 3, testModelOption);

    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = prompt.textRect().x + 2, .y = prompt.textRect().y + 2 } }));
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .text = "hello" }));
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .key = .{ .code = .enter } }));
    try std.testing.expectEqualStrings("hello\n", prompt.text());
    try std.testing.expectEqual(@as(usize, 2), probe.text_changed);

    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = prompt.modelRect().x + 2, .y = prompt.modelRect().y + 2 } }));
    try std.testing.expect(prompt.active_menu == .model);
    const row = prompt.menuRowRect(.model, 1);
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = row.x + 2, .y = row.y + 2 } }));
    try std.testing.expectEqual(@as(?usize, 1), prompt.model_index);
    try std.testing.expectEqualStrings("Deep", prompt.modelLabel());

    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = prompt.fastRect().x + 2, .y = prompt.fastRect().y + 2 } }));
    try std.testing.expect(prompt.fast_enabled);
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = prompt.accessRect().x + 2, .y = prompt.accessRect().y + 2 } }));
    try std.testing.expect(prompt.access_enabled);
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = prompt.sendButtonRect().x + 2, .y = prompt.sendButtonRect().y + 2 } }));
    try std.testing.expectEqual(@as(usize, 1), probe.send_clicked);
    try std.testing.expectEqual(@as(usize, 1), probe.submitted);
    try std.testing.expectEqual(@as(usize, 1), probe.model_changed);
    try std.testing.expectEqual(@as(usize, 1), probe.fast_changed);
    try std.testing.expectEqual(@as(usize, 1), probe.access_changed);
}

test "composer prompt copy and cut stay owned by the focused editor" {
    const Prompt = ComposerPrompt(.{});
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);
    var probe: ComposerProbe = .{};
    defer probe.clipboard.deinit(std.testing.allocator);
    prompt.setCallbacks(.{
        .context = &probe,
        .set_clipboard = probeSetClipboard,
        .get_clipboard = probeGetClipboard,
    });
    try prompt.setText(std.testing.allocator, "copy this text");
    prompt.focused = true;
    prompt.selection_anchor = 0;
    prompt.selection_focus = 4;

    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .key = .{ .code = .c, .primary = true } }));
    try std.testing.expectEqualStrings("copy", probe.clipboard.items);
    try std.testing.expectEqualStrings("copy this text", prompt.text());

    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .key = .{ .code = .x, .primary = true } }));
    try std.testing.expectEqualStrings(" this text", prompt.text());

    prompt.selection_anchor = null;
    prompt.selection_focus = null;
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .key = .{ .code = .c, .primary = true } }));
}

fn manyModelOption(_: ?*anyopaque, index: usize) []const u8 {
    return switch (index) {
        0 => "Auto",
        1 => "Composer 2",
        2 => "GPT-5.5",
        3 => "Codex 5.3",
        4 => "Sonnet 4.6",
        5 => "Opus 4.7",
        6 => "Grok 4.3",
        7 => "GPT-5.4",
        8 => "Opus 4.6",
        9 => "Opus 4.5",
        10 => "GPT-5.2",
        else => "Gemini 3.1 Pro",
    };
}

test "composer prompt model dropdown scrolls overflow rows" {
    const Prompt = ComposerPrompt(.{ .menu_max_visible_rows = 4, .row_height = 20 });
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);
    prompt.setModelOptions(null, 12, manyModelOption);

    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = prompt.modelRect().x + 2, .y = prompt.modelRect().y + 2 } }));
    try std.testing.expect(prompt.active_menu == .model);
    const menu = prompt.menuRect(.model);
    try std.testing.expectEqual(@as(?usize, 0), prompt.menuIndexAtPoint(.{ .x = menu.x + 4, .y = menu.y + 4 }));

    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_wheel = .{ .point = .{ .x = menu.x + 4, .y = menu.y + 4 }, .y = -3 } }));
    try std.testing.expect(prompt.menu_scroll_y > 0.0);
    try std.testing.expectEqual(@as(?usize, 8), prompt.menuIndexAtPoint(.{ .x = menu.x + 4, .y = menu.y + 4 }));
}

test "composer prompt drops text-input control and replacement glyphs" {
    const Prompt = ComposerPrompt(.{});
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);

    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = prompt.textRect().x + 2, .y = prompt.textRect().y + 2 } }));
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .text = "ab\r\n\xef\xbf\xbdcd" }));
    try std.testing.expectEqualStrings("abcd", prompt.text());
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .key = .{ .code = .enter } }));
    try std.testing.expectEqualStrings("abcd\n", prompt.text());
    try prompt.setText(std.testing.allocator, "one\xef\xbf\xbd\ntwo\rthree");
    try std.testing.expectEqualStrings("one\ntwothree", prompt.text());
}

fn proportionalAdvance(_: ?*anyopaque, text: []const u8, byte_offset: usize, _: f32) text_layout.Advance {
    return .{
        .byte_len = 1,
        .width = switch (text[byte_offset]) {
            'W' => 20,
            'i' => 2,
            else => 10,
        },
    };
}

test "composer prompt uses injected metrics for cursor and hit testing" {
    const Prompt = ComposerPrompt(.{ .x = 0, .y = 0, .width = 260, .height = 150 });
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);
    prompt.setFontMetrics(.{
        .font_size = 10,
        .line_height = 18,
        .advance = proportionalAdvance,
    });
    try prompt.setText(std.testing.allocator, "Wi");

    try std.testing.expectEqual(@as(f32, prompt.textRect().x + 22), prompt.cursorRect().x);
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = prompt.textRect().x + 20.4, .y = prompt.textRect().y + 2 } }));
    try std.testing.expectEqual(@as(usize, 1), prompt.cursor);
    try std.testing.expectEqual(@as(f32, prompt.textRect().x + 20), prompt.cursorRect().x);
}

test "composer prompt sizes toolbar pills from measured content" {
    const Prompt = ComposerPrompt(.{
        .width = 520,
        .height = 150,
        .pill_padding_x = 12,
        .pill_icon_gap = 4,
        .pill_chevron_gap = 3,
        .toolbar_fixed_advance = 5,
        .icon_fixed_advance = 6,
        .model_max_width = 240,
    });
    var prompt = Prompt.init();
    const model = prompt.modelRect();
    const slack = @max(8.0, 14.0 * 0.28) * 1.28;
    const trailing = 3.0 + @max(6.0, @max(16.0 * 0.82, 16.0));
    const expected = 12 * 2 + 6 + 4 + @as(f32, @floatFromInt("GPT-5.5".len)) * 5 + slack + trailing;
    // Toolbar rects are pixel-snapped.
    try std.testing.expectEqual(@round(expected), model.w);
}

test "composer prompt external menus emit clicks without opening dropdowns" {
    const Prompt = ComposerPrompt(.{});
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);
    var probe: ComposerProbe = .{};
    prompt.setCallbacks(.{ .context = &probe, .on_event = probeComposerEvent });
    prompt.setModelOptions(null, 3, testModelOption);
    prompt.setExternalModelMenu(true);
    prompt.setExternalReasoningMenu(true);

    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = prompt.modelRect().x + 2, .y = prompt.modelRect().y + 2 } }));
    try std.testing.expect(prompt.active_menu == null);
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = prompt.reasoningRect().x + 2, .y = prompt.reasoningRect().y + 2 } }));
    try std.testing.expect(prompt.active_menu == null);
}

test "composer prompt hides access pill from geometry and hit testing" {
    const Prompt = ComposerPrompt(.{});
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);
    const shown_access = prompt.accessRect();
    try std.testing.expect(shown_access.w > 0.0);

    prompt.setShowAccessToggle(false);
    try std.testing.expectEqual(@as(f32, 0.0), prompt.accessRect().w);
    try std.testing.expect(prompt.hitTest(.{ .x = shown_access.x + 2, .y = shown_access.y + 2 }) != .access);
}

test "composer prompt lays icon slot cells beside their label segments" {
    const Prompt = ComposerPrompt(.{
        .width = 800,
        .height = 150,
        .pill_padding_x = 12,
        .toolbar_fixed_advance = 5,
        .reasoning_max_width = 400,
    });
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);
    try prompt.setReasoningLabel(std.testing.allocator, "High - Fast - Full access");
    prompt.setReasoningIconSlots(&.{
        .{ .byte_offset = 7, .width = 20 },
        .{ .byte_offset = 14, .width = 20 },
    });

    const pill = prompt.reasoningRect();
    const slots = prompt.reasoningIconSlotRects();
    try std.testing.expectEqual(@as(usize, 2), slots.count);
    // First cell sits after "High - " (7 chars * 5 advance) plus padding;
    // second after the first cell plus "Fast - " (another 7 chars).
    try std.testing.expectEqual(pill.x + 47.0, slots.rects[0].x);
    try std.testing.expectEqual(slots.rects[0].x + 55.0, slots.rects[1].x);
    try std.testing.expectEqual(@as(f32, 20.0), slots.rects[0].w);

    // The reserved cells widen the pill by their combined width.
    prompt.setReasoningIconSlots(&.{});
    try std.testing.expectEqual(pill.w - 40.0, prompt.reasoningRect().w);
    try std.testing.expectEqual(@as(usize, 0), prompt.reasoningIconSlotRects().count);
}

test "composer prompt centers icon slot cells over separator spaces" {
    const Prompt = ComposerPrompt(.{
        .width = 800,
        .height = 150,
        .pill_padding_x = 12,
        .toolbar_fixed_advance = 5,
        .reasoning_max_width = 400,
    });
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);
    try prompt.setReasoningLabel(std.testing.allocator, "High · Full access");
    prompt.setReasoningIconSlots(&.{.{ .byte_offset = 4, .width = 20 }});

    const pill = prompt.reasoningRect();
    const slots = prompt.reasoningIconSlotRects();
    try std.testing.expectEqual(@as(usize, 1), slots.count);
    // Cell walks to after "High" (4 chars * 5 advance) plus padding, then is
    // nudged right by half the following space's advance (2.5) so the glyph
    // centers over the whole word gap instead of hugging "High".
    try std.testing.expectEqual(pill.x + 12.0 + 20.0 + 2.5, slots.rects[0].x);
}

test "composer prompt scrolls overflowing text and renders scrollbar" {
    const Prompt = ComposerPrompt(.{ .width = 260, .height = 122, .font_size = 10, .fixed_advance = 5, .scrollbar_width = 4 });
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);
    try prompt.setText(std.testing.allocator, "line 1\nline 2\nline 3\nline 4\nline 5\nline 6");
    prompt.focused = true;
    prompt.cursor = prompt.text().len;
    prompt.ensureCursorVisible();

    try std.testing.expect(prompt.scrollY() > 0);
    const before = prompt.scrollY();
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_wheel = .{ .point = .{ .x = prompt.textRect().x + 2, .y = prompt.textRect().y + 2 }, .y = 1 } }));
    try std.testing.expect(prompt.scrollY() < before);

    var batch: draw.RenderBatch = .{};
    defer batch.deinit(std.testing.allocator);
    try prompt.render(std.testing.allocator, &batch);
    var scrollbar_count: usize = 0;
    for (batch.commands.items) |command| {
        if (command.kind == .scrollbar) scrollbar_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), scrollbar_count);
}

test "composer prompt selects and replaces text" {
    const Prompt = ComposerPrompt(.{ .width = 320, .height = 150, .font_size = 10, .fixed_advance = 10 });
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);
    try prompt.setText(std.testing.allocator, "hello world");
    prompt.focused = true;
    prompt.cursor = 5;

    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .key = .{ .code = .left, .shift = true } }));
    try std.testing.expect(prompt.selection() != null);
    try std.testing.expectEqualStrings("o", prompt.text()[prompt.selection().?.start..prompt.selection().?.end]);
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .text = "O" }));
    try std.testing.expectEqualStrings("hellO world", prompt.text());

    const start = prompt.textRect();
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = .{ .x = start.x + 0, .y = start.y + 2 } }));
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_drag = .{ .x = start.x + 50, .y = start.y + 2 } }));
    try std.testing.expect(prompt.selection() != null);

    var batch: draw.RenderBatch = .{};
    defer batch.deinit(std.testing.allocator);
    try prompt.render(std.testing.allocator, &batch);
    var selection_count: usize = 0;
    for (batch.commands.items) |command| {
        if (command.kind == .selection) selection_count += 1;
    }
    try std.testing.expect(selection_count > 0);
}

test "composer prompt blur clears selection drag and menus" {
    const Prompt = ComposerPrompt(.{ .width = 320, .height = 150 });
    var prompt = Prompt.init();
    defer prompt.deinit(std.testing.allocator);
    prompt.focused = true;
    prompt.selection_anchor = 1;
    prompt.selection_focus = 2;
    prompt.dragging_selection = true;
    prompt.active_menu = .model;
    prompt.hovered_menu_index = 0;

    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .focus = false }));
    try std.testing.expect(!prompt.focused);
    try std.testing.expect(prompt.selection_anchor == null);
    try std.testing.expect(prompt.selection_focus == null);
    try std.testing.expect(!prompt.dragging_selection);
    try std.testing.expect(prompt.active_menu == null);
    try std.testing.expect(prompt.hovered_menu_index == null);

    prompt.selection_anchor = 3;
    prompt.selection_focus = 4;
    prompt.dragging_selection = true;
    prompt.active_menu = .reasoning;
    prompt.hovered_menu_index = 1;
    try std.testing.expect(!try prompt.handleInput(std.testing.allocator, .{ .focus = false }));
    try std.testing.expect(prompt.selection_anchor == null);
    try std.testing.expect(prompt.selection_focus == null);
    try std.testing.expect(!prompt.dragging_selection);
    try std.testing.expect(prompt.active_menu == null);
    try std.testing.expect(prompt.hovered_menu_index == null);
}

const InlineTestPrompt = ComposerPrompt(.{
    .inline_toolbar = true,
    .merged_model_label = true,
    .directory_outside = true,
    .strip_chips = true,
    .strip_height = 24,
    .strip_font_size = 12,
    .strip_icon_reserve = 14,
    .strip_chevron = false,
    .font_size = 10,
    .fixed_advance = 5,
    .toolbar_fixed_advance = 5,
    .padding_x = 16,
    .padding_y = 14,
    .toolbar_height = 32,
    .toolbar_gap = 10,
    .control_gap = 6,
    .pill_overlay_icon_reserve = 18,
});

fn initInlineTestPrompt(prompt: *InlineTestPrompt) !void {
    prompt.setShowDirectoryToggle(true);
    prompt.setShowRuntimeToggle(true);
    try prompt.setModelDetailLabel(std.testing.allocator, "High Fast");
    prompt.setBounds(.{ .x = 0, .y = 0, .w = 600, .h = prompt.preferredHeight(600, false, 1, 10) });
}

fn setTestRepeated(prompt: *InlineTestPrompt, byte: u8, count: usize) !void {
    var buf: [256]u8 = undefined;
    @memset(buf[0..count], byte);
    try prompt.setText(std.testing.allocator, buf[0..count]);
}

fn expectRectInside(inner: draw.Rect, outer: draw.Rect) !void {
    try std.testing.expect(inner.x >= outer.x and inner.y >= outer.y);
    try std.testing.expect(inner.x + inner.w <= outer.x + outer.w and inner.y + inner.h <= outer.y + outer.h);
}

test "composer prompt inline bar lays text and cluster on one row without overlap" {
    var prompt = InlineTestPrompt.init();
    defer prompt.deinit(std.testing.allocator);
    try initInlineTestPrompt(&prompt);

    try std.testing.expect(prompt.inlineActive());
    // Bar = toolbar row + padding_y; strip = strip_height + toolbar_gap.
    try std.testing.expectEqual(@as(f32, 80.0), prompt.bounds().h);
    const frame = prompt.frameRect();
    try std.testing.expectEqual(@as(f32, 46.0), frame.h);
    try std.testing.expectEqual(@as(f32, 22.0), prompt.cornerRadius());

    const text_rect = prompt.textRect();
    const model = prompt.modelRect();
    const reasoning = prompt.reasoningRect();
    const send = prompt.sendButtonRect();
    try expectRectInside(text_rect, frame);
    try expectRectInside(model, frame);
    try expectRectInside(send, frame);
    try std.testing.expect(text_rect.x + text_rect.w <= model.x);
    try std.testing.expectEqual(model.x + model.w, reasoning.x);
    try std.testing.expect(reasoning.x + reasoning.w <= send.x);
    try std.testing.expect(reasoning.w > 0.0);
    // Text and controls share one vertical centre (within pixel snapping).
    try std.testing.expect(@abs(frame.y + frame.h * 0.5 - (text_rect.y + text_rect.h * 0.5)) <= 1.0);
    try std.testing.expectEqual(frame.y + frame.h * 0.5, send.y + send.h * 0.5);

    // Strip chips sit under the frame at the configured strip height.
    const strip = prompt.directoryStripRect();
    try std.testing.expectEqual(@as(f32, 24.0), strip.h);
    try std.testing.expect(strip.y >= frame.y + frame.h);
    try expectRectInside(prompt.directoryRect(), strip);
    try expectRectInside(prompt.runtimeRect(), strip);
    try std.testing.expect(prompt.directoryRect().x + prompt.directoryRect().w < prompt.runtimeRect().x);

    // The caret sits inside the inline column.
    try prompt.setText(std.testing.allocator, "hello");
    try expectRectInside(prompt.cursorRect(), prompt.textRect());
}

test "composer prompt stacks when the draft outgrows the inline column without oscillating" {
    var prompt = InlineTestPrompt.init();
    defer prompt.deinit(std.testing.allocator);
    try initInlineTestPrompt(&prompt);
    const inline_frame = prompt.frameRect();
    const inline_send = prompt.sendButtonRect();
    const inline_text_w = prompt.textRect().w;
    const fit_count: usize = @intFromFloat(@floor(inline_text_w / 5.0));

    // Exactly filling the inline column stays inline at the bar height.
    try setTestRepeated(&prompt, 'a', fit_count);
    try std.testing.expect(prompt.inlineActive());
    try std.testing.expectEqual(@as(f32, 80.0), prompt.preferredHeight(600, false, 1, 10));

    // One more glyph stacks, both at the old bar height and after the host
    // resizes to the stacked preferred height.
    try setTestRepeated(&prompt, 'a', fit_count + 1);
    try std.testing.expect(!prompt.inlineActive());
    const stacked_h = prompt.preferredHeight(600, false, 1, 10);
    try std.testing.expect(stacked_h > 80.0);
    prompt.setBounds(.{ .x = 0, .y = 80 - stacked_h, .w = 600, .h = stacked_h });
    try std.testing.expect(!prompt.inlineActive());
    try std.testing.expectEqual(stacked_h, prompt.preferredHeight(600, false, 1, 10));
    try std.testing.expectEqual(@as(f32, 14.0), prompt.cornerRadius());

    // Full-width text over a toolbar row that keeps the inline insets.
    const frame = prompt.frameRect();
    const text_rect = prompt.textRect();
    const send = prompt.sendButtonRect();
    try std.testing.expectEqual(frame.w - 32.0, text_rect.w);
    try std.testing.expect(text_rect.y + text_rect.h <= prompt.toolbarRect().y);
    try std.testing.expectEqual(inline_frame.y + inline_frame.h - (inline_send.y + inline_send.h), frame.y + frame.h - (send.y + send.h));
    try std.testing.expectEqual(inline_frame.x + inline_frame.w - (inline_send.x + inline_send.w), frame.x + frame.w - (send.x + send.w));
    try std.testing.expectEqual(prompt.modelRect().y + prompt.modelRect().h * 0.5, send.y + send.h * 0.5);
    try expectRectInside(prompt.cursorRect(), text_rect);

    // Deleting back under the limit returns to inline at any bounds height.
    try setTestRepeated(&prompt, 'a', fit_count);
    try std.testing.expect(prompt.inlineActive());
    prompt.setBounds(.{ .x = 0, .y = 0, .w = 600, .h = prompt.preferredHeight(600, false, 1, 10) });
    try std.testing.expect(prompt.inlineActive());

    // A newline always stacks, even for a short draft.
    try prompt.setText(std.testing.allocator, "a\nb");
    try std.testing.expect(!prompt.inlineActive());
}

test "composer prompt placeholder never forces the stacked layout" {
    var prompt = InlineTestPrompt.init();
    defer prompt.deinit(std.testing.allocator);
    try initInlineTestPrompt(&prompt);
    var long_placeholder: [240]u8 = undefined;
    @memset(&long_placeholder, 'p');
    try prompt.setPlaceholder(std.testing.allocator, &long_placeholder);

    try std.testing.expect(prompt.inlineActive());
    try std.testing.expectEqual(@as(f32, 80.0), prompt.preferredHeight(600, false, 1, 10));
    try std.testing.expectEqual(@as(f32, 80.0), prompt.preferredHeight(600, true, 1, 10));

    // Previews ignore the live draft and mirror preferredHeight(empty).
    try setTestRepeated(&prompt, 'a', 200);
    try std.testing.expect(!prompt.inlineActive());
    const preview = prompt.previewGeometry(.{ .x = 10, .y = 20, .w = 600, .h = 80 }, .{ .model = "Other model", .detail = "Low" });
    try std.testing.expect(preview.inline_active);
    try std.testing.expectEqual(@as(f32, 46.0), preview.frame.h);
    try std.testing.expect(preview.text.x + preview.text.w <= preview.model.x);
    try std.testing.expect(preview.model_text.w > 0.0 and preview.detail_text.w > 0.0);
    try std.testing.expect(!prompt.inlineActive());

    // Too narrow for the minimum inline column: always stacked.
    try std.testing.expect(!prompt.previewGeometry(.{ .x = 0, .y = 0, .w = 300, .h = 120 }, .{}).inline_active);
}

test "composer prompt merged label maps name to model and detail to reasoning" {
    var prompt = InlineTestPrompt.init();
    defer prompt.deinit(std.testing.allocator);
    try initInlineTestPrompt(&prompt);
    const layout = prompt.layoutGeometry();

    try expectRectInside(layout.model_text, layout.model);
    try std.testing.expect(layout.detail_text.x >= layout.reasoning.x);
    try std.testing.expect(layout.chevron.x >= layout.reasoning.x);
    try expectRectInside(layout.model_icon, layout.model);
    try std.testing.expectEqual(@as(f32, 18.0), layout.model_icon.w);
    try std.testing.expectEqual(@as(f32, 14.0), layout.directory_icon.w);
    try std.testing.expect(layout.directory_text.x > layout.directory_icon.x + layout.directory_icon.w);
    try std.testing.expectEqual(@as(usize, 0), prompt.reasoningIconSlotRects().count);

    const name_point: draw.Vec2 = .{ .x = layout.model_text.x + 2, .y = layout.model_text.y + layout.model_text.h * 0.5 };
    const detail_point: draw.Vec2 = .{ .x = layout.detail_text.x + 2, .y = layout.detail_text.y + layout.detail_text.h * 0.5 };
    try std.testing.expectEqual(@as(?ComposerPromptPart, .model), prompt.hitTest(name_point));
    try std.testing.expectEqual(@as(?ComposerPromptPart, .reasoning), prompt.hitTest(detail_point));
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = detail_point }));
    try std.testing.expect(prompt.active_menu == .reasoning);
    try std.testing.expect(try prompt.handleInput(std.testing.allocator, .{ .mouse_down = name_point }));
    try std.testing.expect(prompt.active_menu == .model);

    // Without detail words the chevron alone opens run settings.
    try prompt.setModelDetailLabel(std.testing.allocator, "");
    const bare = prompt.layoutGeometry();
    try std.testing.expectEqual(@as(f32, 0.0), bare.detail_text.w);
    try std.testing.expect(bare.reasoning.w > 0.0);
    try std.testing.expectEqual(@as(?ComposerPromptPart, .reasoning), prompt.hitTest(.{ .x = bare.chevron.x + 1, .y = bare.chevron.y + 2 }));

    // Rendering emits the muted detail run.
    try prompt.setModelDetailLabel(std.testing.allocator, "High");
    var batch: draw.RenderBatch = .{};
    defer batch.deinit(std.testing.allocator);
    try prompt.render(std.testing.allocator, &batch);
    var detail_runs: usize = 0;
    for (batch.commands.items) |command| {
        if (command.kind != .text) continue;
        for (command.text_runs) |run| {
            if (std.mem.eql(u8, run.text[run.byte_start..run.byte_end], "High")) detail_runs += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), detail_runs);
}

const RunningOnlySendPrompt = ComposerPrompt(.{
    .inline_toolbar = true,
    .merged_model_label = true,
    .send_button = .running_only,
    .font_size = 10,
    .fixed_advance = 5,
    .toolbar_fixed_advance = 5,
    .padding_x = 16,
    .padding_y = 14,
    .toolbar_height = 32,
    .toolbar_gap = 10,
    .control_gap = 6,
    .pill_overlay_icon_reserve = 18,
});

test "composer prompt running-only send button hides while idle without overlap" {
    var prompt = RunningOnlySendPrompt.init();
    defer prompt.deinit(std.testing.allocator);
    // One click target: no reasoning half, no detail words.
    prompt.setShowReasoningToggle(false);
    prompt.setBounds(.{ .x = 0, .y = 0, .w = 600, .h = prompt.preferredHeight(600, false, 1, 10) });

    try std.testing.expect(prompt.inlineActive());
    const frame = prompt.frameRect();
    const idle = prompt.layoutGeometry();
    try std.testing.expectEqual(@as(f32, 0.0), idle.send.w);
    try std.testing.expectEqual(@as(f32, 0.0), idle.reasoning.w);
    try expectRectInside(idle.model, frame);
    try std.testing.expect(idle.text.x + idle.text.w <= idle.model.x);
    // The label becomes the right-most control, flush with the toolbar edge.
    try std.testing.expectEqual(idle.toolbar.x + idle.toolbar.w, idle.model.x + idle.model.w);
    const chevron_point: draw.Vec2 = .{ .x = idle.chevron.x + 1, .y = idle.chevron.y + idle.chevron.h * 0.5 };
    try std.testing.expectEqual(@as(?ComposerPromptPart, .model), prompt.hitTest(chevron_point));
    try std.testing.expectEqual(@as(?ComposerPromptPart, .model), prompt.hitTest(.{ .x = idle.model_text.x + 1, .y = chevron_point.y }));

    // Idle render draws no send panel: only the frame fills the toolbar row.
    var batch: draw.RenderBatch = .{};
    defer batch.deinit(std.testing.allocator);
    try prompt.render(std.testing.allocator, &batch);
    for (batch.commands.items) |command| {
        if (command.kind != .rect) continue;
        try std.testing.expect(!(command.rect.w == 32.0 and command.rect.h == 32.0));
    }

    // A running turn brings the stop button back beside the label.
    prompt.setSendState(.stop);
    const running = prompt.layoutGeometry();
    try std.testing.expect(running.send.w > 0.0);
    try expectRectInside(running.send, frame);
    try std.testing.expect(running.model.x + running.model.w <= running.send.x);
    try std.testing.expect(running.text.x + running.text.w <= running.model.x);
    try std.testing.expectEqual(@as(?ComposerPromptPart, .send), prompt.hitTest(.{ .x = running.send.x + running.send.w * 0.5, .y = running.send.y + running.send.h * 0.5 }));

    // Previews take the pane's own send state.
    const preview = prompt.previewGeometry(.{ .x = 0, .y = 0, .w = 600, .h = 46 }, .{ .send_state = .send });
    try std.testing.expectEqual(@as(f32, 0.0), preview.send.w);
    try std.testing.expectEqual(preview.toolbar.x + preview.toolbar.w, preview.model.x + preview.model.w);

    // Label-active keeps the hover fill while a host popover is open.
    prompt.setSendState(.send);
    prompt.setLabelActive(true);
    var active_batch: draw.RenderBatch = .{};
    defer active_batch.deinit(std.testing.allocator);
    try prompt.render(std.testing.allocator, &active_batch);
    var label_fills: usize = 0;
    for (active_batch.commands.items) |command| {
        if (command.kind == .rect and command.rect.x == idle.model.x and command.rect.w == idle.model.w and command.rect.y == idle.model.y) label_fills += 1;
    }
    try std.testing.expect(label_fills >= 1);
}
