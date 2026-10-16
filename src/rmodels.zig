//! rmodels - Basic functions to draw 3d shapes and load and draw 3d models
//!
//! Zig port of raylib's `rmodels.c`. Every public raylib model/mesh/material function
//! is exported with its exact C name, byte-compatible signature, and C calling
//! convention, so the rest of raylib (still C) links against it unchanged.
//! Floating-point operation order matches the C source exactly to keep pixel output
//! bit-identical, and libc/libm functions are called via extern declarations.
//!
//! This build mirrors raylib's default `config.h`: OBJ/MTL/IQM/GLTF/VOX/M3D loaders
//! and procedural mesh generation are all enabled. The third-party single-file
//! libraries (tinyobj_loader_c, cgltf, vox_loader, m3d, par_shapes) are instantiated
//! in the C shim `src/c/rmodels_impl.c` and only `extern`-declared and called here.
//! rlgl, raymath, rtextures and rcore are reached through extern declarations too.

const std = @import("std");
const Io = std.Io;
const cmem = @import("cmem.zig");
const iqm = @import("rmodels_iqm.zig");

//----------------------------------------------------------------------------------
// libc / libm functions, called directly so results are bit-identical to the C source.
//----------------------------------------------------------------------------------
extern fn malloc(usize) ?*anyopaque;
extern fn calloc(usize, usize) ?*anyopaque;
extern fn realloc(?*anyopaque, usize) ?*anyopaque;
extern fn free(?*anyopaque) void;
extern fn memcpy(noalias ?*anyopaque, noalias ?*const anyopaque, usize) ?*anyopaque;
extern fn memset(?*anyopaque, c_int, usize) ?*anyopaque;
extern fn memcmp(?*const anyopaque, ?*const anyopaque, usize) c_int;
extern fn strcmp([*c]const u8, [*c]const u8) c_int;
extern fn strlen([*c]const u8) usize;
extern fn strncpy(noalias [*c]u8, noalias [*c]const u8, usize) [*c]u8;
extern fn sprintf(noalias [*c]u8, noalias [*c]const u8, ...) c_int;
extern fn snprintf(noalias [*c]u8, usize, noalias [*c]const u8, ...) c_int;

extern fn sinf(f32) f32;
extern fn cosf(f32) f32;
extern fn sqrtf(f32) f32;
extern fn fmaxf(f32, f32) f32;
extern fn fmin(f64, f64) f64;
extern fn fmax(f64, f64) f64;

// POSIX chdir for LoadOBJ working-directory switch
extern fn chdir([*c]const u8) c_int;

// raylib RL_MALLOC/RL_CALLOC/RL_FREE/RL_REALLOC map to malloc/calloc/free/realloc.
const RL_MALLOC = malloc;
const RL_CALLOC = calloc;
const RL_REALLOC = realloc;
inline fn RL_FREE(p: anytype) void {
    free(@ptrCast(@constCast(p)));
}

const PI: f32 = 3.14159265358979323846;
const DEG2RAD: f32 = PI / 180.0;
const EPSILON: f32 = 0.000001;

//----------------------------------------------------------------------------------
// Defines and Macros
//----------------------------------------------------------------------------------
const MAX_MATERIAL_MAPS = 12;
/// Mirrors config.h `SUPPORT_GPU_SKINNING` (on by default since raylib 6.2): bone
/// indices/weights get their own VBOs and are bound to the shader on draw.
const SUPPORT_GPU_SKINNING = true;

// NOTE: GPU skinning needs two additional vertex buffers (bone indices and weights)
const MAX_MESH_VERTEX_BUFFERS = if (SUPPORT_GPU_SKINNING) 9 else 7;
const MAX_FILEPATH_LENGTH: usize = 4096;

// Default shader vertex attribute locations (from rlgl.h)
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION: c_uint = 0;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD: c_uint = 1;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL: c_uint = 2;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR: c_uint = 3;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT: c_uint = 4;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2: c_uint = 5;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_INDICES: c_uint = 6;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES: c_uint = 7;
const RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS: c_uint = 8;

// rlgl data types
const RL_UNSIGNED_BYTE: c_int = 0x1401;
const RL_FLOAT: c_int = 0x1406;

// TraceLog levels
const LOG_INFO: c_int = 3;
const LOG_DEBUG: c_int = 2;
const LOG_WARNING: c_int = 4;

// rlShaderUniformDataType
const SHADER_UNIFORM_INT: c_int = 4;
const SHADER_UNIFORM_VEC4: c_int = 3;

// rlShaderAttributeDataType
const SHADER_ATTRIB_VEC2: c_int = 1;
const SHADER_ATTRIB_VEC3: c_int = 2;
const SHADER_ATTRIB_VEC4: c_int = 3;

// MaterialMapIndex
const MATERIAL_MAP_ALBEDO: usize = 0;
const MATERIAL_MAP_DIFFUSE: usize = 0; // alias of ALBEDO
const MATERIAL_MAP_METALNESS: usize = 1;
const MATERIAL_MAP_SPECULAR: usize = 1; // alias of METALNESS
const MATERIAL_MAP_NORMAL: usize = 2;
const MATERIAL_MAP_ROUGHNESS: usize = 3;
const MATERIAL_MAP_OCCLUSION: usize = 4;
const MATERIAL_MAP_EMISSION: usize = 5;
const MATERIAL_MAP_HEIGHT: usize = 6;
const MATERIAL_MAP_CUBEMAP: usize = 7;
const MATERIAL_MAP_IRRADIANCE: usize = 8;
const MATERIAL_MAP_PREFILTER: usize = 9;
const MATERIAL_MAP_BRDF: usize = 10;

// ShaderLocationIndex
const SHADER_LOC_VERTEX_POSITION: usize = 0;
const SHADER_LOC_VERTEX_TEXCOORD01: usize = 1;
const SHADER_LOC_VERTEX_TEXCOORD02: usize = 2;
const SHADER_LOC_VERTEX_NORMAL: usize = 3;
const SHADER_LOC_VERTEX_TANGENT: usize = 4;
const SHADER_LOC_VERTEX_COLOR: usize = 5;
const SHADER_LOC_MATRIX_MVP: usize = 6;
const SHADER_LOC_MATRIX_VIEW: usize = 7;
const SHADER_LOC_MATRIX_PROJECTION: usize = 8;
const SHADER_LOC_MATRIX_MODEL: usize = 9;
const SHADER_LOC_MATRIX_NORMAL: usize = 10;
const SHADER_LOC_COLOR_DIFFUSE: usize = 12;
const SHADER_LOC_COLOR_SPECULAR: usize = 13;
const SHADER_LOC_MAP_ALBEDO: usize = 15;
const SHADER_LOC_MAP_DIFFUSE: usize = 15; // alias of MAP_ALBEDO
const SHADER_LOC_VERTEX_BONEIDS: usize = 26;
const SHADER_LOC_VERTEX_BONEWEIGHTS: usize = 27;
const SHADER_LOC_MATRIX_BONETRANSFORMS: usize = 28;
const SHADER_LOC_VERTEX_INSTANCETRANSFORM: usize = 29;

// PixelFormat
const PIXELFORMAT_UNCOMPRESSED_GRAYSCALE: c_int = 1;
const PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA: c_int = 2;
const PIXELFORMAT_UNCOMPRESSED_R8G8B8: c_int = 4;
const PIXELFORMAT_UNCOMPRESSED_R8G8B8A8: c_int = 7;

// RL_LINES/RL_TRIANGLES/RL_QUADS
const RL_LINES: c_int = 0x0001;
const RL_TRIANGLES: c_int = 0x0004;
const RL_QUADS: c_int = 0x0007;

const WHITE = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

//----------------------------------------------------------------------------------
// Types and Structures Definition (public ABI: extern struct, exact raylib.h layout)
//----------------------------------------------------------------------------------
pub const Vector2 = extern struct { x: f32, y: f32 };
pub const Vector3 = extern struct { x: f32, y: f32, z: f32 };
pub const Vector4 = extern struct { x: f32, y: f32, z: f32, w: f32 };
pub const Quaternion = Vector4;

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

pub const Color = extern struct { r: u8, g: u8, b: u8, a: u8 };
pub const Rectangle = extern struct { x: f32, y: f32, width: f32, height: f32 };

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

pub const Shader = extern struct {
    id: c_uint,
    locs: [*c]c_int,
};

pub const MaterialMap = extern struct {
    texture: Texture2D,
    color: Color,
    value: f32,
};

pub const Material = extern struct {
    shader: Shader,
    maps: [*c]MaterialMap,
    params: [4]f32,
};

pub const Transform = extern struct {
    translation: Vector3,
    rotation: Quaternion,
    scale: Vector3,
};

pub const BoneInfo = extern struct {
    name: [32]u8,
    parent: c_int,
};

pub const Mesh = extern struct {
    vertexCount: c_int,
    triangleCount: c_int,

    vertices: [*c]f32,
    texcoords: [*c]f32,
    texcoords2: [*c]f32,
    normals: [*c]f32,
    tangents: [*c]f32,
    colors: [*c]u8,
    indices: [*c]c_ushort,

    boneCount: c_int,
    boneIndices: [*c]u8,
    boneWeights: [*c]f32,

    animVertices: [*c]f32,
    animNormals: [*c]f32,

    vaoId: c_uint,
    vboId: [*c]c_uint,
};

pub const ModelAnimPose = [*c]Transform;

pub const ModelSkeleton = extern struct {
    boneCount: c_uint,
    bones: [*c]BoneInfo,
    bindPose: ModelAnimPose,
};

pub const Model = extern struct {
    transform: Matrix,

    meshCount: c_int,
    materialCount: c_int,
    meshes: [*c]Mesh,
    materials: [*c]Material,
    meshMaterial: [*c]c_int,

    skeleton: ModelSkeleton,

    currentPose: ModelAnimPose,
    boneMatrices: [*c]Matrix,
};

pub const ModelAnimation = extern struct {
    name: [32]u8,
    boneCount: c_uint,
    keyframeCount: c_int,
    keyframePoses: [*c]ModelAnimPose,
};

pub const Ray = extern struct {
    position: Vector3,
    direction: Vector3,
};

pub const RayCollision = extern struct {
    hit: bool,
    distance: f32,
    point: Vector3,
    normal: Vector3,
};

pub const BoundingBox = extern struct {
    min: Vector3,
    max: Vector3,
};

pub const Camera3D = extern struct {
    position: Vector3,
    target: Vector3,
    up: Vector3,
    fovy: f32,
    projection: c_int,
};
pub const Camera = Camera3D;

// float16: row-major 16-float matrix (raymath MatrixToFloatV result)
const float16 = extern struct { v: [16]f32 };

//----------------------------------------------------------------------------------
// Cross-module raylib C symbols (rcore / rtextures, still C in this build).
//----------------------------------------------------------------------------------
extern fn TraceLog(logLevel: c_int, text: [*c]const u8, ...) void;
extern fn LoadFileData(fileName: [*c]const u8, dataSize: [*c]c_int) [*c]u8;
extern fn UnloadFileData(data: [*c]u8) void;
extern fn LoadFileText(fileName: [*c]const u8) [*c]u8;
extern fn UnloadFileText(text: [*c]u8) void;
extern fn SaveFileText(fileName: [*c]const u8, text: [*c]u8) bool;
extern fn GetFileNameWithoutExt(filePath: [*c]const u8) [*c]const u8;
extern fn GetDirectoryPath(filePath: [*c]const u8) [*c]const u8;
extern fn GetWorkingDirectory() [*c]const u8;
extern fn IsFileExtension(fileName: [*c]const u8, ext: [*c]const u8) bool;
extern fn TextFormat(text: [*c]const u8, ...) [*c]const u8;
extern fn TextLength(text: [*c]const u8) c_uint;
extern fn MemAlloc(size: c_uint) ?*anyopaque;
extern fn MemFree(ptr: ?*anyopaque) void;

// rtextures (still C-ABI)
extern fn LoadTexture(fileName: [*c]const u8) Texture2D;
extern fn LoadTextureFromImage(image: Image) Texture2D;
extern fn LoadImage(fileName: [*c]const u8) Image;
extern fn LoadImageFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: c_int) Image;
extern fn UnloadImage(image: Image) void;
extern fn LoadImageColors(image: Image) [*c]Color;
extern fn UnloadImageColors(colors: [*c]Color) void;
extern fn GetImageColor(image: Image, x: c_int, y: c_int) Color;
extern fn UnloadShader(shader: Shader) void;

//----------------------------------------------------------------------------------
// rlgl functions, provided by src/rlgl.zig.
//----------------------------------------------------------------------------------
extern fn rlBegin(mode: c_int) void;
extern fn rlEnd() void;
extern fn rlVertex3f(x: f32, y: f32, z: f32) void;
extern fn rlColor4ub(r: u8, g: u8, b: u8, a: u8) void;
extern fn rlColor3f(x: f32, y: f32, z: f32) void;
extern fn rlNormal3f(x: f32, y: f32, z: f32) void;
extern fn rlTexCoord2f(x: f32, y: f32) void;
extern fn rlPushMatrix() void;
extern fn rlPopMatrix() void;
extern fn rlTranslatef(x: f32, y: f32, z: f32) void;
extern fn rlRotatef(angle: f32, x: f32, y: f32, z: f32) void;
extern fn rlScalef(x: f32, y: f32, z: f32) void;
extern fn rlMultMatrixf(matf: [*c]const f32) void;
extern fn rlSetTexture(id: c_uint) void;
extern fn rlEnableShader(id: c_uint) void;
extern fn rlDisableShader() void;
extern fn rlEnableTexture(id: c_uint) void;
extern fn rlDisableTexture() void;
extern fn rlEnableTextureCubemap(id: c_uint) void;
extern fn rlDisableTextureCubemap() void;
extern fn rlActiveTextureSlot(slot: c_int) void;
extern fn rlEnableWireMode() void;
extern fn rlDisableWireMode() void;
extern fn rlViewport(x: c_int, y: c_int, width: c_int, height: c_int) void;

extern fn rlLoadVertexArray() c_uint;
extern fn rlEnableVertexArray(vaoId: c_uint) bool;
extern fn rlDisableVertexArray() void;
extern fn rlLoadVertexBuffer(buffer: ?*const anyopaque, size: c_int, dynamic: bool) c_uint;
extern fn rlLoadVertexBufferElement(buffer: ?*const anyopaque, size: c_int, dynamic: bool) c_uint;
extern fn rlUpdateVertexBuffer(bufferId: c_uint, data: ?*const anyopaque, dataSize: c_int, offset: c_int) void;
extern fn rlEnableVertexBuffer(id: c_uint) void;
extern fn rlDisableVertexBuffer() void;
extern fn rlEnableVertexBufferElement(id: c_uint) void;
extern fn rlDisableVertexBufferElement() void;
extern fn rlUnloadVertexArray(vaoId: c_uint) void;
extern fn rlUnloadVertexBuffer(vboId: c_uint) void;
extern fn rlSetVertexAttribute(index: c_uint, compSize: c_int, ttype: c_int, normalized: bool, stride: c_int, offset: c_int) void;
extern fn rlSetVertexAttributeDivisor(index: c_uint, divisor: c_int) void;
extern fn rlSetVertexAttributeDefault(locIndex: c_int, value: ?*const anyopaque, attribType: c_int, count: c_int) void;
extern fn rlEnableVertexAttribute(index: c_uint) void;
extern fn rlDisableVertexAttribute(index: c_uint) void;
extern fn rlDrawVertexArray(offset: c_int, count: c_int) void;
extern fn rlDrawVertexArrayElements(offset: c_int, count: c_int, buffer: ?*const anyopaque) void;
extern fn rlDrawVertexArrayInstanced(offset: c_int, count: c_int, instances: c_int) void;
extern fn rlDrawVertexArrayElementsInstanced(offset: c_int, count: c_int, buffer: ?*const anyopaque, instances: c_int) void;

extern fn rlSetUniform(locIndex: c_int, value: ?*const anyopaque, uniformType: c_int, count: c_int) void;
extern fn rlSetUniformMatrix(locIndex: c_int, mat: Matrix) void;
extern fn rlSetUniformMatrices(locIndex: c_int, mat: [*c]const Matrix, count: c_int) void;
extern fn rlGetMatrixModelview() Matrix;
extern fn rlGetMatrixProjection() Matrix;
extern fn rlGetMatrixTransform() Matrix;
extern fn rlGetMatrixViewOffsetStereo(eye: c_int) Matrix;
extern fn rlGetMatrixProjectionStereo(eye: c_int) Matrix;
extern fn rlSetMatrixModelview(view: Matrix) void;
extern fn rlSetMatrixProjection(proj: Matrix) void;
extern fn rlIsStereoRenderEnabled() bool;
extern fn rlGetFramebufferWidth() c_int;
extern fn rlGetFramebufferHeight() c_int;
extern fn rlGetShaderIdDefault() c_uint;
extern fn rlGetShaderLocsDefault() [*c]c_int;
extern fn rlGetTextureIdDefault() c_uint;
extern fn rlUnloadTexture(id: c_uint) void;

//----------------------------------------------------------------------------------
// raymath functions (extern, to avoid bundling raymath into this object).
//----------------------------------------------------------------------------------
extern fn MatrixIdentity() Matrix;
extern fn MatrixMultiply(left: Matrix, right: Matrix) Matrix;
extern fn MatrixTranspose(mat: Matrix) Matrix;
extern fn MatrixInvert(mat: Matrix) Matrix;
extern fn MatrixTranslate(x: f32, y: f32, z: f32) Matrix;
extern fn MatrixRotate(axis: Vector3, angle: f32) Matrix;
extern fn MatrixScale(x: f32, y: f32, z: f32) Matrix;
extern fn MatrixLookAt(eye: Vector3, target: Vector3, up: Vector3) Matrix;
extern fn MatrixToFloatV(mat: Matrix) float16;
extern fn MatrixDecompose(mat: Matrix, translation: [*c]Vector3, rotation: [*c]Quaternion, scale: [*c]Vector3) void;

