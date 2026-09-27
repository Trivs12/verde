//! Command palette overlay (Ctrl+Shift+P): a Raycast-style launcher mixing static
//! commands, thread history search, and workspace switching in one ranked
//! list. The static command set is the `STATIC_COMMANDS` table below — adding
//! a palette entry is adding one row there. Dynamic results (threads,
//! workspaces) come from the collector functions in `rebuildResults`.
//!
//! Input routing lives in `layout.zig` (modal hits, text editing) and
//! `main.zig` (keybind dispatch); this module owns result building, layout,
//! rendering, and activation.

const std = @import("std");
const palette = @import("palette");
const sdl = @import("zsdl3");
const theme = @import("theme.zig");
const runtime = @import("runtime.zig");
const sidebar = @import("sidebar.zig");
const context_menu = @import("context_menu.zig");
const text_measure = @import("text_measure.zig");
const workspace_panes = @import("workspace_panes.zig");
const native_state = @import("../state.zig");
const app_config = @import("../app/config.zig");
const keybinds = @import("../app/keybinds.zig");
const platform_runtime = @import("platform_runtime");
const Provider = native_state.Provider;
const AgentProvider = native_state.AgentTuiProvider;
const AgentTuiHistoryProvider = native_state.AgentTuiHistoryProvider;

const log = std.log.scoped(.native_ui_command_palette);

/// Hard cap on rendered rows per frame; results beyond this are reachable by
/// narrowing the query, matching how launcher UIs bound their lists.
const MAX_ROWS: usize = 64;
/// Scratch candidate pool scored before the top results are taken.
const MAX_CANDIDATES: usize = 512;

/// Canvas-to-app scale for the palette's design values (same factor as
/// `DESIGN_SCALE` in sidebar.zig): the design draws body text at 15px where
/// the app uses 18 UI units, so a design px is 1.2 UI units. Constants
/// suffixed `_CSS` below are design px and go through `designUi`.
const DESIGN_SCALE: f32 = 18.0 / 15.0;

fn designUi(px: f32) f32 {
    return theme.scaledUi(px * DESIGN_SCALE);
}

// Dialog shell.
const DIALOG_W_CSS: f32 = 640.0;
const DIALOG_H_CSS: f32 = 560.0;
/// Distance from the window top on tall windows; shorter windows scale down.
const DIALOG_TOP_CSS: f32 = 110.0;
const DIALOG_MARGIN_CSS: f32 = 16.0;
const DIALOG_RADIUS_CSS: f32 = 16.0;
/// Scrim strength behind the dialog (matches the Settings sheet).
const SCRIM_ALPHA: f32 = 0.22;
// Search row.
const SEARCH_ROW_H_CSS: f32 = 56.0;
const SEARCH_PAD_X_CSS: f32 = 18.0;
const SEARCH_ICON_CSS: f32 = 17.0;
const SEARCH_GAP_CSS: f32 = 12.0;
const SEARCH_FONT_CSS: f32 = 16.0;
const SCOPE_FONT_CSS: f32 = 12.0;
/// `layout.zig` hit-tests modal text from `rect.x + 10` UI units, so the
/// registered input rect starts this far left of the drawn query text.
const MODAL_TEXT_INSET_UI: f32 = 10.0;
// Result list.
const LIST_PAD_CSS: f32 = 8.0;
const ROW_GAP_CSS: f32 = 1.0;
const ROW_H_CSS: f32 = 38.0;
/// Chat rows carry a second "workspace · age" line.
const ROW_TWO_LINE_H_CSS: f32 = 44.0;
const HEADER_FIRST_H_CSS: f32 = 28.0;
const HEADER_H_CSS: f32 = 34.0;
const HEADER_FONT_CSS: f32 = 12.0;
const HEADER_BOTTOM_PAD_CSS: f32 = 4.0;
const ROW_RADIUS_CSS: f32 = 9.0;
const ROW_PAD_X_CSS: f32 = 10.0;
const ROW_ICON_CSS: f32 = 16.0;
const ROW_ICON_GAP_CSS: f32 = 12.0;
const ROW_FONT_CSS: f32 = 14.0;
const ROW_META_FONT_CSS: f32 = 12.0;
const TAG_FONT_CSS: f32 = 11.5;
const TAG_PAD_X_CSS: f32 = 6.0;
const TAG_RADIUS_CSS: f32 = 5.0;
/// Provider bitmap drawn by `sidebar.queuePaletteProviderGlyph` (UI units).
const PROVIDER_GLYPH_UI: f32 = 22.0;
// Footer key hints.
const FOOTER_H_CSS: f32 = 40.0;
const FOOTER_GAP_CSS: f32 = 16.0;
const FOOTER_FONT_CSS: f32 = 12.0;
const FOOTER_KEY_GAP_CSS: f32 = 5.0;
// Action submenu (Right/Tab on a chat row).
const ACTION_MENU_W_CSS: f32 = 200.0;
// Neutral panel→text tints for fills (see `panelTint`).
const SELECTED_TINT: f32 = 0.06;
const HOVER_TINT: f32 = 0.035;
const DIVIDER_TINT: f32 = 0.07;
const SCROLL_THUMB_TINT: f32 = 0.22;
/// Longest title prefix measured for match highlighting; longer titles are
/// ellipsized well before this at any dialog width.
const MAX_HIGHLIGHT_BYTES: usize = 256;
const ELLIPSIS = "\u{2026}";

// Lucide (ISC) glyphs drawn through the `icon_alt` role.
const LU_SEARCH = "\u{E151}";
const LU_CHEVRON_RIGHT = "\u{E06F}";
const LU_FOLDER = "\u{E0D7}";
const LU_FOLDER_OPEN = "\u{E247}";
const LU_FOLDER_PLUS = "\u{E0D9}";
const LU_FOLDER_X = "\u{E33E}";
const LU_ARCHIVE = "\u{E041}";
const LU_ARCHIVE_RESTORE = "\u{E2CD}";
const LU_MESSAGE_SQUARE_PLUS = "\u{E40C}";
const LU_BOT = "\u{E1BB}";
const LU_SLIDERS = "\u{E29A}";
const LU_PENCIL = "\u{E1F9}";
const LU_WAND = "\u{E357}";
const LU_REFRESH = "\u{E145}";
const LU_ARROW_LEFT_RIGHT = "\u{E24A}";
const LU_SQUARE_TERMINAL = "\u{E20A}";
const LU_DOWNLOAD = "\u{E0B2}";
const LU_COLUMNS_2 = "\u{E098}";
const LU_ROWS_2 = "\u{E439}";
const LU_COLUMNS_3 = "\u{E099}";
const LU_CHEVRONS_LEFT_RIGHT = "\u{E293}";
const LU_GLOBE = "\u{E0E8}";
const LU_PLUS = "\u{E13D}";
const LU_COPY = "\u{E09E}";
const LU_PIN = "\u{E259}";
const LU_ARROW_LEFT = "\u{E048}";
const LU_ARROW_RIGHT = "\u{E049}";
const LU_X = "\u{E1B2}";
const LU_MAXIMIZE = "\u{E113}";
const LU_MINIMIZE = "\u{E11B}";
const LU_PIP = "\u{E3AF}";
const LU_DOCK = "\u{E455}";
const LU_LAPTOP = "\u{E1CD}";
const LU_SETTINGS = "\u{E154}";
const LU_SMARTPHONE = "\u{E163}";
const LU_UNLINK = "\u{E19C}";
const LU_HISTORY = "\u{E1F5}";
const LU_PANEL_LEFT = "\u{E12A}";
const LU_CORNER_DOWN_LEFT = "\u{E0A1}";
// macOS modifier symbols, drawn as Lucide glyphs (see `queueShortcutHint`).
const LU_COMMAND = "\u{E09A}";
const LU_SHIFT = "\u{E1E4}";
const LU_OPTION = "\u{E1F8}";
const LU_CONTROL = "\u{E070}";

const Section = enum { threads, panes, workspaces, app };

fn sectionName(section: Section) []const u8 {
    return switch (section) {
        .threads => "threads",
        .panes => "panes",
        .workspaces => "workspaces",
        .app => "app",
    };
}

/// One static palette entry. `keywords` are extra fuzzy-match terms beyond
/// the title; `keybind` selects which loaded accelerator to show as a hint.
const Command = struct {
    id: []const u8,
    title: []const u8,
    keywords: []const u8 = "",
    section: Section = .app,
    /// Leading Lucide glyph for the row.
    icon: []const u8 = LU_CHEVRON_RIGHT,
    keybind: ?KeybindRef = null,
    enabled: *const fn (state: *runtime.AppState) bool = alwaysEnabled,
    run: *const fn (state: *runtime.AppState) void,
    /// History/scope commands re-target the palette instead of leaving it.
    keeps_open: bool = false,
};

/// Names the keybind-config slice used for a command's accelerator hint, so
/// hints stay correct when the user rebinds in verde.json.
const KeybindRef = enum {
    new_thread,
    chat_model_picker,
    chat_run_config,
    chat_directory_picker,
    settings,
    toggle_sidebar,
    toggle_browser,
    toggle_terminal,
    workspace_close,
    workspace_close_current,
    workspace_toggle_maximize,
    workspace_toggle_quick_pane,
    workspace_split_chat_vertical,
    workspace_split_chat_horizontal,
    workspace_split_terminal_vertical,
    workspace_split_terminal_horizontal,
    workspace_previous_pane,
    workspace_next_pane,
};

/// Static command table — add a row here to add a palette entry.
const STATIC_COMMANDS = [_]Command{
    .{ .id = "thread.new", .title = "New Chat", .keywords = "thread conversation start", .section = .threads, .icon = LU_MESSAGE_SQUARE_PLUS, .keybind = .new_thread, .run = runNewChat, .enabled = hasProjects },
    .{ .id = "thread.choose_model", .title = "Choose Chat Model", .keywords = "provider initial picker", .section = .threads, .icon = LU_BOT, .keybind = .chat_model_picker, .run = runChooseChatModel, .enabled = hasFocusedGuiChat },
    .{ .id = "thread.run_config", .title = "Configure Reasoning and Run Settings", .keywords = "effort speed access permissions", .section = .threads, .icon = LU_SLIDERS, .keybind = .chat_run_config, .run = runChatRunConfig, .enabled = hasFocusedGuiChat },
    .{ .id = "thread.choose_directory", .title = "Choose Chat Working Directory", .keywords = "cwd folder path scratch home project", .section = .threads, .icon = LU_FOLDER_OPEN, .keybind = .chat_directory_picker, .run = runChooseChatDirectory, .enabled = hasFocusedGuiChat },
    .{ .id = "thread.rename_current", .title = "Rename Current Chat", .keywords = "thread title label", .section = .threads, .icon = LU_PENCIL, .run = runRenameCurrentChat, .enabled = currentThreadCommitted },
    .{ .id = "thread.regenerate_title", .title = "Regenerate Chat Title", .keywords = "thread rename luna automatic", .section = .threads, .icon = LU_WAND, .run = runRegenerateChatTitle, .enabled = canRegenerateChatTitle },
    .{ .id = "thread.sync_current", .title = "Sync Current Thread", .keywords = "refresh provider", .section = .threads, .icon = LU_REFRESH, .run = runSyncCurrentThread, .enabled = canSyncCurrentThread },
    .{ .id = "thread.handoff_current", .title = "Handoff Current Chat or TUI", .keywords = "transfer provider model agent continue context", .section = .threads, .icon = LU_ARROW_LEFT_RIGHT, .run = runHandoffCurrent, .enabled = canHandoffFocusedPane },
    .{ .id = "thread.open_current_codex_tui", .title = "Open Codex TUI for Current Thread", .keywords = "open codex tui current thread terminal resume active focused", .section = .threads, .icon = LU_SQUARE_TERMINAL, .run = runOpenCurrentThreadInTui, .enabled = canOpenFocusedCodexThreadInTui },
    .{ .id = "thread.open_current_tui", .title = "Open Current Thread in TUI", .keywords = "open agent tui current thread opencode claude cursor terminal resume active focused", .section = .threads, .icon = LU_SQUARE_TERMINAL, .run = runOpenCurrentThreadInTui, .enabled = canOpenFocusedNonCodexThreadInTui },
    .{ .id = "thread.archive_current", .title = "Archive Current Thread", .keywords = "delete remove chat", .section = .threads, .icon = LU_ARCHIVE, .run = runArchiveCurrentThread, .enabled = currentThreadNotPending },
    .{ .id = "thread.import_codex", .title = "Import Codex Thread", .keywords = "resume session", .section = .threads, .icon = LU_DOWNLOAD, .run = runImportCodex, .enabled = hasProjects },
    .{ .id = "thread.import_opencode", .title = "Import OpenCode Thread", .keywords = "resume session", .section = .threads, .icon = LU_DOWNLOAD, .run = runImportOpencode, .enabled = hasProjects },
    .{ .id = "thread.import_claude", .title = "Import Claude Thread", .keywords = "resume session", .section = .threads, .icon = LU_DOWNLOAD, .run = runImportClaude, .enabled = hasProjects },
    .{ .id = "pane.split_chat_right", .title = "Split Chat Right", .keywords = "vsplit vertical pane", .section = .panes, .icon = LU_COLUMNS_2, .keybind = .workspace_split_chat_vertical, .run = runSplitChatRight, .enabled = hasProjects },
    .{ .id = "pane.split_chat_down", .title = "Split Chat Down", .keywords = "hsplit horizontal pane stacked", .section = .panes, .icon = LU_ROWS_2, .keybind = .workspace_split_chat_horizontal, .run = runSplitChatDown, .enabled = hasProjects },
    .{ .id = "pane.split_terminal_right", .title = "Split Terminal Right", .keywords = "vsplit vertical shell", .section = .panes, .icon = LU_COLUMNS_2, .keybind = .workspace_split_terminal_vertical, .run = runSplitTerminalRight, .enabled = hasProjects },
    .{ .id = "pane.split_terminal_down", .title = "Split Terminal Down", .keywords = "hsplit horizontal shell stacked", .section = .panes, .icon = LU_ROWS_2, .keybind = .workspace_split_terminal_horizontal, .run = runSplitTerminalDown, .enabled = hasProjects },
    .{ .id = "pane.terminal", .title = "Open Terminal Pane", .keywords = "shell console", .section = .panes, .icon = LU_SQUARE_TERMINAL, .keybind = .toggle_terminal, .run = runOpenTerminal, .enabled = hasProjects },
    .{ .id = "pane.browser", .title = "Toggle Browser Pane", .keywords = "web url", .section = .panes, .icon = LU_GLOBE, .keybind = .toggle_browser, .run = runToggleBrowser, .enabled = hasProjects },
    .{ .id = "browser.tab.new", .title = "Browser: New Tab", .keywords = "web page create", .section = .panes, .icon = LU_PLUS, .run = runNewBrowserTab, .enabled = hasBrowserPane },
    .{ .id = "browser.tab.duplicate", .title = "Browser: Duplicate Active Tab", .keywords = "web page copy", .section = .panes, .icon = LU_COPY, .run = runDuplicateBrowserTab, .enabled = hasBrowserTab },
    .{ .id = "browser.tab.pin", .title = "Browser: Pin or Unpin Active Tab", .keywords = "web page keep", .section = .panes, .icon = LU_PIN, .run = runToggleBrowserTabPinned, .enabled = hasBrowserTab },
    .{ .id = "browser.tab.move_left", .title = "Browser: Move Active Tab Left", .keywords = "web page reorder", .section = .panes, .icon = LU_ARROW_LEFT, .run = runMoveBrowserTabLeft, .enabled = canMoveBrowserTabLeft },
    .{ .id = "browser.tab.move_right", .title = "Browser: Move Active Tab Right", .keywords = "web page reorder", .section = .panes, .icon = LU_ARROW_RIGHT, .run = runMoveBrowserTabRight, .enabled = canMoveBrowserTabRight },
    .{ .id = "browser.tab.close", .title = "Browser: Close Active Tab", .keywords = "web page remove", .section = .panes, .icon = LU_X, .run = runCloseBrowserTab, .enabled = hasBrowserTab },
    .{ .id = "pane.close", .title = "Close Pane", .section = .panes, .icon = LU_X, .keybind = .workspace_close, .run = runClosePane, .enabled = hasProjects },
    .{ .id = "pane.zoom", .title = "Zoom Pane", .keywords = "maximize restore fullscreen", .section = .panes, .icon = LU_MAXIMIZE, .keybind = .workspace_toggle_maximize, .run = runZoomPane, .enabled = hasProjects },
    .{ .id = "pane.previous", .title = "Previous Pane", .keywords = "niri scroll focus left up back", .section = .panes, .icon = LU_ARROW_LEFT, .keybind = .workspace_previous_pane, .run = runPreviousPane, .enabled = canFocusPreviousPane },
    .{ .id = "pane.next", .title = "Next Pane", .keywords = "niri scroll focus right down forward", .section = .panes, .icon = LU_ARROW_RIGHT, .keybind = .workspace_next_pane, .run = runNextPane, .enabled = canFocusNextPane },
    .{ .id = "pane.float", .title = "Float Focused Pane", .keywords = "quick scratch overlay", .section = .panes, .icon = LU_PIP, .run = runFloatPane, .enabled = hasProjects },
    .{ .id = "pane.quick_toggle", .title = "New or Toggle Quick Terminal", .keywords = "create show hide scratch floating overlay", .section = .panes, .icon = LU_SQUARE_TERMINAL, .keybind = .workspace_toggle_quick_pane, .run = runToggleQuickPane, .enabled = hasProjects },
    .{ .id = "pane.quick_maximize", .title = "Maximize or Restore Quick Pane", .keywords = "floating overlay", .section = .panes, .icon = LU_MAXIMIZE, .run = runMaximizeQuickPane, .enabled = hasQuickPane },
    .{ .id = "pane.quick_minimize", .title = "Minimize Quick Pane", .keywords = "hide floating overlay", .section = .panes, .icon = LU_MINIMIZE, .run = runMinimizeQuickPane, .enabled = hasQuickPane },
    .{ .id = "pane.quick_pin", .title = "Pin or Unpin Quick Pane", .keywords = "floating dim backdrop", .section = .panes, .icon = LU_PIN, .run = runPinQuickPane, .enabled = hasQuickPane },
    .{ .id = "pane.quick_tile", .title = "Return Quick Pane to Tile", .keywords = "dock floating", .section = .panes, .icon = LU_DOCK, .run = runTileQuickPane, .enabled = hasQuickPane },
    .{ .id = "workspace.scrolling_use_global", .title = "Scrolling Layout: Use Global Default", .keywords = "niri panes mode inherit reset", .section = .workspaces, .icon = LU_COLUMNS_3, .run = runScrollingUseGlobal, .enabled = hasProjects },
    .{ .id = "workspace.scrolling_automatic", .title = "Scrolling Layout: Automatic", .keywords = "niri panes mode threshold tiled", .section = .workspaces, .icon = LU_COLUMNS_3, .run = runScrollingAutomatic, .enabled = hasProjects },
    .{ .id = "workspace.scrolling_always", .title = "Scrolling Layout: Always", .keywords = "niri panes mode pin enable", .section = .workspaces, .icon = LU_COLUMNS_3, .run = runScrollingAlways, .enabled = hasProjects },
    .{ .id = "workspace.scrolling_disabled", .title = "Scrolling Layout: Disabled", .keywords = "niri panes mode tiled off disable", .section = .workspaces, .icon = LU_COLUMNS_3, .run = runScrollingDisabled, .enabled = hasProjects },
    .{ .id = "workspace.scrolling_reset_column_width", .title = "Reset Scrolling Pane Widths", .keywords = "niri panes resize default per view", .section = .workspaces, .icon = LU_CHEVRONS_LEFT_RIGHT, .run = runResetScrollingColumnWidth, .enabled = hasCustomScrollingColumnWidth },
    .{ .id = "workspace.runtime_default_current", .title = "Use Current Chat Runtime as Workspace Default", .keywords = "local remote new chat thread route", .section = .workspaces, .icon = LU_LAPTOP, .run = runUseCurrentRuntimeDefault, .enabled = hasFocusedGuiChat },
    .{ .id = "workspace.runtime_default_local", .title = "Use Local as Workspace Runtime Default", .keywords = "remote new chat thread route reset", .section = .workspaces, .icon = LU_LAPTOP, .run = runUseLocalRuntimeDefault, .enabled = hasProjects },
    .{ .id = "workspace.open_settings", .title = "Workspace: Open Settings", .keywords = "default runtime local remote profile connections configure", .section = .workspaces, .icon = LU_SETTINGS, .run = runOpenWorkspaceSettings, .enabled = hasCommandTargetProject },
    .{ .id = "workspace.add", .title = "Add Workspace", .keywords = "new project folder directory create", .section = .workspaces, .icon = LU_FOLDER_PLUS, .run = runAddWorkspace },
    .{ .id = "workspace.rename", .title = "Rename Workspace", .keywords = "label", .section = .workspaces, .icon = LU_PENCIL, .run = runRenameWorkspace, .enabled = hasProjects },
    .{ .id = "workspace.close", .title = "Close Workspace", .keywords = "archive remove project save state", .section = .workspaces, .icon = LU_FOLDER_X, .keybind = .workspace_close_current, .run = runCloseWorkspace, .enabled = workspaceNotBusy },
    .{ .id = "workspace.reopen", .title = "Reopen Last Closed Workspace", .keywords = "restore archived project", .section = .workspaces, .icon = LU_ARCHIVE_RESTORE, .run = runReopenWorkspace, .enabled = hasClosedWorkspaces },
    .{ .id = "workspace.codex_tui", .title = "Start New Codex TUI", .keywords = "agent terminal workspace fresh openai", .section = .workspaces, .icon = LU_SQUARE_TERMINAL, .run = runOpenCodexTui, .enabled = hasProjects },
    .{ .id = "workspace.claude_tui", .title = "Start New Claude TUI", .keywords = "agent terminal workspace fresh anthropic claude code", .section = .workspaces, .icon = LU_SQUARE_TERMINAL, .run = runOpenClaudeTui, .enabled = hasProjects },
    .{ .id = "workspace.opencode_tui", .title = "Start New OpenCode TUI", .keywords = "agent terminal workspace fresh opencode", .section = .workspaces, .icon = LU_SQUARE_TERMINAL, .run = runOpenOpencodeTui, .enabled = hasProjects },
    .{ .id = "workspace.cursor_tui", .title = "Start New Cursor TUI", .keywords = "agent terminal workspace fresh cursor agent", .section = .workspaces, .icon = LU_SQUARE_TERMINAL, .run = runOpenCursorTui, .enabled = hasProjects },
    .{ .id = "workspace.grok_tui", .title = "Start New Grok TUI", .keywords = "agent terminal workspace fresh xai grok build", .section = .workspaces, .icon = LU_SQUARE_TERMINAL, .run = runOpenGrokTui, .enabled = hasProjectsAndGrok },
    .{ .id = "workspace.muse_tui", .title = "Start New Muse TUI", .keywords = "agent terminal workspace fresh meta muse code", .section = .workspaces, .icon = LU_SQUARE_TERMINAL, .run = runOpenMuseTui, .enabled = hasProjects },
    .{ .id = "app.grok_setup", .title = "Set Up Grok Build", .keywords = "install xai agent provider tui", .section = .app, .icon = LU_DOWNLOAD, .run = runGrokSetup, .enabled = grokSetupNeeded },
    .{ .id = "workspace.amp_tui", .title = "Start New Amp TUI", .keywords = "agent terminal workspace fresh amp sourcegraph", .section = .workspaces, .icon = LU_SQUARE_TERMINAL, .run = runOpenAmpTui, .enabled = hasProjects },
    .{ .id = "workspace.herdr_handoff", .title = "Handoff Workspace to Herdr", .keywords = "runtime local terminal tui phone", .section = .workspaces, .icon = LU_SMARTPHONE, .run = runHerdrHandoffWorkspace, .enabled = hasProjects },
    .{ .id = "workspace.herdr_focus_terminal", .title = "Open/Focus Herdr Terminal", .keywords = "runtime terminal tui", .section = .workspaces, .icon = LU_SQUARE_TERMINAL, .run = runFocusHerdrTerminal, .enabled = currentWorkspaceHerdrLinked },
    .{ .id = "workspace.herdr_unlink", .title = "Run Workspace Locally", .keywords = "unlink herdr runtime local", .section = .workspaces, .icon = LU_UNLINK, .run = runUnlinkHerdrWorkspace, .enabled = currentWorkspaceHerdrLinked },
    .{ .id = "app.history", .title = "History: This Workspace", .keywords = "saved chats threads search recent", .section = .app, .icon = LU_HISTORY, .run = runHistoryThisWorkspace, .enabled = hasProjects, .keeps_open = true },
    .{ .id = "app.settings", .title = "Open Settings", .keywords = "preferences config options", .section = .app, .icon = LU_SETTINGS, .keybind = .settings, .run = runSettings },
    .{ .id = "app.sidebar", .title = "Toggle Sidebar", .keywords = "rail collapse", .section = .app, .icon = LU_PANEL_LEFT, .keybind = .toggle_sidebar, .run = runToggleSidebar },
};

