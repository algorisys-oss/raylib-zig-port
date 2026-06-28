//! rtext - Basic functions to load fonts and draw text
//!
//! Zig port of raylib's `rtext.c`. Every public raylib text/font function is exported
//! with its exact C name, byte-compatible signature, and C calling convention, so the
//! rest of raylib (still C) links against it unchanged. Floating-point operation order
//! matches the C source exactly to keep pixel output bit-identical, and libm functions
//! are called via extern declarations rather than `std.math`.
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

//----------------------------------------------------------------------------------
// libc / libm functions, called directly so results are bit-identical to the C source.
//----------------------------------------------------------------------------------
extern fn malloc(usize) ?*anyopaque;
extern fn calloc(usize, usize) ?*anyopaque;
extern fn free(?*anyopaque) void;
extern fn memcpy(noalias ?*anyopaque, noalias ?*const anyopaque, usize) ?*anyopaque;
extern fn memset(?*anyopaque, c_int, usize) ?*anyopaque;
extern fn strcmp([*c]const u8, [*c]const u8) c_int;
extern fn strncpy(noalias [*c]u8, noalias [*c]const u8, usize) [*c]u8;
extern fn strstr([*c]const u8, [*c]const u8) [*c]u8;
extern fn sprintf(noalias [*c]u8, noalias [*c]const u8, ...) c_int;
extern fn snprintf(noalias [*c]u8, usize, noalias [*c]const u8, ...) c_int;
extern fn vsnprintf(noalias [*c]u8, usize, noalias [*c]const u8, ap: *std.builtin.VaList) c_int;
extern fn sscanf(noalias [*c]const u8, noalias [*c]const u8, ...) c_int;

extern fn sqrtf(f32) f32;
extern fn powf(f32, f32) f32;
extern fn ceilf(f32) f32;
extern fn logf(f32) f32;

// raylib uses RL_MALLOC/RL_CALLOC/RL_FREE which map to malloc/calloc/free (config.h default).
const RL_MALLOC = malloc;
const RL_CALLOC = calloc;
inline fn RL_FREE(p: anytype) void {
    free(@ptrCast(p));
}

// C-style pointer arithmetic: ptr + (signed) offset of element type, matching C semantics.
inline fn ptrAdd(ptr: anytype, offset: c_int) @TypeOf(ptr) {
    const Elem = @typeInfo(@TypeOf(ptr)).pointer.child;
    const base = @intFromPtr(ptr);
    const delta: isize = @as(isize, offset) * @as(isize, @sizeOf(Elem));
    return @ptrFromInt(@as(usize, @bitCast(@as(isize, @bitCast(base)) +% delta)));
}

//----------------------------------------------------------------------------------
// Cross-module raylib C symbols (still C in this build) - extern declared and called.
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
extern fn stbtt_GetCodepointBitmap(info: ?*const anyopaque, scale_x: f32, scale_y: f32, codepoint: c_int, width: [*c]c_int, height: [*c]c_int, xoff: [*c]c_int, yoff: [*c]c_int) [*c]u8;

extern fn stbrp_init_target(context: ?*anyopaque, width: c_int, height: c_int, nodes: ?*anyopaque, num_nodes: c_int) void;
extern fn stbrp_pack_rects(context: ?*anyopaque, rects: [*c]stbrp_rect, num_rects: c_int) c_int;

// stbrp_rect mirrors stb_rect_pack's struct (6 ints); rtext reads x/y/was_packed fields.
const stbrp_rect = extern struct {
    id: c_int,
    w: c_int,
    h: c_int,
    x: c_int,
    y: c_int,
    was_packed: c_int,
};

//----------------------------------------------------------------------------------
// Defines and Macros
//----------------------------------------------------------------------------------
const MAX_TEXT_BUFFER_LENGTH: usize = 1024;
const MAX_TEXTSPLIT_COUNT: usize = 128;
const FONT_ATLAS_CORNER_REC_SIZE: c_int = 3;

const FONT_TTF_DEFAULT_SIZE: c_int = 32;
const FONT_TTF_DEFAULT_NUMCHARS: c_int = 95;
const FONT_TTF_DEFAULT_FIRST_CHAR: c_int = 32;
const FONT_TTF_DEFAULT_CHARS_PADDING: c_int = 4;

const FONT_BITMAP_ALPHA_THRESHOLD: c_int = 80;

const MAX_GLYPHS_FROM_IMAGE: usize = 256;
const MAX_TEXTFORMAT_BUFFERS: usize = 4;
const TEXT_BYTES_PER_LINE: c_int = 20;

const MAX_BUFFER_SIZE: usize = 256;
const MAX_FONT_IMAGE_PAGES: usize = 8;

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

//----------------------------------------------------------------------------------
// Global variables
//----------------------------------------------------------------------------------
// Default font provided by raylib
// NOTE: Default font is loaded on InitWindow() and disposed on CloseWindow() [module: core]
var defaultFont: Font = std.mem.zeroes(Font);

// Text vertical line spacing in pixels (between lines)
var textLineSpacing: c_int = 2;

//----------------------------------------------------------------------------------
// Module Functions Definition
//----------------------------------------------------------------------------------
// Load raylib default font
export fn LoadFontDefault() callconv(.c) void {
    // Check to see if the font for an image has already been allocated,
    // and if no need to upload, then return
    if (defaultFont.glyphs != null) return;

    // NOTE: Using UTF-8 encoding table for Unicode U+0000..U+00FF Basic Latin + Latin-1 Supplement
    defaultFont.glyphCount = 224; // Number of glyphs included in our default font
    defaultFont.glyphPadding = 0; // Characters padding

    // Default font is directly defined here (data generated from a sprite font image)
    const defaultFontData = [512]c_uint{
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

    const charsHeight: c_int = 10;
    const charsDivisor: c_int = 1; // Every char is separated from the consecutive by a 1 pixel divisor, horizontally and vertically

    const charsWidth = [224]c_int{
        3, 1, 4, 6, 5, 7, 6, 2, 3, 3, 5, 5, 2, 4, 1, 7, 5, 2, 5, 5, 5, 5, 5, 5, 5, 5, 1, 1, 3, 4, 3, 6,
        7, 6, 6, 6, 6, 6, 6, 6, 6, 3, 5, 6, 5, 7, 6, 6, 6, 6, 6, 6, 7, 6, 7, 7, 6, 6, 6, 2, 7, 2, 3, 5,
        2, 5, 5, 5, 5, 5, 4, 5, 5, 1, 2, 5, 2, 5, 5, 5, 5, 5, 5, 5, 4, 5, 5, 5, 5, 5, 5, 3, 1, 3, 4, 4,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 5, 5, 5, 7, 1, 5, 3, 7, 3, 5, 4, 1, 7, 4, 3, 5, 3, 3, 2, 5, 6, 1, 2, 2, 3, 5, 6, 6, 6, 6,
        6, 6, 6, 6, 6, 6, 7, 6, 6, 6, 6, 6, 3, 3, 3, 3, 7, 6, 6, 6, 6, 6, 6, 5, 6, 6, 6, 6, 6, 6, 4, 6,
        5, 5, 5, 5, 5, 5, 9, 5, 5, 5, 5, 5, 2, 2, 3, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5,
    };

    // Re-construct image from defaultFontData and generate OpenGL texture
    //----------------------------------------------------------------------
    const imFont = Image{
        .data = RL_CALLOC(128 * 128, 2), // 2 bytes per pixel (gray + alpha)
        .width = 128,
        .height = 128,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA,
    };

    // Fill image.data with defaultFontData (convert from bit to pixel!)
    {
        const imData16: [*]u16 = @ptrCast(@alignCast(imFont.data));
        const imData8: [*]u8 = @ptrCast(imFont.data);
        var i: c_int = 0;
        var counter: usize = 0;
        while (i < imFont.width * imFont.height) : (i += 32) {
            var j: c_int = 31;
            while (j >= 0) : (j -= 1) {
                const idx: usize = @intCast(i + j);
                if ((defaultFontData[counter] & (@as(c_uint, 1) << @intCast(j))) != 0) {
                    // NOTE: Unreferencing data as short, considering data as little-endian (alpha + gray)
                    imData16[idx] = 0xffff;
                } else {
                    imData8[idx * @sizeOf(u16)] = 0xff;
                    imData8[idx * @sizeOf(u16) + 1] = 0x00;
                }
            }

            counter += 1;
        }
    }

    defaultFont.texture = LoadTextureFromImage(imFont);

    // Check again if font glyph data has been already loaded
    // to avoid reallocating the glyphs and rects
    if (defaultFont.glyphs != null) {
        UnloadImage(imFont);
        return;
    }

    // Reconstruct charSet using charsWidth[], charsHeight, charsDivisor, glyphCount
    //------------------------------------------------------------------------------
    defaultFont.glyphs = @ptrCast(@alignCast(RL_CALLOC(@intCast(defaultFont.glyphCount), @sizeOf(GlyphInfo))));
    defaultFont.recs = @ptrCast(@alignCast(RL_CALLOC(@intCast(defaultFont.glyphCount), @sizeOf(Rectangle))));

    var currentLine: c_int = 0;
    var currentPosX: c_int = charsDivisor;
    var testPosX: c_int = charsDivisor;

    var i: c_int = 0;
    while (i < defaultFont.glyphCount) : (i += 1) {
        const u: usize = @intCast(i);
        defaultFont.glyphs[u].value = 32 + i; // First char is 32

        defaultFont.recs[u].x = @floatFromInt(currentPosX);
        defaultFont.recs[u].y = @floatFromInt(charsDivisor + currentLine * (charsHeight + charsDivisor));
        defaultFont.recs[u].width = @floatFromInt(charsWidth[u]);
        defaultFont.recs[u].height = @floatFromInt(charsHeight);

        testPosX += @as(c_int, @intFromFloat(defaultFont.recs[u].width + @as(f32, @floatFromInt(charsDivisor))));

        if (testPosX >= imFont.width) {
            currentLine += 1;
            currentPosX = 2 * charsDivisor + charsWidth[u];
            testPosX = currentPosX;

            defaultFont.recs[u].x = @floatFromInt(charsDivisor);
            defaultFont.recs[u].y = @floatFromInt(charsDivisor + currentLine * (charsHeight + charsDivisor));
        } else currentPosX = testPosX;

        // NOTE: On default font character offsets and xAdvance are not required
        defaultFont.glyphs[u].offsetX = 0;
        defaultFont.glyphs[u].offsetY = 0;
        defaultFont.glyphs[u].advanceX = 0;

        // Fill character image data from fontClear data
        defaultFont.glyphs[u].image = ImageFromImage(imFont, defaultFont.recs[u]);
    }

    UnloadImage(imFont);

    defaultFont.baseSize = @intFromFloat(defaultFont.recs[0].height);

    TraceLog(LOG_INFO, "FONT: Default font loaded successfully (%i glyphs)", defaultFont.glyphCount);
}

// Unload raylib default font
export fn UnloadFontDefault() callconv(.c) void {
    var i: c_int = 0;
    while (i < defaultFont.glyphCount) : (i += 1) {
        UnloadImage(defaultFont.glyphs[@intCast(i)].image);
    }
    UnloadTexture(defaultFont.texture);
    RL_FREE(defaultFont.glyphs);
    RL_FREE(defaultFont.recs);
    defaultFont.glyphCount = 0;
    defaultFont.glyphs = null;
    defaultFont.recs = null;
}

// Get the default font
export fn GetFontDefault() callconv(.c) Font {
    return defaultFont;
}

// Load Font from file into GPU memory (VRAM)
export fn LoadFont(fileName: [*c]const u8) callconv(.c) Font {
    var font: Font = std.mem.zeroes(Font);

    if (IsFileExtension(fileName, ".ttf") or IsFileExtension(fileName, ".otf")) {
        font = LoadFontEx(fileName, FONT_TTF_DEFAULT_SIZE, null, FONT_TTF_DEFAULT_NUMCHARS);
    } else if (IsFileExtension(fileName, ".fnt")) {
        font = LoadBMFont(fileName);
    } else {
        const image = LoadImage(fileName);
        if (image.data != null) font = LoadFontFromImage(image, MAGENTA, FONT_TTF_DEFAULT_FIRST_CHAR) else font = GetFontDefault();
        UnloadImage(image);
    }

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
    var font: Font = std.mem.zeroes(Font);

    // Loading file to memory
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);

    if (fileData != null) {
        // Loading font from memory data
        font = LoadFontFromMemory(GetFileExtension(fileName), fileData, dataSize, fontSize, codepoints, codepointCount);

        UnloadFileData(fileData);
    }

    return font;
}

