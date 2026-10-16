//! rtext - Basic functions to load fonts and draw text
//!
//! Zig port of raylib's `rtext.c`. Every public raylib text/font function is exported
//! with its exact C name, byte-compatible signature, and C calling convention, so the
//! rest of raylib links against it unchanged. Floating-point operation order matches
//! the C source exactly to keep pixel output bit-identical.
//!
//! The exports are the C ABI edge: they turn C strings into slices and errors into
//! raylib's log lines and sentinel results. The text logic lives in
//! `rtext_strings.zig` and the BMFont reader in `rtext_bmfont.zig`, both std-only
//! and unit-tested. Memory handed to C callers (glyphs, recs, image pixels, strings
//! from the *Alloc functions) lives on the C heap through `cmem`; scratch memory
//! uses `std.heap.c_allocator`.
//!
//! This build mirrors raylib's default `config.h`: `SUPPORT_FILEFORMAT_TTF` and
//! `SUPPORT_FILEFORMAT_FNT` are enabled, `SUPPORT_FILEFORMAT_BDF` is disabled, and the
//! default embedded font (`SUPPORT_DEFAULT_FONT`) is included.
//!
//! Third-party stb_truetype / stb_rect_pack implementations live in the C shim
//! `src/c/rtext_stb_impl.c`; here they are only `extern`-declared and called. The stb
//! context structs (`stbtt_fontinfo`, `stbrp_context`, `stbrp_node`) are opaque: rtext
//! never reads their fields, so they are allocated as raw byte buffers sized by helper
//! functions the shim exports.

const std = @import("std");
const c_va = @import("c_va.zig");
const cmem = @import("cmem.zig");
const strings = @import("rtext_strings.zig");
const bmfont = @import("rtext_bmfont.zig");

/// Scratch memory that never leaves this file.
const gpa = std.heap.c_allocator;

//----------------------------------------------------------------------------------
// libc / libm, kept where only C gives C's results
//----------------------------------------------------------------------------------
// TextFormat formats with its caller's C varargs, which only libc can read.
extern fn vsnprintf(noalias [*c]u8, usize, noalias [*c]const u8, ap: c_va.Arg) c_int;
// ExportFontAsCode prints floats with "%1.0f": std.fmt rounds ties differently.
extern fn snprintf(noalias [*c]u8, usize, noalias [*c]const u8, ...) c_int;

// libm, called directly so results are bit-identical to the C source.
extern fn powf(f32, f32) f32;
extern fn logf(f32) f32;

//----------------------------------------------------------------------------------
// Cross-module raylib C symbols - extern declared and called.
//----------------------------------------------------------------------------------
extern fn LoadImage(fileName: [*c]const u8) Image;
extern fn LoadImageColors(image: Image) [*c]Color;
extern fn UnloadImage(image: Image) void;
extern fn UnloadImageColors(colors: [*c]Color) void;
extern fn GenImageColor(width: c_int, height: c_int, color: Color) Image;
extern fn ImageFromImage(image: Image, rec: Rectangle) Image;
extern fn ImageResizeCanvas(image: [*c]Image, newWidth: c_int, newHeight: c_int, offsetX: c_int, offsetY: c_int, fill: Color) void;
extern fn ImageDrawImagePro(dst: [*c]Image, src: Image, srcRec: Rectangle, dstRec: Rectangle, origin: Vector2, rotation: f32, tint: Color) void;
extern fn LoadTextureFromImage(image: Image) Texture2D;
extern fn UnloadTexture(texture: Texture2D) void;
extern fn LoadImageFromTexture(texture: Texture2D) Image;
extern fn SetTextureFilter(texture: Texture2D, filter: c_int) void;
extern fn DrawTexturePro(texture: Texture2D, source: Rectangle, dest: Rectangle, origin: Vector2, rotation: f32, tint: Color) void;
extern fn GetPixelDataSize(width: c_int, height: c_int, format: c_int) c_int;
extern fn LoadFileData(fileName: [*c]const u8, dataSize: [*c]c_int) [*c]u8;
extern fn LoadFileText(fileName: [*c]const u8) [*c]u8;
extern fn UnloadFileData(data: [*c]u8) void;
extern fn UnloadFileText(text: [*c]u8) void;
extern fn SaveFileText(fileName: [*c]const u8, text: [*c]u8) bool;
extern fn TraceLog(logLevel: c_int, text: [*c]const u8, ...) void;
extern fn CompressData(data: [*c]const u8, dataSize: c_int, compDataSize: [*c]c_int) [*c]u8;
extern fn GetFileExtension(fileName: [*c]const u8) [*c]const u8;
extern fn GetFileNameWithoutExt(filePath: [*c]const u8) [*c]const u8;
extern fn GetDirectoryPath(filePath: [*c]const u8) [*c]const u8;
extern fn IsFileExtension(fileName: [*c]const u8, ext: [*c]const u8) bool;
extern fn GetFPS() c_int;

// rlgl functions, provided by other translation units in the build (only DrawTextPro uses them).
extern fn rlPushMatrix() void;
extern fn rlPopMatrix() void;
extern fn rlTranslatef(x: f32, y: f32, z: f32) void;
extern fn rlRotatef(angle: f32, x: f32, y: f32, z: f32) void;

//----------------------------------------------------------------------------------
// Third-party stb functions (provided by src/c/rtext_stb_impl.c).
//----------------------------------------------------------------------------------
extern fn rl_sizeof_stbtt_fontinfo() usize;
extern fn rl_sizeof_stbrp_context() usize;
extern fn rl_sizeof_stbrp_node() usize;

extern fn stbtt_InitFont(info: ?*anyopaque, data: [*c]const u8, offset: c_int) c_int;
extern fn stbtt_FindGlyphIndex(info: ?*const anyopaque, unicode_codepoint: c_int) c_int;
extern fn stbtt_ScaleForPixelHeight(info: ?*const anyopaque, pixels: f32) f32;
extern fn stbtt_GetFontVMetrics(info: ?*const anyopaque, ascent: [*c]c_int, descent: [*c]c_int, lineGap: [*c]c_int) void;
extern fn stbtt_GetCodepointHMetrics(info: ?*const anyopaque, codepoint: c_int, advanceWidth: [*c]c_int, leftSideBearing: [*c]c_int) void;
extern fn stbtt_GetCodepointSDF(info: ?*const anyopaque, scale: f32, codepoint: c_int, padding: c_int, onedge_value: u8, pixel_dist_scale: f32, width: [*c]c_int, height: [*c]c_int, xoff: [*c]c_int, yoff: [*c]c_int) [*c]u8;
extern fn stbtt_GetCodepointBitmap(info: ?*const anyopaque, scale_x: f32, scale_y: f32, codepoint: c_int, width: [*c]c_int, height: [*c]c_int, xoff: [*c]c_int, yoff: [*c]c_int) [*c]u8;

extern fn stbrp_init_target(context: ?*anyopaque, width: c_int, height: c_int, nodes: ?*anyopaque, num_nodes: c_int) void;
extern fn stbrp_pack_rects(context: ?*anyopaque, rects: [*c]stbrp_rect, num_rects: c_int) c_int;

// stbrp_rect mirrors stb_rect_pack's struct (6 ints); rtext reads x/y/was_packed fields.
const stbrp_rect = extern struct {
    id: c_int,
    w: c_int,
    h: c_int,
    x: c_int = 0,
    y: c_int = 0,
    was_packed: c_int = 0,
};

/// Alignment of the opaque stb context buffers, as `malloc` gives.
const opaque_alignment: std.mem.Alignment = .@"16";

/// A zeroed buffer for an opaque stb struct of `size` bytes.
fn allocOpaque(size: usize) error{OutOfMemory}![]align(opaque_alignment.toByteUnits()) u8 {
    const buffer = try gpa.alignedAlloc(u8, opaque_alignment, size);
    @memset(buffer, 0);
    return buffer;
}

//----------------------------------------------------------------------------------
// Defines and Macros
//----------------------------------------------------------------------------------
const MAX_TEXT_BUFFER_LENGTH = 1024;
const MAX_TEXTSPLIT_COUNT = 128;
const FONT_ATLAS_CORNER_REC_SIZE = 3;

const FONT_TTF_DEFAULT_SIZE: c_int = 32;
const FONT_TTF_DEFAULT_NUMCHARS: c_int = 95;
const FONT_TTF_DEFAULT_FIRST_CHAR: c_int = 32;
const FONT_TTF_DEFAULT_CHARS_PADDING: c_int = 4;

const FONT_BITMAP_ALPHA_THRESHOLD = 80;

const MAX_GLYPHS_FROM_IMAGE = 256;
const MAX_TEXTFORMAT_BUFFERS = 4;
const TEXT_BYTES_PER_LINE = 20;

const MAX_FONT_IMAGE_PAGES = 8;

// PixelFormat values (raylib.h)
const PIXELFORMAT_UNCOMPRESSED_GRAYSCALE: c_int = 1;
const PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA: c_int = 2;
const PIXELFORMAT_UNCOMPRESSED_R8G8B8A8: c_int = 7;

// TraceLogLevel values (raylib.h)
const LOG_INFO: c_int = 3;
const LOG_WARNING: c_int = 4;
const LOG_DEBUG: c_int = 2;

// FontType values (raylib.h)
const FONT_DEFAULT: c_int = 0;
const FONT_BITMAP: c_int = 1;
const FONT_SDF: c_int = 2;

// SDF font generation parameters (rtext.c defaults)
const FONT_SDF_CHAR_PADDING: c_int = 4;
const FONT_SDF_ON_EDGE_VALUE: u8 = 128;
const FONT_SDF_PIXEL_DIST_SCALE: f32 = 64.0;

// TextureFilter values (raylib.h)
const TEXTURE_FILTER_POINT: c_int = 0;

// Predefined colors (raylib.h)
const LIME = Color{ .r = 0, .g = 158, .b = 47, .a = 255 };
const ORANGE = Color{ .r = 255, .g = 161, .b = 0, .a = 255 };
const RED = Color{ .r = 230, .g = 41, .b = 55, .a = 255 };
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

    fn eql(a: Color, b: Color) bool {
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
    }
};