extern fn Vector3Add(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3Subtract(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3Scale(v: Vector3, scalar: f32) Vector3;
extern fn Vector3Multiply(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3Divide(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3CrossProduct(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3DotProduct(v1: Vector3, v2: Vector3) f32;
extern fn Vector3Length(v: Vector3) f32;
extern fn Vector3Distance(v1: Vector3, v2: Vector3) f32;
extern fn Vector3DistanceSqr(v1: Vector3, v2: Vector3) f32;
extern fn Vector3Normalize(v: Vector3) Vector3;
extern fn Vector3Negate(v: Vector3) Vector3;
extern fn Vector3Perpendicular(v: Vector3) Vector3;
extern fn Vector3Transform(v: Vector3, mat: Matrix) Vector3;
extern fn Vector3RotateByQuaternion(v: Vector3, q: Quaternion) Vector3;
extern fn Vector3RotateByAxisAngle(v: Vector3, axis: Vector3, angle: f32) Vector3;
extern fn Vector3Lerp(v1: Vector3, v2: Vector3, amount: f32) Vector3;
extern fn Vector3Min(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3Max(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3Zero() Vector3;
extern fn Vector3CubicHermite(v1: Vector3, tangent1: Vector3, v2: Vector3, tangent2: Vector3, amount: f32) Vector3;

extern fn Vector2Scale(v: Vector2, scale: f32) Vector2;

extern fn Vector4DotProduct(v1: Vector4, v2: Vector4) f32;
extern fn Vector4Scale(v: Vector4, scale: f32) Vector4;
extern fn Vector4Negate(v: Vector4) Vector4;

extern fn QuaternionMultiply(q1: Quaternion, q2: Quaternion) Quaternion;
extern fn QuaternionSlerp(q1: Quaternion, q2: Quaternion, amount: f32) Quaternion;
extern fn QuaternionNormalize(q: Quaternion) Quaternion;
extern fn QuaternionToMatrix(q: Quaternion) Matrix;
extern fn QuaternionCubicHermiteSpline(q1: Quaternion, outTangent1: Quaternion, q2: Quaternion, inTangent2: Quaternion, t: f32) Quaternion;

extern fn Clamp(value: f32, min: f32, max: f32) f32;
extern fn FloatEquals(x: f32, y: f32) c_int;

//----------------------------------------------------------------------------------
// Internal helpers
//----------------------------------------------------------------------------------
const empty_model = std.mem.zeroes(Model);
const empty_mesh = std.mem.zeroes(Mesh);

/// A C count as a length; negative counts are empty, as C's `i < n` loops treat them
fn count(n: anytype) usize {
    return @intCast(@max(n, 0));
}

fn modelMeshes(model: Model) []Mesh {
    return if (model.meshes == null) &.{} else model.meshes[0..count(model.meshCount)];
}

fn modelMaterials(model: Model) []Material {
    return if (model.materials == null) &.{} else model.materials[0..count(model.materialCount)];
}

/// A float array viewed as the XYZ vectors it holds
fn vector3s(values: []f32) []Vector3 {
    return std.mem.bytesAsSlice(Vector3, std.mem.sliceAsBytes(values));
}

/// A float array viewed as the XY vectors it holds
fn vector2s(values: []f32) []Vector2 {
    return std.mem.bytesAsSlice(Vector2, std.mem.sliceAsBytes(values));
}

/// C's `(int)` cast as x86-64 performs it: NaN and out-of-range values give
/// INT_MIN where Zig's @intFromFloat would trap (an axis-aligned ray makes
/// GetRayCollisionBox divide by zero, and its normal goes infinite)
fn cInt(v: f32) c_int {
    if (!(v >= -2147483648.0 and v < 2147483648.0)) return std.math.minInt(c_int);
    return @intFromFloat(v);
}

/// C's `(unsigned char)` cast of a float: the int conversion, truncated
fn cByte(v: f32) u8 {
    return @truncate(@as(c_uint, @bitCast(cInt(v))));
}

/// Releases a model's meshes' vertex data and its own arrays (CPU side only)
fn freeModelData(model: Model) void {
    for (modelMeshes(model)) |mesh| freeMeshArrays(mesh);
    freeModelArrays(model);
}

/// Copies a C string into `buffer`, truncated to fit as snprintf("%s") does
fn copyCString(buffer: []u8, source: [*c]const u8) [:0]const u8 {
    const text = std.mem.span(source);
    const len = @min(text.len, buffer.len - 1);
    @memcpy(buffer[0..len], text[0..len]);
    buffer[len] = 0;
    return buffer[0..len :0];
}

/// std's process-wide Io: raylib's C API has no parameter to carry one
fn io() Io {
    return Io.Threaded.global_single_threaded.io();
}

fn changeDirectory(path: [*c]const u8) !void {
    try std.process.setCurrentPath(io(), std.mem.span(path));
}

//----------------------------------------------------------------------------------
// Module Functions Definition - 3D Shapes drawing
//----------------------------------------------------------------------------------

// Draw a line in 3D world space
export fn DrawLine3D(startPos: Vector3, endPos: Vector3, color: Color) callconv(.c) void {
    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlVertex3f(startPos.x, startPos.y, startPos.z);
    rlVertex3f(endPos.x, endPos.y, endPos.z);
    rlEnd();
}

// Draw a point in 3D space, actually a small line
export fn DrawPoint3D(position: Vector3, color: Color) callconv(.c) void {
    rlPushMatrix();
    rlTranslatef(position.x, position.y, position.z);
    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlVertex3f(0.0, 0.0, 0.0);
    rlVertex3f(0.0, 0.0, 0.1);
    rlEnd();
    rlPopMatrix();
}

// Draw a circle in 3D world space
export fn DrawCircle3D(center: Vector3, radius: f32, rotationAxis: Vector3, rotationAngle: f32, color: Color) callconv(.c) void {
    rlPushMatrix();
    rlTranslatef(center.x, center.y, center.z);
    rlRotatef(rotationAngle, rotationAxis.x, rotationAxis.y, rotationAxis.z);

    rlBegin(RL_LINES);
    var i: c_int = 0;
    while (i < 360) : (i += 10) {
        rlColor4ub(color.r, color.g, color.b, color.a);

        rlVertex3f(sinf(DEG2RAD * @as(f32, @floatFromInt(i))) * radius, cosf(DEG2RAD * @as(f32, @floatFromInt(i))) * radius, 0.0);
        rlVertex3f(sinf(DEG2RAD * @as(f32, @floatFromInt(i + 10))) * radius, cosf(DEG2RAD * @as(f32, @floatFromInt(i + 10))) * radius, 0.0);
    }
    rlEnd();
    rlPopMatrix();
}

// Draw a color-filled triangle (vertex in counter-clockwise order!)
export fn DrawTriangle3D(v1: Vector3, v2: Vector3, v3: Vector3, color: Color) callconv(.c) void {
    rlBegin(RL_TRIANGLES);
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlVertex3f(v1.x, v1.y, v1.z);
    rlVertex3f(v2.x, v2.y, v2.z);
    rlVertex3f(v3.x, v3.y, v3.z);
    rlEnd();
}

// Draw a triangle strip defined by points
export fn DrawTriangleStrip3D(points: [*c]const Vector3, pointCount: c_int, color: Color) callconv(.c) void {
    if (pointCount < 3) return; // Security check

    rlBegin(RL_TRIANGLES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    var i: c_int = 2;
    while (i < pointCount) : (i += 1) {
        const u: usize = @intCast(i);
        if (@rem(i, 2) == 0) {
            rlVertex3f(points[u].x, points[u].y, points[u].z);
            rlVertex3f(points[u - 2].x, points[u - 2].y, points[u - 2].z);
            rlVertex3f(points[u - 1].x, points[u - 1].y, points[u - 1].z);
        } else {
            rlVertex3f(points[u].x, points[u].y, points[u].z);
            rlVertex3f(points[u - 1].x, points[u - 1].y, points[u - 1].z);
            rlVertex3f(points[u - 2].x, points[u - 2].y, points[u - 2].z);
        }
    }
    rlEnd();
}

// Draw cube
// NOTE: Cube position is the center position
export fn DrawCube(position: Vector3, width: f32, height: f32, length: f32, color: Color) callconv(.c) void {
    const x: f32 = 0.0;
    const y: f32 = 0.0;
    const z: f32 = 0.0;

    rlPushMatrix();
    rlTranslatef(position.x, position.y, position.z);

    rlBegin(RL_TRIANGLES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    // Front face
    rlNormal3f(0.0, 0.0, 1.0);
    rlVertex3f(x - width / 2, y - height / 2, z + length / 2); // Bottom Left
    rlVertex3f(x + width / 2, y - height / 2, z + length / 2); // Bottom Right
    rlVertex3f(x - width / 2, y + height / 2, z + length / 2); // Top Left

    rlVertex3f(x + width / 2, y + height / 2, z + length / 2); // Top Right
    rlVertex3f(x - width / 2, y + height / 2, z + length / 2); // Top Left
    rlVertex3f(x + width / 2, y - height / 2, z + length / 2); // Bottom Right

    // Back face
    rlNormal3f(0.0, 0.0, -1.0);
    rlVertex3f(x - width / 2, y - height / 2, z - length / 2); // Bottom Left
    rlVertex3f(x - width / 2, y + height / 2, z - length / 2); // Top Left
    rlVertex3f(x + width / 2, y - height / 2, z - length / 2); // Bottom Right

    rlVertex3f(x + width / 2, y + height / 2, z - length / 2); // Top Right
    rlVertex3f(x + width / 2, y - height / 2, z - length / 2); // Bottom Right
    rlVertex3f(x - width / 2, y + height / 2, z - length / 2); // Top Left

    // Top face
    rlNormal3f(0.0, 1.0, 0.0);
    rlVertex3f(x - width / 2, y + height / 2, z - length / 2); // Top Left
    rlVertex3f(x - width / 2, y + height / 2, z + length / 2); // Bottom Left
    rlVertex3f(x + width / 2, y + height / 2, z + length / 2); // Bottom Right

    rlVertex3f(x + width / 2, y + height / 2, z - length / 2); // Top Right
    rlVertex3f(x - width / 2, y + height / 2, z - length / 2); // Top Left
    rlVertex3f(x + width / 2, y + height / 2, z + length / 2); // Bottom Right

    // Bottom face
    rlNormal3f(0.0, -1.0, 0.0);
    rlVertex3f(x - width / 2, y - height / 2, z - length / 2); // Top Left
    rlVertex3f(x + width / 2, y - height / 2, z + length / 2); // Bottom Right
    rlVertex3f(x - width / 2, y - height / 2, z + length / 2); // Bottom Left

    rlVertex3f(x + width / 2, y - height / 2, z - length / 2); // Top Right
    rlVertex3f(x + width / 2, y - height / 2, z + length / 2); // Bottom Right
    rlVertex3f(x - width / 2, y - height / 2, z - length / 2); // Top Left

    // Right face
    rlNormal3f(1.0, 0.0, 0.0);
    rlVertex3f(x + width / 2, y - height / 2, z - length / 2); // Bottom Right
    rlVertex3f(x + width / 2, y + height / 2, z - length / 2); // Top Right
    rlVertex3f(x + width / 2, y + height / 2, z + length / 2); // Top Left

    rlVertex3f(x + width / 2, y - height / 2, z + length / 2); // Bottom Left
    rlVertex3f(x + width / 2, y - height / 2, z - length / 2); // Bottom Right
    rlVertex3f(x + width / 2, y + height / 2, z + length / 2); // Top Left

    // Left face
    rlNormal3f(-1.0, 0.0, 0.0);
    rlVertex3f(x - width / 2, y - height / 2, z - length / 2); // Bottom Right
    rlVertex3f(x - width / 2, y + height / 2, z + length / 2); // Top Left
    rlVertex3f(x - width / 2, y + height / 2, z - length / 2); // Top Right

    rlVertex3f(x - width / 2, y - height / 2, z + length / 2); // Bottom Left
    rlVertex3f(x - width / 2, y + height / 2, z + length / 2); // Top Left
    rlVertex3f(x - width / 2, y - height / 2, z - length / 2); // Bottom Right
    rlEnd();
    rlPopMatrix();
}

// Draw cube (Vector version)
export fn DrawCubeV(position: Vector3, size: Vector3, color: Color) callconv(.c) void {
    DrawCube(position, size.x, size.y, size.z, color);
}

// Draw cube wires
export fn DrawCubeWires(position: Vector3, width: f32, height: f32, length: f32, color: Color) callconv(.c) void {
    const x: f32 = 0.0;
    const y: f32 = 0.0;
    const z: f32 = 0.0;

    rlPushMatrix();
    rlTranslatef(position.x, position.y, position.z);

    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    // Front face
    rlVertex3f(x - width / 2, y - height / 2, z + length / 2);
    rlVertex3f(x + width / 2, y - height / 2, z + length / 2);

    rlVertex3f(x + width / 2, y - height / 2, z + length / 2);
    rlVertex3f(x + width / 2, y + height / 2, z + length / 2);

    rlVertex3f(x + width / 2, y + height / 2, z + length / 2);
    rlVertex3f(x - width / 2, y + height / 2, z + length / 2);

    rlVertex3f(x - width / 2, y + height / 2, z + length / 2);
    rlVertex3f(x - width / 2, y - height / 2, z + length / 2);

    // Back face
    rlVertex3f(x - width / 2, y - height / 2, z - length / 2);
    rlVertex3f(x + width / 2, y - height / 2, z - length / 2);

    rlVertex3f(x + width / 2, y - height / 2, z - length / 2);
    rlVertex3f(x + width / 2, y + height / 2, z - length / 2);

    rlVertex3f(x + width / 2, y + height / 2, z - length / 2);
    rlVertex3f(x - width / 2, y + height / 2, z - length / 2);

    rlVertex3f(x - width / 2, y + height / 2, z - length / 2);
    rlVertex3f(x - width / 2, y - height / 2, z - length / 2);

    // Top face
    rlVertex3f(x - width / 2, y + height / 2, z + length / 2);
    rlVertex3f(x - width / 2, y + height / 2, z - length / 2);

    rlVertex3f(x + width / 2, y + height / 2, z + length / 2);
    rlVertex3f(x + width / 2, y + height / 2, z - length / 2);

    // Bottom face
    rlVertex3f(x - width / 2, y - height / 2, z + length / 2);
    rlVertex3f(x - width / 2, y - height / 2, z - length / 2);

    rlVertex3f(x + width / 2, y - height / 2, z + length / 2);
    rlVertex3f(x + width / 2, y - height / 2, z - length / 2);
    rlEnd();
    rlPopMatrix();
}

// Draw cube wires (vector version)
export fn DrawCubeWiresV(position: Vector3, size: Vector3, color: Color) callconv(.c) void {
    DrawCubeWires(position, size.x, size.y, size.z, color);
}

// Draw sphere
export fn DrawSphere(centerPos: Vector3, radius: f32, color: Color) callconv(.c) void {
    DrawSphereEx(centerPos, radius, 16, 16, color);
}

// Rotation of a sphere vertex around the y axis by the slice angle
fn rotateSlice(v: Vector3, cosslice: f32, sinslice: f32) Vector3 {
    return .{ .x = cosslice * v.x - sinslice * v.z, .y = v.y, .z = sinslice * v.x + cosslice * v.z };
}

// Rotation of a sphere vertex around the z axis by the ring angle
fn rotateRing(v: Vector3, cosring: f32, sinring: f32) Vector3 {
    return .{ .x = cosring * v.x + sinring * v.y, .y = -sinring * v.x + cosring * v.y, .z = v.z };
}

// Draw sphere with defined rings and slices
export fn DrawSphereEx(centerPos: Vector3, radius: f32, rings: c_int, slices: c_int, color: Color) callconv(.c) void {
    rlPushMatrix();
    rlTranslatef(centerPos.x, centerPos.y, centerPos.z);
    rlScalef(radius, radius, radius);

    rlBegin(RL_TRIANGLES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    const ringangle = DEG2RAD * (180.0 / @as(f32, @floatFromInt(rings))); // Angle between latitudinal parallels
    const sliceangle = DEG2RAD * (360.0 / @as(f32, @floatFromInt(slices))); // Angle between longitudinal meridians

    const cosring = cosf(ringangle);
    const sinring = sinf(ringangle);
    const cosslice = cosf(sliceangle);
    const sinslice = sinf(sliceangle);

    var vertices = [4]Vector3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = sinring, .y = cosring, .z = 0 },
    };

    var i: c_int = 0;
    while (i < rings) : (i += 1) {
        var j: c_int = 0;
        while (j < slices) : (j += 1) {
            vertices[0] = vertices[2]; // Rotate around y axis to set up vertices for next face
            vertices[1] = vertices[3];
            vertices[2] = rotateSlice(vertices[2], cosslice, sinslice);
            vertices[3] = rotateSlice(vertices[3], cosslice, sinslice);

            rlNormal3f(vertices[0].x, vertices[0].y, vertices[0].z);
            rlVertex3f(vertices[0].x, vertices[0].y, vertices[0].z);
            rlNormal3f(vertices[3].x, vertices[3].y, vertices[3].z);
            rlVertex3f(vertices[3].x, vertices[3].y, vertices[3].z);
            rlNormal3f(vertices[1].x, vertices[1].y, vertices[1].z);
            rlVertex3f(vertices[1].x, vertices[1].y, vertices[1].z);

            rlNormal3f(vertices[0].x, vertices[0].y, vertices[0].z);
            rlVertex3f(vertices[0].x, vertices[0].y, vertices[0].z);
            rlNormal3f(vertices[2].x, vertices[2].y, vertices[2].z);
            rlVertex3f(vertices[2].x, vertices[2].y, vertices[2].z);
            rlNormal3f(vertices[3].x, vertices[3].y, vertices[3].z);
            rlVertex3f(vertices[3].x, vertices[3].y, vertices[3].z);
        }

        vertices[2] = vertices[3]; // Rotate around z axis to set up starting vertices for next ring
        vertices[3] = rotateRing(vertices[3], cosring, sinring);
    }
    rlEnd();
    rlPopMatrix();
}

// Draw sphere wires
export fn DrawSphereWires(centerPos: Vector3, radius: f32, rings: c_int, slices: c_int, color: Color) callconv(.c) void {
    rlPushMatrix();
    rlTranslatef(centerPos.x, centerPos.y, centerPos.z);
    rlScalef(radius, radius, radius);

    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    const ringangle = DEG2RAD * (180.0 / @as(f32, @floatFromInt(rings))); // Angle between latitudinal parallels
    const sliceangle = DEG2RAD * (360.0 / @as(f32, @floatFromInt(slices))); // Angle between longitudinal meridians

    const cosring = cosf(ringangle);
    const sinring = sinf(ringangle);
    const cosslice = cosf(sliceangle);
    const sinslice = sinf(sliceangle);

    var vertices = [4]Vector3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = sinring, .y = cosring, .z = 0 },
    };

    var i: c_int = 0;
    while (i < rings) : (i += 1) {
        var j: c_int = 0;
        while (j < slices) : (j += 1) {
            vertices[0] = vertices[2]; // Rotate around y axis to set up vertices for next face
            vertices[1] = vertices[3];
            vertices[2] = rotateSlice(vertices[2], cosslice, sinslice);
            vertices[3] = rotateSlice(vertices[3], cosslice, sinslice);

            // Longitude lines
            rlVertex3f(vertices[0].x, vertices[0].y, vertices[0].z);
            rlVertex3f(vertices[1].x, vertices[1].y, vertices[1].z);

            // Latitude lines
            rlVertex3f(vertices[0].x, vertices[0].y, vertices[0].z);
            rlVertex3f(vertices[2].x, vertices[2].y, vertices[2].z);

            // Diagonal lines
            rlVertex3f(vertices[0].x, vertices[0].y, vertices[0].z);
            rlVertex3f(vertices[3].x, vertices[3].y, vertices[3].z);
        }

        vertices[2] = vertices[3]; // Rotate around z axis to set up starting vertices for next ring
        vertices[3] = rotateRing(vertices[3], cosring, sinring);
    }
    rlEnd();
    rlPopMatrix();
}

// Draw a cylinder
// NOTE: It could be also used for pyramid and cone
export fn DrawCylinder(position: Vector3, radiusTop: f32, radiusBottom: f32, height: f32, sides_in: c_int, color: Color) callconv(.c) void {
    var sides = sides_in;
    if (sides < 3) sides = 3;

    const angleStep: f32 = 360.0 / @as(f32, @floatFromInt(sides));

    rlPushMatrix();
    rlTranslatef(position.x, position.y, position.z);

    rlBegin(RL_TRIANGLES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    if (radiusTop > 0) {
        // Draw Body
        var i: c_int = 0;
        while (i < sides) : (i += 1) {
            const fi = @as(f32, @floatFromInt(i));
            const fi1 = @as(f32, @floatFromInt(i + 1));
            rlVertex3f(sinf(DEG2RAD * fi * angleStep) * radiusBottom, 0, cosf(DEG2RAD * fi * angleStep) * radiusBottom); // Bottom Left
            rlVertex3f(sinf(DEG2RAD * fi1 * angleStep) * radiusBottom, 0, cosf(DEG2RAD * fi1 * angleStep) * radiusBottom); // Bottom Right
            rlVertex3f(sinf(DEG2RAD * fi1 * angleStep) * radiusTop, height, cosf(DEG2RAD * fi1 * angleStep) * radiusTop); // Top Right

            rlVertex3f(sinf(DEG2RAD * fi * angleStep) * radiusTop, height, cosf(DEG2RAD * fi * angleStep) * radiusTop); // Top Left
            rlVertex3f(sinf(DEG2RAD * fi * angleStep) * radiusBottom, 0, cosf(DEG2RAD * fi * angleStep) * radiusBottom); // Bottom Left
            rlVertex3f(sinf(DEG2RAD * fi1 * angleStep) * radiusTop, height, cosf(DEG2RAD * fi1 * angleStep) * radiusTop); // Top Right
        }

        // Draw Cap
        i = 0;
        while (i < sides) : (i += 1) {
            const fi = @as(f32, @floatFromInt(i));
            const fi1 = @as(f32, @floatFromInt(i + 1));
            rlVertex3f(0, height, 0);
            rlVertex3f(sinf(DEG2RAD * fi * angleStep) * radiusTop, height, cosf(DEG2RAD * fi * angleStep) * radiusTop);
            rlVertex3f(sinf(DEG2RAD * fi1 * angleStep) * radiusTop, height, cosf(DEG2RAD * fi1 * angleStep) * radiusTop);
        }
    } else {
        // Draw Cone
        var i: c_int = 0;
        while (i < sides) : (i += 1) {
            const fi = @as(f32, @floatFromInt(i));
            const fi1 = @as(f32, @floatFromInt(i + 1));
            rlVertex3f(0, height, 0);
            rlVertex3f(sinf(DEG2RAD * fi * angleStep) * radiusBottom, 0, cosf(DEG2RAD * fi * angleStep) * radiusBottom);
            rlVertex3f(sinf(DEG2RAD * fi1 * angleStep) * radiusBottom, 0, cosf(DEG2RAD * fi1 * angleStep) * radiusBottom);
        }
    }

    // Draw Base
    var i: c_int = 0;
    while (i < sides) : (i += 1) {
        const fi = @as(f32, @floatFromInt(i));
        const fi1 = @as(f32, @floatFromInt(i + 1));
        rlVertex3f(0, 0, 0);
        rlVertex3f(sinf(DEG2RAD * fi1 * angleStep) * radiusBottom, 0, cosf(DEG2RAD * fi1 * angleStep) * radiusBottom);
        rlVertex3f(sinf(DEG2RAD * fi * angleStep) * radiusBottom, 0, cosf(DEG2RAD * fi * angleStep) * radiusBottom);
    }
    rlEnd();
    rlPopMatrix();
}

// Draw a cylinder with base at startPos and top at endPos
export fn DrawCylinderEx(startPos: Vector3, endPos: Vector3, startRadius: f32, endRadius: f32, sides_in: c_int, color: Color) callconv(.c) void {
    var sides = sides_in;
    if (sides < 3) sides = 3;

    const direction = Vector3{ .x = endPos.x - startPos.x, .y = endPos.y - startPos.y, .z = endPos.z - startPos.z };
    if ((direction.x == 0) and (direction.y == 0) and (direction.z == 0)) return; // Security check

    const b1 = Vector3Normalize(Vector3Perpendicular(direction));
    const b2 = Vector3Normalize(Vector3CrossProduct(b1, direction));

    const baseAngle: f32 = (2.0 * PI) / @as(f32, @floatFromInt(sides));

    rlBegin(RL_TRIANGLES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    var i: c_int = 0;
    while (i < sides) : (i += 1) {
        const fi = @as(f32, @floatFromInt(i));
        const fi1 = @as(f32, @floatFromInt(i + 1));
        const s1 = sinf(baseAngle * fi) * startRadius;
        const c1 = cosf(baseAngle * fi) * startRadius;
        const w1 = Vector3{ .x = startPos.x + s1 * b1.x + c1 * b2.x, .y = startPos.y + s1 * b1.y + c1 * b2.y, .z = startPos.z + s1 * b1.z + c1 * b2.z };
        const s2 = sinf(baseAngle * fi1) * startRadius;
        const c2 = cosf(baseAngle * fi1) * startRadius;
        const w2 = Vector3{ .x = startPos.x + s2 * b1.x + c2 * b2.x, .y = startPos.y + s2 * b1.y + c2 * b2.y, .z = startPos.z + s2 * b1.z + c2 * b2.z };
        const s3 = sinf(baseAngle * fi) * endRadius;
        const c3 = cosf(baseAngle * fi) * endRadius;
        const w3 = Vector3{ .x = endPos.x + s3 * b1.x + c3 * b2.x, .y = endPos.y + s3 * b1.y + c3 * b2.y, .z = endPos.z + s3 * b1.z + c3 * b2.z };
        const s4 = sinf(baseAngle * fi1) * endRadius;
        const c4 = cosf(baseAngle * fi1) * endRadius;
        const w4 = Vector3{ .x = endPos.x + s4 * b1.x + c4 * b2.x, .y = endPos.y + s4 * b1.y + c4 * b2.y, .z = endPos.z + s4 * b1.z + c4 * b2.z };

        if (startRadius > 0) {
            rlVertex3f(startPos.x, startPos.y, startPos.z);
            rlVertex3f(w2.x, w2.y, w2.z);
            rlVertex3f(w1.x, w1.y, w1.z);
        }

        rlVertex3f(w1.x, w1.y, w1.z);
        rlVertex3f(w2.x, w2.y, w2.z);
        rlVertex3f(w3.x, w3.y, w3.z);

        rlVertex3f(w2.x, w2.y, w2.z);
        rlVertex3f(w4.x, w4.y, w4.z);
        rlVertex3f(w3.x, w3.y, w3.z);

        if (endRadius > 0) {
            rlVertex3f(endPos.x, endPos.y, endPos.z);
            rlVertex3f(w3.x, w3.y, w3.z);
            rlVertex3f(w4.x, w4.y, w4.z);
        }
    }
    rlEnd();
}

// Draw a wired cylinder
export fn DrawCylinderWires(position: Vector3, radiusTop: f32, radiusBottom: f32, height: f32, sides_in: c_int, color: Color) callconv(.c) void {
    var sides = sides_in;
    if (sides < 3) sides = 3;

    const angleStep: f32 = 360.0 / @as(f32, @floatFromInt(sides));

    rlPushMatrix();
    rlTranslatef(position.x, position.y, position.z);

    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    var i: c_int = 0;
    while (i < sides) : (i += 1) {
        const fi = @as(f32, @floatFromInt(i));
        const fi1 = @as(f32, @floatFromInt(i + 1));
        rlVertex3f(sinf(DEG2RAD * fi * angleStep) * radiusBottom, 0, cosf(DEG2RAD * fi * angleStep) * radiusBottom);
        rlVertex3f(sinf(DEG2RAD * fi1 * angleStep) * radiusBottom, 0, cosf(DEG2RAD * fi1 * angleStep) * radiusBottom);

        rlVertex3f(sinf(DEG2RAD * fi1 * angleStep) * radiusBottom, 0, cosf(DEG2RAD * fi1 * angleStep) * radiusBottom);
        rlVertex3f(sinf(DEG2RAD * fi1 * angleStep) * radiusTop, height, cosf(DEG2RAD * fi1 * angleStep) * radiusTop);

        rlVertex3f(sinf(DEG2RAD * fi1 * angleStep) * radiusTop, height, cosf(DEG2RAD * fi1 * angleStep) * radiusTop);
        rlVertex3f(sinf(DEG2RAD * fi * angleStep) * radiusTop, height, cosf(DEG2RAD * fi * angleStep) * radiusTop);

        rlVertex3f(sinf(DEG2RAD * fi * angleStep) * radiusTop, height, cosf(DEG2RAD * fi * angleStep) * radiusTop);
        rlVertex3f(sinf(DEG2RAD * fi * angleStep) * radiusBottom, 0, cosf(DEG2RAD * fi * angleStep) * radiusBottom);
    }
    rlEnd();
    rlPopMatrix();
}

// Draw a wired cylinder with base at startPos and top at endPos
export fn DrawCylinderWiresEx(startPos: Vector3, endPos: Vector3, startRadius: f32, endRadius: f32, slices_in: c_int, color: Color) callconv(.c) void {
    var slices = slices_in;
    if (slices < 3) slices = 3;

    const direction = Vector3{ .x = endPos.x - startPos.x, .y = endPos.y - startPos.y, .z = endPos.z - startPos.z };
    if ((direction.x == 0) and (direction.y == 0) and (direction.z == 0)) return; // Security check

    const b1 = Vector3Normalize(Vector3Perpendicular(direction));
    const b2 = Vector3Normalize(Vector3CrossProduct(b1, direction));

    const baseAngle: f32 = (2.0 * PI) / @as(f32, @floatFromInt(slices));

    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    var i: c_int = 0;
    while (i < slices) : (i += 1) {
        const fi = @as(f32, @floatFromInt(i));
        const fi1 = @as(f32, @floatFromInt(i + 1));
        const s1 = sinf(baseAngle * fi) * startRadius;
        const c1 = cosf(baseAngle * fi) * startRadius;
        const w1 = Vector3{ .x = startPos.x + s1 * b1.x + c1 * b2.x, .y = startPos.y + s1 * b1.y + c1 * b2.y, .z = startPos.z + s1 * b1.z + c1 * b2.z };
        const s2 = sinf(baseAngle * fi1) * startRadius;
        const c2 = cosf(baseAngle * fi1) * startRadius;
        const w2 = Vector3{ .x = startPos.x + s2 * b1.x + c2 * b2.x, .y = startPos.y + s2 * b1.y + c2 * b2.y, .z = startPos.z + s2 * b1.z + c2 * b2.z };
        const s3 = sinf(baseAngle * fi) * endRadius;
        const c3 = cosf(baseAngle * fi) * endRadius;
        const w3 = Vector3{ .x = endPos.x + s3 * b1.x + c3 * b2.x, .y = endPos.y + s3 * b1.y + c3 * b2.y, .z = endPos.z + s3 * b1.z + c3 * b2.z };
        const s4 = sinf(baseAngle * fi1) * endRadius;
        const c4 = cosf(baseAngle * fi1) * endRadius;
        const w4 = Vector3{ .x = endPos.x + s4 * b1.x + c4 * b2.x, .y = endPos.y + s4 * b1.y + c4 * b2.y, .z = endPos.z + s4 * b1.z + c4 * b2.z };

        rlVertex3f(w1.x, w1.y, w1.z);
        rlVertex3f(w2.x, w2.y, w2.z);

        rlVertex3f(w1.x, w1.y, w1.z);
        rlVertex3f(w3.x, w3.y, w3.z);

        rlVertex3f(w3.x, w3.y, w3.z);
        rlVertex3f(w4.x, w4.y, w4.z);
    }
    rlEnd();
}

// Draw a capsule with the center of its sphere caps at startPos and endPos
export fn DrawCapsule(startPos: Vector3, endPos: Vector3, radius: f32, rings_in: c_int, slices_in: c_int, color: Color) callconv(.c) void {
    var slices = slices_in;
    var rings = rings_in;
    if (slices < 3) slices = 3;
    if (rings < 1) rings = 1;
    var direction = Vector3{ .x = endPos.x - startPos.x, .y = endPos.y - startPos.y, .z = endPos.z - startPos.z };

    const sphereCase = (direction.x == 0) and (direction.y == 0) and (direction.z == 0);
    if (sphereCase) direction = .{ .x = 0.0, .y = 1.0, .z = 0.0 };

    var b0 = Vector3Normalize(direction);
    const b1 = Vector3Normalize(Vector3Perpendicular(direction));
    const b2 = Vector3Normalize(Vector3CrossProduct(b1, direction));
    var capCenter = endPos;

    const baseSliceAngle: f32 = (2.0 * PI) / @as(f32, @floatFromInt(slices));
    const baseRingAngle: f32 = PI * 0.5 / @as(f32, @floatFromInt(rings));

    rlBegin(RL_TRIANGLES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    // render both caps
    var c: c_int = 0;
    while (c < 2) : (c += 1) {
        var i: c_int = 0;
        while (i < rings) : (i += 1) {
            var j: c_int = 0;
            while (j < slices) : (j += 1) {
                const fj0 = @as(f32, @floatFromInt(j + 0));
                const fj1 = @as(f32, @floatFromInt(j + 1));
                const fi0 = @as(f32, @floatFromInt(i + 0));
                const fi1 = @as(f32, @floatFromInt(i + 1));

                const ringSin1 = sinf(baseSliceAngle * fj0) * cosf(baseRingAngle * fi0);
                const ringCos1 = cosf(baseSliceAngle * fj0) * cosf(baseRingAngle * fi0);
                const w1 = Vector3{
                    .x = capCenter.x + (sinf(baseRingAngle * fi0) * b0.x + ringSin1 * b1.x + ringCos1 * b2.x) * radius,
                    .y = capCenter.y + (sinf(baseRingAngle * fi0) * b0.y + ringSin1 * b1.y + ringCos1 * b2.y) * radius,
                    .z = capCenter.z + (sinf(baseRingAngle * fi0) * b0.z + ringSin1 * b1.z + ringCos1 * b2.z) * radius,
                };
                const ringSin2 = sinf(baseSliceAngle * fj1) * cosf(baseRingAngle * fi0);
                const ringCos2 = cosf(baseSliceAngle * fj1) * cosf(baseRingAngle * fi0);
                const w2 = Vector3{
                    .x = capCenter.x + (sinf(baseRingAngle * fi0) * b0.x + ringSin2 * b1.x + ringCos2 * b2.x) * radius,
                    .y = capCenter.y + (sinf(baseRingAngle * fi0) * b0.y + ringSin2 * b1.y + ringCos2 * b2.y) * radius,
                    .z = capCenter.z + (sinf(baseRingAngle * fi0) * b0.z + ringSin2 * b1.z + ringCos2 * b2.z) * radius,
                };

                const ringSin3 = sinf(baseSliceAngle * fj0) * cosf(baseRingAngle * fi1);
                const ringCos3 = cosf(baseSliceAngle * fj0) * cosf(baseRingAngle * fi1);
                const w3 = Vector3{
                    .x = capCenter.x + (sinf(baseRingAngle * fi1) * b0.x + ringSin3 * b1.x + ringCos3 * b2.x) * radius,
                    .y = capCenter.y + (sinf(baseRingAngle * fi1) * b0.y + ringSin3 * b1.y + ringCos3 * b2.y) * radius,
                    .z = capCenter.z + (sinf(baseRingAngle * fi1) * b0.z + ringSin3 * b1.z + ringCos3 * b2.z) * radius,
                };
                const ringSin4 = sinf(baseSliceAngle * fj1) * cosf(baseRingAngle * fi1);
                const ringCos4 = cosf(baseSliceAngle * fj1) * cosf(baseRingAngle * fi1);
                const w4 = Vector3{
                    .x = capCenter.x + (sinf(baseRingAngle * fi1) * b0.x + ringSin4 * b1.x + ringCos4 * b2.x) * radius,
                    .y = capCenter.y + (sinf(baseRingAngle * fi1) * b0.y + ringSin4 * b1.y + ringCos4 * b2.y) * radius,
                    .z = capCenter.z + (sinf(baseRingAngle * fi1) * b0.z + ringSin4 * b1.z + ringCos4 * b2.z) * radius,
                };

                if (c == 0) {
                    rlVertex3f(w1.x, w1.y, w1.z);
                    rlVertex3f(w2.x, w2.y, w2.z);
                    rlVertex3f(w3.x, w3.y, w3.z);

                    rlVertex3f(w2.x, w2.y, w2.z);
                    rlVertex3f(w4.x, w4.y, w4.z);
                    rlVertex3f(w3.x, w3.y, w3.z);
                } else {
                    rlVertex3f(w1.x, w1.y, w1.z);
                    rlVertex3f(w3.x, w3.y, w3.z);
                    rlVertex3f(w2.x, w2.y, w2.z);

                    rlVertex3f(w2.x, w2.y, w2.z);
                    rlVertex3f(w3.x, w3.y, w3.z);
                    rlVertex3f(w4.x, w4.y, w4.z);
                }
            }
        }
        capCenter = startPos;
        b0 = Vector3Scale(b0, -1.0);
    }
    // render middle
    if (!sphereCase) {
        var j: c_int = 0;
        while (j < slices) : (j += 1) {
            const fj0 = @as(f32, @floatFromInt(j + 0));
            const fj1 = @as(f32, @floatFromInt(j + 1));
            const ringSin1 = sinf(baseSliceAngle * fj0) * radius;
            const ringCos1 = cosf(baseSliceAngle * fj0) * radius;
            const w1 = Vector3{
                .x = startPos.x + ringSin1 * b1.x + ringCos1 * b2.x,
                .y = startPos.y + ringSin1 * b1.y + ringCos1 * b2.y,
                .z = startPos.z + ringSin1 * b1.z + ringCos1 * b2.z,
            };
            const ringSin2 = sinf(baseSliceAngle * fj1) * radius;
            const ringCos2 = cosf(baseSliceAngle * fj1) * radius;
            const w2 = Vector3{
                .x = startPos.x + ringSin2 * b1.x + ringCos2 * b2.x,
                .y = startPos.y + ringSin2 * b1.y + ringCos2 * b2.y,
                .z = startPos.z + ringSin2 * b1.z + ringCos2 * b2.z,
            };

            const ringSin3 = sinf(baseSliceAngle * fj0) * radius;
            const ringCos3 = cosf(baseSliceAngle * fj0) * radius;
            const w3 = Vector3{
                .x = endPos.x + ringSin3 * b1.x + ringCos3 * b2.x,
                .y = endPos.y + ringSin3 * b1.y + ringCos3 * b2.y,
                .z = endPos.z + ringSin3 * b1.z + ringCos3 * b2.z,
            };
            const ringSin4 = sinf(baseSliceAngle * fj1) * radius;
            const ringCos4 = cosf(baseSliceAngle * fj1) * radius;
            const w4 = Vector3{
                .x = endPos.x + ringSin4 * b1.x + ringCos4 * b2.x,
                .y = endPos.y + ringSin4 * b1.y + ringCos4 * b2.y,
                .z = endPos.z + ringSin4 * b1.z + ringCos4 * b2.z,
            };

            rlVertex3f(w1.x, w1.y, w1.z);
            rlVertex3f(w2.x, w2.y, w2.z);
            rlVertex3f(w3.x, w3.y, w3.z);

            rlVertex3f(w2.x, w2.y, w2.z);
            rlVertex3f(w4.x, w4.y, w4.z);
            rlVertex3f(w3.x, w3.y, w3.z);
        }
    }
    rlEnd();
}

// Draw capsule wires with the center of its sphere caps at startPos and endPos
export fn DrawCapsuleWires(startPos: Vector3, endPos: Vector3, radius: f32, rings_in: c_int, slices_in: c_int, color: Color) callconv(.c) void {
    var slices = slices_in;
    var rings = rings_in;
    if (slices < 3) slices = 3;
    if (rings < 1) rings = 1;
    var direction = Vector3{ .x = endPos.x - startPos.x, .y = endPos.y - startPos.y, .z = endPos.z - startPos.z };

    const sphereCase = (direction.x == 0) and (direction.y == 0) and (direction.z == 0);
    if (sphereCase) direction = .{ .x = 0.0, .y = 1.0, .z = 0.0 };

    var b0 = Vector3Normalize(direction);
    const b1 = Vector3Normalize(Vector3Perpendicular(direction));
    const b2 = Vector3Normalize(Vector3CrossProduct(b1, direction));
    var capCenter = endPos;

    const baseSliceAngle: f32 = (2.0 * PI) / @as(f32, @floatFromInt(slices));
    const baseRingAngle: f32 = PI * 0.5 / @as(f32, @floatFromInt(rings));

    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    var c: c_int = 0;
    while (c < 2) : (c += 1) {
        var i: c_int = 0;
        while (i < rings) : (i += 1) {
            var j: c_int = 0;
            while (j < slices) : (j += 1) {
                const fj0 = @as(f32, @floatFromInt(j + 0));
                const fj1 = @as(f32, @floatFromInt(j + 1));
                const fi0 = @as(f32, @floatFromInt(i + 0));
                const fi1 = @as(f32, @floatFromInt(i + 1));

                const ringSin1 = sinf(baseSliceAngle * fj0) * cosf(baseRingAngle * fi0);
                const ringCos1 = cosf(baseSliceAngle * fj0) * cosf(baseRingAngle * fi0);
                const w1 = Vector3{
                    .x = capCenter.x + (sinf(baseRingAngle * fi0) * b0.x + ringSin1 * b1.x + ringCos1 * b2.x) * radius,
                    .y = capCenter.y + (sinf(baseRingAngle * fi0) * b0.y + ringSin1 * b1.y + ringCos1 * b2.y) * radius,
                    .z = capCenter.z + (sinf(baseRingAngle * fi0) * b0.z + ringSin1 * b1.z + ringCos1 * b2.z) * radius,
                };
                const ringSin2 = sinf(baseSliceAngle * fj1) * cosf(baseRingAngle * fi0);
                const ringCos2 = cosf(baseSliceAngle * fj1) * cosf(baseRingAngle * fi0);
                const w2 = Vector3{
                    .x = capCenter.x + (sinf(baseRingAngle * fi0) * b0.x + ringSin2 * b1.x + ringCos2 * b2.x) * radius,
                    .y = capCenter.y + (sinf(baseRingAngle * fi0) * b0.y + ringSin2 * b1.y + ringCos2 * b2.y) * radius,
                    .z = capCenter.z + (sinf(baseRingAngle * fi0) * b0.z + ringSin2 * b1.z + ringCos2 * b2.z) * radius,
                };

                const ringSin3 = sinf(baseSliceAngle * fj0) * cosf(baseRingAngle * fi1);
                const ringCos3 = cosf(baseSliceAngle * fj0) * cosf(baseRingAngle * fi1);
                const w3 = Vector3{
                    .x = capCenter.x + (sinf(baseRingAngle * fi1) * b0.x + ringSin3 * b1.x + ringCos3 * b2.x) * radius,
                    .y = capCenter.y + (sinf(baseRingAngle * fi1) * b0.y + ringSin3 * b1.y + ringCos3 * b2.y) * radius,
                    .z = capCenter.z + (sinf(baseRingAngle * fi1) * b0.z + ringSin3 * b1.z + ringCos3 * b2.z) * radius,
                };
                const ringSin4 = sinf(baseSliceAngle * fj1) * cosf(baseRingAngle * fi1);
                const ringCos4 = cosf(baseSliceAngle * fj1) * cosf(baseRingAngle * fi1);
                const w4 = Vector3{
                    .x = capCenter.x + (sinf(baseRingAngle * fi1) * b0.x + ringSin4 * b1.x + ringCos4 * b2.x) * radius,
                    .y = capCenter.y + (sinf(baseRingAngle * fi1) * b0.y + ringSin4 * b1.y + ringCos4 * b2.y) * radius,
                    .z = capCenter.z + (sinf(baseRingAngle * fi1) * b0.z + ringSin4 * b1.z + ringCos4 * b2.z) * radius,
                };

                rlVertex3f(w1.x, w1.y, w1.z);
                rlVertex3f(w2.x, w2.y, w2.z);

                rlVertex3f(w2.x, w2.y, w2.z);
                rlVertex3f(w3.x, w3.y, w3.z);

                rlVertex3f(w1.x, w1.y, w1.z);
                rlVertex3f(w3.x, w3.y, w3.z);

                rlVertex3f(w2.x, w2.y, w2.z);
                rlVertex3f(w4.x, w4.y, w4.z);

                rlVertex3f(w3.x, w3.y, w3.z);
                rlVertex3f(w4.x, w4.y, w4.z);
            }
        }
        capCenter = startPos;
        b0 = Vector3Scale(b0, -1.0);
    }
    // render middle
    if (!sphereCase) {
        var j: c_int = 0;
        while (j < slices) : (j += 1) {
            const fj0 = @as(f32, @floatFromInt(j + 0));
            const fj1 = @as(f32, @floatFromInt(j + 1));
            const ringSin1 = sinf(baseSliceAngle * fj0) * radius;
            const ringCos1 = cosf(baseSliceAngle * fj0) * radius;
            const w1 = Vector3{
                .x = startPos.x + ringSin1 * b1.x + ringCos1 * b2.x,
                .y = startPos.y + ringSin1 * b1.y + ringCos1 * b2.y,
                .z = startPos.z + ringSin1 * b1.z + ringCos1 * b2.z,
            };
            const ringSin2 = sinf(baseSliceAngle * fj1) * radius;
            const ringCos2 = cosf(baseSliceAngle * fj1) * radius;
            const w2 = Vector3{
                .x = startPos.x + ringSin2 * b1.x + ringCos2 * b2.x,
                .y = startPos.y + ringSin2 * b1.y + ringCos2 * b2.y,
                .z = startPos.z + ringSin2 * b1.z + ringCos2 * b2.z,
            };

            const ringSin3 = sinf(baseSliceAngle * fj0) * radius;
            const ringCos3 = cosf(baseSliceAngle * fj0) * radius;
            const w3 = Vector3{
                .x = endPos.x + ringSin3 * b1.x + ringCos3 * b2.x,
                .y = endPos.y + ringSin3 * b1.y + ringCos3 * b2.y,
                .z = endPos.z + ringSin3 * b1.z + ringCos3 * b2.z,
            };
            const ringSin4 = sinf(baseSliceAngle * fj1) * radius;
            const ringCos4 = cosf(baseSliceAngle * fj1) * radius;
            const w4 = Vector3{
                .x = endPos.x + ringSin4 * b1.x + ringCos4 * b2.x,
                .y = endPos.y + ringSin4 * b1.y + ringCos4 * b2.y,
                .z = endPos.z + ringSin4 * b1.z + ringCos4 * b2.z,
            };

            rlVertex3f(w1.x, w1.y, w1.z);
            rlVertex3f(w3.x, w3.y, w3.z);

            rlVertex3f(w2.x, w2.y, w2.z);
            rlVertex3f(w4.x, w4.y, w4.z);

            rlVertex3f(w2.x, w2.y, w2.z);
            rlVertex3f(w3.x, w3.y, w3.z);
        }
    }
    rlEnd();
}

// Draw a plane
export fn DrawPlane(centerPos: Vector3, size: Vector2, color: Color) callconv(.c) void {
    rlPushMatrix();
    rlTranslatef(centerPos.x, centerPos.y, centerPos.z);
    rlScalef(size.x, 1.0, size.y);

    rlBegin(RL_QUADS);
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlNormal3f(0.0, 1.0, 0.0);

    rlVertex3f(-0.5, 0.0, -0.5);
    rlVertex3f(-0.5, 0.0, 0.5);
    rlVertex3f(0.5, 0.0, 0.5);
    rlVertex3f(0.5, 0.0, -0.5);
    rlEnd();
    rlPopMatrix();
}

// Draw a ray line
export fn DrawRay(ray: Ray, color: Color) callconv(.c) void {
    const scale: f32 = 10000;

    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlColor4ub(color.r, color.g, color.b, color.a);

    rlVertex3f(ray.position.x, ray.position.y, ray.position.z);
    rlVertex3f(ray.position.x + ray.direction.x * scale, ray.position.y + ray.direction.y * scale, ray.position.z + ray.direction.z * scale);
    rlEnd();
}

// Draw a grid centered at (0, 0, 0)
export fn DrawGrid(slices: c_int, spacing: f32) callconv(.c) void {
    const halfSlices = @divTrunc(slices, 2);

    rlBegin(RL_LINES);
    var i: c_int = -halfSlices;
    while (i <= halfSlices) : (i += 1) {
        if (i == 0) {
            rlColor3f(0.5, 0.5, 0.5);
        } else {
            rlColor3f(0.75, 0.75, 0.75);
        }

        const fi = @as(f32, @floatFromInt(i));
        const fh = @as(f32, @floatFromInt(halfSlices));
        rlVertex3f(fi * spacing, 0.0, -fh * spacing);
        rlVertex3f(fi * spacing, 0.0, fh * spacing);

        rlVertex3f(-fh * spacing, 0.0, fi * spacing);
        rlVertex3f(fh * spacing, 0.0, fi * spacing);
    }
    rlEnd();
}

//----------------------------------------------------------------------------------
// Third-party single-file-lib externs (provided by src/c/rmodels_impl.c).
//----------------------------------------------------------------------------------

// ---- par_shapes ----
const par_shapes_mesh = extern struct {
    points: ?[*]f32,
    npoints: c_int,
    triangles: ?[*]c_ushort,
    ntriangles: c_int,
    normals: ?[*]f32,
    tcoords: ?[*]f32,
};
// NOTE: par_shapes never returns null: it does not check its own allocations
extern fn par_shapes_free_mesh(mesh: *par_shapes_mesh) void;
extern fn par_shapes_create_cylinder(slices: c_int, stacks: c_int) *par_shapes_mesh;
extern fn par_shapes_create_cone(slices: c_int, stacks: c_int) *par_shapes_mesh;
extern fn par_shapes_create_torus(slices: c_int, stacks: c_int, radius: f32) *par_shapes_mesh;
extern fn par_shapes_create_parametric_sphere(slices: c_int, stacks: c_int) *par_shapes_mesh;
extern fn par_shapes_create_trefoil_knot(slices: c_int, stacks: c_int, radius: f32) *par_shapes_mesh;
extern fn par_shapes_create_hemisphere(slices: c_int, stacks: c_int) *par_shapes_mesh;
extern fn par_shapes_create_disk(radius: f32, slices: c_int, center: *const [3]f32, normal: *const [3]f32) *par_shapes_mesh;
extern fn par_shapes_set_epsilon_degenerate_sphere(epsilon: f64) void;
extern fn par_shapes_translate(mesh: *par_shapes_mesh, x: f32, y: f32, z: f32) void;
extern fn par_shapes_rotate(mesh: *par_shapes_mesh, radians: f32, axis: *const [3]f32) void;
extern fn par_shapes_scale(mesh: *par_shapes_mesh, x: f32, y: f32, z: f32) void;
extern fn par_shapes_merge_and_free(dst: *par_shapes_mesh, src: *par_shapes_mesh) void;

// ---- tinyobj ----
const tinyobj_vertex_index_t = extern struct { v_idx: c_int, vt_idx: c_int, vn_idx: c_int };
const tinyobj_attrib_t = extern struct {
    num_vertices: c_uint,
    num_normals: c_uint,
    num_texcoords: c_uint,
    num_faces: c_uint,
    num_face_num_verts: c_uint,
    pad0: c_int,
    vertices: ?[*]f32,
    normals: ?[*]f32,
    texcoords: ?[*]f32,
    faces: ?[*]tinyobj_vertex_index_t,
    face_num_verts: ?[*]c_int,
    material_ids: ?[*]c_int,
};
const tinyobj_shape_t = extern struct {
    name: ?[*:0]u8,
    face_offset: c_uint,
    length: c_uint,
};
const tinyobj_material_t = extern struct {
    name: ?[*:0]u8,
    ambient: [3]f32,
    diffuse: [3]f32,
    specular: [3]f32,
    transmittance: [3]f32,
    emission: [3]f32,
    shininess: f32,
    ior: f32,
    dissolve: f32,
    illum: c_int,
    pad0: c_int,
    ambient_texname: ?[*:0]u8,
    diffuse_texname: ?[*:0]u8,
    specular_texname: ?[*:0]u8,
    specular_highlight_texname: ?[*:0]u8,
    bump_texname: ?[*:0]u8,
    displacement_texname: ?[*:0]u8,
    alpha_texname: ?[*:0]u8,
};
const TINYOBJ_FLAG_TRIANGULATE: c_uint = 1 << 0;
const TINYOBJ_SUCCESS: c_int = 0;
extern fn tinyobj_parse_obj(attrib: *tinyobj_attrib_t, shapes: *?[*]tinyobj_shape_t, num_shapes: *c_uint, materials: *?[*]tinyobj_material_t, num_materials: *c_uint, buf: [*]const u8, len: c_uint, flags: c_uint) c_int;
extern fn tinyobj_parse_mtl_file(materials_out: *?[*]tinyobj_material_t, num_materials_out: *c_uint, filename: [*c]const u8) c_int;
extern fn tinyobj_attrib_free(attrib: *tinyobj_attrib_t) void;
extern fn tinyobj_shapes_free(shapes: ?[*]tinyobj_shape_t, num_shapes: c_uint) void;
extern fn tinyobj_materials_free(materials: ?[*]tinyobj_material_t, num_materials: c_uint) void;

// ---- cgltf ----
const cgltf_size = usize;
const cgltf_float = f32;
const cgltf_int = c_int;
const cgltf_uint = c_uint;
const cgltf_bool = c_int;

const cgltf_file_type = c_int;
const cgltf_file_type_invalid: c_int = 0;
const cgltf_file_type_gltf: c_int = 1;
const cgltf_file_type_glb: c_int = 2;

const cgltf_result = c_int;
const cgltf_result_success: c_int = 0;
const cgltf_result_io_error: c_int = 7;

const cgltf_attribute_type = c_int;
const cgltf_attribute_type_position: c_int = 1;
const cgltf_attribute_type_normal: c_int = 2;
const cgltf_attribute_type_tangent: c_int = 3;
const cgltf_attribute_type_texcoord: c_int = 4;
const cgltf_attribute_type_color: c_int = 5;
const cgltf_attribute_type_joints: c_int = 6;
const cgltf_attribute_type_weights: c_int = 7;

const cgltf_component_type = c_int;
const cgltf_component_type_r_8: c_int = 1;
const cgltf_component_type_r_8u: c_int = 2;
const cgltf_component_type_r_16: c_int = 3;
const cgltf_component_type_r_16u: c_int = 4;
const cgltf_component_type_r_32u: c_int = 5;
const cgltf_component_type_r_32f: c_int = 6;

const cgltf_type = c_int;
const cgltf_type_vec2: c_int = 2;
const cgltf_type_vec3: c_int = 3;
const cgltf_type_vec4: c_int = 4;

const cgltf_primitive_type = c_int;
const cgltf_primitive_type_triangles: c_int = 5;

const cgltf_animation_path_type = c_int;
const cgltf_animation_path_type_translation: c_int = 1;
const cgltf_animation_path_type_rotation: c_int = 2;
const cgltf_animation_path_type_scale: c_int = 3;

const cgltf_interpolation_type = c_int;
const cgltf_interpolation_type_linear: c_int = 0;
const cgltf_interpolation_type_step: c_int = 1;
const cgltf_interpolation_type_cubic_spline: c_int = 2;
const cgltf_interpolation_type_max_enum: c_int = 3;

const cgltf_data_free_method = c_int;
const cgltf_meshopt_compression_mode = c_int;
const cgltf_meshopt_compression_filter = c_int;
const cgltf_alpha_mode = c_int;
const cgltf_buffer_view_type = c_int;
const cgltf_filter_type = c_int;
const cgltf_wrap_mode = c_int;

const cgltf_extras = extern struct {
    start_offset: cgltf_size,
    end_offset: cgltf_size,
    data: ?[*:0]u8,
};
const cgltf_extension = extern struct {
    name: ?[*:0]u8,
    data: ?[*:0]u8,
};
const cgltf_memory_options = extern struct {
    alloc_func: ?*const fn (?*anyopaque, cgltf_size) callconv(.c) ?*anyopaque,
    free_func: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
    user_data: ?*anyopaque,
};
const cgltf_file_options = extern struct {
    read: ?*const fn (?*const cgltf_memory_options, ?*const cgltf_file_options, [*:0]const u8, *cgltf_size, *?*anyopaque) callconv(.c) cgltf_result,
    release: ?*const fn (?*const cgltf_memory_options, ?*const cgltf_file_options, ?*anyopaque, cgltf_size) callconv(.c) void,
    user_data: ?*anyopaque,
};
const cgltf_options = extern struct {
    type: cgltf_file_type,
    json_token_count: cgltf_size,
    memory: cgltf_memory_options,
    file: cgltf_file_options,
};
const cgltf_buffer = extern struct {
    name: ?[*:0]u8,
    size: cgltf_size,
    uri: ?[*:0]u8,
    data: ?*anyopaque,
    data_free_method: cgltf_data_free_method,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_meshopt_compression = extern struct {
    buffer: ?*cgltf_buffer,
    offset: cgltf_size,
    size: cgltf_size,
    stride: cgltf_size,
    count: cgltf_size,
    mode: cgltf_meshopt_compression_mode,
    filter: cgltf_meshopt_compression_filter,
    is_khr: cgltf_bool,
};
const cgltf_buffer_view = extern struct {
    name: ?[*:0]u8,
    buffer: ?*cgltf_buffer,
    offset: cgltf_size,
    size: cgltf_size,
    stride: cgltf_size,
    type: cgltf_buffer_view_type,
    data: ?*anyopaque,
    has_meshopt_compression: cgltf_bool,
    meshopt_compression: cgltf_meshopt_compression,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_accessor_sparse = extern struct {
    count: cgltf_size,
    indices_buffer_view: ?*cgltf_buffer_view,
    indices_byte_offset: cgltf_size,
    indices_component_type: cgltf_component_type,
    values_buffer_view: ?*cgltf_buffer_view,
    values_byte_offset: cgltf_size,
};
const cgltf_accessor = extern struct {
    name: ?[*:0]u8,
    component_type: cgltf_component_type,
    normalized: cgltf_bool,
    type: cgltf_type,
    offset: cgltf_size,
    count: cgltf_size,
    stride: cgltf_size,
    buffer_view: ?*cgltf_buffer_view,
    has_min: cgltf_bool,
    min: [16]cgltf_float,
    has_max: cgltf_bool,
    max: [16]cgltf_float,
    is_sparse: cgltf_bool,
    sparse: cgltf_accessor_sparse,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_attribute = extern struct {
    name: ?[*:0]u8,
    type: cgltf_attribute_type,
    index: cgltf_int,
    data: *cgltf_accessor,
};
const cgltf_image = extern struct {
    name: ?[*:0]u8,
    uri: ?[*:0]u8,
    buffer_view: ?*cgltf_buffer_view,
    mime_type: ?[*:0]u8,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_sampler = extern struct {
    name: ?[*:0]u8,
    mag_filter: cgltf_filter_type,
    min_filter: cgltf_filter_type,
    wrap_s: cgltf_wrap_mode,
    wrap_t: cgltf_wrap_mode,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_texture = extern struct {
    name: ?[*:0]u8,
    image: ?*cgltf_image,
    sampler: ?*cgltf_sampler,
    has_basisu: cgltf_bool,
    basisu_image: ?*cgltf_image,
    has_webp: cgltf_bool,
    webp_image: ?*cgltf_image,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_texture_transform = extern struct {
    offset: [2]cgltf_float,
    rotation: cgltf_float,
    scale: [2]cgltf_float,
    has_texcoord: cgltf_bool,
    texcoord: cgltf_int,
};
const cgltf_texture_view = extern struct {
    texture: ?*cgltf_texture,
    texcoord: cgltf_int,
    scale: cgltf_float,
    has_transform: cgltf_bool,
    transform: cgltf_texture_transform,
};
const cgltf_pbr_metallic_roughness = extern struct {
    base_color_texture: cgltf_texture_view,
    metallic_roughness_texture: cgltf_texture_view,
    base_color_factor: [4]cgltf_float,
    metallic_factor: cgltf_float,
    roughness_factor: cgltf_float,
};
const cgltf_pbr_specular_glossiness = extern struct {
    diffuse_texture: cgltf_texture_view,
    specular_glossiness_texture: cgltf_texture_view,
    diffuse_factor: [4]cgltf_float,
    specular_factor: [3]cgltf_float,
    glossiness_factor: cgltf_float,
};
const cgltf_clearcoat = extern struct {
    clearcoat_texture: cgltf_texture_view,
    clearcoat_roughness_texture: cgltf_texture_view,
    clearcoat_normal_texture: cgltf_texture_view,
    clearcoat_factor: cgltf_float,
    clearcoat_roughness_factor: cgltf_float,
};
const cgltf_transmission = extern struct {
    transmission_texture: cgltf_texture_view,
    transmission_factor: cgltf_float,
};
const cgltf_ior = extern struct {
    ior: cgltf_float,
};
const cgltf_specular = extern struct {
    specular_texture: cgltf_texture_view,
    specular_color_texture: cgltf_texture_view,
    specular_color_factor: [3]cgltf_float,
    specular_factor: cgltf_float,
};
const cgltf_volume = extern struct {
    thickness_texture: cgltf_texture_view,
    thickness_factor: cgltf_float,
    attenuation_color: [3]cgltf_float,
    attenuation_distance: cgltf_float,
};
const cgltf_sheen = extern struct {
    sheen_color_texture: cgltf_texture_view,
    sheen_color_factor: [3]cgltf_float,
    sheen_roughness_texture: cgltf_texture_view,
    sheen_roughness_factor: cgltf_float,
};
const cgltf_emissive_strength = extern struct {
    emissive_strength: cgltf_float,
};
const cgltf_iridescence = extern struct {
    iridescence_factor: cgltf_float,
    iridescence_texture: cgltf_texture_view,
    iridescence_ior: cgltf_float,
    iridescence_thickness_min: cgltf_float,
    iridescence_thickness_max: cgltf_float,
    iridescence_thickness_texture: cgltf_texture_view,
};
const cgltf_diffuse_transmission = extern struct {
    diffuse_transmission_texture: cgltf_texture_view,
    diffuse_transmission_factor: cgltf_float,
    diffuse_transmission_color_factor: [3]cgltf_float,
    diffuse_transmission_color_texture: cgltf_texture_view,
};
const cgltf_anisotropy = extern struct {
    anisotropy_strength: cgltf_float,
    anisotropy_rotation: cgltf_float,
    anisotropy_texture: cgltf_texture_view,
};
const cgltf_dispersion = extern struct {
    dispersion: cgltf_float,
};
const cgltf_material = extern struct {
    name: ?[*:0]u8,
    has_pbr_metallic_roughness: cgltf_bool,
    has_pbr_specular_glossiness: cgltf_bool,
    has_clearcoat: cgltf_bool,
    has_transmission: cgltf_bool,
    has_volume: cgltf_bool,
    has_ior: cgltf_bool,
    has_specular: cgltf_bool,
    has_sheen: cgltf_bool,
    has_emissive_strength: cgltf_bool,
    has_iridescence: cgltf_bool,
    has_diffuse_transmission: cgltf_bool,
    has_anisotropy: cgltf_bool,
    has_dispersion: cgltf_bool,
    pbr_metallic_roughness: cgltf_pbr_metallic_roughness,
    pbr_specular_glossiness: cgltf_pbr_specular_glossiness,
    clearcoat: cgltf_clearcoat,
    ior: cgltf_ior,
    specular: cgltf_specular,
    sheen: cgltf_sheen,
    transmission: cgltf_transmission,
    volume: cgltf_volume,
    emissive_strength: cgltf_emissive_strength,
    iridescence: cgltf_iridescence,
    diffuse_transmission: cgltf_diffuse_transmission,
    anisotropy: cgltf_anisotropy,
    dispersion: cgltf_dispersion,
    normal_texture: cgltf_texture_view,
    occlusion_texture: cgltf_texture_view,
    emissive_texture: cgltf_texture_view,
    emissive_factor: [3]cgltf_float,
    alpha_mode: cgltf_alpha_mode,
    alpha_cutoff: cgltf_float,
    double_sided: cgltf_bool,
    unlit: cgltf_bool,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_material_mapping = extern struct {
    variant: cgltf_size,
    material: ?*cgltf_material,
    extras: cgltf_extras,
};
const cgltf_morph_target = extern struct {
    attributes: ?[*]cgltf_attribute,
    attributes_count: cgltf_size,
};
const cgltf_draco_mesh_compression = extern struct {
    buffer_view: ?*cgltf_buffer_view,
    attributes: ?[*]cgltf_attribute,
    attributes_count: cgltf_size,
};
const cgltf_mesh_gpu_instancing = extern struct {
    attributes: ?[*]cgltf_attribute,
    attributes_count: cgltf_size,
};
const cgltf_primitive = extern struct {
    type: cgltf_primitive_type,
    indices: ?*cgltf_accessor,
    material: ?*cgltf_material,
    attributes: ?[*]cgltf_attribute,
    attributes_count: cgltf_size,
    targets: ?[*]cgltf_morph_target,
    targets_count: cgltf_size,
    extras: cgltf_extras,
    has_draco_mesh_compression: cgltf_bool,
    draco_mesh_compression: cgltf_draco_mesh_compression,
    mappings: ?[*]cgltf_material_mapping,
    mappings_count: cgltf_size,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_mesh = extern struct {
    name: ?[*:0]u8,
    primitives: ?[*]cgltf_primitive,
    primitives_count: cgltf_size,
    weights: ?[*]cgltf_float,
    weights_count: cgltf_size,
    target_names: ?[*][*:0]u8,
    target_names_count: cgltf_size,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_node = extern struct {
    name: ?[*:0]u8,
    parent: ?*cgltf_node,
    children: ?[*]*cgltf_node,
    children_count: cgltf_size,
    skin: ?*anyopaque,
    mesh: ?*cgltf_mesh,
    camera: ?*anyopaque,
    light: ?*anyopaque,
    weights: ?[*]cgltf_float,
    weights_count: cgltf_size,
    has_translation: cgltf_bool,
    has_rotation: cgltf_bool,
    has_scale: cgltf_bool,
    has_matrix: cgltf_bool,
    translation: [3]cgltf_float,
    rotation: [4]cgltf_float,
    scale: [3]cgltf_float,
    matrix: [16]cgltf_float,
    extras: cgltf_extras,
    has_mesh_gpu_instancing: cgltf_bool,
    mesh_gpu_instancing: cgltf_mesh_gpu_instancing,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_skin = extern struct {
    name: ?[*:0]u8,
    joints: ?[*]*cgltf_node,
    joints_count: cgltf_size,
    skeleton: ?*cgltf_node,
    inverse_bind_matrices: ?*cgltf_accessor,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_animation_sampler = extern struct {
    input: *cgltf_accessor,
    output: *cgltf_accessor,
    interpolation: cgltf_interpolation_type,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_animation_channel = extern struct {
    sampler: *cgltf_animation_sampler,
    target_node: ?*cgltf_node,
    target_path: cgltf_animation_path_type,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_animation = extern struct {
    name: ?[*:0]u8,
    samplers: ?[*]cgltf_animation_sampler,
    samplers_count: cgltf_size,
    channels: ?[*]cgltf_animation_channel,
    channels_count: cgltf_size,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_asset = extern struct {
    copyright: ?[*:0]u8,
    generator: ?[*:0]u8,
    version: ?[*:0]u8,
    min_version: ?[*:0]u8,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: ?[*]cgltf_extension,
};
const cgltf_data = extern struct {
    file_type: cgltf_file_type,
    file_data: ?*anyopaque,
    file_size: cgltf_size,
    asset: cgltf_asset,
    meshes: ?[*]cgltf_mesh,
    meshes_count: cgltf_size,
    materials: ?[*]cgltf_material,
    materials_count: cgltf_size,
    accessors: ?[*]cgltf_accessor,
    accessors_count: cgltf_size,
    buffer_views: ?[*]cgltf_buffer_view,
    buffer_views_count: cgltf_size,
    buffers: ?[*]cgltf_buffer,
    buffers_count: cgltf_size,
    images: ?[*]cgltf_image,
    images_count: cgltf_size,
    textures: ?[*]cgltf_texture,
    textures_count: cgltf_size,
    samplers: ?[*]cgltf_sampler,
    samplers_count: cgltf_size,
    skins: ?[*]cgltf_skin,
    skins_count: cgltf_size,
    cameras: ?*anyopaque,
    cameras_count: cgltf_size,
    lights: ?*anyopaque,
    lights_count: cgltf_size,
    nodes: ?[*]cgltf_node,
    nodes_count: cgltf_size,
    scenes: ?*anyopaque,
    scenes_count: cgltf_size,
    scene: ?*anyopaque,
    animations: ?[*]cgltf_animation,
    animations_count: cgltf_size,
    variants: ?*anyopaque,
    variants_count: cgltf_size,
    extras: cgltf_extras,
    data_extensions_count: cgltf_size,
    data_extensions: ?[*]cgltf_extension,
    extensions_used: ?[*][*:0]u8,
    extensions_used_count: cgltf_size,
    extensions_required: ?[*][*:0]u8,
    extensions_required_count: cgltf_size,
    json: ?[*]const u8,
    json_size: cgltf_size,
    bin: ?*const anyopaque,
    bin_size: cgltf_size,
    memory: cgltf_memory_options,
    file: cgltf_file_options,
};
extern fn cgltf_parse(options: *const cgltf_options, data: ?*const anyopaque, size: cgltf_size, out_data: *?*cgltf_data) cgltf_result;
extern fn cgltf_load_buffers(options: *const cgltf_options, data: *cgltf_data, gltf_path: [*c]const u8) cgltf_result;
extern fn cgltf_free(data: *cgltf_data) void;
extern fn cgltf_node_transform_world(node: *const cgltf_node, out_matrix: *[16]cgltf_float) void;
extern fn cgltf_accessor_read_float(accessor: *const cgltf_accessor, index: cgltf_size, out: [*]cgltf_float, element_size: cgltf_size) cgltf_bool;
extern fn cgltf_load_buffer_base64(options: *const cgltf_options, size: cgltf_size, base64: [*]const u8, out_data: *?*anyopaque) cgltf_result;

/// The `len` items a cgltf array field points at (none when it is null)
fn cgltfItems(comptime T: type, ptr: ?[*]T, len: cgltf_size) []T {
    return if (ptr) |items| items[0..len] else &.{};
}

// ---- vox_loader ----
const VoxColor = extern struct { r: u8, g: u8, b: u8, a: u8 };
const VoxVector3 = extern struct { x: f32, y: f32, z: f32 };
const ArrayVector3 = extern struct { array: ?[*]VoxVector3, used: c_int, size: c_int };
const ArrayColor = extern struct { array: ?[*]VoxColor, used: c_int, size: c_int };
const ArrayUShort = extern struct { array: ?[*]c_ushort, used: c_int, size: c_int };
const CubeChunk3D = extern struct { m_array: ?[*]u8, arraySize: c_int };
const VoxArray3D = extern struct {
    sizeX: c_int,
    sizeY: c_int,
    sizeZ: c_int,
    chunksSizeX: c_int,
    chunksSizeY: c_int,
    chunksSizeZ: c_int,
    m_arrayChunks: ?[*]CubeChunk3D,
    arrayChunksSize: c_int,
    ChunkFlattenOffset: c_int,
    chunksAllocated: c_int,
    chunksTotal: c_int,
    vertices: ArrayVector3,
    normals: ArrayVector3,
    indices: ArrayUShort,
    colors: ArrayColor,
    palette: [256]VoxColor,
};
const VOX_SUCCESS: c_int = 0;
extern fn Vox_LoadFromMemory(pvoxData: [*]u8, voxDataSize: c_uint, pvoxarray: *VoxArray3D) c_int;
extern fn Vox_FreeArrays(voxarray: *VoxArray3D) void;

// ---- m3d ----
const M3D_INDEX = u32;
const M3D_FLOAT = f32;
const M3D_UNDEF: u32 = 0xffffffff;
const M3D_NUMBONE: usize = 4;
const m3dti_t = extern struct { u: M3D_FLOAT, v: M3D_FLOAT };
const m3dtx_t = extern struct {
    name: ?[*:0]u8,
    d: ?[*]u8,
    w: u16,
    h: u16,
    f: u8,
};
const m3dw_t = extern struct { vertexid: M3D_INDEX, weight: M3D_FLOAT };
const m3db_t = extern struct {
    parent: M3D_INDEX,
    name: ?[*:0]u8,
    pos: M3D_INDEX,
    ori: M3D_INDEX,
    numweight: M3D_INDEX,
    weight: ?[*]m3dw_t,
    mat4: [16]M3D_FLOAT,
};
const m3ds_t = extern struct {
    boneid: [M3D_NUMBONE]M3D_INDEX,
    weight: [M3D_NUMBONE]M3D_FLOAT,
};
const m3dv_t = extern struct {
    x: M3D_FLOAT,
    y: M3D_FLOAT,
    z: M3D_FLOAT,
    w: M3D_FLOAT,
    color: u32,
    skinid: M3D_INDEX,
};
const m3dp_value = extern union {
    color: u32,
    num: u32,
    fnum: f32,
    textureid: M3D_INDEX,
};
const m3dp_t = extern struct {
    type: u8,
    value: m3dp_value,
};
const m3dm_t = extern struct {
    name: ?[*:0]u8,
    numprop: u8,
    prop: ?[*]m3dp_t,
};
const m3df_t = extern struct {
    materialid: M3D_INDEX,
    vertex: [3]M3D_INDEX,
    normal: [3]M3D_INDEX,
    texcoord: [3]M3D_INDEX,
};
const m3dvi_t = extern struct { count: u16, name: ?[*:0]u8 };
const m3dvt_t = extern struct {
    name: ?[*:0]u8,
    rotation: u8,
    voxshape: u16,
    materialid: M3D_INDEX,
    color: u32,
    skinid: M3D_INDEX,
    numitem: u8,
    item: ?[*]m3dvi_t,
};
const m3dvx_t = extern struct {
    name: ?[*:0]u8,
    x: i32,
    y: i32,
    z: i32,
    w: u32,
    h: u32,
    d: u32,
    uncertain: u8,
    groupid: u8,
    data: ?[*]u16,
};
const m3dc_t = extern struct { type: u16, arg: ?[*]u32 };
const m3dh_t = extern struct {
    name: ?[*:0]u8,
    group: M3D_INDEX,
    numcmd: u32,
    cmd: ?[*]m3dc_t,
};
const m3dl_t = extern struct {
    name: ?[*:0]u8,
    lang: ?[*:0]u8,
    text: ?[*:0]u8,
    color: u32,
    vertexid: M3D_INDEX,
};
const m3dtr_t = extern struct { boneid: M3D_INDEX, pos: M3D_INDEX, ori: M3D_INDEX };
const m3dfr_t = extern struct {
    msec: u32,
    numtransform: M3D_INDEX,
    transform: ?[*]m3dtr_t,
};
const m3da_t = extern struct {
    name: ?[*:0]u8,
    durationmsec: u32,
    numframe: M3D_INDEX,
    frame: ?[*]m3dfr_t,
};
const m3di_t = extern struct {
    name: ?[*:0]u8,
    data: ?[*]u8,
    length: u32,
};
const m3dhdr_t = opaque {};
const m3dchunk_t = opaque {};
const m3d_t = extern struct {
    raw: ?*m3dhdr_t,
    flags: u8,
    errcode: i8,
    vc_s: u8,
    vi_s: u8,
    si_s: u8,
    ci_s: u8,
    ti_s: u8,
    bi_s: u8,
    nb_s: u8,
    sk_s: u8,
    fc_s: u8,
    hi_s: u8,
    fi_s: u8,
    vd_s: u8,
    vp_s: u8,
    name: ?[*:0]u8,
    license: ?[*:0]u8,
    author: ?[*:0]u8,
    desc: ?[*:0]u8,
    scale: M3D_FLOAT,
    numcmap: M3D_INDEX,
    cmap: ?[*]u32,
    numtmap: M3D_INDEX,
    tmap: ?[*]m3dti_t,
    numtexture: M3D_INDEX,
    texture: ?[*]m3dtx_t,
    numbone: M3D_INDEX,
    bone: ?[*]m3db_t,
    numvertex: M3D_INDEX,
    vertex: ?[*]m3dv_t,
    numskin: M3D_INDEX,
    skin: ?[*]m3ds_t,
    nummaterial: M3D_INDEX,
    material: ?[*]m3dm_t,
    numface: M3D_INDEX,
    face: ?[*]m3df_t,
    numvoxtype: M3D_INDEX,
    voxtype: ?[*]m3dvt_t,
    numvoxel: M3D_INDEX,
    voxel: ?[*]m3dvx_t,
    numshape: M3D_INDEX,
    shape: ?[*]m3dh_t,
    numlabel: M3D_INDEX,
    label: ?[*]m3dl_t,
    numaction: M3D_INDEX,
    action: ?[*]m3da_t,
    numinlined: M3D_INDEX,
    inlined: ?[*]m3di_t,
    numextra: M3D_INDEX,
    extra: ?[*]?*m3dchunk_t,
    preview: m3di_t,
};
const m3dread_t = ?*const fn ([*:0]u8, *c_uint) callconv(.c) ?[*]u8;
const m3dfree_t = ?*const fn (?*anyopaque) callconv(.c) void;
extern fn m3d_load(data: [*]u8, readfilecb: m3dread_t, freecb: m3dfree_t, mtllib: ?*m3d_t) ?*m3d_t;
extern fn m3d_free(model: *m3d_t) void;
extern fn m3d_pose(model: *m3d_t, actionid: M3D_INDEX, msec: u32) ?[*]m3db_t;

fn M3D_ERR_ISFATAL(x: i8) bool {
    return (x < 0) and (x > -65);
}

// m3d material property type constants
const m3dp_Kd: u8 = 0;
const m3dp_Ks: u8 = 2;
const m3dp_Ns: u8 = 3;
const m3dp_Ke: u8 = 4;
const m3dp_Pr: u8 = 64;
const m3dp_Pm: u8 = 65;
const m3dp_Ps: u8 = 66;
const m3dp_map_Kd: u8 = 128;
const m3dp_map_Ka: u8 = 129;
const m3dp_map_Ks: u8 = 130;
const m3dp_map_Ke: u8 = 132;
const m3dp_map_Km: u8 = 134;
const m3dp_map_Pm: u8 = 193;

//----------------------------------------------------------------------------------

//----------------------------------------------------------------------------------
// Module Internal Functions Declaration (forward references)
//----------------------------------------------------------------------------------
// (defined later in this file)

//----------------------------------------------------------------------------------
// Module Functions Definition - Model loading/management
//----------------------------------------------------------------------------------

// Load model from files (mesh and material)
export fn LoadModel(fileName: [*c]const u8) callconv(.c) Model {
    var model = if (IsFileExtension(fileName, ".obj"))
        loadObj(fileName)
    else if (IsFileExtension(fileName, ".iqm"))
        loadIqm(fileName)
    else if (IsFileExtension(fileName, ".gltf") or IsFileExtension(fileName, ".glb"))
        loadGltf(fileName)
    else if (IsFileExtension(fileName, ".vox"))
        loadVox(fileName)
    else if (IsFileExtension(fileName, ".m3d"))
        loadM3d(fileName)
    else
        empty_model;

    // Make sure model transform is set to identity matrix!
    model.transform = MatrixIdentity();

    if ((model.meshCount != 0) and (model.meshes != null)) {
        // Upload vertex data to GPU (static meshes)
        for (modelMeshes(model)) |*mesh| UploadMesh(mesh, false);
    } else TraceLog(LOG_WARNING, "MESH: [%s] Failed to load model mesh(es) data", fileName);

    if (model.materialCount == 0) {
        TraceLog(LOG_WARNING, "MATERIAL: [%s] Failed to load model material data, default to white material", fileName);
        addDefaultMaterial(&model) catch TraceLog(LOG_WARNING, "MATERIAL: [%s] Failed to allocate memory for default material", fileName);
    }

    return model;
}

fn addDefaultMaterial(model: *Model) error{OutOfMemory}!void {
    const materials = try cmem.alloc(Material, 1);
    errdefer cmem.free(materials.ptr);
    if (model.meshMaterial == null) model.meshMaterial = (try cmem.alloc(c_int, count(model.meshCount))).ptr;

    materials[0] = LoadMaterialDefault();
    model.materialCount = 1;
    model.materials = materials.ptr;
}

// Load model from generated mesh
export fn LoadModelFromMesh(mesh: Mesh) callconv(.c) Model {
    return modelFromMesh(mesh) catch {
        TraceLog(LOG_WARNING, "MODEL: Failed to allocate memory for model");
        return empty_model;
    };
}

fn modelFromMesh(mesh: Mesh) error{OutOfMemory}!Model {
    var model = empty_model;
    errdefer freeModelArrays(model);

    model.transform = MatrixIdentity();

    model.meshCount = 1;
    model.meshes = (try cmem.alloc(Mesh, 1)).ptr;
    model.meshes[0] = mesh;

    model.materialCount = 1;
    model.materials = (try cmem.alloc(Material, 1)).ptr;
    model.meshMaterial = (try cmem.alloc(c_int, 1)).ptr; // First material index: 0
    model.materials[0] = LoadMaterialDefault();

    return model;
}

// Check if model is valid (loaded in GPU, VAO/VBOs)
export fn IsModelValid(model: Model) callconv(.c) bool {
    const hasData = (model.meshes != null) and
        (model.materials != null) and
        (model.meshMaterial != null) and
        (model.meshCount > 0) and
        (model.materialCount > 0);

    // Every vertex attribute present on the CPU must have its buffer on the GPU
    for (modelMeshes(model)) |mesh| {
        if (!isUploaded(mesh)) return false;
    }

    return hasData;
}

fn isUploaded(mesh: Mesh) bool {
    const Location = struct { present: bool, index: c_uint };
    const locations = [_]Location{
        .{ .present = mesh.vertices != null, .index = RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION },
        .{ .present = mesh.texcoords != null, .index = RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD },
        .{ .present = mesh.normals != null, .index = RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL },
        .{ .present = mesh.colors != null, .index = RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR },
        .{ .present = mesh.tangents != null, .index = RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT },
        .{ .present = mesh.texcoords2 != null, .index = RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2 },
        .{ .present = mesh.indices != null, .index = RL_DEFAULT_SHADER_ATTRIB_LOCATION_INDICES },
        .{ .present = SUPPORT_GPU_SKINNING and (mesh.boneIndices != null), .index = RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES },
        .{ .present = SUPPORT_GPU_SKINNING and (mesh.boneWeights != null), .index = RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS },
    };
    for (locations) |location| {
        if (location.present and (mesh.vboId[location.index] == 0)) return false;
    }
    return true;
}

// Unload model (meshes/materials) from memory (RAM and/or VRAM)
export fn UnloadModel(model: Model) callconv(.c) void {
    for (modelMeshes(model)) |mesh| UnloadMesh(mesh);
    freeModelArrays(model);

    TraceLog(LOG_INFO, "MODEL: Unloaded model (and meshes) from RAM and VRAM");
}

/// Releases a model's C-heap arrays, but not its meshes' vertex data
fn freeModelArrays(model: Model) void {
    for (modelMaterials(model)) |material| cmem.free(material.maps);

    cmem.free(model.meshes);
    cmem.free(model.materials);
    cmem.free(model.meshMaterial);

    cmem.free(model.skeleton.bones);
    cmem.free(model.skeleton.bindPose);
    cmem.free(model.currentPose);
    cmem.free(model.boneMatrices);
}

// Compute model bounding box limits (considers all meshes)
export fn GetModelBoundingBox(model: Model) callconv(.c) BoundingBox {
    var bounds = std.mem.zeroes(BoundingBox);

    if (model.meshCount > 0) {
        const all = modelMeshes(model);
        bounds = GetMeshBoundingBox(all[0]);

        for (all[1..]) |mesh| {
            const meshBounds = GetMeshBoundingBox(mesh);

            // Deliberately not @min/@max: C compares with `<`, keeping the
            // second value on ties and NaNs
            bounds.min = .{
                .x = if (bounds.min.x < meshBounds.min.x) bounds.min.x else meshBounds.min.x,
                .y = if (bounds.min.y < meshBounds.min.y) bounds.min.y else meshBounds.min.y,
                .z = if (bounds.min.z < meshBounds.min.z) bounds.min.z else meshBounds.min.z,
            };
            bounds.max = .{
                .x = if (bounds.max.x > meshBounds.max.x) bounds.max.x else meshBounds.max.x,
                .y = if (bounds.max.y > meshBounds.max.y) bounds.max.y else meshBounds.max.y,
                .z = if (bounds.max.z > meshBounds.max.z) bounds.max.z else meshBounds.max.z,
            };
        }
    }

    // NOTE: BoundingBox does not support rotation: a rotated model's box is up to the user
    bounds.min = Vector3Transform(bounds.min, model.transform);
    bounds.max = Vector3Transform(bounds.max, model.transform);

    return bounds;
}

// Upload vertex data into a VAO (if supported) and VBO
export fn UploadMesh(mesh: [*c]Mesh, dynamic: bool) callconv(.c) void {
    if (mesh.*.vaoId > 0) {
        TraceLog(LOG_WARNING, "VAO: [ID %i] Trying to re-load an already loaded mesh", mesh.*.vaoId);
        return;
    }

    const vboId = cmem.alloc(c_uint, MAX_MESH_VERTEX_BUFFERS) catch {
        TraceLog(LOG_WARNING, "MESH: Failed to allocate memory for vertex buffer ids");
        return;
    };
    mesh.*.vboId = vboId.ptr;
    uploadMeshBuffers(mesh, vboId, dynamic);
}

fn uploadMeshBuffers(mesh: *Mesh, vboId: []c_uint, dynamic: bool) void {
    const vertexCount = mesh.vertexCount;

    mesh.vaoId = rlLoadVertexArray();
    _ = rlEnableVertexArray(mesh.vaoId);

    // Vertex positions (shader-location = 0)
    const vertices: ?*const anyopaque = if (mesh.animVertices != null) mesh.animVertices else mesh.vertices;
    vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION] = rlLoadVertexBuffer(vertices, vertexCount * 3 * @sizeOf(f32), dynamic);
    rlSetVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION, 3, RL_FLOAT, false, 0, 0);
    rlEnableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION);

    const normals: ?*const anyopaque = if (mesh.animNormals != null) mesh.animNormals else mesh.normals;
    const Attribute = struct {
        location: c_uint,
        data: ?*const anyopaque,
        components: c_int,
        size: c_int,
        type: c_int = RL_FLOAT,
        normalized: bool = false,
        /// Value the shader reads when the mesh lacks the attribute
        default: [4]f32,
        defaultType: c_int,
        defaultCount: c_int,
    };
    // NOTE: Order and defaults match upstream rmodels.c exactly, including the
    // bone weights default set with a component count of 2
    const attributes = [_]Attribute{
        .{ .location = RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD, .data = mesh.texcoords, .components = 2, .size = @sizeOf(f32), .default = .{ 0, 0, 0, 0 }, .defaultType = SHADER_ATTRIB_VEC2, .defaultCount = 2 },
        .{ .location = RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL, .data = if (mesh.normals != null) normals else null, .components = 3, .size = @sizeOf(f32), .default = .{ 0, 0, 1, 0 }, .defaultType = SHADER_ATTRIB_VEC3, .defaultCount = 3 },
        .{ .location = RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR, .data = mesh.colors, .components = 4, .size = @sizeOf(u8), .type = RL_UNSIGNED_BYTE, .normalized = true, .default = .{ 1, 1, 1, 1 }, .defaultType = SHADER_ATTRIB_VEC4, .defaultCount = 4 },
        .{ .location = RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT, .data = mesh.tangents, .components = 4, .size = @sizeOf(f32), .default = .{ 1, 0, 0, 1 }, .defaultType = SHADER_ATTRIB_VEC4, .defaultCount = 4 },
        .{ .location = RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2, .data = mesh.texcoords2, .components = 2, .size = @sizeOf(f32), .default = .{ 0, 0, 0, 0 }, .defaultType = SHADER_ATTRIB_VEC2, .defaultCount = 2 },
        // GPU skinning: bone indices and weights
        .{ .location = RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES, .data = mesh.boneIndices, .components = 4, .size = @sizeOf(u8), .type = RL_UNSIGNED_BYTE, .default = .{ 0, 0, 0, 0 }, .defaultType = SHADER_ATTRIB_VEC4, .defaultCount = 4 },
        .{ .location = RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS, .data = mesh.boneWeights, .components = 4, .size = @sizeOf(f32), .default = .{ 0, 0, 0, 0 }, .defaultType = SHADER_ATTRIB_VEC4, .defaultCount = 2 },
    };

    for (attributes[0..if (SUPPORT_GPU_SKINNING) attributes.len else attributes.len - 2]) |*attribute| {
        if (attribute.data != null) {
            vboId[attribute.location] = rlLoadVertexBuffer(attribute.data, vertexCount * attribute.components * attribute.size, dynamic);
            rlSetVertexAttribute(attribute.location, attribute.components, attribute.type, attribute.normalized, 0, 0);
            rlEnableVertexAttribute(attribute.location);
        } else {
            rlSetVertexAttributeDefault(@intCast(attribute.location), &attribute.default, attribute.defaultType, attribute.defaultCount);
            rlDisableVertexAttribute(attribute.location);
        }
    }

    if (mesh.indices != null) {
        vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_INDICES] = rlLoadVertexBufferElement(mesh.indices, mesh.triangleCount * 3 * @sizeOf(c_ushort), dynamic);
    }

    if (mesh.vaoId > 0) TraceLog(LOG_INFO, "VAO: [ID %i] Mesh uploaded successfully to VRAM (GPU)", mesh.vaoId) else TraceLog(LOG_INFO, "VBO: Mesh uploaded successfully to VRAM (GPU)");

    rlDisableVertexArray();
}

// Update mesh vertex data in GPU for a specific buffer index
export fn UpdateMeshBuffer(mesh: Mesh, index: c_int, data: ?*const anyopaque, dataSize: c_int, offset: c_int) callconv(.c) void {
    rlUpdateVertexBuffer(mesh.vboId[@intCast(index)], data, dataSize, offset);
}

// Unload mesh from memory (RAM and VRAM)
export fn UnloadMesh(mesh: Mesh) callconv(.c) void {
    rlUnloadVertexArray(mesh.vaoId);

    if (mesh.vboId != null) {
        for (mesh.vboId[0..MAX_MESH_VERTEX_BUFFERS]) |vbo| rlUnloadVertexBuffer(vbo);
    }
    cmem.free(mesh.vboId);

    freeMeshArrays(mesh);
}

/// Releases a mesh's vertex data (CPU side)
fn freeMeshArrays(mesh: Mesh) void {
    cmem.free(mesh.vertices);
    cmem.free(mesh.texcoords);
    cmem.free(mesh.normals);
    cmem.free(mesh.colors);
    cmem.free(mesh.tangents);
    cmem.free(mesh.texcoords2);
    cmem.free(mesh.indices);

    cmem.free(mesh.boneWeights);
    cmem.free(mesh.boneIndices);

    cmem.free(mesh.animVertices);
    cmem.free(mesh.animNormals);
}

/// Upload material.colDiffuse and material.colSpecular (if locations available)
fn setMaterialColors(material: Material) void {
    const Uniform = struct { location: usize, map: usize };
    for ([_]Uniform{
        .{ .location = SHADER_LOC_COLOR_DIFFUSE, .map = MATERIAL_MAP_DIFFUSE },
        .{ .location = SHADER_LOC_COLOR_SPECULAR, .map = MATERIAL_MAP_SPECULAR },
    }) |uniform| {
        const loc = material.shader.locs[uniform.location];
        if (loc == -1) continue;
        const color = material.maps[uniform.map].color;
        const values = [4]f32{
            @as(f32, @floatFromInt(color.r)) / 255.0,
            @as(f32, @floatFromInt(color.g)) / 255.0,
            @as(f32, @floatFromInt(color.b)) / 255.0,
            @as(f32, @floatFromInt(color.a)) / 255.0,
        };
        rlSetUniform(loc, &values, SHADER_UNIFORM_VEC4, 1);
    }
}

fn isCubemap(map: usize) bool {
    return (map == MATERIAL_MAP_IRRADIANCE) or (map == MATERIAL_MAP_PREFILTER) or (map == MATERIAL_MAP_CUBEMAP);
}

/// Bind active texture maps (if available)
fn bindMaterialTextures(material: Material) void {
    for (material.maps[0..MAX_MATERIAL_MAPS], 0..) |map, i| {
        if (map.texture.id == 0) continue;
        var slot: c_int = @intCast(i);
        rlActiveTextureSlot(slot);
        if (isCubemap(i)) rlEnableTextureCubemap(map.texture.id) else rlEnableTexture(map.texture.id);
        rlSetUniform(material.shader.locs[SHADER_LOC_MAP_DIFFUSE + i], &slot, SHADER_UNIFORM_INT, 1);
    }
}

/// Unbind all bound texture maps
fn unbindMaterialTextures(material: Material) void {
    for (material.maps[0..MAX_MATERIAL_MAPS], 0..) |map, i| {
        if (map.texture.id == 0) continue;
        rlActiveTextureSlot(@intCast(i));
        if (isCubemap(i)) rlDisableTextureCubemap() else rlDisableTexture();
    }
}

/// Bind mesh VBOs to the shader attributes, for when VAOs are not available
fn bindMeshBuffers(mesh: Mesh, shader: Shader) void {
    const locs = shader.locs;

    rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION]);
    rlSetVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_POSITION]), 3, RL_FLOAT, false, 0, 0);
    rlEnableVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_POSITION]));

    rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD]);
    rlSetVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_TEXCOORD01]), 2, RL_FLOAT, false, 0, 0);
    rlEnableVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_TEXCOORD01]));

    if (locs[SHADER_LOC_VERTEX_NORMAL] != -1) {
        rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL]);
        rlSetVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_NORMAL]), 3, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_NORMAL]));
    }

    if (locs[SHADER_LOC_VERTEX_COLOR] != -1) {
        if (mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR] != 0) {
            rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR]);
            rlSetVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_COLOR]), 4, RL_UNSIGNED_BYTE, true, 0, 0);
            rlEnableVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_COLOR]));
        } else {
            // Default value for the unused attribute, needed without VAO support
            const value = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
            rlSetVertexAttributeDefault(locs[SHADER_LOC_VERTEX_COLOR], &value, SHADER_ATTRIB_VEC4, 4);
            rlDisableVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_COLOR]));
        }
    }

    if (locs[SHADER_LOC_VERTEX_TANGENT] != -1) {
        rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT]);
        rlSetVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_TANGENT]), 4, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_TANGENT]));
    }

    if (locs[SHADER_LOC_VERTEX_TEXCOORD02] != -1) {
        rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2]);
        rlSetVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_TEXCOORD02]), 2, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_TEXCOORD02]));
    }

    if (SUPPORT_GPU_SKINNING) {
        if (locs[SHADER_LOC_VERTEX_BONEIDS] != -1) {
            rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES]);
            rlSetVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_BONEIDS]), 4, RL_UNSIGNED_BYTE, false, 0, 0);
            rlEnableVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_BONEIDS]));
        }

        if (locs[SHADER_LOC_VERTEX_BONEWEIGHTS] != -1) {
            rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS]);
            rlSetVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_BONEWEIGHTS]), 4, RL_FLOAT, false, 0, 0);
            rlEnableVertexAttribute(@intCast(locs[SHADER_LOC_VERTEX_BONEWEIGHTS]));
        }
    }

    if (mesh.indices != null) rlEnableVertexBufferElement(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_INDICES]);
}

