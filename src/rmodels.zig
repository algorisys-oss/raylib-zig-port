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
extern fn fabsf(f32) f32;
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
const MAX_MATERIAL_MAPS: c_int = 12;
/// Mirrors config.h `SUPPORT_GPU_SKINNING` (on by default since raylib 6.2): bone
/// indices/weights get their own VBOs and are bound to the shader on draw.
const SUPPORT_GPU_SKINNING = true;

// NOTE: GPU skinning needs two additional vertex buffers (bone indices and weights)
const MAX_MESH_VERTEX_BUFFERS: c_int = if (SUPPORT_GPU_SKINNING) 9 else 7;
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
    points: [*c]f32,
    npoints: c_int,
    triangles: [*c]c_ushort,
    ntriangles: c_int,
    normals: [*c]f32,
    tcoords: [*c]f32,
};
extern fn par_shapes_free_mesh(mesh: ?*par_shapes_mesh) void;
extern fn par_shapes_create_cylinder(slices: c_int, stacks: c_int) ?*par_shapes_mesh;
extern fn par_shapes_create_cone(slices: c_int, stacks: c_int) ?*par_shapes_mesh;
extern fn par_shapes_create_torus(slices: c_int, stacks: c_int, radius: f32) ?*par_shapes_mesh;
extern fn par_shapes_create_parametric_sphere(slices: c_int, stacks: c_int) ?*par_shapes_mesh;
extern fn par_shapes_create_trefoil_knot(slices: c_int, stacks: c_int, radius: f32) ?*par_shapes_mesh;
extern fn par_shapes_create_hemisphere(slices: c_int, stacks: c_int) ?*par_shapes_mesh;
extern fn par_shapes_create_plane(slices: c_int, stacks: c_int) ?*par_shapes_mesh;
extern fn par_shapes_create_disk(radius: f32, slices: c_int, center: [*c]const f32, normal: [*c]const f32) ?*par_shapes_mesh;
extern fn par_shapes_set_epsilon_degenerate_sphere(epsilon: f64) void;
extern fn par_shapes_translate(mesh: ?*par_shapes_mesh, x: f32, y: f32, z: f32) void;
extern fn par_shapes_rotate(mesh: ?*par_shapes_mesh, radians: f32, axis: [*c]const f32) void;
extern fn par_shapes_scale(mesh: ?*par_shapes_mesh, x: f32, y: f32, z: f32) void;
extern fn par_shapes_merge_and_free(dst: ?*par_shapes_mesh, src: ?*par_shapes_mesh) void;
extern fn par_shapes_compute_normals(m: ?*par_shapes_mesh) void;

// ---- tinyobj ----
const tinyobj_vertex_index_t = extern struct { v_idx: c_int, vt_idx: c_int, vn_idx: c_int };
const tinyobj_attrib_t = extern struct {
    num_vertices: c_uint,
    num_normals: c_uint,
    num_texcoords: c_uint,
    num_faces: c_uint,
    num_face_num_verts: c_uint,
    pad0: c_int,
    vertices: [*c]f32,
    normals: [*c]f32,
    texcoords: [*c]f32,
    faces: [*c]tinyobj_vertex_index_t,
    face_num_verts: [*c]c_int,
    material_ids: [*c]c_int,
};
const tinyobj_shape_t = extern struct {
    name: [*c]u8,
    face_offset: c_uint,
    length: c_uint,
};
const tinyobj_material_t = extern struct {
    name: [*c]u8,
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
    ambient_texname: [*c]u8,
    diffuse_texname: [*c]u8,
    specular_texname: [*c]u8,
    specular_highlight_texname: [*c]u8,
    bump_texname: [*c]u8,
    displacement_texname: [*c]u8,
    alpha_texname: [*c]u8,
};
const TINYOBJ_FLAG_TRIANGULATE: c_uint = 1 << 0;
const TINYOBJ_INVALID_INDEX: c_int = @bitCast(@as(c_uint, 0x80000000));
const TINYOBJ_SUCCESS: c_int = 0;
extern fn tinyobj_parse_obj(attrib: [*c]tinyobj_attrib_t, shapes: [*c][*c]tinyobj_shape_t, num_shapes: [*c]c_uint, materials: [*c][*c]tinyobj_material_t, num_materials: [*c]c_uint, buf: [*c]const u8, len: c_uint, flags: c_uint) c_int;
extern fn tinyobj_parse_mtl_file(materials_out: [*c][*c]tinyobj_material_t, num_materials_out: [*c]c_uint, filename: [*c]const u8) c_int;
extern fn tinyobj_attrib_free(attrib: [*c]tinyobj_attrib_t) void;
extern fn tinyobj_shapes_free(shapes: [*c]tinyobj_shape_t, num_shapes: c_uint) void;
extern fn tinyobj_materials_free(materials: [*c]tinyobj_material_t, num_materials: c_uint) void;

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
const cgltf_camera_type = c_int;
const cgltf_light_type = c_int;
const cgltf_filter_type = c_int;
const cgltf_wrap_mode = c_int;

const cgltf_extras = extern struct {
    start_offset: cgltf_size,
    end_offset: cgltf_size,
    data: [*c]u8,
};
const cgltf_extension = extern struct {
    name: [*c]u8,
    data: [*c]u8,
};
const cgltf_memory_options = extern struct {
    alloc_func: ?*const fn (?*anyopaque, cgltf_size) callconv(.c) ?*anyopaque,
    free_func: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
    user_data: ?*anyopaque,
};
const cgltf_file_options = extern struct {
    read: ?*const fn (?*const cgltf_memory_options, ?*const cgltf_file_options, [*c]const u8, [*c]cgltf_size, [*c]?*anyopaque) callconv(.c) cgltf_result,
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
    name: [*c]u8,
    size: cgltf_size,
    uri: [*c]u8,
    data: ?*anyopaque,
    data_free_method: cgltf_data_free_method,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_meshopt_compression = extern struct {
    buffer: [*c]cgltf_buffer,
    offset: cgltf_size,
    size: cgltf_size,
    stride: cgltf_size,
    count: cgltf_size,
    mode: cgltf_meshopt_compression_mode,
    filter: cgltf_meshopt_compression_filter,
    is_khr: cgltf_bool,
};
const cgltf_buffer_view = extern struct {
    name: [*c]u8,
    buffer: [*c]cgltf_buffer,
    offset: cgltf_size,
    size: cgltf_size,
    stride: cgltf_size,
    type: cgltf_buffer_view_type,
    data: ?*anyopaque,
    has_meshopt_compression: cgltf_bool,
    meshopt_compression: cgltf_meshopt_compression,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_accessor_sparse = extern struct {
    count: cgltf_size,
    indices_buffer_view: [*c]cgltf_buffer_view,
    indices_byte_offset: cgltf_size,
    indices_component_type: cgltf_component_type,
    values_buffer_view: [*c]cgltf_buffer_view,
    values_byte_offset: cgltf_size,
};
const cgltf_accessor = extern struct {
    name: [*c]u8,
    component_type: cgltf_component_type,
    normalized: cgltf_bool,
    type: cgltf_type,
    offset: cgltf_size,
    count: cgltf_size,
    stride: cgltf_size,
    buffer_view: [*c]cgltf_buffer_view,
    has_min: cgltf_bool,
    min: [16]cgltf_float,
    has_max: cgltf_bool,
    max: [16]cgltf_float,
    is_sparse: cgltf_bool,
    sparse: cgltf_accessor_sparse,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_attribute = extern struct {
    name: [*c]u8,
    type: cgltf_attribute_type,
    index: cgltf_int,
    data: [*c]cgltf_accessor,
};
const cgltf_image = extern struct {
    name: [*c]u8,
    uri: [*c]u8,
    buffer_view: [*c]cgltf_buffer_view,
    mime_type: [*c]u8,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_sampler = extern struct {
    name: [*c]u8,
    mag_filter: cgltf_filter_type,
    min_filter: cgltf_filter_type,
    wrap_s: cgltf_wrap_mode,
    wrap_t: cgltf_wrap_mode,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_texture = extern struct {
    name: [*c]u8,
    image: [*c]cgltf_image,
    sampler: [*c]cgltf_sampler,
    has_basisu: cgltf_bool,
    basisu_image: [*c]cgltf_image,
    has_webp: cgltf_bool,
    webp_image: [*c]cgltf_image,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_texture_transform = extern struct {
    offset: [2]cgltf_float,
    rotation: cgltf_float,
    scale: [2]cgltf_float,
    has_texcoord: cgltf_bool,
    texcoord: cgltf_int,
};
const cgltf_texture_view = extern struct {
    texture: [*c]cgltf_texture,
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
    name: [*c]u8,
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
    extensions: [*c]cgltf_extension,
};
const cgltf_material_mapping = extern struct {
    variant: cgltf_size,
    material: [*c]cgltf_material,
    extras: cgltf_extras,
};
const cgltf_morph_target = extern struct {
    attributes: [*c]cgltf_attribute,
    attributes_count: cgltf_size,
};
const cgltf_draco_mesh_compression = extern struct {
    buffer_view: [*c]cgltf_buffer_view,
    attributes: [*c]cgltf_attribute,
    attributes_count: cgltf_size,
};
const cgltf_mesh_gpu_instancing = extern struct {
    attributes: [*c]cgltf_attribute,
    attributes_count: cgltf_size,
};
const cgltf_primitive = extern struct {
    type: cgltf_primitive_type,
    indices: [*c]cgltf_accessor,
    material: [*c]cgltf_material,
    attributes: [*c]cgltf_attribute,
    attributes_count: cgltf_size,
    targets: [*c]cgltf_morph_target,
    targets_count: cgltf_size,
    extras: cgltf_extras,
    has_draco_mesh_compression: cgltf_bool,
    draco_mesh_compression: cgltf_draco_mesh_compression,
    mappings: [*c]cgltf_material_mapping,
    mappings_count: cgltf_size,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_mesh = extern struct {
    name: [*c]u8,
    primitives: [*c]cgltf_primitive,
    primitives_count: cgltf_size,
    weights: [*c]cgltf_float,
    weights_count: cgltf_size,
    target_names: [*c][*c]u8,
    target_names_count: cgltf_size,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_node = extern struct {
    name: [*c]u8,
    parent: [*c]cgltf_node,
    children: [*c][*c]cgltf_node,
    children_count: cgltf_size,
    skin: ?*anyopaque,
    mesh: [*c]cgltf_mesh,
    camera: ?*anyopaque,
    light: ?*anyopaque,
    weights: [*c]cgltf_float,
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
    extensions: [*c]cgltf_extension,
};
const cgltf_skin = extern struct {
    name: [*c]u8,
    joints: [*c][*c]cgltf_node,
    joints_count: cgltf_size,
    skeleton: [*c]cgltf_node,
    inverse_bind_matrices: [*c]cgltf_accessor,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_animation_sampler = extern struct {
    input: [*c]cgltf_accessor,
    output: [*c]cgltf_accessor,
    interpolation: cgltf_interpolation_type,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_animation_channel = extern struct {
    sampler: [*c]cgltf_animation_sampler,
    target_node: [*c]cgltf_node,
    target_path: cgltf_animation_path_type,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_animation = extern struct {
    name: [*c]u8,
    samplers: [*c]cgltf_animation_sampler,
    samplers_count: cgltf_size,
    channels: [*c]cgltf_animation_channel,
    channels_count: cgltf_size,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_asset = extern struct {
    copyright: [*c]u8,
    generator: [*c]u8,
    version: [*c]u8,
    min_version: [*c]u8,
    extras: cgltf_extras,
    extensions_count: cgltf_size,
    extensions: [*c]cgltf_extension,
};
const cgltf_data = extern struct {
    file_type: cgltf_file_type,
    file_data: ?*anyopaque,
    file_size: cgltf_size,
    asset: cgltf_asset,
    meshes: [*c]cgltf_mesh,
    meshes_count: cgltf_size,
    materials: [*c]cgltf_material,
    materials_count: cgltf_size,
    accessors: [*c]cgltf_accessor,
    accessors_count: cgltf_size,
    buffer_views: [*c]cgltf_buffer_view,
    buffer_views_count: cgltf_size,
    buffers: [*c]cgltf_buffer,
    buffers_count: cgltf_size,
    images: [*c]cgltf_image,
    images_count: cgltf_size,
    textures: [*c]cgltf_texture,
    textures_count: cgltf_size,
    samplers: [*c]cgltf_sampler,
    samplers_count: cgltf_size,
    skins: [*c]cgltf_skin,
    skins_count: cgltf_size,
    cameras: ?*anyopaque,
    cameras_count: cgltf_size,
    lights: ?*anyopaque,
    lights_count: cgltf_size,
    nodes: [*c]cgltf_node,
    nodes_count: cgltf_size,
    scenes: ?*anyopaque,
    scenes_count: cgltf_size,
    scene: ?*anyopaque,
    animations: [*c]cgltf_animation,
    animations_count: cgltf_size,
    variants: ?*anyopaque,
    variants_count: cgltf_size,
    extras: cgltf_extras,
    data_extensions_count: cgltf_size,
    data_extensions: [*c]cgltf_extension,
    extensions_used: [*c][*c]u8,
    extensions_used_count: cgltf_size,
    extensions_required: [*c][*c]u8,
    extensions_required_count: cgltf_size,
    json: [*c]const u8,
    json_size: cgltf_size,
    bin: ?*const anyopaque,
    bin_size: cgltf_size,
    memory: cgltf_memory_options,
    file: cgltf_file_options,
};
extern fn cgltf_parse(options: ?*const cgltf_options, data: ?*const anyopaque, size: cgltf_size, out_data: [*c][*c]cgltf_data) cgltf_result;
extern fn cgltf_load_buffers(options: ?*const cgltf_options, data: [*c]cgltf_data, gltf_path: [*c]const u8) cgltf_result;
extern fn cgltf_free(data: [*c]cgltf_data) void;
extern fn cgltf_node_transform_world(node: ?*const cgltf_node, out_matrix: [*c]cgltf_float) void;
extern fn cgltf_accessor_read_float(accessor: ?*const cgltf_accessor, index: cgltf_size, out: [*c]cgltf_float, element_size: cgltf_size) cgltf_bool;
extern fn cgltf_load_buffer_base64(options: ?*const cgltf_options, size: cgltf_size, base64: [*c]const u8, out_data: [*c]?*anyopaque) cgltf_result;

// ---- vox_loader ----
const VoxColor = extern struct { r: u8, g: u8, b: u8, a: u8 };
const VoxVector3 = extern struct { x: f32, y: f32, z: f32 };
const ArrayVector3 = extern struct { array: [*c]VoxVector3, used: c_int, size: c_int };
const ArrayColor = extern struct { array: [*c]VoxColor, used: c_int, size: c_int };
const ArrayUShort = extern struct { array: [*c]c_ushort, used: c_int, size: c_int };
const CubeChunk3D = extern struct { m_array: [*c]u8, arraySize: c_int };
const VoxArray3D = extern struct {
    sizeX: c_int,
    sizeY: c_int,
    sizeZ: c_int,
    chunksSizeX: c_int,
    chunksSizeY: c_int,
    chunksSizeZ: c_int,
    m_arrayChunks: [*c]CubeChunk3D,
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
extern fn Vox_LoadFromMemory(pvoxData: [*c]u8, voxDataSize: c_uint, pvoxarray: [*c]VoxArray3D) c_int;
extern fn Vox_FreeArrays(voxarray: [*c]VoxArray3D) void;

// ---- m3d ----
const M3D_INDEX = u32;
const M3D_FLOAT = f32;
const M3D_UNDEF: u32 = 0xffffffff;
const M3D_NUMBONE: usize = 4;
const m3dti_t = extern struct { u: M3D_FLOAT, v: M3D_FLOAT };
const m3dtx_t = extern struct {
    name: [*c]u8,
    d: [*c]u8,
    w: u16,
    h: u16,
    f: u8,
};
const m3dw_t = extern struct { vertexid: M3D_INDEX, weight: M3D_FLOAT };
const m3db_t = extern struct {
    parent: M3D_INDEX,
    name: [*c]u8,
    pos: M3D_INDEX,
    ori: M3D_INDEX,
    numweight: M3D_INDEX,
    weight: [*c]m3dw_t,
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
    name: [*c]u8,
    numprop: u8,
    prop: [*c]m3dp_t,
};
const m3df_t = extern struct {
    materialid: M3D_INDEX,
    vertex: [3]M3D_INDEX,
    normal: [3]M3D_INDEX,
    texcoord: [3]M3D_INDEX,
};
const m3dvi_t = extern struct { count: u16, name: [*c]u8 };
const m3dvt_t = extern struct {
    name: [*c]u8,
    rotation: u8,
    voxshape: u16,
    materialid: M3D_INDEX,
    color: u32,
    skinid: M3D_INDEX,
    numitem: u8,
    item: [*c]m3dvi_t,
};
const m3dvx_t = extern struct {
    name: [*c]u8,
    x: i32,
    y: i32,
    z: i32,
    w: u32,
    h: u32,
    d: u32,
    uncertain: u8,
    groupid: u8,
    data: [*c]u16,
};
const m3dc_t = extern struct { type: u16, arg: [*c]u32 };
const m3dh_t = extern struct {
    name: [*c]u8,
    group: M3D_INDEX,
    numcmd: u32,
    cmd: [*c]m3dc_t,
};
const m3dl_t = extern struct {
    name: [*c]u8,
    lang: [*c]u8,
    text: [*c]u8,
    color: u32,
    vertexid: M3D_INDEX,
};
const m3dtr_t = extern struct { boneid: M3D_INDEX, pos: M3D_INDEX, ori: M3D_INDEX };
const m3dfr_t = extern struct {
    msec: u32,
    numtransform: M3D_INDEX,
    transform: [*c]m3dtr_t,
};
const m3da_t = extern struct {
    name: [*c]u8,
    durationmsec: u32,
    numframe: M3D_INDEX,
    frame: [*c]m3dfr_t,
};
const m3di_t = extern struct {
    name: [*c]u8,
    data: [*c]u8,
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
    name: [*c]u8,
    license: [*c]u8,
    author: [*c]u8,
    desc: [*c]u8,
    scale: M3D_FLOAT,
    numcmap: M3D_INDEX,
    cmap: [*c]u32,
    numtmap: M3D_INDEX,
    tmap: [*c]m3dti_t,
    numtexture: M3D_INDEX,
    texture: [*c]m3dtx_t,
    numbone: M3D_INDEX,
    bone: [*c]m3db_t,
    numvertex: M3D_INDEX,
    vertex: [*c]m3dv_t,
    numskin: M3D_INDEX,
    skin: [*c]m3ds_t,
    nummaterial: M3D_INDEX,
    material: [*c]m3dm_t,
    numface: M3D_INDEX,
    face: [*c]m3df_t,
    numvoxtype: M3D_INDEX,
    voxtype: [*c]m3dvt_t,
    numvoxel: M3D_INDEX,
    voxel: [*c]m3dvx_t,
    numshape: M3D_INDEX,
    shape: [*c]m3dh_t,
    numlabel: M3D_INDEX,
    label: [*c]m3dl_t,
    numaction: M3D_INDEX,
    action: [*c]m3da_t,
    numinlined: M3D_INDEX,
    inlined: [*c]m3di_t,
    numextra: M3D_INDEX,
    extra: [*c]?*m3dchunk_t,
    preview: m3di_t,
};
const m3dread_t = ?*const fn ([*c]u8, [*c]c_uint) callconv(.c) [*c]u8;
const m3dfree_t = ?*const fn (?*anyopaque) callconv(.c) void;
extern fn m3d_load(data: [*c]u8, readfilecb: m3dread_t, freecb: m3dfree_t, mtllib: [*c]m3d_t) [*c]m3d_t;
extern fn m3d_free(model: [*c]m3d_t) void;
extern fn m3d_pose(model: [*c]m3d_t, actionid: M3D_INDEX, msec: u32) [*c]m3db_t;

inline fn M3D_ERR_ISFATAL(x: i8) bool {
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
// Module Internal Functions Declaration (forward references)
//----------------------------------------------------------------------------------
// (defined later in this file)

//----------------------------------------------------------------------------------
// Module Functions Definition - Model loading/management
//----------------------------------------------------------------------------------

// Load model from files (mesh and material)
export fn LoadModel(fileName: [*c]const u8) callconv(.c) Model {
    var model = std.mem.zeroes(Model);

    if (IsFileExtension(fileName, ".obj")) model = LoadOBJ(fileName);
    if (IsFileExtension(fileName, ".iqm")) model = LoadIQM(fileName);
    if (IsFileExtension(fileName, ".gltf") or IsFileExtension(fileName, ".glb")) model = LoadGLTF(fileName);
    if (IsFileExtension(fileName, ".vox")) model = LoadVOX(fileName);
    if (IsFileExtension(fileName, ".m3d")) model = LoadM3D(fileName);

    // Make sure model transform is set to identity matrix!
    model.transform = MatrixIdentity();

    if ((model.meshCount != 0) and (model.meshes != null)) {
        // Upload vertex data to GPU (static meshes)
        var i: c_int = 0;
        while (i < model.meshCount) : (i += 1) UploadMesh(&model.meshes[@intCast(i)], false);
    } else TraceLog(LOG_WARNING, "MESH: [%s] Failed to load model mesh(es) data", fileName);

    if (model.materialCount == 0) {
        TraceLog(LOG_WARNING, "MATERIAL: [%s] Failed to load model material data, default to white material", fileName);

        model.materialCount = 1;
        model.materials = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.materialCount), @sizeOf(Material))));
        model.materials[0] = LoadMaterialDefault();

        if (model.meshMaterial == null) model.meshMaterial = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(c_int))));
    }

    return model;
}

// Load model from generated mesh
export fn LoadModelFromMesh(mesh: Mesh) callconv(.c) Model {
    var model = std.mem.zeroes(Model);

    model.transform = MatrixIdentity();

    model.meshCount = 1;
    model.meshes = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(Mesh))));
    model.meshes[0] = mesh;

    model.materialCount = 1;
    model.materials = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.materialCount), @sizeOf(Material))));
    model.materials[0] = LoadMaterialDefault();

    model.meshMaterial = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(c_int))));
    model.meshMaterial[0] = 0; // First material index

    return model;
}

// Check if model is valid (loaded in GPU, VAO/VBOs)
export fn IsModelValid(model: Model) callconv(.c) bool {
    var result = false;

    if ((model.meshes != null) and
        (model.materials != null) and
        (model.meshMaterial != null) and
        (model.meshCount > 0) and
        (model.materialCount > 0)) result = true;

    var i: c_int = 0;
    while (i < model.meshCount) : (i += 1) {
        const m = &model.meshes[@intCast(i)];
        if ((m.vertices != null) and (m.vboId[0] == 0)) {
            result = false;
            break;
        }
        if ((m.texcoords != null) and (m.vboId[1] == 0)) {
            result = false;
            break;
        }
        if ((m.normals != null) and (m.vboId[2] == 0)) {
            result = false;
            break;
        }
        if ((m.colors != null) and (m.vboId[3] == 0)) {
            result = false;
            break;
        }
        if ((m.tangents != null) and (m.vboId[4] == 0)) {
            result = false;
            break;
        }
        if ((m.texcoords2 != null) and (m.vboId[5] == 0)) {
            result = false;
            break;
        }
        if ((m.indices != null) and (m.vboId[6] == 0)) {
            result = false;
            break;
        }
        if (SUPPORT_GPU_SKINNING) {
            if ((m.boneIndices != null) and (m.vboId[7] == 0)) {
                result = false;
                break;
            }
            if ((m.boneWeights != null) and (m.vboId[8] == 0)) {
                result = false;
                break;
            }
        }
    }

    return result;
}

// Unload model (meshes/materials) from memory (RAM and/or VRAM)
export fn UnloadModel(model: Model) callconv(.c) void {
    var i: c_int = 0;
    while (i < model.meshCount) : (i += 1) UnloadMesh(model.meshes[@intCast(i)]);

    i = 0;
    while (i < model.materialCount) : (i += 1) RL_FREE(model.materials[@intCast(i)].maps);

    RL_FREE(model.meshes);
    RL_FREE(model.materials);
    RL_FREE(model.meshMaterial);

    RL_FREE(model.skeleton.bones);
    RL_FREE(model.skeleton.bindPose);
    RL_FREE(model.currentPose);
    RL_FREE(model.boneMatrices);

    TraceLog(LOG_INFO, "MODEL: Unloaded model (and meshes) from RAM and VRAM");
}

// Compute model bounding box limits (considers all meshes)
export fn GetModelBoundingBox(model: Model) callconv(.c) BoundingBox {
    var bounds = std.mem.zeroes(BoundingBox);

    if (model.meshCount > 0) {
        var temp = std.mem.zeroes(Vector3);
        bounds = GetMeshBoundingBox(model.meshes[0]);

        var i: c_int = 1;
        while (i < model.meshCount) : (i += 1) {
            const tempBounds = GetMeshBoundingBox(model.meshes[@intCast(i)]);

            temp.x = if (bounds.min.x < tempBounds.min.x) bounds.min.x else tempBounds.min.x;
            temp.y = if (bounds.min.y < tempBounds.min.y) bounds.min.y else tempBounds.min.y;
            temp.z = if (bounds.min.z < tempBounds.min.z) bounds.min.z else tempBounds.min.z;
            bounds.min = temp;

            temp.x = if (bounds.max.x > tempBounds.max.x) bounds.max.x else tempBounds.max.x;
            temp.y = if (bounds.max.y > tempBounds.max.y) bounds.max.y else tempBounds.max.y;
            temp.z = if (bounds.max.z > tempBounds.max.z) bounds.max.z else tempBounds.max.z;
            bounds.max = temp;
        }
    }

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

    mesh.*.vboId = @ptrCast(@alignCast(RL_CALLOC(@intCast(MAX_MESH_VERTEX_BUFFERS), @sizeOf(c_uint))));

    mesh.*.vaoId = 0;
    mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION] = 0;
    mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD] = 0;
    mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL] = 0;
    mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR] = 0;
    mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT] = 0;
    mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2] = 0;
    mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_INDICES] = 0;
    if (SUPPORT_GPU_SKINNING) {
        mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES] = 0;
        mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS] = 0;
    }

    mesh.*.vaoId = rlLoadVertexArray();

    _ = rlEnableVertexArray(mesh.*.vaoId);

    // Enable vertex attributes: position (shader-location = 0)
    const vertices: ?*const anyopaque = if (mesh.*.animVertices != null) mesh.*.animVertices else mesh.*.vertices;
    mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION] = rlLoadVertexBuffer(vertices, mesh.*.vertexCount * 3 * @sizeOf(f32), dynamic);
    rlSetVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION, 3, RL_FLOAT, false, 0, 0);
    rlEnableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION);

    // Enable vertex attributes: texcoords (shader-location = 1)
    if (mesh.*.texcoords != null) {
        mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD] = rlLoadVertexBuffer(mesh.*.texcoords, mesh.*.vertexCount * 2 * @sizeOf(f32), dynamic);
        rlSetVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD, 2, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD);
    } else {
        const value = [2]f32{ 0.0, 0.0 };
        rlSetVertexAttributeDefault(@intCast(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD), &value, SHADER_ATTRIB_VEC2, 2);
        rlDisableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD);
    }

    if (mesh.*.normals != null) {
        const normals: ?*const anyopaque = if (mesh.*.animNormals != null) mesh.*.animNormals else mesh.*.normals;
        mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL] = rlLoadVertexBuffer(normals, mesh.*.vertexCount * 3 * @sizeOf(f32), dynamic);
        rlSetVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL, 3, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL);
    } else {
        const value = [3]f32{ 0.0, 0.0, 1.0 };
        rlSetVertexAttributeDefault(@intCast(RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL), &value, SHADER_ATTRIB_VEC3, 3);
        rlDisableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL);
    }

    if (mesh.*.colors != null) {
        mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR] = rlLoadVertexBuffer(mesh.*.colors, mesh.*.vertexCount * 4 * @sizeOf(u8), dynamic);
        rlSetVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR, 4, RL_UNSIGNED_BYTE, true, 0, 0);
        rlEnableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR);
    } else {
        const value = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
        rlSetVertexAttributeDefault(@intCast(RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR), &value, SHADER_ATTRIB_VEC4, 4);
        rlDisableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR);
    }

    if (mesh.*.tangents != null) {
        mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT] = rlLoadVertexBuffer(mesh.*.tangents, mesh.*.vertexCount * 4 * @sizeOf(f32), dynamic);
        rlSetVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT, 4, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT);
    } else {
        const value = [4]f32{ 1.0, 0.0, 0.0, 1.0 };
        rlSetVertexAttributeDefault(@intCast(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT), &value, SHADER_ATTRIB_VEC4, 4);
        rlDisableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT);
    }

    if (mesh.*.texcoords2 != null) {
        mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2] = rlLoadVertexBuffer(mesh.*.texcoords2, mesh.*.vertexCount * 2 * @sizeOf(f32), dynamic);
        rlSetVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2, 2, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2);
    } else {
        const value = [2]f32{ 0.0, 0.0 };
        rlSetVertexAttributeDefault(@intCast(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2), &value, SHADER_ATTRIB_VEC2, 2);
        rlDisableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2);
    }

    if (SUPPORT_GPU_SKINNING) {
        if (mesh.*.boneIndices != null) {
            mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES] = rlLoadVertexBuffer(mesh.*.boneIndices, mesh.*.vertexCount * 4 * @sizeOf(u8), dynamic);
            rlSetVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES, 4, RL_UNSIGNED_BYTE, false, 0, 0);
            rlEnableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES);
        } else {
            const value = [4]f32{ 0.0, 0.0, 0.0, 0.0 };
            rlSetVertexAttributeDefault(@intCast(RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES), &value, SHADER_ATTRIB_VEC4, 4);
            rlDisableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES);
        }

        if (mesh.*.boneWeights != null) {
            mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS] = rlLoadVertexBuffer(mesh.*.boneWeights, mesh.*.vertexCount * 4 * @sizeOf(f32), dynamic);
            rlSetVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS, 4, RL_FLOAT, false, 0, 0);
            rlEnableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS);
        } else {
            // NOTE: Component count 2 (not 4) matches upstream rmodels.c exactly
            const value = [4]f32{ 0.0, 0.0, 0.0, 0.0 };
            rlSetVertexAttributeDefault(@intCast(RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS), &value, SHADER_ATTRIB_VEC4, 2);
            rlDisableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS);
        }
    }

    if (mesh.*.indices != null) {
        mesh.*.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_INDICES] = rlLoadVertexBufferElement(mesh.*.indices, mesh.*.triangleCount * 3 * @sizeOf(c_ushort), dynamic);
    }

    if (mesh.*.vaoId > 0) TraceLog(LOG_INFO, "VAO: [ID %i] Mesh uploaded successfully to VRAM (GPU)", mesh.*.vaoId) else TraceLog(LOG_INFO, "VBO: Mesh uploaded successfully to VRAM (GPU)");

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
        var i: c_int = 0;
        while (i < MAX_MESH_VERTEX_BUFFERS) : (i += 1) rlUnloadVertexBuffer(mesh.vboId[@intCast(i)]);
    }
    RL_FREE(mesh.vboId);

    RL_FREE(mesh.vertices);
    RL_FREE(mesh.texcoords);
    RL_FREE(mesh.normals);
    RL_FREE(mesh.colors);
    RL_FREE(mesh.tangents);
    RL_FREE(mesh.texcoords2);
    RL_FREE(mesh.indices);

    RL_FREE(mesh.boneWeights);
    RL_FREE(mesh.boneIndices);

    RL_FREE(mesh.animVertices);
    RL_FREE(mesh.animNormals);
}