const ThreadRef = struct { project: usize, thread: usize };
const AgentTuiRef = struct { project: usize, dock: u32 };

const ResultRef = union(enum) {
    /// Non-selectable section label.
    header: []const u8,
    /// Index into `STATIC_COMMANDS`.
    command: usize,
    thread: ThreadRef,
    agent_tui: AgentTuiRef,
    /// Index into `state.paletteHistoryItems()`: a closed thread fetched on
    /// demand from the daemon (item 5b).
    history: usize,
    /// Project index for a "Switch to <workspace>" row.
    workspace: usize,
    /// Archived-project index for a "Reopen <workspace>" row.
    closed_workspace: usize,
};

const Result = struct {
    ref: ResultRef,
    score: i32 = 0,
};

const Candidate = struct {
    ref: ResultRef,
    score: i32,
};

const HistoryEntry = struct {
    ref: ResultRef,
    at: i64,
};

/// Per-frame layout + results, rebuilt by `computeLayout` (called both from
/// the pre-event hit registration and the render pass, so hits and visuals
/// agree even when state changed between the two).
var results: [MAX_ROWS]Result = undefined;
var result_count: usize = 0;
var row_rects: [MAX_ROWS]palette.Rect = undefined;
var modal_rect: palette.Rect = .{};
var search_rect: palette.Rect = .{};
var input_rect: palette.Rect = .{};
var list_rect: palette.Rect = .{};
var footer_rect: palette.Rect = .{};
/// Left edge of the drawn query text and of the scope label.
var search_text_x: f32 = 0.0;
var scope_x: f32 = 0.0;
var scroll_y: f32 = 0.0;
var max_scroll_y: f32 = 0.0;
var hovered_row: ?usize = null;
/// Query snapshot used to detect edits and reset selection/scroll.
var last_query: [256]u8 = undefined;
var last_query_len: usize = 0;
var last_scope: ?usize = null;

/// Action submenu geometry (Tab or → on a thread row).
const MAX_ACTIONS: usize = 6;
const ThreadAction = enum { open_new, replace, open_tui, sync, handoff, archive };
const ThreadOpenIntent = enum { new_pane, replace };
var action_rects: [MAX_ACTIONS]palette.Rect = undefined;
var action_kinds: [MAX_ACTIONS]ThreadAction = undefined;
var action_labels: [MAX_ACTIONS][]const u8 = undefined;
var action_enabled: [MAX_ACTIONS]bool = undefined;
var action_count: usize = 0;
var action_menu_rect: palette.Rect = .{};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub const StaticCommandInfo = struct {
    id: []const u8,
    title: []const u8,
    section: []const u8,
    enabled: bool,
};

pub const RunStaticCommandResult = enum {
    ran,
    not_found,
    disabled,
};

/// Returns the number of stable command-palette entries exposed to live IPC.
pub fn staticCommandCount() usize {
    return STATIC_COMMANDS.len;
}

/// Returns public metadata for one static command-palette entry.
pub fn staticCommandInfo(state: *runtime.AppState, index: usize) ?StaticCommandInfo {
    if (index >= STATIC_COMMANDS.len) return null;
    const command = STATIC_COMMANDS[index];
    return .{
        .id = command.id,
        .title = command.title,
        .section = sectionName(command.section),
        .enabled = command.enabled(state),
    };
}

/// Runs one static command-palette entry by stable id, mirroring UI activation.
pub fn runStaticCommandById(state: *runtime.AppState, id: []const u8) RunStaticCommandResult {
    const command_id = if (std.mem.eql(u8, id, "workspace.archive")) "workspace.close" else id;
    for (STATIC_COMMANDS) |command| {
        if (!std.mem.eql(u8, command.id, command_id)) continue;
        if (!command.enabled(state)) {
            state.setSidebarNotice(disabledNoticeForCommand(state, command.id));
            return .disabled;
        }
        if (!command.keeps_open) state.closeCommandPalette();
        command.run(state);
        state.markDirty();
        return .ran;
    }
    return .not_found;
}

/// Registers modal hit targets (scrim, input, rows, action submenu) for the
/// current frame. Mirrors the settings-modal pattern in `layout.zig`.
pub fn registerHits(
    state: *runtime.AppState,
    width: f32,
    height: f32,
    queueHit: *const fn (*runtime.AppState, palette.Rect, runtime.PaletteModalAction, usize) void,
) void {
    if (!state.command_controller.open) return;
    computeLayout(state, width, height);
    const scrim: palette.Rect = .{ .x = 0.0, .y = 0.0, .w = width, .h = height };
    queueHit(state, scrim, .modal_dismiss, 0);
    queueHit(state, modal_rect, .modal_block, 0);
    queueHit(state, input_rect, .command_palette_input, 0);
    var i: usize = 0;
    while (i < result_count) : (i += 1) {
        if (results[i].ref == .header) continue;
        if (!rowVisible(row_rects[i])) continue;
        queueHit(state, row_rects[i], .command_palette_row, i);
    }
    if (state.command_controller.action_menu_open) {
        var ai: usize = 0;
        while (ai < action_count) : (ai += 1) {
            queueHit(state, action_rects[ai], .command_palette_action_row, ai);
        }
    }
}

/// Updates the hovered result row from the retained modal hits.
pub fn updateHover(state: *runtime.AppState, x: f32, y: f32) void {
    if (!state.command_controller.open) {
        if (hovered_row != null) {
            hovered_row = null;
            state.markDirty();
        }
        return;
    }
    var new_hover: ?usize = null;
    var i = state.palette_modal_hits.items.len;
    while (i > 0) {
        i -= 1;
        const hit = state.palette_modal_hits.items[i];
        if (hit.action != .command_palette_row and hit.action != .command_palette_action_row) continue;
        if (!rectContainsPoint(hit.rect, x, y)) continue;
        if (hit.action == .command_palette_action_row) {
            // Pointer over the submenu moves its selection like ↑/↓ do.
            if (state.command_controller.action_selected != hit.index) {
                state.command_controller.action_selected = hit.index;
                state.markDirty();
            }
            break;
        }
        new_hover = hit.index;
        break;
    }
    if (hovered_row == new_hover) return;
    hovered_row = new_hover;
    state.markDirty();
}

/// Routes wheel input to the result list while the palette is open.
pub fn handleWheel(state: *runtime.AppState, width: f32, height: f32, x: f32, y: f32, wheel_y: f32) bool {
    if (!state.command_controller.open) return false;
    _ = width;
    _ = height;
    if (!rectContainsPoint(modal_rect, x, y)) return true; // swallow: scrim owns the screen
    scroll_y = theme.clampf(scroll_y - wheel_y * theme.scaledUi(48.0), 0.0, max_scroll_y);
    state.markDirty();
    return true;
}

/// Palette-owned keys: navigation, activation, scope toggle, dismissal.
/// Returns false for keys the shared modal text-editing path should handle
/// (cursor movement, clipboard, backspace, character input).
pub fn handleKeyDown(state: *runtime.AppState, event: *const sdl.KeyboardEvent) bool {
    if (!state.command_controller.open) return false;
    const primary = (keymodBits(event.mod) & (sdl.Keymod.ctrl | sdl.Keymod.gui)) != 0;
    switch (event.key) {
        .escape => {
            if (state.command_controller.action_menu_open) {
                state.command_controller.action_menu_open = false;
            } else {
                state.closeCommandPalette();
            }
            state.markDirty();
            return true;
        },
        .up => {
            if (state.command_controller.action_menu_open) {
                moveActionSelection(state, -1);
            } else {
                moveSelection(state, -1);
            }
            return true;
        },
        .down => {
            if (state.command_controller.action_menu_open) {
                moveActionSelection(state, 1);
            } else {
                moveSelection(state, 1);
            }
            return true;
        },
        .tab => {
            toggleActionMenu(state);
            return true;
        },
        .right => {
            // → opens the chat row's actions once the caret is at the end of
            // the query; otherwise it stays a caret movement.
            if (state.command_controller.action_menu_open) return true;
            if (!rightArrowOpensActions(state, event.mod)) return false;
            toggleActionMenu(state);
            return true;
        },
        .left => {
            if (!state.command_controller.action_menu_open) return false;
            state.command_controller.action_menu_open = false;
            state.markDirty();
            return true;
        },
        .@"return", .kp_enter => {
            if (state.command_controller.action_menu_open) {
                runActionRow(state, state.command_controller.action_selected);
            } else {
                activateRow(state, state.command_controller.selected, primary);
            }
            return true;
        },
        .p => {
            // Ctrl+Shift+P while open: scoped → widen to global; global → toggle off.
            if (primary) {
                if (state.command_controller.scope_project != null) {
                    state.command_controller.scope_project = null;
                    state.command_controller.selected = 0;
                    scroll_y = 0.0;
                    state.markDirty();
                } else {
                    state.closeCommandPalette();
                }
                return true;
            }
            return false;
        },
        else => return false,
    }
}

/// True when an unmodified → should open the selected chat row's actions:
/// the caret sits at the end of the query with no selection to extend.
fn rightArrowOpensActions(state: *runtime.AppState, mod: sdl.Keymod) bool {
    const modifiers = sdl.Keymod.shift | sdl.Keymod.ctrl | sdl.Keymod.alt | sdl.Keymod.gui;
    if ((keymodBits(mod) & modifiers) != 0) return false;
    const selected = state.command_controller.selected;
    if (selected >= result_count or results[selected].ref != .thread) return false;
    const query_len = state.commandPaletteQuery().len;
    if (state.command_controller.cursor < query_len) return false;
    if (state.modal_text_selection_anchor) |anchor| {
        if (anchor != state.command_controller.cursor) return false;
    }
    return true;
}

