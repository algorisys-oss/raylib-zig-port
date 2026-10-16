//! rlgl - A multi-OpenGL abstraction layer with an immediate-mode style API
//!
//! Zig port of raylib's `rlgl.h` (v6.0), in two configurations chosen at comptime from
//! the target: GRAPHICS_API_OPENGL_33 on the desktop, GRAPHICS_API_OPENGL_ES3 (WebGL 2)
//! on Emscripten. See `graphics_api`.
//! Every public `rl*` function is exported with its exact C name, byte-compatible
//! signature, and C calling convention, so the rest of raylib (still C) links
//! against it unchanged. The vertex-batch accumulation/submission logic mirrors the
//! C source exactly to keep pixel output bit-identical.
//!
//! OpenGL is reached through `glad_gl*` function pointers. On the desktop they are
//! GLAD's, declared in src/gl33.zig and loaded by src/c/glad_impl.c; on the web,
//! src/gles3.zig declares the same names bound directly to Emscripten's WebGL 2
//! functions. raymath helpers and TraceLog are still C and are `extern`-declared here.

const std = @import("std");
const builtin = @import("builtin");

/// rlgl.h's GRAPHICS_API_OPENGL_* switch. Emscripten means a browser, and a browser
/// means WebGL 2, which is OpenGL ES 3.0. Note that rlgl.h defines
/// GRAPHICS_API_OPENGL_ES2 as well whenever ES3 is defined; `es2` below follows it.
pub const GraphicsApi = enum { opengl_33, opengl_es3 };
pub const graphics_api: GraphicsApi = if (builtin.os.tag == .emscripten) .opengl_es3 else .opengl_33;
const es2 = graphics_api == .opengl_es3;

const gl = switch (graphics_api) {
    .opengl_33 => @import("gl33.zig"),
    .opengl_es3 => @import("gles3.zig"),
};

//----------------------------------------------------------------------------------
// libc functions (RL_MALLOC/RL_CALLOC/RL_REALLOC/RL_FREE map to these).
//----------------------------------------------------------------------------------
extern fn malloc(usize) ?*anyopaque;
extern fn calloc(usize, usize) ?*anyopaque;
extern fn realloc(?*anyopaque, usize) ?*anyopaque;
extern fn free(?*anyopaque) void;
extern fn memcpy(noalias ?*anyopaque, noalias ?*const anyopaque, usize) ?*anyopaque;
extern fn strcmp([*c]const u8, [*c]const u8) c_int;
extern fn strlen([*c]const u8) usize;
extern fn floor(f64) f64;
extern fn log(f64) f64;
extern fn sqrtf(f32) f32;
extern fn sinf(f32) f32;
extern fn cosf(f32) f32;

inline fn RL_FREE(p: anytype) void {
    free(@ptrCast(@constCast(p)));
}

//----------------------------------------------------------------------------------
// Cross-module raylib C symbols.
//----------------------------------------------------------------------------------
extern fn TraceLog(logLevel: c_int, text: [*c]const u8, ...) void;

const PI: f32 = 3.14159265358979323846;
const DEG2RAD: f32 = PI / 180.0;

//----------------------------------------------------------------------------------
// Defines and Macros
//----------------------------------------------------------------------------------
pub const RLGL_VERSION = "6.0";

// Smaller batches on ES2/ES3: indices are 16-bit there (see `BatchIndex`).
const RL_DEFAULT_BATCH_BUFFER_ELEMENTS: c_int = if (es2) 2048 else 8192;
const RL_DEFAULT_BATCH_BUFFERS: c_int = 1;
const RL_DEFAULT_BATCH_DRAWCALLS: c_int = 256;
const RL_DEFAULT_BATCH_MAX_TEXTURE_UNITS: c_int = 4;
const RL_MAX_MATRIX_STACK_SIZE: c_int = 32;
const RL_MAX_SHADER_LOCATIONS: c_int = 32;
const RL_CULL_DISTANCE_NEAR: f64 = 0.05;
const RL_CULL_DISTANCE_FAR: f64 = 4000.0;

// Texture parameters (equivalent to OpenGL defines)
const RL_TEXTURE_WRAP_S: c_int = 0x2802;
const RL_TEXTURE_WRAP_T: c_int = 0x2803;
const RL_TEXTURE_MAG_FILTER: c_int = 0x2800;
const RL_TEXTURE_MIN_FILTER: c_int = 0x2801;
const RL_TEXTURE_FILTER_ANISOTROPIC: c_int = 0x3000;
const RL_TEXTURE_MIPMAP_BIAS_RATIO: c_int = 0x4000;
const RL_TEXTURE_WRAP_MIRROR_CLAMP: c_int = 0x8742;

// Matrix modes (equivalent to OpenGL)
const RL_MODELVIEW: c_int = 0x1700;
const RL_PROJECTION: c_int = 0x1701;
const RL_TEXTURE: c_int = 0x1702;

// Primitive assembly draw modes
const RL_LINES: c_int = 0x0001;
const RL_TRIANGLES: c_int = 0x0004;
const RL_QUADS: c_int = 0x0007;

// GL Shader type
const RL_FRAGMENT_SHADER: c_int = 0x8B30;
const RL_VERTEX_SHADER: c_int = 0x8B31;
const RL_COMPUTE_SHADER: c_int = 0x91B9;

const RL_STREAM_COPY: c_int = 0x88E2;

// Default shader vertex attribute locations
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION: c_uint = 0;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD: c_uint = 1;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL: c_uint = 2;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR: c_uint = 3;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT: c_uint = 4;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2: c_uint = 5;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_INDICES: c_uint = 6;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES: c_uint = 7;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS: c_uint = 8;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_INSTANCETRANSFORM: c_uint = 9;

// Default shader attribute/uniform names (null-terminated)
const RL_DEFAULT_SHADER_ATTRIB_NAME_POSITION = "vertexPosition";
const RL_DEFAULT_SHADER_ATTRIB_NAME_TEXCOORD = "vertexTexCoord";
const RL_DEFAULT_SHADER_ATTRIB_NAME_NORMAL = "vertexNormal";
const RL_DEFAULT_SHADER_ATTRIB_NAME_COLOR = "vertexColor";
const RL_DEFAULT_SHADER_ATTRIB_NAME_TANGENT = "vertexTangent";
const RL_DEFAULT_SHADER_ATTRIB_NAME_TEXCOORD2 = "vertexTexCoord2";
const RL_DEFAULT_SHADER_ATTRIB_NAME_BONEINDICES = "vertexBoneIndices";
const RL_DEFAULT_SHADER_ATTRIB_NAME_BONEWEIGHTS = "vertexBoneWeights";
const RL_DEFAULT_SHADER_ATTRIB_NAME_INSTANCETRANSFORM = "instanceTransform";
const RL_DEFAULT_SHADER_UNIFORM_NAME_MVP = "mvp";
const RL_DEFAULT_SHADER_UNIFORM_NAME_COLOR = "colDiffuse";
const RL_DEFAULT_SHADER_SAMPLER2D_NAME_TEXTURE0 = "texture0";

// rlTraceLogLevel
const RL_LOG_INFO: c_int = 3;
const RL_LOG_DEBUG: c_int = 2;
const RL_LOG_WARNING: c_int = 4;
const RL_LOG_ERROR: c_int = 5;

// rlGlVersion
const RL_OPENGL_33: c_int = 3;
const RL_OPENGL_ES_30: c_int = 6;

// rlPixelFormat
const RL_PIXELFORMAT_UNCOMPRESSED_GRAYSCALE: c_int = 1;
const RL_PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA: c_int = 2;
const RL_PIXELFORMAT_UNCOMPRESSED_R5G6B5: c_int = 3;
const RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8: c_int = 4;
const RL_PIXELFORMAT_UNCOMPRESSED_R5G5B5A1: c_int = 5;
const RL_PIXELFORMAT_UNCOMPRESSED_R4G4B4A4: c_int = 6;
const RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8A8: c_int = 7;
const RL_PIXELFORMAT_UNCOMPRESSED_R32: c_int = 8;
const RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32: c_int = 9;
const RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32A32: c_int = 10;
const RL_PIXELFORMAT_UNCOMPRESSED_R16: c_int = 11;
const RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16: c_int = 12;
const RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16A16: c_int = 13;
const RL_PIXELFORMAT_COMPRESSED_DXT1_RGB: c_int = 14;
const RL_PIXELFORMAT_COMPRESSED_DXT1_RGBA: c_int = 15;
const RL_PIXELFORMAT_COMPRESSED_DXT3_RGBA: c_int = 16;
const RL_PIXELFORMAT_COMPRESSED_DXT5_RGBA: c_int = 17;
const RL_PIXELFORMAT_COMPRESSED_ETC1_RGB: c_int = 18;
const RL_PIXELFORMAT_COMPRESSED_ETC2_RGB: c_int = 19;
const RL_PIXELFORMAT_COMPRESSED_ETC2_EAC_RGBA: c_int = 20;
const RL_PIXELFORMAT_COMPRESSED_PVRT_RGB: c_int = 21;
const RL_PIXELFORMAT_COMPRESSED_PVRT_RGBA: c_int = 22;
const RL_PIXELFORMAT_COMPRESSED_ASTC_4x4_RGBA: c_int = 23;
const RL_PIXELFORMAT_COMPRESSED_ASTC_8x8_RGBA: c_int = 24;

// rlBlendMode
const RL_BLEND_ALPHA: c_int = 0;
const RL_BLEND_ADDITIVE: c_int = 1;
const RL_BLEND_MULTIPLIED: c_int = 2;
const RL_BLEND_ADD_COLORS: c_int = 3;
const RL_BLEND_SUBTRACT_COLORS: c_int = 4;
const RL_BLEND_ALPHA_PREMULTIPLY: c_int = 5;
const RL_BLEND_CUSTOM: c_int = 6;
const RL_BLEND_CUSTOM_SEPARATE: c_int = 7;

// rlShaderLocationIndex (only ones used internally)
const RL_SHADER_LOC_VERTEX_POSITION: usize = 0;
const RL_SHADER_LOC_VERTEX_TEXCOORD01: usize = 1;
const RL_SHADER_LOC_VERTEX_NORMAL: usize = 3;
const RL_SHADER_LOC_VERTEX_COLOR: usize = 5;
const RL_SHADER_LOC_MATRIX_MVP: usize = 6;
const RL_SHADER_LOC_MATRIX_VIEW: usize = 7;
const RL_SHADER_LOC_MATRIX_PROJECTION: usize = 8;
const RL_SHADER_LOC_MATRIX_MODEL: usize = 9;
const RL_SHADER_LOC_MATRIX_NORMAL: usize = 10;
const RL_SHADER_LOC_COLOR_DIFFUSE: usize = 12;
const RL_SHADER_LOC_MAP_DIFFUSE: usize = 15; // == RL_SHADER_LOC_MAP_ALBEDO

// rlShaderUniformDataType
const RL_SHADER_UNIFORM_FLOAT: c_int = 0;
const RL_SHADER_UNIFORM_VEC2: c_int = 1;
const RL_SHADER_UNIFORM_VEC3: c_int = 2;
const RL_SHADER_UNIFORM_VEC4: c_int = 3;
const RL_SHADER_UNIFORM_INT: c_int = 4;
const RL_SHADER_UNIFORM_IVEC2: c_int = 5;
const RL_SHADER_UNIFORM_IVEC3: c_int = 6;
const RL_SHADER_UNIFORM_IVEC4: c_int = 7;
const RL_SHADER_UNIFORM_UINT: c_int = 8;
const RL_SHADER_UNIFORM_UIVEC2: c_int = 9;
const RL_SHADER_UNIFORM_UIVEC3: c_int = 10;
const RL_SHADER_UNIFORM_UIVEC4: c_int = 11;
const RL_SHADER_UNIFORM_SAMPLER2D: c_int = 12;

// rlShaderAttributeDataType
const RL_SHADER_ATTRIB_FLOAT: c_int = 0;
const RL_SHADER_ATTRIB_VEC2: c_int = 1;
const RL_SHADER_ATTRIB_VEC3: c_int = 2;
const RL_SHADER_ATTRIB_VEC4: c_int = 3;

// rlFramebufferAttachType
const RL_ATTACHMENT_COLOR_CHANNEL0: c_int = 0;
const RL_ATTACHMENT_COLOR_CHANNEL7: c_int = 7;
const RL_ATTACHMENT_DEPTH: c_int = 100;
const RL_ATTACHMENT_STENCIL: c_int = 200;
// rlFramebufferAttachTextureType
const RL_ATTACHMENT_CUBEMAP_POSITIVE_X: c_int = 0;
const RL_ATTACHMENT_TEXTURE2D: c_int = 100;
const RL_ATTACHMENT_RENDERBUFFER: c_int = 200;

// rlCullMode
const RL_CULL_FACE_FRONT: c_int = 0;
const RL_CULL_FACE_BACK: c_int = 1;

//----------------------------------------------------------------------------------
// Types and Structures Definition (public ABI: extern struct, exact layout)
//----------------------------------------------------------------------------------
pub const Matrix = extern struct {
    m0: f32,
    m4: f32,
    m8: f32,
    m12: f32,
    m1: f32,
    m5: f32,
    m9: f32,
    m13: f32,
    m2: f32,
    m6: f32,
    m10: f32,
    m14: f32,
    m3: f32,
    m7: f32,
    m11: f32,
    m15: f32,
};

/// Element type of the batch index buffer: rlgl.h stores quads' indices as
/// `unsigned short` on ES2/ES3 and `unsigned int` elsewhere.
pub const BatchIndex = if (es2) c_ushort else c_uint;

pub const rlVertexBuffer = extern struct {
    elementCount: c_int,
    vertices: [*c]f32,
    texcoords: [*c]f32,
    normals: [*c]f32,
    colors: [*c]u8,
    indices: [*c]BatchIndex,
    vaoId: c_uint,
    vboId: [5]c_uint,
};

pub const rlDrawCall = extern struct {
    mode: c_int,
    vertexCount: c_int,
    vertexAlignment: c_int,
    textureId: c_uint,
};

pub const rlRenderBatch = extern struct {
    bufferCount: c_int,
    currentBuffer: c_int,
    vertexBuffer: [*c]rlVertexBuffer,
    draws: [*c]rlDrawCall,
    drawCounter: c_int,
    currentDepth: f32,
};

//----------------------------------------------------------------------------------
// Module Types and Structures (file-private RLGL state, layout is ours)
//----------------------------------------------------------------------------------
const rlglLoadProc = ?*const fn (name: [*c]const u8) callconv(.c) ?*anyopaque;

const State = struct {
    vertexCounter: c_int = 0,
    texcoordx: f32 = 0,
    texcoordy: f32 = 0,
    normalx: f32 = 0,
    normaly: f32 = 0,
    normalz: f32 = 0,
    colorr: u8 = 0,
    colorg: u8 = 0,
    colorb: u8 = 0,
    colora: u8 = 0,

    currentMatrixMode: c_int = 0,
    currentMatrix: *Matrix = undefined,
    modelview: Matrix = undefined,
    projection: Matrix = undefined,
    transform: Matrix = undefined,
    transformRequired: bool = false,
    stack: [MATRIX_STACK_SIZE]Matrix = undefined,
    stackCounter: c_int = 0,

    currentTextureId: c_uint = 0,
    defaultTextureId: c_uint = 0,
    activeTextureId: [MAX_TEXTURE_UNITS]c_uint = std.mem.zeroes([MAX_TEXTURE_UNITS]c_uint),
    defaultVShaderId: c_uint = 0,
    defaultFShaderId: c_uint = 0,
    defaultShaderId: c_uint = 0,
    defaultShaderLocs: [*c]c_int = null,
    currentShaderId: c_uint = 0,
    currentShaderLocs: [*c]c_int = null,

    stereoRender: bool = false,
    projectionStereo: [2]Matrix = undefined,
    viewOffsetStereo: [2]Matrix = undefined,

    currentBlendMode: c_int = 0,
    glBlendSrcFactor: c_int = 0,
    glBlendDstFactor: c_int = 0,
    glBlendEquation: c_int = 0,
    glBlendSrcFactorRGB: c_int = 0,
    glBlendDestFactorRGB: c_int = 0,
    glBlendSrcFactorAlpha: c_int = 0,
    glBlendDestFactorAlpha: c_int = 0,
    glBlendEquationRGB: c_int = 0,
    glBlendEquationAlpha: c_int = 0,
    glCustomBlendModeModified: bool = false,

    framebufferWidth: c_int = 0,
    framebufferHeight: c_int = 0,
};

const ExtSupported = struct {
    vao: bool = false,
    instancing: bool = false,
    texNPOT: bool = false,
    texDepth: bool = false,
    texDepthWebGL: bool = false,
    texFloat32: bool = false,
    texFloat16: bool = false,
    texCompDXT: bool = false,
    texCompETC1: bool = false,
    texCompETC2: bool = false,
    texCompPVRT: bool = false,
    texCompASTC: bool = false,
    texMirrorClamp: bool = false,
    texAnisoFilter: bool = false,
    computeShader: bool = false,
    ssbo: bool = false,
    maxAnisotropyLevel: f32 = 0,
    maxDepthBits: c_int = 0,
};

const rlglData = struct {
    currentBatch: *rlRenderBatch = undefined,
    defaultBatch: rlRenderBatch = undefined,
    loader: rlglLoadProc = null,
    State: State = .{},
    ExtSupported: ExtSupported = .{},
};

//----------------------------------------------------------------------------------
// Global Variables Definition
//----------------------------------------------------------------------------------
var isGpuReady: bool = false;
var rlCullDistanceNear: f64 = RL_CULL_DISTANCE_NEAR;
var rlCullDistanceFar: f64 = RL_CULL_DISTANCE_FAR;

const MAX_TEXTURE_UNITS: usize = @intCast(RL_DEFAULT_BATCH_MAX_TEXTURE_UNITS);
const MATRIX_STACK_SIZE: usize = @intCast(RL_MAX_MATRIX_STACK_SIZE);

var RLGL: rlglData = .{};

//----------------------------------------------------------------------------------
// Module Functions Definition - Matrix operations
//----------------------------------------------------------------------------------

// Choose the current matrix to be transformed
export fn rlMatrixMode(mode: c_int) callconv(.c) void {
    if (mode == RL_PROJECTION) RLGL.State.currentMatrix = &RLGL.State.projection else if (mode == RL_MODELVIEW) RLGL.State.currentMatrix = &RLGL.State.modelview;
    RLGL.State.currentMatrixMode = mode;
}

// Push the current matrix into RLGL.State.stack
export fn rlPushMatrix() callconv(.c) void {
    if (RLGL.State.stackCounter >= RL_MAX_MATRIX_STACK_SIZE) {
        TraceLog(RL_LOG_ERROR, "RLGL: Matrix stack overflow (RL_MAX_MATRIX_STACK_SIZE)");
        return;
    }

    if (RLGL.State.currentMatrixMode == RL_MODELVIEW) {
        RLGL.State.transformRequired = true;
        RLGL.State.currentMatrix = &RLGL.State.transform;
    }

    RLGL.State.stack[@intCast(RLGL.State.stackCounter)] = RLGL.State.currentMatrix.*;
    RLGL.State.stackCounter += 1;
}

// Pop latest inserted matrix from RLGL.State.stack
export fn rlPopMatrix() callconv(.c) void {
    if (RLGL.State.stackCounter > 0) {
        const mat = RLGL.State.stack[@intCast(RLGL.State.stackCounter - 1)];
        RLGL.State.currentMatrix.* = mat;
        RLGL.State.stackCounter -= 1;
    }

    if ((RLGL.State.stackCounter == 0) and (RLGL.State.currentMatrixMode == RL_MODELVIEW)) {
        RLGL.State.currentMatrix = &RLGL.State.modelview;
        RLGL.State.transformRequired = false;
    }
}

// Reset current matrix to identity matrix
export fn rlLoadIdentity() callconv(.c) void {
    RLGL.State.currentMatrix.* = rlMatrixIdentity();
}

// Multiply the current matrix by a translation matrix
export fn rlTranslatef(x: f32, y: f32, z: f32) callconv(.c) void {
    var matTranslation = rlMatrixIdentity();
    matTranslation.m12 = x;
    matTranslation.m13 = y;
    matTranslation.m14 = z;
    RLGL.State.currentMatrix.* = rlMatrixMultiply(matTranslation, RLGL.State.currentMatrix.*);
}

