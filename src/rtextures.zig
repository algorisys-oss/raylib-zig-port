//! rtextures - Basic functions to load and draw textures
//!
//! Zig port of raylib's `rtextures.c`. Every public raylib texture/image function is
//! exported with its exact C name, byte-compatible signature, and C calling convention,
//! so the rest of raylib links against it unchanged. Floating-point operation order
//! matches the C source exactly to keep pixel output bit-identical, and libm is called
//! rather than reimplemented. Pixel buffers handed to C (Image.data, LoadImageColors,
//! LoadImagePalette...) live on the C heap through `cmem`; scratch buffers use
//! `std.heap.c_allocator`. Half floats and ExportImageAsCode's text are built by the
//! std-only `rtextures_encode.zig`.
//!
//! This build mirrors raylib's default `config.h`: enabled formats are PNG, BMP, GIF,
//! QOI, DDS; image export (PNG/QOI/BMP) and procedural image generation are enabled.
//! PEP (`SUPPORT_FILEFORMAT_PEP`, new in raylib 6.2) is disabled by default and not ported.
//! The third-party single-file libraries (stb_image, stb_image_write, stb_image_resize2,
//! qoi, stb_perlin, rltexgpu) are instantiated in the C shim `src/c/rtextures_stb_impl.c`
//! and only `extern`-declared and called here.

const std = @import("std");
const Allocator = std.mem.Allocator;
const c_allocator = std.heap.c_allocator;
const cmem = @import("cmem.zig");
const encode = @import("rtextures_encode.zig");

//----------------------------------------------------------------------------------
// libm, called rather than reimplemented so results stay bit-identical to C
// (CLAUDE.md, "Float bit-exactness"). fabsf/floorf/ceilf/sqrtf/round are the
// @abs/@floor/@ceil/@sqrt/@round builtins, which are exact.
//----------------------------------------------------------------------------------
extern fn sinf(f32) f32;
extern fn cosf(f32) f32;
extern fn powf(f32, f32) f32;
extern fn logf(f32) f32;
extern fn fminf(f32, f32) f32;
extern fn fmaxf(f32, f32) f32;
extern fn fmodf(f32, f32) f32;
extern fn hypotf(f32, f32) f32;
// Double precision, where the C source calls the non-f variants
extern fn fmin(f64, f64) f64;
extern fn fmax(f64, f64) f64;
extern fn hypot(f64, f64) f64;

const NAN: f32 = std.math.nan(f32);

//----------------------------------------------------------------------------------
// Cross-module raylib C symbols (still C in this build) - extern declared and called.
//----------------------------------------------------------------------------------
extern fn TraceLog(logLevel: c_int, text: [*c]const u8, ...) void;
extern fn LoadFileData(fileName: [*c]const u8, dataSize: *c_int) ?[*]u8;
extern fn SaveFileData(fileName: [*c]const u8, data: ?*const anyopaque, dataSize: c_int) bool;
extern fn UnloadFileData(data: ?[*]u8) void;
extern fn SaveFileText(fileName: [*c]const u8, text: [*:0]const u8) bool;
extern fn GetFileExtension(fileName: [*c]const u8) ?[*:0]const u8;
extern fn GetFileNameWithoutExt(filePath: [*c]const u8) [*:0]const u8;
extern fn IsFileExtension(fileName: [*c]const u8, ext: [*c]const u8) bool;
extern fn GetRandomValue(min: c_int, max: c_int) c_int;
extern fn GetRenderWidth() c_int;
extern fn GetRenderHeight() c_int;

// [rtext] module functions required by image text drawing
extern fn LoadFontDefault() void;
extern fn GetFontDefault() Font;
extern fn GetGlyphIndex(font: Font, codepoint: c_int) c_int;
extern fn MeasureTextEx(font: Font, text: [*c]const u8, fontSize: f32, spacing: f32) Vector2;
extern fn GetCodepointNext(text: [*:0]const u8, codepointSize: *c_int) c_int;

//----------------------------------------------------------------------------------
// rlgl functions, provided by other translation units in the build.
//----------------------------------------------------------------------------------
extern fn rlLoadTexture(data: ?*const anyopaque, width: c_int, height: c_int, format: c_int, mipmapCount: c_int) c_uint;
extern fn rlLoadTextureDepth(width: c_int, height: c_int, useRenderBuffer: bool) c_uint;
extern fn rlLoadTextureCubemap(data: ?*const anyopaque, size: c_int, format: c_int, mipmapCount: c_int) c_uint;
extern fn rlUpdateTexture(id: c_uint, offsetX: c_int, offsetY: c_int, width: c_int, height: c_int, format: c_int, data: ?*const anyopaque) void;
extern fn rlUnloadTexture(id: c_uint) void;
extern fn rlGetPixelFormatName(format: c_uint) [*:0]const u8;
extern fn rlTextureParameters(id: c_uint, param: c_int, value: c_int) void;
extern fn rlGenTextureMipmaps(id: c_uint, width: c_int, height: c_int, format: c_int, mipmaps: *c_int) void;
extern fn rlReadTexturePixels(id: c_uint, width: c_int, height: c_int, format: c_int) ?*anyopaque;
extern fn rlReadScreenPixels(width: c_int, height: c_int) ?[*]u8;
extern fn rlLoadFramebuffer() c_uint;
extern fn rlFramebufferAttach(id: c_uint, texId: c_uint, attachType: c_int, texType: c_int, mipLevel: c_int) void;
extern fn rlFramebufferComplete(id: c_uint) bool;
extern fn rlUnloadFramebuffer(id: c_uint) void;
extern fn rlEnableFramebuffer(id: c_uint) void;
extern fn rlDisableFramebuffer() void;
extern fn rlBegin(mode: c_int) void;
extern fn rlEnd() void;
extern fn rlColor4ub(r: u8, g: u8, b: u8, a: u8) void;
extern fn rlVertex2f(x: f32, y: f32) void;
extern fn rlTexCoord2f(x: f32, y: f32) void;
extern fn rlNormal3f(x: f32, y: f32, z: f32) void;
extern fn rlSetTexture(id: c_uint) void;
extern fn rlPushMatrix() void;
extern fn rlPopMatrix() void;
extern fn rlTranslatef(x: f32, y: f32, z: f32) void;
extern fn rlRotatef(angle: f32, x: f32, y: f32, z: f32) void;

//----------------------------------------------------------------------------------
// Third-party single-file-lib functions (provided by src/c/rtextures_stb_impl.c).
//----------------------------------------------------------------------------------
extern fn stbi_load_from_memory(buffer: [*]const u8, len: c_int, x: *c_int, y: *c_int, channels_in_file: *c_int, desired_channels: c_int) ?*anyopaque;
extern fn stbi_load_gif_from_memory(buffer: [*]const u8, len: c_int, delays: *?[*]c_int, x: *c_int, y: *c_int, z: *c_int, comp: *c_int, req_comp: c_int) ?*anyopaque;
extern fn stbi_write_png_to_mem(pixels: ?[*]const u8, stride_bytes: c_int, x: c_int, y: c_int, n: c_int, out_len: *c_int) ?[*]u8;
extern fn stbi_write_bmp(filename: [*c]const u8, w: c_int, h: c_int, comp: c_int, data: ?*const anyopaque) c_int;
extern fn stbir_resize_uint8_linear(input_pixels: ?[*]const u8, input_w: c_int, input_h: c_int, input_stride_in_bytes: c_int, output_pixels: [*]u8, output_w: c_int, output_h: c_int, output_stride_in_bytes: c_int, pixel_layout: c_int) ?[*]u8;
extern fn qoi_decode(data: *const anyopaque, size: c_int, desc: *qoi_desc, channels: c_int) ?*anyopaque;
extern fn qoi_write(filename: [*c]const u8, data: ?*const anyopaque, desc: *const qoi_desc) c_int;
extern fn stb_perlin_fbm_noise3(x: f32, y: f32, z: f32, lacunarity: f32, gain: f32, octaves: c_int) f32;
extern fn rl_load_dds_from_memory(file_data: [*]const u8, file_size: c_uint, width: *c_int, height: *c_int, format: *c_int, mips: *c_int) ?*anyopaque;

const qoi_desc = extern struct {
    width: c_uint = 0,
    height: c_uint = 0,
    channels: u8 = 0,
    colorspace: u8 = 0,
};

//----------------------------------------------------------------------------------
// Defines and Macros
//----------------------------------------------------------------------------------
const PI: f32 = 3.14159265358979323846;
const DEG2RAD: f32 = PI / 180.0;

const PIXELFORMAT_UNCOMPRESSED_R5G5B5A1_ALPHA_THRESHOLD: c_int = 50;
const GAUSSIAN_BLUR_ITERATIONS: c_int = 4;
const TEXT_BYTES_PER_LINE: c_int = 20;

// PixelFormat values (raylib.h)
const PIXELFORMAT_UNCOMPRESSED_GRAYSCALE: c_int = 1;
const PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA: c_int = 2;
const PIXELFORMAT_UNCOMPRESSED_R5G6B5: c_int = 3;
const PIXELFORMAT_UNCOMPRESSED_R8G8B8: c_int = 4;
const PIXELFORMAT_UNCOMPRESSED_R5G5B5A1: c_int = 5;
const PIXELFORMAT_UNCOMPRESSED_R4G4B4A4: c_int = 6;
const PIXELFORMAT_UNCOMPRESSED_R8G8B8A8: c_int = 7;
const PIXELFORMAT_UNCOMPRESSED_R32: c_int = 8;
const PIXELFORMAT_UNCOMPRESSED_R32G32B32: c_int = 9;
const PIXELFORMAT_UNCOMPRESSED_R32G32B32A32: c_int = 10;
const PIXELFORMAT_UNCOMPRESSED_R16: c_int = 11;
const PIXELFORMAT_UNCOMPRESSED_R16G16B16: c_int = 12;
const PIXELFORMAT_UNCOMPRESSED_R16G16B16A16: c_int = 13;
const PIXELFORMAT_COMPRESSED_DXT1_RGB: c_int = 14;
const PIXELFORMAT_COMPRESSED_DXT1_RGBA: c_int = 15;
const PIXELFORMAT_COMPRESSED_DXT3_RGBA: c_int = 16;
const PIXELFORMAT_COMPRESSED_DXT5_RGBA: c_int = 17;
const PIXELFORMAT_COMPRESSED_ETC1_RGB: c_int = 18;
const PIXELFORMAT_COMPRESSED_ETC2_RGB: c_int = 19;
const PIXELFORMAT_COMPRESSED_ETC2_EAC_RGBA: c_int = 20;
const PIXELFORMAT_COMPRESSED_PVRT_RGB: c_int = 21;
const PIXELFORMAT_COMPRESSED_PVRT_RGBA: c_int = 22;
const PIXELFORMAT_COMPRESSED_ASTC_4x4_RGBA: c_int = 23;
const PIXELFORMAT_COMPRESSED_ASTC_8x8_RGBA: c_int = 24;

// TraceLogLevel values (raylib.h)
const LOG_INFO: c_int = 3;
const LOG_WARNING: c_int = 4;
const LOG_DEBUG: c_int = 2;

// TextureFilter values (raylib.h)
const TEXTURE_FILTER_POINT: c_int = 0;
const TEXTURE_FILTER_BILINEAR: c_int = 1;
const TEXTURE_FILTER_TRILINEAR: c_int = 2;
const TEXTURE_FILTER_ANISOTROPIC_4X: c_int = 3;
const TEXTURE_FILTER_ANISOTROPIC_8X: c_int = 4;
const TEXTURE_FILTER_ANISOTROPIC_16X: c_int = 5;

// TextureWrap values (raylib.h)
const TEXTURE_WRAP_REPEAT: c_int = 0;
const TEXTURE_WRAP_CLAMP: c_int = 1;
const TEXTURE_WRAP_MIRROR_REPEAT: c_int = 2;
const TEXTURE_WRAP_MIRROR_CLAMP: c_int = 3;

// CubemapLayout values (raylib.h)
const CUBEMAP_LAYOUT_AUTO_DETECT: c_int = 0;
const CUBEMAP_LAYOUT_LINE_VERTICAL: c_int = 1;
const CUBEMAP_LAYOUT_LINE_HORIZONTAL: c_int = 2;
const CUBEMAP_LAYOUT_CROSS_THREE_BY_FOUR: c_int = 3;
const CUBEMAP_LAYOUT_CROSS_FOUR_BY_THREE: c_int = 4;

// NPatchLayout values (raylib.h)
const NPATCH_NINE_PATCH: c_int = 0;
const NPATCH_THREE_PATCH_VERTICAL: c_int = 1;
const NPATCH_THREE_PATCH_HORIZONTAL: c_int = 2;

// rlgl draw modes (rlgl.h)
const RL_LINES: c_int = 0x0001;
const RL_TRIANGLES: c_int = 0x0004;
const RL_QUADS: c_int = 0x0007;

// rlgl texture parameters (rlgl.h)
const RL_TEXTURE_WRAP_S: c_int = 0x2802;
const RL_TEXTURE_WRAP_T: c_int = 0x2803;
const RL_TEXTURE_MAG_FILTER: c_int = 0x2800;
const RL_TEXTURE_MIN_FILTER: c_int = 0x2801;
const RL_TEXTURE_FILTER_NEAREST: c_int = 0x2600;
const RL_TEXTURE_FILTER_LINEAR: c_int = 0x2601;
const RL_TEXTURE_FILTER_MIP_NEAREST: c_int = 0x2700;
const RL_TEXTURE_FILTER_NEAREST_MIP_LINEAR: c_int = 0x2702;
const RL_TEXTURE_FILTER_LINEAR_MIP_NEAREST: c_int = 0x2701;
const RL_TEXTURE_FILTER_MIP_LINEAR: c_int = 0x2703;
const RL_TEXTURE_FILTER_ANISOTROPIC: c_int = 0x3000;
const RL_TEXTURE_WRAP_REPEAT: c_int = 0x2901;
const RL_TEXTURE_WRAP_CLAMP: c_int = 0x812F;
const RL_TEXTURE_WRAP_MIRROR_REPEAT: c_int = 0x8370;
const RL_TEXTURE_WRAP_MIRROR_CLAMP: c_int = 0x8742;

// rlgl framebuffer attachment types (rlgl.h)
const RL_ATTACHMENT_COLOR_CHANNEL0: c_int = 0;
const RL_ATTACHMENT_DEPTH: c_int = 100;
const RL_ATTACHMENT_TEXTURE2D: c_int = 100;
const RL_ATTACHMENT_RENDERBUFFER: c_int = 200;

// Predefined colors (raylib.h)
const WHITE = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
const BLANK = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
const MAGENTA = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };

//----------------------------------------------------------------------------------
// Types and Structures Definition (exact raylib.h layout)
//----------------------------------------------------------------------------------
pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const Vector2 = extern struct {
    x: f32,
    y: f32,
};

pub const Vector3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Vector4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

pub const Rectangle = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const Image = extern struct {
    data: ?*anyopaque = null,
    width: c_int = 0,
    height: c_int = 0,
    mipmaps: c_int = 0,
    format: c_int = 0,
};

pub const Texture = extern struct {
    id: c_uint = 0,
    width: c_int = 0,
    height: c_int = 0,
    mipmaps: c_int = 0,
    format: c_int = 0,
};
pub const Texture2D = Texture;
pub const TextureCubemap = Texture;

pub const RenderTexture = extern struct {
    id: c_uint = 0,
    texture: Texture = .{},
    depth: Texture = .{},
};
pub const RenderTexture2D = RenderTexture;

pub const NPatchInfo = extern struct {
    source: Rectangle,
    left: c_int,
    top: c_int,
    right: c_int,
    bottom: c_int,
    layout: c_int,
};

pub const GlyphInfo = extern struct {
    value: c_int,
    offsetX: c_int,
    offsetY: c_int,
    advanceX: c_int,
    image: Image,
};

pub const Font = extern struct {
    baseSize: c_int,
    glyphCount: c_int,
    glyphPadding: c_int,
    texture: Texture2D,
    recs: [*c]Rectangle,
    glyphs: [*c]GlyphInfo,
};

//----------------------------------------------------------------------------------
// Internal cast helpers (C truncating conversions)
//----------------------------------------------------------------------------------
// C `(int)` truncation toward zero (assumes value in range, like the C source).
inline fn ti(v: anytype) c_int {
    return @intFromFloat(v);
}
// C `(unsigned char)` truncation from float toward zero, then wrap to u8.
inline fn tuc(v: anytype) u8 {
    return @bitCast(@as(i8, @truncate(@as(c_int, @intFromFloat(v)))));
}
// C `(unsigned char)` truncation from an integer (low 8 bits).
inline fn iuc(v: anytype) u8 {
    return @truncate(@as(c_uint, @bitCast(@as(c_int, v))));
}

// C implicit integer-to-float promotion in mixed arithmetic.
inline fn f(v: anytype) f32 {
    return @floatFromInt(v);
}

//----------------------------------------------------------------------------------
// Memory and C-string helpers
//----------------------------------------------------------------------------------
/// `count` zeroed items on the C heap, for a buffer a raylib caller (or
/// UnloadImage) releases with free. Null for a negative count, or when out of
/// memory.
fn allocC(comptime T: type, count: c_int) ?[]T {
    const n = std.math.cast(usize, count) orelse return null;
    return cmem.alloc(T, n) catch null;
}

/// Whether `fileType` is exactly one of `exts`: raylib compares with strcmp,
/// so ".png" and ".PNG" match and ".Png" does not.
fn isFileType(fileType: [*:0]const u8, exts: []const []const u8) bool {
    const t = std.mem.span(fileType);
    for (exts) |ext| {
        if (std.mem.eql(u8, t, ext)) return true;
    }
    return false;
}

/// raylib's `width*height` pixel count.
fn pixelCount(image: Image) usize {
    return @intCast(image.width * image.height);
}

/// The first `len` bytes at `data`.
fn bytesAt(data: ?*anyopaque, len: c_int) []u8 {
    const ptr: [*]u8 = @ptrCast(data orelse return &.{});
    return ptr[0..@intCast(len)];
}

/// Replaces an image's pixels with `pixels` (R8G8B8A8, which it takes over)
/// and converts them back to the image's format: the common tail of the
/// image operations that work on colors.
fn setColorsKeepFormat(image: *Image, pixels: []Color) void {
    const format = image.format;
    cmem.free(image.data);
    image.data = pixels.ptr;
    image.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
    ImageFormat(image, format);
}

//----------------------------------------------------------------------------------
// Pixel codecs: one pixel of an uncompressed format, to and from Color/Vector4
//----------------------------------------------------------------------------------
/// Bytes per pixel of an uncompressed format; 0 for any other format.
fn bytesPerPixel(format: c_int) usize {
    return switch (format) {
        PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => 1,
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA,
        PIXELFORMAT_UNCOMPRESSED_R5G6B5,
        PIXELFORMAT_UNCOMPRESSED_R5G5B5A1,
        PIXELFORMAT_UNCOMPRESSED_R4G4B4A4,
        PIXELFORMAT_UNCOMPRESSED_R16,
        => 2,
        PIXELFORMAT_UNCOMPRESSED_R8G8B8 => 3,
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, PIXELFORMAT_UNCOMPRESSED_R32 => 4,
        PIXELFORMAT_UNCOMPRESSED_R16G16B16 => 6,
        PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => 8,
        PIXELFORMAT_UNCOMPRESSED_R32G32B32 => 12,
        PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => 16,
        else => 0,
    };
}

// Typed views of one pixel. Each codec takes them only in the format arms
// that use them: a 1-byte format can sit at an odd address, where an eager
// @alignCast traps (CLAUDE.md, "Casts C performs freely must stay lazy").
fn u16s(ptr: [*]const u8) [*]const u16 {
    return @ptrCast(@alignCast(ptr));
}
fn f32s(ptr: [*]const u8) [*]const f32 {
    return @ptrCast(@alignCast(ptr));
}
fn u16sOut(ptr: [*]u8) [*]u16 {
    return @ptrCast(@alignCast(ptr));
}
fn f32sOut(ptr: [*]u8) [*]f32 {
    return @ptrCast(@alignCast(ptr));
}