/// Default activation for a result row (click or Enter). The primary modifier
/// reverses thread activation to replace/reuse a chat pane.
pub fn activateRow(state: *runtime.AppState, row_index: usize, replace: bool) void {
    if (row_index >= result_count) return;
    state.noteInteraction();
    switch (results[row_index].ref) {
        .header => {},
        .command => |ci| {
            const command = STATIC_COMMANDS[ci];
            if (!command.enabled(state)) {
                state.setSidebarNotice(disabledNoticeForCommand(state, command.id));
                return;
            }
            if (!command.keeps_open) state.closeCommandPalette();
            command.run(state);
            state.markDirty();
        },
        .thread => |tr| {
            state.closeCommandPalette();
            openThread(state, tr, threadOpenIntentForActivation(replace));
        },
        .history => |hi| {
            // The history cache is freed on close; open first, then close.
            state.openHistoryThread(hi);
            state.closeCommandPalette();
        },
        .agent_tui => |tui| {
            state.closeCommandPalette();
            openAgentTuiHistoryEntry(state, tui);
        },
        .workspace => |pi| {
            state.closeCommandPalette();
            _ = state.selectProjectAtIndex(pi);
        },
        .closed_workspace => |ai| {
            state.closeCommandPalette();
            _ = state.reopenClosedProjectAtIndex(ai);
        },
    }
}

/// Runs a row from the Tab/→ action submenu against the selected thread.
pub fn runActionRow(state: *runtime.AppState, action_index: usize) void {
    if (action_index >= action_count) return;
    const selected = state.command_controller.selected;
    if (selected >= result_count) return;
    const tr = switch (results[selected].ref) {
        .thread => |t| t,
        else => return,
    };
    if (!action_enabled[action_index]) return;
    state.command_controller.action_menu_open = false;
    state.noteInteraction();
    switch (action_kinds[action_index]) {
        .open_new => {
            state.closeCommandPalette();
            openThread(state, tr, .new_pane);
        },
        .replace => {
            state.closeCommandPalette();
            openThread(state, tr, .replace);
        },
        .open_tui => {
            state.closeCommandPalette();
            if (state.threadIsOpenInTui(tr.project, tr.thread)) {
                state.openThreadInChat(tr.project, tr.thread);
            } else {
                state.openThreadInTui(tr.project, tr.thread);
            }
        },
        .sync => {
            state.closeCommandPalette();
            state.syncThreadFromProvider(tr.project, tr.thread);
        },
        .handoff => {
            state.closeCommandPalette();
            // Handoff depends on the selected thread becoming the current
            // chat owner; preserve its existing replace/reuse behavior.
            openThread(state, tr, .replace);
            state.beginHandoffFromFocusedPane();
        },
        .archive => {
            state.archiveThreadAtIndex(tr.project, tr.thread);
            state.command_controller.selected = 0;
            state.markDirty();
        },
    }
}

/// Renders the palette overlay: scrim, dialog shell, search row, result
/// rows, optional action submenu, footer key hints, and scrollbar.
pub fn render(state: *runtime.AppState, width: f32, height: f32) void {
    if (!state.command_controller.open) return;
    computeLayout(state, width, height);

    // Scrim, then the dialog on the neutral panel surface with a soft
    // stacked shadow and a hairline edge (the edge carries the separation on
    // dark themes where the shadow barely reads).
    queueRect(state, .{ .x = 0.0, .y = 0.0, .w = width, .h = height }, paletteColor(theme.scrim(SCRIM_ALPHA)));
    const radius = designUi(DIALOG_RADIUS_CSS);
    queueDialogShadow(state, modal_rect, radius);
    queueRoundedRect(state, modal_rect, paletteColor(theme.COLOR_PANEL), radius);
    queueBorder(state, modal_rect, paletteColor(theme.restingEdge()), radius, hairline());

    renderSearchRow(state);
    renderRows(state);
    renderFooter(state);
    renderScrollbar(state);
    if (state.command_controller.action_menu_open) renderActionMenu(state);
}

// ---------------------------------------------------------------------------
// Layout + result building
// ---------------------------------------------------------------------------

/// Recomputes the modal geometry and result rows for the current state. Pure
/// function of state + window size; cheap enough to run twice per frame.
fn computeLayout(state: *runtime.AppState, width: f32, height: f32) void {
    // Dialog: fixed design size, shrunk to fit small windows, anchored near
    // the top like launcher UIs so the eye line stays put while typing.
    const margin = designUi(DIALOG_MARGIN_CSS);
    const modal_w = @max(@min(designUi(DIALOG_W_CSS), width - margin * 2.0), 0.0);
    const modal_y = theme.clampf(height * 0.12, margin, designUi(DIALOG_TOP_CSS));
    const modal_h = @max(@min(designUi(DIALOG_H_CSS), height - modal_y - margin), 0.0);
    modal_rect = context_menu.snap(.{ .x = (width - modal_w) * 0.5, .y = modal_y, .w = modal_w, .h = modal_h });

    // Search row: icon, query text, scope label at the right edge. The input
    // hit rect starts `MODAL_TEXT_INSET_UI` left of the text so layout.zig's
    // click-to-caret mapping lands on the drawn glyphs.
    const pad_x = designUi(SEARCH_PAD_X_CSS);
    search_rect = .{ .x = modal_rect.x, .y = modal_rect.y, .w = modal_rect.w, .h = designUi(SEARCH_ROW_H_CSS) };
    search_text_x = modal_rect.x + pad_x + designUi(SEARCH_ICON_CSS) + designUi(SEARCH_GAP_CSS);
    var scope_buf: [160]u8 = undefined;
    const scope_label = scopeLabel(state, &scope_buf);
    const scope_w = text_measure.textWidth(.ui, designUi(SCOPE_FONT_CSS), scope_label);
    scope_x = modal_rect.x + modal_rect.w - pad_x - scope_w;
    const input_x = search_text_x - theme.scaledUi(MODAL_TEXT_INSET_UI);
    input_rect = .{
        .x = input_x,
        .y = search_rect.y,
        .w = @max(scope_x - designUi(SEARCH_GAP_CSS) - input_x, theme.scaledUi(40.0)),
        .h = search_rect.h,
    };

    const footer_h = designUi(FOOTER_H_CSS);
    footer_rect = .{ .x = modal_rect.x, .y = modal_rect.y + modal_rect.h - footer_h, .w = modal_rect.w, .h = footer_h };
    const list_pad = designUi(LIST_PAD_CSS);
    const list_top = search_rect.y + search_rect.h + list_pad;
    list_rect = .{
        .x = modal_rect.x + list_pad,
        .y = list_top,
        .w = @max(modal_rect.w - list_pad * 2.0, 0.0),
        .h = @max(footer_rect.y - list_pad - list_top, 0.0),
    };

    rebuildResults(state);

    layoutRows();
    const content_h = if (result_count > 0) row_rects[result_count - 1].y + row_rects[result_count - 1].h + scroll_y - list_rect.y else 0.0;
    max_scroll_y = @max(content_h - list_rect.h, 0.0);
    scroll_y = theme.clampf(scroll_y, 0.0, max_scroll_y);

    ensureSelectedVisible(state);

    // Re-derive row rects after any scroll adjustment so hits match visuals.
    layoutRows();

    computeActionMenuLayout(state);
}

/// Stacks result rows from the list top at the current scroll offset.
fn layoutRows() void {
    var y = list_rect.y - scroll_y;
    for (0..result_count) |i| {
        const h = rowHeight(results[i].ref, i == 0);
        row_rects[i] = .{ .x = list_rect.x, .y = y, .w = list_rect.w, .h = h };
        y += h + designUi(ROW_GAP_CSS);
    }
}

/// Section headers carry their own top gap (smaller for the first one);
/// chat rows are taller for their second line.
fn rowHeight(ref: ResultRef, first: bool) f32 {
    return switch (ref) {
        .header => designUi(if (first) HEADER_FIRST_H_CSS else HEADER_H_CSS),
        .thread, .history, .agent_tui => designUi(ROW_TWO_LINE_H_CSS),
        .command, .workspace, .closed_workspace => designUi(ROW_H_CSS),
    };
}

/// Right-hand label of the search row: which history the palette searches.
fn scopeLabel(state: *runtime.AppState, buf: []u8) []const u8 {
    if (state.command_controller.scope_project) |pi| {
        if (pi < state.project_controller.projects.items.len) {
            return std.fmt.bufPrint(buf, "{s} history", .{state.project_controller.projects.items[pi].label}) catch "Workspace history";
        }
    }
    return "All workspaces";
}

/// Query-field font size, shared with layout.zig's click-to-caret mapping.
pub fn searchFontSize() f32 {
    return designUi(SEARCH_FONT_CSS);
}

/// Builds the result list for the current query + scope, resetting selection
/// when either changed since the last frame.
fn rebuildResults(state: *runtime.AppState) void {
    const query = state.commandPaletteQuery();
    const query_changed = query.len != last_query_len or
        !std.mem.eql(u8, last_query[0..last_query_len], query) or
        !scopeEq(last_scope, state.command_controller.scope_project);
    if (query_changed) {
        const n = @min(query.len, last_query.len);
        @memcpy(last_query[0..n], query[0..n]);
        last_query_len = n;
        last_scope = state.command_controller.scope_project;
        state.command_controller.selected = 0;
        state.command_controller.action_menu_open = false;
        scroll_y = 0.0;
    }

    result_count = 0;
    if (state.command_controller.scope_project) |pi| {
        buildScopedHistory(state, pi, query);
    } else if (query.len == 0) {
        buildSuggestions(state);
    } else {
        buildRanked(state, query);
    }
    clampSelection(state);
}

/// Empty-query global view: recent threads, then the command table, then
/// workspace switching — the palette's "home screen".
fn buildSuggestions(state: *runtime.AppState) void {
    var recent: [8]struct { ref: ThreadRef, at: i64 } = undefined;
    var recent_count: usize = 0;
    for (state.project_controller.projects.items, 0..) |*project, pi| {
        for (project.threads.items, 0..) |*thread, ti| {
            if (!thread.committed or thread.archived) continue;
            const at = thread.last_activity_at;
            // Insertion sort into the small recency buffer.
            var pos = recent_count;
            while (pos > 0 and recent[pos - 1].at < at) : (pos -= 1) {}
            if (pos >= recent.len) continue;
            const tail = @min(recent_count, recent.len - 1);
            var j = tail;
            while (j > pos) : (j -= 1) recent[j] = recent[j - 1];
            recent[pos] = .{ .ref = .{ .project = pi, .thread = ti }, .at = at };
            if (recent_count < recent.len) recent_count += 1;
        }
    }
    if (recent_count > 0) {
        appendResult(.{ .header = "Recent chats" });
        for (recent[0..recent_count]) |entry| appendResult(.{ .thread = entry.ref });
    }
    appendResult(.{ .header = "Commands" });
    for (STATIC_COMMANDS, 0..) |command, ci| {
        if (!command.enabled(state)) continue;
        appendResult(.{ .command = ci });
    }
    // Open workspaces to switch to, then closed ones (tagged "closed" on the
    // row) under the same section.
    const has_switch_targets = state.project_controller.projects.items.len > 1;
    const has_closed = state.project_controller.archived_projects.items.len > 0;
    if (has_switch_targets or has_closed) appendResult(.{ .header = "Workspaces" });
    if (has_switch_targets) {
        for (state.project_controller.projects.items, 0..) |_, pi| {
            if (pi == state.project_controller.selected_index) continue;
            appendResult(.{ .workspace = pi });
        }
    }
    if (has_closed) {
        var remaining = state.project_controller.archived_projects.items.len;
        while (remaining > 0) {
            remaining -= 1;
            appendResult(.{ .closed_workspace = remaining });
        }
    }
}

/// Sidebar "History" scope: one workspace's agent TUIs and committed threads,
/// recency bucketed when browsing and filtered when searching.
fn buildScopedHistory(state: *runtime.AppState, project_index: usize, query: []const u8) void {
    if (project_index >= state.project_controller.projects.items.len) return;
    const project = &state.project_controller.projects.items[project_index];
    var entries: [MAX_CANDIDATES]HistoryEntry = undefined;
    var entry_count: usize = 0;

    const dock_count = project.terminal_docks.items.len + 1;
    for (0..dock_count) |dock_index| {
        const dock_id: u32 = if (dock_index == 0) 0 else project.terminal_docks.items[dock_index - 1].id;
        const activity_at_ms = state.workspaceAgentTuiHistoryAt(project_index, dock_id);
        if (activity_at_ms == 0) continue;
        const provider = state.workspaceAgentTuiProvider(project_index, dock_id) orelse continue;
        if (query.len > 0 and !matchAgentTui(state, project_index, dock_id, provider, query)) continue;
        if (entry_count >= entries.len) break;
        entries[entry_count] = .{
            .ref = .{ .agent_tui = .{ .project = project_index, .dock = dock_id } },
            .at = @divTrunc(activity_at_ms, std.time.ms_per_s),
        };
        entry_count += 1;
    }

    const sorted = project.sortedCommittedThreadIndices(state.allocator);
    for (sorted) |ti| {
        if (ti >= project.threads.items.len or entry_count >= entries.len) continue;
        const thread = &project.threads.items[ti];
        if (query.len > 0 and matchThread(thread, query) == null) continue;
        entries[entry_count] = .{
            .ref = .{ .thread = .{ .project = project_index, .thread = ti } },
            .at = thread.last_activity_at,
        };
        entry_count += 1;
    }
    for (state.paletteHistoryItems(), 0..) |item, hi| {
        if (entry_count >= entries.len) break;
        if (!std.mem.eql(u8, item.workspace_id, project.id)) continue;
        if (query.len > 0 and fuzzyScore(item.title, query) == null) continue;
        entries[entry_count] = .{
            .ref = .{ .history = hi },
            .at = item.last_activity_at orelse 0,
        };
        entry_count += 1;
    }

    std.sort.pdq(HistoryEntry, entries[0..entry_count], {}, historyEntryLessThan);
    const now = unixTimestampSeconds();
    var bucket: usize = 0; // 0 = none emitted, 1 = today, 2 = week, 3 = older
    for (entries[0..entry_count]) |entry| {
        if (query.len == 0) {
            const age = now - entry.at;
            const next_bucket: usize = if (age < 60 * 60 * 24) 1 else if (age < 60 * 60 * 24 * 7) 2 else 3;
            if (next_bucket > bucket) {
                bucket = next_bucket;
                appendResult(.{ .header = switch (next_bucket) {
                    1 => "Today",
                    2 => "This week",
                    else => "Older",
                } });
            }
        }
        appendResult(entry.ref);
        if (result_count >= MAX_ROWS) break;
    }
}

fn historyEntryLessThan(_: void, a: HistoryEntry, b: HistoryEntry) bool {
    return a.at > b.at;
}

/// Query view: every source scored into one ranked list.
fn buildRanked(state: *runtime.AppState, query: []const u8) void {
    var candidates: [MAX_CANDIDATES]Candidate = undefined;
    var candidate_count: usize = 0;

    for (STATIC_COMMANDS, 0..) |command, ci| {
        if (!command.enabled(state)) continue;
        const title_score = fuzzyScore(command.title, query);
        const keyword_score = fuzzyScore(command.keywords, query);
        const best = maxOptional(title_score, if (keyword_score) |s| s - 100 else null);
        if (best) |score| {
            appendCandidate(&candidates, &candidate_count, .{ .ref = .{ .command = ci }, .score = score + 50 });
        }
    }
    const now = unixTimestampSeconds();
    for (state.project_controller.projects.items, 0..) |*project, pi| {
        const label_score = fuzzyScore(project.label, query);
        if (label_score) |score| {
            if (pi != state.project_controller.selected_index) {
                appendCandidate(&candidates, &candidate_count, .{ .ref = .{ .workspace = pi }, .score = score + 25 });
            }
        }
        for (project.threads.items, 0..) |*thread, ti| {
            if (!thread.committed or thread.archived) continue;
            if (matchThread(thread, query)) |score| {
                // Mild recency boost keeps fresh threads above stale equal
                // matches without letting recency beat match quality.
                const age_days: i32 = @intCast(@min(@divTrunc(@max(now - thread.last_activity_at, 0), 60 * 60 * 24), 30));
                appendCandidate(&candidates, &candidate_count, .{
                    .ref = .{ .thread = .{ .project = pi, .thread = ti } },
                    .score = score + (30 - age_days),
                });
            }
        }
        const dock_count = project.terminal_docks.items.len + 1;
        for (0..dock_count) |dock_index| {
            const dock_id: u32 = if (dock_index == 0) 0 else project.terminal_docks.items[dock_index - 1].id;
            if (state.workspaceAgentTuiHistoryAt(pi, dock_id) == 0) continue;
            const provider = state.workspaceAgentTuiProvider(pi, dock_id) orelse continue;
            if (!matchAgentTui(state, pi, dock_id, provider, query)) continue;
            appendCandidate(&candidates, &candidate_count, .{
                .ref = .{ .agent_tui = .{ .project = pi, .dock = dock_id } },
                .score = fuzzyScore(agentTuiSearchLabel(provider), query) orelse 200,
            });
        }
    }
    for (state.paletteHistoryItems(), 0..) |item, hi| {
        const score = fuzzyScore(item.title, query) orelse continue;
        const age_days: i32 = @intCast(@min(@divTrunc(@max(now - (item.last_activity_at orelse 0), 0), 60 * 60 * 24), 30));
        // Cold threads rank just under an equally matching open thread.
        appendCandidate(&candidates, &candidate_count, .{ .ref = .{ .history = hi }, .score = score + (30 - age_days) - 5 });
    }
    for (state.project_controller.archived_projects.items, 0..) |*project, ai| {
        const label_score = fuzzyScore(project.label, query);
        const path_score = fuzzyScore(project.path, query);
        const action_score = maxOptional(
            fuzzyScore("reopen workspace", query),
            fuzzyScore("closed workspace", query),
        );
        const best = maxOptional(
            maxOptional(label_score, if (path_score) |s| s - 50 else null),
            if (action_score) |s| s - @as(i32, @intCast(@min(ai, 40))) else null,
        );
        if (best) |score| {
            appendCandidate(&candidates, &candidate_count, .{ .ref = .{ .closed_workspace = ai }, .score = score + 20 });
        }
    }

    std.sort.pdq(Candidate, candidates[0..candidate_count], {}, candidateLessThan);
    appendGroupedCandidates(candidates[0..candidate_count]);
}