pub const Vector2 = extern struct {
    x: f32,
    y: f32,
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

const empty_font = std.mem.zeroes(Font);

//----------------------------------------------------------------------------------
// C ABI helpers
//----------------------------------------------------------------------------------
fn cSpan(text: [*c]const u8) ?[:0]const u8 {
    return if (text == null) null else std.mem.span(text);
}

/// A C string where raylib treats null as empty.
fn cText(text: [*c]const u8) [:0]const u8 {
    return cSpan(text) orelse "";
}

/// `len` items a C caller passed by pointer; empty for null or len <= 0.
fn cItems(comptime T: type, ptr: [*c]const T, len: c_int) []const T {
    if (ptr == null or len <= 0) return &.{};
    return ptr[0..@intCast(len)];
}

/// `len` mutable items a C caller passed by pointer; empty for null or len <= 0.
fn cItemsMut(comptime T: type, ptr: [*c]T, len: c_int) []T {
    if (ptr == null or len <= 0) return &.{};
    return ptr[0..@intCast(len)];
}

/// The glyphs of `font`, and their rectangles in its atlas.
fn glyphsOf(font: Font) []GlyphInfo {
    return cItemsMut(GlyphInfo, font.glyphs, font.glyphCount);
}

fn recsOf(font: Font) []Rectangle {
    return cItemsMut(Rectangle, font.recs, font.glyphCount);
}

/// Up to the next four bytes of a C string: all a UTF-8 decoder may read.
fn utf8Window(text: [*]const u8) []const u8 {
    var len: usize = 0;
    while (len < 4 and text[len] != 0) len += 1;
    return text[0..len];
}

fn float(value: c_int) f32 {
    return @floatFromInt(value);
}

fn cInt(value: anytype) c_int {
    return @intCast(value);
}

/// C's `(int)` of a float on raylib's targets: NaN and out-of-range values
/// give INT_MIN instead of trapping.
fn truncToInt(value: f32) c_int {
    if (std.math.isNan(value) or value >= 2147483648.0 or value < -2147483648.0) return std.math.minInt(c_int);
    return @intFromFloat(value);
}

//----------------------------------------------------------------------------------
// Global variables
//----------------------------------------------------------------------------------
// Default font provided by raylib
// NOTE: Default font is loaded on InitWindow() and disposed on CloseWindow() [module: core]
var defaultFont: Font = empty_font;

// Text vertical line spacing in pixels (between lines)
var textLineSpacing: c_int = 2;

//----------------------------------------------------------------------------------
// Default font
//----------------------------------------------------------------------------------
// Default font is directly defined here (data generated from a sprite font image):
// one bit per pixel of a 128x128 atlas, least significant bit first.
// NOTE: Using UTF-8 encoding table for Unicode U+0000..U+00FF Basic Latin + Latin-1 Supplement
const default_font_bits = [512]u32{
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00200020, 0x0001b000, 0x00000000, 0x00000000, 0x8ef92520, 0x00020a00, 0x7dbe8000, 0x1f7df45f,
    0x4a2bf2a0, 0x0852091e, 0x41224000, 0x10041450, 0x2e292020, 0x08220812, 0x41222000, 0x10041450, 0x10f92020, 0x3efa084c, 0x7d22103c, 0x107df7de,
    0xe8a12020, 0x08220832, 0x05220800, 0x10450410, 0xa4a3f000, 0x08520832, 0x05220400, 0x10450410, 0xe2f92020, 0x0002085e, 0x7d3e0281, 0x107df41f,
    0x00200000, 0x8001b000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0xc0000fbe, 0xfbf7e00f, 0x5fbf7e7d, 0x0050bee8, 0x440808a2, 0x0a142fe8, 0x50810285, 0x0050a048,
    0x49e428a2, 0x0a142828, 0x40810284, 0x0048a048, 0x10020fbe, 0x09f7ebaf, 0xd89f3e84, 0x0047a04f, 0x09e48822, 0x0a142aa1, 0x50810284, 0x0048a048,
    0x04082822, 0x0a142fa0, 0x50810285, 0x0050a248, 0x00008fbe, 0xfbf42021, 0x5f817e7d, 0x07d09ce8, 0x00008000, 0x00000fe0, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x000c0180,
    0xdfbf4282, 0x0bfbf7ef, 0x42850505, 0x004804bf, 0x50a142c6, 0x08401428, 0x42852505, 0x00a808a0, 0x50a146aa, 0x08401428, 0x42852505, 0x00081090,
    0x5fa14a92, 0x0843f7e8, 0x7e792505, 0x00082088, 0x40a15282, 0x08420128, 0x40852489, 0x00084084, 0x40a16282, 0x0842022a, 0x40852451, 0x00088082,
    0xc0bf4282, 0xf843f42f, 0x7e85fc21, 0x3e0900bf, 0x00000000, 0x00000004, 0x00000000, 0x000c0180, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x04000402, 0x41482000, 0x00000000, 0x00000800,
    0x04000404, 0x4100203c, 0x00000000, 0x00000800, 0xf7df7df0, 0x514bef85, 0xbefbefbe, 0x04513bef, 0x14414500, 0x494a2885, 0xa28a28aa, 0x04510820,
    0xf44145f0, 0x474a289d, 0xa28a28aa, 0x04510be0, 0x14414510, 0x494a2884, 0xa28a28aa, 0x02910a00, 0xf7df7df0, 0xd14a2f85, 0xbefbe8aa, 0x011f7be0,
    0x00000000, 0x00400804, 0x20080000, 0x00000000, 0x00000000, 0x00600f84, 0x20080000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0xac000000, 0x00000f01, 0x00000000, 0x00000000, 0x24000000, 0x00000f01, 0x00000000, 0x06000000, 0x24000000, 0x00000f01, 0x00000000, 0x09108000,
    0x24fa28a2, 0x00000f01, 0x00000000, 0x013e0000, 0x2242252a, 0x00000f52, 0x00000000, 0x038a8000, 0x2422222a, 0x00000f29, 0x00000000, 0x010a8000,
    0x2412252a, 0x00000f01, 0x00000000, 0x010a8000, 0x24fbe8be, 0x00000f01, 0x00000000, 0x0ebe8000, 0xac020000, 0x00000f01, 0x00000000, 0x00048000,
    0x0003e000, 0x00000f00, 0x00000000, 0x00008000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000038, 0x8443b80e, 0x00203a03,
    0x02bea080, 0xf0000020, 0xc452208a, 0x04202b02, 0xf8029122, 0x07f0003b, 0xe44b388e, 0x02203a02, 0x081e8a1c, 0x0411e92a, 0xf4420be0, 0x01248202,
    0xe8140414, 0x05d104ba, 0xe7c3b880, 0x00893a0a, 0x283c0e1c, 0x04500902, 0xc4400080, 0x00448002, 0xe8208422, 0x04500002, 0x80400000, 0x05200002,
    0x083e8e00, 0x04100002, 0x804003e0, 0x07000042, 0xf8008400, 0x07f00003, 0x80400000, 0x04000022, 0x00000000, 0x00000000, 0x80400000, 0x04000002,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00800702, 0x1848a0c2, 0x84010000, 0x02920921, 0x01042642, 0x00005121, 0x42023f7f, 0x00291002,
    0xefc01422, 0x7efdfbf7, 0xefdfa109, 0x03bbbbf7, 0x28440f12, 0x42850a14, 0x20408109, 0x01111010, 0x28440408, 0x42850a14, 0x2040817f, 0x01111010,
    0xefc78204, 0x7efdfbf7, 0xe7cf8109, 0x011111f3, 0x2850a932, 0x42850a14, 0x2040a109, 0x01111010, 0x2850b840, 0x42850a14, 0xefdfbf79, 0x03bbbbf7,
    0x001fa020, 0x00000000, 0x00001000, 0x00000000, 0x00002070, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x08022800, 0x00012283, 0x02430802, 0x01010001, 0x8404147c, 0x20000144, 0x80048404, 0x00823f08, 0xdfbf4284, 0x7e03f7ef, 0x142850a1, 0x0000210a,
    0x50a14684, 0x528a1428, 0x142850a1, 0x03efa17a, 0x50a14a9e, 0x52521428, 0x142850a1, 0x02081f4a, 0x50a15284, 0x4a221428, 0xf42850a1, 0x03efa14b,
    0x50a16284, 0x4a521428, 0x042850a1, 0x0228a17a, 0xdfbf427c, 0x7e8bf7ef, 0xf7efdfbf, 0x03efbd0b, 0x00000000, 0x04000000, 0x00000000, 0x00000008,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00200508, 0x00840400, 0x11458122, 0x00014210,
    0x00514294, 0x51420800, 0x20a22a94, 0x0050a508, 0x00200000, 0x00000000, 0x00050000, 0x08000000, 0xfefbefbe, 0xfbefbefb, 0xfbeb9114, 0x00fbefbe,
    0x20820820, 0x8a28a20a, 0x8a289114, 0x3e8a28a2, 0xfefbefbe, 0xfbefbe0b, 0x8a289114, 0x008a28a2, 0x228a28a2, 0x08208208, 0x8a289114, 0x088a28a2,
    0xfefbefbe, 0xfbefbefb, 0xfa2f9114, 0x00fbefbe, 0x00000000, 0x00000040, 0x00000000, 0x00000000, 0x00000000, 0x00000020, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00210100, 0x00000004, 0x00000000, 0x00000000, 0x14508200, 0x00001402, 0x00000000, 0x00000000,
    0x00000010, 0x00000020, 0x00000000, 0x00000000, 0xa28a28be, 0x00002228, 0x00000000, 0x00000000, 0xa28a28aa, 0x000022e8, 0x00000000, 0x00000000,
    0xa28a28aa, 0x000022a8, 0x00000000, 0x00000000, 0xa28a28aa, 0x000022e8, 0x00000000, 0x00000000, 0xbefbefbe, 0x00003e2f, 0x00000000, 0x00000000,
    0x00000004, 0x00002028, 0x00000000, 0x00000000, 0x80000000, 0x00003e0f, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
};

const default_font_widths = [224]c_int{
    3, 1, 4, 6, 5, 7, 6, 2, 3, 3, 5, 5, 2, 4, 1, 7, 5, 2, 5, 5, 5, 5, 5, 5, 5, 5, 1, 1, 3, 4, 3, 6,
    7, 6, 6, 6, 6, 6, 6, 6, 6, 3, 5, 6, 5, 7, 6, 6, 6, 6, 6, 6, 7, 6, 7, 7, 6, 6, 6, 2, 7, 2, 3, 5,
    2, 5, 5, 5, 5, 5, 4, 5, 5, 1, 2, 5, 2, 5, 5, 5, 5, 5, 5, 5, 4, 5, 5, 5, 5, 5, 5, 3, 1, 3, 4, 4,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 5, 5, 5, 7, 1, 5, 3, 7, 3, 5, 4, 1, 7, 4, 3, 5, 3, 3, 2, 5, 6, 1, 2, 2, 3, 5, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 7, 6, 6, 6, 6, 6, 3, 3, 3, 3, 7, 6, 6, 6, 6, 6, 6, 5, 6, 6, 6, 6, 6, 6, 4, 6,
    5, 5, 5, 5, 5, 5, 9, 5, 5, 5, 5, 5, 2, 2, 3, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5,
};

const default_font_glyph_height: c_int = 10;
// Every char is separated from the consecutive by a 1 pixel divisor, horizontally and vertically
const default_font_divisor: c_int = 1;

// Load raylib default font
export fn LoadFontDefault() callconv(.c) void {
    // Check to see if the font for an image has already been allocated,
    // and if no need to upload, then return
    if (defaultFont.glyphs != null) return;

    defaultFont.glyphCount = default_font_widths.len;
    defaultFont.glyphPadding = 0;

    loadFontDefault() catch return;

    TraceLog(LOG_INFO, "FONT: Default font loaded successfully (%i glyphs)", defaultFont.glyphCount);
}

fn loadFontDefault() error{OutOfMemory}!void {
    // Re-construct image from default_font_bits and generate OpenGL texture
    const size = 128;
    const pixels = try cmem.alloc([2]u8, size * size); // gray + alpha
    const imFont: Image = .{
        .data = pixels.ptr,
        .width = size,
        .height = size,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA,
    };
    defer UnloadImage(imFont);

    for (pixels, 0..) |*pixel, i| {
        const set = (default_font_bits[i / 32] >> @intCast(i % 32)) & 1 != 0;
        pixel.* = if (set) .{ 0xff, 0xff } else .{ 0xff, 0x00 };
    }

    defaultFont.texture = LoadTextureFromImage(imFont);

    // Reconstruct charSet using default_font_widths, the glyph height and divisor
    const glyphs = try cmem.alloc(GlyphInfo, default_font_widths.len);
    errdefer cmem.free(glyphs.ptr);
    const recs = try cmem.alloc(Rectangle, default_font_widths.len);

    const divisor = default_font_divisor;
    const height = default_font_glyph_height;
    var currentLine: c_int = 0;
    var currentPosX: c_int = divisor;
    var testPosX: c_int = divisor;

    for (glyphs, recs, default_font_widths, 0..) |*glyph, *rec, width, i| {
        rec.* = .{
            .x = float(currentPosX),
            .y = float(divisor + currentLine * (height + divisor)),
            .width = float(width),
            .height = float(height),
        };

        testPosX += @intFromFloat(rec.width + float(divisor));

        if (testPosX >= imFont.width) {
            currentLine += 1;
            currentPosX = 2 * divisor + width;
            testPosX = currentPosX;

            rec.x = float(divisor);
            rec.y = float(divisor + currentLine * (height + divisor));
        } else currentPosX = testPosX;

        // NOTE: On default font character offsets and xAdvance are not required
        glyph.* = .{
            .value = 32 + cInt(i), // First char is 32
            .offsetX = 0,
            .offsetY = 0,
            .advanceX = 0,
            // Fill character image data from the font image
            .image = ImageFromImage(imFont, rec.*),
        };
    }

    defaultFont.glyphs = glyphs.ptr;
    defaultFont.recs = recs.ptr;
    defaultFont.baseSize = @intFromFloat(recs[0].height);
}

// Unload raylib default font
export fn UnloadFontDefault() callconv(.c) void {
    for (glyphsOf(defaultFont)) |glyph| UnloadImage(glyph.image);
    UnloadTexture(defaultFont.texture);
    cmem.free(defaultFont.glyphs);
    cmem.free(defaultFont.recs);
    defaultFont.glyphCount = 0;
    defaultFont.glyphs = null;
    defaultFont.recs = null;
}

// Get the default font
export fn GetFontDefault() callconv(.c) Font {
    return defaultFont;
}

//----------------------------------------------------------------------------------
// Font loading
//----------------------------------------------------------------------------------
// Load Font from file into GPU memory (VRAM)
export fn LoadFont(fileName: [*c]const u8) callconv(.c) Font {
    const font = if (IsFileExtension(fileName, ".ttf") or IsFileExtension(fileName, ".otf"))
        LoadFontEx(fileName, FONT_TTF_DEFAULT_SIZE, null, FONT_TTF_DEFAULT_NUMCHARS)
    else if (IsFileExtension(fileName, ".fnt"))
        loadBMFont(fileName)
    else image: {
        const image = LoadImage(fileName);
        defer UnloadImage(image);
        break :image if (image.data != null) LoadFontFromImage(image, MAGENTA, FONT_TTF_DEFAULT_FIRST_CHAR) else GetFontDefault();
    };

    if (font.texture.id == 0) {
        TraceLog(LOG_WARNING, "FONT: [%s] Failed to load font texture -> Using default font", fileName);
    } else {
        SetTextureFilter(font.texture, TEXTURE_FILTER_POINT); // By default, set point filter (the best performance)
        TraceLog(LOG_INFO, "FONT: Data loaded successfully (%i pixel size | %i glyphs)", font.baseSize, font.glyphCount);
    }

    return font;
}

// Load font from file with defined codepoints and generation size
export fn LoadFontEx(fileName: [*c]const u8, fontSize: c_int, codepoints: [*c]const c_int, codepointCount: c_int) callconv(.c) Font {
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);
    if (fileData == null) return empty_font;
    defer UnloadFileData(fileData);

    return LoadFontFromMemory(GetFileExtension(fileName), fileData, dataSize, fontSize, codepoints, codepointCount);
}

