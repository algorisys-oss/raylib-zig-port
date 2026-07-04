//! rtextures - Basic functions to load and draw textures
//!
//! Zig port of raylib's `rtextures.c`. Every public raylib texture/image function is
//! exported with its exact C name, byte-compatible signature, and C calling convention,
//! so the rest of raylib (still C) links against it unchanged. Floating-point operation
//! order matches the C source exactly to keep pixel output bit-identical, and libc/libm
//! functions are called via extern declarations rather than `std.math`.
//!
//! This build mirrors raylib's default `config.h`: enabled formats are PNG, BMP, GIF,
//! QOI, DDS; image export (PNG/QOI/BMP) and procedural image generation are enabled.
//! The third-party single-file libraries (stb_image, stb_image_write, stb_image_resize2,
//! qoi, stb_perlin, rltexgpu) are instantiated in the C shim `src/c/rtextures_stb_impl.c`
//! and only `extern`-declared and called here.

const std = @import("std");

//----------------------------------------------------------------------------------
// libc / libm functions, called directly so results are bit-identical to the C source.
//----------------------------------------------------------------------------------
extern fn malloc(usize) ?*anyopaque;
extern fn calloc(usize, usize) ?*anyopaque;
extern fn realloc(?*anyopaque, usize) ?*anyopaque;
extern fn free(?*anyopaque) void;
extern fn memcpy(noalias ?*anyopaque, noalias ?*const anyopaque, usize) ?*anyopaque;
extern fn memset(?*anyopaque, c_int, usize) ?*anyopaque;
extern fn strcmp([*c]const u8, [*c]const u8) c_int;
extern fn strlen([*c]const u8) usize;
extern fn strncpy(noalias [*c]u8, noalias [*c]const u8, usize) [*c]u8;
extern fn sprintf(noalias [*c]u8, noalias [*c]const u8, ...) c_int;

extern fn sinf(f32) f32;
extern fn cosf(f32) f32;
extern fn sqrtf(f32) f32;
extern fn powf(f32, f32) f32;
extern fn ceilf(f32) f32;
extern fn floorf(f32) f32;
extern fn logf(f32) f32;
extern fn fabsf(f32) f32;
extern fn fminf(f32, f32) f32;
extern fn fmaxf(f32, f32) f32;
extern fn fmodf(f32, f32) f32;
extern fn hypotf(f32, f32) f32;
// Double-precision libm (used verbatim where the C source used the non-f variants)
extern fn round(f64) f64;
extern fn pow(f64, f64) f64;
extern fn fmin(f64, f64) f64;
extern fn fmax(f64, f64) f64;
extern fn hypot(f64, f64) f64;

// raylib RL_MALLOC/RL_CALLOC/RL_FREE/RL_REALLOC map to malloc/calloc/free/realloc.
const RL_MALLOC = malloc;
const RL_CALLOC = calloc;
inline fn RL_FREE(p: anytype) void {
    free(@ptrCast(@constCast(p)));
}

const NAN: f32 = std.math.nan(f32);

//----------------------------------------------------------------------------------
// Cross-module raylib C symbols (still C in this build) - extern declared and called.
//----------------------------------------------------------------------------------
extern fn TraceLog(logLevel: c_int, text: [*c]const u8, ...) void;
extern fn LoadFileData(fileName: [*c]const u8, dataSize: [*c]c_int) [*c]u8;
extern fn SaveFileData(fileName: [*c]const u8, data: ?*const anyopaque, dataSize: c_int) bool;
extern fn UnloadFileData(data: [*c]u8) void;
extern fn SaveFileText(fileName: [*c]const u8, text: [*c]u8) bool;
extern fn GetFileExtension(fileName: [*c]const u8) [*c]const u8;
extern fn GetFileNameWithoutExt(filePath: [*c]const u8) [*c]const u8;
extern fn IsFileExtension(fileName: [*c]const u8, ext: [*c]const u8) bool;
extern fn GetRandomValue(min: c_int, max: c_int) c_int;
extern fn GetRenderWidth() c_int;
extern fn GetRenderHeight() c_int;

// [rtext] module functions required by image text drawing
extern fn LoadFontDefault() void;
extern fn GetFontDefault() Font;
extern fn GetGlyphIndex(font: Font, codepoint: c_int) c_int;
extern fn MeasureTextEx(font: Font, text: [*c]const u8, fontSize: f32, spacing: f32) Vector2;
extern fn GetCodepointNext(text: [*c]const u8, codepointSize: [*c]c_int) c_int;

//----------------------------------------------------------------------------------
// rlgl functions, provided by other translation units in the build.
//----------------------------------------------------------------------------------
extern fn rlLoadTexture(data: ?*const anyopaque, width: c_int, height: c_int, format: c_int, mipmapCount: c_int) c_uint;
extern fn rlLoadTextureDepth(width: c_int, height: c_int, useRenderBuffer: bool) c_uint;
extern fn rlLoadTextureCubemap(data: ?*const anyopaque, size: c_int, format: c_int, mipmapCount: c_int) c_uint;
extern fn rlUpdateTexture(id: c_uint, offsetX: c_int, offsetY: c_int, width: c_int, height: c_int, format: c_int, data: ?*const anyopaque) void;
extern fn rlUnloadTexture(id: c_uint) void;
extern fn rlGetPixelFormatName(format: c_uint) [*c]const u8;
extern fn rlTextureParameters(id: c_uint, param: c_int, value: c_int) void;
extern fn rlGenTextureMipmaps(id: c_uint, width: c_int, height: c_int, format: c_int, mipmaps: [*c]c_int) void;
extern fn rlReadTexturePixels(id: c_uint, width: c_int, height: c_int, format: c_int) ?*anyopaque;
extern fn rlReadScreenPixels(width: c_int, height: c_int) [*c]u8;
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
extern fn stbi_load_from_memory(buffer: [*c]const u8, len: c_int, x: [*c]c_int, y: [*c]c_int, channels_in_file: [*c]c_int, desired_channels: c_int) [*c]u8;
extern fn stbi_load_gif_from_memory(buffer: [*c]const u8, len: c_int, delays: [*c][*c]c_int, x: [*c]c_int, y: [*c]c_int, z: [*c]c_int, comp: [*c]c_int, req_comp: c_int) [*c]u8;
extern fn stbi_write_png_to_mem(pixels: [*c]const u8, stride_bytes: c_int, x: c_int, y: c_int, n: c_int, out_len: [*c]c_int) [*c]u8;
extern fn stbi_write_bmp(filename: [*c]const u8, w: c_int, h: c_int, comp: c_int, data: ?*const anyopaque) c_int;
extern fn stbir_resize_uint8_linear(input_pixels: [*c]const u8, input_w: c_int, input_h: c_int, input_stride_in_bytes: c_int, output_pixels: [*c]u8, output_w: c_int, output_h: c_int, output_stride_in_bytes: c_int, pixel_layout: c_int) [*c]u8;
extern fn qoi_decode(data: ?*const anyopaque, size: c_int, desc: [*c]qoi_desc, channels: c_int) ?*anyopaque;
extern fn qoi_write(filename: [*c]const u8, data: ?*const anyopaque, desc: [*c]const qoi_desc) c_int;
extern fn stb_perlin_fbm_noise3(x: f32, y: f32, z: f32, lacunarity: f32, gain: f32, octaves: c_int) f32;
extern fn rl_load_dds_from_memory(file_data: [*c]const u8, file_size: c_uint, width: [*c]c_int, height: [*c]c_int, format: [*c]c_int, mips: [*c]c_int) ?*anyopaque;

const qoi_desc = extern struct {
    width: c_uint,
    height: c_uint,
    channels: u8,
    colorspace: u8,
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
    data: ?*anyopaque,
    width: c_int,
    height: c_int,
    mipmaps: c_int,
    format: c_int,
};

pub const Texture = extern struct {
    id: c_uint,
    width: c_int,
    height: c_int,
    mipmaps: c_int,
    format: c_int,
};
pub const Texture2D = Texture;
pub const TextureCubemap = Texture;

pub const RenderTexture = extern struct {
    id: c_uint,
    texture: Texture,
    depth: Texture,
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

// C `MIN(a,b)` macro for ints.
inline fn MINi(a: c_int, b: c_int) c_int {
    return if (a < b) a else b;
}

// C `abs()` for c_int.
inline fn absi(v: c_int) c_int {
    return if (v < 0) -v else v;
}

// C-style pointer arithmetic: ptr + (signed) element offset.
inline fn ptrAdd(ptr: anytype, offset: c_int) @TypeOf(ptr) {
    const Elem = @typeInfo(@TypeOf(ptr)).pointer.child;
    const base = @intFromPtr(ptr);
    const delta: isize = @as(isize, offset) * @as(isize, @sizeOf(Elem));
    return @ptrFromInt(@as(usize, @bitCast(@as(isize, @bitCast(base)) +% delta)));
}

//----------------------------------------------------------------------------------
// Module Internal Functions Definition
//----------------------------------------------------------------------------------
// Convert half-float (stored as unsigned short) to float
fn HalfToFloat(x: u16) f32 {
    const e: c_uint = (@as(c_uint, x) & 0x7c00) >> 10; // Exponent
    const m: c_uint = (@as(c_uint, x) & 0x03ff) << 13; // Mantissa
    const fm: f32 = @floatFromInt(m);
    const v: c_uint = @as(c_uint, @bitCast(fm)) >> 23; // log2 bit hack to count leading zeros
    const sign: c_uint = (@as(c_uint, x) & 0x8000) << 16;
    const norm: c_uint = @intFromBool(e != 0) * (((e + 112) << 23) | m);
    const denorm: c_uint = (@intFromBool(e == 0) & @intFromBool(m != 0)) *
        (((v - 37) << 23) | ((m << @intCast(150 - v)) & 0x007fe000));
    const ui: c_uint = sign | norm | denorm;
    return @bitCast(ui);
}

// Convert float to half-float (stored as unsigned short)
fn FloatToHalf(x: f32) u16 {
    const b: c_uint = @as(c_uint, @bitCast(x)) +% 0x00001000; // Round-to-nearest-even
    const e: c_uint = (b & 0x7f800000) >> 23; // Exponent
    const m: c_uint = b & 0x007fffff; // Mantissa
    const sign: c_uint = (b & 0x80000000) >> 16;
    const norm: c_uint = @intFromBool(e > 112) * ((((e - 112) << 10) & 0x7c00) | (m >> 13));
    const denorm: c_uint = (@intFromBool(e < 113) & @intFromBool(e > 101)) *
        ((((0x007ff000 + m) >> @intCast(125 - e)) + 1) >> 1);
    const sat: c_uint = @as(c_uint, @intFromBool(e > 143)) * 0x7fff;
    return @truncate(sign | norm | denorm | sat);
}

// Get pixel data from image as Vector4 array (float normalized)
fn LoadImageDataNormalized(image: Image) [*c]Vector4 {
    const pixels: [*c]Vector4 = @ptrCast(@alignCast(RL_MALLOC(@intCast(image.width * image.height * @as(c_int, @sizeOf(Vector4))))));

    if (image.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "IMAGE: Pixel data retrieval not supported for compressed image formats");
    } else {
        const d8: [*]const u8 = @ptrCast(image.data);
        const d16: [*]const u16 = @ptrCast(@alignCast(image.data));
        const d32: [*]const f32 = @ptrCast(@alignCast(image.data));

        var i: usize = 0;
        var k: usize = 0;
        const total: usize = @intCast(image.width * image.height);
        while (i < total) : (i += 1) {
            switch (image.format) {
                PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => {
                    pixels[i].x = @as(f32, @floatFromInt(d8[i])) / 255.0;
                    pixels[i].y = @as(f32, @floatFromInt(d8[i])) / 255.0;
                    pixels[i].z = @as(f32, @floatFromInt(d8[i])) / 255.0;
                    pixels[i].w = 1.0;
                },
                PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
                    pixels[i].x = @as(f32, @floatFromInt(d8[k])) / 255.0;
                    pixels[i].y = @as(f32, @floatFromInt(d8[k])) / 255.0;
                    pixels[i].z = @as(f32, @floatFromInt(d8[k])) / 255.0;
                    pixels[i].w = @as(f32, @floatFromInt(d8[k + 1])) / 255.0;
                    k += 2;
                },
                PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
                    const pixel = d16[i];
                    pixels[i].x = @as(f32, @floatFromInt((pixel & 0b1111100000000000) >> 11)) * (1.0 / 31.0);
                    pixels[i].y = @as(f32, @floatFromInt((pixel & 0b0000011111000000) >> 6)) * (1.0 / 31.0);
                    pixels[i].z = @as(f32, @floatFromInt((pixel & 0b0000000000111110) >> 1)) * (1.0 / 31.0);
                    pixels[i].w = if ((pixel & 0b0000000000000001) == 0) 0.0 else 1.0;
                },
                PIXELFORMAT_UNCOMPRESSED_R5G6B5 => {
                    const pixel = d16[i];
                    pixels[i].x = @as(f32, @floatFromInt((pixel & 0b1111100000000000) >> 11)) * (1.0 / 31.0);
                    pixels[i].y = @as(f32, @floatFromInt((pixel & 0b0000011111100000) >> 5)) * (1.0 / 63.0);
                    pixels[i].z = @as(f32, @floatFromInt(pixel & 0b0000000000011111)) * (1.0 / 31.0);
                    pixels[i].w = 1.0;
                },
                PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
                    const pixel = d16[i];
                    pixels[i].x = @as(f32, @floatFromInt((pixel & 0b1111000000000000) >> 12)) * (1.0 / 15.0);
                    pixels[i].y = @as(f32, @floatFromInt((pixel & 0b0000111100000000) >> 8)) * (1.0 / 15.0);
                    pixels[i].z = @as(f32, @floatFromInt((pixel & 0b0000000011110000) >> 4)) * (1.0 / 15.0);
                    pixels[i].w = @as(f32, @floatFromInt(pixel & 0b0000000000001111)) * (1.0 / 15.0);
                },
                PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => {
                    pixels[i].x = @as(f32, @floatFromInt(d8[k])) / 255.0;
                    pixels[i].y = @as(f32, @floatFromInt(d8[k + 1])) / 255.0;
                    pixels[i].z = @as(f32, @floatFromInt(d8[k + 2])) / 255.0;
                    pixels[i].w = @as(f32, @floatFromInt(d8[k + 3])) / 255.0;
                    k += 4;
                },
                PIXELFORMAT_UNCOMPRESSED_R8G8B8 => {
                    pixels[i].x = @as(f32, @floatFromInt(d8[k])) / 255.0;
                    pixels[i].y = @as(f32, @floatFromInt(d8[k + 1])) / 255.0;
                    pixels[i].z = @as(f32, @floatFromInt(d8[k + 2])) / 255.0;
                    pixels[i].w = 1.0;
                    k += 3;
                },
                PIXELFORMAT_UNCOMPRESSED_R32 => {
                    pixels[i].x = d32[k];
                    pixels[i].y = 0.0;
                    pixels[i].z = 0.0;
                    pixels[i].w = 1.0;
                    k += 1;
                },
                PIXELFORMAT_UNCOMPRESSED_R32G32B32 => {
                    pixels[i].x = d32[k];
                    pixels[i].y = d32[k + 1];
                    pixels[i].z = d32[k + 2];
                    pixels[i].w = 1.0;
                    k += 3;
                },
                PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => {
                    pixels[i].x = d32[k];
                    pixels[i].y = d32[k + 1];
                    pixels[i].z = d32[k + 2];
                    pixels[i].w = d32[k + 3];
                    k += 4;
                },
                PIXELFORMAT_UNCOMPRESSED_R16 => {
                    pixels[i].x = HalfToFloat(d16[k]);
                    pixels[i].y = 0.0;
                    pixels[i].z = 0.0;
                    pixels[i].w = 1.0;
                    k += 1;
                },
                PIXELFORMAT_UNCOMPRESSED_R16G16B16 => {
                    pixels[i].x = HalfToFloat(d16[k]);
                    pixels[i].y = HalfToFloat(d16[k + 1]);
                    pixels[i].z = HalfToFloat(d16[k + 2]);
                    pixels[i].w = 1.0;
                    k += 3;
                },
                PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => {
                    pixels[i].x = HalfToFloat(d16[k]);
                    pixels[i].y = HalfToFloat(d16[k + 1]);
                    pixels[i].z = HalfToFloat(d16[k + 2]);
                    pixels[i].w = HalfToFloat(d16[k + 3]);
                    k += 4;
                },
                else => {},
            }
        }
    }

    return pixels;
}

//----------------------------------------------------------------------------------
// Module Functions Definition
//----------------------------------------------------------------------------------
// Load image from file into CPU memory (RAM)
export fn LoadImage(fileName: [*c]const u8) callconv(.c) Image {
    var image: Image = std.mem.zeroes(Image);

    // Loading file to memory
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);

    if (fileData != null) {
        image = LoadImageFromMemory(GetFileExtension(fileName), fileData, dataSize);
        UnloadFileData(fileData);
    }

    return image;
}

// Load an image from RAW file data
export fn LoadImageRaw(fileName: [*c]const u8, width: c_int, height: c_int, format: c_int, headerSize: c_int) callconv(.c) Image {
    var image: Image = std.mem.zeroes(Image);

    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);

    if (fileData != null) {
        var dataPtr: [*c]u8 = fileData;
        const size = GetPixelDataSize(width, height, format);

        if (size <= dataSize) { // Security check
            if ((headerSize > 0) and ((headerSize + size) <= dataSize)) dataPtr = ptrAdd(dataPtr, headerSize);

            image.data = RL_MALLOC(@intCast(size)); // Allocate required memory in bytes
            _ = memcpy(image.data, dataPtr, @intCast(size)); // Copy required data to image
            image.width = width;
            image.height = height;
            image.mipmaps = 1;
            image.format = format;
        }

        UnloadFileData(fileData);
    }

    return image;
}

// Load animated image data
export fn LoadImageAnim(fileName: [*c]const u8, frames: [*c]c_int) callconv(.c) Image {
    var image: Image = std.mem.zeroes(Image);
    var frameCount: c_int = 0;

    if (IsFileExtension(fileName, ".gif")) {
        var dataSize: c_int = 0;
        const fileData = LoadFileData(fileName, &dataSize);

        if (fileData != null) {
            var comp: c_int = 0;
            var delays: [*c]c_int = null;
            image.data = stbi_load_gif_from_memory(fileData, dataSize, &delays, &image.width, &image.height, &frameCount, &comp, 4);

            image.mipmaps = 1;
            image.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

            UnloadFileData(fileData);
            RL_FREE(delays); // NOTE: Frames delays are discarded
        }
    } else {
        image = LoadImage(fileName);
        frameCount = 1;
    }

    frames.* = frameCount;
    return image;
}