/// Upload the model-view-projection matrix and draw, once per eye (twice
/// with stereo rendering, each eye on its half of the framebuffer)
fn drawPerEye(mesh: Mesh, shader: Shader, matModelView: Matrix, matProjection: Matrix, instances: ?c_int) void {
    const eyeCount: c_int = if (rlIsStereoRenderEnabled()) 2 else 1;

    var eye: c_int = 0;
    while (eye < eyeCount) : (eye += 1) {
        const matModelViewProjection = if (eyeCount == 1)
            MatrixMultiply(matModelView, matProjection)
        else blk: {
            rlViewport(@divTrunc(eye * rlGetFramebufferWidth(), 2), 0, @divTrunc(rlGetFramebufferWidth(), 2), rlGetFramebufferHeight());
            break :blk MatrixMultiply(MatrixMultiply(matModelView, rlGetMatrixViewOffsetStereo(eye)), rlGetMatrixProjectionStereo(eye));
        };

        rlSetUniformMatrix(shader.locs[SHADER_LOC_MATRIX_MVP], matModelViewProjection);

        if (instances) |n| {
            if (mesh.indices != null) rlDrawVertexArrayElementsInstanced(0, mesh.triangleCount * 3, null, n) else rlDrawVertexArrayInstanced(0, mesh.vertexCount, n);
        } else {
            if (mesh.indices != null) rlDrawVertexArrayElements(0, mesh.triangleCount * 3, null) else rlDrawVertexArray(0, mesh.vertexCount);
        }
    }
}