// Multiply the current matrix by a rotation matrix (angle in degrees)
export fn rlRotatef(angle: f32, x_in: f32, y_in: f32, z_in: f32) callconv(.c) void {
    var matRotation = rlMatrixIdentity();
    var x = x_in;
    var y = y_in;
    var z = z_in;

    const lengthSquared = x * x + y * y + z * z;
    if ((lengthSquared != 1.0) and (lengthSquared != 0.0)) {
        const inverseLength = 1.0 / sqrtf(lengthSquared);
        x *= inverseLength;
        y *= inverseLength;
        z *= inverseLength;
    }

    const sinres = sinf(DEG2RAD * angle);
    const cosres = cosf(DEG2RAD * angle);
    const t = 1.0 - cosres;

    matRotation.m0 = x * x * t + cosres;
    matRotation.m1 = y * x * t + z * sinres;
    matRotation.m2 = z * x * t - y * sinres;
    matRotation.m3 = 0.0;

    matRotation.m4 = x * y * t - z * sinres;
    matRotation.m5 = y * y * t + cosres;
    matRotation.m6 = z * y * t + x * sinres;
    matRotation.m7 = 0.0;

    matRotation.m8 = x * z * t + y * sinres;
    matRotation.m9 = y * z * t - x * sinres;
    matRotation.m10 = z * z * t + cosres;
    matRotation.m11 = 0.0;

    matRotation.m12 = 0.0;
    matRotation.m13 = 0.0;
    matRotation.m14 = 0.0;
    matRotation.m15 = 1.0;

    RLGL.State.currentMatrix.* = rlMatrixMultiply(matRotation, RLGL.State.currentMatrix.*);
}

// Multiply the current matrix by a scaling matrix
export fn rlScalef(x: f32, y: f32, z: f32) callconv(.c) void {
    var matScale = rlMatrixIdentity();
    matScale.m0 = x;
    matScale.m5 = y;
    matScale.m10 = z;
    RLGL.State.currentMatrix.* = rlMatrixMultiply(matScale, RLGL.State.currentMatrix.*);
}

// Multiply the current matrix by another matrix
export fn rlMultMatrixf(matf: [*c]const f32) callconv(.c) void {
    const mat = Matrix{
        .m0 = matf[0],
        .m4 = matf[4],
        .m8 = matf[8],
        .m12 = matf[12],
        .m1 = matf[1],
        .m5 = matf[5],
        .m9 = matf[9],
        .m13 = matf[13],
        .m2 = matf[2],
        .m6 = matf[6],
        .m10 = matf[10],
        .m14 = matf[14],
        .m3 = matf[3],
        .m7 = matf[7],
        .m11 = matf[11],
        .m15 = matf[15],
    };
    RLGL.State.currentMatrix.* = rlMatrixMultiply(mat, RLGL.State.currentMatrix.*);
}

// Multiply the current matrix by a perspective matrix generated by parameters
export fn rlFrustum(left: f64, right: f64, bottom: f64, top: f64, znear: f64, zfar: f64) callconv(.c) void {
    var matFrustum = std.mem.zeroes(Matrix);

    const rl: f32 = @floatCast(right - left);
    const tb: f32 = @floatCast(top - bottom);
    const fn_: f32 = @floatCast(zfar - znear);

    matFrustum.m0 = (@as(f32, @floatCast(znear)) * 2.0) / rl;
    matFrustum.m1 = 0.0;
    matFrustum.m2 = 0.0;
    matFrustum.m3 = 0.0;

    matFrustum.m4 = 0.0;
    matFrustum.m5 = (@as(f32, @floatCast(znear)) * 2.0) / tb;
    matFrustum.m6 = 0.0;
    matFrustum.m7 = 0.0;

    matFrustum.m8 = (@as(f32, @floatCast(right)) + @as(f32, @floatCast(left))) / rl;
    matFrustum.m9 = (@as(f32, @floatCast(top)) + @as(f32, @floatCast(bottom))) / tb;
    matFrustum.m10 = -(@as(f32, @floatCast(zfar)) + @as(f32, @floatCast(znear))) / fn_;
    matFrustum.m11 = -1.0;

    matFrustum.m12 = 0.0;
    matFrustum.m13 = 0.0;
    matFrustum.m14 = -(@as(f32, @floatCast(zfar)) * @as(f32, @floatCast(znear)) * 2.0) / fn_;
    matFrustum.m15 = 0.0;

    RLGL.State.currentMatrix.* = rlMatrixMultiply(RLGL.State.currentMatrix.*, matFrustum);
}

// Multiply the current matrix by an orthographic matrix generated by parameters
export fn rlOrtho(left: f64, right: f64, bottom: f64, top: f64, znear: f64, zfar: f64) callconv(.c) void {
    var matOrtho = std.mem.zeroes(Matrix);

    const rl: f32 = @floatCast(right - left);
    const tb: f32 = @floatCast(top - bottom);
    const fn_: f32 = @floatCast(zfar - znear);

    matOrtho.m0 = 2.0 / rl;
    matOrtho.m1 = 0.0;
    matOrtho.m2 = 0.0;
    matOrtho.m3 = 0.0;
    matOrtho.m4 = 0.0;
    matOrtho.m5 = 2.0 / tb;
    matOrtho.m6 = 0.0;
    matOrtho.m7 = 0.0;
    matOrtho.m8 = 0.0;
    matOrtho.m9 = 0.0;
    matOrtho.m10 = -2.0 / fn_;
    matOrtho.m11 = 0.0;
    matOrtho.m12 = -(@as(f32, @floatCast(left)) + @as(f32, @floatCast(right))) / rl;
    matOrtho.m13 = -(@as(f32, @floatCast(top)) + @as(f32, @floatCast(bottom))) / tb;
    matOrtho.m14 = -(@as(f32, @floatCast(zfar)) + @as(f32, @floatCast(znear))) / fn_;
    matOrtho.m15 = 1.0;

    RLGL.State.currentMatrix.* = rlMatrixMultiply(RLGL.State.currentMatrix.*, matOrtho);
}

// Set the viewport area
export fn rlViewport(x: c_int, y: c_int, width: c_int, height: c_int) callconv(.c) void {
    gl.glad_glViewport.?(x, y, width, height);
}

// Set clip planes distances
export fn rlSetClipPlanes(nearPlane: f64, farPlane: f64) callconv(.c) void {
    rlCullDistanceNear = nearPlane;
    rlCullDistanceFar = farPlane;
}

// Get cull plane distance near
export fn rlGetCullDistanceNear() callconv(.c) f64 {
    return rlCullDistanceNear;
}

// Get cull plane distance far
export fn rlGetCullDistanceFar() callconv(.c) f64 {
    return rlCullDistanceFar;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Vertex level operations
//----------------------------------------------------------------------------------

// Initialize drawing mode (how to organize vertex)
export fn rlBegin(mode: c_int) callconv(.c) void {
    const batch = RLGL.currentBatch;
    if (batch.draws[@intCast(batch.drawCounter - 1)].mode != mode) {
        if (batch.draws[@intCast(batch.drawCounter - 1)].vertexCount > 0) {
            const dc = &batch.draws[@intCast(batch.drawCounter - 1)];
            if (dc.mode == RL_LINES) {
                dc.vertexAlignment = if (dc.vertexCount < 4) dc.vertexCount else @rem(dc.vertexCount, 4);
            } else if (dc.mode == RL_TRIANGLES) {
                dc.vertexAlignment = if (dc.vertexCount < 4) 1 else (4 - @rem(dc.vertexCount, 4));
            } else {
                dc.vertexAlignment = 0;
            }

            if (!rlCheckRenderBatchLimit(dc.vertexAlignment)) {
                RLGL.State.vertexCounter += dc.vertexAlignment;
                batch.drawCounter += 1;
            }
        }

        if (batch.drawCounter >= RL_DEFAULT_BATCH_DRAWCALLS) rlDrawRenderBatch(batch);

        batch.draws[@intCast(batch.drawCounter - 1)].mode = mode;
        batch.draws[@intCast(batch.drawCounter - 1)].textureId = RLGL.State.currentTextureId;
        RLGL.State.currentTextureId = RLGL.State.defaultTextureId;
    }
}

// Finish vertex providing
export fn rlEnd() callconv(.c) void {
    RLGL.currentBatch.currentDepth += (1.0 / 20000.0);
}

// Define one vertex (position) - 3 float
export fn rlVertex3f(x: f32, y: f32, z: f32) callconv(.c) void {
    var tx = x;
    var ty = y;
    var tz = z;

    if (RLGL.State.transformRequired) {
        const t = RLGL.State.transform;
        tx = t.m0 * x + t.m4 * y + t.m8 * z + t.m12;
        ty = t.m1 * x + t.m5 * y + t.m9 * z + t.m13;
        tz = t.m2 * x + t.m6 * y + t.m10 * z + t.m14;
    }

    const batch = RLGL.currentBatch;

    if (RLGL.State.vertexCounter > (batch.vertexBuffer[@intCast(batch.currentBuffer)].elementCount * 4 - 4)) {
        const dc = batch.draws[@intCast(batch.drawCounter - 1)];
        if ((dc.mode == RL_LINES) and (@rem(dc.vertexCount, 2) == 0)) {
            _ = rlCheckRenderBatchLimit(2 + 1);
        } else if ((dc.mode == RL_TRIANGLES) and (@rem(dc.vertexCount, 3) == 0)) {
            _ = rlCheckRenderBatchLimit(3 + 1);
        } else if ((dc.mode == RL_QUADS) and (@rem(dc.vertexCount, 4) == 0)) {
            _ = rlCheckRenderBatchLimit(4 + 1);
        }
    }

    // The check above may have flushed the batch and moved to its next buffer
    const vbuf = &batch.vertexBuffer[@intCast(batch.currentBuffer)];
    const vc: usize = @intCast(RLGL.State.vertexCounter);

    // Add vertices
    vbuf.vertices[3 * vc] = tx;
    vbuf.vertices[3 * vc + 1] = ty;
    vbuf.vertices[3 * vc + 2] = tz;

    // Add current texcoord
    vbuf.texcoords[2 * vc] = RLGL.State.texcoordx;
    vbuf.texcoords[2 * vc + 1] = RLGL.State.texcoordy;

    // Add current normal
    vbuf.normals[3 * vc] = RLGL.State.normalx;
    vbuf.normals[3 * vc + 1] = RLGL.State.normaly;
    vbuf.normals[3 * vc + 2] = RLGL.State.normalz;

    // Add current color
    vbuf.colors[4 * vc] = RLGL.State.colorr;
    vbuf.colors[4 * vc + 1] = RLGL.State.colorg;
    vbuf.colors[4 * vc + 2] = RLGL.State.colorb;
    vbuf.colors[4 * vc + 3] = RLGL.State.colora;

    RLGL.State.vertexCounter += 1;
    batch.draws[@intCast(batch.drawCounter - 1)].vertexCount += 1;
}

// Define one vertex (position) - 2 float
export fn rlVertex2f(x: f32, y: f32) callconv(.c) void {
    rlVertex3f(x, y, RLGL.currentBatch.currentDepth);
}

// Define one vertex (position) - 2 int
export fn rlVertex2i(x: c_int, y: c_int) callconv(.c) void {
    rlVertex3f(@floatFromInt(x), @floatFromInt(y), RLGL.currentBatch.currentDepth);
}

// Define one vertex (texture coordinate) - 2 float
export fn rlTexCoord2f(x: f32, y: f32) callconv(.c) void {
    RLGL.State.texcoordx = x;
    RLGL.State.texcoordy = y;
}

// Define one vertex (normal) - 3 float
export fn rlNormal3f(x: f32, y: f32, z: f32) callconv(.c) void {
    var normalx = x;
    var normaly = y;
    var normalz = z;
    if (RLGL.State.transformRequired) {
        const t = RLGL.State.transform;
        normalx = t.m0 * x + t.m4 * y + t.m8 * z;
        normaly = t.m1 * x + t.m5 * y + t.m9 * z;
        normalz = t.m2 * x + t.m6 * y + t.m10 * z;
    }
    RLGL.State.normalx = normalx;
    RLGL.State.normaly = normaly;
    RLGL.State.normalz = normalz;
}

// Define one vertex (color) - 4 byte
export fn rlColor4ub(x: u8, y: u8, z: u8, w: u8) callconv(.c) void {
    RLGL.State.colorr = x;
    RLGL.State.colorg = y;
    RLGL.State.colorb = z;
    RLGL.State.colora = w;
}

// Define one vertex (color) - 4 float
export fn rlColor4f(r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    rlColor4ub(@intFromFloat(r * 255), @intFromFloat(g * 255), @intFromFloat(b * 255), @intFromFloat(a * 255));
}

// Define one vertex (color) - 3 float
export fn rlColor3f(x: f32, y: f32, z: f32) callconv(.c) void {
    rlColor4ub(@intFromFloat(x * 255), @intFromFloat(y * 255), @intFromFloat(z * 255), 255);
}

//--------------------------------------------------------------------------------------
// Module Functions Definition - OpenGL style functions
//--------------------------------------------------------------------------------------

// Set current texture to use
export fn rlSetTexture(id: c_uint) callconv(.c) void {
    const batch = RLGL.currentBatch;
    if (id == 0) {
        // NOTE: If quads batch limit is reached, force a draw call and next batch starts
        if (RLGL.State.vertexCounter >= batch.vertexBuffer[@intCast(batch.currentBuffer)].elementCount * 4) {
            rlDrawRenderBatch(batch);
        }
        RLGL.State.currentTextureId = RLGL.State.defaultTextureId;
    } else {
        RLGL.State.currentTextureId = id;
        if (batch.draws[@intCast(batch.drawCounter - 1)].textureId != id) {
            if (batch.draws[@intCast(batch.drawCounter - 1)].vertexCount > 0) {
                const dc = &batch.draws[@intCast(batch.drawCounter - 1)];
                if (dc.mode == RL_LINES) {
                    dc.vertexAlignment = if (dc.vertexCount < 4) dc.vertexCount else @rem(dc.vertexCount, 4);
                } else if (dc.mode == RL_TRIANGLES) {
                    dc.vertexAlignment = if (dc.vertexCount < 4) 1 else (4 - @rem(dc.vertexCount, 4));
                } else {
                    dc.vertexAlignment = 0;
                }

                if (!rlCheckRenderBatchLimit(dc.vertexAlignment)) {
                    RLGL.State.vertexCounter += dc.vertexAlignment;
                    batch.drawCounter += 1;
                    batch.draws[@intCast(batch.drawCounter - 1)].mode = batch.draws[@intCast(batch.drawCounter - 2)].mode;
                }
            }

            if (batch.drawCounter >= RL_DEFAULT_BATCH_DRAWCALLS) rlDrawRenderBatch(batch);

            batch.draws[@intCast(batch.drawCounter - 1)].textureId = id;
            batch.draws[@intCast(batch.drawCounter - 1)].vertexCount = 0;
        }
    }
}

// Select and active a texture slot
export fn rlActiveTextureSlot(slot: c_int) callconv(.c) void {
    gl.glad_glActiveTexture.?(gl.GL_TEXTURE0 + @as(c_uint, @intCast(slot)));
}

// Enable texture
export fn rlEnableTexture(id: c_uint) callconv(.c) void {
    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, id);
}

// Disable texture
export fn rlDisableTexture() callconv(.c) void {
    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, 0);
}

// Enable texture cubemap
export fn rlEnableTextureCubemap(id: c_uint) callconv(.c) void {
    gl.glad_glBindTexture.?(gl.GL_TEXTURE_CUBE_MAP, id);
}

// Disable texture cubemap
export fn rlDisableTextureCubemap() callconv(.c) void {
    gl.glad_glBindTexture.?(gl.GL_TEXTURE_CUBE_MAP, 0);
}

// Set texture parameters (wrap mode/filter mode)
export fn rlTextureParameters(id: c_uint, param: c_int, value: c_int) callconv(.c) void {
    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, id);

    switch (param) {
        RL_TEXTURE_WRAP_S, RL_TEXTURE_WRAP_T => {
            if (value == RL_TEXTURE_WRAP_MIRROR_CLAMP) {
                if (RLGL.ExtSupported.texMirrorClamp) {
                    gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, @intCast(param), value);
                } else TraceLog(RL_LOG_WARNING, "GL: Clamp mirror wrap mode not supported (GL_MIRROR_CLAMP_EXT)");
            } else gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, @intCast(param), value);
        },
        RL_TEXTURE_MAG_FILTER, RL_TEXTURE_MIN_FILTER => gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, @intCast(param), value),
        RL_TEXTURE_FILTER_ANISOTROPIC => {
            gl.glad_glTexParameterf.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAX_ANISOTROPY_EXT, 1.0);
            if (@as(f32, @floatFromInt(value)) <= RLGL.ExtSupported.maxAnisotropyLevel) {
                gl.glad_glTexParameterf.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAX_ANISOTROPY_EXT, @floatFromInt(value));
            } else if (RLGL.ExtSupported.maxAnisotropyLevel > 0.0) {
                TraceLog(RL_LOG_WARNING, "GL: Maximum anisotropic filter level supported is %iX", id, @as(c_int, @intFromFloat(RLGL.ExtSupported.maxAnisotropyLevel)));
                gl.glad_glTexParameterf.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAX_ANISOTROPY_EXT, @floatFromInt(value));
            } else TraceLog(RL_LOG_WARNING, "GL: Anisotropic filtering not supported");
        },
        // GL_TEXTURE_LOD_BIAS does not exist in OpenGL ES.
        RL_TEXTURE_MIPMAP_BIAS_RATIO => if (!es2) gl.glad_glTexParameterf.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_LOD_BIAS, @as(f32, @floatFromInt(value)) / 100.0),
        else => {},
    }

    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, 0);
}

// Set cubemap parameters (wrap mode/filter mode)
export fn rlCubemapParameters(id: c_uint, param: c_int, value: c_int) callconv(.c) void {
    gl.glad_glBindTexture.?(gl.GL_TEXTURE_CUBE_MAP, id);
    gl.glad_glTexParameterf.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MAX_ANISOTROPY_EXT, 1.0);

    switch (param) {
        RL_TEXTURE_WRAP_S, RL_TEXTURE_WRAP_T => {
            if (value == RL_TEXTURE_WRAP_MIRROR_CLAMP) {
                if (RLGL.ExtSupported.texMirrorClamp) {
                    gl.glad_glTexParameteri.?(gl.GL_TEXTURE_CUBE_MAP, @intCast(param), value);
                } else TraceLog(RL_LOG_WARNING, "GL: Clamp mirror wrap mode not supported (GL_MIRROR_CLAMP_EXT)");
            } else gl.glad_glTexParameteri.?(gl.GL_TEXTURE_CUBE_MAP, @intCast(param), value);
        },
        RL_TEXTURE_MAG_FILTER, RL_TEXTURE_MIN_FILTER => gl.glad_glTexParameteri.?(gl.GL_TEXTURE_CUBE_MAP, @intCast(param), value),
        RL_TEXTURE_FILTER_ANISOTROPIC => {
            if (@as(f32, @floatFromInt(value)) <= RLGL.ExtSupported.maxAnisotropyLevel) {
                gl.glad_glTexParameterf.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MAX_ANISOTROPY_EXT, @floatFromInt(value));
            } else if (RLGL.ExtSupported.maxAnisotropyLevel > 0.0) {
                TraceLog(RL_LOG_WARNING, "GL: Maximum anisotropic filter level supported is %iX", id, @as(c_int, @intFromFloat(RLGL.ExtSupported.maxAnisotropyLevel)));
                gl.glad_glTexParameterf.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MAX_ANISOTROPY_EXT, @floatFromInt(value));
            } else TraceLog(RL_LOG_WARNING, "GL: Anisotropic filtering not supported");
        },
        // GL_TEXTURE_LOD_BIAS does not exist in OpenGL ES.
        RL_TEXTURE_MIPMAP_BIAS_RATIO => if (!es2) gl.glad_glTexParameterf.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_LOD_BIAS, @as(f32, @floatFromInt(value)) / 100.0),
        else => {},
    }

    gl.glad_glBindTexture.?(gl.GL_TEXTURE_CUBE_MAP, 0);
}

// Enable shader program
export fn rlEnableShader(id: c_uint) callconv(.c) void {
    gl.glad_glUseProgram.?(id);
}

// Disable shader program
export fn rlDisableShader() callconv(.c) void {
    gl.glad_glUseProgram.?(0);
}

// Enable rendering to texture (fbo)
export fn rlEnableFramebuffer(id: c_uint) callconv(.c) void {
    gl.glad_glBindFramebuffer.?(gl.GL_FRAMEBUFFER, id);
}

// Return the active render texture (fbo)
export fn rlGetActiveFramebuffer() callconv(.c) c_uint {
    var fboId: c_int = 0;
    gl.glad_glGetIntegerv.?(gl.GL_DRAW_FRAMEBUFFER_BINDING, &fboId);
    return @intCast(fboId);
}

// Disable rendering to texture
export fn rlDisableFramebuffer() callconv(.c) void {
    gl.glad_glBindFramebuffer.?(gl.GL_FRAMEBUFFER, 0);
}