// Bind mesh bone ids and bone weights VBOs to the shader attributes, if the shader uses them
fn bindBoneVertexBuffers(mesh: Mesh, shader: Shader) void {
    if (shader.locs[SHADER_LOC_VERTEX_BONEIDS] != -1) {
        rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEINDICES]);
        rlSetVertexAttribute(@intCast(shader.locs[SHADER_LOC_VERTEX_BONEIDS]), 4, RL_UNSIGNED_BYTE, false, 0, 0);
        rlEnableVertexAttribute(@intCast(shader.locs[SHADER_LOC_VERTEX_BONEIDS]));
    }

    if (shader.locs[SHADER_LOC_VERTEX_BONEWEIGHTS] != -1) {
        rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_BONEWEIGHTS]);
        rlSetVertexAttribute(@intCast(shader.locs[SHADER_LOC_VERTEX_BONEWEIGHTS]), 4, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(@intCast(shader.locs[SHADER_LOC_VERTEX_BONEWEIGHTS]));
    }
}

// Draw a 3d mesh with material and transform
export fn DrawMesh(mesh: Mesh, material: Material, transform: Matrix) callconv(.c) void {
    // Bind shader program
    rlEnableShader(material.shader.id);

    if (material.shader.locs == null) return;

    // Upload to shader material.colDiffuse
    if (material.shader.locs[SHADER_LOC_COLOR_DIFFUSE] != -1) {
        const values = [4]f32{
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_DIFFUSE].color.r)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_DIFFUSE].color.g)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_DIFFUSE].color.b)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_DIFFUSE].color.a)) / 255.0,
        };
        rlSetUniform(material.shader.locs[SHADER_LOC_COLOR_DIFFUSE], &values, SHADER_UNIFORM_VEC4, 1);
    }

    // Upload to shader material.colSpecular (if location available)
    if (material.shader.locs[SHADER_LOC_COLOR_SPECULAR] != -1) {
        const values = [4]f32{
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_SPECULAR].color.r)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_SPECULAR].color.g)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_SPECULAR].color.b)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_SPECULAR].color.a)) / 255.0,
        };
        rlSetUniform(material.shader.locs[SHADER_LOC_COLOR_SPECULAR], &values, SHADER_UNIFORM_VEC4, 1);
    }

    var matModel = MatrixIdentity();
    const matView = rlGetMatrixModelview();
    var matModelView = MatrixIdentity();
    const matProjection = rlGetMatrixProjection();

    if (material.shader.locs[SHADER_LOC_MATRIX_VIEW] != -1) rlSetUniformMatrix(material.shader.locs[SHADER_LOC_MATRIX_VIEW], matView);
    if (material.shader.locs[SHADER_LOC_MATRIX_PROJECTION] != -1) rlSetUniformMatrix(material.shader.locs[SHADER_LOC_MATRIX_PROJECTION], matProjection);

    matModel = MatrixMultiply(transform, rlGetMatrixTransform());

    if (material.shader.locs[SHADER_LOC_MATRIX_MODEL] != -1) rlSetUniformMatrix(material.shader.locs[SHADER_LOC_MATRIX_MODEL], matModel);

    matModelView = MatrixMultiply(matModel, matView);

    if (material.shader.locs[SHADER_LOC_MATRIX_NORMAL] != -1) rlSetUniformMatrix(material.shader.locs[SHADER_LOC_MATRIX_NORMAL], MatrixTranspose(MatrixInvert(matModel)));

    // Bind active texture maps (if available)
    var i: c_int = 0;
    while (i < MAX_MATERIAL_MAPS) : (i += 1) {
        const ui: usize = @intCast(i);
        if (material.maps[ui].texture.id > 0) {
            rlActiveTextureSlot(i);

            if ((ui == MATERIAL_MAP_IRRADIANCE) or (ui == MATERIAL_MAP_PREFILTER) or (ui == MATERIAL_MAP_CUBEMAP)) rlEnableTextureCubemap(material.maps[ui].texture.id) else rlEnableTexture(material.maps[ui].texture.id);

            rlSetUniform(material.shader.locs[SHADER_LOC_MAP_DIFFUSE + ui], &i, SHADER_UNIFORM_INT, 1);
        }
    }

    if (!rlEnableVertexArray(mesh.vaoId)) {
        rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION]);
        rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_POSITION]), 3, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_POSITION]));

        rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD]);
        rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD01]), 2, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD01]));

        if (material.shader.locs[SHADER_LOC_VERTEX_NORMAL] != -1) {
            rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL]);
            rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_NORMAL]), 3, RL_FLOAT, false, 0, 0);
            rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_NORMAL]));
        }

        if (material.shader.locs[SHADER_LOC_VERTEX_COLOR] != -1) {
            if (mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR] != 0) {
                rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR]);
                rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_COLOR]), 4, RL_UNSIGNED_BYTE, true, 0, 0);
                rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_COLOR]));
            } else {
                const value = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
                rlSetVertexAttributeDefault(material.shader.locs[SHADER_LOC_VERTEX_COLOR], &value, SHADER_ATTRIB_VEC4, 4);
                rlDisableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_COLOR]));
            }
        }

        if (material.shader.locs[SHADER_LOC_VERTEX_TANGENT] != -1) {
            rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT]);
            rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TANGENT]), 4, RL_FLOAT, false, 0, 0);
            rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TANGENT]));
        }

        if (material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD02] != -1) {
            rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2]);
            rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD02]), 2, RL_FLOAT, false, 0, 0);
            rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD02]));
        }

        if (SUPPORT_GPU_SKINNING) bindBoneVertexBuffers(mesh, material.shader);

        if (mesh.indices != null) rlEnableVertexBufferElement(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_INDICES]);
    }

    var eyeCount: c_int = 1;
    if (rlIsStereoRenderEnabled()) eyeCount = 2;

    var eye: c_int = 0;
    while (eye < eyeCount) : (eye += 1) {
        var matModelViewProjection = MatrixIdentity();
        if (eyeCount == 1) {
            matModelViewProjection = MatrixMultiply(matModelView, matProjection);
        } else {
            rlViewport(@divTrunc(eye * rlGetFramebufferWidth(), 2), 0, @divTrunc(rlGetFramebufferWidth(), 2), rlGetFramebufferHeight());
            matModelViewProjection = MatrixMultiply(MatrixMultiply(matModelView, rlGetMatrixViewOffsetStereo(eye)), rlGetMatrixProjectionStereo(eye));
        }

        rlSetUniformMatrix(material.shader.locs[SHADER_LOC_MATRIX_MVP], matModelViewProjection);

        if (mesh.indices != null) rlDrawVertexArrayElements(0, mesh.triangleCount * 3, null) else rlDrawVertexArray(0, mesh.vertexCount);
    }

    // Unbind all bound texture maps
    i = 0;
    while (i < MAX_MATERIAL_MAPS) : (i += 1) {
        const ui: usize = @intCast(i);
        if (material.maps[ui].texture.id > 0) {
            rlActiveTextureSlot(i);
            if ((ui == MATERIAL_MAP_IRRADIANCE) or (ui == MATERIAL_MAP_PREFILTER) or (ui == MATERIAL_MAP_CUBEMAP)) rlDisableTextureCubemap() else rlDisableTexture();
        }
    }

    rlDisableVertexArray();
    rlDisableVertexBuffer();
    rlDisableVertexBufferElement();

    rlDisableShader();

    rlSetMatrixModelview(matView);
    rlSetMatrixProjection(matProjection);
}

// Draw multiple mesh instances with material and different transforms
export fn DrawMeshInstanced(mesh: Mesh, material: Material, transforms: [*c]const Matrix, instances: c_int) callconv(.c) void {
    var instanceTransform: [*c]float16 = null;
    var instancesVboId: c_uint = 0;

    rlEnableShader(material.shader.id);

    if (material.shader.locs[SHADER_LOC_COLOR_DIFFUSE] != -1) {
        const values = [4]f32{
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_DIFFUSE].color.r)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_DIFFUSE].color.g)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_DIFFUSE].color.b)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_DIFFUSE].color.a)) / 255.0,
        };
        rlSetUniform(material.shader.locs[SHADER_LOC_COLOR_DIFFUSE], &values, SHADER_UNIFORM_VEC4, 1);
    }

    if (material.shader.locs[SHADER_LOC_COLOR_SPECULAR] != -1) {
        const values = [4]f32{
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_SPECULAR].color.r)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_SPECULAR].color.g)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_SPECULAR].color.b)) / 255.0,
            @as(f32, @floatFromInt(material.maps[MATERIAL_MAP_SPECULAR].color.a)) / 255.0,
        };
        rlSetUniform(material.shader.locs[SHADER_LOC_COLOR_SPECULAR], &values, SHADER_UNIFORM_VEC4, 1);
    }

    const matModel = MatrixIdentity();
    const matView = rlGetMatrixModelview();
    var matModelView = MatrixIdentity();
    const matProjection = rlGetMatrixProjection();

    if (material.shader.locs[SHADER_LOC_MATRIX_VIEW] != -1) rlSetUniformMatrix(material.shader.locs[SHADER_LOC_MATRIX_VIEW], matView);
    if (material.shader.locs[SHADER_LOC_MATRIX_PROJECTION] != -1) rlSetUniformMatrix(material.shader.locs[SHADER_LOC_MATRIX_PROJECTION], matProjection);

    instanceTransform = @ptrCast(@alignCast(RL_CALLOC(@intCast(instances), @sizeOf(float16))));

    var i: c_int = 0;
    while (i < instances) : (i += 1) instanceTransform[@intCast(i)] = MatrixToFloatV(transforms[@intCast(i)]);

    _ = rlEnableVertexArray(mesh.vaoId);

    instancesVboId = rlLoadVertexBuffer(instanceTransform, instances * @sizeOf(float16), false);

    if (material.shader.locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM] != -1) {
        var k: c_uint = 0;
        while (k < 4) : (k += 1) {
            const loc: c_uint = @intCast(material.shader.locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM]);
            rlEnableVertexAttribute(loc + k);
            rlSetVertexAttribute(loc + k, 4, RL_FLOAT, false, @sizeOf(Matrix), @intCast(k * @sizeOf(Vector4)));
            rlSetVertexAttributeDivisor(loc + k, 1);
        }
    }

    rlDisableVertexBuffer();
    rlDisableVertexArray();

    matModelView = MatrixMultiply(rlGetMatrixTransform(), matView);

    if (material.shader.locs[SHADER_LOC_MATRIX_NORMAL] != -1) rlSetUniformMatrix(material.shader.locs[SHADER_LOC_MATRIX_NORMAL], MatrixTranspose(MatrixInvert(matModel)));

    i = 0;
    while (i < MAX_MATERIAL_MAPS) : (i += 1) {
        const ui: usize = @intCast(i);
        if (material.maps[ui].texture.id > 0) {
            rlActiveTextureSlot(i);
            if ((ui == MATERIAL_MAP_IRRADIANCE) or (ui == MATERIAL_MAP_PREFILTER) or (ui == MATERIAL_MAP_CUBEMAP)) rlEnableTextureCubemap(material.maps[ui].texture.id) else rlEnableTexture(material.maps[ui].texture.id);
            rlSetUniform(material.shader.locs[SHADER_LOC_MAP_DIFFUSE + ui], &i, SHADER_UNIFORM_INT, 1);
        }
    }

    if (!rlEnableVertexArray(mesh.vaoId)) {
        rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION]);
        rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_POSITION]), 3, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_POSITION]));

        rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD]);
        rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD01]), 2, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD01]));

        if (material.shader.locs[SHADER_LOC_VERTEX_NORMAL] != -1) {
            rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL]);
            rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_NORMAL]), 3, RL_FLOAT, false, 0, 0);
            rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_NORMAL]));
        }

        if (material.shader.locs[SHADER_LOC_VERTEX_COLOR] != -1) {
            if (mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR] != 0) {
                rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR]);
                rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_COLOR]), 4, RL_UNSIGNED_BYTE, true, 0, 0);
                rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_COLOR]));
            } else {
                const value = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
                rlSetVertexAttributeDefault(material.shader.locs[SHADER_LOC_VERTEX_COLOR], &value, SHADER_ATTRIB_VEC4, 4);
                rlDisableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_COLOR]));
            }
        }

        if (material.shader.locs[SHADER_LOC_VERTEX_TANGENT] != -1) {
            rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT]);
            rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TANGENT]), 4, RL_FLOAT, false, 0, 0);
            rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TANGENT]));
        }

        if (material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD02] != -1) {
            rlEnableVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_TEXCOORD2]);
            rlSetVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD02]), 2, RL_FLOAT, false, 0, 0);
            rlEnableVertexAttribute(@intCast(material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD02]));
        }

        if (SUPPORT_GPU_SKINNING) bindBoneVertexBuffers(mesh, material.shader);

        if (mesh.indices != null) rlEnableVertexBufferElement(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_INDICES]);
    }

    var eyeCount: c_int = 1;
    if (rlIsStereoRenderEnabled()) eyeCount = 2;

    var eye: c_int = 0;
    while (eye < eyeCount) : (eye += 1) {
        var matModelViewProjection = MatrixIdentity();
        if (eyeCount == 1) {
            matModelViewProjection = MatrixMultiply(matModelView, matProjection);
        } else {
            rlViewport(@divTrunc(eye * rlGetFramebufferWidth(), 2), 0, @divTrunc(rlGetFramebufferWidth(), 2), rlGetFramebufferHeight());
            matModelViewProjection = MatrixMultiply(MatrixMultiply(matModelView, rlGetMatrixViewOffsetStereo(eye)), rlGetMatrixProjectionStereo(eye));
        }

        rlSetUniformMatrix(material.shader.locs[SHADER_LOC_MATRIX_MVP], matModelViewProjection);

        if (mesh.indices != null) rlDrawVertexArrayElementsInstanced(0, mesh.triangleCount * 3, null, instances) else rlDrawVertexArrayInstanced(0, mesh.vertexCount, instances);
    }

    i = 0;
    while (i < MAX_MATERIAL_MAPS) : (i += 1) {
        const ui: usize = @intCast(i);
        if (material.maps[ui].texture.id > 0) {
            rlActiveTextureSlot(i);
            if ((ui == MATERIAL_MAP_IRRADIANCE) or (ui == MATERIAL_MAP_PREFILTER) or (ui == MATERIAL_MAP_CUBEMAP)) rlDisableTextureCubemap() else rlDisableTexture();
        }
    }

    rlDisableVertexArray();
    rlDisableVertexBuffer();
    rlDisableVertexBufferElement();

    rlDisableShader();

    rlUnloadVertexBuffer(instancesVboId);
    RL_FREE(instanceTransform);
}

// Export mesh data to file
export fn ExportMesh(mesh: Mesh, fileName: [*c]const u8) callconv(.c) bool {
    var result = false;

    if (IsFileExtension(fileName, ".obj")) {
        const vc = mesh.vertexCount;
        const dataSize: c_int = vc * @as(c_int, @intCast(strlen("v -0000.000000f -0000.000000f -0000.000000f\n"))) +
            vc * @as(c_int, @intCast(strlen("vt -0.000000f -0.000000f\n"))) +
            vc * @as(c_int, @intCast(strlen("vn -0.0000f -0.0000f -0.0000f\n"))) +
            mesh.triangleCount * snprintf(null, 0, "f %i/%i/%i %i/%i/%i %i/%i/%i\n", vc, vc, vc, vc, vc, vc, vc, vc, vc);

        const txtData: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(@intCast(dataSize + 1000), @sizeOf(u8))));

        var byteCount: c_int = 0;
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# //////////////////////////////////////////////////////////////////////////////////\n");
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# //                                                                              //\n");
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# // rMeshOBJ exporter v1.0 - Mesh exported as triangle faces and not optimized   //\n");
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# //                                                                              //\n");
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# // more info and bugs-report:  github.com/raysan5/raylib                        //\n");
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# // feedback and support:       ray[at]raylib.com                                //\n");
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# //                                                                              //\n");
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# // Copyright (c) 2018-2026 Ramon Santamaria (@raysan5)                          //\n");
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# //                                                                              //\n");
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# //////////////////////////////////////////////////////////////////////////////////\n\n");
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# Vertex Count:     %i\n", mesh.vertexCount);
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# Triangle Count:   %i\n\n", mesh.triangleCount);

        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "g mesh\n");

        {
            var i: c_int = 0;
            var v: c_int = 0;
            while (i < mesh.vertexCount) : ({
                i += 1;
                v += 3;
            }) {
                const u: usize = @intCast(v);
                byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "v %.6f %.6f %.6f\n", mesh.vertices[u], mesh.vertices[u + 1], mesh.vertices[u + 2]);
            }
        }
        {
            var i: c_int = 0;
            var v: c_int = 0;
            while (i < mesh.vertexCount) : ({
                i += 1;
                v += 2;
            }) {
                const u: usize = @intCast(v);
                byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "vt %.6f %.6f\n", mesh.texcoords[u], mesh.texcoords[u + 1]);
            }
        }
        {
            var i: c_int = 0;
            var v: c_int = 0;
            while (i < mesh.vertexCount) : ({
                i += 1;
                v += 3;
            }) {
                const u: usize = @intCast(v);
                byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "vn %.4f %.4f %.4f\n", mesh.normals[u], mesh.normals[u + 1], mesh.normals[u + 2]);
            }
        }

        if (mesh.indices != null) {
            var i: c_int = 0;
            var v: c_int = 0;
            while (i < mesh.triangleCount) : ({
                i += 1;
                v += 3;
            }) {
                const u: usize = @intCast(v);
                byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "f %i/%i/%i %i/%i/%i %i/%i/%i\n", mesh.indices[u] + 1, mesh.indices[u] + 1, mesh.indices[u] + 1, mesh.indices[u + 1] + 1, mesh.indices[u + 1] + 1, mesh.indices[u + 1] + 1, mesh.indices[u + 2] + 1, mesh.indices[u + 2] + 1, mesh.indices[u + 2] + 1);
            }
        } else {
            var i: c_int = 0;
            var v: c_int = 1;
            while (i < mesh.triangleCount) : ({
                i += 1;
                v += 3;
            }) {
                byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "f %i/%i/%i %i/%i/%i %i/%i/%i\n", v, v, v, v + 1, v + 1, v + 1, v + 2, v + 2, v + 2);
            }
        }

        result = SaveFileText(fileName, txtData);

        RL_FREE(txtData);
    }

    return result;
}

// Export mesh as code file (.h) defining multiple arrays of vertex attributes
export fn ExportMeshAsCode(mesh: Mesh, fileName: [*c]const u8) callconv(.c) bool {
    var result = false;

    const TEXT_BYTES_PER_LINE: c_int = 20;

    const txtData: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(64 * 1024 * 1024, @sizeOf(u8))));

    var byteCount: c_int = 0;
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "////////////////////////////////////////////////////////////////////////////////////////\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                                    //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// MeshAsCode exporter v1.0 - Mesh vertex data exported as arrays                     //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                                    //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// more info and bugs-report:  github.com/raysan5/raylib                              //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// feedback and support:       ray[at]raylib.com                                      //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                                    //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// Copyright (c) 2023 Ramon Santamaria (@raysan5)                                     //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                                    //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "////////////////////////////////////////////////////////////////////////////////////////\n\n");

    var varFileName = std.mem.zeroes([256]u8);
    _ = strncpy(&varFileName, GetFileNameWithoutExt(fileName), 256 - 1);
    {
        var i: usize = 0;
        while (varFileName[i] != 0) : (i += 1) {
            if ((varFileName[i] >= 'a') and (varFileName[i] <= 'z')) varFileName[i] = varFileName[i] - 32;
        }
    }

    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// Mesh basic information\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#define %s_VERTEX_COUNT    %i\n", &varFileName, mesh.vertexCount);
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#define %s_TRIANGLE_COUNT   %i\n\n", &varFileName, mesh.triangleCount);

    if (mesh.vertices != null) {
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "static float %s_VERTEX_DATA[%i] = { ", &varFileName, mesh.vertexCount * 3);
        var i: c_int = 0;
        while (i < mesh.vertexCount * 3 - 1) : (i += 1) byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), if (@rem(i, TEXT_BYTES_PER_LINE) == 0) "%.3ff,\n" else "%.3ff, ", mesh.vertices[@intCast(i)]);
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "%.3ff };\n\n", mesh.vertices[@intCast(mesh.vertexCount * 3 - 1)]);
    }

    if (mesh.texcoords != null) {
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "static float %s_TEXCOORD_DATA[%i] = { ", &varFileName, mesh.vertexCount * 2);
        var i: c_int = 0;
        while (i < mesh.vertexCount * 2 - 1) : (i += 1) byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), if (@rem(i, TEXT_BYTES_PER_LINE) == 0) "%.3ff,\n" else "%.3ff, ", mesh.texcoords[@intCast(i)]);
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "%.3ff };\n\n", mesh.texcoords[@intCast(mesh.vertexCount * 2 - 1)]);
    }

    if (mesh.texcoords2 != null) {
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "static float %s_TEXCOORD2_DATA[%i] = { ", &varFileName, mesh.vertexCount * 2);
        var i: c_int = 0;
        while (i < mesh.vertexCount * 2 - 1) : (i += 1) byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), if (@rem(i, TEXT_BYTES_PER_LINE) == 0) "%.3ff,\n" else "%.3ff, ", mesh.texcoords2[@intCast(i)]);
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "%.3ff };\n\n", mesh.texcoords2[@intCast(mesh.vertexCount * 2 - 1)]);
    }

    if (mesh.normals != null) {
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "static float %s_NORMAL_DATA[%i] = { ", &varFileName, mesh.vertexCount * 3);
        var i: c_int = 0;
        while (i < mesh.vertexCount * 3 - 1) : (i += 1) byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), if (@rem(i, TEXT_BYTES_PER_LINE) == 0) "%.3ff,\n" else "%.3ff, ", mesh.normals[@intCast(i)]);
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "%.3ff };\n\n", mesh.normals[@intCast(mesh.vertexCount * 3 - 1)]);
    }

    if (mesh.tangents != null) {
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "static float %s_TANGENT_DATA[%i] = { ", &varFileName, mesh.vertexCount * 4);
        var i: c_int = 0;
        while (i < mesh.vertexCount * 4 - 1) : (i += 1) byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), if (@rem(i, TEXT_BYTES_PER_LINE) == 0) "%.3ff,\n" else "%.3ff, ", mesh.tangents[@intCast(i)]);
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "%.3ff };\n\n", mesh.tangents[@intCast(mesh.vertexCount * 4 - 1)]);
    }

    if (mesh.colors != null) {
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "static unsigned char %s_COLOR_DATA[%i] = { ", &varFileName, mesh.vertexCount * 4);
        var i: c_int = 0;
        while (i < mesh.vertexCount * 4 - 1) : (i += 1) byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), if (@rem(i, TEXT_BYTES_PER_LINE) == 0) "0x%x,\n" else "0x%x, ", mesh.colors[@intCast(i)]);
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "0x%x };\n\n", mesh.colors[@intCast(mesh.vertexCount * 4 - 1)]);
    }

    if (mesh.indices != null) {
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "static unsigned short %s_INDEX_DATA[%i] = { ", &varFileName, mesh.triangleCount * 3);
        var i: c_int = 0;
        while (i < mesh.triangleCount * 3 - 1) : (i += 1) byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), if (@rem(i, TEXT_BYTES_PER_LINE) == 0) "%i,\n" else "%i, ", mesh.indices[@intCast(i)]);
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "%i };\n", mesh.indices[@intCast(mesh.triangleCount * 3 - 1)]);
    }

    result = SaveFileText(fileName, txtData);

    RL_FREE(txtData);

    return result;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Materials
//----------------------------------------------------------------------------------

// Process obj materials
fn ProcessMaterialsOBJ(materials: [*c]Material, mats: [*c]tinyobj_material_t, materialCount: c_int) void {
    var m: c_int = 0;
    while (m < materialCount) : (m += 1) {
        const um: usize = @intCast(m);
        materials[um] = LoadMaterialDefault();

        if (mats == null) continue;

        materials[um].maps[MATERIAL_MAP_DIFFUSE].texture = .{ .id = rlGetTextureIdDefault(), .width = 1, .height = 1, .mipmaps = 1, .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 };

        if (mats[um].diffuse_texname != null) {
            materials[um].maps[MATERIAL_MAP_DIFFUSE].texture = LoadTexture(mats[um].diffuse_texname);
        } else materials[um].maps[MATERIAL_MAP_DIFFUSE].color = .{ .r = @intFromFloat(mats[um].diffuse[0] * 255.0), .g = @intFromFloat(mats[um].diffuse[1] * 255.0), .b = @intFromFloat(mats[um].diffuse[2] * 255.0), .a = 255 };
        materials[um].maps[MATERIAL_MAP_DIFFUSE].value = 0.0;

        if (mats[um].specular_texname != null) materials[um].maps[MATERIAL_MAP_SPECULAR].texture = LoadTexture(mats[um].specular_texname);
        materials[um].maps[MATERIAL_MAP_SPECULAR].color = .{ .r = @intFromFloat(mats[um].specular[0] * 255.0), .g = @intFromFloat(mats[um].specular[1] * 255.0), .b = @intFromFloat(mats[um].specular[2] * 255.0), .a = 255 };
        materials[um].maps[MATERIAL_MAP_SPECULAR].value = 0.0;

        if (mats[um].bump_texname != null) materials[um].maps[MATERIAL_MAP_NORMAL].texture = LoadTexture(mats[um].bump_texname);
        materials[um].maps[MATERIAL_MAP_NORMAL].color = WHITE;
        materials[um].maps[MATERIAL_MAP_NORMAL].value = mats[um].shininess;

        materials[um].maps[MATERIAL_MAP_EMISSION].color = .{ .r = @intFromFloat(mats[um].emission[0] * 255.0), .g = @intFromFloat(mats[um].emission[1] * 255.0), .b = @intFromFloat(mats[um].emission[2] * 255.0), .a = 255 };

        if (mats[um].displacement_texname != null) materials[um].maps[MATERIAL_MAP_HEIGHT].texture = LoadTexture(mats[um].displacement_texname);
    }
}

// Load materials from model file
export fn LoadMaterials(fileName: [*c]const u8, materialCount: [*c]c_int) callconv(.c) [*c]Material {
    var materials: [*c]Material = null;
    var count: c_uint = 0;

    if (IsFileExtension(fileName, ".mtl")) {
        var mats: [*c]tinyobj_material_t = null;

        const result = tinyobj_parse_mtl_file(&mats, &count, fileName);
        if (result != TINYOBJ_SUCCESS) TraceLog(LOG_WARNING, "MATERIAL: [%s] Failed to parse materials file", fileName);

        materials = @ptrCast(@alignCast(RL_CALLOC(count, @sizeOf(Material))));
        ProcessMaterialsOBJ(materials, mats, @intCast(count));

        tinyobj_materials_free(mats, count);
    }

    materialCount.* = @intCast(count);
    return materials;
}

// Load default material (Supports: DIFFUSE, SPECULAR, NORMAL maps)
export fn LoadMaterialDefault() callconv(.c) Material {
    var material = std.mem.zeroes(Material);
    material.maps = @ptrCast(@alignCast(RL_CALLOC(@intCast(MAX_MATERIAL_MAPS), @sizeOf(MaterialMap))));

    material.shader.id = rlGetShaderIdDefault();
    material.shader.locs = rlGetShaderLocsDefault();

    material.maps[MATERIAL_MAP_DIFFUSE].texture = .{ .id = rlGetTextureIdDefault(), .width = 1, .height = 1, .mipmaps = 1, .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 };

    material.maps[MATERIAL_MAP_DIFFUSE].color = WHITE;
    material.maps[MATERIAL_MAP_SPECULAR].color = WHITE;

    return material;
}

// Check if material is valid
export fn IsMaterialValid(material: Material) callconv(.c) bool {
    var result = false;
    if ((material.maps != null) and (material.shader.id > 0)) result = true;
    return result;
}

// Unload material from memory
export fn UnloadMaterial(material: Material) callconv(.c) void {
    if (material.shader.id != rlGetShaderIdDefault()) UnloadShader(material.shader);

    if (material.maps != null) {
        var i: c_int = 0;
        while (i < MAX_MATERIAL_MAPS) : (i += 1) {
            if (material.maps[@intCast(i)].texture.id != rlGetTextureIdDefault()) rlUnloadTexture(material.maps[@intCast(i)].texture.id);
        }
    }

    RL_FREE(material.maps);
}

// Set texture for a material map type
export fn SetMaterialTexture(material: [*c]Material, mapType: c_int, texture: Texture2D) callconv(.c) void {
    material.*.maps[@intCast(mapType)].texture = texture;
}

// Set the material for a mesh
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

    if (IsFileExtension(fileName, ".iqm")) animations = LoadModelAnimationsIQM(fileName, animCount);
    if (IsFileExtension(fileName, ".m3d")) animations = LoadModelAnimationsM3D(fileName, animCount);
    if (IsFileExtension(fileName, ".gltf;.glb")) animations = LoadModelAnimationsGLTF(fileName, animCount);

    return animations;
}