// Load an Image font file (XNA style)
export fn LoadFontFromImage(image: Image, key: Color, firstChar: c_int) callconv(.c) Font {
    var font = GetFontDefault();

    var charSpacing: c_int = 0;
    var lineSpacing: c_int = 0;

    var x: c_int = 0;
    var y: c_int = 0;

    // Allocate temporal arrays for glyphs data measures
    var tempCharValues = std.mem.zeroes([MAX_GLYPHS_FROM_IMAGE]c_int);
    var tempCharRecs = std.mem.zeroes([MAX_GLYPHS_FROM_IMAGE]Rectangle);

    const pixels = LoadImageColors(image);

    const colorEqual = struct {
        inline fn eq(c1: Color, c2: Color) bool {
            return (c1.r == c2.r) and (c1.g == c2.g) and (c1.b == c2.b) and (c1.a == c2.a);
        }
    }.eq;

    // Parse image data to get charSpacing and lineSpacing
    y = 0;
    while (y < image.height) : (y += 1) {
        x = 0;
        while (x < image.width) : (x += 1) {
            if (!colorEqual(pixels[@intCast(y * image.width + x)], key)) break;
        }

        if (!colorEqual(pixels[@intCast(y * image.width + x)], key)) break;
    }

    if ((x == 0) or (y == 0)) return font; // Security check

    charSpacing = x;
    lineSpacing = y;

    var charHeight: c_int = 0;
    var j: c_int = 0;

    while (((lineSpacing + j) < image.height) and
        !colorEqual(pixels[@intCast((lineSpacing + j) * image.width + charSpacing)], key)) j += 1;

    charHeight = j;

    // Check array values to get characters: value, x, y, w, h
    var index: c_int = 0;
    var lineToRead: c_int = 0;
    var xPosToRead: c_int = charSpacing;

    // Parse image data to get rectangle sizes
    while ((lineSpacing + lineToRead * (charHeight + lineSpacing)) < image.height) {
        while ((xPosToRead < image.width) and
            !colorEqual(pixels[@intCast((lineSpacing + (charHeight + lineSpacing) * lineToRead) * image.width + xPosToRead)], key))
        {
            const ui: usize = @intCast(index);
            tempCharValues[ui] = firstChar + index;

            tempCharRecs[ui].x = @floatFromInt(xPosToRead);
            tempCharRecs[ui].y = @floatFromInt(lineSpacing + lineToRead * (charHeight + lineSpacing));
            tempCharRecs[ui].height = @floatFromInt(charHeight);

            var charWidth: c_int = 0;

            while (((xPosToRead + charWidth) < image.width) and
                !colorEqual(pixels[@intCast((lineSpacing + (charHeight + lineSpacing) * lineToRead) * image.width + xPosToRead + charWidth)], key)) charWidth += 1;

            tempCharRecs[ui].width = @floatFromInt(charWidth);

            index += 1;

            xPosToRead += (charWidth + charSpacing);
        }

        lineToRead += 1;
        xPosToRead = charSpacing;
    }

    // NOTE: Key color borders need to be removed from image to avoid weird artifacts
    {
        var i: c_int = 0;
        while (i < image.height * image.width) : (i += 1) {
            if (colorEqual(pixels[@intCast(i)], key)) pixels[@intCast(i)] = BLANK;
        }
    }

    // Create a new image with the processed color data (key color replaced by BLANK)
    const fontClear = Image{
        .data = pixels,
        .width = image.width,
        .height = image.height,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };

    // Set font with all data parsed from image
    font.texture = LoadTextureFromImage(fontClear); // Convert processed image to OpenGL texture
    font.glyphCount = index;
    font.glyphPadding = 0;

    // Move temp data to sized charValues and charRecs arrays
    font.glyphs = @ptrCast(@alignCast(RL_MALLOC(@intCast(font.glyphCount * @as(c_int, @sizeOf(GlyphInfo))))));
    font.recs = @ptrCast(@alignCast(RL_MALLOC(@intCast(font.glyphCount * @as(c_int, @sizeOf(Rectangle))))));

    var i: c_int = 0;
    while (i < font.glyphCount) : (i += 1) {
        const u: usize = @intCast(i);
        font.glyphs[u].value = tempCharValues[u];

        // Get character rectangle in the font atlas texture
        font.recs[u] = tempCharRecs[u];

        // NOTE: On image based fonts (XNA style), character offsets and xAdvance are not required (set to 0)
        font.glyphs[u].offsetX = 0;
        font.glyphs[u].offsetY = 0;
        font.glyphs[u].advanceX = 0;

        // Fill character image data from fontClear data
        font.glyphs[u].image = ImageFromImage(fontClear, tempCharRecs[u]);
    }

    UnloadImage(fontClear); // Unload processed image once converted to texture

    font.baseSize = @intFromFloat(font.recs[0].height);

    return font;
}

// Load font from memory buffer, fileType refers to extension: i.e. ".ttf"
export fn LoadFontFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: c_int, fontSize: c_int, codepoints: [*c]const c_int, codepointCount: c_int) callconv(.c) Font {
    var font: Font = std.mem.zeroes(Font);

    var fileExtLower = std.mem.zeroes([16]u8);
    _ = strncpy(&fileExtLower, TextToLower(fileType), 16 - 1);

    font.baseSize = fontSize;
    font.glyphPadding = 0;

    if (TextIsEqual(&fileExtLower, ".ttf") or TextIsEqual(&fileExtLower, ".otf")) {
        font.glyphs = LoadFontData(fileData, dataSize, font.baseSize, codepoints, if (codepointCount > 0) codepointCount else 95, FONT_DEFAULT, &font.glyphCount);
    } else {
        font.glyphs = null;
    }

    if (font.glyphs != null) {
        font.glyphPadding = FONT_TTF_DEFAULT_CHARS_PADDING;

        const atlas = GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, font.baseSize, font.glyphPadding, 0);
        font.texture = LoadTextureFromImage(atlas);

        // Update glyphs[i].image to use alpha, required to be used on ImageDrawText()
        var i: c_int = 0;
        while (i < font.glyphCount) : (i += 1) {
            const u: usize = @intCast(i);
            UnloadImage(font.glyphs[u].image);
            font.glyphs[u].image = ImageFromImage(atlas, font.recs[u]);
        }

        UnloadImage(atlas);

        TraceLog(LOG_INFO, "FONT: Data loaded successfully (%i pixel size | %i glyphs)", font.baseSize, font.glyphCount);
    } else {
        TraceLog(LOG_WARNING, "FONT: Font is not supported by LoadFontEx/LoadFontFromMemory or no glyphs found, reverted to default font");
        font = GetFontDefault();
    }

    return font;
}

// Check if font is valid (font data loaded)
export fn IsFontValid(font: Font) callconv(.c) bool {
    return ((font.baseSize > 0) and // Validate font size
        (font.glyphCount > 0) and // Validate font contains some glyph
        (font.recs != null) and // Validate font recs defining glyphs on texture atlas
        (font.glyphs != null)); // Validate glyph data is loaded
}

// Load font data for further use
// NOTE: Requires TTF font memory data and can generate SDF data
export fn LoadFontData(fileData: [*c]const u8, dataSize: c_int, fontSize: c_int, codepoints: [*c]const c_int, codepointCount_in: c_int, type_: c_int, glyphCount: [*c]c_int) callconv(.c) [*c]GlyphInfo {
    _ = dataSize;
    var codepointCount = codepointCount_in;

    var glyphs: [*c]GlyphInfo = null;
    var glyphCounter: c_int = 0;

    // Load font data (including pixel data) from TTF memory file
    if (fileData != null) {
        var genFontChars = false;
        const fontInfoBuf = RL_CALLOC(1, rl_sizeof_stbtt_fontinfo());
        const fontInfo: ?*anyopaque = fontInfoBuf;
        // NOTE: stbtt_fontinfo is a zeroed opaque buffer (was a local `= {0}` in C).

        // TODO: Should a shallow copy be created to avoid "dealing" with a const user array?
        var requiredCodepoints: [*c]c_int = @constCast(codepoints);

        if (stbtt_InitFont(fontInfo, fileData, 0) != 0) { // Initialize font for data reading
            // Calculate font scale factor
            const scaleFactor = stbtt_ScaleForPixelHeight(fontInfo, @floatFromInt(fontSize));

            // Calculate font basic metrics
            // NOTE: ascent is equivalent to font baseline
            var ascent: c_int = 0;
            var descent: c_int = 0;
            var lineGap: c_int = 0;
            stbtt_GetFontVMetrics(fontInfo, &ascent, &descent, &lineGap);

            // In case no chars count provided, default to 95
            codepointCount = if (codepointCount > 0) codepointCount else 95;

            // Fill fontChars in case not provided externally
            if (requiredCodepoints == null) {
                requiredCodepoints = @ptrCast(@alignCast(RL_MALLOC(@intCast(codepointCount * @as(c_int, @sizeOf(c_int))))));
                var i: c_int = 0;
                while (i < codepointCount) : (i += 1) requiredCodepoints[@intCast(i)] = i + 32;
                genFontChars = true;
            }

            // Check available glyphs on provided font before loading them
            {
                var i: c_int = 0;
                while (i < codepointCount) : (i += 1) {
                    const index = stbtt_FindGlyphIndex(fontInfo, requiredCodepoints[@intCast(i)]);
                    if (index > 0) glyphCounter += 1;
                }
            }

            // WARNING: Allocating space for maximum number of codepoints
            glyphs = @ptrCast(@alignCast(RL_CALLOC(@intCast(glyphCounter), @sizeOf(GlyphInfo))));
            glyphCounter = 0; // Reset to reuse

            var k: c_int = 0;
            var i: c_int = 0;
            while (i < codepointCount) : (i += 1) {
                var cpWidth: c_int = 0;
                var cpHeight: c_int = 0; // Codepoint width and height (on generation)
                const cp = requiredCodepoints[@intCast(i)]; // Codepoint value to get info for

                // Check if glyph is available in the font
                const index = stbtt_FindGlyphIndex(fontInfo, cp);

                if (index > 0) {
                    const uk: usize = @intCast(k);
                    // NOTE: Only storing glyphs for codepoints found in the font
                    glyphs[uk].value = cp;

                    switch (type_) {
                        FONT_DEFAULT, FONT_BITMAP => {
                            glyphs[uk].image.data = stbtt_GetCodepointBitmap(fontInfo, scaleFactor, scaleFactor, cp, &cpWidth, &cpHeight, &glyphs[uk].offsetX, &glyphs[uk].offsetY);
                        },
                        // FONT_SDF path requires stbtt_GetCodepointSDF; not exercised in this build.
                        else => {},
                    }

                    if (glyphs[uk].image.data != null) { // Glyph data has been found in the font
                        stbtt_GetCodepointHMetrics(fontInfo, cp, &glyphs[uk].advanceX, null);
                        glyphs[uk].advanceX = @intFromFloat(@as(f32, @floatFromInt(glyphs[uk].advanceX)) * scaleFactor);

                        if ((type_ != FONT_SDF) and (cpHeight > fontSize)) TraceLog(LOG_WARNING, "FONT: [0x%04x] Glyph height is bigger than requested font size: %i > %i", cp, cpHeight, fontSize);

                        // Load glyph image
                        glyphs[uk].image.width = cpWidth;
                        glyphs[uk].image.height = cpHeight;
                        glyphs[uk].image.mipmaps = 1;
                        glyphs[uk].image.format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE;

                        glyphs[uk].offsetY += @intFromFloat(@as(f32, @floatFromInt(ascent)) * scaleFactor);
                    }

                    // Create an empty image for Space character (0x20), useful for sprite font generation
                    if ((cp == 0x20) or (cp == 0x3000)) {
                        stbtt_GetCodepointHMetrics(fontInfo, cp, &glyphs[uk].advanceX, null);
                        glyphs[uk].advanceX = @intFromFloat(@as(f32, @floatFromInt(glyphs[uk].advanceX)) * scaleFactor);

                        var imSpace = Image{
                            .data = null,
                            .width = glyphs[uk].advanceX,
                            .height = fontSize,
                            .mipmaps = 1,
                            .format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
                        };

                        // Only allocate space image if required
                        if (glyphs[uk].advanceX > 0) imSpace.data = RL_CALLOC(@intCast(glyphs[uk].advanceX * fontSize), 1) else glyphs[uk].advanceX = 0;

                        glyphs[uk].image = imSpace;
                    }

                    if (type_ == FONT_BITMAP) {
                        // Aliased bitmap (black & white) font generation, avoiding anti-aliasing
                        const data8: [*]u8 = @ptrCast(glyphs[uk].image.data);
                        var p: c_int = 0;
                        while (p < cpWidth * cpHeight) : (p += 1) {
                            const up: usize = @intCast(p);
                            if (data8[up] < FONT_BITMAP_ALPHA_THRESHOLD) data8[up] = 0 else data8[up] = 255;
                        }
                    }

                    k += 1;
                    glyphCounter += 1;
                } else {
                    // WARNING: Glyph not found on font, optionally use a fallback glyph
                }
            }

            if (glyphCounter < codepointCount) TraceLog(LOG_WARNING, "FONT: Requested codepoints glyphs found: [%i/%i]", k, codepointCount);
        } else TraceLog(LOG_WARNING, "FONT: Failed to process TTF font data");

        if (genFontChars) RL_FREE(requiredCodepoints);
        RL_FREE(fontInfoBuf);
    }

    glyphCount.* = glyphCounter;
    return glyphs;
}