// Blit active framebuffer to main framebuffer
export fn rlBlitFramebuffer(srcX: c_int, srcY: c_int, srcWidth: c_int, srcHeight: c_int, dstX: c_int, dstY: c_int, dstWidth: c_int, dstHeight: c_int, bufferMask: c_int) callconv(.c) void {
    gl.glad_glBlitFramebuffer.?(srcX, srcY, srcWidth, srcHeight, dstX, dstY, dstWidth, dstHeight, @intCast(bufferMask), gl.GL_NEAREST);
}

// Bind framebuffer object (fbo)
export fn rlBindFramebuffer(target: c_uint, framebuffer: c_uint) callconv(.c) void {
    gl.glad_glBindFramebuffer.?(target, framebuffer);
}

// Activate multiple draw color buffers
export fn rlActiveDrawBuffers(count: c_int) callconv(.c) void {
    if (count > 0) {
        if (count > 8) {
            TraceLog(RL_LOG_WARNING, "GL: Max color buffers limited to 8");
        } else {
            var buffers = [8]c_uint{
                gl.GL_COLOR_ATTACHMENT0,
                gl.GL_COLOR_ATTACHMENT0 + 1,
                gl.GL_COLOR_ATTACHMENT0 + 2,
                gl.GL_COLOR_ATTACHMENT0 + 3,
                gl.GL_COLOR_ATTACHMENT0 + 4,
                gl.GL_COLOR_ATTACHMENT0 + 5,
                gl.GL_COLOR_ATTACHMENT0 + 6,
                gl.GL_COLOR_ATTACHMENT0 + 7,
            };
            gl.glad_glDrawBuffers.?(count, &buffers);
        }
    } else TraceLog(RL_LOG_WARNING, "GL: One color buffer active by default");
}

//----------------------------------------------------------------------------------
// General render state configuration
//----------------------------------------------------------------------------------

export fn rlEnableColorBlend() callconv(.c) void {
    gl.glad_glEnable.?(gl.GL_BLEND);
}
export fn rlDisableColorBlend() callconv(.c) void {
    gl.glad_glDisable.?(gl.GL_BLEND);
}
export fn rlEnableDepthTest() callconv(.c) void {
    gl.glad_glEnable.?(gl.GL_DEPTH_TEST);
}
export fn rlDisableDepthTest() callconv(.c) void {
    gl.glad_glDisable.?(gl.GL_DEPTH_TEST);
}
export fn rlEnableDepthMask() callconv(.c) void {
    gl.glad_glDepthMask.?(@intCast(gl.GL_TRUE));
}
export fn rlDisableDepthMask() callconv(.c) void {
    gl.glad_glDepthMask.?(@intCast(gl.GL_FALSE));
}
export fn rlEnableBackfaceCulling() callconv(.c) void {
    gl.glad_glEnable.?(gl.GL_CULL_FACE);
}
export fn rlDisableBackfaceCulling() callconv(.c) void {
    gl.glad_glDisable.?(gl.GL_CULL_FACE);
}

// Set color mask active for screen read/draw
export fn rlColorMask(r: bool, g: bool, b: bool, a: bool) callconv(.c) void {
    gl.glad_glColorMask.?(@intFromBool(r), @intFromBool(g), @intFromBool(b), @intFromBool(a));
}

// Set face culling mode
export fn rlSetCullFace(mode: c_int) callconv(.c) void {
    switch (mode) {
        RL_CULL_FACE_BACK => gl.glad_glCullFace.?(gl.GL_BACK),
        RL_CULL_FACE_FRONT => gl.glad_glCullFace.?(gl.GL_FRONT),
        else => {},
    }
}

export fn rlEnableScissorTest() callconv(.c) void {
    gl.glad_glEnable.?(gl.GL_SCISSOR_TEST);
}
export fn rlDisableScissorTest() callconv(.c) void {
    gl.glad_glDisable.?(gl.GL_SCISSOR_TEST);
}

// Scissor test
export fn rlScissor(x: c_int, y: c_int, width: c_int, height: c_int) callconv(.c) void {
    gl.glad_glScissor.?(x, y, width, height);
}

// Wire and point modes need glPolygonMode, which OpenGL ES does not have: on ES3
// these four are no-ops, as in rlgl.h.

// Enable wire mode
export fn rlEnableWireMode() callconv(.c) void {
    if (es2) return;
    gl.glad_glPolygonMode.?(gl.GL_FRONT_AND_BACK, gl.GL_LINE);
}
// Disable wire mode
export fn rlDisableWireMode() callconv(.c) void {
    if (es2) return;
    gl.glad_glPolygonMode.?(gl.GL_FRONT_AND_BACK, gl.GL_FILL);
}

// Enable point mode
export fn rlEnablePointMode() callconv(.c) void {
    if (es2) return;
    gl.glad_glPolygonMode.?(gl.GL_FRONT_AND_BACK, gl.GL_POINT);
    gl.glad_glEnable.?(gl.GL_PROGRAM_POINT_SIZE);
}
// Disable point mode
export fn rlDisablePointMode() callconv(.c) void {
    if (es2) return;
    gl.glad_glPolygonMode.?(gl.GL_FRONT_AND_BACK, gl.GL_FILL);
}

// Set the line drawing width
export fn rlSetLineWidth(width: f32) callconv(.c) void {
    gl.glad_glLineWidth.?(width);
}

// Get the line drawing width
export fn rlGetLineWidth() callconv(.c) f32 {
    var width: f32 = 0;
    gl.glad_glGetFloatv.?(gl.GL_LINE_WIDTH, &width);
    return width;
}

// Set the point drawing size (no-op on GL 3.3, only OpenGL 1.1)
export fn rlSetPointSize(size: f32) callconv(.c) void {
    _ = size;
}

// Get the point drawing size
export fn rlGetPointSize() callconv(.c) f32 {
    const size: f32 = 1;
    return size;
}

// Enable line aliasing
// (GL_LINE_SMOOTH is desktop-only: a no-op on ES3.)
export fn rlEnableSmoothLines() callconv(.c) void {
    if (es2) return;
    gl.glad_glEnable.?(gl.GL_LINE_SMOOTH);
}
// Disable line aliasing
export fn rlDisableSmoothLines() callconv(.c) void {
    if (es2) return;
    gl.glad_glDisable.?(gl.GL_LINE_SMOOTH);
}

// Enable stereo rendering
export fn rlEnableStereoRender() callconv(.c) void {
    RLGL.State.stereoRender = true;
}
// Disable stereo rendering
export fn rlDisableStereoRender() callconv(.c) void {
    RLGL.State.stereoRender = false;
}
// Check if stereo render is enabled
export fn rlIsStereoRenderEnabled() callconv(.c) bool {
    return RLGL.State.stereoRender;
}

// Clear color buffer with color
export fn rlClearColor(r: u8, g: u8, b: u8, a: u8) callconv(.c) void {
    const cr = @as(f32, @floatFromInt(r)) / 255;
    const cg = @as(f32, @floatFromInt(g)) / 255;
    const cb = @as(f32, @floatFromInt(b)) / 255;
    const ca = @as(f32, @floatFromInt(a)) / 255;
    gl.glad_glClearColor.?(cr, cg, cb, ca);
}

// Clear used screen buffers (color and depth)
export fn rlClearScreenBuffers() callconv(.c) void {
    gl.glad_glClear.?(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
}

// Check and log OpenGL error codes
export fn rlCheckErrors() callconv(.c) void {
    var check: c_int = 1;
    while (check != 0) {
        const err = gl.glad_glGetError.?();
        switch (err) {
            gl.GL_NO_ERROR => check = 0,
            0x0500 => TraceLog(RL_LOG_WARNING, "GL: Error detected: GL_INVALID_ENUM"),
            0x0501 => TraceLog(RL_LOG_WARNING, "GL: Error detected: GL_INVALID_VALUE"),
            0x0502 => TraceLog(RL_LOG_WARNING, "GL: Error detected: GL_INVALID_OPERATION"),
            0x0503 => TraceLog(RL_LOG_WARNING, "GL: Error detected: GL_STACK_OVERFLOW"),
            0x0504 => TraceLog(RL_LOG_WARNING, "GL: Error detected: GL_STACK_UNDERFLOW"),
            0x0505 => TraceLog(RL_LOG_WARNING, "GL: Error detected: GL_OUT_OF_MEMORY"),
            0x0506 => TraceLog(RL_LOG_WARNING, "GL: Error detected: GL_INVALID_FRAMEBUFFER_OPERATION"),
            else => TraceLog(RL_LOG_WARNING, "GL: Error detected: Unknown error code: %x", err),
        }
    }
}

// Set blend mode
export fn rlSetBlendMode(mode: c_int) callconv(.c) void {
    if ((RLGL.State.currentBlendMode != mode) or ((mode == RL_BLEND_CUSTOM or mode == RL_BLEND_CUSTOM_SEPARATE) and RLGL.State.glCustomBlendModeModified)) {
        rlDrawRenderBatch(RLGL.currentBatch);

        switch (mode) {
            RL_BLEND_ALPHA => {
                gl.glad_glBlendFunc.?(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
                gl.glad_glBlendEquation.?(gl.GL_FUNC_ADD);
            },
            RL_BLEND_ADDITIVE => {
                gl.glad_glBlendFunc.?(gl.GL_SRC_ALPHA, gl.GL_ONE);
                gl.glad_glBlendEquation.?(gl.GL_FUNC_ADD);
            },
            RL_BLEND_MULTIPLIED => {
                gl.glad_glBlendFunc.?(gl.GL_DST_COLOR, gl.GL_ONE_MINUS_SRC_ALPHA);
                gl.glad_glBlendEquation.?(gl.GL_FUNC_ADD);
            },
            RL_BLEND_ADD_COLORS => {
                gl.glad_glBlendFunc.?(gl.GL_ONE, gl.GL_ONE);
                gl.glad_glBlendEquation.?(gl.GL_FUNC_ADD);
            },
            RL_BLEND_SUBTRACT_COLORS => {
                gl.glad_glBlendFunc.?(gl.GL_ONE, gl.GL_ONE);
                gl.glad_glBlendEquation.?(gl.GL_FUNC_SUBTRACT);
            },
            RL_BLEND_ALPHA_PREMULTIPLY => {
                gl.glad_glBlendFunc.?(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
                gl.glad_glBlendEquation.?(gl.GL_FUNC_ADD);
            },
            RL_BLEND_CUSTOM => {
                gl.glad_glBlendFunc.?(@intCast(RLGL.State.glBlendSrcFactor), @intCast(RLGL.State.glBlendDstFactor));
                gl.glad_glBlendEquation.?(@intCast(RLGL.State.glBlendEquation));
            },
            RL_BLEND_CUSTOM_SEPARATE => {
                gl.glad_glBlendFuncSeparate.?(@intCast(RLGL.State.glBlendSrcFactorRGB), @intCast(RLGL.State.glBlendDestFactorRGB), @intCast(RLGL.State.glBlendSrcFactorAlpha), @intCast(RLGL.State.glBlendDestFactorAlpha));
                gl.glad_glBlendEquationSeparate.?(@intCast(RLGL.State.glBlendEquationRGB), @intCast(RLGL.State.glBlendEquationAlpha));
            },
            else => {},
        }

        RLGL.State.currentBlendMode = mode;
        RLGL.State.glCustomBlendModeModified = false;
    }
}

// Set blending mode factor and equation
export fn rlSetBlendFactors(glSrcFactor: c_int, glDstFactor: c_int, glEquation: c_int) callconv(.c) void {
    if ((RLGL.State.glBlendSrcFactor != glSrcFactor) or
        (RLGL.State.glBlendDstFactor != glDstFactor) or
        (RLGL.State.glBlendEquation != glEquation))
    {
        RLGL.State.glBlendSrcFactor = glSrcFactor;
        RLGL.State.glBlendDstFactor = glDstFactor;
        RLGL.State.glBlendEquation = glEquation;
        RLGL.State.glCustomBlendModeModified = true;
    }
}

// Set blending mode factors and equations separately for RGB and alpha
export fn rlSetBlendFactorsSeparate(glSrcRGB: c_int, glDstRGB: c_int, glSrcAlpha: c_int, glDstAlpha: c_int, glEqRGB: c_int, glEqAlpha: c_int) callconv(.c) void {
    if ((RLGL.State.glBlendSrcFactorRGB != glSrcRGB) or
        (RLGL.State.glBlendDestFactorRGB != glDstRGB) or
        (RLGL.State.glBlendSrcFactorAlpha != glSrcAlpha) or
        (RLGL.State.glBlendDestFactorAlpha != glDstAlpha) or
        (RLGL.State.glBlendEquationRGB != glEqRGB) or
        (RLGL.State.glBlendEquationAlpha != glEqAlpha))
    {
        RLGL.State.glBlendSrcFactorRGB = glSrcRGB;
        RLGL.State.glBlendDestFactorRGB = glDstRGB;
        RLGL.State.glBlendSrcFactorAlpha = glSrcAlpha;
        RLGL.State.glBlendDestFactorAlpha = glDstAlpha;
        RLGL.State.glBlendEquationRGB = glEqRGB;
        RLGL.State.glBlendEquationAlpha = glEqAlpha;
        RLGL.State.glCustomBlendModeModified = true;
    }
}

//----------------------------------------------------------------------------------
// Module Functions Definition - rlgl functionality
//----------------------------------------------------------------------------------

// Initialize rlgl: default buffers/shaders/textures, OpenGL states
export fn rlglInit(width: c_int, height: c_int) callconv(.c) void {
    isGpuReady = true;

    // Init default white texture
    var pixels = [4]u8{ 255, 255, 255, 255 };
    RLGL.State.defaultTextureId = rlLoadTexture(&pixels, 1, 1, RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, 1);
    RLGL.State.currentTextureId = RLGL.State.defaultTextureId;

    if (RLGL.State.defaultTextureId != 0) {
        TraceLog(RL_LOG_INFO, "TEXTURE: [ID %i] Default texture loaded successfully", RLGL.State.defaultTextureId);
    } else TraceLog(RL_LOG_WARNING, "TEXTURE: Failed to load default texture");

    // Init default Shader
    rlLoadShaderDefault();
    RLGL.State.currentShaderId = RLGL.State.defaultShaderId;
    RLGL.State.currentShaderLocs = RLGL.State.defaultShaderLocs;

    // Init default vertex arrays buffers
    RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_NORMAL] = @intCast(RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL);
    RLGL.defaultBatch = rlLoadRenderBatch(RL_DEFAULT_BATCH_BUFFERS, RL_DEFAULT_BATCH_BUFFER_ELEMENTS);
    RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_NORMAL] = -1;
    RLGL.currentBatch = &RLGL.defaultBatch;

    // Init stack matrices (emulating OpenGL 1.1)
    var i: usize = 0;
    while (i < @as(usize, @intCast(RL_MAX_MATRIX_STACK_SIZE))) : (i += 1) RLGL.State.stack[i] = rlMatrixIdentity();

    // Init internal matrices
    RLGL.State.transform = rlMatrixIdentity();
    RLGL.State.projection = rlMatrixIdentity();
    RLGL.State.modelview = rlMatrixIdentity();
    RLGL.State.currentMatrix = &RLGL.State.modelview;

    // Initialize OpenGL default states
    gl.glad_glDepthFunc.?(gl.GL_LEQUAL);
    gl.glad_glDisable.?(gl.GL_DEPTH_TEST);

    gl.glad_glBlendFunc.?(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
    gl.glad_glEnable.?(gl.GL_BLEND);

    gl.glad_glCullFace.?(gl.GL_BACK);
    gl.glad_glFrontFace.?(gl.GL_CCW);
    gl.glad_glEnable.?(gl.GL_CULL_FACE);

    // Init state: Cubemap seamless (always on, and not a capability, in ES3)
    if (!es2) gl.glad_glEnable.?(gl.GL_TEXTURE_CUBE_MAP_SEAMLESS);

    // Store screen size into global variables
    RLGL.State.framebufferWidth = width;
    RLGL.State.framebufferHeight = height;

    // Init state: Color/Depth buffers clear
    gl.glad_glClearColor.?(0.0, 0.0, 0.0, 1.0);
    if (es2) gl.glad_glClearDepthf.?(1.0) else gl.glad_glClearDepth.?(1.0);
    gl.glad_glClear.?(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

    TraceLog(RL_LOG_INFO, "RLGL: Default OpenGL state initialized successfully");
}

// Vertex Buffer Object deinitialization (memory free)
export fn rlglClose() callconv(.c) void {
    rlUnloadRenderBatch(RLGL.defaultBatch);

    rlUnloadShaderDefault();

    gl.glad_glDeleteTextures.?(1, &RLGL.State.defaultTextureId);
    TraceLog(RL_LOG_INFO, "TEXTURE: [ID %i] Default texture unloaded successfully", RLGL.State.defaultTextureId);

    isGpuReady = false;
}

// Load OpenGL extensions (loader function required)
export fn rlLoadExtensions(loader: ?*anyopaque) callconv(.c) void {
    switch (graphics_api) {
        .opengl_33 => {
            if (gl.gladLoadGL(@ptrCast(@alignCast(loader))) == 0) {
                TraceLog(RL_LOG_WARNING, "GLAD: Cannot load OpenGL extensions");
            } else TraceLog(RL_LOG_INFO, "GLAD: OpenGL extensions loaded successfully");

            var numExt: c_int = 0;
            gl.glad_glGetIntegerv.?(gl.GL_NUM_EXTENSIONS, &numExt);
            TraceLog(RL_LOG_INFO, "GL: Supported extensions count: %i", numExt);
        },
        // WebGL 2 functions are linked directly (src/gles3.zig): nothing to load.
        .opengl_es3 => {},
    }

    // Register supported extensions flags
    // OpenGL 3.3 and OpenGL ES 3.0 extensions supported by default (core)
    RLGL.ExtSupported.vao = true;
    RLGL.ExtSupported.instancing = true;
    RLGL.ExtSupported.texNPOT = true;
    RLGL.ExtSupported.texFloat32 = true;
    RLGL.ExtSupported.texFloat16 = true;
    RLGL.ExtSupported.texDepth = true;
    switch (graphics_api) {
        .opengl_33 => RLGL.ExtSupported.maxDepthBits = 32,
        .opengl_es3 => {
            RLGL.ExtSupported.texDepthWebGL = true;
            RLGL.ExtSupported.maxDepthBits = 24;
        },
    }
    RLGL.ExtSupported.texAnisoFilter = true;
    RLGL.ExtSupported.texMirrorClamp = true;

    // Optional OpenGL 3.3 extensions
    if (graphics_api == .opengl_33) {
        RLGL.ExtSupported.texCompASTC = gl.GLAD_GL_KHR_texture_compression_astc_hdr != 0 and gl.GLAD_GL_KHR_texture_compression_astc_ldr != 0;
        RLGL.ExtSupported.texCompDXT = gl.GLAD_GL_EXT_texture_compression_s3tc != 0;
        RLGL.ExtSupported.texCompETC2 = gl.GLAD_GL_ARB_ES3_compatibility != 0;
    }

    // Check OpenGL information and capabilities
    TraceLog(RL_LOG_INFO, "GL: OpenGL device information:");
    TraceLog(RL_LOG_INFO, "    > Vendor:   %s", gl.glad_glGetString.?(gl.GL_VENDOR));
    TraceLog(RL_LOG_INFO, "    > Renderer: %s", gl.glad_glGetString.?(gl.GL_RENDERER));
    TraceLog(RL_LOG_INFO, "    > Version:  %s", gl.glad_glGetString.?(gl.GL_VERSION));
    TraceLog(RL_LOG_INFO, "    > GLSL:     %s", gl.glad_glGetString.?(gl.GL_SHADING_LANGUAGE_VERSION));

    RLGL.loader = @ptrCast(@alignCast(loader));

    gl.glad_glGetFloatv.?(gl.GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &RLGL.ExtSupported.maxAnisotropyLevel);

    // Show some basic info about GL supported features
    if (RLGL.ExtSupported.vao) {
        TraceLog(RL_LOG_INFO, "GL: VAO extension detected, VAO functions loaded successfully");
    } else TraceLog(RL_LOG_WARNING, "GL: VAO extension not found, VAO not supported");
    if (RLGL.ExtSupported.texNPOT) {
        TraceLog(RL_LOG_INFO, "GL: NPOT textures extension detected, full NPOT textures supported");
    } else TraceLog(RL_LOG_WARNING, "GL: NPOT textures extension not found, limited NPOT support (no-mipmaps, no-repeat)");
    if (RLGL.ExtSupported.texCompDXT) TraceLog(RL_LOG_INFO, "GL: DXT compressed textures supported");
    if (RLGL.ExtSupported.texCompETC1) TraceLog(RL_LOG_INFO, "GL: ETC1 compressed textures supported");
    if (RLGL.ExtSupported.texCompETC2) TraceLog(RL_LOG_INFO, "GL: ETC2/EAC compressed textures supported");
    if (RLGL.ExtSupported.texCompPVRT) TraceLog(RL_LOG_INFO, "GL: PVRT compressed textures supported");
    if (RLGL.ExtSupported.texCompASTC) TraceLog(RL_LOG_INFO, "GL: ASTC compressed textures supported");
    if (RLGL.ExtSupported.computeShader) TraceLog(RL_LOG_INFO, "GL: Compute shaders supported");
    if (RLGL.ExtSupported.ssbo) TraceLog(RL_LOG_INFO, "GL: Shader storage buffer objects supported");
}

// Get OpenGL procedure address
export fn rlGetProcAddress(procName: [*c]const u8) callconv(.c) ?*anyopaque {
    if (RLGL.loader) |l| return l(procName);
    return null;
}

// Get current OpenGL version
export fn rlGetVersion() callconv(.c) c_int {
    return switch (graphics_api) {
        .opengl_33 => RL_OPENGL_33,
        .opengl_es3 => RL_OPENGL_ES_30,
    };
}

// Set/get current framebuffer width/height
export fn rlSetFramebufferWidth(width: c_int) callconv(.c) void {
    RLGL.State.framebufferWidth = width;
}
export fn rlSetFramebufferHeight(height: c_int) callconv(.c) void {
    RLGL.State.framebufferHeight = height;
}
export fn rlGetFramebufferWidth() callconv(.c) c_int {
    return RLGL.State.framebufferWidth;
}
export fn rlGetFramebufferHeight() callconv(.c) c_int {
    return RLGL.State.framebufferHeight;
}

// Get default internal texture (white texture)
export fn rlGetTextureIdDefault() callconv(.c) c_uint {
    return RLGL.State.defaultTextureId;
}
// Get default shader id
export fn rlGetShaderIdDefault() callconv(.c) c_uint {
    return RLGL.State.defaultShaderId;
}
// Get default shader locs
export fn rlGetShaderLocsDefault() callconv(.c) [*c]c_int {
    return RLGL.State.defaultShaderLocs;
}

// Render batch management
//------------------------------------------------------------------------------------------------

// Load render batch
export fn rlLoadRenderBatch(numBuffers: c_int, bufferElements: c_int) callconv(.c) rlRenderBatch {
    var batch = std.mem.zeroes(rlRenderBatch);
    if (!isGpuReady) {
        TraceLog(RL_LOG_WARNING, "GL: GPU is not ready to load data, trying to load before InitWindow()?");
        return batch;
    }

    const nb: usize = @intCast(numBuffers);
    const be: usize = @intCast(bufferElements);

    // Initialize CPU (RAM) vertex buffers
    batch.vertexBuffer = @ptrCast(@alignCast(calloc(nb, @sizeOf(rlVertexBuffer))));

    var i: usize = 0;
    while (i < nb) : (i += 1) {
        const vb = &batch.vertexBuffer[i];
        vb.elementCount = bufferElements;

        vb.vertices = @ptrCast(@alignCast(calloc(be * 3 * 4, @sizeOf(f32))));
        vb.texcoords = @ptrCast(@alignCast(calloc(be * 2 * 4, @sizeOf(f32))));
        vb.normals = @ptrCast(@alignCast(calloc(be * 3 * 4, @sizeOf(f32))));
        vb.colors = @ptrCast(@alignCast(calloc(be * 4 * 4, @sizeOf(u8))));
        vb.indices = @ptrCast(@alignCast(calloc(be * 6, @sizeOf(BatchIndex))));

        var j: usize = 0;
        while (j < 3 * 4 * be) : (j += 1) vb.vertices[j] = 0.0;
        j = 0;
        while (j < 2 * 4 * be) : (j += 1) vb.texcoords[j] = 0.0;
        j = 0;
        while (j < 3 * 4 * be) : (j += 1) vb.normals[j] = 0.0;
        j = 0;
        while (j < 4 * 4 * be) : (j += 1) vb.colors[j] = 0;

        var k: BatchIndex = 0;
        // Indices can be initialized right now
        j = 0;
        while (j < 6 * be) : (j += 6) {
            vb.indices[j] = 4 * k;
            vb.indices[j + 1] = 4 * k + 1;
            vb.indices[j + 2] = 4 * k + 2;
            vb.indices[j + 3] = 4 * k;
            vb.indices[j + 4] = 4 * k + 2;
            vb.indices[j + 5] = 4 * k + 3;
            k += 1;
        }

        RLGL.State.vertexCounter = 0;
    }

    TraceLog(RL_LOG_INFO, "RLGL: Render batch vertex buffers loaded successfully in RAM (CPU)");

    // Upload to GPU (VRAM) vertex data and initialize VAOs/VBOs
    i = 0;
    while (i < nb) : (i += 1) {
        const vb = &batch.vertexBuffer[i];
        if (RLGL.ExtSupported.vao) {
            gl.glad_glGenVertexArrays.?(1, &vb.vaoId);
            gl.glad_glBindVertexArray.?(vb.vaoId);
        }

        // Vertex position buffer (shader-location = 0)
        gl.glad_glGenBuffers.?(1, &vb.vboId[0]);
        gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, vb.vboId[0]);
        gl.glad_glBufferData.?(gl.GL_ARRAY_BUFFER, @intCast(be * 3 * 4 * @sizeOf(f32)), vb.vertices, gl.GL_DYNAMIC_DRAW);
        gl.glad_glEnableVertexAttribArray.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_POSITION]));
        gl.glad_glVertexAttribPointer.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_POSITION]), 3, gl.GL_FLOAT, 0, 0, null);

        // Vertex texcoord buffer (shader-location = 1)
        gl.glad_glGenBuffers.?(1, &vb.vboId[1]);
        gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, vb.vboId[1]);
        gl.glad_glBufferData.?(gl.GL_ARRAY_BUFFER, @intCast(be * 2 * 4 * @sizeOf(f32)), vb.texcoords, gl.GL_DYNAMIC_DRAW);
        gl.glad_glEnableVertexAttribArray.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_TEXCOORD01]));
        gl.glad_glVertexAttribPointer.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_TEXCOORD01]), 2, gl.GL_FLOAT, 0, 0, null);

        // Vertex normal buffer (shader-location = 2)
        gl.glad_glGenBuffers.?(1, &vb.vboId[2]);
        gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, vb.vboId[2]);
        gl.glad_glBufferData.?(gl.GL_ARRAY_BUFFER, @intCast(be * 3 * 4 * @sizeOf(f32)), vb.normals, gl.GL_DYNAMIC_DRAW);
        gl.glad_glEnableVertexAttribArray.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_NORMAL]));
        gl.glad_glVertexAttribPointer.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_NORMAL]), 3, gl.GL_FLOAT, 0, 0, null);

        // Vertex color buffer (shader-location = 3)
        gl.glad_glGenBuffers.?(1, &vb.vboId[3]);
        gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, vb.vboId[3]);
        gl.glad_glBufferData.?(gl.GL_ARRAY_BUFFER, @intCast(be * 4 * 4 * @sizeOf(u8)), vb.colors, gl.GL_DYNAMIC_DRAW);
        gl.glad_glEnableVertexAttribArray.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_COLOR]));
        gl.glad_glVertexAttribPointer.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_COLOR]), 4, gl.GL_UNSIGNED_BYTE, @intCast(gl.GL_TRUE), 0, null);

        // Fill index buffer
        gl.glad_glGenBuffers.?(1, &vb.vboId[4]);
        gl.glad_glBindBuffer.?(gl.GL_ELEMENT_ARRAY_BUFFER, vb.vboId[4]);
        gl.glad_glBufferData.?(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(be * 6 * @sizeOf(BatchIndex)), vb.indices, gl.GL_STATIC_DRAW);
    }

    TraceLog(RL_LOG_INFO, "RLGL: Render batch vertex buffers loaded successfully in VRAM (GPU)");

    if (RLGL.ExtSupported.vao) gl.glad_glBindVertexArray.?(0);

    // Init draw calls tracking system
    batch.draws = @ptrCast(@alignCast(calloc(@intCast(RL_DEFAULT_BATCH_DRAWCALLS), @sizeOf(rlDrawCall))));

    i = 0;
    while (i < @as(usize, @intCast(RL_DEFAULT_BATCH_DRAWCALLS))) : (i += 1) {
        batch.draws[i].mode = RL_QUADS;
        batch.draws[i].vertexCount = 0;
        batch.draws[i].vertexAlignment = 0;
        batch.draws[i].textureId = RLGL.State.defaultTextureId;
    }

    batch.bufferCount = numBuffers;
    batch.drawCounter = 1;
    batch.currentDepth = -1.0;

    return batch;
}