/// One pixel as normalized floats, as LoadImageDataNormalized decodes it;
/// null for a format it does not decode.
fn readNormalized(src: [*]const u8, format: c_int) ?Vector4 {
    return switch (format) {
        PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => .{ .x = f(src[0]) / 255.0, .y = f(src[0]) / 255.0, .z = f(src[0]) / 255.0, .w = 1.0 },
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => .{ .x = f(src[0]) / 255.0, .y = f(src[0]) / 255.0, .z = f(src[0]) / 255.0, .w = f(src[1]) / 255.0 },
        PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => blk: {
            const pixel = u16s(src)[0];
            break :blk .{
                .x = f((pixel & 0b1111100000000000) >> 11) * (1.0 / 31.0),
                .y = f((pixel & 0b0000011111000000) >> 6) * (1.0 / 31.0),
                .z = f((pixel & 0b0000000000111110) >> 1) * (1.0 / 31.0),
                .w = if ((pixel & 0b0000000000000001) == 0) 0.0 else 1.0,
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R5G6B5 => blk: {
            const pixel = u16s(src)[0];
            break :blk .{
                .x = f((pixel & 0b1111100000000000) >> 11) * (1.0 / 31.0),
                .y = f((pixel & 0b0000011111100000) >> 5) * (1.0 / 63.0),
                .z = f(pixel & 0b0000000000011111) * (1.0 / 31.0),
                .w = 1.0,
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => blk: {
            const pixel = u16s(src)[0];
            break :blk .{
                .x = f((pixel & 0b1111000000000000) >> 12) * (1.0 / 15.0),
                .y = f((pixel & 0b0000111100000000) >> 8) * (1.0 / 15.0),
                .z = f((pixel & 0b0000000011110000) >> 4) * (1.0 / 15.0),
                .w = f(pixel & 0b0000000000001111) * (1.0 / 15.0),
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => .{ .x = f(src[0]) / 255.0, .y = f(src[1]) / 255.0, .z = f(src[2]) / 255.0, .w = f(src[3]) / 255.0 },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8 => .{ .x = f(src[0]) / 255.0, .y = f(src[1]) / 255.0, .z = f(src[2]) / 255.0, .w = 1.0 },
        PIXELFORMAT_UNCOMPRESSED_R32 => .{ .x = f32s(src)[0], .y = 0.0, .z = 0.0, .w = 1.0 },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32 => .{ .x = f32s(src)[0], .y = f32s(src)[1], .z = f32s(src)[2], .w = 1.0 },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => .{ .x = f32s(src)[0], .y = f32s(src)[1], .z = f32s(src)[2], .w = f32s(src)[3] },
        PIXELFORMAT_UNCOMPRESSED_R16 => .{ .x = encode.halfToFloat(u16s(src)[0]), .y = 0.0, .z = 0.0, .w = 1.0 },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16 => .{
            .x = encode.halfToFloat(u16s(src)[0]),
            .y = encode.halfToFloat(u16s(src)[1]),
            .z = encode.halfToFloat(u16s(src)[2]),
            .w = 1.0,
        },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => .{
            .x = encode.halfToFloat(u16s(src)[0]),
            .y = encode.halfToFloat(u16s(src)[1]),
            .z = encode.halfToFloat(u16s(src)[2]),
            .w = encode.halfToFloat(u16s(src)[3]),
        },
        else => null,
    };
}

/// Gray as raylib weighs it: ITU-R BT.601 luma.
fn luma(p: Vector4) f32 {
    return p.x * 0.299 + p.y * 0.587 + p.z * 0.114;
}

/// Writes one pixel from normalized floats, as ImageFormat encodes it.
fn writeNormalized(dst: [*]u8, p: Vector4, format: c_int) void {
    switch (format) {
        PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => dst[0] = tuc(luma(p) * 255.0),
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
            dst[0] = tuc(luma(p) * 255.0);
            dst[1] = tuc(p.w * 255.0);
        },
        PIXELFORMAT_UNCOMPRESSED_R5G6B5 => {
            const r: u16 = tuc(@round(p.x * 31.0));
            const g: u16 = tuc(@round(p.y * 63.0));
            const b: u16 = tuc(@round(p.z * 31.0));
            u16sOut(dst)[0] = (r << 11) | (g << 5) | b;
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8 => {
            dst[0] = tuc(p.x * 255.0);
            dst[1] = tuc(p.y * 255.0);
            dst[2] = tuc(p.z * 255.0);
        },
        PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
            const r: u16 = tuc(@round(p.x * 31.0));
            const g: u16 = tuc(@round(p.y * 31.0));
            const b: u16 = tuc(@round(p.z * 31.0));
            const a: u16 = if (p.w > (f(PIXELFORMAT_UNCOMPRESSED_R5G5B5A1_ALPHA_THRESHOLD) / 255.0)) 1 else 0;
            u16sOut(dst)[0] = (r << 11) | (g << 6) | (b << 1) | a;
        },
        PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
            const r: u16 = tuc(@round(p.x * 15.0));
            const g: u16 = tuc(@round(p.y * 15.0));
            const b: u16 = tuc(@round(p.z * 15.0));
            const a: u16 = tuc(@round(p.w * 15.0));
            u16sOut(dst)[0] = (r << 12) | (g << 8) | (b << 4) | a;
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => {
            dst[0] = tuc(p.x * 255.0);
            dst[1] = tuc(p.y * 255.0);
            dst[2] = tuc(p.z * 255.0);
            dst[3] = tuc(p.w * 255.0);
        },
        PIXELFORMAT_UNCOMPRESSED_R32 => f32sOut(dst)[0] = luma(p),
        PIXELFORMAT_UNCOMPRESSED_R32G32B32 => f32sOut(dst)[0..3].* = .{ p.x, p.y, p.z },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => f32sOut(dst)[0..4].* = .{ p.x, p.y, p.z, p.w },
        PIXELFORMAT_UNCOMPRESSED_R16 => u16sOut(dst)[0] = encode.floatToHalf(luma(p)),
        PIXELFORMAT_UNCOMPRESSED_R16G16B16 => u16sOut(dst)[0..3].* = .{
            encode.floatToHalf(p.x),
            encode.floatToHalf(p.y),
            encode.floatToHalf(p.z),
        },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => u16sOut(dst)[0..4].* = .{
            encode.floatToHalf(p.x),
            encode.floatToHalf(p.y),
            encode.floatToHalf(p.z),
            encode.floatToHalf(p.w),
        },
        else => {},
    }
}

/// `color` as normalized floats.
fn toNormalized(color: Color) Vector4 {
    return .{ .x = f(color.r) / 255.0, .y = f(color.g) / 255.0, .z = f(color.b) / 255.0, .w = f(color.a) / 255.0 };
}

/// Writes one pixel from a Color, as ImageDrawPixel does: 8-bit channels are
/// stored as they are, everything else goes through the normalized encoder.
fn writeColor(dst: [*]u8, color: Color, format: c_int) void {
    switch (format) {
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
            dst[0] = tuc(luma(toNormalized(color)) * 255.0);
            dst[1] = color.a;
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8 => dst[0..3].* = .{ color.r, color.g, color.b },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => dst[0..4].* = .{ color.r, color.g, color.b, color.a },
        else => writeNormalized(dst, toNormalized(color), format),
    }
}

/// One pixel as a Color, as LoadImageColors and GetImageColor decode it; null
/// for a format they do not decode.
fn readColor(src: [*]const u8, format: c_int) ?Color {
    // NOTE: raylib scales 5- and 6-bit channels by the integers 255/31 (8) and
    // 255/63 (4), not by 8.23 and 4.05: white reads back as 248. Deliberate.
    return switch (format) {
        PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => .{ .r = src[0], .g = src[0], .b = src[0], .a = 255 },
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => .{ .r = src[0], .g = src[0], .b = src[0], .a = src[1] },
        PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => blk: {
            const pixel = u16s(src)[0];
            break :blk .{
                .r = tuc(f((pixel & 0b1111100000000000) >> 11) * @divTrunc(255, 31)),
                .g = tuc(f((pixel & 0b0000011111000000) >> 6) * @divTrunc(255, 31)),
                .b = tuc(f((pixel & 0b0000000000111110) >> 1) * @divTrunc(255, 31)),
                .a = iuc((pixel & 0b0000000000000001) * 255),
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R5G6B5 => blk: {
            const pixel = u16s(src)[0];
            break :blk .{
                .r = tuc(f((pixel & 0b1111100000000000) >> 11) * @divTrunc(255, 31)),
                .g = tuc(f((pixel & 0b0000011111100000) >> 5) * @divTrunc(255, 63)),
                .b = tuc(f(pixel & 0b0000000000011111) * @divTrunc(255, 31)),
                .a = 255,
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => blk: {
            const pixel = u16s(src)[0];
            break :blk .{
                .r = tuc(f((pixel & 0b1111000000000000) >> 12) * @divTrunc(255, 15)),
                .g = tuc(f((pixel & 0b0000111100000000) >> 8) * @divTrunc(255, 15)),
                .b = tuc(f((pixel & 0b0000000011110000) >> 4) * @divTrunc(255, 15)),
                .a = tuc(f(pixel & 0b0000000000001111) * @divTrunc(255, 15)),
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => .{ .r = src[0], .g = src[1], .b = src[2], .a = src[3] },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8 => .{ .r = src[0], .g = src[1], .b = src[2], .a = 255 },
        PIXELFORMAT_UNCOMPRESSED_R32 => .{ .r = tuc(f32s(src)[0] * 255.0), .g = 0, .b = 0, .a = 255 },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32 => .{
            .r = tuc(f32s(src)[0] * 255.0),
            .g = tuc(f32s(src)[1] * 255.0),
            .b = tuc(f32s(src)[2] * 255.0),
            .a = 255,
        },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => .{
            .r = tuc(f32s(src)[0] * 255.0),
            .g = tuc(f32s(src)[1] * 255.0),
            .b = tuc(f32s(src)[2] * 255.0),
            .a = tuc(f32s(src)[3] * 255.0),
        },
        PIXELFORMAT_UNCOMPRESSED_R16 => .{ .r = tuc(encode.halfToFloat(u16s(src)[0]) * 255.0), .g = 0, .b = 0, .a = 255 },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16 => .{
            .r = tuc(encode.halfToFloat(u16s(src)[0]) * 255.0),
            .g = tuc(encode.halfToFloat(u16s(src)[1]) * 255.0),
            .b = tuc(encode.halfToFloat(u16s(src)[2]) * 255.0),
            .a = 255,
        },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => .{
            .r = tuc(encode.halfToFloat(u16s(src)[0]) * 255.0),
            .g = tuc(encode.halfToFloat(u16s(src)[1]) * 255.0),
            .b = tuc(encode.halfToFloat(u16s(src)[2]) * 255.0),
            .a = tuc(encode.halfToFloat(u16s(src)[3]) * 255.0),
        },
        else => null,
    };
}

/// The pixels of `image` as normalized floats, in scratch memory the caller
/// frees with `gpa`. Pixels of a format it cannot decode are left undefined.
fn loadNormalized(gpa: Allocator, image: Image) Allocator.Error![]Vector4 {
    const pixels = try gpa.alloc(Vector4, pixelCount(image));

    if (image.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "IMAGE: Pixel data retrieval not supported for compressed image formats");
        return pixels;
    }

    const src: [*]const u8 = @ptrCast(image.data);
    const size = bytesPerPixel(image.format);
    for (pixels, 0..) |*pixel, i| {
        pixel.* = readNormalized(src + i * size, image.format) orelse continue;
    }
    return pixels;
}

/// The pixels of `image` as R8G8B8A8, on the C heap; LoadImageColors' result.
fn loadColors(image: Image) ?[]Color {
    if ((image.width == 0) or (image.height == 0)) return null; // Security check

    const pixels = allocC(Color, image.width * image.height) orelse return null;

    if (image.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "IMAGE: Pixel data retrieval not supported for compressed image formats");
        return pixels;
    }

    if ((image.format == PIXELFORMAT_UNCOMPRESSED_R32) or
        (image.format == PIXELFORMAT_UNCOMPRESSED_R32G32B32) or
        (image.format == PIXELFORMAT_UNCOMPRESSED_R32G32B32A32)) TraceLog(LOG_WARNING, "IMAGE: Pixel format converted from 32bit to 8bit per channel");

    if ((image.format == PIXELFORMAT_UNCOMPRESSED_R16) or
        (image.format == PIXELFORMAT_UNCOMPRESSED_R16G16B16) or
        (image.format == PIXELFORMAT_UNCOMPRESSED_R16G16B16A16)) TraceLog(LOG_WARNING, "IMAGE: Pixel format converted from 16bit to 8bit per channel");

    const src: [*]const u8 = @ptrCast(image.data);
    const size = bytesPerPixel(image.format);
    for (pixels, 0..) |*pixel, i| {
        pixel.* = readColor(src + i * size, image.format) orelse continue;
    }
    return pixels;
}

//----------------------------------------------------------------------------------
// Module Functions Definition
//----------------------------------------------------------------------------------
// Load image from file into CPU memory (RAM)
export fn LoadImage(fileName: [*c]const u8) callconv(.c) Image {
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize) orelse return .{};
    defer UnloadFileData(fileData);

    return LoadImageFromMemory(GetFileExtension(fileName), fileData, dataSize);
}

// Load an image from RAW file data
export fn LoadImageRaw(fileName: [*c]const u8, width: c_int, height: c_int, format: c_int, headerSize: c_int) callconv(.c) Image {
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize) orelse return .{};
    defer UnloadFileData(fileData);

    const size = GetPixelDataSize(width, height, format);
    if (size > dataSize) return .{}; // Security check

    // NOTE: A header that would leave too few bytes is ignored, as raylib does
    const offset: usize = if ((headerSize > 0) and ((headerSize + size) <= dataSize)) @intCast(headerSize) else 0;
    const pixels = allocC(u8, size) orelse return .{};
    @memcpy(pixels, fileData[offset..][0..pixels.len]);

    return .{ .data = pixels.ptr, .width = width, .height = height, .mipmaps = 1, .format = format };
}

// Load animated image data
export fn LoadImageAnim(fileName: [*c]const u8, frames: [*c]c_int) callconv(.c) Image {
    if (!IsFileExtension(fileName, ".gif")) {
        frames.* = 1;
        return LoadImage(fileName);
    }

    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize) orelse {
        frames.* = 0;
        return .{};
    };
    defer UnloadFileData(fileData);

    return loadGif(fileData, dataSize, frames);
}

// Load animated image data from memory
export fn LoadImageAnimFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: c_int, frames: [*c]c_int) callconv(.c) Image {
    // NOTE: `frames` is left untouched by a failed security check, as in raylib
    if ((fileType == null) or (fileData == null) or (dataSize == 0)) return .{}; // Security check

    if (!isFileType(fileType, &.{ ".gif", ".GIF" })) {
        frames.* = 1;
        return LoadImageFromMemory(fileType, fileData, dataSize);
    }
    return loadGif(fileData, dataSize, frames);
}

/// Every frame of a GIF, stacked vertically in one R8G8B8A8 image.
fn loadGif(fileData: [*]const u8, dataSize: c_int, frames: *c_int) Image {
    var image: Image = .{ .mipmaps = 1, .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 };
    var comp: c_int = 0;
    var delays: ?[*]c_int = null;
    frames.* = 0;
    image.data = stbi_load_gif_from_memory(fileData, dataSize, &delays, &image.width, &image.height, frames, &comp, 4);
    cmem.free(delays); // NOTE: Frames delays are discarded
    return image;
}

// Load image from memory buffer, fileType refers to extension: i.e. ".png"
export fn LoadImageFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: c_int) callconv(.c) Image {
    // Security checks for input data
    if ((fileData == null) or (dataSize == 0)) {
        TraceLog(LOG_WARNING, "IMAGE: Invalid file data");
        return .{};
    }
    if (fileType == null) {
        TraceLog(LOG_WARNING, "IMAGE: Missing file extension");
        return .{};
    }

    var image: Image = .{};

    if (isFileType(fileType, &.{ ".png", ".PNG", ".bmp", ".BMP", ".gif", ".GIF" })) {
        // NOTE: Using stb_image to load images (Supports multiple image formats)
        var comp: c_int = 0;
        image.data = stbi_load_from_memory(fileData, dataSize, &image.width, &image.height, &comp, 0);

        if (image.data != null) {
            image.mipmaps = 1;
            image.format = switch (comp) {
                1 => PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
                2 => PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA,
                3 => PIXELFORMAT_UNCOMPRESSED_R8G8B8,
                4 => PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
                else => 0,
            };
        }
    } else if (isFileType(fileType, &.{ ".qoi", ".QOI" })) {
        var desc: qoi_desc = .{};
        // The channel count is read from the QOI header itself
        image.data = qoi_decode(fileData, dataSize, &desc, fileData[12]);
        image.width = @intCast(desc.width);
        image.height = @intCast(desc.height);
        image.format = if (desc.channels == 4) PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 else PIXELFORMAT_UNCOMPRESSED_R8G8B8;
        image.mipmaps = 1;
    } else if (isFileType(fileType, &.{ ".dds", ".DDS" })) {
        image.data = rl_load_dds_from_memory(fileData, @intCast(dataSize), &image.width, &image.height, &image.format, &image.mipmaps);
    } else TraceLog(LOG_WARNING, "IMAGE: Data format not supported");

    if (image.data != null) {
        TraceLog(LOG_INFO, "IMAGE: Data loaded successfully (%ix%i | %s | %i mipmaps)", image.width, image.height, rlGetPixelFormatName(@intCast(image.format)), image.mipmaps);
    } else TraceLog(LOG_WARNING, "IMAGE: Failed to load image data");

    return image;
}

// Load image from GPU texture data
export fn LoadImageFromTexture(texture: Texture2D) callconv(.c) Image {
    if (texture.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "TEXTURE: [ID %i] Failed to retrieve compressed pixel data", texture.id);
        return .{};
    }

    const data = rlReadTexturePixels(texture.id, texture.width, texture.height, texture.format) orelse {
        TraceLog(LOG_WARNING, "TEXTURE: [ID %i] Failed to retrieve pixel data", texture.id);
        return .{};
    };

    TraceLog(LOG_INFO, "TEXTURE: [ID %i] Pixel data retrieved successfully", texture.id);
    return .{ .data = data, .width = texture.width, .height = texture.height, .mipmaps = 1, .format = texture.format };
}

// Load image from screen buffer (screenshot)
export fn LoadImageFromScreen() callconv(.c) Image {
    const width = GetRenderWidth();
    const height = GetRenderHeight();
    return .{
        .data = rlReadScreenPixels(width, height),
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
}

// Check if an image is valid
export fn IsImageValid(image: Image) callconv(.c) bool {
    return (image.data != null) and
        (image.width > 0) and
        (image.height > 0) and
        (image.format > 0) and
        (image.mipmaps > 0);
}

// Unload image from CPU memory (RAM)
export fn UnloadImage(image: Image) callconv(.c) void {
    cmem.free(image.data);
}

/// Channel count of the 8-bit-per-channel formats stb_image_write takes as
/// they are; null for any other format.
fn stbChannels(format: c_int) ?c_int {
    return switch (format) {
        PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => 1,
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => 2,
        PIXELFORMAT_UNCOMPRESSED_R8G8B8 => 3,
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => 4,
        else => null,
    };
}

// Export image data to file
export fn ExportImage(image: Image, fileName: [*c]const u8) callconv(.c) bool {
    if ((image.width == 0) or (image.height == 0) or (image.data == null)) return false; // Security check

    // NOTE: Any other format is exported as RGBA unsigned char values
    const colors: ?[]Color = if (stbChannels(image.format) == null) loadColors(image) else null;
    defer if (colors) |pixels| cmem.free(pixels.ptr);
    const channels = stbChannels(image.format) orelse 4;
    const imgData: ?*const anyopaque = if (colors) |pixels| pixels.ptr else image.data;

    const result = if (IsFileExtension(fileName, ".png")) png: {
        var dataSize: c_int = 0;
        const fileData = stbi_write_png_to_mem(@ptrCast(imgData), image.width * channels, image.width, image.height, channels, &dataSize);
        defer cmem.free(fileData);
        break :png SaveFileData(fileName, fileData, dataSize);
    } else if (IsFileExtension(fileName, ".bmp"))
        stbi_write_bmp(fileName, image.width, image.height, channels, imgData) != 0
    else if (IsFileExtension(fileName, ".qoi")) qoi: {
        const qoiChannels: u8 = switch (image.format) {
            PIXELFORMAT_UNCOMPRESSED_R8G8B8 => 3,
            PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => 4,
            else => {
                TraceLog(LOG_WARNING, "IMAGE: Image pixel format must be R8G8B8 or R8G8B8A8");
                break :qoi false;
            },
        };
        const desc: qoi_desc = .{
            .width = @intCast(image.width),
            .height = @intCast(image.height),
            .channels = qoiChannels,
            .colorspace = 0, // QOI_SRGB
        };
        break :qoi qoi_write(fileName, imgData, &desc) != 0;
    } else if (IsFileExtension(fileName, ".raw"))
        // Export raw pixel data (without header)
        SaveFileData(fileName, image.data, GetPixelDataSize(image.width, image.height, image.format))
    else unsupported: {
        TraceLog(LOG_WARNING, "IMAGE: Export image format requested not supported");
        break :unsupported false;
    };

    if (result) {
        TraceLog(LOG_INFO, "FILEIO: [%s] Image exported successfully", fileName);
    } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export image", fileName);

    return result;
}

// Export image to memory buffer
export fn ExportImageToMemory(image: Image, fileType: [*c]const u8, dataSize: [*c]c_int) callconv(.c) [*c]u8 {
    dataSize.* = 0;

    if ((image.width == 0) or (image.height == 0) or (image.data == null)) return null; // Security check
    if (!isFileType(fileType, &.{ ".png", ".PNG" })) return null;

    // NOTE: Unlike ExportImage, other formats are not converted: their data is
    // read as 4 channels (raylib behaviour)
    const channels = stbChannels(image.format) orelse 4;
    return stbi_write_png_to_mem(@ptrCast(image.data), image.width * channels, image.width, image.height, channels, dataSize);
}

// Export image as code file (.h) defining an array of bytes
export fn ExportImageAsCode(image: Image, fileName: [*c]const u8) callconv(.c) bool {
    const dataSize = GetPixelDataSize(image.width, image.height, image.format);

    const result = saved: {
        // NOTE: raylib reads one byte before the data of an empty image
        // (undefined behaviour); here that export fails instead
        if ((dataSize <= 0) or (image.data == null)) break :saved false;

        const info: encode.ImageInfo = .{ .width = image.width, .height = image.height, .format = image.format };
        const stem = std.mem.span(GetFileNameWithoutExt(fileName));
        const text = encode.imageAsCode(c_allocator, bytesAt(image.data, dataSize), info, stem) catch break :saved false;
        defer c_allocator.free(text);
        break :saved SaveFileText(fileName, text.ptr);
    };

    if (result) {
        TraceLog(LOG_INFO, "FILEIO: [%s] Image as code exported successfully", fileName);
    } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export image as code", fileName);

    return result;
}

//------------------------------------------------------------------------------------
// Image generation functions
//------------------------------------------------------------------------------------
/// A C `int` dimension as a loop bound: C loops `for (i = 0; i < n; i++)`
/// never run for a negative `n`.
fn dim(n: c_int) usize {
    return std.math.cast(usize, n) orelse 0;
}

/// A generated R8G8B8A8 image over `pixels`.
fn rgbaImage(pixels: ?[]Color, width: c_int, height: c_int) Image {
    return .{
        .data = if (pixels) |p| p.ptr else null,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
}

/// C `(unsigned char)(a*factor + b*(1.0f - factor))` for each channel.
fn blendColors(a: Color, b: Color, factor: f32) Color {
    return .{
        .r = tuc(f(a.r) * factor + f(b.r) * (1.0 - factor)),
        .g = tuc(f(a.g) * factor + f(b.g) * (1.0 - factor)),
        .b = tuc(f(a.b) * factor + f(b.b) * (1.0 - factor)),
        .a = tuc(f(a.a) * factor + f(b.a) * (1.0 - factor)),
    };
}

// Generate image: plain color
export fn GenImageColor(width: c_int, height: c_int, color: Color) callconv(.c) Image {
    // NOTE: Sized by GetPixelDataSize, so an oversized request (>2GB) gets an
    // empty buffer
    const dataSize = GetPixelDataSize(width, height, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);
    const pixels = allocC(Color, @divTrunc(dataSize, @sizeOf(Color)));
    if (pixels) |p| @memset(p, color);
    return rgbaImage(pixels, width, height);
}

// Generate image: linear gradient
export fn GenImageGradientLinear(width: c_int, height: c_int, direction: c_int, start: Color, end: Color) callconv(.c) Image {
    const pixels = allocC(Color, width * height) orelse return rgbaImage(null, width, height);

    const radianDirection: f32 = f(90 - direction) / 180.0 * 3.14159;
    const cosDir = cosf(radianDirection);
    const sinDir = sinf(radianDirection);

    const startingPos: f32 = 0.5 - (cosDir * f(width) / 2) - (sinDir * f(height) / 2);

    const maxPosValue: f32 = if ((std.math.signbit(sinDir)) == (std.math.signbit(cosDir)))
        @abs(startingPos)
    else
        @abs(startingPos + f(width) * cosDir);

    for (0..dim(height)) |j| {
        for (0..dim(width)) |i| {
            const pos: f32 = (startingPos + (f(i) * cosDir + f(j) * sinDir)) / maxPosValue;

            // NOTE: Ternaries rather than std.math.clamp, which would turn NaN into a bound
            var factor = pos;
            factor = if (factor > 1.0) 1.0 else factor;
            factor = if (factor < -1.0) -1.0 else factor;
            factor = factor / 2.0 + 0.5;

            pixels[j * dim(width) + i] = blendColors(end, start, factor);
        }
    }

    return rgbaImage(pixels, width, height);
}

// Generate image: radial gradient
export fn GenImageGradientRadial(width: c_int, height: c_int, density: f32, inner: Color, outer: Color) callconv(.c) Image {
    const pixels = allocC(Color, width * height) orelse return rgbaImage(null, width, height);
    const radius: f32 = if (width < height) f(width) / 2.0 else f(height) / 2.0;

    const centerX: f32 = f(width) / 2.0;
    const centerY: f32 = f(height) / 2.0;

    for (0..dim(height)) |y| {
        for (0..dim(width)) |x| {
            const dist = hypotf(f(x) - centerX, f(y) - centerY);
            var factor = (dist - radius * density) / (radius * (1.0 - density));

            factor = @floatCast(fmax(factor, 0.0));
            factor = @floatCast(fmin(factor, 1.0)); // dist can be bigger than radius, so we have to check

            pixels[y * dim(width) + x] = blendColors(outer, inner, factor);
        }
    }

    return rgbaImage(pixels, width, height);
}

// Generate image: square gradient
export fn GenImageGradientSquare(width: c_int, height: c_int, density: f32, inner: Color, outer: Color) callconv(.c) Image {
    const pixels = allocC(Color, width * height) orelse return rgbaImage(null, width, height);

    const centerX: f32 = f(width) / 2.0;
    const centerY: f32 = f(height) / 2.0;

    for (0..dim(height)) |y| {
        for (0..dim(width)) |x| {
            // Calculate the Manhattan distance from the center
            const distX = @abs(f(x) - centerX);
            const distY = @abs(f(y) - centerY);

            // Normalize the distances by the dimensions of the gradient rectangle
            const normalizedDistX = distX / centerX;
            const normalizedDistY = distY / centerY;

            // Calculate the total normalized Manhattan distance
            const manhattanDist = fmaxf(normalizedDistX, normalizedDistY);

            // Subtract the density from the manhattanDist, then divide by (1 - density)
            // This makes the gradient start from the center when density is 0, and from the edge when density is 1
            const factor = (manhattanDist - density) / (1.0 - density);

            // Clamp the factor between 0 and 1
            const clamped = fminf(fmaxf(factor, 0.0), 1.0);

            pixels[y * dim(width) + x] = blendColors(outer, inner, clamped);
        }
    }

    return rgbaImage(pixels, width, height);
}

// Generate image: checked
export fn GenImageChecked(width: c_int, height: c_int, checksX: c_int, checksY: c_int, col1: Color, col2: Color) callconv(.c) Image {
    const pixels = allocC(Color, width * height) orelse return rgbaImage(null, width, height);

    for (0..dim(height)) |yi| {
        for (0..dim(width)) |xi| {
            // C int division: negative check sizes keep their sign
            const x: c_int = @intCast(xi);
            const y: c_int = @intCast(yi);
            pixels[yi * dim(width) + xi] = if (@rem(@divTrunc(x, checksX) + @divTrunc(y, checksY), 2) == 0) col1 else col2;
        }
    }

    return rgbaImage(pixels, width, height);
}

// Generate image: white noise
export fn GenImageWhiteNoise(width: c_int, height: c_int, factor: f32) callconv(.c) Image {
    const pixels = allocC(Color, width * height) orelse return rgbaImage(null, width, height);

    for (pixels) |*pixel| pixel.* = if (GetRandomValue(0, 99) < ti(factor * 100.0)) WHITE else BLACK;

    return rgbaImage(pixels, width, height);
}

// Generate image: perlin noise
export fn GenImagePerlinNoise(width: c_int, height: c_int, offsetX: c_int, offsetY: c_int, scale: f32) callconv(.c) Image {
    const pixels = allocC(Color, width * height) orelse return rgbaImage(null, width, height);

    const aspectRatio: f32 = f(width) / f(height);

    for (0..dim(height)) |yi| {
        for (0..dim(width)) |xi| {
            const x: c_int = @intCast(xi);
            const y: c_int = @intCast(yi);
            var nx: f32 = f(x + offsetX) * (scale / f(width));
            var ny: f32 = f(y + offsetY) * (scale / f(height));

            // Apply aspect ratio compensation to wider side
            if (width > height) nx *= aspectRatio else ny /= aspectRatio;

            // Basic perlin noise implementation (not used)
            // Calculate a better perlin noise using fbm (fractal brownian motion)
            // Typical values to start playing with:
            //   lacunarity = ~2.0   -- spacing between successive octaves (use exactly 2.0 for wrapping output)
            //   gain       =  0.5   -- relative weighting applied to each successive octave
            //   octaves    =  6     -- number of "octaves" of noise3() to sum
            var p = stb_perlin_fbm_noise3(nx, ny, 1.0, 2.0, 0.5, 6);

            // Clamp between -1.0f and 1.0f
            if (p < -1.0) p = -1.0;
            if (p > 1.0) p = 1.0;

            // We need to normalize the data from [-1..1] to [0..1]
            const np: f32 = (p + 1.0) / 2.0;

            const intensity: u8 = tuc(np * 255.0);
            pixels[yi * dim(width) + xi] = .{ .r = intensity, .g = intensity, .b = intensity, .a = 255 };
        }
    }

    return rgbaImage(pixels, width, height);
}

// Generate image: cellular algorithm. Bigger tileSize means bigger cells
export fn GenImageCellular(width: c_int, height: c_int, tileSize: c_int) callconv(.c) Image {
    const pixels = allocC(Color, width * height) orelse return rgbaImage(null, width, height);

    const seedsPerRow = @divTrunc(width, tileSize);
    const seedsPerCol = @divTrunc(height, tileSize);
    const seedCount = seedsPerRow * seedsPerCol;

    const seeds = c_allocator.alloc(Vector2, dim(seedCount)) catch {
        cmem.free(pixels.ptr);
        return rgbaImage(null, width, height);
    };
    defer c_allocator.free(seeds);

    for (seeds, 0..) |*seed, n| {
        const i: c_int = @intCast(n);
        const y = @divTrunc(i, seedsPerRow) * tileSize + GetRandomValue(0, tileSize - 1);
        const x = @rem(i, seedsPerRow) * tileSize + GetRandomValue(0, tileSize - 1);
        seed.* = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
    }

    for (0..dim(height)) |yi| {
        const y: c_int = @intCast(yi);
        const tileY = @divTrunc(y, tileSize);

        for (0..dim(width)) |xi| {
            const x: c_int = @intCast(xi);
            const tileX = @divTrunc(x, tileSize);

            var minDistance: f32 = 65536.0; //std::numeric_limits<float>::max();

            // Check all adjacent tiles
            var i: c_int = -1;
            while (i < 2) : (i += 1) {
                if ((tileX + i < 0) or (tileX + i >= seedsPerRow)) continue;

                var j: c_int = -1;
                while (j < 2) : (j += 1) {
                    if ((tileY + j < 0) or (tileY + j >= seedsPerCol)) continue;

                    const neighborSeed = seeds[@intCast((tileY + j) * seedsPerRow + tileX + i)];

                    const dist: f32 = @floatCast(hypot(@floatFromInt(x - ti(neighborSeed.x)), @floatFromInt(y - ti(neighborSeed.y))));
                    minDistance = @floatCast(fmin(minDistance, dist));
                }
            }

            // I made this up, but it seems to give good results at all tile sizes
            const intensity = @min(ti(minDistance * 256.0 / f(tileSize)), 255);

            const intensityUC: u8 = iuc(intensity);
            pixels[yi * dim(width) + xi] = .{ .r = intensityUC, .g = intensityUC, .b = intensityUC, .a = 255 };
        }
    }

    return rgbaImage(pixels, width, height);
}

// Generate image: grayscale image from text data
export fn GenImageText(width: c_int, height: c_int, text: [*c]const u8) callconv(.c) Image {
    const pixels = allocC(u8, width * height);

    if (pixels) |p| {
        if (text != null) {
            const bytes = std.mem.span(text);
            const len = @min(bytes.len, p.len);
            @memcpy(p[0..len], bytes[0..len]);
        }
    }

    return .{
        .data = if (pixels) |p| p.ptr else null,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
    };
}

//------------------------------------------------------------------------------------
// Image manipulation functions
//------------------------------------------------------------------------------------
/// The base-level pixels of an uncompressed `image`, each viewed as a `P`
/// (u8, u16, [4]u8, [4]f32...).
fn pixelData(comptime P: type, image: Image) []P {
    const ptr: [*]P = @ptrCast(@alignCast(image.data));
    return ptr[0..pixelCount(image)];
}

// Copy an image to a new image
export fn ImageCopy(image: Image) callconv(.c) Image {
    var width = image.width;
    var height = image.height;
    var size: c_int = 0;

    // Every mipmap level
    for (0..dim(image.mipmaps)) |_| {
        size += GetPixelDataSize(width, height, image.format);

        width = @max(@divTrunc(width, 2), 1);
        height = @max(@divTrunc(height, 2), 1);
    }

    const data = allocC(u8, size) orelse return .{};
    @memcpy(data, bytesAt(image.data, size));

    return .{ .data = data.ptr, .width = image.width, .height = image.height, .mipmaps = image.mipmaps, .format = image.format };
}

// Create an image from another image piece
export fn ImageFromImage(image: Image, rec: Rectangle) callconv(.c) Image {
    // Security check to avoid program crash
    if ((image.data == null) or (image.width == 0) or (image.height == 0)) return .{};

    if (image.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "IMAGE: Image manipulation not supported for compressed formats");
        return .{};
    }

    // Basic rectangle validation: size smaller than image size
    const valid = (rec.x >= 0) and (rec.y >= 0) and (rec.width > 0) and (rec.height > 0) and
        ((ti(rec.x) + ti(rec.width)) <= image.width) and
        ((ti(rec.y) + ti(rec.height)) <= image.height);
    if (!valid) {
        TraceLog(LOG_WARNING, "IMAGE: ImageFromImage(), rectangle provided not valid");
        return .{};
    }

    const pixelSize = GetPixelDataSize(1, 1, image.format);
    const width = ti(rec.width);
    const height = ti(rec.height);
    const data = allocC(u8, width * height * pixelSize) orelse return .{};

    const src: [*]const u8 = @ptrCast(image.data);
    const rowSize: usize = @intCast(width * pixelSize);
    for (0..dim(height)) |y| {
        const from: usize = @intCast(((@as(c_int, @intCast(y)) + ti(rec.y)) * image.width + ti(rec.x)) * pixelSize);
        @memcpy(data[y * rowSize ..][0..rowSize], src[from..][0..rowSize]);
    }

    return .{ .data = data.ptr, .width = width, .height = height, .mipmaps = 1, .format = image.format };
}

/// One channel of a pixel, normalized, as ImageFromChannel reads it; -1 when
/// the format has no such channel.
fn channelValue(src: [*]const u8, format: c_int, channel: usize) f32 {
    return switch (format) {
        PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA,
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
        PIXELFORMAT_UNCOMPRESSED_R8G8B8,
        => f(src[channel]) / 255.0,
        PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
            const pixel = u16s(src)[0];
            return switch (channel) {
                0 => f((pixel & 0b1111100000000000) >> 11) * (1.0 / 31.0),
                1 => f((pixel & 0b0000011111000000) >> 6) * (1.0 / 31.0),
                2 => f((pixel & 0b0000000000111110) >> 1) * (1.0 / 31.0),
                3 => if ((pixel & 0b0000000000000001) == 0) 0.0 else 1.0,
                else => -1,
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R5G6B5 => {
            const pixel = u16s(src)[0];
            return switch (channel) {
                0 => f((pixel & 0b1111100000000000) >> 11) * (1.0 / 31.0),
                1 => f((pixel & 0b0000011111100000) >> 5) * (1.0 / 63.0),
                2 => f(pixel & 0b0000000000011111) * (1.0 / 31.0),
                else => -1,
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
            const pixel = u16s(src)[0];
            return switch (channel) {
                0 => f((pixel & 0b1111000000000000) >> 12) * (1.0 / 15.0),
                1 => f((pixel & 0b0000111100000000) >> 8) * (1.0 / 15.0),
                2 => f((pixel & 0b0000000011110000) >> 4) * (1.0 / 15.0),
                3 => f(pixel & 0b0000000000001111) * (1.0 / 15.0),
                else => -1,
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R32 => f32s(src)[0],
        PIXELFORMAT_UNCOMPRESSED_R32G32B32, PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => f32s(src)[channel],
        PIXELFORMAT_UNCOMPRESSED_R16 => encode.halfToFloat(u16s(src)[0]),
        PIXELFORMAT_UNCOMPRESSED_R16G16B16, PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => encode.halfToFloat(u16s(src)[channel]),
        else => -1,
    };
}

// Create an image from a selected channel of another image
export fn ImageFromChannel(image: Image, selectedChannel_in: c_int) callconv(.c) Image {
    var selectedChannel = selectedChannel_in;

    if ((image.data == null) or (image.width == 0) or (image.height == 0)) return .{}; // Security check

    // Check selected channel is valid
    if (selectedChannel < 0) {
        TraceLog(LOG_WARNING, "Channel cannot be negative. Setting channel to 0.");
        selectedChannel = 0;
    }

    if (image.format == PIXELFORMAT_UNCOMPRESSED_GRAYSCALE or
        image.format == PIXELFORMAT_UNCOMPRESSED_R32 or
        image.format == PIXELFORMAT_UNCOMPRESSED_R16)
    {
        if (selectedChannel > 0) {
            TraceLog(LOG_WARNING, "This image has only 1 channel. Setting channel to it.");
            selectedChannel = 0;
        }
    } else if (image.format == PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA) {
        if (selectedChannel > 1) {
            TraceLog(LOG_WARNING, "This image has only 2 channels. Setting channel to alpha.");
            selectedChannel = 1;
        }
    } else if (image.format == PIXELFORMAT_UNCOMPRESSED_R5G6B5 or
        image.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8 or
        image.format == PIXELFORMAT_UNCOMPRESSED_R32G32B32 or
        image.format == PIXELFORMAT_UNCOMPRESSED_R16G16B16)
    {
        if (selectedChannel > 2) {
            TraceLog(LOG_WARNING, "This image has only 3 channels. Setting channel to red.");
            selectedChannel = 0;
        }
    }

    // Check for RGBA formats
    if (selectedChannel > 3) {
        TraceLog(LOG_WARNING, "ImageFromChannel supports channels 0 to 3 (RGBA). Setting channel to alpha.");
        selectedChannel = 3;
    }

    const pixels = allocC(u8, image.width * image.height) orelse return .{};

    if (image.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "IMAGE: Pixel data retrieval not supported for compressed image formats");
    } else {
        const src: [*]const u8 = @ptrCast(image.data);
        const size = bytesPerPixel(image.format);
        for (pixels, 0..) |*pixel, i| {
            pixel.* = tuc(channelValue(src + i * size, image.format, @intCast(selectedChannel)) * 255);
        }
    }

    return .{
        .data = pixels.ptr,
        .width = image.width,
        .height = image.height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
    };
}

// Crop an image to area defined by a rectangle
// NOTE: Security checks are performed in case rectangle goes out of bounds
export fn ImageCrop(image: [*c]Image, crop_in: Rectangle) callconv(.c) void {
    var crop = crop_in;

    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    // Security checks to validate crop rectangle
    if (crop.x < 0) {
        crop.width += crop.x;
        crop.x = 0;
    }
    if (crop.y < 0) {
        crop.height += crop.y;
        crop.y = 0;
    }
    if ((crop.x + crop.width) > f(image.*.width)) crop.width = f(image.*.width) - crop.x;
    if ((crop.y + crop.height) > f(image.*.height)) crop.height = f(image.*.height) - crop.y;
    if ((crop.x > f(image.*.width)) or (crop.y > f(image.*.height))) {
        TraceLog(LOG_WARNING, "IMAGE: Failed to crop, rectangle out of bounds");
        return;
    }

    if (image.*.mipmaps > 1) TraceLog(LOG_WARNING, "Image manipulation only applied to base mipmap level");
    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image manipulation not supported for compressed formats");
        return;
    }

    const pixelSize = GetPixelDataSize(1, 1, image.*.format);
    const cropped = allocC(u8, ti(crop.width * crop.height) * pixelSize) orelse return;

    const src: [*]const u8 = @ptrCast(image.*.data);
    const rowSize: usize = @intCast(ti(crop.width) * pixelSize);
    var offset: usize = 0;
    var y = ti(crop.y);
    while (y < ti(crop.y + crop.height)) : (y += 1) {
        const from: usize = @intCast((y * image.*.width + ti(crop.x)) * pixelSize);
        @memcpy(cropped[offset..][0..rowSize], src[from..][0..rowSize]);
        offset += rowSize;
    }

    cmem.free(image.*.data);
    image.*.data = cropped.ptr;
    image.*.width = ti(crop.width);
    image.*.height = ti(crop.height);
}

// Convert image data to desired format
export fn ImageFormat(image: [*c]Image, newFormat: c_int) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if ((newFormat == 0) or (image.*.format == newFormat)) return;

    if ((image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) or (newFormat >= PIXELFORMAT_COMPRESSED_DXT1_RGB)) {
        TraceLog(LOG_WARNING, "IMAGE: Data format is compressed, can not be converted");
        return;
    }

    const pixels = loadNormalized(c_allocator, image.*) catch return; // Supports 8 to 32 bit per channel
    defer c_allocator.free(pixels);

    cmem.free(image.*.data);
    image.*.data = null;
    image.*.format = newFormat;

    // NOTE: A format with no encoder leaves the image without data, as in raylib
    const size = bytesPerPixel(newFormat);
    if (size > 0) {
        const data = cmem.alloc(u8, pixels.len * size) catch return;
        for (pixels, 0..) |pixel, i| writeNormalized(data[i * size ..].ptr, pixel, newFormat);
        image.*.data = data.ptr;
    }

    // In case original image had mipmaps, generate mipmaps for formatted image
    // NOTE: Original mipmaps are replaced by new ones, if custom mipmaps were used, they are lost
    if (image.*.mipmaps > 1) {
        image.*.mipmaps = 1;
        if (image.*.data != null) ImageMipmaps(image);
    }
}

// Create an image from text (default font)
export fn ImageText(text: [*c]const u8, fontSize: c_int, color: Color) callconv(.c) Image {
    const defaultFontSize = 10; // Default Font chars height in pixel
    const size = @max(fontSize, defaultFontSize);
    const spacing = @divTrunc(size, defaultFontSize);

    return ImageTextEx(GetFontDefault(), text, f(size), f(spacing), color);
}

// Create an image from text (custom sprite font)
// WARNING: Module required: rtext
export fn ImageTextEx(font: Font, text: [*c]const u8, fontSize: f32, spacing: f32, tint: Color) callconv(.c) Image {
    if (text == null) return .{};

    const bytes = std.mem.span(text);
    var textOffsetX: c_int = 0; // Image drawing position X
    var textOffsetY: c_int = 0; // Offset between lines (on linebreak '\n')

    // NOTE: Text image is generated at font base size, later scaled to desired font size
    const imSize = MeasureTextEx(font, text, f(font.baseSize), spacing); // WARNING: Module required: rtext
    const textSize = MeasureTextEx(font, text, fontSize, spacing);

    // Create image to store text
    var imText = GenImageColor(ti(imSize.x), ti(imSize.y), BLANK);

    var i: usize = 0;
    while (i < bytes.len) {
        // Get next codepoint from byte string and glyph index in font
        var codepointByteCount: c_int = 0;
        const codepoint = GetCodepointNext(bytes[i..].ptr, &codepointByteCount); // WARNING: Module required: rtext
        const glyph: usize = @intCast(GetGlyphIndex(font, codepoint)); // WARNING: Module required: rtext
        i += @intCast(codepointByteCount);

        if (codepoint == '\n') {
            // NOTE: Fixed line spacing of 1.5 line-height
            // TODO: Support custom line spacing defined by user
            textOffsetY += (font.baseSize + @divTrunc(font.baseSize, 2));
            textOffsetX = 0;
            continue;
        }

        const info = font.glyphs[glyph];
        const rec = font.recs[glyph];

        if ((codepoint != ' ') and (codepoint != '\t')) {
            const dstRec: Rectangle = .{
                .x = f(textOffsetX + info.offsetX),
                .y = f(textOffsetY + info.offsetY),
                .width = rec.width,
                .height = rec.height,
            };
            const srcRec: Rectangle = .{ .x = 0, .y = 0, .width = f(info.image.width), .height = f(info.image.height) };
            ImageDrawImagePro(&imText, info.image, srcRec, dstRec, .{ .x = 0, .y = 0 }, 0.0, tint);
        }

        if (info.advanceX == 0) {
            textOffsetX += ti(rec.width + spacing);
        } else textOffsetX += info.advanceX + ti(spacing);
    }

    // Scale image depending on text size
    if (textSize.y != imSize.y) {
        const scaleFactor = textSize.y / imSize.y;
        TraceLog(LOG_INFO, "IMAGE: Text scaled by factor: %f", @as(f64, scaleFactor));

        // Using nearest-neighbor scaling algorithm for default font
        // TODO: Allow defining the preferred scaling mechanism externally
        if (font.texture.id == GetFontDefault().texture.id) {
            ImageResizeNN(&imText, ti(imSize.x * scaleFactor), ti(imSize.y * scaleFactor));
        } else ImageResize(&imText, ti(imSize.x * scaleFactor), ti(imSize.y * scaleFactor));
    }

    return imText;
}

// Resize and image to new size using Nearest-Neighbor scaling algorithm
export fn ImageResizeNN(image: [*c]Image, newWidth: c_int, newHeight: c_int) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const pixels = loadColors(image.*) orelse return;
    defer cmem.free(pixels.ptr);
    const output = allocC(Color, newWidth * newHeight) orelse return;

    // EDIT: added +1 to account for an early rounding problem
    const xRatio = @divTrunc(image.*.width << 16, newWidth) + 1;
    const yRatio = @divTrunc(image.*.height << 16, newHeight) + 1;

    for (0..dim(newHeight)) |yi| {
        for (0..dim(newWidth)) |xi| {
            const x2 = (@as(c_int, @intCast(xi)) * xRatio) >> 16;
            const y2 = (@as(c_int, @intCast(yi)) * yRatio) >> 16;
            output[yi * dim(newWidth) + xi] = pixels[@intCast((y2 * image.*.width) + x2)];
        }
    }

    image.*.width = newWidth;
    image.*.height = newHeight;
    setColorsKeepFormat(image, output);
}

// Resize and image to new size
// NOTE: Uses stb default scaling filters (both bicubic):
// STBIR_DEFAULT_FILTER_UPSAMPLE    STBIR_FILTER_CATMULLROM
// STBIR_DEFAULT_FILTER_DOWNSAMPLE  STBIR_FILTER_MITCHELL   (high-quality Catmull-Rom)
export fn ImageResize(image: [*c]Image, newWidth: c_int, newHeight: c_int) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    // 8-bit-per-channel formats are resized as they are; their channel count
    // is also stb_image_resize2's pixel layout (STBIR_1CHANNEL...STBIR_RGBA)
    if (stbChannels(image.*.format)) |layout| {
        const pixelSize = GetPixelDataSize(1, 1, image.*.format);
        const output = allocC(u8, newWidth * newHeight * pixelSize) orelse return;

        _ = stbir_resize_uint8_linear(@ptrCast(image.*.data), image.*.width, image.*.height, 0, output.ptr, newWidth, newHeight, 0, layout);

        cmem.free(image.*.data);
        image.*.data = output.ptr;
        image.*.width = newWidth;
        image.*.height = newHeight;
    } else {
        // Get data as Color pixels array to work with it
        const pixels = loadColors(image.*) orelse return;
        defer cmem.free(pixels.ptr);
        const output = allocC(Color, newWidth * newHeight) orelse return;

        // NOTE: Color data is cast to (unsigned char *), there shouldn't been any problem...
        _ = stbir_resize_uint8_linear(@ptrCast(pixels.ptr), image.*.width, image.*.height, 0, @ptrCast(output.ptr), newWidth, newHeight, 0, 4);

        image.*.width = newWidth;
        image.*.height = newHeight;
        setColorsKeepFormat(image, output);
    }
}

// Resize canvas and fill with color
// NOTE: Resize offset is relative to the top-left corner of the original image
export fn ImageResizeCanvas(image: [*c]Image, newWidth: c_int, newHeight: c_int, offsetX: c_int, offsetY: c_int, fill: Color) callconv(.c) void {
    if (!editableBaseLevel(image.*)) return;
    if ((newWidth == image.*.width) and (newHeight == image.*.height)) return;

    var srcRec: Rectangle = .{ .x = 0, .y = 0, .width = f(image.*.width), .height = f(image.*.height) };
    var dstPos: Vector2 = .{ .x = f(offsetX), .y = f(offsetY) };

    if (offsetX < 0) {
        srcRec.x = f(-offsetX);
        srcRec.width += f(offsetX);
        dstPos.x = 0;
    } else if ((offsetX + image.*.width) > newWidth) srcRec.width = f(newWidth - offsetX);

    if (offsetY < 0) {
        srcRec.y = f(-offsetY);
        srcRec.height += f(offsetY);
        dstPos.y = 0;
    } else if ((offsetY + image.*.height) > newHeight) srcRec.height = f(newHeight - offsetY);

    if (f(newWidth) < srcRec.width) srcRec.width = f(newWidth);
    if (f(newHeight) < srcRec.height) srcRec.height = f(newHeight);

    const pixelSize = GetPixelDataSize(1, 1, image.*.format);
    const resized = allocC(u8, newWidth * newHeight * pixelSize) orelse return;
    const size: usize = @intCast(pixelSize);
    const rowSize = dim(newWidth) * size;

    // Fill resized canvas with fill color: set the first pixel in the image
    // format, then repeat it along the first row and that row down the canvas
    SetPixelColor(resized.ptr, fill, image.*.format);
    for (1..dim(newWidth)) |x| @memcpy(resized[x * size ..][0..size], resized[0..size]);
    for (1..dim(newHeight)) |y| @memcpy(resized[y * rowSize ..][0..rowSize], resized[0..rowSize]);

    const src: [*]const u8 = @ptrCast(image.*.data);
    const copySize: usize = @intCast(ti(srcRec.width) * pixelSize);
    var dstOffset: usize = @intCast((ti(dstPos.y) * newWidth + ti(dstPos.x)) * pixelSize);
    for (0..dim(ti(srcRec.height))) |yi| {
        const y: c_int = @intCast(yi);
        const from: usize = @intCast(((y + ti(srcRec.y)) * image.*.width + ti(srcRec.x)) * pixelSize);
        @memcpy(resized[dstOffset..][0..copySize], src[from..][0..copySize]);
        dstOffset += rowSize;
    }

    cmem.free(image.*.data);
    image.*.data = resized.ptr;
    image.*.width = newWidth;
    image.*.height = newHeight;
}

// Convert image to POT (power-of-two)
// NOTE: It could be useful on OpenGL ES 2.0 (RPI, HTML5)
export fn ImageToPOT(image: [*c]Image, fill: Color) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    // Calculate next power-of-two values
    // NOTE: Just add the required amount of pixels at the right and bottom sides of image...
    const potWidth = ti(powf(2, @ceil(logf(f(image.*.width)) / logf(2))));
    const potHeight = ti(powf(2, @ceil(logf(f(image.*.height)) / logf(2))));

    // Check if POT texture generation is required (if texture is not already POT)
    if ((potWidth != image.*.width) or (potHeight != image.*.height)) ImageResizeCanvas(image, potWidth, potHeight, 0, 0, fill);
}

// Crop image depending on alpha value
// NOTE: Threshold is defined as a percentage: 0.0f -> 1.0f
export fn ImageAlphaCrop(image: [*c]Image, threshold: f32) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const crop = GetImageAlphaBorder(image.*, threshold);

    // Crop if rectangle is valid
    if ((ti(crop.width) != 0) and (ti(crop.height) != 0)) ImageCrop(image, crop);
}

// Clear alpha channel to desired color
// NOTE: Threshold defines the alpha limit, 0.0f to 1.0f
export fn ImageAlphaClear(image: [*c]Image, color: Color, threshold: f32) callconv(.c) void {
    if (!editableBaseLevel(image.*)) return;

    switch (image.*.format) {
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
            const thresholdValue: u8 = tuc(threshold * 255.0);
            for (pixelData([2]u8, image.*)) |*pixel| {
                if (pixel[1] <= thresholdValue) pixel.* = .{ color.r, color.a };
            }
        },
        PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
            const thresholdValue: u16 = if (threshold < 0.5) 0 else 1;

            const r: u16 = tuc(@round(f(color.r) * 31.0));
            const g: u16 = tuc(@round(f(color.g) * 31.0));
            const b: u16 = tuc(@round(f(color.b) * 31.0));
            const a: u16 = if (color.a < 128) 0 else 1;

            for (pixelData(u16, image.*)) |*pixel| {
                if ((pixel.* & 0b0000000000000001) <= thresholdValue) pixel.* = (r << 11) | (g << 6) | (b << 1) | a;
            }
        },
        PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
            const thresholdValue: u16 = tuc(threshold * 15.0);

            const r: u16 = tuc(@round(f(color.r) * 15.0));
            const g: u16 = tuc(@round(f(color.g) * 15.0));
            const b: u16 = tuc(@round(f(color.b) * 15.0));
            const a: u16 = tuc(@round(f(color.a) * 15.0));

            for (pixelData(u16, image.*)) |*pixel| {
                if ((pixel.* & 0x000f) <= thresholdValue) pixel.* = (r << 12) | (g << 8) | (b << 4) | a;
            }
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => {
            const thresholdValue: u8 = tuc(threshold * 255.0);
            for (pixelData([4]u8, image.*)) |*pixel| {
                if (pixel[3] <= thresholdValue) pixel.* = .{ color.r, color.g, color.b, color.a };
            }
        },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => {
            for (pixelData([4]f32, image.*)) |*pixel| {
                if (pixel[3] <= threshold) pixel.* = .{ f(color.r) / 255.0, f(color.g) / 255.0, f(color.b) / 255.0, f(color.a) / 255.0 };
            }
        },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => {
            for (pixelData([4]u16, image.*)) |*pixel| {
                if (encode.halfToFloat(pixel[3]) <= threshold) pixel.* = .{
                    encode.floatToHalf(f(color.r) / 255.0),
                    encode.floatToHalf(f(color.g) / 255.0),
                    encode.floatToHalf(f(color.b) / 255.0),
                    encode.floatToHalf(f(color.a) / 255.0),
                };
            }
        },
        else => {},
    }
}