// Generate image font atlas using chars info
// NOTE: Packing method: 0-Default, 1-Skyline
export fn GenImageFontAtlas(glyphs: [*c]const GlyphInfo, glyphRecs: [*c][*c]Rectangle, glyphCount_in: c_int, fontSize: c_int, padding: c_int, packMethod: c_int) callconv(.c) Image {
    var atlas: Image = std.mem.zeroes(Image);

    if (glyphs == null) {
        TraceLog(LOG_WARNING, "FONT: Provided glyphs info not valid, returning empty image atlas");
        return atlas;
    }

    glyphRecs.* = null;

    // In case no chars count provided, suppose default of 95
    const glyphCount = if (glyphCount_in > 0) glyphCount_in else 95;

    // NOTE: Rectangles memory is loaded here!
    const recs: [*c]Rectangle = @ptrCast(@alignCast(RL_MALLOC(@intCast(glyphCount * @as(c_int, @sizeOf(Rectangle))))));

    // Calculate image size based on total glyph width and glyph row count
    var totalWidth: c_int = 0;
    var maxGlyphWidth: c_int = 0;

    {
        var i: c_int = 0;
        while (i < glyphCount) : (i += 1) {
            const u: usize = @intCast(i);
            if (glyphs[u].image.width > maxGlyphWidth) maxGlyphWidth = glyphs[u].image.width;
            totalWidth += glyphs[u].image.width + 2 * padding;
        }
    }

    const paddedFontSize = fontSize + 2 * padding;

    // Estimate image atlas size from available data
    const totalArea: f32 = @as(f32, @floatFromInt(totalWidth * paddedFontSize)) * 1.2;
    const imageMinSize = sqrtf(totalArea);
    const imageSize: c_int = @intFromFloat(powf(2, ceilf(logf(imageMinSize) / logf(2))));

    if (totalArea < @as(f32, @floatFromInt(@divTrunc(imageSize * imageSize, 2)))) {
        atlas.width = imageSize; // Atlas bitmap width
        atlas.height = @divTrunc(imageSize, 2); // Atlas bitmap height
    } else {
        atlas.width = imageSize; // Atlas bitmap width
        atlas.height = imageSize; // Atlas bitmap height
    }

    var atlasDataSize = atlas.width * atlas.height; // Save total size for bounds checking
    atlas.data = RL_CALLOC(@intCast(atlasDataSize), 1); // Create a bitmap to store characters (8 bpp)
    atlas.format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE;
    atlas.mipmaps = 1;

    if (packMethod == 0) { // Use basic packing algorithm
        var offsetX: c_int = padding;
        var offsetY: c_int = padding;

        // NOTE: Using simple packaging, one char after another
        var i: c_int = 0;
        while (i < glyphCount) : (i += 1) {
            const u: usize = @intCast(i);
            // Check remaining space for glyph
            if (offsetX >= (atlas.width - glyphs[u].image.width - 2 * padding)) {
                offsetX = padding;

                offsetY += (fontSize + 2 * padding);

                if (offsetY > (atlas.height - fontSize - padding)) {
                    TraceLog(LOG_WARNING, "FONT: Updating atlas size to fit all characters");

                    // Update atlas size to fit all characters
                    const updatedAtlasHeight = atlas.height * 2;
                    const updatedAtlasDataSize = atlas.width * updatedAtlasHeight;
                    const updatedAtlasData = RL_CALLOC(@intCast(updatedAtlasDataSize), 1);

                    _ = memcpy(updatedAtlasData, atlas.data, @intCast(atlasDataSize));
                    RL_FREE(atlas.data);
                    atlas.data = updatedAtlasData;
                    atlas.height = updatedAtlasHeight;
                    atlasDataSize = updatedAtlasDataSize;
                }
            }

            // Copy pixel data from glyph image to atlas
            const atlasData: [*]u8 = @ptrCast(atlas.data);
            const glyphData: [*]const u8 = @ptrCast(glyphs[u].image.data);
            var yy: c_int = 0;
            while (yy < glyphs[u].image.height) : (yy += 1) {
                var xx: c_int = 0;
                while (xx < glyphs[u].image.width) : (xx += 1) {
                    const destX = offsetX + xx;
                    const destY = offsetY + yy;

                    // Security: check both lower and upper bounds
                    if ((destX >= 0) and (destX < atlas.width) and (destY >= 0) and (destY < atlas.height)) {
                        atlasData[@intCast(destY * atlas.width + destX)] =
                            glyphData[@intCast(yy * glyphs[u].image.width + xx)];
                    }
                }
            }

            // Fill chars rectangles in atlas info
            recs[u].x = @floatFromInt(offsetX);
            recs[u].y = @floatFromInt(offsetY);
            recs[u].width = @floatFromInt(glyphs[u].image.width);
            recs[u].height = @floatFromInt(glyphs[u].image.height);

            // Move atlas position X for next character drawing
            offsetX += (glyphs[u].image.width + 2 * padding);
        }
    } else if (packMethod == 1) { // Use Skyline rect packing algorithm (stb_pack_rect)
        const context = RL_MALLOC(rl_sizeof_stbrp_context());
        const nodes = RL_MALLOC(@as(usize, @intCast(glyphCount)) * rl_sizeof_stbrp_node());

        stbrp_init_target(context, atlas.width, atlas.height, nodes, glyphCount);
        const rects: [*c]stbrp_rect = @ptrCast(@alignCast(RL_MALLOC(@as(usize, @intCast(glyphCount)) * @sizeOf(stbrp_rect))));

        // Fill rectangles for packaging
        {
            var i: c_int = 0;
            while (i < glyphCount) : (i += 1) {
                const u: usize = @intCast(i);
                rects[u].id = i;
                rects[u].w = glyphs[u].image.width + 2 * padding;
                rects[u].h = glyphs[u].image.height + 2 * padding;
            }
        }

        // Package rectangles into atlas
        _ = stbrp_pack_rects(context, rects, glyphCount);

        const atlasData: [*]u8 = @ptrCast(atlas.data);
        var i: c_int = 0;
        while (i < glyphCount) : (i += 1) {
            const u: usize = @intCast(i);
            // It returns char rectangles in atlas
            recs[u].x = @as(f32, @floatFromInt(rects[u].x)) + @as(f32, @floatFromInt(padding));
            recs[u].y = @as(f32, @floatFromInt(rects[u].y)) + @as(f32, @floatFromInt(padding));
            recs[u].width = @floatFromInt(glyphs[u].image.width);
            recs[u].height = @floatFromInt(glyphs[u].image.height);

            if (rects[u].was_packed != 0) {
                // Copy pixel data from fc.data to atlas
                const glyphData: [*]const u8 = @ptrCast(glyphs[u].image.data);
                var yy: c_int = 0;
                while (yy < glyphs[u].image.height) : (yy += 1) {
                    var xx: c_int = 0;
                    while (xx < glyphs[u].image.width) : (xx += 1) {
                        const destX = rects[u].x + padding + xx;
                        const destY = rects[u].y + padding + yy;

                        if (destX >= 0 and destX < atlas.width and destY >= 0 and destY < atlas.height) {
                            atlasData[@intCast(destY * atlas.width + destX)] =
                                glyphData[@intCast(yy * glyphs[u].image.width + xx)];
                        }
                    }
                }
            } else TraceLog(LOG_WARNING, "FONT: Failed to package glyph (0x%02x)", glyphs[u].value);
        }

        RL_FREE(rects);
        RL_FREE(nodes);
        RL_FREE(context);
    }

    // Add a 3x3 white rectangle at the bottom-right corner of the generated atlas
    if ((FONT_ATLAS_CORNER_REC_SIZE > 0) and (atlas.width >= 3) and (atlas.height >= 3)) {
        const atlasData: [*]u8 = @ptrCast(atlas.data);
        var i: c_int = 0;
        var k: c_int = atlas.width * atlas.height - 1;
        while (i < FONT_ATLAS_CORNER_REC_SIZE) : (i += 1) {
            atlasData[@intCast(k - 0)] = 255;
            atlasData[@intCast(k - 1)] = 255;
            atlasData[@intCast(k - 2)] = 255;
            k -= atlas.width;
        }
    }

    // Convert image data from GRAYSCALE to GRAY_ALPHA
    const dataGrayAlpha: [*]u8 = @ptrCast(RL_MALLOC(@intCast(atlas.width * atlas.height * @as(c_int, @sizeOf(u8)) * 2)));

    {
        const atlasData: [*]const u8 = @ptrCast(atlas.data);
        var i: c_int = 0;
        var k: c_int = 0;
        while (i < atlas.width * atlas.height) : ({
            i += 1;
            k += 2;
        }) {
            dataGrayAlpha[@intCast(k)] = 255;
            dataGrayAlpha[@intCast(k + 1)] = atlasData[@intCast(i)];
        }
    }

    RL_FREE(atlas.data);
    atlas.data = dataGrayAlpha;
    atlas.format = PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA;

    glyphRecs.* = recs;

    return atlas;
}

// Unload font glyphs info data (RAM)
export fn UnloadFontData(glyphs: [*c]GlyphInfo, glyphCount: c_int) callconv(.c) void {
    if (glyphs != null) {
        var i: c_int = 0;
        while (i < glyphCount) : (i += 1) UnloadImage(glyphs[@intCast(i)].image);

        RL_FREE(glyphs);
    }
}

// Unload Font from GPU memory (VRAM)
export fn UnloadFont(font: Font) callconv(.c) void {
    // NOTE: Make sure font is not default font (fallback)
    if (font.texture.id != GetFontDefault().texture.id) {
        UnloadFontData(font.glyphs, font.glyphCount);
        UnloadTexture(font.texture);
        RL_FREE(font.recs);

        TraceLog(LOG_DEBUG, "FONT: Unloaded font data from RAM and VRAM");
    }
}