// Update model animation data (bone matrices) for a specific pose
// NOTE: Request frame could be fractional, using a lerp interpolation between two frames
// NOTE: Not declared in raylib.h, but a public (non-static) symbol of upstream rmodels.c
export fn UpdateModelAnimationBones(model: Model, anim: ModelAnimation, frame: f32) callconv(.c) void {
    if (model.boneMatrices == null) return;

    if ((anim.keyframeCount > 0) and (model.skeleton.bones != null) and (anim.keyframePoses != null)) {
        var currentFrame: c_int = @intFromFloat(frame);
        var nextFrame: c_int = currentFrame + 1;
        var blend: f32 = frame - @as(f32, @floatFromInt(currentFrame));
        blend = Clamp(blend, 0.0, 1.0);
        if (currentFrame >= anim.keyframeCount) currentFrame = @rem(currentFrame, anim.keyframeCount);
        if (nextFrame >= anim.keyframeCount) nextFrame = @rem(nextFrame, anim.keyframeCount);

        var bindPoseMatrix = std.mem.zeroes(Matrix);
        var currentPoseMatrix = std.mem.zeroes(Matrix);

        var bi: usize = 0;
        while (bi < model.skeleton.boneCount) : (bi += 1) {
            const cf: usize = @intCast(currentFrame);
            const nf: usize = @intCast(nextFrame);
            model.currentPose[bi].translation = Vector3Lerp(anim.keyframePoses[cf][bi].translation, anim.keyframePoses[nf][bi].translation, blend);
            model.currentPose[bi].rotation = QuaternionSlerp(anim.keyframePoses[cf][bi].rotation, anim.keyframePoses[nf][bi].rotation, blend);
            model.currentPose[bi].scale = Vector3Lerp(anim.keyframePoses[cf][bi].scale, anim.keyframePoses[nf][bi].scale, blend);

            const bindPoseTransform = &model.skeleton.bindPose[bi];
            bindPoseMatrix = MatrixMultiply(MatrixMultiply(MatrixScale(bindPoseTransform.scale.x, bindPoseTransform.scale.y, bindPoseTransform.scale.z), QuaternionToMatrix(bindPoseTransform.rotation)), MatrixTranslate(bindPoseTransform.translation.x, bindPoseTransform.translation.y, bindPoseTransform.translation.z));

            const currentPoseTransform = &model.currentPose[bi];
            currentPoseMatrix = MatrixMultiply(MatrixMultiply(MatrixScale(currentPoseTransform.scale.x, currentPoseTransform.scale.y, currentPoseTransform.scale.z), QuaternionToMatrix(currentPoseTransform.rotation)), MatrixTranslate(currentPoseTransform.translation.x, currentPoseTransform.translation.y, currentPoseTransform.translation.z));

            model.boneMatrices[bi] = MatrixMultiply(MatrixInvert(bindPoseMatrix), currentPoseMatrix);
        }
    }
}

// Update model animation data (vertex buffers / bone matrices) for a specific pose
// NOTE: Animated vertex data is uploaded to GPU in case of CPU skinning; for GPU
// skinning, bone matrices are uploaded to the shader on DrawModelEx()
export fn UpdateModelAnimation(model: Model, anim: ModelAnimation, frame: f32) callconv(.c) void {
    if ((anim.keyframeCount > 0) and (model.skeleton.bones != null) and (anim.keyframePoses != null)) {
        UpdateModelAnimationBones(model, anim, frame);
        UpdateModelAnimationVertexBuffers(model);
    }
}

// Update model animation data (bone matrices) for a pose defined by two animations blended together
// NOTE: Not declared in raylib.h, but a public (non-static) symbol of upstream rmodels.c
export fn UpdateModelAnimationBonesEx(model: Model, animA: ModelAnimation, frameA: f32, animB: ModelAnimation, frameB: f32, blend: f32) callconv(.c) void {
    if (model.boneMatrices == null) return;

    if ((animA.keyframeCount > 0) and (animA.keyframePoses != null) and
        (animB.keyframeCount > 0) and (animB.keyframePoses != null) and
        (blend >= 0.0) and (blend <= 1.0))
    {
        var currentFrameA: c_int = @rem(@as(c_int, @intFromFloat(frameA)), animA.keyframeCount);
        var nextFrameA: c_int = currentFrameA + 1;
        var blendA: f32 = frameA - @as(f32, @floatFromInt(currentFrameA));
        blendA = Clamp(blendA, 0.0, 1.0);
        if (currentFrameA >= animA.keyframeCount) currentFrameA = @rem(currentFrameA, animA.keyframeCount);
        if (nextFrameA >= animA.keyframeCount) nextFrameA = @rem(nextFrameA, animA.keyframeCount);

        var currentFrameB: c_int = @rem(@as(c_int, @intFromFloat(frameB)), animB.keyframeCount);
        var nextFrameB: c_int = currentFrameB + 1;
        var blendB: f32 = frameB - @as(f32, @floatFromInt(currentFrameB));
        blendB = Clamp(blendB, 0.0, 1.0);
        if (currentFrameB >= animB.keyframeCount) currentFrameB = @rem(currentFrameB, animB.keyframeCount);
        if (nextFrameB >= animB.keyframeCount) nextFrameB = @rem(nextFrameB, animB.keyframeCount);

        var bindPoseMatrix = std.mem.zeroes(Matrix);
        var currentPoseMatrix = std.mem.zeroes(Matrix);

        var bi: usize = 0;
        while (bi < model.skeleton.boneCount) : (bi += 1) {
            const cfa: usize = @intCast(currentFrameA);
            const nfa: usize = @intCast(nextFrameA);
            const cfb: usize = @intCast(currentFrameB);
            const nfb: usize = @intCast(nextFrameB);

            const frameATranslation = Vector3Lerp(animA.keyframePoses[cfa][bi].translation, animA.keyframePoses[nfa][bi].translation, blendA);
            const frameARotation = QuaternionSlerp(animA.keyframePoses[cfa][bi].rotation, animA.keyframePoses[nfa][bi].rotation, blendA);
            const frameAScale = Vector3Lerp(animA.keyframePoses[cfa][bi].scale, animA.keyframePoses[nfa][bi].scale, blendA);

            const frameBTranslation = Vector3Lerp(animB.keyframePoses[cfb][bi].translation, animB.keyframePoses[nfb][bi].translation, blendB);
            const frameBRotation = QuaternionSlerp(animB.keyframePoses[cfb][bi].rotation, animB.keyframePoses[nfb][bi].rotation, blendB);
            const frameBScale = Vector3Lerp(animB.keyframePoses[cfb][bi].scale, animB.keyframePoses[nfb][bi].scale, blendB);

            model.currentPose[bi].translation = Vector3Lerp(frameATranslation, frameBTranslation, blend);
            model.currentPose[bi].rotation = QuaternionSlerp(frameARotation, frameBRotation, blend);
            model.currentPose[bi].scale = Vector3Lerp(frameAScale, frameBScale, blend);

            const bindPoseTransform = &model.skeleton.bindPose[bi];
            bindPoseMatrix = MatrixMultiply(MatrixMultiply(MatrixScale(bindPoseTransform.scale.x, bindPoseTransform.scale.y, bindPoseTransform.scale.z), QuaternionToMatrix(bindPoseTransform.rotation)), MatrixTranslate(bindPoseTransform.translation.x, bindPoseTransform.translation.y, bindPoseTransform.translation.z));

            const currentPoseTransform = &model.currentPose[bi];
            currentPoseMatrix = MatrixMultiply(MatrixMultiply(MatrixScale(currentPoseTransform.scale.x, currentPoseTransform.scale.y, currentPoseTransform.scale.z), QuaternionToMatrix(currentPoseTransform.rotation)), MatrixTranslate(currentPoseTransform.translation.x, currentPoseTransform.translation.y, currentPoseTransform.translation.z));

            model.boneMatrices[bi] = MatrixMultiply(MatrixInvert(bindPoseMatrix), currentPoseMatrix);
        }
    }
}

// Update model animation data (vertex buffers / bone matrices) for a pose defined by
// two animations blended together
export fn UpdateModelAnimationEx(model: Model, animA: ModelAnimation, frameA: f32, animB: ModelAnimation, frameB: f32, blend: f32) callconv(.c) void {
    if (model.boneMatrices == null) return;

    if ((animA.keyframeCount > 0) and (animA.keyframePoses != null) and
        (animB.keyframeCount > 0) and (animB.keyframePoses != null) and
        (blend >= 0.0) and (blend <= 1.0))
    {
        UpdateModelAnimationBonesEx(model, animA, frameA, animB, frameB, blend);
        UpdateModelAnimationVertexBuffers(model);
    }
}

// Update model vertex animation buffers (positions and normals)
// NOTE: Required for CPU skinning, uploads animated vertex buffers to GPU
// NOTE: Upstream 6.2 also precomputes a per-bone normal matrix table here that it never
// reads (normals still use the per-vertex MatrixTranspose(MatrixInvert(...))); that dead
// computation has no observable effect and is not ported
fn UpdateModelAnimationVertexBuffers(model: Model) void {
    var m: c_int = 0;
    while (m < model.meshCount) : (m += 1) {
        const mesh = &model.meshes[@intCast(m)]; // Not a copy: CPU buffers may be allocated below
        var animVertex = std.mem.zeroes(Vector3);
        var animNormal = std.mem.zeroes(Vector3);
        const vertexValuesCount = mesh.vertexCount * 3;

        var boneIndex: c_int = 0;
        var boneCounter: c_int = 0;
        var boneWeight: f32 = 0.0;
        var bufferUpdateRequired = false;

        if ((mesh.boneWeights == null) or (mesh.boneIndices == null)) continue;

        // Skip if the shader is using the bones directly
        if (SUPPORT_GPU_SKINNING) {
            const material = model.materials[@intCast(model.meshMaterial[@intCast(m)])];
            if ((material.shader.locs != null) and (material.shader.locs[SHADER_LOC_VERTEX_BONEIDS] != -1)) continue;
        }

        // Lazy allocation of CPU animation buffers (positions and normals) for software skinning
        const valuesSize: usize = @as(usize, @intCast(mesh.vertexCount * 3)) * @sizeOf(f32);
        if (mesh.animVertices == null) {
            mesh.animVertices = @ptrCast(@alignCast(RL_CALLOC(@intCast(mesh.vertexCount * 3), @sizeOf(f32))));
            _ = memcpy(mesh.animVertices, mesh.vertices, valuesSize);
        }
        if ((mesh.normals != null) and (mesh.animNormals == null)) {
            mesh.animNormals = @ptrCast(@alignCast(RL_CALLOC(@intCast(mesh.vertexCount * 3), @sizeOf(f32))));
            _ = memcpy(mesh.animNormals, mesh.normals, valuesSize);
        }

        var vCounter: c_int = 0;
        while (vCounter < vertexValuesCount) : (vCounter += 3) {
            const vc: usize = @intCast(vCounter);
            mesh.animVertices[vc] = 0;
            mesh.animVertices[vc + 1] = 0;
            mesh.animVertices[vc + 2] = 0;
            if (mesh.animNormals != null) {
                mesh.animNormals[vc] = 0;
                mesh.animNormals[vc + 1] = 0;
                mesh.animNormals[vc + 2] = 0;
            }

            var j: c_int = 0;
            while (j < 4) : ({
                j += 1;
                boneCounter += 1;
            }) {
                const bc: usize = @intCast(boneCounter);
                boneWeight = mesh.boneWeights[bc];
                boneIndex = mesh.boneIndices[bc];

                if (boneWeight == 0.0) continue;
                animVertex = .{ .x = mesh.vertices[vc], .y = mesh.vertices[vc + 1], .z = mesh.vertices[vc + 2] };
                animVertex = Vector3Transform(animVertex, model.boneMatrices[@intCast(boneIndex)]);
                mesh.animVertices[vc] += animVertex.x * boneWeight;
                mesh.animVertices[vc + 1] += animVertex.y * boneWeight;
                mesh.animVertices[vc + 2] += animVertex.z * boneWeight;
                bufferUpdateRequired = true;

                if ((mesh.normals != null) and (mesh.animNormals != null)) {
                    animNormal = .{ .x = mesh.normals[vc], .y = mesh.normals[vc + 1], .z = mesh.normals[vc + 2] };
                    animNormal = Vector3Transform(animNormal, MatrixTranspose(MatrixInvert(model.boneMatrices[@intCast(boneIndex)])));
                    mesh.animNormals[vc] += animNormal.x * boneWeight;
                    mesh.animNormals[vc + 1] += animNormal.y * boneWeight;
                    mesh.animNormals[vc + 2] += animNormal.z * boneWeight;
                }
            }
        }

        if (bufferUpdateRequired) {
            rlUpdateVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_POSITION], mesh.animVertices, mesh.vertexCount * 3 * @sizeOf(f32), 0);
            if (mesh.normals != null) rlUpdateVertexBuffer(mesh.vboId[RL_DEFAULT_SHADER_ATTRIB_LOCATION_NORMAL], mesh.animNormals, mesh.vertexCount * 3 * @sizeOf(f32), 0);
        }
    }
}

// Unload animation array data
export fn UnloadModelAnimations(animations: [*c]ModelAnimation, animCount: c_int) callconv(.c) void {
    var a: c_int = 0;
    while (a < animCount) : (a += 1) {
        var i: c_int = 0;
        while (i < animations[@intCast(a)].keyframeCount) : (i += 1) RL_FREE(animations[@intCast(a)].keyframePoses[@intCast(i)]);
        RL_FREE(animations[@intCast(a)].keyframePoses);
    }
    RL_FREE(animations);
}

// Check model animation skeleton match
export fn IsModelAnimationValid(model: Model, anim: ModelAnimation) callconv(.c) bool {
    var result = true;
    if (model.skeleton.boneCount != anim.boneCount) result = false;
    return result;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Mesh bounding box / tangents
//----------------------------------------------------------------------------------

// Compute mesh bounding box limits
export fn GetMeshBoundingBox(mesh: Mesh) callconv(.c) BoundingBox {
    var minVertex = std.mem.zeroes(Vector3);
    var maxVertex = std.mem.zeroes(Vector3);

    if (mesh.vertices != null) {
        minVertex = .{ .x = mesh.vertices[0], .y = mesh.vertices[1], .z = mesh.vertices[2] };
        maxVertex = .{ .x = mesh.vertices[0], .y = mesh.vertices[1], .z = mesh.vertices[2] };

        var i: c_int = 1;
        while (i < mesh.vertexCount) : (i += 1) {
            const u: usize = @intCast(i);
            const v: Vector3 = .{ .x = mesh.vertices[u * 3], .y = mesh.vertices[u * 3 + 1], .z = mesh.vertices[u * 3 + 2] };
            // C inlines raymath's fminf/fmaxf as LLVM minnum/maxnum, which is what
            // @min/@max lower to; the exported Vector3Min calls libm instead, and
            // the two disagree on the sign of a zero result
            minVertex = .{ .x = @min(minVertex.x, v.x), .y = @min(minVertex.y, v.y), .z = @min(minVertex.z, v.z) };
            maxVertex = .{ .x = @max(maxVertex.x, v.x), .y = @max(maxVertex.y, v.y), .z = @max(maxVertex.z, v.z) };
        }
    }

    var box = std.mem.zeroes(BoundingBox);
    box.min = minVertex;
    box.max = maxVertex;

    return box;
}

// Compute mesh tangents
export fn GenMeshTangents(mesh: [*c]Mesh) callconv(.c) void {
    if ((mesh == null) or (mesh.*.vertices == null) or (mesh.*.texcoords == null) or (mesh.*.normals == null)) {
        TraceLog(LOG_WARNING, "MESH: Tangents generation requires vertices, texcoords and normals vertex attribute data");
        return;
    }

    if (mesh.*.tangents == null) {
        mesh.*.tangents = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.*.vertexCount * 4 * @sizeOf(f32)))));
    } else {
        RL_FREE(mesh.*.tangents);
        mesh.*.tangents = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.*.vertexCount * 4 * @sizeOf(f32)))));
    }

    const tan1: [*c]Vector3 = @ptrCast(@alignCast(RL_CALLOC(@intCast(mesh.*.vertexCount), @sizeOf(Vector3))));
    const tan2: [*c]Vector3 = @ptrCast(@alignCast(RL_CALLOC(@intCast(mesh.*.vertexCount), @sizeOf(Vector3))));

    if (tan1 == null or tan2 == null) {
        TraceLog(LOG_WARNING, "MESH: Failed to allocate temporary memory for tangent calculation");
        if (tan1 != null) RL_FREE(tan1);
        if (tan2 != null) RL_FREE(tan2);
        return;
    }

    var t: c_int = 0;
    while (t < mesh.*.triangleCount) : (t += 1) {
        var idx0: c_int = 0;
        var idx1: c_int = 0;
        var idx2: c_int = 0;

        if (mesh.*.indices != null) {
            idx0 = mesh.*.indices[@intCast(t * 3 + 0)];
            idx1 = mesh.*.indices[@intCast(t * 3 + 1)];
            idx2 = mesh.*.indices[@intCast(t * 3 + 2)];
        } else {
            idx0 = t * 3 + 0;
            idx1 = t * 3 + 1;
            idx2 = t * 3 + 2;
        }

        const vi0: usize = @intCast(idx0);
        const vi1: usize = @intCast(idx1);
        const vi2: usize = @intCast(idx2);

        const v1 = Vector3{ .x = mesh.*.vertices[vi0 * 3 + 0], .y = mesh.*.vertices[vi0 * 3 + 1], .z = mesh.*.vertices[vi0 * 3 + 2] };
        const v2 = Vector3{ .x = mesh.*.vertices[vi1 * 3 + 0], .y = mesh.*.vertices[vi1 * 3 + 1], .z = mesh.*.vertices[vi1 * 3 + 2] };
        const v3 = Vector3{ .x = mesh.*.vertices[vi2 * 3 + 0], .y = mesh.*.vertices[vi2 * 3 + 1], .z = mesh.*.vertices[vi2 * 3 + 2] };

        const uv1 = Vector2{ .x = mesh.*.texcoords[vi0 * 2 + 0], .y = mesh.*.texcoords[vi0 * 2 + 1] };
        const uv2 = Vector2{ .x = mesh.*.texcoords[vi1 * 2 + 0], .y = mesh.*.texcoords[vi1 * 2 + 1] };
        const uv3 = Vector2{ .x = mesh.*.texcoords[vi2 * 2 + 0], .y = mesh.*.texcoords[vi2 * 2 + 1] };

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
        const r: f32 = if (fabsf(div) < 0.0001) 0.0 else 1.0 / div;

        const sdir = Vector3{ .x = (t2 * x1 - t1 * x2) * r, .y = (t2 * y1 - t1 * y2) * r, .z = (t2 * z1 - t1 * z2) * r };
        const tdir = Vector3{ .x = (s1 * x2 - s2 * x1) * r, .y = (s1 * y2 - s2 * y1) * r, .z = (s1 * z2 - s2 * z1) * r };

        tan1[vi0] = Vector3Add(tan1[vi0], sdir);
        tan1[vi1] = Vector3Add(tan1[vi1], sdir);
        tan1[vi2] = Vector3Add(tan1[vi2], sdir);

        tan2[vi0] = Vector3Add(tan2[vi0], tdir);
        tan2[vi1] = Vector3Add(tan2[vi1], tdir);
        tan2[vi2] = Vector3Add(tan2[vi2], tdir);
    }

    var i: c_int = 0;
    while (i < mesh.*.vertexCount) : (i += 1) {
        const u: usize = @intCast(i);
        const normal = Vector3{ .x = mesh.*.normals[u * 3 + 0], .y = mesh.*.normals[u * 3 + 1], .z = mesh.*.normals[u * 3 + 2] };
        var tangent = tan1[u];

        if (Vector3Length(tangent) < 0.0001) {
            if (fabsf(normal.z) > 0.707) tangent = .{ .x = 1.0, .y = 0.0, .z = 0.0 } else tangent = Vector3Normalize(.{ .x = -normal.y, .y = normal.x, .z = 0.0 });

            mesh.*.tangents[u * 4 + 0] = tangent.x;
            mesh.*.tangents[u * 4 + 1] = tangent.y;
            mesh.*.tangents[u * 4 + 2] = tangent.z;
            mesh.*.tangents[u * 4 + 3] = 1.0;
            continue;
        }

        var orthogonalized = Vector3Subtract(tangent, Vector3Scale(normal, Vector3DotProduct(normal, tangent)));

        if (Vector3Length(orthogonalized) < 0.0001) {
            if (fabsf(normal.z) > 0.707) orthogonalized = .{ .x = 1.0, .y = 0.0, .z = 0.0 } else orthogonalized = Vector3Normalize(.{ .x = -normal.y, .y = normal.x, .z = 0.0 });
        } else {
            orthogonalized = Vector3Normalize(orthogonalized);
        }

        mesh.*.tangents[u * 4 + 0] = orthogonalized.x;
        mesh.*.tangents[u * 4 + 1] = orthogonalized.y;
        mesh.*.tangents[u * 4 + 2] = orthogonalized.z;

        mesh.*.tangents[u * 4 + 3] = if (Vector3DotProduct(Vector3CrossProduct(normal, orthogonalized), tan2[u]) < 0.0) -1.0 else 1.0;
    }

    RL_FREE(tan1);
    RL_FREE(tan2);

    if (mesh.*.vboId != null) {
        if (mesh.*.vboId[SHADER_LOC_VERTEX_TANGENT] != 0) {
            rlUpdateVertexBuffer(mesh.*.vboId[SHADER_LOC_VERTEX_TANGENT], mesh.*.tangents, mesh.*.vertexCount * 4 * @sizeOf(f32), 0);
        } else {
            mesh.*.vboId[SHADER_LOC_VERTEX_TANGENT] = rlLoadVertexBuffer(mesh.*.tangents, mesh.*.vertexCount * 4 * @sizeOf(f32), false);
        }

        _ = rlEnableVertexArray(mesh.*.vaoId);
        rlSetVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT, 4, RL_FLOAT, false, 0, 0);
        rlEnableVertexAttribute(RL_DEFAULT_SHADER_ATTRIB_LOCATION_TANGENT);
        rlDisableVertexArray();
    }

    TraceLog(LOG_INFO, "MESH: Tangents data computed and uploaded for provided mesh");
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Mesh generation
//----------------------------------------------------------------------------------

// Copy a par_shapes mesh (indexed) into a raylib Mesh (de-indexed triangle soup)
fn copyParShapesMesh(mesh: *Mesh, ps: *par_shapes_mesh) void {
    mesh.vertices = @ptrCast(@alignCast(RL_MALLOC(@intCast(ps.ntriangles * 3 * 3 * @sizeOf(f32)))));
    mesh.texcoords = @ptrCast(@alignCast(RL_MALLOC(@intCast(ps.ntriangles * 3 * 2 * @sizeOf(f32)))));
    mesh.normals = @ptrCast(@alignCast(RL_MALLOC(@intCast(ps.ntriangles * 3 * 3 * @sizeOf(f32)))));

    mesh.vertexCount = ps.ntriangles * 3;
    mesh.triangleCount = ps.ntriangles;

    var k: c_int = 0;
    while (k < mesh.vertexCount) : (k += 1) {
        const uk: usize = @intCast(k);
        const ti: usize = @intCast(ps.triangles[uk]);
        mesh.vertices[uk * 3] = ps.points[ti * 3];
        mesh.vertices[uk * 3 + 1] = ps.points[ti * 3 + 1];
        mesh.vertices[uk * 3 + 2] = ps.points[ti * 3 + 2];

        mesh.normals[uk * 3] = ps.normals[ti * 3];
        mesh.normals[uk * 3 + 1] = ps.normals[ti * 3 + 1];
        mesh.normals[uk * 3 + 2] = ps.normals[ti * 3 + 2];

        mesh.texcoords[uk * 2] = ps.tcoords[ti * 2];
        mesh.texcoords[uk * 2 + 1] = ps.tcoords[ti * 2 + 1];
    }
}

// Generate polygonal mesh
export fn GenMeshPoly(sides: c_int, radius: f32) callconv(.c) Mesh {
    var mesh = std.mem.zeroes(Mesh);

    if (sides < 3) return mesh; // Security check

    const vertexCount = sides * 3;

    const vertices: [*c]Vector3 = @ptrCast(@alignCast(RL_MALLOC(@intCast(vertexCount * @sizeOf(Vector3)))));

    var d: f32 = 0.0;
    const dStep: f32 = 360.0 / @as(f32, @floatFromInt(sides));
    var v: c_int = 0;
    while (v < vertexCount - 2) : (v += 3) {
        const uv: usize = @intCast(v);
        vertices[uv] = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
        vertices[uv + 1] = .{ .x = sinf(DEG2RAD * d) * radius, .y = 0.0, .z = cosf(DEG2RAD * d) * radius };
        vertices[uv + 2] = .{ .x = sinf(DEG2RAD * (d + dStep)) * radius, .y = 0.0, .z = cosf(DEG2RAD * (d + dStep)) * radius };
        d += dStep;
    }

    const normals: [*c]Vector3 = @ptrCast(@alignCast(RL_MALLOC(@intCast(vertexCount * @sizeOf(Vector3)))));
    var n: c_int = 0;
    while (n < vertexCount) : (n += 1) normals[@intCast(n)] = .{ .x = 0.0, .y = 1.0, .z = 0.0 };

    const texcoords: [*c]Vector2 = @ptrCast(@alignCast(RL_MALLOC(@intCast(vertexCount * @sizeOf(Vector2)))));
    n = 0;
    while (n < vertexCount) : (n += 1) texcoords[@intCast(n)] = .{ .x = 0.0, .y = 0.0 };

    mesh.vertexCount = vertexCount;
    mesh.triangleCount = sides;
    mesh.vertices = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 3 * @sizeOf(f32)))));
    mesh.texcoords = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 2 * @sizeOf(f32)))));
    mesh.normals = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 3 * @sizeOf(f32)))));

    var i: c_int = 0;
    while (i < mesh.vertexCount) : (i += 1) {
        const ui: usize = @intCast(i);
        mesh.vertices[3 * ui] = vertices[ui].x;
        mesh.vertices[3 * ui + 1] = vertices[ui].y;
        mesh.vertices[3 * ui + 2] = vertices[ui].z;
    }

    i = 0;
    while (i < mesh.vertexCount) : (i += 1) {
        const ui: usize = @intCast(i);
        mesh.texcoords[2 * ui] = texcoords[ui].x;
        mesh.texcoords[2 * ui + 1] = texcoords[ui].y;
    }

    i = 0;
    while (i < mesh.vertexCount) : (i += 1) {
        const ui: usize = @intCast(i);
        mesh.normals[3 * ui] = normals[ui].x;
        mesh.normals[3 * ui + 1] = normals[ui].y;
        mesh.normals[3 * ui + 2] = normals[ui].z;
    }

    RL_FREE(vertices);
    RL_FREE(normals);
    RL_FREE(texcoords);

    UploadMesh(&mesh, false);

    return mesh;
}

// Generate plane mesh (with subdivisions)
export fn GenMeshPlane(width: f32, length: f32, resX_in: c_int, resZ_in: c_int) callconv(.c) Mesh {
    var mesh = std.mem.zeroes(Mesh);

    const resX = resX_in + 1;
    const resZ = resZ_in + 1;

    const vertexCount = resX * resZ; // vertices get reused for the faces

    const vertices: [*c]Vector3 = @ptrCast(@alignCast(RL_MALLOC(@intCast(vertexCount * @sizeOf(Vector3)))));
    {
        var z: c_int = 0;
        while (z < resZ) : (z += 1) {
            const zPos = (@as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(resZ - 1)) - 0.5) * length;
            var x: c_int = 0;
            while (x < resX) : (x += 1) {
                const xPos = (@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(resX - 1)) - 0.5) * width;
                vertices[@intCast(x + z * resX)] = .{ .x = xPos, .y = 0.0, .z = zPos };
            }
        }
    }

    const normals: [*c]Vector3 = @ptrCast(@alignCast(RL_MALLOC(@intCast(vertexCount * @sizeOf(Vector3)))));
    {
        var nn: c_int = 0;
        while (nn < vertexCount) : (nn += 1) normals[@intCast(nn)] = .{ .x = 0.0, .y = 1.0, .z = 0.0 };
    }

    const texcoords: [*c]Vector2 = @ptrCast(@alignCast(RL_MALLOC(@intCast(vertexCount * @sizeOf(Vector2)))));
    {
        var vv: c_int = 0;
        while (vv < resZ) : (vv += 1) {
            var uu: c_int = 0;
            while (uu < resX) : (uu += 1) {
                texcoords[@intCast(uu + vv * resX)] = .{ .x = @as(f32, @floatFromInt(uu)) / @as(f32, @floatFromInt(resX - 1)), .y = @as(f32, @floatFromInt(vv)) / @as(f32, @floatFromInt(resZ - 1)) };
            }
        }
    }

    const numFaces = (resX - 1) * (resZ - 1);
    const triangles: [*c]c_int = @ptrCast(@alignCast(RL_MALLOC(@intCast(numFaces * 6 * @sizeOf(c_int)))));
    {
        var t: usize = 0;
        var face: c_int = 0;
        while (face < numFaces) : (face += 1) {
            const i = face + @divTrunc(face, (resX - 1));
            triangles[t] = i + resX;
            t += 1;
            triangles[t] = i + 1;
            t += 1;
            triangles[t] = i;
            t += 1;
            triangles[t] = i + resX;
            t += 1;
            triangles[t] = i + resX + 1;
            t += 1;
            triangles[t] = i + 1;
            t += 1;
        }
    }

    mesh.vertexCount = vertexCount;
    mesh.triangleCount = numFaces * 2;
    mesh.vertices = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 3 * @sizeOf(f32)))));
    mesh.texcoords = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 2 * @sizeOf(f32)))));
    mesh.normals = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 3 * @sizeOf(f32)))));
    mesh.indices = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.triangleCount * 3 * @sizeOf(c_ushort)))));

    {
        var i: c_int = 0;
        while (i < mesh.vertexCount) : (i += 1) {
            const ui: usize = @intCast(i);
            mesh.vertices[3 * ui] = vertices[ui].x;
            mesh.vertices[3 * ui + 1] = vertices[ui].y;
            mesh.vertices[3 * ui + 2] = vertices[ui].z;
        }
        i = 0;
        while (i < mesh.vertexCount) : (i += 1) {
            const ui: usize = @intCast(i);
            mesh.texcoords[2 * ui] = texcoords[ui].x;
            mesh.texcoords[2 * ui + 1] = texcoords[ui].y;
        }
        i = 0;
        while (i < mesh.vertexCount) : (i += 1) {
            const ui: usize = @intCast(i);
            mesh.normals[3 * ui] = normals[ui].x;
            mesh.normals[3 * ui + 1] = normals[ui].y;
            mesh.normals[3 * ui + 2] = normals[ui].z;
        }
        i = 0;
        while (i < mesh.triangleCount * 3) : (i += 1) mesh.indices[@intCast(i)] = @intCast(triangles[@intCast(i)]);
    }

    RL_FREE(vertices);
    RL_FREE(normals);
    RL_FREE(texcoords);
    RL_FREE(triangles);

    UploadMesh(&mesh, false);

    return mesh;
}