// Apply alpha mask to image
// NOTE 1: Returned image is GRAY_ALPHA (16bit) or RGBA (32bit)
// NOTE 2: alphaMask should be same size as image
export fn ImageAlphaMask(image: [*c]Image, alphaMask: Image) callconv(.c) void {
    if ((image.*.width != alphaMask.width) or (image.*.height != alphaMask.height)) {
        TraceLog(LOG_WARNING, "IMAGE: Alpha mask must be same size as image");
        return;
    }
    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "IMAGE: Alpha mask can not be applied to compressed data formats");
        return;
    }

    // Force mask to be Grayscale
    var mask = ImageCopy(alphaMask);
    defer UnloadImage(mask);
    if (mask.format != PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) ImageFormat(&mask, PIXELFORMAT_UNCOMPRESSED_GRAYSCALE);
    const alphas = pixelData(u8, mask);

    // In case image is only grayscale, we just add alpha channel
    if (image.*.format == PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) {
        const data = allocC([2]u8, image.*.width * image.*.height) orelse return;
        for (data, pixelData(u8, image.*), alphas) |*pixel, gray, alpha| pixel.* = .{ gray, alpha };

        cmem.free(image.*.data);
        image.*.data = data.ptr;
        image.*.format = PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA;
    } else {
        // Convert image to RGBA
        if (image.*.format != PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) ImageFormat(image, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);

        // Apply alpha mask to alpha channel
        for (pixelData([4]u8, image.*), alphas) |*pixel, alpha| pixel[3] = alpha;
    }
}

