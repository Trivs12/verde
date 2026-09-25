//! UI font-family faces: which TTF backs each chrome/prose/code role for a
//! `ui.font_family` choice, where the file lives at runtime, and how to open
//! named instances of the variable macOS system fonts.

const std = @import("std");
const builtin = @import("builtin");
const palette = @import("palette");

const app_config = @import("../app/config.zig");

const log = std.log.scoped(.font_family);

pub const UiFontFamily = app_config.UiFontFamily;

/// A font file embedded in the binary. Materialized next to the dev tree when
/// run from a checkout, otherwise written into the preferences `fonts/` dir.
pub const Bundled = struct {
    file_name: []const u8,
    bytes: []const u8,
};

pub const CAL_SANS = bundled("CalSans-Regular.ttf");
pub const NOTO_SANS_REGULAR = bundled("NotoSans-Regular.ttf");
pub const NOTO_SANS_BOLD = bundled("NotoSans-Bold.ttf");
pub const NOTO_SANS_ITALIC = bundled("NotoSans-Italic.ttf");
pub const NOTO_SANS_BOLD_ITALIC = bundled("NotoSans-BoldItalic.ttf");

/// Role-to-file table for one bundled family. `null` roles alias: `ui_medium`
/// to `ui`, `code` to the terminal mono face.
const BundledSpec = struct {
    ui: Bundled,
    ui_medium: ?Bundled,
    ui_bold: Bundled,
    prose: Bundled,
    prose_bold: Bundled,
    prose_italic: Bundled,
    prose_bold_italic: Bundled,
    code: ?Bundled,
};

// Classic is exactly the pre-family face set. Its chrome emphasis stays on
// Cal Sans (see the composer's `bold_font_role`), so `ui_medium` aliases `ui`.
const CLASSIC_SPEC: BundledSpec = .{
    .ui = CAL_SANS,
    .ui_medium = null,
    .ui_bold = NOTO_SANS_BOLD,
    .prose = NOTO_SANS_REGULAR,
    .prose_bold = NOTO_SANS_BOLD,
    .prose_italic = NOTO_SANS_ITALIC,
    .prose_bold_italic = NOTO_SANS_BOLD_ITALIC,
    .code = null,
};

// Single-family sets use one face for chrome and prose. Chrome emphasis uses
// Medium / SemiBold; Bold is reserved for markdown strong text.
const INTER_SPEC: BundledSpec = .{
    .ui = bundled("Inter-Regular.ttf"),
    .ui_medium = bundled("Inter-Medium.ttf"),
    .ui_bold = bundled("Inter-SemiBold.ttf"),
    .prose = bundled("Inter-Regular.ttf"),
    .prose_bold = bundled("Inter-Bold.ttf"),
    .prose_italic = bundled("Inter-Italic.ttf"),
    .prose_bold_italic = bundled("Inter-BoldItalic.ttf"),
    // Inter pairs with JetBrains Mono, which the terminal mono already is.
    .code = null,
};

const GEIST_SPEC: BundledSpec = .{
    .ui = bundled("Geist-Regular.ttf"),
    .ui_medium = bundled("Geist-Medium.ttf"),
    .ui_bold = bundled("Geist-SemiBold.ttf"),
    .prose = bundled("Geist-Regular.ttf"),
    .prose_bold = bundled("Geist-Bold.ttf"),
    .prose_italic = bundled("Geist-Italic.ttf"),
    .prose_bold_italic = bundled("Geist-BoldItalic.ttf"),
    .code = bundled("GeistMono-Regular.ttf"),
};

const IBM_PLEX_SPEC: BundledSpec = .{
    .ui = bundled("IBMPlexSans-Regular.ttf"),
    .ui_medium = bundled("IBMPlexSans-Medium.ttf"),
    .ui_bold = bundled("IBMPlexSans-SemiBold.ttf"),
    .prose = bundled("IBMPlexSans-Regular.ttf"),
    .prose_bold = bundled("IBMPlexSans-Bold.ttf"),
    .prose_italic = bundled("IBMPlexSans-Italic.ttf"),
    .prose_bold_italic = bundled("IBMPlexSans-BoldItalic.ttf"),
    .code = bundled("IBMPlexMono-Regular.ttf"),
};