// Generate cuboid mesh
export fn GenMeshCube(width: f32, height: f32, length: f32) callconv(.c) Mesh {
    var mesh = std.mem.zeroes(Mesh);

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

    mesh.vertices = @ptrCast(@alignCast(RL_MALLOC(24 * 3 * @sizeOf(f32))));
    _ = memcpy(mesh.vertices, &vertices, 24 * 3 * @sizeOf(f32));

    mesh.texcoords = @ptrCast(@alignCast(RL_MALLOC(24 * 2 * @sizeOf(f32))));
    _ = memcpy(mesh.texcoords, &texcoords, 24 * 2 * @sizeOf(f32));

    mesh.normals = @ptrCast(@alignCast(RL_MALLOC(24 * 3 * @sizeOf(f32))));
    _ = memcpy(mesh.normals, &normals, 24 * 3 * @sizeOf(f32));

    mesh.indices = @ptrCast(@alignCast(RL_MALLOC(36 * @sizeOf(c_ushort))));

    var k: c_ushort = 0;
    var i: usize = 0;
    while (i < 36) : (i += 6) {
        mesh.indices[i] = 4 * k;
        mesh.indices[i + 1] = 4 * k + 1;
        mesh.indices[i + 2] = 4 * k + 2;
        mesh.indices[i + 3] = 4 * k;
        mesh.indices[i + 4] = 4 * k + 2;
        mesh.indices[i + 5] = 4 * k + 3;
        k += 1;
    }

    mesh.vertexCount = 24;
    mesh.triangleCount = 12;

    UploadMesh(&mesh, false);

    return mesh;
}

// Generate sphere mesh (standard sphere)
export fn GenMeshSphere(radius: f32, rings: c_int, slices: c_int) callconv(.c) Mesh {
    var mesh = std.mem.zeroes(Mesh);

    if ((rings >= 3) and (slices >= 3)) {
        par_shapes_set_epsilon_degenerate_sphere(0.0);
        const sphere = par_shapes_create_parametric_sphere(slices, rings).?;
        par_shapes_scale(sphere, radius, radius, radius);

        copyParShapesMesh(&mesh, sphere);

        par_shapes_free_mesh(sphere);

        UploadMesh(&mesh, false);
    } else TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: sphere");

    return mesh;
}

// Generate hemisphere mesh (half sphere, no bottom cap)
export fn GenMeshHemiSphere(radius_in: f32, rings: c_int, slices: c_int) callconv(.c) Mesh {
    var mesh = std.mem.zeroes(Mesh);
    var radius = radius_in;

    if ((rings >= 3) and (slices >= 3)) {
        if (radius < 0.0) radius = 0.0;

        const sphere = par_shapes_create_hemisphere(slices, rings).?;
        par_shapes_scale(sphere, radius, radius, radius);

        copyParShapesMesh(&mesh, sphere);

        par_shapes_free_mesh(sphere);

        UploadMesh(&mesh, false);
    } else TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: hemisphere");

    return mesh;
}

// Generate cylinder mesh
export fn GenMeshCylinder(radius: f32, height: f32, slices: c_int) callconv(.c) Mesh {
    var mesh = std.mem.zeroes(Mesh);

    if (slices >= 3) {
        const cylinder = par_shapes_create_cylinder(slices, 8).?;
        par_shapes_scale(cylinder, radius, radius, height);
        par_shapes_rotate(cylinder, -PI / 2.0, &[_]f32{ 1, 0, 0 });

        const capTop = par_shapes_create_disk(radius, slices, &[_]f32{ 0, 0, 0 }, &[_]f32{ 0, 0, 1 }).?;
        capTop.tcoords = @ptrCast(@alignCast(RL_MALLOC(@intCast(2 * capTop.npoints * @sizeOf(f32)))));
        {
            var i: c_int = 0;
            while (i < 2 * capTop.npoints) : (i += 1) capTop.tcoords[@intCast(i)] = 0.0;
        }
        par_shapes_rotate(capTop, -PI / 2.0, &[_]f32{ 1, 0, 0 });
        par_shapes_rotate(capTop, 90 * DEG2RAD, &[_]f32{ 0, 1, 0 });
        par_shapes_translate(capTop, 0, height, 0);

        const capBottom = par_shapes_create_disk(radius, slices, &[_]f32{ 0, 0, 0 }, &[_]f32{ 0, 0, -1 }).?;
        capBottom.tcoords = @ptrCast(@alignCast(RL_MALLOC(@intCast(2 * capBottom.npoints * @sizeOf(f32)))));
        {
            var i: c_int = 0;
            while (i < 2 * capBottom.npoints) : (i += 1) capBottom.tcoords[@intCast(i)] = 0.95;
        }
        par_shapes_rotate(capBottom, PI / 2.0, &[_]f32{ 1, 0, 0 });
        par_shapes_rotate(capBottom, -90 * DEG2RAD, &[_]f32{ 0, 1, 0 });

        par_shapes_merge_and_free(cylinder, capTop);
        par_shapes_merge_and_free(cylinder, capBottom);

        copyParShapesMesh(&mesh, cylinder);

        par_shapes_free_mesh(cylinder);

        UploadMesh(&mesh, false);
    } else TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: cylinder");

    return mesh;
}

// Generate cone/pyramid mesh
export fn GenMeshCone(radius: f32, height: f32, slices: c_int) callconv(.c) Mesh {
    var mesh = std.mem.zeroes(Mesh);

    if (slices >= 3) {
        const cone = par_shapes_create_cone(slices, 8).?;
        par_shapes_scale(cone, radius, radius, height);
        par_shapes_rotate(cone, -PI / 2.0, &[_]f32{ 1, 0, 0 });
        par_shapes_rotate(cone, PI / 2.0, &[_]f32{ 0, 1, 0 });

        const capBottom = par_shapes_create_disk(radius, slices, &[_]f32{ 0, 0, 0 }, &[_]f32{ 0, 0, -1 }).?;
        capBottom.tcoords = @ptrCast(@alignCast(RL_MALLOC(@intCast(2 * capBottom.npoints * @sizeOf(f32)))));
        {
            var i: c_int = 0;
            while (i < 2 * capBottom.npoints) : (i += 1) capBottom.tcoords[@intCast(i)] = 0.95;
        }
        par_shapes_rotate(capBottom, PI / 2.0, &[_]f32{ 1, 0, 0 });

        par_shapes_merge_and_free(cone, capBottom);

        copyParShapesMesh(&mesh, cone);

        par_shapes_free_mesh(cone);

        UploadMesh(&mesh, false);
    } else TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: cone");

    return mesh;
}

// Generate torus mesh
export fn GenMeshTorus(radius_in: f32, size: f32, radSeg: c_int, sides: c_int) callconv(.c) Mesh {
    var mesh = std.mem.zeroes(Mesh);
    var radius = radius_in;

    if ((sides >= 3) and (radSeg >= 3)) {
        if (radius > 1.0) radius = 1.0 else if (radius < 0.1) radius = 0.1;

        const torus = par_shapes_create_torus(radSeg, sides, radius).?;
        par_shapes_scale(torus, size / 2, size / 2, size / 2);

        copyParShapesMesh(&mesh, torus);

        par_shapes_free_mesh(torus);

        UploadMesh(&mesh, false);
    } else TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: torus");

    return mesh;
}

// Generate trefoil knot mesh
export fn GenMeshKnot(radius_in: f32, size: f32, radSeg: c_int, sides: c_int) callconv(.c) Mesh {
    var mesh = std.mem.zeroes(Mesh);
    var radius = radius_in;

    if ((sides >= 3) and (radSeg >= 3)) {
        if (radius > 3.0) radius = 3.0 else if (radius < 0.5) radius = 0.5;

        const knot = par_shapes_create_trefoil_knot(radSeg, sides, radius).?;
        par_shapes_scale(knot, size, size, size);

        copyParShapesMesh(&mesh, knot);

        par_shapes_free_mesh(knot);

        UploadMesh(&mesh, false);
    } else TraceLog(LOG_WARNING, "MESH: Failed to generate mesh: knot");

    return mesh;
}

// Generate a mesh from heightmap
export fn GenMeshHeightmap(heightmap: Image, size: Vector3) callconv(.c) Mesh {
    var mesh = std.mem.zeroes(Mesh);

    const mapX = heightmap.width;
    const mapZ = heightmap.height;

    const pixels = LoadImageColors(heightmap);

    mesh.triangleCount = (mapX - 1) * (mapZ - 1) * 2;
    mesh.vertexCount = mesh.triangleCount * 3;

    mesh.vertices = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 3 * @sizeOf(f32)))));
    mesh.normals = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 3 * @sizeOf(f32)))));
    mesh.texcoords = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 2 * @sizeOf(f32)))));
    mesh.colors = null;

    var vCounter: usize = 0;
    var tcCounter: usize = 0;
    var nCounter: usize = 0;

    const scaleFactor = Vector3{ .x = size.x / @as(f32, @floatFromInt(mapX - 1)), .y = size.y / 255.0, .z = size.z / @as(f32, @floatFromInt(mapZ - 1)) };

    var vA = std.mem.zeroes(Vector3);
    var vB = std.mem.zeroes(Vector3);
    var vC = std.mem.zeroes(Vector3);
    var vN = std.mem.zeroes(Vector3);

    var z: c_int = 0;
    while (z < mapZ - 1) : (z += 1) {
        var x: c_int = 0;
        while (x < mapX - 1) : (x += 1) {
            const fx = @as(f32, @floatFromInt(x));
            const fz = @as(f32, @floatFromInt(z));
            const fx1 = @as(f32, @floatFromInt(x + 1));
            const fz1 = @as(f32, @floatFromInt(z + 1));

            mesh.vertices[vCounter] = fx * scaleFactor.x;
            mesh.vertices[vCounter + 1] = grayValue(pixels[@intCast(x + z * mapX)]) * scaleFactor.y;
            mesh.vertices[vCounter + 2] = fz * scaleFactor.z;

            mesh.vertices[vCounter + 3] = fx * scaleFactor.x;
            mesh.vertices[vCounter + 4] = grayValue(pixels[@intCast(x + (z + 1) * mapX)]) * scaleFactor.y;
            mesh.vertices[vCounter + 5] = fz1 * scaleFactor.z;

            mesh.vertices[vCounter + 6] = fx1 * scaleFactor.x;
            mesh.vertices[vCounter + 7] = grayValue(pixels[@intCast((x + 1) + z * mapX)]) * scaleFactor.y;
            mesh.vertices[vCounter + 8] = fz * scaleFactor.z;

            mesh.vertices[vCounter + 9] = mesh.vertices[vCounter + 6];
            mesh.vertices[vCounter + 10] = mesh.vertices[vCounter + 7];
            mesh.vertices[vCounter + 11] = mesh.vertices[vCounter + 8];

            mesh.vertices[vCounter + 12] = mesh.vertices[vCounter + 3];
            mesh.vertices[vCounter + 13] = mesh.vertices[vCounter + 4];
            mesh.vertices[vCounter + 14] = mesh.vertices[vCounter + 5];

            mesh.vertices[vCounter + 15] = fx1 * scaleFactor.x;
            mesh.vertices[vCounter + 16] = grayValue(pixels[@intCast((x + 1) + (z + 1) * mapX)]) * scaleFactor.y;
            mesh.vertices[vCounter + 17] = fz1 * scaleFactor.z;
            vCounter += 18;

            mesh.texcoords[tcCounter] = fx / @as(f32, @floatFromInt(mapX - 1));
            mesh.texcoords[tcCounter + 1] = fz / @as(f32, @floatFromInt(mapZ - 1));

            mesh.texcoords[tcCounter + 2] = fx / @as(f32, @floatFromInt(mapX - 1));
            mesh.texcoords[tcCounter + 3] = fz1 / @as(f32, @floatFromInt(mapZ - 1));

            mesh.texcoords[tcCounter + 4] = fx1 / @as(f32, @floatFromInt(mapX - 1));
            mesh.texcoords[tcCounter + 5] = fz / @as(f32, @floatFromInt(mapZ - 1));

            mesh.texcoords[tcCounter + 6] = mesh.texcoords[tcCounter + 4];
            mesh.texcoords[tcCounter + 7] = mesh.texcoords[tcCounter + 5];

            mesh.texcoords[tcCounter + 8] = mesh.texcoords[tcCounter + 2];
            mesh.texcoords[tcCounter + 9] = mesh.texcoords[tcCounter + 3];

            mesh.texcoords[tcCounter + 10] = fx1 / @as(f32, @floatFromInt(mapX - 1));
            mesh.texcoords[tcCounter + 11] = fz1 / @as(f32, @floatFromInt(mapZ - 1));
            tcCounter += 12;

            var i: usize = 0;
            while (i < 18) : (i += 9) {
                vA.x = mesh.vertices[nCounter + i];
                vA.y = mesh.vertices[nCounter + i + 1];
                vA.z = mesh.vertices[nCounter + i + 2];

                vB.x = mesh.vertices[nCounter + i + 3];
                vB.y = mesh.vertices[nCounter + i + 4];
                vB.z = mesh.vertices[nCounter + i + 5];

                vC.x = mesh.vertices[nCounter + i + 6];
                vC.y = mesh.vertices[nCounter + i + 7];
                vC.z = mesh.vertices[nCounter + i + 8];

                vN = Vector3Normalize(Vector3CrossProduct(Vector3Subtract(vB, vA), Vector3Subtract(vC, vA)));

                mesh.normals[nCounter + i] = vN.x;
                mesh.normals[nCounter + i + 1] = vN.y;
                mesh.normals[nCounter + i + 2] = vN.z;

                mesh.normals[nCounter + i + 3] = vN.x;
                mesh.normals[nCounter + i + 4] = vN.y;
                mesh.normals[nCounter + i + 5] = vN.z;

                mesh.normals[nCounter + i + 6] = vN.x;
                mesh.normals[nCounter + i + 7] = vN.y;
                mesh.normals[nCounter + i + 8] = vN.z;
            }

            nCounter += 18;
        }
    }

    UnloadImageColors(pixels);

    UploadMesh(&mesh, false);

    return mesh;
}

fn grayValue(c: Color) f32 {
    return @as(f32, @floatFromInt(@as(c_int, c.r) + @as(c_int, c.g) + @as(c_int, c.b))) / 3.0;
}

fn colorEqual(c1: Color, c2: Color) bool {
    return (c1.r == c2.r) and (c1.g == c2.g) and (c1.b == c2.b) and (c1.a == c2.a);
}

const RectangleF = extern struct { x: f32, y: f32, width: f32, height: f32 };

// Generate a cubes mesh from pixel data
export fn GenMeshCubicmap(cubicmap: Image, cubeSize: Vector3) callconv(.c) Mesh {
    var mesh = std.mem.zeroes(Mesh);

    const pixels = LoadImageColors(cubicmap);

    const maxTriangles = cubicmap.width * cubicmap.height * 12;

    var vCounter: usize = 0;
    var tcCounter: usize = 0;
    var nCounter: usize = 0;

    const w = cubeSize.x;
    const h = cubeSize.z;
    const h2 = cubeSize.y;

    const mapVertices: [*c]Vector3 = @ptrCast(@alignCast(RL_MALLOC(@intCast(maxTriangles * 3 * @sizeOf(Vector3)))));
    const mapTexcoords: [*c]Vector2 = @ptrCast(@alignCast(RL_MALLOC(@intCast(maxTriangles * 3 * @sizeOf(Vector2)))));
    const mapNormals: [*c]Vector3 = @ptrCast(@alignCast(RL_MALLOC(@intCast(maxTriangles * 3 * @sizeOf(Vector3)))));

    const n1 = Vector3{ .x = 1.0, .y = 0.0, .z = 0.0 };
    const n2 = Vector3{ .x = -1.0, .y = 0.0, .z = 0.0 };
    const n3 = Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    const n4 = Vector3{ .x = 0.0, .y = -1.0, .z = 0.0 };
    const n5 = Vector3{ .x = 0.0, .y = 0.0, .z = -1.0 };
    const n6 = Vector3{ .x = 0.0, .y = 0.0, .z = 1.0 };

    const rightTexUV = RectangleF{ .x = 0.0, .y = 0.0, .width = 0.5, .height = 0.5 };
    const leftTexUV = RectangleF{ .x = 0.5, .y = 0.0, .width = 0.5, .height = 0.5 };
    const frontTexUV = RectangleF{ .x = 0.0, .y = 0.0, .width = 0.5, .height = 0.5 };
    const backTexUV = RectangleF{ .x = 0.5, .y = 0.0, .width = 0.5, .height = 0.5 };
    const topTexUV = RectangleF{ .x = 0.0, .y = 0.5, .width = 0.5, .height = 0.5 };
    const bottomTexUV = RectangleF{ .x = 0.5, .y = 0.5, .width = 0.5, .height = 0.5 };

    var z: c_int = 0;
    while (z < cubicmap.height) : (z += 1) {
        var x: c_int = 0;
        while (x < cubicmap.width) : (x += 1) {
            const fx = @as(f32, @floatFromInt(x));
            const fz = @as(f32, @floatFromInt(z));
            const v1 = Vector3{ .x = w * (fx - 0.5), .y = h2, .z = h * (fz - 0.5) };
            const v2 = Vector3{ .x = w * (fx - 0.5), .y = h2, .z = h * (fz + 0.5) };
            const v3 = Vector3{ .x = w * (fx + 0.5), .y = h2, .z = h * (fz + 0.5) };
            const v4 = Vector3{ .x = w * (fx + 0.5), .y = h2, .z = h * (fz - 0.5) };
            const v5 = Vector3{ .x = w * (fx + 0.5), .y = 0, .z = h * (fz - 0.5) };
            const v6 = Vector3{ .x = w * (fx - 0.5), .y = 0, .z = h * (fz - 0.5) };
            const v7 = Vector3{ .x = w * (fx - 0.5), .y = 0, .z = h * (fz + 0.5) };
            const v8 = Vector3{ .x = w * (fx + 0.5), .y = 0, .z = h * (fz + 0.5) };

            const pix = pixels[@intCast(z * cubicmap.width + x)];

            if (colorEqual(pix, WHITE)) {
                // Top
                mapVertices[vCounter] = v1;
                mapVertices[vCounter + 1] = v2;
                mapVertices[vCounter + 2] = v3;
                mapVertices[vCounter + 3] = v1;
                mapVertices[vCounter + 4] = v3;
                mapVertices[vCounter + 5] = v4;
                vCounter += 6;

                mapNormals[nCounter] = n3;
                mapNormals[nCounter + 1] = n3;
                mapNormals[nCounter + 2] = n3;
                mapNormals[nCounter + 3] = n3;
                mapNormals[nCounter + 4] = n3;
                mapNormals[nCounter + 5] = n3;
                nCounter += 6;

                mapTexcoords[tcCounter] = .{ .x = topTexUV.x, .y = topTexUV.y };
                mapTexcoords[tcCounter + 1] = .{ .x = topTexUV.x, .y = topTexUV.y + topTexUV.height };
                mapTexcoords[tcCounter + 2] = .{ .x = topTexUV.x + topTexUV.width, .y = topTexUV.y + topTexUV.height };
                mapTexcoords[tcCounter + 3] = .{ .x = topTexUV.x, .y = topTexUV.y };
                mapTexcoords[tcCounter + 4] = .{ .x = topTexUV.x + topTexUV.width, .y = topTexUV.y + topTexUV.height };
                mapTexcoords[tcCounter + 5] = .{ .x = topTexUV.x + topTexUV.width, .y = topTexUV.y };
                tcCounter += 6;

                // Bottom
                mapVertices[vCounter] = v6;
                mapVertices[vCounter + 1] = v8;
                mapVertices[vCounter + 2] = v7;
                mapVertices[vCounter + 3] = v6;
                mapVertices[vCounter + 4] = v5;
                mapVertices[vCounter + 5] = v8;
                vCounter += 6;

                mapNormals[nCounter] = n4;
                mapNormals[nCounter + 1] = n4;
                mapNormals[nCounter + 2] = n4;
                mapNormals[nCounter + 3] = n4;
                mapNormals[nCounter + 4] = n4;
                mapNormals[nCounter + 5] = n4;
                nCounter += 6;

                mapTexcoords[tcCounter] = .{ .x = bottomTexUV.x + bottomTexUV.width, .y = bottomTexUV.y };
                mapTexcoords[tcCounter + 1] = .{ .x = bottomTexUV.x, .y = bottomTexUV.y + bottomTexUV.height };
                mapTexcoords[tcCounter + 2] = .{ .x = bottomTexUV.x + bottomTexUV.width, .y = bottomTexUV.y + bottomTexUV.height };
                mapTexcoords[tcCounter + 3] = .{ .x = bottomTexUV.x + bottomTexUV.width, .y = bottomTexUV.y };
                mapTexcoords[tcCounter + 4] = .{ .x = bottomTexUV.x, .y = bottomTexUV.y };
                mapTexcoords[tcCounter + 5] = .{ .x = bottomTexUV.x, .y = bottomTexUV.y + bottomTexUV.height };
                tcCounter += 6;

                if (((z < cubicmap.height - 1) and colorEqual(pixels[@intCast((z + 1) * cubicmap.width + x)], BLACK)) or (z == cubicmap.height - 1)) {
                    // Front
                    mapVertices[vCounter] = v2;
                    mapVertices[vCounter + 1] = v7;
                    mapVertices[vCounter + 2] = v3;
                    mapVertices[vCounter + 3] = v3;
                    mapVertices[vCounter + 4] = v7;
                    mapVertices[vCounter + 5] = v8;
                    vCounter += 6;

                    mapNormals[nCounter] = n6;
                    mapNormals[nCounter + 1] = n6;
                    mapNormals[nCounter + 2] = n6;
                    mapNormals[nCounter + 3] = n6;
                    mapNormals[nCounter + 4] = n6;
                    mapNormals[nCounter + 5] = n6;
                    nCounter += 6;

                    mapTexcoords[tcCounter] = .{ .x = frontTexUV.x, .y = frontTexUV.y };
                    mapTexcoords[tcCounter + 1] = .{ .x = frontTexUV.x, .y = frontTexUV.y + frontTexUV.height };
                    mapTexcoords[tcCounter + 2] = .{ .x = frontTexUV.x + frontTexUV.width, .y = frontTexUV.y };
                    mapTexcoords[tcCounter + 3] = .{ .x = frontTexUV.x + frontTexUV.width, .y = frontTexUV.y };
                    mapTexcoords[tcCounter + 4] = .{ .x = frontTexUV.x, .y = frontTexUV.y + frontTexUV.height };
                    mapTexcoords[tcCounter + 5] = .{ .x = frontTexUV.x + frontTexUV.width, .y = frontTexUV.y + frontTexUV.height };
                    tcCounter += 6;
                }

                if (((z > 0) and colorEqual(pixels[@intCast((z - 1) * cubicmap.width + x)], BLACK)) or (z == 0)) {
                    // Back
                    mapVertices[vCounter] = v1;
                    mapVertices[vCounter + 1] = v5;
                    mapVertices[vCounter + 2] = v6;
                    mapVertices[vCounter + 3] = v1;
                    mapVertices[vCounter + 4] = v4;
                    mapVertices[vCounter + 5] = v5;
                    vCounter += 6;

                    mapNormals[nCounter] = n5;
                    mapNormals[nCounter + 1] = n5;
                    mapNormals[nCounter + 2] = n5;
                    mapNormals[nCounter + 3] = n5;
                    mapNormals[nCounter + 4] = n5;
                    mapNormals[nCounter + 5] = n5;
                    nCounter += 6;

                    mapTexcoords[tcCounter] = .{ .x = backTexUV.x + backTexUV.width, .y = backTexUV.y };
                    mapTexcoords[tcCounter + 1] = .{ .x = backTexUV.x, .y = backTexUV.y + backTexUV.height };
                    mapTexcoords[tcCounter + 2] = .{ .x = backTexUV.x + backTexUV.width, .y = backTexUV.y + backTexUV.height };
                    mapTexcoords[tcCounter + 3] = .{ .x = backTexUV.x + backTexUV.width, .y = backTexUV.y };
                    mapTexcoords[tcCounter + 4] = .{ .x = backTexUV.x, .y = backTexUV.y };
                    mapTexcoords[tcCounter + 5] = .{ .x = backTexUV.x, .y = backTexUV.y + backTexUV.height };
                    tcCounter += 6;
                }

                if (((x < cubicmap.width - 1) and colorEqual(pixels[@intCast(z * cubicmap.width + (x + 1))], BLACK)) or (x == cubicmap.width - 1)) {
                    // Right
                    mapVertices[vCounter] = v3;
                    mapVertices[vCounter + 1] = v8;
                    mapVertices[vCounter + 2] = v4;
                    mapVertices[vCounter + 3] = v4;
                    mapVertices[vCounter + 4] = v8;
                    mapVertices[vCounter + 5] = v5;
                    vCounter += 6;

                    mapNormals[nCounter] = n1;
                    mapNormals[nCounter + 1] = n1;
                    mapNormals[nCounter + 2] = n1;
                    mapNormals[nCounter + 3] = n1;
                    mapNormals[nCounter + 4] = n1;
                    mapNormals[nCounter + 5] = n1;
                    nCounter += 6;

                    mapTexcoords[tcCounter] = .{ .x = rightTexUV.x, .y = rightTexUV.y };
                    mapTexcoords[tcCounter + 1] = .{ .x = rightTexUV.x, .y = rightTexUV.y + rightTexUV.height };
                    mapTexcoords[tcCounter + 2] = .{ .x = rightTexUV.x + rightTexUV.width, .y = rightTexUV.y };
                    mapTexcoords[tcCounter + 3] = .{ .x = rightTexUV.x + rightTexUV.width, .y = rightTexUV.y };
                    mapTexcoords[tcCounter + 4] = .{ .x = rightTexUV.x, .y = rightTexUV.y + rightTexUV.height };
                    mapTexcoords[tcCounter + 5] = .{ .x = rightTexUV.x + rightTexUV.width, .y = rightTexUV.y + rightTexUV.height };
                    tcCounter += 6;
                }

                if (((x > 0) and colorEqual(pixels[@intCast(z * cubicmap.width + (x - 1))], BLACK)) or (x == 0)) {
                    // Left
                    mapVertices[vCounter] = v1;
                    mapVertices[vCounter + 1] = v7;
                    mapVertices[vCounter + 2] = v2;
                    mapVertices[vCounter + 3] = v1;
                    mapVertices[vCounter + 4] = v6;
                    mapVertices[vCounter + 5] = v7;
                    vCounter += 6;

                    mapNormals[nCounter] = n2;
                    mapNormals[nCounter + 1] = n2;
                    mapNormals[nCounter + 2] = n2;
                    mapNormals[nCounter + 3] = n2;
                    mapNormals[nCounter + 4] = n2;
                    mapNormals[nCounter + 5] = n2;
                    nCounter += 6;

                    mapTexcoords[tcCounter] = .{ .x = leftTexUV.x, .y = leftTexUV.y };
                    mapTexcoords[tcCounter + 1] = .{ .x = leftTexUV.x + leftTexUV.width, .y = leftTexUV.y + leftTexUV.height };
                    mapTexcoords[tcCounter + 2] = .{ .x = leftTexUV.x + leftTexUV.width, .y = leftTexUV.y };
                    mapTexcoords[tcCounter + 3] = .{ .x = leftTexUV.x, .y = leftTexUV.y };
                    mapTexcoords[tcCounter + 4] = .{ .x = leftTexUV.x, .y = leftTexUV.y + leftTexUV.height };
                    mapTexcoords[tcCounter + 5] = .{ .x = leftTexUV.x + leftTexUV.width, .y = leftTexUV.y + leftTexUV.height };
                    tcCounter += 6;
                }
            } else if (colorEqual(pix, BLACK)) {
                // Top
                mapVertices[vCounter] = v1;
                mapVertices[vCounter + 1] = v3;
                mapVertices[vCounter + 2] = v2;
                mapVertices[vCounter + 3] = v1;
                mapVertices[vCounter + 4] = v4;
                mapVertices[vCounter + 5] = v3;
                vCounter += 6;

                mapNormals[nCounter] = n4;
                mapNormals[nCounter + 1] = n4;
                mapNormals[nCounter + 2] = n4;
                mapNormals[nCounter + 3] = n4;
                mapNormals[nCounter + 4] = n4;
                mapNormals[nCounter + 5] = n4;
                nCounter += 6;

                mapTexcoords[tcCounter] = .{ .x = topTexUV.x, .y = topTexUV.y };
                mapTexcoords[tcCounter + 1] = .{ .x = topTexUV.x + topTexUV.width, .y = topTexUV.y + topTexUV.height };
                mapTexcoords[tcCounter + 2] = .{ .x = topTexUV.x, .y = topTexUV.y + topTexUV.height };
                mapTexcoords[tcCounter + 3] = .{ .x = topTexUV.x, .y = topTexUV.y };
                mapTexcoords[tcCounter + 4] = .{ .x = topTexUV.x + topTexUV.width, .y = topTexUV.y };
                mapTexcoords[tcCounter + 5] = .{ .x = topTexUV.x + topTexUV.width, .y = topTexUV.y + topTexUV.height };
                tcCounter += 6;

                // Bottom
                mapVertices[vCounter] = v6;
                mapVertices[vCounter + 1] = v7;
                mapVertices[vCounter + 2] = v8;
                mapVertices[vCounter + 3] = v6;
                mapVertices[vCounter + 4] = v8;
                mapVertices[vCounter + 5] = v5;
                vCounter += 6;

                mapNormals[nCounter] = n3;
                mapNormals[nCounter + 1] = n3;
                mapNormals[nCounter + 2] = n3;
                mapNormals[nCounter + 3] = n3;
                mapNormals[nCounter + 4] = n3;
                mapNormals[nCounter + 5] = n3;
                nCounter += 6;

                mapTexcoords[tcCounter] = .{ .x = bottomTexUV.x + bottomTexUV.width, .y = bottomTexUV.y };
                mapTexcoords[tcCounter + 1] = .{ .x = bottomTexUV.x + bottomTexUV.width, .y = bottomTexUV.y + bottomTexUV.height };
                mapTexcoords[tcCounter + 2] = .{ .x = bottomTexUV.x, .y = bottomTexUV.y + bottomTexUV.height };
                mapTexcoords[tcCounter + 3] = .{ .x = bottomTexUV.x + bottomTexUV.width, .y = bottomTexUV.y };
                mapTexcoords[tcCounter + 4] = .{ .x = bottomTexUV.x, .y = bottomTexUV.y + bottomTexUV.height };
                mapTexcoords[tcCounter + 5] = .{ .x = bottomTexUV.x, .y = bottomTexUV.y };
                tcCounter += 6;
            }
        }
    }

    mesh.vertexCount = @intCast(vCounter);
    mesh.triangleCount = @intCast(vCounter / 3);

    mesh.vertices = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 3 * @sizeOf(f32)))));
    mesh.normals = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 3 * @sizeOf(f32)))));
    mesh.texcoords = @ptrCast(@alignCast(RL_MALLOC(@intCast(mesh.vertexCount * 2 * @sizeOf(f32)))));
    mesh.colors = null;

    var fCounter: usize = 0;

    var i: usize = 0;
    while (i < vCounter) : (i += 1) {
        mesh.vertices[fCounter] = mapVertices[i].x;
        mesh.vertices[fCounter + 1] = mapVertices[i].y;
        mesh.vertices[fCounter + 2] = mapVertices[i].z;
        fCounter += 3;
    }

    fCounter = 0;
    i = 0;
    while (i < nCounter) : (i += 1) {
        mesh.normals[fCounter] = mapNormals[i].x;
        mesh.normals[fCounter + 1] = mapNormals[i].y;
        mesh.normals[fCounter + 2] = mapNormals[i].z;
        fCounter += 3;
    }

    fCounter = 0;
    i = 0;
    while (i < tcCounter) : (i += 1) {
        mesh.texcoords[fCounter] = mapTexcoords[i].x;
        mesh.texcoords[fCounter + 1] = mapTexcoords[i].y;
        fCounter += 2;
    }

    RL_FREE(mapVertices);
    RL_FREE(mapNormals);
    RL_FREE(mapTexcoords);

    UnloadImageColors(pixels);

    UploadMesh(&mesh, false);

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

    DrawBillboardRec(camera, texture, rec, position, .{ .x = scale * fabsf(rec.width / rec.height), .y = scale }, tint);
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

    size.x = fabsf(box.max.x - box.min.x);
    size.y = fabsf(box.max.y - box.min.y);
    size.z = fabsf(box.max.z - box.min.z);

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
        const hitDistance = if (inside) vector + sqrtf(d) else vector - sqrtf(d);
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