// Unload default internal buffers vertex data from CPU and GPU
export fn rlUnloadRenderBatch(batch: rlRenderBatch) callconv(.c) void {
    gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, 0);
    gl.glad_glBindBuffer.?(gl.GL_ELEMENT_ARRAY_BUFFER, 0);

    var i: usize = 0;
    while (i < @as(usize, @intCast(batch.bufferCount))) : (i += 1) {
        const vb = &batch.vertexBuffer[i];
        if (RLGL.ExtSupported.vao) {
            gl.glad_glBindVertexArray.?(vb.vaoId);
            gl.glad_glDisableVertexAttribArray.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION);
            gl.glad_glDisableVertexAttribArray.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD);
            gl.glad_glDisableVertexAttribArray.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL);
            gl.glad_glDisableVertexAttribArray.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR);
            gl.glad_glBindVertexArray.?(0);
        }

        gl.glad_glDeleteBuffers.?(1, &vb.vboId[0]);
        gl.glad_glDeleteBuffers.?(1, &vb.vboId[1]);
        gl.glad_glDeleteBuffers.?(1, &vb.vboId[2]);
        gl.glad_glDeleteBuffers.?(1, &vb.vboId[3]);
        gl.glad_glDeleteBuffers.?(1, &vb.vboId[4]);

        if (RLGL.ExtSupported.vao) gl.glad_glDeleteVertexArrays.?(1, &vb.vaoId);

        RL_FREE(vb.vertices);
        RL_FREE(vb.texcoords);
        RL_FREE(vb.normals);
        RL_FREE(vb.colors);
        RL_FREE(vb.indices);
    }

    RL_FREE(batch.vertexBuffer);
    RL_FREE(batch.draws);
}

// Draw render batch
// NOTE: Batch is reseted and current buffer is updated (for multi-buffer config)
export fn rlDrawRenderBatch(batch: *rlRenderBatch) callconv(.c) void {
    const cb: usize = @intCast(batch.currentBuffer);

    // Update batch vertex buffers
    if (RLGL.State.vertexCounter > 0) {
        if (RLGL.ExtSupported.vao) gl.glad_glBindVertexArray.?(batch.vertexBuffer[cb].vaoId);

        const vc: isize = @intCast(RLGL.State.vertexCounter);

        // Vertex positions buffer
        gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, batch.vertexBuffer[cb].vboId[0]);
        gl.glad_glBufferSubData.?(gl.GL_ARRAY_BUFFER, 0, vc * 3 * @sizeOf(f32), batch.vertexBuffer[cb].vertices);

        // Texture coordinates buffer
        gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, batch.vertexBuffer[cb].vboId[1]);
        gl.glad_glBufferSubData.?(gl.GL_ARRAY_BUFFER, 0, vc * 2 * @sizeOf(f32), batch.vertexBuffer[cb].texcoords);

        // Normals buffer
        gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, batch.vertexBuffer[cb].vboId[2]);
        gl.glad_glBufferSubData.?(gl.GL_ARRAY_BUFFER, 0, vc * 3 * @sizeOf(f32), batch.vertexBuffer[cb].normals);

        // Colors buffer
        gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, batch.vertexBuffer[cb].vboId[3]);
        gl.glad_glBufferSubData.?(gl.GL_ARRAY_BUFFER, 0, vc * 4 * @sizeOf(u8), batch.vertexBuffer[cb].colors);

        if (RLGL.ExtSupported.vao) gl.glad_glBindVertexArray.?(0);
    }

    // Draw batch vertex buffers (considering VR stereo if required)
    const matProjection = RLGL.State.projection;
    const matModelView = RLGL.State.modelview;

    var eyeCount: c_int = 1;
    if (RLGL.State.stereoRender) eyeCount = 2;

    var eye: c_int = 0;
    while (eye < eyeCount) : (eye += 1) {
        if (eyeCount == 2) {
            // Setup current eye viewport (half screen width)
            rlViewport(@divTrunc(eye * RLGL.State.framebufferWidth, 2), 0, @divTrunc(RLGL.State.framebufferWidth, 2), RLGL.State.framebufferHeight);

            rlSetMatrixModelview(rlMatrixMultiply(matModelView, RLGL.State.viewOffsetStereo[@intCast(eye)]));
            rlSetMatrixProjection(RLGL.State.projectionStereo[@intCast(eye)]);
        }

        // Draw buffers
        if (RLGL.State.vertexCounter > 0) {
            gl.glad_glUseProgram.?(RLGL.State.currentShaderId);

            // Create modelview-projection matrix and upload to shader
            const matMVP = rlMatrixMultiply(RLGL.State.modelview, RLGL.State.projection);
            var fMVP = rlMatrixToFloatV(matMVP);
            gl.glad_glUniformMatrix4fv.?(RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_MVP], 1, @intCast(gl.GL_FALSE), &fMVP.v);

            if (RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_PROJECTION] != -1) {
                var fProj = rlMatrixToFloatV(RLGL.State.projection);
                gl.glad_glUniformMatrix4fv.?(RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_PROJECTION], 1, @intCast(gl.GL_FALSE), &fProj.v);
            }

            if (RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_VIEW] != -1) {
                var fView = rlMatrixToFloatV(RLGL.State.modelview);
                gl.glad_glUniformMatrix4fv.?(RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_VIEW], 1, @intCast(gl.GL_FALSE), &fView.v);
            }

            if (RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_MODEL] != -1) {
                var fModel = rlMatrixToFloatV(RLGL.State.transform);
                gl.glad_glUniformMatrix4fv.?(RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_MODEL], 1, @intCast(gl.GL_FALSE), &fModel.v);
            }

            if (RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_NORMAL] != -1) {
                var fNormal = rlMatrixToFloatV(rlMatrixTranspose(rlMatrixInvert(RLGL.State.transform)));
                gl.glad_glUniformMatrix4fv.?(RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_NORMAL], 1, @intCast(gl.GL_FALSE), &fNormal.v);
            }

            if (RLGL.ExtSupported.vao) {
                gl.glad_glBindVertexArray.?(batch.vertexBuffer[cb].vaoId);
            } else {
                gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, batch.vertexBuffer[cb].vboId[0]);
                gl.glad_glVertexAttribPointer.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_POSITION]), 3, gl.GL_FLOAT, 0, 0, null);
                gl.glad_glEnableVertexAttribArray.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_POSITION]));

                gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, batch.vertexBuffer[cb].vboId[1]);
                gl.glad_glVertexAttribPointer.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_TEXCOORD01]), 2, gl.GL_FLOAT, 0, 0, null);
                gl.glad_glEnableVertexAttribArray.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_TEXCOORD01]));

                gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, batch.vertexBuffer[cb].vboId[2]);
                gl.glad_glVertexAttribPointer.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_NORMAL]), 3, gl.GL_FLOAT, 0, 0, null);
                gl.glad_glEnableVertexAttribArray.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_NORMAL]));

                gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, batch.vertexBuffer[cb].vboId[3]);
                gl.glad_glVertexAttribPointer.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_COLOR]), 4, gl.GL_UNSIGNED_BYTE, @intCast(gl.GL_TRUE), 0, null);
                gl.glad_glEnableVertexAttribArray.?(@bitCast(RLGL.State.currentShaderLocs[RL_SHADER_LOC_VERTEX_COLOR]));

                gl.glad_glBindBuffer.?(gl.GL_ELEMENT_ARRAY_BUFFER, batch.vertexBuffer[cb].vboId[4]);
            }

            // Setup some default shader values
            gl.glad_glUniform4f.?(RLGL.State.currentShaderLocs[RL_SHADER_LOC_COLOR_DIFFUSE], 1.0, 1.0, 1.0, 1.0);
            gl.glad_glUniform1i.?(RLGL.State.currentShaderLocs[RL_SHADER_LOC_MAP_DIFFUSE], 0);

            // Activate additional sampler textures
            var t: usize = 0;
            while (t < @as(usize, @intCast(RL_DEFAULT_BATCH_MAX_TEXTURE_UNITS))) : (t += 1) {
                if (RLGL.State.activeTextureId[t] > 0) {
                    gl.glad_glActiveTexture.?(gl.GL_TEXTURE0 + 1 + @as(c_uint, @intCast(t)));
                    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, RLGL.State.activeTextureId[t]);
                }
            }

            // Activate default sampler2D texture0
            gl.glad_glActiveTexture.?(gl.GL_TEXTURE0);

            var vertexOffset: c_int = 0;
            var di: usize = 0;
            while (di < @as(usize, @intCast(batch.drawCounter))) : (di += 1) {
                const draw = batch.draws[di];
                gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, draw.textureId);

                if ((draw.mode == RL_LINES) or (draw.mode == RL_TRIANGLES)) {
                    gl.glad_glDrawArrays.?(@intCast(draw.mode), vertexOffset, draw.vertexCount);
                } else {
                    const indexOffset: usize = @as(usize, @intCast(@divTrunc(vertexOffset, 4))) * 6 * @sizeOf(BatchIndex);
                    const indexType = if (es2) gl.GL_UNSIGNED_SHORT else gl.GL_UNSIGNED_INT;
                    gl.glad_glDrawElements.?(gl.GL_TRIANGLES, @divTrunc(draw.vertexCount, 4) * 6, indexType, @ptrFromInt(indexOffset));
                }

                vertexOffset += (draw.vertexCount + draw.vertexAlignment);
            }

            if (!RLGL.ExtSupported.vao) {
                gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, 0);
                gl.glad_glBindBuffer.?(gl.GL_ELEMENT_ARRAY_BUFFER, 0);
            }

            gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, 0);
        }

        if (RLGL.ExtSupported.vao) gl.glad_glBindVertexArray.?(0);

        gl.glad_glUseProgram.?(0);
    }

    // Restore viewport to default measures
    if (eyeCount == 2) rlViewport(0, 0, RLGL.State.framebufferWidth, RLGL.State.framebufferHeight);

    // Reset batch buffers
    RLGL.State.vertexCounter = 0;
    batch.currentDepth = -1.0;

    RLGL.State.projection = matProjection;
    RLGL.State.modelview = matModelView;

    // Reset draws array
    var i: usize = 0;
    while (i < @as(usize, @intCast(RL_DEFAULT_BATCH_DRAWCALLS))) : (i += 1) {
        batch.draws[i].mode = RL_QUADS;
        batch.draws[i].vertexCount = 0;
        batch.draws[i].textureId = RLGL.State.defaultTextureId;
    }

    // Reset active texture units for next batch
    i = 0;
    while (i < @as(usize, @intCast(RL_DEFAULT_BATCH_MAX_TEXTURE_UNITS))) : (i += 1) RLGL.State.activeTextureId[i] = 0;

    batch.drawCounter = 1;

    batch.currentBuffer += 1;
    if (batch.currentBuffer >= batch.bufferCount) batch.currentBuffer = 0;
}

// Set the active render batch for rlgl
export fn rlSetRenderBatchActive(batch: ?*rlRenderBatch) callconv(.c) void {
    rlDrawRenderBatch(RLGL.currentBatch);

    if (batch) |b| RLGL.currentBatch = b else RLGL.currentBatch = &RLGL.defaultBatch;
}

// Update and draw internal render batch
export fn rlDrawRenderBatchActive() callconv(.c) void {
    rlDrawRenderBatch(RLGL.currentBatch);
}

// Check internal buffer overflow for a given number of vertex
export fn rlCheckRenderBatchLimit(vCount: c_int) callconv(.c) bool {
    var overflow = false;
    const batch = RLGL.currentBatch;

    if ((RLGL.State.vertexCounter + vCount) >= (batch.vertexBuffer[@intCast(batch.currentBuffer)].elementCount * 4)) {
        overflow = true;

        const currentMode = batch.draws[@intCast(batch.drawCounter - 1)].mode;
        const currentTexture = batch.draws[@intCast(batch.drawCounter - 1)].textureId;

        rlDrawRenderBatch(batch);

        batch.draws[@intCast(batch.drawCounter - 1)].mode = currentMode;
        batch.draws[@intCast(batch.drawCounter - 1)].textureId = currentTexture;
    }

    return overflow;
}

// Textures data management
//-----------------------------------------------------------------------------------------