/// An image's pixels, compared against a key color by coordinates.
const KeyedPixels = struct {
    pixels: [*]Color,
    width: c_int,
    key: Color,

    /// Like raylib, (x, y) may be one pixel past the end of a row: that reads
    /// the first pixel of the next row.
    fn isKey(keyed: KeyedPixels, x: c_int, y: c_int) bool {
        return keyed.pixels[@intCast(y * keyed.width + x)].eql(keyed.key);
    }
};

// Load an Image font file (XNA style)
export fn LoadFontFromImage(image: Image, key: Color, firstChar: c_int) callconv(.c) Font {
    const font = GetFontDefault();
    return loadFontFromImage(image, key, firstChar) catch |err| switch (err) {
        error.NoGlyphs, error.OutOfMemory => font,
    };
}

fn loadFontFromImage(image: Image, key: Color, firstChar: c_int) error{ NoGlyphs, OutOfMemory }!Font {
    const pixels = LoadImageColors(image);
    const keyed: KeyedPixels = .{ .pixels = pixels, .width = image.width, .key = key };

    // Parse image data to get charSpacing and lineSpacing: the key-colored
    // margin before the first glyph
    var x: c_int = 0;
    var y: c_int = 0;
    while (y < image.height) : (y += 1) {
        x = 0;
        while (x < image.width and keyed.isKey(x, y)) x += 1;
        if (!keyed.isKey(x, y)) break;
    }

    // Security check
    if (x == 0 or y == 0) {
        UnloadImageColors(pixels);
        return error.NoGlyphs;
    }

    const charSpacing = x;
    const lineSpacing = y;

    var charHeight: c_int = 0;
    while (lineSpacing + charHeight < image.height and !keyed.isKey(charSpacing, lineSpacing + charHeight)) charHeight += 1;

    // Check array values to get characters: value, x, y, w, h
    var values: [MAX_GLYPHS_FROM_IMAGE]c_int = undefined;
    var rects: [MAX_GLYPHS_FROM_IMAGE]Rectangle = undefined;
    var count: usize = 0;

    // Parse image data to get rectangle sizes
    var line: c_int = 0;
    while (lineSpacing + line * (charHeight + lineSpacing) < image.height) : (line += 1) {
        const lineY = lineSpacing + (charHeight + lineSpacing) * line;
        var xPos = charSpacing;
        while (xPos < image.width and !keyed.isKey(xPos, lineY)) {
            var charWidth: c_int = 0;
            while (xPos + charWidth < image.width and !keyed.isKey(xPos + charWidth, lineY)) charWidth += 1;

            values[count] = firstChar + cInt(count);
            rects[count] = .{ .x = float(xPos), .y = float(lineY), .width = float(charWidth), .height = float(charHeight) };
            count += 1;

            xPos += charWidth + charSpacing;
        }
    }

    // NOTE: Key color borders need to be removed from image to avoid weird artifacts
    for (pixels[0..@intCast(image.width * image.height)]) |*pixel| {
        if (pixel.eql(key)) pixel.* = BLANK;
    }

    // Create a new image with the processed color data (key color replaced by BLANK)
    const fontClear: Image = .{
        .data = pixels,
        .width = image.width,
        .height = image.height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
    defer UnloadImage(fontClear); // Unload processed image once converted to texture

    const texture = LoadTextureFromImage(fontClear); // Convert processed image to OpenGL texture
    errdefer UnloadTexture(texture);

    // Move temp data to sized glyphs and recs arrays
    const glyphs = try cmem.alloc(GlyphInfo, count);
    errdefer cmem.free(glyphs.ptr);
    const recs = try cmem.alloc(Rectangle, count);
    @memcpy(recs, rects[0..count]);

    for (glyphs, values[0..count], recs) |*glyph, value, rec| {
        // NOTE: On image based fonts (XNA style), character offsets and xAdvance are not required (set to 0)
        glyph.* = .{
            .value = value,
            .offsetX = 0,
            .offsetY = 0,
            .advanceX = 0,
            // Fill character image data from fontClear data
            .image = ImageFromImage(fontClear, rec),
        };
    }

    return .{
        .texture = texture,
        .glyphCount = cInt(count),
        .glyphPadding = 0,
        .glyphs = glyphs.ptr,
        .recs = recs.ptr,
        // Read through the pointer: with no glyphs this is C's unchecked recs[0]
        .baseSize = @intFromFloat(recs.ptr[0].height),
    };
}

// Load font from memory buffer, fileType refers to extension: i.e. ".ttf"
export fn LoadFontFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: c_int, fontSize: c_int, codepoints: [*c]const c_int, codepointCount: c_int) callconv(.c) Font {
    var font = empty_font;
    font.baseSize = fontSize;

    // raylib lower-cases through TextToLower (and its static buffer)
    const extension = std.mem.span(TextToLower(fileType));
    if (std.mem.eql(u8, extension, ".ttf") or std.mem.eql(u8, extension, ".otf")) {
        font.glyphs = LoadFontData(fileData, dataSize, font.baseSize, codepoints, if (codepointCount > 0) codepointCount else 95, FONT_DEFAULT, &font.glyphCount);
    }

    if (font.glyphs == null) {
        TraceLog(LOG_WARNING, "FONT: Font is not supported by LoadFontEx/LoadFontFromMemory or no glyphs found, reverted to default font");
        return GetFontDefault();
    }

    font.glyphPadding = FONT_TTF_DEFAULT_CHARS_PADDING;

    const atlas = GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, font.baseSize, font.glyphPadding, 0);
    defer UnloadImage(atlas);
    font.texture = LoadTextureFromImage(atlas);

    // Update glyphs[i].image to use alpha, required to be used on ImageDrawText()
    for (glyphsOf(font), recsOf(font)) |*glyph, rec| {
        UnloadImage(glyph.image);
        glyph.image = ImageFromImage(atlas, rec);
    }

    TraceLog(LOG_INFO, "FONT: Data loaded successfully (%i pixel size | %i glyphs)", font.baseSize, font.glyphCount);
    return font;
}

// Check if font is valid (font data loaded)
export fn IsFontValid(font: Font) callconv(.c) bool {
    return font.baseSize > 0 and // Validate font size
        font.glyphCount > 0 and // Validate font contains some glyph
        font.recs != null and // Validate font recs defining glyphs on texture atlas
        font.glyphs != null; // Validate glyph data is loaded
}

/// Unicode space characters that get an empty (advance-sized) glyph image.
fn isUnicodeSpace(cp: c_int) bool {
    return switch (cp) {
        0x20, // ASCII space
        0xA0, // No-break space
        0x1680, // Ogham Space Mark
        0x2000...0x200A, // En Quad .. Hair Space
        0x202F, // Narrow No-break Space
        0x205F, // Medium Mathematical Space
        0x3000, // Ideographic Space
        => true,
        else => false,
    };
}