/// C's `(int)` cast as x86-64 performs it: NaN and out-of-range values give
/// INT_MIN where Zig's @intFromFloat would trap (an axis-aligned ray makes
/// GetRayCollisionBox divide by zero, and its normal goes infinite)
fn cInt(v: f32) c_int {
    if (!(v >= -2147483648.0 and v < 2147483648.0)) return std.math.minInt(c_int);
    return @intFromFloat(v);
}

// Get collision info between ray and box
export fn GetRayCollisionBox(ray_in: Ray, box: BoundingBox) callconv(.c) RayCollision {
    var ray = ray_in;
    var collision = std.mem.zeroes(RayCollision);

    const insideBox = (ray.position.x > box.min.x) and (ray.position.x < box.max.x) and
        (ray.position.y > box.min.y) and (ray.position.y < box.max.y) and
        (ray.position.z > box.min.z) and (ray.position.z < box.max.z);

    if (insideBox) ray.direction = Vector3Negate(ray.direction);

    var t = std.mem.zeroes([11]f32);

    t[8] = 1.0 / ray.direction.x;
    t[9] = 1.0 / ray.direction.y;
    t[10] = 1.0 / ray.direction.z;

    t[0] = (box.min.x - ray.position.x) * t[8];
    t[1] = (box.max.x - ray.position.x) * t[8];
    t[2] = (box.min.y - ray.position.y) * t[9];
    t[3] = (box.max.y - ray.position.y) * t[9];
    t[4] = (box.min.z - ray.position.z) * t[10];
    t[5] = (box.max.z - ray.position.z) * t[10];
    t[6] = @floatCast(fmax(fmax(fmin(t[0], t[1]), fmin(t[2], t[3])), fmin(t[4], t[5])));
    t[7] = @floatCast(fmin(fmin(fmax(t[0], t[1]), fmax(t[2], t[3])), fmax(t[4], t[5])));

    collision.hit = !((t[7] < 0) or (t[6] > t[7]));
    collision.distance = t[6];
    collision.point = Vector3Add(ray.position, Vector3Scale(ray.direction, collision.distance));

    collision.normal = Vector3Lerp(box.min, box.max, 0.5);
    collision.normal = Vector3Subtract(collision.point, collision.normal);
    collision.normal = Vector3Scale(collision.normal, 2.01);
    collision.normal = Vector3Divide(collision.normal, Vector3Subtract(box.max, box.min));
    collision.normal.x = @floatFromInt(cInt(collision.normal.x));
    collision.normal.y = @floatFromInt(cInt(collision.normal.y));
    collision.normal.z = @floatFromInt(cInt(collision.normal.z));

    collision.normal = Vector3Normalize(collision.normal);

    if (insideBox) {
        ray.direction = Vector3Negate(ray.direction);
        collision.distance *= -1.0;
        collision.normal = Vector3Negate(collision.normal);
    }

    return collision;
}

// Get collision info between ray and mesh
export fn GetRayCollisionMesh(ray: Ray, mesh: Mesh, transform: Matrix) callconv(.c) RayCollision {
    var collision = std.mem.zeroes(RayCollision);

    if (mesh.vertices != null) {
        const triangleCount = mesh.triangleCount;

        var i: c_int = 0;
        while (i < triangleCount) : (i += 1) {
            var a = std.mem.zeroes(Vector3);
            var b = std.mem.zeroes(Vector3);
            var c = std.mem.zeroes(Vector3);
            const vertdata: [*c]Vector3 = @ptrCast(@alignCast(mesh.vertices));

            if (mesh.indices != null) {
                a = vertdata[mesh.indices[@intCast(i * 3 + 0)]];
                b = vertdata[mesh.indices[@intCast(i * 3 + 1)]];
                c = vertdata[mesh.indices[@intCast(i * 3 + 2)]];
            } else {
                a = vertdata[@intCast(i * 3 + 0)];
                b = vertdata[@intCast(i * 3 + 1)];
                c = vertdata[@intCast(i * 3 + 2)];
            }

            a = Vector3Transform(a, transform);
            b = Vector3Transform(b, transform);
            c = Vector3Transform(c, transform);

            const triHitInfo = GetRayCollisionTriangle(ray, a, b, c);

            if (triHitInfo.hit) {
                if ((!collision.hit) or (collision.distance > triHitInfo.distance)) collision = triHitInfo;
            }
        }
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
fn BuildPoseFromParentJoints(bones: [*c]BoneInfo, boneCount: c_int, transforms: [*c]Transform) void {
    var i: c_int = 0;
    while (i < boneCount) : (i += 1) {
        const ui: usize = @intCast(i);
        if (bones[ui].parent >= 0) {
            if (bones[ui].parent > i) {
                TraceLog(LOG_WARNING, "Skipping bone not topologically sorted: Bone %d has parent %d", i, bones[ui].parent);
                continue;
            }
            const pp: usize = @intCast(bones[ui].parent);
            transforms[ui].rotation = QuaternionMultiply(transforms[pp].rotation, transforms[ui].rotation);
            transforms[ui].scale = Vector3Multiply(transforms[ui].scale, transforms[pp].scale);
            transforms[ui].translation = Vector3Multiply(transforms[ui].translation, transforms[pp].scale);
            transforms[ui].translation = Vector3RotateByQuaternion(transforms[ui].translation, transforms[pp].rotation);
            transforms[ui].translation = Vector3Add(transforms[ui].translation, transforms[pp].translation);
        }
    }
}

// Load OBJ mesh data
fn LoadOBJ(fileName: [*c]const u8) Model {
    var objAttributes = std.mem.zeroes(tinyobj_attrib_t);
    var objShapes: [*c]tinyobj_shape_t = null;
    var objShapeCount: c_uint = 0;

    var objMaterials: [*c]tinyobj_material_t = null;
    var objMaterialCount: c_uint = 0;

    var model = std.mem.zeroes(Model);
    model.transform = MatrixIdentity();

    const fileText = LoadFileText(fileName);

    if (fileText == null) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Unable to read obj file", fileName);
        return model;
    }

    var currentDir = std.mem.zeroes([MAX_FILEPATH_LENGTH]u8);
    _ = strncpy(&currentDir, GetWorkingDirectory(), MAX_FILEPATH_LENGTH - 1);
    const workingDir = GetDirectoryPath(fileName);
    if (chdir(workingDir) != 0) TraceLog(LOG_WARNING, "MODEL: [%s] Failed to change working directory", workingDir);

    const dataSize: c_uint = @intCast(strlen(fileText));

    const flags = TINYOBJ_FLAG_TRIANGULATE;
    const ret = tinyobj_parse_obj(&objAttributes, &objShapes, &objShapeCount, &objMaterials, &objMaterialCount, fileText, dataSize, flags);

    if (ret != TINYOBJ_SUCCESS) {
        TraceLog(LOG_WARNING, "MODEL: Unable to read obj data %s", fileName);
        return model;
    }

    UnloadFileText(fileText);

    var faceVertIndex: c_uint = 0;
    var nextShape: c_uint = 1;
    var lastMaterial: c_int = -1;
    var meshIndex: c_uint = 0;

    var nextShapeEnd: c_uint = objAttributes.num_face_num_verts;

    if (objShapeCount > 1) nextShapeEnd = objShapes[nextShape].face_offset;

    var faceId: c_uint = 0;
    while (faceId < objAttributes.num_faces) : (faceId += 1) {
        if (faceId >= nextShapeEnd) {
            nextShape += 1;
            if (nextShape < objShapeCount) nextShapeEnd = objShapes[nextShape].face_offset else nextShapeEnd = objAttributes.num_face_num_verts;
            meshIndex += 1;
        } else if ((lastMaterial != -1) and (objAttributes.material_ids[faceId] != lastMaterial)) {
            meshIndex += 1;
        }

        lastMaterial = objAttributes.material_ids[faceId];
        faceVertIndex += @intCast(objAttributes.face_num_verts[faceId]);
    }

    model.meshCount = @intCast(meshIndex + 1);
    model.meshes = @ptrCast(@alignCast(MemAlloc(@intCast(@sizeOf(Mesh) * @as(usize, @intCast(model.meshCount))))));

    if (objMaterialCount > 0) {
        model.materialCount = @intCast(objMaterialCount);
        model.materials = @ptrCast(@alignCast(MemAlloc(@intCast(@sizeOf(Material) * objMaterialCount))));
    } else {
        model.materialCount = 1;
        model.materials = @ptrCast(@alignCast(MemAlloc(@sizeOf(Material) * 1)));
    }

    model.meshMaterial = @ptrCast(@alignCast(MemAlloc(@intCast(@sizeOf(c_int) * @as(usize, @intCast(model.meshCount))))));

    var localMeshVertexCounts: [*c]c_uint = @ptrCast(@alignCast(MemAlloc(@intCast(@sizeOf(c_uint) * @as(usize, @intCast(model.meshCount))))));

    faceVertIndex = 0;
    nextShapeEnd = objAttributes.num_face_num_verts;
    lastMaterial = -1;
    meshIndex = 0;
    var localMeshVertexCount: c_uint = 0;

    nextShape = 1;
    if (objShapeCount > 1) nextShapeEnd = objShapes[nextShape].face_offset;

    faceId = 0;
    while (faceId < objAttributes.num_faces) : (faceId += 1) {
        var newMesh = false;
        if (faceId >= nextShapeEnd) {
            nextShape += 1;
            if (nextShape < objShapeCount) nextShapeEnd = objShapes[nextShape].face_offset else nextShapeEnd = objAttributes.num_face_num_verts;
            newMesh = true;
        } else if ((lastMaterial != -1) and (objAttributes.material_ids[faceId] != lastMaterial)) {
            newMesh = true;
        }

        lastMaterial = objAttributes.material_ids[faceId];

        if (newMesh) {
            localMeshVertexCounts[meshIndex] = localMeshVertexCount;
            localMeshVertexCount = 0;
            meshIndex += 1;
        }

        faceVertIndex += @intCast(objAttributes.face_num_verts[faceId]);
        localMeshVertexCount += @intCast(objAttributes.face_num_verts[faceId]);
    }

    localMeshVertexCounts[meshIndex] = localMeshVertexCount;

    {
        var i: c_int = 0;
        while (i < model.meshCount) : (i += 1) {
            const ui: usize = @intCast(i);
            const vertexCount = localMeshVertexCounts[ui];

            model.meshes[ui].vertexCount = @intCast(vertexCount);
            model.meshes[ui].triangleCount = @intCast(vertexCount / 3);

            model.meshes[ui].vertices = @ptrCast(@alignCast(MemAlloc(@intCast(@sizeOf(f32) * vertexCount * 3))));
            model.meshes[ui].normals = @ptrCast(@alignCast(MemAlloc(@intCast(@sizeOf(f32) * vertexCount * 3))));
            model.meshes[ui].texcoords = @ptrCast(@alignCast(MemAlloc(@intCast(@sizeOf(f32) * vertexCount * 2))));
            model.meshes[ui].colors = @ptrCast(@alignCast(MemAlloc(@intCast(@sizeOf(u8) * vertexCount * 4))));
        }
    }

    MemFree(localMeshVertexCounts);
    localMeshVertexCounts = null;

    faceVertIndex = 0;
    nextShapeEnd = objAttributes.num_face_num_verts;
    nextShape = 1;
    if (objShapeCount > 1) nextShapeEnd = objShapes[nextShape].face_offset;
    lastMaterial = -1;
    meshIndex = 0;
    localMeshVertexCount = 0;

    faceId = 0;
    while (faceId < objAttributes.num_faces) : (faceId += 1) {
        var newMesh = false;
        if (faceId >= nextShapeEnd) {
            nextShape += 1;
            if (nextShape < objShapeCount) nextShapeEnd = objShapes[nextShape].face_offset else nextShapeEnd = objAttributes.num_face_num_verts;
            newMesh = true;
        }

        if ((lastMaterial != -1) and (objAttributes.material_ids[faceId] != lastMaterial)) newMesh = true;
        lastMaterial = objAttributes.material_ids[faceId];

        if (newMesh) {
            localMeshVertexCount = 0;
            meshIndex += 1;
        }

        var matId: c_int = 0;
        if ((lastMaterial >= 0) and (lastMaterial < @as(c_int, @intCast(objMaterialCount)))) matId = lastMaterial;

        model.meshMaterial[meshIndex] = matId;

        var f: c_int = 0;
        while (f < objAttributes.face_num_verts[faceId]) : (f += 1) {
            const vertIndex = objAttributes.faces[faceVertIndex].v_idx;
            const normalIndex = objAttributes.faces[faceVertIndex].vn_idx;
            const texcordIndex = objAttributes.faces[faceVertIndex].vt_idx;

            const mi: usize = @intCast(meshIndex);
            const lc: usize = @intCast(localMeshVertexCount);

            // NOTE: Out-of-range indices from malformed files are skipped, keeping zeroed values
            var i: usize = 0;
            if ((vertIndex >= 0) and (vertIndex < @as(c_int, @bitCast(objAttributes.num_vertices)))) {
                while (i < 3) : (i += 1) model.meshes[mi].vertices[lc * 3 + i] = objAttributes.vertices[@as(usize, @intCast(vertIndex)) * 3 + i];
            }

            if ((objAttributes.texcoords != null) and (texcordIndex != TINYOBJ_INVALID_INDEX) and (texcordIndex >= 0) and (texcordIndex < @as(c_int, @bitCast(objAttributes.num_texcoords))) and (model.meshes[mi].texcoords != null)) {
                i = 0;
                while (i < 2) : (i += 1) model.meshes[mi].texcoords[lc * 2 + i] = objAttributes.texcoords[@as(usize, @intCast(texcordIndex)) * 2 + i];
                model.meshes[mi].texcoords[lc * 2 + 1] = 1.0 - model.meshes[mi].texcoords[lc * 2 + 1];
            }

            if ((objAttributes.normals != null) and (normalIndex != TINYOBJ_INVALID_INDEX) and (normalIndex >= 0) and (normalIndex < @as(c_int, @bitCast(objAttributes.num_normals)))) {
                i = 0;
                while (i < 3) : (i += 1) model.meshes[mi].normals[lc * 3 + i] = objAttributes.normals[@as(usize, @intCast(normalIndex)) * 3 + i];
            } else {
                model.meshes[mi].normals[lc * 3 + 0] = 0.0;
                model.meshes[mi].normals[lc * 3 + 1] = 1.0;
                model.meshes[mi].normals[lc * 3 + 2] = 0.0;
            }

            i = 0;
            while (i < 4) : (i += 1) model.meshes[mi].colors[lc * 4 + i] = 255;
            faceVertIndex += 1;
            localMeshVertexCount += 1;
        }
    }

    if (objMaterialCount > 0) ProcessMaterialsOBJ(model.materials, objMaterials, @intCast(objMaterialCount)) else model.materials[0] = LoadMaterialDefault();

    tinyobj_attrib_free(&objAttributes);
    tinyobj_shapes_free(objShapes, objShapeCount);
    tinyobj_materials_free(objMaterials, objMaterialCount);

    if (chdir(&currentDir) != 0) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to change working directory", &currentDir);
    }

    return model;
}

// IQM file structs (read via memcpy from file data)
const IQMHeader = extern struct {
    magic: [16]u8,
    version: c_uint,
    dataSize: c_uint,
    flags: c_uint,
    num_text: c_uint,
    ofs_text: c_uint,
    num_meshes: c_uint,
    ofs_meshes: c_uint,
    num_vertexarrays: c_uint,
    num_vertexes: c_uint,
    ofs_vertexarrays: c_uint,
    num_triangles: c_uint,
    ofs_triangles: c_uint,
    ofs_adjacency: c_uint,
    num_joints: c_uint,
    ofs_joints: c_uint,
    num_poses: c_uint,
    ofs_poses: c_uint,
    num_anims: c_uint,
    ofs_anims: c_uint,
    num_frames: c_uint,
    num_framechannels: c_uint,
    ofs_frames: c_uint,
    ofs_bounds: c_uint,
    num_comment: c_uint,
    ofs_comment: c_uint,
    num_extensions: c_uint,
    ofs_extensions: c_uint,
};
const IQMMesh = extern struct {
    name: c_uint,
    material: c_uint,
    first_vertex: c_uint,
    num_vertexes: c_uint,
    first_triangle: c_uint,
    num_triangles: c_uint,
};
const IQMTriangle = extern struct { vertex: [3]c_uint };
const IQMJoint = extern struct {
    name: c_uint,
    parent: c_int,
    translate: [3]f32,
    rotate: [4]f32,
    scale: [3]f32,
};
const IQMVertexArray = extern struct {
    type: c_uint,
    flags: c_uint,
    format: c_uint,
    size: c_uint,
    offset: c_uint,
};
const IQMPose = extern struct {
    parent: c_int,
    mask: c_uint,
    channeloffset: [10]f32,
    channelscale: [10]f32,
};
const IQMAnim = extern struct {
    name: c_uint,
    first_frame: c_uint,
    num_frames: c_uint,
    framerate: f32,
    flags: c_uint,
};

const IQM_MAGIC = "INTERQUAKEMODEL";
const IQM_VERSION: c_uint = 2;
const BONE_NAME_LENGTH: usize = 32;
const MESH_NAME_LENGTH: usize = 32;
const MATERIAL_NAME_LENGTH: usize = 32;

// IQM vertex data types
const IQM_POSITION: c_uint = 0;
const IQM_TEXCOORD: c_uint = 1;
const IQM_NORMAL: c_uint = 2;
const IQM_TANGENT: c_uint = 3;
const IQM_BLENDINDEXES: c_uint = 4;
const IQM_BLENDWEIGHTS: c_uint = 5;
const IQM_COLOR: c_uint = 6;

// Load IQM mesh data
fn LoadIQM(fileName: [*c]const u8) Model {
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);
    const fileDataPtr = fileData;

    var model = std.mem.zeroes(Model);

    var imesh: [*c]IQMMesh = null;
    var tri: [*c]IQMTriangle = null;
    var va: [*c]IQMVertexArray = null;
    var ijoint: [*c]IQMJoint = null;

    var vertex: [*c]f32 = null;
    var normal: [*c]f32 = null;
    var text: [*c]f32 = null;
    var blendi: [*c]u8 = null;
    var blendw: [*c]u8 = null;
    var color: [*c]u8 = null;

    if (fileDataPtr == null) return model;

    const basePath = GetDirectoryPath(fileName);

    const iqmHeader: *IQMHeader = @ptrCast(@alignCast(fileDataPtr));

    if (memcmp(&iqmHeader.magic, IQM_MAGIC, IQM_MAGIC.len + 1) != 0) {
        TraceLog(LOG_WARNING, "MODEL: [%s] IQM file is not a valid model", fileName);
        UnloadFileData(fileData);
        return model;
    }

    if (iqmHeader.version != IQM_VERSION) {
        TraceLog(LOG_WARNING, "MODEL: [%s] IQM file version not supported (%i)", fileName, iqmHeader.version);
        UnloadFileData(fileData);
        return model;
    }

    imesh = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_meshes * @sizeOf(IQMMesh))));
    _ = memcpy(imesh, fileDataPtr + iqmHeader.ofs_meshes, iqmHeader.num_meshes * @sizeOf(IQMMesh));

    model.meshCount = @intCast(iqmHeader.num_meshes);
    model.meshes = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(Mesh))));

    model.materialCount = model.meshCount;
    model.materials = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.materialCount), @sizeOf(Material))));
    model.meshMaterial = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(c_int))));

    var name = std.mem.zeroes([MESH_NAME_LENGTH]u8);
    var material = std.mem.zeroes([MATERIAL_NAME_LENGTH]u8);

    {
        var i: c_int = 0;
        while (i < model.meshCount) : (i += 1) {
            const ui: usize = @intCast(i);
            _ = memcpy(&name, fileDataPtr + iqmHeader.ofs_text + imesh[ui].name, MESH_NAME_LENGTH);
            _ = memcpy(&material, fileDataPtr + iqmHeader.ofs_text + imesh[ui].material, MATERIAL_NAME_LENGTH);

            model.materials[ui] = LoadMaterialDefault();
            if (TextLength(&material) > 0) model.materials[ui].maps[MATERIAL_MAP_ALBEDO].texture = LoadTexture(TextFormat("%s/%s", basePath, &material));

            model.meshMaterial[ui] = i;

            TraceLog(LOG_DEBUG, "MODEL: [%s] mesh name (%s), material (%s)", fileName, &name, &material);

            model.meshes[ui].vertexCount = @intCast(imesh[ui].num_vertexes);

            model.meshes[ui].vertices = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[ui].vertexCount * 3), @sizeOf(f32))));
            model.meshes[ui].normals = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[ui].vertexCount * 3), @sizeOf(f32))));
            model.meshes[ui].texcoords = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[ui].vertexCount * 2), @sizeOf(f32))));

            model.meshes[ui].boneIndices = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[ui].vertexCount * 4), @sizeOf(u8))));
            model.meshes[ui].boneWeights = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[ui].vertexCount * 4), @sizeOf(f32))));

            model.meshes[ui].triangleCount = @intCast(imesh[ui].num_triangles);
            model.meshes[ui].indices = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[ui].triangleCount * 3), @sizeOf(c_ushort))));
        }
    }

    tri = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_triangles * @sizeOf(IQMTriangle))));
    _ = memcpy(tri, fileDataPtr + iqmHeader.ofs_triangles, iqmHeader.num_triangles * @sizeOf(IQMTriangle));

    {
        var m: c_int = 0;
        while (m < model.meshCount) : (m += 1) {
            const um: usize = @intCast(m);
            var tcounter: usize = 0;
            var i: c_uint = imesh[um].first_triangle;
            while (i < (imesh[um].first_triangle + imesh[um].num_triangles)) : (i += 1) {
                model.meshes[um].indices[tcounter + 2] = @intCast(tri[i].vertex[0] - imesh[um].first_vertex);
                model.meshes[um].indices[tcounter + 1] = @intCast(tri[i].vertex[1] - imesh[um].first_vertex);
                model.meshes[um].indices[tcounter] = @intCast(tri[i].vertex[2] - imesh[um].first_vertex);
                tcounter += 3;
            }
        }
    }

    va = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_vertexarrays * @sizeOf(IQMVertexArray))));
    _ = memcpy(va, fileDataPtr + iqmHeader.ofs_vertexarrays, iqmHeader.num_vertexarrays * @sizeOf(IQMVertexArray));

    {
        var i: c_uint = 0;
        while (i < iqmHeader.num_vertexarrays) : (i += 1) {
            switch (va[i].type) {
                IQM_POSITION => {
                    vertex = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_vertexes * 3 * @sizeOf(f32))));
                    _ = memcpy(vertex, fileDataPtr + va[i].offset, iqmHeader.num_vertexes * 3 * @sizeOf(f32));

                    var m: c_uint = 0;
                    while (m < iqmHeader.num_meshes) : (m += 1) {
                        var vCounter: usize = 0;
                        var ii: c_uint = imesh[m].first_vertex * 3;
                        while (ii < (imesh[m].first_vertex + imesh[m].num_vertexes) * 3) : (ii += 1) {
                            model.meshes[m].vertices[vCounter] = vertex[ii];
                            if (model.meshes[m].animVertices != null) model.meshes[m].animVertices[vCounter] = vertex[ii];
                            vCounter += 1;
                        }
                    }
                },
                IQM_NORMAL => {
                    normal = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_vertexes * 3 * @sizeOf(f32))));
                    _ = memcpy(normal, fileDataPtr + va[i].offset, iqmHeader.num_vertexes * 3 * @sizeOf(f32));

                    var m: c_uint = 0;
                    while (m < iqmHeader.num_meshes) : (m += 1) {
                        var vCounter: usize = 0;
                        var ii: c_uint = imesh[m].first_vertex * 3;
                        while (ii < (imesh[m].first_vertex + imesh[m].num_vertexes) * 3) : (ii += 1) {
                            model.meshes[m].normals[vCounter] = normal[ii];
                            if (model.meshes[m].animNormals != null) model.meshes[m].animNormals[vCounter] = normal[ii];
                            vCounter += 1;
                        }
                    }
                },
                IQM_TEXCOORD => {
                    text = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_vertexes * 2 * @sizeOf(f32))));
                    _ = memcpy(text, fileDataPtr + va[i].offset, iqmHeader.num_vertexes * 2 * @sizeOf(f32));

                    var m: c_uint = 0;
                    while (m < iqmHeader.num_meshes) : (m += 1) {
                        var vCounter: usize = 0;
                        var ii: c_uint = imesh[m].first_vertex * 2;
                        while (ii < (imesh[m].first_vertex + imesh[m].num_vertexes) * 2) : (ii += 1) {
                            model.meshes[m].texcoords[vCounter] = text[ii];
                            vCounter += 1;
                        }
                    }
                },
                IQM_BLENDINDEXES => {
                    blendi = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_vertexes * 4 * @sizeOf(u8))));
                    _ = memcpy(blendi, fileDataPtr + va[i].offset, iqmHeader.num_vertexes * 4 * @sizeOf(u8));

                    var m: c_uint = 0;
                    while (m < iqmHeader.num_meshes) : (m += 1) {
                        var boneCounter: usize = 0;
                        var ii: c_uint = imesh[m].first_vertex * 4;
                        while (ii < (imesh[m].first_vertex + imesh[m].num_vertexes) * 4) : (ii += 1) {
                            model.meshes[m].boneIndices[boneCounter] = blendi[ii];
                            boneCounter += 1;
                        }
                    }
                },
                IQM_BLENDWEIGHTS => {
                    blendw = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_vertexes * 4 * @sizeOf(u8))));
                    _ = memcpy(blendw, fileDataPtr + va[i].offset, iqmHeader.num_vertexes * 4 * @sizeOf(u8));

                    var m: c_uint = 0;
                    while (m < iqmHeader.num_meshes) : (m += 1) {
                        var boneCounter: usize = 0;
                        var ii: c_uint = imesh[m].first_vertex * 4;
                        while (ii < (imesh[m].first_vertex + imesh[m].num_vertexes) * 4) : (ii += 1) {
                            model.meshes[m].boneWeights[boneCounter] = @as(f32, @floatFromInt(blendw[ii])) / 255.0;
                            boneCounter += 1;
                        }
                    }
                },
                IQM_COLOR => {
                    color = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_vertexes * 4 * @sizeOf(u8))));
                    _ = memcpy(color, fileDataPtr + va[i].offset, iqmHeader.num_vertexes * 4 * @sizeOf(u8));

                    var m: c_uint = 0;
                    while (m < iqmHeader.num_meshes) : (m += 1) {
                        model.meshes[m].colors = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[m].vertexCount * 4), @sizeOf(u8))));

                        var vCounter: usize = 0;
                        var ii: c_uint = imesh[m].first_vertex * 4;
                        while (ii < (imesh[m].first_vertex + imesh[m].num_vertexes) * 4) : (ii += 1) {
                            model.meshes[m].colors[vCounter] = color[ii];
                            vCounter += 1;
                        }
                    }
                },
                else => {},
            }
        }
    }

    ijoint = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_joints * @sizeOf(IQMJoint))));
    _ = memcpy(ijoint, fileDataPtr + iqmHeader.ofs_joints, iqmHeader.num_joints * @sizeOf(IQMJoint));

    model.skeleton.boneCount = @intCast(iqmHeader.num_joints);
    model.skeleton.bones = @ptrCast(@alignCast(RL_CALLOC(iqmHeader.num_joints, @sizeOf(BoneInfo))));
    model.skeleton.bindPose = @ptrCast(@alignCast(RL_CALLOC(iqmHeader.num_joints, @sizeOf(Transform))));

    {
        var i: c_uint = 0;
        while (i < iqmHeader.num_joints) : (i += 1) {
            model.skeleton.bones[i].parent = ijoint[i].parent;
            _ = memcpy(&model.skeleton.bones[i].name, fileDataPtr + iqmHeader.ofs_text + ijoint[i].name, BONE_NAME_LENGTH);

            model.skeleton.bindPose[i].translation.x = ijoint[i].translate[0];
            model.skeleton.bindPose[i].translation.y = ijoint[i].translate[1];
            model.skeleton.bindPose[i].translation.z = ijoint[i].translate[2];

            model.skeleton.bindPose[i].rotation.x = ijoint[i].rotate[0];
            model.skeleton.bindPose[i].rotation.y = ijoint[i].rotate[1];
            model.skeleton.bindPose[i].rotation.z = ijoint[i].rotate[2];
            model.skeleton.bindPose[i].rotation.w = ijoint[i].rotate[3];

            model.skeleton.bindPose[i].scale.x = ijoint[i].scale[0];
            model.skeleton.bindPose[i].scale.y = ijoint[i].scale[1];
            model.skeleton.bindPose[i].scale.z = ijoint[i].scale[2];
        }
    }

    BuildPoseFromParentJoints(model.skeleton.bones, @bitCast(model.skeleton.boneCount), model.skeleton.bindPose);

    model.currentPose = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.skeleton.boneCount), @sizeOf(Transform))));
    model.boneMatrices = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.skeleton.boneCount), @sizeOf(Matrix))));
    {
        var j: c_int = 0;
        while (j < model.skeleton.boneCount) : (j += 1) model.boneMatrices[@intCast(j)] = MatrixIdentity();
    }

    UnloadFileData(fileData);

    RL_FREE(imesh);
    RL_FREE(tri);
    RL_FREE(va);
    RL_FREE(vertex);
    RL_FREE(normal);
    RL_FREE(text);
    RL_FREE(blendi);
    RL_FREE(blendw);
    RL_FREE(ijoint);
    RL_FREE(color);

    return model;
}