/// Section a ranked result is listed under while searching.
const ResultGroup = enum { commands, chats, workspaces };

fn resultGroup(ref: ResultRef) ResultGroup {
    return switch (ref) {
        .command, .header => .commands,
        .thread, .agent_tui, .history => .chats,
        .workspace, .closed_workspace => .workspaces,
    };
}

fn resultGroupLabel(group: ResultGroup) []const u8 {
    return switch (group) {
        .commands => "Commands",
        .chats => "Recent chats",
        .workspaces => "Workspaces",
    };
}

/// Emits score-sorted candidates under section headers. Sections appear in
/// the order of their best match and keep score order inside, so the top
/// overall match stays the first selectable row.
fn appendGroupedCandidates(sorted: []const Candidate) void {
    const group_count = @typeInfo(ResultGroup).@"enum".fields.len;
    const take = sorted[0..@min(sorted.len, MAX_ROWS - group_count)];
    var order: [group_count]ResultGroup = undefined;
    var order_len: usize = 0;
    for (take) |candidate| {
        const group = resultGroup(candidate.ref);
        if (std.mem.indexOfScalar(ResultGroup, order[0..order_len], group) == null) {
            order[order_len] = group;
            order_len += 1;
        }
    }
    for (order[0..order_len]) |group| {
        appendResult(.{ .header = resultGroupLabel(group) });
        for (take) |candidate| {
            if (resultGroup(candidate.ref) == group) appendResult(candidate.ref);
        }
    }
}

fn candidateLessThan(_: void, a: Candidate, b: Candidate) bool {
    return a.score > b.score;
}

fn appendCandidate(buf: *[MAX_CANDIDATES]Candidate, count: *usize, candidate: Candidate) void {
    if (count.* >= buf.len) return;
    buf[count.*] = candidate;
    count.* += 1;
}

fn appendResult(ref: ResultRef) void {
    if (result_count >= MAX_ROWS) return;
    results[result_count] = .{ .ref = ref };
    result_count += 1;
}

/// Scores a thread against the query: title fuzzy match first, then message
/// bodies (substring only, query >= 3 chars, capped scan) as a weaker hit.
fn matchThread(thread: anytype, query: []const u8) ?i32 {
    if (fuzzyScore(thread.title, query)) |score| return score;
    if (query.len < 3) return null;
    // Body scan budget: enough to cover long threads without making each
    // keystroke scan megabytes across every workspace.
    var budget: usize = 64 * 1024;
    for (thread.messages.items) |*message| {
        const body = message.body[0..@min(message.body.len, budget)];
        if (asciiIndexOfIgnoreCase(body, query) != null) return 200;
        if (budget <= body.len) break;
        budget -= body.len;
    }
    return null;
}

fn matchAgentTui(state: *runtime.AppState, project_index: usize, dock_id: u32, provider: AgentTuiHistoryProvider, query: []const u8) bool {
    if (fuzzyScore(agentTuiSearchLabel(provider), query) != null) return true;
    var title_buf: [96]u8 = undefined;
    const dock = state.projectTerminalDock(project_index, dock_id) orelse return false;
    return fuzzyScore(dock.activeProcessLabel(&title_buf), query) != null;
}

fn agentTuiSearchLabel(provider: AgentTuiHistoryProvider) []const u8 {
    return switch (provider) {
        .codex => "Codex TUI",
        .claude => "Claude TUI",
        .opencode => "OpenCode TUI",
        .cursor => "Cursor TUI",
        .pi => "Pi TUI",
        .fx => "FX TUI",
        .grok => "Grok TUI",
        .amp => "Amp TUI",
        .muse => "Muse TUI",
    };
}

/// Case-insensitive scoring: exact substring ranks far above subsequence
/// matches; both prefer earlier/tighter hits. Returns null on no match.
fn fuzzyScore(haystack: []const u8, needle: []const u8) ?i32 {
    if (needle.len == 0 or haystack.len == 0) return null;
    if (asciiIndexOfIgnoreCase(haystack, needle)) |pos| {
        return 1000 - @as(i32, @intCast(@min(pos, 400)));
    }
    // Subsequence walk: every needle byte must appear in order; gaps cost.
    var hi: usize = 0;
    var gaps: i32 = 0;
    var last_hit: usize = 0;
    for (needle) |nb| {
        const nl = std.ascii.toLower(nb);
        var found = false;
        while (hi < haystack.len) : (hi += 1) {
            if (std.ascii.toLower(haystack[hi]) == nl) {
                if (last_hit != 0) gaps += @intCast(@min(hi - last_hit, 20));
                last_hit = hi + 1;
                hi += 1;
                found = true;
                break;
            }
        }
        if (!found) return null;
    }
    return 500 - gaps;
}

fn asciiIndexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or haystack.len < needle.len) return null;
    var i: usize = 0;
    const end = haystack.len - needle.len;
    outer: while (i <= end) : (i += 1) {
        for (needle, 0..) |nb, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nb)) continue :outer;
        }
        return i;
    }
    return null;
}

/// Wall-clock seconds; `std.time.timestamp` was removed in the Zig 0.16 std
/// reorganization, so this mirrors `state.zig`'s libc-based helper.
fn unixTimestampSeconds() i64 {
    return @divTrunc(platform_runtime.unixTimestampMs(), std.time.ms_per_s);
}

fn maxOptional(a: ?i32, b: ?i32) ?i32 {
    if (a == null) return b;
    if (b == null) return a;
    return @max(a.?, b.?);
}

fn scopeEq(a: ?usize, b: ?usize) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return a.? == b.?;
}

// ---------------------------------------------------------------------------
// Selection + action submenu
// ---------------------------------------------------------------------------

fn isSelectable(index: usize) bool {
    return index < result_count and results[index].ref != .header;
}

fn firstSelectable() ?usize {
    var i: usize = 0;
    while (i < result_count) : (i += 1) {
        if (isSelectable(i)) return i;
    }
    return null;
}

fn clampSelection(state: *runtime.AppState) void {
    if (isSelectable(state.command_controller.selected)) return;
    state.command_controller.selected = firstSelectable() orelse 0;
}

/// Moves the selected row by `delta`, skipping section headers.
fn moveSelection(state: *runtime.AppState, delta: i32) void {
    if (result_count == 0) return;
    var index: i64 = @intCast(state.command_controller.selected);
    const count: i64 = @intCast(result_count);
    var remaining: usize = result_count;
    while (remaining > 0) : (remaining -= 1) {
        index += delta;
        if (index < 0) index = count - 1;
        if (index >= count) index = 0;
        if (isSelectable(@intCast(index))) {
            state.command_controller.selected = @intCast(index);
            state.command_controller.action_menu_open = false;
            state.markDirty();
            return;
        }
    }
}

fn moveActionSelection(state: *runtime.AppState, delta: i32) void {
    if (action_count == 0) return;
    var index: i64 = @intCast(state.command_controller.action_selected);
    const count: i64 = @intCast(action_count);
    index += delta;
    if (index < 0) index = count - 1;
    if (index >= count) index = 0;
    state.command_controller.action_selected = @intCast(index);
    state.markDirty();
}

/// Tab (or → at the end of the query) on a thread row opens the secondary
/// action submenu; non-thread rows have a single behavior so it is a no-op.
fn toggleActionMenu(state: *runtime.AppState) void {
    if (state.command_controller.action_menu_open) {
        state.command_controller.action_menu_open = false;
        state.markDirty();
        return;
    }
    const selected = state.command_controller.selected;
    if (selected >= result_count) return;
    if (results[selected].ref != .thread) return;
    state.command_controller.action_menu_open = true;
    state.command_controller.action_selected = 0;
    state.markDirty();
}

/// Rebuilds the action submenu rows + geometry for the selected thread row.
fn computeActionMenuLayout(state: *runtime.AppState) void {
    action_count = 0;
    if (!state.command_controller.action_menu_open) return;
    const selected = state.command_controller.selected;
    if (selected >= result_count) {
        state.command_controller.action_menu_open = false;
        return;
    }
    const tr = switch (results[selected].ref) {
        .thread => |t| t,
        else => {
            state.command_controller.action_menu_open = false;
            return;
        },
    };
    if (tr.project >= state.project_controller.projects.items.len) return;
    const project = &state.project_controller.projects.items[tr.project];
    if (tr.thread >= project.threads.items.len) return;
    const thread = &project.threads.items[tr.thread];
    const pending = thread.isSendPendingForUi();
    const can_sync = thread.provider_thread_id != null and !pending;
    const in_tui = state.threadIsOpenInTui(tr.project, tr.thread);

    appendAction(.open_new, "Open in New Pane", true);
    appendAction(.replace, "Replace Current Pane", true);
    appendAction(.open_tui, if (in_tui) "Open as Chat" else "Open in TUI", in_tui or can_sync);
    appendAction(.sync, "Sync Thread", can_sync);
    appendAction(.handoff, "Handoff to Another Agent", !pending);
    appendAction(.archive, "Archive Thread", !pending);

    // Shared context-menu metrics, anchored under the selected row's right
    // edge (flipped above it when the dialog bottom would clip it).
    const row_h = theme.scaledUi(context_menu.ROW_HEIGHT_UI);
    const menu_w = designUi(ACTION_MENU_W_CSS);
    const menu_pad = theme.scaledUi(context_menu.PAD_UI);
    const menu_h = menu_pad * 2.0 + row_h * @as(f32, @floatFromInt(action_count));
    const anchor = row_rects[selected];
    const edge = designUi(LIST_PAD_CSS);
    var menu_x = anchor.x + anchor.w - menu_w - edge;
    var menu_y = anchor.y + anchor.h + theme.scaledUi(2.0);
    menu_x = theme.clampf(menu_x, modal_rect.x + edge, modal_rect.x + modal_rect.w - menu_w - edge);
    if (menu_y + menu_h > modal_rect.y + modal_rect.h) menu_y = anchor.y - menu_h - theme.scaledUi(2.0);
    action_menu_rect = context_menu.snap(.{ .x = menu_x, .y = menu_y, .w = menu_w, .h = menu_h });
    for (0..action_count) |i| {
        action_rects[i] = .{
            .x = action_menu_rect.x + menu_pad,
            .y = action_menu_rect.y + menu_pad + row_h * @as(f32, @floatFromInt(i)),
            .w = action_menu_rect.w - menu_pad * 2.0,
            .h = row_h,
        };
    }
}

fn appendAction(kind: ThreadAction, label: []const u8, enabled: bool) void {
    if (action_count >= MAX_ACTIONS) return;
    action_kinds[action_count] = kind;
    action_labels[action_count] = label;
    action_enabled[action_count] = enabled;
    action_count += 1;
}

/// Keeps the keyboard selection inside the list viewport by nudging scroll.
fn ensureSelectedVisible(state: *runtime.AppState) void {
    const selected = state.command_controller.selected;
    if (selected >= result_count) return;
    const row = row_rects[selected];
    const top = list_rect.y;
    const bottom = list_rect.y + list_rect.h;
    if (row.y < top) {
        scroll_y = @max(scroll_y - (top - row.y), 0.0);
    } else if (row.y + row.h > bottom) {
        scroll_y = @min(scroll_y + (row.y + row.h - bottom), max_scroll_y);
    }
}

// ---------------------------------------------------------------------------
// Thread helpers
// ---------------------------------------------------------------------------

/// Pane id of the chat pane currently showing `thread_index`, if any.
fn threadOpenPaneId(project: *const native_state.Project, thread_index: usize) ?runtime.WorkspacePaneId {
    for (project.workspace_layout.panes.items) |*pane| {
        switch (pane.ref) {
            .chat => |ref| if (ref.thread_index == thread_index) return pane.id,
            else => {},
        }
    }
    return null;
}

fn threadOpenIntentForActivation(replace: bool) ThreadOpenIntent {
    return if (replace) .replace else .new_pane;
}

/// Enter opens a new pane; Ctrl/Cmd+Enter retains the former replace/reuse
/// behavior, including focusing an existing pane for the selected thread.
fn openThread(state: *runtime.AppState, tr: ThreadRef, intent: ThreadOpenIntent) void {
    if (tr.project >= state.project_controller.projects.items.len) return;
    if (intent == .new_pane) {
        state.openThreadInWorkspaceSplit(tr.project, tr.thread);
        return;
    }
    const project = &state.project_controller.projects.items[tr.project];
    if (threadOpenPaneId(project, tr.thread)) |pane_id| {
        state.focusWorkspaceOpenPane(tr.project, pane_id);
        state.markDirty();
        return;
    }
    state.selectThreadForProject(tr.project, tr.thread);
}

fn openAgentTuiHistoryEntry(state: *runtime.AppState, tui: AgentTuiRef) void {
    _ = state.openWorkspaceAgentTuiHistory(tui.project, tui.dock);
}

// ---------------------------------------------------------------------------
// Command run/enabled fns (thin wrappers over AppState)
// ---------------------------------------------------------------------------

fn alwaysEnabled(_: *runtime.AppState) bool {
    return true;
}

/// Static workspace commands act on the currently selected workspace at
/// activation, like the other workspace entries. `scope_project` is
/// history-filter state that survives `closeCommandPalette`, so reading it
/// here could retarget a stale prior workspace (especially for live/daemon
/// `runStaticCommandById` while the palette is closed).
fn commandTargetProject(state: *runtime.AppState) ?usize {
    const index = state.project_controller.selected_index;
    if (index >= state.project_controller.projects.items.len) return null;
    return index;
}

fn hasCommandTargetProject(state: *runtime.AppState) bool {
    return commandTargetProject(state) != null;
}

fn hasProjects(state: *runtime.AppState) bool {
    return state.project_controller.projects.items.len > 0;
}

fn hasCustomScrollingColumnWidth(state: *runtime.AppState) bool {
    if (state.project_controller.selected_index >= state.project_controller.projects.items.len) return false;
    return state.project_controller.projects.items[state.project_controller.selected_index].workspace_layout.hasCustomScrollPaneExtent();
}

fn adjacentPaneForCommand(state: *runtime.AppState, previous: bool) ?runtime.WorkspacePaneId {
    if (state.project_controller.selected_index >= state.project_controller.projects.items.len) return null;
    const layout = &state.project_controller.projects.items[state.project_controller.selected_index].workspace_layout;
    const focused_pane_id = layout.focused_pane_id orelse return null;
    return layout.adjacentTiledPaneIdInSidebarOrder(
        focused_pane_id,
        paneTraversalDirection(state.app_config.workspace_scroll_direction, previous),
    );
}

fn canFocusPreviousPane(state: *runtime.AppState) bool {
    return adjacentPaneForCommand(state, true) != null;
}

fn canFocusNextPane(state: *runtime.AppState) bool {
    return adjacentPaneForCommand(state, false) != null;
}

fn hasProjectsAndGrok(state: *runtime.AppState) bool {
    return hasProjects(state) and native_state.AppState.grokTuiInstalled();
}

fn grokSetupNeeded(_: *runtime.AppState) bool {
    return !native_state.AppState.grokTuiInstalled();
}

fn hasQuickPane(state: *runtime.AppState) bool {
    return state.currentProjectQuickPane() != null;
}

fn hasFocusedGuiChat(state: *runtime.AppState) bool {
    return focusedGuiThreadIndex(state) != null;
}

fn workspaceNotBusy(state: *runtime.AppState) bool {
    if (state.project_controller.selected_index >= state.project_controller.projects.items.len) return false;
    for (state.project_controller.projects.items[state.project_controller.selected_index].threads.items) |*thread| {
        if (thread.isSendPendingForUi()) return false;
    }
    return true;
}

fn hasClosedWorkspaces(state: *runtime.AppState) bool {
    return state.project_controller.archived_projects.items.len > 0;
}

fn hasBrowserPane(state: *runtime.AppState) bool {
    return state.currentProjectVisibleBrowserPaneId() != null;
}

fn hasBrowserTab(state: *runtime.AppState) bool {
    return hasBrowserPane(state) and state.browserTabCount() > 0;
}