// Draw a 3d mesh with material and transform
export fn DrawMesh(mesh: Mesh, material: Material, transform: Matrix) callconv(.c) void {
    // Bind shader program
    rlEnableShader(material.shader.id);

    if (material.shader.locs == null) return;
    const locs = material.shader.locs;

    setMaterialColors(material);

    // Get a copy of current matrices to work with,
    // just in case stereo render is required, and we need to modify them
    const matView = rlGetMatrixModelview();
    const matProjection = rlGetMatrixProjection();

    if (locs[SHADER_LOC_MATRIX_VIEW] != -1) rlSetUniformMatrix(locs[SHADER_LOC_MATRIX_VIEW], matView);
    if (locs[SHADER_LOC_MATRIX_PROJECTION] != -1) rlSetUniformMatrix(locs[SHADER_LOC_MATRIX_PROJECTION], matProjection);

    // Model transformation matrix, accumulated with the internal (push/pop) transform
    const matModel = MatrixMultiply(transform, rlGetMatrixTransform());

    if (locs[SHADER_LOC_MATRIX_MODEL] != -1) rlSetUniformMatrix(locs[SHADER_LOC_MATRIX_MODEL], matModel);

    const matModelView = MatrixMultiply(matModel, matView);

    if (locs[SHADER_LOC_MATRIX_NORMAL] != -1) rlSetUniformMatrix(locs[SHADER_LOC_MATRIX_NORMAL], MatrixTranspose(MatrixInvert(matModel)));

    bindMaterialTextures(material);

    // Try binding vertex array objects (VAO) or use VBOs if not possible
    if (!rlEnableVertexArray(mesh.vaoId)) bindMeshBuffers(mesh, material.shader);

    drawPerEye(mesh, material.shader, matModelView, matProjection, null);

    unbindMaterialTextures(material);

    // Disable all possible vertex array objects (or VBOs)
    rlDisableVertexArray();
    rlDisableVertexBuffer();
    rlDisableVertexBufferElement();

    // Disable shader program
    rlDisableShader();

    // Restore rlgl internal modelview and projection matrices
    rlSetMatrixModelview(matView);
    rlSetMatrixProjection(matProjection);
}

// Draw multiple mesh instances with material and different transforms
export fn DrawMeshInstanced(mesh: Mesh, material: Material, transforms: [*c]const Matrix, instances: c_int) callconv(.c) void {
    // Instance transforms as float16 arrays, for the instances buffer
    const instanceTransforms = std.heap.c_allocator.alloc(float16, count(instances)) catch {
        TraceLog(LOG_WARNING, "MESH: Failed to allocate memory for instance transforms");
        return;
    };
    defer std.heap.c_allocator.free(instanceTransforms);
    for (instanceTransforms, transforms[0..instanceTransforms.len]) |*instance, transform| instance.* = MatrixToFloatV(transform);

    // Bind shader program
    rlEnableShader(material.shader.id);
    const locs = material.shader.locs;

    setMaterialColors(material);

    const matModel = MatrixIdentity();
    const matView = rlGetMatrixModelview();
    const matProjection = rlGetMatrixProjection();

    if (locs[SHADER_LOC_MATRIX_VIEW] != -1) rlSetUniformMatrix(locs[SHADER_LOC_MATRIX_VIEW], matView);
    if (locs[SHADER_LOC_MATRIX_PROJECTION] != -1) rlSetUniformMatrix(locs[SHADER_LOC_MATRIX_PROJECTION], matProjection);

    // Enable mesh VAO to attach the instances buffer
    _ = rlEnableVertexArray(mesh.vaoId);

    const instancesVboId = rlLoadVertexBuffer(instanceTransforms.ptr, instances * @sizeOf(float16), false);

    // Instance transformation matrices go to shader attribute location SHADER_LOC_VERTEX_INSTANCETRANSFORM
    if (locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM] != -1) {
        const loc: c_uint = @intCast(locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM]);
        for (0..4) |column| {
            const attribute = loc + @as(c_uint, @intCast(column));
            rlEnableVertexAttribute(attribute);
            rlSetVertexAttribute(attribute, 4, RL_FLOAT, false, @sizeOf(Matrix), @intCast(column * @sizeOf(Vector4)));
            rlSetVertexAttributeDivisor(attribute, 1);
        }
    }

    rlDisableVertexBuffer();
    rlDisableVertexArray();

    // NOTE: The instance transformation is computed in the shader
    const matModelView = MatrixMultiply(rlGetMatrixTransform(), matView);

    if (locs[SHADER_LOC_MATRIX_NORMAL] != -1) rlSetUniformMatrix(locs[SHADER_LOC_MATRIX_NORMAL], MatrixTranspose(MatrixInvert(matModel)));

    bindMaterialTextures(material);

    // Try binding vertex array objects (VAO) or use VBOs if not possible
    if (!rlEnableVertexArray(mesh.vaoId)) bindMeshBuffers(mesh, material.shader);

    drawPerEye(mesh, material.shader, matModelView, matProjection, instances);

    unbindMaterialTextures(material);

    // Disable all possible vertex array objects (or VBOs)
    rlDisableVertexArray();
    rlDisableVertexBuffer();
    rlDisableVertexBufferElement();

    // Disable shader program
    rlDisableShader();

    // Remove instance transforms buffer
    rlUnloadVertexBuffer(instancesVboId);
}

// Export mesh data to file, returns true on success
export fn ExportMesh(mesh: Mesh, fileName: [*c]const u8) callconv(.c) bool {
    // NOTE: .gltf/.glb and .raw are recognized upstream but not implemented: they return false
    if (!IsFileExtension(fileName, ".obj")) return false;

    var text: Io.Writer.Allocating = .init(std.heap.c_allocator);
    defer text.deinit();
    writeMeshObj(&text.writer, mesh) catch {
        TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to allocate memory for mesh export", fileName);
        return false;
    };
    return saveText(fileName, &text);
}

// Export mesh as code file (.h) defining multiple arrays of vertex attributes
export fn ExportMeshAsCode(mesh: Mesh, fileName: [*c]const u8) callconv(.c) bool {
    // Variable names are the file name, uppercased (truncated to 255 bytes, as raylib does)
    const baseName = std.mem.span(GetFileNameWithoutExt(fileName));
    var nameBuffer: [255]u8 = undefined;
    const name = std.ascii.upperString(&nameBuffer, baseName[0..@min(baseName.len, nameBuffer.len)]);

    var text: Io.Writer.Allocating = .init(std.heap.c_allocator);
    defer text.deinit();
    writeMeshCode(&text.writer, mesh, name) catch {
        TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to allocate memory for mesh export", fileName);
        return false;
    };
    return saveText(fileName, &text);
}

/// Saves the text through raylib's SaveFileText (which honours user callbacks)
fn saveText(fileName: [*c]const u8, text: *Io.Writer.Allocating) bool {
    text.writer.writeByte(0) catch return false;
    return SaveFileText(fileName, text.written().ptr);
}

/// Writes `value` as C's printf would with `format`. std.fmt rounds ties
/// differently (CLAUDE.md), so the exported text goes through libc.
fn printFloat(w: *Io.Writer, format: [*:0]const u8, value: f32) Io.Writer.Error!void {
    var buffer: [128]u8 = undefined;
    const len = snprintf(&buffer, buffer.len, format, @as(f64, value));
    try w.writeAll(buffer[0..@min(@as(usize, @intCast(len)), buffer.len - 1)]);
}

fn writeMeshObj(w: *Io.Writer, mesh: Mesh) Io.Writer.Error!void {
    const vertexCount = count(mesh.vertexCount);

    try w.writeAll(
        \\# //////////////////////////////////////////////////////////////////////////////////
        \\# //                                                                              //
        \\# // rMeshOBJ exporter v1.0 - Mesh exported as triangle faces and not optimized   //
        \\# //                                                                              //
        \\# // more info and bugs-report:  github.com/raysan5/raylib                        //
        \\# // feedback and support:       ray[at]raylib.com                                //
        \\# //                                                                              //
        \\# // Copyright (c) 2018-2026 Ramon Santamaria (@raysan5)                          //
        \\# //                                                                              //
        \\# //////////////////////////////////////////////////////////////////////////////////
        \\
        \\
    );
    try w.print("# Vertex Count:     {d}\n", .{mesh.vertexCount});
    try w.print("# Triangle Count:   {d}\n\n", .{mesh.triangleCount});
    try w.writeAll("g mesh\n");

    const lines = [_]struct { prefix: []const u8, values: [*c]const f32, components: usize, format: [:0]const u8 }{
        .{ .prefix = "v", .values = mesh.vertices, .components = 3, .format = "%.6f" },
        .{ .prefix = "vt", .values = mesh.texcoords, .components = 2, .format = "%.6f" },
        .{ .prefix = "vn", .values = mesh.normals, .components = 3, .format = "%.4f" },
    };
    for (lines) |line| {
        for (0..vertexCount) |i| {
            try w.writeAll(line.prefix);
            for (line.values[i * line.components ..][0..line.components]) |value| {
                try w.writeByte(' ');
                try printFloat(w, line.format, value);
            }
            try w.writeByte('\n');
        }
    }

    for (0..count(mesh.triangleCount)) |t| {
        // Face vertices are 1-based; unindexed meshes use the vertices in order
        var face: [3]c_int = undefined;
        for (&face, 0..) |*vertex, k| {
            vertex.* = if (mesh.indices != null) @as(c_int, mesh.indices[t * 3 + k]) + 1 else @intCast(t * 3 + k + 1);
        }
        try w.print("f {d}/{d}/{d} {d}/{d}/{d} {d}/{d}/{d}\n", .{ face[0], face[0], face[0], face[1], face[1], face[1], face[2], face[2], face[2] });
    }
}

fn writeMeshCode(w: *Io.Writer, mesh: Mesh, name: []const u8) Io.Writer.Error!void {
    try w.writeAll(
        \\////////////////////////////////////////////////////////////////////////////////////////
        \\//                                                                                    //
        \\// MeshAsCode exporter v1.0 - Mesh vertex data exported as arrays                     //
        \\//                                                                                    //
        \\// more info and bugs-report:  github.com/raysan5/raylib                              //
        \\// feedback and support:       ray[at]raylib.com                                      //
        \\//                                                                                    //
        \\// Copyright (c) 2023 Ramon Santamaria (@raysan5)                                     //
        \\//                                                                                    //
        \\////////////////////////////////////////////////////////////////////////////////////////
        \\
        \\
    );

    try w.writeAll("// Mesh basic information\n");
    try w.print("#define {s}_VERTEX_COUNT    {d}\n", .{ name, mesh.vertexCount });
    try w.print("#define {s}_TRIANGLE_COUNT   {d}\n\n", .{ name, mesh.triangleCount });

    const vertexCount = count(mesh.vertexCount);
    const floatArrays = [_]struct { label: []const u8, values: [*c]const f32, components: usize }{
        .{ .label = "VERTEX", .values = mesh.vertices, .components = 3 },
        .{ .label = "TEXCOORD", .values = mesh.texcoords, .components = 2 },
        .{ .label = "TEXCOORD2", .values = mesh.texcoords2, .components = 2 },
        .{ .label = "NORMAL", .values = mesh.normals, .components = 3 },
        .{ .label = "TANGENT", .values = mesh.tangents, .components = 4 },
    };
    for (floatArrays) |array| {
        if (array.values == null) continue;
        const values = array.values[0 .. vertexCount * array.components];
        try w.print("static float {s}_{s}_DATA[{d}] = {{ ", .{ name, array.label, values.len });
        for (values, 0..) |value, i| {
            try printFloat(w, "%.3ff", value);
            try w.writeAll(codeSeparator(i, values.len));
        }
        try w.writeAll("\n");
    }

    if (mesh.colors != null) {
        const colors = mesh.colors[0 .. vertexCount * 4];
        try w.print("static unsigned char {s}_COLOR_DATA[{d}] = {{ ", .{ name, colors.len });
        for (colors, 0..) |color, i| {
            try w.print("0x{x}", .{color});
            try w.writeAll(codeSeparator(i, colors.len));
        }
        try w.writeAll("\n");
    }

    if (mesh.indices != null) {
        const indices = mesh.indices[0 .. count(mesh.triangleCount) * 3];
        try w.print("static unsigned short {s}_INDEX_DATA[{d}] = {{ ", .{ name, indices.len });
        // NOTE: The index array, last in the file, ends without a blank line
        for (indices, 0..) |index, i| {
            try w.print("{d}", .{index});
            try w.writeAll(codeSeparator(i, indices.len));
        }
    }
}

/// What follows array element `i` of `len` in ExportMeshAsCode: a line break
/// every 20 elements (raylib's TEXT_BYTES_PER_LINE), and the closing brace
/// after the last
fn codeSeparator(i: usize, len: usize) []const u8 {
    if (i + 1 == len) return " };\n";
    return if (i % 20 == 0) ",\n" else ", ";
}
//----------------------------------------------------------------------------------
// Module Functions Definition - Materials
//----------------------------------------------------------------------------------

/// Build raylib materials from tinyobj's
fn processMaterialsObj(materials: []Material, mats: ?[*]tinyobj_material_t) void {
    for (materials, 0..) |*material, m| {
        // Default material: the default shader only supports MATERIAL_MAP_DIFFUSE
        material.* = LoadMaterialDefault();

        const mat = &(mats orelse continue)[m];
        const maps = material.maps;

        // rlgl's default texture (1x1 UNCOMPRESSED_R8G8B8A8) in case none is defined
        maps[MATERIAL_MAP_DIFFUSE].texture = .{ .id = rlGetTextureIdDefault(), .width = 1, .height = 1, .mipmaps = 1, .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 };

        if (mat.diffuse_texname) |texname| {
            maps[MATERIAL_MAP_DIFFUSE].texture = LoadTexture(texname);
        } else maps[MATERIAL_MAP_DIFFUSE].color = colorFromFloats(mat.diffuse);
        maps[MATERIAL_MAP_DIFFUSE].value = 0.0;

        if (mat.specular_texname) |texname| maps[MATERIAL_MAP_SPECULAR].texture = LoadTexture(texname);
        maps[MATERIAL_MAP_SPECULAR].color = colorFromFloats(mat.specular);
        maps[MATERIAL_MAP_SPECULAR].value = 0.0;

        if (mat.bump_texname) |texname| maps[MATERIAL_MAP_NORMAL].texture = LoadTexture(texname);
        maps[MATERIAL_MAP_NORMAL].color = WHITE;
        maps[MATERIAL_MAP_NORMAL].value = mat.shininess;

        maps[MATERIAL_MAP_EMISSION].color = colorFromFloats(mat.emission);

        if (mat.displacement_texname) |texname| maps[MATERIAL_MAP_HEIGHT].texture = LoadTexture(texname);
    }
}

/// An opaque color from 0..1 RGB components, converted as C's (unsigned char) casts do
fn colorFromFloats(rgb: [3]f32) Color {
    return .{ .r = cByte(rgb[0] * 255.0), .g = cByte(rgb[1] * 255.0), .b = cByte(rgb[2] * 255.0), .a = 255 };
}

// Load materials from model file
export fn LoadMaterials(fileName: [*c]const u8, materialCount: [*c]c_int) callconv(.c) [*c]Material {
    var materials: [*c]Material = null;
    var matCount: c_uint = 0;

    if (IsFileExtension(fileName, ".mtl")) {
        var mats: ?[*]tinyobj_material_t = null;

        const result = tinyobj_parse_mtl_file(&mats, &matCount, fileName);
        if (result != TINYOBJ_SUCCESS) TraceLog(LOG_WARNING, "MATERIAL: [%s] Failed to parse materials file", fileName);
        defer tinyobj_materials_free(mats, matCount);

        if (cmem.alloc(Material, matCount)) |loaded| {
            processMaterialsObj(loaded, mats);
            materials = loaded.ptr;
        } else |_| {
            TraceLog(LOG_WARNING, "MATERIAL: [%s] Failed to allocate memory for materials", fileName);
            matCount = 0;
        }
    }

    materialCount.* = @intCast(matCount);
    return materials;
}

// Load default material (Supports: DIFFUSE, SPECULAR, NORMAL maps)
export fn LoadMaterialDefault() callconv(.c) Material {
    var material = std.mem.zeroes(Material);
    const maps = cmem.alloc(MaterialMap, MAX_MATERIAL_MAPS) catch {
        TraceLog(LOG_WARNING, "MATERIAL: Failed to allocate memory for material maps");
        return material;
    };
    material.maps = maps.ptr;

    // Using rlgl default shader and default texture (1x1 pixel UNCOMPRESSED_R8G8B8A8, white)
    material.shader.id = rlGetShaderIdDefault();
    material.shader.locs = rlGetShaderLocsDefault();

    maps[MATERIAL_MAP_DIFFUSE].texture = .{ .id = rlGetTextureIdDefault(), .width = 1, .height = 1, .mipmaps = 1, .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 };

    maps[MATERIAL_MAP_DIFFUSE].color = WHITE;
    maps[MATERIAL_MAP_SPECULAR].color = WHITE;

    return material;
}

// Check if material is valid (shader assigned, map textures loaded in GPU)
export fn IsMaterialValid(material: Material) callconv(.c) bool {
    // NOTE: The map textures are not checked, as in raylib
    return (material.maps != null) and (material.shader.id > 0);
}

// Unload material from GPU memory (VRAM)
export fn UnloadMaterial(material: Material) callconv(.c) void {
    // Unload material shader (avoid unloading default shader, managed by raylib)
    if (material.shader.id != rlGetShaderIdDefault()) UnloadShader(material.shader);

    // Unload loaded texture maps (avoid unloading default texture, managed by raylib)
    if (material.maps != null) {
        for (material.maps[0..MAX_MATERIAL_MAPS]) |map| {
            if (map.texture.id != rlGetTextureIdDefault()) rlUnloadTexture(map.texture.id);
        }
    }

    cmem.free(material.maps);
}

// Set texture for a material map type (MATERIAL_MAP_DIFFUSE, MATERIAL_MAP_SPECULAR...)
export fn SetMaterialTexture(material: [*c]Material, mapType: c_int, texture: Texture2D) callconv(.c) void {
    material.*.maps[@intCast(mapType)].texture = texture;
}

// Set material for a mesh
export fn SetModelMeshMaterial(model: [*c]Model, meshId: c_int, materialId: c_int) callconv(.c) void {
    if (meshId >= model.*.meshCount) {
        TraceLog(LOG_WARNING, "MESH: Id greater than mesh count");
    } else if (materialId >= model.*.materialCount) {
        TraceLog(LOG_WARNING, "MATERIAL: Id greater than material count");
    } else model.*.meshMaterial[@intCast(meshId)] = materialId;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Model animations
//----------------------------------------------------------------------------------

// Load model animations from file
export fn LoadModelAnimations(fileName: [*c]const u8, animCount: [*c]c_int) callconv(.c) [*c]ModelAnimation {
    var animations: [*c]ModelAnimation = null;

    if (IsFileExtension(fileName, ".iqm")) animations = loadModelAnimationsIqm(fileName, animCount);
    if (IsFileExtension(fileName, ".m3d")) animations = loadModelAnimationsM3d(fileName, animCount);
    if (IsFileExtension(fileName, ".gltf;.glb")) animations = loadModelAnimationsGltf(fileName, animCount);

    return animations;
}

/// One animation frame position: the two keyframes around it and the blend between them
const FramePair = struct {
    current: usize,
    next: usize,
    blend: f32,

    /// `current` is the frame's integer part (C's (int) cast), and both
    /// keyframes wrap around the animation
    fn init(frame: f32, keyframeCount: c_int, wrapFirst: bool) FramePair {
        var current = cInt(frame);
        // UpdateModelAnimationBonesEx wraps the frame before computing the blend
        if (wrapFirst) current = @rem(current, keyframeCount);
        var next = current + 1;
        const blend = Clamp(frame - @as(f32, @floatFromInt(current)), 0.0, 1.0);
        if (current >= keyframeCount) current = @rem(current, keyframeCount);
        if (next >= keyframeCount) next = @rem(next, keyframeCount);
        return .{ .current = @intCast(current), .next = @intCast(next), .blend = blend };
    }

    /// The interpolated pose of `bone` between the pair's two keyframes
    fn pose(pair: FramePair, anim: ModelAnimation, bone: usize) Transform {
        const a = anim.keyframePoses[pair.current][bone];
        const b = anim.keyframePoses[pair.next][bone];
        return .{
            .translation = Vector3Lerp(a.translation, b.translation, pair.blend),
            .rotation = QuaternionSlerp(a.rotation, b.rotation, pair.blend),
            .scale = Vector3Lerp(a.scale, b.scale, pair.blend),
        };
    }
};

/// Scale, then rotation, then translation
fn transformMatrix(transform: Transform) Matrix {
    return MatrixMultiply(
        MatrixMultiply(MatrixScale(transform.scale.x, transform.scale.y, transform.scale.z), QuaternionToMatrix(transform.rotation)),
        MatrixTranslate(transform.translation.x, transform.translation.y, transform.translation.z),
    );
}

/// Bone matrix for the model's current pose of `bone`, relative to its bind pose
fn updateBoneMatrix(model: Model, bone: usize) void {
    const bindPoseMatrix = transformMatrix(model.skeleton.bindPose[bone]);
    const currentPoseMatrix = transformMatrix(model.currentPose[bone]);
    model.boneMatrices[bone] = MatrixMultiply(MatrixInvert(bindPoseMatrix), currentPoseMatrix);
}

// Update model animation data (bone matrices) for a specific pose
// NOTE: Request frame could be fractional, using a lerp interpolation between two frames
// NOTE: Not declared in raylib.h, but a public (non-static) symbol of upstream rmodels.c
export fn UpdateModelAnimationBones(model: Model, anim: ModelAnimation, frame: f32) callconv(.c) void {
    if (model.boneMatrices == null) return;

    if ((anim.keyframeCount > 0) and (model.skeleton.bones != null) and (anim.keyframePoses != null)) {
        const pair: FramePair = .init(frame, anim.keyframeCount, false);

        for (0..model.skeleton.boneCount) |bone| {
            model.currentPose[bone] = pair.pose(anim, bone);
            updateBoneMatrix(model, bone);
        }
    }
}

// Update model animation pose (vertex buffers and bone matrices)
// NOTE: Animated vertex data is uploaded to GPU in case of CPU skinning; for GPU
// skinning, bone matrices are uploaded to the shader on DrawModelEx()
export fn UpdateModelAnimation(model: Model, anim: ModelAnimation, frame: f32) callconv(.c) void {
    if ((anim.keyframeCount > 0) and (model.skeleton.bones != null) and (anim.keyframePoses != null)) {
        UpdateModelAnimationBones(model, anim, frame);
        updateModelAnimationVertexBuffers(model);
    }
}

fn isBlendable(animA: ModelAnimation, animB: ModelAnimation, blend: f32) bool {
    return (animA.keyframeCount > 0) and (animA.keyframePoses != null) and
        (animB.keyframeCount > 0) and (animB.keyframePoses != null) and
        (blend >= 0.0) and (blend <= 1.0);
}

// Update model animation data (bone matrices) for a pose defined by two animations blended together
// NOTE: Not declared in raylib.h, but a public (non-static) symbol of upstream rmodels.c
export fn UpdateModelAnimationBonesEx(model: Model, animA: ModelAnimation, frameA: f32, animB: ModelAnimation, frameB: f32, blend: f32) callconv(.c) void {
    if (model.boneMatrices == null) return;
    if (!isBlendable(animA, animB, blend)) return;

    const pairA: FramePair = .init(frameA, animA.keyframeCount, true);
    const pairB: FramePair = .init(frameB, animB.keyframeCount, true);

    for (0..model.skeleton.boneCount) |bone| {
        const poseA = pairA.pose(animA, bone);
        const poseB = pairB.pose(animB, bone);

        model.currentPose[bone] = .{
            .translation = Vector3Lerp(poseA.translation, poseB.translation, blend),
            .rotation = QuaternionSlerp(poseA.rotation, poseB.rotation, blend),
            .scale = Vector3Lerp(poseA.scale, poseB.scale, blend),
        };
        updateBoneMatrix(model, bone);
    }
}

// Update model animation pose, blending two animations
export fn UpdateModelAnimationEx(model: Model, animA: ModelAnimation, frameA: f32, animB: ModelAnimation, frameB: f32, blend: f32) callconv(.c) void {
    if (model.boneMatrices == null) return;

    if (isBlendable(animA, animB, blend)) {
        UpdateModelAnimationBonesEx(model, animA, frameA, animB, frameB, blend);
        updateModelAnimationVertexBuffers(model);
    }
}

/// CPU skinning: recompute animated positions and normals from the bone
/// matrices and upload them to the GPU
/// NOTE: Upstream 6.2 also precomputes a per-bone normal matrix table here that it
/// never reads (normals still use the per-vertex MatrixTranspose(MatrixInvert(...)));
/// that dead computation has no observable effect and is not ported
fn updateModelAnimationVertexBuffers(model: Model) void {
    for (modelMeshes(model), 0..) |*mesh, m| {
        // Skip if missing bone data
        if ((mesh.boneWeights == null) or (mesh.boneIndices == null)) continue;

        // Skip if the shader is using the bones directly (GPU skinning)
        if (SUPPORT_GPU_SKINNING) {
            const material = model.materials[@intCast(model.meshMaterial[m])];
            if ((material.shader.locs != null) and (material.shader.locs[SHADER_LOC_VERTEX_BONEIDS] != -1)) continue;
        }

        skinMesh(mesh, model.boneMatrices) catch {
            TraceLog(LOG_WARNING, "MESH: Failed to allocate memory for animated vertex data");
        };
    }
}

fn skinMesh(mesh: *Mesh, boneMatrices: [*c]const Matrix) error{OutOfMemory}!void {
    const valueCount = count(mesh.vertexCount) * 3;
    const vertices = mesh.vertices[0..valueCount];
    const normals: ?[]const f32 = if (mesh.normals != null) mesh.normals[0..valueCount] else null;

    // Lazy allocation of the CPU animation buffers, for software skinning
    if (mesh.animVertices == null) {
        const animVertices = try cmem.alloc(f32, valueCount);
        @memcpy(animVertices, vertices);
        mesh.animVertices = animVertices.ptr;
    }
    if (normals != null and mesh.animNormals == null) {
        const animNormals = try cmem.alloc(f32, valueCount);
        @memcpy(animNormals, normals.?);
        mesh.animNormals = animNormals.ptr;
    }

    const animVertices = mesh.animVertices[0..valueCount];
    const animNormals: ?[]f32 = if (mesh.animNormals != null) mesh.animNormals[0..valueCount] else null;
    const boneWeights = mesh.boneWeights[0 .. valueCount / 3 * 4];
    const boneIndices = mesh.boneIndices[0 .. valueCount / 3 * 4];

    var bufferUpdateRequired = false;
    var v: usize = 0;
    while (v < valueCount) : (v += 3) {
        @memset(animVertices[v..][0..3], 0);
        if (animNormals) |n| @memset(n[v..][0..3], 0);

        // Up to 4 bones per vertex
        const first = v / 3 * 4;
        for (boneWeights[first..][0..4], boneIndices[first..][0..4]) |boneWeight, boneIndex| {
            // Early stop when no transformation will be applied
            if (boneWeight == 0.0) continue;

            const animVertex = Vector3Transform(.{ .x = vertices[v], .y = vertices[v + 1], .z = vertices[v + 2] }, boneMatrices[boneIndex]);
            animVertices[v] += animVertex.x * boneWeight;
            animVertices[v + 1] += animVertex.y * boneWeight;
            animVertices[v + 2] += animVertex.z * boneWeight;
            bufferUpdateRequired = true;

            if ((normals != null) and (animNormals != null)) {
                const base = normals.?;
                const n = animNormals.?;
                const animNormal = Vector3Transform(.{ .x = base[v], .y = base[v + 1], .z = base[v + 2] }, MatrixTranspose(MatrixInvert(boneMatrices[boneIndex])));
                n[v] += animNormal.x * boneWeight;
                n[v + 1] += animNormal.y * boneWeight;
                n[v + 2] += animNormal.z * boneWeight;
            }
        }
    }

    if (bufferUpdateRequired) {
        // Update GPU vertex buffers with the animated positions and normals
        rlUpdateVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION], mesh.animVertices, mesh.vertexCount * 3 * @sizeOf(f32), 0);
        if (mesh.normals != null) rlUpdateVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL], mesh.animNormals, mesh.vertexCount * 3 * @sizeOf(f32), 0);
    }
}