// Load IQM animation data
fn LoadModelAnimationsIQM(fileName: [*c]const u8, animCount: [*c]c_int) [*c]ModelAnimation {
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);
    const fileDataPtr = fileData;

    if (fileDataPtr == null) return null;

    const iqmHeader: *IQMHeader = @ptrCast(@alignCast(fileDataPtr));

    if (memcmp(&iqmHeader.magic, IQM_MAGIC, IQM_MAGIC.len + 1) != 0) {
        TraceLog(LOG_WARNING, "MODEL: [%s] IQM file is not a valid model", fileName);
        UnloadFileData(fileData);
        return null;
    }

    if (iqmHeader.version != IQM_VERSION) {
        TraceLog(LOG_WARNING, "MODEL: [%s] IQM file version not supported (%i)", fileName, iqmHeader.version);
        UnloadFileData(fileData);
        return null;
    }

    const poses: [*c]IQMPose = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_poses * @sizeOf(IQMPose))));
    _ = memcpy(poses, fileDataPtr + iqmHeader.ofs_poses, iqmHeader.num_poses * @sizeOf(IQMPose));

    animCount.* = @intCast(iqmHeader.num_anims);
    const anim: [*c]IQMAnim = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_anims * @sizeOf(IQMAnim))));
    _ = memcpy(anim, fileDataPtr + iqmHeader.ofs_anims, iqmHeader.num_anims * @sizeOf(IQMAnim));

    const animations: [*c]ModelAnimation = @ptrCast(@alignCast(RL_CALLOC(iqmHeader.num_anims, @sizeOf(ModelAnimation))));

    const framedata: [*c]c_ushort = @ptrCast(@alignCast(RL_CALLOC(iqmHeader.num_frames * iqmHeader.num_framechannels, @sizeOf(c_ushort))));
    _ = memcpy(framedata, fileDataPtr + iqmHeader.ofs_frames, iqmHeader.num_frames * iqmHeader.num_framechannels * @sizeOf(c_ushort));

    const joints: [*c]IQMJoint = @ptrCast(@alignCast(RL_CALLOC(iqmHeader.num_joints, @sizeOf(IQMJoint))));
    _ = memcpy(joints, fileDataPtr + iqmHeader.ofs_joints, iqmHeader.num_joints * @sizeOf(IQMJoint));

    var a: c_uint = 0;
    while (a < iqmHeader.num_anims) : (a += 1) {
        animations[a].boneCount = @intCast(iqmHeader.num_poses);
        const bones: [*c]BoneInfo = @ptrCast(@alignCast(RL_CALLOC(iqmHeader.num_poses, @sizeOf(BoneInfo))));

        animations[a].keyframeCount = @intCast(anim[a].num_frames);
        animations[a].keyframePoses = @ptrCast(@alignCast(RL_CALLOC(anim[a].num_frames, @sizeOf(ModelAnimPose))));
        _ = memcpy(&animations[a].name, fileDataPtr + iqmHeader.ofs_text + anim[a].name, 32);

        TraceLog(LOG_INFO, "MODEL: [%s] Loaded animation: %s | Frames: %d | Framerate: %f", fileName, &animations[a].name, animations[a].keyframeCount, @as(f64, anim[a].framerate));

        var j: c_uint = 0;
        while (j < iqmHeader.num_poses) : (j += 1) {
            bones[j].parent = poses[j].parent;
        }

        j = 0;
        while (j < anim[a].num_frames) : (j += 1) {
            animations[a].keyframePoses[j] = @ptrCast(@alignCast(RL_MALLOC(iqmHeader.num_poses * @sizeOf(Transform))));
        }

        var dcounter: usize = @intCast(anim[a].first_frame * iqmHeader.num_framechannels);

        var frame: c_uint = 0;
        while (frame < anim[a].num_frames) : (frame += 1) {
            var i: c_uint = 0;
            while (i < iqmHeader.num_poses) : (i += 1) {
                const kp = &animations[a].keyframePoses[frame][i];
                kp.translation.x = poses[i].channeloffset[0];
                if (poses[i].mask & 0x01 != 0) {
                    kp.translation.x += @as(f32, @floatFromInt(framedata[dcounter])) * poses[i].channelscale[0];
                    dcounter += 1;
                }
                kp.translation.y = poses[i].channeloffset[1];
                if (poses[i].mask & 0x02 != 0) {
                    kp.translation.y += @as(f32, @floatFromInt(framedata[dcounter])) * poses[i].channelscale[1];
                    dcounter += 1;
                }
                kp.translation.z = poses[i].channeloffset[2];
                if (poses[i].mask & 0x04 != 0) {
                    kp.translation.z += @as(f32, @floatFromInt(framedata[dcounter])) * poses[i].channelscale[2];
                    dcounter += 1;
                }
                kp.rotation.x = poses[i].channeloffset[3];
                if (poses[i].mask & 0x08 != 0) {
                    kp.rotation.x += @as(f32, @floatFromInt(framedata[dcounter])) * poses[i].channelscale[3];
                    dcounter += 1;
                }
                kp.rotation.y = poses[i].channeloffset[4];
                if (poses[i].mask & 0x10 != 0) {
                    kp.rotation.y += @as(f32, @floatFromInt(framedata[dcounter])) * poses[i].channelscale[4];
                    dcounter += 1;
                }
                kp.rotation.z = poses[i].channeloffset[5];
                if (poses[i].mask & 0x20 != 0) {
                    kp.rotation.z += @as(f32, @floatFromInt(framedata[dcounter])) * poses[i].channelscale[5];
                    dcounter += 1;
                }
                kp.rotation.w = poses[i].channeloffset[6];
                if (poses[i].mask & 0x40 != 0) {
                    kp.rotation.w += @as(f32, @floatFromInt(framedata[dcounter])) * poses[i].channelscale[6];
                    dcounter += 1;
                }
                kp.scale.x = poses[i].channeloffset[7];
                if (poses[i].mask & 0x80 != 0) {
                    kp.scale.x += @as(f32, @floatFromInt(framedata[dcounter])) * poses[i].channelscale[7];
                    dcounter += 1;
                }
                kp.scale.y = poses[i].channeloffset[8];
                if (poses[i].mask & 0x100 != 0) {
                    kp.scale.y += @as(f32, @floatFromInt(framedata[dcounter])) * poses[i].channelscale[8];
                    dcounter += 1;
                }
                kp.scale.z = poses[i].channeloffset[9];
                if (poses[i].mask & 0x200 != 0) {
                    kp.scale.z += @as(f32, @floatFromInt(framedata[dcounter])) * poses[i].channelscale[9];
                    dcounter += 1;
                }

                kp.rotation = QuaternionNormalize(kp.rotation);
            }
        }

        frame = 0;
        while (frame < anim[a].num_frames) : (frame += 1) {
            var i: c_int = 0;
            while (i < animations[a].boneCount) : (i += 1) {
                const ui: usize = @intCast(i);
                if (bones[ui].parent >= 0) {
                    const pp: usize = @intCast(bones[ui].parent);
                    animations[a].keyframePoses[frame][ui].rotation = QuaternionMultiply(animations[a].keyframePoses[frame][pp].rotation, animations[a].keyframePoses[frame][ui].rotation);
                    animations[a].keyframePoses[frame][ui].translation = Vector3RotateByQuaternion(animations[a].keyframePoses[frame][ui].translation, animations[a].keyframePoses[frame][pp].rotation);
                    animations[a].keyframePoses[frame][ui].translation = Vector3Add(animations[a].keyframePoses[frame][ui].translation, animations[a].keyframePoses[frame][pp].translation);
                    animations[a].keyframePoses[frame][ui].scale = Vector3Multiply(animations[a].keyframePoses[frame][ui].scale, animations[a].keyframePoses[frame][pp].scale);
                }
            }
        }

        RL_FREE(bones);
    }

    UnloadFileData(fileData);

    RL_FREE(joints);
    RL_FREE(framedata);
    RL_FREE(poses);
    RL_FREE(anim);

    return animations;
}

//----------------------------------------------------------------------------------
// GLTF loader
//----------------------------------------------------------------------------------

// Load attribute helper: copies `numComp`-component elements from an accessor's buffer
// into dstPtr, converting from srcType to dstType (mirrors the LOAD_ATTRIBUTE macros).
fn loadAttribute(comptime SrcType: type, comptime DstType: type, accessor: *cgltf_accessor, numComp: usize, dstPtr: [*]DstType) void {
    const bufRaw: [*]u8 = @ptrCast(@alignCast(accessor.buffer_view.*.buffer.*.data));
    const byteOffset = accessor.buffer_view.*.offset + accessor.offset;
    const buffer: [*]const SrcType = @ptrCast(@alignCast(bufRaw + byteOffset));
    const strideElems = accessor.stride / @sizeOf(SrcType);

    var n: usize = 0;
    var k: usize = 0;
    while (k < accessor.count) : (k += 1) {
        var l: usize = 0;
        while (l < numComp) : (l += 1) {
            dstPtr[numComp * k + l] = castNum(SrcType, DstType, buffer[n + l]);
        }
        n += strideElems;
    }
}

inline fn castNum(comptime SrcType: type, comptime DstType: type, v: SrcType) DstType {
    if (DstType == f32) {
        return switch (@typeInfo(SrcType)) {
            .float => @floatCast(v),
            else => @floatFromInt(v),
        };
    } else {
        return switch (@typeInfo(SrcType)) {
            .float => @intFromFloat(v),
            else => @intCast(v),
        };
    }
}

// Load file data callback for cgltf
fn LoadFileGLTFCallback(memoryOptions: ?*const cgltf_memory_options, fileOptions: ?*const cgltf_file_options, path: [*c]const u8, size: [*c]cgltf_size, data: [*c]?*anyopaque) callconv(.c) cgltf_result {
    _ = memoryOptions;
    _ = fileOptions;
    var filesize: c_int = 0;
    const filedata = LoadFileData(path, &filesize);

    if (filedata == null) return cgltf_result_io_error;

    size.* = @intCast(filesize);
    data.* = filedata;

    return cgltf_result_success;
}

// Release file data callback for cgltf
fn ReleaseFileGLTFCallback(memoryOptions: ?*const cgltf_memory_options, fileOptions: ?*const cgltf_file_options, data: ?*anyopaque, size: cgltf_size) callconv(.c) void {
    _ = memoryOptions;
    _ = fileOptions;
    _ = size;
    UnloadFileData(@ptrCast(data));
}

// Load image from different glTF provided methods (uri, path, buffer_view)
fn LoadImageFromCgltfImage(cgltfImage: [*c]cgltf_image, texPath: [*c]const u8) Image {
    var image = std.mem.zeroes(Image);

    if (cgltfImage == null) return image;

    if (cgltfImage.*.uri != null) {
        if ((strlen(cgltfImage.*.uri) > 5) and
            (cgltfImage.*.uri[0] == 'd') and
            (cgltfImage.*.uri[1] == 'a') and
            (cgltfImage.*.uri[2] == 't') and
            (cgltfImage.*.uri[3] == 'a') and
            (cgltfImage.*.uri[4] == ':'))
        {
            var i: usize = 0;
            while ((cgltfImage.*.uri[i] != ',') and (cgltfImage.*.uri[i] != 0)) i += 1;

            if (cgltfImage.*.uri[i] == 0) {
                TraceLog(LOG_WARNING, "IMAGE: glTF data URI is not a valid image");
            } else {
                var base64Size: c_int = @intCast(strlen(cgltfImage.*.uri + i + 1));
                while (cgltfImage.*.uri[i + @as(usize, @intCast(base64Size))] == '=') base64Size -= 1;
                const numberOfEncodedBits = base64Size * 6 - @rem(base64Size * 6, 8);
                const outSize = @divTrunc(numberOfEncodedBits, 8);
                var data: ?*anyopaque = null;

                var options = std.mem.zeroes(cgltf_options);
                options.file.read = LoadFileGLTFCallback;
                options.file.release = ReleaseFileGLTFCallback;
                const result = cgltf_load_buffer_base64(&options, @intCast(outSize), cgltfImage.*.uri + i + 1, &data);

                if (result == cgltf_result_success) {
                    image = LoadImageFromMemory(".png", @ptrCast(data), outSize);
                    RL_FREE(data);
                }
            }
        } else {
            image = LoadImage(TextFormat("%s/%s", texPath, cgltfImage.*.uri));
        }
    } else if ((cgltfImage.*.buffer_view != null) and (cgltfImage.*.buffer_view.*.buffer.*.data != null)) {
        const data: [*c]u8 = @ptrCast(@alignCast(RL_MALLOC(cgltfImage.*.buffer_view.*.size)));
        var offset: usize = cgltfImage.*.buffer_view.*.offset;
        const stride: usize = if (cgltfImage.*.buffer_view.*.stride != 0) cgltfImage.*.buffer_view.*.stride else 1;

        const src: [*c]u8 = @ptrCast(@alignCast(cgltfImage.*.buffer_view.*.buffer.*.data));
        var i: usize = 0;
        while (i < cgltfImage.*.buffer_view.*.size) : (i += 1) {
            data[i] = src[offset];
            offset += stride;
        }

        if ((strcmp(cgltfImage.*.mime_type, "image\\/png") == 0) or (strcmp(cgltfImage.*.mime_type, "image/png") == 0)) {
            image = LoadImageFromMemory(".png", data, @intCast(cgltfImage.*.buffer_view.*.size));
        } else if ((strcmp(cgltfImage.*.mime_type, "image\\/jpeg") == 0) or (strcmp(cgltfImage.*.mime_type, "image/jpeg") == 0)) {
            image = LoadImageFromMemory(".jpg", data, @intCast(cgltfImage.*.buffer_view.*.size));
        } else TraceLog(LOG_WARNING, "MODEL: glTF image data MIME type not recognized", TextFormat("%s/%s", texPath, cgltfImage.*.uri));

        RL_FREE(data);
    }

    return image;
}

// Load bone info from GLTF skin data
fn LoadBoneInfoGLTF(skin: cgltf_skin, boneCount: [*c]c_uint) [*c]BoneInfo {
    boneCount.* = @truncate(skin.joints_count);
    const bones: [*c]BoneInfo = @ptrCast(@alignCast(RL_CALLOC(skin.joints_count, @sizeOf(BoneInfo))));

    var i: c_uint = 0;
    while (i < skin.joints_count) : (i += 1) {
        const node = skin.joints[i].*;
        if (node.name != null) _ = strncpy(&bones[i].name, node.name, bones[i].name.len - 1);

        var parentIndex: c_int = -1;
        var ancestor = node.parent;
        while (ancestor != null and parentIndex == -1) {
            var j: c_uint = 0;
            while (j < skin.joints_count) : (j += 1) {
                if (skin.joints[j] == ancestor) {
                    parentIndex = @intCast(j);
                    break;
                }
            }
            if (parentIndex == -1) ancestor = ancestor.*.parent;
        }

        bones[i].parent = parentIndex;
    }

    return bones;
}