fn canMoveBrowserTabLeft(state: *runtime.AppState) bool {
    return hasBrowserTab(state) and state.activeBrowserTabIndex() > 0;
}

fn canMoveBrowserTabRight(state: *runtime.AppState) bool {
    return hasBrowserTab(state) and state.activeBrowserTabIndex() + 1 < state.browserTabCount();
}

fn currentWorkspaceHerdrLinked(state: *runtime.AppState) bool {
    return state.project_controller.selected_index < state.project_controller.projects.items.len and
        state.project_controller.projects.items[state.project_controller.selected_index].herdr_link != null;
}

fn currentWorkspaceHasHerdrAttachTerminal(state: *runtime.AppState) bool {
    if (!currentWorkspaceHerdrLinked(state)) return false;
    const link = state.project_controller.projects.items[state.project_controller.selected_index].herdr_link.?;
    return link.attach_dock_id != null;
}

fn currentThreadNotPending(state: *runtime.AppState) bool {
    if (state.project_controller.selected_index >= state.project_controller.projects.items.len) return false;
    const project = &state.project_controller.projects.items[state.project_controller.selected_index];
    if (project.selected_thread_index >= project.threads.items.len) return false;
    const thread = &project.threads.items[project.selected_thread_index];
    return thread.committed and !thread.isSendPendingForUi();
}

fn currentThreadCommitted(state: *runtime.AppState) bool {
    if (state.project_controller.selected_index >= state.project_controller.projects.items.len) return false;
    const project = &state.project_controller.projects.items[state.project_controller.selected_index];
    if (project.selected_thread_index >= project.threads.items.len) return false;
    return project.threads.items[project.selected_thread_index].committed;
}

fn canRegenerateChatTitle(state: *runtime.AppState) bool {
    return state.canRegenerateCurrentThreadTitle();
}

fn canSyncCurrentThread(state: *runtime.AppState) bool {
    if (state.project_controller.selected_index >= state.project_controller.projects.items.len) return false;
    const thread_index = focusedGuiThreadIndex(state) orelse return false;
    const project = &state.project_controller.projects.items[state.project_controller.selected_index];
    if (thread_index >= project.threads.items.len) return false;
    const thread = &project.threads.items[thread_index];
    return thread.provider_thread_id != null and !thread.isSendPendingForUi();
}

fn canOpenFocusedThreadInTui(state: *runtime.AppState) bool {
    if (state.project_controller.selected_index >= state.project_controller.projects.items.len) return false;
    const thread_index = focusedGuiThreadIndex(state) orelse return false;
    const project = &state.project_controller.projects.items[state.project_controller.selected_index];
    if (thread_index >= project.threads.items.len) return false;
    const thread = &project.threads.items[thread_index];
    return thread.provider_thread_id != null;
}

fn canOpenFocusedCodexThreadInTui(state: *runtime.AppState) bool {
    return canOpenFocusedThreadInTui(state) and focusedGuiThreadProvider(state) == .codex;
}

fn canOpenFocusedNonCodexThreadInTui(state: *runtime.AppState) bool {
    const provider = focusedGuiThreadProvider(state) orelse return false;
    return provider != .codex and canOpenFocusedThreadInTui(state);
}

fn canHandoffFocusedPane(state: *runtime.AppState) bool {
    if (state.project_controller.selected_index >= state.project_controller.projects.items.len) return false;
    const project = &state.project_controller.projects.items[state.project_controller.selected_index];
    const pane_id = project.workspace_layout.focused_pane_id orelse return false;
    return switch (state.workspacePaneKindById(pane_id) orelse return false) {
        .chat => blk: {
            const thread_index = state.workspaceChatThreadIndexByPane(pane_id) orelse break :blk false;
            break :blk thread_index < project.threads.items.len and !project.threads.items[thread_index].isSendPendingForUi();
        },
        .terminal => blk: {
            const dock_id = state.workspaceTerminalDockIdByPane(pane_id) orelse break :blk false;
            break :blk state.projectTerminalSurface(state.project_controller.selected_index, dock_id) != null;
        },
        .browser => false,
    };
}

fn disabledNoticeForCommand(state: *runtime.AppState, id: []const u8) []const u8 {
    if (std.mem.eql(u8, id, "thread.open_current_codex_tui") or std.mem.eql(u8, id, "thread.open_current_tui")) {
        const thread_index = focusedGuiThreadIndex(state) orelse return "Focus a GUI chat pane before opening a thread in TUI.";
        if (state.project_controller.selected_index >= state.project_controller.projects.items.len) return "No workspace selected.";
        const project = &state.project_controller.projects.items[state.project_controller.selected_index];
        if (thread_index >= project.threads.items.len) return "Focused chat thread is unavailable.";
        const thread = &project.threads.items[thread_index];
        if (thread.provider_thread_id == null) return "Thread has no provider session id yet.";
    }
    if (std.mem.eql(u8, id, "workspace.reopen")) return "No closed workspaces to reopen.";
    if (std.mem.eql(u8, id, "workspace.grok_tui")) return "Grok Build is not installed. Run “Set Up Grok Build” first.";
    if (std.mem.eql(u8, id, "app.grok_setup")) return "Grok Build is already installed.";
    if (std.mem.eql(u8, id, "workspace.herdr_focus_terminal")) return "Current workspace is not linked to Herdr.";
    if (std.mem.eql(u8, id, "workspace.herdr_unlink")) return "Current workspace is already running locally.";
    return "Command is unavailable right now.";
}

fn focusedGuiThreadIndex(state: *runtime.AppState) ?usize {
    const pane_id = state.focusedWorkspaceChatPaneId() orelse return null;
    return state.workspaceChatThreadIndexByPane(pane_id);
}

fn focusedGuiThreadProvider(state: *runtime.AppState) ?Provider {
    if (state.project_controller.selected_index >= state.project_controller.projects.items.len) return null;
    const thread_index = focusedGuiThreadIndex(state) orelse return null;
    const project = &state.project_controller.projects.items[state.project_controller.selected_index];
    if (thread_index >= project.threads.items.len) return null;
    return project.threads.items[thread_index].provider;
}

fn runNewChat(state: *runtime.AppState) void {
    if (state.project_controller.projects.items.len == 0) return;
    state.createThreadForProject(@min(state.project_controller.selected_index, state.project_controller.projects.items.len - 1));
}

// Both open the composer's model & settings menu, matching the toolbar
// label and the `chat_model_picker` / `chat_run_config` shortcuts.
fn runChooseChatModel(state: *runtime.AppState) void {
    state.openComposerSettingsMenu(.model);
}

fn runChatRunConfig(state: *runtime.AppState) void {
    state.openComposerSettingsMenu(null);
}

fn runChooseChatDirectory(state: *runtime.AppState) void {
    state.openPaletteDirectoryPicker();
}

fn runSyncCurrentThread(state: *runtime.AppState) void {
    const thread_index = focusedGuiThreadIndex(state) orelse return;
    state.syncThreadFromProvider(state.project_controller.selected_index, thread_index);
}

fn runHandoffCurrent(state: *runtime.AppState) void {
    state.beginHandoffFromFocusedPane();
}

fn runOpenCurrentThreadInTui(state: *runtime.AppState) void {
    const thread_index = focusedGuiThreadIndex(state) orelse return;
    state.openThreadInTui(state.project_controller.selected_index, thread_index);
}

fn runArchiveCurrentThread(state: *runtime.AppState) void {
    const project = &state.project_controller.projects.items[state.project_controller.selected_index];
    state.archiveThreadAtIndex(state.project_controller.selected_index, project.selected_thread_index);
}

fn runImportCodex(state: *runtime.AppState) void {
    state.beginThreadImport(state.project_controller.selected_index, .codex);
}

fn runImportOpencode(state: *runtime.AppState) void {
    state.beginThreadImport(state.project_controller.selected_index, .opencode);
}

fn runImportClaude(state: *runtime.AppState) void {
    state.beginThreadImport(state.project_controller.selected_index, .claude);
}

fn runSplitChatRight(state: *runtime.AppState) void {
    _ = state.splitFocusedWorkspacePaneTiledWithChatPlacement(.vertical, true);
}

fn runSplitChatDown(state: *runtime.AppState) void {
    _ = state.splitFocusedWorkspacePaneTiledWithChatPlacement(.horizontal, true);
}

fn runSplitTerminalRight(state: *runtime.AppState) void {
    _ = state.splitFocusedWorkspacePaneTiledWithTerminalPlacement(.vertical, true);
}

fn runSplitTerminalDown(state: *runtime.AppState) void {
    _ = state.splitFocusedWorkspacePaneTiledWithTerminalPlacement(.horizontal, true);
}

fn runOpenTerminal(state: *runtime.AppState) void {
    _ = state.openTerminalPaneForProjectIndex(state.project_controller.selected_index);
}

fn runToggleBrowser(state: *runtime.AppState) void {
    state.toggleBrowser();
}

fn runNewBrowserTab(state: *runtime.AppState) void {
    state.createBrowserTab();
}

fn runDuplicateBrowserTab(state: *runtime.AppState) void {
    state.duplicateBrowserTab(state.activeBrowserTabIndex());
}

fn runToggleBrowserTabPinned(state: *runtime.AppState) void {
    state.toggleBrowserTabPinned(state.activeBrowserTabIndex());
}

fn runMoveBrowserTabLeft(state: *runtime.AppState) void {
    const active = state.activeBrowserTabIndex();
    if (active > 0) state.moveBrowserTab(active, active - 1);
}

fn runMoveBrowserTabRight(state: *runtime.AppState) void {
    const active = state.activeBrowserTabIndex();
    if (active + 1 < state.browserTabCount()) state.moveBrowserTab(active, active + 1);
}

fn runCloseBrowserTab(state: *runtime.AppState) void {
    state.closeBrowserTab(state.activeBrowserTabIndex());
}

fn runClosePane(state: *runtime.AppState) void {
    _ = state.closeFocusedWorkspacePane();
}

fn runZoomPane(state: *runtime.AppState) void {
    _ = state.toggleFocusedWorkspacePaneMaximized();
}

fn runPreviousPane(state: *runtime.AppState) void {
    focusAdjacentPane(state, true);
}

fn runNextPane(state: *runtime.AppState) void {
    focusAdjacentPane(state, false);
}

fn focusAdjacentPane(state: *runtime.AppState, previous: bool) void {
    const pane_id = adjacentPaneForCommand(state, previous) orelse return;
    _ = state.focusCurrentProjectWorkspacePane(pane_id);
}

fn paneTraversalDirection(scroll_direction: app_config.WorkspaceScrollDirection, previous: bool) runtime.WorkspacePaneDirection {
    return switch (scroll_direction) {
        .horizontal => if (previous) .left else .right,
        .vertical => if (previous) .up else .down,
    };
}

fn runFloatPane(state: *runtime.AppState) void {
    _ = state.floatFocusedWorkspacePane();
}

fn runToggleQuickPane(state: *runtime.AppState) void {
    _ = state.toggleCurrentProjectQuickPane();
}

fn runMaximizeQuickPane(state: *runtime.AppState) void {
    _ = state.toggleCurrentProjectQuickPaneMaximized();
}

fn runMinimizeQuickPane(state: *runtime.AppState) void {
    _ = state.minimizeCurrentProjectQuickPane();
}

fn runPinQuickPane(state: *runtime.AppState) void {
    _ = state.toggleCurrentProjectQuickPanePinned();
}

fn runTileQuickPane(state: *runtime.AppState) void {
    _ = state.returnCurrentProjectQuickPaneToTile();
}

fn runScrollingAutomatic(state: *runtime.AppState) void {
    state.setWorkspaceScrollMode(.automatic);
}

fn runScrollingAlways(state: *runtime.AppState) void {
    state.setWorkspaceScrollMode(.always);
}

fn runScrollingDisabled(state: *runtime.AppState) void {
    state.setWorkspaceScrollMode(.disabled);
}

fn runScrollingUseGlobal(state: *runtime.AppState) void {
    state.setWorkspaceScrollMode(null);
}

fn runResetScrollingColumnWidth(state: *runtime.AppState) void {
    if (state.project_controller.selected_index >= state.project_controller.projects.items.len) return;
    state.project_controller.projects.items[state.project_controller.selected_index].workspace_layout.clearScrollPaneExtents();
    state.setSidebarNotice("Scrolling pane widths reset to Panes per view.");
    state.markDirty();
}

fn runUseCurrentRuntimeDefault(state: *runtime.AppState) void {
    state.useCurrentThreadRuntimeAsWorkspaceDefault();
}

fn runUseLocalRuntimeDefault(state: *runtime.AppState) void {
    state.useLocalAsWorkspaceRuntimeDefault();
}

fn runAddWorkspace(state: *runtime.AppState) void {
    state.openWorkspaceCreator(true);
}

fn runRenameWorkspace(state: *runtime.AppState) void {
    state.beginProjectRename(state.project_controller.selected_index);
}

fn runRenameCurrentChat(state: *runtime.AppState) void {
    state.beginCurrentThreadRename();
}

fn runRegenerateChatTitle(state: *runtime.AppState) void {
    state.regenerateCurrentThreadTitle();
}

fn runCloseWorkspace(state: *runtime.AppState) void {
    state.closeProjectAtIndex(state.project_controller.selected_index);
}

fn runReopenWorkspace(state: *runtime.AppState) void {
    _ = state.reopenLastClosedProject();
}

fn runOpenCodexTui(state: *runtime.AppState) void {
    runOpenAgentTui(state, .codex);
}

fn runOpenClaudeTui(state: *runtime.AppState) void {
    runOpenAgentTui(state, .claude);
}

fn runOpenOpencodeTui(state: *runtime.AppState) void {
    runOpenAgentTui(state, .opencode);
}

fn runOpenCursorTui(state: *runtime.AppState) void {
    runOpenAgentTui(state, .cursor);
}

fn runOpenGrokTui(state: *runtime.AppState) void {
    runOpenAgentTui(state, .grok);
}

fn runOpenMuseTui(state: *runtime.AppState) void {
    runOpenAgentTui(state, .muse);
}

fn runGrokSetup(state: *runtime.AppState) void {
    state.openGrokSetupGuide();
}

fn runOpenAmpTui(state: *runtime.AppState) void {
    runOpenAgentTui(state, .amp);
}

fn runHerdrHandoffWorkspace(state: *runtime.AppState) void {
    state.handoffProjectToLocalHerdrFromUi(state.project_controller.selected_index);
}

fn runFocusHerdrTerminal(state: *runtime.AppState) void {
    _ = state.focusProjectHerdrAttachTerminal(state.project_controller.selected_index);
}

fn runUnlinkHerdrWorkspace(state: *runtime.AppState) void {
    state.unlinkProjectHerdrFromUi(state.project_controller.selected_index);
}

fn runOpenAgentTui(state: *runtime.AppState, provider: AgentProvider) void {
    if (workspace_panes.gridNewPanePlacement(state)) |placement| {
        _ = state.openAgentTuiAtPlacement(state.project_controller.selected_index, provider, placement.pane_id, placement.axis, placement.new_after) catch false;
        return;
    }
    _ = state.openAgentTuiAtPlacement(state.project_controller.selected_index, provider, null, .horizontal, true) catch false;
}

fn runHistoryThisWorkspace(state: *runtime.AppState) void {
    state.command_controller.scope_project = state.project_controller.selected_index;
    state.command_controller.query_storage[0] = 0;
    state.command_controller.cursor = 0;
    state.command_controller.selected = 0;
    state.command_controller.action_menu_open = false;
    state.markDirty();
}

fn runSettings(state: *runtime.AppState) void {
    state.openSettingsModal();
}

fn runOpenWorkspaceSettings(state: *runtime.AppState) void {
    // The opener binds the modal by workspace id, so a later selection change
    // cannot retarget the settings surface this command aimed at.
    const index = commandTargetProject(state) orelse return;
    state.openWorkspaceSettingsForProject(index);
}