// Unload animation array data
export fn UnloadModelAnimations(animations: [*c]ModelAnimation, animCount: c_int) callconv(.c) void {
    if (animations != null) {
        for (animations[0..count(animCount)]) |animation| {
            for (animation.keyframePoses[0..count(animation.keyframeCount)]) |pose| cmem.free(pose);
            cmem.free(animation.keyframePoses);
        }
    }
    cmem.free(animations);
}

// Check model animation skeleton match
// NOTE: Only the number of bones is checked
export fn IsModelAnimationValid(model: Model, anim: ModelAnimation) callconv(.c) bool {
    return model.skeleton.boneCount == anim.boneCount;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Mesh bounding box / tangents
//----------------------------------------------------------------------------------

// Compute mesh bounding box limits
export fn GetMeshBoundingBox(mesh: Mesh) callconv(.c) BoundingBox {
    var box = std.mem.zeroes(BoundingBox);
    if (mesh.vertices == null) return box;

    // NOTE: Reads the first vertex even when vertexCount is 0, as raylib does
    const positions = vector3s(mesh.vertices[0 .. @max(count(mesh.vertexCount), 1) * 3]);
    box = .{ .min = positions[0], .max = positions[0] };
    for (positions[1..]) |v| {
        // C inlines raymath's fminf/fmaxf as LLVM minnum/maxnum, which is what
        // @min/@max lower to; the exported Vector3Min calls libm instead, and
        // the two disagree on the sign of a zero result
        box.min = .{ .x = @min(box.min.x, v.x), .y = @min(box.min.y, v.y), .z = @min(box.min.z, v.z) };
        box.max = .{ .x = @max(box.max.x, v.x), .y = @max(box.max.y, v.y), .z = @max(box.max.z, v.z) };
    }
    return box;
}

// Compute mesh tangents
export fn GenMeshTangents(mesh: [*c]Mesh) callconv(.c) void {
    if ((mesh == null) or (mesh.*.vertices == null) or (mesh.*.texcoords == null) or (mesh.*.normals == null)) {
        TraceLog(LOG_WARNING, "MESH: Tangents generation requires vertices, texcoords and normals vertex attribute data");
        return;
    }

    computeTangents(mesh) catch {
        TraceLog(LOG_WARNING, "MESH: Failed to allocate temporary memory for tangent calculation");
        return;
    };

    if (mesh.*.vboId != null) {
        // Upload tangents to GPU, as a new buffer or into the existing one
        const tangentsSize = mesh.*.vertexCount * 4 * @sizeOf(f32);
        if (mesh.*.vboId[SHADER_LOC_VERTEX_TANGENT] != 0) {
            rlUpdateVertexBuffer(mesh.*.vboId[SHADER_LOC_VERTEX_TANGENT], mesh.*.tangents, tangentsSize, 0);
        } else {
            mesh.*.vboId[SHADER_LOC_VERTEX_TANGENT] = rlLoadVertexBuffer(mesh.*.tangents, tangentsSize, false);
        }

        _ = rlEnableVertexArray(mesh.*.vaoId);
        rlSetVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT, 4, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT);
        rlDisableVertexArray();
    }

    TraceLog(LOG_INFO, "MESH: Tangents data computed and uploaded for provided mesh");
}

/// Fills mesh.tangents (replacing any) from positions, texcoords and normals
fn computeTangents(mesh: *Mesh) error{OutOfMemory}!void {
    const vertexCount = count(mesh.vertexCount);
    const gpa = std.heap.c_allocator;

    // Per-vertex accumulated tangent (s) and bitangent (t) directions
    const tan1 = try gpa.alloc(Vector3, vertexCount);
    defer gpa.free(tan1);
    const tan2 = try gpa.alloc(Vector3, vertexCount);
    defer gpa.free(tan2);
    @memset(tan1, Vector3Zero());
    @memset(tan2, Vector3Zero());

    const tangents = try cmem.alloc(f32, vertexCount * 4);
    cmem.free(mesh.tangents);
    mesh.tangents = tangents.ptr;

    const positions = vector3s(mesh.vertices[0 .. vertexCount * 3]);
    const uvs = vector2s(mesh.texcoords[0 .. vertexCount * 2]);
    const normals = vector3s(mesh.normals[0 .. vertexCount * 3]);

    for (0..count(mesh.triangleCount)) |t| {
        var index: [3]usize = .{ t * 3, t * 3 + 1, t * 3 + 2 };
        if (mesh.indices != null) {
            for (&index) |*i| i.* = mesh.indices[i.*];
        }

        const v1 = positions[index[0]];
        const v2 = positions[index[1]];
        const v3 = positions[index[2]];
        const uv1 = uvs[index[0]];
        const uv2 = uvs[index[1]];
        const uv3 = uvs[index[2]];

        const x1 = v2.x - v1.x;
        const y1 = v2.y - v1.y;
        const z1 = v2.z - v1.z;
        const x2 = v3.x - v1.x;
        const y2 = v3.y - v1.y;
        const z2 = v3.z - v1.z;

        const s1 = uv2.x - uv1.x;
        const t1 = uv2.y - uv1.y;
        const s2 = uv3.x - uv1.x;
        const t2 = uv3.y - uv1.y;

        const div = s1 * t2 - s2 * t1;
        const r: f32 = if (@abs(div) < 0.0001) 0.0 else 1.0 / div;

        const sdir = Vector3{ .x = (t2 * x1 - t1 * x2) * r, .y = (t2 * y1 - t1 * y2) * r, .z = (t2 * z1 - t1 * z2) * r };
        const tdir = Vector3{ .x = (s1 * x2 - s2 * x1) * r, .y = (s1 * y2 - s2 * y1) * r, .z = (s1 * z2 - s2 * z1) * r };

        for (index) |i| {
            tan1[i] = Vector3Add(tan1[i], sdir);
            tan2[i] = Vector3Add(tan2[i], tdir);
        }
    }

    for (normals, tan1, tan2, 0..) |normal, tangent, bitangent, i| {
        const out = tangents[i * 4 ..][0..4];

        // Degenerate tangent: any vector perpendicular to the normal
        if (Vector3Length(tangent) < 0.0001) {
            const fallback = perpendicular(normal);
            out.* = .{ fallback.x, fallback.y, fallback.z, 1.0 };
            continue;
        }

        // Gram-Schmidt orthogonalization against the normal
        var orthogonalized = Vector3Subtract(tangent, Vector3Scale(normal, Vector3DotProduct(normal, tangent)));
        orthogonalized = if (Vector3Length(orthogonalized) < 0.0001) perpendicular(normal) else Vector3Normalize(orthogonalized);

        // Handedness
        const w: f32 = if (Vector3DotProduct(Vector3CrossProduct(normal, orthogonalized), bitangent) < 0.0) -1.0 else 1.0;
        out.* = .{ orthogonalized.x, orthogonalized.y, orthogonalized.z, w };
    }
}

/// A tangent for `normal` when the texture coordinates give none
fn perpendicular(normal: Vector3) Vector3 {
    if (@abs(normal.z) > 0.707) return .{ .x = 1.0, .y = 0.0, .z = 0.0 };
    return Vector3Normalize(.{ .x = -normal.y, .y = normal.x, .z = 0.0 });
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Mesh generation
//----------------------------------------------------------------------------------

/// Uploads a generated mesh, or reports that generating it ran out of memory
fn generated(result: error{OutOfMemory}!Mesh) Mesh {
    var mesh = result catch {
        TraceLog(LOG_WARNING, "MESH: Failed to allocate memory for mesh generation");
        return empty_mesh;
    };
    UploadMesh(&mesh, false);
    return mesh;
}

/// A mesh's vertex arrays on the C heap, which UnloadMesh frees
const MeshArrays = struct {
    vertices: []Vector3,
    texcoords: []Vector2,
    normals: []Vector3,

    fn alloc(mesh: *Mesh, vertexCount: usize) error{OutOfMemory}!MeshArrays {
        errdefer freeMeshArrays(mesh.*);
        const vertices = try cmem.alloc(f32, vertexCount * 3);
        mesh.vertices = vertices.ptr;
        const texcoords = try cmem.alloc(f32, vertexCount * 2);
        mesh.texcoords = texcoords.ptr;
        const normals = try cmem.alloc(f32, vertexCount * 3);
        mesh.normals = normals.ptr;
        mesh.vertexCount = @intCast(vertexCount);
        return .{ .vertices = vector3s(vertices), .texcoords = vector2s(texcoords), .normals = vector3s(normals) };
    }
};

// Generate polygonal mesh
export fn GenMeshPoly(sides: c_int, radius: f32) callconv(.c) Mesh {
    if (sides < 3) return empty_mesh; // Security check
    return generated(polyMesh(@intCast(sides), radius));
}

fn polyMesh(sides: usize, radius: f32) error{OutOfMemory}!Mesh {
    var mesh = empty_mesh;
    const arrays = try MeshArrays.alloc(&mesh, sides * 3);
    mesh.triangleCount = @intCast(sides);

    // One triangle per side, from the center
    var d: f32 = 0.0;
    const dStep: f32 = 360.0 / @as(f32, @floatFromInt(sides));
    for (0..sides) |side| {
        const triangle = arrays.vertices[side * 3 ..][0..3];
        triangle[0] = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
        triangle[1] = .{ .x = sinf(DEG2RAD * d) * radius, .y = 0.0, .z = cosf(DEG2RAD * d) * radius };
        triangle[2] = .{ .x = sinf(DEG2RAD * (d + dStep)) * radius, .y = 0.0, .z = cosf(DEG2RAD * (d + dStep)) * radius };
        d += dStep;
    }

    @memset(arrays.normals, .{ .x = 0.0, .y = 1.0, .z = 0.0 }); // Vector3.up
    @memset(arrays.texcoords, .{ .x = 0.0, .y = 0.0 });

    return mesh;
}

// Generate plane mesh (with subdivisions)
export fn GenMeshPlane(width: f32, length: f32, resX: c_int, resZ: c_int) callconv(.c) Mesh {
    return generated(planeMesh(width, length, resX + 1, resZ + 1));
}

/// `columns` x `rows` vertices, shared between the faces
fn planeMesh(width: f32, length: f32, columns: c_int, rows: c_int) error{OutOfMemory}!Mesh {
    var mesh = empty_mesh;
    const arrays = try MeshArrays.alloc(&mesh, count(columns * rows));
    errdefer freeMeshArrays(mesh);

    const lastColumn: f32 = @floatFromInt(columns - 1);
    const lastRow: f32 = @floatFromInt(rows - 1);
    for (0..count(rows)) |z| {
        const fz: f32 = @floatFromInt(z);
        const zPos = (fz / lastRow - 0.5) * length; // [-length/2, length/2]
        for (0..count(columns)) |x| {
            const fx: f32 = @floatFromInt(x);
            const xPos = (fx / lastColumn - 0.5) * width; // [-width/2, width/2]
            const i = x + z * count(columns);
            arrays.vertices[i] = .{ .x = xPos, .y = 0.0, .z = zPos };
            arrays.texcoords[i] = .{ .x = fx / lastColumn, .y = fz / lastRow };
        }
    }
    @memset(arrays.normals, .{ .x = 0.0, .y = 1.0, .z = 0.0 }); // Vector3.up

    // Two triangles per face
    const faceCount = count((columns - 1) * (rows - 1));
    mesh.triangleCount = @intCast(faceCount * 2);
    const indices = try cmem.alloc(c_ushort, faceCount * 6);
    mesh.indices = indices.ptr;

    for (0..faceCount) |face| {
        const i: c_int = @intCast(face + face / count(columns - 1));
        const quad = [6]c_int{ i + columns, i + 1, i, i + columns, i + columns + 1, i + 1 };
        // C stores the int indices into unsigned short: large planes wrap
        for (indices[face * 6 ..][0..6], quad) |*index, vertex| index.* = @truncate(@as(c_uint, @bitCast(vertex)));
    }

    return mesh;
}

// Generate cuboid mesh
export fn GenMeshCube(width: f32, height: f32, length: f32) callconv(.c) Mesh {
    return generated(cubeMesh(width, height, length));
}

fn cubeMesh(width: f32, height: f32, length: f32) error{OutOfMemory}!Mesh {
    const vertices = [_]f32{
        -width / 2, -height / 2, length / 2,
        width / 2,  -height / 2, length / 2,
        width / 2,  height / 2,  length / 2,
        -width / 2, height / 2,  length / 2,
        -width / 2, -height / 2, -length / 2,
        -width / 2, height / 2,  -length / 2,
        width / 2,  height / 2,  -length / 2,
        width / 2,  -height / 2, -length / 2,
        -width / 2, height / 2,  -length / 2,
        -width / 2, height / 2,  length / 2,
        width / 2,  height / 2,  length / 2,
        width / 2,  height / 2,  -length / 2,
        -width / 2, -height / 2, -length / 2,
        width / 2,  -height / 2, -length / 2,
        width / 2,  -height / 2, length / 2,
        -width / 2, -height / 2, length / 2,
        width / 2,  -height / 2, -length / 2,
        width / 2,  height / 2,  -length / 2,
        width / 2,  height / 2,  length / 2,
        width / 2,  -height / 2, length / 2,
        -width / 2, -height / 2, -length / 2,
        -width / 2, -height / 2, length / 2,
        -width / 2, height / 2,  length / 2,
        -width / 2, height / 2,  -length / 2,
    };

    const texcoords = [_]f32{
        0.0, 0.0,
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
        0.0, 0.0,
        0.0, 1.0,
        0.0, 0.0,
        1.0, 0.0,
        1.0, 1.0,
        1.0, 1.0,
        0.0, 1.0,
        0.0, 0.0,
        1.0, 0.0,
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
        0.0, 0.0,
        0.0, 0.0,
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
    };

    const normals = [_]f32{
        0.0,  0.0,  1.0,
        0.0,  0.0,  1.0,
        0.0,  0.0,  1.0,
        0.0,  0.0,  1.0,
        0.0,  0.0,  -1.0,
        0.0,  0.0,  -1.0,
        0.0,  0.0,  -1.0,
        0.0,  0.0,  -1.0,
        0.0,  1.0,  0.0,
        0.0,  1.0,  0.0,
        0.0,  1.0,  0.0,
        0.0,  1.0,  0.0,
        0.0,  -1.0, 0.0,
        0.0,  -1.0, 0.0,
        0.0,  -1.0, 0.0,
        0.0,  -1.0, 0.0,
        1.0,  0.0,  0.0,
        1.0,  0.0,  0.0,
        1.0,  0.0,  0.0,
        1.0,  0.0,  0.0,
        -1.0, 0.0,  0.0,
        -1.0, 0.0,  0.0,
        -1.0, 0.0,  0.0,
        -1.0, 0.0,  0.0,
    };

    var mesh = empty_mesh;
    const arrays = try MeshArrays.alloc(&mesh, 24);
    errdefer freeMeshArrays(mesh);
    @memcpy(std.mem.sliceAsBytes(arrays.vertices), std.mem.sliceAsBytes(vertices[0..]));
    @memcpy(std.mem.sliceAsBytes(arrays.texcoords), std.mem.sliceAsBytes(texcoords[0..]));
    @memcpy(std.mem.sliceAsBytes(arrays.normals), std.mem.sliceAsBytes(normals[0..]));

    // Two triangles per face, four vertices per face
    const indices = try cmem.alloc(c_ushort, 36);
    mesh.indices = indices.ptr;
    for (0..6) |face| {
        const k: c_ushort = @intCast(face * 4);
        indices[face * 6 ..][0..6].* = .{ k, k + 1, k + 2, k, k + 2, k + 3 };
    }

    mesh.triangleCount = 12;

    return mesh;
}

/// Copies an indexed par_shapes mesh into a raylib mesh, as a triangle soup
fn meshFromParShapes(shape: *const par_shapes_mesh) error{OutOfMemory}!Mesh {
    var mesh = empty_mesh;
    const triangleCount = count(shape.ntriangles);
    const arrays = try MeshArrays.alloc(&mesh, triangleCount * 3);
    mesh.triangleCount = shape.ntriangles;

    const points = vector3s(shape.points.?[0..count(shape.npoints * 3)]);
    const normals = vector3s(shape.normals.?[0..count(shape.npoints * 3)]);
    const tcoords = vector2s(shape.tcoords.?[0..count(shape.npoints * 2)]);
    for (shape.triangles.?[0 .. triangleCount * 3], arrays.vertices, arrays.normals, arrays.texcoords) |point, *vertex, *normal, *texcoord| {
        vertex.* = points[point];
        normal.* = normals[point];
        texcoord.* = tcoords[point];
    }

    return mesh;
}

/// meshFromParShapes, releasing the par_shapes mesh
fn takeParShapes(shape: *par_shapes_mesh) error{OutOfMemory}!Mesh {
    defer par_shapes_free_mesh(shape);
    return meshFromParShapes(shape);
}

// Generate sphere mesh (standard sphere)
export fn GenMeshSphere(radius: f32, rings: c_int, slices: c_int) callconv(.c) Mesh {
    if ((rings < 3) or (slices < 3)) {
        TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: sphere");
        return empty_mesh;
    }

    par_shapes_set_epsilon_degenerate_sphere(0.0);
    const sphere = par_shapes_create_parametric_sphere(slices, rings);
    par_shapes_scale(sphere, radius, radius, radius);
    return generated(takeParShapes(sphere));
}

// Generate hemisphere mesh (half sphere, no bottom cap)
export fn GenMeshHemiSphere(radius: f32, rings: c_int, slices: c_int) callconv(.c) Mesh {
    if ((rings < 3) or (slices < 3)) {
        TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: hemisphere");
        return empty_mesh;
    }

    const r = if (radius < 0.0) 0.0 else radius;
    const sphere = par_shapes_create_hemisphere(slices, rings);
    par_shapes_scale(sphere, r, r, r);
    return generated(takeParShapes(sphere));
}

const x_axis = [3]f32{ 1, 0, 0 };
const y_axis = [3]f32{ 0, 1, 0 };
const disk_center = [3]f32{ 0, 0, 0 };

/// A disk cap for cylinders and cones, with all texture coordinates at `texcoord`
fn parShapesCap(radius: f32, slices: c_int, normal: [3]f32, texcoord: f32) error{OutOfMemory}!*par_shapes_mesh {
    const cap = par_shapes_create_disk(radius, slices, &disk_center, &normal);
    errdefer par_shapes_free_mesh(cap);
    // NOTE: par_shapes frees tcoords with RL_FREE, so they live on the C heap
    const tcoords = try cmem.alloc(f32, count(2 * cap.npoints));
    @memset(tcoords, texcoord);
    cap.tcoords = tcoords.ptr;
    return cap;
}

// Generate cylinder mesh
export fn GenMeshCylinder(radius: f32, height: f32, slices: c_int) callconv(.c) Mesh {
    if (slices < 3) {
        TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: cylinder");
        return empty_mesh;
    }
    return generated(cylinderMesh(radius, height, slices));
}

fn cylinderMesh(radius: f32, height: f32, slices: c_int) error{OutOfMemory}!Mesh {
    // Instance a cylinder that sits on the Z=0 plane using the given tessellation
    // levels across the UV domain, Think of "slices" like a number of pizza
    // slices, and "stacks" like a number of stacked rings.
    // Height and radius are both 1.0, but they can easily be changed with par_shapes_scale
    const cylinder = par_shapes_create_cylinder(slices, 8);
    errdefer par_shapes_free_mesh(cylinder);
    par_shapes_scale(cylinder, radius, radius, height);
    par_shapes_rotate(cylinder, -PI / 2.0, &x_axis);

    // Generate an orientable disk shape (top cap)
    const capTop = try parShapesCap(radius, slices, .{ 0, 0, 1 }, 0.0);
    par_shapes_rotate(capTop, -PI / 2.0, &x_axis);
    par_shapes_rotate(capTop, 90 * DEG2RAD, &y_axis);
    par_shapes_translate(capTop, 0, height, 0);

    // Generate an orientable disk shape (bottom cap)
    const capBottom = parShapesCap(radius, slices, .{ 0, 0, -1 }, 0.95) catch |err| {
        par_shapes_free_mesh(capTop);
        return err;
    };
    par_shapes_rotate(capBottom, PI / 2.0, &x_axis);
    par_shapes_rotate(capBottom, -90 * DEG2RAD, &y_axis);

    par_shapes_merge_and_free(cylinder, capTop);
    par_shapes_merge_and_free(cylinder, capBottom);

    return takeParShapes(cylinder);
}

// Generate cone/pyramid mesh
export fn GenMeshCone(radius: f32, height: f32, slices: c_int) callconv(.c) Mesh {
    if (slices < 3) {
        TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: cone");
        return empty_mesh;
    }
    return generated(coneMesh(radius, height, slices));
}

fn coneMesh(radius: f32, height: f32, slices: c_int) error{OutOfMemory}!Mesh {
    // Instance a cone that sits on the Z=0 plane using the given tessellation
    // levels across the UV domain, Think of "slices" like a number of pizza
    // slices, and "stacks" like a number of stacked rings.
    // Height and radius are both 1.0, but they can easily be changed with par_shapes_scale
    const cone = par_shapes_create_cone(slices, 8);
    errdefer par_shapes_free_mesh(cone);
    par_shapes_scale(cone, radius, radius, height);
    par_shapes_rotate(cone, -PI / 2.0, &x_axis);
    par_shapes_rotate(cone, PI / 2.0, &y_axis);

    // Generate an orientable disk shape (bottom cap)
    const capBottom = try parShapesCap(radius, slices, .{ 0, 0, -1 }, 0.95);
    par_shapes_rotate(capBottom, PI / 2.0, &x_axis);

    par_shapes_merge_and_free(cone, capBottom);

    return takeParShapes(cone);
}

// Generate torus mesh
export fn GenMeshTorus(radius: f32, size: f32, radSeg: c_int, sides: c_int) callconv(.c) Mesh {
    if ((sides < 3) or (radSeg < 3)) {
        TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: torus");
        return empty_mesh;
    }

    // NOTE: Deliberately not std.math.clamp: a NaN radius stays NaN, as in raylib
    const r = if (radius > 1.0) 1.0 else if (radius < 0.1) 0.1 else radius;
    const torus = par_shapes_create_torus(radSeg, sides, r);
    par_shapes_scale(torus, size / 2, size / 2, size / 2);
    return generated(takeParShapes(torus));
}

// Generate trefoil knot mesh
export fn GenMeshKnot(radius: f32, size: f32, radSeg: c_int, sides: c_int) callconv(.c) Mesh {
    if ((sides < 3) or (radSeg < 3)) {
        TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: knot");
        return empty_mesh;
    }

    const r = if (radius > 3.0) 3.0 else if (radius < 0.5) 0.5 else radius;
    const knot = par_shapes_create_trefoil_knot(radSeg, sides, r);
    par_shapes_scale(knot, size, size, size);
    return generated(takeParShapes(knot));
}

// Generate a mesh from heightmap
// NOTE: Vertex data is uploaded to GPU
export fn GenMeshHeightmap(heightmap: Image, size: Vector3) callconv(.c) Mesh {
    const pixels = LoadImageColors(heightmap);
    defer UnloadImageColors(pixels);
    return generated(heightmapMesh(pixels, count(heightmap.width), count(heightmap.height), size));
}

fn grayValue(c: Color) f32 {
    return @as(f32, @floatFromInt(@as(c_int, c.r) + c.g + c.b)) / 3.0;
}

fn heightmapMesh(pixels: [*c]const Color, mapX: usize, mapZ: usize, size: Vector3) error{OutOfMemory}!Mesh {
    var mesh = empty_mesh;
    // One quad every four pixels, two triangles each
    const quadsX = mapX -| 1;
    const quadsZ = mapZ -| 1;
    mesh.triangleCount = @intCast(quadsX * quadsZ * 2);
    const arrays = try MeshArrays.alloc(&mesh, quadsX * quadsZ * 6);

    const lastX: f32 = @floatFromInt(@as(isize, @intCast(mapX)) - 1);
    const lastZ: f32 = @floatFromInt(@as(isize, @intCast(mapZ)) - 1);
    const scaleFactor = Vector3{ .x = size.x / lastX, .y = size.y / 255.0, .z = size.z / lastZ };

    var quad: usize = 0;
    for (0..quadsZ) |z| {
        for (0..quadsX) |x| {
            const fx: f32 = @floatFromInt(x);
            const fz: f32 = @floatFromInt(z);
            const fx1: f32 = @floatFromInt(x + 1);
            const fz1: f32 = @floatFromInt(z + 1);

            // The quad's corners, then its two triangles: (A, B, C) and (C, B, D)
            const a = Vector3{ .x = fx * scaleFactor.x, .y = grayValue(pixels[x + z * mapX]) * scaleFactor.y, .z = fz * scaleFactor.z };
            const b = Vector3{ .x = fx * scaleFactor.x, .y = grayValue(pixels[x + (z + 1) * mapX]) * scaleFactor.y, .z = fz1 * scaleFactor.z };
            const c = Vector3{ .x = fx1 * scaleFactor.x, .y = grayValue(pixels[(x + 1) + z * mapX]) * scaleFactor.y, .z = fz * scaleFactor.z };
            const d = Vector3{ .x = fx1 * scaleFactor.x, .y = grayValue(pixels[(x + 1) + (z + 1) * mapX]) * scaleFactor.y, .z = fz1 * scaleFactor.z };
            arrays.vertices[quad * 6 ..][0..6].* = .{ a, b, c, c, b, d };

            const uvA = Vector2{ .x = fx / lastX, .y = fz / lastZ };
            const uvB = Vector2{ .x = fx / lastX, .y = fz1 / lastZ };
            const uvC = Vector2{ .x = fx1 / lastX, .y = fz / lastZ };
            const uvD = Vector2{ .x = fx1 / lastX, .y = fz1 / lastZ };
            arrays.texcoords[quad * 6 ..][0..6].* = .{ uvA, uvB, uvC, uvC, uvB, uvD };

            // Flat normals, one per triangle
            for (0..2) |t| {
                const triangle = arrays.vertices[quad * 6 + t * 3 ..][0..3];
                const normal = Vector3Normalize(Vector3CrossProduct(Vector3Subtract(triangle[1], triangle[0]), Vector3Subtract(triangle[2], triangle[0])));
                @memset(arrays.normals[quad * 6 + t * 3 ..][0..3], normal);
            }

            quad += 1;
        }
    }

    return mesh;
}

const RectangleF = struct { x: f32, y: f32, width: f32, height: f32 };

/// One cube face of a cubicmap cell: six vertices (two triangles) picked from
/// the cell's eight corners, one normal, and texture coordinates picked from
/// the corners of a texture atlas rectangle
const CubeFace = struct {
    /// Indices into the cell's corners, 1-based as in raylib's v1..v8
    corners: [6]u4,
    normal: Vector3,
    uv: RectangleF,
    /// (right, bottom) flags into `uv`: 0 is the rectangle's x/y, 1 is x+width/y+height
    uvCorners: [6][2]u1,
};

const cubicmap_faces = struct {
    const n1 = Vector3{ .x = 1.0, .y = 0.0, .z = 0.0 };
    const n2 = Vector3{ .x = -1.0, .y = 0.0, .z = 0.0 };
    const n3 = Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    const n4 = Vector3{ .x = 0.0, .y = -1.0, .z = 0.0 };
    const n5 = Vector3{ .x = 0.0, .y = 0.0, .z = -1.0 };
    const n6 = Vector3{ .x = 0.0, .y = 0.0, .z = 1.0 };

    // Texture atlas: the cubicmap texture is split in 4 quadrants
    const rightTexUV = RectangleF{ .x = 0.0, .y = 0.0, .width = 0.5, .height = 0.5 };
    const leftTexUV = RectangleF{ .x = 0.5, .y = 0.0, .width = 0.5, .height = 0.5 };
    const frontTexUV = RectangleF{ .x = 0.0, .y = 0.0, .width = 0.5, .height = 0.5 };
    const backTexUV = RectangleF{ .x = 0.5, .y = 0.0, .width = 0.5, .height = 0.5 };
    const topTexUV = RectangleF{ .x = 0.0, .y = 0.5, .width = 0.5, .height = 0.5 };
    const bottomTexUV = RectangleF{ .x = 0.5, .y = 0.5, .width = 0.5, .height = 0.5 };

    // Faces of a wall cell (white pixel)
    const top: CubeFace = .{ .corners = .{ 1, 2, 3, 1, 3, 4 }, .normal = n3, .uv = topTexUV, .uvCorners = .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 0, 0 }, .{ 1, 1 }, .{ 1, 0 } } };
    const bottom: CubeFace = .{ .corners = .{ 6, 8, 7, 6, 5, 8 }, .normal = n4, .uv = bottomTexUV, .uvCorners = .{ .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0 }, .{ 0, 0 }, .{ 0, 1 } } };
    const front: CubeFace = .{ .corners = .{ 2, 7, 3, 3, 7, 8 }, .normal = n6, .uv = frontTexUV, .uvCorners = .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } } };
    const back: CubeFace = .{ .corners = .{ 1, 5, 6, 1, 4, 5 }, .normal = n5, .uv = backTexUV, .uvCorners = .{ .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0 }, .{ 0, 0 }, .{ 0, 1 } } };
    const right: CubeFace = .{ .corners = .{ 3, 8, 4, 4, 8, 5 }, .normal = n1, .uv = rightTexUV, .uvCorners = .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } } };
    const left: CubeFace = .{ .corners = .{ 1, 7, 2, 1, 6, 7 }, .normal = n2, .uv = leftTexUV, .uvCorners = .{ .{ 0, 0 }, .{ 1, 1 }, .{ 1, 0 }, .{ 0, 0 }, .{ 0, 1 }, .{ 1, 1 } } };

    // Faces of a floor cell (black pixel): a ceiling looking down, a floor looking up
    const ceiling: CubeFace = .{ .corners = .{ 1, 3, 2, 1, 4, 3 }, .normal = n4, .uv = topTexUV, .uvCorners = .{ .{ 0, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 } } };
    const floor: CubeFace = .{ .corners = .{ 6, 7, 8, 6, 8, 5 }, .normal = n3, .uv = bottomTexUV, .uvCorners = .{ .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ 1, 0 }, .{ 0, 1 }, .{ 0, 0 } } };
};

/// Faces collected for a cubicmap mesh
const CubicmapGeometry = struct {
    vertices: []Vector3,
    normals: []Vector3,
    texcoords: []Vector2,
    len: usize = 0,

    fn add(geometry: *CubicmapGeometry, cell: [8]Vector3, face: CubeFace) void {
        for (face.corners, face.uvCorners, 0..) |corner, uvCorner, i| {
            geometry.vertices[geometry.len + i] = cell[corner - 1];
            geometry.normals[geometry.len + i] = face.normal;
            geometry.texcoords[geometry.len + i] = .{
                .x = if (uvCorner[0] == 1) face.uv.x + face.uv.width else face.uv.x,
                .y = if (uvCorner[1] == 1) face.uv.y + face.uv.height else face.uv.y,
            };
        }
        geometry.len += 6;
    }
};

fn colorEqual(c1: Color, c2: Color) bool {
    return (c1.r == c2.r) and (c1.g == c2.g) and (c1.b == c2.b) and (c1.a == c2.a);
}

// Generate a cubes mesh from pixel data
// NOTE: Vertex data is uploaded to GPU
export fn GenMeshCubicmap(cubicmap: Image, cubeSize: Vector3) callconv(.c) Mesh {
    const pixels = LoadImageColors(cubicmap);
    defer UnloadImageColors(pixels);
    return generated(cubicmapMesh(pixels, count(cubicmap.width), count(cubicmap.height), cubeSize));
}