// Convert image data to OpenGL texture (returns OpenGL valid Id)
export fn rlLoadTexture(data: ?*const anyopaque, width: c_int, height: c_int, format: c_int, mipmapCount: c_int) callconv(.c) c_uint {
    var id: c_uint = 0;
    if (!isGpuReady) {
        TraceLog(RL_LOG_WARNING, "GL: GPU is not ready to load data, trying to load before InitWindow()?");
        return id;
    }

    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, 0); // Free any old binding

    if ((!RLGL.ExtSupported.texCompDXT) and ((format == RL_PIXELFORMAT_COMPRESSED_DXT1_RGB) or (format == RL_PIXELFORMAT_COMPRESSED_DXT1_RGBA) or
        (format == RL_PIXELFORMAT_COMPRESSED_DXT3_RGBA) or (format == RL_PIXELFORMAT_COMPRESSED_DXT5_RGBA)))
    {
        TraceLog(RL_LOG_WARNING, "GL: DXT compressed texture format not supported");
        return id;
    }
    if ((!RLGL.ExtSupported.texCompETC1) and (format == RL_PIXELFORMAT_COMPRESSED_ETC1_RGB)) {
        TraceLog(RL_LOG_WARNING, "GL: ETC1 compressed texture format not supported");
        return id;
    }
    if ((!RLGL.ExtSupported.texCompETC2) and ((format == RL_PIXELFORMAT_COMPRESSED_ETC2_RGB) or (format == RL_PIXELFORMAT_COMPRESSED_ETC2_EAC_RGBA))) {
        TraceLog(RL_LOG_WARNING, "GL: ETC2 compressed texture format not supported");
        return id;
    }
    if ((!RLGL.ExtSupported.texCompPVRT) and ((format == RL_PIXELFORMAT_COMPRESSED_PVRT_RGB) or (format == RL_PIXELFORMAT_COMPRESSED_PVRT_RGBA))) {
        TraceLog(RL_LOG_WARNING, "GL: PVRT compressed texture format not supported");
        return id;
    }
    if ((!RLGL.ExtSupported.texCompASTC) and ((format == RL_PIXELFORMAT_COMPRESSED_ASTC_4x4_RGBA) or (format == RL_PIXELFORMAT_COMPRESSED_ASTC_8x8_RGBA))) {
        TraceLog(RL_LOG_WARNING, "GL: ASTC compressed texture format not supported");
        return id;
    }

    gl.glad_glPixelStorei.?(gl.GL_UNPACK_ALIGNMENT, 1);

    gl.glad_glGenTextures.?(1, &id);
    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, id);

    var mipWidth = width;
    var mipHeight = height;
    var mipOffset: c_int = 0;

    var dataPtr: ?[*]const u8 = null;
    if (data != null) dataPtr = @ptrCast(data);

    var i: c_int = 0;
    while (i < mipmapCount) : (i += 1) {
        const mipSize = rlGetPixelDataSize(mipWidth, mipHeight, format);

        var glInternalFormat: c_uint = undefined;
        var glFormat: c_uint = undefined;
        var glType: c_uint = undefined;
        rlGetGlTextureFormats(format, &glInternalFormat, &glFormat, &glType);

        TraceLog(RL_LOG_DEBUG, "TEXTURE: Load mipmap level %i (%i x %i), size: %i, offset: %i", i, mipWidth, mipHeight, mipSize, mipOffset);

        if (glInternalFormat != 0) {
            if (format < RL_PIXELFORMAT_COMPRESSED_DXT1_RGB) {
                gl.glad_glTexImage2D.?(gl.GL_TEXTURE_2D, i, @intCast(glInternalFormat), mipWidth, mipHeight, 0, glFormat, glType, dataPtr);
            } else gl.glad_glCompressedTexImage2D.?(gl.GL_TEXTURE_2D, i, glInternalFormat, mipWidth, mipHeight, 0, mipSize, dataPtr);

            // Swizzle grayscale into RGB on GL 3.3. ES uploads these formats as
            // GL_LUMINANCE(_ALPHA) instead (rlGetGlTextureFormats).
            if (es2) {} else if (format == RL_PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) {
                const swizzleMask = [4]c_int{ @intCast(gl.GL_RED), @intCast(gl.GL_RED), @intCast(gl.GL_RED), @intCast(gl.GL_ONE) };
                gl.glad_glTexParameteriv.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_SWIZZLE_RGBA, &swizzleMask);
            } else if (format == RL_PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA) {
                const swizzleMask = [4]c_int{ @intCast(gl.GL_RED), @intCast(gl.GL_RED), @intCast(gl.GL_RED), @intCast(gl.GL_GREEN) };
                gl.glad_glTexParameteriv.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_SWIZZLE_RGBA, &swizzleMask);
            }
        }

        mipWidth = @divTrunc(mipWidth, 2);
        mipHeight = @divTrunc(mipHeight, 2);
        mipOffset += mipSize;
        if (data != null) dataPtr.? += @intCast(mipSize);

        if (mipWidth < 1) mipWidth = 1;
        if (mipHeight < 1) mipHeight = 1;
    }

    // Texture parameters configuration
    if (es2) {
        // NOTE: OpenGL ES 2.0 with no GL_OES_texture_npot support (i.e. WebGL) has limited NPOT support, so CLAMP_TO_EDGE must be used
        const texIsPOT = (width > 0 and (width & (width - 1)) == 0) and (height > 0 and (height & (height - 1)) == 0);
        const wrap = if (texIsPOT or RLGL.ExtSupported.texNPOT) gl.GL_REPEAT else gl.GL_CLAMP_TO_EDGE;
        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, @intCast(wrap));
        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, @intCast(wrap));
    } else {
        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, @intCast(gl.GL_REPEAT));
        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, @intCast(gl.GL_REPEAT));
    }

    gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, @intCast(gl.GL_NEAREST));
    gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, @intCast(gl.GL_NEAREST));

    // rlgl.h sets mipmap filtering and levels on GL 3.3 only.
    if (!es2 and mipmapCount > 1) {
        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, @intCast(gl.GL_LINEAR));
        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, @intCast(gl.GL_LINEAR_MIPMAP_LINEAR));

        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_BASE_LEVEL, 0);
        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAX_LEVEL, mipmapCount - 1);
    }

    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, 0);

    if (id > 0) {
        TraceLog(RL_LOG_INFO, "TEXTURE: [ID %i] Texture loaded successfully (%ix%i | %s | %i mipmaps)", id, width, height, rlGetPixelFormatName(@intCast(format)), mipmapCount);
    } else TraceLog(RL_LOG_WARNING, "TEXTURE: Failed to load texture");

    return id;
}

// Load depth texture/renderbuffer (to be attached to fbo)
export fn rlLoadTextureDepth(width: c_int, height: c_int, useRenderBuffer_in: bool) callconv(.c) c_uint {
    var id: c_uint = 0;
    if (!isGpuReady) {
        TraceLog(RL_LOG_WARNING, "GL: GPU is not ready to load data, trying to load before InitWindow()?");
        return id;
    }

    var useRenderBuffer = useRenderBuffer_in;
    if (!RLGL.ExtSupported.texDepth) useRenderBuffer = true;

    // Possible formats: GL_DEPTH_COMPONENT16, GL_DEPTH_COMPONENT24, GL_DEPTH_COMPONENT32 and GL_DEPTH_COMPONENT32F
    // On ES3 (WebGL 2) rlgl.h picks a sized format from maxDepthBits.
    const glInternalFormat: c_uint = if (!es2)
        gl.GL_DEPTH_COMPONENT
    else if (RLGL.ExtSupported.maxDepthBits == 24)
        gl.GL_DEPTH_COMPONENT24
    else
        gl.GL_DEPTH_COMPONENT16;

    if (!useRenderBuffer and RLGL.ExtSupported.texDepth) {
        gl.glad_glGenTextures.?(1, &id);
        gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, id);
        gl.glad_glTexImage2D.?(gl.GL_TEXTURE_2D, 0, @intCast(glInternalFormat), width, height, 0, gl.GL_DEPTH_COMPONENT, gl.GL_UNSIGNED_INT, null);

        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, @intCast(gl.GL_NEAREST));
        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, @intCast(gl.GL_NEAREST));
        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, @intCast(gl.GL_CLAMP_TO_EDGE));
        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, @intCast(gl.GL_CLAMP_TO_EDGE));

        gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, 0);

        TraceLog(RL_LOG_INFO, "TEXTURE: Depth texture loaded successfully");
    } else {
        gl.glad_glGenRenderbuffers.?(1, &id);
        gl.glad_glBindRenderbuffer.?(gl.GL_RENDERBUFFER, id);
        gl.glad_glRenderbufferStorage.?(gl.GL_RENDERBUFFER, glInternalFormat, width, height);

        gl.glad_glBindRenderbuffer.?(gl.GL_RENDERBUFFER, 0);

        TraceLog(RL_LOG_INFO, "TEXTURE: [ID %i] Depth renderbuffer loaded successfully (%i bits)", id, if (RLGL.ExtSupported.maxDepthBits >= 24) RLGL.ExtSupported.maxDepthBits else 16);
    }

    return id;
}

// Load texture cubemap
export fn rlLoadTextureCubemap(data: ?*const anyopaque, size: c_int, format: c_int, mipmapCount: c_int) callconv(.c) c_uint {
    var id: c_uint = 0;
    if (!isGpuReady) {
        TraceLog(RL_LOG_WARNING, "GL: GPU is not ready to load data, trying to load before InitWindow()?");
        return id;
    }

    var mipSize = size;

    var dataPtr: ?[*]const u8 = null;
    if (data != null) dataPtr = @ptrCast(data);

    var dataSize = rlGetPixelDataSize(size, size, format);

    gl.glad_glGenTextures.?(1, &id);
    gl.glad_glBindTexture.?(gl.GL_TEXTURE_CUBE_MAP, id);

    var glInternalFormat: c_uint = undefined;
    var glFormat: c_uint = undefined;
    var glType: c_uint = undefined;
    rlGetGlTextureFormats(format, &glInternalFormat, &glFormat, &glType);

    if (glInternalFormat != 0) {
        var i: c_int = 0;
        while (i < 6 * mipmapCount) : (i += 1) {
            const mipmapLevel = @divTrunc(i, 6);
            const face: c_uint = @intCast(@rem(i, 6));

            if (data == null) {
                if (format < RL_PIXELFORMAT_COMPRESSED_DXT1_RGB) {
                    if ((format == RL_PIXELFORMAT_UNCOMPRESSED_R32) or
                        (format == RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32A32) or
                        (format == RL_PIXELFORMAT_UNCOMPRESSED_R16) or
                        (format == RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16A16))
                    {
                        TraceLog(RL_LOG_WARNING, "TEXTURES: Cubemap requested format not supported");
                    } else gl.glad_glTexImage2D.?(gl.GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, mipmapLevel, @intCast(glInternalFormat), mipSize, mipSize, 0, glFormat, glType, null);
                } else TraceLog(RL_LOG_WARNING, "TEXTURES: Empty cubemap creation does not support compressed format");
            } else {
                const facePtr = dataPtr.? + @as(usize, @intCast(face)) * @as(usize, @intCast(dataSize));
                if (format < RL_PIXELFORMAT_COMPRESSED_DXT1_RGB) {
                    gl.glad_glTexImage2D.?(gl.GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, mipmapLevel, @intCast(glInternalFormat), mipSize, mipSize, 0, glFormat, glType, facePtr);
                } else gl.glad_glCompressedTexImage2D.?(gl.GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, mipmapLevel, glInternalFormat, mipSize, mipSize, 0, dataSize, facePtr);
            }

            // GL 3.3 only, as in rlLoadTexture
            if (es2) {} else if (format == RL_PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) {
                const swizzleMask = [4]c_int{ @intCast(gl.GL_RED), @intCast(gl.GL_RED), @intCast(gl.GL_RED), @intCast(gl.GL_ONE) };
                gl.glad_glTexParameteriv.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_SWIZZLE_RGBA, &swizzleMask);
            } else if (format == RL_PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA) {
                const swizzleMask = [4]c_int{ @intCast(gl.GL_RED), @intCast(gl.GL_RED), @intCast(gl.GL_RED), @intCast(gl.GL_GREEN) };
                gl.glad_glTexParameteriv.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_SWIZZLE_RGBA, &swizzleMask);
            }

            if (face == 5) {
                mipSize = @divTrunc(mipSize, 2);
                if (data != null) dataPtr.? += @as(usize, @intCast(dataSize)) * 6;

                if (mipSize < 1) mipSize = 1;

                dataSize = rlGetPixelDataSize(mipSize, mipSize, format);
            }
        }
    }

    if (mipmapCount > 1) {
        gl.glad_glTexParameteri.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MIN_FILTER, @intCast(gl.GL_LINEAR_MIPMAP_LINEAR));
    } else gl.glad_glTexParameteri.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MIN_FILTER, @intCast(gl.GL_LINEAR));

    gl.glad_glTexParameteri.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MAG_FILTER, @intCast(gl.GL_LINEAR));
    gl.glad_glTexParameteri.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_S, @intCast(gl.GL_CLAMP_TO_EDGE));
    gl.glad_glTexParameteri.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_T, @intCast(gl.GL_CLAMP_TO_EDGE));
    if (!es2) gl.glad_glTexParameteri.?(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_R, @intCast(gl.GL_CLAMP_TO_EDGE)); // Flag not supported on OpenGL ES 2.0

    gl.glad_glBindTexture.?(gl.GL_TEXTURE_CUBE_MAP, 0);

    if (id > 0) {
        TraceLog(RL_LOG_INFO, "TEXTURE: [ID %i] Cubemap texture loaded successfully (%ix%i)", id, size, size);
    } else TraceLog(RL_LOG_WARNING, "TEXTURE: Failed to load cubemap texture");

    return id;
}

// Update already loaded texture in GPU with new data
export fn rlUpdateTexture(id: c_uint, offsetX: c_int, offsetY: c_int, width: c_int, height: c_int, format: c_int, data: ?*const anyopaque) callconv(.c) void {
    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, id);

    var glInternalFormat: c_uint = undefined;
    var glFormat: c_uint = undefined;
    var glType: c_uint = undefined;
    rlGetGlTextureFormats(format, &glInternalFormat, &glFormat, &glType);

    if ((glInternalFormat != 0) and (format < RL_PIXELFORMAT_COMPRESSED_DXT1_RGB)) {
        gl.glad_glTexSubImage2D.?(gl.GL_TEXTURE_2D, 0, offsetX, offsetY, width, height, glFormat, glType, data);
    } else TraceLog(RL_LOG_WARNING, "TEXTURE: [ID %i] Failed to update for current texture format (%i)", id, format);
}