fn runToggleSidebar(state: *runtime.AppState) void {
    state.toggleSidebarCollapsed();
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// Soft ambient shadow approximating the design's `0 24px 64px` drop.
fn queueDialogShadow(state: *runtime.AppState, rect: palette.Rect, radius: f32) void {
    context_menu.queueSoftShadow(state, rect, radius, designUi(48.0), designUi(16.0), 0.12);
}

/// Search row: magnifier, query field, scope label, bottom divider.
fn renderSearchRow(state: *runtime.AppState) void {
    const cy = search_rect.y + search_rect.h * 0.5;
    const icon = designUi(SEARCH_ICON_CSS);
    queueLucide(state, .{
        .x = search_rect.x + designUi(SEARCH_PAD_X_CSS),
        .y = cy - icon * 0.5,
        .w = icon,
        .h = icon,
    }, LU_SEARCH, icon, paletteColor(theme.COLOR_TEXT_SUBTLE), search_rect);
    renderSearchField(state, cy);

    var scope_buf: [160]u8 = undefined;
    const label = scopeLabel(state, &scope_buf);
    const font = designUi(SCOPE_FONT_CSS);
    queueUiText(state, .{
        .x = scope_x,
        .y = @round(cy - font * 0.65),
        .w = modal_rect.x + modal_rect.w - scope_x,
        .h = font * 1.3,
    }, label, paletteColor(theme.COLOR_TEXT_SUBTLE), font, .ui, search_rect);
    queueDivider(state, search_rect.y + search_rect.h - hairline());
}

/// Borderless query field with selection highlight + caret. Text starts
/// `MODAL_TEXT_INSET_UI` inside `input_rect`, which is what layout.zig's
/// click/drag caret mapping assumes, and uses `searchFontSize()`.
fn renderSearchField(state: *runtime.AppState, cy: f32) void {
    const focused = state.palette_modal_text_focus == .command_palette;
    const value = state.commandPaletteQuery();
    const font_size = searchFontSize();
    const line_height = font_size * 1.25;
    const text_x = search_text_x;
    const text_y = cy - line_height * 0.5;
    const text_w = @max(input_rect.x + input_rect.w - text_x, 0.0);
    // Leave room left of the text for the caret at offset 0.
    const text_clip: palette.Rect = .{ .x = text_x - theme.scaledUi(2.0), .y = search_rect.y, .w = text_w + theme.scaledUi(2.0), .h = search_rect.h };

    if (focused) {
        state.modal_text_input_rect = input_rect;
        state.modal_text_input_font_size = font_size;
        if (state.modal_text_selection_anchor) |anchor| {
            const cursor = @min(state.command_controller.cursor, value.len);
            const a = @min(anchor, value.len);
            if (a != cursor) {
                const start = @min(a, cursor);
                const end = @max(a, cursor);
                const x0 = text_x + runtime.paletteUiTextPrefixWidth(value, font_size, start);
                const x1 = text_x + runtime.paletteUiTextPrefixWidth(value, font_size, end);
                const clamped_x0 = @max(x0, text_x);
                const clamped_x1 = @min(x1, text_x + text_w);
                if (clamped_x1 > clamped_x0) {
                    queueRect(state, .{ .x = clamped_x0, .y = text_y, .w = clamped_x1 - clamped_x0, .h = line_height }, paletteColor(theme.withAlpha(theme.selection(), 200)));
                }
            }
        }
    }

    const placeholder = if (state.command_controller.scope_project != null)
        "Search this workspace's chats"
    else
        "Search chats, commands, and workspaces";
    const shown = if (value.len > 0) value else placeholder;
    const color = if (value.len > 0) theme.COLOR_WHITE else theme.COLOR_TEXT_SUBTLE;
    queueRoleText(state, .{ .x = text_x, .y = text_y, .w = text_w, .h = line_height }, shown, paletteColor(color), font_size, text_clip);

    if (focused) {
        const clamped_cursor = @min(state.command_controller.cursor, value.len);
        const cursor_x = text_x + runtime.paletteUiTextPrefixWidth(value, font_size, clamped_cursor);
        queueRect(state, .{ .x = cursor_x, .y = text_y, .w = theme.scaledUi(1.0), .h = line_height }, paletteColor(theme.COLOR_WHITE));
    }
}

/// Result rows: sentence-case section headers, then command / chat /
/// workspace rows, or the empty state.
fn renderRows(state: *runtime.AppState) void {
    if (result_count == 0) {
        renderEmptyState(state);
        return;
    }
    for (0..result_count) |i| {
        const rect = row_rects[i];
        if (!rowVisible(rect)) continue;
        // Partially-scrolled rows clip to the list viewport so they never
        // paint over the search row above or the footer below.
        const row_clip = intersectRects(rect, list_rect);
        if (row_clip.w <= 0.0 or row_clip.h <= 0.0) continue;
        switch (results[i].ref) {
            .header => |label| renderHeader(state, rect, label, row_clip),
            .command => |ci| renderCommandRow(state, i, ci, rect, row_clip),
            .thread => |tr| renderThreadRow(state, i, tr, rect, row_clip),
            .history => |hi| renderHistoryRow(state, i, hi, rect, row_clip),
            .agent_tui => |tui| renderAgentTuiRow(state, i, tui, rect, row_clip),
            .workspace => |pi| renderWorkspaceRow(state, i, pi, rect, row_clip),
            .closed_workspace => |ai| renderClosedWorkspaceRow(state, i, ai, rect, row_clip),
        }
    }
}

/// Section label sitting on the bottom of its (gap-including) header band.
fn renderHeader(state: *runtime.AppState, rect: palette.Rect, label: []const u8, clip: palette.Rect) void {
    const font = designUi(HEADER_FONT_CSS);
    const bottom = rect.y + rect.h - designUi(HEADER_BOTTOM_PAD_CSS);
    queueUiText(state, .{
        .x = rect.x + designUi(ROW_PAD_X_CSS),
        .y = @round(bottom - font * 1.3),
        .w = rect.w - designUi(ROW_PAD_X_CSS) * 2.0,
        .h = font * 1.3,
    }, label, paletteColor(theme.COLOR_TEXT_SUBTLE), font, .ui_medium, clip);
}

fn renderEmptyState(state: *runtime.AppState) void {
    const query = state.commandPaletteQuery();
    var buf: [320]u8 = undefined;
    const label = if (query.len > 0)
        std.fmt.bufPrint(&buf, "No results for \u{201C}{s}\u{201D}", .{query}) catch "No results"
    else if (state.command_controller.scope_project != null)
        "No saved chats in this workspace yet"
    else
        "Nothing to show yet";
    const font = designUi(ROW_FONT_CSS);
    const max_w = @max(list_rect.w - designUi(ROW_PAD_X_CSS) * 2.0, 0.0);
    const w = @min(text_measure.textWidth(.ui, font, label), max_w);
    queueMatchText(state, list_rect.x + (list_rect.w - w) * 0.5, list_rect.y + designUi(32.0), w, label, 0, "", paletteColor(theme.COLOR_TEXT_SUBTLE), font, list_rect);
}

/// Leading slot of a result row: a Lucide glyph or a provider logo.
const RowLeading = union(enum) {
    icon: []const u8,
    provider: Provider,
};

/// Right-aligned element of a result row.
const RowTrailing = union(enum) {
    none,
    /// Keybind hint as produced by `keybinds.formatKeybind`.
    hint: []const u8,
    /// Plain status word ("open", "saved").
    status: struct { label: []const u8, color: [4]f32 },
    /// Small outlined tag ("closed").
    tag: []const u8,
};

const RowSpec = struct {
    leading: RowLeading,
    title: []const u8,
    /// Byte offset where query highlighting may start, so fixed prefixes
    /// ("Switch to ") never light up.
    match_from: usize = 0,
    /// Secondary line; rows without one are single-line.
    meta: []const u8 = "",
    trailing: RowTrailing = .none,
};

/// Shared row body: selection/hover fill, leading slot, title with matched
/// query characters in medium weight, optional meta line, trailing element.
fn renderResultRow(state: *runtime.AppState, row_index: usize, rect: palette.Rect, clip: palette.Rect, spec: RowSpec) void {
    renderRowBackground(state, row_index, rect, clip);
    const selected = state.command_controller.selected == row_index;
    const pad = designUi(ROW_PAD_X_CSS);
    const icon = designUi(ROW_ICON_CSS);
    const cy = rect.y + rect.h * 0.5;
    const icon_x = rect.x + pad;
    switch (spec.leading) {
        .icon => |glyph| queueLucide(
            state,
            .{ .x = icon_x, .y = cy - icon * 0.5, .w = icon, .h = icon },
            glyph,
            icon,
            paletteColor(if (selected) theme.COLOR_WHITE else theme.COLOR_TEXT_MUTED),
            clip,
        ),
        .provider => |provider| {
            const glyph = theme.scaledUi(PROVIDER_GLYPH_UI);
            sidebar.queuePaletteProviderGlyph(state, provider, icon_x + (icon - glyph) * 0.5, cy, clip);
        },
    }

    const gap = designUi(ROW_ICON_GAP_CSS);
    const title_x = icon_x + icon + gap;
    const right = rect.x + rect.w - pad;
    const trailing_w = queueRowTrailing(state, right, cy, spec.trailing, clip);
    const title_right = if (trailing_w > 0.0) right - trailing_w - gap else right;
    const max_w = @max(title_right - title_x, 0.0);
    const font = designUi(ROW_FONT_CSS);
    const query = state.commandPaletteQuery();
    const title_color = paletteColor(theme.COLOR_WHITE);
    if (spec.meta.len == 0) {
        queueMatchText(state, title_x, cy, max_w, spec.title, spec.match_from, query, title_color, font, clip);
        return;
    }
    // Title + meta at line-height 1.3, centred as one block.
    const meta_font = designUi(ROW_META_FONT_CSS);
    const title_h = font * 1.3;
    const meta_h = meta_font * 1.3;
    const top = cy - (title_h + meta_h) * 0.5;
    queueMatchText(state, title_x, top + title_h * 0.5, max_w, spec.title, spec.match_from, query, title_color, font, clip);
    queueMatchText(state, title_x, top + title_h + meta_h * 0.5, max_w, spec.meta, 0, "", paletteColor(theme.COLOR_TEXT_SUBTLE), meta_font, clip);
}

/// Draws the trailing element ending at `right`; returns its width.
fn queueRowTrailing(state: *runtime.AppState, right: f32, cy: f32, trailing: RowTrailing, clip: palette.Rect) f32 {
    const font = designUi(ROW_META_FONT_CSS);
    switch (trailing) {
        .none => return 0.0,
        .hint => |hint| {
            if (hint.len == 0) return 0.0;
            const w = shortcutHintWidth(hint, font);
            queueShortcutHint(state, right - w, cy, hint, paletteColor(theme.COLOR_TEXT_SUBTLE), font, clip);
            return w;
        },
        .status => |status| {
            const w = text_measure.textWidth(.ui, font, status.label);
            queueUiText(state, .{
                .x = right - w,
                .y = @round(cy - font * 0.65),
                .w = w + theme.scaledUi(2.0),
                .h = font * 1.3,
            }, status.label, paletteColor(status.color), font, .ui, clip);
            return w;
        },
        .tag => |label| {
            const tag_font = designUi(TAG_FONT_CSS);
            const pad_x = designUi(TAG_PAD_X_CSS);
            const text_w = text_measure.textWidth(.ui, tag_font, label);
            const w = text_w + pad_x * 2.0;
            const h = tag_font * 1.3 + designUi(2.0);
            const pill = context_menu.snap(.{ .x = right - w, .y = cy - h * 0.5, .w = w, .h = h });
            state.palette_overlay_batch.rectBorderClipped(state.allocator, pill, paletteColor(theme.restingEdge()), designUi(TAG_RADIUS_CSS), hairline(), clip) catch |err| {
                log.warn("failed to queue palette tag border: {s}", .{@errorName(err)});
            };
            queueUiText(state, .{
                .x = pill.x + pad_x,
                .y = @round(cy - tag_font * 0.65),
                .w = text_w + theme.scaledUi(2.0),
                .h = tag_font * 1.3,
            }, label, paletteColor(theme.COLOR_TEXT_SUBTLE), tag_font, .ui, clip);
            return w;
        },
    }
}

/// Soft neutral fill for the keyboard-selected row, lighter for hover.
fn renderRowBackground(state: *runtime.AppState, row_index: usize, rect: palette.Rect, clip: palette.Rect) void {
    const selected = state.command_controller.selected == row_index;
    const hovered = hovered_row != null and hovered_row.? == row_index;
    if (!selected and !hovered) return;
    const fill = panelTint(if (selected) SELECTED_TINT else HOVER_TINT);
    state.palette_overlay_batch.roundedRectClipped(state.allocator, rect, paletteColor(fill), designUi(ROW_RADIUS_CSS), clip) catch |err| {
        log.warn("failed to queue palette row fill: {s}", .{@errorName(err)});
    };
}

fn renderCommandRow(state: *runtime.AppState, row_index: usize, command_index: usize, rect: palette.Rect, clip: palette.Rect) void {
    const command = STATIC_COMMANDS[command_index];
    renderResultRow(state, row_index, rect, clip, .{
        .leading = .{ .icon = command.icon },
        .title = command.title,
        .trailing = .{ .hint = keybindHintFor(state, command.keybind) },
    });
}

fn renderThreadRow(state: *runtime.AppState, row_index: usize, tr: ThreadRef, rect: palette.Rect, clip: palette.Rect) void {
    if (tr.project >= state.project_controller.projects.items.len) return;
    const project = &state.project_controller.projects.items[tr.project];
    if (tr.thread >= project.threads.items.len) return;
    const thread = &project.threads.items[tr.thread];
    var title_buf: sidebar.TerminalTitleBuffer = undefined;
    var meta_buf: [192]u8 = undefined;
    renderResultRow(state, row_index, rect, clip, .{
        .leading = .{ .provider = thread.provider },
        .title = sidebar.chatTitle(&title_buf, thread.title),
        .meta = chatMeta(state, &meta_buf, "", project.label, thread.last_activity_at),
        .trailing = statusTrailing(threadOpenPaneId(project, tr.thread) != null),
    });
}

/// Row for a closed thread fetched from the daemon (item 5b).
fn renderHistoryRow(state: *runtime.AppState, row_index: usize, history_index: usize, rect: palette.Rect, clip: palette.Rect) void {
    const items = state.paletteHistoryItems();
    if (history_index >= items.len) return;
    const item = items[history_index];
    var workspace: []const u8 = item.workspace_id;
    for (state.project_controller.projects.items) |*project| {
        if (std.mem.eql(u8, project.id, item.workspace_id)) {
            workspace = project.label;
            break;
        }
    }
    var meta_buf: [192]u8 = undefined;
    renderResultRow(state, row_index, rect, clip, .{
        .leading = .{ .provider = std.meta.stringToEnum(Provider, item.provider) orelse .opencode },
        .title = item.title,
        .meta = chatMeta(state, &meta_buf, "", workspace, item.last_activity_at orelse 0),
        .trailing = statusTrailing(false),
    });
}

/// History row for a saved agent TUI terminal session.
fn renderAgentTuiRow(state: *runtime.AppState, row_index: usize, tui: AgentTuiRef, rect: palette.Rect, clip: palette.Rect) void {
    if (tui.project >= state.project_controller.projects.items.len) return;
    const project = &state.project_controller.projects.items[tui.project];
    const provider = state.workspaceAgentTuiProvider(tui.project, tui.dock) orelse return;
    const provider_label = agentTuiSearchLabel(provider);
    var title_buf: [96]u8 = undefined;
    const title = if (state.projectTerminalDock(tui.project, tui.dock)) |dock|
        dock.activeProcessLabel(&title_buf)
    else
        provider_label;
    var is_open = false;
    for (project.workspace_layout.panes.items) |pane| {
        switch (pane.ref) {
            .terminal => |ref| if (ref.dock_id == tui.dock) {
                is_open = true;
                break;
            },
            else => {},
        }
    }
    var meta_buf: [192]u8 = undefined;
    const activity_at = @divTrunc(state.workspaceAgentTuiHistoryAt(tui.project, tui.dock), std.time.ms_per_s);
    const prefix = if (std.mem.eql(u8, title, provider_label)) "" else provider_label;
    renderResultRow(state, row_index, rect, clip, .{
        .leading = .{ .icon = LU_SQUARE_TERMINAL },
        .title = title,
        .meta = chatMeta(state, &meta_buf, prefix, project.label, activity_at),
        .trailing = statusTrailing(is_open),
    });
}

fn renderWorkspaceRow(state: *runtime.AppState, row_index: usize, project_index: usize, rect: palette.Rect, clip: palette.Rect) void {
    if (project_index >= state.project_controller.projects.items.len) return;
    const prefix = "Switch to ";
    var buf: [128]u8 = undefined;
    const label = std.fmt.bufPrint(&buf, prefix ++ "{s}", .{state.project_controller.projects.items[project_index].label}) catch "Switch workspace";
    var hint_buf_local: [32]u8 = undefined;
    renderResultRow(state, row_index, rect, clip, .{
        .leading = .{ .icon = LU_FOLDER },
        .title = label,
        .match_from = prefix.len,
        .trailing = .{ .hint = workspaceSelectHintFor(state, &hint_buf_local, project_index) },
    });
}

fn renderClosedWorkspaceRow(state: *runtime.AppState, row_index: usize, archived_index: usize, rect: palette.Rect, clip: palette.Rect) void {
    if (archived_index >= state.project_controller.archived_projects.items.len) return;
    const prefix = "Reopen ";
    var buf: [128]u8 = undefined;
    const label = std.fmt.bufPrint(&buf, prefix ++ "{s}", .{state.project_controller.archived_projects.items[archived_index].label}) catch "Reopen workspace";
    renderResultRow(state, row_index, rect, clip, .{
        .leading = .{ .icon = LU_FOLDER },
        .title = label,
        .match_from = prefix.len,
        .trailing = .{ .tag = "closed" },
    });
}

fn statusTrailing(is_open: bool) RowTrailing {
    return .{ .status = .{
        .label = if (is_open) "open" else "saved",
        .color = if (is_open) theme.success() else theme.COLOR_TEXT_SUBTLE,
    } };
}

/// Secondary chat line: optional prefix, the workspace (only when results
/// span workspaces), and a relative age, joined by middle dots.
fn chatMeta(state: *runtime.AppState, buf: []u8, prefix: []const u8, workspace: []const u8, at: i64) []const u8 {
    var age_buf: [32]u8 = undefined;
    const show_workspace = state.command_controller.scope_project == null;
    const parts = [_][]const u8{ prefix, if (show_workspace) workspace else "", formatAge(&age_buf, at) };
    var len: usize = 0;
    for (parts) |part| {
        if (part.len == 0) continue;
        if (len > 0) len += copyInto(buf[len..], " \u{00B7} ");
        len += copyInto(buf[len..], part);
    }
    return buf[0..len];
}

/// Relative age for chat rows ("3h ago", "yesterday"); "" when unknown.
fn formatAge(buf: []u8, timestamp: i64) []const u8 {
    if (timestamp <= 0) return "";
    return formatElapsed(buf, @max(unixTimestampSeconds() - timestamp, 0));
}

fn formatElapsed(buf: []u8, elapsed: i64) []const u8 {
    const day: i64 = 86_400;
    if (elapsed < 60) return "just now";
    if (elapsed < 3600) return std.fmt.bufPrint(buf, "{d}m ago", .{@divFloor(elapsed, 60)}) catch "";
    if (elapsed < day) return std.fmt.bufPrint(buf, "{d}h ago", .{@divFloor(elapsed, 3600)}) catch "";
    if (elapsed < 2 * day) return "yesterday";
    if (elapsed < 7 * day) return std.fmt.bufPrint(buf, "{d} days ago", .{@divFloor(elapsed, day)}) catch "";
    if (elapsed < 14 * day) return "last week";
    if (elapsed < 30 * day) return std.fmt.bufPrint(buf, "{d} weeks ago", .{@divFloor(elapsed, 7 * day)}) catch "";
    if (elapsed < 60 * day) return "last month";
    if (elapsed < 365 * day) return std.fmt.bufPrint(buf, "{d} months ago", .{@divFloor(elapsed, 30 * day)}) catch "";
    return "over a year ago";
}

/// Tab/→ submenu for a chat row, drawn with the shared context-menu chrome.
fn renderActionMenu(state: *runtime.AppState) void {
    if (action_count == 0) return;
    const panel = context_menu.queuePanel(state, action_menu_rect);
    for (0..action_count) |i| {
        const row = action_rects[i];
        const selected = state.command_controller.action_selected == i;
        if (selected and action_enabled[i]) context_menu.queueRowHighlight(state, row);
        context_menu.queueLabel(state, row, action_labels[i], context_menu.labelColor(action_enabled[i], selected), 0.0, 0.0, panel);
    }
}

/// Key used in a footer hint: a Lucide glyph (↵, →) or a short word (esc).
const FooterKey = union(enum) {
    glyph: []const u8,
    text: []const u8,
};

/// Footer key hints: ↵ Run, → Thread actions, a scope hint when it fits,
/// and esc Close pinned right.
fn renderFooter(state: *runtime.AppState) void {
    queueDivider(state, footer_rect.y);
    const font = designUi(FOOTER_FONT_CSS);
    const cy = footer_rect.y + footer_rect.h * 0.5;
    const color = paletteColor(theme.COLOR_TEXT_SUBTLE);
    const pad_x = designUi(SEARCH_PAD_X_CSS);
    const gap = designUi(FOOTER_GAP_CSS);
    const clip = footer_rect;

    const esc_key: FooterKey = .{ .text = "esc" };
    const esc_x = footer_rect.x + footer_rect.w - pad_x - footerHintWidth(esc_key, "Close", font);
    var x = footer_rect.x + pad_x;
    x = queueFooterHint(state, x, cy, .{ .glyph = LU_CORNER_DOWN_LEFT }, "Run", font, color, clip) + gap;
    x = queueFooterHint(state, x, cy, .{ .glyph = LU_ARROW_RIGHT }, "Thread actions", font, color, clip) + gap;

    if (state.command_controller.scope_project == null) {
        // "Type history for this workspace" — the History command re-scopes.
        const lead = "Type ";
        const word = "history";
        const tail = " for this workspace";
        const lead_w = text_measure.textWidth(.ui, font, lead);
        const word_w = text_measure.textWidth(.ui_medium, font, word);
        const tail_w = text_measure.textWidth(.ui, font, tail);
        if (x + lead_w + word_w + tail_w <= esc_x - gap) {
            x = queueFooterText(state, x, cy, lead, .ui, font, color, clip);
            x = queueFooterText(state, x, cy, word, .ui_medium, font, color, clip);
            _ = queueFooterText(state, x, cy, tail, .ui, font, color, clip);
        }
    } else {
        // Scoped history: the palette shortcut widens back to all workspaces.
        const shortcut = commandPaletteShortcutHint(state);
        const label = "All workspaces";
        const key_gap = designUi(FOOTER_KEY_GAP_CSS);
        const shortcut_w = shortcutHintWidth(shortcut, font);
        if (shortcut.len > 0 and x + shortcut_w + key_gap + text_measure.textWidth(.ui, font, label) <= esc_x - gap) {
            queueShortcutHint(state, x, cy, shortcut, color, font, clip);
            _ = queueFooterText(state, x + shortcut_w + key_gap, cy, label, .ui, font, color, clip);
        }
    }
    _ = queueFooterHint(state, esc_x, cy, esc_key, "Close", font, color, clip);
}

fn footerKeyWidth(key: FooterKey, font: f32) f32 {
    return switch (key) {
        .glyph => font,
        .text => |value| text_measure.textWidth(.ui_medium, font, value),
    };
}

fn footerHintWidth(key: FooterKey, label: []const u8, font: f32) f32 {
    return footerKeyWidth(key, font) + designUi(FOOTER_KEY_GAP_CSS) + text_measure.textWidth(.ui, font, label);
}

/// Draws "<key> <label>" from `x`; returns the right edge.
fn queueFooterHint(state: *runtime.AppState, x: f32, cy: f32, key: FooterKey, label: []const u8, font: f32, color: palette.Color, clip: palette.Rect) f32 {
    const key_w = footerKeyWidth(key, font);
    switch (key) {
        .glyph => |glyph| queueLucide(state, .{ .x = x, .y = cy - font * 0.5, .w = font, .h = font }, glyph, font, color, clip),
        .text => |value| _ = queueFooterText(state, x, cy, value, .ui_medium, font, color, clip),
    }
    return queueFooterText(state, x + key_w + designUi(FOOTER_KEY_GAP_CSS), cy, label, .ui, font, color, clip);
}

/// Draws one footer text run from `x`; returns the right edge.
fn queueFooterText(state: *runtime.AppState, x: f32, cy: f32, value: []const u8, role: palette.FontRole, font: f32, color: palette.Color, clip: palette.Rect) f32 {
    const w = text_measure.textWidth(role, font, value);
    queueUiText(state, .{ .x = x, .y = @round(cy - font * 0.65), .w = w + theme.scaledUi(4.0), .h = font * 1.3 }, value, color, font, role, clip);
    return x + w;
}

/// Thin neutral thumb on the list's right edge when results overflow.
fn renderScrollbar(state: *runtime.AppState) void {
    if (max_scroll_y <= 1.0 or list_rect.h <= designUi(32.0)) return;
    const track: palette.Rect = .{
        .x = modal_rect.x + modal_rect.w - designUi(6.0),
        .y = list_rect.y + designUi(2.0),
        .w = designUi(3.0),
        .h = list_rect.h - designUi(4.0),
    };
    const thumb_h = @max(designUi(24.0), track.h * (track.h / (track.h + max_scroll_y)));
    const thumb_y = track.y + (track.h - thumb_h) * (scroll_y / max_scroll_y);
    queueRoundedRect(state, .{ .x = track.x, .y = thumb_y, .w = track.w, .h = thumb_h }, paletteColor(panelTint(SCROLL_THUMB_TINT)), track.w * 0.5);
}

// ---------------------------------------------------------------------------
// Match highlighting + shortcut hints
// ---------------------------------------------------------------------------

/// Draws a single line vertically centred on `cy`, ellipsized to `max_w`,
/// with the bytes matching `query` (from `match_from` on) in medium weight.
/// An empty query draws plain ellipsized text.
fn queueMatchText(
    state: *runtime.AppState,
    x: f32,
    cy: f32,
    max_w: f32,
    full: []const u8,
    match_from: usize,
    query: []const u8,
    color: palette.Color,
    font_size: f32,
    clip: palette.Rect,
) void {
    if (max_w <= 0.0 or full.len == 0) return;
    const text = utf8Prefix(full, MAX_HIGHLIGHT_BYTES);
    var mask: [MAX_HIGHLIGHT_BYTES]bool = @splat(false);
    var any_match = false;
    if (query.len > 0 and match_from < text.len) {
        any_match = matchMask(text[match_from..], query, mask[match_from..text.len]);
    }
    // Keep multi-byte sequences in one run so no segment splits a codepoint.
    for (1..text.len) |i| {
        if ((text[i] & 0xC0) == 0x80) mask[i] = mask[i - 1];
    }

    var regular: [MAX_HIGHLIGHT_BYTES]f32 = undefined;
    var medium: [MAX_HIGHLIGHT_BYTES]f32 = undefined;
    text_measure.textGlyphAdvances(.ui, text, font_size, regular[0..text.len]);
    if (any_match) text_measure.textGlyphAdvances(.ui_medium, text, font_size, medium[0..text.len]);
    const advances = struct {
        fn at(m: []const bool, r: []const f32, md: []const f32, i: usize) f32 {
            return if (m[i]) md[i] else r[i];
        }
    };

    var total: f32 = 0.0;
    for (0..text.len) |i| total += advances.at(&mask, &regular, &medium, i);
    var end = text.len;
    const ellipsize = total > max_w or text.len < full.len;
    if (ellipsize) {
        const ellipsis_w = text_measure.textWidth(.ui, font_size, ELLIPSIS);
        var acc: f32 = 0.0;
        end = 0;
        for (0..text.len) |i| {
            acc += advances.at(&mask, &regular, &medium, i);
            const boundary = i + 1 == text.len or (text[i + 1] & 0xC0) != 0x80;
            if (!boundary) continue;
            if (acc + ellipsis_w > max_w) break;
            end = i + 1;
        }
    }

    const line_h = font_size * 1.3;
    const y = @round(cy - font_size * 0.65);
    const text_clip = intersectRects(.{ .x = x, .y = clip.y, .w = max_w + theme.scaledUi(2.0), .h = clip.h }, clip);
    if (text_clip.w <= 0.0 or text_clip.h <= 0.0) return;
    var seg_x = x;
    var i: usize = 0;
    while (i < end) {
        const emphasized = mask[i];
        var j = i;
        var seg_w: f32 = 0.0;
        while (j < end and mask[j] == emphasized) : (j += 1) seg_w += advances.at(&mask, &regular, &medium, j);
        queueUiText(state, .{ .x = seg_x, .y = y, .w = seg_w + theme.scaledUi(4.0), .h = line_h }, text[i..j], color, font_size, if (emphasized) .ui_medium else .ui, text_clip);
        seg_x += seg_w;
        i = j;
    }
    if (ellipsize) {
        queueUiText(state, .{ .x = seg_x, .y = y, .w = font_size * 2.0, .h = line_h }, ELLIPSIS, color, font_size, .ui, text_clip);
    }
}

/// Longest prefix of `value` no longer than `max_len` bytes that ends on a
/// UTF-8 boundary.
fn utf8Prefix(value: []const u8, max_len: usize) []const u8 {
    if (value.len <= max_len) return value;
    var end = max_len;
    while (end > 0 and (value[end] & 0xC0) == 0x80) end -= 1;
    return value[0..end];
}

/// Marks the haystack bytes `fuzzyScore` matches: the substring hit, else
/// the greedy in-order subsequence. Leaves `mask` untouched and returns
/// false when the query does not match.
fn matchMask(haystack: []const u8, needle: []const u8, mask: []bool) bool {
    std.debug.assert(mask.len == haystack.len);
    if (needle.len == 0 or haystack.len == 0) return false;
    if (asciiIndexOfIgnoreCase(haystack, needle)) |pos| {
        @memset(mask[pos .. pos + needle.len], true);
        return true;
    }
    var positions: [MAX_HIGHLIGHT_BYTES]usize = undefined;
    if (needle.len > positions.len) return false;
    var hi: usize = 0;
    for (needle, 0..) |nb, ni| {
        const nl = std.ascii.toLower(nb);
        while (hi < haystack.len and std.ascii.toLower(haystack[hi]) != nl) : (hi += 1) {}
        if (hi >= haystack.len) return false;
        positions[ni] = hi;
        hi += 1;
    }
    for (positions[0..needle.len]) |pos| mask[pos] = true;
    return true;
}

/// A keybind hint split into leading macOS modifier symbols (⌃⌥⇧⌘, from
/// `keybinds.formatKeybind`) mapped to Lucide glyphs, and the key text.
/// Mirrors sidebar.zig's `renderShortcutHint` so hints share one look.
const ShortcutParts = struct {
    mods: [4][]const u8 = undefined,
    mod_count: usize = 0,
    key: []const u8 = "",
};

fn splitShortcut(hint: []const u8) ShortcutParts {
    var parts: ShortcutParts = .{};
    var rest = hint;
    while (rest.len >= 3 and parts.mod_count < parts.mods.len) {
        const lucide: ?[]const u8 = if (std.mem.startsWith(u8, rest, "\u{2303}"))
            LU_CONTROL
        else if (std.mem.startsWith(u8, rest, "\u{2325}"))
            LU_OPTION
        else if (std.mem.startsWith(u8, rest, "\u{21E7}"))
            LU_SHIFT
        else if (std.mem.startsWith(u8, rest, "\u{2318}"))
            LU_COMMAND
        else
            null;
        parts.mods[parts.mod_count] = lucide orelse break;
        parts.mod_count += 1;
        rest = rest[3..];
    }
    parts.key = rest;
    return parts;
}

/// Modifier glyphs sit a touch smaller than the key text (11.5 vs 12 px).
fn shortcutGlyphSize(font: f32) f32 {
    return font * (11.5 / 12.0);
}

fn shortcutHintWidth(hint: []const u8, font: f32) f32 {
    if (hint.len == 0) return 0.0;
    const parts = splitShortcut(hint);
    const mods_w = @as(f32, @floatFromInt(parts.mod_count)) * (shortcutGlyphSize(font) + designUi(1.0));
    return mods_w + text_measure.textWidth(.ui, font, parts.key);
}

/// Draws a keybind hint starting at `x`, vertically centred on `cy`.
fn queueShortcutHint(state: *runtime.AppState, x: f32, cy: f32, hint: []const u8, color: palette.Color, font: f32, clip: palette.Rect) void {
    const parts = splitShortcut(hint);
    const glyph = shortcutGlyphSize(font);
    var cursor_x = x;
    for (parts.mods[0..parts.mod_count]) |g| {
        queueLucide(state, .{ .x = cursor_x, .y = cy - glyph * 0.5, .w = glyph, .h = glyph }, g, glyph, color, clip);
        cursor_x += glyph + designUi(1.0);
    }
    if (parts.key.len == 0) return;
    const key_w = text_measure.textWidth(.ui, font, parts.key);
    queueUiText(state, .{ .x = cursor_x, .y = @round(cy - font * 0.65), .w = key_w + theme.scaledUi(4.0), .h = font * 1.3 }, parts.key, color, font, .ui, clip);
}

// ---------------------------------------------------------------------------
// Keybind hints
// ---------------------------------------------------------------------------

var hint_buf: [32]u8 = undefined;

/// Formats the first loaded accelerator for a command's keybind reference, so
/// hints track user rebinds. Returns "" when unbound.
fn keybindHintFor(state: *runtime.AppState, ref: ?KeybindRef) []const u8 {
    const keybind_ref = ref orelse return "";
    const config = state.command_controller.keyboard_config orelse return "";
    const bindings = switch (keybind_ref) {
        .new_thread => config.new_thread,
        .chat_model_picker => config.chat_model_picker,
        .chat_run_config => config.chat_run_config,
        .chat_directory_picker => config.chat_directory_picker,
        .settings => config.settings,
        .toggle_sidebar => config.toggle_sidebar,
        .toggle_browser => config.toggle_browser,
        .toggle_terminal => config.toggle_terminal,
        .workspace_close => config.workspace_close,
        .workspace_close_current => config.workspace_close_current,
        .workspace_toggle_maximize => config.workspace_toggle_maximize,
        .workspace_toggle_quick_pane => config.workspace_toggle_quick_pane,
        .workspace_split_chat_vertical => config.workspace_split_chat_vertical,
        .workspace_split_chat_horizontal => config.workspace_split_chat_horizontal,
        .workspace_split_terminal_vertical => config.workspace_split_terminal_vertical,
        .workspace_split_terminal_horizontal => config.workspace_split_terminal_horizontal,
        .workspace_previous_pane => switch (state.app_config.workspace_scroll_direction) {
            .horizontal => config.workspace_focus_left,
            .vertical => config.workspace_focus_up,
        },
        .workspace_next_pane => switch (state.app_config.workspace_scroll_direction) {
            .horizontal => config.workspace_focus_right,
            .vertical => config.workspace_focus_down,
        },
    };
    if (bindings.len == 0) return "";
    return formatKeybind(&hint_buf, bindings[0]);
}

fn workspaceSelectHintFor(state: *runtime.AppState, buf: []u8, project_index: usize) []const u8 {
    const config = state.command_controller.keyboard_config orelse return "";
    return indexedKeybindHint(buf, config.workspace_select, project_index);
}

fn indexedKeybindHint(buf: []u8, bindings: []const keybinds.Keybind, index: usize) []const u8 {
    if (index >= bindings.len) return "";
    return formatKeybind(buf, bindings[index]);
}

/// Formats the first loaded command-palette accelerator for UI hints (the
/// sidebar's search-trigger badge), so the label tracks user rebinds instead
/// of hardcoding the default. Returns "" when unbound.
pub fn commandPaletteShortcutHint(state: *runtime.AppState) []const u8 {
    const config = state.command_controller.keyboard_config orelse return "";
    if (config.command_palette.len == 0) return "";
    return formatKeybind(&hint_buf, config.command_palette[0]);
}

fn formatKeybind(buf: []u8, keybind: keybinds.Keybind) []const u8 {
    return keybinds.formatKeybind(buf, keybind);
}

fn copyInto(dest: []u8, src: []const u8) usize {
    const n = @min(dest.len, src.len);
    @memcpy(dest[0..n], src[0..n]);
    return n;
}

// ---------------------------------------------------------------------------
// Palette batch helpers (module-local mirrors of layout.zig's queue fns)
// ---------------------------------------------------------------------------

fn rowVisible(rect: palette.Rect) bool {
    return rect.y + rect.h >= list_rect.y and rect.y <= list_rect.y + list_rect.h;
}

fn rectContainsPoint(rect: palette.Rect, x: f32, y: f32) bool {
    return x >= rect.x and y >= rect.y and x <= rect.x + rect.w and y <= rect.y + rect.h;
}

fn paletteColor(value: [4]f32) palette.Color {
    return .{ .r = value[0], .g = value[1], .b = value[2], .a = value[3] };
}

/// Neutral fill mixed from the dialog surface toward the text colour, so
/// selection/hover/dividers read on light and dark themes alike.
fn panelTint(amount: f32) [4]f32 {
    return theme.mix(theme.COLOR_PANEL, theme.COLOR_WHITE, amount);
}

/// One device-pixel-or-more hairline width.
fn hairline() f32 {
    return @max(@round(theme.scaledUi(1.0)), 1.0);
}

/// Full-width divider inside the dialog border at `y`.
fn queueDivider(state: *runtime.AppState, y: f32) void {
    const inset = hairline();
    queueRect(state, context_menu.snap(.{ .x = modal_rect.x + inset, .y = y, .w = modal_rect.w - inset * 2.0, .h = inset }), paletteColor(panelTint(DIVIDER_TINT)));
}

fn keymodBits(modifier_state: sdl.Keymod) u16 {
    return @as(*const u16, @ptrCast(&modifier_state)).*;
}

fn queueRect(state: *runtime.AppState, rect: palette.Rect, color: palette.Color) void {
    state.palette_overlay_batch.rect(state.allocator, rect, color) catch |err| {
        log.warn("failed to queue palette rect: {s}", .{@errorName(err)});
    };
}

fn queueRoundedRect(state: *runtime.AppState, rect: palette.Rect, color: palette.Color, radius: f32) void {
    state.palette_overlay_batch.roundedRect(state.allocator, rect, color, radius) catch |err| {
        log.warn("failed to queue palette rounded rect: {s}", .{@errorName(err)});
    };
}

fn queueBorder(state: *runtime.AppState, rect: palette.Rect, color: palette.Color, radius: f32, width: f32) void {
    state.palette_overlay_batch.rectBorder(state.allocator, rect, color, radius, width) catch |err| {
        log.warn("failed to queue palette border: {s}", .{@errorName(err)});
    };
}

fn stableText(state: *runtime.AppState, value: []const u8) ?[]const u8 {
    return state.palette_frame_text_arena.allocator().dupe(u8, value) catch |err| {
        log.warn("failed to retain palette text: {s}", .{@errorName(err)});
        return null;
    };
}

fn intersectRects(a: palette.Rect, b: palette.Rect) palette.Rect {
    const x0 = @max(a.x, b.x);
    const y0 = @max(a.y, b.y);
    const x1 = @min(a.x + a.w, b.x + b.w);
    const y1 = @min(a.y + a.h, b.y + b.h);
    return .{ .x = x0, .y = y0, .w = @max(x1 - x0, 0.0), .h = @max(y1 - y0, 0.0) };
}

/// Lucide glyph centred in `rect`.
fn queueLucide(state: *runtime.AppState, rect: palette.Rect, glyph: []const u8, size: f32, color: palette.Color, clip: palette.Rect) void {
    const stable_value = stableText(state, glyph) orelse return;
    state.palette_overlay_batch.roleText(
        state.allocator,
        context_menu.snap(.{ .x = rect.x + (rect.w - size) * 0.5, .y = rect.y + (rect.h - size) * 0.5, .w = size, .h = size }),
        stable_value,
        color,
        size,
        .icon_alt,
        null,
        clip,
    ) catch |err| {
        log.warn("failed to queue command palette glyph: {s}", .{@errorName(err)});
    };
}

/// Single-line chrome text in an explicit role (a null role renders bold).
fn queueUiText(state: *runtime.AppState, rect: palette.Rect, value: []const u8, color: palette.Color, font_size: f32, role: palette.FontRole, clip: palette.Rect) void {
    const stable_value = stableText(state, value) orelse return;
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
        log.warn("failed to queue palette text: {s}", .{@errorName(err)});
    };
}