fn cubicmapMesh(pixels: [*c]const Color, width: usize, height: usize, cubeSize: Vector3) error{OutOfMemory}!Mesh {
    const gpa = std.heap.c_allocator;

    // Room for six faces in every cell
    const maxVertices = width * height * 36;
    var geometry: CubicmapGeometry = .{
        .vertices = try gpa.alloc(Vector3, maxVertices),
        .normals = undefined,
        .texcoords = undefined,
    };
    defer gpa.free(geometry.vertices);
    geometry.normals = try gpa.alloc(Vector3, maxVertices);
    defer gpa.free(geometry.normals);
    geometry.texcoords = try gpa.alloc(Vector2, maxVertices);
    defer gpa.free(geometry.texcoords);

    const w = cubeSize.x;
    const h = cubeSize.z;
    const h2 = cubeSize.y;
    const faces = cubicmap_faces;

    for (0..height) |z| {
        for (0..width) |x| {
            const fx: f32 = @floatFromInt(x);
            const fz: f32 = @floatFromInt(z);
            // The cell's corners v1..v8: top (y = h2) then bottom (y = 0)
            const cell = [8]Vector3{
                .{ .x = w * (fx - 0.5), .y = h2, .z = h * (fz - 0.5) },
                .{ .x = w * (fx - 0.5), .y = h2, .z = h * (fz + 0.5) },
                .{ .x = w * (fx + 0.5), .y = h2, .z = h * (fz + 0.5) },
                .{ .x = w * (fx + 0.5), .y = h2, .z = h * (fz - 0.5) },
                .{ .x = w * (fx + 0.5), .y = 0, .z = h * (fz - 0.5) },
                .{ .x = w * (fx - 0.5), .y = 0, .z = h * (fz - 0.5) },
                .{ .x = w * (fx - 0.5), .y = 0, .z = h * (fz + 0.5) },
                .{ .x = w * (fx + 0.5), .y = 0, .z = h * (fz + 0.5) },
            };

            const pixel = pixels[z * width + x];
            if (colorEqual(pixel, WHITE)) {
                // Wall: top and bottom faces, and a side wherever the
                // neighbour is open floor or the map ends
                geometry.add(cell, faces.top);
                geometry.add(cell, faces.bottom);
                if ((z == height - 1) or colorEqual(pixels[(z + 1) * width + x], BLACK)) geometry.add(cell, faces.front);
                if ((z == 0) or colorEqual(pixels[(z - 1) * width + x], BLACK)) geometry.add(cell, faces.back);
                if ((x == width - 1) or colorEqual(pixels[z * width + (x + 1)], BLACK)) geometry.add(cell, faces.right);
                if ((x == 0) or colorEqual(pixels[z * width + (x - 1)], BLACK)) geometry.add(cell, faces.left);
            } else if (colorEqual(pixel, BLACK)) {
                // Open floor: ceiling and floor
                geometry.add(cell, faces.ceiling);
                geometry.add(cell, faces.floor);
            }
        }
    }

    var mesh = empty_mesh;
    const arrays = try MeshArrays.alloc(&mesh, geometry.len);
    mesh.triangleCount = @intCast(geometry.len / 3);
    @memcpy(arrays.vertices, geometry.vertices[0..geometry.len]);
    @memcpy(arrays.normals, geometry.normals[0..geometry.len]);
    @memcpy(arrays.texcoords, geometry.texcoords[0..geometry.len]);

    return mesh;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Model drawing
//----------------------------------------------------------------------------------

// Draw a model (with texture if set)
export fn DrawModel(model: Model, position: Vector3, scale: f32, tint: Color) callconv(.c) void {
    const vScale = Vector3{ .x = scale, .y = scale, .z = scale };
    const rotationAxis = Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 };

    DrawModelEx(model, position, rotationAxis, 0.0, vScale, tint);
}

// Draw a model with custom transform
export fn DrawModelEx(model_in: Model, position: Vector3, rotationAxis: Vector3, rotationAngle: f32, scale: Vector3, tint: Color) callconv(.c) void {
    var model = model_in;
    const matScale = MatrixScale(scale.x, scale.y, scale.z);
    const matRotation = MatrixRotate(rotationAxis, rotationAngle * DEG2RAD);
    const matTranslation = MatrixTranslate(position.x, position.y, position.z);

    const matTransform = MatrixMultiply(MatrixMultiply(matScale, matRotation), matTranslation);

    model.transform = MatrixMultiply(model.transform, matTransform);

    var i: c_int = 0;
    while (i < model.meshCount) : (i += 1) {
        var mat = model.materials[@intCast(model.meshMaterial[@intCast(i)])];
        const colDiffuse = mat.maps[MATERIAL_MAP_DIFFUSE].color;

        var colTinted = std.mem.zeroes(Color);
        colTinted.r = @intCast(@divTrunc(@as(c_int, colDiffuse.r) * @as(c_int, tint.r), 255));
        colTinted.g = @intCast(@divTrunc(@as(c_int, colDiffuse.g) * @as(c_int, tint.g), 255));
        colTinted.b = @intCast(@divTrunc(@as(c_int, colDiffuse.b) * @as(c_int, tint.b), 255));
        colTinted.a = @intCast(@divTrunc(@as(c_int, colDiffuse.a) * @as(c_int, tint.a), 255));

        mat.maps[MATERIAL_MAP_DIFFUSE].color = colTinted;

        if ((mat.shader.locs != null) and (mat.shader.locs[SHADER_LOC_MATRIX_BONETRANSFORMS] != -1) and (model.boneMatrices != null)) {
            rlEnableShader(mat.shader.id);
            rlSetUniformMatrices(mat.shader.locs[SHADER_LOC_MATRIX_BONETRANSFORMS], model.boneMatrices, @bitCast(model.skeleton.boneCount));
        }

        DrawMesh(model.meshes[@intCast(i)], mat, model.transform);

        mat.maps[MATERIAL_MAP_DIFFUSE].color = colDiffuse;
    }
}

// Draw a model wires (with texture if set)
export fn DrawModelWires(model: Model, position: Vector3, scale: f32, tint: Color) callconv(.c) void {
    rlEnableWireMode();
    DrawModel(model, position, scale, tint);
    rlDisableWireMode();
}

// Draw a model wires with custom transform
export fn DrawModelWiresEx(model: Model, position: Vector3, rotationAxis: Vector3, rotationAngle: f32, scale: Vector3, tint: Color) callconv(.c) void {
    rlEnableWireMode();
    DrawModelEx(model, position, rotationAxis, rotationAngle, scale, tint);
    rlDisableWireMode();
}

// Draw a billboard
export fn DrawBillboard(camera: Camera, texture: Texture2D, position: Vector3, scale: f32, tint: Color) callconv(.c) void {
    const rec = Rectangle{ .x = 0.0, .y = 0.0, .width = @floatFromInt(texture.width), .height = @floatFromInt(texture.height) };

    DrawBillboardRec(camera, texture, rec, position, .{ .x = scale * @abs(rec.width / rec.height), .y = scale }, tint);
}

// Draw a billboard (part of a texture defined by a rectangle)
export fn DrawBillboardRec(camera: Camera, texture: Texture2D, rec: Rectangle, position: Vector3, size: Vector2, tint: Color) callconv(.c) void {
    const up = Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 };

    DrawBillboardPro(camera, texture, rec, position, up, size, Vector2Scale(size, 0.5), 0.0, tint);
}

// Draw a billboard texture defined by source rectangle with scaling and rotation
export fn DrawBillboardPro(camera: Camera, texture: Texture2D, rec_in: Rectangle, position: Vector3, up_in: Vector3, size: Vector2, origin_in: Vector2, rotation: f32, tint: Color) callconv(.c) void {
    var rec = rec_in;
    var origin = origin_in;
    var up = up_in;

    const matView = MatrixLookAt(camera.position, camera.target, camera.up);
    var right = Vector3{ .x = matView.m0, .y = matView.m4, .z = matView.m8 };
    right = Vector3Scale(right, size.x);
    up = Vector3Scale(up, size.y);

    if (size.x < 0.0) {
        rec.x -= size.x;
        rec.width *= -1.0;
        right = Vector3Negate(right);
        origin.x *= -1.0;
    }
    if (size.y < 0.0) {
        rec.y -= size.y;
        rec.height *= -1.0;
        up = Vector3Negate(up);
        origin.y *= -1.0;
    }

    var forward = std.mem.zeroes(Vector3);
    if (rotation != 0.0) forward = Vector3CrossProduct(right, up);

    const origin3D = Vector3Add(Vector3Scale(Vector3Normalize(right), origin.x), Vector3Scale(Vector3Normalize(up), origin.y));

    var points: [4]Vector3 = undefined;
    points[0] = Vector3Zero();
    points[1] = right;
    points[2] = Vector3Add(up, right);
    points[3] = up;

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        points[i] = Vector3Subtract(points[i], origin3D);
        if (rotation != 0.0) points[i] = Vector3RotateByAxisAngle(points[i], forward, rotation * DEG2RAD);
        points[i] = Vector3Add(points[i], position);
    }

    var texcoords: [4]Vector2 = undefined;
    const tw = @as(f32, @floatFromInt(texture.width));
    const th = @as(f32, @floatFromInt(texture.height));
    texcoords[0] = .{ .x = rec.x / tw, .y = (rec.y + rec.height) / th };
    texcoords[1] = .{ .x = (rec.x + rec.width) / tw, .y = (rec.y + rec.height) / th };
    texcoords[2] = .{ .x = (rec.x + rec.width) / tw, .y = rec.y / th };
    texcoords[3] = .{ .x = rec.x / tw, .y = rec.y / th };

    rlSetTexture(texture.id);
    rlBegin(RL_QUADS);

    rlColor4ub(tint.r, tint.g, tint.b, tint.a);
    i = 0;
    while (i < 4) : (i += 1) {
        rlTexCoord2f(texcoords[i].x, texcoords[i].y);
        rlVertex3f(points[i].x, points[i].y, points[i].z);
    }

    rlEnd();
    rlSetTexture(0);
}

// Draw a bounding box with wires
export fn DrawBoundingBox(box: BoundingBox, color: Color) callconv(.c) void {
    var size = std.mem.zeroes(Vector3);

    size.x = @abs(box.max.x - box.min.x);
    size.y = @abs(box.max.y - box.min.y);
    size.z = @abs(box.max.z - box.min.z);

    const center = Vector3{ .x = box.min.x + size.x / 2.0, .y = box.min.y + size.y / 2.0, .z = box.min.z + size.z / 2.0 };

    DrawCubeWires(center, size.x, size.y, size.z, color);
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Collision detection
//----------------------------------------------------------------------------------

// Check collision between two spheres
export fn CheckCollisionSpheres(center1: Vector3, radius1: f32, center2: Vector3, radius2: f32) callconv(.c) bool {
    var collision = false;

    const radSum = radius1 + radius2;
    if (Vector3DistanceSqr(center1, center2) <= (radSum * radSum)) collision = true;

    return collision;
}

// Check collision between two boxes
export fn CheckCollisionBoxes(box1: BoundingBox, box2: BoundingBox) callconv(.c) bool {
    var collision = true;

    if ((box1.max.x >= box2.min.x) and (box1.min.x <= box2.max.x)) {
        if ((box1.max.y < box2.min.y) or (box1.min.y > box2.max.y)) collision = false;
        if ((box1.max.z < box2.min.z) or (box1.min.z > box2.max.z)) collision = false;
    } else collision = false;

    return collision;
}

// Check collision between box and sphere
export fn CheckCollisionBoxSphere(box: BoundingBox, center: Vector3, radius: f32) callconv(.c) bool {
    var collision = false;

    const closestPoint = Vector3{
        .x = Clamp(center.x, box.min.x, box.max.x),
        .y = Clamp(center.y, box.min.y, box.max.y),
        .z = Clamp(center.z, box.min.z, box.max.z),
    };

    if (Vector3DistanceSqr(center, closestPoint) <= (radius * radius)) collision = true;

    return collision;
}

// Get collision info between ray and sphere
export fn GetRayCollisionSphere(ray: Ray, center: Vector3, radius: f32) callconv(.c) RayCollision {
    var collision = std.mem.zeroes(RayCollision);

    const raySpherePos = Vector3Subtract(center, ray.position);
    const vector = Vector3DotProduct(raySpherePos, ray.direction);
    const distanceToCenter = Vector3Length(raySpherePos);
    const d = radius * radius - (distanceToCenter * distanceToCenter - vector * vector);

    // Check if the ray's line intersects with the sphere
    if (d >= 0.0) {
        // Ray origin inside the sphere: the hit is on the far side, normal points outwards
        const inside = distanceToCenter < radius;
        const hitDistance = if (inside) vector + @sqrt(d) else vector - @sqrt(d);
        const point = Vector3Add(ray.position, Vector3Scale(ray.direction, hitDistance));
        const surfaceNormal = Vector3Normalize(Vector3Subtract(point, center));
        const normal = if (inside) Vector3Negate(surfaceNormal) else surfaceNormal;

        // Only hits in front of the ray origin count
        if (hitDistance >= 0.0) {
            collision.hit = true;
            collision.point = point;
            collision.normal = normal;
            collision.distance = hitDistance;
        }
    }

    return collision;
}

// Get collision info between ray and box
export fn GetRayCollisionBox(ray: Ray, box: BoundingBox) callconv(.c) RayCollision {
    var collision = std.mem.zeroes(RayCollision);

    // NOTE: If the ray starts inside the box, the distance is negative (as if the
    // ray was reversed): reversing ray.direction gives the right result
    const insideBox = (ray.position.x > box.min.x) and (ray.position.x < box.max.x) and
        (ray.position.y > box.min.y) and (ray.position.y < box.max.y) and
        (ray.position.z > box.min.z) and (ray.position.z < box.max.z);

    const direction = if (insideBox) Vector3Negate(ray.direction) else ray.direction;

    // Slab intersection: entry and exit distances along each axis
    const inverse = Vector3{ .x = 1.0 / direction.x, .y = 1.0 / direction.y, .z = 1.0 / direction.z };
    const minX = (box.min.x - ray.position.x) * inverse.x;
    const maxX = (box.max.x - ray.position.x) * inverse.x;
    const minY = (box.min.y - ray.position.y) * inverse.y;
    const maxY = (box.max.y - ray.position.y) * inverse.y;
    const minZ = (box.min.z - ray.position.z) * inverse.z;
    const maxZ = (box.max.z - ray.position.z) * inverse.z;
    // C's fmin/fmax are LLVM minnum/maxnum, as @min/@max are (NaN loses)
    const entry = @max(@max(@min(minX, maxX), @min(minY, maxY)), @min(minZ, maxZ));
    const exit = @min(@min(@max(minX, maxX), @max(minY, maxY)), @max(minZ, maxZ));

    collision.hit = !((exit < 0) or (entry > exit));
    collision.distance = entry;
    collision.point = Vector3Add(ray.position, Vector3Scale(direction, collision.distance));

    // Vector from the box center to the hit point, scaled to the unit cube.
    // The extra .01 fixes numerical errors: the relevant component is now
    // slightly beyond +-1 and the others within, so truncating to int gives
    // the normal
    var normal = Vector3Subtract(collision.point, Vector3Lerp(box.min, box.max, 0.5));
    normal = Vector3Divide(Vector3Scale(normal, 2.01), Vector3Subtract(box.max, box.min));
    normal = .{
        .x = @floatFromInt(cInt(normal.x)),
        .y = @floatFromInt(cInt(normal.y)),
        .z = @floatFromInt(cInt(normal.z)),
    };
    collision.normal = Vector3Normalize(normal);

    if (insideBox) {
        collision.distance *= -1.0;
        collision.normal = Vector3Negate(collision.normal);
    }

    return collision;
}

// Get collision info between ray and mesh
export fn GetRayCollisionMesh(ray: Ray, mesh: Mesh, transform: Matrix) callconv(.c) RayCollision {
    var collision = std.mem.zeroes(RayCollision);

    // Check if mesh vertex data on CPU for testing
    if (mesh.vertices == null) return collision;

    const positions = vector3s(mesh.vertices[0 .. count(mesh.vertexCount) * 3]);
    for (0..count(mesh.triangleCount)) |t| {
        var triangle: [3]Vector3 = undefined;
        for (&triangle, 0..) |*vertex, k| {
            const index = if (mesh.indices != null) mesh.indices[t * 3 + k] else t * 3 + k;
            vertex.* = Vector3Transform(positions[index], transform);
        }

        const triHitInfo = GetRayCollisionTriangle(ray, triangle[0], triangle[1], triangle[2]);

        // Keep the closest hit
        if (triHitInfo.hit and ((!collision.hit) or (collision.distance > triHitInfo.distance))) collision = triHitInfo;
    }

    return collision;
}

// Get collision info between ray and triangle
export fn GetRayCollisionTriangle(ray: Ray, p1: Vector3, p2: Vector3, p3: Vector3) callconv(.c) RayCollision {
    var collision = std.mem.zeroes(RayCollision);

    const edge1 = Vector3Subtract(p2, p1);
    const edge2 = Vector3Subtract(p3, p1);

    const p = Vector3CrossProduct(ray.direction, edge2);

    const det = Vector3DotProduct(edge1, p);

    if ((det > -EPSILON) and (det < EPSILON)) return collision;

    const invDet = 1.0 / det;

    const tv = Vector3Subtract(ray.position, p1);

    const u = Vector3DotProduct(tv, p) * invDet;

    if ((u < 0.0) or (u > 1.0)) return collision;

    const q = Vector3CrossProduct(tv, edge1);

    const v = Vector3DotProduct(ray.direction, q) * invDet;

    if ((v < 0.0) or ((u + v) > 1.0)) return collision;

    const t = Vector3DotProduct(edge2, q) * invDet;

    if (t > EPSILON) {
        collision.hit = true;
        collision.distance = t;
        collision.normal = Vector3Normalize(Vector3CrossProduct(edge1, edge2));
        collision.point = Vector3Add(ray.position, Vector3Scale(ray.direction, t));
    }

    return collision;
}

// Get collision info between ray and quad
export fn GetRayCollisionQuad(ray: Ray, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3) callconv(.c) RayCollision {
    var collision = GetRayCollisionTriangle(ray, p1, p2, p4);

    if (!collision.hit) collision = GetRayCollisionTriangle(ray, p2, p3, p4);

    return collision;
}

//----------------------------------------------------------------------------------
// Module Internal Functions Definition - File loaders
//----------------------------------------------------------------------------------

// Build pose from parent joints (required by IQM and GLTF)
fn buildPoseFromParentJoints(bones: []const BoneInfo, transforms: []Transform) void {
    for (bones, transforms, 0..) |bone, *transform, i| {
        if (bone.parent < 0) continue;
        if (bone.parent > i) {
            TraceLog(LOG_WARNING, "Skipping bone not topologically sorted: Bone %d has parent %d", @as(c_int, @intCast(i)), bone.parent);
            continue;
        }

        // NOTE: Sequential, as in C: a bone that is its own parent sees its updates
        const parent = &transforms[@intCast(bone.parent)];
        transform.rotation = QuaternionMultiply(parent.rotation, transform.rotation);
        transform.scale = Vector3Multiply(transform.scale, parent.scale);
        transform.translation = Vector3Multiply(transform.translation, parent.scale);
        transform.translation = Vector3RotateByQuaternion(transform.translation, parent.rotation);
        transform.translation = Vector3Add(transform.translation, parent.translation);
    }
}

// Load OBJ mesh data
// NOTE: A mesh is created for every shape, and for every change of material
// within one; tinyobj triangulates the faces
fn loadObj(fileName: [*c]const u8) Model {
    var model = empty_model;
    model.transform = MatrixIdentity();

    const fileText = LoadFileText(fileName);
    if (fileText == null) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Unable to read obj file", fileName);
        return model;
    }

    // Switch to the OBJ directory so material and texture paths resolve
    var currentDirBuffer: [MAX_FILEPATH_LENGTH]u8 = undefined;
    const currentDir = copyCString(&currentDirBuffer, GetWorkingDirectory());
    const workingDir = GetDirectoryPath(fileName);
    changeDirectory(workingDir) catch TraceLog(LOG_WARNING, "MODEL: [%s] Failed to change working directory", workingDir);

    var obj: ObjData = .{};
    const text = std.mem.span(fileText);
    if (tinyobj_parse_obj(&obj.attrib, &obj.shapes, &obj.shapeCount, &obj.materials, &obj.materialCount, text.ptr, @intCast(text.len), TINYOBJ_FLAG_TRIANGULATE) != TINYOBJ_SUCCESS) {
        // NOTE: Deliberately as raylib: returns without freeing the text or
        // restoring the working directory
        TraceLog(LOG_WARNING, "MODEL: Unable to read obj data %s", fileName);
        return model;
    }

    UnloadFileText(fileText);

    defer changeDirectory(currentDir.ptr) catch TraceLog(LOG_WARNING, "MODEL: [%s] Failed to change working directory", currentDir.ptr);
    defer obj.deinit();

    return objModel(obj) catch {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to allocate memory for obj data", fileName);
        return model;
    };
}

/// tinyobj's parse results
const ObjData = struct {
    attrib: tinyobj_attrib_t = std.mem.zeroes(tinyobj_attrib_t),
    shapes: ?[*]tinyobj_shape_t = null,
    shapeCount: c_uint = 0,
    materials: ?[*]tinyobj_material_t = null,
    materialCount: c_uint = 0,

    fn deinit(obj: *ObjData) void {
        tinyobj_attrib_free(&obj.attrib);
        tinyobj_shapes_free(obj.shapes, obj.shapeCount);
        tinyobj_materials_free(obj.materials, obj.materialCount);
    }
};

/// Walks an OBJ's faces in order, telling where a new mesh starts: at each
/// shape boundary and wherever the material changes
const ObjMeshSplitter = struct {
    attrib: *const tinyobj_attrib_t,
    shapes: []const tinyobj_shape_t,
    nextShape: usize = 1,
    nextShapeEnd: c_uint,
    lastMaterial: c_int = -1,

    fn init(obj: *const ObjData) ObjMeshSplitter {
        const shapes = if (obj.shapes) |shapes| shapes[0..obj.shapeCount] else &.{};
        // NOTE: Deliberately as raylib: past the last shape, the end is the total
        // number of face vertices, compared against a face index
        return .{
            .attrib = &obj.attrib,
            .shapes = shapes,
            .nextShapeEnd = if (shapes.len > 1) shapes[1].face_offset else obj.attrib.num_face_num_verts,
        };
    }

    /// Whether face `faceId` (visited in order) starts a new mesh
    fn startsMesh(splitter: *ObjMeshSplitter, faceId: usize) bool {
        var newMesh = false;
        if (faceId >= splitter.nextShapeEnd) {
            splitter.nextShape += 1;
            splitter.nextShapeEnd = if (splitter.nextShape < splitter.shapes.len) splitter.shapes[splitter.nextShape].face_offset else splitter.attrib.num_face_num_verts;
            newMesh = true;
        }

        const material = splitter.attrib.material_ids.?[faceId];
        if ((splitter.lastMaterial != -1) and (material != splitter.lastMaterial)) newMesh = true;
        splitter.lastMaterial = material;
        return newMesh;
    }
};

fn objModel(obj: ObjData) error{OutOfMemory}!Model {
    const attrib = &obj.attrib;
    const gpa = std.heap.c_allocator;

    var model = empty_model;
    model.transform = MatrixIdentity();
    errdefer freeModelData(model);

    // Count the vertices of each mesh
    var vertexCounts: std.ArrayList(usize) = .empty;
    defer vertexCounts.deinit(gpa);
    try vertexCounts.append(gpa, 0);

    var splitter: ObjMeshSplitter = .init(&obj);
    for (0..attrib.num_faces) |faceId| {
        if (splitter.startsMesh(faceId)) try vertexCounts.append(gpa, 0);
        vertexCounts.items[vertexCounts.items.len - 1] += count(attrib.face_num_verts.?[faceId]);
    }

    // Allocate the meshes, and at least one material
    model.meshCount = @intCast(vertexCounts.items.len);
    model.meshes = (try cmem.alloc(Mesh, vertexCounts.items.len)).ptr;
    model.materialCount = @intCast(@max(obj.materialCount, 1));
    model.materials = (try cmem.alloc(Material, @max(obj.materialCount, 1))).ptr;
    model.meshMaterial = (try cmem.alloc(c_int, vertexCounts.items.len)).ptr;

    for (modelMeshes(model), vertexCounts.items) |*mesh, vertexCount| {
        mesh.vertexCount = @intCast(vertexCount);
        mesh.triangleCount = @intCast(vertexCount / 3);
        mesh.vertices = (try cmem.alloc(f32, vertexCount * 3)).ptr;
        mesh.normals = (try cmem.alloc(f32, vertexCount * 3)).ptr;
        mesh.texcoords = (try cmem.alloc(f32, vertexCount * 2)).ptr;
        mesh.colors = (try cmem.alloc(u8, vertexCount * 4)).ptr;
    }

    // Fill the meshes
    splitter = .init(&obj);
    var meshIndex: usize = 0;
    var meshVertex: usize = 0;
    var faceVertIndex: usize = 0;
    for (0..attrib.num_faces) |faceId| {
        if (splitter.startsMesh(faceId)) {
            meshIndex += 1;
            meshVertex = 0;
        }

        const material = splitter.lastMaterial;
        model.meshMaterial[meshIndex] = if ((material >= 0) and (material < @as(c_int, @intCast(obj.materialCount)))) material else 0;

        const mesh = &modelMeshes(model)[meshIndex];
        for (0..count(attrib.face_num_verts.?[faceId])) |_| {
            fillObjVertex(mesh, meshVertex, attrib, attrib.faces.?[faceVertIndex]);
            faceVertIndex += 1;
            meshVertex += 1;
        }
    }

    if (obj.materialCount > 0) processMaterialsObj(model.materials[0..obj.materialCount], obj.materials) else model.materials[0] = LoadMaterialDefault();

    return model;
}

/// Copies one face vertex from tinyobj's arrays into mesh vertex `v`
fn fillObjVertex(mesh: *Mesh, v: usize, attrib: *const tinyobj_attrib_t, index: tinyobj_vertex_index_t) void {
    // NOTE: Out-of-range indices from malformed files are skipped, keeping zeroed values
    if (objIndex(index.v_idx, attrib.num_vertices)) |i| {
        @memcpy(mesh.vertices[v * 3 ..][0..3], attrib.vertices.?[i * 3 ..][0..3]);
    }

    if (attrib.texcoords) |texcoords| {
        if (objIndex(index.vt_idx, attrib.num_texcoords)) |i| {
            mesh.texcoords[v * 2 ..][0..2].* = .{ texcoords[i * 2], 1.0 - texcoords[i * 2 + 1] };
        }
    }

    const normal = mesh.normals[v * 3 ..][0..3];
    normal.* = .{ 0.0, 1.0, 0.0 };
    if (attrib.normals) |normals| {
        if (objIndex(index.vn_idx, attrib.num_normals)) |i| @memcpy(normal, normals[i * 3 ..][0..3]);
    }

    @memset(mesh.colors[v * 4 ..][0..4], 255);
}

/// A tinyobj index, when it is valid and within the `limit` items parsed
fn objIndex(index: c_int, limit: c_uint) ?usize {
    // TINYOBJ_INVALID_INDEX is negative, so it fails the range check too
    if ((index < 0) or (index >= @as(c_int, @bitCast(limit)))) return null;
    return @intCast(index);
}

/// Loads a model file's bytes, checks the IQM header and logs why it can't
/// be used. The caller releases the data with UnloadFileData.
fn openIqm(fileName: [*c]const u8) ?iqm.File {
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);
    if (fileData == null) return null;

    const file: iqm.File = .init(fileData[0..count(dataSize)]);
    file.check() catch |err| {
        switch (err) {
            error.NotIqm => TraceLog(LOG_WARNING, "MODEL: [%s] IQM file is not a valid model", fileName),
            error.UnsupportedVersion => TraceLog(LOG_WARNING, "MODEL: [%s] IQM file version not supported (%i)", fileName, file.header.version),
        }
        UnloadFileData(fileData);
        return null;
    };
    return file;
}

fn unloadIqm(file: iqm.File) void {
    UnloadFileData(@constCast(file.data.ptr));
}

// Load IQM mesh data
fn loadIqm(fileName: [*c]const u8) Model {
    const file = openIqm(fileName) orelse return empty_model;
    defer unloadIqm(file);

    return iqmModel(fileName, file) catch {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to allocate memory for IQM data", fileName);
        return empty_model;
    };
}

/// A 32-byte IQM name as a C string: the extra byte keeps it terminated
fn iqmCString(name: iqm.Name) [33]u8 {
    return name ++ [_]u8{0};
}

fn iqmModel(fileName: [*c]const u8, file: iqm.File) error{OutOfMemory}!Model {
    const header = file.header;
    const basePath = GetDirectoryPath(fileName);

    var model = empty_model;
    errdefer freeModelData(model);

    // Meshes, each with its own default material
    model.meshCount = @intCast(header.num_meshes);
    model.meshes = (try cmem.alloc(Mesh, header.num_meshes)).ptr;
    model.materialCount = model.meshCount;
    model.materials = (try cmem.alloc(Material, header.num_meshes)).ptr;
    model.meshMaterial = (try cmem.alloc(c_int, header.num_meshes)).ptr;

    for (modelMeshes(model), 0..) |*mesh, i| {
        const imesh = file.read(iqm.Mesh, header.ofs_meshes, i);
        const name = iqmCString(file.name(imesh.name));
        const material = iqmCString(file.name(imesh.material));

        model.materials[i] = LoadMaterialDefault();
        if (material[0] != 0) model.materials[i].maps[MATERIAL_MAP_ALBEDO].texture = LoadTexture(TextFormat("%s/%s", basePath, &material));

        model.meshMaterial[i] = @intCast(i);

        TraceLog(LOG_DEBUG, "MODEL: [%s] mesh name (%s), material (%s)", fileName, &name, &material);

        const vertexCount = imesh.num_vertexes;
        mesh.vertexCount = @intCast(vertexCount);
        mesh.vertices = (try cmem.alloc(f32, vertexCount * 3)).ptr;
        mesh.normals = (try cmem.alloc(f32, vertexCount * 3)).ptr;
        mesh.texcoords = (try cmem.alloc(f32, vertexCount * 2)).ptr;
        // Up to 4 bones per vertex
        mesh.boneIndices = (try cmem.alloc(u8, vertexCount * 4)).ptr;
        mesh.boneWeights = (try cmem.alloc(f32, vertexCount * 4)).ptr;

        mesh.triangleCount = @intCast(imesh.num_triangles);
        mesh.indices = (try cmem.alloc(c_ushort, imesh.num_triangles * 3)).ptr;
    }

    // Triangles
    for (modelMeshes(model), 0..) |mesh, m| {
        const imesh = file.read(iqm.Mesh, header.ofs_meshes, m);
        for (0..imesh.num_triangles) |t| {
            const triangle = file.read(iqm.Triangle, header.ofs_triangles, imesh.first_triangle + t);
            // IQM triangles are clockwise: reversed for raylib's counter-clockwise order
            // NOTE: C stores the unsigned difference into unsigned short, truncating
            for (mesh.indices[t * 3 ..][0..3], 0..) |*index, k| index.* = @truncate(triangle.vertex[2 - k] -% imesh.first_vertex);
        }
    }

    // Vertex arrays
    for (0..header.num_vertexarrays) |a| {
        const vertexArray = file.read(iqm.VertexArray, header.ofs_vertexarrays, a);
        for (modelMeshes(model), 0..) |*mesh, m| {
            const imesh = file.read(iqm.Mesh, header.ofs_meshes, m);
            try readIqmVertexArray(file, vertexArray, imesh, mesh);
        }
    }

    // Bones (joints) and their bind pose (base pose)
    const boneCount = header.num_joints;
    model.skeleton.boneCount = boneCount;
    const bones = try cmem.alloc(BoneInfo, boneCount);
    model.skeleton.bones = bones.ptr;
    const bindPose = try cmem.alloc(Transform, boneCount);
    model.skeleton.bindPose = bindPose.ptr;

    for (bones, bindPose, 0..) |*bone, *pose, j| {
        const joint = file.read(iqm.Joint, header.ofs_joints, j);
        bone.parent = joint.parent;
        bone.name = file.name(joint.name);
        pose.* = .{
            .translation = .{ .x = joint.translate[0], .y = joint.translate[1], .z = joint.translate[2] },
            .rotation = .{ .x = joint.rotate[0], .y = joint.rotate[1], .z = joint.rotate[2], .w = joint.rotate[3] },
            .scale = .{ .x = joint.scale[0], .y = joint.scale[1], .z = joint.scale[2] },
        };
    }

    buildPoseFromParentJoints(bones, bindPose);

    try initAnimationState(&model);

    return model;
}

/// Copies the vertex data of one IQM vertex array into one mesh
fn readIqmVertexArray(file: iqm.File, vertexArray: iqm.VertexArray, imesh: iqm.Mesh, mesh: *Mesh) error{OutOfMemory}!void {
    const first: usize = imesh.first_vertex;
    const vertexCount = imesh.num_vertexes;
    switch (@as(iqm.VertexArrayType, @fromBackingInt(@intCast(vertexArray.type)))) {
        .position => for (mesh.vertices[0 .. vertexCount * 3], first * 3..) |*value, i| {
            value.* = file.read(f32, vertexArray.offset, i);
        },
        .normal => for (mesh.normals[0 .. vertexCount * 3], first * 3..) |*value, i| {
            value.* = file.read(f32, vertexArray.offset, i);
        },
        .texcoord => for (mesh.texcoords[0 .. vertexCount * 2], first * 2..) |*value, i| {
            value.* = file.read(f32, vertexArray.offset, i);
        },
        .blendindexes => for (mesh.boneIndices[0 .. vertexCount * 4], first * 4..) |*value, i| {
            value.* = file.read(u8, vertexArray.offset, i);
        },
        .blendweights => for (mesh.boneWeights[0 .. vertexCount * 4], first * 4..) |*value, i| {
            value.* = @as(f32, @floatFromInt(file.read(u8, vertexArray.offset, i))) / 255.0;
        },
        .color => {
            const colors = try cmem.alloc(u8, vertexCount * 4);
            cmem.free(mesh.colors);
            mesh.colors = colors.ptr;
            for (colors, first * 4..) |*value, i| value.* = file.read(u8, vertexArray.offset, i);
        },
        .tangent, _ => {},
    }
}

/// Allocates the model's current pose and its bone matrices, set to identity
fn initAnimationState(model: *Model) error{OutOfMemory}!void {
    const boneCount = model.skeleton.boneCount;
    model.currentPose = (try cmem.alloc(Transform, boneCount)).ptr;
    const boneMatrices = try cmem.alloc(Matrix, boneCount);
    @memset(boneMatrices, MatrixIdentity());
    model.boneMatrices = boneMatrices.ptr;
}

// Load IQM animation data
fn loadModelAnimationsIqm(fileName: [*c]const u8, animCount: [*c]c_int) [*c]ModelAnimation {
    const file = openIqm(fileName) orelse return null;
    defer unloadIqm(file);

    animCount.* = @intCast(file.header.num_anims);
    const animations = iqmAnimations(fileName, file) catch {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to allocate memory for IQM animations", fileName);
        animCount.* = 0;
        return null;
    };
    return animations.ptr;
}