// Premultiply alpha channel
export fn ImageAlphaPremultiply(image: [*c]Image) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const pixels = loadColors(image.*) orelse return;

    for (pixels) |*pixel| {
        if (pixel.a == 0) {
            pixel.r = 0;
            pixel.g = 0;
            pixel.b = 0;
        } else if (pixel.a < 255) {
            const alpha = f(pixel.a) / 255.0;
            pixel.r = tuc(f(pixel.r) * alpha);
            pixel.g = tuc(f(pixel.g) * alpha);
            pixel.b = tuc(f(pixel.b) * alpha);
        }
    }

    setColorsKeepFormat(image, pixels);
}

const Rgba = @Vector(4, f32);

/// One box-blur pass along a line of `len` pixels starting at `start`, `stride`
/// apart, from `src` into `dst`. Lane-wise float math is the same IEEE
/// arithmetic as raylib's four scalar sums. `quantize` truncates results to
/// whole channel values, as raylib's vertical pass does.
fn boxBlurLine(src: []const Rgba, dst: []Rgba, start: usize, stride: usize, len: c_int, blurSize: c_int, quantize: bool) void {
    var avg: Rgba = @splat(0.0);
    var convolutionSize = blurSize;

    for (0..dim(blurSize)) |i| avg += src[start + i * stride];

    var x: c_int = 0;
    while (x < len) : (x += 1) {
        if (x - blurSize - 1 >= 0) {
            avg -= src[start + @as(usize, @intCast(x - blurSize - 1)) * stride];
            convolutionSize -= 1;
        }
        if (x + blurSize < len) {
            avg += src[start + @as(usize, @intCast(x + blurSize)) * stride];
            convolutionSize += 1;
        }

        const value = avg / @as(Rgba, @splat(f(convolutionSize)));
        dst[start + @as(usize, @intCast(x)) * stride] = if (quantize)
            .{ f(tuc(value[0])), f(tuc(value[1])), f(tuc(value[2])), f(tuc(value[3])) }
        else
            value;
    }
}

// Apply box blur to image
export fn ImageBlurGaussian(image: [*c]Image, blurSize: c_int) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    ImageAlphaPremultiply(image);

    const pixels = loadColors(image.*) orelse return;

    // Loop switches between pixelsCopy1 and pixelsCopy2
    const pixelsCopy1 = c_allocator.alloc(Rgba, pixels.len) catch return cmem.free(pixels.ptr);
    defer c_allocator.free(pixelsCopy1);
    const pixelsCopy2 = c_allocator.alloc(Rgba, pixels.len) catch return cmem.free(pixels.ptr);
    defer c_allocator.free(pixelsCopy2);

    for (pixelsCopy1, pixels) |*copy, pixel| copy.* = .{ f(pixel.r), f(pixel.g), f(pixel.b), f(pixel.a) };

    const width = dim(image.*.width);
    const height = dim(image.*.height);

    // Repeated convolution of rectangular window signal by itself converges to a gaussian distribution
    for (0..GAUSSIAN_BLUR_ITERATIONS) |_| {
        // Horizontal motion blur
        for (0..height) |row| boxBlurLine(pixelsCopy1, pixelsCopy2, row * width, 1, image.*.width, blurSize, false);

        // Vertical motion blur
        for (0..width) |col| boxBlurLine(pixelsCopy2, pixelsCopy1, col, width, image.*.height, blurSize, true);
    }

    // Reverse premultiply
    for (pixels, pixelsCopy1) |*pixel, copy| {
        if (copy[3] == 0.0) {
            pixel.* = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
        } else if (copy[3] <= 255.0) {
            const alpha: f32 = copy[3] / 255.0;
            pixel.r = tuc(fminf(copy[0] / alpha, 255.0));
            pixel.g = tuc(fminf(copy[1] / alpha, 255.0));
            pixel.b = tuc(fminf(copy[2] / alpha, 255.0));
            pixel.a = tuc(copy[3]);
        }
    }

    setColorsKeepFormat(image, pixels);
}

// Apply custom square convolution kernel to image
// NOTE: The convolution kernel matrix is expected to be square
export fn ImageKernelConvolution(image: [*c]Image, kernel: [*c]const f32, kernelSize: c_int) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0) or kernel == null) return;

    const kernelWidth = ti(@sqrt(f(kernelSize)));

    if (kernelWidth * kernelWidth != kernelSize) {
        TraceLog(LOG_WARNING, "IMAGE: Convolution kernel must be square to be applied");
        return;
    }

    const weights = kernel[0..@intCast(kernelSize)];
    const pixels = loadColors(image.*) orelse return;
    defer cmem.free(pixels.ptr);
    const result = allocC(Color, image.*.height * image.*.width) orelse return;

    // An even kernel has one more row/column before its center than after
    const startRange = -@divTrunc(kernelWidth, 2);
    const endRange = if (@rem(kernelWidth, 2) == 0) @divTrunc(kernelWidth, 2) else @divTrunc(kernelWidth, 2) + 1;

    var x: c_int = 0;
    while (x < image.*.height) : (x += 1) {
        var y: c_int = 0;
        while (y < image.*.width) : (y += 1) {
            var rRes: f32 = 0.0;
            var gRes: f32 = 0.0;
            var bRes: f32 = 0.0;
            var aRes: f32 = 0.0;

            var xk: c_int = startRange;
            while (xk < endRange) : (xk += 1) {
                // Clamp neighbour row and column to image bounds, edge pixels are repeated
                const row = std.math.clamp(x + xk, 0, image.*.height - 1);

                var yk: c_int = startRange;
                while (yk < endRange) : (yk += 1) {
                    const col = std.math.clamp(y + yk, 0, image.*.width - 1);

                    const xkabs = xk + @divTrunc(kernelWidth, 2);
                    const ykabs = yk + @divTrunc(kernelWidth, 2);
                    const weight = weights[@intCast(kernelWidth * xkabs + ykabs)];
                    const pixel = pixels[@intCast(image.*.width * row + col)];

                    rRes += f(pixel.r) / 255.0 * weight;
                    gRes += f(pixel.g) / 255.0 * weight;
                    bRes += f(pixel.b) / 255.0 * weight;
                    aRes += f(pixel.a) / 255.0 * weight;
                }
            }

            rRes = std.math.clamp(rRes, 0.0, 1.0);
            gRes = std.math.clamp(gRes, 0.0, 1.0);
            bRes = std.math.clamp(bRes, 0.0, 1.0);
            aRes = std.math.clamp(aRes, 0.0, 1.0);

            result[@intCast(image.*.width * x + y)] = .{
                .r = tuc(rRes * 255.0),
                .g = tuc(gRes * 255.0),
                .b = tuc(bRes * 255.0),
                .a = tuc(aRes * 255.0),
            };
        }
    }

    setColorsKeepFormat(image, result);
}

// Generate all mipmap levels for a provided image
// NOTE 1: Supports POT and NPOT images
// NOTE 2: image.data is scaled to include mipmap levels
// NOTE 3: Mipmaps format is the same as base image
export fn ImageMipmaps(image: [*c]Image) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    var mipCount: c_int = 1; // Required mipmap levels count (including base level)
    var mipWidth = image.*.width; // Base image width
    var mipHeight = image.*.height; // Base image height
    var mipSize = GetPixelDataSize(mipWidth, mipHeight, image.*.format); // Image data size (in bytes)

    // Count mipmap levels required
    while ((mipWidth != 1) or (mipHeight != 1)) {
        if (mipWidth != 1) mipWidth = @divTrunc(mipWidth, 2);
        if (mipHeight != 1) mipHeight = @divTrunc(mipHeight, 2);

        // Security check for NPOT textures
        if (mipWidth < 1) mipWidth = 1;
        if (mipHeight < 1) mipHeight = 1;

        TraceLog(LOG_DEBUG, "IMAGE: Next mipmap level: %i x %i - current size %i", mipWidth, mipHeight, mipSize);

        mipCount += 1;
        mipSize += GetPixelDataSize(mipWidth, mipHeight, image.*.format); // Add mipmap size (in bytes)
    }

    if (image.*.mipmaps >= mipCount) {
        TraceLog(LOG_WARNING, "IMAGE: Mipmaps already available");
        return;
    }

    const data = allocC(u8, mipSize) orelse return;
    // NOTE: Only the base level is kept; existing levels are regenerated below
    const baseSize = GetPixelDataSize(image.*.width, image.*.height, image.*.format);
    @memcpy(data[0..@intCast(baseSize)], bytesAt(image.*.data, baseSize));
    cmem.free(image.*.data);
    image.*.data = data.ptr;

    mipWidth = image.*.width;
    mipHeight = image.*.height;
    mipSize = GetPixelDataSize(mipWidth, mipHeight, image.*.format);
    var offset: usize = 0;

    var imCopy = ImageCopy(image.*);
    defer UnloadImage(imCopy);

    var i: c_int = 1;
    while (i < mipCount) : (i += 1) {
        offset += @intCast(mipSize);

        mipWidth = @max(@divTrunc(mipWidth, 2), 1);
        mipHeight = @max(@divTrunc(mipHeight, 2), 1);

        mipSize = GetPixelDataSize(mipWidth, mipHeight, image.*.format);

        // NOTE: Levels the image claimed to have are skipped (left zeroed), as raylib does
        if (i < image.*.mipmaps) continue;

        TraceLog(LOG_DEBUG, "IMAGE: Generating mipmap level: %i (%i x %i) - size: %i - offset: 0x%x", i, mipWidth, mipHeight, mipSize, data.ptr + offset);

        ImageResize(&imCopy, mipWidth, mipHeight);

        @memcpy(data[offset..][0..@intCast(mipSize)], bytesAt(imCopy.data, mipSize));
    }

    image.*.mipmaps = mipCount;
}

// Dither image data to 16bpp or lower (Floyd-Steinberg dithering)
// NOTE: In case selected bpp do not represent a known 16bit format,
// dithered data is stored in the LSB part of the unsigned short
export fn ImageDither(image: [*c]Image, rBpp: c_int, gBpp: c_int, bBpp: c_int, aBpp: c_int) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "IMAGE: Compressed data formats can not be dithered");
        return;
    }

    if ((rBpp + gBpp + bBpp + aBpp) > 16) {
        TraceLog(LOG_WARNING, "IMAGE: Unsupported dithering bpps (%ibpp), only 16bpp or lower modes supported", (rBpp + gBpp + bBpp + aBpp));
        return;
    }

    const pixels = loadColors(image.*) orelse return;
    defer cmem.free(pixels.ptr);

    cmem.free(image.*.data); // free old image data

    if ((image.*.format != PIXELFORMAT_UNCOMPRESSED_R8G8B8) and (image.*.format != PIXELFORMAT_UNCOMPRESSED_R8G8B8A8)) {
        TraceLog(LOG_WARNING, "IMAGE: Format is already 16bpp or lower, dithering could have no effect");
    }

    // Define new image format, check if desired bpp match internal known format
    if ((rBpp == 5) and (gBpp == 6) and (bBpp == 5) and (aBpp == 0)) {
        image.*.format = PIXELFORMAT_UNCOMPRESSED_R5G6B5;
    } else if ((rBpp == 5) and (gBpp == 5) and (bBpp == 5) and (aBpp == 1)) {
        image.*.format = PIXELFORMAT_UNCOMPRESSED_R5G5B5A1;
    } else if ((rBpp == 4) and (gBpp == 4) and (bBpp == 4) and (aBpp == 4)) {
        image.*.format = PIXELFORMAT_UNCOMPRESSED_R4G4B4A4;
    } else {
        image.*.format = 0;
        TraceLog(LOG_WARNING, "IMAGE: Unsupported dithered OpenGL internal format: %ibpp (R%iG%iB%iA%i)", (rBpp + gBpp + bBpp + aBpp), rBpp, gBpp, bBpp, aBpp);
    }

    // NOTE: We will store the dithered data as unsigned short (16bpp)
    const output = allocC(u16, image.*.width * image.*.height);
    image.*.data = if (output) |o| o.ptr else null;
    const out = output orelse return;

    const w = image.*.width;
    var newPixel = WHITE;

    var y: c_int = 0;
    while (y < image.*.height) : (y += 1) {
        var x: c_int = 0;
        while (x < image.*.width) : (x += 1) {
            const oldPixel = pixels[@intCast(y * w + x)];

            // NOTE: New pixel obtained by bits truncate, it would be better to round values (check ImageFormat())
            // (C shifts the int-promoted channel, so a 0-bit channel shifts by 8 to 0)
            newPixel.r = iuc(@as(c_int, oldPixel.r) >> @intCast(8 - rBpp)); // R bits
            newPixel.g = iuc(@as(c_int, oldPixel.g) >> @intCast(8 - gBpp)); // G bits
            newPixel.b = iuc(@as(c_int, oldPixel.b) >> @intCast(8 - bBpp)); // B bits
            newPixel.a = iuc(@as(c_int, oldPixel.a) >> @intCast(8 - aBpp)); // A bits (not used on dithering)

            // NOTE: Error must be computed between new and old pixel but using same number of bits!
            // We want to know how much color precision we have lost...
            const rError: c_int = @as(c_int, oldPixel.r) - (@as(c_int, newPixel.r) << @intCast(8 - rBpp));
            const gError: c_int = @as(c_int, oldPixel.g) - (@as(c_int, newPixel.g) << @intCast(8 - gBpp));
            const bError: c_int = @as(c_int, oldPixel.b) - (@as(c_int, newPixel.b) << @intCast(8 - bBpp));

            pixels[@intCast(y * w + x)] = newPixel;

            // NOTE: Some cases are out of the array and should be ignored
            if (x < (image.*.width - 1)) {
                spreadError(&pixels[@intCast(y * w + x + 1)], rError, gError, bError, 7.0);
            }

            if ((x > 0) and (y < (image.*.height - 1))) {
                spreadError(&pixels[@intCast((y + 1) * w + x - 1)], rError, gError, bError, 3.0);
            }

            if (y < (image.*.height - 1)) {
                spreadError(&pixels[@intCast((y + 1) * w + x)], rError, gError, bError, 5.0);
            }

            if ((x < (image.*.width - 1)) and (y < (image.*.height - 1))) {
                spreadError(&pixels[@intCast((y + 1) * w + x + 1)], rError, gError, bError, 1.0);
            }

            const rPixel: u16 = newPixel.r;
            const gPixel: u16 = newPixel.g;
            const bPixel: u16 = newPixel.b;
            const aPixel: u16 = newPixel.a;

            out[@intCast(y * w + x)] = (rPixel << @intCast(gBpp + bBpp + aBpp)) | (gPixel << @intCast(bBpp + aBpp)) | (bPixel << @intCast(aBpp)) | aPixel;
        }
    }
}

/// Floyd-Steinberg: adds `weight`/16 of the quantization error to a neighbour,
/// saturating each channel at 0xff.
fn spreadError(pixel: *Color, rError: c_int, gError: c_int, bError: c_int, comptime weight: f32) void {
    pixel.r = iuc(@min(@as(c_int, pixel.r) + ti(f(rError) * weight / 16), 0xff));
    pixel.g = iuc(@min(@as(c_int, pixel.g) + ti(f(gError) * weight / 16), 0xff));
    pixel.b = iuc(@min(@as(c_int, pixel.b) + ti(f(bError) * weight / 16), 0xff));
}

/// The size in bytes of one pixel of an uncompressed `image`, and a new C-heap
/// buffer for all its pixels: the start of every pixel-moving operation.
fn movePixels(image: Image) ?struct { size: usize, src: []const u8, dst: []u8 } {
    const pixelSize = GetPixelDataSize(1, 1, image.format);
    const total = image.width * image.height * pixelSize;
    const dst = allocC(u8, total) orelse return null;
    return .{ .size = @intCast(pixelSize), .src = bytesAt(image.data, total), .dst = dst };
}

/// The checks that open every operation on the base level of an image:
/// whether it has pixels, warning for mipmaps and refusing compressed data.
fn editableBaseLevel(image: Image) bool {
    // Security check to avoid program crash
    if ((image.data == null) or (image.width == 0) or (image.height == 0)) return false;

    if (image.mipmaps > 1) TraceLog(LOG_WARNING, "Image manipulation only applied to base mipmap level");
    if (image.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image manipulation not supported for compressed formats");
        return false;
    }
    return true;
}

// Flip image vertically
export fn ImageFlipVertical(image: [*c]Image) callconv(.c) void {
    if (!editableBaseLevel(image.*)) return;

    const move = movePixels(image.*) orelse return;
    const rowSize = dim(image.*.width) * move.size;
    const height = dim(image.*.height);
    for (0..height) |y| {
        @memcpy(move.dst[y * rowSize ..][0..rowSize], move.src[(height - 1 - y) * rowSize ..][0..rowSize]);
    }

    cmem.free(image.*.data);
    image.*.data = move.dst.ptr;
}

// Flip image horizontally
export fn ImageFlipHorizontal(image: [*c]Image) callconv(.c) void {
    if (!editableBaseLevel(image.*)) return;

    const move = movePixels(image.*) orelse return;
    const width = dim(image.*.width);
    const n = move.size;
    for (0..dim(image.*.height)) |y| {
        for (0..width) |x| {
            @memcpy(move.dst[(y * width + x) * n ..][0..n], move.src[(y * width + (width - 1 - x)) * n ..][0..n]);
        }
    }

    cmem.free(image.*.data);
    image.*.data = move.dst.ptr;
}

// Rotate image in degrees
export fn ImageRotate(image: [*c]Image, degrees: c_int) callconv(.c) void {
    if (!editableBaseLevel(image.*)) return;

    const rad: f32 = f(degrees) * PI / 180.0;
    const sinRadius = sinf(rad);
    const cosRadius = cosf(rad);

    const width = ti(@abs(f(image.*.width) * cosRadius) + @abs(f(image.*.height) * sinRadius));
    const height = ti(@abs(f(image.*.height) * cosRadius) + @abs(f(image.*.width) * sinRadius));

    const pixelSize = GetPixelDataSize(1, 1, image.*.format);
    const rotated = allocC(u8, GetPixelDataSize(width, height, image.*.format)) orelse return;
    const src: [*]const u8 = @ptrCast(image.*.data);
    const iw = image.*.width;

    var y: c_int = 0;
    while (y < height) : (y += 1) {
        var x: c_int = 0;
        while (x < width) : (x += 1) {
            const oldX = ((f(x) - f(width) / 2.0) * cosRadius + (f(y) - f(height) / 2.0) * sinRadius) + f(image.*.width) / 2.0;
            const oldY = ((f(y) - f(height) / 2.0) * cosRadius - (f(x) - f(width) / 2.0) * sinRadius) + f(image.*.height) / 2.0;

            if ((oldX >= 0) and (oldX < f(image.*.width)) and (oldY >= 0) and (oldY < f(image.*.height))) {
                const x1 = ti(@floor(oldX));
                const y1 = ti(@floor(oldY));
                const x2 = @min(x1 + 1, image.*.width - 1);
                const y2 = @min(y1 + 1, image.*.height - 1);

                const px = oldX - f(x1);
                const py = oldY - f(y1);

                var i: c_int = 0;
                while (i < pixelSize) : (i += 1) {
                    const f1: f32 = f(src[@intCast((y1 * iw + x1) * pixelSize + i)]);
                    const f2: f32 = f(src[@intCast((y1 * iw + x2) * pixelSize + i)]);
                    const f3: f32 = f(src[@intCast((y2 * iw + x1) * pixelSize + i)]);
                    const f4: f32 = f(src[@intCast((y2 * iw + x2) * pixelSize + i)]);

                    const val = f1 * (1 - px) * (1 - py) + f2 * px * (1 - py) + f3 * (1 - px) * py + f4 * px * py;

                    rotated[@intCast((y * width + x) * pixelSize + i)] = tuc(val);
                }
            }
        }
    }

    cmem.free(image.*.data);
    image.*.data = rotated.ptr;
    image.*.width = width;
    image.*.height = height;
}