// SF Pro / SF Mono ship as variable fonts; weights are FreeType named
// instances selected by style name (indices differ across macOS releases).
const SF_TEXT_PATH = "/System/Library/Fonts/SFNS.ttf";
const SF_ITALIC_PATH = "/System/Library/Fonts/SFNSItalic.ttf";
const SF_MONO_PATH = "/System/Library/Fonts/SFNSMono.ttf";
/// Upper bound on named instances probed per variable font (SFNS has ~20).
const MAX_NAMED_INSTANCES: i64 = 64;

/// One role's face: a font file plus, for variable fonts, the named instance.
pub const Face = struct {
    path: [:0]u8,
    /// Named-instance style (for example "Semibold"); null opens face 0.
    style_name: ?[]const u8 = null,

    fn deinit(self: Face, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

/// Resolved faces for every family-owned role. Owns its paths.
pub const Faces = struct {
    /// The configured family, kept even when `effective` fell back.
    requested: UiFontFamily,
    effective: UiFontFamily,
    ui: Face,
    ui_medium: ?Face,
    ui_bold: Face,
    prose: Face,
    prose_bold: Face,
    prose_italic: Face,
    prose_bold_italic: Face,
    code: ?Face,

    pub fn deinit(self: *Faces, allocator: std.mem.Allocator) void {
        self.ui.deinit(allocator);
        if (self.ui_medium) |face| face.deinit(allocator);
        self.ui_bold.deinit(allocator);
        self.prose.deinit(allocator);
        self.prose_bold.deinit(allocator);
        self.prose_italic.deinit(allocator);
        self.prose_bold_italic.deinit(allocator);
        if (self.code) |face| face.deinit(allocator);
        self.* = undefined;
    }
};

/// Resolves the faces for `requested`. `.system` falls back to Inter when the
/// SF files are absent (non-macOS or a stripped system).
pub fn resolve(allocator: std.mem.Allocator, pref_path: []const u8, requested: UiFontFamily) !Faces {
    const effective = effectiveFamily(requested, requested == .system and systemFontsPresent());
    if (requested == .system and effective != .system) {
        log.info("SF system fonts unavailable; ui.font_family=system uses Inter", .{});
    }
    return switch (effective) {
        .system => try resolveSystem(allocator, requested),
        else => try resolveBundled(allocator, pref_path, requested, effective, bundledSpec(effective)),
    };
}

/// Family actually loaded for `requested` given whether the SF files exist.
pub fn effectiveFamily(requested: UiFontFamily, system_fonts_present: bool) UiFontFamily {
    if (requested == .system and !system_fonts_present) return .inter;
    return requested;
}

/// Opens `face` at `point_size`, selecting its named instance when set.
pub fn openFace(face: Face, point_size: f32) !*palette.sdl.Font {
    const style = face.style_name orelse return try palette.sdl.ttfOpenFont(face.path, point_size);
    // Face 0 is the font's default instance; check it before probing.
    const default_face = try palette.sdl.ttfOpenFont(face.path, point_size);
    if (std.ascii.eqlIgnoreCase(palette.sdl.ttfFontStyleName(default_face), style)) return default_face;
    palette.sdl.ttfCloseFont(default_face);
    var instance: i64 = 1;
    while (instance <= MAX_NAMED_INSTANCES) : (instance += 1) {
        const candidate = palette.sdl.ttfOpenFontFace(face.path, point_size, instance << 16) catch break;
        if (std.ascii.eqlIgnoreCase(palette.sdl.ttfFontStyleName(candidate), style)) return candidate;
        palette.sdl.ttfCloseFont(candidate);
    }
    log.warn("named instance \"{s}\" not found in {s}", .{ style, face.path });
    return error.FontStyleNotFound;
}

/// Path of a bundled font: the checkout copy when running from the repo,
/// otherwise the embedded bytes written into `<pref_path>/fonts/`.
pub fn bundledFontPath(allocator: std.mem.Allocator, pref_path: []const u8, font: Bundled) ![:0]u8 {
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const dev_roots = [_][]const u8{ "src/assets/fonts", "packages/desktop/src/assets/fonts" };
    for (dev_roots) |root| {
        const candidate = try std.fs.path.joinZ(allocator, &.{ root, font.file_name });
        std.Io.Dir.cwd().access(io, candidate, .{}) catch {
            allocator.free(candidate);
            continue;
        };
        return candidate;
    }
    return try installBundledFont(allocator, pref_path, font.file_name, font.bytes);
}

/// Writes embedded font bytes to `<pref_path>/fonts/<file_name>`.
pub fn installBundledFont(
    allocator: std.mem.Allocator,
    pref_path: []const u8,
    file_name: []const u8,
    bytes: []const u8,
) ![:0]u8 {
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    var pref_dir = try std.Io.Dir.openDirAbsolute(threaded.io(), pref_path, .{});
    defer pref_dir.close(threaded.io());
    try pref_dir.createDirPath(threaded.io(), "fonts");

    const path = try std.fs.path.join(allocator, &.{ pref_path, "fonts", file_name });
    defer allocator.free(path);

    var file = try std.Io.Dir.createFileAbsolute(threaded.io(), path, .{ .truncate = true });
    defer file.close(threaded.io());
    try file.writeStreamingAll(threaded.io(), bytes);

    return try allocator.dupeZ(u8, path);
}

fn bundled(comptime file_name: []const u8) Bundled {
    return .{ .file_name = file_name, .bytes = @embedFile("../assets/fonts/" ++ file_name) };
}

fn bundledSpec(family: UiFontFamily) BundledSpec {
    return switch (family) {
        .classic => CLASSIC_SPEC,
        .inter, .system => INTER_SPEC,
        .geist => GEIST_SPEC,
        .ibm_plex => IBM_PLEX_SPEC,
    };
}

fn resolveBundled(
    allocator: std.mem.Allocator,
    pref_path: []const u8,
    requested: UiFontFamily,
    effective: UiFontFamily,
    spec: BundledSpec,
) !Faces {
    const ui = try bundledFace(allocator, pref_path, spec.ui);
    errdefer ui.deinit(allocator);
    const ui_medium = if (spec.ui_medium) |font| try bundledFace(allocator, pref_path, font) else null;
    errdefer if (ui_medium) |face| face.deinit(allocator);
    const ui_bold = try bundledFace(allocator, pref_path, spec.ui_bold);
    errdefer ui_bold.deinit(allocator);
    const prose = try bundledFace(allocator, pref_path, spec.prose);
    errdefer prose.deinit(allocator);
    const prose_bold = try bundledFace(allocator, pref_path, spec.prose_bold);
    errdefer prose_bold.deinit(allocator);
    const prose_italic = try bundledFace(allocator, pref_path, spec.prose_italic);
    errdefer prose_italic.deinit(allocator);
    const prose_bold_italic = try bundledFace(allocator, pref_path, spec.prose_bold_italic);
    errdefer prose_bold_italic.deinit(allocator);
    const code = if (spec.code) |font| try bundledFace(allocator, pref_path, font) else null;
    return .{
        .requested = requested,
        .effective = effective,
        .ui = ui,
        .ui_medium = ui_medium,
        .ui_bold = ui_bold,
        .prose = prose,
        .prose_bold = prose_bold,
        .prose_italic = prose_italic,
        .prose_bold_italic = prose_bold_italic,
        .code = code,
    };
}

fn bundledFace(allocator: std.mem.Allocator, pref_path: []const u8, font: Bundled) !Face {
    return .{ .path = try bundledFontPath(allocator, pref_path, font) };
}

fn resolveSystem(allocator: std.mem.Allocator, requested: UiFontFamily) !Faces {
    const ui = try systemFace(allocator, SF_TEXT_PATH, "Regular");
    errdefer ui.deinit(allocator);
    const ui_medium = try systemFace(allocator, SF_TEXT_PATH, "Medium");
    errdefer ui_medium.deinit(allocator);
    const ui_bold = try systemFace(allocator, SF_TEXT_PATH, "Semibold");
    errdefer ui_bold.deinit(allocator);
    const prose = try systemFace(allocator, SF_TEXT_PATH, "Regular");
    errdefer prose.deinit(allocator);
    const prose_bold = try systemFace(allocator, SF_TEXT_PATH, "Bold");
    errdefer prose_bold.deinit(allocator);
    const prose_italic = try systemFace(allocator, SF_ITALIC_PATH, "Regular Italic");
    errdefer prose_italic.deinit(allocator);
    const prose_bold_italic = try systemFace(allocator, SF_ITALIC_PATH, "Bold Italic");
    errdefer prose_bold_italic.deinit(allocator);
    // SFNSMono's default instance is Light; select Regular explicitly.
    const code = try systemFace(allocator, SF_MONO_PATH, "Regular");
    return .{
        .requested = requested,
        .effective = .system,
        .ui = ui,
        .ui_medium = ui_medium,
        .ui_bold = ui_bold,
        .prose = prose,
        .prose_bold = prose_bold,
        .prose_italic = prose_italic,
        .prose_bold_italic = prose_bold_italic,
        .code = code,
    };
}

fn systemFace(allocator: std.mem.Allocator, path: []const u8, style_name: []const u8) !Face {
    return .{ .path = try allocator.dupeZ(u8, path), .style_name = style_name };
}

fn systemFontsPresent() bool {
    if (builtin.os.tag != .macos) return false;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    for ([_][]const u8{ SF_TEXT_PATH, SF_ITALIC_PATH, SF_MONO_PATH }) |path| {
        std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    }
    return true;
}

test "classic family keeps the pre-family face files" {
    const spec = bundledSpec(.classic);
    try std.testing.expectEqualStrings("CalSans-Regular.ttf", spec.ui.file_name);
    try std.testing.expect(spec.ui_medium == null);
    try std.testing.expectEqualStrings("NotoSans-Bold.ttf", spec.ui_bold.file_name);
    try std.testing.expectEqualStrings("NotoSans-Regular.ttf", spec.prose.file_name);
    try std.testing.expectEqualStrings("NotoSans-Bold.ttf", spec.prose_bold.file_name);
    try std.testing.expectEqualStrings("NotoSans-Italic.ttf", spec.prose_italic.file_name);
    try std.testing.expectEqualStrings("NotoSans-BoldItalic.ttf", spec.prose_bold_italic.file_name);
    try std.testing.expect(spec.code == null);
}

test "bundled families embed every face and emphasize chrome below bold" {
    for ([_]UiFontFamily{ .inter, .geist, .ibm_plex }) |family| {
        const spec = bundledSpec(family);
        const faces = [_]?Bundled{ spec.ui, spec.ui_medium, spec.ui_bold, spec.prose, spec.prose_bold, spec.prose_italic, spec.prose_bold_italic, spec.code };
        for (faces) |maybe_face| {
            const face = maybe_face orelse continue;
            try std.testing.expect(face.bytes.len > 1024);
            try std.testing.expect(std.mem.endsWith(u8, face.file_name, ".ttf"));
        }
        try std.testing.expect(std.mem.endsWith(u8, spec.ui_medium.?.file_name, "-Medium.ttf"));
        try std.testing.expect(std.mem.endsWith(u8, spec.ui_bold.file_name, "-SemiBold.ttf"));
        try std.testing.expect(std.mem.endsWith(u8, spec.prose_bold.file_name, "-Bold.ttf"));
    }
    try std.testing.expect(bundledSpec(.inter).code == null);
    try std.testing.expectEqualStrings("GeistMono-Regular.ttf", bundledSpec(.geist).code.?.file_name);
    try std.testing.expectEqualStrings("IBMPlexMono-Regular.ttf", bundledSpec(.ibm_plex).code.?.file_name);
}

test "system family falls back to Inter without SF fonts" {
    try std.testing.expectEqual(UiFontFamily.system, effectiveFamily(.system, true));
    try std.testing.expectEqual(UiFontFamily.inter, effectiveFamily(.system, false));
    for ([_]UiFontFamily{ .classic, .inter, .geist, .ibm_plex }) |family| {
        try std.testing.expectEqual(family, effectiveFamily(family, false));
    }
}

test "bundled font path writes embedded bytes into the preferences fonts dir" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const pref_path = path_buf[0..path_len];
    const font: Bundled = .{ .file_name = "VerdeTestFace-Regular.ttf", .bytes = "not-a-real-font" };
    const path = try bundledFontPath(std.testing.allocator, pref_path, font);
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, "fonts" ++ std.fs.path.sep_str ++ "VerdeTestFace-Regular.ttf"));
    const written = try tmp.dir.readFileAlloc(std.testing.io, "fonts/VerdeTestFace-Regular.ttf", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(written);
    try std.testing.expectEqualStrings(font.bytes, written);
}
