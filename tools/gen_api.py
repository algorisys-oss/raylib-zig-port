#!/usr/bin/env python3
"""gen_api.py — generate the idiomatic Zig API from raylib.h (docs/zig-api.md).

Outputs:
  src/api/c.zig       exact-C `extern fn` declarations (the only C-shaped code)
  src/api/raylib.zig  idiomatic layer: types, enums, flags, colors, wrappers

Every RLAPI function is mapped by the mechanical rules in docs/zig-api.md. A
function the rules cannot map cleanly (out-params, varargs, owned buffers,
callbacks) must appear in OVERRIDES with a hand-written wrapper, or the run
fails and names it — nothing falls through as a raw C type.

Usage: python3 tools/gen_api.py [raylib.h]
"""
import keyword  # noqa: F401  (Zig keywords listed below)
import pathlib
import re
import sys

HEADER = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "vendor/raylib/src/raylib.h")
RAYMATH = HEADER.with_name("raymath.h")
OUT_DIR = pathlib.Path("src/api")

ZIG_KEYWORDS = {
    "addrspace", "align", "allowzero", "and", "anyframe", "anytype", "asm", "break",
    "callconv", "catch", "comptime", "const", "continue", "defer", "else", "enum",
    "errdefer", "error", "export", "extern", "fn", "for", "if", "inline", "linksection",
    "noalias", "noinline", "nosuspend", "opaque", "or", "orelse", "packed", "pub",
    "resume", "return", "struct", "suspend", "switch", "test", "threadlocal", "try",
    "union", "unreachable", "var", "volatile", "while", "null", "true", "false",
    "undefined", "type", "anyerror", "bool", "void", "noreturn", "u8", "i32", "f32",
}

# --------------------------------------------------------------------------
# Rule tables
# --------------------------------------------------------------------------

# C scalar -> Zig type, for the C boundary and for the idiomatic layer.
C_SCALARS = {
    "void": ("void", "void"),
    "bool": ("bool", "bool"),
    "char": ("u8", "u8"),
    "unsigned char": ("u8", "u8"),
    "short": ("c_short", "i16"),
    "unsigned short": ("c_ushort", "u16"),
    "int": ("c_int", "i32"),
    "unsigned int": ("c_uint", "u32"),
    "long": ("c_long", "i64"),
    "float": ("f32", "f32"),
    "double": ("f64", "f64"),
}

# Enums whose values form an open set (raylib can return values outside the
# declared members, or users pass raw codes) are non-exhaustive.
OPEN_ENUMS = {"KeyboardKey", "GamepadButton", "GamepadAxis", "MouseButton",
              "MouseCursor", "Gesture", "ShaderLocationIndex", "MaterialMapIndex"}

# Enums raylib passes as `unsigned int` (default backing is c_int).
ENUM_BACKING = {"Gesture": "c_uint"}

# The ConfigFlags enum is a bit set -> packed struct(u32).
FLAG_ENUMS = {"ConfigFlags"}

# Struct fields typed with an enum in the API (ABI-identical: enum(c_int)).
FIELD_ENUMS = {
    ("Image", "format"): "PixelFormat",
    ("Texture", "format"): "PixelFormat",
    ("Camera3D", "projection"): "CameraProjection",
}

# (function-name regex, param name) -> enum/flags type. First match wins.
PARAM_ENUMS = [
    (r"Key|ExitKey", "key", "KeyboardKey"),
    (r"Mouse", "button", "MouseButton"),
    (r"Gamepad", "button", "GamepadButton"),
    (r"Gamepad", "axis", "GamepadAxis"),
    (r"SetMouseCursor", "cursor", "MouseCursor"),
    (r"IsGestureDetected", "gesture", "Gesture"),
    (r"TraceLog|SetTraceLogLevel", "logLevel", "TraceLogLevel"),
    (r"ConfigFlags|WindowState", "flags", "ConfigFlags"),
    (r".", "format", "PixelFormat"),
    (r".", "newFormat", "PixelFormat"),
    (r"SetTextureFilter", "filter", "TextureFilter"),
    (r"SetTextureWrap", "wrap", "TextureWrap"),
    (r"LoadTextureCubemap", "layout", "CubemapLayout"),
    (r"BeginBlendMode", "mode", "BlendMode"),
    (r"UpdateCamera$", "mode", "CameraMode"),
    (r"SetShaderValue", "uniformType", "ShaderUniformDataType"),
    (r"LoadFontData", "type", "FontType"),
    (r"SetMaterialTexture", "mapType", "MaterialMapIndex"),
]

RETURN_ENUMS = {
    "GetKeyPressed": "KeyboardKey",
    "GetGamepadButtonPressed": "GamepadButton",
    "GetGestureDetected": "Gesture",
}

# Pointer param followed by an int param with one of these names -> one slice.
COUNT_NAMES = re.compile(r"(?:[cC]ount|[sS]ize|[lL]ength|^instances)$")

# Pointer params followed by a *Size/*Count-named int that is NOT their element
# count (a single in/out struct, or a byte size of an opaque block).
NOT_SLICES = {("ImageBlurGaussian", "image"), ("MemRealloc", "ptr")}

# Params whose C name would shadow a declaration in Zig (Zig forbids shadowing).
PARAM_RENAMES = {
    ("FileRename", "fileRename"): "newFileName",
    # `c` is the boundary namespace; name the triangle's vertices uniformly.
    ("Vector3Barycenter", "a"): "v1",
    ("Vector3Barycenter", "b"): "v2",
    ("Vector3Barycenter", "c"): "v3",
}
RESERVED_PARAMS = {"c", "std", "math"}  # module-level names in raylib.zig

# `const char *` params that raylib documents as accepting NULL.
NULLABLE_STRINGS = {
    ("LoadShader", "vsFileName"), ("LoadShader", "fsFileName"),
    ("LoadShaderFromMemory", "vsCode"), ("LoadShaderFromMemory", "fsCode"),
}

# `const char *` returns that can be NULL.
NULLABLE_STRING_RETURNS = {"GetClipboardText", "GetGamepadName", "GetKeyName"}