fn iqmAnimations(fileName: [*c]const u8, file: iqm.File) error{OutOfMemory}![]ModelAnimation {
    const header = file.header;
    const animations = try cmem.alloc(ModelAnimation, header.num_anims);
    errdefer UnloadModelAnimations(animations.ptr, @intCast(animations.len));

    for (animations, 0..) |*animation, a| {
        const anim = file.read(iqm.Anim, header.ofs_anims, a);
        animation.boneCount = header.num_poses;
        const keyframePoses = try cmem.alloc(ModelAnimPose, anim.num_frames);
        animation.keyframePoses = keyframePoses.ptr;
        animation.keyframeCount = @intCast(anim.num_frames);
        animation.name = file.name(anim.name);
        // TODO (upstream): store the animation framerate?

        TraceLog(LOG_INFO, "MODEL: [%s] Loaded animation: %s | Frames: %d | Framerate: %f", fileName, &animation.name, animation.keyframeCount, @as(f64, anim.framerate));

        for (keyframePoses) |*pose| pose.* = (try cmem.alloc(Transform, header.num_poses)).ptr;

        // Each frame stores the animated channels of every pose, in order
        var channel: usize = @as(usize, anim.first_frame) * header.num_framechannels;
        for (keyframePoses) |pose| {
            for (pose[0..header.num_poses], 0..) |*transform, i| {
                const ipose = file.read(iqm.Pose, header.ofs_poses, i);
                var values: [10]f32 = undefined;
                for (&values, ipose.channeloffset, ipose.channelscale, 0..) |*value, offset, scale, c| {
                    value.* = offset;
                    if ((ipose.mask >> @intCast(c)) & 1 != 0) {
                        value.* += @as(f32, @floatFromInt(file.read(u16, header.ofs_frames, channel))) * scale;
                        channel += 1;
                    }
                }
                transform.* = .{
                    .translation = .{ .x = values[0], .y = values[1], .z = values[2] },
                    .rotation = QuaternionNormalize(.{ .x = values[3], .y = values[4], .z = values[5], .w = values[6] }),
                    .scale = .{ .x = values[7], .y = values[8], .z = values[9] },
                };
            }
        }

        // Build frame poses: each bone relative to its parent
        for (keyframePoses) |pose| {
            for (0..animation.boneCount) |i| {
                const parent = file.read(iqm.Pose, header.ofs_poses, i).parent;
                if (parent < 0) continue;
                const transform = &pose[i];
                const parentTransform = &pose[@intCast(parent)];
                transform.rotation = QuaternionMultiply(parentTransform.rotation, transform.rotation);
                transform.translation = Vector3RotateByQuaternion(transform.translation, parentTransform.rotation);
                transform.translation = Vector3Add(transform.translation, parentTransform.translation);
                transform.scale = Vector3Multiply(transform.scale, parentTransform.scale);
            }
        }
    }

    return animations;
}

//----------------------------------------------------------------------------------
// GLTF loader
//----------------------------------------------------------------------------------

/// The values of an accessor, element by element and component by component,
/// read as `T` from its buffer. Like raylib's LOAD_ATTRIBUTE macro, the offsets
/// and stride are counted in whole `T`s.
fn AccessorValues(comptime T: type) type {
    return struct {
        bytes: []const u8,
        first: usize,
        stride: usize,
        components: usize,
        count: usize,
        element: usize = 0,
        component: usize = 0,

        const Self = @This();

        fn init(accessor: *const cgltf_accessor, components: usize) Self {
            const view = accessor.buffer_view.?;
            const buffer = view.buffer.?;
            const data: [*]const u8 = @ptrCast(buffer.data.?);
            return .{
                .bytes = data[0..buffer.size],
                .first = view.offset / @sizeOf(T) + accessor.offset / @sizeOf(T),
                .stride = accessor.stride / @sizeOf(T),
                .components = components,
                .count = accessor.count,
            };
        }

        fn next(values: *Self) ?T {
            if (values.element >= values.count) return null;
            const index = values.first + values.element * values.stride + values.component;
            values.component += 1;
            if (values.component == values.components) {
                values.component = 0;
                values.element += 1;
            }
            return std.mem.bytesToValue(T, values.bytes[index * @sizeOf(T) ..][0..@sizeOf(T)]);
        }

        /// Fills `out` (count * components values, or fewer if `out` is shorter)
        fn read(values: *Self, out: []T) void {
            for (out) |*value| value.* = values.next() orelse return;
        }
    };
}

/// An accessor's values read as `T` and converted to `f32`, scaled by `1/divisor`
fn readAccessorFloats(comptime T: type, accessor: *const cgltf_accessor, components: usize, out: []f32, divisor: ?f32) void {
    var values: AccessorValues(T) = .init(accessor, components);
    for (out) |*value| {
        const v = values.next() orelse return;
        const float: f32 = if (T == f32) v else @floatFromInt(v);
        value.* = if (divisor) |d| float / d else float;
    }
}

/// An accessor's `n`-component values, as a new C-heap array of `n` floats each
fn accessorFloats(comptime T: type, accessor: *const cgltf_accessor, components: usize, divisor: ?f32) error{OutOfMemory}![]f32 {
    const out = try cmem.alloc(f32, accessor.count * components);
    readAccessorFloats(T, accessor, components, out, divisor);
    return out;
}

// Load file data callback for cgltf
fn loadFileGltfCallback(_: ?*const cgltf_memory_options, _: ?*const cgltf_file_options, path: [*:0]const u8, size: *cgltf_size, data: *?*anyopaque) callconv(.c) cgltf_result {
    var filesize: c_int = 0;
    const filedata = LoadFileData(path, &filesize);

    if (filedata == null) return cgltf_result_io_error;

    size.* = @intCast(filesize);
    data.* = filedata;

    return cgltf_result_success;
}

// Release file data callback for cgltf
fn releaseFileGltfCallback(_: ?*const cgltf_memory_options, _: ?*const cgltf_file_options, data: ?*anyopaque, _: cgltf_size) callconv(.c) void {
    UnloadFileData(@ptrCast(data));
}

/// cgltf options that read files through raylib's LoadFileData (honouring user callbacks)
fn gltfOptions() cgltf_options {
    var options = std.mem.zeroes(cgltf_options);
    options.file.read = loadFileGltfCallback;
    options.file.release = releaseFileGltfCallback;
    return options;
}

// Load image from different glTF provided methods (uri, path, buffer_view)
fn loadImageFromCgltfImage(cgltfImage: ?*const cgltf_image, texPath: [*c]const u8) Image {
    const image = cgltfImage orelse return std.mem.zeroes(Image);

    if (image.uri) |uri| {
        const text = std.mem.span(uri);
        // Data URI format: data:<mediatype>;base64,<data>
        if ((text.len > 5) and std.mem.startsWith(u8, text, "data:")) return loadImageFromDataUri(text);
        // Image path, relative to the glTF file
        return LoadImage(TextFormat("%s/%s", texPath, uri));
    }

    if (image.buffer_view) |view| {
        if (view.buffer.?.data != null) return loadImageFromBufferView(image, view, texPath);
    }

    return std.mem.zeroes(Image);
}

fn loadImageFromDataUri(uri: [:0]const u8) Image {
    const comma = std.mem.indexOfScalar(u8, uri, ',') orelse {
        TraceLog(LOG_WARNING, "IMAGE: glTF data URI is not a valid image");
        return std.mem.zeroes(Image);
    };

    // Ignore the optional padding: the encoded bytes are the whole 8-bit groups
    const base64 = uri[comma + 1 ..];
    const base64Size: c_int = @intCast(std.mem.trimEnd(u8, base64, "=").len);
    const outSize = (base64Size * 6 - @rem(base64Size * 6, 8)) >> 3;

    var data: ?*anyopaque = null;
    const options = gltfOptions();
    if (cgltf_load_buffer_base64(&options, @intCast(outSize), base64.ptr, &data) != cgltf_result_success) return std.mem.zeroes(Image);
    defer cmem.free(data);

    // NOTE: raylib decodes every data URI as PNG, whatever its media type
    return LoadImageFromMemory(".png", @ptrCast(data), outSize);
}

fn loadImageFromBufferView(image: *const cgltf_image, view: *const cgltf_buffer_view, texPath: [*c]const u8) Image {
    const gpa = std.heap.c_allocator;
    const data = gpa.alloc(u8, view.size) catch {
        TraceLog(LOG_WARNING, "IMAGE: Failed to allocate memory for glTF image data");
        return std.mem.zeroes(Image);
    };
    defer gpa.free(data);

    // Copy buffer data to memory for loading
    const source: [*]const u8 = @ptrCast(view.buffer.?.data.?);
    const stride = if (view.stride != 0) view.stride else 1;
    for (data, 0..) |*byte, i| byte.* = source[view.offset + i * stride];

    // NOTE: Some models give the mime_type as "image\/png"
    const mime: []const u8 = if (image.mime_type) |mime| std.mem.span(mime) else "";
    const size: c_int = @intCast(view.size);
    if (std.mem.eql(u8, mime, "image\\/png") or std.mem.eql(u8, mime, "image/png")) return LoadImageFromMemory(".png", data.ptr, size);
    if (std.mem.eql(u8, mime, "image\\/jpeg") or std.mem.eql(u8, mime, "image/jpeg")) return LoadImageFromMemory(".jpg", data.ptr, size);

    // NOTE: raylib formats the image path as an unused extra argument (with a null uri)
    TraceLog(LOG_WARNING, "MODEL: glTF image data MIME type not recognized", TextFormat("%s/%s", texPath, image.uri));
    return std.mem.zeroes(Image);
}

/// The texture of a glTF texture view, if it has one and its image loads
fn loadTextureFromView(view: cgltf_texture_view, texPath: [*c]const u8) ?Texture2D {
    const texture = view.texture orelse return null;
    const image = loadImageFromCgltfImage(texture.image, texPath);
    if (image.data == null) return null;
    defer UnloadImage(image);
    return LoadTextureFromImage(image);
}

// Load bone info from GLTF skin data
fn loadBoneInfoGltf(skin: cgltf_skin) error{OutOfMemory}![]BoneInfo {
    const joints = cgltfItems(*cgltf_node, skin.joints, skin.joints_count);
    const bones = try cmem.alloc(BoneInfo, joints.len);

    for (bones, joints) |*bone, joint| {
        if (joint.name) |name| _ = copyCString(&bone.name, name);

        // The parent bone is the nearest ancestor that is also a joint: some
        // exporters put intermediate (non-joint) transform nodes in between
        bone.parent = -1;
        var ancestor = joint.parent;
        while (ancestor) |node| : (ancestor = node.parent) {
            if (std.mem.indexOfScalar(*cgltf_node, joints, node)) |index| {
                bone.parent = @intCast(index);
                break;
            }
        }
    }

    return bones;
}

/// A glTF column-major matrix as a raylib Matrix
fn matrixFromGltf(t: [16]cgltf_float) Matrix {
    return .{
        .m0 = t[0],
        .m4 = t[4],
        .m8 = t[8],
        .m12 = t[12],
        .m1 = t[1],
        .m5 = t[5],
        .m9 = t[9],
        .m13 = t[13],
        .m2 = t[2],
        .m6 = t[6],
        .m10 = t[10],
        .m14 = t[14],
        .m3 = t[3],
        .m7 = t[7],
        .m11 = t[11],
        .m15 = t[15],
    };
}

fn nodeWorldMatrix(node: *const cgltf_node) Matrix {
    var worldTransform = std.mem.zeroes([16]cgltf_float);
    cgltf_node_transform_world(node, &worldTransform);
    return matrixFromGltf(worldTransform);
}

/// Transforms the XYZ triples of `values` in place, normalizing the results if asked
fn transformTriples(values: []f32, matrix: Matrix, normalize: bool) void {
    for (vector3s(values)) |*v| {
        const transformed = Vector3Transform(v.*, matrix);
        v.* = if (normalize) Vector3Normalize(transformed) else transformed;
    }
}

/// The triangle primitives of every node's mesh, in file order: each becomes one raylib mesh
const TrianglePrimitives = struct {
    nodes: []cgltf_node,
    node: usize = 0,
    primitive: usize = 0,

    const Item = struct { node: *cgltf_node, primitive: *cgltf_primitive };

    fn next(it: *TrianglePrimitives) ?Item {
        while (it.node < it.nodes.len) {
            const node = &it.nodes[it.node];
            const primitives: []cgltf_primitive = if (node.mesh) |mesh| cgltfItems(cgltf_primitive, mesh.primitives, mesh.primitives_count) else &.{};
            while (it.primitive < primitives.len) {
                const primitive = &primitives[it.primitive];
                it.primitive += 1;
                if (primitive.type == cgltf_primitive_type_triangles) return .{ .node = node, .primitive = primitive };
            }
            it.node += 1;
            it.primitive = 0;
        }
        return null;
    }
};

/// glTF file data parsed by cgltf, with its buffers loaded
const GltfFile = struct {
    fileData: [*c]u8,
    data: *cgltf_data,

    fn deinit(file: GltfFile) void {
        cgltf_free(file.data);
        UnloadFileData(file.fileData);
    }
};

// Load glTF file into model struct, .gltf and .glb supported
// NOTE: Every triangle primitive of every node's mesh becomes a raylib Mesh, with the
// node's world transform applied; scenes are ignored. Only PBR metallic/roughness
// materials are read.
fn loadGltf(fileName: [*c]const u8) Model {
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);
    if (fileData == null) return empty_model;

    const options = gltfOptions();
    var parsed: ?*cgltf_data = null;
    if (cgltf_parse(&options, fileData, @intCast(dataSize), &parsed) != cgltf_result_success) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load glTF data", fileName);
        UnloadFileData(fileData);
        return empty_model;
    }
    // NOTE: cgltf needs the file data alive while reading
    const file: GltfFile = .{ .fileData = fileData, .data = parsed.? };
    defer file.deinit();
    const data = file.data;

    if (data.file_type == cgltf_file_type_glb) {
        TraceLog(LOG_INFO, "MODEL: [%s] Model basic data (glb) loaded successfully", fileName);
    } else if (data.file_type == cgltf_file_type_gltf) {
        TraceLog(LOG_INFO, "MODEL: [%s] Model basic data (glTF) loaded successfully", fileName);
    } else TraceLog(LOG_WARNING, "MODEL: [%s] Model format not recognized", fileName);

    TraceLog(LOG_INFO, "    > Meshes count: %i", @as(c_int, @intCast(data.meshes_count)));
    TraceLog(LOG_INFO, "    > Materials count: %i (+1 default)", @as(c_int, @intCast(data.materials_count)));
    TraceLog(LOG_DEBUG, "    > Buffers count: %i", @as(c_int, @intCast(data.buffers_count)));
    TraceLog(LOG_DEBUG, "    > Images count: %i", @as(c_int, @intCast(data.images_count)));
    TraceLog(LOG_DEBUG, "    > Textures count: %i", @as(c_int, @intCast(data.textures_count)));

    // Force reading data buffers (fills buffer_view->buffer->data)
    // NOTE: A uri to base64 data or to an external file is loaded automatically
    if (cgltf_load_buffers(&options, data, fileName) != cgltf_result_success) TraceLog(LOG_INFO, "MODEL: [%s] Failed to load mesh/material buffers", fileName);

    // Count the meshes needed, from the node hierarchy
    var primitivesCount: c_int = 0;
    var dracoCompression = false;
    for (cgltfItems(cgltf_node, data.nodes, data.nodes_count)) |node| {
        const mesh = node.mesh orelse continue;
        for (cgltfItems(cgltf_primitive, mesh.primitives, mesh.primitives_count)) |primitive| {
            if (primitive.has_draco_mesh_compression != 0) {
                // NOTE: Logged once per node with a Draco primitive, as raylib does
                dracoCompression = true;
                TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load mesh data, Draco compression not supported", fileName);
                break;
            }
            if (primitive.type == cgltf_primitive_type_triangles) primitivesCount += 1;
        }
    }

    if (dracoCompression) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load glTF data", fileName);
        return empty_model;
    }

    TraceLog(LOG_DEBUG, "    > Primitives (triangles only) count based on hierarchy : %i", primitivesCount);

    return gltfModel(fileName, data, count(primitivesCount)) catch {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to allocate memory for glTF data", fileName);
        return empty_model;
    };
}

fn gltfModel(fileName: [*c]const u8, data: *cgltf_data, meshCount: usize) error{OutOfMemory}!Model {
    var model = empty_model;
    errdefer freeModelData(model);

    model.meshCount = @intCast(meshCount);
    model.meshes = (try cmem.alloc(Mesh, meshCount)).ptr;

    // NOTE: An extra slot for the default material (index 0), for meshes without one
    const gltfMaterials = cgltfItems(cgltf_material, data.materials, data.materials_count);
    model.materialCount = @intCast(gltfMaterials.len + 1);
    model.materials = (try cmem.alloc(Material, gltfMaterials.len + 1)).ptr;
    model.materials[0] = LoadMaterialDefault();

    // Every mesh uses material 0 unless its primitive names one
    model.meshMaterial = (try cmem.alloc(c_int, meshCount)).ptr;

    for (gltfMaterials, model.materials[1 .. gltfMaterials.len + 1]) |*gltfMaterial, *material| {
        material.* = LoadMaterialDefault();
        try loadGltfMaterial(gltfMaterial, material.maps, GetDirectoryPath(fileName));
    }

    // Mesh vertex data, transformed to world space
    var primitives: TrianglePrimitives = .{ .nodes = cgltfItems(cgltf_node, data.nodes, data.nodes_count) };
    for (modelMeshes(model), model.meshMaterial[0..meshCount]) |*mesh, *meshMaterial| {
        const item = primitives.next().?;
        const worldMatrix = nodeWorldMatrix(item.node);
        try loadGltfPrimitive(fileName, item.primitive, mesh, worldMatrix);

        // The primitive points at its material; raylib stores its index, skipping the default
        for (gltfMaterials, 1..) |*gltfMaterial, index| {
            if (item.primitive.material == gltfMaterial) {
                meshMaterial.* = @intCast(index);
                break;
            }
        }
    }

    // Skeleton
    // NOTE: Only one skin (armature) per file, with linear interpolation, and
    // translation/rotation/scale channels (no morph target weights)
    const skins = cgltfItems(cgltf_skin, data.skins, data.skins_count);
    if (skins.len > 0) {
        try loadGltfSkeleton(&model, skins[0]);
        if (skins.len > 1) TraceLog(LOG_WARNING, "MODEL: [%s] can only load one skin (armature) per model, but gltf skins_count == %i", fileName, skins.len);
    }

    // Skin (bone) vertex data
    primitives = .{ .nodes = cgltfItems(cgltf_node, data.nodes, data.nodes_count) };
    for (modelMeshes(model)) |*mesh| {
        const item = primitives.next().?;
        const hasJoints = try loadGltfSkinData(fileName, item.primitive, mesh);

        // An animated mesh with no bone data of its own that is the child of a
        // bone node: all its vertices follow that bone
        if ((skins.len > 0) and !hasJoints) {
            if (item.node.parent) |parent| {
                if (parent.mesh == null) try attachToBone(mesh, skins[0], model.skeleton.boneCount, parent);
            }
        }

        mesh.boneCount = @bitCast(model.skeleton.boneCount);
    }

    // Runtime animation data, unless there are no bones
    if (model.skeleton.boneCount > 0) try initAnimationState(&model);

    return model;
}

fn loadGltfMaterial(gltfMaterial: *const cgltf_material, maps: [*c]MaterialMap, texPath: [*c]const u8) error{OutOfMemory}!void {
    // Only the PBR metallic/roughness flow is supported: specular/glossiness,
    // clearcoat, transmission, volume, ior, specular and sheen are not
    if (gltfMaterial.has_pbr_metallic_roughness == 0) return;
    const pbr = &gltfMaterial.pbr_metallic_roughness;

    // Base color texture (albedo) and factor (tint)
    if (loadTextureFromView(pbr.base_color_texture, texPath)) |texture| maps[MATERIAL_MAP_ALBEDO].texture = texture;
    maps[MATERIAL_MAP_ALBEDO].color = .{
        .r = cByte(pbr.base_color_factor[0] * 255),
        .g = cByte(pbr.base_color_factor[1] * 255),
        .b = cByte(pbr.base_color_factor[2] * 255),
        .a = cByte(pbr.base_color_factor[3] * 255),
    };

    // Metallic/roughness texture: roughness is its green channel, metalness its blue
    if (pbr.metallic_roughness_texture.texture) |texture| {
        const image = loadImageFromCgltfImage(texture.image, texPath);
        if (image.data != null) {
            defer UnloadImage(image);
            maps[MATERIAL_MAP_ROUGHNESS].texture, maps[MATERIAL_MAP_METALNESS].texture = try splitMetallicRoughness(image);
        }

        maps[MATERIAL_MAP_ROUGHNESS].value = pbr.roughness_factor;
        maps[MATERIAL_MAP_METALNESS].value = pbr.metallic_factor;
    }

    if (loadTextureFromView(gltfMaterial.normal_texture, texPath)) |texture| maps[MATERIAL_MAP_NORMAL].texture = texture;
    if (loadTextureFromView(gltfMaterial.occlusion_texture, texPath)) |texture| maps[MATERIAL_MAP_OCCLUSION].texture = texture;

    // Emissive texture and color factor
    if (gltfMaterial.emissive_texture.texture != null) {
        if (loadTextureFromView(gltfMaterial.emissive_texture, texPath)) |texture| maps[MATERIAL_MAP_EMISSION].texture = texture;
        maps[MATERIAL_MAP_EMISSION].color = .{
            .r = cByte(gltfMaterial.emissive_factor[0] * 255),
            .g = cByte(gltfMaterial.emissive_factor[1] * 255),
            .b = cByte(gltfMaterial.emissive_factor[2] * 255),
            .a = 255,
        };
    }
}

/// Roughness (green) and metalness (blue) textures from a metallic/roughness image
fn splitMetallicRoughness(image: Image) error{OutOfMemory}!struct { Texture2D, Texture2D } {
    const pixelCount = count(image.width * image.height);
    // Grayscale images for UnloadImage, so on the C heap
    var roughness: Image = .{ .data = null, .width = image.width, .height = image.height, .mipmaps = 1, .format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE };
    var metallic = roughness;
    const metallicData = try cmem.alloc(u8, pixelCount);
    metallic.data = metallicData.ptr;
    defer UnloadImage(metallic);
    const roughnessData = try cmem.alloc(u8, pixelCount);
    roughness.data = roughnessData.ptr;
    defer UnloadImage(roughness);

    var x: c_int = 0;
    while (x < image.width) : (x += 1) {
        var y: c_int = 0;
        while (y < image.height) : (y += 1) {
            const color = GetImageColor(image, x, y);
            const i: usize = @intCast(y * image.width + x);
            roughnessData[i] = color.g;
            metallicData[i] = color.b;
        }
    }

    return .{ LoadTextureFromImage(roughness), LoadTextureFromImage(metallic) };
}

/// Loads the vertex attributes and indices of one triangle primitive into `mesh`
fn loadGltfPrimitive(fileName: [*c]const u8, primitive: *const cgltf_primitive, mesh: *Mesh, worldMatrix: Matrix) error{OutOfMemory}!void {
    const worldMatrixNormals = MatrixTranspose(MatrixInvert(worldMatrix));

    // NOTE: Attributes come in several data formats; only some are supported per
    // attribute. Bone joints and weights are loaded after the skeleton.
    for (cgltfItems(cgltf_attribute, primitive.attributes, primitive.attributes_count)) |attribute| {
        const accessor = attribute.data;
        switch (attribute.type) {
            cgltf_attribute_type_position => try loadGltfPositions(fileName, accessor, mesh, worldMatrix),
            cgltf_attribute_type_normal => try loadGltfNormals(fileName, accessor, mesh, worldMatrixNormals),
            cgltf_attribute_type_tangent => try loadGltfTangents(fileName, accessor, mesh, worldMatrix),
            cgltf_attribute_type_texcoord => try loadGltfTexcoords(fileName, accessor, attribute.index, mesh),
            cgltf_attribute_type_color => try loadGltfColors(fileName, accessor, mesh),
            else => {},
        }
    }

    // Primitive indices (if provided)
    const indices = primitive.indices orelse return unindexed(mesh);
    if (indices.buffer_view == null) return unindexed(mesh);

    mesh.triangleCount = @divTrunc(@as(c_int, @intCast(indices.count)), 3);

    if (mesh.indices != null) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Indices attribute data already loaded", fileName);
        return;
    }

    switch (indices.component_type) {
        cgltf_component_type_r_16u => mesh.indices = (try accessorIndices(u16, indices)).ptr,
        cgltf_component_type_r_8u => mesh.indices = (try accessorIndices(u8, indices)).ptr,
        cgltf_component_type_r_32u => {
            mesh.indices = (try accessorIndices(u32, indices)).ptr;
            TraceLog(LOG_WARNING, "MODEL: [%s] Indices data converted from u32 to u16, possible loss of data", fileName);
        },
        else => TraceLog(LOG_WARNING, "MODEL: [%s] Indices data format not supported, use u16", fileName),
    }
}

fn unindexed(mesh: *Mesh) void {
    mesh.triangleCount = @divTrunc(mesh.vertexCount, 3);
}

/// An index accessor's values as 16-bit indices; wider ones are truncated, as C casts
fn accessorIndices(comptime T: type, accessor: *const cgltf_accessor) error{OutOfMemory}![]c_ushort {
    const indices = try cmem.alloc(c_ushort, accessor.count);
    var values: AccessorValues(T) = .init(accessor, 1);
    for (indices) |*index| index.* = @truncate(values.next().?);
    return indices;
}

// POSITION: vec3 of float, u16 or i16, transformed to world space
// NOTE: The glTF spec requires the POSITION accessor's min and max
fn loadGltfPositions(fileName: [*c]const u8, accessor: *const cgltf_accessor, mesh: *Mesh, worldMatrix: Matrix) error{OutOfMemory}!void {
    if (mesh.vertices != null) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Vertices attribute data already loaded", fileName);
        return;
    }

    const vertices = (if (accessor.type != cgltf_type_vec3) null else switch (accessor.component_type) {
        cgltf_component_type_r_32f => try accessorFloats(f32, accessor, 3, null),
        // The world matrix scales integer positions to their real size
        cgltf_component_type_r_16u => try accessorFloats(u16, accessor, 3, null),
        cgltf_component_type_r_16 => try accessorFloats(i16, accessor, 3, null),
        else => null,
    }) orelse {
        TraceLog(LOG_WARNING, "MODEL: [%s] Vertices attribute data format not supported, use vec3 float", fileName);
        return;
    };

    mesh.vertexCount = @intCast(accessor.count);
    mesh.vertices = vertices.ptr;
    transformTriples(vertices, worldMatrix, false);
}

// NORMAL: vec3 of float, or of normalized integers (renormalized after transforming)
fn loadGltfNormals(fileName: [*c]const u8, accessor: *const cgltf_accessor, mesh: *Mesh, worldMatrixNormals: Matrix) error{OutOfMemory}!void {
    if (mesh.normals != null) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Normals attribute data already loaded", fileName);
        return;
    }

    const normals = (if (accessor.type != cgltf_type_vec3) null else switch (accessor.component_type) {
        cgltf_component_type_r_32f => try accessorFloats(f32, accessor, 3, null),
        cgltf_component_type_r_16 => try accessorFloats(i16, accessor, 3, null),
        cgltf_component_type_r_8u => try accessorFloats(u8, accessor, 3, null),
        cgltf_component_type_r_8 => try accessorFloats(i8, accessor, 3, null),
        else => null,
    }) orelse {
        TraceLog(LOG_WARNING, "MODEL: [%s] Normals attribute data format not supported, use vec3 float", fileName);
        return;
    };

    mesh.normals = normals.ptr;
    transformTriples(normals, worldMatrixNormals, accessor.component_type != cgltf_component_type_r_32f);
}

// TANGENT: vec4 of float, w is the tangent basis sign
fn loadGltfTangents(fileName: [*c]const u8, accessor: *const cgltf_accessor, mesh: *Mesh, worldMatrix: Matrix) error{OutOfMemory}!void {
    if (mesh.tangents != null) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Tangents attribute data already loaded", fileName);
        return;
    }
    if ((accessor.type != cgltf_type_vec4) or (accessor.component_type != cgltf_component_type_r_32f)) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Tangents attribute data format not supported, use vec4 float", fileName);
        return;
    }

    const tangents = try accessorFloats(f32, accessor, 4, null);
    mesh.tangents = tangents.ptr;
    for (std.mem.bytesAsSlice(Vector4, std.mem.sliceAsBytes(tangents))) |*tangent| {
        const t = Vector3Transform(.{ .x = tangent.x, .y = tangent.y, .z = tangent.z }, worldMatrix);
        tangent.x = t.x;
        tangent.y = t.y;
        tangent.z = t.z;
    }
}

// TEXCOORD_n: vec2 of float, u8n or u16n; up to two sets
fn loadGltfTexcoords(fileName: [*c]const u8, accessor: *const cgltf_accessor, index: c_int, mesh: *Mesh) error{OutOfMemory}!void {
    var texcoords: ?[]f32 = null;
    if (accessor.type == cgltf_type_vec2) {
        texcoords = switch (accessor.component_type) {
            cgltf_component_type_r_32f => try accessorFloats(f32, accessor, 2, null),
            cgltf_component_type_r_8u => try accessorFloats(u8, accessor, 2, 255.0),
            cgltf_component_type_r_16u => try accessorFloats(u16, accessor, 2, 65535.0),
            else => null,
        };
        if (texcoords == null) TraceLog(LOG_WARNING, "MODEL: [%s] Texcoords attribute data format not supported", fileName);
    } else TraceLog(LOG_WARNING, "MODEL: [%s] Texcoords attribute data format not supported, use vec2 float", fileName);

    const ptr: [*c]f32 = if (texcoords) |t| t.ptr else null;
    switch (index) {
        0 => mesh.texcoords = ptr,
        1 => mesh.texcoords2 = ptr,
        else => {
            TraceLog(LOG_WARNING, "MODEL: [%s] No more than 2 texture coordinates attributes supported", fileName);
            cmem.free(ptr);
        },
    }
}

// COLOR_n: vec3 (RGB) or vec4 (RGBA) of u8n, u16n or float, to 8-bit RGBA
// NOTE: The glTF spec requires colors clamped to [0.0, 1.0]
fn loadGltfColors(fileName: [*c]const u8, accessor: *const cgltf_accessor, mesh: *Mesh) error{OutOfMemory}!void {
    if (mesh.colors != null) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Colors attribute data already loaded", fileName);
        return;
    }

    const components: usize = switch (accessor.type) {
        cgltf_type_vec3 => 3,
        cgltf_type_vec4 => 4,
        else => {
            TraceLog(LOG_WARNING, "MODEL: [%s] Color attribute data format not supported", fileName);
            return;
        },
    };

    const colors = switch (accessor.component_type) {
        cgltf_component_type_r_8u => try accessorColors(u8, accessor, components),
        cgltf_component_type_r_16u => try accessorColors(u16, accessor, components),
        cgltf_component_type_r_32f => try accessorColors(f32, accessor, components),
        else => {
            TraceLog(LOG_WARNING, "MODEL: [%s] Color attribute data format not supported", fileName);
            return;
        },
    };
    mesh.colors = colors.ptr;
}

/// A color accessor's values as RGBA bytes; RGB colors get an opaque alpha
fn accessorColors(comptime T: type, accessor: *const cgltf_accessor, components: usize) error{OutOfMemory}![]u8 {
    const colors = try cmem.alloc(u8, accessor.count * 4);
    var values: AccessorValues(T) = .init(accessor, components);
    for (0..accessor.count) |i| {
        const color = colors[i * 4 ..][0..4];
        for (color[0..components]) |*channel| channel.* = colorChannel(T, values.next().?);
        if (components == 3) color[3] = 255;
    }
    return colors;
}

fn colorChannel(comptime T: type, value: T) u8 {
    return switch (T) {
        u8 => value,
        u16 => cByte((@as(f32, @floatFromInt(value)) / 65535.0) * 255.0),
        f32 => cByte(value * 255.0),
        else => @compileError("unsupported color component type"),
    };
}

/// Loads a primitive's bone joints and weights into `mesh`; whether it has joints
fn loadGltfSkinData(fileName: [*c]const u8, primitive: *const cgltf_primitive, mesh: *Mesh) error{OutOfMemory}!bool {
    var hasJoints = false;
    const valueCount = count(mesh.vertexCount) * 4;

    // NOTE: JOINTS_1 + WEIGHTS_1 (more than 4 bones per vertex) are not supported
    for (cgltfItems(cgltf_attribute, primitive.attributes, primitive.attributes_count)) |attribute| {
        const accessor = attribute.data;
        switch (attribute.type) {
            // JOINTS_n: vec4 of u8 or u16. raylib stores u8 bone indices: wider
            // ones are truncated, with a warning
            cgltf_attribute_type_joints => {
                hasJoints = true;
                if (accessor.type != cgltf_type_vec4) {
                    TraceLog(LOG_WARNING, "MODEL: [%s] Joint attribute data format not supported", fileName);
                    continue;
                }
                switch (accessor.component_type) {
                    cgltf_component_type_r_8u => {
                        const boneIndices = try cmem.alloc(u8, valueCount);
                        mesh.boneIndices = boneIndices.ptr;
                        var values: AccessorValues(u8) = .init(accessor, 4);
                        values.read(boneIndices);
                    },
                    cgltf_component_type_r_16u => {
                        const boneIndices = try cmem.alloc(u8, valueCount);
                        mesh.boneIndices = boneIndices.ptr;
                        var values: AccessorValues(u16) = .init(accessor, 4);
                        var overflowWarned = false;
                        for (boneIndices) |*boneIndex| {
                            // NOTE: C reads a zeroed scratch buffer: missing values are 0
                            const value = values.next() orelse 0;
                            if ((value > 255) and !overflowWarned) {
                                TraceLog(LOG_WARNING, "MODEL: [%s] Joint attribute data format (u16) overflow", fileName);
                                overflowWarned = true;
                            }
                            // Despite the possible overflow, convert to unsigned char
                            boneIndex.* = @truncate(value);
                        }
                    },
                    else => TraceLog(LOG_WARNING, "MODEL: [%s] Joint attribute data format not supported", fileName),
                }
            },
            // WEIGHTS_n: vec4 of u8n, u16n or float
            cgltf_attribute_type_weights => {
                const supported = switch (accessor.component_type) {
                    cgltf_component_type_r_8u, cgltf_component_type_r_16u, cgltf_component_type_r_32f => true,
                    else => false,
                };
                if ((accessor.type != cgltf_type_vec4) or !supported) {
                    TraceLog(LOG_WARNING, "MODEL: [%s] Joint weight attribute data format not supported, use vec4 float", fileName);
                    continue;
                }

                const boneWeights = try cmem.alloc(f32, valueCount);
                mesh.boneWeights = boneWeights.ptr;
                switch (accessor.component_type) {
                    cgltf_component_type_r_8u => readAccessorFloats(u8, accessor, 4, boneWeights, 255.0),
                    cgltf_component_type_r_16u => readAccessorFloats(u16, accessor, 4, boneWeights, 65535.0),
                    else => readAccessorFloats(f32, accessor, 4, boneWeights, null),
                }
            },
            else => {},
        }
    }

    return hasJoints;
}

/// Binds every vertex of `mesh` fully to the skin joint `node`, if it is one
fn attachToBone(mesh: *Mesh, skin: cgltf_skin, boneCount: c_uint, node: *cgltf_node) error{OutOfMemory}!void {
    const joints = cgltfItems(*cgltf_node, skin.joints, skin.joints_count)[0..boneCount];
    const bone = std.mem.indexOfScalar(*cgltf_node, joints, node) orelse return;

    // Replaces any bone weights the primitive had without joints
    const valueCount = count(mesh.vertexCount) * 4;
    const boneIndices = try cmem.alloc(u8, valueCount);
    cmem.free(mesh.boneIndices);
    mesh.boneIndices = boneIndices.ptr;
    const boneWeights = try cmem.alloc(f32, valueCount);
    cmem.free(mesh.boneWeights);
    mesh.boneWeights = boneWeights.ptr;

    var i: usize = 0;
    while (i < valueCount) : (i += 4) {
        boneIndices[i] = @truncate(bone);
        boneWeights[i] = 1.0;
    }
}