/// Query-field text; `roleText` keeps glyph placement identical to the
/// `paletteUiTextPrefixWidth` metrics the caret and selection use.
fn queueRoleText(state: *runtime.AppState, rect: palette.Rect, value: []const u8, color: palette.Color, font_size: f32, clip: ?palette.Rect) void {
    const stable_value = stableText(state, value) orelse return;
    state.palette_overlay_batch.roleText(
        state.allocator,
        rect,
        stable_value,
        color,
        font_size,
        .ui,
        null,
        clip,
    ) catch |err| {
        log.warn("failed to queue palette role text: {s}", .{@errorName(err)});
    };
}

test "static commands expose scrolling layout controls" {
    const expected_ids = [_][]const u8{
        "pane.previous",
        "pane.next",
        "workspace.scrolling_use_global",
        "workspace.scrolling_automatic",
        "workspace.scrolling_always",
        "workspace.scrolling_disabled",
        "workspace.scrolling_reset_column_width",
    };
    for (expected_ids) |expected_id| {
        var found = false;
        for (STATIC_COMMANDS) |command| {
            if (std.mem.eql(u8, command.id, expected_id)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "static commands expose workspace runtime defaults without replacing thread selection" {
    const expected_ids = [_][]const u8{
        "workspace.runtime_default_current",
        "workspace.runtime_default_local",
    };
    for (expected_ids) |expected_id| {
        var found = false;
        for (STATIC_COMMANDS) |command| {
            if (!std.mem.eql(u8, command.id, expected_id)) continue;
            found = true;
            break;
        }
        try std.testing.expect(found);
    }
}

test "workspace open settings command routes to the palette target workspace" {
    // Registration + searchability: the entry exists under a stable id and
    // both "workspace" and "settings" query words match its title.
    var registered: ?Command = null;
    for (STATIC_COMMANDS) |command| {
        if (std.mem.eql(u8, command.id, "workspace.open_settings")) registered = command;
    }
    const command = registered.?;
    try std.testing.expectEqualStrings("Workspace: Open Settings", command.title);
    try std.testing.expect(fuzzyScore(command.title, "workspace settings") != null);
    try std.testing.expect(fuzzyScore(command.title, "open settings") != null);
    try std.testing.expect(!command.keeps_open);

    // Routing: activation targets the currently selected workspace and binds
    // the modal to its id. A stale history-scope left over from a previous
    // palette session must not override the selection.
    const allocator = std.testing.allocator;
    var state: runtime.AppState = undefined;
    state.allocator = allocator;
    state.lifecycle = .{};
    state.sidebar_context_menu_open = false;
    state.palette_modal_text_focus = .command_palette;
    state.modal_text_selection_anchor = null;
    state.command_controller = .{};
    state.command_controller.open = true;
    state.command_controller.scope_project = 1;
    state.composer_controller.composer = @TypeOf(state.composer_controller.composer).init();
    state.composer_controller.focused = false;
    state.project_controller.projects = .empty;
    state.project_controller.selected_index = 0;
    state.workspace_settings_project_id = null;
    state.workspace_settings_notice_storage = @splat(0);
    state.workspace_settings_scroll_y = 0.0;
    defer {
        if (state.workspace_settings_project_id) |id| allocator.free(id);
        for (state.project_controller.projects.items) |*entry| entry.deinit(allocator);
        state.project_controller.projects.deinit(allocator);
    }
    inline for (.{ .{ "workspace-a", "Alpha" }, .{ "workspace-b", "Beta" } }) |spec| {
        var entry = try native_state.Project.init(allocator, spec[0], spec[1], "/tmp/palette-workspace-settings", 0);
        state.project_controller.projects.append(allocator, entry) catch |err| {
            entry.deinit(allocator);
            return err;
        };
    }

    state.project_controller.selected_index = 1;
    try std.testing.expect(command.enabled(&state));
    try std.testing.expectEqual(RunStaticCommandResult.ran, runStaticCommandById(&state, "workspace.open_settings"));
    try std.testing.expect(!state.command_controller.open);
    try std.testing.expectEqualStrings("workspace-b", state.workspace_settings_project_id.?);

    // A stale scope surviving palette close never overrides the selection.
    allocator.free(state.workspace_settings_project_id.?);
    state.workspace_settings_project_id = null;
    state.command_controller.scope_project = 0;
    runOpenWorkspaceSettings(&state);
    try std.testing.expectEqualStrings("workspace-b", state.workspace_settings_project_id.?);

    // Without a valid selected workspace the command is unavailable and
    // safely no-ops.
    allocator.free(state.workspace_settings_project_id.?);
    state.workspace_settings_project_id = null;
    state.project_controller.selected_index = state.project_controller.projects.items.len;
    try std.testing.expect(!command.enabled(&state));
    runOpenWorkspaceSettings(&state);
    try std.testing.expect(state.workspace_settings_project_id == null);
}

test "shortcut-backed palette commands expose their keybind references" {
    const expected = [_]struct { id: []const u8, keybind: KeybindRef }{
        .{ .id = "workspace.close", .keybind = .workspace_close_current },
    };
    for (expected) |entry| {
        var found = false;
        for (STATIC_COMMANDS) |command| {
            if (!std.mem.eql(u8, command.id, entry.id)) continue;
            try std.testing.expectEqual(entry.keybind, command.keybind.?);
            found = true;
            break;
        }
        try std.testing.expect(found);
    }
}

test "pane traversal commands follow the configured scrolling axis" {
    try std.testing.expectEqual(runtime.WorkspacePaneDirection.left, paneTraversalDirection(.horizontal, true));
    try std.testing.expectEqual(runtime.WorkspacePaneDirection.right, paneTraversalDirection(.horizontal, false));
    try std.testing.expectEqual(runtime.WorkspacePaneDirection.up, paneTraversalDirection(.vertical, true));
    try std.testing.expectEqual(runtime.WorkspacePaneDirection.down, paneTraversalDirection(.vertical, false));
}

test "thread activation defaults to new pane and modifier selects replace" {
    try std.testing.expectEqual(ThreadOpenIntent.new_pane, threadOpenIntentForActivation(false));
    try std.testing.expectEqual(ThreadOpenIntent.replace, threadOpenIntentForActivation(true));
}

test "fuzzyScore ranks substring above subsequence and rejects non-matches" {
    const substring = fuzzyScore("Split Chat Right", "chat").?;
    const subsequence = fuzzyScore("Split Chat Right", "scr").?;
    try std.testing.expect(substring > subsequence);
    try std.testing.expect(fuzzyScore("Split Chat Right", "browser") == null);
    // Earlier substring hits outrank later ones.
    const early = fuzzyScore("chat about chat", "chat").?;
    const late = fuzzyScore("talk about chat", "chat").?;
    try std.testing.expect(early > late);
}

test "asciiIndexOfIgnoreCase finds case-insensitive needles" {
    try std.testing.expectEqual(@as(?usize, 6), asciiIndexOfIgnoreCase("Split CHAT Right", "chat"));
    try std.testing.expectEqual(@as(?usize, null), asciiIndexOfIgnoreCase("Split", "chat"));
    try std.testing.expectEqual(@as(?usize, 0), asciiIndexOfIgnoreCase("chat", "chat"));
}

test "formatKeybind renders modifiers and uppercases single letters" {
    var buf: [32]u8 = undefined;
    const rendered = keybinds.formatKeybindText(&buf, .{ .primary = true, .shift = true, .key = .p });
    try std.testing.expectEqualStrings("Ctrl+Shift+P", rendered);
    const plain = keybinds.formatKeybindText(&buf, .{ .alt = true, .key = .left });
    try std.testing.expectEqualStrings("Alt+Left", plain);
    try std.testing.expectEqualStrings("\u{21E7}\u{2318}P", keybinds.formatKeybindMac(&buf, .{ .primary = true, .shift = true, .key = .p }));
    try std.testing.expectEqualStrings("\u{2303}\u{2325}T", keybinds.formatKeybindMac(&buf, .{ .ctrl = true, .alt = true, .key = .t }));
}

test "indexed keybind hints follow loaded workspace bindings" {
    const bindings = [_]keybinds.Keybind{
        .{ .ctrl = true, .key = .@"1" },
        .{ .ctrl = true, .key = .@"0" },
    };
    var buf: [32]u8 = undefined;
    const mac = @import("builtin").os.tag == .macos;
    try std.testing.expectEqualStrings(if (mac) "\u{2303}1" else "Ctrl+1", indexedKeybindHint(&buf, &bindings, 0));
    try std.testing.expectEqualStrings(if (mac) "\u{2303}0" else "Ctrl+0", indexedKeybindHint(&buf, &bindings, 1));
    try std.testing.expectEqualStrings("", indexedKeybindHint(&buf, &bindings, 2));
}

test "matchMask marks substring hits, then in-order subsequences" {
    var mask: [16]bool = @splat(false);
    try std.testing.expect(matchMask("Split Chat Right", "chat", mask[0..16]));
    for (mask[0..16], 0..) |marked, i| try std.testing.expectEqual(i >= 6 and i < 10, marked);

    mask = @splat(false);
    try std.testing.expect(matchMask("Split Chat Right", "scr", mask[0..16]));
    try std.testing.expect(mask[0] and mask[6] and mask[11]);
    var marked_count: usize = 0;
    for (mask[0..16]) |marked| marked_count += @intFromBool(marked);
    try std.testing.expectEqual(@as(usize, 3), marked_count);

    // No match leaves the mask untouched, matching fuzzyScore's rejection.
    mask = @splat(false);
    try std.testing.expect(!matchMask("Split Chat Right", "browser", mask[0..16]));
    for (mask[0..16]) |marked| try std.testing.expect(!marked);
}

test "ranked results group into sections ordered by their best match" {
    result_count = 0;
    defer result_count = 0;
    const sorted = [_]Candidate{
        .{ .ref = .{ .command = 0 }, .score = 900 },
        .{ .ref = .{ .thread = .{ .project = 0, .thread = 0 } }, .score = 800 },
        .{ .ref = .{ .command = 1 }, .score = 700 },
        .{ .ref = .{ .closed_workspace = 0 }, .score = 600 },
    };
    appendGroupedCandidates(&sorted);
    try std.testing.expectEqual(@as(usize, 7), result_count);
    try std.testing.expectEqualStrings("Commands", results[0].ref.header);
    try std.testing.expectEqual(@as(usize, 0), results[1].ref.command);
    try std.testing.expectEqual(@as(usize, 1), results[2].ref.command);
    try std.testing.expectEqualStrings("Recent chats", results[3].ref.header);
    try std.testing.expect(results[4].ref == .thread);
    try std.testing.expectEqualStrings("Workspaces", results[5].ref.header);
    try std.testing.expect(results[6].ref == .closed_workspace);
    try std.testing.expectEqual(@as(?usize, 1), firstSelectable());
}

test "chat ages read as short relative phrases" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("just now", formatElapsed(&buf, 5));
    try std.testing.expectEqualStrings("12m ago", formatElapsed(&buf, 12 * 60));
    try std.testing.expectEqualStrings("3h ago", formatElapsed(&buf, 3 * 3600));
    try std.testing.expectEqualStrings("yesterday", formatElapsed(&buf, 30 * 3600));
    try std.testing.expectEqualStrings("4 days ago", formatElapsed(&buf, 4 * 86_400));
    try std.testing.expectEqualStrings("last week", formatElapsed(&buf, 9 * 86_400));
    try std.testing.expectEqualStrings("3 weeks ago", formatElapsed(&buf, 21 * 86_400));
    try std.testing.expectEqualStrings("over a year ago", formatElapsed(&buf, 400 * 86_400));
}

test "shortcut hints split macOS modifier symbols from the key" {
    const parts = splitShortcut("\u{21E7}\u{2318}P");
    try std.testing.expectEqual(@as(usize, 2), parts.mod_count);
    try std.testing.expectEqualStrings(LU_SHIFT, parts.mods[0]);
    try std.testing.expectEqualStrings(LU_COMMAND, parts.mods[1]);
    try std.testing.expectEqualStrings("P", parts.key);
    const plain = splitShortcut("Ctrl+Shift+T");
    try std.testing.expectEqual(@as(usize, 0), plain.mod_count);
    try std.testing.expectEqualStrings("Ctrl+Shift+T", plain.key);
}