// Load font data for further use
// NOTE: Requires TTF font memory data and can generate SDF data
export fn LoadFontData(fileData: [*c]const u8, dataSize: c_int, fontSize: c_int, codepoints: [*c]const c_int, codepointCount: c_int, type_: c_int, glyphCount: [*c]c_int) callconv(.c) [*c]GlyphInfo {
    _ = dataSize;
    glyphCount.* = 0;
    if (fileData == null) return null;

    const glyphs = loadFontData(fileData, fontSize, codepoints, codepointCount, type_) catch |err| switch (err) {
        error.InvalidFont => {
            TraceLog(LOG_WARNING, "FONT: Failed to process TTF font data");
            return null;
        },
        error.OutOfMemory => return null,
    };
    glyphCount.* = cInt(glyphs.len);
    return glyphs.ptr;
}

fn loadFontData(fileData: [*]const u8, fontSize: c_int, codepoints: ?[*]const c_int, codepointCount: c_int, fontType: c_int) error{ InvalidFont, OutOfMemory }![]GlyphInfo {
    // NOTE: stbtt_fontinfo is opaque here: a zeroed buffer (a local `= {0}` in C)
    const fontInfo = try allocOpaque(rl_sizeof_stbtt_fontinfo());
    defer gpa.free(fontInfo);
    const info = fontInfo.ptr;

    // Initialize font for data reading
    if (stbtt_InitFont(info, fileData, 0) == 0) return error.InvalidFont;

    // Calculate font scale factor
    const scaleFactor = stbtt_ScaleForPixelHeight(info, float(fontSize));

    // Calculate font basic metrics
    // NOTE: ascent is equivalent to font baseline
    var ascent: c_int = 0;
    var descent: c_int = 0;
    var lineGap: c_int = 0;
    stbtt_GetFontVMetrics(info, &ascent, &descent, &lineGap);

    // In case no chars count provided, default to 95
    const count: usize = if (codepointCount > 0) @intCast(codepointCount) else 95;

    // Fill fontChars in case not provided externally
    const generated: []c_int = if (codepoints == null) try gpa.alloc(c_int, count) else &.{};
    defer gpa.free(generated);
    for (generated, 32..) |*cp, value| cp.* = cInt(value);
    const required: []const c_int = if (codepoints) |provided| provided[0..count] else generated;

    // Check available glyphs on provided font before loading them
    var available: usize = 0;
    for (required) |cp| {
        if (stbtt_FindGlyphIndex(info, cp) > 0) available += 1;
    }

    // WARNING: Allocating space for maximum number of codepoints
    const glyphs = try cmem.alloc(GlyphInfo, available);
    var loaded: usize = 0;
    errdefer UnloadFontData(glyphs.ptr, cInt(loaded));

    for (required) |cp| {
        // Only storing glyphs for codepoints found in the font; a missing
        // glyph could optionally use a fallback glyph
        if (stbtt_FindGlyphIndex(info, cp) <= 0) continue;

        const glyph = &glyphs[loaded];
        glyph.value = cp;

        // Codepoint width and height (on generation)
        var cpWidth: c_int = 0;
        var cpHeight: c_int = 0;
        switch (fontType) {
            FONT_DEFAULT, FONT_BITMAP => {
                glyph.image.data = stbtt_GetCodepointBitmap(info, scaleFactor, scaleFactor, cp, &cpWidth, &cpHeight, &glyph.offsetX, &glyph.offsetY);
            },
            FONT_SDF => if (cp != 32) {
                glyph.image.data = stbtt_GetCodepointSDF(info, scaleFactor, cp, FONT_SDF_CHAR_PADDING, FONT_SDF_ON_EDGE_VALUE, FONT_SDF_PIXEL_DIST_SCALE, &cpWidth, &cpHeight, &glyph.offsetX, &glyph.offsetY);
            },
            else => {},
        }

        if (glyph.image.data != null) { // Glyph data has been found in the font
            stbtt_GetCodepointHMetrics(info, cp, &glyph.advanceX, null);
            glyph.advanceX = @intFromFloat(float(glyph.advanceX) * scaleFactor);

            if (fontType != FONT_SDF and cpHeight > fontSize) TraceLog(LOG_WARNING, "FONT: [0x%04x] Glyph height is bigger than requested font size: %i > %i", cp, cpHeight, fontSize);

            // Load glyph image
            glyph.image.width = cpWidth;
            glyph.image.height = cpHeight;
            glyph.image.mipmaps = 1;
            glyph.image.format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE;

            glyph.offsetY += @intFromFloat(float(ascent) * scaleFactor);
        }

        // Create an empty image for Unicode space characters, useful for sprite font generation
        if (isUnicodeSpace(cp)) {
            stbtt_GetCodepointHMetrics(info, cp, &glyph.advanceX, null);
            glyph.advanceX = @intFromFloat(float(glyph.advanceX) * scaleFactor);

            var imSpace: Image = .{
                .data = null,
                .width = glyph.advanceX,
                .height = fontSize,
                .mipmaps = 1,
                .format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
            };

            // Only allocate space image if required
            if (glyph.advanceX > 0) {
                imSpace.data = (try cmem.alloc(u8, @intCast(glyph.advanceX * fontSize))).ptr;
            } else glyph.advanceX = 0;

            glyph.image = imSpace;
        }

        if (fontType == FONT_BITMAP and cpWidth * cpHeight > 0) {
            // Aliased bitmap (black & white) font generation, avoiding anti-aliasing
            // NOTE: The size is the bitmap's even if a space image replaced it, as in C
            const pixels: [*]u8 = @ptrCast(glyph.image.data.?);
            for (pixels[0..@intCast(cpWidth * cpHeight)]) |*pixel| {
                pixel.* = if (pixel.* < FONT_BITMAP_ALPHA_THRESHOLD) 0 else 255;
            }
        }

        loaded += 1;
    }

    if (loaded < count) TraceLog(LOG_WARNING, "FONT: Requested codepoints glyphs found: [%i/%i]", cInt(loaded), cInt(count));

    return glyphs;
}

/// A GRAYSCALE font atlas and the glyph rectangles in it.
const Atlas = struct {
    pixels: []u8,
    width: c_int,
    height: c_int,

    fn init(width: c_int, height: c_int) error{OutOfMemory}!Atlas {
        return .{ .pixels = try cmem.alloc(u8, @intCast(width * height)), .width = width, .height = height };
    }

    /// Copies a GRAYSCALE glyph image to (x, y), clipped to the atlas.
    fn blit(atlas: Atlas, image: Image, x: c_int, y: c_int) void {
        // Missing glyphs have no data and a zero size
        if (image.width <= 0 or image.height <= 0) return;
        const glyph: [*]const u8 = @ptrCast(image.data.?);

        var yy: c_int = 0;
        while (yy < image.height) : (yy += 1) {
            var xx: c_int = 0;
            while (xx < image.width) : (xx += 1) {
                const destX = x + xx;
                const destY = y + yy;

                // Security: check both lower and upper bounds
                if (destX >= 0 and destX < atlas.width and destY >= 0 and destY < atlas.height) {
                    atlas.pixels[@intCast(destY * atlas.width + destX)] = glyph[@intCast(yy * image.width + xx)];
                }
            }
        }
    }

    /// Doubles the height, keeping the pixels.
    fn grow(atlas: *Atlas) error{OutOfMemory}!void {
        const grown = try cmem.alloc(u8, atlas.pixels.len * 2);
        @memcpy(grown[0..atlas.pixels.len], atlas.pixels);
        cmem.free(atlas.pixels.ptr);
        atlas.pixels = grown;
        atlas.height *= 2;
    }
};

// Generate image font atlas using chars info
// NOTE: Packing method: 0-Default, 1-Skyline
export fn GenImageFontAtlas(glyphs: [*c]const GlyphInfo, glyphRecs: [*c][*c]Rectangle, glyphCount: c_int, fontSize: c_int, padding: c_int, packMethod: c_int) callconv(.c) Image {
    if (glyphs == null) {
        TraceLog(LOG_WARNING, "FONT: Provided glyphs info not valid, returning empty image atlas");
        return std.mem.zeroes(Image);
    }

    glyphRecs.* = null;

    // In case no chars count provided, suppose default of 95
    const count: usize = if (glyphCount > 0) @intCast(glyphCount) else 95;

    // NOTE: Rectangles memory is loaded here!
    const recs = cmem.alloc(Rectangle, count) catch return std.mem.zeroes(Image);
    const atlas = genImageFontAtlas(glyphs[0..count], recs, fontSize, padding, packMethod) catch {
        cmem.free(recs.ptr);
        return std.mem.zeroes(Image);
    };

    glyphRecs.* = recs.ptr;
    return atlas;
}

fn genImageFontAtlas(glyphs: []const GlyphInfo, recs: []Rectangle, fontSize: c_int, padding: c_int, packMethod: c_int) error{OutOfMemory}!Image {
    // Calculate image size based on total glyph width and glyph row count
    var totalWidth: c_int = 0;
    for (glyphs) |glyph| totalWidth += glyph.image.width + 2 * padding;

    const paddedFontSize = fontSize + 2 * padding;

    // Estimate image atlas size from available data
    const totalArea: f32 = float(totalWidth * paddedFontSize) * 1.2;
    const imageMinSize = @sqrt(totalArea);
    const imageSize = truncToInt(powf(2, @ceil(logf(imageMinSize) / logf(2))));

    // Create a bitmap to store characters (8 bpp)
    var atlas: Atlas = try .init(imageSize, if (totalArea < float(@divTrunc(imageSize * imageSize, 2))) @divTrunc(imageSize, 2) else imageSize);
    errdefer cmem.free(atlas.pixels.ptr);

    switch (packMethod) {
        0 => { // Use basic packing algorithm
            var offsetX = padding;
            var offsetY = padding;

            // NOTE: Using simple packaging, one char after another
            for (glyphs, recs) |glyph, *rec| {
                // Check remaining space for glyph
                if (offsetX >= atlas.width - glyph.image.width - 2 * padding) {
                    offsetX = padding;
                    offsetY += fontSize + 2 * padding;

                    if (offsetY > atlas.height - fontSize - padding) {
                        TraceLog(LOG_WARNING, "FONT: Updating atlas size to fit all characters");
                        try atlas.grow();
                    }
                }

                atlas.blit(glyph.image, offsetX, offsetY);

                // Fill chars rectangles in atlas info
                rec.* = .{ .x = float(offsetX), .y = float(offsetY), .width = float(glyph.image.width), .height = float(glyph.image.height) };

                // Move atlas position X for next character drawing
                offsetX += glyph.image.width + 2 * padding;
            }
        },
        1 => { // Use Skyline rect packing algorithm (stb_pack_rect)
            const context = try allocOpaque(rl_sizeof_stbrp_context());
            defer gpa.free(context);
            const nodes = try allocOpaque(glyphs.len * rl_sizeof_stbrp_node());
            defer gpa.free(nodes);
            stbrp_init_target(context.ptr, atlas.width, atlas.height, nodes.ptr, cInt(glyphs.len));

            // Fill rectangles for packaging
            const rects = try gpa.alloc(stbrp_rect, glyphs.len);
            defer gpa.free(rects);
            for (rects, glyphs, 0..) |*rect, glyph, i| {
                rect.* = .{ .id = cInt(i), .w = glyph.image.width + 2 * padding, .h = glyph.image.height + 2 * padding };
            }

            // Package rectangles into atlas
            _ = stbrp_pack_rects(context.ptr, rects.ptr, cInt(rects.len));

            for (glyphs, recs, rects) |glyph, *rec, rect| {
                // It returns char rectangles in atlas
                rec.* = .{
                    .x = float(rect.x) + float(padding),
                    .y = float(rect.y) + float(padding),
                    .width = float(glyph.image.width),
                    .height = float(glyph.image.height),
                };

                if (rect.was_packed != 0) {
                    atlas.blit(glyph.image, rect.x + padding, rect.y + padding);
                } else TraceLog(LOG_WARNING, "FONT: Failed to package glyph (0x%02x)", glyph.value);
            }
        },
        else => {},
    }

    // Add a 3x3 white rectangle at the bottom-right corner of the generated atlas
    if (atlas.width >= 3 and atlas.height >= 3) {
        var k: usize = @intCast(atlas.width * atlas.height - 1);
        for (0..FONT_ATLAS_CORNER_REC_SIZE) |_| {
            @memset(atlas.pixels[k - 2 ..][0..3], 255);
            k -= @intCast(atlas.width);
        }
    }

    // Convert image data from GRAYSCALE to GRAY_ALPHA
    const grayAlpha = try cmem.alloc([2]u8, atlas.pixels.len);
    for (grayAlpha, atlas.pixels) |*pixel, gray| pixel.* = .{ 255, gray };
    cmem.free(atlas.pixels.ptr);

    return .{
        .data = grayAlpha.ptr,
        .width = atlas.width,
        .height = atlas.height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA,
    };
}