// Get OpenGL internal formats and data type from raylib PixelFormat (GL 3.3 branch)
export fn rlGetGlTextureFormats(format: c_int, glInternalFormat: [*c]c_uint, glFormat: [*c]c_uint, glType: [*c]c_uint) callconv(.c) void {
    glInternalFormat.* = 0;
    glFormat.* = 0;
    glType.* = 0;

    // NOTE: on OpenGL ES 2.0 (WebGL), internalFormat must match format and options
    // allowed are: GL_LUMINANCE, GL_RGB, GL_RGBA. rlgl.h keeps that rule on ES3. Its
    // ES float formats (GL_R32F_EXT, GL_RED_EXT, ...) have the same values as the
    // GL 3.3 names used below, so only the 8-bit formats differ.
    switch (format) {
        RL_PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => {
            glInternalFormat.* = if (es2) gl.GL_LUMINANCE else gl.GL_R8;
            glFormat.* = if (es2) gl.GL_LUMINANCE else gl.GL_RED;
            glType.* = gl.GL_UNSIGNED_BYTE;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => {
            glInternalFormat.* = if (es2) gl.GL_LUMINANCE_ALPHA else gl.GL_RG8;
            glFormat.* = if (es2) gl.GL_LUMINANCE_ALPHA else gl.GL_RG;
            glType.* = gl.GL_UNSIGNED_BYTE;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_R5G6B5 => {
            glInternalFormat.* = if (es2) gl.GL_RGB else gl.GL_RGB565;
            glFormat.* = gl.GL_RGB;
            glType.* = gl.GL_UNSIGNED_SHORT_5_6_5;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8 => {
            glInternalFormat.* = if (es2) gl.GL_RGB else gl.GL_RGB8;
            glFormat.* = gl.GL_RGB;
            glType.* = gl.GL_UNSIGNED_BYTE;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => {
            glInternalFormat.* = if (es2) gl.GL_RGBA else gl.GL_RGB5_A1;
            glFormat.* = gl.GL_RGBA;
            glType.* = gl.GL_UNSIGNED_SHORT_5_5_5_1;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => {
            glInternalFormat.* = if (es2) gl.GL_RGBA else gl.GL_RGBA4;
            glFormat.* = gl.GL_RGBA;
            glType.* = gl.GL_UNSIGNED_SHORT_4_4_4_4;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => {
            glInternalFormat.* = if (es2) gl.GL_RGBA else gl.GL_RGBA8;
            glFormat.* = gl.GL_RGBA;
            glType.* = gl.GL_UNSIGNED_BYTE;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_R32 => {
            if (RLGL.ExtSupported.texFloat32) glInternalFormat.* = gl.GL_R32F;
            glFormat.* = gl.GL_RED;
            glType.* = gl.GL_FLOAT;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32 => {
            if (RLGL.ExtSupported.texFloat32) glInternalFormat.* = gl.GL_RGB32F;
            glFormat.* = gl.GL_RGB;
            glType.* = gl.GL_FLOAT;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => {
            if (RLGL.ExtSupported.texFloat32) glInternalFormat.* = gl.GL_RGBA32F;
            glFormat.* = gl.GL_RGBA;
            glType.* = gl.GL_FLOAT;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_R16 => {
            if (RLGL.ExtSupported.texFloat16) glInternalFormat.* = gl.GL_R16F;
            glFormat.* = gl.GL_RED;
            glType.* = gl.GL_HALF_FLOAT;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16 => {
            if (RLGL.ExtSupported.texFloat16) glInternalFormat.* = gl.GL_RGB16F;
            glFormat.* = gl.GL_RGB;
            glType.* = gl.GL_HALF_FLOAT;
        },
        RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => {
            if (RLGL.ExtSupported.texFloat16) glInternalFormat.* = gl.GL_RGBA16F;
            glFormat.* = gl.GL_RGBA;
            glType.* = gl.GL_HALF_FLOAT;
        },
        RL_PIXELFORMAT_COMPRESSED_DXT1_RGB => {
            if (RLGL.ExtSupported.texCompDXT) glInternalFormat.* = gl.GL_COMPRESSED_RGB_S3TC_DXT1_EXT;
        },
        RL_PIXELFORMAT_COMPRESSED_DXT1_RGBA => {
            if (RLGL.ExtSupported.texCompDXT) glInternalFormat.* = gl.GL_COMPRESSED_RGBA_S3TC_DXT1_EXT;
        },
        RL_PIXELFORMAT_COMPRESSED_DXT3_RGBA => {
            if (RLGL.ExtSupported.texCompDXT) glInternalFormat.* = gl.GL_COMPRESSED_RGBA_S3TC_DXT3_EXT;
        },
        RL_PIXELFORMAT_COMPRESSED_DXT5_RGBA => {
            if (RLGL.ExtSupported.texCompDXT) glInternalFormat.* = gl.GL_COMPRESSED_RGBA_S3TC_DXT5_EXT;
        },
        RL_PIXELFORMAT_COMPRESSED_ETC1_RGB => {
            if (RLGL.ExtSupported.texCompETC1) glInternalFormat.* = gl.GL_ETC1_RGB8_OES;
        },
        RL_PIXELFORMAT_COMPRESSED_ETC2_RGB => {
            if (RLGL.ExtSupported.texCompETC2) glInternalFormat.* = gl.GL_COMPRESSED_RGB8_ETC2;
        },
        RL_PIXELFORMAT_COMPRESSED_ETC2_EAC_RGBA => {
            if (RLGL.ExtSupported.texCompETC2) glInternalFormat.* = gl.GL_COMPRESSED_RGBA8_ETC2_EAC;
        },
        RL_PIXELFORMAT_COMPRESSED_PVRT_RGB => {
            if (RLGL.ExtSupported.texCompPVRT) glInternalFormat.* = gl.GL_COMPRESSED_RGB_PVRTC_4BPPV1_IMG;
        },
        RL_PIXELFORMAT_COMPRESSED_PVRT_RGBA => {
            if (RLGL.ExtSupported.texCompPVRT) glInternalFormat.* = gl.GL_COMPRESSED_RGBA_PVRTC_4BPPV1_IMG;
        },
        RL_PIXELFORMAT_COMPRESSED_ASTC_4x4_RGBA => {
            if (RLGL.ExtSupported.texCompASTC) glInternalFormat.* = gl.GL_COMPRESSED_RGBA_ASTC_4x4_KHR;
        },
        RL_PIXELFORMAT_COMPRESSED_ASTC_8x8_RGBA => {
            if (RLGL.ExtSupported.texCompASTC) glInternalFormat.* = gl.GL_COMPRESSED_RGBA_ASTC_8x8_KHR;
        },
        else => TraceLog(RL_LOG_WARNING, "TEXTURE: Current format not supported (%i)", format),
    }
}

// Unload texture from GPU memory
export fn rlUnloadTexture(id: c_uint) callconv(.c) void {
    var idv = id;
    gl.glad_glDeleteTextures.?(1, &idv);
}

// Generate mipmap data for selected texture
export fn rlGenTextureMipmaps(id: c_uint, width: c_int, height: c_int, format: c_int, mipmaps: [*c]c_int) callconv(.c) void {
    _ = format;
    if (!isGpuReady) {
        TraceLog(RL_LOG_WARNING, "GL: GPU is not ready to load data, trying to load before InitWindow()?");
        return;
    }

    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, id);

    var texIsPOT = false;
    if (((width > 0) and ((width & (width - 1)) == 0)) and
        ((height > 0) and ((height & (height - 1)) == 0))) texIsPOT = true;

    if (texIsPOT or RLGL.ExtSupported.texNPOT) {
        gl.glad_glGenerateMipmap.?(gl.GL_TEXTURE_2D);

        const maxDim: f64 = @floatFromInt(if (width > height) width else height);
        mipmaps.* = 1 + @as(c_int, @intFromFloat(floor(log(maxDim) / log(2))));
        TraceLog(RL_LOG_INFO, "TEXTURE: [ID %i] Mipmaps generated automatically, total: %i", id, mipmaps.*);
    } else TraceLog(RL_LOG_WARNING, "TEXTURE: [ID %i] Failed to generate mipmaps", id);

    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, 0);
}

// Read texture pixel data
export fn rlReadTexturePixels(id: c_uint, width: c_int, height: c_int, format: c_int) callconv(.c) ?*anyopaque {
    if (es2) return readTexturePixelsFramebuffer(id, width, height, format);

    var pixels: ?*anyopaque = null;

    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, id);

    gl.glad_glPixelStorei.?(gl.GL_PACK_ALIGNMENT, 1);

    var glInternalFormat: c_uint = undefined;
    var glFormat: c_uint = undefined;
    var glType: c_uint = undefined;
    rlGetGlTextureFormats(format, &glInternalFormat, &glFormat, &glType);
    const size = rlGetPixelDataSize(width, height, format);

    if ((glInternalFormat != 0) and (format < RL_PIXELFORMAT_COMPRESSED_DXT1_RGB)) {
        pixels = calloc(@intCast(size), 1);
        gl.glad_glGetTexImage.?(gl.GL_TEXTURE_2D, 0, glFormat, glType, pixels);
    } else TraceLog(RL_LOG_WARNING, "TEXTURE: [ID %i] Data retrieval not suported for pixel format (%i)", id, format);

    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, 0);

    return pixels;
}

/// rlReadTexturePixels on OpenGL ES, which has no glGetTexImage: attach the texture
/// to a temporary framebuffer and read it back with glReadPixels. As in rlgl.h,
/// this only works for formats the framebuffer can render to (RGBA8 is safe).
fn readTexturePixelsFramebuffer(id: c_uint, width: c_int, height: c_int, format: c_int) ?*anyopaque {
    const fboId = rlLoadFramebuffer();
    gl.glad_glBindFramebuffer.?(gl.GL_FRAMEBUFFER, fboId);
    gl.glad_glBindTexture.?(gl.GL_TEXTURE_2D, 0);

    // Attach our texture to FBO
    gl.glad_glFramebufferTexture2D.?(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, id, 0);

    // We read data as RGBA because FBO texture is configured as RGBA, despite binding another texture format
    const pixels = malloc(@intCast(rlGetPixelDataSize(width, height, format)));

    var glInternalFormat: c_uint = 0;
    var glFormat: c_uint = 0;
    var glType: c_uint = 0;
    rlGetGlTextureFormats(format, &glInternalFormat, &glFormat, &glType);
    gl.glad_glReadPixels.?(0, 0, width, height, glFormat, glType, pixels);

    gl.glad_glBindFramebuffer.?(gl.GL_FRAMEBUFFER, 0);

    // Clean up temporal fbo
    rlUnloadFramebuffer(fboId);

    return pixels;
}

// Copy framebuffer pixel data to internal buffer (software backend only - no-op for GL 3.3)
export fn rlCopyFramebuffer(x: c_int, y: c_int, width: c_int, height: c_int, format: c_int, pixels: ?*anyopaque) callconv(.c) void {
    _ = x;
    _ = y;
    _ = width;
    _ = height;
    _ = format;
    _ = pixels;
}

// Resize internal framebuffer (software backend only - no-op for GL 3.3)
export fn rlResizeFramebuffer(width: c_int, height: c_int) callconv(.c) void {
    _ = width;
    _ = height;
}

// Read screen pixel data (color buffer)
export fn rlReadScreenPixels(width: c_int, height: c_int) callconv(.c) [*c]u8 {
    const w: usize = @intCast(width);
    const h: usize = @intCast(height);
    const imgData: [*c]u8 = @ptrCast(@alignCast(calloc(w * h * 4, @sizeOf(u8))));

    gl.glad_glReadPixels.?(0, 0, width, height, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, imgData);

    // Flip image vertically
    var y: c_int = height - 1;
    while (y >= @divTrunc(height, 2)) : (y -= 1) {
        var x: c_int = 0;
        while (x < width * 4) : (x += 4) {
            const s: usize = @intCast(((height - 1) - y) * width * 4 + x);
            const e: usize = @intCast(y * width * 4 + x);

            const r = imgData[s];
            const g = imgData[s + 1];
            const b = imgData[s + 2];

            imgData[s] = imgData[e];
            imgData[s + 1] = imgData[e + 1];
            imgData[s + 2] = imgData[e + 2];
            imgData[s + 3] = 255;

            imgData[e] = r;
            imgData[e + 1] = g;
            imgData[e + 2] = b;
            imgData[e + 3] = 255;
        }
    }

    return imgData;
}

// Get name string for pixel format
export fn rlGetPixelFormatName(format: c_uint) callconv(.c) [*c]const u8 {
    return switch (format) {
        RL_PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => "GRAYSCALE",
        RL_PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA => "GRAY_ALPHA",
        RL_PIXELFORMAT_UNCOMPRESSED_R5G6B5 => "R5G6B5",
        RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8 => "R8G8B8",
        RL_PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 => "R5G5B5A1",
        RL_PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 => "R4G4B4A4",
        RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => "R8G8B8A8",
        RL_PIXELFORMAT_UNCOMPRESSED_R32 => "R32",
        RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32 => "R32G32B32",
        RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => "R32G32B32A32",
        RL_PIXELFORMAT_UNCOMPRESSED_R16 => "R16",
        RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16 => "R16G16B16",
        RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => "R16G16B16A16",
        RL_PIXELFORMAT_COMPRESSED_DXT1_RGB => "DXT1_RGB",
        RL_PIXELFORMAT_COMPRESSED_DXT1_RGBA => "DXT1_RGBA",
        RL_PIXELFORMAT_COMPRESSED_DXT3_RGBA => "DXT3_RGBA",
        RL_PIXELFORMAT_COMPRESSED_DXT5_RGBA => "DXT5_RGBA",
        RL_PIXELFORMAT_COMPRESSED_ETC1_RGB => "ETC1_RGB",
        RL_PIXELFORMAT_COMPRESSED_ETC2_RGB => "ETC2_RGB",
        RL_PIXELFORMAT_COMPRESSED_ETC2_EAC_RGBA => "ETC2_RGBA",
        RL_PIXELFORMAT_COMPRESSED_PVRT_RGB => "PVRT_RGB",
        RL_PIXELFORMAT_COMPRESSED_PVRT_RGBA => "PVRT_RGBA",
        RL_PIXELFORMAT_COMPRESSED_ASTC_4x4_RGBA => "ASTC_4x4_RGBA",
        RL_PIXELFORMAT_COMPRESSED_ASTC_8x8_RGBA => "ASTC_8x8_RGBA",
        else => "UNKNOWN",
    };
}

// Framebuffer management (fbo)
//-----------------------------------------------------------------------------------------

// Load a framebuffer to be used for rendering
export fn rlLoadFramebuffer() callconv(.c) c_uint {
    var fboId: c_uint = 0;
    if (!isGpuReady) {
        TraceLog(RL_LOG_WARNING, "GL: GPU is not ready to load data, trying to load before InitWindow()?");
        return fboId;
    }

    gl.glad_glGenFramebuffers.?(1, &fboId);
    gl.glad_glBindFramebuffer.?(gl.GL_FRAMEBUFFER, 0);

    return fboId;
}

// Attach color buffer texture to a framebuffer object
export fn rlFramebufferAttach(id: c_uint, texId: c_uint, attachType: c_int, texType: c_int, mipLevel: c_int) callconv(.c) void {
    gl.glad_glBindFramebuffer.?(gl.GL_FRAMEBUFFER, id);

    switch (attachType) {
        RL_ATTACHMENT_COLOR_CHANNEL0...RL_ATTACHMENT_COLOR_CHANNEL7 => {
            const attach: c_uint = gl.GL_COLOR_ATTACHMENT0 + @as(c_uint, @intCast(attachType));
            if (texType == RL_ATTACHMENT_TEXTURE2D) {
                gl.glad_glFramebufferTexture2D.?(gl.GL_FRAMEBUFFER, attach, gl.GL_TEXTURE_2D, texId, mipLevel);
            } else if (texType == RL_ATTACHMENT_RENDERBUFFER) {
                gl.glad_glFramebufferRenderbuffer.?(gl.GL_FRAMEBUFFER, attach, gl.GL_RENDERBUFFER, texId);
            } else if (texType >= RL_ATTACHMENT_CUBEMAP_POSITIVE_X) {
                gl.glad_glFramebufferTexture2D.?(gl.GL_FRAMEBUFFER, attach, gl.GL_TEXTURE_CUBE_MAP_POSITIVE_X + @as(c_uint, @intCast(texType)), texId, mipLevel);
            }
        },
        RL_ATTACHMENT_DEPTH => {
            if (texType == RL_ATTACHMENT_TEXTURE2D) {
                gl.glad_glFramebufferTexture2D.?(gl.GL_FRAMEBUFFER, gl.GL_DEPTH_ATTACHMENT, gl.GL_TEXTURE_2D, texId, mipLevel);
            } else if (texType == RL_ATTACHMENT_RENDERBUFFER) {
                gl.glad_glFramebufferRenderbuffer.?(gl.GL_FRAMEBUFFER, gl.GL_DEPTH_ATTACHMENT, gl.GL_RENDERBUFFER, texId);
            }
        },
        RL_ATTACHMENT_STENCIL => {
            if (texType == RL_ATTACHMENT_TEXTURE2D) {
                gl.glad_glFramebufferTexture2D.?(gl.GL_FRAMEBUFFER, gl.GL_STENCIL_ATTACHMENT, gl.GL_TEXTURE_2D, texId, mipLevel);
            } else if (texType == RL_ATTACHMENT_RENDERBUFFER) {
                gl.glad_glFramebufferRenderbuffer.?(gl.GL_FRAMEBUFFER, gl.GL_STENCIL_ATTACHMENT, gl.GL_RENDERBUFFER, texId);
            }
        },
        else => {},
    }

    gl.glad_glBindFramebuffer.?(gl.GL_FRAMEBUFFER, 0);
}

// Verify render texture is complete
export fn rlFramebufferComplete(id: c_uint) callconv(.c) bool {
    var result = false;

    gl.glad_glBindFramebuffer.?(gl.GL_FRAMEBUFFER, id);

    const status = gl.glad_glCheckFramebufferStatus.?(gl.GL_FRAMEBUFFER);

    if (status != gl.GL_FRAMEBUFFER_COMPLETE) {
        switch (status) {
            gl.GL_FRAMEBUFFER_UNSUPPORTED => TraceLog(RL_LOG_WARNING, "FBO: [ID %i] Framebuffer is unsupported", id),
            gl.GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT => TraceLog(RL_LOG_WARNING, "FBO: [ID %i] Framebuffer has incomplete attachment", id),
            gl.GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT => TraceLog(RL_LOG_WARNING, "FBO: [ID %i] Framebuffer has a missing attachment", id),
            else => if (es2 and status == gl.GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS) {
                TraceLog(RL_LOG_WARNING, "FBO: [ID %i] Framebuffer has incomplete dimensions", id);
            },
        }
    }

    gl.glad_glBindFramebuffer.?(gl.GL_FRAMEBUFFER, 0);

    result = (status == gl.GL_FRAMEBUFFER_COMPLETE);

    return result;
}

// Unload framebuffer from GPU memory
export fn rlUnloadFramebuffer(id: c_uint) callconv(.c) void {
    var idv = id;
    var depthType: c_int = 0;
    gl.glad_glBindFramebuffer.?(gl.GL_FRAMEBUFFER, id);
    gl.glad_glGetFramebufferAttachmentParameteriv.?(gl.GL_FRAMEBUFFER, gl.GL_DEPTH_ATTACHMENT, gl.GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &depthType);

    var depthId: c_int = 0;
    gl.glad_glGetFramebufferAttachmentParameteriv.?(gl.GL_FRAMEBUFFER, gl.GL_DEPTH_ATTACHMENT, gl.GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, &depthId);

    var depthIdU: c_uint = @intCast(depthId);
    if (depthType == @as(c_int, @intCast(gl.GL_RENDERBUFFER))) {
        gl.glad_glDeleteRenderbuffers.?(1, &depthIdU);
    } else if (depthType == @as(c_int, @intCast(gl.GL_TEXTURE))) {
        gl.glad_glDeleteTextures.?(1, &depthIdU);
    }

    gl.glad_glBindFramebuffer.?(gl.GL_FRAMEBUFFER, 0);
    gl.glad_glDeleteFramebuffers.?(1, &idv);

    TraceLog(RL_LOG_INFO, "FBO: [ID %i] Unloaded framebuffer from VRAM (GPU)", id);
}

// Vertex data management
//-----------------------------------------------------------------------------------------

// Load a new attributes buffer
export fn rlLoadVertexBuffer(buffer: ?*const anyopaque, size: c_int, dynamic: bool) callconv(.c) c_uint {
    var id: c_uint = 0;
    if (!isGpuReady) {
        TraceLog(RL_LOG_WARNING, "GL: GPU is not ready to load data, trying to load before InitWindow()?");
        return id;
    }

    gl.glad_glGenBuffers.?(1, &id);
    gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, id);
    gl.glad_glBufferData.?(gl.GL_ARRAY_BUFFER, size, buffer, if (dynamic) gl.GL_DYNAMIC_DRAW else gl.GL_STATIC_DRAW);

    return id;
}

// Load a new attributes element buffer
export fn rlLoadVertexBufferElement(buffer: ?*const anyopaque, size: c_int, dynamic: bool) callconv(.c) c_uint {
    var id: c_uint = 0;
    if (!isGpuReady) {
        TraceLog(RL_LOG_WARNING, "GL: GPU is not ready to load data, trying to load before InitWindow()?");
        return id;
    }

    gl.glad_glGenBuffers.?(1, &id);
    gl.glad_glBindBuffer.?(gl.GL_ELEMENT_ARRAY_BUFFER, id);
    gl.glad_glBufferData.?(gl.GL_ELEMENT_ARRAY_BUFFER, size, buffer, if (dynamic) gl.GL_DYNAMIC_DRAW else gl.GL_STATIC_DRAW);

    return id;
}

// Enable/disable vertex buffer (VBO)
export fn rlEnableVertexBuffer(id: c_uint) callconv(.c) void {
    gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, id);
}
export fn rlDisableVertexBuffer() callconv(.c) void {
    gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, 0);
}
export fn rlEnableVertexBufferElement(id: c_uint) callconv(.c) void {
    gl.glad_glBindBuffer.?(gl.GL_ELEMENT_ARRAY_BUFFER, id);
}
export fn rlDisableVertexBufferElement() callconv(.c) void {
    gl.glad_glBindBuffer.?(gl.GL_ELEMENT_ARRAY_BUFFER, 0);
}

// Update vertex buffer with new data
export fn rlUpdateVertexBuffer(id: c_uint, data: ?*const anyopaque, dataSize: c_int, offset: c_int) callconv(.c) void {
    gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, id);
    gl.glad_glBufferSubData.?(gl.GL_ARRAY_BUFFER, offset, dataSize, data);
}

// Update vertex buffer elements with new data
export fn rlUpdateVertexBufferElements(id: c_uint, data: ?*const anyopaque, dataSize: c_int, offset: c_int) callconv(.c) void {
    gl.glad_glBindBuffer.?(gl.GL_ELEMENT_ARRAY_BUFFER, id);
    gl.glad_glBufferSubData.?(gl.GL_ELEMENT_ARRAY_BUFFER, offset, dataSize, data);
}

// Enable vertex array object (VAO)
export fn rlEnableVertexArray(vaoId: c_uint) callconv(.c) bool {
    var result = false;
    if (RLGL.ExtSupported.vao) {
        gl.glad_glBindVertexArray.?(vaoId);
        result = true;
    }
    return result;
}

// Disable vertex array object (VAO)
export fn rlDisableVertexArray() callconv(.c) void {
    if (RLGL.ExtSupported.vao) gl.glad_glBindVertexArray.?(0);
}

// Enable/disable vertex attribute index
export fn rlEnableVertexAttribute(index: c_uint) callconv(.c) void {
    gl.glad_glEnableVertexAttribArray.?(index);
}
export fn rlDisableVertexAttribute(index: c_uint) callconv(.c) void {
    gl.glad_glDisableVertexAttribArray.?(index);
}

// Draw vertex array
export fn rlDrawVertexArray(offset: c_int, count: c_int) callconv(.c) void {
    gl.glad_glDrawArrays.?(gl.GL_TRIANGLES, offset, count);
}

// Draw vertex array elements
export fn rlDrawVertexArrayElements(offset: c_int, count: c_int, buffer: ?*const anyopaque) callconv(.c) void {
    var bufferPtr: [*c]const u16 = @ptrCast(@alignCast(buffer));
    if (offset > 0) bufferPtr += @intCast(offset);
    gl.glad_glDrawElements.?(gl.GL_TRIANGLES, count, gl.GL_UNSIGNED_SHORT, bufferPtr);
}

// Draw vertex array instanced
export fn rlDrawVertexArrayInstanced(offset: c_int, count: c_int, instances: c_int) callconv(.c) void {
    gl.glad_glDrawArraysInstanced.?(gl.GL_TRIANGLES, offset, count, instances);
}

// Draw vertex array elements instanced
export fn rlDrawVertexArrayElementsInstanced(offset: c_int, count: c_int, buffer: ?*const anyopaque, instances: c_int) callconv(.c) void {
    var bufferPtr: [*c]const u16 = @ptrCast(@alignCast(buffer));
    if (offset > 0) bufferPtr += @intCast(offset);
    gl.glad_glDrawElementsInstanced.?(gl.GL_TRIANGLES, count, gl.GL_UNSIGNED_SHORT, bufferPtr, instances);
}

// Enable vertex state pointer (OpenGL 1.1 only - no-op for GL 3.3)
export fn rlEnableStatePointer(vertexAttribType: c_int, buffer: ?*anyopaque) callconv(.c) void {
    _ = vertexAttribType;
    _ = buffer;
}

// Disable vertex state pointer (OpenGL 1.1 only - no-op for GL 3.3)
export fn rlDisableStatePointer(vertexAttribType: c_int) callconv(.c) void {
    _ = vertexAttribType;
}

// Load vertex array object (VAO)
export fn rlLoadVertexArray() callconv(.c) c_uint {
    var vaoId: c_uint = 0;
    if (!isGpuReady) {
        TraceLog(RL_LOG_WARNING, "GL: GPU is not ready to load data, trying to load before InitWindow()?");
        return vaoId;
    }

    if (RLGL.ExtSupported.vao) gl.glad_glGenVertexArrays.?(1, &vaoId);

    return vaoId;
}

// Set vertex attribute
export fn rlSetVertexAttribute(index: c_uint, compSize: c_int, type_: c_int, normalized: bool, stride: c_int, offset: c_int) callconv(.c) void {
    const offsetNative: usize = @intCast(offset);
    gl.glad_glVertexAttribPointer.?(index, compSize, @intCast(type_), @intFromBool(normalized), stride, @ptrFromInt(offsetNative));
}

// Set vertex attribute divisor
export fn rlSetVertexAttributeDivisor(index: c_uint, divisor: c_int) callconv(.c) void {
    gl.glad_glVertexAttribDivisor.?(index, @intCast(divisor));
}

// Unload vertex array object (VAO)
export fn rlUnloadVertexArray(vaoId: c_uint) callconv(.c) void {
    var v = vaoId;
    if (RLGL.ExtSupported.vao) {
        gl.glad_glBindVertexArray.?(0);
        gl.glad_glDeleteVertexArrays.?(1, &v);
        TraceLog(RL_LOG_INFO, "VAO: [ID %i] Unloaded vertex array data from VRAM (GPU)", vaoId);
    }
}

// Unload vertex buffer (VBO)
export fn rlUnloadVertexBuffer(vboId: c_uint) callconv(.c) void {
    var v = vboId;
    gl.glad_glDeleteBuffers.?(1, &v);
}

// Shaders management
//-----------------------------------------------------------------------------------------------

// Load (compile) shader and return shader id
export fn rlLoadShader(code: [*c]const u8, type_: c_int) callconv(.c) c_uint {
    var shaderId: c_uint = 0;

    shaderId = gl.glad_glCreateShader.?(@intCast(type_));
    var codePtr: [*c]const u8 = code;
    gl.glad_glShaderSource.?(shaderId, 1, &codePtr, null);

    var success: c_int = 0;
    gl.glad_glCompileShader.?(shaderId);
    gl.glad_glGetShaderiv.?(shaderId, gl.GL_COMPILE_STATUS, &success);

    if (success == @as(c_int, @intCast(gl.GL_FALSE))) {
        switch (type_) {
            RL_VERTEX_SHADER => TraceLog(RL_LOG_WARNING, "SHADER: [ID %i] Failed to compile vertex shader code", shaderId),
            RL_FRAGMENT_SHADER => TraceLog(RL_LOG_WARNING, "SHADER: [ID %i] Failed to compile fragment shader code", shaderId),
            RL_COMPUTE_SHADER => if (!es2) TraceLog(RL_LOG_WARNING, "SHADER: Compute shaders not enabled. Define GRAPHICS_API_OPENGL_43", shaderId),
            else => {},
        }

        var maxLength: c_int = 0;
        gl.glad_glGetShaderiv.?(shaderId, gl.GL_INFO_LOG_LENGTH, &maxLength);

        if (maxLength > 0) {
            var length: c_int = 0;
            const logbuf: [*c]u8 = @ptrCast(@alignCast(calloc(@intCast(maxLength), @sizeOf(u8))));
            gl.glad_glGetShaderInfoLog.?(shaderId, maxLength, &length, logbuf);
            TraceLog(RL_LOG_WARNING, "SHADER: [ID %i] Compile error: %s", shaderId, logbuf);
            RL_FREE(logbuf);
        }

        gl.glad_glDeleteShader.?(shaderId);
        shaderId = 0;
    } else {
        switch (type_) {
            RL_VERTEX_SHADER => TraceLog(RL_LOG_INFO, "SHADER: [ID %i] Vertex shader compiled successfully", shaderId),
            RL_FRAGMENT_SHADER => TraceLog(RL_LOG_INFO, "SHADER: [ID %i] Fragment shader compiled successfully", shaderId),
            RL_COMPUTE_SHADER => if (!es2) TraceLog(RL_LOG_WARNING, "SHADER: Compute shaders not enabled. Define GRAPHICS_API_OPENGL_43", shaderId),
            else => {},
        }
    }

    return shaderId;
}

// Load shader program from code strings
export fn rlLoadShaderProgram(vsCode: [*c]const u8, fsCode: [*c]const u8) callconv(.c) c_uint {
    var id: c_uint = 0;
    if (!isGpuReady) {
        TraceLog(RL_LOG_WARNING, "GL: GPU is not ready to load data, trying to load before InitWindow()?");
        return id;
    }

    var vertexShaderId: c_uint = 0;
    var fragmentShaderId: c_uint = 0;

    if (vsCode != null) vertexShaderId = rlLoadShader(vsCode, RL_VERTEX_SHADER) else vertexShaderId = RLGL.State.defaultVShaderId;
    if (fsCode != null) fragmentShaderId = rlLoadShader(fsCode, RL_FRAGMENT_SHADER) else fragmentShaderId = RLGL.State.defaultFShaderId;

    if ((vertexShaderId == RLGL.State.defaultVShaderId) and (fragmentShaderId == RLGL.State.defaultFShaderId)) {
        id = RLGL.State.defaultShaderId;
    } else if ((vertexShaderId > 0) and (fragmentShaderId > 0)) {
        id = rlLoadShaderProgramEx(vertexShaderId, fragmentShaderId);

        if (vertexShaderId != RLGL.State.defaultVShaderId) {
            if (id > 0) gl.glad_glDetachShader.?(id, vertexShaderId);
            gl.glad_glDeleteShader.?(vertexShaderId);
        }
        if (fragmentShaderId != RLGL.State.defaultFShaderId) {
            if (id > 0) gl.glad_glDetachShader.?(id, fragmentShaderId);
            gl.glad_glDeleteShader.?(fragmentShaderId);
        }

        if (id == 0) {
            TraceLog(RL_LOG_WARNING, "SHADER: Failed to load custom shader code, using default shader");
            id = RLGL.State.defaultShaderId;
        }
    }

    return id;
}

// Load shader program from already loaded shader ids
export fn rlLoadShaderProgramEx(vsId: c_uint, fsId: c_uint) callconv(.c) c_uint {
    var programId: c_uint = 0;
    if (!isGpuReady) {
        TraceLog(RL_LOG_WARNING, "GL: GPU is not ready to load data, trying to load before InitWindow()?");
        return programId;
    }

    var success: c_int = 0;
    programId = gl.glad_glCreateProgram.?();

    gl.glad_glAttachShader.?(programId, vsId);
    gl.glad_glAttachShader.?(programId, fsId);

    gl.glad_glBindAttribLocation.?(programId, RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION, RL_DEFAULT_SHADER_ATTRIB_NAME_POSITION);
    gl.glad_glBindAttribLocation.?(programId, RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD, RL_DEFAULT_SHADER_ATTRIB_NAME_TEXCOORD);
    gl.glad_glBindAttribLocation.?(programId, RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL, RL_DEFAULT_SHADER_ATTRIB_NAME_NORMAL);
    gl.glad_glBindAttribLocation.?(programId, RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR, RL_DEFAULT_SHADER_ATTRIB_NAME_COLOR);
    gl.glad_glBindAttribLocation.?(programId, RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT, RL_DEFAULT_SHADER_ATTRIB_NAME_TANGENT);
    gl.glad_glBindAttribLocation.?(programId, RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2, RL_DEFAULT_SHADER_ATTRIB_NAME_TEXCOORD2);
    gl.glad_glBindAttribLocation.?(programId, RL_DEFAULT_SHADER_ATTRIB_LOCATION_INSTANCETRANSFORM, RL_DEFAULT_SHADER_ATTRIB_NAME_INSTANCETRANSFORM);
    gl.glad_glBindAttribLocation.?(programId, RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES, RL_DEFAULT_SHADER_ATTRIB_NAME_BONEINDICES);
    gl.glad_glBindAttribLocation.?(programId, RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS, RL_DEFAULT_SHADER_ATTRIB_NAME_BONEWEIGHTS);

    gl.glad_glLinkProgram.?(programId);

    gl.glad_glGetProgramiv.?(programId, gl.GL_LINK_STATUS, &success);

    if (success == @as(c_int, @intCast(gl.GL_FALSE))) {
        TraceLog(RL_LOG_WARNING, "SHADER: [ID %i] Failed to link shader program", programId);

        var maxLength: c_int = 0;
        gl.glad_glGetProgramiv.?(programId, gl.GL_INFO_LOG_LENGTH, &maxLength);

        if (maxLength > 0) {
            var length: c_int = 0;
            const logbuf: [*c]u8 = @ptrCast(@alignCast(calloc(@intCast(maxLength), @sizeOf(u8))));
            gl.glad_glGetProgramInfoLog.?(programId, maxLength, &length, logbuf);
            TraceLog(RL_LOG_WARNING, "SHADER: [ID %i] Link error: %s", programId, logbuf);
            RL_FREE(logbuf);
        }

        gl.glad_glDeleteProgram.?(programId);
        programId = 0;
    } else {
        TraceLog(RL_LOG_INFO, "SHADER: [ID %i] Program shader loaded successfully", programId);
    }

    return programId;
}

// Load compute shader program (OpenGL 4.3 only - not supported here)
export fn rlLoadShaderProgramCompute(csId: c_uint) callconv(.c) c_uint {
    _ = csId;
    TraceLog(RL_LOG_WARNING, "SHADER: Compute shaders not supported, enable GRAPHICS_API_OPENGL_43");
    return 0;
}

// Delete shader
export fn rlUnloadShader(id: c_uint) callconv(.c) void {
    gl.glad_glDeleteShader.?(id);
    TraceLog(RL_LOG_INFO, "SHADER: [ID %i] Unloaded shader data from VRAM (GPU)", id);
}

// Unload shader program
export fn rlUnloadShaderProgram(id: c_uint) callconv(.c) void {
    gl.glad_glDeleteProgram.?(id);
    TraceLog(RL_LOG_INFO, "SHADER: [ID %i] Unloaded shader program data from VRAM (GPU)", id);
}

// Get shader location uniform
export fn rlGetLocationUniform(id: c_uint, uniformName: [*c]const u8) callconv(.c) c_int {
    return gl.glad_glGetUniformLocation.?(id, uniformName);
}

// Get shader location attribute
export fn rlGetLocationAttrib(id: c_uint, attribName: [*c]const u8) callconv(.c) c_int {
    return gl.glad_glGetAttribLocation.?(id, attribName);
}

// Set shader value uniform
export fn rlSetUniform(locIndex: c_int, value: ?*const anyopaque, uniformType: c_int, count: c_int) callconv(.c) void {
    switch (uniformType) {
        RL_SHADER_UNIFORM_FLOAT => gl.glad_glUniform1fv.?(locIndex, count, @ptrCast(@alignCast(value))),
        RL_SHADER_UNIFORM_VEC2 => gl.glad_glUniform2fv.?(locIndex, count, @ptrCast(@alignCast(value))),
        RL_SHADER_UNIFORM_VEC3 => gl.glad_glUniform3fv.?(locIndex, count, @ptrCast(@alignCast(value))),
        RL_SHADER_UNIFORM_VEC4 => gl.glad_glUniform4fv.?(locIndex, count, @ptrCast(@alignCast(value))),
        RL_SHADER_UNIFORM_INT => gl.glad_glUniform1iv.?(locIndex, count, @ptrCast(@alignCast(value))),
        RL_SHADER_UNIFORM_IVEC2 => gl.glad_glUniform2iv.?(locIndex, count, @ptrCast(@alignCast(value))),
        RL_SHADER_UNIFORM_IVEC3 => gl.glad_glUniform3iv.?(locIndex, count, @ptrCast(@alignCast(value))),
        RL_SHADER_UNIFORM_IVEC4 => gl.glad_glUniform4iv.?(locIndex, count, @ptrCast(@alignCast(value))),
        // rlgl.h sets unsigned uniforms on GL 3.3 only; on ES they fall to the warning.
        RL_SHADER_UNIFORM_UINT, RL_SHADER_UNIFORM_UIVEC2, RL_SHADER_UNIFORM_UIVEC3, RL_SHADER_UNIFORM_UIVEC4 => if (es2) {
            TraceLog(RL_LOG_WARNING, "SHADER: Failed to set uniform value, data type not recognized");
        } else switch (uniformType) {
            RL_SHADER_UNIFORM_UINT => gl.glad_glUniform1uiv.?(locIndex, count, @ptrCast(@alignCast(value))),
            RL_SHADER_UNIFORM_UIVEC2 => gl.glad_glUniform2uiv.?(locIndex, count, @ptrCast(@alignCast(value))),
            RL_SHADER_UNIFORM_UIVEC3 => gl.glad_glUniform3uiv.?(locIndex, count, @ptrCast(@alignCast(value))),
            else => gl.glad_glUniform4uiv.?(locIndex, count, @ptrCast(@alignCast(value))),
        },
        RL_SHADER_UNIFORM_SAMPLER2D => gl.glad_glUniform1iv.?(locIndex, count, @ptrCast(@alignCast(value))),
        else => TraceLog(RL_LOG_WARNING, "SHADER: Failed to set uniform value, data type not recognized"),
    }
}

// Set shader value attribute
export fn rlSetVertexAttributeDefault(locIndex: c_int, value: ?*const anyopaque, attribType: c_int, count: c_int) callconv(.c) void {
    switch (attribType) {
        RL_SHADER_ATTRIB_FLOAT => if (count == 1) gl.glad_glVertexAttrib1fv.?(@intCast(locIndex), @ptrCast(@alignCast(value))),
        RL_SHADER_ATTRIB_VEC2 => if (count == 2) gl.glad_glVertexAttrib2fv.?(@intCast(locIndex), @ptrCast(@alignCast(value))),
        RL_SHADER_ATTRIB_VEC3 => if (count == 3) gl.glad_glVertexAttrib3fv.?(@intCast(locIndex), @ptrCast(@alignCast(value))),
        RL_SHADER_ATTRIB_VEC4 => if (count == 4) gl.glad_glVertexAttrib4fv.?(@intCast(locIndex), @ptrCast(@alignCast(value))),
        else => TraceLog(RL_LOG_WARNING, "SHADER: Failed to set attrib default value, data type not recognized"),
    }
}

// Set shader value uniform matrix
export fn rlSetUniformMatrix(locIndex: c_int, mat: Matrix) callconv(.c) void {
    var f = rlMatrixToFloatV(mat);
    gl.glad_glUniformMatrix4fv.?(locIndex, 1, @intCast(gl.GL_FALSE), &f.v);
}

// Set shader value uniform matrices
export fn rlSetUniformMatrices(locIndex: c_int, matrices: [*c]const Matrix, count: c_int) callconv(.c) void {
    // WARNING: WebGL does not support Matrix transpose ("true" parameter)
    const transpose = if (es2) gl.GL_FALSE else gl.GL_TRUE;
    gl.glad_glUniformMatrix4fv.?(locIndex, count, @intCast(transpose), @ptrCast(@alignCast(matrices)));
}

// Set shader value uniform sampler
export fn rlSetUniformSampler(locIndex: c_int, textureId: c_uint) callconv(.c) void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(RL_DEFAULT_BATCH_MAX_TEXTURE_UNITS))) : (i += 1) {
        if (RLGL.State.activeTextureId[i] == textureId) {
            gl.glad_glUniform1i.?(locIndex, @intCast(1 + i));
            return;
        }
    }

    i = 0;
    while (i < @as(usize, @intCast(RL_DEFAULT_BATCH_MAX_TEXTURE_UNITS))) : (i += 1) {
        if (RLGL.State.activeTextureId[i] == 0) {
            gl.glad_glUniform1i.?(locIndex, @intCast(1 + i));
            RLGL.State.activeTextureId[i] = textureId;
            break;
        }
    }
}