// Load animated image data from memory
export fn LoadImageAnimFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: c_int, frames: [*c]c_int) callconv(.c) Image {
    var image: Image = std.mem.zeroes(Image);
    var frameCount: c_int = 0;

    if ((fileType == null) or (fileData == null) or (dataSize == 0)) return image; // Security check

    if ((strcmp(fileType, ".gif") == 0) or (strcmp(fileType, ".GIF") == 0)) {
        if (fileData != null) {
            var comp: c_int = 0;
            var delays: [*c]c_int = null;
            image.data = stbi_load_gif_from_memory(fileData, dataSize, &delays, &image.width, &image.height, &frameCount, &comp, 4);

            image.mipmaps = 1;
            image.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

            RL_FREE(delays); // NOTE: Frames delays are discarded
        }
    } else {
        image = LoadImageFromMemory(fileType, fileData, dataSize);
        frameCount = 1;
    }

    frames.* = frameCount;
    return image;
}

// Load image from memory buffer, fileType refers to extension: i.e. ".png"
export fn LoadImageFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: c_int) callconv(.c) Image {
    var image: Image = std.mem.zeroes(Image);

    // Security checks for input data
    if ((fileData == null) or (dataSize == 0)) {
        TraceLog(LOG_WARNING, "IMAGE: Invalid file data");
        return image;
    }
    if (fileType == null) {
        TraceLog(LOG_WARNING, "IMAGE: Missing file extension");
        return image;
    }

    if ((strcmp(fileType, ".png") == 0) or (strcmp(fileType, ".PNG") == 0) or
        (strcmp(fileType, ".bmp") == 0) or (strcmp(fileType, ".BMP") == 0) or
        (strcmp(fileType, ".gif") == 0) or (strcmp(fileType, ".GIF") == 0))
    {
        // NOTE: Using stb_image to load images (Supports multiple image formats)
        if (fileData != null) {
            var comp: c_int = 0;
            image.data = stbi_load_from_memory(fileData, dataSize, &image.width, &image.height, &comp, 0);

            if (image.data != null) {
                image.mipmaps = 1;

                if (comp == 1) {
                    image.format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE;
                } else if (comp == 2) {
                    image.format = PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA;
                } else if (comp == 3) {
                    image.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8;
                } else if (comp == 4) {
                    image.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
                }
            }
        }
    } else if ((strcmp(fileType, ".qoi") == 0) or (strcmp(fileType, ".QOI") == 0)) {
        if (fileData != null) {
            var desc: qoi_desc = std.mem.zeroes(qoi_desc);
            image.data = qoi_decode(fileData, dataSize, &desc, @as(c_int, fileData[12]));
            image.width = @intCast(desc.width);
            image.height = @intCast(desc.height);
            image.format = if (desc.channels == 4) PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 else PIXELFORMAT_UNCOMPRESSED_R8G8B8;
            image.mipmaps = 1;
        }
    } else if ((strcmp(fileType, ".dds") == 0) or (strcmp(fileType, ".DDS") == 0)) {
        image.data = rl_load_dds_from_memory(fileData, @intCast(dataSize), &image.width, &image.height, &image.format, &image.mipmaps);
    } else TraceLog(LOG_WARNING, "IMAGE: Data format not supported");

    if (image.data != null) {
        TraceLog(LOG_INFO, "IMAGE: Data loaded successfully (%ix%i | %s | %i mipmaps)", image.width, image.height, rlGetPixelFormatName(@intCast(image.format)), image.mipmaps);
    } else TraceLog(LOG_WARNING, "IMAGE: Failed to load image data");

    return image;
}

// Load image from GPU texture data
export fn LoadImageFromTexture(texture: Texture2D) callconv(.c) Image {
    var image: Image = std.mem.zeroes(Image);

    if (texture.format < PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        image.data = rlReadTexturePixels(texture.id, texture.width, texture.height, texture.format);

        if (image.data != null) {
            image.width = texture.width;
            image.height = texture.height;
            image.format = texture.format;
            image.mipmaps = 1;

            TraceLog(LOG_INFO, "TEXTURE: [ID %i] Pixel data retrieved successfully", texture.id);
        } else TraceLog(LOG_WARNING, "TEXTURE: [ID %i] Failed to retrieve pixel data", texture.id);
    } else TraceLog(LOG_WARNING, "TEXTURE: [ID %i] Failed to retrieve compressed pixel data", texture.id);

    return image;
}

// Load image from screen buffer (screenshot)
export fn LoadImageFromScreen() callconv(.c) Image {
    var image: Image = std.mem.zeroes(Image);

    image.width = GetRenderWidth();
    image.height = GetRenderHeight();
    image.mipmaps = 1;
    image.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
    image.data = rlReadScreenPixels(image.width, image.height);

    return image;
}

// Check if an image is valid
export fn IsImageValid(image: Image) callconv(.c) bool {
    var result = false;

    if ((image.data != null) and
        (image.width > 0) and
        (image.height > 0) and
        (image.format > 0) and
        (image.mipmaps > 0)) result = true;

    return result;
}

// Unload image from CPU memory (RAM)
export fn UnloadImage(image: Image) callconv(.c) void {
    RL_FREE(image.data);
}

// Export image data to file
export fn ExportImage(image: Image, fileName: [*c]const u8) callconv(.c) bool {
    var result: c_int = 0;

    if ((image.width == 0) or (image.height == 0) or (image.data == null)) return result != 0; // Security check

    var channels: c_int = 4;
    var allocatedData = false;
    var imgData: [*c]u8 = @ptrCast(image.data);

    if (image.format == PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) {
        channels = 1;
    } else if (image.format == PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA) {
        channels = 2;
    } else if (image.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8) {
        channels = 3;
    } else if (image.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) {
        channels = 4;
    } else {
        // NOTE: Getting Color array as RGBA unsigned char values
        imgData = @ptrCast(LoadImageColors(image));
        allocatedData = true;
    }

    if (false) {} else if (IsFileExtension(fileName, ".png")) {
        var dataSize: c_int = 0;
        const fileData = stbi_write_png_to_mem(imgData, image.width * channels, image.width, image.height, channels, &dataSize);
        result = @intFromBool(SaveFileData(fileName, fileData, dataSize));
        RL_FREE(fileData);
    } else if (IsFileExtension(fileName, ".bmp")) {
        result = stbi_write_bmp(fileName, image.width, image.height, channels, imgData);
    } else if (IsFileExtension(fileName, ".qoi")) {
        channels = 0;
        if (image.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8) {
            channels = 3;
        } else if (image.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) {
            channels = 4;
        } else TraceLog(LOG_WARNING, "IMAGE: Image pixel format must be R8G8B8 or R8G8B8A8");

        if ((channels == 3) or (channels == 4)) {
            var desc: qoi_desc = std.mem.zeroes(qoi_desc);
            desc.width = @intCast(image.width);
            desc.height = @intCast(image.height);
            desc.channels = @intCast(channels);
            desc.colorspace = 0; // QOI_SRGB

            result = qoi_write(fileName, imgData, &desc);
        }
    } else if (IsFileExtension(fileName, ".raw")) {
        // Export raw pixel data (without header)
        result = @intFromBool(SaveFileData(fileName, image.data, GetPixelDataSize(image.width, image.height, image.format)));
    } else TraceLog(LOG_WARNING, "IMAGE: Export image format requested not supported");

    if (allocatedData) RL_FREE(imgData);

    if (result != 0) {
        TraceLog(LOG_INFO, "FILEIO: [%s] Image exported successfully", fileName);
    } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export image", fileName);

    return result != 0;
}

// Export image to memory buffer
export fn ExportImageToMemory(image: Image, fileType: [*c]const u8, dataSize: [*c]c_int) callconv(.c) [*c]u8 {
    var fileData: [*c]u8 = null;
    dataSize.* = 0;

    if ((image.width == 0) or (image.height == 0) or (image.data == null)) return fileData; // Security check

    var channels: c_int = 4;

    if (image.format == PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) {
        channels = 1;
    } else if (image.format == PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA) {
        channels = 2;
    } else if (image.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8) {
        channels = 3;
    } else if (image.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) {
        channels = 4;
    }

    if ((strcmp(fileType, ".png") == 0) or (strcmp(fileType, ".PNG") == 0)) {
        fileData = stbi_write_png_to_mem(@ptrCast(image.data), image.width * channels, image.width, image.height, channels, dataSize);
    }

    return fileData;
}