fn matrixFromGLTF(t: *const [16]cgltf_float) Matrix {
    return Matrix{
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

// Load glTF file into model struct, .gltf and .glb supported
fn LoadGLTF(fileName: [*c]const u8) Model {
    var model = std.mem.zeroes(Model);

    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);

    if (fileData == null) return model;

    var options = std.mem.zeroes(cgltf_options);
    options.file.read = LoadFileGLTFCallback;
    options.file.release = ReleaseFileGLTFCallback;
    var data: [*c]cgltf_data = null;
    var result = cgltf_parse(&options, fileData, @intCast(dataSize), &data);

    if (result == cgltf_result_success) {
        if (data.*.file_type == cgltf_file_type_glb) {
            TraceLog(LOG_INFO, "MODEL: [%s] Model basic data (glb) loaded successfully", fileName);
        } else if (data.*.file_type == cgltf_file_type_gltf) {
            TraceLog(LOG_INFO, "MODEL: [%s] Model basic data (glTF) loaded successfully", fileName);
        } else TraceLog(LOG_WARNING, "MODEL: [%s] Model format not recognized", fileName);

        TraceLog(LOG_INFO, "    > Meshes count: %i", @as(c_int, @intCast(data.*.meshes_count)));
        TraceLog(LOG_INFO, "    > Materials count: %i (+1 default)", @as(c_int, @intCast(data.*.materials_count)));
        TraceLog(LOG_DEBUG, "    > Buffers count: %i", @as(c_int, @intCast(data.*.buffers_count)));
        TraceLog(LOG_DEBUG, "    > Images count: %i", @as(c_int, @intCast(data.*.images_count)));
        TraceLog(LOG_DEBUG, "    > Textures count: %i", @as(c_int, @intCast(data.*.textures_count)));

        result = cgltf_load_buffers(&options, data, fileName);
        if (result != cgltf_result_success) TraceLog(LOG_INFO, "MODEL: [%s] Failed to load mesh/material buffers", fileName);

        var primitivesCount: c_int = 0;
        var dracoCompression = false;

        var i: c_uint = 0;
        while (i < data.*.nodes_count) : (i += 1) {
            const node = &data.*.nodes[i];
            const mesh = node.mesh;
            if (mesh == null) continue;

            var p: c_uint = 0;
            while (p < mesh.*.primitives_count) : (p += 1) {
                if (mesh.*.primitives[p].has_draco_mesh_compression != 0) {
                    dracoCompression = true;
                    TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load mesh data, Draco compression not supported", fileName);
                    break;
                } else if (mesh.*.primitives[p].type == cgltf_primitive_type_triangles) primitivesCount += 1;
            }
        }

        if (dracoCompression) {
            TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load glTF data", fileName);
            cgltf_free(data);
            UnloadFileData(fileData);
            return model;
        }

        TraceLog(LOG_DEBUG, "    > Primitives (triangles only) count based on hierarchy : %i", primitivesCount);

        model.meshCount = primitivesCount;
        model.meshes = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(Mesh))));

        model.materialCount = @as(c_int, @intCast(data.*.materials_count)) + 1;
        model.materials = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.materialCount), @sizeOf(Material))));
        model.materials[0] = LoadMaterialDefault();

        model.meshMaterial = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(c_int))));

        // Load materials data
        {
            var mi: c_uint = 0;
            var j: usize = 1;
            while (mi < data.*.materials_count) : ({
                mi += 1;
                j += 1;
            }) {
                model.materials[j] = LoadMaterialDefault();
                const texPath = GetDirectoryPath(fileName);
                const mat = &data.*.materials[mi];

                if (mat.has_pbr_metallic_roughness != 0) {
                    if (mat.pbr_metallic_roughness.base_color_texture.texture != null) {
                        const imAlbedo = LoadImageFromCgltfImage(mat.pbr_metallic_roughness.base_color_texture.texture.*.image, texPath);
                        if (imAlbedo.data != null) {
                            model.materials[j].maps[MATERIAL_MAP_ALBEDO].texture = LoadTextureFromImage(imAlbedo);
                            UnloadImage(imAlbedo);
                        }
                    }
                    model.materials[j].maps[MATERIAL_MAP_ALBEDO].color.r = @intFromFloat(mat.pbr_metallic_roughness.base_color_factor[0] * 255);
                    model.materials[j].maps[MATERIAL_MAP_ALBEDO].color.g = @intFromFloat(mat.pbr_metallic_roughness.base_color_factor[1] * 255);
                    model.materials[j].maps[MATERIAL_MAP_ALBEDO].color.b = @intFromFloat(mat.pbr_metallic_roughness.base_color_factor[2] * 255);
                    model.materials[j].maps[MATERIAL_MAP_ALBEDO].color.a = @intFromFloat(mat.pbr_metallic_roughness.base_color_factor[3] * 255);

                    if (mat.pbr_metallic_roughness.metallic_roughness_texture.texture != null) {
                        const imMetallicRoughness = LoadImageFromCgltfImage(mat.pbr_metallic_roughness.metallic_roughness_texture.texture.*.image, texPath);
                        if (imMetallicRoughness.data != null) {
                            var imMetallic = std.mem.zeroes(Image);
                            var imRoughness = std.mem.zeroes(Image);

                            imMetallic.data = RL_MALLOC(@intCast(imMetallicRoughness.width * imMetallicRoughness.height));
                            imRoughness.data = RL_MALLOC(@intCast(imMetallicRoughness.width * imMetallicRoughness.height));

                            imMetallic.width = imMetallicRoughness.width;
                            imRoughness.width = imMetallicRoughness.width;
                            imMetallic.height = imMetallicRoughness.height;
                            imRoughness.height = imMetallicRoughness.height;

                            imMetallic.format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE;
                            imRoughness.format = PIXELFORMAT_UNCOMPRESSED_GRAYSCALE;
                            imMetallic.mipmaps = 1;
                            imRoughness.mipmaps = 1;

                            var x: c_int = 0;
                            while (x < imRoughness.width) : (x += 1) {
                                var y: c_int = 0;
                                while (y < imRoughness.height) : (y += 1) {
                                    const col = GetImageColor(imMetallicRoughness, x, y);
                                    const rdata: [*c]u8 = @ptrCast(imRoughness.data);
                                    const mdata: [*c]u8 = @ptrCast(imMetallic.data);
                                    rdata[@intCast(y * imRoughness.width + x)] = col.g;
                                    mdata[@intCast(y * imMetallic.width + x)] = col.b;
                                }
                            }

                            model.materials[j].maps[MATERIAL_MAP_ROUGHNESS].texture = LoadTextureFromImage(imRoughness);
                            model.materials[j].maps[MATERIAL_MAP_METALNESS].texture = LoadTextureFromImage(imMetallic);

                            UnloadImage(imRoughness);
                            UnloadImage(imMetallic);
                            UnloadImage(imMetallicRoughness);
                        }

                        model.materials[j].maps[MATERIAL_MAP_ROUGHNESS].value = mat.pbr_metallic_roughness.roughness_factor;
                        model.materials[j].maps[MATERIAL_MAP_METALNESS].value = mat.pbr_metallic_roughness.metallic_factor;
                    }

                    if (mat.normal_texture.texture != null) {
                        const imNormal = LoadImageFromCgltfImage(mat.normal_texture.texture.*.image, texPath);
                        if (imNormal.data != null) {
                            model.materials[j].maps[MATERIAL_MAP_NORMAL].texture = LoadTextureFromImage(imNormal);
                            UnloadImage(imNormal);
                        }
                    }

                    if (mat.occlusion_texture.texture != null) {
                        const imOcclusion = LoadImageFromCgltfImage(mat.occlusion_texture.texture.*.image, texPath);
                        if (imOcclusion.data != null) {
                            model.materials[j].maps[MATERIAL_MAP_OCCLUSION].texture = LoadTextureFromImage(imOcclusion);
                            UnloadImage(imOcclusion);
                        }
                    }

                    if (mat.emissive_texture.texture != null) {
                        const imEmissive = LoadImageFromCgltfImage(mat.emissive_texture.texture.*.image, texPath);
                        if (imEmissive.data != null) {
                            model.materials[j].maps[MATERIAL_MAP_EMISSION].texture = LoadTextureFromImage(imEmissive);
                            UnloadImage(imEmissive);
                        }

                        model.materials[j].maps[MATERIAL_MAP_EMISSION].color.r = @intFromFloat(mat.emissive_factor[0] * 255);
                        model.materials[j].maps[MATERIAL_MAP_EMISSION].color.g = @intFromFloat(mat.emissive_factor[1] * 255);
                        model.materials[j].maps[MATERIAL_MAP_EMISSION].color.b = @intFromFloat(mat.emissive_factor[2] * 255);
                        model.materials[j].maps[MATERIAL_MAP_EMISSION].color.a = 255;
                    }
                }
            }
        }

        // Load meshes data
        var meshIndex: usize = 0;
        i = 0;
        while (i < data.*.nodes_count) : (i += 1) {
            const node = &data.*.nodes[i];
            const mesh = node.mesh;
            if (mesh == null) continue;

            var worldTransform: [16]cgltf_float = undefined;
            cgltf_node_transform_world(node, &worldTransform);

            const worldMatrix = matrixFromGLTF(&worldTransform);
            const worldMatrixNormals = MatrixTranspose(MatrixInvert(worldMatrix));

            var p: c_uint = 0;
            while (p < mesh.*.primitives_count) : (p += 1) {
                if (mesh.*.primitives[p].type != cgltf_primitive_type_triangles) continue;

                var j: c_uint = 0;
                while (j < mesh.*.primitives[p].attributes_count) : (j += 1) {
                    const attr = &mesh.*.primitives[p].attributes[j];
                    if (attr.type == cgltf_attribute_type_position) {
                        const attribute = attr.data;
                        if (model.meshes[meshIndex].vertices != null) {
                            TraceLog(LOG_WARNING, "MODEL: [%s] Vertices attribute data already loaded", fileName);
                        } else if ((attribute.*.type == cgltf_type_vec3) and (attribute.*.component_type == cgltf_component_type_r_32f)) {
                            model.meshes[meshIndex].vertexCount = @intCast(attribute.*.count);
                            model.meshes[meshIndex].vertices = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(f32))));
                            loadAttribute(f32, f32, attribute, 3, model.meshes[meshIndex].vertices);
                            transformVertices(model.meshes[meshIndex].vertices, attribute.*.count, worldMatrix, false);
                        } else if ((attribute.*.type == cgltf_type_vec3) and (attribute.*.component_type == cgltf_component_type_r_16u)) {
                            model.meshes[meshIndex].vertexCount = @intCast(attribute.*.count);
                            model.meshes[meshIndex].vertices = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(f32))));
                            const temp: [*c]c_ushort = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(c_ushort))));
                            loadAttribute(c_ushort, c_ushort, attribute, 3, temp);
                            var t: usize = 0;
                            while (t < attribute.*.count * 3) : (t += 1) model.meshes[meshIndex].vertices[t] = @floatFromInt(temp[t]);
                            RL_FREE(temp);
                            transformVertices(model.meshes[meshIndex].vertices, attribute.*.count, worldMatrix, false);
                        } else if ((attribute.*.type == cgltf_type_vec3) and (attribute.*.component_type == cgltf_component_type_r_16)) {
                            model.meshes[meshIndex].vertexCount = @intCast(attribute.*.count);
                            model.meshes[meshIndex].vertices = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(f32))));
                            const temp: [*c]i16 = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(i16))));
                            loadAttribute(i16, i16, attribute, 3, temp);
                            var t: usize = 0;
                            while (t < attribute.*.count * 3) : (t += 1) model.meshes[meshIndex].vertices[t] = @floatFromInt(temp[t]);
                            RL_FREE(temp);
                            transformVertices(model.meshes[meshIndex].vertices, attribute.*.count, worldMatrix, false);
                        } else TraceLog(LOG_WARNING, "MODEL: [%s] Vertices attribute data format not supported, use vec3 float", fileName);
                    } else if (attr.type == cgltf_attribute_type_normal) {
                        const attribute = attr.data;
                        if (model.meshes[meshIndex].normals != null) {
                            TraceLog(LOG_WARNING, "MODEL: [%s] Normals attribute data already loaded", fileName);
                        } else if ((attribute.*.type == cgltf_type_vec3) and (attribute.*.component_type == cgltf_component_type_r_32f)) {
                            model.meshes[meshIndex].normals = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(f32))));
                            loadAttribute(f32, f32, attribute, 3, model.meshes[meshIndex].normals);
                            transformVertices(model.meshes[meshIndex].normals, attribute.*.count, worldMatrixNormals, false);
                        } else if ((attribute.*.type == cgltf_type_vec3) and (attribute.*.component_type == cgltf_component_type_r_16)) {
                            model.meshes[meshIndex].normals = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(f32))));
                            const temp: [*c]i16 = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(i16))));
                            loadAttribute(i16, i16, attribute, 3, temp);
                            var t: usize = 0;
                            while (t < attribute.*.count * 3) : (t += 1) model.meshes[meshIndex].normals[t] = @floatFromInt(temp[t]);
                            RL_FREE(temp);
                            transformVertices(model.meshes[meshIndex].normals, attribute.*.count, worldMatrixNormals, true);
                        } else if ((attribute.*.type == cgltf_type_vec3) and (attribute.*.component_type == cgltf_component_type_r_8u)) {
                            model.meshes[meshIndex].normals = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(f32))));
                            const temp: [*c]u8 = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(u8))));
                            loadAttribute(u8, u8, attribute, 3, temp);
                            var t: usize = 0;
                            while (t < attribute.*.count * 3) : (t += 1) model.meshes[meshIndex].normals[t] = @floatFromInt(temp[t]);
                            RL_FREE(temp);
                            transformVertices(model.meshes[meshIndex].normals, attribute.*.count, worldMatrixNormals, true);
                        } else if ((attribute.*.type == cgltf_type_vec3) and (attribute.*.component_type == cgltf_component_type_r_8)) {
                            model.meshes[meshIndex].normals = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(f32))));
                            const temp: [*c]i8 = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(i8))));
                            loadAttribute(i8, i8, attribute, 3, temp);
                            var t: usize = 0;
                            while (t < attribute.*.count * 3) : (t += 1) model.meshes[meshIndex].normals[t] = @floatFromInt(temp[t]);
                            RL_FREE(temp);
                            transformVertices(model.meshes[meshIndex].normals, attribute.*.count, worldMatrixNormals, true);
                        } else TraceLog(LOG_WARNING, "MODEL: [%s] Normals attribute data format not supported, use vec3 float", fileName);
                    } else if (attr.type == cgltf_attribute_type_tangent) {
                        const attribute = attr.data;
                        if (model.meshes[meshIndex].tangents != null) {
                            TraceLog(LOG_WARNING, "MODEL: [%s] Tangents attribute data already loaded", fileName);
                        } else if ((attribute.*.type == cgltf_type_vec4) and (attribute.*.component_type == cgltf_component_type_r_32f)) {
                            model.meshes[meshIndex].tangents = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 4 * @sizeOf(f32))));
                            loadAttribute(f32, f32, attribute, 4, model.meshes[meshIndex].tangents);
                            const tangents = model.meshes[meshIndex].tangents;
                            var k: usize = 0;
                            while (k < attribute.*.count) : (k += 1) {
                                const tt = Vector3Transform(.{ .x = tangents[4 * k], .y = tangents[4 * k + 1], .z = tangents[4 * k + 2] }, worldMatrix);
                                tangents[4 * k] = tt.x;
                                tangents[4 * k + 1] = tt.y;
                                tangents[4 * k + 2] = tt.z;
                            }
                        } else TraceLog(LOG_WARNING, "MODEL: [%s] Tangents attribute data format not supported, use vec4 float", fileName);
                    } else if (attr.type == cgltf_attribute_type_texcoord) {
                        var texcoordPtr: [*c]f32 = null;
                        const attribute = attr.data;

                        if (attribute.*.type == cgltf_type_vec2) {
                            if (attribute.*.component_type == cgltf_component_type_r_32f) {
                                texcoordPtr = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 2 * @sizeOf(f32))));
                                loadAttribute(f32, f32, attribute, 2, texcoordPtr);
                            } else if (attribute.*.component_type == cgltf_component_type_r_8u) {
                                texcoordPtr = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 2 * @sizeOf(f32))));
                                const temp: [*c]u8 = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 2 * @sizeOf(u8))));
                                loadAttribute(u8, u8, attribute, 2, temp);
                                var t: usize = 0;
                                while (t < attribute.*.count * 2) : (t += 1) texcoordPtr[t] = @as(f32, @floatFromInt(temp[t])) / 255.0;
                                RL_FREE(temp);
                            } else if (attribute.*.component_type == cgltf_component_type_r_16u) {
                                texcoordPtr = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 2 * @sizeOf(f32))));
                                const temp: [*c]c_ushort = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 2 * @sizeOf(c_ushort))));
                                loadAttribute(c_ushort, c_ushort, attribute, 2, temp);
                                var t: usize = 0;
                                while (t < attribute.*.count * 2) : (t += 1) texcoordPtr[t] = @as(f32, @floatFromInt(temp[t])) / 65535.0;
                                RL_FREE(temp);
                            } else TraceLog(LOG_WARNING, "MODEL: [%s] Texcoords attribute data format not supported", fileName);
                        } else TraceLog(LOG_WARNING, "MODEL: [%s] Texcoords attribute data format not supported, use vec2 float", fileName);

                        const index = attr.index;
                        if (index == 0) {
                            model.meshes[meshIndex].texcoords = texcoordPtr;
                        } else if (index == 1) {
                            model.meshes[meshIndex].texcoords2 = texcoordPtr;
                        } else {
                            TraceLog(LOG_WARNING, "MODEL: [%s] No more than 2 texture coordinates attributes supported", fileName);
                            if (texcoordPtr != null) RL_FREE(texcoordPtr);
                        }
                    } else if (attr.type == cgltf_attribute_type_color) {
                        const attribute = attr.data;
                        if (model.meshes[meshIndex].colors != null) {
                            TraceLog(LOG_WARNING, "MODEL: [%s] Colors attribute data already loaded", fileName);
                        } else if (attribute.*.type == cgltf_type_vec3) {
                            if (attribute.*.component_type == cgltf_component_type_r_8u) {
                                model.meshes[meshIndex].colors = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 4 * @sizeOf(u8))));
                                const temp: [*c]u8 = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(u8))));
                                loadAttribute(u8, u8, attribute, 3, temp);
                                var c: usize = 0;
                                var k: usize = 0;
                                while (c < (attribute.*.count * 4 - 3)) : ({
                                    c += 4;
                                    k += 3;
                                }) {
                                    model.meshes[meshIndex].colors[c] = temp[k];
                                    model.meshes[meshIndex].colors[c + 1] = temp[k + 1];
                                    model.meshes[meshIndex].colors[c + 2] = temp[k + 2];
                                    model.meshes[meshIndex].colors[c + 3] = 255;
                                }
                                RL_FREE(temp);
                            } else if (attribute.*.component_type == cgltf_component_type_r_16u) {
                                model.meshes[meshIndex].colors = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 4 * @sizeOf(u8))));
                                const temp: [*c]c_ushort = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(c_ushort))));
                                loadAttribute(c_ushort, c_ushort, attribute, 3, temp);
                                var c: usize = 0;
                                var k: usize = 0;
                                while (c < (attribute.*.count * 4 - 3)) : ({
                                    c += 4;
                                    k += 3;
                                }) {
                                    model.meshes[meshIndex].colors[c] = @intFromFloat((@as(f32, @floatFromInt(temp[k])) / 65535.0) * 255.0);
                                    model.meshes[meshIndex].colors[c + 1] = @intFromFloat((@as(f32, @floatFromInt(temp[k + 1])) / 65535.0) * 255.0);
                                    model.meshes[meshIndex].colors[c + 2] = @intFromFloat((@as(f32, @floatFromInt(temp[k + 2])) / 65535.0) * 255.0);
                                    model.meshes[meshIndex].colors[c + 3] = 255;
                                }
                                RL_FREE(temp);
                            } else if (attribute.*.component_type == cgltf_component_type_r_32f) {
                                model.meshes[meshIndex].colors = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 4 * @sizeOf(u8))));
                                const temp: [*c]f32 = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 3 * @sizeOf(f32))));
                                loadAttribute(f32, f32, attribute, 3, temp);
                                var c: usize = 0;
                                var k: usize = 0;
                                while (c < (attribute.*.count * 4 - 3)) : ({
                                    c += 4;
                                    k += 3;
                                }) {
                                    model.meshes[meshIndex].colors[c] = @intFromFloat(temp[k] * 255.0);
                                    model.meshes[meshIndex].colors[c + 1] = @intFromFloat(temp[k + 1] * 255.0);
                                    model.meshes[meshIndex].colors[c + 2] = @intFromFloat(temp[k + 2] * 255.0);
                                    model.meshes[meshIndex].colors[c + 3] = 255;
                                }
                                RL_FREE(temp);
                            } else TraceLog(LOG_WARNING, "MODEL: [%s] Color attribute data format not supported", fileName);
                        } else if (attribute.*.type == cgltf_type_vec4) {
                            if (attribute.*.component_type == cgltf_component_type_r_8u) {
                                model.meshes[meshIndex].colors = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 4 * @sizeOf(u8))));
                                loadAttribute(u8, u8, attribute, 4, model.meshes[meshIndex].colors);
                            } else if (attribute.*.component_type == cgltf_component_type_r_16u) {
                                model.meshes[meshIndex].colors = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 4 * @sizeOf(u8))));
                                const temp: [*c]c_ushort = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 4 * @sizeOf(c_ushort))));
                                loadAttribute(c_ushort, c_ushort, attribute, 4, temp);
                                var c: usize = 0;
                                while (c < attribute.*.count * 4) : (c += 1) model.meshes[meshIndex].colors[c] = @intFromFloat((@as(f32, @floatFromInt(temp[c])) / 65535.0) * 255.0);
                                RL_FREE(temp);
                            } else if (attribute.*.component_type == cgltf_component_type_r_32f) {
                                model.meshes[meshIndex].colors = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 4 * @sizeOf(u8))));
                                const temp: [*c]f32 = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 4 * @sizeOf(f32))));
                                loadAttribute(f32, f32, attribute, 4, temp);
                                var c: usize = 0;
                                while (c < attribute.*.count * 4) : (c += 1) model.meshes[meshIndex].colors[c] = @intFromFloat(temp[c] * 255.0);
                                RL_FREE(temp);
                            } else TraceLog(LOG_WARNING, "MODEL: [%s] Color attribute data format not supported", fileName);
                        } else TraceLog(LOG_WARNING, "MODEL: [%s] Color attribute data format not supported", fileName);
                    }
                }

                // Load primitive indices data (if provided)
                if ((mesh.*.primitives[p].indices != null) and (mesh.*.primitives[p].indices.*.buffer_view != null)) {
                    const attribute = mesh.*.primitives[p].indices;
                    model.meshes[meshIndex].triangleCount = @intCast(attribute.*.count / 3);

                    if (model.meshes[meshIndex].indices != null) {
                        TraceLog(LOG_WARNING, "MODEL: [%s] Indices attribute data already loaded", fileName);
                    } else if (attribute.*.component_type == cgltf_component_type_r_16u) {
                        model.meshes[meshIndex].indices = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * @sizeOf(c_ushort))));
                        loadAttribute(c_ushort, c_ushort, attribute, 1, model.meshes[meshIndex].indices);
                    } else if (attribute.*.component_type == cgltf_component_type_r_8u) {
                        model.meshes[meshIndex].indices = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * @sizeOf(c_ushort))));
                        loadAttribute(u8, c_ushort, attribute, 1, model.meshes[meshIndex].indices);
                    } else if (attribute.*.component_type == cgltf_component_type_r_32u) {
                        model.meshes[meshIndex].indices = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * @sizeOf(c_ushort))));
                        loadAttribute(c_uint, c_ushort, attribute, 1, model.meshes[meshIndex].indices);
                        TraceLog(LOG_WARNING, "MODEL: [%s] Indices data converted from u32 to u16, possible loss of data", fileName);
                    } else TraceLog(LOG_WARNING, "MODEL: [%s] Indices data format not supported, use u16", fileName);
                } else model.meshes[meshIndex].triangleCount = @divTrunc(model.meshes[meshIndex].vertexCount, 3);

                var m: c_uint = 0;
                while (m < data.*.materials_count) : (m += 1) {
                    if (&data.*.materials[m] == mesh.*.primitives[p].material) {
                        model.meshMaterial[meshIndex] = @intCast(m + 1);
                        break;
                    }
                }

                meshIndex += 1;
            }
        }

        // Load animation data (skins)
        if (data.*.skins_count > 0) {
            const skin = data.*.skins[0];
            model.skeleton.bones = LoadBoneInfoGLTF(skin, &model.skeleton.boneCount);
            model.skeleton.bindPose = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.skeleton.boneCount), @sizeOf(Transform))));

            var bi: c_int = 0;
            while (bi < model.skeleton.boneCount) : (bi += 1) {
                var bindMatrix = std.mem.zeroes(Matrix);
                var inverseBindTransform = std.mem.zeroes([16]cgltf_float);

                if ((skin.inverse_bind_matrices != null) and
                    (skin.inverse_bind_matrices.*.count >= skin.joints_count) and
                    (cgltf_accessor_read_float(skin.inverse_bind_matrices, @intCast(bi), &inverseBindTransform, 16) != 0))
                {
                    const inverseBindMatrix = matrixFromGLTF(&inverseBindTransform);
                    bindMatrix = MatrixInvert(inverseBindMatrix);
                } else {
                    var worldTransform = std.mem.zeroes([16]cgltf_float);
                    cgltf_node_transform_world(skin.joints[@intCast(bi)], &worldTransform);
                    bindMatrix = matrixFromGLTF(&worldTransform);
                }

                MatrixDecompose(bindMatrix, &model.skeleton.bindPose[@intCast(bi)].translation, &model.skeleton.bindPose[@intCast(bi)].rotation, &model.skeleton.bindPose[@intCast(bi)].scale);
            }

            if (data.*.skins_count > 1) TraceLog(LOG_WARNING, "MODEL: [%s] can only load one skin (armature) per model, but gltf skins_count == %i", fileName, data.*.skins_count);
        }

        // Load skin/bone vertex data
        meshIndex = 0;
        i = 0;
        while (i < data.*.nodes_count) : (i += 1) {
            const node = &data.*.nodes[i];
            const mesh = node.mesh;
            if (mesh == null) continue;

            var p: c_uint = 0;
            while (p < mesh.*.primitives_count) : (p += 1) {
                var hasJoints = false;

                if (mesh.*.primitives[p].type != cgltf_primitive_type_triangles) continue;

                var j: c_uint = 0;
                while (j < mesh.*.primitives[p].attributes_count) : (j += 1) {
                    const attr = &mesh.*.primitives[p].attributes[j];
                    if (attr.type == cgltf_attribute_type_joints) {
                        hasJoints = true;
                        const attribute = attr.data;
                        if (attribute.*.type == cgltf_type_vec4) {
                            if (attribute.*.component_type == cgltf_component_type_r_8u) {
                                model.meshes[meshIndex].boneIndices = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[meshIndex].vertexCount * 4), @sizeOf(u8))));
                                loadAttribute(u8, u8, attribute, 4, model.meshes[meshIndex].boneIndices);
                            } else if (attribute.*.component_type == cgltf_component_type_r_16u) {
                                model.meshes[meshIndex].boneIndices = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[meshIndex].vertexCount * 4), @sizeOf(u8))));
                                const temp: [*c]c_ushort = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[meshIndex].vertexCount * 4), @sizeOf(c_ushort))));
                                loadAttribute(c_ushort, c_ushort, attribute, 4, temp);
                                var boneIdOverflowWarning = false;
                                var b: c_int = 0;
                                while (b < model.meshes[meshIndex].vertexCount * 4) : (b += 1) {
                                    if ((temp[@intCast(b)] > 255) and !boneIdOverflowWarning) {
                                        TraceLog(LOG_WARNING, "MODEL: [%s] Joint attribute data format (u16) overflow", fileName);
                                        boneIdOverflowWarning = true;
                                    }
                                    model.meshes[meshIndex].boneIndices[@intCast(b)] = @truncate(temp[@intCast(b)]);
                                }
                                RL_FREE(temp);
                            } else TraceLog(LOG_WARNING, "MODEL: [%s] Joint attribute data format not supported", fileName);
                        } else TraceLog(LOG_WARNING, "MODEL: [%s] Joint attribute data format not supported", fileName);
                    } else if (attr.type == cgltf_attribute_type_weights) {
                        const attribute = attr.data;
                        if (attribute.*.type == cgltf_type_vec4) {
                            if (attribute.*.component_type == cgltf_component_type_r_8u) {
                                model.meshes[meshIndex].boneWeights = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[meshIndex].vertexCount * 4), @sizeOf(f32))));
                                const temp: [*c]u8 = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 4 * @sizeOf(u8))));
                                loadAttribute(u8, u8, attribute, 4, temp);
                                var b: usize = 0;
                                while (b < attribute.*.count * 4) : (b += 1) model.meshes[meshIndex].boneWeights[b] = @as(f32, @floatFromInt(temp[b])) / 255.0;
                                RL_FREE(temp);
                            } else if (attribute.*.component_type == cgltf_component_type_r_16u) {
                                model.meshes[meshIndex].boneWeights = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[meshIndex].vertexCount * 4), @sizeOf(f32))));
                                const temp: [*c]c_ushort = @ptrCast(@alignCast(RL_MALLOC(attribute.*.count * 4 * @sizeOf(c_ushort))));
                                loadAttribute(c_ushort, c_ushort, attribute, 4, temp);
                                var b: usize = 0;
                                while (b < attribute.*.count * 4) : (b += 1) model.meshes[meshIndex].boneWeights[b] = @as(f32, @floatFromInt(temp[b])) / 65535.0;
                                RL_FREE(temp);
                            } else if (attribute.*.component_type == cgltf_component_type_r_32f) {
                                model.meshes[meshIndex].boneWeights = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[meshIndex].vertexCount * 4), @sizeOf(f32))));
                                loadAttribute(f32, f32, attribute, 4, model.meshes[meshIndex].boneWeights);
                            } else TraceLog(LOG_WARNING, "MODEL: [%s] Joint weight attribute data format not supported, use vec4 float", fileName);
                        } else TraceLog(LOG_WARNING, "MODEL: [%s] Joint weight attribute data format not supported, use vec4 float", fileName);
                    }
                }

                if ((data.*.skins_count > 0) and !hasJoints and (node.parent != null) and (node.parent.*.mesh == null)) {
                    var parentBoneId: c_int = -1;
                    var joint: c_int = 0;
                    while (joint < model.skeleton.boneCount) : (joint += 1) {
                        if (data.*.skins[0].joints[@intCast(joint)] == node.parent) {
                            parentBoneId = joint;
                            break;
                        }
                    }

                    if (parentBoneId >= 0) {
                        model.meshes[meshIndex].boneIndices = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[meshIndex].vertexCount * 4), @sizeOf(u8))));
                        model.meshes[meshIndex].boneWeights = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[meshIndex].vertexCount * 4), @sizeOf(f32))));

                        var vertexIndex: c_int = 0;
                        while (vertexIndex < model.meshes[meshIndex].vertexCount * 4) : (vertexIndex += 4) {
                            model.meshes[meshIndex].boneIndices[@intCast(vertexIndex)] = @intCast(parentBoneId);
                            model.meshes[meshIndex].boneWeights[@intCast(vertexIndex)] = 1.0;
                        }
                    }
                }

                model.meshes[meshIndex].boneCount = @bitCast(model.skeleton.boneCount);

                meshIndex += 1;
            }
        }

        model.currentPose = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.skeleton.boneCount), @sizeOf(Transform))));
        model.boneMatrices = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.skeleton.boneCount), @sizeOf(Matrix))));
        {
            var j: c_int = 0;
            while (j < model.skeleton.boneCount) : (j += 1) model.boneMatrices[@intCast(j)] = MatrixIdentity();
        }

        if (model.skeleton.boneCount == 0) {
            RL_FREE(model.currentPose);
            RL_FREE(model.boneMatrices);
            model.currentPose = null;
            model.boneMatrices = null;
        }

        cgltf_free(data);
    } else TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load glTF data", fileName);

    UnloadFileData(fileData);

    return model;
}

// Transform vertices/normals in place by a matrix (normalize normals when requested)
fn transformVertices(values: [*c]f32, count: cgltf_size, mat: Matrix, normalize: bool) void {
    var k: usize = 0;
    while (k < count) : (k += 1) {
        var vt = Vector3Transform(.{ .x = values[3 * k], .y = values[3 * k + 1], .z = values[3 * k + 2] }, mat);
        if (normalize) vt = Vector3Normalize(vt);
        values[3 * k] = vt.x;
        values[3 * k + 1] = vt.y;
        values[3 * k + 2] = vt.z;
    }
}

// Get interpolated pose for bone sampler at a specific time. Returns true on success
fn GetPoseAtTimeGLTF(interpolationType_in: cgltf_interpolation_type, input: [*c]cgltf_accessor, output: [*c]cgltf_accessor, time: f32, data: ?*anyopaque) bool {
    var interpolationType = interpolationType_in;
    if (interpolationType >= cgltf_interpolation_type_max_enum) return false;

    var tstart: f32 = 0.0;
    var tend: f32 = 0.0;
    var keyframe: c_int = 0; // Defaults to first pose
    var found = false;

    const keyCount: c_int = @intCast(input.*.count);
    var i: c_int = 0;
    while (i < keyCount - 1) : (i += 1) {
        const r1 = cgltf_accessor_read_float(input, @intCast(i), &tstart, 1);
        if (r1 == 0) return false;

        const r2 = cgltf_accessor_read_float(input, @intCast(i + 1), &tend, 1);
        if (r2 == 0) return false;

        if ((tstart <= time) and (time < tend)) {
            keyframe = i;
            found = true;
            break;
        }
    }

    // No interval contains a time at (or past) the last keyframe, because the search
    // above requires time < tend: clamp to the edge interval instead of falling back
    // to keyframe 0, which would return a pose from the start
    if (!found and (keyCount >= 2)) {
        keyframe = keyCount - 2;

        var tfirst: f32 = 0.0;
        if (cgltf_accessor_read_float(input, 0, &tfirst, 1) == 0) return false;
        if (time < tfirst) keyframe = 0;

        if (cgltf_accessor_read_float(input, @intCast(keyframe), &tstart, 1) == 0) return false;
        if (cgltf_accessor_read_float(input, @intCast(keyframe + 1), &tend, 1) == 0) return false;
    }

    if (FloatEquals(tend, tstart) != 0) {
        interpolationType = cgltf_interpolation_type_step;
    }

    const duration = fmaxf((tend - tstart), EPSILON);
    var t = (time - tstart) / duration;
    t = if (t < 0.0) 0.0 else t;
    t = if (t > 1.0) 1.0 else t;

    if (output.*.component_type != cgltf_component_type_r_32f) return false;

    if (output.*.type == cgltf_type_vec3) {
        const r: *Vector3 = @ptrCast(@alignCast(data));
        switch (interpolationType) {
            cgltf_interpolation_type_step => {
                var tmp = std.mem.zeroes([3]f32);
                _ = cgltf_accessor_read_float(output, @intCast(keyframe), &tmp, 3);
                r.* = .{ .x = tmp[0], .y = tmp[1], .z = tmp[2] };
            },
            cgltf_interpolation_type_linear => {
                var tmp = std.mem.zeroes([3]f32);
                _ = cgltf_accessor_read_float(output, @intCast(keyframe), &tmp, 3);
                const v1 = Vector3{ .x = tmp[0], .y = tmp[1], .z = tmp[2] };
                _ = cgltf_accessor_read_float(output, @intCast(keyframe + 1), &tmp, 3);
                const v2 = Vector3{ .x = tmp[0], .y = tmp[1], .z = tmp[2] };
                r.* = Vector3Lerp(v1, v2, t);
            },
            cgltf_interpolation_type_cubic_spline => {
                var tmp = std.mem.zeroes([3]f32);
                _ = cgltf_accessor_read_float(output, @intCast(3 * keyframe + 1), &tmp, 3);
                const v1 = Vector3{ .x = tmp[0], .y = tmp[1], .z = tmp[2] };
                _ = cgltf_accessor_read_float(output, @intCast(3 * keyframe + 2), &tmp, 3);
                const tangent1 = Vector3{ .x = tmp[0], .y = tmp[1], .z = tmp[2] };
                _ = cgltf_accessor_read_float(output, @intCast(3 * (keyframe + 1) + 1), &tmp, 3);
                const v2 = Vector3{ .x = tmp[0], .y = tmp[1], .z = tmp[2] };
                _ = cgltf_accessor_read_float(output, @intCast(3 * (keyframe + 1)), &tmp, 3);
                const tangent2 = Vector3{ .x = tmp[0], .y = tmp[1], .z = tmp[2] };
                r.* = Vector3CubicHermite(v1, tangent1, v2, tangent2, t);
            },
            else => {},
        }
    } else if (output.*.type == cgltf_type_vec4) {
        const r: *Vector4 = @ptrCast(@alignCast(data));
        switch (interpolationType) {
            cgltf_interpolation_type_step => {
                var tmp = std.mem.zeroes([4]f32);
                _ = cgltf_accessor_read_float(output, @intCast(keyframe), &tmp, 4);
                r.* = .{ .x = tmp[0], .y = tmp[1], .z = tmp[2], .w = tmp[3] };
            },
            cgltf_interpolation_type_linear => {
                var tmp = std.mem.zeroes([4]f32);
                _ = cgltf_accessor_read_float(output, @intCast(keyframe), &tmp, 4);
                const v1 = Vector4{ .x = tmp[0], .y = tmp[1], .z = tmp[2], .w = tmp[3] };
                _ = cgltf_accessor_read_float(output, @intCast(keyframe + 1), &tmp, 4);
                const v2 = Vector4{ .x = tmp[0], .y = tmp[1], .z = tmp[2], .w = tmp[3] };
                r.* = QuaternionSlerp(v1, v2, t);
            },
            cgltf_interpolation_type_cubic_spline => {
                var tmp = std.mem.zeroes([4]f32);
                _ = cgltf_accessor_read_float(output, @intCast(3 * keyframe + 1), &tmp, 4);
                var v1 = Vector4{ .x = tmp[0], .y = tmp[1], .z = tmp[2], .w = tmp[3] };
                _ = cgltf_accessor_read_float(output, @intCast(3 * keyframe + 2), &tmp, 4);
                var outTangent1 = Vector4{ .x = tmp[0], .y = tmp[1], .z = tmp[2], .w = 0.0 };
                _ = cgltf_accessor_read_float(output, @intCast(3 * (keyframe + 1) + 1), &tmp, 4);
                var v2 = Vector4{ .x = tmp[0], .y = tmp[1], .z = tmp[2], .w = tmp[3] };
                _ = cgltf_accessor_read_float(output, @intCast(3 * (keyframe + 1)), &tmp, 4);
                var inTangent2 = Vector4{ .x = tmp[0], .y = tmp[1], .z = tmp[2], .w = 0.0 };

                v1 = QuaternionNormalize(v1);
                v2 = QuaternionNormalize(v2);

                if (Vector4DotProduct(v1, v2) < 0.0) {
                    v2 = Vector4Negate(v2);
                }

                outTangent1 = Vector4Scale(outTangent1, duration);
                inTangent2 = Vector4Scale(inTangent2, duration);

                r.* = QuaternionCubicHermiteSpline(v1, outTangent1, v2, inTangent2, t);
            },
            else => {},
        }
    }

    return true;
}

const GLTF_FRAMERATE: f32 = 60.0;

const ChannelsGLTF = extern struct {
    translate: [*c]cgltf_animation_channel,
    rotate: [*c]cgltf_animation_channel,
    scale: [*c]cgltf_animation_channel,
};

fn LoadModelAnimationsGLTF(fileName: [*c]const u8, animCount: [*c]c_int) [*c]ModelAnimation {
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);

    var animations: [*c]ModelAnimation = null;

    var options = std.mem.zeroes(cgltf_options);
    options.file.read = LoadFileGLTFCallback;
    options.file.release = ReleaseFileGLTFCallback;
    var data: [*c]cgltf_data = null;
    var result = cgltf_parse(&options, fileData, @intCast(dataSize), &data);

    if (result != cgltf_result_success) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load glTF data", fileName);
        animCount.* = 0;
        return null;
    }

    result = cgltf_load_buffers(&options, data, fileName);
    if (result != cgltf_result_success) TraceLog(LOG_INFO, "MODEL: [%s] Failed to load animation buffers", fileName);

    if (result == cgltf_result_success) {
        if (data.*.skins_count > 0) {
            const skin = data.*.skins[0];

            const jointCount: c_int = @intCast(skin.joints_count);
            const extOffset: [*c]Matrix = @ptrCast(@alignCast(RL_MALLOC(@as(usize, @intCast(jointCount)) * @sizeOf(Matrix))));

            if (extOffset == null) {
                TraceLog(LOG_WARNING, "MODEL: [%s] Failed to allocate joint offset buffer", fileName);
                cgltf_free(data);
                UnloadFileData(fileData);
                animCount.* = 0;
                return null;
            }

            animCount.* = @intCast(data.*.animations_count);
            animations = @ptrCast(@alignCast(RL_CALLOC(data.*.animations_count, @sizeOf(ModelAnimation))));

            var k: c_int = 0;
            while (k < jointCount) : (k += 1) {
                extOffset[@intCast(k)] = MatrixIdentity();
                var n = skin.joints[@intCast(k)].*.parent;

                while (n != null) {
                    var isJoint = false;
                    var jj: c_int = 0;
                    while (jj < jointCount) : (jj += 1) {
                        if (skin.joints[@intCast(jj)] == n) {
                            isJoint = true;
                            break;
                        }
                    }

                    if (isJoint) break;

                    const nsc = n.*.scale;
                    const nro = n.*.rotation;
                    const ntr = n.*.translation;
                    const nodeScale = MatrixScale(nsc[0], nsc[1], nsc[2]);
                    const nodeRotation = QuaternionToMatrix(.{ .x = nro[0], .y = nro[1], .z = nro[2], .w = nro[3] });
                    const nodeTranslation = MatrixTranslate(ntr[0], ntr[1], ntr[2]);
                    const nodeTransform = MatrixMultiply(MatrixMultiply(nodeScale, nodeRotation), nodeTranslation);

                    extOffset[@intCast(k)] = MatrixMultiply(extOffset[@intCast(k)], nodeTransform);
                    n = n.*.parent;
                }
            }

            var a: c_uint = 0;
            while (a < data.*.animations_count) : (a += 1) {
                const bones = LoadBoneInfoGLTF(skin, &animations[a].boneCount);

                const animData = data.*.animations[a];

                const boneChannels: [*c]ChannelsGLTF = @ptrCast(@alignCast(RL_CALLOC(@intCast(animations[a].boneCount), @sizeOf(ChannelsGLTF))));
                var animDuration: f32 = 0.0;

                var j: c_uint = 0;
                while (j < animData.channels_count) : (j += 1) {
                    const channel = animData.channels[j];
                    var boneIndex: c_int = -1;

                    var kk: c_uint = 0;
                    while (kk < skin.joints_count) : (kk += 1) {
                        if (animData.channels[j].target_node == skin.joints[kk]) {
                            boneIndex = @intCast(kk);
                            break;
                        }
                    }

                    if (boneIndex == -1) continue;

                    const ubi: usize = @intCast(boneIndex);

                    if (animData.channels[j].sampler.*.interpolation != cgltf_interpolation_type_max_enum) {
                        if (channel.target_path == cgltf_animation_path_type_translation) {
                            boneChannels[ubi].translate = &animData.channels[j];
                        } else if (channel.target_path == cgltf_animation_path_type_rotation) {
                            boneChannels[ubi].rotate = &animData.channels[j];
                        } else if (channel.target_path == cgltf_animation_path_type_scale) {
                            boneChannels[ubi].scale = &animData.channels[j];
                        } else {
                            TraceLog(LOG_WARNING, "MODEL: [%s] Unsupported target_path on channel %d's sampler for animation %d. Skipping.", fileName, j, a);
                        }
                    } else TraceLog(LOG_WARNING, "MODEL: [%s] Invalid interpolation curve encountered for GLTF animation.", fileName);

                    var time: f32 = 0.0;
                    const r = cgltf_accessor_read_float(channel.sampler.*.input, channel.sampler.*.input.*.count - 1, &time, 1);

                    if (r == 0) {
                        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load input time", fileName);
                        continue;
                    }

                    animDuration = if (time > animDuration) time else animDuration;
                }

                if (animData.name != null) _ = strncpy(&animations[a].name, animData.name, animations[a].name.len - 1);

                animations[a].keyframeCount = @as(c_int, @intFromFloat(animDuration * GLTF_FRAMERATE)) + 1;
                animations[a].keyframePoses = @ptrCast(@alignCast(RL_CALLOC(@intCast(animations[a].keyframeCount), @sizeOf(ModelAnimPose))));

                var jf: c_int = 0;
                while (jf < animations[a].keyframeCount) : (jf += 1) {
                    const ujf: usize = @intCast(jf);
                    animations[a].keyframePoses[ujf] = @ptrCast(@alignCast(RL_CALLOC(@intCast(animations[a].boneCount), @sizeOf(Transform))));
                    const time = @as(f32, @floatFromInt(jf)) / GLTF_FRAMERATE;

                    var kb: c_int = 0;
                    while (kb < animations[a].boneCount) : (kb += 1) {
                        const ukb: usize = @intCast(kb);
                        const jtr = skin.joints[ukb].*.translation;
                        const jro = skin.joints[ukb].*.rotation;
                        const jsc = skin.joints[ukb].*.scale;
                        var translation = Vector3{ .x = jtr[0], .y = jtr[1], .z = jtr[2] };
                        var rotation = Quaternion{ .x = jro[0], .y = jro[1], .z = jro[2], .w = jro[3] };
                        var scale = Vector3{ .x = jsc[0], .y = jsc[1], .z = jsc[2] };

                        if (boneChannels[ukb].translate != null) {
                            if (!GetPoseAtTimeGLTF(boneChannels[ukb].translate.*.sampler.*.interpolation, boneChannels[ukb].translate.*.sampler.*.input, boneChannels[ukb].translate.*.sampler.*.output, time, &translation)) {
                                TraceLog(LOG_INFO, "MODEL: [%s] Failed to load translate pose data for bone %s", fileName, &bones[ukb].name);
                            }
                        }

                        if (boneChannels[ukb].rotate != null) {
                            if (!GetPoseAtTimeGLTF(boneChannels[ukb].rotate.*.sampler.*.interpolation, boneChannels[ukb].rotate.*.sampler.*.input, boneChannels[ukb].rotate.*.sampler.*.output, time, &rotation)) {
                                TraceLog(LOG_INFO, "MODEL: [%s] Failed to load rotate pose data for bone %s", fileName, &bones[ukb].name);
                            }
                        }

                        if (boneChannels[ukb].scale != null) {
                            if (!GetPoseAtTimeGLTF(boneChannels[ukb].scale.*.sampler.*.interpolation, boneChannels[ukb].scale.*.sampler.*.input, boneChannels[ukb].scale.*.sampler.*.output, time, &scale)) {
                                TraceLog(LOG_INFO, "MODEL: [%s] Failed to load scale pose data for bone %s", fileName, &bones[ukb].name);
                            }
                        }

                        const S = MatrixScale(scale.x, scale.y, scale.z);
                        const R = QuaternionToMatrix(rotation);
                        const T = MatrixTranslate(translation.x, translation.y, translation.z);
                        const jointLocal = MatrixMultiply(MatrixMultiply(S, R), T);
                        const combined = MatrixMultiply(jointLocal, extOffset[ukb]);

                        var tr: Transform = undefined;
                        MatrixDecompose(combined, &tr.translation, &tr.rotation, &tr.scale);
                        animations[a].keyframePoses[ujf][ukb] = tr;
                    }

                    BuildPoseFromParentJoints(bones, @bitCast(animations[a].boneCount), animations[a].keyframePoses[ujf]);
                }

                TraceLog(LOG_INFO, "MODEL: [%s] Loaded animation: %s | Frames: %d | Duration: %fs", fileName, if (animData.name != null) @as([*c]const u8, animData.name) else @as([*c]const u8, "NULL"), animations[a].keyframeCount, animDuration);
                RL_FREE(boneChannels);
                RL_FREE(bones);
            }

            RL_FREE(extOffset);
        }

        if (data.*.skins_count > 1) {
            TraceLog(LOG_WARNING, "MODEL: [%s] Expected one unique skin to load animation data from, but found %i", fileName, data.*.skins_count);
        }

        cgltf_free(data);
    }

    UnloadFileData(fileData);

    return animations;
}