// Rotate image clockwise 90deg
export fn ImageRotateCW(image: [*c]Image) callconv(.c) void {
    if (!editableBaseLevel(image.*)) return;

    const move = movePixels(image.*) orelse return;
    const width = dim(image.*.width);
    const height = dim(image.*.height);
    const n = move.size;
    for (0..height) |y| {
        for (0..width) |x| {
            @memcpy(move.dst[(x * height + (height - y - 1)) * n ..][0..n], move.src[(y * width + x) * n ..][0..n]);
        }
    }

    cmem.free(image.*.data);
    image.*.data = move.dst.ptr;
    std.mem.swap(c_int, &image.*.width, &image.*.height);
}

// Rotate image counter-clockwise 90deg
export fn ImageRotateCCW(image: [*c]Image) callconv(.c) void {
    if (!editableBaseLevel(image.*)) return;

    const move = movePixels(image.*) orelse return;
    const width = dim(image.*.width);
    const height = dim(image.*.height);
    const n = move.size;
    for (0..height) |y| {
        for (0..width) |x| {
            @memcpy(move.dst[(x * height + y) * n ..][0..n], move.src[(y * width + (width - x - 1)) * n ..][0..n]);
        }
    }

    cmem.free(image.*.data);
    image.*.data = move.dst.ptr;
    std.mem.swap(c_int, &image.*.width, &image.*.height);
}

// Modify image color: tint
export fn ImageColorTint(image: [*c]Image, color: Color) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const pixels = loadColors(image.*) orelse return;
    for (pixels) |*pixel| pixel.* = ColorTint(pixel.*, color);
    setColorsKeepFormat(image, pixels);
}

// Modify image color: invert
export fn ImageColorInvert(image: [*c]Image) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const pixels = loadColors(image.*) orelse return;
    for (pixels) |*pixel| {
        pixel.r = 255 - pixel.r;
        pixel.g = 255 - pixel.g;
        pixel.b = 255 - pixel.b;
    }
    setColorsKeepFormat(image, pixels);
}

// Modify image color: grayscale
export fn ImageColorGrayscale(image: [*c]Image) callconv(.c) void {
    ImageFormat(image, PIXELFORMAT_UNCOMPRESSED_GRAYSCALE);
}

/// One channel with contrast `factor` applied around mid-gray, clamped.
fn contrastChannel(channel: u8, factor: f32) u8 {
    var p: f32 = f(channel) / 255.0;
    p -= 0.5;
    p *= factor;
    p += 0.5;
    p *= 255;
    if (p < 0) p = 0;
    if (p > 255) p = 255;
    return tuc(p);
}

// Modify image color: contrast
// NOTE: Contrast values between -100 and 100
export fn ImageColorContrast(image: [*c]Image, contrast: c_int) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    var factor: f32 = f(100 + std.math.clamp(contrast, -100, 100)) / 100.0;
    factor *= factor;

    const pixels = loadColors(image.*) orelse return;
    for (pixels) |*pixel| {
        pixel.r = contrastChannel(pixel.r, factor);
        pixel.g = contrastChannel(pixel.g, factor);
        pixel.b = contrastChannel(pixel.b, factor);
    }
    setColorsKeepFormat(image, pixels);
}

/// One channel shifted by `brightness`. NOTE: raylib clamps a negative result
/// to 1, not 0 (deliberate).
fn brightenChannel(channel: u8, brightness: c_int) u8 {
    const value = @as(c_int, channel) + brightness;
    if (value < 0) return 1;
    return iuc(@min(value, 255));
}

// Modify image color: brightness
// NOTE: Brightness values between -255 and 255
export fn ImageColorBrightness(image: [*c]Image, brightness: c_int) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const amount = std.math.clamp(brightness, -255, 255);

    const pixels = loadColors(image.*) orelse return;
    for (pixels) |*pixel| {
        pixel.r = brightenChannel(pixel.r, amount);
        pixel.g = brightenChannel(pixel.g, amount);
        pixel.b = brightenChannel(pixel.b, amount);
    }
    setColorsKeepFormat(image, pixels);
}

// Modify image color: replace color
export fn ImageColorReplace(image: [*c]Image, color: Color, replace: Color) callconv(.c) void {
    // Security check to avoid program crash
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const pixels = loadColors(image.*) orelse return;
    for (pixels) |*pixel| {
        if (ColorIsEqual(pixel.*, color)) pixel.* = replace;
    }

    const format = image.*.format;
    cmem.free(image.*.data);

    image.*.data = pixels.ptr;
    image.*.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

    // NOTE: Only formats without alpha are converted back; the others stay
    // R8G8B8A8 (raylib behaviour)
    if ((format == PIXELFORMAT_UNCOMPRESSED_R8G8B8) or
        (format == PIXELFORMAT_UNCOMPRESSED_R5G6B5) or
        (format == PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) or
        (format == PIXELFORMAT_UNCOMPRESSED_R32G32B32) or
        (format == PIXELFORMAT_UNCOMPRESSED_R16G16B16) or
        (format == PIXELFORMAT_COMPRESSED_DXT1_RGB) or
        (format == PIXELFORMAT_COMPRESSED_ETC1_RGB) or
        (format == PIXELFORMAT_COMPRESSED_ETC2_RGB) or
        (format == PIXELFORMAT_COMPRESSED_PVRT_RGB)) ImageFormat(image, format);
}

// Load color data from image as a Color array (RGBA - 32bit)
// NOTE: Memory allocated should be freed using UnloadImageColors();
export fn LoadImageColors(image: Image) callconv(.c) [*c]Color {
    return if (loadColors(image)) |pixels| pixels.ptr else null;
}

// Load colors palette from image as a Color array (RGBA - 32bit)
// NOTE: Memory allocated should be freed using UnloadImagePalette()
export fn LoadImagePalette(image: Image, maxPaletteSize: c_int, colorCount: [*c]c_int) callconv(.c) [*c]Color {
    colorCount.* = 0;
    const pixels = loadColors(image) orelse return null;
    defer cmem.free(pixels.ptr);

    const palette = allocC(Color, maxPaletteSize) orelse return null;
    @memset(palette, BLANK);

    var count: usize = 0;
    for (pixels) |pixel| {
        if (pixel.a == 0) continue;

        // NOTE: Searches the whole palette, unused BLANK entries included
        const known = for (palette) |entry| {
            if (ColorIsEqual(entry, pixel)) break true;
        } else false;
        if (known) continue;

        palette[count] = pixel;
        count += 1;

        if (count >= palette.len) {
            TraceLog(LOG_WARNING, "IMAGE: Palette is greater than %i colors", maxPaletteSize);
            break;
        }
    }

    colorCount.* = @intCast(count);
    return palette.ptr;
}

// Unload color data loaded with LoadImageColors()
export fn UnloadImageColors(colors: [*c]Color) callconv(.c) void {
    cmem.free(colors);
}

// Unload colors palette loaded with LoadImagePalette()
export fn UnloadImagePalette(colors: [*c]Color) callconv(.c) void {
    cmem.free(colors);
}

// Get image alpha border rectangle
// NOTE: Threshold is defined as a percentage: 0.0f -> 1.0f
export fn GetImageAlphaBorder(image: Image, threshold: f32) callconv(.c) Rectangle {
    const pixels = loadColors(image) orelse return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    defer cmem.free(pixels.ptr);

    var xMin: c_int = 65536; // Define a big enough number
    var xMax: c_int = 0;
    var yMin: c_int = 65536;
    var yMax: c_int = 0;

    var y: c_int = 0;
    while (y < image.height) : (y += 1) {
        var x: c_int = 0;
        while (x < image.width) : (x += 1) {
            if (pixels[@intCast(y * image.width + x)].a > tuc(threshold * 255.0)) {
                if (x < xMin) xMin = x;
                if (x > xMax) xMax = x;
                if (y < yMin) yMin = y;
                if (y > yMax) yMax = y;
            }
        }
    }

    // Check for empty blank image
    if ((xMin == 65536) or (xMax == 65536)) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };

    return .{ .x = f(xMin), .y = f(yMin), .width = f((xMax + 1) - xMin), .height = f((yMax + 1) - yMin) };
}

// Get image pixel color at (x, y) position
export fn GetImageColor(image: Image, x: c_int, y: c_int) callconv(.c) Color {
    if ((x < 0) or (x >= image.width) or (y < 0) or (y >= image.height)) {
        TraceLog(LOG_WARNING, "Requested image pixel (%i, %i) out of bounds", x, y);
        return BLANK;
    }

    const src: [*]const u8 = @ptrCast(image.data);
    const i: usize = @intCast(y * image.width + x);
    return readColor(src + i * bytesPerPixel(image.format), image.format) orelse {
        TraceLog(LOG_WARNING, "Compressed image format does not support color reading");
        return BLANK;
    };
}

//------------------------------------------------------------------------------------
// Image drawing functions
//------------------------------------------------------------------------------------
// Clear image background with given color
export fn ImageClearBackground(dst: [*c]Image, color: Color) callconv(.c) void {
    // Security check to avoid program crash
    if ((dst.*.data == null) or (dst.*.width == 0) or (dst.*.height == 0)) return;

    // Fill in first pixel based on image format
    // NOTE: We could use ImageDrawPixel() but this is faster
    ImageDrawPixel(dst, 0, 0, color);

    const pixelSize: usize = @intCast(GetPixelDataSize(1, 1, dst.*.format));
    const totalPixels = pixelCount(dst.*);
    const data = bytesAt(dst.*.data, @intCast(totalPixels * pixelSize));

    // Repeat the first pixel into the rest of the image, doubling the filled span each time
    var filled: usize = 1;
    while (filled < totalPixels) : (filled *= 2) {
        const n = @min(filled, totalPixels - filled) * pixelSize;
        @memcpy(data[filled * pixelSize ..][0..n], data[0..n]);
    }
}

// Draw pixel within an image
// NOTE: Compressed image formats not supported
export fn ImageDrawPixel(dst: [*c]Image, x: c_int, y: c_int, color: Color) callconv(.c) void {
    // Security check to avoid program crash
    if ((dst.*.data == null) or (x < 0) or (x >= dst.*.width) or (y < 0) or (y >= dst.*.height)) return;

    const data: [*]u8 = @ptrCast(dst.*.data);
    const i: usize = @intCast(y * dst.*.width + x);
    writeColor(data + i * bytesPerPixel(dst.*.format), color, dst.*.format);
}

// Draw pixel within an image (Vector version)
export fn ImageDrawPixelV(dst: [*c]Image, position: Vector2, color: Color) callconv(.c) void {
    ImageDrawPixel(dst, ti(position.x), ti(position.y), color);
}

// Draw line within an image
export fn ImageDrawLine(dst: [*c]Image, startPosX: c_int, startPosY: c_int, endPosX: c_int, endPosY: c_int, color: Color) callconv(.c) void {
    var shortLen = endPosY - startPosY;
    var longLen = endPosX - startPosX;
    var yLonger = false;

    if (@abs(shortLen) > @abs(longLen)) {
        const temp = shortLen;
        shortLen = longLen;
        longLen = temp;
        yLonger = true;
    }

    var endVal = longLen + 1;
    var sgnInc: c_int = 1;

    if (longLen < 0) {
        longLen = -longLen;
        sgnInc = -1;
        endVal -= 2;
    }

    const decInc: c_int = if (longLen == 0) 0 else @divTrunc(shortLen << 16, longLen);

    if (yLonger) {
        var i: c_int = 0;
        var j: c_int = (1 << 15);
        while (i != endVal) : ({
            i += sgnInc;
            j += decInc;
        }) {
            ImageDrawPixel(dst, startPosX + (j >> 16), startPosY + i, color);
        }
    } else {
        var i: c_int = 0;
        var j: c_int = (1 << 15);
        while (i != endVal) : ({
            i += sgnInc;
            j += decInc;
        }) {
            ImageDrawPixel(dst, startPosX + i, startPosY + (j >> 16), color);
        }
    }
}

// Draw line within an image (Vector version)
export fn ImageDrawLineV(dst: [*c]Image, start: Vector2, end: Vector2, color: Color) callconv(.c) void {
    const x1 = ti(start.x + 0.5);
    const y1 = ti(start.y + 0.5);
    const x2 = ti(end.x + 0.5);
    const y2 = ti(end.y + 0.5);

    ImageDrawLine(dst, x1, y1, x2, y2, color);
}

// Draw a line defining thickness within an image
export fn ImageDrawLineEx(dst: [*c]Image, start: Vector2, end: Vector2, thick: c_int, color: Color) callconv(.c) void {
    const x1 = ti(start.x + 0.5);
    const y1 = ti(start.y + 0.5);
    const x2 = ti(end.x + 0.5);
    const y2 = ti(end.y + 0.5);

    const dx = x2 - x1;
    const dy = y2 - y1;

    if ((dx != 0) and (@abs(@divTrunc(dy, dx)) < 1)) {
        const wy = thick - 1;

        var i: c_int = 0;
        while (i <= @divTrunc(wy + 1, 2)) : (i += 1) {
            ImageDrawLine(dst, x1, y1 + i, x2, y2 + i, color);
        }

        i = 1;
        while (i <= @divTrunc(wy, 2)) : (i += 1) {
            ImageDrawLine(dst, x1, y1 - i, x2, y2 - i, color);
        }
    } else if (dy != 0) {
        const wx = thick - 1;

        var i: c_int = 0;
        while (i <= @divTrunc(wx + 1, 2)) : (i += 1) {
            ImageDrawLine(dst, x1 + i, y1, x2 + i, y2, color);
        }

        i = 1;
        while (i <= @divTrunc(wx, 2)) : (i += 1) {
            ImageDrawLine(dst, x1 - i, y1, x2 - i, y2, color);
        }
    }
}

// Draw a lines sequence within an image
export fn ImageDrawLineStrip(dst: [*c]Image, points: [*c]const Vector2, pointCount: c_int, color: Color) callconv(.c) void {
    if (pointCount < 2) return;
    const pts = points[0..@intCast(pointCount)];
    for (pts[0 .. pts.len - 1], pts[1..]) |start, end| ImageDrawLineV(dst, start, end, color);
}

// Draw triangle within an image
export fn ImageDrawTriangle(dst: [*c]Image, v1: Vector2, v2: Vector2, v3: Vector2, color: Color) callconv(.c) void {
    var xMin = ti(if (v1.x < v2.x) (if (v1.x < v3.x) v1.x else v3.x) else (if (v2.x < v3.x) v2.x else v3.x));
    var yMin = ti(if (v1.y < v2.y) (if (v1.y < v3.y) v1.y else v3.y) else (if (v2.y < v3.y) v2.y else v3.y));
    var xMax = ti(if (v1.x > v2.x) (if (v1.x > v3.x) v1.x else v3.x) else (if (v2.x > v3.x) v2.x else v3.x));
    var yMax = ti(if (v1.y > v2.y) (if (v1.y > v3.y) v1.y else v3.y) else (if (v2.y > v3.y) v2.y else v3.y));

    if (xMin < 0) xMin = 0;
    if (yMin < 0) yMin = 0;
    if (xMax > dst.*.width) xMax = dst.*.width;
    if (yMax > dst.*.height) yMax = dst.*.height;

    const signedArea = (v2.x - v1.x) * (v3.y - v1.y) - (v3.x - v1.x) * (v2.y - v1.y);
    const isBackFace = (signedArea > 0);

    var w1XStep = ti(v3.y - v2.y);
    var w1YStep = ti(v2.x - v3.x);
    var w2XStep = ti(v1.y - v3.y);
    var w2YStep = ti(v3.x - v1.x);
    var w3XStep = ti(v2.y - v1.y);
    var w3YStep = ti(v1.x - v2.x);

    if (isBackFace) {
        w1XStep = -w1XStep;
        w1YStep = -w1YStep;
        w2XStep = -w2XStep;
        w2YStep = -w2YStep;
        w3XStep = -w3XStep;
        w3YStep = -w3YStep;
    }

    var w1Row = ti((@as(f32, @floatFromInt(xMin)) - v2.x) * @as(f32, @floatFromInt(w1XStep)) + @as(f32, @floatFromInt(w1YStep)) * (@as(f32, @floatFromInt(yMin)) - v2.y));
    var w2Row = ti((@as(f32, @floatFromInt(xMin)) - v3.x) * @as(f32, @floatFromInt(w2XStep)) + @as(f32, @floatFromInt(w2YStep)) * (@as(f32, @floatFromInt(yMin)) - v3.y));
    var w3Row = ti((@as(f32, @floatFromInt(xMin)) - v1.x) * @as(f32, @floatFromInt(w3XStep)) + @as(f32, @floatFromInt(w3YStep)) * (@as(f32, @floatFromInt(yMin)) - v1.y));

    var y: c_int = yMin;
    while (y <= yMax) : (y += 1) {
        var w1 = w1Row;
        var w2 = w2Row;
        var w3 = w3Row;

        var x: c_int = xMin;
        while (x <= xMax) : (x += 1) {
            if ((w1 | w2 | w3) >= 0) ImageDrawPixel(dst, x, y, color);

            w1 += w1XStep;
            w2 += w2XStep;
            w3 += w3XStep;
        }

        w1Row += w1YStep;
        w2Row += w2YStep;
        w3Row += w3YStep;
    }
}

// Draw triangle with interpolated colors within an image
export fn ImageDrawTriangleGradient(dst: [*c]Image, v1: Vector2, v2: Vector2, v3: Vector2, c1: Color, c2: Color, c3: Color) callconv(.c) void {
    var xMin = ti(if (v1.x < v2.x) (if (v1.x < v3.x) v1.x else v3.x) else (if (v2.x < v3.x) v2.x else v3.x));
    var yMin = ti(if (v1.y < v2.y) (if (v1.y < v3.y) v1.y else v3.y) else (if (v2.y < v3.y) v2.y else v3.y));
    var xMax = ti(if (v1.x > v2.x) (if (v1.x > v3.x) v1.x else v3.x) else (if (v2.x > v3.x) v2.x else v3.x));
    var yMax = ti(if (v1.y > v2.y) (if (v1.y > v3.y) v1.y else v3.y) else (if (v2.y > v3.y) v2.y else v3.y));

    if (xMin < 0) xMin = 0;
    if (yMin < 0) yMin = 0;
    if (xMax > dst.*.width) xMax = dst.*.width;
    if (yMax > dst.*.height) yMax = dst.*.height;

    const signedArea = (v2.x - v1.x) * (v3.y - v1.y) - (v3.x - v1.x) * (v2.y - v1.y);
    const isBackFace = (signedArea > 0);

    var w1XStep = ti(v3.y - v2.y);
    var w1YStep = ti(v2.x - v3.x);
    var w2XStep = ti(v1.y - v3.y);
    var w2YStep = ti(v3.x - v1.x);
    var w3XStep = ti(v2.y - v1.y);
    var w3YStep = ti(v1.x - v2.x);

    if (isBackFace) {
        w1XStep = -w1XStep;
        w1YStep = -w1YStep;
        w2XStep = -w2XStep;
        w2YStep = -w2YStep;
        w3XStep = -w3XStep;
        w3YStep = -w3YStep;
    }

    var w1Row = ti((@as(f32, @floatFromInt(xMin)) - v2.x) * @as(f32, @floatFromInt(w1XStep)) + @as(f32, @floatFromInt(w1YStep)) * (@as(f32, @floatFromInt(yMin)) - v2.y));
    var w2Row = ti((@as(f32, @floatFromInt(xMin)) - v3.x) * @as(f32, @floatFromInt(w2XStep)) + @as(f32, @floatFromInt(w2YStep)) * (@as(f32, @floatFromInt(yMin)) - v3.y));
    var w3Row = ti((@as(f32, @floatFromInt(xMin)) - v1.x) * @as(f32, @floatFromInt(w3XStep)) + @as(f32, @floatFromInt(w3YStep)) * (@as(f32, @floatFromInt(yMin)) - v1.y));

    const wInvSum: f32 = 255.0 / @as(f32, @floatFromInt(w1Row + w2Row + w3Row));

    var y: c_int = yMin;
    while (y <= yMax) : (y += 1) {
        var w1 = w1Row;
        var w2 = w2Row;
        var w3 = w3Row;

        var x: c_int = xMin;
        while (x <= xMax) : (x += 1) {
            if ((w1 | w2 | w3) >= 0) {
                const aW1: u8 = tuc(@as(f32, @floatFromInt(w1)) * wInvSum);
                const aW2: u8 = tuc(@as(f32, @floatFromInt(w2)) * wInvSum);
                const aW3: u8 = tuc(@as(f32, @floatFromInt(w3)) * wInvSum);

                var finalColor: Color = BLANK;
                finalColor.r = iuc(@divTrunc(@as(c_int, c1.r) * @as(c_int, aW1) + @as(c_int, c2.r) * @as(c_int, aW2) + @as(c_int, c3.r) * @as(c_int, aW3), 255));
                finalColor.g = iuc(@divTrunc(@as(c_int, c1.g) * @as(c_int, aW1) + @as(c_int, c2.g) * @as(c_int, aW2) + @as(c_int, c3.g) * @as(c_int, aW3), 255));
                finalColor.b = iuc(@divTrunc(@as(c_int, c1.b) * @as(c_int, aW1) + @as(c_int, c2.b) * @as(c_int, aW2) + @as(c_int, c3.b) * @as(c_int, aW3), 255));
                finalColor.a = iuc(@divTrunc(@as(c_int, c1.a) * @as(c_int, aW1) + @as(c_int, c2.a) * @as(c_int, aW2) + @as(c_int, c3.a) * @as(c_int, aW3), 255));

                ImageDrawPixel(dst, x, y, finalColor);
            }

            w1 += w1XStep;
            w2 += w2XStep;
            w3 += w3XStep;
        }

        w1Row += w1YStep;
        w2Row += w2YStep;
        w3Row += w3YStep;
    }
}

// Draw triangle outline within an image
export fn ImageDrawTriangleLines(dst: [*c]Image, v1: Vector2, v2: Vector2, v3: Vector2, color: Color) callconv(.c) void {
    ImageDrawLine(dst, ti(v1.x), ti(v1.y), ti(v2.x), ti(v2.y), color);
    ImageDrawLine(dst, ti(v2.x), ti(v2.y), ti(v3.x), ti(v3.y), color);
    ImageDrawLine(dst, ti(v3.x), ti(v3.y), ti(v1.x), ti(v1.y), color);
}

// Draw a triangle fan defined by points within an image (first vertex is the center)
export fn ImageDrawTriangleFan(dst: [*c]Image, points: [*c]const Vector2, pointCount: c_int, color: Color) callconv(.c) void {
    if (pointCount < 3) return;
    const pts = points[0..@intCast(pointCount)];
    for (pts[1 .. pts.len - 1], pts[2..]) |b, c| ImageDrawTriangle(dst, pts[0], b, c, color);
}

// Draw a triangle strip defined by points within an image
export fn ImageDrawTriangleStrip(dst: [*c]Image, points: [*c]const Vector2, pointCount: c_int, color: Color) callconv(.c) void {
    if (pointCount < 3) return;
    const pts = points[0..@intCast(pointCount)];
    // Alternate the winding so every triangle faces the same way
    for (2..pts.len) |i| {
        if (i % 2 == 0) {
            ImageDrawTriangle(dst, pts[i], pts[i - 2], pts[i - 1], color);
        } else ImageDrawTriangle(dst, pts[i], pts[i - 1], pts[i - 2], color);
    }
}

// Draw rectangle within an image
export fn ImageDrawRectangle(dst: [*c]Image, posX: c_int, posY: c_int, width: c_int, height: c_int, color: Color) callconv(.c) void {
    ImageDrawRectangleRec(dst, .{ .x = @floatFromInt(posX), .y = @floatFromInt(posY), .width = @floatFromInt(width), .height = @floatFromInt(height) }, color);
}

// Draw rectangle within an image (Vector version)
export fn ImageDrawRectangleV(dst: [*c]Image, position: Vector2, size: Vector2, color: Color) callconv(.c) void {
    ImageDrawRectangle(dst, ti(position.x), ti(position.y), ti(size.x), ti(size.y), color);
}