// Unload font glyphs info data (RAM)
export fn UnloadFontData(glyphs: [*c]GlyphInfo, glyphCount: c_int) callconv(.c) void {
    if (glyphs == null) return;
    for (cItems(GlyphInfo, glyphs, glyphCount)) |glyph| UnloadImage(glyph.image);
    cmem.free(glyphs);
}

// Unload Font from GPU memory (VRAM)
export fn UnloadFont(font: Font) callconv(.c) void {
    // NOTE: Make sure font is not default font (fallback)
    if (font.texture.id == GetFontDefault().texture.id) return;

    UnloadFontData(font.glyphs, font.glyphCount);
    UnloadTexture(font.texture);
    cmem.free(font.recs);

    TraceLog(LOG_DEBUG, "FONT: Unloaded font data from RAM and VRAM");
}

// Export font as code file, returns true on success
export fn ExportFontAsCode(font: Font, fileName: [*c]const u8) callconv(.c) bool {
    // Get file name from path
    var namePascal: [256]u8 = @splat(0);
    strings.copyTruncated(&namePascal, std.mem.span(TextToPascal(GetFileNameWithoutExt(fileName))));

    // Get font atlas image and size, required to estimate code file size
    const image = LoadImageFromTexture(font.texture);
    if (image.format != PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA) TraceLog(LOG_WARNING, "Font export as code: Font image format is not GRAY+ALPHA!");
    const imageDataSize = GetPixelDataSize(image.width, image.height, image.format);

    // WARNING: Data is compressed using raylib CompressData() DEFLATE
    var compDataSize: c_int = 0;
    const compData = CompressData(@ptrCast(image.data), imageDataSize, &compDataSize);

    const code: FontCode = .{
        .font = font,
        .name = std.mem.sliceTo(&namePascal, 0),
        .nameUpper = std.mem.span(TextToUpper(&namePascal)),
        .image = image,
        .compressed = compData[0..@intCast(compDataSize)],
    };
    const text = code.format(@intCast(imageDataSize));
    cmem.free(compData);
    UnloadImage(image);

    // NOTE: Text data size exported is determined by '\0' (NULL) character
    const result = if (text) |t| saved: {
        defer gpa.free(t);
        break :saved SaveFileText(fileName, t.ptr);
    } else |_| false;

    if (result) TraceLog(LOG_INFO, "FILEIO: [%s] Font as code exported successfully", fileName) else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export font as code", fileName);

    return result;
}

/// The C header ExportFontAsCode writes.
const FontCode = struct {
    font: Font,
    /// File name in PascalCase, and upper-cased
    name: []const u8,
    nameUpper: []const u8,
    image: Image,
    /// The atlas pixels, DEFLATE-compressed
    compressed: []const u8,

    /// The header text; the caller owns it.
    fn format(code: FontCode, imageDataSize: usize) error{OutOfMemory}![:0]u8 {
        const glyphCount: usize = @intCast(@max(code.font.glyphCount, 0));
        var text: std.Io.Writer.Allocating = try .initCapacity(gpa, imageDataSize * 6 + glyphCount * 128 + 32768);
        defer text.deinit();
        code.write(&text.writer) catch return error.OutOfMemory;
        return text.toOwnedSliceSentinel(0);
    }

    fn write(code: FontCode, w: *std.Io.Writer) std.Io.Writer.Error!void {
        const font = code.font;
        const name = code.name;

        try w.writeAll(
            \\////////////////////////////////////////////////////////////////////////////////////////
            \\//                                                                                    //
            \\// FontAsCode exporter v1.0 - Font data exported as an array of bytes                 //
            \\//                                                                                    //
            \\// more info and bugs-report:  github.com/raysan5/raylib                              //
            \\// feedback and support:       ray[at]raylib.com                                      //
            \\//                                                                                    //
            \\// Copyright (c) 2018-2026 Ramon Santamaria (@raysan5)                                //
            \\//                                                                                    //
            \\// ---------------------------------------------------------------------------------- //
            \\//                                                                                    //
            \\// TODO: Fill the information and license of the exported font here:                  //
            \\//                                                                                    //
            \\// Font name:    ....                                                                 //
            \\// Font creator: ....                                                                 //
            \\// Font LICENSE: ....                                                                 //
            \\//                                                                                    //
            \\////////////////////////////////////////////////////////////////////////////////////////
            \\
            \\
        );

        // Save font image data (compressed)
        try w.print("#define COMPRESSED_DATA_SIZE_FONT_{s} {d}\n\n", .{ code.nameUpper, code.compressed.len });
        try w.writeAll(
            \\// Font image pixels data compressed (DEFLATE)
            \\// NOTE: Original pixel data simplified to GRAYSCALE
            \\
        );
        try w.print("static unsigned char fontData_{s}[COMPRESSED_DATA_SIZE_FONT_{s}] = {{ ", .{ name, code.nameUpper });
        const last = code.compressed.len - 1;
        for (code.compressed[0..last], 0..) |byte, i| {
            if (i % TEXT_BYTES_PER_LINE == 0) try w.print("0x{x:0>2},\n    ", .{byte}) else try w.print("0x{x:0>2}, ", .{byte});
        }
        try w.print("0x{x:0>2} }};\n\n", .{code.compressed[last]});

        // Save font recs data
        try w.writeAll("// Font characters rectangles data\n");
        try w.print("static Rectangle fontRecs_{s}[{d}] = {{\n", .{ name, font.glyphCount });
        for (recsOf(font)) |rec| {
            // printf rounding: see snprintf above
            var line: [256]u8 = undefined;
            const len = snprintf(&line, line.len, "    { %1.0f, %1.0f, %1.0f , %1.0f },\n", @as(f64, rec.x), @as(f64, rec.y), @as(f64, rec.width), @as(f64, rec.height));
            try w.writeAll(line[0..@min(@as(usize, @intCast(len)), line.len - 1)]);
        }
        try w.writeAll("};\n\n");

        // Save font glyphs data
        try w.writeAll(
            \\// Font glyphs info data
            \\// NOTE: No glyphs.image data provided
            \\
        );
        try w.print("static GlyphInfo fontGlyphs_{s}[{d}] = {{\n", .{ name, font.glyphCount });
        for (glyphsOf(font)) |glyph| {
            try w.print("    {{ {d}, {d}, {d}, {d}, {{ 0 }}}},\n", .{ glyph.value, glyph.offsetX, glyph.offsetY, glyph.advanceX });
        }
        try w.writeAll("};\n\n");

        // Custom font loading function
        try w.print("// Font loading function: {s}\n", .{name});
        try w.print("static Font LoadFont_{s}(void)\n{{\n", .{name});
        try w.writeAll("    Font font = { 0 };\n\n");
        try w.print("    font.baseSize = {d};\n", .{font.baseSize});
        try w.print("    font.glyphCount = {d};\n", .{font.glyphCount});
        try w.print("    font.glyphPadding = {d};\n\n", .{font.glyphPadding});
        try w.writeAll(
            \\    // Custom font loading
            \\    // NOTE: Compressed font image data (DEFLATE), it requires DecompressData() function
            \\
        );
        try w.print("    int fontDataSize_{s} = 0;\n", .{name});
        try w.print("    unsigned char *data = DecompressData(fontData_{s}, COMPRESSED_DATA_SIZE_FONT_{s}, &fontDataSize_{s});\n", .{ name, code.nameUpper, name });
        try w.print("    Image imFont = {{ data, {d}, {d}, 1, {d} }};\n\n", .{ code.image.width, code.image.height, code.image.format });
        try w.writeAll(
            \\    // Load texture from image
            \\    font.texture = LoadTextureFromImage(imFont);
            \\    UnloadImage(imFont);  // Uncompressed data can be unloaded from memory
            \\
            \\    // Assign glyph recs and info data directly
            \\    // WARNING: This font data must not be unloaded
            \\
        );
        try w.print("    font.recs = fontRecs_{s};\n", .{name});
        try w.print("    font.glyphs = fontGlyphs_{s};\n\n", .{name});
        try w.writeAll(
            \\    return font;
            \\}
            \\
        );
    }
};

//----------------------------------------------------------------------------------
// Text drawing
//----------------------------------------------------------------------------------
// Draw current FPS
export fn DrawFPS(posX: c_int, posY: c_int) callconv(.c) void {
    const fps = GetFPS();
    const color = if (fps < 15) RED // Low FPS
        else if (fps < 30) ORANGE // Warning FPS
        else LIME; // Good FPS

    DrawText(TextFormat("%2i FPS", fps), posX, posY, 20, color);
}

// Draw text (using default font)
export fn DrawText(text: [*c]const u8, posX: c_int, posY: c_int, fontSize: c_int, color: Color) callconv(.c) void {
    // Check if default font has been loaded
    if (GetFontDefault().texture.id == 0) return;

    const position: Vector2 = .{ .x = float(posX), .y = float(posY) };

    const defaultFontSize = 10; // Default Font chars height in pixel
    const size = @max(fontSize, defaultFontSize);
    const spacing = @divTrunc(size, defaultFontSize);

    DrawTextEx(GetFontDefault(), text, position, float(size), float(spacing), color);
}

/// How far a drawn glyph moves the pen before spacing: its advance, or its
/// width for fonts without advances.
fn penAdvance(font: Font, index: usize, scaleFactor: f32) f32 {
    const advance = font.glyphs[index].advanceX;
    return if (advance == 0) font.recs[index].width * scaleFactor else float(advance) * scaleFactor;
}