// Export font as code file, returns true on success
export fn ExportFontAsCode(font: Font, fileName: [*c]const u8) callconv(.c) bool {
    var result = false;

    // Get file name from path
    var fileNamePascal = std.mem.zeroes([256]u8);
    _ = strncpy(&fileNamePascal, TextToPascal(GetFileNameWithoutExt(fileName)), 256 - 1);

    // Get font atlas image and size, required to estimate code file size
    const image = LoadImageFromTexture(font.texture);
    if (image.format != PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA) TraceLog(LOG_WARNING, "Font export as code: Font image format is not GRAY+ALPHA!");
    const imageDataSize = GetPixelDataSize(image.width, image.height, image.format);

    // Estimate text code size
    const txtDataSize = imageDataSize * 6 + font.glyphCount * 64 + font.glyphCount * 64 + 32768;
    const txtData: [*c]u8 = @ptrCast(RL_CALLOC(@intCast(txtDataSize), @sizeOf(u8)));

    var byteCount: c_int = 0;
    byteCount += sprintf(ptrAdd(txtData, byteCount), "////////////////////////////////////////////////////////////////////////////////////////\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "//                                                                                    //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// FontAsCode exporter v1.0 - Font data exported as an array of bytes                 //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "//                                                                                    //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// more info and bugs-report:  github.com/raysan5/raylib                              //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// feedback and support:       ray[at]raylib.com                                      //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "//                                                                                    //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// Copyright (c) 2018-2026 Ramon Santamaria (@raysan5)                                //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "//                                                                                    //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// ---------------------------------------------------------------------------------- //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "//                                                                                    //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// TODO: Fill the information and license of the exported font here:                  //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "//                                                                                    //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// Font name:    ....                                                                 //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// Font creator: ....                                                                 //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// Font LICENSE: ....                                                                 //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "//                                                                                    //\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "////////////////////////////////////////////////////////////////////////////////////////\n\n");

    // WARNING: Data is compressed using raylib CompressData() DEFLATE
    // Compress font image data
    var compDataSize: c_int = 0;
    const compData = CompressData(@ptrCast(image.data), imageDataSize, &compDataSize);

    // Save font image data (compressed)
    byteCount += sprintf(ptrAdd(txtData, byteCount), "#define COMPRESSED_DATA_SIZE_FONT_%s %i\n\n", TextToUpper(&fileNamePascal), compDataSize);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// Font image pixels data compressed (DEFLATE)\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// NOTE: Original pixel data simplified to GRAYSCALE\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "static unsigned char fontData_%s[COMPRESSED_DATA_SIZE_FONT_%s] = { ", &fileNamePascal, TextToUpper(&fileNamePascal));
    {
        var i: c_int = 0;
        while (i < compDataSize - 1) : (i += 1) {
            byteCount += sprintf(ptrAdd(txtData, byteCount), if (@rem(i, TEXT_BYTES_PER_LINE) == 0) "0x%02x,\n    " else "0x%02x, ", compData[@intCast(i)]);
        }
    }
    byteCount += sprintf(ptrAdd(txtData, byteCount), "0x%02x };\n\n", compData[@intCast(compDataSize - 1)]);
    RL_FREE(compData);

    // Save font recs data
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// Font characters rectangles data\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "static Rectangle fontRecs_%s[%i] = {\n", &fileNamePascal, font.glyphCount);
    {
        var i: c_int = 0;
        while (i < font.glyphCount) : (i += 1) {
            const u: usize = @intCast(i);
            byteCount += sprintf(ptrAdd(txtData, byteCount), "    { %1.0f, %1.0f, %1.0f , %1.0f },\n", @as(f64, font.recs[u].x), @as(f64, font.recs[u].y), @as(f64, font.recs[u].width), @as(f64, font.recs[u].height));
        }
    }
    byteCount += sprintf(ptrAdd(txtData, byteCount), "};\n\n");

    // Save font glyphs data
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// Font glyphs info data\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// NOTE: No glyphs.image data provided\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "static GlyphInfo fontGlyphs_%s[%i] = {\n", &fileNamePascal, font.glyphCount);
    {
        var i: c_int = 0;
        while (i < font.glyphCount) : (i += 1) {
            const u: usize = @intCast(i);
            byteCount += sprintf(ptrAdd(txtData, byteCount), "    { %i, %i, %i, %i, { 0 }},\n", font.glyphs[u].value, font.glyphs[u].offsetX, font.glyphs[u].offsetY, font.glyphs[u].advanceX);
        }
    }
    byteCount += sprintf(ptrAdd(txtData, byteCount), "};\n\n");

    // Custom font loading function
    byteCount += sprintf(ptrAdd(txtData, byteCount), "// Font loading function: %s\n", &fileNamePascal);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "static Font LoadFont_%s(void)\n{\n", &fileNamePascal);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    Font font = { 0 };\n\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    font.baseSize = %i;\n", font.baseSize);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    font.glyphCount = %i;\n", font.glyphCount);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    font.glyphPadding = %i;\n\n", font.glyphPadding);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    // Custom font loading\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    // NOTE: Compressed font image data (DEFLATE), it requires DecompressData() function\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    int fontDataSize_%s = 0;\n", &fileNamePascal);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    unsigned char *data = DecompressData(fontData_%s, COMPRESSED_DATA_SIZE_FONT_%s, &fontDataSize_%s);\n", &fileNamePascal, TextToUpper(&fileNamePascal), &fileNamePascal);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    Image imFont = { data, %i, %i, 1, %i };\n\n", image.width, image.height, image.format);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    // Load texture from image\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    font.texture = LoadTextureFromImage(imFont);\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    UnloadImage(imFont);  // Uncompressed data can be unloaded from memory\n\n");

    byteCount += sprintf(ptrAdd(txtData, byteCount), "    // Assign glyph recs and info data directly\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    // WARNING: This font data must not be unloaded\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    font.recs = fontRecs_%s;\n", &fileNamePascal);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    font.glyphs = fontGlyphs_%s;\n\n", &fileNamePascal);
    byteCount += sprintf(ptrAdd(txtData, byteCount), "    return font;\n");
    byteCount += sprintf(ptrAdd(txtData, byteCount), "}\n");

    UnloadImage(image);

    // NOTE: Text data size exported is determined by '\0' (NULL) character
    result = SaveFileText(fileName, txtData);

    RL_FREE(txtData);

    if (result != false) TraceLog(LOG_INFO, "FILEIO: [%s] Font as code exported successfully", fileName) else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export font as code", fileName);

    return result;
}

// Draw current FPS
export fn DrawFPS(posX: c_int, posY: c_int) callconv(.c) void {
    var color = LIME; // Good FPS
    const fps = GetFPS();

    if ((fps < 30) and (fps >= 15)) color = ORANGE // Warning FPS
    else if (fps < 15) color = RED; // Low FPS

    DrawText(TextFormat("%2i FPS", fps), posX, posY, 20, color);
}

// Draw text (using default font)
export fn DrawText(text: [*c]const u8, posX: c_int, posY: c_int, fontSize_in: c_int, color: Color) callconv(.c) void {
    // Check if default font has been loaded
    if (GetFontDefault().texture.id != 0) {
        const position = Vector2{ .x = @floatFromInt(posX), .y = @floatFromInt(posY) };

        const defaultFontSize: c_int = 10; // Default Font chars height in pixel
        var fontSize = fontSize_in;
        if (fontSize < defaultFontSize) fontSize = defaultFontSize;
        const spacing = @divTrunc(fontSize, defaultFontSize);

        DrawTextEx(GetFontDefault(), text, position, @floatFromInt(fontSize), @floatFromInt(spacing), color);
    }
}