// Export image as code file (.h) defining an array of bytes
export fn ExportImageAsCode(image: Image, fileName: [*c]const u8) callconv(.c) bool {
    var result = false;

    const dataSize = GetPixelDataSize(image.width, image.height, image.format);

    // NOTE: Text data buffer size is estimated considering image data size in bytes
    // and requiring 6 char bytes for every byte: "0x00, "
    const txtData: [*c]u8 = @ptrCast(RL_CALLOC(@intCast(dataSize * 6 + 2000), @sizeOf(u8)));

    var byteCount: c_int = 0;
    byteCount += sprintf(ptrAdd(txtData, byteCount), "////////////////////////////////////////////////////////////////////////////////////////\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "//                                                                                    //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// ImageAsCode exporter v1.0 - Image pixel data exported as an array of bytes         //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "//                                                                                    //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// more info and bugs-report:  github.com/raysan5/raylib                              //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// feedback and support:       ray[at]raylib.com                                      //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "//                                                                                    //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// Copyright (c) 2018-2026 Ramon Santamaria (@raysan5)                                //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "//                                                                                    //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "////////////////////////////////////////////////////////////////////////////////////////\n\n");

    // Get file name from path and convert variable name to uppercase
    var varFileName = std.mem.zeroes([256]u8);
    _ = strncpy(&varFileName, GetFileNameWithoutExt(fileName), 256 - 1);
    {
        var i: usize = 0;
        while (varFileName[i] != 0) : (i += 1) {
            if ((varFileName[i] >= 'a') and (varFileName[i] <= 'z')) varFileName[i] = varFileName[i] - 32;
        }
    }

    // Add image information
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// Image data information\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "#define %s_WIDTH    %i\n", &varFileName, image.width);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "#define %s_HEIGHT   %i\n", &varFileName, image.height);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "#define %s_FORMAT   %i          // raylib internal pixel format\n\n", &varFileName, image.format);

    byteCount += sprintf(ptrAdd(txtData, byteCount), "static unsigned char %s_DATA[%i] = { ", &varFileName, dataSize);
    {
        const d8: [*]const u8 = @ptrCast(image.data);
        var i: c_int = 0;
        while (i < dataSize - 1) : (i += 1) {
            byteCount += sprintf(ptrAdd(txtData, byteCount), if (@rem(i, TEXT_BYTES_PER_LINE) == 0) "0x%x,\n" else "0x%x, ", @as(c_uint, d8[@intCast(i)]));
        }
        byteCount += sprintf(ptrAdd(txtData, byteCount), "0x%x };\n", @as(c_uint, d8[@intCast(dataSize - 1)]));
    }

    // NOTE: Text data size exported is determined by '\0' (NULL) character
    result = SaveFileText(fileName, txtData);

    RL_FREE(txtData);

    if (result) {
        TraceLog(LOG_INFO, "FILEIO: [%s] Image as code exported successfully", fileName);
    } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export image as code", fileName);

    return result;
}

//------------------------------------------------------------------------------------
// Image generation functions
//------------------------------------------------------------------------------------
// Generate image: plain color
export fn GenImageColor(width: c_int, height: c_int, color: Color) callconv(.c) Image {
    const pixels: [*c]Color = @ptrCast(@alignCast(RL_CALLOC(@intCast(width * height), @sizeOf(Color))));

    var i: usize = 0;
    const total: usize = @intCast(width * height);
    while (i < total) : (i += 1) pixels[i] = color;

    return .{
        .data = pixels,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
}

// Generate image: linear gradient
export fn GenImageGradientLinear(width: c_int, height: c_int, direction: c_int, start: Color, end: Color) callconv(.c) Image {
    const pixels: [*c]Color = @ptrCast(@alignCast(RL_MALLOC(@intCast(width * height * @as(c_int, @sizeOf(Color))))));

    const radianDirection: f32 = @as(f32, @floatFromInt(90 - direction)) / 180.0 * 3.14159;
    const cosDir = cosf(radianDirection);
    const sinDir = sinf(radianDirection);

    const startingPos: f32 = 0.5 - (cosDir * @as(f32, @floatFromInt(width)) / 2) - (sinDir * @as(f32, @floatFromInt(height)) / 2);

    const maxPosValue: f32 = if ((std.math.signbit(sinDir)) == (std.math.signbit(cosDir)))
        fabsf(startingPos)
    else
        fabsf(startingPos + @as(f32, @floatFromInt(width)) * cosDir);

    var i: c_int = 0;
    while (i < width) : (i += 1) {
        var j: c_int = 0;
        while (j < height) : (j += 1) {
            const pos: f32 = (startingPos + (@as(f32, @floatFromInt(i)) * cosDir + @as(f32, @floatFromInt(j)) * sinDir)) / maxPosValue;

            var factor = pos;
            factor = if (factor > 1.0) 1.0 else factor;
            factor = if (factor < -1.0) -1.0 else factor;
            factor = factor / 2.0 + 0.5;

            const idx: usize = @intCast(j * width + i);
            pixels[idx].r = tuc(@as(f32, @floatFromInt(end.r)) * factor + @as(f32, @floatFromInt(start.r)) * (1.0 - factor));
            pixels[idx].g = tuc(@as(f32, @floatFromInt(end.g)) * factor + @as(f32, @floatFromInt(start.g)) * (1.0 - factor));
            pixels[idx].b = tuc(@as(f32, @floatFromInt(end.b)) * factor + @as(f32, @floatFromInt(start.b)) * (1.0 - factor));
            pixels[idx].a = tuc(@as(f32, @floatFromInt(end.a)) * factor + @as(f32, @floatFromInt(start.a)) * (1.0 - factor));
        }
    }

    return .{
        .data = pixels,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
}

// Generate image: radial gradient
export fn GenImageGradientRadial(width: c_int, height: c_int, density: f32, inner: Color, outer: Color) callconv(.c) Image {
    const pixels: [*c]Color = @ptrCast(@alignCast(RL_MALLOC(@intCast(width * height * @as(c_int, @sizeOf(Color))))));
    const radius: f32 = if (width < height) @as(f32, @floatFromInt(width)) / 2.0 else @as(f32, @floatFromInt(height)) / 2.0;

    const centerX: f32 = @as(f32, @floatFromInt(width)) / 2.0;
    const centerY: f32 = @as(f32, @floatFromInt(height)) / 2.0;

    var y: c_int = 0;
    while (y < height) : (y += 1) {
        var x: c_int = 0;
        while (x < width) : (x += 1) {
            const dist = hypotf(@as(f32, @floatFromInt(x)) - centerX, @as(f32, @floatFromInt(y)) - centerY);
            var factor = (dist - radius * density) / (radius * (1.0 - density));

            factor = @floatCast(fmax(@floatCast(factor), 0.0));
            factor = @floatCast(fmin(@floatCast(factor), 1.0));

            const idx: usize = @intCast(y * width + x);
            pixels[idx].r = tuc(@as(f32, @floatFromInt(outer.r)) * factor + @as(f32, @floatFromInt(inner.r)) * (1.0 - factor));
            pixels[idx].g = tuc(@as(f32, @floatFromInt(outer.g)) * factor + @as(f32, @floatFromInt(inner.g)) * (1.0 - factor));
            pixels[idx].b = tuc(@as(f32, @floatFromInt(outer.b)) * factor + @as(f32, @floatFromInt(inner.b)) * (1.0 - factor));
            pixels[idx].a = tuc(@as(f32, @floatFromInt(outer.a)) * factor + @as(f32, @floatFromInt(inner.a)) * (1.0 - factor));
        }
    }

    return .{
        .data = pixels,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
}

// Generate image: square gradient
export fn GenImageGradientSquare(width: c_int, height: c_int, density: f32, inner: Color, outer: Color) callconv(.c) Image {
    const pixels: [*c]Color = @ptrCast(@alignCast(RL_MALLOC(@intCast(width * height * @as(c_int, @sizeOf(Color))))));

    const centerX: f32 = @as(f32, @floatFromInt(width)) / 2.0;
    const centerY: f32 = @as(f32, @floatFromInt(height)) / 2.0;

    var y: c_int = 0;
    while (y < height) : (y += 1) {
        var x: c_int = 0;
        while (x < width) : (x += 1) {
            // Calculate the Manhattan distance from the center
            const distX = fabsf(@as(f32, @floatFromInt(x)) - centerX);
            const distY = fabsf(@as(f32, @floatFromInt(y)) - centerY);

            const normalizedDistX = distX / centerX;
            const normalizedDistY = distY / centerY;

            const manhattanDist = fmaxf(normalizedDistX, normalizedDistY);

            const factor = (manhattanDist - density) / (1.0 - density);

            const clamped = fminf(fmaxf(factor, 0.0), 1.0);

            const idx: usize = @intCast(y * width + x);
            pixels[idx].r = tuc(@as(f32, @floatFromInt(outer.r)) * clamped + @as(f32, @floatFromInt(inner.r)) * (1.0 - clamped));
            pixels[idx].g = tuc(@as(f32, @floatFromInt(outer.g)) * clamped + @as(f32, @floatFromInt(inner.g)) * (1.0 - clamped));
            pixels[idx].b = tuc(@as(f32, @floatFromInt(outer.b)) * clamped + @as(f32, @floatFromInt(inner.b)) * (1.0 - clamped));
            pixels[idx].a = tuc(@as(f32, @floatFromInt(outer.a)) * clamped + @as(f32, @floatFromInt(inner.a)) * (1.0 - clamped));
        }
    }

    return .{
        .data = pixels,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
}

// Generate image: checked
export fn GenImageChecked(width: c_int, height: c_int, checksX: c_int, checksY: c_int, col1: Color, col2: Color) callconv(.c) Image {
    const pixels: [*c]Color = @ptrCast(@alignCast(RL_MALLOC(@intCast(width * height * @as(c_int, @sizeOf(Color))))));

    var y: c_int = 0;
    while (y < height) : (y += 1) {
        var x: c_int = 0;
        while (x < width) : (x += 1) {
            const idx: usize = @intCast(y * width + x);
            if (@rem(@divTrunc(x, checksX) + @divTrunc(y, checksY), 2) == 0) pixels[idx] = col1 else pixels[idx] = col2;
        }
    }

    return .{
        .data = pixels,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
}

// Generate image: white noise
export fn GenImageWhiteNoise(width: c_int, height: c_int, factor: f32) callconv(.c) Image {
    const pixels: [*c]Color = @ptrCast(@alignCast(RL_MALLOC(@intCast(width * height * @as(c_int, @sizeOf(Color))))));

    var i: usize = 0;
    const total: usize = @intCast(width * height);
    while (i < total) : (i += 1) {
        if (GetRandomValue(0, 99) < ti(factor * 100.0)) pixels[i] = WHITE else pixels[i] = BLACK;
    }

    return .{
        .data = pixels,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
}

// Generate image: perlin noise
export fn GenImagePerlinNoise(width: c_int, height: c_int, offsetX: c_int, offsetY: c_int, scale: f32) callconv(.c) Image {
    const pixels: [*c]Color = @ptrCast(@alignCast(RL_MALLOC(@intCast(width * height * @as(c_int, @sizeOf(Color))))));

    const aspectRatio: f32 = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

    var y: c_int = 0;
    while (y < height) : (y += 1) {
        var x: c_int = 0;
        while (x < width) : (x += 1) {
            var nx: f32 = @as(f32, @floatFromInt(x + offsetX)) * (scale / @as(f32, @floatFromInt(width)));
            var ny: f32 = @as(f32, @floatFromInt(y + offsetY)) * (scale / @as(f32, @floatFromInt(height)));

            if (width > height) nx *= aspectRatio else ny /= aspectRatio;

            var p = stb_perlin_fbm_noise3(nx, ny, 1.0, 2.0, 0.5, 6);

            if (p < -1.0) p = -1.0;
            if (p > 1.0) p = 1.0;

            const np: f32 = (p + 1.0) / 2.0;

            const intensity: u8 = tuc(np * 255.0);
            pixels[@intCast(y * width + x)] = .{ .r = intensity, .g = intensity, .b = intensity, .a = 255 };
        }
    }

    return .{
        .data = pixels,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
}

// Generate image: cellular algorithm
export fn GenImageCellular(width: c_int, height: c_int, tileSize: c_int) callconv(.c) Image {
    const pixels: [*c]Color = @ptrCast(@alignCast(RL_MALLOC(@intCast(width * height * @as(c_int, @sizeOf(Color))))));

    const seedsPerRow = @divTrunc(width, tileSize);
    const seedsPerCol = @divTrunc(height, tileSize);
    const seedCount = seedsPerRow * seedsPerCol;

    const seeds: [*c]Vector2 = @ptrCast(@alignCast(RL_MALLOC(@intCast(seedCount * @as(c_int, @sizeOf(Vector2))))));

    {
        var i: c_int = 0;
        while (i < seedCount) : (i += 1) {
            const yy = @divTrunc(i, seedsPerRow) * tileSize + GetRandomValue(0, tileSize - 1);
            const xx = @rem(i, seedsPerRow) * tileSize + GetRandomValue(0, tileSize - 1);
            seeds[@intCast(i)] = .{ .x = @floatFromInt(xx), .y = @floatFromInt(yy) };
        }
    }

    var y: c_int = 0;
    while (y < height) : (y += 1) {
        const tileY = @divTrunc(y, tileSize);

        var x: c_int = 0;
        while (x < width) : (x += 1) {
            const tileX = @divTrunc(x, tileSize);

            var minDistance: f32 = 65536.0;

            var i: c_int = -1;
            while (i < 2) : (i += 1) {
                if ((tileX + i < 0) or (tileX + i >= seedsPerRow)) continue;

                var j: c_int = -1;
                while (j < 2) : (j += 1) {
                    if ((tileY + j < 0) or (tileY + j >= seedsPerCol)) continue;

                    const neighborSeed = seeds[@intCast((tileY + j) * seedsPerRow + tileX + i)];

                    const dist: f32 = @floatCast(hypot(@floatFromInt(x - ti(neighborSeed.x)), @floatFromInt(y - ti(neighborSeed.y))));
                    minDistance = @floatCast(fmin(@floatCast(minDistance), @floatCast(dist)));
                }
            }

            var intensity = ti(minDistance * 256.0 / @as(f32, @floatFromInt(tileSize)));
            if (intensity > 255) intensity = 255;

            const intensityUC: u8 = iuc(intensity);
            pixels[@intCast(y * width + x)] = .{ .r = intensityUC, .g = intensityUC, .b = intensityUC, .a = 255 };
        }
    }

    RL_FREE(seeds);

    return .{
        .data = pixels,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
}

// Generate image: grayscale image from text data
export fn GenImageText(width: c_int, height: c_int, text: [*c]const u8) callconv(.c) Image {
    var image: Image = std.mem.zeroes(Image);

    const imageSize = width * height;
    image.width = width;
    image.height = height;
    image.format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE;
    image.data = RL_CALLOC(@intCast(imageSize), 1);
    image.mipmaps = 1;

    if (text != null) {
        const textLength: c_int = @intCast(strlen(text));
        _ = memcpy(image.data, text, @intCast(if (textLength > imageSize) imageSize else textLength));
    }

    return image;
}

//------------------------------------------------------------------------------------
// Image manipulation functions
//------------------------------------------------------------------------------------
// Copy an image to a new image
export fn ImageCopy(image: Image) callconv(.c) Image {
    var newImage: Image = std.mem.zeroes(Image);

    var width = image.width;
    var height = image.height;
    var size: c_int = 0;

    var i: c_int = 0;
    while (i < image.mipmaps) : (i += 1) {
        size += GetPixelDataSize(width, height, image.format);

        width = @divTrunc(width, 2);
        height = @divTrunc(height, 2);

        if (width < 1) width = 1;
        if (height < 1) height = 1;
    }

    newImage.data = RL_CALLOC(@intCast(size), 1);

    if (newImage.data != null) {
        _ = memcpy(newImage.data, image.data, @intCast(size));

        newImage.width = image.width;
        newImage.height = image.height;
        newImage.mipmaps = image.mipmaps;
        newImage.format = image.format;
    }

    return newImage;
}

// Create an image from another image piece
export fn ImageFromImage(image: Image, rec: Rectangle) callconv(.c) Image {
    var result: Image = std.mem.zeroes(Image);

    const bytesPerPixel = GetPixelDataSize(1, 1, image.format);

    result.width = ti(rec.width);
    result.height = ti(rec.height);
    result.data = RL_CALLOC(@intCast(ti(rec.width) * ti(rec.height) * bytesPerPixel), 1);
    result.format = image.format;
    result.mipmaps = 1;

    const dst8: [*]u8 = @ptrCast(result.data);
    const src8: [*]const u8 = @ptrCast(image.data);

    var y: c_int = 0;
    while (y < ti(rec.height)) : (y += 1) {
        _ = memcpy(
            dst8 + @as(usize, @intCast(y * ti(rec.width) * bytesPerPixel)),
            src8 + @as(usize, @intCast(((y + ti(rec.y)) * image.width + ti(rec.x)) * bytesPerPixel)),
            @intCast(ti(rec.width) * bytesPerPixel),
        );
    }

    return result;
}

// Create an image from a selected channel of another image
export fn ImageFromChannel(image: Image, selectedChannel_in: c_int) callconv(.c) Image {
    var result: Image = std.mem.zeroes(Image);
    var selectedChannel = selectedChannel_in;

    if ((image.data == null) or (image.width == 0) or (image.height == 0)) return result; // Security check

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

    if (selectedChannel > 3) {
        TraceLog(LOG_WARNING, "ImageFromChannel supports channels 0 to 3 (RGBA). Setting channel to alpha.");
        selectedChannel = 3;
    }

    result.format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE;
    result.height = image.height;
    result.width = image.width;
    result.mipmaps = 1;

    const pixels: [*c]u8 = @ptrCast(RL_CALLOC(@intCast(image.width * image.height), @sizeOf(u8)));

    if (image.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "IMAGE: Pixel data retrieval not supported for compressed image formats");
    } else {
        const d8: [*]const u8 = @ptrCast(image.data);
        const d16: [*]const u16 = @ptrCast(@alignCast(image.data));
        const d32: [*]const f32 = @ptrCast(@alignCast(image.data));
        const sc: usize = @intCast(selectedChannel);

        var i: usize = 0;
        var k: usize = 0;
        const total: usize = @intCast(image.width * image.height);
        while (i < total) : (i += 1) {
            var pixelValue: f32 = -1;
            switch (image.format) {
                PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => {
                    pixelValue = @as(f32, @floatFromInt(d8[i + sc])) / 255.0;
                },
                PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
                    pixelValue = @as(f32, @floatFromInt(d8[k + sc])) / 255.0;
                    k += 2;
                },
                PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
                    const pixel = d16[i];
                    if (selectedChannel == 0) {
                        pixelValue = @as(f32, @floatFromInt((pixel & 0b1111100000000000) >> 11)) * (1.0 / 31.0);
                    } else if (selectedChannel == 1) {
                        pixelValue = @as(f32, @floatFromInt((pixel & 0b0000011111000000) >> 6)) * (1.0 / 31.0);
                    } else if (selectedChannel == 2) {
                        pixelValue = @as(f32, @floatFromInt((pixel & 0b0000000000111110) >> 1)) * (1.0 / 31.0);
                    } else if (selectedChannel == 3) {
                        pixelValue = if ((pixel & 0b0000000000000001) == 0) 0.0 else 1.0;
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R5G6B5 => {
                    const pixel = d16[i];
                    if (selectedChannel == 0) {
                        pixelValue = @as(f32, @floatFromInt((pixel & 0b1111100000000000) >> 11)) * (1.0 / 31.0);
                    } else if (selectedChannel == 1) {
                        pixelValue = @as(f32, @floatFromInt((pixel & 0b0000011111100000) >> 5)) * (1.0 / 63.0);
                    } else if (selectedChannel == 2) {
                        pixelValue = @as(f32, @floatFromInt(pixel & 0b0000000000011111)) * (1.0 / 31.0);
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
                    const pixel = d16[i];
                    if (selectedChannel == 0) {
                        pixelValue = @as(f32, @floatFromInt((pixel & 0b1111000000000000) >> 12)) * (1.0 / 15.0);
                    } else if (selectedChannel == 1) {
                        pixelValue = @as(f32, @floatFromInt((pixel & 0b0000111100000000) >> 8)) * (1.0 / 15.0);
                    } else if (selectedChannel == 2) {
                        pixelValue = @as(f32, @floatFromInt((pixel & 0b0000000011110000) >> 4)) * (1.0 / 15.0);
                    } else if (selectedChannel == 3) {
                        pixelValue = @as(f32, @floatFromInt(pixel & 0b0000000000001111)) * (1.0 / 15.0);
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => {
                    pixelValue = @as(f32, @floatFromInt(d8[k + sc])) / 255.0;
                    k += 4;
                },
                PIXELFORMAT_UNCOMPRESSED_R8G8B8 => {
                    pixelValue = @as(f32, @floatFromInt(d8[k + sc])) / 255.0;
                    k += 3;
                },
                PIXELFORMAT_UNCOMPRESSED_R32 => {
                    pixelValue = d32[k];
                    k += 1;
                },
                PIXELFORMAT_UNCOMPRESSED_R32G32B32 => {
                    pixelValue = d32[k + sc];
                    k += 3;
                },
                PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => {
                    pixelValue = d32[k + sc];
                    k += 4;
                },
                PIXELFORMAT_UNCOMPRESSED_R16 => {
                    pixelValue = HalfToFloat(d16[k]);
                    k += 1;
                },
                PIXELFORMAT_UNCOMPRESSED_R16G16B16 => {
                    pixelValue = HalfToFloat(d16[k + sc]);
                    k += 3;
                },
                PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => {
                    pixelValue = HalfToFloat(d16[k + sc]);
                    k += 4;
                },
                else => {},
            }

            pixels[i] = tuc(pixelValue * 255);
        }
    }

    result.data = pixels;

    return result;
}

// Crop an image to area defined by a rectangle
export fn ImageCrop(image: [*c]Image, crop_in: Rectangle) callconv(.c) void {
    var crop = crop_in;
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if (crop.x < 0) {
        crop.width += crop.x;
        crop.x = 0;
    }
    if (crop.y < 0) {
        crop.height += crop.y;
        crop.y = 0;
    }
    if ((crop.x + crop.width) > @as(f32, @floatFromInt(image.*.width))) crop.width = @as(f32, @floatFromInt(image.*.width)) - crop.x;
    if ((crop.y + crop.height) > @as(f32, @floatFromInt(image.*.height))) crop.height = @as(f32, @floatFromInt(image.*.height)) - crop.y;
    if ((crop.x > @as(f32, @floatFromInt(image.*.width))) or (crop.y > @as(f32, @floatFromInt(image.*.height)))) {
        TraceLog(LOG_WARNING, "IMAGE: Failed to crop, rectangle out of bounds");
        return;
    }

    if (image.*.mipmaps > 1) TraceLog(LOG_WARNING, "Image manipulation only applied to base mipmap level");
    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image manipulation not supported for compressed formats");
    } else {
        const bytesPerPixel = GetPixelDataSize(1, 1, image.*.format);

        const croppedData: [*]u8 = @ptrCast(RL_MALLOC(@intCast(ti(crop.width * crop.height) * bytesPerPixel)));
        const src8: [*]const u8 = @ptrCast(image.*.data);

        var y: c_int = ti(crop.y);
        var offsetSize: c_int = 0;
        while (y < ti(crop.y + crop.height)) : (y += 1) {
            _ = memcpy(
                croppedData + @as(usize, @intCast(offsetSize)),
                src8 + @as(usize, @intCast((y * image.*.width + ti(crop.x)) * bytesPerPixel)),
                @intCast(ti(crop.width) * bytesPerPixel),
            );
            offsetSize += (ti(crop.width) * bytesPerPixel);
        }

        RL_FREE(image.*.data);
        image.*.data = croppedData;
        image.*.width = ti(crop.width);
        image.*.height = ti(crop.height);
    }
}

// Convert image data to desired format
export fn ImageFormat(image: [*c]Image, newFormat: c_int) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if ((newFormat != 0) and (image.*.format != newFormat)) {
        if ((image.*.format < PIXELFORMAT_COMPRESSED_DXT1_RGB) and (newFormat < PIXELFORMAT_COMPRESSED_DXT1_RGB)) {
            const pixels = LoadImageDataNormalized(image.*); // Supports 8 to 32 bit per channel

            RL_FREE(image.*.data);
            image.*.data = null;
            image.*.format = newFormat;

            const total: usize = @intCast(image.*.width * image.*.height);

            switch (image.*.format) {
                PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * @as(c_int, @sizeOf(u8))));
                    const o: [*]u8 = @ptrCast(image.*.data);
                    var i: usize = 0;
                    while (i < total) : (i += 1) {
                        o[i] = tuc((pixels[i].x * 0.299 + pixels[i].y * 0.587 + pixels[i].z * 0.114) * 255.0);
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * 2 * @as(c_int, @sizeOf(u8))));
                    const o: [*]u8 = @ptrCast(image.*.data);
                    var i: usize = 0;
                    var k: usize = 0;
                    while (i < total * 2) : ({
                        i += 2;
                        k += 1;
                    }) {
                        o[i] = tuc((pixels[k].x * 0.299 + pixels[k].y * 0.587 + pixels[k].z * 0.114) * 255.0);
                        o[i + 1] = tuc(pixels[k].w * 255.0);
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R5G6B5 => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * @as(c_int, @sizeOf(u16))));
                    const o: [*]u16 = @ptrCast(@alignCast(image.*.data));
                    var i: usize = 0;
                    while (i < total) : (i += 1) {
                        const r: u16 = tuc(round(@floatCast(pixels[i].x * 31.0)));
                        const g: u16 = tuc(round(@floatCast(pixels[i].y * 63.0)));
                        const b: u16 = tuc(round(@floatCast(pixels[i].z * 31.0)));
                        o[i] = (r << 11) | (g << 5) | b;
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R8G8B8 => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * 3 * @as(c_int, @sizeOf(u8))));
                    const o: [*]u8 = @ptrCast(image.*.data);
                    var i: usize = 0;
                    var k: usize = 0;
                    while (i < total * 3) : ({
                        i += 3;
                        k += 1;
                    }) {
                        o[i] = tuc(pixels[k].x * 255.0);
                        o[i + 1] = tuc(pixels[k].y * 255.0);
                        o[i + 2] = tuc(pixels[k].z * 255.0);
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * @as(c_int, @sizeOf(u16))));
                    const o: [*]u16 = @ptrCast(@alignCast(image.*.data));
                    var i: usize = 0;
                    while (i < total) : (i += 1) {
                        const r: u16 = tuc(round(@floatCast(pixels[i].x * 31.0)));
                        const g: u16 = tuc(round(@floatCast(pixels[i].y * 31.0)));
                        const b: u16 = tuc(round(@floatCast(pixels[i].z * 31.0)));
                        const a: u16 = if (pixels[i].w > (@as(f32, @floatFromInt(PIXELFORMAT_UNCOMPRESSED_R5G5B5A1_ALPHA_THRESHOLD)) / 255.0)) 1 else 0;
                        o[i] = (r << 11) | (g << 6) | (b << 1) | a;
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * @as(c_int, @sizeOf(u16))));
                    const o: [*]u16 = @ptrCast(@alignCast(image.*.data));
                    var i: usize = 0;
                    while (i < total) : (i += 1) {
                        const r: u16 = tuc(round(@floatCast(pixels[i].x * 15.0)));
                        const g: u16 = tuc(round(@floatCast(pixels[i].y * 15.0)));
                        const b: u16 = tuc(round(@floatCast(pixels[i].z * 15.0)));
                        const a: u16 = tuc(round(@floatCast(pixels[i].w * 15.0)));
                        o[i] = (r << 12) | (g << 8) | (b << 4) | a;
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * 4 * @as(c_int, @sizeOf(u8))));
                    const o: [*]u8 = @ptrCast(image.*.data);
                    var i: usize = 0;
                    var k: usize = 0;
                    while (i < total * 4) : ({
                        i += 4;
                        k += 1;
                    }) {
                        o[i] = tuc(pixels[k].x * 255.0);
                        o[i + 1] = tuc(pixels[k].y * 255.0);
                        o[i + 2] = tuc(pixels[k].z * 255.0);
                        o[i + 3] = tuc(pixels[k].w * 255.0);
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R32 => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * @as(c_int, @sizeOf(f32))));
                    const o: [*]f32 = @ptrCast(@alignCast(image.*.data));
                    var i: usize = 0;
                    while (i < total) : (i += 1) {
                        o[i] = pixels[i].x * 0.299 + pixels[i].y * 0.587 + pixels[i].z * 0.114;
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R32G32B32 => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * 3 * @as(c_int, @sizeOf(f32))));
                    const o: [*]f32 = @ptrCast(@alignCast(image.*.data));
                    var i: usize = 0;
                    var k: usize = 0;
                    while (i < total * 3) : ({
                        i += 3;
                        k += 1;
                    }) {
                        o[i] = pixels[k].x;
                        o[i + 1] = pixels[k].y;
                        o[i + 2] = pixels[k].z;
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * 4 * @as(c_int, @sizeOf(f32))));
                    const o: [*]f32 = @ptrCast(@alignCast(image.*.data));
                    var i: usize = 0;
                    var k: usize = 0;
                    while (i < total * 4) : ({
                        i += 4;
                        k += 1;
                    }) {
                        o[i] = pixels[k].x;
                        o[i + 1] = pixels[k].y;
                        o[i + 2] = pixels[k].z;
                        o[i + 3] = pixels[k].w;
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R16 => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * @as(c_int, @sizeOf(u16))));
                    const o: [*]u16 = @ptrCast(@alignCast(image.*.data));
                    var i: usize = 0;
                    while (i < total) : (i += 1) {
                        o[i] = FloatToHalf(pixels[i].x * 0.299 + pixels[i].y * 0.587 + pixels[i].z * 0.114);
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R16G16B16 => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * 3 * @as(c_int, @sizeOf(u16))));
                    const o: [*]u16 = @ptrCast(@alignCast(image.*.data));
                    var i: usize = 0;
                    var k: usize = 0;
                    while (i < total * 3) : ({
                        i += 3;
                        k += 1;
                    }) {
                        o[i] = FloatToHalf(pixels[k].x);
                        o[i + 1] = FloatToHalf(pixels[k].y);
                        o[i + 2] = FloatToHalf(pixels[k].z);
                    }
                },
                PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => {
                    image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * 4 * @as(c_int, @sizeOf(u16))));
                    const o: [*]u16 = @ptrCast(@alignCast(image.*.data));
                    var i: usize = 0;
                    var k: usize = 0;
                    while (i < total * 4) : ({
                        i += 4;
                        k += 1;
                    }) {
                        o[i] = FloatToHalf(pixels[k].x);
                        o[i + 1] = FloatToHalf(pixels[k].y);
                        o[i + 2] = FloatToHalf(pixels[k].z);
                        o[i + 3] = FloatToHalf(pixels[k].w);
                    }
                },
                else => {},
            }

            RL_FREE(pixels);

            if (image.*.mipmaps > 1) {
                image.*.mipmaps = 1;
                if (image.*.data != null) ImageMipmaps(image);
            }
        } else TraceLog(LOG_WARNING, "IMAGE: Data format is compressed, can not be converted");
    }
}