// Draw rectangle within an image
export fn ImageDrawRectangleRec(dst: [*c]Image, rec_in: Rectangle, color: Color) callconv(.c) void {
    var rec = rec_in;
    if ((dst.*.data == null) or (dst.*.width == 0) or (dst.*.height == 0)) return;

    if (rec.x < 0) {
        rec.width += rec.x;
        rec.x = 0;
    }
    if (rec.y < 0) {
        rec.height += rec.y;
        rec.y = 0;
    }
    if (rec.width < 0) rec.width = 0;
    if (rec.height < 0) rec.height = 0;

    if ((rec.x + rec.width) >= @as(f32, @floatFromInt(dst.*.width))) rec.width = @as(f32, @floatFromInt(dst.*.width)) - rec.x;
    if ((rec.y + rec.height) >= @as(f32, @floatFromInt(dst.*.height))) rec.height = @as(f32, @floatFromInt(dst.*.height)) - rec.y;

    if ((rec.x >= @as(f32, @floatFromInt(dst.*.width))) or (rec.y >= @as(f32, @floatFromInt(dst.*.height)))) return;
    if (((rec.x + rec.width) <= 0) or (rec.y + rec.height <= 0)) return;

    const sy = ti(rec.y);
    const sx = ti(rec.x);

    const pixelSize = GetPixelDataSize(1, 1, dst.*.format);

    // Fill in the first pixel of the first row based on image format
    ImageDrawPixel(dst, sx, sy, color);

    const data: [*]u8 = @ptrCast(dst.*.data);
    const first = data + @as(usize, @intCast(((sy * dst.*.width) + sx) * pixelSize));
    const size: usize = @intCast(pixelSize);
    const width = dim(ti(rec.width));

    // Repeat the first pixel through the first row, doubling the filled span each time
    var filled: usize = 1;
    while (filled < width) : (filled *= 2) {
        const n = @min(filled, width - filled) * size;
        @memcpy(first[filled * size ..][0..n], first[0..n]);
    }

    // Repeat the first row down the rectangle
    const rowSize = size * width;
    const stride = dim(dst.*.width) * size;
    for (1..dim(ti(rec.height))) |y| @memcpy(first[y * stride ..][0..rowSize], first[0..rowSize]);
}

// Bounding box of a rectangle rotated around `pivot`; corners are given relative to the pivot.
const Bounds = struct { x0: c_int, y0: c_int, x1: c_int, y1: c_int };

fn rotatedBounds(cornersX: [4]f32, cornersY: [4]f32, cosA: f32, sinA: f32, pivot: Vector2, width: c_int, height: c_int) ?Bounds {
    var minX: f32 = 65536;
    var minY: f32 = 65536;
    var maxX: f32 = -65536;
    var maxY: f32 = -65536;

    for (cornersX, cornersY) |cx, cy| {
        const rx = (cx * cosA - cy * sinA) + pivot.x;
        const ry = (cx * sinA + cy * cosA) + pivot.y;

        if (rx < minX) minX = rx;
        if (ry < minY) minY = ry;
        if (rx > maxX) maxX = rx;
        if (ry > maxY) maxY = ry;
    }

    return clampBounds(ti(@floor(minX)), ti(@floor(minY)), ti(@ceil(maxX)), ti(@ceil(maxY)), width, height);
}

// Limit integer pixel bounds to the image; null when nothing remains to draw.
fn clampBounds(x0: c_int, y0: c_int, x1: c_int, y1: c_int, width: c_int, height: c_int) ?Bounds {
    const b = Bounds{ .x0 = @max(x0, 0), .y0 = @max(y0, 0), .x1 = @min(x1, width), .y1 = @min(y1, height) };
    if ((b.x0 >= b.x1) or (b.y0 >= b.y1)) return null;
    return b;
}

// Draw a color-filled rectangle with pro parameters within and image
export fn ImageDrawRectanglePro(dst: [*c]Image, rec: Rectangle, origin: Vector2, rotation: f32, color: Color) callconv(.c) void {
    // Security checks to avoid program crash
    if ((dst == null) or (dst.*.data == null) or (rec.width <= 0) or (rec.height <= 0)) return;

    const cosAngle = cosf(rotation * DEG2RAD);
    const sinAngle = sinf(rotation * DEG2RAD);

    // Rotation origin in world/image coordinates
    const ox = rec.x + origin.x;
    const oy = rec.y + origin.y;

    // Rectangle corners relative to rotation origin
    const x1 = -origin.x;
    const y1 = -origin.y;
    const x2 = rec.width - origin.x;
    const y2 = rec.height - origin.y;

    const b = rotatedBounds(.{ x1, x2, x2, x1 }, .{ y1, y1, y2, y2 }, cosAngle, sinAngle, .{ .x = ox, .y = oy }, dst.*.width, dst.*.height) orelse return;

    var y = b.y0;
    while (y < b.y1) : (y += 1) {
        var x = b.x0;
        while (x < b.x1) : (x += 1) {
            // Pixel center in world coordinates
            const px = @as(f32, @floatFromInt(x)) + 0.5 - ox;
            const py = @as(f32, @floatFromInt(y)) + 0.5 - oy;

            // Inverse-rotate pixel into rectangle local space
            const localX = px * cosAngle + py * sinAngle;
            const localY = -px * sinAngle + py * cosAngle;

            // Check whether pixel lies inside the rectangle
            if ((localX >= x1) and (localX < x2) and (localY >= y1) and (localY < y2)) {
                // NOTE: Pixel format conversion managed by function
                ImageDrawPixel(dst, x, y, color);
            }
        }
    }
}

// Draw rectangle lines within an image
export fn ImageDrawRectangleLines(dst: [*c]Image, posX: c_int, posY: c_int, width: c_int, height: c_int, color: Color) callconv(.c) void {
    const rec = Rectangle{ .x = @floatFromInt(posX), .y = @floatFromInt(posY), .width = @floatFromInt(width), .height = @floatFromInt(height) };
    ImageDrawRectangleLinesEx(dst, rec, 1, color);
}

// Draw rectangle lines within an image with line thickness
export fn ImageDrawRectangleLinesEx(dst: [*c]Image, rec: Rectangle, thick: c_int, color: Color) callconv(.c) void {
    ImageDrawRectangle(dst, ti(rec.x), ti(rec.y), ti(rec.width), thick, color);
    ImageDrawRectangle(dst, ti(rec.x), ti(rec.y + @as(f32, @floatFromInt(thick))), thick, ti(rec.height - @as(f32, @floatFromInt(thick * 2))), color);
    ImageDrawRectangle(dst, ti(rec.x + rec.width - @as(f32, @floatFromInt(thick))), ti(rec.y + @as(f32, @floatFromInt(thick))), thick, ti(rec.height - @as(f32, @floatFromInt(thick * 2))), color);
    ImageDrawRectangle(dst, ti(rec.x), ti(rec.y + rec.height - @as(f32, @floatFromInt(thick))), ti(rec.width), thick, color);
}

// Draw rectangle with gradient colors within an image, counter-clockwise color order
export fn ImageDrawRectangleGradientEx(dst: [*c]Image, rec: Rectangle, col1: Color, col2: Color, col3: Color, col4: Color) callconv(.c) void {
    // Security checks to avoid program crash
    if ((dst == null) or (dst.*.data == null) or (rec.width <= 0) or (rec.height <= 0)) return;

    const b = clampBounds(
        ti(@floor(rec.x)),
        ti(@floor(rec.y)),
        ti(@ceil(rec.x + rec.width)),
        ti(@ceil(rec.y + rec.height)),
        dst.*.width,
        dst.*.height,
    ) orelse return;

    var y = b.y0;
    while (y < b.y1) : (y += 1) {
        const ty = std.math.clamp((@as(f32, @floatFromInt(y)) - rec.y) / rec.height, 0.0, 1.0);

        var x = b.x0;
        while (x < b.x1) : (x += 1) {
            const tx = std.math.clamp((@as(f32, @floatFromInt(x)) - rec.x) / rec.width, 0.0, 1.0);

            // Bilinear interpolation weights
            const w = [4]f32{ (1.0 - tx) * (1.0 - ty), (1.0 - tx) * ty, tx * ty, tx * (1.0 - ty) };

            // Using ImageDrawPixel() to let it manage color format conversion
            ImageDrawPixel(dst, x, y, .{
                .r = tuc(f(col1.r) * w[0] + f(col2.r) * w[1] + f(col3.r) * w[2] + f(col4.r) * w[3]),
                .g = tuc(f(col1.g) * w[0] + f(col2.g) * w[1] + f(col3.g) * w[2] + f(col4.g) * w[3]),
                .b = tuc(f(col1.b) * w[0] + f(col2.b) * w[1] + f(col3.b) * w[2] + f(col4.b) * w[3]),
                .a = tuc(f(col1.a) * w[0] + f(col2.a) * w[1] + f(col3.a) * w[2] + f(col4.a) * w[3]),
            });
        }
    }
}

// Draw circle within an image
export fn ImageDrawCircle(dst: [*c]Image, centerX: c_int, centerY: c_int, radius: c_int, color: Color) callconv(.c) void {
    var x: c_int = 0;
    var y: c_int = radius;
    var decesionParameter: c_int = 3 - 2 * radius;

    while (y >= x) {
        ImageDrawRectangle(dst, centerX - x, centerY + y, x * 2 + 1, 1, color);
        ImageDrawRectangle(dst, centerX - x, centerY - y, x * 2 + 1, 1, color);
        ImageDrawRectangle(dst, centerX - y, centerY + x, y * 2 + 1, 1, color);
        ImageDrawRectangle(dst, centerX - y, centerY - x, y * 2 + 1, 1, color);
        x += 1;

        if (decesionParameter > 0) {
            y -= 1;
            decesionParameter = decesionParameter + 4 * (x - y) + 10;
        } else decesionParameter = decesionParameter + 4 * x + 6;
    }
}

// Draw circle within an image (Vector version)
export fn ImageDrawCircleV(dst: [*c]Image, center: Vector2, radius: c_int, color: Color) callconv(.c) void {
    ImageDrawCircle(dst, ti(center.x), ti(center.y), radius, color);
}

// Draw circle outline within an image
export fn ImageDrawCircleLines(dst: [*c]Image, centerX: c_int, centerY: c_int, radius: c_int, color: Color) callconv(.c) void {
    var x: c_int = 0;
    var y: c_int = radius;
    var decesionParameter: c_int = 3 - 2 * radius;

    while (y >= x) {
        ImageDrawPixel(dst, centerX + x, centerY + y, color);
        ImageDrawPixel(dst, centerX - x, centerY + y, color);
        ImageDrawPixel(dst, centerX + x, centerY - y, color);
        ImageDrawPixel(dst, centerX - x, centerY - y, color);
        ImageDrawPixel(dst, centerX + y, centerY + x, color);
        ImageDrawPixel(dst, centerX - y, centerY + x, color);
        ImageDrawPixel(dst, centerX + y, centerY - x, color);
        ImageDrawPixel(dst, centerX - y, centerY - x, color);
        x += 1;

        if (decesionParameter > 0) {
            y -= 1;
            decesionParameter = decesionParameter + 4 * (x - y) + 10;
        } else decesionParameter = decesionParameter + 4 * x + 6;
    }
}

// Draw circle outline within an image (Vector version)
export fn ImageDrawCircleLinesV(dst: [*c]Image, center: Vector2, radius: c_int, color: Color) callconv(.c) void {
    ImageDrawCircleLines(dst, ti(center.x), ti(center.y), radius, color);
}

// Draw a gradient-filled circle within an image
export fn ImageDrawCircleGradient(dst: [*c]Image, center: Vector2, radius: f32, inner: Color, outer: Color) callconv(.c) void {
    // Security checks to avoid program crash
    if ((dst == null) or (dst.*.data == null) or (radius <= 0.0)) return;

    const b = clampBounds(
        ti(@floor(center.x - radius)),
        ti(@floor(center.y - radius)),
        ti(@ceil(center.x + radius)),
        ti(@ceil(center.y + radius)),
        dst.*.width,
        dst.*.height,
    ) orelse return;

    const radiusSq = radius * radius;

    var y = b.y0;
    while (y < b.y1) : (y += 1) {
        var x = b.x0;
        while (x < b.x1) : (x += 1) {
            // Center relative to circle center
            const dx = (@as(f32, @floatFromInt(x)) + 0.5) - center.x;
            const dy = (@as(f32, @floatFromInt(y)) + 0.5) - center.y;

            const distSq = dx * dx + dy * dy;

            // Skip pixels outside the circle
            if (distSq > radiusSq) continue;

            // Linear interpolation from inner to outer color
            const t = @sqrt(distSq) / radius;

            // NOTE: Pixel format conversion managed by function
            ImageDrawPixel(dst, x, y, .{
                .r = lerpChannel(inner.r, outer.r, t),
                .g = lerpChannel(inner.g, outer.g, t),
                .b = lerpChannel(inner.b, outer.b, t),
                .a = lerpChannel(inner.a, outer.a, t),
            });
        }
    }
}

// C `(unsigned char)(a + (b - a)*t)`: the channel difference is an int, promoted to float.
fn lerpChannel(a: u8, b: u8, t: f32) u8 {
    const diff: c_int = @as(c_int, b) - @as(c_int, a);
    return tuc(f(a) + @as(f32, @floatFromInt(diff)) * t);
}

// Draw an image within an image
export fn ImageDrawImage(dst: [*c]Image, src: Image, posX: c_int, posY: c_int, tint: Color) callconv(.c) void {
    const srcRec = Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(src.width), .height = @floatFromInt(src.height) };
    const dstRec = Rectangle{ .x = @floatFromInt(posX), .y = @floatFromInt(posY), .width = srcRec.width, .height = srcRec.height };
    ImageDrawImagePro(dst, src, srcRec, dstRec, .{ .x = 0, .y = 0 }, 0.0, tint);
}

// Draw an image with scaling and rotation within an image
// NOTE: Rotation applied from top-left corner origin
export fn ImageDrawImageEx(dst: [*c]Image, src: Image, position: Vector2, rotation: f32, scale: f32, tint: Color) callconv(.c) void {
    // Security checks to avoid program crash
    if ((dst == null) or (dst.*.data == null) or (dst.*.width <= 0) or (dst.*.height <= 0) or (src.width <= 0) or (src.height <= 0)) return;

    const cosA = cosf(rotation * DEG2RAD);
    const sinA = sinf(rotation * DEG2RAD);

    // Rotate around the source image top-left corner
    const w = f(src.width) * scale;
    const h = f(src.height) * scale;
    const b = rotatedBounds(.{ 0.0, w, w, 0.0 }, .{ 0.0, 0.0, h, h }, cosA, sinA, position, dst.*.width, dst.*.height) orelse return;

    var y = b.y0;
    while (y < b.y1) : (y += 1) {
        var x = b.x0;
        while (x < b.x1) : (x += 1) {
            // Destination pixel center relative to image position
            const dx = (@as(f32, @floatFromInt(x)) + 0.5) - position.x;
            const dy = (@as(f32, @floatFromInt(y)) + 0.5) - position.y;

            // Inverse-rotate into the scaled source space, then revert scaling
            const sx = (dx * cosA + dy * sinA) / scale;
            const sy = (-dx * sinA + dy * cosA) / scale;

            // Skip pixels outside the source image
            if ((sx < 0.0) or (sy < 0.0) or (sx >= f(src.width)) or (sy >= f(src.height))) continue;

            // Nearest-neighbor source sampling
            const srcColor = GetImageColor(src, ti(sx), ti(sy));

            // Skip fully transparent pixels
            if (srcColor.a == 0) continue;

            // Blend source over destination (takes destination alpha into account), applying tint
            const dstColor = GetImageColor(dst.*, x, y);
            ImageDrawPixel(dst, x, y, ColorAlphaBlend(dstColor, srcColor, tint));
        }
    }
}

// Draw a part of an image defined by a rectangle within an image
export fn ImageDrawImageRec(dst: [*c]Image, src: Image, srcRec: Rectangle, position: Vector2, tint: Color) callconv(.c) void {
    const dstRec = Rectangle{ .x = position.x, .y = position.y, .width = srcRec.width, .height = srcRec.height };
    ImageDrawImagePro(dst, src, srcRec, dstRec, .{ .x = 0, .y = 0 }, 0.0, tint);
}

// Draw a part of an image into destination rectangle, with scaling, within an image
export fn ImageDrawImagePro(dst: [*c]Image, src: Image, srcRec_in: Rectangle, dstRec_in: Rectangle, origin: Vector2, rotation: f32, tint: Color) callconv(.c) void {
    _ = origin;
    _ = rotation;
    var srcRec = srcRec_in;
    var dstRec = dstRec_in;

    if ((dst == null) or (dst.*.data == null) or (dst.*.width == 0) or (dst.*.height == 0) or
        (src.data == null) or (src.width == 0) or (src.height == 0)) return;

    if (dst.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image drawing not supported for compressed formats");
    } else {
        var srcMod: Image = .{};
        var srcPtr: *const Image = &src;
        var useSrcMod = false;

        if (srcRec.x < 0) {
            srcRec.width += srcRec.x;
            srcRec.x = 0;
        }
        if (srcRec.y < 0) {
            srcRec.height += srcRec.y;
            srcRec.y = 0;
        }
        if ((srcRec.x + srcRec.width) > @as(f32, @floatFromInt(src.width))) srcRec.width = @as(f32, @floatFromInt(src.width)) - srcRec.x;
        if ((srcRec.y + srcRec.height) > @as(f32, @floatFromInt(src.height))) srcRec.height = @as(f32, @floatFromInt(src.height)) - srcRec.y;

        if ((ti(srcRec.width) != ti(dstRec.width)) or (ti(srcRec.height) != ti(dstRec.height))) {
            srcMod = ImageFromImage(src, srcRec);
            ImageResize(&srcMod, ti(dstRec.width), ti(dstRec.height));
            srcRec = .{ .x = 0, .y = 0, .width = @floatFromInt(srcMod.width), .height = @floatFromInt(srcMod.height) };

            srcPtr = &srcMod;
            useSrcMod = true;
        }

        if (dstRec.x < 0) {
            srcRec.x -= dstRec.x;
            srcRec.width += dstRec.x;
            dstRec.x = 0;
        } else if ((dstRec.x + srcRec.width) > @as(f32, @floatFromInt(dst.*.width))) srcRec.width = @as(f32, @floatFromInt(dst.*.width)) - dstRec.x;

        if (dstRec.y < 0) {
            srcRec.y -= dstRec.y;
            srcRec.height += dstRec.y;
            dstRec.y = 0;
        } else if ((dstRec.y + srcRec.height) > @as(f32, @floatFromInt(dst.*.height))) srcRec.height = @as(f32, @floatFromInt(dst.*.height)) - dstRec.y;

        if (@as(f32, @floatFromInt(dst.*.width)) < srcRec.width) srcRec.width = @floatFromInt(dst.*.width);
        if (@as(f32, @floatFromInt(dst.*.height)) < srcRec.height) srcRec.height = @floatFromInt(dst.*.height);

        var blendRequired = true;

        // Fast path: Avoid blend if source has no alpha to blend
        if ((tint.a == 255) and
            ((srcPtr.format == PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) or
                (srcPtr.format == PIXELFORMAT_UNCOMPRESSED_R5G6B5) or
                (srcPtr.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8) or
                (srcPtr.format == PIXELFORMAT_UNCOMPRESSED_R32) or
                (srcPtr.format == PIXELFORMAT_UNCOMPRESSED_R32G32B32) or
                (srcPtr.format == PIXELFORMAT_UNCOMPRESSED_R16) or
                (srcPtr.format == PIXELFORMAT_UNCOMPRESSED_R16G16B16)))
            blendRequired = false;

        const strideDst = GetPixelDataSize(dst.*.width, 1, dst.*.format);
        const bytesPerPixelDst = @divTrunc(strideDst, dst.*.width);

        const strideSrc = GetPixelDataSize(srcPtr.width, 1, srcPtr.format);
        const bytesPerPixelSrc = @divTrunc(strideSrc, srcPtr.width);

        const srcDataBase: [*]const u8 = @ptrCast(srcPtr.data);
        const dstDataBase: [*]u8 = @ptrCast(dst.*.data);

        var pSrcBase = srcDataBase + @as(usize, @intCast((ti(srcRec.y) * srcPtr.width + ti(srcRec.x)) * bytesPerPixelSrc));
        var pDstBase = dstDataBase + @as(usize, @intCast((ti(dstRec.y) * dst.*.width + ti(dstRec.x)) * bytesPerPixelDst));

        var y: c_int = 0;
        while (y < ti(srcRec.height)) : (y += 1) {
            var pSrc = pSrcBase;
            var pDst = pDstBase;

            if (!blendRequired and (srcPtr.format == dst.*.format)) {
                // NOTE: memmove, not memcpy: drawing an image onto itself overlaps
                const n: usize = @intCast(ti(srcRec.width) * bytesPerPixelSrc);
                @memmove(pDst[0..n], pSrc[0..n]);
            } else {
                var x: c_int = 0;
                while (x < ti(srcRec.width)) : (x += 1) {
                    const colSrc = GetPixelColor(pSrc, srcPtr.format);
                    const colDst = GetPixelColor(pDst, dst.*.format);

                    const blend = if (blendRequired) ColorAlphaBlend(colDst, colSrc, tint) else colSrc;

                    SetPixelColor(pDst, blend, dst.*.format);

                    pDst += @intCast(bytesPerPixelDst);
                    pSrc += @intCast(bytesPerPixelSrc);
                }
            }

            pSrcBase += @intCast(strideSrc);
            pDstBase += @intCast(strideDst);
        }

        if (useSrcMod) UnloadImage(srcMod);

        if ((dst.*.mipmaps > 1) and (src.mipmaps > 1)) {
            var mipmapDst = dst.*;
            mipmapDst.data = @as([*]u8, @ptrCast(mipmapDst.data)) + @as(usize, @intCast(GetPixelDataSize(mipmapDst.width, mipmapDst.height, mipmapDst.format)));
            mipmapDst.width = @divTrunc(mipmapDst.width, 2);
            mipmapDst.height = @divTrunc(mipmapDst.height, 2);
            mipmapDst.mipmaps -= 1;

            var mipmapSrc = src;
            mipmapSrc.data = @as([*]u8, @ptrCast(mipmapSrc.data)) + @as(usize, @intCast(GetPixelDataSize(mipmapSrc.width, mipmapSrc.height, mipmapSrc.format)));
            mipmapSrc.width = @divTrunc(mipmapSrc.width, 2);
            mipmapSrc.height = @divTrunc(mipmapSrc.height, 2);
            mipmapSrc.mipmaps -= 1;

            var mipmapSrcRec = srcRec;
            mipmapSrcRec.width /= 2;
            mipmapSrcRec.height /= 2;
            mipmapSrcRec.x /= 2;
            mipmapSrcRec.y /= 2;

            var mipmapDstRec = dstRec;
            mipmapDstRec.width /= 2;
            mipmapDstRec.height /= 2;
            mipmapDstRec.x /= 2;
            mipmapDstRec.y /= 2;

            ImageDrawImagePro(&mipmapDst, mipmapSrc, mipmapSrcRec, mipmapDstRec, .{ .x = 0, .y = 0 }, 0.0, tint);
        }
    }
}

// Draw text (default font) within an image (destination)
export fn ImageDrawText(dst: [*c]Image, text: [*c]const u8, posX: c_int, posY: c_int, fontSize: c_int, color: Color) callconv(.c) void {
    if (GetFontDefault().texture.id == 0) LoadFontDefault();

    const position = Vector2{ .x = @floatFromInt(posX), .y = @floatFromInt(posY) };
    ImageDrawTextEx(dst, GetFontDefault(), text, position, @floatFromInt(fontSize), 1.0, color);
}

// Draw text (custom sprite font) within an image (destination)
export fn ImageDrawTextEx(dst: [*c]Image, font: Font, text: [*c]const u8, position: Vector2, fontSize: f32, spacing: f32, tint: Color) callconv(.c) void {
    const imText = ImageTextEx(font, text, fontSize, spacing, tint);

    const srcRec = Rectangle{ .x = 0.0, .y = 0.0, .width = @floatFromInt(imText.width), .height = @floatFromInt(imText.height) };
    const dstRec = Rectangle{ .x = position.x, .y = position.y, .width = @floatFromInt(imText.width), .height = @floatFromInt(imText.height) };

    ImageDrawImagePro(dst, imText, srcRec, dstRec, .{ .x = 0, .y = 0 }, 0.0, WHITE);

    UnloadImage(imText);
}

// Draw text using Font and pro parameters (rotation)
// NOTE: Not implemented upstream yet (raylib 6.2 ships an empty stub); kept a no-op for parity
export fn ImageDrawTextPro(dst: [*c]Image, font: Font, text: [*c]const u8, position: Vector2, origin: Vector2, rotation: f32, fontSize: f32, spacing: f32, tint: Color) callconv(.c) void {
    _ = .{ dst, font, text, position, origin, rotation, fontSize, spacing, tint };
}

//------------------------------------------------------------------------------------
// Texture loading functions
//------------------------------------------------------------------------------------
// Load texture from file into GPU memory (VRAM)
export fn LoadTexture(fileName: [*c]const u8) callconv(.c) Texture2D {
    const image = LoadImage(fileName);
    if (image.data == null) return .{};
    defer UnloadImage(image);

    return LoadTextureFromImage(image);
}