# Loaders whose failure raylib reports through IsXValid -> error{LoadFailed}!T.
VALIDATED_LOADERS = {
    "LoadImage": "IsImageValid", "LoadImageRaw": "IsImageValid",
    "LoadImageAnim": "IsImageValid", "LoadImageAnimFromMemory": "IsImageValid",
    "LoadImageFromMemory": "IsImageValid", "LoadImageFromTexture": "IsImageValid",
    "LoadImageFromScreen": "IsImageValid",
    "LoadTexture": "IsTextureValid", "LoadTextureFromImage": "IsTextureValid",
    "LoadTextureCubemap": "IsTextureValid",
    "LoadRenderTexture": "IsRenderTextureValid", "LoadRenderTextureEx": "IsRenderTextureValid",
    "LoadFont": "IsFontValid", "LoadFontEx": "IsFontValid",
    "LoadFontFromImage": "IsFontValid", "LoadFontFromMemory": "IsFontValid",
    "LoadShader": "IsShaderValid", "LoadShaderFromMemory": "IsShaderValid",
    "LoadModel": "IsModelValid", "LoadModelFromMesh": "IsModelValid",
    "LoadWave": "IsWaveValid", "LoadWaveFromMemory": "IsWaveValid",
    "LoadSound": "IsSoundValid", "LoadSoundFromWave": "IsSoundValid",
    "LoadSoundAlias": "IsSoundValid",
    "LoadMusicStream": "IsMusicValid", "LoadMusicStreamFromMemory": "IsMusicValid",
    "LoadAudioStream": "IsAudioStreamValid",
}

COLOR_NAMES = {
    "LIGHTGRAY": "light_gray", "DARKGRAY": "dark_gray", "SKYBLUE": "sky_blue",
    "DARKBLUE": "dark_blue", "DARKGREEN": "dark_green", "DARKPURPLE": "dark_purple",
    "DARKBROWN": "dark_brown", "RAYWHITE": "ray_white",
}

# Methods appended to generated structs: accessors where a C idiom (an array
# indexed by an enum) has no direct Zig spelling. ABI unaffected (decls only).
STRUCT_METHODS = {
    "Material": '''
    /// Material map by index: `model.materials.?[0].map(.diffuse).texture = texture`
    /// (C: `model.materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = texture`).
    pub fn map(material: Material, index: MaterialMapIndex) *MaterialMap {
        return &material.maps.?[@intCast(@intFromEnum(index))];
    }
''',
}