// Create an image from text (default font)
export fn ImageText(text: [*c]const u8, fontSize: c_int, color: Color) callconv(.c) Image {
    var imText: Image = std.mem.zeroes(Image);
    const defaultFontSize: c_int = 10; // Default Font chars height in pixel
    var fs = fontSize;
    if (fs < defaultFontSize) fs = defaultFontSize;
    const spacing = @divTrunc(fs, defaultFontSize);
    imText = ImageTextEx(GetFontDefault(), text, @floatFromInt(fs), @floatFromInt(spacing), color);
    return imText;
}

// Create an image from text (custom sprite font)
export fn ImageTextEx(font: Font, text: [*c]const u8, fontSize: f32, spacing: f32, tint: Color) callconv(.c) Image {
    var imText: Image = std.mem.zeroes(Image);
    if (text == null) return imText;

    const textLength: c_int = @intCast(strlen(text)); // Get length of text in bytes
    var textOffsetX: c_int = 0; // Image drawing position X
    var textOffsetY: c_int = 0; // Offset between lines (on linebreak '\n')

    // NOTE: Text image is generated at font base size, later scaled to desired font size
    const imSize = MeasureTextEx(font, text, @floatFromInt(font.baseSize), spacing);
    const textSize = MeasureTextEx(font, text, fontSize, spacing);

    imText = GenImageColor(ti(imSize.x), ti(imSize.y), BLANK);

    var i: c_int = 0;
    while (i < textLength) {
        var codepointByteCount: c_int = 0;
        const codepoint = GetCodepointNext(ptrAdd(text, i), &codepointByteCount);
        const index = GetGlyphIndex(font, codepoint);
        const u: usize = @intCast(index);

        if (codepoint == '\n') {
            textOffsetY += (font.baseSize + @divTrunc(font.baseSize, 2));
            textOffsetX = 0;
        } else {
            if ((codepoint != ' ') and (codepoint != '\t')) {
                const rec = Rectangle{
                    .x = @floatFromInt(textOffsetX + font.glyphs[u].offsetX),
                    .y = @floatFromInt(textOffsetY + font.glyphs[u].offsetY),
                    .width = font.recs[u].width,
                    .height = font.recs[u].height,
                };
                ImageDrawImagePro(&imText, font.glyphs[u].image, .{ .x = 0, .y = 0, .width = @floatFromInt(font.glyphs[u].image.width), .height = @floatFromInt(font.glyphs[u].image.height) }, rec, .{ .x = 0, .y = 0 }, 0.0, tint);
            }

            if (font.glyphs[u].advanceX == 0) {
                textOffsetX += ti(font.recs[u].width + spacing);
            } else textOffsetX += font.glyphs[u].advanceX + ti(spacing);
        }

        i += codepointByteCount;
    }

    // Scale image depending on text size
    if (textSize.y != imSize.y) {
        const scaleFactor = textSize.y / imSize.y;
        TraceLog(LOG_INFO, "IMAGE: Text scaled by factor: %f", @as(f64, scaleFactor));

        if (font.texture.id == GetFontDefault().texture.id) {
            ImageResizeNN(&imText, ti(imSize.x * scaleFactor), ti(imSize.y * scaleFactor));
        } else ImageResize(&imText, ti(imSize.x * scaleFactor), ti(imSize.y * scaleFactor));
    }

    return imText;
}

// Resize and image to new size using Nearest-Neighbor scaling algorithm
export fn ImageResizeNN(image: [*c]Image, newWidth: c_int, newHeight: c_int) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const pixels = LoadImageColors(image.*);
    const output: [*c]Color = @ptrCast(@alignCast(RL_MALLOC(@intCast(newWidth * newHeight * @as(c_int, @sizeOf(Color))))));

    // EDIT: added +1 to account for an early rounding problem
    const xRatio = @divTrunc(image.*.width << 16, newWidth) + 1;
    const yRatio = @divTrunc(image.*.height << 16, newHeight) + 1;

    var y: c_int = 0;
    while (y < newHeight) : (y += 1) {
        var x: c_int = 0;
        while (x < newWidth) : (x += 1) {
            const x2 = (x * xRatio) >> 16;
            const y2 = (y * yRatio) >> 16;
            output[@intCast((y * newWidth) + x)] = pixels[@intCast((y2 * image.*.width) + x2)];
        }
    }

    const format = image.*.format;

    RL_FREE(image.*.data);

    image.*.data = output;
    image.*.width = newWidth;
    image.*.height = newHeight;
    image.*.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

    ImageFormat(image, format);

    UnloadImageColors(pixels);
}

// Resize and image to new size
export fn ImageResize(image: [*c]Image, newWidth: c_int, newHeight: c_int) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if ((image.*.format == PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) or
        (image.*.format == PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA) or
        (image.*.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8) or
        (image.*.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8))
    {
        const bytesPerPixel = GetPixelDataSize(1, 1, image.*.format);
        const output: [*c]u8 = @ptrCast(RL_MALLOC(@intCast(newWidth * newHeight * bytesPerPixel)));

        switch (image.*.format) {
            PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => _ = stbir_resize_uint8_linear(@ptrCast(image.*.data), image.*.width, image.*.height, 0, output, newWidth, newHeight, 0, 1),
            PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => _ = stbir_resize_uint8_linear(@ptrCast(image.*.data), image.*.width, image.*.height, 0, output, newWidth, newHeight, 0, 2),
            PIXELFORMAT_UNCOMPRESSED_R8G8B8 => _ = stbir_resize_uint8_linear(@ptrCast(image.*.data), image.*.width, image.*.height, 0, output, newWidth, newHeight, 0, 3),
            PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => _ = stbir_resize_uint8_linear(@ptrCast(image.*.data), image.*.width, image.*.height, 0, output, newWidth, newHeight, 0, 4),
            else => {},
        }

        RL_FREE(image.*.data);
        image.*.data = output;
        image.*.width = newWidth;
        image.*.height = newHeight;
    } else {
        const pixels = LoadImageColors(image.*);
        const output: [*c]Color = @ptrCast(@alignCast(RL_MALLOC(@intCast(newWidth * newHeight * @as(c_int, @sizeOf(Color))))));

        _ = stbir_resize_uint8_linear(@ptrCast(pixels), image.*.width, image.*.height, 0, @ptrCast(output), newWidth, newHeight, 0, 4);

        const format = image.*.format;

        UnloadImageColors(pixels);
        RL_FREE(image.*.data);

        image.*.data = output;
        image.*.width = newWidth;
        image.*.height = newHeight;
        image.*.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

        ImageFormat(image, format);
    }
}

// Resize canvas and fill with color
export fn ImageResizeCanvas(image: [*c]Image, newWidth: c_int, newHeight: c_int, offsetX: c_int, offsetY: c_int, fill: Color) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if (image.*.mipmaps > 1) TraceLog(LOG_WARNING, "Image manipulation only applied to base mipmap level");
    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image manipulation not supported for compressed formats");
    } else if ((newWidth != image.*.width) or (newHeight != image.*.height)) {
        var srcRec = Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(image.*.width), .height = @floatFromInt(image.*.height) };
        var dstPos = Vector2{ .x = @floatFromInt(offsetX), .y = @floatFromInt(offsetY) };

        if (offsetX < 0) {
            srcRec.x = @floatFromInt(-offsetX);
            srcRec.width += @floatFromInt(offsetX);
            dstPos.x = 0;
        } else if ((offsetX + image.*.width) > newWidth) srcRec.width = @floatFromInt(newWidth - offsetX);

        if (offsetY < 0) {
            srcRec.y = @floatFromInt(-offsetY);
            srcRec.height += @floatFromInt(offsetY);
            dstPos.y = 0;
        } else if ((offsetY + image.*.height) > newHeight) srcRec.height = @floatFromInt(newHeight - offsetY);

        if (@as(f32, @floatFromInt(newWidth)) < srcRec.width) srcRec.width = @floatFromInt(newWidth);
        if (@as(f32, @floatFromInt(newHeight)) < srcRec.height) srcRec.height = @floatFromInt(newHeight);

        const bytesPerPixel = GetPixelDataSize(1, 1, image.*.format);
        const resizedData: [*]u8 = @ptrCast(RL_CALLOC(@intCast(newWidth * newHeight * bytesPerPixel), 1));

        // Fill resized canvas with fill color (set first pixel with image format)
        SetPixelColor(resizedData, fill, image.*.format);

        var x: c_int = 1;
        while (x < newWidth) : (x += 1) {
            _ = memcpy(resizedData + @as(usize, @intCast(x * bytesPerPixel)), resizedData, @intCast(bytesPerPixel));
        }
        var yy: c_int = 1;
        while (yy < newHeight) : (yy += 1) {
            _ = memcpy(resizedData + @as(usize, @intCast(yy * newWidth * bytesPerPixel)), resizedData, @intCast(newWidth * bytesPerPixel));
        }

        const src8: [*]const u8 = @ptrCast(image.*.data);
        var dstOffsetSize: c_int = (ti(dstPos.y) * newWidth + ti(dstPos.x)) * bytesPerPixel;

        var y: c_int = 0;
        while (y < ti(srcRec.height)) : (y += 1) {
            _ = memcpy(
                resizedData + @as(usize, @intCast(dstOffsetSize)),
                src8 + @as(usize, @intCast(((y + ti(srcRec.y)) * image.*.width + ti(srcRec.x)) * bytesPerPixel)),
                @intCast(ti(srcRec.width) * bytesPerPixel),
            );
            dstOffsetSize += (newWidth * bytesPerPixel);
        }

        RL_FREE(image.*.data);
        image.*.data = resizedData;
        image.*.width = newWidth;
        image.*.height = newHeight;
    }
}

// Convert image to POT (power-of-two)
export fn ImageToPOT(image: [*c]Image, fill: Color) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const potWidth = ti(powf(2, ceilf(logf(@floatFromInt(image.*.width)) / logf(2))));
    const potHeight = ti(powf(2, ceilf(logf(@floatFromInt(image.*.height)) / logf(2))));

    if ((potWidth != image.*.width) or (potHeight != image.*.height)) ImageResizeCanvas(image, potWidth, potHeight, 0, 0, fill);
}

// Crop image depending on alpha value
export fn ImageAlphaCrop(image: [*c]Image, threshold: f32) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const crop = GetImageAlphaBorder(image.*, threshold);

    if ((ti(crop.width) != 0) and (ti(crop.height) != 0)) ImageCrop(image, crop);
}

// Clear alpha channel to desired color
export fn ImageAlphaClear(image: [*c]Image, color: Color, threshold: f32) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if (image.*.mipmaps > 1) TraceLog(LOG_WARNING, "Image manipulation only applied to base mipmap level");
    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image manipulation not supported for compressed formats");
    } else {
        const total: usize = @intCast(image.*.width * image.*.height);
        switch (image.*.format) {
            PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
                const d: [*]u8 = @ptrCast(image.*.data);
                const thresholdValue: u8 = tuc(threshold * 255.0);
                var i: usize = 1;
                while (i < total * 2) : (i += 2) {
                    if (d[i] <= thresholdValue) {
                        d[i - 1] = color.r;
                        d[i] = color.a;
                    }
                }
            },
            PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
                const d: [*]u16 = @ptrCast(@alignCast(image.*.data));
                const thresholdValue: u16 = if (threshold < 0.5) 0 else 1;
                const r: u16 = tuc(round(@floatCast(@as(f32, @floatFromInt(color.r)) * 31.0)));
                const g: u16 = tuc(round(@floatCast(@as(f32, @floatFromInt(color.g)) * 31.0)));
                const b: u16 = tuc(round(@floatCast(@as(f32, @floatFromInt(color.b)) * 31.0)));
                const a: u16 = if (color.a < 128) 0 else 1;
                var i: usize = 0;
                while (i < total) : (i += 1) {
                    if ((d[i] & 0b0000000000000001) <= thresholdValue) {
                        d[i] = (r << 11) | (g << 6) | (b << 1) | a;
                    }
                }
            },
            PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
                const d: [*]u16 = @ptrCast(@alignCast(image.*.data));
                const thresholdValue: u16 = tuc(threshold * 15.0);
                const r: u16 = tuc(round(@floatCast(@as(f32, @floatFromInt(color.r)) * 15.0)));
                const g: u16 = tuc(round(@floatCast(@as(f32, @floatFromInt(color.g)) * 15.0)));
                const b: u16 = tuc(round(@floatCast(@as(f32, @floatFromInt(color.b)) * 15.0)));
                const a: u16 = tuc(round(@floatCast(@as(f32, @floatFromInt(color.a)) * 15.0)));
                var i: usize = 0;
                while (i < total) : (i += 1) {
                    if ((d[i] & 0x000f) <= thresholdValue) {
                        d[i] = (r << 12) | (g << 8) | (b << 4) | a;
                    }
                }
            },
            PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => {
                const d: [*]u8 = @ptrCast(image.*.data);
                const thresholdValue: u8 = tuc(threshold * 255.0);
                var i: usize = 3;
                while (i < total * 4) : (i += 4) {
                    if (d[i] <= thresholdValue) {
                        d[i - 3] = color.r;
                        d[i - 2] = color.g;
                        d[i - 1] = color.b;
                        d[i] = color.a;
                    }
                }
            },
            PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => {
                const d: [*]f32 = @ptrCast(@alignCast(image.*.data));
                var i: usize = 3;
                while (i < total * 4) : (i += 4) {
                    if (d[i] <= threshold) {
                        d[i - 3] = @as(f32, @floatFromInt(color.r)) / 255.0;
                        d[i - 2] = @as(f32, @floatFromInt(color.g)) / 255.0;
                        d[i - 1] = @as(f32, @floatFromInt(color.b)) / 255.0;
                        d[i] = @as(f32, @floatFromInt(color.a)) / 255.0;
                    }
                }
            },
            PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => {
                const d: [*]u16 = @ptrCast(@alignCast(image.*.data));
                var i: usize = 3;
                while (i < total * 4) : (i += 4) {
                    if (HalfToFloat(d[i]) <= threshold) {
                        d[i - 3] = FloatToHalf(@as(f32, @floatFromInt(color.r)) / 255.0);
                        d[i - 2] = FloatToHalf(@as(f32, @floatFromInt(color.g)) / 255.0);
                        d[i - 1] = FloatToHalf(@as(f32, @floatFromInt(color.b)) / 255.0);
                        d[i] = FloatToHalf(@as(f32, @floatFromInt(color.a)) / 255.0);
                    }
                }
            },
            else => {},
        }
    }
}

// Apply alpha mask to image
export fn ImageAlphaMask(image: [*c]Image, alphaMask: Image) callconv(.c) void {
    if ((image.*.width != alphaMask.width) or (image.*.height != alphaMask.height)) {
        TraceLog(LOG_WARNING, "IMAGE: Alpha mask must be same size as image");
    } else if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "IMAGE: Alpha mask can not be applied to compressed data formats");
    } else {
        var mask = ImageCopy(alphaMask);
        if (mask.format != PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) ImageFormat(&mask, PIXELFORMAT_UNCOMPRESSED_GRAYSCALE);

        const maskTotal: usize = @intCast(mask.width * mask.height);
        const imgTotal: usize = @intCast(image.*.width * image.*.height);
        const maskData: [*]const u8 = @ptrCast(mask.data);

        if (image.*.format == PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) {
            const data: [*]u8 = @ptrCast(RL_MALLOC(@intCast(image.*.width * image.*.height * 2)));
            const imgData: [*]const u8 = @ptrCast(image.*.data);

            var i: usize = 0;
            var k: usize = 0;
            while ((i < maskTotal) or (i < imgTotal)) : ({
                i += 1;
                k += 2;
            }) {
                data[k] = imgData[i];
                data[k + 1] = maskData[i];
            }

            RL_FREE(image.*.data);
            image.*.data = data;
            image.*.format = PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA;
        } else {
            if (image.*.format != PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) ImageFormat(image, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);

            const imgData: [*]u8 = @ptrCast(image.*.data);
            var i: usize = 0;
            var k: usize = 3;
            while ((i < maskTotal) or (i < imgTotal)) : ({
                i += 1;
                k += 4;
            }) {
                imgData[k] = maskData[i];
            }
        }

        UnloadImage(mask);
    }
}

// Premultiply alpha channel
export fn ImageAlphaPremultiply(image: [*c]Image) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    var alpha: f32 = 0.0;
    const pixels = LoadImageColors(image.*);

    var i: usize = 0;
    const total: usize = @intCast(image.*.width * image.*.height);
    while (i < total) : (i += 1) {
        if (pixels[i].a == 0) {
            pixels[i].r = 0;
            pixels[i].g = 0;
            pixels[i].b = 0;
        } else if (pixels[i].a < 255) {
            alpha = @as(f32, @floatFromInt(pixels[i].a)) / 255.0;
            pixels[i].r = tuc(@as(f32, @floatFromInt(pixels[i].r)) * alpha);
            pixels[i].g = tuc(@as(f32, @floatFromInt(pixels[i].g)) * alpha);
            pixels[i].b = tuc(@as(f32, @floatFromInt(pixels[i].b)) * alpha);
        }
    }

    RL_FREE(image.*.data);

    const format = image.*.format;
    image.*.data = pixels;
    image.*.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

    ImageFormat(image, format);
}