// Draw text using Font
export fn DrawTextEx(fontIn: Font, text: [*c]const u8, position: Vector2, fontSize: f32, spacing: f32, tint: Color) callconv(.c) void {
    const font = if (fontIn.texture.id == 0) GetFontDefault() else fontIn; // Security check in case of not valid font
    const bytes = cText(text);

    var textOffsetY: f32 = 0; // Offset between lines (on linebreak '\n')
    var textOffsetX: f32 = 0.0; // Offset X to next character to draw

    const scaleFactor = fontSize / float(font.baseSize); // Character quad scaling factor

    var i: usize = 0;
    while (i < bytes.len) {
        // Get next codepoint from byte string and glyph index in font
        const next = strings.decodeNext(bytes[i..]);
        const codepoint = next.codepoint;
        i += next.size;

        if (codepoint == '\n') {
            // NOTE: Line spacing is a global variable, use SetTextLineSpacing() to setup
            textOffsetY += fontSize + float(textLineSpacing);
            textOffsetX = 0.0;
            continue;
        }

        if (codepoint != ' ' and codepoint != '\t') {
            DrawTextCodepoint(font, codepoint, .{ .x = position.x + textOffsetX, .y = position.y + textOffsetY }, fontSize, tint);
        }

        textOffsetX += penAdvance(font, @intCast(GetGlyphIndex(font, codepoint)), scaleFactor) + spacing;
    }
}

// Draw text using Font and pro parameters (rotation)
export fn DrawTextPro(font: Font, text: [*c]const u8, position: Vector2, origin: Vector2, rotation: f32, fontSize: f32, spacing: f32, tint: Color) callconv(.c) void {
    rlPushMatrix();

    rlTranslatef(position.x, position.y, 0.0);
    rlRotatef(rotation, 0.0, 0.0, 1.0);
    rlTranslatef(-origin.x, -origin.y, 0.0);

    DrawTextEx(font, text, .{ .x = 0.0, .y = 0.0 }, fontSize, spacing, tint);

    rlPopMatrix();
}

// Draw one character (codepoint)
export fn DrawTextCodepoint(font: Font, codepoint: c_int, position: Vector2, fontSize: f32, tint: Color) callconv(.c) void {
    // Character index position in sprite font
    const index: usize = @intCast(GetGlyphIndex(font, codepoint));
    const glyph = font.glyphs[index];
    const rec = font.recs[index];
    const padding = float(font.glyphPadding);
    const scaleFactor = fontSize / float(font.baseSize); // Character quad scaling factor

    // Character destination rectangle on screen
    const dstRec: Rectangle = .{
        .x = position.x + float(glyph.offsetX) * scaleFactor - padding * scaleFactor,
        .y = position.y + float(glyph.offsetY) * scaleFactor - padding * scaleFactor,
        .width = (rec.width + 2.0 * padding) * scaleFactor,
        .height = (rec.height + 2.0 * padding) * scaleFactor,
    };

    // Character source rectangle from font texture atlas
    const srcRec: Rectangle = .{
        .x = rec.x - padding,
        .y = rec.y - padding,
        .width = rec.width + 2.0 * padding,
        .height = rec.height + 2.0 * padding,
    };

    // Draw the character texture on the screen
    DrawTexturePro(font.texture, srcRec, dstRec, .{ .x = 0, .y = 0 }, 0.0, tint);
}

// Draw multiple characters (codepoints)
export fn DrawTextCodepoints(font: Font, codepoints: [*c]const c_int, codepointCount: c_int, position: Vector2, fontSize: f32, spacing: f32, tint: Color) callconv(.c) void {
    var textOffsetY: f32 = 0; // Offset between lines (on linebreak '\n')
    var textOffsetX: f32 = 0.0; // Offset X to next character to draw

    const scaleFactor = fontSize / float(font.baseSize); // Character quad scaling factor

    for (cItems(c_int, codepoints, codepointCount)) |codepoint| {
        if (codepoint == '\n') {
            // NOTE: Line spacing is a global variable, use SetTextLineSpacing() to setup
            textOffsetY += fontSize + float(textLineSpacing);
            textOffsetX = 0.0;
            continue;
        }

        if (codepoint != ' ' and codepoint != '\t') {
            DrawTextCodepoint(font, codepoint, .{ .x = position.x + textOffsetX, .y = position.y + textOffsetY }, fontSize, tint);
        }

        textOffsetX += penAdvance(font, @intCast(GetGlyphIndex(font, codepoint)), scaleFactor) + spacing;
    }
}

// Set vertical line spacing when drawing with line-breaks
export fn SetTextLineSpacing(spacing: c_int) callconv(.c) void {
    textLineSpacing = spacing;
}

//----------------------------------------------------------------------------------
// Text measuring and glyph lookup
//----------------------------------------------------------------------------------
// Measure string width for default font
export fn MeasureText(text: [*c]const u8, fontSize: c_int) callconv(.c) c_int {
    // Check if default font has been loaded
    if (GetFontDefault().texture.id == 0) return 0;

    const defaultFontSize = 10; // Default Font glyphs height in pixel
    const size = @max(fontSize, defaultFontSize);
    const spacing = @divTrunc(size, defaultFontSize);

    return @intFromFloat(MeasureTextEx(GetFontDefault(), text, float(size), float(spacing)).x);
}

/// How much a measured glyph adds to the line width, before scaling: its
/// advance, or for fonts without advances its width and offset.
fn measuredWidth(font: Font, index: usize) f32 {
    const glyph = font.glyphs[index];
    return if (glyph.advanceX > 0) float(glyph.advanceX) else font.recs[index].width + float(glyph.offsetX);
}

/// The widest line of a text measured glyph by glyph.
const Measure = struct {
    font: Font,
    fontSize: f32,
    /// Width of the current line
    lineWidth: f32 = 0.0,
    /// Width of the longest line so far
    maxWidth: f32 = 0.0,
    /// Glyphs on the current line, and the most on any line
    lineGlyphs: c_int = 0,
    maxGlyphs: c_int = 0,
    height: f32,

    fn init(font: Font, fontSize: f32) Measure {
        return .{ .font = font, .fontSize = fontSize, .height = fontSize };
    }

    fn glyph(m: *Measure, codepoint: c_int) void {
        m.lineWidth += measuredWidth(m.font, @intCast(GetGlyphIndex(m.font, codepoint)));
    }

    fn newLine(m: *Measure) void {
        if (m.maxWidth < m.lineWidth) m.maxWidth = m.lineWidth;
        m.lineWidth = 0;
        m.lineGlyphs = 0;

        // NOTE: Line spacing is a global variable, use SetTextLineSpacing() to setup
        m.height += m.fontSize + float(textLineSpacing);
    }

    fn size(m: *Measure, spacing: f32) Vector2 {
        if (m.maxWidth < m.lineWidth) m.maxWidth = m.lineWidth;
        const scaleFactor = m.fontSize / float(m.font.baseSize);
        // C: `(float)((count - 1)*spacing)` multiplies int by float in FLOAT;
        // the cast is a no-op. Truncating spacing would zero fractional spacings.
        return .{ .x = m.maxWidth * scaleFactor + float(m.maxGlyphs - 1) * spacing, .y = m.height };
    }
};

// Measure string size for Font
export fn MeasureTextEx(font: Font, text: [*c]const u8, fontSize: f32, spacing: f32) callconv(.c) Vector2 {
    const bytes = cText(text);
    if (font.texture.id == 0 or bytes.len == 0) return .{ .x = 0, .y = 0 }; // Security check

    var m: Measure = .init(font, fontSize);
    var i: usize = 0;
    while (i < bytes.len) {
        // raylib counts bytes per line here, not glyphs: a line feed resets
        // the count after it was incremented
        m.lineGlyphs += 1;

        const next = strings.decodeNext(bytes[i..]);
        i += next.size;

        if (next.codepoint != '\n') m.glyph(next.codepoint) else m.newLine();

        if (m.maxGlyphs < m.lineGlyphs) m.maxGlyphs = m.lineGlyphs;
    }

    return m.size(spacing);
}

// Measure string size for an existing array of codepoints for Font
export fn MeasureTextCodepoints(font: Font, codepoints: [*c]const c_int, length: c_int, fontSize: f32, spacing: f32) callconv(.c) Vector2 {
    if (font.texture.id == 0 or codepoints == null or length == 0) return .{ .x = 0, .y = 0 }; // Security check

    var m: Measure = .init(font, fontSize);
    for (cItems(c_int, codepoints, length)) |codepoint| {
        if (codepoint != '\n') {
            m.lineGlyphs += 1;
            m.glyph(codepoint);
        } else m.newLine();

        if (m.maxGlyphs < m.lineGlyphs) m.maxGlyphs = m.lineGlyphs;
    }

    return m.size(spacing);
}

// Get index position for a unicode character on font
// NOTE: If codepoint is not found in the font it fallbacks to '?'
export fn GetGlyphIndex(font: Font, codepoint: c_int) callconv(.c) c_int {
    if (!IsFontValid(font)) return 0;

    var fallbackIndex: c_int = 0; // Index of the last fallback glyph '?'
    for (glyphsOf(font), 0..) |glyph, i| {
        if (glyph.value == codepoint) return cInt(i);
        if (glyph.value == '?') fallbackIndex = cInt(i);
    }
    return fallbackIndex;
}

// Get glyph font info data for a codepoint (unicode character)
// NOTE: If codepoint is not found in the font it fallbacks to '?'
export fn GetGlyphInfo(font: Font, codepoint: c_int) callconv(.c) GlyphInfo {
    return font.glyphs[@intCast(GetGlyphIndex(font, codepoint))];
}

// Get glyph rectangle in font atlas for a codepoint (unicode character)
// NOTE: If codepoint is not found in the font it fallbacks to '?'
export fn GetGlyphAtlasRec(font: Font, codepoint: c_int) callconv(.c) Rectangle {
    return font.recs[@intCast(GetGlyphIndex(font, codepoint))];
}

//----------------------------------------------------------------------------------
// Text strings management functions
//----------------------------------------------------------------------------------
// Load text as separate lines ('\n')
// WARNING: There is a limit set for number of lines and line-size
export fn LoadTextLines(text: [*c]const u8, count: [*c]c_int) callconv(.c) [*c][*c]u8 {
    count.* = 0;
    const lines = loadTextLines(cSpan(text) orelse return null) catch return null;
    count.* = cInt(lines.len);
    return lines.ptr;
}

fn loadTextLines(text: []const u8) error{OutOfMemory}![][*c]u8 {
    const lines = try cmem.alloc([*c]u8, std.mem.countScalar(u8, text, '\n') + 1);
    var filled: usize = 0;
    errdefer UnloadTextLines(lines.ptr, cInt(filled));

    var pieces = std.mem.splitScalar(u8, text, '\n');
    while (pieces.next()) |piece| : (filled += 1) {
        const line = try cmem.alloc(u8, piece.len + 1);
        @memcpy(line[0..piece.len], piece);
        lines[filled] = line.ptr;
    }
    return lines;
}

// Unload text lines
export fn UnloadTextLines(lines: [*c][*c]u8, lineCount: c_int) callconv(.c) void {
    for (cItems([*c]u8, lines, lineCount)) |line| cmem.free(line);
    cmem.free(lines);
}