// Load a texture from image data
// NOTE: image is not unloaded, it must be done manually
export fn LoadTextureFromImage(image: Image) callconv(.c) Texture2D {
    var texture: Texture2D = .{
        .width = image.width,
        .height = image.height,
        .mipmaps = image.mipmaps,
        .format = image.format,
    };

    if ((image.width != 0) and (image.height != 0)) {
        texture.id = rlLoadTexture(image.data, image.width, image.height, image.format, image.mipmaps);
    } else TraceLog(LOG_WARNING, "IMAGE: Data is not valid to load texture");

    return texture;
}

/// Where each cubemap face sits in an image laid out as `layout`, in units of
/// the face size; null for a layout that is not a cross or a horizontal line.
fn cubemapFaceCells(layout: c_int) ?[6][2]u8 {
    return switch (layout) {
        CUBEMAP_LAYOUT_LINE_HORIZONTAL => .{ .{ 0, 0 }, .{ 1, 0 }, .{ 2, 0 }, .{ 3, 0 }, .{ 4, 0 }, .{ 5, 0 } },
        CUBEMAP_LAYOUT_CROSS_THREE_BY_FOUR => .{ .{ 1, 1 }, .{ 1, 3 }, .{ 1, 0 }, .{ 1, 2 }, .{ 0, 1 }, .{ 2, 1 } },
        CUBEMAP_LAYOUT_CROSS_FOUR_BY_THREE => .{ .{ 2, 1 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 2 }, .{ 1, 1 }, .{ 3, 1 } },
        else => null,
    };
}

// Load cubemap from image, multiple image cubemap layouts supported
export fn LoadTextureCubemap(image: Image, layout_in: c_int) callconv(.c) TextureCubemap {
    var cubemap: TextureCubemap = .{};
    var layout = layout_in;

    if (layout == CUBEMAP_LAYOUT_AUTO_DETECT) { // Try to automatically guess layout type
        // Check image width/height to determine the type of cubemap provided
        if (image.width > image.height) {
            if (@divTrunc(image.width, 6) == image.height) {
                layout = CUBEMAP_LAYOUT_LINE_HORIZONTAL;
                cubemap.width = @divTrunc(image.width, 6);
            } else if (@divTrunc(image.width, 4) == @divTrunc(image.height, 3)) {
                layout = CUBEMAP_LAYOUT_CROSS_FOUR_BY_THREE;
                cubemap.width = @divTrunc(image.width, 4);
            }
        } else if (image.height > image.width) {
            if (@divTrunc(image.height, 6) == image.width) {
                layout = CUBEMAP_LAYOUT_LINE_VERTICAL;
                cubemap.width = @divTrunc(image.height, 6);
            } else if (@divTrunc(image.width, 3) == @divTrunc(image.height, 4)) {
                layout = CUBEMAP_LAYOUT_CROSS_THREE_BY_FOUR;
                cubemap.width = @divTrunc(image.width, 3);
            }
        }
    } else {
        if (layout == CUBEMAP_LAYOUT_LINE_VERTICAL) cubemap.width = @divTrunc(image.height, 6);
        if (layout == CUBEMAP_LAYOUT_LINE_HORIZONTAL) cubemap.width = @divTrunc(image.width, 6);
        if (layout == CUBEMAP_LAYOUT_CROSS_THREE_BY_FOUR) cubemap.width = @divTrunc(image.width, 3);
        if (layout == CUBEMAP_LAYOUT_CROSS_FOUR_BY_THREE) cubemap.width = @divTrunc(image.width, 4);
    }

    cubemap.height = cubemap.width;

    // Layout provided or already auto-detected
    if (layout == CUBEMAP_LAYOUT_AUTO_DETECT) {
        TraceLog(LOG_WARNING, "IMAGE: Failed to detect cubemap image layout");
        return cubemap;
    }

    const size = cubemap.width;

    // NOTE: Image formatting does not work with compressed textures
    const faces = if (layout == CUBEMAP_LAYOUT_LINE_VERTICAL)
        ImageCopy(image) // Image data already follows expected convention
    else faces: {
        // Convert image data to 6 faces in a vertical column, that's the optimum layout for loading
        // NOTE: An unrecognized layout leaves every face at the image's top-left corner (raylib)
        const cells = cubemapFaceCells(layout) orelse @as([6][2]u8, @splat(.{ 0, 0 }));

        var faces = GenImageColor(size, size * 6, MAGENTA); // Image to store faces
        ImageFormat(&faces, image.format);

        var mipmapped = ImageCopy(image);
        defer UnloadImage(mipmapped);
        if (image.mipmaps > 1) {
            ImageMipmaps(&mipmapped);
            ImageMipmaps(&faces);
        }

        // NOTE: Image formatting does not work with compressed textures
        for (cells, 0..) |cell, i| {
            const face: Rectangle = .{ .x = f(size) * f(cell[0]), .y = f(size) * f(cell[1]), .width = f(size), .height = f(size) };
            const dst: Rectangle = .{ .x = 0, .y = f(size) * f(i), .width = f(size), .height = f(size) };
            ImageDrawImagePro(&faces, mipmapped, face, dst, .{ .x = 0, .y = 0 }, 0.0, WHITE);
        }
        break :faces faces;
    };
    defer UnloadImage(faces);

    // NOTE: Cubemap data is expected to be provided as 6 images in a single data array,
    // one after the other (that's a vertical image), following convention: +X, -X, +Y, -Y, +Z, -Z
    cubemap.id = rlLoadTextureCubemap(faces.data, size, faces.format, faces.mipmaps);

    if (cubemap.id != 0) {
        cubemap.format = faces.format;
        cubemap.mipmaps = faces.mipmaps;
    } else TraceLog(LOG_WARNING, "IMAGE: Failed to load cubemap image");

    return cubemap;
}

// Load texture for rendering (framebuffer)
export fn LoadRenderTexture(width: c_int, height: c_int) callconv(.c) RenderTexture2D {
    return LoadRenderTextureEx(width, height, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);
}

// Load texture for rendering (framebuffer), with specific format
// NOTE: Render texture is loaded by default with RGBA color attachment and depth RenderBuffer
export fn LoadRenderTextureEx(width: c_int, height: c_int, format: c_int) callconv(.c) RenderTexture2D {
    var target: RenderTexture2D = .{};

    if (format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "FBO: Render texture format not supported");
        return target;
    }

    target.id = rlLoadFramebuffer(); // Load an empty framebuffer

    if (target.id > 0) {
        rlEnableFramebuffer(target.id);

        // Create color texture (default to RGBA)
        target.texture.id = rlLoadTexture(null, width, height, format, 1);
        target.texture.width = width;
        target.texture.height = height;
        target.texture.format = format;
        target.texture.mipmaps = 1;

        // Create depth renderbuffer/texture
        target.depth.id = rlLoadTextureDepth(width, height, true);
        target.depth.width = width;
        target.depth.height = height;
        target.depth.format = 19; // DEPTH_COMPONENT_24BIT?
        target.depth.mipmaps = 1;

        // Attach color texture and depth renderbuffer/texture to FBO
        rlFramebufferAttach(target.id, target.texture.id, RL_ATTACHMENT_COLOR_CHANNEL0, RL_ATTACHMENT_TEXTURE2D, 0);
        rlFramebufferAttach(target.id, target.depth.id, RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_RENDERBUFFER, 0);

        if (rlFramebufferComplete(target.id)) TraceLog(LOG_INFO, "FBO: [ID %i] Framebuffer object created successfully", target.id);

        rlDisableFramebuffer();
    } else TraceLog(LOG_WARNING, "FBO: Framebuffer object can not be created");

    return target;
}

// Check if texture is valid (loaded in GPU)
export fn IsTextureValid(texture: Texture2D) callconv(.c) bool {
    return (texture.id > 0) and // Validate OpenGL id (texture uploaded to GPU)
        (texture.width > 0) and // Validate texture width
        (texture.height > 0) and // Validate texture height
        (texture.format > 0) and // Validate texture pixel format
        (texture.mipmaps > 0); // Validate texture mipmaps (at least 1 for basic mipmap level)
}

// Unload texture from GPU memory (VRAM)
export fn UnloadTexture(texture: Texture2D) callconv(.c) void {
    if (texture.id > 0) {
        rlUnloadTexture(texture.id);
        TraceLog(LOG_INFO, "TEXTURE: [ID %i] Unloaded texture data from VRAM (GPU)", texture.id);
    }
}

// Check if render texture is valid (loaded in GPU)
export fn IsRenderTextureValid(target: RenderTexture2D) callconv(.c) bool {
    return (target.id > 0) and // Validate OpenGL id (loaded on GPU)
        IsTextureValid(target.depth) and // Validate FBO depth texture/renderbuffer attachment
        IsTextureValid(target.texture); // Validate FBO texture attachment
}

// Unload render texture from GPU memory (VRAM)
export fn UnloadRenderTexture(target: RenderTexture2D) callconv(.c) void {
    if (target.id > 0) {
        if (target.texture.id > 0) {
            rlUnloadTexture(target.texture.id);
        }
        rlUnloadFramebuffer(target.id);
    }
}

// Update GPU texture with new data
export fn UpdateTexture(texture: Texture2D, pixels: ?*const anyopaque) callconv(.c) void {
    rlUpdateTexture(texture.id, 0, 0, texture.width, texture.height, texture.format, pixels);
}

// Update GPU texture rectangle with new data
export fn UpdateTextureRec(texture: Texture2D, rec: Rectangle, pixels: ?*const anyopaque) callconv(.c) void {
    rlUpdateTexture(texture.id, ti(rec.x), ti(rec.y), ti(rec.width), ti(rec.height), texture.format, pixels);
}

//------------------------------------------------------------------------------------
// Texture configuration functions
//------------------------------------------------------------------------------------
// Generate GPU mipmaps for a texture
export fn GenTextureMipmaps(texture: [*c]Texture2D) callconv(.c) void {
    rlGenTextureMipmaps(texture.*.id, texture.*.width, texture.*.height, texture.*.format, &texture.*.mipmaps);
}

// Set texture scaling filter mode
export fn SetTextureFilter(texture: Texture2D, filter: c_int) callconv(.c) void {
    switch (filter) {
        TEXTURE_FILTER_POINT => {
            if (texture.mipmaps > 1) {
                rlTextureParameters(texture.id, RL_TEXTURE_MIN_FILTER, RL_TEXTURE_FILTER_MIP_NEAREST);
                rlTextureParameters(texture.id, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_NEAREST);
            } else {
                rlTextureParameters(texture.id, RL_TEXTURE_MIN_FILTER, RL_TEXTURE_FILTER_NEAREST);
                rlTextureParameters(texture.id, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_NEAREST);
            }
        },
        TEXTURE_FILTER_BILINEAR => {
            if (texture.mipmaps > 1) {
                rlTextureParameters(texture.id, RL_TEXTURE_MIN_FILTER, RL_TEXTURE_FILTER_LINEAR_MIP_NEAREST);
                rlTextureParameters(texture.id, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_LINEAR);
            } else {
                rlTextureParameters(texture.id, RL_TEXTURE_MIN_FILTER, RL_TEXTURE_FILTER_LINEAR);
                rlTextureParameters(texture.id, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_LINEAR);
            }
        },
        TEXTURE_FILTER_TRILINEAR => {
            if (texture.mipmaps > 1) {
                rlTextureParameters(texture.id, RL_TEXTURE_MIN_FILTER, RL_TEXTURE_FILTER_MIP_LINEAR);
                rlTextureParameters(texture.id, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_LINEAR);
            } else {
                TraceLog(LOG_WARNING, "TEXTURE: [ID %i] No mipmaps available for TRILINEAR texture filtering", texture.id);
                rlTextureParameters(texture.id, RL_TEXTURE_MIN_FILTER, RL_TEXTURE_FILTER_LINEAR);
                rlTextureParameters(texture.id, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_LINEAR);
            }
        },
        TEXTURE_FILTER_ANISOTROPIC_4X => rlTextureParameters(texture.id, RL_TEXTURE_FILTER_ANISOTROPIC, 4),
        TEXTURE_FILTER_ANISOTROPIC_8X => rlTextureParameters(texture.id, RL_TEXTURE_FILTER_ANISOTROPIC, 8),
        TEXTURE_FILTER_ANISOTROPIC_16X => rlTextureParameters(texture.id, RL_TEXTURE_FILTER_ANISOTROPIC, 16),
        else => {},
    }
}

// Set texture wrapping mode
export fn SetTextureWrap(texture: Texture2D, wrap: c_int) callconv(.c) void {
    switch (wrap) {
        TEXTURE_WRAP_REPEAT => {
            rlTextureParameters(texture.id, RL_TEXTURE_WRAP_S, RL_TEXTURE_WRAP_REPEAT);
            rlTextureParameters(texture.id, RL_TEXTURE_WRAP_T, RL_TEXTURE_WRAP_REPEAT);
        },
        TEXTURE_WRAP_CLAMP => {
            rlTextureParameters(texture.id, RL_TEXTURE_WRAP_S, RL_TEXTURE_WRAP_CLAMP);
            rlTextureParameters(texture.id, RL_TEXTURE_WRAP_T, RL_TEXTURE_WRAP_CLAMP);
        },
        TEXTURE_WRAP_MIRROR_REPEAT => {
            rlTextureParameters(texture.id, RL_TEXTURE_WRAP_S, RL_TEXTURE_WRAP_MIRROR_REPEAT);
            rlTextureParameters(texture.id, RL_TEXTURE_WRAP_T, RL_TEXTURE_WRAP_MIRROR_REPEAT);
        },
        TEXTURE_WRAP_MIRROR_CLAMP => {
            rlTextureParameters(texture.id, RL_TEXTURE_WRAP_S, RL_TEXTURE_WRAP_MIRROR_CLAMP);
            rlTextureParameters(texture.id, RL_TEXTURE_WRAP_T, RL_TEXTURE_WRAP_MIRROR_CLAMP);
        },
        else => {},
    }
}

//------------------------------------------------------------------------------------
// Texture drawing functions
//------------------------------------------------------------------------------------
// Draw a texture
export fn DrawTexture(texture: Texture2D, posX: c_int, posY: c_int, tint: Color) callconv(.c) void {
    DrawTextureEx(texture, .{ .x = @floatFromInt(posX), .y = @floatFromInt(posY) }, 0.0, 1.0, tint);
}

// Draw a texture with position defined as Vector2
export fn DrawTextureV(texture: Texture2D, position: Vector2, tint: Color) callconv(.c) void {
    DrawTextureEx(texture, position, 0, 1.0, tint);
}

// Draw a texture with rotation and scale
export fn DrawTextureEx(texture: Texture2D, position: Vector2, rotation: f32, scale: f32, tint: Color) callconv(.c) void {
    const srcrec = Rectangle{ .x = 0.0, .y = 0.0, .width = @floatFromInt(texture.width), .height = @floatFromInt(texture.height) };
    const dstrec = Rectangle{ .x = position.x, .y = position.y, .width = @as(f32, @floatFromInt(texture.width)) * scale, .height = @as(f32, @floatFromInt(texture.height)) * scale };
    const origin = Vector2{ .x = 0.0, .y = 0.0 };

    DrawTexturePro(texture, srcrec, dstrec, origin, rotation, tint);
}

// Draw a part of a texture (defined by a rectangle)
export fn DrawTextureRec(texture: Texture2D, rec: Rectangle, position: Vector2, tint: Color) callconv(.c) void {
    const dstrec = Rectangle{ .x = position.x, .y = position.y, .width = @abs(rec.width), .height = @abs(rec.height) };
    const origin = Vector2{ .x = 0.0, .y = 0.0 };

    DrawTexturePro(texture, rec, dstrec, origin, 0.0, tint);
}

// Draw a part of a texture (defined by a rectangle) with 'pro' parameters
export fn DrawTexturePro(texture: Texture2D, srcrec_in: Rectangle, dstrec_in: Rectangle, origin: Vector2, rotation: f32, tint: Color) callconv(.c) void {
    var srcrec = srcrec_in;
    var dstrec = dstrec_in;

    if (texture.id > 0) {
        const width: f32 = @floatFromInt(texture.width);
        const height: f32 = @floatFromInt(texture.height);

        var flipX = false;

        if (srcrec.width < 0) {
            flipX = true;
            srcrec.width *= -1;
        }
        if (srcrec.height < 0) srcrec.y -= srcrec.height;

        if (dstrec.width < 0) dstrec.width *= -1;
        if (dstrec.height < 0) dstrec.height *= -1;

        var topLeft: Vector2 = .{ .x = 0, .y = 0 };
        var topRight: Vector2 = .{ .x = 0, .y = 0 };
        var bottomLeft: Vector2 = .{ .x = 0, .y = 0 };
        var bottomRight: Vector2 = .{ .x = 0, .y = 0 };

        if (rotation == 0.0) {
            const x = dstrec.x - origin.x;
            const y = dstrec.y - origin.y;
            topLeft = .{ .x = x, .y = y };
            topRight = .{ .x = x + dstrec.width, .y = y };
            bottomLeft = .{ .x = x, .y = y + dstrec.height };
            bottomRight = .{ .x = x + dstrec.width, .y = y + dstrec.height };
        } else {
            const sinRotation = sinf(rotation * DEG2RAD);
            const cosRotation = cosf(rotation * DEG2RAD);
            const x = dstrec.x;
            const y = dstrec.y;
            const dx = -origin.x;
            const dy = -origin.y;

            topLeft.x = x + dx * cosRotation - dy * sinRotation;
            topLeft.y = y + dx * sinRotation + dy * cosRotation;

            topRight.x = x + (dx + dstrec.width) * cosRotation - dy * sinRotation;
            topRight.y = y + (dx + dstrec.width) * sinRotation + dy * cosRotation;

            bottomLeft.x = x + dx * cosRotation - (dy + dstrec.height) * sinRotation;
            bottomLeft.y = y + dx * sinRotation + (dy + dstrec.height) * cosRotation;

            bottomRight.x = x + (dx + dstrec.width) * cosRotation - (dy + dstrec.height) * sinRotation;
            bottomRight.y = y + (dx + dstrec.width) * sinRotation + (dy + dstrec.height) * cosRotation;
        }

        rlSetTexture(texture.id);
        rlBegin(RL_QUADS);

        rlColor4ub(tint.r, tint.g, tint.b, tint.a);
        rlNormal3f(0.0, 0.0, 1.0); // Normal vector pointing towards viewer

        // Top-left corner for texture and quad
        if (flipX) rlTexCoord2f((srcrec.x + srcrec.width) / width, srcrec.y / height) else rlTexCoord2f(srcrec.x / width, srcrec.y / height);
        rlVertex2f(topLeft.x, topLeft.y);

        // Bottom-left corner for texture and quad
        if (flipX) rlTexCoord2f((srcrec.x + srcrec.width) / width, (srcrec.y + srcrec.height) / height) else rlTexCoord2f(srcrec.x / width, (srcrec.y + srcrec.height) / height);
        rlVertex2f(bottomLeft.x, bottomLeft.y);

        // Bottom-right corner for texture and quad
        if (flipX) rlTexCoord2f(srcrec.x / width, (srcrec.y + srcrec.height) / height) else rlTexCoord2f((srcrec.x + srcrec.width) / width, (srcrec.y + srcrec.height) / height);
        rlVertex2f(bottomRight.x, bottomRight.y);

        // Top-right corner for texture and quad
        if (flipX) rlTexCoord2f(srcrec.x / width, srcrec.y / height) else rlTexCoord2f((srcrec.x + srcrec.width) / width, srcrec.y / height);
        rlVertex2f(topRight.x, topRight.y);

        rlEnd();
        rlSetTexture(0);
    }
}