# Hand-written wrappers: name -> Zig source (uses `c.` for the boundary).
# Each exists because its C signature carries something the mechanical rules
# deliberately don't guess at: out-params, owned buffers, varargs, callbacks.
OVERRIDES = {
    # ---- varargs: std.fmt instead of printf --------------------------------
    "TraceLog": '''
/// Show trace log messages (LOG_DEBUG, LOG_INFO, LOG_WARNING, LOG_ERROR...).
/// Formats with std.fmt; messages longer than 1023 bytes are truncated.
pub fn traceLog(logLevel: TraceLogLevel, comptime format: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    const text = std.fmt.bufPrintSentinel(&buffer, format, args, 0) catch blk: {
        buffer[buffer.len - 1] = 0;
        break :blk buffer[0 .. buffer.len - 1 :0];
    };
    c.TraceLog(@backingInt(logLevel), "%s", text.ptr);
}
''',
    "TextFormat": '''
/// Text formatting with variables (std.fmt syntax). Like raylib's TextFormat,
/// the result lives in one of a few internal static buffers: it is valid until
/// the same buffer is reused several calls later. Truncates at 1023 bytes.
pub fn textFormat(comptime format: []const u8, args: anytype) [:0]const u8 {
    const S = struct {
        threadlocal var buffers: [4][1024]u8 = undefined;
        threadlocal var index: usize = 0;
    };
    const buffer = &S.buffers[S.index];
    S.index = (S.index + 1) % S.buffers.len;
    return std.fmt.bufPrintSentinel(buffer, format, args, 0) catch blk: {
        buffer[buffer.len - 1] = 0;
        break :blk buffer[0 .. buffer.len - 1 :0];
    };
}
''',
    # ---- callbacks: raw C function pointers --------------------------------
    "SetTraceLogCallback": '''
/// Set custom trace log callback (raw C callback; `args` is a C va_list).
pub fn setTraceLogCallback(callback: TraceLogCallback) void {
    c.SetTraceLogCallback(callback);
}
''',
    "SetLoadFileDataCallback": '''
/// Set custom file binary data loader (raw C callback).
pub fn setLoadFileDataCallback(callback: LoadFileDataCallback) void {
    c.SetLoadFileDataCallback(callback);
}
''',
    "SetSaveFileDataCallback": '''
/// Set custom file binary data saver (raw C callback).
pub fn setSaveFileDataCallback(callback: SaveFileDataCallback) void {
    c.SetSaveFileDataCallback(callback);
}
''',
    "SetLoadFileTextCallback": '''
/// Set custom file text data loader (raw C callback).
pub fn setLoadFileTextCallback(callback: LoadFileTextCallback) void {
    c.SetLoadFileTextCallback(callback);
}
''',
    "SetSaveFileTextCallback": '''
/// Set custom file text data saver (raw C callback).
pub fn setSaveFileTextCallback(callback: SaveFileTextCallback) void {
    c.SetSaveFileTextCallback(callback);
}
''',
    "SetAudioStreamCallback": '''
/// Audio thread callback to request new data (raw C callback).
pub fn setAudioStreamCallback(stream: AudioStream, callback: AudioCallback) void {
    c.SetAudioStreamCallback(stream, callback);
}
''',
    "AttachAudioStreamProcessor": '''
/// Attach audio stream processor to stream, receives frames x 2 samples as 'float' (stereo).
pub fn attachAudioStreamProcessor(stream: AudioStream, processor: AudioCallback) void {
    c.AttachAudioStreamProcessor(stream, processor);
}
''',
    "DetachAudioStreamProcessor": '''
/// Detach audio stream processor from stream.
pub fn detachAudioStreamProcessor(stream: AudioStream, processor: AudioCallback) void {
    c.DetachAudioStreamProcessor(stream, processor);
}
''',
    "AttachAudioMixedProcessor": '''
/// Attach audio stream processor to the entire audio pipeline, receives frames x 2 samples as 'float' (stereo).
pub fn attachAudioMixedProcessor(processor: AudioCallback) void {
    c.AttachAudioMixedProcessor(processor);
}
''',
    "DetachAudioMixedProcessor": '''
/// Detach audio stream processor from the entire audio pipeline.
pub fn detachAudioMixedProcessor(processor: AudioCallback) void {
    c.DetachAudioMixedProcessor(processor);
}
''',
    # ---- file data: owned buffers as slices --------------------------------
    "LoadFileData": '''
/// Load file data as byte array (read). Free with `unloadFileData`.
pub fn loadFileData(fileName: [:0]const u8) error{LoadFailed}![]u8 {
    var dataSize: c_int = 0;
    const data = c.LoadFileData(fileName.ptr, &dataSize) orelse return error.LoadFailed;
    return data[0..@intCast(dataSize)];
}
''',
    "UnloadFileData": '''
/// Unload file data allocated by `loadFileData`.
pub fn unloadFileData(data: []u8) void {
    c.UnloadFileData(data.ptr);
}
''',
    "LoadFileText": '''
/// Load text data from file (read). Free with `unloadFileText`.
pub fn loadFileText(fileName: [:0]const u8) error{LoadFailed}![:0]u8 {
    const text = c.LoadFileText(fileName.ptr) orelse return error.LoadFailed;
    return std.mem.span(text);
}
''',
    "UnloadFileText": '''
/// Unload file text data allocated by `loadFileText`.
pub fn unloadFileText(text: [:0]u8) void {
    c.UnloadFileText(text.ptr);
}
''',
    "CompressData": '''
/// Compress data (DEFLATE algorithm). Free with `memFree`.
pub fn compressData(data: []const u8) error{CompressFailed}![]u8 {
    var size: c_int = 0;
    const out = c.CompressData(data.ptr, @intCast(data.len), &size) orelse return error.CompressFailed;
    return out[0..@intCast(size)];
}
''',
    "DecompressData": '''
/// Decompress data (DEFLATE algorithm). Free with `memFree`.
pub fn decompressData(compData: []const u8) error{DecompressFailed}![]u8 {
    var size: c_int = 0;
    const out = c.DecompressData(compData.ptr, @intCast(compData.len), &size) orelse return error.DecompressFailed;
    return out[0..@intCast(size)];
}
''',
    "EncodeDataBase64": '''
/// Encode data to Base64 string (includes NULL terminator). Free with `memFree`.
pub fn encodeDataBase64(data: []const u8) error{EncodeFailed}![:0]u8 {
    var size: c_int = 0;
    const out = c.EncodeDataBase64(data.ptr, @intCast(data.len), &size) orelse return error.EncodeFailed;
    return std.mem.span(out);
}
''',
    "DecodeDataBase64": '''
/// Decode Base64 string. Free with `memFree`.
pub fn decodeDataBase64(text: [:0]const u8) error{DecodeFailed}![]u8 {
    var size: c_int = 0;
    const out = c.DecodeDataBase64(text.ptr, &size) orelse return error.DecodeFailed;
    return out[0..@intCast(size)];
}
''',
    "ComputeCRC32": '''
/// Compute CRC32 hash code.
pub fn computeCRC32(data: []const u8) u32 {
    return c.ComputeCRC32(@constCast(data.ptr), @intCast(data.len));
}
''',
    "ComputeMD5": '''
/// Compute MD5 hash code (returned array lives in a static buffer).
pub fn computeMD5(data: []const u8) *const [4]u32 {
    return @ptrCast(c.ComputeMD5(@constCast(data.ptr), @intCast(data.len)));
}
''',
    "ComputeSHA1": '''
/// Compute SHA1 hash code (returned array lives in a static buffer).
pub fn computeSHA1(data: []const u8) *const [5]u32 {
    return @ptrCast(c.ComputeSHA1(@constCast(data.ptr), @intCast(data.len)));
}
''',
    "ComputeSHA256": '''
/// Compute SHA256 hash code (returned array lives in a static buffer).
pub fn computeSHA256(data: []const u8) *const [8]u32 {
    return @ptrCast(c.ComputeSHA256(@constCast(data.ptr), @intCast(data.len)));
}
''',
    "SaveFileData": '''
/// Save data to file from byte array (write), returns true on success.
pub fn saveFileData(fileName: [:0]const u8, data: []const u8) bool {
    return c.SaveFileData(fileName.ptr, @constCast(data.ptr), @intCast(data.len));
}
''',
    "SaveFileText": '''
/// Save text data to file (write), returns true on success.
pub fn saveFileText(fileName: [:0]const u8, text: [:0]const u8) bool {
    return c.SaveFileText(fileName.ptr, text.ptr);
}
''',
    # ---- images / colors ---------------------------------------------------
    "LoadImageColors": '''
/// Load color data from image as a Color array (RGBA - 32bit). Free with `unloadImageColors`.
pub fn loadImageColors(image: Image) error{LoadFailed}![]Color {
    const colors = c.LoadImageColors(image) orelse return error.LoadFailed;
    return colors[0..@intCast(image.width * image.height)];
}
''',
    "LoadImagePalette": '''
/// Load colors palette from image as a Color array (RGBA - 32bit). Free with `unloadImagePalette`.
pub fn loadImagePalette(image: Image, maxPaletteSize: i32) error{LoadFailed}![]Color {
    var count: c_int = 0;
    const colors = c.LoadImagePalette(image, maxPaletteSize, &count) orelse return error.LoadFailed;
    return colors[0..@intCast(count)];
}
''',
    "UnloadImageColors": '''
/// Unload color data loaded with `loadImageColors`.
pub fn unloadImageColors(colors: []Color) void {
    c.UnloadImageColors(colors.ptr);
}
''',
    "UnloadImagePalette": '''
/// Unload colors palette loaded with `loadImagePalette`.
pub fn unloadImagePalette(colors: []Color) void {
    c.UnloadImagePalette(colors.ptr);
}
''',
    "ImageText": '''
/// Create an image from text (default font).
pub fn imageText(text: [:0]const u8, fontSize: i32, color: Color) Image {
    return c.ImageText(text.ptr, fontSize, color);
}
''',
    "LoadImageAnim": '''
pub const ImageAnim = struct { image: Image, frames: i32 };

/// Load image sequence from file (frames appended to image.data).
pub fn loadImageAnim(fileName: [:0]const u8) error{LoadFailed}!ImageAnim {
    var frames: c_int = 0;
    const image = c.LoadImageAnim(fileName.ptr, &frames);
    if (!c.IsImageValid(image)) return error.LoadFailed;
    return .{ .image = image, .frames = frames };
}
''',
    "LoadImageAnimFromMemory": '''
/// Load image sequence from memory buffer (fileType: ".gif").
pub fn loadImageAnimFromMemory(fileType: [:0]const u8, fileData: []const u8) error{LoadFailed}!ImageAnim {
    var frames: c_int = 0;
    const image = c.LoadImageAnimFromMemory(fileType.ptr, fileData.ptr, @intCast(fileData.len), &frames);
    if (!c.IsImageValid(image)) return error.LoadFailed;
    return .{ .image = image, .frames = frames };
}
''',
    "ExportImageToMemory": '''
/// Export image to memory buffer (fileType: ".png"...). Free with `memFree`.
pub fn exportImageToMemory(image: Image, fileType: [:0]const u8) error{ExportFailed}![]u8 {
    var size: c_int = 0;
    const data = c.ExportImageToMemory(image, fileType.ptr, &size) orelse return error.ExportFailed;
    return data[0..@intCast(size)];
}
''',
    # ---- text / codepoints -------------------------------------------------
    "LoadFontData": '''
/// Load font data for further use. Free with `unloadFontData`.
pub fn loadFontData(fileData: []const u8, fontSize: i32, codepoints: ?[]const i32, @"type": FontType) error{LoadFailed}![]GlyphInfo {
    var glyphCount: c_int = 0;
    const cps: [*c]const c_int = if (codepoints) |cp| cp.ptr else null;
    const count: c_int = if (codepoints) |cp| @intCast(cp.len) else 0;
    const glyphs = c.LoadFontData(fileData.ptr, @intCast(fileData.len), fontSize, @constCast(cps), count, @backingInt(@"type"), &glyphCount) orelse return error.LoadFailed;
    return glyphs[0..@intCast(glyphCount)];
}
''',
    "GenImageFontAtlas": '''
/// Generate image font atlas using chars info. `glyphRecs` receives a
/// raylib-allocated rectangle array (free with `memFree`).
pub fn genImageFontAtlas(glyphs: []const GlyphInfo, glyphRecs: *[*]Rectangle, fontSize: i32, padding: i32, packMethod: i32) Image {
    return c.GenImageFontAtlas(glyphs.ptr, @ptrCast(glyphRecs), @intCast(glyphs.len), fontSize, padding, packMethod);
}
''',
    "LoadCodepoints": '''
/// Load all codepoints from a UTF-8 text string. Free with `unloadCodepoints`.
pub fn loadCodepoints(text: [:0]const u8) error{LoadFailed}![]i32 {
    var count: c_int = 0;
    const codepoints = c.LoadCodepoints(text.ptr, &count) orelse return error.LoadFailed;
    return codepoints[0..@intCast(count)];
}
''',
    "UnloadCodepoints": '''
/// Unload codepoints data from memory.
pub fn unloadCodepoints(codepoints: []i32) void {
    c.UnloadCodepoints(codepoints.ptr);
}
''',
    "LoadUTF8": '''
/// Load UTF-8 text encoded from codepoints array. Free with `unloadUTF8`.
pub fn loadUTF8(codepoints: []const i32) error{LoadFailed}![:0]u8 {
    const text = c.LoadUTF8(codepoints.ptr, @intCast(codepoints.len)) orelse return error.LoadFailed;
    return std.mem.span(text);
}
''',
    "UnloadUTF8": '''
/// Unload UTF-8 text encoded from codepoints array.
pub fn unloadUTF8(text: [:0]u8) void {
    c.UnloadUTF8(text.ptr);
}
''',
    "GetCodepoint": '''
pub const CodepointResult = struct { codepoint: i32, size: i32 };

/// Get next codepoint in a UTF-8 encoded string and its size in bytes; 0x3f('?') on failure.
pub fn getCodepoint(text: [:0]const u8) CodepointResult {
    var size: c_int = 0;
    const codepoint = c.GetCodepoint(text.ptr, &size);
    return .{ .codepoint = codepoint, .size = size };
}
''',
    "GetCodepointNext": '''
/// Get next codepoint in a UTF-8 encoded string and its size in bytes; 0x3f('?') on failure.
pub fn getCodepointNext(text: [:0]const u8) CodepointResult {
    var size: c_int = 0;
    const codepoint = c.GetCodepointNext(text.ptr, &size);
    return .{ .codepoint = codepoint, .size = size };
}
''',
    "GetCodepointPrevious": '''
/// Get previous codepoint in a UTF-8 encoded string and its size in bytes; 0x3f('?') on failure.
pub fn getCodepointPrevious(text: [:0]const u8) CodepointResult {
    var size: c_int = 0;
    const codepoint = c.GetCodepointPrevious(text.ptr, &size);
    return .{ .codepoint = codepoint, .size = size };
}
''',
    "CodepointToUTF8": '''
/// Encode one codepoint into UTF-8 bytes (slice into a static buffer).
pub fn codepointToUTF8(codepoint: i32) []const u8 {
    var size: c_int = 0;
    const bytes = c.CodepointToUTF8(codepoint, &size);
    return bytes[0..@intCast(size)];
}
''',
    "TextCopy": '''
/// Copy one string to another, returns bytes copied. `dst` must be large
/// enough for `src` plus its terminator (C semantics, unchecked).
pub fn textCopy(dst: [*]u8, src: [:0]const u8) i32 {
    return c.TextCopy(dst, src.ptr);
}
''',
    "TextAppend": '''
/// Append text at specific position and move cursor. `text` must have room
/// (C semantics, unchecked).
pub fn textAppend(text: [*]u8, append: [:0]const u8, position: *i32) void {
    c.TextAppend(text, append.ptr, position);
}
''',
    "TextSplit": '''
/// Split text into multiple strings (static memory, valid until the next call).
pub fn textSplit(text: [:0]const u8, delimiter: u8) []const [*:0]const u8 {
    var count: c_int = 0;
    const parts = c.TextSplit(text.ptr, delimiter, &count);
    return @as([*]const [*:0]const u8, @ptrCast(parts))[0..@intCast(count)];
}
''',
    "TextJoin": '''
/// Join text strings with delimiter (static memory).
pub fn textJoin(textList: []const [*:0]const u8, delimiter: [:0]const u8) [:0]const u8 {
    return std.mem.span(c.TextJoin(@ptrCast(@constCast(textList.ptr)), @intCast(textList.len), delimiter.ptr));
}
''',
    "LoadTextLines": '''
/// Load text as separate lines ('\\n'). Free with `unloadTextLines`.
pub fn loadTextLines(text: [:0]const u8) error{LoadFailed}![][*:0]u8 {
    var count: c_int = 0;
    const lines = c.LoadTextLines(text.ptr, &count) orelse return error.LoadFailed;
    return @as([*][*:0]u8, @ptrCast(lines))[0..@intCast(count)];
}
''',
    "UnloadTextLines": '''
/// Unload text lines loaded with `loadTextLines`.
pub fn unloadTextLines(lines: [][*:0]u8) void {
    c.UnloadTextLines(@ptrCast(lines.ptr), @intCast(lines.len));
}
''',
    # ---- models / audio ----------------------------------------------------
    "LoadMaterials": '''
/// Load materials from model file. Free each with `unloadMaterial`, then the array with `memFree`.
pub fn loadMaterials(fileName: [:0]const u8) error{LoadFailed}![]Material {
    var count: c_int = 0;
    const materials = c.LoadMaterials(fileName.ptr, &count) orelse return error.LoadFailed;
    return materials[0..@intCast(count)];
}
''',
    "LoadModelAnimations": '''
/// Load model animations from file. Free with `unloadModelAnimations`.
pub fn loadModelAnimations(fileName: [:0]const u8) error{LoadFailed}![]ModelAnimation {
    var count: c_int = 0;
    const animations = c.LoadModelAnimations(fileName.ptr, &count) orelse return error.LoadFailed;
    return animations[0..@intCast(count)];
}
''',
    "LoadWaveSamples": '''
/// Load samples data from wave as a 32bit float data array. Free with `unloadWaveSamples`.
pub fn loadWaveSamples(wave: Wave) error{LoadFailed}![]f32 {
    const samples = c.LoadWaveSamples(wave) orelse return error.LoadFailed;
    return samples[0 .. wave.frameCount * wave.channels];
}
''',
    "UnloadWaveSamples": '''
/// Unload samples data loaded with `loadWaveSamples`.
pub fn unloadWaveSamples(samples: []f32) void {
    c.UnloadWaveSamples(samples.ptr);
}
''',
    "LoadRandomSequence": '''
/// Load random values sequence, no values repeated. Free with `unloadRandomSequence`.
pub fn loadRandomSequence(count: u32, min: i32, max: i32) error{LoadFailed}![]i32 {
    const sequence = c.LoadRandomSequence(count, min, max) orelse return error.LoadFailed;
    return sequence[0..count];
}
''',
    "UnloadRandomSequence": '''
/// Unload random values sequence.
pub fn unloadRandomSequence(sequence: []i32) void {
    c.UnloadRandomSequence(sequence.ptr);
}
''',
}