// Draw text using Font
export fn DrawTextEx(font_in: Font, text: [*c]const u8, position: Vector2, fontSize: f32, spacing: f32, tint: Color) callconv(.c) void {
    var font = font_in;
    if (font.texture.id == 0) font = GetFontDefault(); // Security check in case of not valid font

    const size: c_int = @intCast(TextLength(text)); // Total size in bytes of the text, scanned by codepoints in loop

    var textOffsetY: f32 = 0; // Offset between lines (on linebreak '\n')
    var textOffsetX: f32 = 0.0; // Offset X to next character to draw

    const scaleFactor = fontSize / @as(f32, @floatFromInt(font.baseSize)); // Character quad scaling factor

    var i: c_int = 0;
    while (i < size) {
        // Get next codepoint from byte string and glyph index in font
        var codepointByteCount: c_int = 0;
        const codepoint = GetCodepointNext(ptrAdd(text, i), &codepointByteCount);
        const index = GetGlyphIndex(font, codepoint);

        if (codepoint == '\n') {
            // NOTE: Line spacing is a global variable, use SetTextLineSpacing() to setup
            textOffsetY += (fontSize + @as(f32, @floatFromInt(textLineSpacing)));
            textOffsetX = 0.0;
        } else {
            if ((codepoint != ' ') and (codepoint != '\t')) {
                DrawTextCodepoint(font, codepoint, .{ .x = position.x + textOffsetX, .y = position.y + textOffsetY }, fontSize, tint);
            }

            const u: usize = @intCast(index);
            if (font.glyphs[u].advanceX == 0) textOffsetX += (@as(f32, @floatFromInt(@as(c_int, @intFromFloat(font.recs[u].width)))) * scaleFactor + spacing) else textOffsetX += (@as(f32, @floatFromInt(font.glyphs[u].advanceX)) * scaleFactor + spacing);
        }

        i += codepointByteCount; // Move text bytes counter to next codepoint
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
    const index = GetGlyphIndex(font, codepoint);
    const u: usize = @intCast(index);
    const scaleFactor = fontSize / @as(f32, @floatFromInt(font.baseSize)); // Character quad scaling factor

    // Character destination rectangle on screen
    const dstRec = Rectangle{
        .x = position.x + @as(f32, @floatFromInt(font.glyphs[u].offsetX)) * scaleFactor - @as(f32, @floatFromInt(font.glyphPadding)) * scaleFactor,
        .y = position.y + @as(f32, @floatFromInt(font.glyphs[u].offsetY)) * scaleFactor - @as(f32, @floatFromInt(font.glyphPadding)) * scaleFactor,
        .width = (font.recs[u].width + 2.0 * @as(f32, @floatFromInt(font.glyphPadding))) * scaleFactor,
        .height = (font.recs[u].height + 2.0 * @as(f32, @floatFromInt(font.glyphPadding))) * scaleFactor,
    };

    // Character source rectangle from font texture atlas
    const srcRec = Rectangle{
        .x = font.recs[u].x - @as(f32, @floatFromInt(font.glyphPadding)),
        .y = font.recs[u].y - @as(f32, @floatFromInt(font.glyphPadding)),
        .width = font.recs[u].width + 2.0 * @as(f32, @floatFromInt(font.glyphPadding)),
        .height = font.recs[u].height + 2.0 * @as(f32, @floatFromInt(font.glyphPadding)),
    };

    // Draw the character texture on the screen
    DrawTexturePro(font.texture, srcRec, dstRec, .{ .x = 0, .y = 0 }, 0.0, tint);
}

// Draw multiple characters (codepoints)
export fn DrawTextCodepoints(font: Font, codepoints: [*c]const c_int, codepointCount: c_int, position: Vector2, fontSize: f32, spacing: f32, tint: Color) callconv(.c) void {
    var textOffsetY: f32 = 0; // Offset between lines (on linebreak '\n')
    var textOffsetX: f32 = 0.0; // Offset X to next character to draw

    const scaleFactor = fontSize / @as(f32, @floatFromInt(font.baseSize)); // Character quad scaling factor

    var i: c_int = 0;
    while (i < codepointCount) : (i += 1) {
        const ui: usize = @intCast(i);
        const index = GetGlyphIndex(font, codepoints[ui]);

        if (codepoints[ui] == '\n') {
            // NOTE: Line spacing is a global variable, use SetTextLineSpacing() to setup
            textOffsetY += (fontSize + @as(f32, @floatFromInt(textLineSpacing)));
            textOffsetX = 0.0;
        } else {
            if ((codepoints[ui] != ' ') and (codepoints[ui] != '\t')) {
                DrawTextCodepoint(font, codepoints[ui], .{ .x = position.x + textOffsetX, .y = position.y + textOffsetY }, fontSize, tint);
            }

            const u: usize = @intCast(index);
            if (font.glyphs[u].advanceX == 0) textOffsetX += (@as(f32, @floatFromInt(@as(c_int, @intFromFloat(font.recs[u].width)))) * scaleFactor + spacing) else textOffsetX += (@as(f32, @floatFromInt(font.glyphs[u].advanceX)) * scaleFactor + spacing);
        }
    }
}

// Set vertical line spacing when drawing with line-breaks
export fn SetTextLineSpacing(spacing: c_int) callconv(.c) void {
    textLineSpacing = spacing;
}

// Measure string width for default font
export fn MeasureText(text: [*c]const u8, fontSize_in: c_int) callconv(.c) c_int {
    var textSize = Vector2{ .x = 0.0, .y = 0.0 };

    // Check if default font has been loaded
    if (GetFontDefault().texture.id != 0) {
        const defaultFontSize: c_int = 10; // Default Font glyphs height in pixel
        var fontSize = fontSize_in;
        if (fontSize < defaultFontSize) fontSize = defaultFontSize;
        const spacing = @divTrunc(fontSize, defaultFontSize);

        textSize = MeasureTextEx(GetFontDefault(), text, @floatFromInt(fontSize), @floatFromInt(spacing));
    }

    return @intFromFloat(textSize.x);
}

// Measure string size for Font
export fn MeasureTextEx(font: Font, text: [*c]const u8, fontSize: f32, spacing: f32) callconv(.c) Vector2 {
    var textSize: Vector2 = std.mem.zeroes(Vector2);

    if ((font.texture.id == 0) or (text == null) or (text[0] == 0)) return textSize; // Security check

    const size: c_int = @intCast(TextLength(text)); // Get size in bytes of text
    var tempByteCounter: c_int = 0; // Used to count longer text line num chars
    var byteCounter: c_int = 0;

    var textWidth: f32 = 0.0;
    var tempTextWidth: f32 = 0.0; // Used to count longer text line width

    var textHeight = fontSize;
    const scaleFactor = fontSize / @as(f32, @floatFromInt(font.baseSize));

    var letter: c_int = 0; // Current character
    var index: c_int = 0; // Index position in sprite font

    var i: c_int = 0;
    while (i < size) {
        byteCounter += 1;

        var codepointByteCount: c_int = 0;
        letter = GetCodepointNext(ptrAdd(text, i), &codepointByteCount);
        index = GetGlyphIndex(font, letter);

        i += codepointByteCount;

        if (letter != '\n') {
            const u: usize = @intCast(index);
            if (font.glyphs[u].advanceX > 0) textWidth += @floatFromInt(font.glyphs[u].advanceX) else textWidth += (font.recs[u].width + @as(f32, @floatFromInt(font.glyphs[u].offsetX)));
        } else {
            if (tempTextWidth < textWidth) tempTextWidth = textWidth;
            byteCounter = 0;
            textWidth = 0;

            // NOTE: Line spacing is a global variable, use SetTextLineSpacing() to setup
            textHeight += (fontSize + @as(f32, @floatFromInt(textLineSpacing)));
        }

        if (tempByteCounter < byteCounter) tempByteCounter = byteCounter;
    }

    if (tempTextWidth < textWidth) tempTextWidth = textWidth;

    textSize.x = tempTextWidth * scaleFactor + @as(f32, @floatFromInt((tempByteCounter - 1) * @as(c_int, @intFromFloat(spacing))));
    textSize.y = textHeight;

    return textSize;
}

// Measure string size for an existing array of codepoints for Font
export fn MeasureTextCodepoints(font: Font, codepoints: [*c]const c_int, length: c_int, fontSize: f32, spacing: f32) callconv(.c) Vector2 {
    var textSize: Vector2 = std.mem.zeroes(Vector2);

    if ((font.texture.id == 0) or (codepoints == null) or (length == 0)) return textSize; // Security check

    var textWidth: f32 = 0.0;
    var tempTextWidth: f32 = 0.0; // Used to count longer text line width

    var tempGlyphCounter: c_int = 0; // Used to count longer text line num chars
    var glyphCounter: c_int = 0;

    var textHeight = fontSize;
    const scaleFactor = fontSize / @as(f32, @floatFromInt(font.baseSize));

    var letter: c_int = 0; // Current character
    var index: c_int = 0; // Index position in sprite font

    var i: c_int = 0;
    while (i < length) : (i += 1) {
        letter = codepoints[@intCast(i)];
        index = GetGlyphIndex(font, letter);

        if (letter != '\n') {
            glyphCounter += 1;

            const u: usize = @intCast(index);
            if (font.glyphs[u].advanceX > 0) textWidth += @floatFromInt(font.glyphs[u].advanceX) else textWidth += (font.recs[u].width + @as(f32, @floatFromInt(font.glyphs[u].offsetX)));
        } else {
            if (tempTextWidth < textWidth) tempTextWidth = textWidth;

            textWidth = 0;
            glyphCounter = 0;

            // NOTE: Line spacing is a global variable, use SetTextLineSpacing() to setup
            textHeight += (fontSize + @as(f32, @floatFromInt(textLineSpacing)));
        }

        if (tempGlyphCounter < glyphCounter) tempGlyphCounter = glyphCounter;
    }

    if (tempTextWidth < textWidth) tempTextWidth = textWidth;

    textSize.x = tempTextWidth * scaleFactor + @as(f32, @floatFromInt((tempGlyphCounter - 1) * @as(c_int, @intFromFloat(spacing))));
    textSize.y = textHeight;

    return textSize;
}

// Get index position for a unicode character on font
export fn GetGlyphIndex(font: Font, codepoint: c_int) callconv(.c) c_int {
    var index: c_int = 0;
    if (!IsFontValid(font)) return index;

    var fallbackIndex: c_int = 0; // Get index of fallback glyph '?'

    // Look for character index in the unordered charset
    var i: c_int = 0;
    while (i < font.glyphCount) : (i += 1) {
        const u: usize = @intCast(i);
        if (font.glyphs[u].value == 63) fallbackIndex = i;

        if (font.glyphs[u].value == codepoint) {
            index = i;
            break;
        }
    }

    if ((index == 0) and (font.glyphs[0].value != codepoint)) index = fallbackIndex;

    return index;
}

// Get glyph font info data for a codepoint (unicode character)
export fn GetGlyphInfo(font: Font, codepoint: c_int) callconv(.c) GlyphInfo {
    var info: GlyphInfo = std.mem.zeroes(GlyphInfo);

    info = font.glyphs[@intCast(GetGlyphIndex(font, codepoint))];

    return info;
}

// Get glyph rectangle in font atlas for a codepoint (unicode character)
export fn GetGlyphAtlasRec(font: Font, codepoint: c_int) callconv(.c) Rectangle {
    var rec: Rectangle = std.mem.zeroes(Rectangle);

    rec = font.recs[@intCast(GetGlyphIndex(font, codepoint))];

    return rec;
}

//----------------------------------------------------------------------------------
// Text strings management functions
//----------------------------------------------------------------------------------
// Load text as separate lines ('\n')
export fn LoadTextLines(text: [*c]const u8, count: [*c]c_int) callconv(.c) [*c][*c]u8 {
    var lines: [*c][*c]u8 = null;
    var lineCount: c_int = 0;

    if (text != null) {
        const textLength: c_int = @intCast(TextLength(text));
        lineCount = 1;

        // First text scan pass to get required line count
        var i: c_int = 0;
        while (i < textLength) : (i += 1) {
            if (text[@intCast(i)] == '\n') lineCount += 1;
        }

        lines = @ptrCast(@alignCast(RL_CALLOC(@intCast(lineCount), @sizeOf([*c]u8))));
        var l: c_int = 0;
        var lineLen: c_int = 0;
        i = 0;
        while (i <= textLength) : (i += 1) {
            if ((text[@intCast(i)] == '\n') or (text[@intCast(i)] == '\x00')) {
                lines[@intCast(l)] = @ptrCast(RL_CALLOC(@intCast(lineLen + 1), 1));
                _ = strncpy(lines[@intCast(l)], ptrAdd(text, i - lineLen), @intCast(lineLen));
                lineLen = 0;
                l += 1;
            } else lineLen += 1;
        }
    }

    count.* = lineCount;
    return lines;
}

// Unload text lines
export fn UnloadTextLines(lines: [*c][*c]u8, lineCount: c_int) callconv(.c) void {
    var i: c_int = 0;
    while (i < lineCount) : (i += 1) RL_FREE(lines[@intCast(i)]);
    RL_FREE(lines);
}

// Get text length in bytes, check for \0 character
export fn TextLength(text: [*c]const u8) callconv(.c) c_uint {
    var length: c_uint = 0;

    if (text != null) {
        while (text[length] != '\x00') length += 1;
    }

    return length;
}

// Formatting of text with variables to 'embed'
export fn TextFormat(text: [*c]const u8, ...) callconv(.c) [*c]const u8 {
    // Create an array of buffers so strings don't expire until MAX_TEXTFORMAT_BUFFERS invocations
    const S = struct {
        var buffers: [MAX_TEXTFORMAT_BUFFERS][MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXTFORMAT_BUFFERS][MAX_TEXT_BUFFER_LENGTH]u8);
        var index: usize = 0;
    };

    const currentBuffer: [*c]u8 = &S.buffers[S.index];
    _ = memset(currentBuffer, 0, MAX_TEXT_BUFFER_LENGTH); // Clear buffer before using

    if (text != null) {
        var args = @cVaStart();
        const requiredByteCount = vsnprintf(currentBuffer, MAX_TEXT_BUFFER_LENGTH, text, &args);
        @cVaEnd(&args);

        // If requiredByteCount is larger than the MAX_TEXT_BUFFER_LENGTH, then overflow occurred
        if (requiredByteCount >= MAX_TEXT_BUFFER_LENGTH) {
            // Inserting "..." at the end of the string to mark as truncated
            const truncBuffer: [*c]u8 = ptrAdd(@as([*c]u8, &S.buffers[S.index]), MAX_TEXT_BUFFER_LENGTH - 4); // Adding 4 bytes = "...\0"
            _ = snprintf(truncBuffer, 4, "...");
        }

        S.index += 1; // Move to next buffer for next function call
        if (S.index >= MAX_TEXTFORMAT_BUFFERS) S.index = 0;
    }

    return currentBuffer;
}

// Get integer value from text
export fn TextToInteger(text_in: [*c]const u8) callconv(.c) c_int {
    var text = text_in;
    var value: c_int = 0;
    var sign: c_int = 1;

    if (text != null) {
        if ((text[0] == '+') or (text[0] == '-')) {
            if (text[0] == '-') sign = -1;
            text += 1;
        }

        var i: usize = 0;
        while ((text[i] >= '0') and (text[i] <= '9')) : (i += 1) value = value * 10 + @as(c_int, @intCast(text[i] - '0'));
    }

    return value * sign;
}

// Get float value from text
export fn TextToFloat(text_in: [*c]const u8) callconv(.c) f32 {
    var text = text_in;
    var value: f32 = 0.0;
    var sign: f32 = 1.0;

    if (text != null) {
        if ((text[0] == '+') or (text[0] == '-')) {
            if (text[0] == '-') sign = -1.0;
            text += 1;
        }

        var i: usize = 0;
        while ((text[i] >= '0') and (text[i] <= '9')) : (i += 1) value = value * 10.0 + @as(f32, @floatFromInt(text[i] - '0'));

        const after = text[i];
        i += 1;
        if (after == '.') {
            var divisor: f32 = 10.0;
            while ((text[i] >= '0') and (text[i] <= '9')) : (i += 1) {
                value += @as(f32, @floatFromInt(text[i] - '0')) / divisor;
                divisor = divisor * 10.0;
            }
        }
    }

    return value * sign;
}

// Copy one string to another, returns bytes copied
export fn TextCopy(dst: [*c]u8, src_in: [*c]const u8) callconv(.c) c_int {
    var src = src_in;
    var dstp = dst;
    var bytes: c_int = 0;

    if ((src != null) and (dstp != null)) {
        while (src.* != '\x00') {
            dstp.* = src.*;
            dstp += 1;
            src += 1;

            bytes += 1;
        }

        dstp.* = '\x00';
    }

    return bytes;
}

// Check if two text strings are equal
export fn TextIsEqual(text1: [*c]const u8, text2: [*c]const u8) callconv(.c) bool {
    var result = false;

    if ((text1 != null) and (text2 != null)) {
        if (strcmp(text1, text2) == 0) result = true;
    }

    return result;
}

// Get a piece of a text string
export fn TextSubtext(text: [*c]const u8, position: c_int, length_in: c_int) callconv(.c) [*c]const u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    var length = length_in;
    if (text != null) {
        const textLength: c_int = @intCast(TextLength(text));

        if (position < textLength) {
            const maxLength = textLength - position;
            if (length > maxLength) length = maxLength;
            if (length >= MAX_TEXT_BUFFER_LENGTH) length = MAX_TEXT_BUFFER_LENGTH - 1;

            var c: c_int = 0;
            while (c < length) : (c += 1) S.buffer[@intCast(c)] = text[@intCast(position + c)];

            S.buffer[@intCast(length)] = '\x00';
        }
    }

    return &S.buffer;
}

