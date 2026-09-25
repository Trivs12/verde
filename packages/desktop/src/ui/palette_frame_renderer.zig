const std = @import("std");
const builtin = @import("builtin");
const palette = @import("palette");
const sdl = @import("zsdl3");

const app_config = @import("../app/config.zig");
const app_state = @import("../state.zig");
const browser_texture = @import("../browser/texture.zig");
const stb_image = @import("../media/stb_image.zig");
const font_family = @import("font_family.zig");
const text_measure = @import("text_measure.zig");
const theme = @import("theme.zig");

const log = std.log.scoped(.palette_frame_renderer);

// Base size for opened faces; sized copies are made per render size.
const BASE_FONT_POINT_SIZE: f32 = 16.0;

pub const Backend = enum {
    sdl_gpu,
};

/// Open TTF handles for the roles owned by the UI font family. Null roles
/// alias (`ui_medium` to `ui`, `code` to the terminal mono face).
const FamilyFonts = struct {
    ui: *palette.sdl.Font,
    ui_medium: ?*palette.sdl.Font,
    ui_bold: *palette.sdl.Font,
    prose: *palette.sdl.Font,
    prose_bold: *palette.sdl.Font,
    prose_italic: *palette.sdl.Font,
    prose_bold_italic: *palette.sdl.Font,
    code: ?*palette.sdl.Font,

    fn open(faces: *const font_family.Faces) !FamilyFonts {
        const ui = try font_family.openFace(faces.ui, BASE_FONT_POINT_SIZE);
        errdefer palette.sdl.ttfCloseFont(ui);
        const ui_medium = if (faces.ui_medium) |face| try font_family.openFace(face, BASE_FONT_POINT_SIZE) else null;
        errdefer if (ui_medium) |font| palette.sdl.ttfCloseFont(font);
        const ui_bold = try font_family.openFace(faces.ui_bold, BASE_FONT_POINT_SIZE);
        errdefer palette.sdl.ttfCloseFont(ui_bold);
        const prose = try font_family.openFace(faces.prose, BASE_FONT_POINT_SIZE);
        errdefer palette.sdl.ttfCloseFont(prose);
        const prose_bold = try font_family.openFace(faces.prose_bold, BASE_FONT_POINT_SIZE);
        errdefer palette.sdl.ttfCloseFont(prose_bold);
        const prose_italic = try font_family.openFace(faces.prose_italic, BASE_FONT_POINT_SIZE);
        errdefer palette.sdl.ttfCloseFont(prose_italic);
        const prose_bold_italic = try font_family.openFace(faces.prose_bold_italic, BASE_FONT_POINT_SIZE);
        errdefer palette.sdl.ttfCloseFont(prose_bold_italic);
        const code = if (faces.code) |face| try font_family.openFace(face, BASE_FONT_POINT_SIZE) else null;
        return .{
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

    fn close(self: FamilyFonts) void {
        if (self.code) |font| palette.sdl.ttfCloseFont(font);
        palette.sdl.ttfCloseFont(self.prose_bold_italic);
        palette.sdl.ttfCloseFont(self.prose_italic);
        palette.sdl.ttfCloseFont(self.prose_bold);
        palette.sdl.ttfCloseFont(self.prose);
        palette.sdl.ttfCloseFont(self.ui_bold);
        if (self.ui_medium) |font| palette.sdl.ttfCloseFont(font);
        palette.sdl.ttfCloseFont(self.ui);
    }
};

pub const Renderer = struct {
    requested_backend: Backend,
    active_backend: Backend,
    window: ?*sdl.Window = null,
    gpu: ?palette.renderer.Renderer = null,
    gpu_family_fonts: ?FamilyFonts = null,
    /// Configured family the loaded faces were resolved for (possibly via a
    /// fallback). The main loop reloads when the config diverges from it.
    font_family: app_config.UiFontFamily = .classic,
    effective_font_family: app_config.UiFontFamily = .classic,
    gpu_mono_font: ?*palette.sdl.Font = null,
    gpu_icon_font: ?*palette.sdl.Font = null,
    gpu_mono_symbols_font: ?*palette.sdl.Font = null,
    gpu_symbols_font: ?*palette.sdl.Font = null,
    gpu_symbols_alt_font: ?*palette.sdl.Font = null,
    gpu_math_font: ?*palette.sdl.Font = null,
    gpu_emoji_font: ?*palette.sdl.Font = null,
    gpu_ttf_initialized: bool = false,
    next_texture_id: u32 = 1,

    pub const InitOptions = struct {
        requested_backend: Backend,
        window: *sdl.Window,
        /// Chrome, prose and transcript-code faces for the UI font family.
        family_faces: *const font_family.Faces,
        /// Faces tried when `family_faces` cannot be opened (for example a
        /// macOS release without the expected SF named instances).
        fallback_family_faces: ?*const font_family.Faces = null,
        mono_font_path: [:0]const u8,
        icon_font_path: [:0]const u8,
        /// Optional coverage fallback for `mono`. Typically Verde's embedded
        /// JetBrains Mono Nerd, used when the user's chosen terminal mono has
        /// sparse Dingbats/Arrows coverage (CaskaydiaMono etc.). Null disables
        /// the fallback.
        mono_symbols_font_path: ?[:0]const u8 = null,
        /// Optional dedicated symbols face (Noto Sans Symbols 2) used as the
        /// final coverage stage for Dingbats / Misc Symbols glyphs that
        /// neither the primary mono nor mono_symbols carry. Null disables.
        symbols_font_path: ?[:0]const u8 = null,
        /// Optional secondary symbols face (Noto Sans Symbols, original) that
        /// complements `symbols` with numbered dingbats (❶❷..❿ / ➀➁..➓) and
        /// other blocks Symbols 2 omits. Null disables.
        symbols_alt_font_path: ?[:0]const u8 = null,
        /// Optional system math face for Mathematical Alphanumeric Symbols
        /// such as FX's stylized `𝒇` banner glyph. Null disables.
        math_font_path: ?[:0]const u8 = null,
        /// Optional monochrome emoji face (Noto Emoji) for emoji-styled
        /// Dingbats (✨/✅/❌/➕/❤) and 4-byte emoji (🔥/📦) that the
        /// symbols face excludes. Null disables.
        emoji_font_path: ?[:0]const u8 = null,
    };

    pub fn init(options: InitOptions) !Renderer {
        return try initSdlGpu(options);
    }

    fn initSdlGpu(options: InitOptions) !Renderer {
        var result: Renderer = .{
            .requested_backend = .sdl_gpu,
            .active_backend = .sdl_gpu,
            .window = options.window,
        };
        errdefer result.deinit(std.heap.smp_allocator);

        try palette.sdl.ttfInit();
        result.gpu_ttf_initialized = true;
        const faces = options.family_faces;
        var effective_family = faces.effective;
        result.gpu_family_fonts = FamilyFonts.open(faces) catch |err| blk: {
            const fallback = options.fallback_family_faces orelse return err;
            log.warn("failed to open {s} UI fonts ({s}); using {s}", .{ @tagName(faces.effective), @errorName(err), @tagName(fallback.effective) });
            effective_family = fallback.effective;
            break :blk try FamilyFonts.open(fallback);
        };
        result.font_family = faces.requested;
        result.effective_font_family = effective_family;
        result.gpu_mono_font = try palette.sdl.ttfOpenFont(options.mono_font_path, BASE_FONT_POINT_SIZE);
        result.gpu_icon_font = try palette.sdl.ttfOpenFont(options.icon_font_path, 16.0);
        if (options.mono_symbols_font_path) |path| {
            result.gpu_mono_symbols_font = palette.sdl.ttfOpenFont(path, 16.0) catch null;
        }
        if (options.symbols_font_path) |path| {
            result.gpu_symbols_font = palette.sdl.ttfOpenFont(path, 16.0) catch null;
        }
        if (options.symbols_alt_font_path) |path| {
            result.gpu_symbols_alt_font = palette.sdl.ttfOpenFont(path, 16.0) catch null;
        }
        if (options.math_font_path) |path| {
            result.gpu_math_font = palette.sdl.ttfOpenFont(path, 16.0) catch null;
        }
        if (options.emoji_font_path) |path| {
            result.gpu_emoji_font = palette.sdl.ttfOpenFont(path, 16.0) catch null;
        }
        result.gpu = try palette.renderer.Renderer.init(.{
            .debug_mode = builtin.mode == .Debug,
            .shader_formats = palette.renderer.ShaderFormat.defaultForTarget(builtin.os.tag),
            .shader_packages = palette.renderer.ShaderSource.packagesForTarget(builtin.os.tag),
        });
        try result.gpu.?.configureGpuTextWithAllRoleFonts(result.gpuRoleFonts(result.gpu_family_fonts.?));
        result.configureTextMeasureFonts();
        try result.gpu.?.claimWindow(@ptrCast(options.window));
        return result;
    }

    /// Swaps the UI font family live: opens `faces`, hands them to the GPU
    /// text path (which drops every shaped-text, sized-font and atlas cache),
    /// then closes the previous faces and bumps the text-measure generation
    /// so width/height memos keyed on it re-measure. On error the previous
    /// faces stay active.
    pub fn applyFontFamily(self: *Renderer, faces: *const font_family.Faces) !void {
        if (self.active_backend != .sdl_gpu) return error.SdlGpuUnavailable;
        const next = try FamilyFonts.open(faces);
        errdefer next.close();
        try self.gpu.?.replaceGpuTextRoleFonts(self.gpuRoleFonts(next));
        const previous = self.gpu_family_fonts;
        self.gpu_family_fonts = next;
        self.configureTextMeasureFonts();
        self.configureTextMeasureRenderer();
        if (previous) |fonts| fonts.close();
        self.font_family = faces.requested;
        self.effective_font_family = faces.effective;
    }

    fn gpuRoleFonts(self: *const Renderer, family: FamilyFonts) palette.renderer.Renderer.RoleFonts {
        return .{
            .ui = family.ui,
            .ui_medium = family.ui_medium,
            .ui_bold = family.ui_bold,
            .prose = family.prose,
            .prose_bold = family.prose_bold,
            .prose_italic = family.prose_italic,
            .prose_bold_italic = family.prose_bold_italic,
            .mono = self.gpu_mono_font,
            .code = family.code,
            .icon = self.gpu_icon_font,
            .mono_symbols = self.gpu_mono_symbols_font,
            .symbols = self.gpu_symbols_font,
            .symbols_alt = self.gpu_symbols_alt_font,
            .math = self.gpu_math_font,
            .emoji = self.gpu_emoji_font,
        };
    }

    fn configureTextMeasureFonts(self: *const Renderer) void {
        const family = self.gpu_family_fonts.?;
        text_measure.configure(.{
            .ui = family.ui,
            .ui_medium = family.ui_medium orelse family.ui,
            .ui_bold = family.ui_bold,
            .prose = family.prose,
            .prose_bold = family.prose_bold,
            .prose_italic = family.prose_italic,
            .prose_bold_italic = family.prose_bold_italic,
            .mono = self.gpu_mono_font.?,
            .code = family.code orelse self.gpu_mono_font.?,
            .icon = self.gpu_icon_font.?,
        });
    }

    pub fn configureTextMeasureRenderer(self: *Renderer) void {
        if (self.active_backend == .sdl_gpu) {
            if (self.gpu) |*gpu| text_measure.configureRenderer(gpu);
        }
    }

    pub fn deinit(self: *Renderer, allocator: std.mem.Allocator) void {
        _ = allocator;
        if (self.active_backend == .sdl_gpu) {
            // SDL_GPU teardown can block indefinitely on some Linux/NVIDIA/Wayland
            // close paths. The process is exiting, so prefer prompt shutdown and let
            // the OS/driver reclaim GPU resources.
            self.* = undefined;
            return;
        }
        text_measure.clear();
        if (self.gpu) |*gpu| {
            if (self.window) |window| gpu.releaseWindow(@ptrCast(window));
            gpu.deinit();
        }
        if (self.gpu_emoji_font) |font| palette.sdl.ttfCloseFont(font);
        if (self.gpu_math_font) |font| palette.sdl.ttfCloseFont(font);
        if (self.gpu_symbols_alt_font) |font| palette.sdl.ttfCloseFont(font);
        if (self.gpu_symbols_font) |font| palette.sdl.ttfCloseFont(font);
        if (self.gpu_mono_symbols_font) |font| palette.sdl.ttfCloseFont(font);
        if (self.gpu_icon_font) |font| palette.sdl.ttfCloseFont(font);
        if (self.gpu_mono_font) |font| palette.sdl.ttfCloseFont(font);
        if (self.gpu_family_fonts) |fonts| fonts.close();
        if (self.gpu_ttf_initialized) palette.sdl.ttfQuit();
        self.* = undefined;
    }

    pub fn usingFallback(self: *const Renderer) bool {
        return self.requested_backend != self.active_backend;
    }

    pub fn activeBackend(self: *const Renderer) Backend {
        return self.active_backend;
    }

    pub fn uploadLoadedTextureCallback(context: ?*anyopaque, loaded: stb_image.LoadedImage) ?app_state.CachedImageTexture {
        const renderer: *Renderer = @ptrCast(@alignCast(context orelse return null));
        return renderer.uploadLoadedTexture(loaded);
    }

    pub fn uploadLoadedTexture(self: *Renderer, loaded: stb_image.LoadedImage) ?app_state.CachedImageTexture {
        if (self.active_backend != .sdl_gpu) return null;
        const id = self.nextTextureId();

        const width: u32 = @intCast(loaded.width);
        const height: u32 = @intCast(loaded.height);
        self.gpu.?.uploadTexture(id, width, height, .rgba8, .image, loaded.pixels[0 .. @as(usize, width) * @as(usize, height) * 4]) catch return null;
        return .{
            .texture_id = id,
            .width = loaded.width,
            .height = loaded.height,
            .valid = true,
            .backend = .external,
        };
    }

    pub fn uploadPaneTextureCallback(context: ?*anyopaque, pane_texture: *browser_texture.PaneTexture, width: u32, height: u32, format: browser_texture.PixelFormat, pixels: []const u8) !void {
        const renderer: *Renderer = @ptrCast(@alignCast(context orelse return error.SdlGpuTextureUnavailable));
        if (renderer.active_backend != .sdl_gpu) return error.SdlGpuTextureUnavailable;
        const texture_id = if (pane_texture.texture_id == 0) renderer.nextTextureId() else pane_texture.texture_id;
        const gpu_format: palette.renderer.Renderer.TextureFormat = switch (format) {
            .rgba => .rgba8,
            .bgra => .bgra8,
        };
        try renderer.gpu.?.uploadTexture(texture_id, width, height, gpu_format, .browser, pixels);
        pane_texture.update(texture_id, width, height, true);
    }

    pub fn releasePaneTextureCallback(context: ?*anyopaque, texture_id: c_uint) void {
        const renderer: *Renderer = @ptrCast(@alignCast(context orelse return));
        if (renderer.active_backend != .sdl_gpu) return;
        renderer.gpu.?.releaseTexture(texture_id);
    }

    pub fn releaseTextureCallback(context: ?*anyopaque, texture_id: c_uint) void {
        releasePaneTextureCallback(context, texture_id);
    }

    fn nextTextureId(self: *Renderer) u32 {
        const id = self.next_texture_id;
        self.next_texture_id +%= 1;
        if (self.next_texture_id == 0) self.next_texture_id = 1;
        return id;
    }

    pub fn renderBatch(
        self: *Renderer,
        allocator: std.mem.Allocator,
        batch: *const palette.RenderBatch,
        framebuffer_width: f32,
        framebuffer_height: f32,
    ) !palette.renderer.WindowRenderOutcome {
        _ = framebuffer_width;
        _ = framebuffer_height;
        return try self.renderSdlGpuBatch(allocator, batch);
    }

    fn renderSdlGpuBatch(self: *Renderer, allocator: std.mem.Allocator, batch: *const palette.RenderBatch) !palette.renderer.WindowRenderOutcome {
        const window = self.window orelse return error.SdlGpuWindowMissing;
        return try self.gpu.?.renderWindow(
            allocator,
            @ptrCast(window),
            batch,
            .{
                .r = theme.background()[0],
                .g = theme.background()[1],
                .b = theme.background()[2],
                .a = theme.background()[3],
            },
        );
    }

    pub fn lastSdlGpuFrameStats(self: *const Renderer) ?palette.renderer.FrameStats {
        if (self.active_backend != .sdl_gpu) return null;
        return self.gpu.?.lastFrameStats();
    }
};