// Apply box blur to image (Gaussian approximation)
export fn ImageBlurGaussian(image: [*c]Image, blurSize: c_int) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    ImageAlphaPremultiply(image);

    const pixels = LoadImageColors(image.*);

    const w: usize = @intCast(image.*.width);
    const h: usize = @intCast(image.*.height);

    const pixelsCopy1: [*c]Vector4 = @ptrCast(@alignCast(RL_MALLOC(@intCast(image.*.height * image.*.width * @as(c_int, @sizeOf(Vector4))))));
    const pixelsCopy2: [*c]Vector4 = @ptrCast(@alignCast(RL_MALLOC(@intCast(image.*.height * image.*.width * @as(c_int, @sizeOf(Vector4))))));

    {
        var i: usize = 0;
        while (i < h * w) : (i += 1) {
            pixelsCopy1[i].x = @floatFromInt(pixels[i].r);
            pixelsCopy1[i].y = @floatFromInt(pixels[i].g);
            pixelsCopy1[i].z = @floatFromInt(pixels[i].b);
            pixelsCopy1[i].w = @floatFromInt(pixels[i].a);
        }
    }

    var j: c_int = 0;
    while (j < GAUSSIAN_BLUR_ITERATIONS) : (j += 1) {
        // Horizontal motion blur
        var row: c_int = 0;
        while (row < image.*.height) : (row += 1) {
            var avgR: f32 = 0.0;
            var avgG: f32 = 0.0;
            var avgB: f32 = 0.0;
            var avgAlpha: f32 = 0.0;
            var convolutionSize: c_int = blurSize;
            const rw: usize = @intCast(row * image.*.width);

            var i: c_int = 0;
            while (i < blurSize) : (i += 1) {
                avgR += pixelsCopy1[rw + @as(usize, @intCast(i))].x;
                avgG += pixelsCopy1[rw + @as(usize, @intCast(i))].y;
                avgB += pixelsCopy1[rw + @as(usize, @intCast(i))].z;
                avgAlpha += pixelsCopy1[rw + @as(usize, @intCast(i))].w;
            }

            var x: c_int = 0;
            while (x < image.*.width) : (x += 1) {
                if (x - blurSize - 1 >= 0) {
                    const idx = rw + @as(usize, @intCast(x - blurSize - 1));
                    avgR -= pixelsCopy1[idx].x;
                    avgG -= pixelsCopy1[idx].y;
                    avgB -= pixelsCopy1[idx].z;
                    avgAlpha -= pixelsCopy1[idx].w;
                    convolutionSize -= 1;
                }

                if (x + blurSize < image.*.width) {
                    const idx = rw + @as(usize, @intCast(x + blurSize));
                    avgR += pixelsCopy1[idx].x;
                    avgG += pixelsCopy1[idx].y;
                    avgB += pixelsCopy1[idx].z;
                    avgAlpha += pixelsCopy1[idx].w;
                    convolutionSize += 1;
                }

                const o = rw + @as(usize, @intCast(x));
                const cs: f32 = @floatFromInt(convolutionSize);
                pixelsCopy2[o].x = avgR / cs;
                pixelsCopy2[o].y = avgG / cs;
                pixelsCopy2[o].z = avgB / cs;
                pixelsCopy2[o].w = avgAlpha / cs;
            }
        }

        // Vertical motion blur
        var col: c_int = 0;
        while (col < image.*.width) : (col += 1) {
            var avgR: f32 = 0.0;
            var avgG: f32 = 0.0;
            var avgB: f32 = 0.0;
            var avgAlpha: f32 = 0.0;
            var convolutionSize: c_int = blurSize;
            const c: usize = @intCast(col);

            var i: c_int = 0;
            while (i < blurSize) : (i += 1) {
                const idx = @as(usize, @intCast(i)) * w + c;
                avgR += pixelsCopy2[idx].x;
                avgG += pixelsCopy2[idx].y;
                avgB += pixelsCopy2[idx].z;
                avgAlpha += pixelsCopy2[idx].w;
            }

            var y: c_int = 0;
            while (y < image.*.height) : (y += 1) {
                if (y - blurSize - 1 >= 0) {
                    const idx = @as(usize, @intCast(y - blurSize - 1)) * w + c;
                    avgR -= pixelsCopy2[idx].x;
                    avgG -= pixelsCopy2[idx].y;
                    avgB -= pixelsCopy2[idx].z;
                    avgAlpha -= pixelsCopy2[idx].w;
                    convolutionSize -= 1;
                }
                if (y + blurSize < image.*.height) {
                    const idx = @as(usize, @intCast(y + blurSize)) * w + c;
                    avgR += pixelsCopy2[idx].x;
                    avgG += pixelsCopy2[idx].y;
                    avgB += pixelsCopy2[idx].z;
                    avgAlpha += pixelsCopy2[idx].w;
                    convolutionSize += 1;
                }

                const o = @as(usize, @intCast(y)) * w + c;
                const cs: f32 = @floatFromInt(convolutionSize);
                pixelsCopy1[o].x = @floatFromInt(tuc(avgR / cs));
                pixelsCopy1[o].y = @floatFromInt(tuc(avgG / cs));
                pixelsCopy1[o].z = @floatFromInt(tuc(avgB / cs));
                pixelsCopy1[o].w = @floatFromInt(tuc(avgAlpha / cs));
            }
        }
    }

    // Reverse premultiply
    {
        var i: usize = 0;
        while (i < w * h) : (i += 1) {
            if (pixelsCopy1[i].w == 0.0) {
                pixels[i].r = 0;
                pixels[i].g = 0;
                pixels[i].b = 0;
                pixels[i].a = 0;
            } else if (pixelsCopy1[i].w <= 255.0) {
                const alpha: f32 = pixelsCopy1[i].w / 255.0;
                pixels[i].r = tuc(fminf(pixelsCopy1[i].x / alpha, 255.0));
                pixels[i].g = tuc(fminf(pixelsCopy1[i].y / alpha, 255.0));
                pixels[i].b = tuc(fminf(pixelsCopy1[i].z / alpha, 255.0));
                pixels[i].a = tuc(pixelsCopy1[i].w);
            }
        }
    }

    const format = image.*.format;
    RL_FREE(image.*.data);
    RL_FREE(pixelsCopy1);
    RL_FREE(pixelsCopy2);

    image.*.data = pixels;
    image.*.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

    ImageFormat(image, format);
}

// Apply custom square convolution kernel to image
export fn ImageKernelConvolution(image: [*c]Image, kernel: [*c]const f32, kernelSize: c_int) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0) or kernel == null) return;

    const kernelWidth = ti(sqrtf(@floatFromInt(kernelSize)));

    if (kernelWidth * kernelWidth != kernelSize) {
        TraceLog(LOG_WARNING, "IMAGE: Convolution kernel must be square to be applied");
        return;
    }

    const pixels = LoadImageColors(image.*);

    const imageCopy2: [*c]Vector4 = @ptrCast(@alignCast(RL_MALLOC(@intCast(image.*.height * image.*.width * @as(c_int, @sizeOf(Vector4))))));
    const temp: [*c]Vector4 = @ptrCast(@alignCast(RL_MALLOC(@intCast(kernelSize * @as(c_int, @sizeOf(Vector4))))));

    {
        var i: usize = 0;
        while (i < @as(usize, @intCast(kernelSize))) : (i += 1) {
            temp[i].x = 0.0;
            temp[i].y = 0.0;
            temp[i].z = 0.0;
            temp[i].w = 0.0;
        }
    }

    var rRes: f32 = 0.0;
    var gRes: f32 = 0.0;
    var bRes: f32 = 0.0;
    var aRes: f32 = 0.0;

    var startRange: c_int = 0;
    var endRange: c_int = 0;

    if (@rem(kernelWidth, 2) == 0) {
        startRange = -@divTrunc(kernelWidth, 2);
        endRange = @divTrunc(kernelWidth, 2);
    } else {
        startRange = -@divTrunc(kernelWidth, 2);
        endRange = @divTrunc(kernelWidth, 2) + 1;
    }

    const totalImg: c_uint = @bitCast(image.*.width * image.*.height);

    var x: c_int = 0;
    while (x < image.*.height) : (x += 1) {
        var y: c_int = 0;
        while (y < image.*.width) : (y += 1) {
            var xk: c_int = startRange;
            while (xk < endRange) : (xk += 1) {
                var yk: c_int = startRange;
                while (yk < endRange) : (yk += 1) {
                    const xkabs = xk + @divTrunc(kernelWidth, 2);
                    const ykabs = yk + @divTrunc(kernelWidth, 2);
                    const imgindex: c_uint = @bitCast(image.*.width * (x + xk) + (y + yk));
                    const ti_idx: usize = @intCast(kernelWidth * xkabs + ykabs);

                    if (imgindex >= totalImg) {
                        temp[ti_idx].x = 0.0;
                        temp[ti_idx].y = 0.0;
                        temp[ti_idx].z = 0.0;
                        temp[ti_idx].w = 0.0;
                    } else {
                        const ker = kernel[ti_idx];
                        const px = pixels[@intCast(imgindex)];
                        temp[ti_idx].x = (@as(f32, @floatFromInt(px.r))) / 255.0 * ker;
                        temp[ti_idx].y = (@as(f32, @floatFromInt(px.g))) / 255.0 * ker;
                        temp[ti_idx].z = (@as(f32, @floatFromInt(px.b))) / 255.0 * ker;
                        temp[ti_idx].w = (@as(f32, @floatFromInt(px.a))) / 255.0 * ker;
                    }
                }
            }

            {
                var i: usize = 0;
                while (i < @as(usize, @intCast(kernelSize))) : (i += 1) {
                    rRes += temp[i].x;
                    gRes += temp[i].y;
                    bRes += temp[i].z;
                    aRes += temp[i].w;
                }
            }

            if (rRes < 0.0) rRes = 0.0;
            if (gRes < 0.0) gRes = 0.0;
            if (bRes < 0.0) bRes = 0.0;

            if (rRes > 1.0) rRes = 1.0;
            if (gRes > 1.0) gRes = 1.0;
            if (bRes > 1.0) bRes = 1.0;

            const o: usize = @intCast(image.*.width * x + y);
            imageCopy2[o].x = rRes;
            imageCopy2[o].y = gRes;
            imageCopy2[o].z = bRes;
            imageCopy2[o].w = aRes;

            rRes = 0.0;
            gRes = 0.0;
            bRes = 0.0;
            aRes = 0.0;

            {
                var i: usize = 0;
                while (i < @as(usize, @intCast(kernelSize))) : (i += 1) {
                    temp[i].x = 0.0;
                    temp[i].y = 0.0;
                    temp[i].z = 0.0;
                    temp[i].w = 0.0;
                }
            }
        }
    }

    {
        var i: usize = 0;
        const total: usize = @intCast(image.*.width * image.*.height);
        while (i < total) : (i += 1) {
            const alpha: f32 = imageCopy2[i].w;
            pixels[i].r = tuc(imageCopy2[i].x * 255.0);
            pixels[i].g = tuc(imageCopy2[i].y * 255.0);
            pixels[i].b = tuc(imageCopy2[i].z * 255.0);
            pixels[i].a = tuc(alpha * 255.0);
        }
    }

    const format = image.*.format;
    RL_FREE(image.*.data);
    RL_FREE(imageCopy2);
    RL_FREE(temp);

    image.*.data = pixels;
    image.*.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
    ImageFormat(image, format);
}

// Generate all mipmap levels for a provided image
export fn ImageMipmaps(image: [*c]Image) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    var mipCount: c_int = 1;
    var mipWidth = image.*.width;
    var mipHeight = image.*.height;
    var mipSize = GetPixelDataSize(mipWidth, mipHeight, image.*.format);

    while ((mipWidth != 1) or (mipHeight != 1)) {
        if (mipWidth != 1) mipWidth = @divTrunc(mipWidth, 2);
        if (mipHeight != 1) mipHeight = @divTrunc(mipHeight, 2);

        if (mipWidth < 1) mipWidth = 1;
        if (mipHeight < 1) mipHeight = 1;

        TraceLog(LOG_DEBUG, "IMAGE: Next mipmap level: %i x %i - current size %i", mipWidth, mipHeight, mipSize);

        mipCount += 1;
        mipSize += GetPixelDataSize(mipWidth, mipHeight, image.*.format);
    }

    if (image.*.mipmaps < mipCount) {
        const temp = RL_CALLOC(@intCast(mipSize), 1);
        _ = memcpy(temp, image.*.data, @intCast(GetPixelDataSize(image.*.width, image.*.height, image.*.format)));
        RL_FREE(image.*.data);
        image.*.data = temp;

        var nextmip: [*]u8 = @ptrCast(image.*.data);

        mipWidth = image.*.width;
        mipHeight = image.*.height;
        mipSize = GetPixelDataSize(mipWidth, mipHeight, image.*.format);
        var imCopy = ImageCopy(image.*);

        var i: c_int = 1;
        while (i < mipCount) : (i += 1) {
            nextmip += @intCast(mipSize);

            mipWidth = @divTrunc(mipWidth, 2);
            mipHeight = @divTrunc(mipHeight, 2);

            if (mipWidth < 1) mipWidth = 1;
            if (mipHeight < 1) mipHeight = 1;

            mipSize = GetPixelDataSize(mipWidth, mipHeight, image.*.format);

            if (i < image.*.mipmaps) continue;

            TraceLog(LOG_DEBUG, "IMAGE: Generating mipmap level: %i (%i x %i) - size: %i - offset: 0x%x", i, mipWidth, mipHeight, mipSize, nextmip);
            ImageResize(&imCopy, mipWidth, mipHeight);
            _ = memcpy(nextmip, imCopy.data, @intCast(mipSize));
        }

        UnloadImage(imCopy);

        image.*.mipmaps = mipCount;
    } else TraceLog(LOG_WARNING, "IMAGE: Mipmaps already available");
}

// Dither image data to 16bpp or lower (Floyd-Steinberg dithering)
export fn ImageDither(image: [*c]Image, rBpp: c_int, gBpp: c_int, bBpp: c_int, aBpp: c_int) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "IMAGE: Compressed data formats can not be dithered");
        return;
    }

    if ((rBpp + gBpp + bBpp + aBpp) > 16) {
        TraceLog(LOG_WARNING, "IMAGE: Unsupported dithering bpps (%ibpp), only 16bpp or lower modes supported", (rBpp + gBpp + bBpp + aBpp));
    } else {
        const pixels = LoadImageColors(image.*);

        RL_FREE(image.*.data); // free old image data

        if ((image.*.format != PIXELFORMAT_UNCOMPRESSED_R8G8B8) and (image.*.format != PIXELFORMAT_UNCOMPRESSED_R8G8B8A8)) {
            TraceLog(LOG_WARNING, "IMAGE: Format is already 16bpp or lower, dithering could have no effect");
        }

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

        image.*.data = RL_MALLOC(@intCast(image.*.width * image.*.height * @as(c_int, @sizeOf(u16))));
        const out16: [*]u16 = @ptrCast(@alignCast(image.*.data));

        var newPixel = WHITE;

        const w = image.*.width;

        var y: c_int = 0;
        while (y < image.*.height) : (y += 1) {
            var x: c_int = 0;
            while (x < image.*.width) : (x += 1) {
                const oldPixel = pixels[@intCast(y * w + x)];

                // NOTE: New pixel obtained by bits truncate
                newPixel.r = oldPixel.r >> @intCast(8 - rBpp);
                newPixel.g = oldPixel.g >> @intCast(8 - gBpp);
                newPixel.b = oldPixel.b >> @intCast(8 - bBpp);
                newPixel.a = oldPixel.a >> @intCast(8 - aBpp);

                const rError: c_int = @as(c_int, oldPixel.r) - @as(c_int, @intCast(@as(c_int, newPixel.r) << @intCast(8 - rBpp)));
                const gError: c_int = @as(c_int, oldPixel.g) - @as(c_int, @intCast(@as(c_int, newPixel.g) << @intCast(8 - gBpp)));
                const bError: c_int = @as(c_int, oldPixel.b) - @as(c_int, @intCast(@as(c_int, newPixel.b) << @intCast(8 - bBpp)));

                pixels[@intCast(y * w + x)] = newPixel;

                if (x < (image.*.width - 1)) {
                    const p = &pixels[@intCast(y * w + x + 1)];
                    p.r = iuc(MINi(@as(c_int, p.r) + ti(@as(f32, @floatFromInt(rError)) * 7.0 / 16), 0xff));
                    p.g = iuc(MINi(@as(c_int, p.g) + ti(@as(f32, @floatFromInt(gError)) * 7.0 / 16), 0xff));
                    p.b = iuc(MINi(@as(c_int, p.b) + ti(@as(f32, @floatFromInt(bError)) * 7.0 / 16), 0xff));
                }

                if ((x > 0) and (y < (image.*.height - 1))) {
                    const p = &pixels[@intCast((y + 1) * w + x - 1)];
                    p.r = iuc(MINi(@as(c_int, p.r) + ti(@as(f32, @floatFromInt(rError)) * 3.0 / 16), 0xff));
                    p.g = iuc(MINi(@as(c_int, p.g) + ti(@as(f32, @floatFromInt(gError)) * 3.0 / 16), 0xff));
                    p.b = iuc(MINi(@as(c_int, p.b) + ti(@as(f32, @floatFromInt(bError)) * 3.0 / 16), 0xff));
                }

                if (y < (image.*.height - 1)) {
                    const p = &pixels[@intCast((y + 1) * w + x)];
                    p.r = iuc(MINi(@as(c_int, p.r) + ti(@as(f32, @floatFromInt(rError)) * 5.0 / 16), 0xff));
                    p.g = iuc(MINi(@as(c_int, p.g) + ti(@as(f32, @floatFromInt(gError)) * 5.0 / 16), 0xff));
                    p.b = iuc(MINi(@as(c_int, p.b) + ti(@as(f32, @floatFromInt(bError)) * 5.0 / 16), 0xff));
                }

                if ((x < (image.*.width - 1)) and (y < (image.*.height - 1))) {
                    const p = &pixels[@intCast((y + 1) * w + x + 1)];
                    p.r = iuc(MINi(@as(c_int, p.r) + ti(@as(f32, @floatFromInt(rError)) * 1.0 / 16), 0xff));
                    p.g = iuc(MINi(@as(c_int, p.g) + ti(@as(f32, @floatFromInt(gError)) * 1.0 / 16), 0xff));
                    p.b = iuc(MINi(@as(c_int, p.b) + ti(@as(f32, @floatFromInt(bError)) * 1.0 / 16), 0xff));
                }

                const rPixel: u16 = newPixel.r;
                const gPixel: u16 = newPixel.g;
                const bPixel: u16 = newPixel.b;
                const aPixel: u16 = newPixel.a;

                out16[@intCast(y * w + x)] = (rPixel << @intCast(gBpp + bBpp + aBpp)) | (gPixel << @intCast(bBpp + aBpp)) | (bPixel << @intCast(aBpp)) | aPixel;
            }
        }

        UnloadImageColors(pixels);
    }
}