// Remove text spaces, concat words
export fn TextRemoveSpaces(text: [*c]const u8) callconv(.c) [*c]const u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    if (text != null) {
        // Avoid copying the ' ' characters
        var i: usize = 0;
        var j: usize = 0;
        while ((i < MAX_TEXT_BUFFER_LENGTH - 1) and (text[i] != '\x00')) : (i += 1) {
            if (text[i] != ' ') {
                S.buffer[j] = text[i];
                j += 1;
            }
        }
    }

    return &S.buffer;
}

// Get text between two strings
export fn GetTextBetween(text: [*c]const u8, begin: [*c]const u8, end: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    const beginIndex = TextFindIndex(text, begin);

    if (beginIndex > -1) {
        const beginLen: c_int = @intCast(TextLength(begin));
        var endIndex = TextFindIndex(ptrAdd(text, beginIndex + beginLen), end);

        if (endIndex > -1) {
            endIndex += (beginIndex + beginLen);
            const len = (endIndex - beginIndex - beginLen);
            if (len < (MAX_TEXT_BUFFER_LENGTH - 1)) _ = strncpy(&S.buffer, ptrAdd(text, beginIndex + beginLen), @intCast(len)) else _ = strncpy(&S.buffer, ptrAdd(text, beginIndex + beginLen), MAX_TEXT_BUFFER_LENGTH - 1);
        }
    }

    return &S.buffer;
}

// Replace text string
export fn TextReplace(text: [*c]const u8, search: [*c]const u8, replacement_in: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    var replacement = replacement_in;
    var textp = text;
    if ((textp != null) and (search != null) and (search[0] != '\x00')) {
        if (replacement == null) replacement = "";

        var insertPoint: [*c]u8 = null; // Next insert point
        var tempPtr: [*c]u8 = null; // Temp pointer
        var textLen: c_int = 0;
        var searchLen: c_int = 0;
        var replaceLen: c_int = 0;
        var lastReplacePos: c_int = 0;
        var count: c_int = 0;

        textLen = @intCast(TextLength(textp));
        searchLen = @intCast(TextLength(search));
        replaceLen = @intCast(TextLength(replacement));

        // Count the number of replacements needed
        insertPoint = @constCast(textp);
        count = 0;
        while (true) {
            tempPtr = strstr(insertPoint, search);
            if (tempPtr == null) break;
            insertPoint = ptrAdd(tempPtr, searchLen);
            count += 1;
        }

        if ((textLen + count * (replaceLen - searchLen)) < (MAX_TEXT_BUFFER_LENGTH - 1)) {
            tempPtr = &S.buffer; // Point to result start

            while (count > 0) {
                insertPoint = strstr(textp, search);
                lastReplacePos = @intCast(@intFromPtr(insertPoint) - @intFromPtr(textp));

                _ = memcpy(tempPtr, textp, @intCast(lastReplacePos));
                tempPtr = ptrAdd(tempPtr, lastReplacePos);

                if (replaceLen > 0) {
                    _ = memcpy(tempPtr, replacement, @intCast(replaceLen));
                    tempPtr = ptrAdd(tempPtr, replaceLen);
                }

                textp = ptrAdd(textp, lastReplacePos + searchLen); // Move to next "end of replace"
                count -= 1;
            }

            // Copy remaind text part after replacement to result
            _ = strncpy(tempPtr, textp, TextLength(textp));
        } else TraceLog(LOG_WARNING, "Text with replacement is longer than internal buffer, use TextReplaceAlloc()");
    }

    return &S.buffer;
}

// Replace text string (allocates)
export fn TextReplaceAlloc(text: [*c]const u8, search: [*c]const u8, replacement_in: [*c]const u8) callconv(.c) [*c]u8 {
    var result: [*c]u8 = null;

    var replacement = replacement_in;
    var textp = text;
    if ((textp != null) and (search != null) and (search[0] != '\x00')) {
        if (replacement == null) replacement = "";

        var insertPoint: [*c]u8 = null;
        var temp: [*c]u8 = null;
        var textLen: c_int = 0;
        var searchLen: c_int = 0;
        var replaceLen: c_int = 0;
        var lastReplacePos: c_int = 0;
        var count: c_int = 0;

        textLen = @intCast(TextLength(textp));
        searchLen = @intCast(TextLength(search));
        replaceLen = @intCast(TextLength(replacement));

        // Count the number of replacements needed
        insertPoint = @constCast(textp);
        count = 0;
        while (true) {
            temp = strstr(insertPoint, search);
            if (temp == null) break;
            insertPoint = ptrAdd(temp, searchLen);
            count += 1;
        }

        // Allocate returning string and point temp to it
        const tempLen = textLen + (replaceLen - searchLen) * count + 1;
        result = @ptrCast(RL_CALLOC(@intCast(tempLen), @sizeOf(u8)));
        temp = result;

        if (result != null) { // Memory was allocated
            while (count > 0) {
                insertPoint = strstr(textp, search);
                lastReplacePos = @intCast(@intFromPtr(insertPoint) - @intFromPtr(textp));

                _ = memcpy(temp, textp, @intCast(lastReplacePos));
                temp = ptrAdd(temp, lastReplacePos);

                if (replaceLen > 0) {
                    _ = memcpy(temp, replacement, @intCast(replaceLen));
                    temp = ptrAdd(temp, replaceLen);
                }

                textp = ptrAdd(textp, lastReplacePos + searchLen); // Move to next "end of replace"

                count -= 1;
            }

            // Copy remaind text part after replacement to result
            _ = strncpy(temp, textp, TextLength(textp));
        }
    }

    return result;
}

// Replace text between two specific strings
export fn TextReplaceBetween(text: [*c]const u8, begin: [*c]const u8, end: [*c]const u8, replacement: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    if ((text != null) and (begin != null) and (end != null)) {
        const beginIndex = TextFindIndex(text, begin);

        if (beginIndex > -1) {
            const beginLen: c_int = @intCast(TextLength(begin));
            var endIndex = TextFindIndex(ptrAdd(text, beginIndex + beginLen), end);

            if (endIndex > -1) {
                endIndex += (beginIndex + beginLen);

                const textLen: c_int = @intCast(TextLength(text));
                const replaceLen: c_int = if (replacement == null) 0 else @intCast(TextLength(replacement));

                if ((beginIndex + beginLen + replaceLen + (textLen - endIndex)) < (MAX_TEXT_BUFFER_LENGTH - 1)) {
                    _ = strncpy(&S.buffer, text, @intCast(beginIndex + beginLen)); // Copy first text part
                    if (replacement != null) _ = strncpy(ptrAdd(@as([*c]u8, &S.buffer), beginIndex + beginLen), replacement, @intCast(replaceLen)); // Copy replacement (if provided)
                    _ = strncpy(ptrAdd(@as([*c]u8, &S.buffer), beginIndex + beginLen + replaceLen), ptrAdd(text, endIndex), @intCast(textLen - endIndex)); // Copy end text part
                } else TraceLog(LOG_WARNING, "TEXT: Text with replaced string is longer than internal buffer (MAX_TEXT_BUFFER_LENGTH)");
            }
        }
    }

    return &S.buffer;
}

// Replace text between two specific strings (allocates)
export fn TextReplaceBetweenAlloc(text: [*c]const u8, begin: [*c]const u8, end: [*c]const u8, replacement: [*c]const u8) callconv(.c) [*c]u8 {
    var result: [*c]u8 = null;

    if ((text != null) and (begin != null) and (end != null)) {
        const beginIndex = TextFindIndex(text, begin);

        if (beginIndex > -1) {
            const beginLen: c_int = @intCast(TextLength(begin));
            var endIndex = TextFindIndex(ptrAdd(text, beginIndex + beginLen), end);

            if (endIndex > -1) {
                endIndex += (beginIndex + beginLen);

                const textLen: c_int = @intCast(TextLength(text));
                const replaceLen: c_int = if (replacement == null) 0 else @intCast(TextLength(replacement));
                const toreplaceLen = endIndex - beginIndex - beginLen;
                result = @ptrCast(RL_CALLOC(@intCast(textLen + replaceLen - toreplaceLen + 1), @sizeOf(u8)));

                _ = strncpy(result, text, @intCast(beginIndex + beginLen)); // Copy first text part
                if (replacement != null) _ = strncpy(ptrAdd(result, beginIndex + beginLen), replacement, @intCast(replaceLen)); // Copy replacement (if provided)
                _ = strncpy(ptrAdd(result, beginIndex + beginLen + replaceLen), ptrAdd(text, endIndex), @intCast(textLen - endIndex)); // Copy end text part
            }
        }
    }

    return result;
}

// Insert text in a specific position, moves all text forward
export fn TextInsert(text: [*c]const u8, insert: [*c]const u8, position: c_int) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    if ((text != null) and (insert != null)) {
        const textLen: c_int = @intCast(TextLength(text));
        const insertLen: c_int = @intCast(TextLength(insert));

        if ((textLen + insertLen) < (MAX_TEXT_BUFFER_LENGTH - 1)) {
            var i: c_int = 0;
            while (i < position) : (i += 1) S.buffer[@intCast(i)] = text[@intCast(i)];
            i = position;
            while (i < insertLen + position) : (i += 1) S.buffer[@intCast(i)] = insert[@intCast(i - position)];
            i = insertLen + position;
            while (i < textLen + insertLen) : (i += 1) S.buffer[@intCast(i)] = text[@intCast(i)];

            S.buffer[@intCast(textLen + insertLen)] = '\x00'; // Add EOL
        } else TraceLog(LOG_WARNING, "Text with inserted string is longer than internal buffer, use TextInserExt()");
    }

    return &S.buffer;
}

// Insert text in a specific position, moves all text forward (allocates)
export fn TextInsertAlloc(text: [*c]const u8, insert: [*c]const u8, position: c_int) callconv(.c) [*c]u8 {
    var result: [*c]u8 = null;

    if ((text != null) and (insert != null)) {
        const textLen: c_int = @intCast(TextLength(text));
        const insertLen: c_int = @intCast(TextLength(insert));

        result = @ptrCast(RL_MALLOC(@intCast(textLen + insertLen + 1)));

        var i: c_int = 0;
        while (i < position) : (i += 1) result[@intCast(i)] = text[@intCast(i)];
        i = position;
        while (i < insertLen + position) : (i += 1) result[@intCast(i)] = insert[@intCast(i - position)];
        i = insertLen + position;
        while (i < textLen + insertLen) : (i += 1) result[@intCast(i)] = text[@intCast(i)];

        result[@intCast(textLen + insertLen)] = '\x00'; // Add EOL
    }

    return result;
}

// Join text strings with delimiter
export fn TextJoin(textList: [*c][*c]u8, count: c_int, delimiter: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);
    var textPtr: [*c]u8 = &S.buffer;

    var totalLength: c_int = 0;
    const delimiterLen: c_int = @intCast(TextLength(delimiter));

    var i: c_int = 0;
    while (i < count) : (i += 1) {
        const textLength: c_int = @intCast(TextLength(textList[@intCast(i)]));

        // Make sure joined text could fit inside MAX_TEXT_BUFFER_LENGTH
        if ((totalLength + textLength) < MAX_TEXT_BUFFER_LENGTH) {
            _ = memcpy(textPtr, textList[@intCast(i)], @intCast(textLength));
            totalLength += textLength;
            textPtr = ptrAdd(textPtr, textLength);

            if ((delimiterLen > 0) and (i < (count - 1))) {
                _ = memcpy(textPtr, delimiter, @intCast(delimiterLen));
                totalLength += delimiterLen;
                textPtr = ptrAdd(textPtr, delimiterLen);
            }
        }
    }

    return &S.buffer;
}