MATH_OVERRIDES = {
    "QuaternionToAxisAngle": '''
/// Get the rotation angle and axis for a given quaternion
pub fn quaternionToAxisAngle(q: Quaternion, outAxis: *Vector3, outAngle: *f32) void {
    c.QuaternionToAxisAngle(q, outAxis, outAngle);
}
''',
}

# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------

def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class Param:
    def __init__(self, ctype, name):
        self.ctype = " ".join(ctype.split())
        self.name = name

    @property
    def base(self):
        return self.ctype.replace("const ", "").replace("*", "").strip()

    @property
    def stars(self):
        return self.ctype.count("*")

    @property
    def is_const(self):
        return self.ctype.startswith("const ")


def split_decl(decl):
    """'const char *fileName' -> Param('const char *', 'fileName')"""
    decl = decl.strip()
    m = re.match(r"(.*?)([A-Za-z_]\w*)\s*$", decl)
    ctype, name = m.group(1), m.group(2)
    return Param(ctype.replace(" *", "*").replace("*", " *").strip(), name)


def parse_functions(src, prefix="RLAPI "):
    """RLAPI prototypes (raylib.h, comment trailing) or RMAPI definitions
    (raymath.h, comment on the preceding line)."""
    funcs = []
    lines = src.splitlines()
    for i, line in enumerate(lines):
        if not line.startswith(prefix):
            continue
        if "//" in line:
            comment = line.split("//", 1)[1].strip()
        else:
            above = lines[i - 1].strip()
            comment = above[2:].strip() if above.startswith("//") else ""
        decl = line.split("//", 1)[0].strip()[len(prefix):].rstrip(";").strip()
        head, args = decl.split("(", 1)
        args = args.rsplit(")", 1)[0].strip()
        ret = split_decl(head)
        params = []
        if args and args != "void":
            for a in args.split(","):
                a = a.strip()
                params.append(Param("...", "...") if a == "..." else split_decl(a))
        funcs.append((ret.name, ret, params, comment))
    return funcs