// Flip image vertically
export fn ImageFlipVertical(image: [*c]Image) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if (image.*.mipmaps > 1) TraceLog(LOG_WARNING, "Image manipulation only applied to base mipmap level");
    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image manipulation not supported for compressed formats");
    } else {
        const bytesPerPixel = GetPixelDataSize(1, 1, image.*.format);
        const flippedData: [*]u8 = @ptrCast(RL_MALLOC(@intCast(image.*.width * image.*.height * bytesPerPixel)));
        const src8: [*]const u8 = @ptrCast(image.*.data);

        var i: c_int = image.*.height - 1;
        var offsetSize: c_int = 0;
        while (i >= 0) : (i -= 1) {
            _ = memcpy(
                flippedData + @as(usize, @intCast(offsetSize)),
                src8 + @as(usize, @intCast(i * image.*.width * bytesPerPixel)),
                @intCast(image.*.width * bytesPerPixel),
            );
            offsetSize += image.*.width * bytesPerPixel;
        }

        RL_FREE(image.*.data);
        image.*.data = flippedData;
    }
}

// Flip image horizontally
export fn ImageFlipHorizontal(image: [*c]Image) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if (image.*.mipmaps > 1) TraceLog(LOG_WARNING, "Image manipulation only applied to base mipmap level");
    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image manipulation not supported for compressed formats");
    } else {
        const bytesPerPixel = GetPixelDataSize(1, 1, image.*.format);
        const flippedData: [*]u8 = @ptrCast(RL_MALLOC(@intCast(image.*.width * image.*.height * bytesPerPixel)));
        const src8: [*]const u8 = @ptrCast(image.*.data);
        const w = image.*.width;

        var y: c_int = 0;
        while (y < image.*.height) : (y += 1) {
            var x: c_int = 0;
            while (x < w) : (x += 1) {
                var i: c_int = 0;
                while (i < bytesPerPixel) : (i += 1) {
                    flippedData[@intCast((y * w + x) * bytesPerPixel + i)] = src8[@intCast((y * w + (w - 1 - x)) * bytesPerPixel + i)];
                }
            }
        }

        RL_FREE(image.*.data);
        image.*.data = flippedData;
    }
}

// Rotate image in degrees
export fn ImageRotate(image: [*c]Image, degrees: c_int) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if (image.*.mipmaps > 1) TraceLog(LOG_WARNING, "Image manipulation only applied to base mipmap level");
    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image manipulation not supported for compressed formats");
    } else {
        const rad: f32 = @as(f32, @floatFromInt(degrees)) * PI / 180.0;
        const sinRadius = sinf(rad);
        const cosRadius = cosf(rad);

        const width = ti(fabsf(@as(f32, @floatFromInt(image.*.width)) * cosRadius) + fabsf(@as(f32, @floatFromInt(image.*.height)) * sinRadius));
        const height = ti(fabsf(@as(f32, @floatFromInt(image.*.height)) * cosRadius) + fabsf(@as(f32, @floatFromInt(image.*.width)) * sinRadius));

        const bytesPerPixel = GetPixelDataSize(1, 1, image.*.format);
        const rotatedData: [*]u8 = @ptrCast(RL_CALLOC(@intCast(width * height), @intCast(bytesPerPixel)));
        const src8: [*]const u8 = @ptrCast(image.*.data);
        const iw = image.*.width;

        var y: c_int = 0;
        while (y < height) : (y += 1) {
            var x: c_int = 0;
            while (x < width) : (x += 1) {
                const oldX = ((@as(f32, @floatFromInt(x)) - @as(f32, @floatFromInt(width)) / 2.0) * cosRadius + (@as(f32, @floatFromInt(y)) - @as(f32, @floatFromInt(height)) / 2.0) * sinRadius) + @as(f32, @floatFromInt(image.*.width)) / 2.0;
                const oldY = ((@as(f32, @floatFromInt(y)) - @as(f32, @floatFromInt(height)) / 2.0) * cosRadius - (@as(f32, @floatFromInt(x)) - @as(f32, @floatFromInt(width)) / 2.0) * sinRadius) + @as(f32, @floatFromInt(image.*.height)) / 2.0;

                if ((oldX >= 0) and (oldX < @as(f32, @floatFromInt(image.*.width))) and (oldY >= 0) and (oldY < @as(f32, @floatFromInt(image.*.height)))) {
                    const x1 = ti(floorf(oldX));
                    const y1 = ti(floorf(oldY));
                    const x2 = MINi(x1 + 1, image.*.width - 1);
                    const y2 = MINi(y1 + 1, image.*.height - 1);

                    const px = oldX - @as(f32, @floatFromInt(x1));
                    const py = oldY - @as(f32, @floatFromInt(y1));

                    var i: c_int = 0;
                    while (i < bytesPerPixel) : (i += 1) {
                        const f1: f32 = @floatFromInt(src8[@intCast((y1 * iw + x1) * bytesPerPixel + i)]);
                        const f2: f32 = @floatFromInt(src8[@intCast((y1 * iw + x2) * bytesPerPixel + i)]);
                        const f3: f32 = @floatFromInt(src8[@intCast((y2 * iw + x1) * bytesPerPixel + i)]);
                        const f4: f32 = @floatFromInt(src8[@intCast((y2 * iw + x2) * bytesPerPixel + i)]);

                        const val = f1 * (1 - px) * (1 - py) + f2 * px * (1 - py) + f3 * (1 - px) * py + f4 * px * py;

                        rotatedData[@intCast((y * width + x) * bytesPerPixel + i)] = tuc(val);
                    }
                }
            }
        }

        RL_FREE(image.*.data);
        image.*.data = rotatedData;
        image.*.width = width;
        image.*.height = height;
    }
}

// Rotate image clockwise 90deg
export fn ImageRotateCW(image: [*c]Image) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if (image.*.mipmaps > 1) TraceLog(LOG_WARNING, "Image manipulation only applied to base mipmap level");
    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image manipulation not supported for compressed formats");
    } else {
        const bytesPerPixel = GetPixelDataSize(1, 1, image.*.format);
        const rotatedData: [*]u8 = @ptrCast(RL_MALLOC(@intCast(image.*.width * image.*.height * bytesPerPixel)));
        const src8: [*]const u8 = @ptrCast(image.*.data);
        const w = image.*.width;
        const hh = image.*.height;

        var y: c_int = 0;
        while (y < hh) : (y += 1) {
            var x: c_int = 0;
            while (x < w) : (x += 1) {
                var i: c_int = 0;
                while (i < bytesPerPixel) : (i += 1) {
                    rotatedData[@intCast((x * hh + (hh - y - 1)) * bytesPerPixel + i)] = src8[@intCast((y * w + x) * bytesPerPixel + i)];
                }
            }
        }

        RL_FREE(image.*.data);
        image.*.data = rotatedData;
        const width = image.*.width;
        const height = image.*.height;
        image.*.width = height;
        image.*.height = width;
    }
}

// Rotate image counter-clockwise 90deg
export fn ImageRotateCCW(image: [*c]Image) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    if (image.*.mipmaps > 1) TraceLog(LOG_WARNING, "Image manipulation only applied to base mipmap level");
    if (image.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image manipulation not supported for compressed formats");
    } else {
        const bytesPerPixel = GetPixelDataSize(1, 1, image.*.format);
        const rotatedData: [*]u8 = @ptrCast(RL_MALLOC(@intCast(image.*.width * image.*.height * bytesPerPixel)));
        const src8: [*]const u8 = @ptrCast(image.*.data);
        const w = image.*.width;
        const hh = image.*.height;

        var y: c_int = 0;
        while (y < hh) : (y += 1) {
            var x: c_int = 0;
            while (x < w) : (x += 1) {
                var i: c_int = 0;
                while (i < bytesPerPixel) : (i += 1) {
                    rotatedData[@intCast((x * hh + y) * bytesPerPixel + i)] = src8[@intCast((y * w + (w - x - 1)) * bytesPerPixel + i)];
                }
            }
        }

        RL_FREE(image.*.data);
        image.*.data = rotatedData;
        const width = image.*.width;
        const height = image.*.height;
        image.*.width = height;
        image.*.height = width;
    }
}

// Modify image color: tint
export fn ImageColorTint(image: [*c]Image, color: Color) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const pixels = LoadImageColors(image.*);

    var i: usize = 0;
    const total: usize = @intCast(image.*.width * image.*.height);
    while (i < total) : (i += 1) {
        const r: u8 = iuc(@divTrunc(@as(c_int, pixels[i].r) * @as(c_int, color.r), 255));
        const g: u8 = iuc(@divTrunc(@as(c_int, pixels[i].g) * @as(c_int, color.g), 255));
        const b: u8 = iuc(@divTrunc(@as(c_int, pixels[i].b) * @as(c_int, color.b), 255));
        const a: u8 = iuc(@divTrunc(@as(c_int, pixels[i].a) * @as(c_int, color.a), 255));

        pixels[i].r = r;
        pixels[i].g = g;
        pixels[i].b = b;
        pixels[i].a = a;
    }

    const format = image.*.format;
    RL_FREE(image.*.data);

    image.*.data = pixels;
    image.*.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

    ImageFormat(image, format);
}

// Modify image color: invert
export fn ImageColorInvert(image: [*c]Image) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const pixels = LoadImageColors(image.*);

    var i: usize = 0;
    const total: usize = @intCast(image.*.width * image.*.height);
    while (i < total) : (i += 1) {
        pixels[i].r = 255 - pixels[i].r;
        pixels[i].g = 255 - pixels[i].g;
        pixels[i].b = 255 - pixels[i].b;
    }

    const format = image.*.format;
    RL_FREE(image.*.data);

    image.*.data = pixels;
    image.*.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

    ImageFormat(image, format);
}

// Modify image color: grayscale
export fn ImageColorGrayscale(image: [*c]Image) callconv(.c) void {
    ImageFormat(image, PIXELFORMAT_UNCOMPRESSED_GRAYSCALE);
}

// Modify image color: contrast
export fn ImageColorContrast(image: [*c]Image, contrast_in: c_int) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    var contrast = contrast_in;
    if (contrast < -100) contrast = -100;
    if (contrast > 100) contrast = 100;

    var factor: f32 = @as(f32, @floatFromInt(100 + contrast)) / 100.0;
    factor *= factor;

    const pixels = LoadImageColors(image.*);

    var i: usize = 0;
    const total: usize = @intCast(image.*.width * image.*.height);
    while (i < total) : (i += 1) {
        var pR: f32 = @as(f32, @floatFromInt(pixels[i].r)) / 255.0;
        pR -= 0.5;
        pR *= factor;
        pR += 0.5;
        pR *= 255;
        if (pR < 0) pR = 0;
        if (pR > 255) pR = 255;

        var pG: f32 = @as(f32, @floatFromInt(pixels[i].g)) / 255.0;
        pG -= 0.5;
        pG *= factor;
        pG += 0.5;
        pG *= 255;
        if (pG < 0) pG = 0;
        if (pG > 255) pG = 255;

        var pB: f32 = @as(f32, @floatFromInt(pixels[i].b)) / 255.0;
        pB -= 0.5;
        pB *= factor;
        pB += 0.5;
        pB *= 255;
        if (pB < 0) pB = 0;
        if (pB > 255) pB = 255;

        pixels[i].r = tuc(pR);
        pixels[i].g = tuc(pG);
        pixels[i].b = tuc(pB);
    }

    const format = image.*.format;
    RL_FREE(image.*.data);

    image.*.data = pixels;
    image.*.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

    ImageFormat(image, format);
}

// Modify image color: brightness
export fn ImageColorBrightness(image: [*c]Image, brightness_in: c_int) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    var brightness = brightness_in;
    if (brightness < -255) brightness = -255;
    if (brightness > 255) brightness = 255;

    const pixels = LoadImageColors(image.*);

    var i: usize = 0;
    const total: usize = @intCast(image.*.width * image.*.height);
    while (i < total) : (i += 1) {
        var cR: c_int = @as(c_int, pixels[i].r) + brightness;
        var cG: c_int = @as(c_int, pixels[i].g) + brightness;
        var cB: c_int = @as(c_int, pixels[i].b) + brightness;

        if (cR < 0) cR = 1;
        if (cR > 255) cR = 255;

        if (cG < 0) cG = 1;
        if (cG > 255) cG = 255;

        if (cB < 0) cB = 1;
        if (cB > 255) cB = 255;

        pixels[i].r = iuc(cR);
        pixels[i].g = iuc(cG);
        pixels[i].b = iuc(cB);
    }

    const format = image.*.format;
    RL_FREE(image.*.data);

    image.*.data = pixels;
    image.*.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

    ImageFormat(image, format);
}

// Modify image color: replace color
export fn ImageColorReplace(image: [*c]Image, color: Color, replace: Color) callconv(.c) void {
    if ((image.*.data == null) or (image.*.width == 0) or (image.*.height == 0)) return;

    const pixels = LoadImageColors(image.*);

    var i: usize = 0;
    const total: usize = @intCast(image.*.width * image.*.height);
    while (i < total) : (i += 1) {
        if ((pixels[i].r == color.r) and
            (pixels[i].g == color.g) and
            (pixels[i].b == color.b) and
            (pixels[i].a == color.a))
        {
            pixels[i].r = replace.r;
            pixels[i].g = replace.g;
            pixels[i].b = replace.b;
            pixels[i].a = replace.a;
        }
    }

    const format = image.*.format;
    RL_FREE(image.*.data);

    image.*.data = pixels;
    image.*.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

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
export fn LoadImageColors(image: Image) callconv(.c) [*c]Color {
    if ((image.width == 0) or (image.height == 0)) return null; // Security check

    const pixels: [*c]Color = @ptrCast(@alignCast(RL_MALLOC(@intCast(image.width * image.height * @as(c_int, @sizeOf(Color))))));

    if (image.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "IMAGE: Pixel data retrieval not supported for compressed image formats");
    } else {
        if ((image.format == PIXELFORMAT_UNCOMPRESSED_R32) or
            (image.format == PIXELFORMAT_UNCOMPRESSED_R32G32B32) or
            (image.format == PIXELFORMAT_UNCOMPRESSED_R32G32B32A32)) TraceLog(LOG_WARNING, "IMAGE: Pixel format converted from 32bit to 8bit per channel");

        if ((image.format == PIXELFORMAT_UNCOMPRESSED_R16) or
            (image.format == PIXELFORMAT_UNCOMPRESSED_R16G16B16) or
            (image.format == PIXELFORMAT_UNCOMPRESSED_R16G16B16A16)) TraceLog(LOG_WARNING, "IMAGE: Pixel format converted from 16bit to 8bit per channel");

        const d8: [*]const u8 = @ptrCast(image.data);
        const d16: [*]const u16 = @ptrCast(@alignCast(image.data));
        const d32: [*]const f32 = @ptrCast(@alignCast(image.data));

        var i: usize = 0;
        var k: usize = 0;
        const total: usize = @intCast(image.width * image.height);
        while (i < total) : (i += 1) {
            switch (image.format) {
                PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => {
                    pixels[i].r = d8[i];
                    pixels[i].g = d8[i];
                    pixels[i].b = d8[i];
                    pixels[i].a = 255;
                },
                PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
                    pixels[i].r = d8[k];
                    pixels[i].g = d8[k];
                    pixels[i].b = d8[k];
                    pixels[i].a = d8[k + 1];
                    k += 2;
                },
                PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
                    const pixel = d16[i];
                    pixels[i].r = tuc(@as(f32, @floatFromInt((pixel & 0b1111100000000000) >> 11)) * (255.0 / 31.0));
                    pixels[i].g = tuc(@as(f32, @floatFromInt((pixel & 0b0000011111000000) >> 6)) * (255.0 / 31.0));
                    pixels[i].b = tuc(@as(f32, @floatFromInt((pixel & 0b0000000000111110) >> 1)) * (255.0 / 31.0));
                    pixels[i].a = iuc((pixel & 0b0000000000000001) * 255);
                },
                PIXELFORMAT_UNCOMPRESSED_R5G6B5 => {
                    const pixel = d16[i];
                    pixels[i].r = tuc(@as(f32, @floatFromInt((pixel & 0b1111100000000000) >> 11)) * (255.0 / 31.0));
                    pixels[i].g = tuc(@as(f32, @floatFromInt((pixel & 0b0000011111100000) >> 5)) * (255.0 / 63.0));
                    pixels[i].b = tuc(@as(f32, @floatFromInt(pixel & 0b0000000000011111)) * (255.0 / 31.0));
                    pixels[i].a = 255;
                },
                PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
                    const pixel = d16[i];
                    pixels[i].r = tuc(@as(f32, @floatFromInt((pixel & 0b1111000000000000) >> 12)) * (255.0 / 15.0));
                    pixels[i].g = tuc(@as(f32, @floatFromInt((pixel & 0b0000111100000000) >> 8)) * (255.0 / 15.0));
                    pixels[i].b = tuc(@as(f32, @floatFromInt((pixel & 0b0000000011110000) >> 4)) * (255.0 / 15.0));
                    pixels[i].a = tuc(@as(f32, @floatFromInt(pixel & 0b0000000000001111)) * (255.0 / 15.0));
                },
                PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => {
                    pixels[i].r = d8[k];
                    pixels[i].g = d8[k + 1];
                    pixels[i].b = d8[k + 2];
                    pixels[i].a = d8[k + 3];
                    k += 4;
                },
                PIXELFORMAT_UNCOMPRESSED_R8G8B8 => {
                    pixels[i].r = d8[k];
                    pixels[i].g = d8[k + 1];
                    pixels[i].b = d8[k + 2];
                    pixels[i].a = 255;
                    k += 3;
                },
                PIXELFORMAT_UNCOMPRESSED_R32 => {
                    pixels[i].r = tuc(d32[k] * 255.0);
                    pixels[i].g = 0;
                    pixels[i].b = 0;
                    pixels[i].a = 255;
                    k += 1;
                },
                PIXELFORMAT_UNCOMPRESSED_R32G32B32 => {
                    pixels[i].r = tuc(d32[k] * 255.0);
                    pixels[i].g = tuc(d32[k + 1] * 255.0);
                    pixels[i].b = tuc(d32[k + 2] * 255.0);
                    pixels[i].a = 255;
                    k += 3;
                },
                PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => {
                    pixels[i].r = tuc(d32[k] * 255.0);
                    pixels[i].g = tuc(d32[k + 1] * 255.0);
                    pixels[i].b = tuc(d32[k + 2] * 255.0);
                    pixels[i].a = tuc(d32[k + 3] * 255.0);
                    k += 4;
                },
                PIXELFORMAT_UNCOMPRESSED_R16 => {
                    pixels[i].r = tuc(HalfToFloat(d16[k]) * 255.0);
                    pixels[i].g = 0;
                    pixels[i].b = 0;
                    pixels[i].a = 255;
                    k += 1;
                },
                PIXELFORMAT_UNCOMPRESSED_R16G16B16 => {
                    pixels[i].r = tuc(HalfToFloat(d16[k]) * 255.0);
                    pixels[i].g = tuc(HalfToFloat(d16[k + 1]) * 255.0);
                    pixels[i].b = tuc(HalfToFloat(d16[k + 2]) * 255.0);
                    pixels[i].a = 255;
                    k += 3;
                },
                PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => {
                    pixels[i].r = tuc(HalfToFloat(d16[k]) * 255.0);
                    pixels[i].g = tuc(HalfToFloat(d16[k + 1]) * 255.0);
                    pixels[i].b = tuc(HalfToFloat(d16[k + 2]) * 255.0);
                    pixels[i].a = tuc(HalfToFloat(d16[k + 3]) * 255.0);
                    k += 4;
                },
                else => {},
            }
        }
    }

    return pixels;
}