// Split string into multiple strings
export fn TextSplit(text: [*c]const u8, delimiter: u8, count: [*c]c_int) callconv(.c) [*c][*c]u8 {
    const S = struct {
        var buffers: [MAX_TEXTSPLIT_COUNT][*c]u8 = std.mem.zeroes([MAX_TEXTSPLIT_COUNT][*c]u8);
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    S.buffers[0] = &S.buffer;
    var counter: c_int = 0;

    if (text != null) {
        counter = 1;

        // Count how many substrings are found on text and set pointers to every one
        var i: usize = 0;
        while (i < MAX_TEXT_BUFFER_LENGTH) : (i += 1) {
            S.buffer[i] = text[i];
            if (S.buffer[i] == '\x00') break else if (S.buffer[i] == delimiter) {
                S.buffer[i] = '\x00'; // Set an end of string at this point
                S.buffers[@intCast(counter)] = ptrAdd(@as([*c]u8, &S.buffer), @as(c_int, @intCast(i)) + 1);
                counter += 1;

                if (counter == MAX_TEXTSPLIT_COUNT) break;
            }
        }
    }

    count.* = counter;
    return &S.buffers;
}

// Append text at specific position and move cursor
export fn TextAppend(text: [*c]u8, append: [*c]const u8, position: [*c]c_int) callconv(.c) void {
    if ((text != null) and (append != null)) {
        _ = TextCopy(ptrAdd(text, position.*), append);
        position.* += @intCast(TextLength(append));
    }
}

// Find first text occurrence within a string
export fn TextFindIndex(text: [*c]const u8, search: [*c]const u8) callconv(.c) c_int {
    var position: c_int = -1;

    if (text != null) {
        const ptr = strstr(text, search);

        if (ptr != null) position = @intCast(@intFromPtr(ptr) - @intFromPtr(text));
    }

    return position;
}

// Get upper case version of provided string
export fn TextToUpper(text: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    if (text != null) {
        var i: usize = 0;
        while ((i < MAX_TEXT_BUFFER_LENGTH - 1) and (text[i] != '\x00')) : (i += 1) {
            if ((text[i] >= 'a') and (text[i] <= 'z')) S.buffer[i] = text[i] - 32 else S.buffer[i] = text[i];
        }
    }

    return &S.buffer;
}

// Get lower case version of provided string
export fn TextToLower(text: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    if (text != null) {
        var i: usize = 0;
        while ((i < MAX_TEXT_BUFFER_LENGTH - 1) and (text[i] != '\x00')) : (i += 1) {
            if ((text[i] >= 'A') and (text[i] <= 'Z')) S.buffer[i] = text[i] + 32 else S.buffer[i] = text[i];
        }
    }

    return &S.buffer;
}

// Get Pascal case notation version of provided string
export fn TextToPascal(text: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    if (text != null) {
        // Upper case first character
        if ((text[0] >= 'a') and (text[0] <= 'z')) S.buffer[0] = text[0] - 32 else S.buffer[0] = text[0];

        // Check for next separator to upper case another character
        var i: usize = 1;
        var j: usize = 1;
        while ((i < MAX_TEXT_BUFFER_LENGTH - 1) and (text[j] != '\x00')) : ({
            i += 1;
            j += 1;
        }) {
            if (text[j] != '_') S.buffer[i] = text[j] else {
                j += 1;
                if ((text[j] >= 'a') and (text[j] <= 'z')) S.buffer[i] = text[j] - 32 else if ((text[j] >= '0') and (text[j] <= '9')) S.buffer[i] = text[j];
            }
        }
    }

    return &S.buffer;
}

// Get snake case notation version of provided string
export fn TextToSnake(text: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    if (text != null) {
        // Check for next separator to upper case another character
        var i: usize = 0;
        var j: usize = 0;
        while ((i < MAX_TEXT_BUFFER_LENGTH - 1) and (text[j] != '\x00')) : ({
            i += 1;
            j += 1;
        }) {
            if ((text[j] >= 'A') and (text[j] <= 'Z')) {
                if (i >= 1) {
                    S.buffer[i] = '_';
                    i += 1;
                }
                S.buffer[i] = text[j] + 32;
            } else S.buffer[i] = text[j];
        }
    }

    return &S.buffer;
}

// Get Camel case notation version of provided string
export fn TextToCamel(text: [*c]const u8) callconv(.c) [*c]u8 {
    const S = struct {
        var buffer: [MAX_TEXT_BUFFER_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_BUFFER_LENGTH]u8);
    };
    _ = memset(&S.buffer, 0, MAX_TEXT_BUFFER_LENGTH);

    if (text != null) {
        // Lower case first character
        if ((text[0] >= 'A') and (text[0] <= 'Z')) S.buffer[0] = text[0] + 32 else S.buffer[0] = text[0];

        // Check for next separator to upper case another character
        var i: usize = 1;
        var j: usize = 1;
        while ((i < MAX_TEXT_BUFFER_LENGTH - 1) and (text[j] != '\x00')) : ({
            i += 1;
            j += 1;
        }) {
            if (text[j] != '_') S.buffer[i] = text[j] else {
                j += 1;
                if ((text[j] >= 'a') and (text[j] <= 'z')) S.buffer[i] = text[j] - 32;
            }
        }
    }

    return &S.buffer;
}

// Encode text codepoint into UTF-8 text (allocates)
export fn LoadUTF8(codepoints: [*c]const c_int, length: c_int) callconv(.c) [*c]u8 {
    var text: [*c]u8 = null;

    if ((codepoints != null) and (length > 0)) {
        // Allocate enough memory to fit all possible codepoints
        text = @ptrCast(RL_CALLOC(@intCast(length * 5), 1));
        var utf8: [*c]const u8 = null;
        var size: c_int = 0;

        var i: c_int = 0;
        var bytes: c_int = 0;
        while (i < length) : (i += 1) {
            utf8 = CodepointToUTF8(codepoints[@intCast(i)], &bytes);
            _ = memcpy(ptrAdd(text, size), utf8, @intCast(bytes));
            size += bytes;
        }

        // Create second buffer and copy data manually to it
        const temp: [*c]u8 = @ptrCast(RL_CALLOC(@intCast(size + 1), 1));
        _ = memcpy(temp, text, @intCast(size));
        RL_FREE(text);
        text = temp;
    }

    return text;
}

// Unload UTF-8 text encoded from codepoints array
export fn UnloadUTF8(text: [*c]u8) callconv(.c) void {
    RL_FREE(text);
}

// Load all codepoints from a UTF-8 text string
export fn LoadCodepoints(text: [*c]const u8, count: [*c]c_int) callconv(.c) [*c]c_int {
    var codepoints: [*c]c_int = null;
    var codepointCount: c_int = 0;

    if (text != null) {
        const textLength: c_int = @intCast(TextLength(text));

        // Allocate a big enough buffer to store as many codepoints as text bytes
        codepoints = @ptrCast(@alignCast(RL_CALLOC(@intCast(textLength), @sizeOf(c_int))));

        var codepointSize: c_int = 0;
        var i: c_int = 0;
        while (i < textLength) : (codepointCount += 1) {
            codepoints[@intCast(codepointCount)] = GetCodepointNext(ptrAdd(text, i), &codepointSize);
            i += codepointSize;
        }

        // Create second buffer and copy data manually to it
        const temp: [*c]c_int = @ptrCast(@alignCast(RL_CALLOC(@intCast(codepointCount), @sizeOf(c_int))));
        i = 0;
        while (i < codepointCount) : (i += 1) temp[@intCast(i)] = codepoints[@intCast(i)];
        RL_FREE(codepoints);
        codepoints = temp;
    }

    count.* = codepointCount;
    return codepoints;
}

// Unload codepoints data from memory
export fn UnloadCodepoints(codepoints: [*c]c_int) callconv(.c) void {
    RL_FREE(codepoints);
}

// Get total number of characters (codepoints) in a UTF-8 encoded text
export fn GetCodepointCount(text: [*c]const u8) callconv(.c) c_int {
    var length: c_uint = 0;
    var ptr = text;

    if (ptr != null) {
        while (ptr.* != '\x00') {
            var next: c_int = 0;
            _ = GetCodepointNext(ptr, &next);
            ptr += @intCast(next);
            length += 1;
        }
    }

    return @intCast(length);
}

// Encode codepoint into utf8 text (char array length returned as parameter)
export fn CodepointToUTF8(codepoint: c_int, utf8Size: [*c]c_int) callconv(.c) [*c]const u8 {
    const S = struct {
        var utf8: [6]u8 = std.mem.zeroes([6]u8);
    };
    _ = memset(&S.utf8, 0, 6); // Clear static array
    var size: c_int = 0; // Byte size of codepoint

    if (codepoint <= 0x7f) {
        S.utf8[0] = @truncate(@as(c_uint, @bitCast(codepoint)));
        size = 1;
    } else if (codepoint <= 0x7ff) {
        S.utf8[0] = @truncate(@as(c_uint, @bitCast(((codepoint >> 6) & 0x1f) | 0xc0)));
        S.utf8[1] = @truncate(@as(c_uint, @bitCast((codepoint & 0x3f) | 0x80)));
        size = 2;
    } else if (codepoint <= 0xffff) {
        S.utf8[0] = @truncate(@as(c_uint, @bitCast(((codepoint >> 12) & 0x0f) | 0xe0)));
        S.utf8[1] = @truncate(@as(c_uint, @bitCast(((codepoint >> 6) & 0x3f) | 0x80)));
        S.utf8[2] = @truncate(@as(c_uint, @bitCast((codepoint & 0x3f) | 0x80)));
        size = 3;
    } else if (codepoint <= 0x10ffff) {
        S.utf8[0] = @truncate(@as(c_uint, @bitCast(((codepoint >> 18) & 0x07) | 0xf0)));
        S.utf8[1] = @truncate(@as(c_uint, @bitCast(((codepoint >> 12) & 0x3f) | 0x80)));
        S.utf8[2] = @truncate(@as(c_uint, @bitCast(((codepoint >> 6) & 0x3f) | 0x80)));
        S.utf8[3] = @truncate(@as(c_uint, @bitCast((codepoint & 0x3f) | 0x80)));
        size = 4;
    }

    utf8Size.* = size;

    return &S.utf8;
}

// Get next codepoint in a UTF-8 encoded text, scanning until '\0' is found
export fn GetCodepoint(text: [*c]const u8, codepointSize: [*c]c_int) callconv(.c) c_int {
    var codepoint: c_int = 0x3f; // Codepoint (defaults to '?')
    codepointSize.* = 1;
    if (text == null) return codepoint;

    // NOTE: On decoding errors, return as soon as possible
    const octet: c_int = @as(c_int, text[0]); // The first UTF8 octet

    if (octet <= 0x7f) {
        // Only one octet (ASCII range x00-7F)
        codepoint = text[0];
    } else if ((octet & 0xe0) == 0xc0) {
        // Two octets
        const octet1: u8 = text[1];

        if ((octet1 == '\x00') or ((octet1 >> 6) != 2)) {
            codepointSize.* = 2;
            return codepoint;
        } // Unexpected sequence

        if ((octet >= 0xc2) and (octet <= 0xdf)) {
            codepoint = ((octet & 0x1f) << 6) | (octet1 & 0x3f);
            codepointSize.* = 2;
        }
    } else if ((octet & 0xf0) == 0xe0) {
        // Three octets
        const octet1: u8 = text[1];
        var octet2: u8 = '\x00';

        if ((octet1 == '\x00') or ((octet1 >> 6) != 2)) {
            codepointSize.* = 2;
            return codepoint;
        } // Unexpected sequence

        octet2 = text[2];

        if ((octet2 == '\x00') or ((octet2 >> 6) != 2)) {
            codepointSize.* = 3;
            return codepoint;
        } // Unexpected sequence

        if (((octet == 0xe0) and !((octet1 >= 0xa0) and (octet1 <= 0xbf))) or
            ((octet == 0xed) and !((octet1 >= 0x80) and (octet1 <= 0x9f))))
        {
            codepointSize.* = 2;
            return codepoint;
        }

        if ((octet >= 0xe0) and (octet <= 0xef)) {
            codepoint = ((octet & 0xf) << 12) | (@as(c_int, octet1 & 0x3f) << 6) | (octet2 & 0x3f);
            codepointSize.* = 3;
        }
    } else if ((octet & 0xf8) == 0xf0) {
        // Four octets
        if (octet > 0xf4) return codepoint;

        const octet1: u8 = text[1];
        var octet2: u8 = '\x00';
        var octet3: u8 = '\x00';

        if ((octet1 == '\x00') or ((octet1 >> 6) != 2)) {
            codepointSize.* = 2;
            return codepoint;
        } // Unexpected sequence

        octet2 = text[2];

        if ((octet2 == '\x00') or ((octet2 >> 6) != 2)) {
            codepointSize.* = 3;
            return codepoint;
        } // Unexpected sequence

        octet3 = text[3];

        if ((octet3 == '\x00') or ((octet3 >> 6) != 2)) {
            codepointSize.* = 4;
            return codepoint;
        } // Unexpected sequence

        if (((octet == 0xf0) and !((octet1 >= 0x90) and (octet1 <= 0xbf))) or
            ((octet == 0xf4) and !((octet1 >= 0x80) and (octet1 <= 0x8f))))
        {
            codepointSize.* = 2;
            return codepoint;
        } // Unexpected sequence

        if (octet >= 0xf0) {
            codepoint = ((octet & 0x7) << 18) | (@as(c_int, octet1 & 0x3f) << 12) | (@as(c_int, octet2 & 0x3f) << 6) | (octet3 & 0x3f);
            codepointSize.* = 4;
        }
    }

    if (codepoint > 0x10ffff) codepoint = 0x3f; // Codepoints after U+10ffff are invalid

    return codepoint;
}