//----------------------------------------------------------------------------------
// VOX loader
//----------------------------------------------------------------------------------

// Load VOX (MagicaVoxel) mesh data
fn LoadVOX(fileName: [*c]const u8) Model {
    var model = std.mem.zeroes(Model);

    var nbvertices: c_int = 0;
    var meshescount: c_int = 0;

    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);

    if (fileData == null) {
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load VOX file", fileName);
        return model;
    }

    var voxarray = std.mem.zeroes(VoxArray3D);
    const ret = Vox_LoadFromMemory(fileData, @intCast(dataSize), &voxarray);

    if (ret != VOX_SUCCESS) {
        UnloadFileData(fileData);
        TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load VOX data", fileName);
        return model;
    } else {
        nbvertices = voxarray.vertices.used;
        meshescount = 1 + @divTrunc(nbvertices, 65536);
        TraceLog(LOG_INFO, "MODEL: [%s] VOX data loaded successfully : %i vertices/%i meshes", fileName, nbvertices, meshescount);
    }

    model.transform = MatrixIdentity();

    model.meshCount = meshescount;
    model.meshes = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(Mesh))));

    model.meshMaterial = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(c_int))));

    model.materialCount = 1;
    model.materials = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.materialCount), @sizeOf(Material))));
    model.materials[0] = LoadMaterialDefault();

    var verticesRemain: c_int = voxarray.vertices.used;
    const verticesMax: c_int = 65532;

    var pvertices: [*c]VoxVector3 = voxarray.vertices.array;
    var pnormals: [*c]VoxVector3 = voxarray.normals.array;
    var pcolors: [*c]VoxColor = voxarray.colors.array;

    const pindices: [*c]c_ushort = voxarray.indices.array;

    var size: c_int = 0;

    var i: c_int = 0;
    while (i < meshescount) : (i += 1) {
        const pmesh = &model.meshes[@intCast(i)];
        _ = memset(pmesh, 0, @sizeOf(Mesh));

        pmesh.vertexCount = @intFromFloat(fmin(@floatFromInt(verticesMax), @floatFromInt(verticesRemain)));

        size = pmesh.vertexCount * @sizeOf(f32) * 3;
        pmesh.vertices = @ptrCast(@alignCast(RL_MALLOC(@intCast(size))));
        _ = memcpy(pmesh.vertices, pvertices, @intCast(size));

        pmesh.normals = @ptrCast(@alignCast(RL_MALLOC(@intCast(size))));
        _ = memcpy(pmesh.normals, pnormals, @intCast(size));

        size = voxarray.indices.used * @sizeOf(c_ushort);
        pmesh.indices = @ptrCast(@alignCast(RL_MALLOC(@intCast(size))));
        _ = memcpy(pmesh.indices, pindices, @intCast(size));

        pmesh.triangleCount = @divTrunc(pmesh.vertexCount, 4) * 2;

        size = pmesh.vertexCount * @sizeOf(Color);
        pmesh.colors = @ptrCast(@alignCast(RL_MALLOC(@intCast(size))));
        _ = memcpy(pmesh.colors, pcolors, @intCast(size));

        model.meshMaterial[@intCast(i)] = 0;

        verticesRemain -= verticesMax;
        pvertices += @intCast(verticesMax);
        pnormals += @intCast(verticesMax);
        pcolors += @intCast(verticesMax);
    }

    Vox_FreeArrays(&voxarray);
    UnloadFileData(fileData);

    return model;
}

//----------------------------------------------------------------------------------
// M3D loader
//----------------------------------------------------------------------------------

// Hook LoadFileData()/UnloadFileData() calls to M3D loaders
fn m3d_loaderhook(fn_: [*c]u8, len: [*c]c_uint) callconv(.c) [*c]u8 {
    return LoadFileData(fn_, @ptrCast(len));
}
fn m3d_freehook(data: ?*anyopaque) callconv(.c) void {
    UnloadFileData(@ptrCast(data));
}

const M3D_ANIMDELAY: u32 = 17;

// Load M3D mesh data
fn LoadM3D(fileName: [*c]const u8) Model {
    var model = std.mem.zeroes(Model);

    var m3d: [*c]m3d_t = null;
    var prop: [*c]m3dp_t = null;
    var i: c_int = 0;
    var j: c_int = 0;
    var k: c_int = -1;
    var l: c_int = 0;
    var n: c_int = 0;
    var mi: c_int = -2;
    var vcolor: c_int = 0;

    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);

    if (fileData != null) {
        m3d = m3d_load(fileData, m3d_loaderhook, m3d_freehook, null);

        if ((m3d == null) or M3D_ERR_ISFATAL(m3d.*.errcode)) {
            TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load M3D data, error code %d", fileName, if (m3d != null) @as(c_int, m3d.*.errcode) else -2);
            if (m3d != null) m3d_free(m3d);
            UnloadFileData(fileData);
            return model;
        } else TraceLog(LOG_INFO, "MODEL: [%s] M3D data loaded successfully: %i faces/%i materials", fileName, m3d.*.numface, m3d.*.nummaterial);

        if (m3d.*.numface == 0) {
            m3d_free(m3d);
            UnloadFileData(fileData);
            return model;
        }

        if (m3d.*.nummaterial > 0) {
            model.meshCount = @intCast(m3d.*.nummaterial);
            model.materialCount = @intCast(m3d.*.nummaterial);
            TraceLog(LOG_INFO, "MODEL: model has %i material meshes", model.materialCount);
        } else {
            model.meshCount = 1;
            model.materialCount = 0;
            TraceLog(LOG_INFO, "MODEL: No materials, putting all meshes in a default material");
        }

        model.materialCount += 1;

        model.meshes = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(Mesh))));
        model.meshMaterial = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(c_int))));
        model.materials = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.materialCount + 1), @sizeOf(Material))));

        model.materials[0] = LoadMaterialDefault();

        i = 0;
        l = 0;
        k = -1;
        while (i < @as(c_int, @intCast(m3d.*.numface))) : ({
            i += 1;
            l += 1;
        }) {
            if (mi != @as(c_int, @bitCast(m3d.*.face[@intCast(i)].materialid))) {
                if (k + 1 >= model.meshCount) {
                    model.meshCount += 1;

                    const tempMeshes: [*c]Mesh = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(Mesh))));
                    _ = memcpy(tempMeshes, model.meshes, @intCast((model.meshCount - 1) * @sizeOf(Mesh)));
                    RL_FREE(model.meshes);
                    model.meshes = tempMeshes;

                    const tempMeshMaterial: [*c]c_int = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshCount), @sizeOf(c_int))));
                    _ = memcpy(tempMeshMaterial, model.meshMaterial, @intCast((model.meshCount - 1) * @sizeOf(c_int)));
                    RL_FREE(model.meshMaterial);
                    model.meshMaterial = tempMeshMaterial;
                }

                k += 1;
                mi = @bitCast(m3d.*.face[@intCast(i)].materialid);

                j = i;
                l = 0;
                vcolor = 0;
                while ((j < @as(c_int, @intCast(m3d.*.numface))) and (mi == @as(c_int, @bitCast(m3d.*.face[@intCast(j)].materialid)))) : ({
                    j += 1;
                    l += 1;
                }) {
                    if ((m3d.*.vertex[m3d.*.face[@intCast(j)].vertex[0]].color == 0) or
                        (m3d.*.vertex[m3d.*.face[@intCast(j)].vertex[1]].color == 0) or
                        (m3d.*.vertex[m3d.*.face[@intCast(j)].vertex[2]].color == 0)) vcolor = 1;
                }

                const uk: usize = @intCast(k);
                model.meshes[uk].vertexCount = l * 3;
                model.meshes[uk].triangleCount = l;
                model.meshes[uk].vertices = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[uk].vertexCount * 3), @sizeOf(f32))));
                model.meshes[uk].texcoords = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[uk].vertexCount * 2), @sizeOf(f32))));
                model.meshes[uk].normals = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[uk].vertexCount * 3), @sizeOf(f32))));

                if ((mi == @as(c_int, @bitCast(M3D_UNDEF))) or (vcolor != 0)) model.meshes[uk].colors = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[uk].vertexCount * 4), @sizeOf(u8))));

                if ((mi == @as(c_int, @bitCast(M3D_UNDEF))) and (model.meshes[uk].colors != null)) {
                    var c: c_int = 0;
                    while (c < model.meshes[uk].vertexCount * 4) : (c += 1) model.meshes[uk].colors[@intCast(c)] = 255;
                }

                if ((m3d.*.numbone != 0) and (m3d.*.numskin != 0)) {
                    model.meshes[uk].boneIndices = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[uk].vertexCount * 4), @sizeOf(u8))));
                    model.meshes[uk].boneWeights = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.meshes[uk].vertexCount * 4), @sizeOf(f32))));
                }

                model.meshMaterial[uk] = mi + 1;
                l = 0;
            }

            const uk: usize = @intCast(k);
            const ul: usize = @intCast(l);
            const ui: usize = @intCast(i);
            const scale = m3d.*.scale;

            model.meshes[uk].vertices[ul * 9 + 0] = m3d.*.vertex[m3d.*.face[ui].vertex[0]].x * scale;
            model.meshes[uk].vertices[ul * 9 + 1] = m3d.*.vertex[m3d.*.face[ui].vertex[0]].y * scale;
            model.meshes[uk].vertices[ul * 9 + 2] = m3d.*.vertex[m3d.*.face[ui].vertex[0]].z * scale;
            model.meshes[uk].vertices[ul * 9 + 3] = m3d.*.vertex[m3d.*.face[ui].vertex[1]].x * scale;
            model.meshes[uk].vertices[ul * 9 + 4] = m3d.*.vertex[m3d.*.face[ui].vertex[1]].y * scale;
            model.meshes[uk].vertices[ul * 9 + 5] = m3d.*.vertex[m3d.*.face[ui].vertex[1]].z * scale;
            model.meshes[uk].vertices[ul * 9 + 6] = m3d.*.vertex[m3d.*.face[ui].vertex[2]].x * scale;
            model.meshes[uk].vertices[ul * 9 + 7] = m3d.*.vertex[m3d.*.face[ui].vertex[2]].y * scale;
            model.meshes[uk].vertices[ul * 9 + 8] = m3d.*.vertex[m3d.*.face[ui].vertex[2]].z * scale;

            if (model.meshes[uk].colors != null) {
                if (m3d.*.vertex[m3d.*.face[ui].vertex[0]].color & 0xff000000 != 0)
                    _ = memcpy(&model.meshes[uk].colors[ul * 12 + 0], &m3d.*.vertex[m3d.*.face[ui].vertex[0]].color, 4);
                if (m3d.*.vertex[m3d.*.face[ui].vertex[1]].color & 0xff000000 != 0)
                    _ = memcpy(&model.meshes[uk].colors[ul * 12 + 4], &m3d.*.vertex[m3d.*.face[ui].vertex[1]].color, 4);
                if (m3d.*.vertex[m3d.*.face[ui].vertex[2]].color & 0xff000000 != 0)
                    _ = memcpy(&model.meshes[uk].colors[ul * 12 + 8], &m3d.*.vertex[m3d.*.face[ui].vertex[2]].color, 4);
            }

            if (m3d.*.face[ui].texcoord[0] != M3D_UNDEF) {
                model.meshes[uk].texcoords[ul * 6 + 0] = m3d.*.tmap[m3d.*.face[ui].texcoord[0]].u;
                model.meshes[uk].texcoords[ul * 6 + 1] = 1.0 - m3d.*.tmap[m3d.*.face[ui].texcoord[0]].v;
                model.meshes[uk].texcoords[ul * 6 + 2] = m3d.*.tmap[m3d.*.face[ui].texcoord[1]].u;
                model.meshes[uk].texcoords[ul * 6 + 3] = 1.0 - m3d.*.tmap[m3d.*.face[ui].texcoord[1]].v;
                model.meshes[uk].texcoords[ul * 6 + 4] = m3d.*.tmap[m3d.*.face[ui].texcoord[2]].u;
                model.meshes[uk].texcoords[ul * 6 + 5] = 1.0 - m3d.*.tmap[m3d.*.face[ui].texcoord[2]].v;
            }

            if (m3d.*.face[ui].normal[0] != M3D_UNDEF) {
                model.meshes[uk].normals[ul * 9 + 0] = m3d.*.vertex[m3d.*.face[ui].normal[0]].x;
                model.meshes[uk].normals[ul * 9 + 1] = m3d.*.vertex[m3d.*.face[ui].normal[0]].y;
                model.meshes[uk].normals[ul * 9 + 2] = m3d.*.vertex[m3d.*.face[ui].normal[0]].z;
                model.meshes[uk].normals[ul * 9 + 3] = m3d.*.vertex[m3d.*.face[ui].normal[1]].x;
                model.meshes[uk].normals[ul * 9 + 4] = m3d.*.vertex[m3d.*.face[ui].normal[1]].y;
                model.meshes[uk].normals[ul * 9 + 5] = m3d.*.vertex[m3d.*.face[ui].normal[1]].z;
                model.meshes[uk].normals[ul * 9 + 6] = m3d.*.vertex[m3d.*.face[ui].normal[2]].x;
                model.meshes[uk].normals[ul * 9 + 7] = m3d.*.vertex[m3d.*.face[ui].normal[2]].y;
                model.meshes[uk].normals[ul * 9 + 8] = m3d.*.vertex[m3d.*.face[ui].normal[2]].z;
            }

            if ((m3d.*.numbone != 0) and (m3d.*.numskin != 0)) {
                n = 0;
                while (n < 3) : (n += 1) {
                    const skinid = m3d.*.vertex[m3d.*.face[ui].vertex[@intCast(n)]].skinid;

                    if ((skinid != M3D_UNDEF) and (skinid < m3d.*.numskin)) {
                        var jj: c_int = 0;
                        while (jj < 4) : (jj += 1) {
                            // C truncates: unused slots of the 4-bone skin hold
                            // M3D_UNDEF (0xFFFFFFFF) -> 255 in the u8 bone array.
                            model.meshes[uk].boneIndices[ul * 12 + @as(usize, @intCast(n)) * 4 + @as(usize, @intCast(jj))] = @truncate(m3d.*.skin[skinid].boneid[@intCast(jj)]);
                            model.meshes[uk].boneWeights[ul * 12 + @as(usize, @intCast(n)) * 4 + @as(usize, @intCast(jj))] = m3d.*.skin[skinid].weight[@intCast(jj)];
                        }
                    } else {
                        model.meshes[uk].boneIndices[ul * 12 + @as(usize, @intCast(n)) * 4] = @truncate(m3d.*.numbone);
                        model.meshes[uk].boneWeights[ul * 12 + @as(usize, @intCast(n)) * 4] = 1.0;
                    }
                }
            }
        }

        // Load materials
        i = 0;
        while (i < @as(c_int, @intCast(m3d.*.nummaterial))) : (i += 1) {
            const ui: usize = @intCast(i);
            model.materials[ui + 1] = LoadMaterialDefault();

            j = 0;
            while (j < m3d.*.material[ui].numprop) : (j += 1) {
                prop = &m3d.*.material[ui].prop[@intCast(j)];

                switch (prop.*.type) {
                    m3dp_Kd => {
                        _ = memcpy(&model.materials[ui + 1].maps[MATERIAL_MAP_DIFFUSE].color, &prop.*.value.color, 4);
                        model.materials[ui + 1].maps[MATERIAL_MAP_DIFFUSE].value = 0.0;
                    },
                    m3dp_Ks => {
                        _ = memcpy(&model.materials[ui + 1].maps[MATERIAL_MAP_SPECULAR].color, &prop.*.value.color, 4);
                    },
                    m3dp_Ns => {
                        model.materials[ui + 1].maps[MATERIAL_MAP_SPECULAR].value = prop.*.value.fnum;
                    },
                    m3dp_Ke => {
                        _ = memcpy(&model.materials[ui + 1].maps[MATERIAL_MAP_EMISSION].color, &prop.*.value.color, 4);
                        model.materials[ui + 1].maps[MATERIAL_MAP_EMISSION].value = 0.0;
                    },
                    m3dp_Pm => {
                        model.materials[ui + 1].maps[MATERIAL_MAP_METALNESS].value = prop.*.value.fnum;
                    },
                    m3dp_Pr => {
                        model.materials[ui + 1].maps[MATERIAL_MAP_ROUGHNESS].value = prop.*.value.fnum;
                    },
                    m3dp_Ps => {
                        model.materials[ui + 1].maps[MATERIAL_MAP_NORMAL].color = WHITE;
                        model.materials[ui + 1].maps[MATERIAL_MAP_NORMAL].value = prop.*.value.fnum;
                    },
                    else => {
                        if (prop.*.type >= 128) {
                            var image = std.mem.zeroes(Image);
                            const tex = &m3d.*.texture[prop.*.value.textureid];
                            image.data = tex.d;
                            image.width = tex.w;
                            image.height = tex.h;
                            image.mipmaps = 1;
                            image.format = if (tex.f == 4) PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 else if (tex.f == 3) PIXELFORMAT_UNCOMPRESSED_R8G8B8 else if (tex.f == 2) PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA else PIXELFORMAT_UNCOMPRESSED_GRAYSCALE;

                            switch (prop.*.type) {
                                m3dp_map_Kd => model.materials[ui + 1].maps[MATERIAL_MAP_DIFFUSE].texture = LoadTextureFromImage(image),
                                m3dp_map_Ks => model.materials[ui + 1].maps[MATERIAL_MAP_SPECULAR].texture = LoadTextureFromImage(image),
                                m3dp_map_Ke => model.materials[ui + 1].maps[MATERIAL_MAP_EMISSION].texture = LoadTextureFromImage(image),
                                m3dp_map_Km => model.materials[ui + 1].maps[MATERIAL_MAP_NORMAL].texture = LoadTextureFromImage(image),
                                m3dp_map_Ka => model.materials[ui + 1].maps[MATERIAL_MAP_OCCLUSION].texture = LoadTextureFromImage(image),
                                m3dp_map_Pm => model.materials[ui + 1].maps[MATERIAL_MAP_ROUGHNESS].texture = LoadTextureFromImage(image),
                                else => {},
                            }
                        }
                    },
                }
            }
        }

        // Load bones
        if (m3d.*.numbone != 0) {
            model.skeleton.boneCount = m3d.*.numbone +% 1;
            model.skeleton.bones = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.skeleton.boneCount), @sizeOf(BoneInfo))));
            model.skeleton.bindPose = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.skeleton.boneCount), @sizeOf(Transform))));

            i = 0;
            while (i < @as(c_int, @intCast(m3d.*.numbone))) : (i += 1) {
                const ui: usize = @intCast(i);
                model.skeleton.bones[ui].parent = @bitCast(m3d.*.bone[ui].parent);
                _ = strncpy(&model.skeleton.bones[ui].name, m3d.*.bone[ui].name, model.skeleton.bones[ui].name.len - 1);
                model.skeleton.bindPose[ui].translation.x = m3d.*.vertex[m3d.*.bone[ui].pos].x * m3d.*.scale;
                model.skeleton.bindPose[ui].translation.y = m3d.*.vertex[m3d.*.bone[ui].pos].y * m3d.*.scale;
                model.skeleton.bindPose[ui].translation.z = m3d.*.vertex[m3d.*.bone[ui].pos].z * m3d.*.scale;
                model.skeleton.bindPose[ui].rotation.x = m3d.*.vertex[m3d.*.bone[ui].ori].x;
                model.skeleton.bindPose[ui].rotation.y = m3d.*.vertex[m3d.*.bone[ui].ori].y;
                model.skeleton.bindPose[ui].rotation.z = m3d.*.vertex[m3d.*.bone[ui].ori].z;
                model.skeleton.bindPose[ui].rotation.w = m3d.*.vertex[m3d.*.bone[ui].ori].w;

                model.skeleton.bindPose[ui].rotation = QuaternionNormalize(model.skeleton.bindPose[ui].rotation);
                model.skeleton.bindPose[ui].scale.x = 1.0;
                model.skeleton.bindPose[ui].scale.y = 1.0;
                model.skeleton.bindPose[ui].scale.z = 1.0;

                if (model.skeleton.bones[ui].parent >= 0) {
                    const pp: usize = @intCast(model.skeleton.bones[ui].parent);
                    model.skeleton.bindPose[ui].rotation = QuaternionMultiply(model.skeleton.bindPose[pp].rotation, model.skeleton.bindPose[ui].rotation);
                    model.skeleton.bindPose[ui].translation = Vector3RotateByQuaternion(model.skeleton.bindPose[ui].translation, model.skeleton.bindPose[pp].rotation);
                    model.skeleton.bindPose[ui].translation = Vector3Add(model.skeleton.bindPose[ui].translation, model.skeleton.bindPose[pp].translation);
                    model.skeleton.bindPose[ui].scale = Vector3Multiply(model.skeleton.bindPose[ui].scale, model.skeleton.bindPose[pp].scale);
                }
            }

            // Add a special "no bone" bone
            const uin: usize = @intCast(i);
            model.skeleton.bones[uin].parent = -1;
            _ = memcpy(&model.skeleton.bones[uin].name, "NO BONE", 7);
            model.skeleton.bindPose[uin].translation.x = 0.0;
            model.skeleton.bindPose[uin].translation.y = 0.0;
            model.skeleton.bindPose[uin].translation.z = 0.0;
            model.skeleton.bindPose[uin].rotation.x = 0.0;
            model.skeleton.bindPose[uin].rotation.y = 0.0;
            model.skeleton.bindPose[uin].rotation.z = 0.0;
            model.skeleton.bindPose[uin].rotation.w = 1.0;
            model.skeleton.bindPose[uin].scale.x = 1.0;
            model.skeleton.bindPose[uin].scale.y = 1.0;
            model.skeleton.bindPose[uin].scale.z = 1.0;
        }

        if ((m3d.*.numbone != 0) and (m3d.*.numskin != 0)) {
            i = 0;
            while (i < model.meshCount) : (i += 1) {
                const ui: usize = @intCast(i);
                model.meshes[ui].boneCount = @bitCast(model.skeleton.boneCount);
            }

            model.currentPose = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.skeleton.boneCount), @sizeOf(Transform))));
            model.boneMatrices = @ptrCast(@alignCast(RL_CALLOC(@intCast(model.skeleton.boneCount), @sizeOf(Matrix))));
            j = 0;
            while (j < model.skeleton.boneCount) : (j += 1) model.boneMatrices[@intCast(j)] = MatrixIdentity();
        }

        m3d_free(m3d);
        UnloadFileData(fileData);
    }

    return model;
}

// Load M3D animation data
fn LoadModelAnimationsM3D(fileName: [*c]const u8, animCount: [*c]c_int) [*c]ModelAnimation {
    var animations: [*c]ModelAnimation = null;

    var m3d: [*c]m3d_t = null;
    var i: c_int = 0;
    var j: c_int = 0;
    animCount.* = 0;

    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);

    if (fileData != null) {
        m3d = m3d_load(fileData, m3d_loaderhook, m3d_freehook, null);

        if ((m3d == null) or M3D_ERR_ISFATAL(m3d.*.errcode)) {
            TraceLog(LOG_WARNING, "MODEL: [%s] Failed to load M3D data, error code %d", fileName, if (m3d != null) @as(c_int, m3d.*.errcode) else -2);
            UnloadFileData(fileData);
            return null;
        } else TraceLog(LOG_INFO, "MODEL: [%s] M3D data loaded successfully: %i animations, %i bones, %i skins", fileName, m3d.*.numaction, m3d.*.numbone, m3d.*.numskin);

        if ((m3d.*.numaction == 0) or (m3d.*.numbone == 0)) {
            m3d_free(m3d);
            UnloadFileData(fileData);
            return null;
        }

        animations = @ptrCast(@alignCast(RL_CALLOC(m3d.*.numaction, @sizeOf(ModelAnimation))));
        animCount.* = @intCast(m3d.*.numaction);

        var a: c_uint = 0;
        while (a < m3d.*.numaction) : (a += 1) {
            animations[a].boneCount = m3d.*.numbone +% 1;
            const bones: [*c]BoneInfo = @ptrCast(@alignCast(RL_CALLOC(m3d.*.numbone + 1, @sizeOf(BoneInfo))));

            animations[a].keyframeCount = @intCast(m3d.*.action[a].durationmsec / M3D_ANIMDELAY);
            animations[a].keyframePoses = @ptrCast(@alignCast(RL_CALLOC(@intCast(animations[a].keyframeCount), @sizeOf(ModelAnimPose))));
            _ = strncpy(&animations[a].name, m3d.*.action[a].name, animations[a].name.len - 1);

            TraceLog(LOG_INFO, "MODEL: [%s] Loaded animation: %s | Frames: %d | Duration: %fs", fileName, &animations[a].name, animations[a].keyframeCount, m3d.*.action[a].durationmsec);

            i = 0;
            while (i < @as(c_int, @intCast(m3d.*.numbone))) : (i += 1) {
                const ui: usize = @intCast(i);
                bones[ui].parent = @bitCast(m3d.*.bone[ui].parent);
                _ = strncpy(&bones[ui].name, m3d.*.bone[ui].name, bones[ui].name.len - 1);
            }

            const uin: usize = @intCast(i);
            bones[uin].parent = -1;
            _ = memcpy(&bones[uin].name, "NO BONE", 7);

            i = 0;
            while (i < animations[a].keyframeCount) : (i += 1) {
                const ui: usize = @intCast(i);
                animations[a].keyframePoses[ui] = @ptrCast(@alignCast(RL_CALLOC(@intCast(m3d.*.numbone + 1), @sizeOf(Transform))));

                const pose = m3d_pose(m3d, a, @as(u32, @intCast(i)) * M3D_ANIMDELAY);

                if (pose != null) {
                    j = 0;
                    while (j < @as(c_int, @intCast(m3d.*.numbone))) : (j += 1) {
                        const uj: usize = @intCast(j);
                        const kp = &animations[a].keyframePoses[ui][uj];
                        kp.translation.x = m3d.*.vertex[pose[uj].pos].x * m3d.*.scale;
                        kp.translation.y = m3d.*.vertex[pose[uj].pos].y * m3d.*.scale;
                        kp.translation.z = m3d.*.vertex[pose[uj].pos].z * m3d.*.scale;
                        kp.rotation.x = m3d.*.vertex[pose[uj].ori].x;
                        kp.rotation.y = m3d.*.vertex[pose[uj].ori].y;
                        kp.rotation.z = m3d.*.vertex[pose[uj].ori].z;
                        kp.rotation.w = m3d.*.vertex[pose[uj].ori].w;
                        kp.rotation = QuaternionNormalize(kp.rotation);
                        kp.scale.x = 1.0;
                        kp.scale.y = 1.0;
                        kp.scale.z = 1.0;

                        if (bones[uj].parent >= 0) {
                            const pp: usize = @intCast(bones[uj].parent);
                            kp.rotation = QuaternionMultiply(animations[a].keyframePoses[ui][pp].rotation, kp.rotation);
                            kp.translation = Vector3RotateByQuaternion(kp.translation, animations[a].keyframePoses[ui][pp].rotation);
                            kp.translation = Vector3Add(kp.translation, animations[a].keyframePoses[ui][pp].translation);
                            kp.scale = Vector3Multiply(kp.scale, animations[a].keyframePoses[ui][pp].scale);
                        }
                    }

                    const uj: usize = @intCast(j);
                    const kp = &animations[a].keyframePoses[ui][uj];
                    kp.translation.x = 0.0;
                    kp.translation.y = 0.0;
                    kp.translation.z = 0.0;
                    kp.rotation.x = 0.0;
                    kp.rotation.y = 0.0;
                    kp.rotation.z = 0.0;
                    kp.rotation.w = 1.0;
                    kp.scale.x = 1.0;
                    kp.scale.y = 1.0;
                    kp.scale.z = 1.0;

                    RL_FREE(pose);
                }
            }

            RL_FREE(bones);
        }

        m3d_free(m3d);
        UnloadFileData(fileData);
    }

    return animations;
}