// Load colors palette from image as a Color array (RGBA - 32bit)
export fn LoadImagePalette(image: Image, maxPaletteSize: c_int, colorCount: [*c]c_int) callconv(.c) [*c]Color {
    var palCount: c_int = 0;
    var palette: [*c]Color = null;
    const pixels = LoadImageColors(image);

    if (pixels != null) {
        palette = @ptrCast(@alignCast(RL_MALLOC(@intCast(maxPaletteSize * @as(c_int, @sizeOf(Color))))));

        var j: usize = 0;
        while (j < @as(usize, @intCast(maxPaletteSize))) : (j += 1) palette[j] = BLANK;

        var i: c_int = 0;
        const total: c_int = image.width * image.height;
        while (i < total) : (i += 1) {
            if (pixels[@intCast(i)].a > 0) {
                var colorInPalette = false;

                var jj: c_int = 0;
                while (jj < maxPaletteSize) : (jj += 1) {
                    const c1 = pixels[@intCast(i)];
                    const c2 = palette[@intCast(jj)];
                    if ((c1.r == c2.r) and (c1.g == c2.g) and (c1.b == c2.b) and (c1.a == c2.a)) {
                        colorInPalette = true;
                        break;
                    }
                }

                if (!colorInPalette) {
                    palette[@intCast(palCount)] = pixels[@intCast(i)];
                    palCount += 1;

                    if (palCount >= maxPaletteSize) {
                        i = image.width * image.height;
                        TraceLog(LOG_WARNING, "IMAGE: Palette is greater than %i colors", maxPaletteSize);
                    }
                }
            }
        }

        UnloadImageColors(pixels);
    }

    colorCount.* = palCount;

    return palette;
}

// Unload color data loaded with LoadImageColors()
export fn UnloadImageColors(colors: [*c]Color) callconv(.c) void {
    RL_FREE(colors);
}

// Unload colors palette loaded with LoadImagePalette()
export fn UnloadImagePalette(colors: [*c]Color) callconv(.c) void {
    RL_FREE(colors);
}

// Get image alpha border rectangle
export fn GetImageAlphaBorder(image: Image, threshold: f32) callconv(.c) Rectangle {
    var crop: Rectangle = std.mem.zeroes(Rectangle);

    const pixels = LoadImageColors(image);

    if (pixels != null) {
        var xMin: c_int = 65536;
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

        if ((xMin != 65536) and (xMax != 65536)) {
            crop = .{ .x = @floatFromInt(xMin), .y = @floatFromInt(yMin), .width = @floatFromInt((xMax + 1) - xMin), .height = @floatFromInt((yMax + 1) - yMin) };
        }

        UnloadImageColors(pixels);
    }

    return crop;
}

// Get image pixel color at (x, y) position
export fn GetImageColor(image: Image, x: c_int, y: c_int) callconv(.c) Color {
    var color: Color = std.mem.zeroes(Color);

    if ((x >= 0) and (x < image.width) and (y >= 0) and (y < image.height)) {
        const idx: usize = @intCast(y * image.width + x);
        const d8: [*]const u8 = @ptrCast(image.data);
        const d16: [*]const u16 = @ptrCast(@alignCast(image.data));
        const d32: [*]const f32 = @ptrCast(@alignCast(image.data));

        switch (image.format) {
            PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => {
                color.r = d8[idx];
                color.g = d8[idx];
                color.b = d8[idx];
                color.a = 255;
            },
            PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
                color.r = d8[idx * 2];
                color.g = d8[idx * 2];
                color.b = d8[idx * 2];
                color.a = d8[idx * 2 + 1];
            },
            PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
                const pixel = d16[idx];
                color.r = tuc(@as(f32, @floatFromInt((pixel & 0b1111100000000000) >> 11)) * (255.0 / 31.0));
                color.g = tuc(@as(f32, @floatFromInt((pixel & 0b0000011111000000) >> 6)) * (255.0 / 31.0));
                color.b = tuc(@as(f32, @floatFromInt((pixel & 0b0000000000111110) >> 1)) * (255.0 / 31.0));
                color.a = iuc((pixel & 0b0000000000000001) * 255);
            },
            PIXELFORMAT_UNCOMPRESSED_R5G6B5 => {
                const pixel = d16[idx];
                color.r = tuc(@as(f32, @floatFromInt((pixel & 0b1111100000000000) >> 11)) * (255.0 / 31.0));
                color.g = tuc(@as(f32, @floatFromInt((pixel & 0b0000011111100000) >> 5)) * (255.0 / 63.0));
                color.b = tuc(@as(f32, @floatFromInt(pixel & 0b0000000000011111)) * (255.0 / 31.0));
                color.a = 255;
            },
            PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
                const pixel = d16[idx];
                color.r = tuc(@as(f32, @floatFromInt((pixel & 0b1111000000000000) >> 12)) * (255.0 / 15.0));
                color.g = tuc(@as(f32, @floatFromInt((pixel & 0b0000111100000000) >> 8)) * (255.0 / 15.0));
                color.b = tuc(@as(f32, @floatFromInt((pixel & 0b0000000011110000) >> 4)) * (255.0 / 15.0));
                color.a = tuc(@as(f32, @floatFromInt(pixel & 0b0000000000001111)) * (255.0 / 15.0));
            },
            PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => {
                color.r = d8[idx * 4];
                color.g = d8[idx * 4 + 1];
                color.b = d8[idx * 4 + 2];
                color.a = d8[idx * 4 + 3];
            },
            PIXELFORMAT_UNCOMPRESSED_R8G8B8 => {
                color.r = d8[idx * 3];
                color.g = d8[idx * 3 + 1];
                color.b = d8[idx * 3 + 2];
                color.a = 255;
            },
            PIXELFORMAT_UNCOMPRESSED_R32 => {
                color.r = tuc(d32[idx] * 255.0);
                color.g = 0;
                color.b = 0;
                color.a = 255;
            },
            PIXELFORMAT_UNCOMPRESSED_R32G32B32 => {
                color.r = tuc(d32[idx * 3] * 255.0);
                color.g = tuc(d32[idx * 3 + 1] * 255.0);
                color.b = tuc(d32[idx * 3 + 2] * 255.0);
                color.a = 255;
            },
            PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => {
                color.r = tuc(d32[idx * 4] * 255.0);
                color.g = tuc(d32[idx * 4 + 1] * 255.0);
                color.b = tuc(d32[idx * 4 + 2] * 255.0);
                color.a = tuc(d32[idx * 4 + 3] * 255.0);
            },
            PIXELFORMAT_UNCOMPRESSED_R16 => {
                color.r = tuc(HalfToFloat(d16[idx]) * 255.0);
                color.g = 0;
                color.b = 0;
                color.a = 255;
            },
            PIXELFORMAT_UNCOMPRESSED_R16G16B16 => {
                color.r = tuc(HalfToFloat(d16[idx * 3]) * 255.0);
                color.g = tuc(HalfToFloat(d16[idx * 3 + 1]) * 255.0);
                color.b = tuc(HalfToFloat(d16[idx * 3 + 2]) * 255.0);
                color.a = 255;
            },
            PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => {
                color.r = tuc(HalfToFloat(d16[idx * 4]) * 255.0);
                color.g = tuc(HalfToFloat(d16[idx * 4 + 1]) * 255.0);
                color.b = tuc(HalfToFloat(d16[idx * 4 + 2]) * 255.0);
                color.a = tuc(HalfToFloat(d16[idx * 4 + 3]) * 255.0);
            },
            else => TraceLog(LOG_WARNING, "Compressed image format does not support color reading"),
        }
    } else TraceLog(LOG_WARNING, "Requested image pixel (%i, %i) out of bounds", x, y);

    return color;
}

//------------------------------------------------------------------------------------
// Image drawing functions
//------------------------------------------------------------------------------------
// Clear image background with given color
export fn ImageClearBackground(dst: [*c]Image, color: Color) callconv(.c) void {
    if ((dst.*.data == null) or (dst.*.width == 0) or (dst.*.height == 0)) return;

    // Fill in first pixel based on image format
    ImageDrawPixel(dst, 0, 0, color);

    const pSrcPixel: [*]u8 = @ptrCast(dst.*.data);
    const bytesPerPixel = GetPixelDataSize(1, 1, dst.*.format);
    const totalPixels = dst.*.width * dst.*.height;

    var i: c_int = 1;
    while (i < totalPixels) : (i *= 2) {
        const pixelsToCopy = MINi(i, totalPixels - i);
        _ = memcpy(pSrcPixel + @as(usize, @intCast(i * bytesPerPixel)), pSrcPixel, @intCast(pixelsToCopy * bytesPerPixel));
    }
}