// Get text length in bytes, check for \0 character
export fn TextLength(text: [*c]const u8) callconv(.c) c_uint {
    return @intCast(cText(text).len);
}

// Formatting of text with variables to 'embed'
// WARNING: String returned will expire after this function is called MAX_TEXTFORMAT_BUFFERS times
export fn TextFormat(text: [*c]const u8, ...) callconv(.c) [*c]const u8 {
    // Create an array of buffers so strings don't expire until MAX_TEXTFORMAT_BUFFERS invocations
    const S = struct {
        var buffers: [MAX_TEXTFORMAT_BUFFERS][MAX_TEXT_BUFFER_LENGTH]u8 = @splat(@splat(0));
        var index: usize = 0;
    };

    const buffer = &S.buffers[S.index];
    @memset(buffer, 0); // Clear buffer before using
    if (text == null) return buffer;

    // The format and its arguments are C's: vsnprintf is the boundary here
    var args = @cVaStart();
    const requiredByteCount = vsnprintf(buffer, buffer.len, text, c_va.arg(&args));
    @cVaEnd(&args);

    // If requiredByteCount is larger than the buffer, then overflow occurred:
    // mark the string as truncated with "..." at its end
    if (requiredByteCount >= MAX_TEXT_BUFFER_LENGTH) buffer[buffer.len - 4 ..].* = "...\x00".*;

    S.index = (S.index + 1) % MAX_TEXTFORMAT_BUFFERS; // Move to next buffer for next function call
    return buffer;
}

// Get integer value from text
export fn TextToInteger(text: [*c]const u8) callconv(.c) c_int {
    return strings.parseInt(cSpan(text) orelse return 0);
}

// Get float value from text
// WARNING: Only '.' character is understood as decimal point
export fn TextToFloat(text: [*c]const u8) callconv(.c) f32 {
    return strings.parseFloat(cSpan(text) orelse return 0.0);
}

// Copy one string to another, returns bytes copied
export fn TextCopy(dst: [*c]u8, src: [*c]const u8) callconv(.c) c_int {
    const source = cSpan(src) orelse return 0;
    if (dst == null) return 0;

    // Overlapping strings (TextAppend within one buffer) are undefined in
    // raylib's byte loop; here they copy as memmove does
    @memmove(dst[0..source.len], source);
    dst[source.len] = 0;
    return cInt(source.len);
}

// Check if two text strings are equal
export fn TextIsEqual(text1: [*c]const u8, text2: [*c]const u8) callconv(.c) bool {
    const a = cSpan(text1) orelse return false;
    const b = cSpan(text2) orelse return false;
    return std.mem.eql(u8, a, b);
}

// Get a piece of a text string
export fn TextSubtext(text: [*c]const u8, position: c_int, length: c_int) callconv(.c) [*c]const u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);
    if (cSpan(text)) |t| strings.subtext(&S.buffer, t, position, length);
    return &S.buffer;
}

// Remove text spaces, concat words
export fn TextRemoveSpaces(text: [*c]const u8) callconv(.c) [*c]const u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);
    if (cSpan(text)) |t| strings.removeSpaces(&S.buffer, t);
    return &S.buffer;
}

// Get text between two strings
export fn GetTextBetween(text: [*c]const u8, begin: [*c]const u8, end: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);

    const t = cSpan(text) orelse return &S.buffer;
    const b = cSpan(begin) orelse return &S.buffer;
    const e = cSpan(end) orelse return &S.buffer;
    strings.between(&S.buffer, t, b, e);
    return &S.buffer;
}

// Replace text string
// NOTE: Limited text replace functionality, using static string
export fn TextReplace(text: [*c]const u8, search: [*c]const u8, replacement: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);

    const t = cSpan(text) orelse return &S.buffer;
    const s = cSpan(search) orelse return &S.buffer;
    if (s.len == 0) return &S.buffer;
    const r = cText(replacement);

    const size = std.mem.replacementSize(u8, t, s, r);
    if (size < S.buffer.len - 1) {
        _ = std.mem.replace(u8, t, s, r, S.buffer[0..size]);
    } else TraceLog(LOG_WARNING, "Text with replacement is longer than internal buffer, use TextReplaceAlloc()");

    return &S.buffer;
}

// Replace text string (allocates)
// WARNING: Allocated memory must be manually freed
export fn TextReplaceAlloc(text: [*c]const u8, search: [*c]const u8, replacement: [*c]const u8) callconv(.c) [*c]u8 {
    const t = cSpan(text) orelse return null;
    const s = cSpan(search) orelse return null;
    if (s.len == 0) return null;
    const r = cText(replacement);

    const result = cmem.alloc(u8, std.mem.replacementSize(u8, t, s, r) + 1) catch return null;
    _ = std.mem.replace(u8, t, s, r, result[0 .. result.len - 1]);
    return result.ptr;
}

// Replace text between two specific strings
// NOTE: If (replacement == NULL) remove "begin"[ ]"end" text
export fn TextReplaceBetween(text: [*c]const u8, begin: [*c]const u8, end: [*c]const u8, replacement: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);

    const t = cSpan(text) orelse return &S.buffer;
    const found = strings.findBetween(t, cSpan(begin) orelse return &S.buffer, cSpan(end) orelse return &S.buffer) orelse return &S.buffer;
    const r = cText(replacement);

    const size = strings.replaceBetweenSize(t, found, r);
    if (size < S.buffer.len - 1) {
        strings.replaceBetween(S.buffer[0..size], t, found, r);
    } else TraceLog(LOG_WARNING, "TEXT: Text with replaced string is longer than internal buffer (MAX_TEXT_BUFFER_LENGTH)");

    return &S.buffer;
}

// Replace text between two specific strings (allocates)
// NOTE: If (replacement == NULL) remove "begin"[ ]"end" text
// WARNING: Returned string must be freed by user
export fn TextReplaceBetweenAlloc(text: [*c]const u8, begin: [*c]const u8, end: [*c]const u8, replacement: [*c]const u8) callconv(.c) [*c]u8 {
    const t = cSpan(text) orelse return null;
    const found = strings.findBetween(t, cSpan(begin) orelse return null, cSpan(end) orelse return null) orelse return null;
    const r = cText(replacement);

    const result = cmem.alloc(u8, strings.replaceBetweenSize(t, found, r) + 1) catch return null;
    strings.replaceBetween(result[0 .. result.len - 1], t, found, r);
    return result.ptr;
}

// Insert text in a specific position, moves all text forward
export fn TextInsert(text: [*c]const u8, insert: [*c]const u8, position: c_int) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);

    const t = cSpan(text) orelse return &S.buffer;
    const piece = cSpan(insert) orelse return &S.buffer;
    if (position < 0) return &S.buffer;

    const len = t.len + piece.len;
    if (len < S.buffer.len - 1) {
        strings.insert(S.buffer[0..len], t, piece, @min(@as(usize, @intCast(position)), t.len)); // Clamp to end of text string
    } else TraceLog(LOG_WARNING, "Text with inserted string is longer than internal buffer, use TextInserExt()");

    return &S.buffer;
}

// Insert text in a specific position, moves all text forward (allocates)
// WARNING: Allocated memory must be manually freed
export fn TextInsertAlloc(text: [*c]const u8, insert: [*c]const u8, position: c_int) callconv(.c) [*c]u8 {
    const t = cSpan(text) orelse return null;
    const piece = cSpan(insert) orelse return null;
    if (position < 0) return null;

    const result = cmem.alloc(u8, t.len + piece.len + 1) catch return null;
    strings.insert(result[0 .. result.len - 1], t, piece, @min(@as(usize, @intCast(position)), t.len)); // Clamp to end of text string
    return result.ptr;
}

// Join text strings with delimiter
export fn TextJoin(textList: [*c][*c]u8, count: c_int, delimiter: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);

    const separator = cText(delimiter);
    const items = cItems([*c]u8, textList, count);
    var len: usize = 0;
    for (items, 0..) |item, i| {
        const piece = cText(item);

        // Make sure joined text could fit inside MAX_TEXT_BUFFER_LENGTH
        // (with a delimiter after it, even after the last piece)
        if (len + piece.len + separator.len >= S.buffer.len) continue;

        @memcpy(S.buffer[len..][0..piece.len], piece);
        len += piece.len;

        if (i < items.len - 1) {
            @memcpy(S.buffer[len..][0..separator.len], separator);
            len += separator.len;
        }
    }

    return &S.buffer;
}

// Split string into multiple strings
// NOTE: Returns a copy of the text with '\0' at each delimiter, in a static
// buffer: at most MAX_TEXTSPLIT_COUNT pieces of MAX_TEXT_BUFFER_LENGTH bytes in all
export fn TextSplit(text: [*c]const u8, delimiter: u8, count: [*c]c_int) callconv(.c) [*c][*c]u8 {
    const S = struct {
        var pieces: [MAX_TEXTSPLIT_COUNT][*c]u8 = @splat(null); // Pointers to buffer text data
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0); // Text data with '\0' separators
    };
    @memset(&S.buffer, 0);
    S.pieces[0] = &S.buffer;

    const bytes = cSpan(text) orelse {
        count.* = 0;
        return &S.pieces;
    };

    // NOTE: Last buffer byte is reserved to terminate the last substring
    var counter: usize = 1;
    for (bytes[0..@min(bytes.len, S.buffer.len - 1)], 0..) |c, i| {
        if (c != delimiter) {
            S.buffer[i] = c;
            continue;
        }
        // The zero left at S.buffer[i] ends this piece
        S.pieces[counter] = S.buffer[i + 1 ..].ptr;
        counter += 1;
        // Like raylib, the rest of the text is dropped: the last piece is empty
        if (counter == MAX_TEXTSPLIT_COUNT) break;
    }

    count.* = cInt(counter);
    return &S.pieces;
}

// Append text at specific position and move cursor
// WARNING: It's up to the user to make sure appended text does not overflow the buffer!
export fn TextAppend(text: [*c]u8, append: [*c]const u8, position: [*c]c_int) callconv(.c) void {
    if (text == null or append == null) return;
    position.* += TextCopy(text + @as(usize, @intCast(position.*)), append);
}

// Find first text occurrence within a string, -1 if not found
export fn TextFindIndex(text: [*c]const u8, search: [*c]const u8) callconv(.c) c_int {
    const t = cSpan(text) orelse return -1;
    const s = cSpan(search) orelse return -1;
    return if (std.mem.find(u8, t, s)) |index| cInt(index) else -1;
}

// Get upper case version of provided string
// WARNING: Limited functionality, only basic characters set
export fn TextToUpper(text: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);
    if (cSpan(text)) |t| strings.toUpper(&S.buffer, t);
    return &S.buffer;
}

// Get lower case version of provided string
// WARNING: Limited functionality, only basic characters set
export fn TextToLower(text: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);
    if (cSpan(text)) |t| strings.toLower(&S.buffer, t);
    return &S.buffer;
}

// Get Pascal case notation version of provided string
export fn TextToPascal(text: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);
    if (cSpan(text)) |t| strings.joinWords(&S.buffer, t, .upper);
    return &S.buffer;
}

// Get snake case notation version of provided string
export fn TextToSnake(text: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);
    if (cSpan(text)) |t| strings.snake(&S.buffer, t);
    return &S.buffer;
}