def parse_structs(src):
    clean = strip_comments(src)
    structs = []
    for m in re.finditer(r"typedef struct (\w+) \{(.*?)\} (\w+);", clean, re.S):
        name, body = m.group(3), m.group(2)
        fields = []
        for decl in body.split(";"):
            decl = " ".join(decl.split())
            if not decl:
                continue
            fm = re.match(r"((?:const |unsigned |struct )*\w+\s*\**)\s*(.*)$", decl)
            ctype = fm.group(1)
            for item in fm.group(2).split(","):
                item = item.strip()
                stars = ctype.count("*") + len(item) - len(item.lstrip("*"))
                item = item.lstrip("*")
                am = re.match(r"(\w+)(?:\[(\w+)\])?", item)
                fields.append((ctype.replace("*", "").strip(), stars, am.group(1), am.group(2)))
        structs.append((name, fields))
    aliases = re.findall(r"^typedef (\w+) (\w+);", clean, re.M)
    pointer_aliases = re.findall(r"^typedef (\w+) \*(\w+);", clean, re.M)
    return structs, aliases, pointer_aliases


def parse_enums(src):
    """Enums with members (name, value, comment), plus #define member aliases."""
    enums = []
    for m in re.finditer(r"typedef enum \{(.*?)\} (\w+);", src, re.S):
        members, nxt = [], 0
        for line in m.group(1).splitlines():
            comment = line.split("//", 1)[1].strip() if "//" in line else ""
            code = line.split("//", 1)[0].strip().rstrip(",").strip()
            if not code:
                continue
            name, _, init = code.partition("=")
            name = name.strip()
            if init.strip():
                nxt = int(init.strip(), 0)
            members.append((name, nxt, comment))
            nxt += 1
        enums.append((m.group(2), members))
    return enums


def parse_colors(src):
    return re.findall(r"^#define (\w+)\s+CLITERAL\(Color\)\{ *(\d+), *(\d+), *(\d+), *(\d+) *\}\s*//\s*(.*)$", src, re.M)


def parse_enum_aliases(src, member_names):
    out = []
    for m in re.finditer(r"^#define (\w+)\s+(\w+)\s*(?://.*)?$", src, re.M):
        if m.group(2) in member_names:
            out.append((m.group(1), m.group(2)))
    return out


# --------------------------------------------------------------------------
# Naming
# --------------------------------------------------------------------------

def zig_ident(name):
    return f'@"{name}"' if name in ZIG_KEYWORDS or not re.match(r"[A-Za-z_]", name) else name


def camel(name):
    return name[0].lower() + name[1:]


def common_prefix(names):
    prefix = names[0]
    for n in names[1:]:
        while not n.startswith(prefix):
            prefix = prefix[:-1]
    return prefix[: prefix.rfind("_") + 1] if "_" in prefix else ""


# --------------------------------------------------------------------------
# Generation
# --------------------------------------------------------------------------