// Set shader currently active (id and locations)
export fn rlSetShader(id: c_uint, locs: [*c]c_int) callconv(.c) void {
    if (RLGL.State.currentShaderId != id) {
        rlDrawRenderBatch(RLGL.currentBatch);
        RLGL.State.currentShaderId = id;
        RLGL.State.currentShaderLocs = locs;
    }
}

// Compute shader management (OpenGL 4.3 only - not supported here)
export fn rlComputeShaderDispatch(groupX: c_uint, groupY: c_uint, groupZ: c_uint) callconv(.c) void {
    _ = groupX;
    _ = groupY;
    _ = groupZ;
}

// Shader buffer storage object management (ssbo) - OpenGL 4.3 only
export fn rlLoadShaderBuffer(size: c_uint, data: ?*const anyopaque, usageHint: c_int) callconv(.c) c_uint {
    _ = size;
    _ = data;
    _ = usageHint;
    TraceLog(RL_LOG_WARNING, "SSBO: SSBO not enabled. Define GRAPHICS_API_OPENGL_43");
    return 0;
}
export fn rlUnloadShaderBuffer(ssboId: c_uint) callconv(.c) void {
    _ = ssboId;
    TraceLog(RL_LOG_WARNING, "SSBO: SSBO not enabled. Define GRAPHICS_API_OPENGL_43");
}
export fn rlUpdateShaderBuffer(id: c_uint, data: ?*const anyopaque, dataSize: c_uint, offset: c_uint) callconv(.c) void {
    _ = id;
    _ = data;
    _ = dataSize;
    _ = offset;
}
export fn rlGetShaderBufferSize(id: c_uint) callconv(.c) c_uint {
    _ = id;
    return 0;
}
export fn rlReadShaderBuffer(id: c_uint, dest: ?*anyopaque, count: c_uint, offset: c_uint) callconv(.c) void {
    _ = id;
    _ = dest;
    _ = count;
    _ = offset;
}
export fn rlBindShaderBuffer(id: c_uint, index: c_uint) callconv(.c) void {
    _ = id;
    _ = index;
}
export fn rlCopyShaderBuffer(destId: c_uint, srcId: c_uint, destOffset: c_uint, srcOffset: c_uint, count: c_uint) callconv(.c) void {
    _ = destId;
    _ = srcId;
    _ = destOffset;
    _ = srcOffset;
    _ = count;
}

// Bind image texture (OpenGL 4.3 only - not supported here)
export fn rlBindImageTexture(id: c_uint, index: c_uint, format: c_int, readonly: bool) callconv(.c) void {
    _ = id;
    _ = index;
    _ = format;
    _ = readonly;
    TraceLog(RL_LOG_WARNING, "TEXTURE: Image texture binding not enabled. Define GRAPHICS_API_OPENGL_43");
}

// Matrix state management
//-----------------------------------------------------------------------------------------

export fn rlGetMatrixModelview() callconv(.c) Matrix {
    return RLGL.State.modelview;
}
export fn rlGetMatrixProjection() callconv(.c) Matrix {
    return RLGL.State.projection;
}
export fn rlGetMatrixTransform() callconv(.c) Matrix {
    return RLGL.State.transform;
}
export fn rlGetMatrixProjectionStereo(eye: c_int) callconv(.c) Matrix {
    return RLGL.State.projectionStereo[@intCast(eye)];
}
export fn rlGetMatrixViewOffsetStereo(eye: c_int) callconv(.c) Matrix {
    return RLGL.State.viewOffsetStereo[@intCast(eye)];
}
export fn rlSetMatrixModelview(view: Matrix) callconv(.c) void {
    RLGL.State.modelview = view;
}
export fn rlSetMatrixProjection(projection: Matrix) callconv(.c) void {
    RLGL.State.projection = projection;
}
export fn rlSetMatrixProjectionStereo(right: Matrix, left: Matrix) callconv(.c) void {
    RLGL.State.projectionStereo[0] = right;
    RLGL.State.projectionStereo[1] = left;
}
export fn rlSetMatrixViewOffsetStereo(right: Matrix, left: Matrix) callconv(.c) void {
    RLGL.State.viewOffsetStereo[0] = right;
    RLGL.State.viewOffsetStereo[1] = left;
}

// Load and draw a quad in NDC
export fn rlLoadDrawQuad() callconv(.c) void {
    var quadVAO: c_uint = 0;
    var quadVBO: c_uint = 0;

    const vertices = [_]f32{
        -1.0, 1.0,  0.0, 0.0, 1.0,
        -1.0, -1.0, 0.0, 0.0, 0.0,
        1.0,  1.0,  0.0, 1.0, 1.0,
        1.0,  -1.0, 0.0, 1.0, 0.0,
    };

    gl.glad_glGenVertexArrays.?(1, &quadVAO);
    gl.glad_glBindVertexArray.?(quadVAO);

    gl.glad_glGenBuffers.?(1, &quadVBO);
    gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, quadVBO);
    gl.glad_glBufferData.?(gl.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.GL_STATIC_DRAW);

    gl.glad_glEnableVertexAttribArray.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION);
    gl.glad_glVertexAttribPointer.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION, 3, gl.GL_FLOAT, @intCast(gl.GL_FALSE), 5 * @sizeOf(f32), @ptrFromInt(0));
    gl.glad_glEnableVertexAttribArray.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD);
    gl.glad_glVertexAttribPointer.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD, 2, gl.GL_FLOAT, @intCast(gl.GL_FALSE), 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));

    gl.glad_glBindVertexArray.?(quadVAO);
    gl.glad_glDrawArrays.?(gl.GL_TRIANGLE_STRIP, 0, 4);
    gl.glad_glBindVertexArray.?(0);

    gl.glad_glDeleteBuffers.?(1, &quadVBO);
    gl.glad_glDeleteVertexArrays.?(1, &quadVAO);
}