/// The bones of the skin, and their bind pose from the inverse bind matrices
/// (or the joints' world transforms when there are none)
fn loadGltfSkeleton(model: *Model, skin: cgltf_skin) error{OutOfMemory}!void {
    const bones = try loadBoneInfoGltf(skin);
    model.skeleton.bones = bones.ptr;
    model.skeleton.boneCount = @intCast(bones.len);
    const bindPose = try cmem.alloc(Transform, bones.len);
    model.skeleton.bindPose = bindPose.ptr;

    const joints = cgltfItems(*cgltf_node, skin.joints, skin.joints_count);
    for (bindPose, joints, 0..) |*pose, joint, i| {
        var inverseBindTransform = std.mem.zeroes([16]cgltf_float);
        const bindMatrix = if ((skin.inverse_bind_matrices != null) and
            (skin.inverse_bind_matrices.?.count >= skin.joints_count) and
            (cgltf_accessor_read_float(skin.inverse_bind_matrices.?, i, &inverseBindTransform, 16) != 0))
            MatrixInvert(matrixFromGltf(inverseBindTransform))
        else
            nodeWorldMatrix(joint);

        MatrixDecompose(bindMatrix, &pose.translation, &pose.rotation, &pose.scale);
    }
}

/// Samples an animation sampler at `time` into `out` (3 floats for vec3
/// outputs, 4 for quaternions). Returns false if the sampler can't be read.
fn getPoseAtTimeGltf(sampler: *const cgltf_animation_sampler, time: f32, out: []f32) bool {
    var interpolation = sampler.interpolation;
    if (interpolation >= cgltf_interpolation_type_max_enum) return false;

    const input = sampler.input;
    const output = sampler.output;

    // Find the keyframe interval containing `time` (input and output have the same count)
    var tstart: f32 = 0.0;
    var tend: f32 = 0.0;
    var keyframe: usize = 0; // Defaults to the first pose
    var found = false;

    const keyCount: c_int = @intCast(input.count);
    var i: usize = 0;
    while (@as(c_int, @intCast(i)) < keyCount - 1) : (i += 1) {
        if (cgltf_accessor_read_float(input, i, (&tstart)[0..1], 1) == 0) return false;
        if (cgltf_accessor_read_float(input, i + 1, (&tend)[0..1], 1) == 0) return false;

        if ((tstart <= time) and (time < tend)) {
            keyframe = i;
            found = true;
            break;
        }
    }

    // No interval contains a time at (or past) the last keyframe, because the
    // search requires time < tend: clamp to the edge interval instead of falling
    // back to keyframe 0, which would return a pose from the start
    if (!found and (keyCount >= 2)) {
        keyframe = @intCast(keyCount - 2);

        var tfirst: f32 = 0.0;
        if (cgltf_accessor_read_float(input, 0, (&tfirst)[0..1], 1) == 0) return false;
        if (time < tfirst) keyframe = 0;

        if (cgltf_accessor_read_float(input, keyframe, (&tstart)[0..1], 1) == 0) return false;
        if (cgltf_accessor_read_float(input, keyframe + 1, (&tend)[0..1], 1) == 0) return false;
    }

    // Constant animation, no need to interpolate
    if (FloatEquals(tend, tstart) != 0) interpolation = cgltf_interpolation_type_step;

    // C's fmaxf is LLVM maxnum, as @max is
    const duration = @max(tend - tstart, EPSILON);
    var t = (time - tstart) / duration;
    t = if (t < 0.0) 0.0 else t;
    t = if (t > 1.0) 1.0 else t;

    if (output.component_type != cgltf_component_type_r_32f) return false;

    if (output.type == cgltf_type_vec3) {
        const read = struct {
            fn at(accessor: *const cgltf_accessor, index: usize) Vector3 {
                var tmp = [3]f32{ 0, 0, 0 };
                _ = cgltf_accessor_read_float(accessor, index, &tmp, 3);
                return .{ .x = tmp[0], .y = tmp[1], .z = tmp[2] };
            }
        }.at;
        const result: ?Vector3 = switch (interpolation) {
            cgltf_interpolation_type_step => read(output, keyframe),
            cgltf_interpolation_type_linear => Vector3Lerp(read(output, keyframe), read(output, keyframe + 1), t),
            cgltf_interpolation_type_cubic_spline => blk: {
                // Cubic spline outputs are (in-tangent, value, out-tangent) triples
                const v1 = read(output, 3 * keyframe + 1);
                const tangent1 = read(output, 3 * keyframe + 2);
                const v2 = read(output, 3 * (keyframe + 1) + 1);
                const tangent2 = read(output, 3 * (keyframe + 1));
                break :blk Vector3CubicHermite(v1, tangent1, v2, tangent2, t);
            },
            else => null,
        };
        if (result) |r| out[0..3].* = .{ r.x, r.y, r.z };
    } else if (output.type == cgltf_type_vec4) {
        // Only rotations are vec4: quaternions
        const read = struct {
            fn at(accessor: *const cgltf_accessor, index: usize) Vector4 {
                var tmp = [4]f32{ 0, 0, 0, 0 };
                _ = cgltf_accessor_read_float(accessor, index, &tmp, 4);
                return .{ .x = tmp[0], .y = tmp[1], .z = tmp[2], .w = tmp[3] };
            }
        }.at;
        const result: ?Vector4 = switch (interpolation) {
            cgltf_interpolation_type_step => read(output, keyframe),
            cgltf_interpolation_type_linear => QuaternionSlerp(read(output, keyframe), read(output, keyframe + 1), t),
            cgltf_interpolation_type_cubic_spline => blk: {
                var v1 = read(output, 3 * keyframe + 1);
                var outTangent1 = read(output, 3 * keyframe + 2);
                outTangent1.w = 0.0;
                var v2 = read(output, 3 * (keyframe + 1) + 1);
                var inTangent2 = read(output, 3 * (keyframe + 1));
                inTangent2.w = 0.0;

                v1 = QuaternionNormalize(v1);
                v2 = QuaternionNormalize(v2);
                if (Vector4DotProduct(v1, v2) < 0.0) v2 = Vector4Negate(v2);

                outTangent1 = Vector4Scale(outTangent1, duration);
                inTangent2 = Vector4Scale(inTangent2, duration);

                break :blk QuaternionCubicHermiteSpline(v1, outTangent1, v2, inTangent2, t);
            },
            else => null,
        };
        if (result) |r| out[0..4].* = .{ r.x, r.y, r.z, r.w };
    }

    return true;
}

/// The floats of a vector or quaternion, for getPoseAtTimeGltf to write into
fn floatsOf(value: anytype) []f32 {
    return std.mem.bytesAsSlice(f32, std.mem.asBytes(value));
}

const GLTF_FRAMERATE: f32 = 60.0; // glTF animation framerate (frames per second)

/// The animation channels driving one bone
const BoneChannels = struct {
    translate: ?*cgltf_animation_channel = null,
    rotate: ?*cgltf_animation_channel = null,
    scale: ?*cgltf_animation_channel = null,
};

// Load glTF animation data
fn loadModelAnimationsGltf(fileName: [*c]const u8, animCount: [*c]c_int) [*c]ModelAnimation {
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);

    const options = gltfOptions();
    var parsed: ?*cgltf_data = null;
    if (cgltf_parse(&options, fileData, @intCast(dataSize), &parsed) != cgltf_result_success) {
        // NOTE: Deliberately as raylib: the file data is not released here
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load glTF data", fileName);
        animCount.* = 0;
        return null;
    }
    const data = parsed.?;
    defer UnloadFileData(fileData);

    if (cgltf_load_buffers(&options, data, fileName) != cgltf_result_success) {
        // NOTE: Deliberately as raylib: animCount is left untouched, cgltf data not freed
        TraceLog(LOG_INFO, "MODEL: [%s] Failed to load animation buffers", fileName);
        return null;
    }
    defer cgltf_free(data);

    // NOTE: Without a skin animCount is left untouched, as in raylib
    var animations: [*c]ModelAnimation = null;
    const skins = cgltfItems(cgltf_skin, data.skins, data.skins_count);
    if (skins.len > 0) {
        if (gltfAnimations(fileName, data, skins[0], animCount)) |loaded| {
            animations = loaded.ptr;
        } else |err| {
            switch (err) {
                error.JointOffsetBuffer => TraceLog(LOG_WARNING, "MODEL: [%s] Failed to allocate joint offset buffer", fileName),
                error.OutOfMemory => TraceLog(LOG_WARNING, "MODEL: [%s] Failed to allocate memory for glTF animations", fileName),
            }
            animCount.* = 0;
        }
    }

    if (skins.len > 1) TraceLog(LOG_WARNING, "MODEL: [%s] Expected one unique skin to load animation data from, but found %i", fileName, skins.len);

    return animations;
}

fn gltfAnimations(fileName: [*c]const u8, data: *cgltf_data, skin: cgltf_skin, animCount: [*c]c_int) error{ JointOffsetBuffer, OutOfMemory }![]ModelAnimation {
    const gpa = std.heap.c_allocator;
    const joints = cgltfItems(*cgltf_node, skin.joints, skin.joints_count);

    // Per joint, the static transform of any intermediate non-joint nodes
    // between the joint and its nearest joint ancestor: some exporters store
    // bone offsets on dummy parent nodes. Depends only on the skin.
    const extOffset = gpa.alloc(Matrix, joints.len) catch return error.JointOffsetBuffer;
    defer gpa.free(extOffset);
    for (extOffset, joints) |*offset, joint| {
        offset.* = MatrixIdentity();
        var ancestor = joint.parent;
        while (ancestor) |node| : (ancestor = node.parent) {
            if (std.mem.indexOfScalar(*cgltf_node, joints, node) != null) break;

            // The intermediate node's local TRS: scale, then rotation, then translation
            const nodeTransform = transformMatrix(.{
                .translation = .{ .x = node.translation[0], .y = node.translation[1], .z = node.translation[2] },
                .rotation = .{ .x = node.rotation[0], .y = node.rotation[1], .z = node.rotation[2], .w = node.rotation[3] },
                .scale = .{ .x = node.scale[0], .y = node.scale[1], .z = node.scale[2] },
            });
            offset.* = MatrixMultiply(offset.*, nodeTransform);
        }
    }

    const gltfAnims = cgltfItems(cgltf_animation, data.animations, data.animations_count);
    animCount.* = @intCast(gltfAnims.len);
    const animations = try cmem.alloc(ModelAnimation, gltfAnims.len);
    errdefer UnloadModelAnimations(animations.ptr, @intCast(animations.len));

    for (animations, gltfAnims, 0..) |*animation, *animData, a| {
        const bones = try loadBoneInfoGltf(skin);
        defer cmem.free(bones.ptr);
        animation.boneCount = @intCast(bones.len);

        const boneChannels = try gpa.alloc(BoneChannels, bones.len);
        defer gpa.free(boneChannels);
        @memset(boneChannels, .{});

        var animDuration: f32 = 0.0;
        for (cgltfItems(cgltf_animation_channel, animData.channels, animData.channels_count), 0..) |*channel, j| {
            // Skip channels for nodes not in the skeleton
            const boneIndex = std.mem.indexOfScalar(*cgltf_node, joints, channel.target_node orelse continue) orelse continue;

            if (channel.sampler.interpolation != cgltf_interpolation_type_max_enum) {
                switch (channel.target_path) {
                    cgltf_animation_path_type_translation => boneChannels[boneIndex].translate = channel,
                    cgltf_animation_path_type_rotation => boneChannels[boneIndex].rotate = channel,
                    cgltf_animation_path_type_scale => boneChannels[boneIndex].scale = channel,
                    else => TraceLog(LOG_WARNING, "MODEL: [%s] Unsupported target_path on channel %d's sampler for animation %d. Skipping.", fileName, @as(c_uint, @intCast(j)), @as(c_uint, @intCast(a))),
                }
            } else TraceLog(LOG_WARNING, "MODEL: [%s] Invalid interpolation curve encountered for GLTF animation.", fileName);

            // The animation lasts until its latest keyframe
            var time: f32 = 0.0;
            const input = channel.sampler.input;
            if (cgltf_accessor_read_float(input, input.count -% 1, (&time)[0..1], 1) == 0) {
                TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load input time", fileName);
                continue;
            }
            animDuration = if (time > animDuration) time else animDuration;
        }

        if (animData.name) |name| _ = copyCString(&animation.name, name);

        const keyframeCount = cInt(animDuration * GLTF_FRAMERATE) + 1;
        const keyframePoses = try cmem.alloc(ModelAnimPose, count(keyframeCount));
        animation.keyframePoses = keyframePoses.ptr;
        animation.keyframeCount = keyframeCount;

        for (keyframePoses, 0..) |*keyframePose, frame| {
            const poses = try cmem.alloc(Transform, bones.len);
            keyframePose.* = poses.ptr;
            const time = @as(f32, @floatFromInt(frame)) / GLTF_FRAMERATE;

            for (poses, joints[0..bones.len], boneChannels, bones, extOffset[0..bones.len]) |*pose, joint, channels, bone, offset| {
                var translation = Vector3{ .x = joint.translation[0], .y = joint.translation[1], .z = joint.translation[2] };
                var rotation = Quaternion{ .x = joint.rotation[0], .y = joint.rotation[1], .z = joint.rotation[2], .w = joint.rotation[3] };
                var scale = Vector3{ .x = joint.scale[0], .y = joint.scale[1], .z = joint.scale[2] };

                if (channels.translate) |channel| {
                    if (!getPoseAtTimeGltf(channel.sampler, time, floatsOf(&translation))) TraceLog(LOG_INFO, "MODEL: [%s] Failed to load translate pose data for bone %s", fileName, &bone.name);
                }
                if (channels.rotate) |channel| {
                    if (!getPoseAtTimeGltf(channel.sampler, time, floatsOf(&rotation))) TraceLog(LOG_INFO, "MODEL: [%s] Failed to load rotate pose data for bone %s", fileName, &bone.name);
                }
                if (channels.scale) |channel| {
                    if (!getPoseAtTimeGltf(channel.sampler, time, floatsOf(&scale))) TraceLog(LOG_INFO, "MODEL: [%s] Failed to load scale pose data for bone %s", fileName, &bone.name);
                }

                // The joint's local TRS, then the static intermediate offsets, so the
                // pose is relative to the joint's skeleton parent
                const jointLocal = transformMatrix(.{ .translation = translation, .rotation = rotation, .scale = scale });
                const combined = MatrixMultiply(jointLocal, offset);
                MatrixDecompose(combined, &pose.translation, &pose.rotation, &pose.scale);
            }

            buildPoseFromParentJoints(bones, poses);
        }

        const name: [*:0]const u8 = animData.name orelse "NULL";
        TraceLog(LOG_INFO, "MODEL: [%s] Loaded animation: %s | Frames: %d | Duration: %fs", fileName, name, animation.keyframeCount, @as(f64, animDuration));
    }

    return animations;
}

//----------------------------------------------------------------------------------
// VOX loader
//----------------------------------------------------------------------------------

// Load VOX (MagicaVoxel) mesh data
fn loadVox(fileName: [*c]const u8) Model {
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);
    if (fileData == null) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load VOX file", fileName);
        return empty_model;
    }
    defer UnloadFileData(fileData);

    var voxarray = std.mem.zeroes(VoxArray3D);
    if (Vox_LoadFromMemory(fileData, @intCast(dataSize), &voxarray) != VOX_SUCCESS) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load VOX data", fileName);
        return empty_model;
    }
    defer Vox_FreeArrays(&voxarray);

    // NOTE: Deliberately as raylib: one mesh per 65536 vertices, although
    // each mesh holds at most 65532 (see voxModel)
    const vertexCount = voxarray.vertices.used;
    const meshCount = 1 + @divTrunc(vertexCount, 65536);
    TraceLog(LOG_INFO, "MODEL: [%s] VOX data loaded successfully : %i vertices/%i meshes", fileName, vertexCount, meshCount);

    return voxModel(voxarray, count(meshCount)) catch {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to allocate memory for VOX data", fileName);
        return empty_model;
    };
}

fn voxModel(voxarray: VoxArray3D, meshCount: usize) error{OutOfMemory}!Model {
    var model = empty_model;
    errdefer freeModelData(model);
    model.transform = MatrixIdentity();

    model.meshCount = @intCast(meshCount);
    model.meshes = (try cmem.alloc(Mesh, meshCount)).ptr;
    model.meshMaterial = (try cmem.alloc(c_int, meshCount)).ptr; // All use the first material

    model.materialCount = 1;
    model.materials = (try cmem.alloc(Material, 1)).ptr;
    model.materials[0] = LoadMaterialDefault();

    // 5461 voxels x 12 vertices per voxel -> 65532 (must be less than 65536)
    const verticesMax = 65532;
    const vertices = voxarray.vertices.array.?[0..count(voxarray.vertices.used)];
    const normals = voxarray.normals.array.?;
    const colors = voxarray.colors.array.?;
    // NOTE: Deliberately as raylib: every mesh gets all the indices (at most 5461*6*6)
    const indices = voxarray.indices.array.?[0..count(voxarray.indices.used)];

    for (modelMeshes(model), 0..) |*mesh, i| {
        const first = i * verticesMax;
        const vertexCount: usize = @min(verticesMax, vertices.len - first);
        mesh.vertexCount = @intCast(vertexCount);
        mesh.triangleCount = @intCast(vertexCount / 4 * 2);

        const meshVertices = try cmem.alloc(f32, vertexCount * 3);
        mesh.vertices = meshVertices.ptr;
        @memcpy(std.mem.sliceAsBytes(meshVertices), std.mem.sliceAsBytes(vertices[first..][0..vertexCount]));

        const meshNormals = try cmem.alloc(f32, vertexCount * 3);
        mesh.normals = meshNormals.ptr;
        @memcpy(std.mem.sliceAsBytes(meshNormals), std.mem.sliceAsBytes(normals[first..][0..vertexCount]));

        const meshIndices = try cmem.alloc(c_ushort, indices.len);
        mesh.indices = meshIndices.ptr;
        @memcpy(meshIndices, indices);

        const meshColors = try cmem.alloc(u8, vertexCount * 4);
        mesh.colors = meshColors.ptr;
        @memcpy(meshColors, std.mem.sliceAsBytes(colors[first..][0..vertexCount]));
    }

    return model;
}

//----------------------------------------------------------------------------------
// M3D loader
//----------------------------------------------------------------------------------

// Hook LoadFileData()/UnloadFileData() calls to M3D loaders
fn m3dLoaderHook(fileName: [*:0]u8, len: *c_uint) callconv(.c) ?[*]u8 {
    return LoadFileData(fileName, @ptrCast(len));
}
fn m3dFreeHook(data: ?*anyopaque) callconv(.c) void {
    UnloadFileData(@ptrCast(data));
}

/// m3d's model data, with the file data it was loaded from
const M3dFile = struct {
    fileData: [*c]u8,
    m3d: *m3d_t,

    fn deinit(file: M3dFile) void {
        m3d_free(file.m3d);
        UnloadFileData(file.fileData);
    }
};

/// Loads and parses an M3D file, logging why it can't be used
fn openM3d(fileName: [*c]const u8) ?M3dFile {
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);
    if (fileData == null) return null;

    const m3d = m3d_load(fileData, m3dLoaderHook, m3dFreeHook, null);
    if ((m3d == null) or M3D_ERR_ISFATAL(m3d.?.errcode)) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load M3D data, error code %d", fileName, if (m3d) |model| @as(c_int, model.errcode) else -2);
        if (m3d) |model| m3d_free(model);
        UnloadFileData(fileData);
        return null;
    }
    return .{ .fileData = fileData, .m3d = m3d.? };
}

// Load M3D mesh data
fn loadM3d(fileName: [*c]const u8) Model {
    const file = openM3d(fileName) orelse return empty_model;
    defer file.deinit();
    const m3d = file.m3d;

    TraceLog(LOG_INFO, "MODEL: [%s] M3D data loaded successfully: %i faces/%i materials", fileName, m3d.numface, m3d.nummaterial);

    // No faces: probably just a material library
    if (m3d.numface == 0) return empty_model;

    return m3dModel(m3d) catch {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to allocate memory for M3D data", fileName);
        return empty_model;
    };
}

fn m3dModel(m3d: *const m3d_t) error{OutOfMemory}!Model {
    var model = empty_model;
    errdefer freeModelData(model);

    // One mesh per material, or one in the default material
    if (m3d.nummaterial > 0) {
        model.meshCount = @intCast(m3d.nummaterial);
        model.materialCount = model.meshCount;
        TraceLog(LOG_INFO, "MODEL: model has %i material meshes", model.materialCount);
    } else {
        model.meshCount = 1;
        model.materialCount = 0;
        TraceLog(LOG_INFO, "MODEL: No materials, putting all meshes in a default material");
    }

    // A default material is always required, so adding +1
    model.materialCount += 1;

    // NOTE: Faces must be sorted by material id, as valid M3D files are
    model.meshes = (try cmem.alloc(Mesh, count(model.meshCount))).ptr;
    model.meshMaterial = (try cmem.alloc(c_int, count(model.meshCount))).ptr;
    // NOTE: Deliberately as raylib: one slot more than materialCount
    model.materials = (try cmem.alloc(Material, count(model.materialCount) + 1)).ptr;

    // Map no material to index 0 with default shader, everything else materialid + 1
    model.materials[0] = LoadMaterialDefault();

    const faces = m3d.face.?[0..m3d.numface];
    const vertices = m3d.vertex.?;
    const skinned = (m3d.numbone != 0) and (m3d.numskin != 0);

    var materialId: M3D_INDEX = @bitCast(@as(i32, -2)); // No material read yet
    var meshIndex: usize = 0;
    var start: usize = 0;
    while (start < faces.len) {
        // A run of faces with the same material makes one mesh
        materialId = faces[start].materialid;
        var end = start;
        var vcolor = false;
        while ((end < faces.len) and (faces[end].materialid == materialId)) : (end += 1) {
            // Vertex colors only if some vertex isn't fully transparent black
            for (faces[end].vertex) |v| {
                if (vertices[v].color == 0) vcolor = true;
            }
        }

        // There should be one run per material, but be bulletproof for non-optimal files
        if (meshIndex >= count(model.meshCount)) try growMeshes(&model);

        try fillM3dMesh(&modelMeshes(model)[meshIndex], m3d, faces[start..end], materialId, vcolor, skinned);
        // NOTE: M3D_UNDEF + 1 wraps to 0, the default material
        model.meshMaterial[meshIndex] = @as(c_int, @bitCast(materialId)) +% 1;

        meshIndex += 1;
        start = end;
    }

    for (cgltfItems(m3dm_t, m3d.material, m3d.nummaterial), model.materials[1 .. m3d.nummaterial + 1]) |m3dMaterial, *material| {
        material.* = LoadMaterialDefault();
        loadM3dMaterial(m3d, m3dMaterial, material.maps);
    }

    if (m3d.numbone != 0) try loadM3dSkeleton(&model, m3d);

    // Bone-pose data, updated by UpdateModelAnimation
    if (skinned) {
        for (modelMeshes(model)) |*mesh| mesh.boneCount = @bitCast(model.skeleton.boneCount);
        try initAnimationState(&model);
    }

    return model;
}

/// One more mesh (and mesh material), zeroed
fn growMeshes(model: *Model) error{OutOfMemory}!void {
    const meshCount = count(model.meshCount) + 1;
    const grownMeshes = try cmem.realloc(Mesh, model.meshes, meshCount);
    model.meshes = grownMeshes.ptr;
    grownMeshes[meshCount - 1] = empty_mesh;
    const meshMaterial = try cmem.realloc(c_int, model.meshMaterial, meshCount);
    model.meshMaterial = meshMaterial.ptr;
    meshMaterial[meshCount - 1] = 0;
    model.meshCount = @intCast(meshCount);
}

/// Builds the mesh for a run of faces sharing one material
fn fillM3dMesh(mesh: *Mesh, m3d: *const m3d_t, faces: []const m3df_t, materialId: M3D_INDEX, vcolor: bool, skinned: bool) error{OutOfMemory}!void {
    const vertices = m3d.vertex.?;
    const scale = m3d.scale;
    const vertexCount = faces.len * 3;

    mesh.vertexCount = @intCast(vertexCount);
    mesh.triangleCount = @intCast(faces.len);
    const meshVertices = try cmem.alloc(f32, vertexCount * 3);
    mesh.vertices = meshVertices.ptr;
    const texcoords = try cmem.alloc(f32, vertexCount * 2);
    mesh.texcoords = texcoords.ptr;
    const normals = try cmem.alloc(f32, vertexCount * 3);
    mesh.normals = normals.ptr;

    // M3D only uses vertex colors when there is no material; raylib uses both
    // and mixes the colors. Without a material they start white.
    const colors: ?[]u8 = if ((materialId == M3D_UNDEF) or vcolor) try cmem.alloc(u8, vertexCount * 4) else null;
    if (colors) |c| {
        mesh.colors = c.ptr;
        if (materialId == M3D_UNDEF) @memset(c, 255);
    }

    if (skinned) {
        mesh.boneIndices = (try cmem.alloc(u8, vertexCount * 4)).ptr;
        mesh.boneWeights = (try cmem.alloc(f32, vertexCount * 4)).ptr;
    }

    for (faces, 0..) |face, l| {
        for (face.vertex, 0..) |v, n| {
            const vertex = vertices[v];
            meshVertices[l * 9 + n * 3 ..][0..3].* = .{ vertex.x * scale, vertex.y * scale, vertex.z * scale };

            // A fully transparent vertex color keeps the default
            if (colors) |c| {
                if (vertex.color & 0xff000000 != 0) c[l * 12 + n * 4 ..][0..4].* = @bitCast(vertex.color);
            }
        }

        if (face.texcoord[0] != M3D_UNDEF) {
            for (face.texcoord, 0..) |t, n| {
                const uv = m3d.tmap.?[t];
                texcoords[l * 6 + n * 2 ..][0..2].* = .{ uv.u, 1.0 - uv.v };
            }
        }

        if (face.normal[0] != M3D_UNDEF) {
            for (face.normal, 0..) |index, n| {
                const normal = vertices[index];
                normals[l * 9 + n * 3 ..][0..3].* = .{ normal.x, normal.y, normal.z };
            }
        }

        // Skin: vertex / bone weight pairs
        if (skinned) {
            for (face.vertex, 0..) |v, n| {
                const first = l * 12 + n * 4;
                const skinid = vertices[v].skinid;
                if ((skinid != M3D_UNDEF) and (@as(i32, @bitCast(skinid)) < @as(i32, @bitCast(m3d.numskin)))) {
                    const skin = m3d.skin.?[skinid];
                    // NOTE: C stores the 32-bit bone ids into bytes: unused slots
                    // (M3D_UNDEF) become 255
                    for (mesh.boneIndices[first..][0..4], skin.boneid) |*boneIndex, boneId| boneIndex.* = @truncate(boneId);
                    @memcpy(mesh.boneWeights[first..][0..4], &skin.weight);
                } else {
                    // Boneless vertices with skeletal animations are not supported:
                    // they go to a special "no bone" bone
                    mesh.boneIndices[first] = @truncate(m3d.numbone);
                    mesh.boneWeights[first] = 1.0;
                }
            }
        }
    }
}

/// An m3d color (RGBA bytes in a native-endian u32), as raylib memcpy's it into a Color
fn m3dColor(value: u32) Color {
    return std.mem.bytesToValue(Color, std.mem.asBytes(&value));
}

fn loadM3dMaterial(m3d: *const m3d_t, m3dMaterial: m3dm_t, maps: [*c]MaterialMap) void {
    for (cgltfItems(m3dp_t, m3dMaterial.prop, m3dMaterial.numprop)) |prop| {
        switch (prop.type) {
            m3dp_Kd => {
                maps[MATERIAL_MAP_DIFFUSE].color = m3dColor(prop.value.color);
                maps[MATERIAL_MAP_DIFFUSE].value = 0.0;
            },
            m3dp_Ks => maps[MATERIAL_MAP_SPECULAR].color = m3dColor(prop.value.color),
            m3dp_Ns => maps[MATERIAL_MAP_SPECULAR].value = prop.value.fnum,
            m3dp_Ke => {
                maps[MATERIAL_MAP_EMISSION].color = m3dColor(prop.value.color);
                maps[MATERIAL_MAP_EMISSION].value = 0.0;
            },
            m3dp_Pm => maps[MATERIAL_MAP_METALNESS].value = prop.value.fnum,
            m3dp_Pr => maps[MATERIAL_MAP_ROUGHNESS].value = prop.value.fnum,
            m3dp_Ps => {
                maps[MATERIAL_MAP_NORMAL].color = WHITE;
                maps[MATERIAL_MAP_NORMAL].value = prop.value.fnum;
            },
            else => {
                // Texture maps
                if (prop.type < 128) continue;
                const map: usize = switch (prop.type) {
                    m3dp_map_Kd => MATERIAL_MAP_DIFFUSE,
                    m3dp_map_Ks => MATERIAL_MAP_SPECULAR,
                    m3dp_map_Ke => MATERIAL_MAP_EMISSION,
                    m3dp_map_Km => MATERIAL_MAP_NORMAL,
                    m3dp_map_Ka => MATERIAL_MAP_OCCLUSION,
                    m3dp_map_Pm => MATERIAL_MAP_ROUGHNESS,
                    else => continue,
                };
                const texture = m3d.texture.?[prop.value.textureid];
                const image: Image = .{
                    .data = texture.d,
                    .width = texture.w,
                    .height = texture.h,
                    .mipmaps = 1,
                    .format = switch (texture.f) {
                        4 => PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
                        3 => PIXELFORMAT_UNCOMPRESSED_R8G8B8,
                        2 => PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA,
                        else => PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
                    },
                };
                maps[map].texture = LoadTextureFromImage(image);
            },
        }
    }
}

/// An m3d name as raylib's snprintf("%s") formats it: glibc prints a null string as "(null)"
fn m3dCString(name: ?[*:0]const u8) [*:0]const u8 {
    return name orelse "(null)";
}

/// An M3D bone pose in model space: positions and orientations are vertices,
/// and child bones are relative to their parent
fn m3dBoneTransform(m3d: *const m3d_t, pos: M3D_INDEX, ori: M3D_INDEX) Transform {
    const vertices = m3d.vertex.?;
    const position = vertices[pos];
    const orientation = vertices[ori];
    return .{
        .translation = .{ .x = position.x * m3d.scale, .y = position.y * m3d.scale, .z = position.z * m3d.scale },
        // NOTE: A non-normalized orientation quaternion encodes scaling
        .rotation = QuaternionNormalize(.{ .x = orientation.x, .y = orientation.y, .z = orientation.z, .w = orientation.w }),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    };
}

/// Child bones are stored relative to their parent: converts `pose[bone]` to model space
fn m3dToModelSpace(pose: []Transform, bone: usize, parent: c_int) void {
    if (parent < 0) return;
    const transform = &pose[bone];
    const parentTransform = &pose[@intCast(parent)];
    transform.rotation = QuaternionMultiply(parentTransform.rotation, transform.rotation);
    transform.translation = Vector3RotateByQuaternion(transform.translation, parentTransform.rotation);
    transform.translation = Vector3Add(transform.translation, parentTransform.translation);
    transform.scale = Vector3Multiply(transform.scale, parentTransform.scale);
}

const no_bone_transform: Transform = .{
    .translation = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    .rotation = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
    .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
};

/// The model's bones, plus a final "no bone" bone for boneless vertices
fn m3dBones(m3d: *const m3d_t) error{OutOfMemory}![]BoneInfo {
    const bones = try cmem.alloc(BoneInfo, m3d.numbone + 1);
    for (bones[0..m3d.numbone], m3d.bone.?) |*bone, m3dBone| {
        bone.parent = @bitCast(m3dBone.parent);
        _ = copyCString(&bone.name, m3dCString(m3dBone.name));
    }
    const noBone = &bones[m3d.numbone];
    noBone.parent = -1;
    @memcpy(noBone.name[0..7], "NO BONE");
    return bones;
}

fn loadM3dSkeleton(model: *Model, m3d: *const m3d_t) error{OutOfMemory}!void {
    const bones = try m3dBones(m3d);
    model.skeleton.bones = bones.ptr;
    model.skeleton.boneCount = @intCast(bones.len);
    const bindPose = try cmem.alloc(Transform, bones.len);
    model.skeleton.bindPose = bindPose.ptr;

    for (m3d.bone.?[0..m3d.numbone], bones[0..m3d.numbone], 0..) |m3dBone, bone, i| {
        bindPose[i] = m3dBoneTransform(m3d, m3dBone.pos, m3dBone.ori);
        m3dToModelSpace(bindPose, i, bone.parent);
    }
    bindPose[m3d.numbone] = no_bone_transform;
}

const M3D_ANIMDELAY: u32 = 17; // Animation frames delay, (~1000 ms/60 FPS = 16.666666 ms)

// Load M3D animation data
fn loadModelAnimationsM3d(fileName: [*c]const u8, animCount: [*c]c_int) [*c]ModelAnimation {
    animCount.* = 0;

    const file = openM3d(fileName) orelse return null;
    defer file.deinit();
    const m3d = file.m3d;

    TraceLog(LOG_INFO, "MODEL: [%s] M3D data loaded successfully: %i animations, %i bones, %i skins", fileName, m3d.numaction, m3d.numbone, m3d.numskin);

    // No animation or bones: skins are not required, some use one animation for N models
    if ((m3d.numaction == 0) or (m3d.numbone == 0)) return null;

    const animations = m3dAnimations(fileName, m3d, animCount) catch {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to allocate memory for M3D animations", fileName);
        animCount.* = 0;
        return null;
    };
    return animations.ptr;
}

fn m3dAnimations(fileName: [*c]const u8, m3d: *m3d_t, animCount: [*c]c_int) error{OutOfMemory}![]ModelAnimation {
    const animations = try cmem.alloc(ModelAnimation, m3d.numaction);
    errdefer UnloadModelAnimations(animations.ptr, @intCast(animations.len));
    animCount.* = @intCast(m3d.numaction);

    for (animations, m3d.action.?[0..m3d.numaction], 0..) |*animation, action, a| {
        animation.boneCount = m3d.numbone + 1;
        const bones = try m3dBones(m3d);
        defer cmem.free(bones.ptr);

        const keyframePoses = try cmem.alloc(ModelAnimPose, action.durationmsec / M3D_ANIMDELAY);
        animation.keyframePoses = keyframePoses.ptr;
        animation.keyframeCount = @intCast(keyframePoses.len);
        _ = copyCString(&animation.name, m3dCString(action.name));

        // NOTE: Upstream bug kept: the duration is an unsigned int printed with
        // "%f", so the logged value is undefined
        TraceLog(LOG_INFO, "MODEL: [%s] Loaded animation: %s | Frames: %d | Duration: %fs", fileName, &animation.name, animation.keyframeCount, action.durationmsec);

        // M3D stores sparse skeletons at arbitrary times; raylib needs full ones
        // at regular intervals, so the M3D SDK interpolates the bones
        for (keyframePoses, 0..) |*keyframePose, frame| {
            const pose = try cmem.alloc(Transform, bones.len);
            keyframePose.* = pose.ptr;

            const m3dPose = m3d_pose(m3d, @intCast(a), @as(u32, @intCast(frame)) * M3D_ANIMDELAY) orelse continue;
            defer cmem.free(m3dPose);

            for (m3dPose[0..m3d.numbone], bones[0..m3d.numbone], 0..) |m3dBone, bone, j| {
                pose[j] = m3dBoneTransform(m3d, m3dBone.pos, m3dBone.ori);
                m3dToModelSpace(pose, j, bone.parent);
            }
            // The "no bone" bone is never transformed
            pose[m3d.numbone] = no_bone_transform;
        }
    }

    return animations;
}