class Gen:
    def __init__(self, src):
        self.src = src
        self.structs, self.aliases, self.pointer_aliases = parse_structs(src)
        self.struct_names = ({n for n, _ in self.structs} | {a for _, a in self.aliases}
                             | {a for _, a in self.pointer_aliases})
        self.enums = parse_enums(src)
        self.enum_names = {n for n, _ in self.enums}
        self.funcs = parse_functions(src)
        self.math_src = RAYMATH.read_text()
        self.math_funcs = parse_functions(self.math_src, "RMAPI ")
        self.struct_names |= {"float3", "float16"}
        self.callbacks = re.findall(r"^typedef (.+?)\(\*(\w+)\)\((.*?)\);", src, re.M)
        self.callback_names = {n for _, n, _ in self.callbacks}
        self.errors = []

    # --- C boundary types ----------------------------------------------------
    def c_type(self, p):
        base, stars = p.base, p.stars
        if base in C_SCALARS:
            z = C_SCALARS[base][0]
        elif base in self.struct_names or base in self.callback_names:
            z = base
        elif base in ("rAudioBuffer", "rAudioProcessor"):
            z = "anyopaque"
        else:
            raise ValueError(f"unknown C type {p.ctype}")
        if base == "void" and stars:
            z = "anyopaque"
            t = "?*const anyopaque" if p.is_const else "?*anyopaque"
            for _ in range(stars - 1):
                t = f"[*c]{t}"
            return t
        for i in range(stars):
            z = f"[*c]{'const ' if p.is_const and i == 0 else ''}{z}"
        return z

    # --- idiomatic types ------------------------------------------------------
    def api_scalar(self, base):
        if base in C_SCALARS:
            return C_SCALARS[base][1]
        return base

    def enum_for(self, fname, pname):
        for pat, name, enum in PARAM_ENUMS:
            if pname == name and re.search(pat, fname):
                return enum
        return None

    def wrap_function(self, fname, ret, params, comment):
        if fname in OVERRIDES:
            return OVERRIDES[fname].strip("\n")
        sig, call = [], []
        i = 0
        while i < len(params):
            p = params[i]
            nxt = params[i + 1] if i + 1 < len(params) else None
            pn = zig_ident(PARAM_RENAMES.get((fname, p.name), p.name))
            if pn in RESERVED_PARAMS:
                raise ValueError(f"param '{pn}' shadows a module-level name; add a PARAM_RENAMES entry")
            if p.ctype == "...":
                raise ValueError("varargs")
            enum = self.enum_for(fname, p.name)
            if enum and p.stars == 0:
                sig.append(f"{pn}: {enum}")
                call.append(f"@bitCast({pn})" if enum in FLAG_ENUMS else f"@backingInt({pn})")
            elif p.base == "char" and p.stars == 1 and p.is_const:
                if (fname, p.name) in NULLABLE_STRINGS:
                    sig.append(f"{pn}: ?[:0]const u8")
                    call.append(f"if ({pn}) |s| s.ptr else null")
                else:
                    sig.append(f"{pn}: [:0]const u8")
                    call.append(f"{pn}.ptr")
            elif (p.stars == 1 and nxt is not None and nxt.stars == 0 and nxt.base in ("int", "unsigned int")
                  and COUNT_NAMES.search(nxt.name) and p.base != "char"
                  and (fname, p.name) not in NOT_SLICES):
                elem = "u8" if p.base == "void" else self.api_scalar(p.base)
                if p.base == "char":
                    raise ValueError("char slice")
                sig.append(f"{pn}: []{'const ' if p.is_const else ''}{elem}")
                ptr = f"{pn}.ptr"
                if p.base == "void":
                    ptr = f"@ptrCast({pn}.ptr)"
                elif p.base in C_SCALARS and C_SCALARS[p.base][0] != elem:
                    ptr = f"@ptrCast({pn}.ptr)"
                call.append(ptr)
                call.append(f"@intCast({pn}.len)")
                i += 2
                continue
            elif p.stars == 1 and p.base in self.struct_names:
                sig.append(f"{pn}: *{'const ' if p.is_const else ''}{p.base}")
                call.append(pn)
            elif p.stars == 1 and p.base == "void":
                sig.append(f"{pn}: *{'const ' if p.is_const else ''}anyopaque")
                call.append(pn)
            elif p.stars == 0 and p.base in C_SCALARS:
                sig.append(f"{pn}: {self.api_scalar(p.base)}")
                call.append(pn)
            elif p.stars == 0 and (p.base in self.struct_names or p.base in self.callback_names):
                sig.append(f"{pn}: {p.base}")
                call.append(pn)
            else:
                raise ValueError(f"param {p.ctype} {p.name}")
            i += 1

        name = camel(fname)
        args = ", ".join(sig)
        cargs = ", ".join(call)
        doc = f"/// {comment}\n" if comment else ""
        if fname in VALIDATED_LOADERS:
            if ret.stars != 0:
                raise ValueError("pointer loader")
            check = VALIDATED_LOADERS[fname]
            return (f"{doc}pub fn {name}({args}) error{{LoadFailed}}!{ret.base} {{\n"
                    f"    const result = c.{fname}({cargs});\n"
                    f"    if (!c.{check}(result)) return error.LoadFailed;\n"
                    f"    return result;\n}}")
        if ret.base == "char" and ret.stars == 1 and ret.is_const:
            if fname in NULLABLE_STRING_RETURNS:
                return (f"{doc}pub fn {name}({args}) ?[:0]const u8 {{\n"
                        f"    const result = c.{fname}({cargs}) orelse return null;\n"
                        f"    return std.mem.span(result);\n}}")
            return f"{doc}pub fn {name}({args}) [:0]const u8 {{\n    return std.mem.span(c.{fname}({cargs}));\n}}"
        if ret.base == "char" and ret.stars == 1 and not ret.is_const:
            # rtext: `TextX` returns raylib's static buffer (never NULL);
            # `TextXAlloc` returns caller-owned memory (NULL on failure).
            if fname.endswith("Alloc"):
                return (f"{doc}/// Caller owns the result: free with `memFree`.\n"
                        f"pub fn {name}({args}) ?[:0]u8 {{\n"
                        f"    const result = c.{fname}({cargs}) orelse return null;\n"
                        f"    return std.mem.span(result);\n}}")
            return f"{doc}pub fn {name}({args}) [:0]const u8 {{\n    return std.mem.span(c.{fname}({cargs}));\n}}"
        if fname in RETURN_ENUMS:
            enum = RETURN_ENUMS[fname]
            return f"{doc}pub fn {name}({args}) {enum} {{\n    return @enumFromInt(c.{fname}({cargs}));\n}}"
        if ret.stars == 0 and (ret.base in C_SCALARS or ret.base in self.struct_names):
            rt = self.api_scalar(ret.base)
            body = f"c.{fname}({cargs})"
            stmt = f"{body};" if rt == "void" else f"return {body};"
            return f"{doc}pub fn {name}({args}) {rt} {{\n    {stmt}\n}}"
        if ret.base == "void" and ret.stars == 1:
            return f"{doc}pub fn {name}({args}) ?*anyopaque {{\n    return c.{fname}({cargs});\n}}"
        raise ValueError(f"return {ret.ctype}")

    # --- emit ------------------------------------------------------------------
    def emit_c(self, shim=False):
        out = [HEADER_C_EXDIFF if shim else HEADER_C]
        for rt, name, args in self.callbacks:
            ps = [] if args.strip() == "void" else [split_decl(a) for a in args.split(",")]
            cps = []
            for p in ps:
                cps.append("?*anyopaque" if p.base == "va_list" else self.c_type(p))
            r = self.c_type(split_decl(rt.strip() + " x"))
            out.append(f"pub const {name} = ?*const fn ({', '.join(cps)}) callconv(.c) {r};")
        out.append("")
        for fname, ret, params, _ in self.funcs + self.math_funcs:
            cps = []
            for p in params:
                cps.append("..." if p.ctype == "..." else f"{zig_ident(p.name)}: {self.c_type(p)}")
            if shim and fname in EXDIFF_SHIMMED:
                out.append(f"extern fn Exdiff{fname}({', '.join(cps)}) {self.c_type(ret)};")
                out.append(f"pub const {fname} = Exdiff{fname};")
            else:
                out.append(f"pub extern fn {fname}({', '.join(cps)}) {self.c_type(ret)};")
        out.append("")
        return "\n".join(out)

    def field_type(self, sname, base, stars, name, array):
        enum = FIELD_ENUMS.get((sname, name))
        if enum:
            return enum
        if base in ("rAudioBuffer", "rAudioProcessor") or (base == "void" and stars):
            z = "anyopaque"
            t = f"?*{z}"
            for _ in range(stars - 1):
                t = f"?[*]{t}"
            return t
        if base == "char" and stars:
            # `char *` fields are NUL-terminated strings (FilePathList.paths).
            t = "[*:0]u8"
            for _ in range(stars - 1):
                t = f"[*]{t}"
            return f"?{t}"
        z = self.api_scalar(base) if base in C_SCALARS else base
        if base in C_SCALARS:
            z = {"int": "c_int", "unsigned int": "c_uint"}.get(base, z)
        if stars == 0:
            return f"[{array}]{z}" if array else z
        t = z
        for i in range(stars):
            t = f"?[*]{t}"
        return t

    def emit_api(self):
        out = [HEADER_API]
        # Types
        out.append("// " + "-" * 74 + "\n// Structures\n// " + "-" * 74)
        for sname, fields in self.structs:
            out.append(f"pub const {sname} = extern struct {{")
            for base, stars, fname, array in fields:
                out.append(f"    {zig_ident(fname)}: {self.field_type(sname, base, stars, fname, array)},")
            if sname in STRUCT_METHODS:
                out.append(STRUCT_METHODS[sname].rstrip("\n"))
            if sname == "Color":
                out.append("")
                for cname, r, g, b, a, comment in parse_colors(self.src):
                    zname = COLOR_NAMES.get(cname, cname.lower())
                    out.append(f"    pub const {zname}: Color = .{{ .r = {r}, .g = {g}, .b = {b}, .a = {a} }}; // {comment.strip()}")
            out.append("};\n")
        for target, alias in self.aliases:
            out.append(f"pub const {alias} = {target};")
        for target, alias in self.pointer_aliases:
            out.append(f"pub const {alias} = ?[*]{target};")
        out.append("")
        for _, name, _ in self.callbacks:
            out.append(f"pub const {name} = c.{name};")
        out.append("")
        # Enums
        out.append("// " + "-" * 74 + "\n// Enumerators\n// " + "-" * 74)
        all_members = {m for _, ms in self.enums for m, _, _ in ms}
        aliases = parse_enum_aliases(self.src, all_members)
        for ename, members in self.enums:
            prefix = common_prefix([m for m, _, _ in members])
            if ename in FLAG_ENUMS:
                out.append(self.emit_flags(ename, members, prefix))
                continue
            out.append(f"pub const {ename} = enum({ENUM_BACKING.get(ename, 'c_int')}) {{")
            for m, v, comment in members:
                tag = zig_ident(m[len(prefix):].lower())
                out.append(f"    {tag} = {v},{(' // ' + comment) if comment else ''}")
            if ename in OPEN_ENUMS:
                out.append("    _,")
            names = {m for m, _, _ in members}
            for alias, target in aliases:
                if target in names and alias.startswith(prefix):
                    out.append(f"\n    pub const {zig_ident(alias[len(prefix):].lower())}: {ename} = .{zig_ident(target[len(prefix):].lower())};")
            out.append("};\n")
        # Functions
        out.append("// " + "-" * 74 + "\n// Functions\n// " + "-" * 74)
        for fname, ret, params, comment in self.funcs:
            try:
                out.append(self.wrap_function(fname, ret, params, comment) + "\n")
            except ValueError as e:
                self.errors.append(f"{fname}: {e}")
        out.append(self.emit_math())
        return "\n".join(out)

    def emit_math(self):
        out = ["// " + "-" * 74,
               "// raymath — vector, matrix and quaternion math (raymath.h)",
               "// " + "-" * 74,
               "",
               "/// raymath: same functions as raymath.h, first letter lower-cased",
               "/// (`Vector2Add` -> `rl.math.vector2Add`).",
               "pub const math = struct {",
               "    pub const float3 = extern struct { v: [3]f32 };",
               "    pub const float16 = extern struct { v: [16]f32 };",
               ""]
        for fname, ret, params, comment in self.math_funcs:
            try:
                body = MATH_OVERRIDES.get(fname) or self.wrap_function(fname, ret, params, comment)
            except ValueError as e:
                self.errors.append(f"raymath {fname}: {e}")
                continue
            out.extend("    " + l if l else "" for l in body.strip("\n").splitlines())
            out.append("")
        out.append("};")
        return "\n".join(out)

    def emit_flags(self, ename, members, prefix):
        by_bit = {}
        for m, v, comment in members:
            if v & (v - 1) or v == 0:
                raise SystemExit(f"{ename}.{m} is not a single bit")
            by_bit[v.bit_length() - 1] = (m[len(prefix):].lower(), comment)
        lines = [f"pub const {ename} = packed struct(u32) {{"]
        pad = 0
        for bit in range(32):
            if bit in by_bit:
                tag, comment = by_bit[bit]
                lines.append(f"    {zig_ident(tag)}: bool = false,{(' // ' + comment) if comment else ''}")
            else:
                lines.append(f"    _unused{pad}: u1 = 0,")
                pad += 1
        lines.append("};\n")
        return "\n".join(lines)