// Get next codepoint in a byte sequence and bytes processed
export fn GetCodepointNext(text: [*c]const u8, codepointSize: [*c]c_int) callconv(.c) c_int {
    const ptr = text;
    var codepoint: c_int = 0x3f; // Codepoint (defaults to '?')
    codepointSize.* = 1;
    if (text == null) return codepoint;

    // Get current codepoint and bytes processed
    if (0xf0 == (0xf8 & ptr[0])) {
        // 4 byte UTF-8 codepoint
        if (((ptr[1] & 0xC0) ^ 0x80) != 0 or ((ptr[2] & 0xC0) ^ 0x80) != 0 or ((ptr[3] & 0xC0) ^ 0x80) != 0) {
            return codepoint;
        } // 10xxxxxx checks
        codepoint = (@as(c_int, 0x07 & ptr[0]) << 18) | (@as(c_int, 0x3f & ptr[1]) << 12) | (@as(c_int, 0x3f & ptr[2]) << 6) | (0x3f & ptr[3]);
        codepointSize.* = 4;
    } else if (0xe0 == (0xf0 & ptr[0])) {
        // 3 byte UTF-8 codepoint
        if (((ptr[1] & 0xC0) ^ 0x80) != 0 or ((ptr[2] & 0xC0) ^ 0x80) != 0) {
            return codepoint;
        } // 10xxxxxx checks
        codepoint = (@as(c_int, 0x0f & ptr[0]) << 12) | (@as(c_int, 0x3f & ptr[1]) << 6) | (0x3f & ptr[2]);
        codepointSize.* = 3;
    } else if (0xc0 == (0xe0 & ptr[0])) {
        // 2 byte UTF-8 codepoint
        if (((ptr[1] & 0xC0) ^ 0x80) != 0) {
            return codepoint;
        } // 10xxxxxx checks
        codepoint = (@as(c_int, 0x1f & ptr[0]) << 6) | (0x3f & ptr[1]);
        codepointSize.* = 2;
    } else if (0x00 == (0x80 & ptr[0])) {
        // 1 byte UTF-8 codepoint
        codepoint = ptr[0];
        codepointSize.* = 1;
    }

    return codepoint;
}

// Get previous codepoint in a byte sequence and bytes processed
export fn GetCodepointPrevious(text: [*c]const u8, codepointSize: [*c]c_int) callconv(.c) c_int {
    var ptr = text;
    var codepoint: c_int = 0x3f; // Codepoint (defaults to '?')
    codepointSize.* = 1;
    if (text == null) return codepoint;

    // Move to previous codepoint
    while (true) {
        ptr -= 1;
        if (!(((0x80 & ptr[0]) != 0) and ((0xc0 & ptr[0]) == 0x80))) break;
    }

    var cpSize: c_int = 0;
    codepoint = GetCodepointNext(ptr, &cpSize);
    if (codepoint != 0) codepointSize.* = cpSize;

    return codepoint;
}

//----------------------------------------------------------------------------------
// Module Internal Functions Definition
//----------------------------------------------------------------------------------
// Read a line from memory
// NOTE: Returns the number of bytes read
fn GetLine(origin: [*c]const u8, buffer: [*c]u8, maxLength: c_int) c_int {
    var count: c_int = 0;
    while (count < maxLength - 1) : (count += 1) {
        if (origin[@intCast(count)] == '\n') break;
    }
    _ = memcpy(buffer, origin, @intCast(count));
    buffer[@intCast(count)] = '\x00';
    return count;
}

// Load a BMFont file (AngelCode font file)
fn LoadBMFont(fileName: [*c]const u8) Font {
    var font: Font = std.mem.zeroes(Font);

    var buffer = std.mem.zeroes([MAX_BUFFER_SIZE]u8);
    var searchPoint: [*c]u8 = null;

    var fontSize: c_int = 0;
    var glyphCount: c_int = 0;

    var imWidth: c_int = 0;
    var imHeight: c_int = 0;
    var pageCount: c_int = 1;
    var imFileName = std.mem.zeroes([MAX_FONT_IMAGE_PAGES][129]u8);

    var base: c_int = 0; // Useless data
    var readBytes: c_int = 0; // Data bytes read
    var readVars: c_int = 0; // Variables filled by sscanf()

    const fileText = LoadFileText(fileName);

    if (fileText == null) return font;

    var fileTextPtr = fileText;

    // NOTE: Skip first line, it contains no useful information
    readBytes = GetLine(fileTextPtr, &buffer, MAX_BUFFER_SIZE);
    fileTextPtr += @intCast(readBytes + 1);

    // Read line data
    readBytes = GetLine(fileTextPtr, &buffer, MAX_BUFFER_SIZE);
    searchPoint = strstr(&buffer, "lineHeight");
    readVars = sscanf(searchPoint, "lineHeight=%i base=%i scaleW=%i scaleH=%i pages=%i", &fontSize, &base, &imWidth, &imHeight, &pageCount);
    fileTextPtr += @intCast(readBytes + 1);

    if (readVars < 4) {
        UnloadFileText(fileText);
        return font;
    } // Some data not available, file malformed

    if (pageCount > MAX_FONT_IMAGE_PAGES) {
        TraceLog(LOG_WARNING, "FONT: [%s] Font defines more pages than supported: %i/%i", fileName, pageCount, @as(c_int, MAX_FONT_IMAGE_PAGES));
        pageCount = MAX_FONT_IMAGE_PAGES;
    }

    {
        var i: c_int = 0;
        while (i < pageCount) : (i += 1) {
            readBytes = GetLine(fileTextPtr, &buffer, MAX_BUFFER_SIZE);
            searchPoint = strstr(&buffer, "file");
            readVars = sscanf(searchPoint, "file=\"%128[^\"]\"", &imFileName[@intCast(i)]);
            fileTextPtr += @intCast(readBytes + 1);

            if (readVars < 1) {
                UnloadFileText(fileText);
                return font;
            } // No fileName read
        }
    }

    readBytes = GetLine(fileTextPtr, &buffer, MAX_BUFFER_SIZE);
    searchPoint = strstr(&buffer, "count");
    readVars = sscanf(searchPoint, "count=%i", &glyphCount);
    fileTextPtr += @intCast(readBytes + 1);

    if (readVars < 1) {
        UnloadFileText(fileText);
        return font;
    } // No glyphCount read

    // Load all required images for further compose
    const imFonts: [*c]Image = @ptrCast(@alignCast(RL_CALLOC(@intCast(pageCount), @sizeOf(Image)))); // Font atlases, multiple images

    {
        var i: c_int = 0;
        while (i < pageCount) : (i += 1) {
            const u: usize = @intCast(i);
            imFonts[u] = LoadImage(TextFormat("%s/%s", GetDirectoryPath(fileName), &imFileName[u]));

            if (imFonts[u].format == PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) {
                // Convert image to GRAYSCALE + ALPHA, using the mask as the alpha channel
                const imFontAlpha = Image{
                    .data = RL_CALLOC(@intCast(imFonts[u].width * imFonts[u].height), 2),
                    .width = imFonts[u].width,
                    .height = imFonts[u].height,
                    .mipmaps = 1,
                    .format = PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA,
                };

                const alphaData: [*]u8 = @ptrCast(imFontAlpha.data);
                const srcData: [*]const u8 = @ptrCast(imFonts[u].data);
                var p: c_int = 0;
                var pi: c_int = 0;
                while (p < (imFonts[u].width * imFonts[u].height * 2)) : ({
                    p += 2;
                    pi += 1;
                }) {
                    alphaData[@intCast(p)] = 0xff;
                    alphaData[@intCast(p + 1)] = srcData[@intCast(pi)];
                }

                UnloadImage(imFonts[u]);
                imFonts[u] = imFontAlpha;
            }
        }
    }

    var fullFont = imFonts[0];
    {
        var i: c_int = 1;
        while (i < pageCount) : (i += 1) UnloadImage(imFonts[@intCast(i)]);
    }

    // If multiple atlas, then merge atlas
    if (pageCount > 1) {
        // Resize font atlas to draw additional images
        ImageResizeCanvas(&fullFont, imWidth, imHeight * pageCount, 0, 0, BLACK);

        var i: c_int = 1;
        while (i < pageCount) : (i += 1) {
            const srcRec = Rectangle{ .x = 0.0, .y = 0.0, .width = @floatFromInt(imWidth), .height = @floatFromInt(imHeight) };
            const dstRec = Rectangle{ .x = 0.0, .y = @as(f32, @floatFromInt(imHeight)) * @as(f32, @floatFromInt(i)), .width = @floatFromInt(imWidth), .height = @floatFromInt(imHeight) };
            ImageDrawImagePro(&fullFont, imFonts[@intCast(i)], srcRec, dstRec, .{ .x = 0, .y = 0 }, 0.0, WHITE);
        }
    }

    RL_FREE(imFonts);

    font.texture = LoadTextureFromImage(fullFont);

    // Fill font characters info data
    font.baseSize = fontSize;
    font.glyphCount = glyphCount;
    font.glyphPadding = 0;
    font.glyphs = @ptrCast(@alignCast(RL_MALLOC(@intCast(glyphCount * @as(c_int, @sizeOf(GlyphInfo))))));
    font.recs = @ptrCast(@alignCast(RL_MALLOC(@intCast(glyphCount * @as(c_int, @sizeOf(Rectangle))))));

    var charId: c_int = 0;
    var charX: c_int = 0;
    var charY: c_int = 0;
    var charWidth: c_int = 0;
    var charHeight: c_int = 0;
    var charOffsetX: c_int = 0;
    var charOffsetY: c_int = 0;
    var charAdvanceX: c_int = 0;
    var pageID: c_int = 0;

    {
        var i: c_int = 0;
        while (i < glyphCount) : (i += 1) {
            const u: usize = @intCast(i);
            readBytes = GetLine(fileTextPtr, &buffer, MAX_BUFFER_SIZE);
            readVars = sscanf(&buffer, "char id=%i x=%i y=%i width=%i height=%i xoffset=%i yoffset=%i xadvance=%i page=%i", &charId, &charX, &charY, &charWidth, &charHeight, &charOffsetX, &charOffsetY, &charAdvanceX, &pageID);
            fileTextPtr += @intCast(readBytes + 1);

            if (readVars == 9) { // Make sure all char data has been properly read
                // Get character rectangle in the font atlas texture
                font.recs[u] = Rectangle{ .x = @floatFromInt(charX), .y = @as(f32, @floatFromInt(charY)) + @as(f32, @floatFromInt(imHeight)) * @as(f32, @floatFromInt(pageID)), .width = @floatFromInt(charWidth), .height = @floatFromInt(charHeight) };

                // Save data properly in sprite font
                font.glyphs[u].value = charId;
                font.glyphs[u].offsetX = charOffsetX;
                font.glyphs[u].offsetY = charOffsetY;
                font.glyphs[u].advanceX = charAdvanceX;

                // Fill character image data from full font data
                font.glyphs[u].image = ImageFromImage(fullFont, font.recs[u]);
            } else {
                font.glyphs[u].image = GenImageColor(@intFromFloat(font.recs[u].width), @intFromFloat(font.recs[u].height), BLACK);
                TraceLog(LOG_WARNING, "FONT: [%s] Some characters data not correctly provided", fileName);
            }
        }
    }

    UnloadImage(fullFont);
    UnloadFileText(fileText);

    if (font.texture.id == 0) {
        UnloadFont(font);
        font = GetFontDefault();
        TraceLog(LOG_WARNING, "FONT: [%s] Failed to load texture, reverted to default font", fileName);
    } else TraceLog(LOG_INFO, "FONT: [%s] Font loaded successfully (%i glyphs)", fileName, font.glyphCount);

    return font;
}