// Draw pixel within an image
export fn ImageDrawPixel(dst: [*c]Image, x: c_int, y: c_int, color: Color) callconv(.c) void {
    if ((dst.*.data == null) or (x < 0) or (x >= dst.*.width) or (y < 0) or (y >= dst.*.height)) return;

    const idx: usize = @intCast(y * dst.*.width + x);

    switch (dst.*.format) {
        PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => {
            const coln = Vector3{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0 };
            const gray: u8 = tuc((coln.x * 0.299 + coln.y * 0.587 + coln.z * 0.114) * 255.0);
            const d: [*]u8 = @ptrCast(dst.*.data);
            d[idx] = gray;
        },
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
            const coln = Vector3{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0 };
            const gray: u8 = tuc((coln.x * 0.299 + coln.y * 0.587 + coln.z * 0.114) * 255.0);
            const d: [*]u8 = @ptrCast(dst.*.data);
            d[idx * 2] = gray;
            d[idx * 2 + 1] = color.a;
        },
        PIXELFORMAT_UNCOMPRESSED_R5G6B5 => {
            const coln = Vector3{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0 };
            const r: u16 = tuc(round(@floatCast(coln.x * 31.0)));
            const g: u16 = tuc(round(@floatCast(coln.y * 63.0)));
            const b: u16 = tuc(round(@floatCast(coln.z * 31.0)));
            const d: [*]u16 = @ptrCast(@alignCast(dst.*.data));
            d[idx] = (r << 11) | (g << 5) | b;
        },
        PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
            const coln = Vector4{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0, .w = @as(f32, @floatFromInt(color.a)) / 255.0 };
            const r: u16 = tuc(round(@floatCast(coln.x * 31.0)));
            const g: u16 = tuc(round(@floatCast(coln.y * 31.0)));
            const b: u16 = tuc(round(@floatCast(coln.z * 31.0)));
            const a: u16 = if (coln.w > (@as(f32, @floatFromInt(PIXELFORMAT_UNCOMPRESSED_R5G5B5A1_ALPHA_THRESHOLD)) / 255.0)) 1 else 0;
            const d: [*]u16 = @ptrCast(@alignCast(dst.*.data));
            d[idx] = (r << 11) | (g << 6) | (b << 1) | a;
        },
        PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
            const coln = Vector4{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0, .w = @as(f32, @floatFromInt(color.a)) / 255.0 };
            const r: u16 = tuc(round(@floatCast(coln.x * 15.0)));
            const g: u16 = tuc(round(@floatCast(coln.y * 15.0)));
            const b: u16 = tuc(round(@floatCast(coln.z * 15.0)));
            const a: u16 = tuc(round(@floatCast(coln.w * 15.0)));
            const d: [*]u16 = @ptrCast(@alignCast(dst.*.data));
            d[idx] = (r << 12) | (g << 8) | (b << 4) | a;
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8 => {
            const d: [*]u8 = @ptrCast(dst.*.data);
            d[idx * 3] = color.r;
            d[idx * 3 + 1] = color.g;
            d[idx * 3 + 2] = color.b;
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => {
            const d: [*]u8 = @ptrCast(dst.*.data);
            d[idx * 4] = color.r;
            d[idx * 4 + 1] = color.g;
            d[idx * 4 + 2] = color.b;
            d[idx * 4 + 3] = color.a;
        },
        PIXELFORMAT_UNCOMPRESSED_R32 => {
            const coln = Vector3{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0 };
            const d: [*]f32 = @ptrCast(@alignCast(dst.*.data));
            d[idx] = coln.x * 0.299 + coln.y * 0.587 + coln.z * 0.114;
        },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32 => {
            const coln = Vector3{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0 };
            const d: [*]f32 = @ptrCast(@alignCast(dst.*.data));
            d[idx * 3] = coln.x;
            d[idx * 3 + 1] = coln.y;
            d[idx * 3 + 2] = coln.z;
        },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => {
            const coln = Vector4{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0, .w = @as(f32, @floatFromInt(color.a)) / 255.0 };
            const d: [*]f32 = @ptrCast(@alignCast(dst.*.data));
            d[idx * 4] = coln.x;
            d[idx * 4 + 1] = coln.y;
            d[idx * 4 + 2] = coln.z;
            d[idx * 4 + 3] = coln.w;
        },
        PIXELFORMAT_UNCOMPRESSED_R16 => {
            const coln = Vector3{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0 };
            const d: [*]u16 = @ptrCast(@alignCast(dst.*.data));
            d[idx] = FloatToHalf(coln.x * 0.299 + coln.y * 0.587 + coln.z * 0.114);
        },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16 => {
            const coln = Vector3{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0 };
            const d: [*]u16 = @ptrCast(@alignCast(dst.*.data));
            d[idx * 3] = FloatToHalf(coln.x);
            d[idx * 3 + 1] = FloatToHalf(coln.y);
            d[idx * 3 + 2] = FloatToHalf(coln.z);
        },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => {
            const coln = Vector4{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0, .w = @as(f32, @floatFromInt(color.a)) / 255.0 };
            const d: [*]u16 = @ptrCast(@alignCast(dst.*.data));
            d[idx * 4] = FloatToHalf(coln.x);
            d[idx * 4 + 1] = FloatToHalf(coln.y);
            d[idx * 4 + 2] = FloatToHalf(coln.z);
            d[idx * 4 + 3] = FloatToHalf(coln.w);
        },
        else => {},
    }
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

    if (absi(shortLen) > absi(longLen)) {
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

    if ((dx != 0) and (absi(@divTrunc(dy, dx)) < 1)) {
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
    var i: c_int = 0;
    while (i < pointCount - 1) : (i += 1) {
        ImageDrawLineV(dst, points[@intCast(i)], points[@intCast(i + 1)], color);
    }
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

                var finalColor: Color = std.mem.zeroes(Color);
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
    if (pointCount >= 3) {
        var i: c_int = 1;
        while (i < pointCount - 1) : (i += 1) {
            ImageDrawTriangle(dst, points[0], points[@intCast(i)], points[@intCast(i + 1)], color);
        }
    }
}

// Draw a triangle strip defined by points within an image
export fn ImageDrawTriangleStrip(dst: [*c]Image, points: [*c]const Vector2, pointCount: c_int, color: Color) callconv(.c) void {
    if (pointCount >= 3) {
        var i: c_int = 2;
        while (i < pointCount) : (i += 1) {
            if (@rem(i, 2) == 0) {
                ImageDrawTriangle(dst, points[@intCast(i)], points[@intCast(i - 2)], points[@intCast(i - 1)], color);
            } else ImageDrawTriangle(dst, points[@intCast(i)], points[@intCast(i - 1)], points[@intCast(i - 2)], color);
        }
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

    const bytesPerPixel = GetPixelDataSize(1, 1, dst.*.format);

    ImageDrawPixel(dst, sx, sy, color);

    const bytesOffset = ((sy * dst.*.width) + sx) * bytesPerPixel;
    const base8: [*]u8 = @ptrCast(dst.*.data);
    const pSrcPixel = base8 + @as(usize, @intCast(bytesOffset));

    var x: c_int = 1;
    while (x < ti(rec.width)) : (x *= 2) {
        const pixelsToCopy = MINi(x, ti(rec.width) - x);
        _ = memcpy(pSrcPixel + @as(usize, @intCast(x * bytesPerPixel)), pSrcPixel, @intCast(pixelsToCopy * bytesPerPixel));
    }

    const bytesPerRow = bytesPerPixel * ti(rec.width);
    var yy: c_int = 1;
    while (yy < ti(rec.height)) : (yy += 1) {
        _ = memcpy(pSrcPixel + @as(usize, @intCast((yy * dst.*.width) * bytesPerPixel)), pSrcPixel, @intCast(bytesPerRow));
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

// Draw circle within an image
export fn ImageDrawCircle(dst: [*c]Image, centerX: c_int, centerY: c_int, radius: c_int, color: Color) callconv(.c) void {
    var x: c_int = 0;
    var y: c_int = radius;
    var decesionParameter: c_int = 3 - 2 * radius;

    while (y >= x) {
        ImageDrawRectangle(dst, centerX - x, centerY + y, x * 2, 1, color);
        ImageDrawRectangle(dst, centerX - x, centerY - y, x * 2, 1, color);
        ImageDrawRectangle(dst, centerX - y, centerY + x, y * 2, 1, color);
        ImageDrawRectangle(dst, centerX - y, centerY - x, y * 2, 1, color);
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
    // TODO: Implement gradient circle drawing
    _ = dst;
    _ = center;
    _ = radius;
    _ = inner;
    _ = outer;
}

// Draw an image within an image
export fn ImageDrawImage(dst: [*c]Image, src: Image, posX: c_int, posY: c_int, tint: Color) callconv(.c) void {
    const srcRec = Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(src.width), .height = @floatFromInt(src.height) };
    const dstRec = Rectangle{ .x = @floatFromInt(posX), .y = @floatFromInt(posY), .width = srcRec.width, .height = srcRec.height };
    ImageDrawImagePro(dst, src, srcRec, dstRec, .{ .x = 0, .y = 0 }, 0.0, tint);
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

    if ((dst.*.data == null) or (dst.*.width == 0) or (dst.*.height == 0) or
        (src.data == null) or (src.width == 0) or (src.height == 0)) return;

    if (dst.*.format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) {
        TraceLog(LOG_WARNING, "Image drawing not supported for compressed formats");
    } else {
        var srcMod: Image = std.mem.zeroes(Image);
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

        var blend: Color = std.mem.zeroes(Color);
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
                _ = memcpy(pDst, pSrc, @intCast(ti(srcRec.width) * bytesPerPixelSrc));
            } else {
                var x: c_int = 0;
                while (x < ti(srcRec.width)) : (x += 1) {
                    const colSrc = GetPixelColor(pSrc, srcPtr.format);
                    const colDst = GetPixelColor(pDst, dst.*.format);

                    if (blendRequired) blend = ColorAlphaBlend(colDst, colSrc, tint) else blend = colSrc;

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
            mipmapDst.data = ptrAdd(@as([*]u8, @ptrCast(mipmapDst.data)), GetPixelDataSize(mipmapDst.width, mipmapDst.height, mipmapDst.format));
            mipmapDst.width = @divTrunc(mipmapDst.width, 2);
            mipmapDst.height = @divTrunc(mipmapDst.height, 2);
            mipmapDst.mipmaps -= 1;

            var mipmapSrc = src;
            mipmapSrc.data = ptrAdd(@as([*]u8, @ptrCast(mipmapSrc.data)), GetPixelDataSize(mipmapSrc.width, mipmapSrc.height, mipmapSrc.format));
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

//------------------------------------------------------------------------------------
// Texture loading functions
//------------------------------------------------------------------------------------
// Load texture from file into GPU memory (VRAM)
export fn LoadTexture(fileName: [*c]const u8) callconv(.c) Texture2D {
    var texture: Texture2D = std.mem.zeroes(Texture2D);

    const image = LoadImage(fileName);

    if (image.data != null) {
        texture = LoadTextureFromImage(image);
        UnloadImage(image);
    }

    return texture;
}

// Load a texture from image data
export fn LoadTextureFromImage(image: Image) callconv(.c) Texture2D {
    var texture: Texture2D = std.mem.zeroes(Texture2D);

    if ((image.width != 0) and (image.height != 0)) {
        texture.id = rlLoadTexture(image.data, image.width, image.height, image.format, image.mipmaps);
    } else TraceLog(LOG_WARNING, "IMAGE: Data is not valid to load texture");

    texture.width = image.width;
    texture.height = image.height;
    texture.mipmaps = image.mipmaps;
    texture.format = image.format;

    return texture;
}

// Load cubemap from image, multiple image cubemap layouts supported
export fn LoadTextureCubemap(image: Image, layout_in: c_int) callconv(.c) TextureCubemap {
    var cubemap: TextureCubemap = std.mem.zeroes(TextureCubemap);
    var layout = layout_in;

    if (layout == CUBEMAP_LAYOUT_AUTO_DETECT) {
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

    if (layout != CUBEMAP_LAYOUT_AUTO_DETECT) {
        const size = cubemap.width;

        var faces: Image = std.mem.zeroes(Image);
        var faceRecs: [6]Rectangle = std.mem.zeroes([6]Rectangle);

        {
            var i: usize = 0;
            while (i < 6) : (i += 1) faceRecs[i] = .{ .x = 0, .y = 0, .width = @floatFromInt(size), .height = @floatFromInt(size) };
        }

        if (layout == CUBEMAP_LAYOUT_LINE_VERTICAL) {
            faces = ImageCopy(image);
        } else {
            if (layout == CUBEMAP_LAYOUT_LINE_HORIZONTAL) {
                var i: c_int = 0;
                while (i < 6) : (i += 1) faceRecs[@intCast(i)].x = @floatFromInt(size * i);
            } else if (layout == CUBEMAP_LAYOUT_CROSS_THREE_BY_FOUR) {
                faceRecs[0].x = @floatFromInt(size);
                faceRecs[0].y = @floatFromInt(size);
                faceRecs[1].x = @floatFromInt(size);
                faceRecs[1].y = @floatFromInt(size * 3);
                faceRecs[2].x = @floatFromInt(size);
                faceRecs[2].y = 0;
                faceRecs[3].x = @floatFromInt(size);
                faceRecs[3].y = @floatFromInt(size * 2);
                faceRecs[4].x = 0;
                faceRecs[4].y = @floatFromInt(size);
                faceRecs[5].x = @floatFromInt(size * 2);
                faceRecs[5].y = @floatFromInt(size);
            } else if (layout == CUBEMAP_LAYOUT_CROSS_FOUR_BY_THREE) {
                faceRecs[0].x = @floatFromInt(size * 2);
                faceRecs[0].y = @floatFromInt(size);
                faceRecs[1].x = 0;
                faceRecs[1].y = @floatFromInt(size);
                faceRecs[2].x = @floatFromInt(size);
                faceRecs[2].y = 0;
                faceRecs[3].x = @floatFromInt(size);
                faceRecs[3].y = @floatFromInt(size * 2);
                faceRecs[4].x = @floatFromInt(size);
                faceRecs[4].y = @floatFromInt(size);
                faceRecs[5].x = @floatFromInt(size * 3);
                faceRecs[5].y = @floatFromInt(size);
            }

            faces = GenImageColor(size, size * 6, MAGENTA);
            ImageFormat(&faces, image.format);

            var mipmapped = ImageCopy(image);
            if (image.mipmaps > 1) {
                ImageMipmaps(&mipmapped);
                ImageMipmaps(&faces);
            }

            var i: c_int = 0;
            while (i < 6) : (i += 1) {
                ImageDrawImagePro(&faces, mipmapped, faceRecs[@intCast(i)], .{ .x = 0, .y = @floatFromInt(size * i), .width = @floatFromInt(size), .height = @floatFromInt(size) }, .{ .x = 0, .y = 0 }, 0.0, WHITE);
            }

            UnloadImage(mipmapped);
        }

        cubemap.id = rlLoadTextureCubemap(faces.data, size, faces.format, faces.mipmaps);

        if (cubemap.id != 0) {
            cubemap.format = faces.format;
            cubemap.mipmaps = faces.mipmaps;
        } else TraceLog(LOG_WARNING, "IMAGE: Failed to load cubemap image");

        UnloadImage(faces);
    } else TraceLog(LOG_WARNING, "IMAGE: Failed to detect cubemap image layout");

    return cubemap;
}

// Load texture for rendering (framebuffer)
export fn LoadRenderTexture(width: c_int, height: c_int) callconv(.c) RenderTexture2D {
    var target: RenderTexture2D = std.mem.zeroes(RenderTexture2D);

    target.id = rlLoadFramebuffer(); // Load an empty framebuffer

    if (target.id > 0) {
        rlEnableFramebuffer(target.id);

        // Create color texture (default to RGBA)
        target.texture.id = rlLoadTexture(null, width, height, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, 1);
        target.texture.width = width;
        target.texture.height = height;
        target.texture.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
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
    var result = false;

    if ((texture.id > 0) and
        (texture.width > 0) and
        (texture.height > 0) and
        (texture.format > 0) and
        (texture.mipmaps > 0)) result = true;

    return result;
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
    var result = false;

    if ((target.id > 0) and
        IsTextureValid(target.depth) and
        IsTextureValid(target.texture)) result = true;

    return result;
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
    const dstrec = Rectangle{ .x = position.x, .y = position.y, .width = fabsf(rec.width), .height = fabsf(rec.height) };
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

        var topLeft: Vector2 = std.mem.zeroes(Vector2);
        var topRight: Vector2 = std.mem.zeroes(Vector2);
        var bottomLeft: Vector2 = std.mem.zeroes(Vector2);
        var bottomRight: Vector2 = std.mem.zeroes(Vector2);

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

        var vertA: Vector2 = std.mem.zeroes(Vector2);
        var vertB: Vector2 = std.mem.zeroes(Vector2);
        var vertC: Vector2 = std.mem.zeroes(Vector2);
        var vertD: Vector2 = std.mem.zeroes(Vector2);
        vertA.x = 0.0; // Outer left
        vertA.y = 0.0; // Outer top
        vertB.x = leftBorder; // Inner left
        vertB.y = topBorder; // Inner top
        vertC.x = patchWidth - rightBorder; // Inner right
        vertC.y = patchHeight - bottomBorder; // Inner bottom
        vertD.x = patchWidth; // Outer right
        vertD.y = patchHeight; // Outer bottom

        var coordA: Vector2 = std.mem.zeroes(Vector2);
        var coordB: Vector2 = std.mem.zeroes(Vector2);
        var coordC: Vector2 = std.mem.zeroes(Vector2);
        var coordD: Vector2 = std.mem.zeroes(Vector2);
        coordA.x = nPatchInfo.source.x / width;
        coordA.y = nPatchInfo.source.y / height;
        coordB.x = (nPatchInfo.source.x + leftBorder) / width;
        coordB.y = (nPatchInfo.source.y + topBorder) / height;
        coordC.x = (nPatchInfo.source.x + nPatchInfo.source.width - rightBorder) / width;
        coordC.y = (nPatchInfo.source.y + nPatchInfo.source.height - bottomBorder) / height;
        coordD.x = (nPatchInfo.source.x + nPatchInfo.source.width) / width;
        coordD.y = (nPatchInfo.source.y + nPatchInfo.source.height) / height;

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
    var result = false;
    if ((col1.r == col2.r) and (col1.g == col2.g) and (col1.b == col2.b) and (col1.a == col2.a)) result = true;
    return result;
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
    var hsv: Vector3 = std.mem.zeroes(Vector3);
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
    var result = color;

    const r: u8 = iuc(@divTrunc(@as(c_int, color.r) * @as(c_int, tint.r), 255));
    const g: u8 = iuc(@divTrunc(@as(c_int, color.g) * @as(c_int, tint.g), 255));
    const b: u8 = iuc(@divTrunc(@as(c_int, color.b) * @as(c_int, tint.b), 255));
    const a: u8 = iuc(@divTrunc(@as(c_int, color.a) * @as(c_int, tint.a), 255));

    result.r = r;
    result.g = g;
    result.b = b;
    result.a = a;

    return result;
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
    var color: Color = std.mem.zeroes(Color);
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
export fn GetPixelColor(srcPtr: ?*const anyopaque, format: c_int) callconv(.c) Color {
    var color: Color = std.mem.zeroes(Color);

    // The wider views are computed lazily inside the arms that use them: for
    // 1-byte formats srcPtr is often odd-aligned (a byte offset into the image),
    // and an eager @alignCast would trap. C casts per-case for the same reason.
    const s8: [*]const u8 = @ptrCast(srcPtr);
    const S = struct {
        inline fn u16s(p: ?*const anyopaque) [*]const u16 {
            return @ptrCast(@alignCast(p));
        }
        inline fn f32s(p: ?*const anyopaque) [*]const f32 {
            return @ptrCast(@alignCast(p));
        }
    };
    const s16 = S.u16s;
    const s32 = S.f32s;

    switch (format) {
        PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => color = .{ .r = s8[0], .g = s8[0], .b = s8[0], .a = 255 },
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => color = .{ .r = s8[0], .g = s8[0], .b = s8[0], .a = s8[1] },
        PIXELFORMAT_UNCOMPRESSED_R5G6B5 => {
            color.r = iuc(@divTrunc(@as(c_int, (s16(srcPtr)[0] >> 11)) * 255, 31));
            color.g = iuc(@divTrunc(@as(c_int, ((s16(srcPtr)[0] >> 5) & 0b0000000000111111)) * 255, 63));
            color.b = iuc(@divTrunc(@as(c_int, (s16(srcPtr)[0] & 0b0000000000011111)) * 255, 31));
            color.a = 255;
        },
        PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
            color.r = iuc(@divTrunc(@as(c_int, (s16(srcPtr)[0] >> 11)) * 255, 31));
            color.g = iuc(@divTrunc(@as(c_int, ((s16(srcPtr)[0] >> 6) & 0b0000000000011111)) * 255, 31));
            color.b = iuc(@divTrunc(@as(c_int, (s16(srcPtr)[0] & 0b0000000000011111)) * 255, 31));
            color.a = if ((s16(srcPtr)[0] & 0b0000000000000001) != 0) 255 else 0;
        },
        PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
            color.r = iuc(@divTrunc(@as(c_int, (s16(srcPtr)[0] >> 12)) * 255, 15));
            color.g = iuc(@divTrunc(@as(c_int, ((s16(srcPtr)[0] >> 8) & 0b0000000000001111)) * 255, 15));
            color.b = iuc(@divTrunc(@as(c_int, ((s16(srcPtr)[0] >> 4) & 0b0000000000001111)) * 255, 15));
            color.a = iuc(@divTrunc(@as(c_int, (s16(srcPtr)[0] & 0b0000000000001111)) * 255, 15));
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => color = .{ .r = s8[0], .g = s8[1], .b = s8[2], .a = s8[3] },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8 => color = .{ .r = s8[0], .g = s8[1], .b = s8[2], .a = 255 },
        PIXELFORMAT_UNCOMPRESSED_R32 => {
            color.r = tuc(s32(srcPtr)[0] * 255.0);
            color.g = tuc(s32(srcPtr)[0] * 255.0);
            color.b = tuc(s32(srcPtr)[0] * 255.0);
            color.a = 255;
        },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32 => {
            color.r = tuc(s32(srcPtr)[0] * 255.0);
            color.g = tuc(s32(srcPtr)[1] * 255.0);
            color.b = tuc(s32(srcPtr)[2] * 255.0);
            color.a = 255;
        },
        PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => {
            color.r = tuc(s32(srcPtr)[0] * 255.0);
            color.g = tuc(s32(srcPtr)[1] * 255.0);
            color.b = tuc(s32(srcPtr)[2] * 255.0);
            color.a = tuc(s32(srcPtr)[3] * 255.0);
        },
        PIXELFORMAT_UNCOMPRESSED_R16 => {
            color.r = tuc(HalfToFloat(s16(srcPtr)[0]) * 255.0);
            color.g = tuc(HalfToFloat(s16(srcPtr)[0]) * 255.0);
            color.b = tuc(HalfToFloat(s16(srcPtr)[0]) * 255.0);
            color.a = 255;
        },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16 => {
            color.r = tuc(HalfToFloat(s16(srcPtr)[0]) * 255.0);
            color.g = tuc(HalfToFloat(s16(srcPtr)[1]) * 255.0);
            color.b = tuc(HalfToFloat(s16(srcPtr)[2]) * 255.0);
            color.a = 255;
        },
        PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => {
            color.r = tuc(HalfToFloat(s16(srcPtr)[0]) * 255.0);
            color.g = tuc(HalfToFloat(s16(srcPtr)[1]) * 255.0);
            color.b = tuc(HalfToFloat(s16(srcPtr)[2]) * 255.0);
            color.a = tuc(HalfToFloat(s16(srcPtr)[3]) * 255.0);
        },
        else => {},
    }

    return color;
}

// Set pixel color formatted into destination pointer
export fn SetPixelColor(dstPtr: ?*anyopaque, color: Color, format: c_int) callconv(.c) void {
    switch (format) {
        PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => {
            const coln = Vector3{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0 };
            const gray: u8 = tuc((coln.x * 0.299 + coln.y * 0.587 + coln.z * 0.114) * 255.0);
            const d: [*]u8 = @ptrCast(dstPtr);
            d[0] = gray;
        },
        PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
            const coln = Vector3{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0 };
            const gray: u8 = tuc((coln.x * 0.299 + coln.y * 0.587 + coln.z * 0.114) * 255.0);
            const d: [*]u8 = @ptrCast(dstPtr);
            d[0] = gray;
            d[1] = color.a;
        },
        PIXELFORMAT_UNCOMPRESSED_R5G6B5 => {
            const coln = Vector3{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0 };
            const r: u16 = tuc(round(@floatCast(coln.x * 31.0)));
            const g: u16 = tuc(round(@floatCast(coln.y * 63.0)));
            const b: u16 = tuc(round(@floatCast(coln.z * 31.0)));
            const d: [*]u16 = @ptrCast(@alignCast(dstPtr));
            d[0] = (r << 11) | (g << 5) | b;
        },
        PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
            const coln = Vector4{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0, .w = @as(f32, @floatFromInt(color.a)) / 255.0 };
            const r: u16 = tuc(round(@floatCast(coln.x * 31.0)));
            const g: u16 = tuc(round(@floatCast(coln.y * 31.0)));
            const b: u16 = tuc(round(@floatCast(coln.z * 31.0)));
            const a: u16 = if (coln.w > (@as(f32, @floatFromInt(PIXELFORMAT_UNCOMPRESSED_R5G5B5A1_ALPHA_THRESHOLD)) / 255.0)) 1 else 0;
            const d: [*]u16 = @ptrCast(@alignCast(dstPtr));
            d[0] = (r << 11) | (g << 6) | (b << 1) | a;
        },
        PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
            const coln = Vector4{ .x = @as(f32, @floatFromInt(color.r)) / 255.0, .y = @as(f32, @floatFromInt(color.g)) / 255.0, .z = @as(f32, @floatFromInt(color.b)) / 255.0, .w = @as(f32, @floatFromInt(color.a)) / 255.0 };
            const r: u16 = tuc(round(@floatCast(coln.x * 15.0)));
            const g: u16 = tuc(round(@floatCast(coln.y * 15.0)));
            const b: u16 = tuc(round(@floatCast(coln.z * 15.0)));
            const a: u16 = tuc(round(@floatCast(coln.w * 15.0)));
            const d: [*]u16 = @ptrCast(@alignCast(dstPtr));
            d[0] = (r << 12) | (g << 8) | (b << 4) | a;
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8 => {
            const d: [*]u8 = @ptrCast(dstPtr);
            d[0] = color.r;
            d[1] = color.g;
            d[2] = color.b;
        },
        PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => {
            const d: [*]u8 = @ptrCast(dstPtr);
            d[0] = color.r;
            d[1] = color.g;
            d[2] = color.b;
            d[3] = color.a;
        },
        else => {},
    }
}

// Get pixel data size in bytes for certain format
export fn GetPixelDataSize(width: c_int, height: c_int, format: c_int) callconv(.c) c_int {
    var dataSize: c_int = 0; // Size in bytes
    var bpp: c_int = 0; // Bits per pixel

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

    const bytesPerPixel: f64 = @as(f64, @floatFromInt(bpp)) / 8.0;
    dataSize = ti(bytesPerPixel * @as(f64, @floatFromInt(width)) * @as(f64, @floatFromInt(height))); // Total data size in bytes

    if ((width < 4) and (height < 4)) {
        if ((format >= PIXELFORMAT_COMPRESSED_DXT1_RGB) and (format < PIXELFORMAT_COMPRESSED_DXT3_RGBA)) {
            dataSize = 8;
        } else if ((format >= PIXELFORMAT_COMPRESSED_DXT3_RGBA) and (format < PIXELFORMAT_COMPRESSED_ASTC_8x8_RGBA)) dataSize = 16;
    }

    return dataSize;
}