HEADER_C = '''// GENERATED by tools/gen_api.py from vendor/raylib/src/raylib.h — do not edit.
//
// The C boundary of the idiomatic Zig API: exact-C declarations of the
// raylib.h exports the port provides. This is the only file in src/api that
// uses C-shaped types; src/api/raylib.zig wraps every function idiomatically.

const raylib = @import("raylib");
const Vector2 = raylib.Vector2;
const Vector3 = raylib.Vector3;
const Vector4 = raylib.Vector4;
const Quaternion = raylib.Quaternion;
const Matrix = raylib.Matrix;
const Color = raylib.Color;
const Rectangle = raylib.Rectangle;
const Image = raylib.Image;
const Texture = raylib.Texture;
const Texture2D = raylib.Texture2D;
const TextureCubemap = raylib.TextureCubemap;
const RenderTexture = raylib.RenderTexture;
const RenderTexture2D = raylib.RenderTexture2D;
const NPatchInfo = raylib.NPatchInfo;
const GlyphInfo = raylib.GlyphInfo;
const Font = raylib.Font;
const Camera3D = raylib.Camera3D;
const Camera = raylib.Camera;
const Camera2D = raylib.Camera2D;
const Mesh = raylib.Mesh;
const Shader = raylib.Shader;
const MaterialMap = raylib.MaterialMap;
const Material = raylib.Material;
const Transform = raylib.Transform;
const BoneInfo = raylib.BoneInfo;
const ModelSkeleton = raylib.ModelSkeleton;
const ModelAnimPose = raylib.ModelAnimPose;
const Model = raylib.Model;
const ModelAnimation = raylib.ModelAnimation;
const Ray = raylib.Ray;
const RayCollision = raylib.RayCollision;
const BoundingBox = raylib.BoundingBox;
const Wave = raylib.Wave;
const AudioStream = raylib.AudioStream;
const Sound = raylib.Sound;
const Music = raylib.Music;
const VrDeviceInfo = raylib.VrDeviceInfo;
const VrStereoConfig = raylib.VrStereoConfig;
const FilePathList = raylib.FilePathList;
const AutomationEvent = raylib.AutomationEvent;
const AutomationEventList = raylib.AutomationEventList;
const float3 = raylib.math.float3;
const float16 = raylib.math.float16;
'''