// Get Camel case notation version of provided string
export fn TextToCamel(text: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = @splat(0);
    };
    @memset(&S.buffer, 0);
    if (cSpan(text)) |t| strings.joinWords(&S.buffer, t, .lower);
    return &S.buffer;
}

//----------------------------------------------------------------------------------
// Codepoints and UTF-8
//----------------------------------------------------------------------------------
// Encode text codepoint into UTF-8 text (allocates)
// WARNING: Allocated memory must be manually freed
export fn LoadUTF8(codepoints: [*c]const c_int, length: c_int) callconv(.c) [*c]u8 {
    const items = cItems(c_int, codepoints, length);
    if (items.len == 0) return null;
    const text = loadUTF8(items) catch return null;
    return text.ptr;
}

fn loadUTF8(codepoints: []const c_int) error{OutOfMemory}![]u8 {
    // Enough memory to fit all possible codepoints
    const scratch = try gpa.alloc(u8, codepoints.len * 4);
    defer gpa.free(scratch);

    var size: usize = 0;
    for (codepoints) |codepoint| {
        // raylib encodes through CodepointToUTF8, leaving its static buffer as C does
        var bytes: c_int = 0;
        const utf8 = CodepointToUTF8(codepoint, &bytes);
        const len: usize = @intCast(bytes);
        @memcpy(scratch[size..][0..len], utf8[0..len]);
        size += len;
    }

    const text = try cmem.alloc(u8, size + 1);
    @memcpy(text[0..size], scratch[0..size]);
    return text;
}

// Unload UTF-8 text encoded from codepoints array
export fn UnloadUTF8(text: [*c]u8) callconv(.c) void {
    cmem.free(text);
}

// Load all codepoints from a UTF-8 text string, codepoints count returned by parameter
export fn LoadCodepoints(text: [*c]const u8, count: [*c]c_int) callconv(.c) [*c]c_int {
    count.* = 0;
    const codepoints = loadCodepoints(cSpan(text) orelse return null) catch return null;
    count.* = cInt(codepoints.len);
    return codepoints.ptr;
}

fn loadCodepoints(text: []const u8) error{OutOfMemory}![]c_int {
    // A big enough buffer to store as many codepoints as text bytes
    const scratch = try gpa.alloc(c_int, text.len);
    defer gpa.free(scratch);

    var count: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (count += 1) {
        const next = strings.decodeNext(text[i..]);
        scratch[count] = next.codepoint;
        i += next.size;
    }

    const codepoints = try cmem.alloc(c_int, count);
    @memcpy(codepoints, scratch[0..count]);
    return codepoints;
}

// Unload codepoints data from memory
export fn UnloadCodepoints(codepoints: [*c]c_int) callconv(.c) void {
    cmem.free(codepoints);
}

// Get total number of characters (codepoints) in a UTF-8 encoded text, until '\0' is found
export fn GetCodepointCount(text: [*c]const u8) callconv(.c) c_int {
    const bytes = cSpan(text) orelse return 0;
    var count: c_int = 0;
    var i: usize = 0;
    while (i < bytes.len) : (count += 1) i += strings.decodeNext(bytes[i..]).size;
    return count;
}

// Encode codepoint into utf8 text (char array length returned as parameter)
// NOTE: It uses a static array to store UTF-8 bytes
export fn CodepointToUTF8(codepoint: c_int, utf8Size: [*c]c_int) callconv(.c) [*c]const u8 {
    const S = struct {
        var utf8: [6]u8 = @splat(0);
    };
    @memset(&S.utf8, 0); // Clear static array
    utf8Size.* = cInt(strings.encode(codepoint, S.utf8[0..4]).len);
    return &S.utf8;
}

// Get next codepoint in a UTF-8 encoded text, scanning until '\0' is found
// NOTE: On error, '?' (0x3f) is returned and codepointSize tells how many bytes to skip
export fn GetCodepoint(text: [*c]const u8, codepointSize: [*c]c_int) callconv(.c) c_int {
    codepointSize.* = 1;
    if (text == null) return '?';
    const decoded = strings.decode(utf8Window(text));
    codepointSize.* = decoded.size;
    return decoded.codepoint;
}

// Get next codepoint in a byte sequence and bytes processed
export fn GetCodepointNext(text: [*c]const u8, codepointSize: [*c]c_int) callconv(.c) c_int {
    codepointSize.* = 1;
    if (text == null) return '?';
    const decoded = strings.decodeNext(utf8Window(text));
    codepointSize.* = decoded.size;
    return decoded.codepoint;
}

// Get previous codepoint in a byte sequence and bytes processed
export fn GetCodepointPrevious(text: [*c]const u8, codepointSize: [*c]c_int) callconv(.c) c_int {
    codepointSize.* = 1;
    if (text == null) return '?';

    // Move to previous codepoint: like raylib, this reads before `text` and
    // trusts the caller that a codepoint starts there
    var start: [*]const u8 = text - 1;
    while (start[0] & 0xc0 == 0x80) start -= 1;

    const decoded = strings.decodeNext(utf8Window(start));
    if (decoded.codepoint != 0) codepointSize.* = decoded.size;
    return decoded.codepoint;
}

//----------------------------------------------------------------------------------
// Module Internal Functions Definition
//----------------------------------------------------------------------------------
// Load a BMFont file (AngelCode font file)
fn loadBMFont(fileName: [*:0]const u8) Font {
    const fileText = LoadFileText(fileName);
    if (fileText == null) return empty_font;
    defer UnloadFileText(fileText);

    const font = loadBMFontText(fileName, std.mem.span(fileText)) catch |err| switch (err) {
        error.Malformed, error.OutOfMemory => return empty_font,
    };

    if (font.texture.id == 0) {
        UnloadFont(font);
        TraceLog(LOG_WARNING, "FONT: [%s] Failed to load texture, reverted to default font", fileName);
        return GetFontDefault();
    }
    TraceLog(LOG_INFO, "FONT: [%s] Font loaded successfully (%i glyphs)", fileName, font.glyphCount);
    return font;
}

fn loadBMFontText(fileName: [*:0]const u8, text: []const u8) error{ Malformed, OutOfMemory }!Font {
    var lines: bmfont.Lines = .{ .rest = text };

    // NOTE: Skip first line, it contains no useful information
    _ = lines.next();

    // Some data not available, file malformed
    const common = bmfont.scanCommon(lines.next()) orelse return error.Malformed;

    var pageCount = common.pages;
    if (pageCount > MAX_FONT_IMAGE_PAGES) {
        TraceLog(LOG_WARNING, "FONT: [%s] Font defines more pages than supported: %i/%i", fileName, pageCount, @as(c_int, MAX_FONT_IMAGE_PAGES));
        pageCount = MAX_FONT_IMAGE_PAGES;
    }
    // raylib goes on to read an image it never loaded
    if (pageCount <= 0) return error.Malformed;
    const pages: usize = @intCast(pageCount);

    var files: [MAX_FONT_IMAGE_PAGES][bmfont.max_page_file_length + 1]u8 = undefined;
    for (files[0..pages]) |*file| {
        const name = bmfont.scanPageFile(lines.next()) orelse return error.Malformed; // No fileName read
        @memset(file, 0);
        @memcpy(file[0..name.len], name);
    }

    const glyphCount = bmfont.scanCount(lines.next()) orelse return error.Malformed; // No glyphCount read
    // raylib allocates the negative size, gets NULL and crashes
    if (glyphCount < 0) return error.Malformed;

    // Load all required images for further compose
    var images: [MAX_FONT_IMAGE_PAGES]Image = undefined;
    for (images[0..pages], files[0..pages], 0..) |*image, *file, loaded| {
        errdefer for (images[0..loaded]) |page| UnloadImage(page);
        // TextFormat as raylib: the path takes one of its rotating buffers
        image.* = LoadImage(TextFormat("%s/%s", GetDirectoryPath(fileName), @as([*c]const u8, file)));
        if (image.format == PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) image.* = try grayAsAlpha(image.*);
    }

    var fullFont = images[0];
    defer UnloadImage(fullFont);

    // If multiple atlas, then merge atlas
    // NOTE: raylib 6.2 unloads pages 1.. before drawing them here (a
    // use-after-free whose pixels are undefined); they are unloaded after
    if (pages > 1) {
        // Resize font atlas to draw additional images
        ImageResizeCanvas(&fullFont, common.scale_w, common.scale_h * pageCount, 0, 0, BLACK);

        for (images[1..pages], 1..) |page, i| {
            const srcRec: Rectangle = .{ .x = 0.0, .y = 0.0, .width = float(common.scale_w), .height = float(common.scale_h) };
            const dstRec: Rectangle = .{ .x = 0.0, .y = float(common.scale_h) * float(cInt(i)), .width = float(common.scale_w), .height = float(common.scale_h) };
            ImageDrawImagePro(&fullFont, page, srcRec, dstRec, .{ .x = 0, .y = 0 }, 0.0, WHITE);
        }
    }
    for (images[1..pages]) |page| UnloadImage(page);

    const texture = LoadTextureFromImage(fullFont);
    errdefer UnloadTexture(texture);

    const glyphs = try cmem.alloc(GlyphInfo, @intCast(glyphCount));
    errdefer cmem.free(glyphs.ptr);
    const recs = try cmem.alloc(Rectangle, @intCast(glyphCount));

    // Fill font characters info data
    for (glyphs, recs) |*glyph, *rec| {
        // Make sure all char data has been properly read
        const char = bmfont.scanChar(lines.next()) orelse {
            // NOTE: raylib sizes this image from an uninitialized rectangle; ours is zeroed
            glyph.image = GenImageColor(@intFromFloat(rec.width), @intFromFloat(rec.height), BLACK);
            TraceLog(LOG_WARNING, "FONT: [%s] Some characters data not correctly provided", fileName);
            continue;
        };

        // Get character rectangle in the font atlas texture
        rec.* = .{
            .x = float(char.x),
            .y = float(char.y) + float(common.scale_h) * float(char.page),
            .width = float(char.width),
            .height = float(char.height),
        };

        // Save data properly in sprite font
        glyph.* = .{
            .value = char.id,
            .offsetX = char.offset_x,
            .offsetY = char.offset_y,
            .advanceX = char.advance_x,
            // Fill character image data from full font data
            .image = ImageFromImage(fullFont, rec.*),
        };
    }

    return .{
        .texture = texture,
        .baseSize = common.line_height,
        .glyphCount = glyphCount,
        .glyphPadding = 0,
        .glyphs = glyphs.ptr,
        .recs = recs.ptr,
    };
}

/// A GRAYSCALE image as GRAY_ALPHA, using the gray as the alpha channel; the
/// original is unloaded.
fn grayAsAlpha(image: Image) error{OutOfMemory}!Image {
    const count: usize = @intCast(image.width * image.height);
    const pixels = try cmem.alloc([2]u8, count);
    const gray: [*]const u8 = @ptrCast(image.data.?);
    for (pixels, gray[0..count]) |*pixel, alpha| pixel.* = .{ 0xff, alpha };
    UnloadImage(image);

    return .{
        .data = pixels.ptr,
        .width = image.width,
        .height = image.height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA,
    };
}