// Draw a texture (or part of it) that stretches or shrinks nicely using n-patch info
export fn DrawTextureNPatch(texture: Texture2D, nPatchInfo_in: NPatchInfo, dstrec: Rectangle, origin: Vector2, rotation: f32, tint: Color) callconv(.c) void {
    var nPatchInfo = nPatchInfo_in;
    if (texture.id > 0) {
        const width: f32 = @floatFromInt(texture.width);
        const height: f32 = @floatFromInt(texture.height);

        var patchWidth: f32 = if (ti(dstrec.width) <= 0) 0.0 else dstrec.width;
        var patchHeight: f32 = if (ti(dstrec.height) <= 0) 0.0 else dstrec.height;

        if (nPatchInfo.source.width < 0) nPatchInfo.source.x -= nPatchInfo.source.width;
        if (nPatchInfo.source.height < 0) nPatchInfo.source.y -= nPatchInfo.source.height;
        if (nPatchInfo.layout == NPATCH_THREE_PATCH_HORIZONTAL) patchHeight = nPatchInfo.source.height;
        if (nPatchInfo.layout == NPATCH_THREE_PATCH_VERTICAL) patchWidth = nPatchInfo.source.width;

        var drawCenter = true;
        var drawMiddle = true;
        var leftBorder: f32 = @floatFromInt(nPatchInfo.left);
        var topBorder: f32 = @floatFromInt(nPatchInfo.top);
        var rightBorder: f32 = @floatFromInt(nPatchInfo.right);
        var bottomBorder: f32 = @floatFromInt(nPatchInfo.bottom);

        if (patchWidth <= (leftBorder + rightBorder) and nPatchInfo.layout != NPATCH_THREE_PATCH_VERTICAL) {
            drawCenter = false;
            leftBorder = (leftBorder / (leftBorder + rightBorder)) * patchWidth;
            rightBorder = patchWidth - leftBorder;
        }

        if (patchHeight <= (topBorder + bottomBorder) and nPatchInfo.layout != NPATCH_THREE_PATCH_HORIZONTAL) {
            drawMiddle = false;
            topBorder = (topBorder / (topBorder + bottomBorder)) * patchHeight;
            bottomBorder = patchHeight - topBorder;
        }

        const vertA: Vector2 = .{ .x = 0.0, .y = 0.0 }; // Outer left, outer top
        const vertB: Vector2 = .{ .x = leftBorder, .y = topBorder }; // Inner left, inner top
        const vertC: Vector2 = .{ .x = patchWidth - rightBorder, .y = patchHeight - bottomBorder }; // Inner right, inner bottom
        const vertD: Vector2 = .{ .x = patchWidth, .y = patchHeight }; // Outer right, outer bottom

        const source = nPatchInfo.source;
        const coordA: Vector2 = .{ .x = source.x / width, .y = source.y / height };
        const coordB: Vector2 = .{ .x = (source.x + leftBorder) / width, .y = (source.y + topBorder) / height };
        const coordC: Vector2 = .{ .x = (source.x + source.width - rightBorder) / width, .y = (source.y + source.height - bottomBorder) / height };
        const coordD: Vector2 = .{ .x = (source.x + source.width) / width, .y = (source.y + source.height) / height };

        rlSetTexture(texture.id);

        rlPushMatrix();
        rlTranslatef(dstrec.x, dstrec.y, 0.0);
        rlRotatef(rotation, 0.0, 0.0, 1.0);
        rlTranslatef(-origin.x, -origin.y, 0.0);

        rlBegin(RL_QUADS);
        rlColor4ub(tint.r, tint.g, tint.b, tint.a);
        rlNormal3f(0.0, 0.0, 1.0); // Normal vector pointing towards viewer

        if (nPatchInfo.layout == NPATCH_NINE_PATCH) {
            // TOP-LEFT QUAD
            rlTexCoord2f(coordA.x, coordB.y);
            rlVertex2f(vertA.x, vertB.y);
            rlTexCoord2f(coordB.x, coordB.y);
            rlVertex2f(vertB.x, vertB.y);
            rlTexCoord2f(coordB.x, coordA.y);
            rlVertex2f(vertB.x, vertA.y);
            rlTexCoord2f(coordA.x, coordA.y);
            rlVertex2f(vertA.x, vertA.y);
            if (drawCenter) {
                // TOP-CENTER QUAD
                rlTexCoord2f(coordB.x, coordB.y);
                rlVertex2f(vertB.x, vertB.y);
                rlTexCoord2f(coordC.x, coordB.y);
                rlVertex2f(vertC.x, vertB.y);
                rlTexCoord2f(coordC.x, coordA.y);
                rlVertex2f(vertC.x, vertA.y);
                rlTexCoord2f(coordB.x, coordA.y);
                rlVertex2f(vertB.x, vertA.y);
            }
            // TOP-RIGHT QUAD
            rlTexCoord2f(coordC.x, coordB.y);
            rlVertex2f(vertC.x, vertB.y);
            rlTexCoord2f(coordD.x, coordB.y);
            rlVertex2f(vertD.x, vertB.y);
            rlTexCoord2f(coordD.x, coordA.y);
            rlVertex2f(vertD.x, vertA.y);
            rlTexCoord2f(coordC.x, coordA.y);
            rlVertex2f(vertC.x, vertA.y);
            if (drawMiddle) {
                // MIDDLE-LEFT QUAD
                rlTexCoord2f(coordA.x, coordC.y);
                rlVertex2f(vertA.x, vertC.y);
                rlTexCoord2f(coordB.x, coordC.y);
                rlVertex2f(vertB.x, vertC.y);
                rlTexCoord2f(coordB.x, coordB.y);
                rlVertex2f(vertB.x, vertB.y);
                rlTexCoord2f(coordA.x, coordB.y);
                rlVertex2f(vertA.x, vertB.y);
                if (drawCenter) {
                    // MIDDLE-CENTER QUAD
                    rlTexCoord2f(coordB.x, coordC.y);
                    rlVertex2f(vertB.x, vertC.y);
                    rlTexCoord2f(coordC.x, coordC.y);
                    rlVertex2f(vertC.x, vertC.y);
                    rlTexCoord2f(coordC.x, coordB.y);
                    rlVertex2f(vertC.x, vertB.y);
                    rlTexCoord2f(coordB.x, coordB.y);
                    rlVertex2f(vertB.x, vertB.y);
                }

                // MIDDLE-RIGHT QUAD
                rlTexCoord2f(coordC.x, coordC.y);
                rlVertex2f(vertC.x, vertC.y);
                rlTexCoord2f(coordD.x, coordC.y);
                rlVertex2f(vertD.x, vertC.y);
                rlTexCoord2f(coordD.x, coordB.y);
                rlVertex2f(vertD.x, vertB.y);
                rlTexCoord2f(coordC.x, coordB.y);
                rlVertex2f(vertC.x, vertB.y);
            }

            // BOTTOM-LEFT QUAD
            rlTexCoord2f(coordA.x, coordD.y);
            rlVertex2f(vertA.x, vertD.y);
            rlTexCoord2f(coordB.x, coordD.y);
            rlVertex2f(vertB.x, vertD.y);
            rlTexCoord2f(coordB.x, coordC.y);
            rlVertex2f(vertB.x, vertC.y);
            rlTexCoord2f(coordA.x, coordC.y);
            rlVertex2f(vertA.x, vertC.y);
            if (drawCenter) {
                // BOTTOM-CENTER QUAD
                rlTexCoord2f(coordB.x, coordD.y);
                rlVertex2f(vertB.x, vertD.y);
                rlTexCoord2f(coordC.x, coordD.y);
                rlVertex2f(vertC.x, vertD.y);
                rlTexCoord2f(coordC.x, coordC.y);
                rlVertex2f(vertC.x, vertC.y);
                rlTexCoord2f(coordB.x, coordC.y);
                rlVertex2f(vertB.x, vertC.y);
            }

            // BOTTOM-RIGHT QUAD
            rlTexCoord2f(coordC.x, coordD.y);
            rlVertex2f(vertC.x, vertD.y);
            rlTexCoord2f(coordD.x, coordD.y);
            rlVertex2f(vertD.x, vertD.y);
            rlTexCoord2f(coordD.x, coordC.y);
            rlVertex2f(vertD.x, vertC.y);
            rlTexCoord2f(coordC.x, coordC.y);
            rlVertex2f(vertC.x, vertC.y);
        } else if (nPatchInfo.layout == NPATCH_THREE_PATCH_VERTICAL) {
            // TOP QUAD
            rlTexCoord2f(coordA.x, coordB.y);
            rlVertex2f(vertA.x, vertB.y);
            rlTexCoord2f(coordD.x, coordB.y);
            rlVertex2f(vertD.x, vertB.y);
            rlTexCoord2f(coordD.x, coordA.y);
            rlVertex2f(vertD.x, vertA.y);
            rlTexCoord2f(coordA.x, coordA.y);
            rlVertex2f(vertA.x, vertA.y);
            if (drawCenter) {
                // MIDDLE QUAD
                rlTexCoord2f(coordA.x, coordC.y);
                rlVertex2f(vertA.x, vertC.y);
                rlTexCoord2f(coordD.x, coordC.y);
                rlVertex2f(vertD.x, vertC.y);
                rlTexCoord2f(coordD.x, coordB.y);
                rlVertex2f(vertD.x, vertB.y);
                rlTexCoord2f(coordA.x, coordB.y);
                rlVertex2f(vertA.x, vertB.y);
            }
            // BOTTOM QUAD
            rlTexCoord2f(coordA.x, coordD.y);
            rlVertex2f(vertA.x, vertD.y);
            rlTexCoord2f(coordD.x, coordD.y);
            rlVertex2f(vertD.x, vertD.y);
            rlTexCoord2f(coordD.x, coordC.y);
            rlVertex2f(vertD.x, vertC.y);
            rlTexCoord2f(coordA.x, coordC.y);
            rlVertex2f(vertA.x, vertC.y);
        } else if (nPatchInfo.layout == NPATCH_THREE_PATCH_HORIZONTAL) {
            // LEFT QUAD
            rlTexCoord2f(coordA.x, coordD.y);
            rlVertex2f(vertA.x, vertD.y);
            rlTexCoord2f(coordB.x, coordD.y);
            rlVertex2f(vertB.x, vertD.y);
            rlTexCoord2f(coordB.x, coordA.y);
            rlVertex2f(vertB.x, vertA.y);
            rlTexCoord2f(coordA.x, coordA.y);
            rlVertex2f(vertA.x, vertA.y);
            if (drawCenter) {
                // CENTER QUAD
                rlTexCoord2f(coordB.x, coordD.y);
                rlVertex2f(vertB.x, vertD.y);
                rlTexCoord2f(coordC.x, coordD.y);
                rlVertex2f(vertC.x, vertD.y);
                rlTexCoord2f(coordC.x, coordA.y);
                rlVertex2f(vertC.x, vertA.y);
                rlTexCoord2f(coordB.x, coordA.y);
                rlVertex2f(vertB.x, vertA.y);
            }
            // RIGHT QUAD
            rlTexCoord2f(coordC.x, coordD.y);
            rlVertex2f(vertC.x, vertD.y);
            rlTexCoord2f(coordD.x, coordD.y);
            rlVertex2f(vertD.x, vertD.y);
            rlTexCoord2f(coordD.x, coordA.y);
            rlVertex2f(vertD.x, vertA.y);
            rlTexCoord2f(coordC.x, coordA.y);
            rlVertex2f(vertC.x, vertA.y);
        }
        rlEnd();
        rlPopMatrix();

        rlSetTexture(0);
    }
}

//------------------------------------------------------------------------------------
// Color/pixel related functions
//------------------------------------------------------------------------------------
// Check if two colors are equal
export fn ColorIsEqual(col1: Color, col2: Color) callconv(.c) bool {
    return (col1.r == col2.r) and (col1.g == col2.g) and (col1.b == col2.b) and (col1.a == col2.a);
}

// Get color with alpha applied, alpha goes from 0.0f to 1.0f
export fn Fade(color: Color, alpha_in: f32) callconv(.c) Color {
    var result = color;
    var alpha = alpha_in;

    if (alpha < 0.0) alpha = 0.0 else if (alpha > 1.0) alpha = 1.0;

    result.a = tuc(255.0 * alpha);

    return result;
}

// Get hexadecimal value for a Color
export fn ColorToInt(color: Color) callconv(.c) c_int {
    const result: c_uint = (@as(c_uint, color.r) << 24) |
        (@as(c_uint, color.g) << 16) |
        (@as(c_uint, color.b) << 8) |
        @as(c_uint, color.a);
    return @bitCast(result);
}

// Get color normalized as float [0..1]
export fn ColorNormalize(color: Color) callconv(.c) Vector4 {
    var result: Vector4 = undefined;
    result.x = @as(f32, @floatFromInt(color.r)) / 255.0;
    result.y = @as(f32, @floatFromInt(color.g)) / 255.0;
    result.z = @as(f32, @floatFromInt(color.b)) / 255.0;
    result.w = @as(f32, @floatFromInt(color.a)) / 255.0;
    return result;
}

// Get color from normalized values [0..1]
export fn ColorFromNormalized(normalized: Vector4) callconv(.c) Color {
    var result: Color = undefined;
    result.r = tuc(normalized.x * 255.0);
    result.g = tuc(normalized.y * 255.0);
    result.b = tuc(normalized.z * 255.0);
    result.a = tuc(normalized.w * 255.0);
    return result;
}

// Get HSV values for a Color, Hue [0..360], Saturation/Value [0..1]
export fn ColorToHSV(color: Color) callconv(.c) Vector3 {
    var hsv: Vector3 = .{ .x = 0, .y = 0, .z = 0 };
    const rgb = Vector3{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0 };
    var min: f32 = 0.0;
    var max: f32 = 0.0;
    var delta: f32 = 0.0;

    min = if (rgb.x < rgb.y) rgb.x else rgb.y;
    min = if (min < rgb.z) min else rgb.z;

    max = if (rgb.x > rgb.y) rgb.x else rgb.y;
    max = if (max > rgb.z) max else rgb.z;

    hsv.z = max; // Value
    delta = max - min;

    if (delta < 0.00001) {
        hsv.y = 0.0;
        hsv.x = 0.0;
        return hsv;
    }

    if (max > 0.0) {
        hsv.y = (delta / max); // Saturation
    } else {
        hsv.y = 0.0;
        hsv.x = NAN;
        return hsv;
    }

    if (rgb.x >= max) {
        hsv.x = (rgb.y - rgb.z) / delta; // Between yellow & magenta
    } else {
        if (rgb.y >= max) {
            hsv.x = 2.0 + (rgb.z - rgb.x) / delta; // Between cyan & yellow
        } else hsv.x = 4.0 + (rgb.x - rgb.y) / delta; // Between magenta & cyan
    }

    hsv.x *= 60.0; // Convert to degrees

    if (hsv.x < 0.0) hsv.x += 360.0;

    return hsv;
}

// Get a Color from HSV values, hue [0..360], saturation/value [0..1]
export fn ColorFromHSV(hue: f32, saturation: f32, value: f32) callconv(.c) Color {
    var color = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

    // Red channel
    var k = fmodf((5.0 + hue / 60.0), 6);
    var t = 4.0 - k;
    k = if (t < k) t else k;
    k = if (k < 1) k else 1;
    k = if (k > 0) k else 0;
    color.r = tuc((value - value * saturation * k) * 255.0);

    // Green channel
    k = fmodf((3.0 + hue / 60.0), 6);
    t = 4.0 - k;
    k = if (t < k) t else k;
    k = if (k < 1) k else 1;
    k = if (k > 0) k else 0;
    color.g = tuc((value - value * saturation * k) * 255.0);

    // Blue channel
    k = fmodf((1.0 + hue / 60.0), 6);
    t = 4.0 - k;
    k = if (t < k) t else k;
    k = if (k < 1) k else 1;
    k = if (k > 0) k else 0;
    color.b = tuc((value - value * saturation * k) * 255.0);

    return color;
}

// Get color multiplied with another color
export fn ColorTint(color: Color, tint: Color) callconv(.c) Color {
    return .{
        .r = iuc(@divTrunc(@as(c_int, color.r) * @as(c_int, tint.r), 255)),
        .g = iuc(@divTrunc(@as(c_int, color.g) * @as(c_int, tint.g), 255)),
        .b = iuc(@divTrunc(@as(c_int, color.b) * @as(c_int, tint.b), 255)),
        .a = iuc(@divTrunc(@as(c_int, color.a) * @as(c_int, tint.a), 255)),
    };
}

// Get color with brightness correction, brightness factor goes from -1.0f to 1.0f
export fn ColorBrightness(color: Color, factor_in: f32) callconv(.c) Color {
    var result = color;
    var factor = factor_in;

    if (factor > 1.0) factor = 1.0 else if (factor < -1.0) factor = -1.0;

    var red: f32 = @floatFromInt(color.r);
    var green: f32 = @floatFromInt(color.g);
    var blue: f32 = @floatFromInt(color.b);

    if (factor < 0.0) {
        factor = 1.0 + factor;
        red *= factor;
        green *= factor;
        blue *= factor;
    } else {
        red = (255 - red) * factor + red;
        green = (255 - green) * factor + green;
        blue = (255 - blue) * factor + blue;
    }

    result.r = tuc(red);
    result.g = tuc(green);
    result.b = tuc(blue);

    return result;
}

// Get color with contrast correction, contrast [-1.0f..1.0f]
export fn ColorContrast(color: Color, contrast_in: f32) callconv(.c) Color {
    var result = color;
    var contrast = contrast_in;

    if (contrast < -1.0) contrast = -1.0 else if (contrast > 1.0) contrast = 1.0;

    contrast = (1.0 + contrast);
    contrast *= contrast;

    var pR: f32 = @as(f32, @floatFromInt(color.r)) / 255.0;
    pR -= 0.5;
    pR *= contrast;
    pR += 0.5;
    pR *= 255;
    if (pR < 0) pR = 0 else if (pR > 255) pR = 255;

    var pG: f32 = @as(f32, @floatFromInt(color.g)) / 255.0;
    pG -= 0.5;
    pG *= contrast;
    pG += 0.5;
    pG *= 255;
    if (pG < 0) pG = 0 else if (pG > 255) pG = 255;

    var pB: f32 = @as(f32, @floatFromInt(color.b)) / 255.0;
    pB -= 0.5;
    pB *= contrast;
    pB += 0.5;
    pB *= 255;
    if (pB < 0) pB = 0 else if (pB > 255) pB = 255;

    result.r = tuc(pR);
    result.g = tuc(pG);
    result.b = tuc(pB);

    return result;
}

// Get color with alpha applied, alpha goes from 0.0f to 1.0f
export fn ColorAlpha(color: Color, alpha_in: f32) callconv(.c) Color {
    var result = color;
    var alpha = alpha_in;

    if (alpha < 0.0) alpha = 0.0 else if (alpha > 1.0) alpha = 1.0;

    result.a = tuc(255.0 * alpha);

    return result;
}

// Get src alpha-blended into dst color with tint
export fn ColorAlphaBlend(dst: Color, src_in: Color, tint: Color) callconv(.c) Color {
    var result = WHITE;
    var src = src_in;

    // Apply color tint to source color
    src.r = @truncate((@as(c_uint, src.r) * (@as(c_uint, tint.r) + 1)) >> 8);
    src.g = @truncate((@as(c_uint, src.g) * (@as(c_uint, tint.g) + 1)) >> 8);
    src.b = @truncate((@as(c_uint, src.b) * (@as(c_uint, tint.b) + 1)) >> 8);
    src.a = @truncate((@as(c_uint, src.a) * (@as(c_uint, tint.a) + 1)) >> 8);

    if (src.a == 0) {
        result = dst;
    } else if (src.a == 255) {
        result = src;
    } else {
        const alpha: c_uint = @as(c_uint, src.a) + 1; // Shifting by 8 (dividing by 256)
        result.a = @truncate((alpha * 256 + @as(c_uint, dst.a) * (256 - alpha)) >> 8);

        if (result.a > 0) {
            result.r = @truncate(((@as(c_uint, src.r) * alpha * 256 + @as(c_uint, dst.r) * @as(c_uint, dst.a) * (256 - alpha)) / @as(c_uint, result.a)) >> 8);
            result.g = @truncate(((@as(c_uint, src.g) * alpha * 256 + @as(c_uint, dst.g) * @as(c_uint, dst.a) * (256 - alpha)) / @as(c_uint, result.a)) >> 8);
            result.b = @truncate(((@as(c_uint, src.b) * alpha * 256 + @as(c_uint, dst.b) * @as(c_uint, dst.a) * (256 - alpha)) / @as(c_uint, result.a)) >> 8);
        }
    }

    return result;
}

// Get color lerp interpolation between two colors, factor [0.0f..1.0f]
export fn ColorLerp(color1: Color, color2: Color, factor_in: f32) callconv(.c) Color {
    var color: Color = BLANK;
    var factor = factor_in;

    if (factor < 0.0) factor = 0.0 else if (factor > 1.0) factor = 1.0;

    color.r = tuc((1.0 - factor) * @as(f32, @floatFromInt(color1.r)) + factor * @as(f32, @floatFromInt(color2.r)));
    color.g = tuc((1.0 - factor) * @as(f32, @floatFromInt(color1.g)) + factor * @as(f32, @floatFromInt(color2.g)));
    color.b = tuc((1.0 - factor) * @as(f32, @floatFromInt(color1.b)) + factor * @as(f32, @floatFromInt(color2.b)));
    color.a = tuc((1.0 - factor) * @as(f32, @floatFromInt(color1.a)) + factor * @as(f32, @floatFromInt(color2.a)));

    return color;
}

// Get a Color struct from hexadecimal value
export fn GetColor(hexValue: c_uint) callconv(.c) Color {
    var color: Color = undefined;

    color.r = @truncate((hexValue >> 24) & 0xff);
    color.g = @truncate((hexValue >> 16) & 0xff);
    color.b = @truncate((hexValue >> 8) & 0xff);
    color.a = @truncate(hexValue & 0xff);

    return color;
}

// Get color from a pixel from certain format
// NOTE: Unlike LoadImageColors, 16-bit formats are scaled with integer math
export fn GetPixelColor(srcPtr: ?*const anyopaque, format: c_int) callconv(.c) Color {
    const src: [*]const u8 = @ptrCast(srcPtr);

    return switch (format) {
        PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => .{ .r = src[0], .g = src[0], .b = src[0], .a = 255 },
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => .{ .r = src[0], .g = src[0], .b = src[0], .a = src[1] },
        PIXELFORMAT_UNCOMPRESSED_R5G6B5 => blk: {
            const pixel: c_int = u16s(src)[0];
            break :blk .{
                .r = iuc(@divTrunc((pixel >> 11) * 255, 31)),
                .g = iuc(@divTrunc(((pixel >> 5) & 0b0000000000111111) * 255, 63)),
                .b = iuc(@divTrunc((pixel & 0b0000000000011111) * 255, 31)),
                .a = 255,
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => blk: {
            const pixel: c_int = u16s(src)[0];
            break :blk .{
                .r = iuc(@divTrunc((pixel >> 11) * 255, 31)),
                .g = iuc(@divTrunc(((pixel >> 6) & 0b0000000000011111) * 255, 31)),
                .b = iuc(@divTrunc(((pixel >> 1) & 0b0000000000011111) * 255, 31)),
                .a = if ((pixel & 0b0000000000000001) != 0) 255 else 0,
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => blk: {
            const pixel: c_int = u16s(src)[0];
            break :blk .{
                .r = iuc(@divTrunc((pixel >> 12) * 255, 15)),
                .g = iuc(@divTrunc(((pixel >> 8) & 0b0000000000001111) * 255, 15)),
                .b = iuc(@divTrunc(((pixel >> 4) & 0b0000000000001111) * 255, 15)),
                .a = iuc(@divTrunc((pixel & 0b0000000000001111) * 255, 15)),
            };
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => .{ .r = src[0], .g = src[1], .b = src[2], .a = src[3] },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8 => .{ .r = src[0], .g = src[1], .b = src[2], .a = 255 },
        // NOTE: Single-channel float formats read as gray here (LoadImageColors reads red)
        PIXELFORMAT_UNCOMPRESSED_R32 => blk: {
            const value = tuc(f32s(src)[0] * 255.0);
            break :blk .{ .r = value, .g = value, .b = value, .a = 255 };
        },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32 => .{
            .r = tuc(f32s(src)[0] * 255.0),
            .g = tuc(f32s(src)[1] * 255.0),
            .b = tuc(f32s(src)[2] * 255.0),
            .a = 255,
        },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => .{
            .r = tuc(f32s(src)[0] * 255.0),
            .g = tuc(f32s(src)[1] * 255.0),
            .b = tuc(f32s(src)[2] * 255.0),
            .a = tuc(f32s(src)[3] * 255.0),
        },
        PIXELFORMAT_UNCOMPRESSED_R16 => blk: {
            const value = tuc(encode.halfToFloat(u16s(src)[0]) * 255.0);
            break :blk .{ .r = value, .g = value, .b = value, .a = 255 };
        },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16 => .{
            .r = tuc(encode.halfToFloat(u16s(src)[0]) * 255.0),
            .g = tuc(encode.halfToFloat(u16s(src)[1]) * 255.0),
            .b = tuc(encode.halfToFloat(u16s(src)[2]) * 255.0),
            .a = 255,
        },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => .{
            .r = tuc(encode.halfToFloat(u16s(src)[0]) * 255.0),
            .g = tuc(encode.halfToFloat(u16s(src)[1]) * 255.0),
            .b = tuc(encode.halfToFloat(u16s(src)[2]) * 255.0),
            .a = tuc(encode.halfToFloat(u16s(src)[3]) * 255.0),
        },
        else => BLANK,
    };
}

// Set pixel color formatted into destination pointer
// NOTE: Only formats up to 8 bits per channel are written; others are ignored
export fn SetPixelColor(dstPtr: ?*anyopaque, color: Color, format: c_int) callconv(.c) void {
    if ((format >= PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) and (format <= PIXELFORMAT_UNCOMPRESSED_R8G8B8A8)) {
        writeColor(@ptrCast(dstPtr), color, format);
    }
}

// Get pixel data size in bytes for certain format
export fn GetPixelDataSize(width: c_int, height: c_int, format: c_int) callconv(.c) c_int {
    var dataSize: c_int = 0; // Size in bytes
    var bpp: c_int = 0; // Bits per pixel

    if ((width <= 0) or (height <= 0)) return dataSize;

    switch (format) {
        PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => bpp = 8,
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA,
        PIXELFORMAT_UNCOMPRESSED_R5G6B5,
        PIXELFORMAT_UNCOMPRESSED_R5G5B5A1,
        PIXELFORMAT_UNCOMPRESSED_R4G4B4A4,
        => bpp = 16,
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => bpp = 32,
        PIXELFORMAT_UNCOMPRESSED_R8G8B8 => bpp = 24,
        PIXELFORMAT_UNCOMPRESSED_R32 => bpp = 32,
        PIXELFORMAT_UNCOMPRESSED_R32G32B32 => bpp = 32 * 3,
        PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => bpp = 32 * 4,
        PIXELFORMAT_UNCOMPRESSED_R16 => bpp = 16,
        PIXELFORMAT_UNCOMPRESSED_R16G16B16 => bpp = 16 * 3,
        PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => bpp = 16 * 4,
        PIXELFORMAT_COMPRESSED_DXT1_RGB,
        PIXELFORMAT_COMPRESSED_DXT1_RGBA,
        PIXELFORMAT_COMPRESSED_ETC1_RGB,
        PIXELFORMAT_COMPRESSED_ETC2_RGB,
        PIXELFORMAT_COMPRESSED_PVRT_RGB,
        PIXELFORMAT_COMPRESSED_PVRT_RGBA,
        => bpp = 4,
        PIXELFORMAT_COMPRESSED_DXT3_RGBA,
        PIXELFORMAT_COMPRESSED_DXT5_RGBA,
        PIXELFORMAT_COMPRESSED_ETC2_EAC_RGBA,
        PIXELFORMAT_COMPRESSED_ASTC_4x4_RGBA,
        => bpp = 8,
        PIXELFORMAT_COMPRESSED_ASTC_8x8_RGBA => bpp = 2,
        else => {},
    }

    // Size in bytes (bits divided by 8); width/height are positive here, bpp is non-negative
    const dataSizeBytes = (@as(u64, @intCast(width)) * @as(u64, @intCast(height)) * @as(u64, @intCast(bpp))) >> 3;

    if (dataSizeBytes >= std.math.maxInt(c_int)) {
        // NOTE: In case required image data larger than 2GB, no memory allocated at all (NULL)
        TraceLog(LOG_WARNING, "Requested image size is larger than 2GB, it can not be allocated");
        return dataSize;
    }

    dataSize = @intCast(dataSizeBytes);

    // Most compressed formats works on 4x4 blocks,
    // if texture is smaller, minimum dataSize is 8 or 16
    if ((width < 4) and (height < 4)) {
        if ((format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) and (format < PIXELFORMAT_COMPRESSED_DXT3_RGBA)) {
            dataSize = 8;
        } else if ((format >= PIXELFORMAT_COMPRESSED_DXT3_RGBA) and (format < PIXELFORMAT_COMPRESSED_ASTC_8x8_RGBA)) dataSize = 16;
    }

    return dataSize;
}