# Functions the examples gate's determinism shim replaces (tools/exdiff/hooks.c).
EXDIFF_SHIMMED = {"InitWindow", "WindowShouldClose", "GetFrameTime", "GetTime",
                  "GetFPS", "DrawFPS", "SetTargetFPS"}

HEADER_C_EXDIFF = HEADER_C.replace(
    "uses C-shaped types; src/api/raylib.zig wraps every function idiomatically.",
    "uses C-shaped types; src/api/raylib.zig wraps every function idiomatically.\n"
    "//\n// EXDIFF VARIANT — used only by the examples gate (zig build apiexamples):\n"
    "// identical to c.zig except that the functions the determinism shim replaces\n"
    "// resolve to the hooks in tools/exdiff/hooks.c.")

HEADER_API = '''// GENERATED by tools/gen_api.py from vendor/raylib/src/raylib.h — do not edit.
// Rules: docs/zig-api.md. Hand-written wrappers live in gen_api.py OVERRIDES.
//
//   raylib — a simple and easy-to-use library to enjoy videogames programming
//   Copyright (c) 2013-2026 Ramon Santamaria (@raysan5); zlib/libpng license.
//
// The idiomatic Zig API over the C-ABI raylib port: same functions, names and
// types as raylib.h (first letter lower-cased), with slices, [:0]const u8
// strings, real enums, packed flags and error unions on loaders.

const std = @import("std");

/// The exact-C declarations this API wraps (escape hatch for raw access).
/// A named module: build.zig wires it to src/api/c.zig (the examples gate
/// substitutes the generated c_exdiff.zig determinism variant).
pub const c = @import("raylib_c");

// raylib.h math defines, typed f32 like the C macros (DEG2RAD is PI/180.0f).
pub const pi: f32 = 3.14159265358979323846;
pub const deg2rad: f32 = pi / 180.0;
pub const rad2deg: f32 = 180.0 / pi;

/// `std.mem.Allocator` over raylib's MemAlloc/MemRealloc/MemFree: use it for
/// buffers raylib takes ownership of and frees itself (e.g. `Mesh.vertices`
/// handed to `uploadMesh`, released by `unloadMesh`/`unloadModel`).
pub const mem_allocator: std.mem.Allocator = .{ .ptr = undefined, .vtable = &mem_vtable };

const mem_vtable: std.mem.Allocator.VTable = .{
    .alloc = memAllocFn,
    .resize = std.mem.Allocator.noResize,
    .remap = memRemapFn,
    .free = memFreeFn,
};

// MemAlloc is malloc-backed: aligned for any fundamental type, no more.
const mem_max_align = @alignOf(std.c.max_align_t);

fn memAllocFn(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    if (alignment.toByteUnits() > mem_max_align) return null;
    return @ptrCast(c.MemAlloc(std.math.cast(c_uint, len) orelse return null));
}

fn memRemapFn(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, _: usize) ?[*]u8 {
    if (alignment.toByteUnits() > mem_max_align) return null;
    return @ptrCast(c.MemRealloc(memory.ptr, std.math.cast(c_uint, new_len) orelse return null));
}

fn memFreeFn(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
    c.MemFree(memory.ptr);
}
'''


def main():
    gen = Gen(HEADER.read_text())
    api = gen.emit_api()
    if gen.errors:
        print("Functions the rules cannot map (add to OVERRIDES):")
        for e in gen.errors:
            print("  " + e)
        sys.exit(1)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # c.zig must reference only types the generated struct section defines.
    (OUT_DIR / "c.zig").write_text(gen.emit_c())
    (OUT_DIR / "c_exdiff.zig").write_text(gen.emit_c(shim=True))
    (OUT_DIR / "raylib.zig").write_text(api)
    print(f"OK  {len(gen.funcs)} raylib + {len(gen.math_funcs)} raymath functions, "
          f"{len(gen.structs)} structs, {len(gen.enums)} enums -> {OUT_DIR}/")


if __name__ == "__main__":
    main()