// Load and draw a cube in NDC
export fn rlLoadDrawCube() callconv(.c) void {
    var cubeVAO: c_uint = 0;
    var cubeVBO: c_uint = 0;

    const vertices = [_]f32{
        -1.0, -1.0, -1.0, 0.0,  0.0,  -1.0, 0.0, 0.0,
        1.0,  1.0,  -1.0, 0.0,  0.0,  -1.0, 1.0, 1.0,
        1.0,  -1.0, -1.0, 0.0,  0.0,  -1.0, 1.0, 0.0,
        1.0,  1.0,  -1.0, 0.0,  0.0,  -1.0, 1.0, 1.0,
        -1.0, -1.0, -1.0, 0.0,  0.0,  -1.0, 0.0, 0.0,
        -1.0, 1.0,  -1.0, 0.0,  0.0,  -1.0, 0.0, 1.0,
        -1.0, -1.0, 1.0,  0.0,  0.0,  1.0,  0.0, 0.0,
        1.0,  -1.0, 1.0,  0.0,  0.0,  1.0,  1.0, 0.0,
        1.0,  1.0,  1.0,  0.0,  0.0,  1.0,  1.0, 1.0,
        1.0,  1.0,  1.0,  0.0,  0.0,  1.0,  1.0, 1.0,
        -1.0, 1.0,  1.0,  0.0,  0.0,  1.0,  0.0, 1.0,
        -1.0, -1.0, 1.0,  0.0,  0.0,  1.0,  0.0, 0.0,
        -1.0, 1.0,  1.0,  -1.0, 0.0,  0.0,  1.0, 0.0,
        -1.0, 1.0,  -1.0, -1.0, 0.0,  0.0,  1.0, 1.0,
        -1.0, -1.0, -1.0, -1.0, 0.0,  0.0,  0.0, 1.0,
        -1.0, -1.0, -1.0, -1.0, 0.0,  0.0,  0.0, 1.0,
        -1.0, -1.0, 1.0,  -1.0, 0.0,  0.0,  0.0, 0.0,
        -1.0, 1.0,  1.0,  -1.0, 0.0,  0.0,  1.0, 0.0,
        1.0,  1.0,  1.0,  1.0,  0.0,  0.0,  1.0, 0.0,
        1.0,  -1.0, -1.0, 1.0,  0.0,  0.0,  0.0, 1.0,
        1.0,  1.0,  -1.0, 1.0,  0.0,  0.0,  1.0, 1.0,
        1.0,  -1.0, -1.0, 1.0,  0.0,  0.0,  0.0, 1.0,
        1.0,  1.0,  1.0,  1.0,  0.0,  0.0,  1.0, 0.0,
        1.0,  -1.0, 1.0,  1.0,  0.0,  0.0,  0.0, 0.0,
        -1.0, -1.0, -1.0, 0.0,  -1.0, 0.0,  0.0, 1.0,
        1.0,  -1.0, -1.0, 0.0,  -1.0, 0.0,  1.0, 1.0,
        1.0,  -1.0, 1.0,  0.0,  -1.0, 0.0,  1.0, 0.0,
        1.0,  -1.0, 1.0,  0.0,  -1.0, 0.0,  1.0, 0.0,
        -1.0, -1.0, 1.0,  0.0,  -1.0, 0.0,  0.0, 0.0,
        -1.0, -1.0, -1.0, 0.0,  -1.0, 0.0,  0.0, 1.0,
        -1.0, 1.0,  -1.0, 0.0,  1.0,  0.0,  0.0, 1.0,
        1.0,  1.0,  1.0,  0.0,  1.0,  0.0,  1.0, 0.0,
        1.0,  1.0,  -1.0, 0.0,  1.0,  0.0,  1.0, 1.0,
        1.0,  1.0,  1.0,  0.0,  1.0,  0.0,  1.0, 0.0,
        -1.0, 1.0,  -1.0, 0.0,  1.0,  0.0,  0.0, 1.0,
        -1.0, 1.0,  1.0,  0.0,  1.0,  0.0,  0.0, 0.0,
    };

    gl.glad_glGenVertexArrays.?(1, &cubeVAO);
    gl.glad_glBindVertexArray.?(cubeVAO);

    gl.glad_glGenBuffers.?(1, &cubeVBO);
    gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, cubeVBO);
    gl.glad_glBufferData.?(gl.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.GL_STATIC_DRAW);

    gl.glad_glBindVertexArray.?(cubeVAO);
    gl.glad_glEnableVertexAttribArray.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION);
    gl.glad_glVertexAttribPointer.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION, 3, gl.GL_FLOAT, @intCast(gl.GL_FALSE), 8 * @sizeOf(f32), @ptrFromInt(0));
    gl.glad_glEnableVertexAttribArray.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL);
    gl.glad_glVertexAttribPointer.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL, 3, gl.GL_FLOAT, @intCast(gl.GL_FALSE), 8 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    gl.glad_glEnableVertexAttribArray.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD);
    gl.glad_glVertexAttribPointer.?(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD, 2, gl.GL_FLOAT, @intCast(gl.GL_FALSE), 8 * @sizeOf(f32), @ptrFromInt(6 * @sizeOf(f32)));
    gl.glad_glBindBuffer.?(gl.GL_ARRAY_BUFFER, 0);
    gl.glad_glBindVertexArray.?(0);

    gl.glad_glBindVertexArray.?(cubeVAO);
    gl.glad_glDrawArrays.?(gl.GL_TRIANGLES, 0, 36);
    gl.glad_glBindVertexArray.?(0);

    gl.glad_glDeleteBuffers.?(1, &cubeVBO);
    gl.glad_glDeleteVertexArrays.?(1, &cubeVAO);
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Internal helpers (file-private)
//----------------------------------------------------------------------------------

// Default shaders: GLSL 330 on GL 3.3, GLSL 300 es on ES3. Only the header differs.
const defaultVShaderHeader = switch (graphics_api) {
    .opengl_33 => "#version 330                       \n",
    // Precision highp is mandatory in vertex shaders, mediump may run as fp16 and misplace vertices
    .opengl_es3 => "#version 300 es                    \n" ++
        "precision highp float;             \n",
};
const defaultFShaderHeader = switch (graphics_api) {
    .opengl_33 => "#version 330       \n",
    .opengl_es3 => "#version 300 es                    \n" ++
        "#ifdef GL_FRAGMENT_PRECISION_HIGH  \n" ++
        "precision highp float;             \n" ++
        "#else                              \n" ++
        "precision mediump float;           \n" ++
        "#endif                             \n",
};

// Default vertex shader code
const defaultVShaderCode =
    defaultVShaderHeader ++
    "in vec3 vertexPosition;            \n" ++
    "in vec2 vertexTexCoord;            \n" ++
    "in vec4 vertexColor;               \n" ++
    "out vec2 fragTexCoord;             \n" ++
    "out vec4 fragColor;                \n" ++
    "uniform mat4 mvp;                  \n" ++
    "void main()                        \n" ++
    "{                                  \n" ++
    "    fragTexCoord = vertexTexCoord; \n" ++
    "    fragColor = vertexColor;       \n" ++
    "    gl_Position = mvp*vec4(vertexPosition, 1.0); \n" ++
    "}                                  \n";

// Default fragment shader code
const defaultFShaderCode =
    defaultFShaderHeader ++
    "in vec2 fragTexCoord;              \n" ++
    "in vec4 fragColor;                 \n" ++
    "out vec4 finalColor;               \n" ++
    "uniform sampler2D texture0;        \n" ++
    "uniform vec4 colDiffuse;           \n" ++
    "void main()                        \n" ++
    "{                                  \n" ++
    "    vec4 texelColor = texture(texture0, fragTexCoord);   \n" ++
    "    finalColor = texelColor*colDiffuse*fragColor;        \n" ++
    "}                                  \n";

// Load default shader (just vertex positioning and texture coloring)
fn rlLoadShaderDefault() void {
    RLGL.State.defaultShaderLocs = @ptrCast(@alignCast(calloc(@intCast(RL_MAX_SHADER_LOCATIONS), @sizeOf(c_int))));

    var i: usize = 0;
    while (i < @as(usize, @intCast(RL_MAX_SHADER_LOCATIONS))) : (i += 1) RLGL.State.defaultShaderLocs[i] = -1;

    RLGL.State.defaultVShaderId = rlLoadShader(defaultVShaderCode, RL_VERTEX_SHADER);
    RLGL.State.defaultFShaderId = rlLoadShader(defaultFShaderCode, RL_FRAGMENT_SHADER);

    RLGL.State.defaultShaderId = rlLoadShaderProgramEx(RLGL.State.defaultVShaderId, RLGL.State.defaultFShaderId);

    if (RLGL.State.defaultShaderId > 0) {
        TraceLog(RL_LOG_INFO, "SHADER: [ID %i] Default shader loaded successfully", RLGL.State.defaultShaderId);

        RLGL.State.defaultShaderLocs[RL_SHADER_LOC_VERTEX_POSITION] = gl.glad_glGetAttribLocation.?(RLGL.State.defaultShaderId, RL_DEFAULT_SHADER_ATTRIB_NAME_POSITION);
        RLGL.State.defaultShaderLocs[RL_SHADER_LOC_VERTEX_TEXCOORD01] = gl.glad_glGetAttribLocation.?(RLGL.State.defaultShaderId, RL_DEFAULT_SHADER_ATTRIB_NAME_TEXCOORD);
        RLGL.State.defaultShaderLocs[RL_SHADER_LOC_VERTEX_COLOR] = gl.glad_glGetAttribLocation.?(RLGL.State.defaultShaderId, RL_DEFAULT_SHADER_ATTRIB_NAME_COLOR);

        RLGL.State.defaultShaderLocs[RL_SHADER_LOC_MATRIX_MVP] = gl.glad_glGetUniformLocation.?(RLGL.State.defaultShaderId, RL_DEFAULT_SHADER_UNIFORM_NAME_MVP);
        RLGL.State.defaultShaderLocs[RL_SHADER_LOC_COLOR_DIFFUSE] = gl.glad_glGetUniformLocation.?(RLGL.State.defaultShaderId, RL_DEFAULT_SHADER_UNIFORM_NAME_COLOR);
        RLGL.State.defaultShaderLocs[RL_SHADER_LOC_MAP_DIFFUSE] = gl.glad_glGetUniformLocation.?(RLGL.State.defaultShaderId, RL_DEFAULT_SHADER_SAMPLER2D_NAME_TEXTURE0);
    } else TraceLog(RL_LOG_WARNING, "SHADER: [ID %i] Failed to load default shader", RLGL.State.defaultShaderId);
}

// Unload default shader
fn rlUnloadShaderDefault() void {
    gl.glad_glUseProgram.?(0);

    gl.glad_glDetachShader.?(RLGL.State.defaultShaderId, RLGL.State.defaultVShaderId);
    gl.glad_glDetachShader.?(RLGL.State.defaultShaderId, RLGL.State.defaultFShaderId);
    gl.glad_glDeleteShader.?(RLGL.State.defaultVShaderId);
    gl.glad_glDeleteShader.?(RLGL.State.defaultFShaderId);

    gl.glad_glDeleteProgram.?(RLGL.State.defaultShaderId);

    RL_FREE(RLGL.State.defaultShaderLocs);

    TraceLog(RL_LOG_INFO, "SHADER: [ID %i] Default shader unloaded successfully", RLGL.State.defaultShaderId);
}

// Get pixel data size in bytes (image or texture)
fn rlGetPixelDataSize(width: c_int, height: c_int, format: c_int) c_int {
    var dataSize: c_int = 0;
    var bpp: c_int = 0;

    if (width <= 0 or height <= 0) return dataSize;

    switch (format) {
        RL_PIXELFORMAT_UNCOMPRESSED_GRAYSCALE => bpp = 8,
        RL_PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA,
        RL_PIXELFORMAT_UNCOMPRESSED_R5G6B5,
        RL_PIXELFORMAT_UNCOMPRESSED_R5G5B5A1,
        RL_PIXELFORMAT_UNCOMPRESSED_R4G4B4A4,
        => bpp = 16,
        RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 => bpp = 32,
        RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8 => bpp = 24,
        RL_PIXELFORMAT_UNCOMPRESSED_R32 => bpp = 32,
        RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32 => bpp = 32 * 3,
        RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 => bpp = 32 * 4,
        RL_PIXELFORMAT_UNCOMPRESSED_R16 => bpp = 16,
        RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16 => bpp = 16 * 3,
        RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 => bpp = 16 * 4,
        RL_PIXELFORMAT_COMPRESSED_DXT1_RGB,
        RL_PIXELFORMAT_COMPRESSED_DXT1_RGBA,
        RL_PIXELFORMAT_COMPRESSED_ETC1_RGB,
        RL_PIXELFORMAT_COMPRESSED_ETC2_RGB,
        RL_PIXELFORMAT_COMPRESSED_PVRT_RGB,
        RL_PIXELFORMAT_COMPRESSED_PVRT_RGBA,
        => {
            dataSize = compressedDataSize(width, height, 8);
        },
        RL_PIXELFORMAT_COMPRESSED_DXT3_RGBA,
        RL_PIXELFORMAT_COMPRESSED_DXT5_RGBA,
        RL_PIXELFORMAT_COMPRESSED_ETC2_EAC_RGBA,
        RL_PIXELFORMAT_COMPRESSED_ASTC_4x4_RGBA,
        => {
            dataSize = compressedDataSize(width, height, 16);
        },
        RL_PIXELFORMAT_COMPRESSED_ASTC_8x8_RGBA => {
            dataSize = compressedDataSize(width, height, 4);
        },
        else => {},
    }

    if ((format >= RL_PIXELFORMAT_UNCOMPRESSED_GRAYSCALE) and
        (format <= RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16A16))
    {
        const dataSizeBytes = (@as(u64, @intCast(width)) * @as(u64, @intCast(height)) * @as(u64, @intCast(bpp))) >> 3; // Get size in bytes (dividing by 8)
        if (dataSizeBytes < std.math.maxInt(c_int)) {
            dataSize = @intCast(dataSizeBytes);
        } else TraceLog(RL_LOG_WARNING, "Requested image size is larger than 2GB, it can not be allocated");
    }

    return dataSize;
}

/// Size in bytes of a block-compressed image (4x4 pixel blocks), or 0 when it
/// does not fit in a c_int. Expects positive dimensions.
fn compressedDataSize(width: c_int, height: c_int, bytesPerBlock: u64) c_int {
    const blockWidth: u64 = @intCast(@divTrunc(width + 3, 4));
    const blockHeight: u64 = @intCast(@divTrunc(height + 3, 4));
    const dataSizeBytes = blockWidth * blockHeight * bytesPerBlock;
    return if (dataSizeBytes < std.math.maxInt(c_int)) @intCast(dataSizeBytes) else 0;
}

// Auxiliar math functions
//-------------------------------------------------------------------------------
const rl_float16 = struct { v: [16]f32 };

fn rlMatrixIdentity() Matrix {
    var matIdentity = std.mem.zeroes(Matrix);
    matIdentity.m0 = 1.0;
    matIdentity.m5 = 1.0;
    matIdentity.m10 = 1.0;
    matIdentity.m15 = 1.0;
    return matIdentity;
}

fn rlMatrixToFloatV(mat: Matrix) rl_float16 {
    var result: rl_float16 = .{ .v = undefined };
    result.v[0] = mat.m0;
    result.v[1] = mat.m1;
    result.v[2] = mat.m2;
    result.v[3] = mat.m3;
    result.v[4] = mat.m4;
    result.v[5] = mat.m5;
    result.v[6] = mat.m6;
    result.v[7] = mat.m7;
    result.v[8] = mat.m8;
    result.v[9] = mat.m9;
    result.v[10] = mat.m10;
    result.v[11] = mat.m11;
    result.v[12] = mat.m12;
    result.v[13] = mat.m13;
    result.v[14] = mat.m14;
    result.v[15] = mat.m15;
    return result;
}

fn rlMatrixMultiply(left: Matrix, right: Matrix) Matrix {
    var result = std.mem.zeroes(Matrix);

    result.m0 = left.m0 * right.m0 + left.m1 * right.m4 + left.m2 * right.m8 + left.m3 * right.m12;
    result.m1 = left.m0 * right.m1 + left.m1 * right.m5 + left.m2 * right.m9 + left.m3 * right.m13;
    result.m2 = left.m0 * right.m2 + left.m1 * right.m6 + left.m2 * right.m10 + left.m3 * right.m14;
    result.m3 = left.m0 * right.m3 + left.m1 * right.m7 + left.m2 * right.m11 + left.m3 * right.m15;
    result.m4 = left.m4 * right.m0 + left.m5 * right.m4 + left.m6 * right.m8 + left.m7 * right.m12;
    result.m5 = left.m4 * right.m1 + left.m5 * right.m5 + left.m6 * right.m9 + left.m7 * right.m13;
    result.m6 = left.m4 * right.m2 + left.m5 * right.m6 + left.m6 * right.m10 + left.m7 * right.m14;
    result.m7 = left.m4 * right.m3 + left.m5 * right.m7 + left.m6 * right.m11 + left.m7 * right.m15;
    result.m8 = left.m8 * right.m0 + left.m9 * right.m4 + left.m10 * right.m8 + left.m11 * right.m12;
    result.m9 = left.m8 * right.m1 + left.m9 * right.m5 + left.m10 * right.m9 + left.m11 * right.m13;
    result.m10 = left.m8 * right.m2 + left.m9 * right.m6 + left.m10 * right.m10 + left.m11 * right.m14;
    result.m11 = left.m8 * right.m3 + left.m9 * right.m7 + left.m10 * right.m11 + left.m11 * right.m15;
    result.m12 = left.m12 * right.m0 + left.m13 * right.m4 + left.m14 * right.m8 + left.m15 * right.m12;
    result.m13 = left.m12 * right.m1 + left.m13 * right.m5 + left.m14 * right.m9 + left.m15 * right.m13;
    result.m14 = left.m12 * right.m2 + left.m13 * right.m6 + left.m14 * right.m10 + left.m15 * right.m14;
    result.m15 = left.m12 * right.m3 + left.m13 * right.m7 + left.m14 * right.m11 + left.m15 * right.m15;

    return result;
}

fn rlMatrixTranspose(mat: Matrix) Matrix {
    var result = std.mem.zeroes(Matrix);
    result.m0 = mat.m0;
    result.m1 = mat.m4;
    result.m2 = mat.m8;
    result.m3 = mat.m12;
    result.m4 = mat.m1;
    result.m5 = mat.m5;
    result.m6 = mat.m9;
    result.m7 = mat.m13;
    result.m8 = mat.m2;
    result.m9 = mat.m6;
    result.m10 = mat.m10;
    result.m11 = mat.m14;
    result.m12 = mat.m3;
    result.m13 = mat.m7;
    result.m14 = mat.m11;
    result.m15 = mat.m15;
    return result;
}

fn rlMatrixInvert(mat: Matrix) Matrix {
    var result = std.mem.zeroes(Matrix);

    const a00 = mat.m0;
    const a01 = mat.m1;
    const a02 = mat.m2;
    const a03 = mat.m3;
    const a10 = mat.m4;
    const a11 = mat.m5;
    const a12 = mat.m6;
    const a13 = mat.m7;
    const a20 = mat.m8;
    const a21 = mat.m9;
    const a22 = mat.m10;
    const a23 = mat.m11;
    const a30 = mat.m12;
    const a31 = mat.m13;
    const a32 = mat.m14;
    const a33 = mat.m15;

    const b00 = a00 * a11 - a01 * a10;
    const b01 = a00 * a12 - a02 * a10;
    const b02 = a00 * a13 - a03 * a10;
    const b03 = a01 * a12 - a02 * a11;
    const b04 = a01 * a13 - a03 * a11;
    const b05 = a02 * a13 - a03 * a12;
    const b06 = a20 * a31 - a21 * a30;
    const b07 = a20 * a32 - a22 * a30;
    const b08 = a20 * a33 - a23 * a30;
    const b09 = a21 * a32 - a22 * a31;
    const b10 = a21 * a33 - a23 * a31;
    const b11 = a22 * a33 - a23 * a32;

    const invDet = 1.0 / (b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06);

    result.m0 = (a11 * b11 - a12 * b10 + a13 * b09) * invDet;
    result.m1 = (-a01 * b11 + a02 * b10 - a03 * b09) * invDet;
    result.m2 = (a31 * b05 - a32 * b04 + a33 * b03) * invDet;
    result.m3 = (-a21 * b05 + a22 * b04 - a23 * b03) * invDet;
    result.m4 = (-a10 * b11 + a12 * b08 - a13 * b07) * invDet;
    result.m5 = (a00 * b11 - a02 * b08 + a03 * b07) * invDet;
    result.m6 = (-a30 * b05 + a32 * b02 - a33 * b01) * invDet;
    result.m7 = (a20 * b05 - a22 * b02 + a23 * b01) * invDet;
    result.m8 = (a10 * b10 - a11 * b08 + a13 * b06) * invDet;
    result.m9 = (-a00 * b10 + a01 * b08 - a03 * b06) * invDet;
    result.m10 = (a30 * b04 - a31 * b02 + a33 * b00) * invDet;
    result.m11 = (-a20 * b04 + a21 * b02 - a23 * b00) * invDet;
    result.m12 = (-a10 * b09 + a11 * b07 - a12 * b06) * invDet;
    result.m13 = (a00 * b09 - a01 * b07 + a02 * b06) * invDet;
    result.m14 = (-a30 * b03 + a31 * b01 - a32 * b00) * invDet;
    result.m15 = (a20 * b03 - a21 * b01 + a22 * b00) * invDet;

    return result;
}
