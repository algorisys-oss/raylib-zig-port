//! rcore - Window/display, graphics-context and input management.
//!
//! Zig port of raylib's `rcore.c`. In C, rcore.c `#include`s one platform backend
//! (`platforms/rcore_<platform>.c`) and the two form one translation unit sharing the
//! file-global `CoreData CORE`. Here the backend is its own file under src/platforms/,
//! imported at comptime from the target (see `backend`): rcore_desktop_glfw.zig on the
//! desktop, rcore_web.zig on Emscripten. The backend imports this file back for `CORE`
//! and the helpers both halves use.
//!
//! Every public raylib window/input/timing/data/file/shader function is exported with its
//! exact C name, byte-compatible signature and C calling convention, so the rest of raylib
//! (still C) links against it unchanged.
//!
//! GLFW, rlgl, raymath, rgestures and rcamera are still C/other-Zig-modules and are
//! `extern`-declared. The compression (sdefl/sinfl) and random (rprand) single-file libs
//! are instantiated by `src/c/rcore_impl.c` and reached via extern.
//!
//! `CoreData CORE` is global but read only by rcore+platform, so it is modelled as a private
//! Zig struct (layout is ours, every sub-field mirrored faithfully).

const std = @import("std");
const builtin = @import("builtin");
const c_va = @import("c_va.zig");
const fs = @import("fs.zig");
const automation = @import("automation.zig");
const cmem = @import("cmem.zig");

/// The platform backend: rcore.c `#include`s one `platforms/rcore_<platform>.c`, and
/// rcore.zig imports one of these. Emscripten means the browser (PLATFORM_WEB, on
/// Emscripten's GLFW); everything else is the desktop GLFW backend.
const backend = switch (builtin.os.tag) {
    .emscripten => @import("platforms/rcore_web.zig"),
    else => @import("platforms/rcore_desktop_glfw.zig"),
};
comptime {
    _ = backend; // its exports are part of this module's C ABI
}
const ClosePlatform = backend.ClosePlatform;
const GetTime = backend.GetTime;
const GetWindowScaleDPI = backend.GetWindowScaleDPI;
const InitPlatform = backend.InitPlatform;
const MaximizeWindow = backend.MaximizeWindow;
const MinimizeWindow = backend.MinimizeWindow;
const PollInputEvents = backend.PollInputEvents;
const SetWindowSize = backend.SetWindowSize;
const SwapScreenBuffer = backend.SwapScreenBuffer;

//----------------------------------------------------------------------------------
// libc: what rcore still needs from C, and why
//----------------------------------------------------------------------------------
// TraceLog formats a caller's printf string with its C variadic arguments
extern fn vprintf([*c]const u8, c_va.Arg) c_int;
extern fn fflush(?*anyopaque) c_int;
// The process clock comes from libc (time, std.c.clock_gettime, std.c.nanosleep),
// not std.Io: the examples gate freezes it by preloading those libc symbols
// (tools/exdiff/fakeclock.c)
extern fn time(?*std.c.time_t) std.c.time_t;
const timespec = std.c.timespec;
// The same libm as C, for bit-exact results (CLAUDE.md, "Float bit-exactness")
extern fn tan(f64) f64;
extern fn atan2f(f32, f32) f32;

//----------------------------------------------------------------------------------
// Public ABI structs (extern struct, exact layout matching raylib.h)
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
pub const RenderTexture = extern struct {
    id: c_uint,
    texture: Texture,
    depth: Texture,
};
pub const RenderTexture2D = RenderTexture;
pub const Shader = extern struct {
    id: c_uint,
    locs: [*c]c_int,
};
pub const Ray = extern struct {
    position: Vector3,
    direction: Vector3,
};
pub const Camera3D = extern struct {
    position: Vector3,
    target: Vector3,
    up: Vector3,
    fovy: f32,
    projection: c_int,
};
pub const Camera = Camera3D;
pub const Camera2D = extern struct {
    offset: Vector2,
    target: Vector2,
    rotation: f32,
    zoom: f32,
};
pub const VrDeviceInfo = extern struct {
    hResolution: c_int,
    vResolution: c_int,
    hScreenSize: f32,
    vScreenSize: f32,
    eyeToScreenDistance: f32,
    lensSeparationDistance: f32,
    interpupillaryDistance: f32,
    lensDistortionValues: [4]f32,
    chromaAbCorrection: [4]f32,
};
pub const VrStereoConfig = extern struct {
    projection: [2]Matrix,
    viewOffset: [2]Matrix,
    leftLensCenter: [2]f32,
    rightLensCenter: [2]f32,
    leftScreenCenter: [2]f32,
    rightScreenCenter: [2]f32,
    scale: [2]f32,
    scaleIn: [2]f32,
};
pub const FilePathList = extern struct {
    count: c_uint,
    paths: [*c][*c]u8,
};
pub const AutomationEvent = automation.Event;
pub const AutomationEventList = extern struct {
    capacity: c_uint,
    count: c_uint,
    events: [*c]AutomationEvent,
};

const TraceLogCallback = ?*const fn (logLevel: c_int, text: [*c]const u8, args: *anyopaque) callconv(.c) void;
const LoadFileDataCallback = ?*const fn (fileName: [*c]const u8, dataSize: [*c]c_int) callconv(.c) [*c]u8;
const SaveFileDataCallback = ?*const fn (fileName: [*c]const u8, data: ?*anyopaque, dataSize: c_int) callconv(.c) bool;
const LoadFileTextCallback = ?*const fn (fileName: [*c]const u8) callconv(.c) [*c]u8;
const SaveFileTextCallback = ?*const fn (fileName: [*c]const u8, text: [*c]u8) callconv(.c) bool;

//----------------------------------------------------------------------------------
// Defines and Macros
//----------------------------------------------------------------------------------
const RAYLIB_VERSION = "6.2";

const MAX_TRACELOG_MSG_LENGTH: usize = 256;
const MAX_FILEPATH_CAPACITY: usize = 8192;
pub const MAX_FILEPATH_LENGTH: usize = 4096;
pub const MAX_KEYBOARD_KEYS: usize = 512;
pub const MAX_MOUSE_BUTTONS: usize = 8;
pub const MAX_GAMEPADS: usize = 4;
pub const MAX_GAMEPAD_NAME_LENGTH: usize = 128;
pub const MAX_GAMEPAD_AXES: usize = 8;
pub const MAX_GAMEPAD_BUTTONS: usize = 32;
pub const MAX_TOUCH_POINTS: usize = 8;
pub const MAX_KEY_PRESSED_QUEUE: usize = 16;
pub const MAX_CHAR_PRESSED_QUEUE: usize = 16;
const MAX_DECOMPRESSION_SIZE: usize = 64;
const MAX_AUTOMATION_EVENTS: usize = 16384;

const FILE_FILTER_TAG_ALL = "*.*";
const FILE_FILTER_TAG_FILE_ONLY = "FILES*";
const FILE_FILTER_TAG_DIR_ONLY = "DIRS*";

const PI: f32 = 3.14159265358979323846;
const DEG2RAD: f32 = PI / 180.0;

// TraceLogLevel
const LOG_ALL: c_int = 0;
const LOG_TRACE: c_int = 1;
const LOG_DEBUG: c_int = 2;
pub const LOG_INFO: c_int = 3;
pub const LOG_WARNING: c_int = 4;
const LOG_ERROR: c_int = 5;
pub const LOG_FATAL: c_int = 6;
const LOG_NONE: c_int = 7;

// ConfigFlags
pub const FLAG_VSYNC_HINT: c_uint = 0x00000040;
pub const FLAG_FULLSCREEN_MODE: c_uint = 0x00000002;
pub const FLAG_WINDOW_RESIZABLE: c_uint = 0x00000004;
pub const FLAG_WINDOW_UNDECORATED: c_uint = 0x00000008;
pub const FLAG_WINDOW_HIDDEN: c_uint = 0x00000080;
pub const FLAG_WINDOW_MINIMIZED: c_uint = 0x00000200;
pub const FLAG_WINDOW_MAXIMIZED: c_uint = 0x00000400;
pub const FLAG_WINDOW_UNFOCUSED: c_uint = 0x00000800;
pub const FLAG_WINDOW_TOPMOST: c_uint = 0x00001000;
pub const FLAG_WINDOW_ALWAYS_RUN: c_uint = 0x00000100;
pub const FLAG_WINDOW_TRANSPARENT: c_uint = 0x00000010;
pub const FLAG_WINDOW_HIGHDPI: c_uint = 0x00002000;
pub const FLAG_WINDOW_MOUSE_PASSTHROUGH: c_uint = 0x00004000;
pub const FLAG_BORDERLESS_WINDOWED_MODE: c_uint = 0x00008000;
pub const FLAG_MSAA_4X_HINT: c_uint = 0x00000020;
pub const FLAG_INTERLACED_HINT: c_uint = 0x00010000;

// Keys (subset used internally)
const KEY_ESCAPE: c_int = 256;
const KEY_F12: c_int = 301;
pub const KEY_CAPS_LOCK: c_int = 280;
pub const KEY_NUM_LOCK: c_int = 282;
const KEY_DOWN: c_int = 264;
const KEY_UP: c_int = 265;
const KEY_RIGHT: c_int = 262;
const KEY_LEFT: c_int = 263;
const KEY_Q: c_int = 81;
const KEY_E: c_int = 69;
const KEY_W: c_int = 87;
const KEY_A: c_int = 65;
const KEY_S: c_int = 83;
const KEY_D: c_int = 68;
const KEY_SPACE: c_int = 32;
const KEY_LEFT_CONTROL: c_int = 341;
const KEY_KP_SUBTRACT: c_int = 333;
const KEY_KP_ADD: c_int = 334;

// Mouse
const MOUSE_BUTTON_MIDDLE: c_int = 2;
const MOUSE_BUTTON_BACK: c_int = 6;
pub const MOUSE_CURSOR_DEFAULT: c_int = 0;
const MOUSE_CURSOR_ARROW: c_int = 1;

// Gamepad buttons (raylib enum values)
pub const GAMEPAD_BUTTON_UNKNOWN: c_int = 0;
pub const GAMEPAD_BUTTON_LEFT_FACE_UP: c_int = 1;
pub const GAMEPAD_BUTTON_LEFT_FACE_RIGHT: c_int = 2;
pub const GAMEPAD_BUTTON_LEFT_FACE_DOWN: c_int = 3;
pub const GAMEPAD_BUTTON_LEFT_FACE_LEFT: c_int = 4;
pub const GAMEPAD_BUTTON_RIGHT_FACE_UP: c_int = 5;
pub const GAMEPAD_BUTTON_RIGHT_FACE_RIGHT: c_int = 6;
pub const GAMEPAD_BUTTON_RIGHT_FACE_DOWN: c_int = 7;
pub const GAMEPAD_BUTTON_RIGHT_FACE_LEFT: c_int = 8;
pub const GAMEPAD_BUTTON_LEFT_TRIGGER_1: c_int = 9;
pub const GAMEPAD_BUTTON_LEFT_TRIGGER_2: c_int = 10;
pub const GAMEPAD_BUTTON_RIGHT_TRIGGER_1: c_int = 11;
pub const GAMEPAD_BUTTON_RIGHT_TRIGGER_2: c_int = 12;
pub const GAMEPAD_BUTTON_MIDDLE_LEFT: c_int = 13;
pub const GAMEPAD_BUTTON_MIDDLE: c_int = 14;
pub const GAMEPAD_BUTTON_MIDDLE_RIGHT: c_int = 15;
pub const GAMEPAD_BUTTON_LEFT_THUMB: c_int = 16;
pub const GAMEPAD_BUTTON_RIGHT_THUMB: c_int = 17;
// Gamepad axes
const GAMEPAD_AXIS_LEFT_X: c_int = 0;
const GAMEPAD_AXIS_LEFT_Y: c_int = 1;
const GAMEPAD_AXIS_RIGHT_X: c_int = 2;
const GAMEPAD_AXIS_RIGHT_Y: c_int = 3;
pub const GAMEPAD_AXIS_LEFT_TRIGGER: c_int = 4;
pub const GAMEPAD_AXIS_RIGHT_TRIGGER: c_int = 5;

// Camera modes / projections
const CAMERA_CUSTOM: c_int = 0;
const CAMERA_FREE: c_int = 1;
const CAMERA_ORBITAL: c_int = 2;
const CAMERA_FIRST_PERSON: c_int = 3;
const CAMERA_THIRD_PERSON: c_int = 4;
const CAMERA_PERSPECTIVE: c_int = 0;
const CAMERA_ORTHOGRAPHIC: c_int = 1;

const BLEND_ALPHA: c_int = 0;
pub const PIXELFORMAT_UNCOMPRESSED_R8G8B8A8: c_int = 7;

// Camera control speeds (rcamera.h)
const CAMERA_MOVE_SPEED: f32 = 5.4;
const CAMERA_ROTATION_SPEED: f32 = 0.03;
const CAMERA_PAN_SPEED: f32 = 2.0;
const CAMERA_MOUSE_MOVE_SENSITIVITY: f32 = 0.003;
const CAMERA_ORBITAL_SPEED: f32 = 0.5;

// rlgl matrix modes / version
const RL_PROJECTION: c_int = 0x1701;
const RL_MODELVIEW: c_int = 0x1700;
const RL_MAX_SHADER_LOCATIONS: c_int = 32;
const RL_OPENGL_11: c_int = 1;
pub const RL_OPENGL_21: c_int = 2;
pub const RL_OPENGL_33: c_int = 3;
pub const RL_OPENGL_43: c_int = 4;
pub const RL_OPENGL_ES_20: c_int = 5;
pub const RL_OPENGL_ES_30: c_int = 6;

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
const SHADER_LOC_MAP_DIFFUSE: usize = 15;
const SHADER_LOC_MAP_SPECULAR: usize = 16;
const SHADER_LOC_MAP_NORMAL: usize = 17;
// raylib.h ShaderLocationIndex: ..., MAP_BRDF = 25, then:
const SHADER_LOC_VERTEX_BONEIDS: usize = 26;
const SHADER_LOC_VERTEX_BONEWEIGHTS: usize = 27;
const SHADER_LOC_MATRIX_BONETRANSFORMS: usize = 28;
const SHADER_LOC_VERTEX_INSTANCETRANSFORM: usize = 29;

// Default shader attribute/uniform names (null-terminated)
const RL_DEFAULT_SHADER_ATTRIB_NAME_POSITION = "vertexPosition";
const RL_DEFAULT_SHADER_ATTRIB_NAME_TEXCOORD = "vertexTexCoord";
const RL_DEFAULT_SHADER_ATTRIB_NAME_TEXCOORD2 = "vertexTexCoord2";
const RL_DEFAULT_SHADER_ATTRIB_NAME_NORMAL = "vertexNormal";
const RL_DEFAULT_SHADER_ATTRIB_NAME_TANGENT = "vertexTangent";
const RL_DEFAULT_SHADER_ATTRIB_NAME_COLOR = "vertexColor";
const RL_DEFAULT_SHADER_ATTRIB_NAME_BONEINDICES = "vertexBoneIndices";
const RL_DEFAULT_SHADER_ATTRIB_NAME_BONEWEIGHTS = "vertexBoneWeights";
const RL_DEFAULT_SHADER_ATTRIB_NAME_INSTANCETRANSFORM = "instanceTransform";
const RL_DEFAULT_SHADER_UNIFORM_NAME_MVP = "mvp";
const RL_DEFAULT_SHADER_UNIFORM_NAME_VIEW = "matView";
const RL_DEFAULT_SHADER_UNIFORM_NAME_PROJECTION = "matProjection";
const RL_DEFAULT_SHADER_UNIFORM_NAME_MODEL = "matModel";
const RL_DEFAULT_SHADER_UNIFORM_NAME_NORMAL = "matNormal";
const RL_DEFAULT_SHADER_UNIFORM_NAME_BONEMATRICES = "boneMatrices";
const RL_DEFAULT_SHADER_UNIFORM_NAME_COLOR = "colDiffuse";
const RL_DEFAULT_SHADER_SAMPLER2D_NAME_TEXTURE0 = "texture0";
const RL_DEFAULT_SHADER_SAMPLER2D_NAME_TEXTURE1 = "texture1";
const RL_DEFAULT_SHADER_SAMPLER2D_NAME_TEXTURE2 = "texture2";

//----------------------------------------------------------------------------------
// rlgl externs (from src/rlgl.zig)
//----------------------------------------------------------------------------------
extern fn rlglInit(width: c_int, height: c_int) void;
extern fn rlglClose() void;
pub extern fn rlLoadExtensions(loader: ?*anyopaque) void;
pub extern fn rlGetVersion() c_int;
extern fn rlSetFramebufferWidth(width: c_int) void;
extern fn rlSetFramebufferHeight(height: c_int) void;
extern fn rlClearColor(r: u8, g: u8, b: u8, a: u8) void;
extern fn rlClearScreenBuffers() void;
extern fn rlSetBlendMode(mode: c_int) void;
extern fn rlGetTextureIdDefault() c_uint;
extern fn rlGetShaderIdDefault() c_uint;
extern fn rlGetShaderLocsDefault() [*c]c_int;
extern fn rlDrawRenderBatchActive() void;
extern fn rlLoadIdentity() void;
extern fn rlMultMatrixf(matf: [*c]const f32) void;
extern fn rlMatrixMode(mode: c_int) void;
extern fn rlPushMatrix() void;
extern fn rlPopMatrix() void;
extern fn rlFrustum(left: f64, right: f64, bottom: f64, top: f64, znear: f64, zfar: f64) void;
extern fn rlOrtho(left: f64, right: f64, bottom: f64, top: f64, znear: f64, zfar: f64) void;
extern fn rlViewport(x: c_int, y: c_int, width: c_int, height: c_int) void;
extern fn rlEnableDepthTest() void;
extern fn rlDisableDepthTest() void;
extern fn rlEnableFramebuffer(id: c_uint) void;
extern fn rlDisableFramebuffer() void;
extern fn rlGetActiveFramebuffer() c_uint;
extern fn rlEnableScissorTest() void;
extern fn rlDisableScissorTest() void;
extern fn rlScissor(x: c_int, y: c_int, width: c_int, height: c_int) void;
extern fn rlEnableStereoRender() void;
extern fn rlDisableStereoRender() void;
extern fn rlSetMatrixProjectionStereo(right: Matrix, left: Matrix) void;
extern fn rlSetMatrixViewOffsetStereo(right: Matrix, left: Matrix) void;
extern fn rlReadScreenPixels(width: c_int, height: c_int) [*c]u8;
extern fn rlLoadShaderProgram(vsCode: [*c]const u8, fsCode: [*c]const u8) c_uint;
extern fn rlUnloadShaderProgram(id: c_uint) void;
extern fn rlGetLocationUniform(id: c_uint, uniformName: [*c]const u8) c_int;
extern fn rlGetLocationAttrib(id: c_uint, attribName: [*c]const u8) c_int;
extern fn rlSetUniform(locIndex: c_int, value: ?*const anyopaque, uniformType: c_int, count: c_int) void;
extern fn rlSetUniformMatrix(locIndex: c_int, mat: Matrix) void;
extern fn rlSetUniformSampler(locIndex: c_int, textureId: c_uint) void;
extern fn rlSetShader(id: c_uint, locs: [*c]c_int) void;
extern fn rlEnableShader(id: c_uint) void;
extern fn rlGetCullDistanceNear() f64;
extern fn rlGetCullDistanceFar() f64;

//----------------------------------------------------------------------------------
// raymath externs (from src/raymath.zig)
//----------------------------------------------------------------------------------
extern fn MatrixIdentity() Matrix;

// MatrixToFloat(mat) in C = MatrixToFloatV(mat).v, ordering v[0]=m0, v[1]=m1, ... v[15]=m15.
// Reproduced locally to avoid the by-value float16 return-struct ABI.
fn matrixToFloat(mat: Matrix) [16]f32 {
    return .{
        mat.m0,  mat.m1,  mat.m2,  mat.m3,
        mat.m4,  mat.m5,  mat.m6,  mat.m7,
        mat.m8,  mat.m9,  mat.m10, mat.m11,
        mat.m12, mat.m13, mat.m14, mat.m15,
    };
}
pub extern fn MatrixScale(x: f32, y: f32, z: f32) Matrix;
extern fn MatrixTranslate(x: f32, y: f32, z: f32) Matrix;
extern fn MatrixRotate(axis: Vector3, angle: f32) Matrix;
extern fn MatrixMultiply(left: Matrix, right: Matrix) Matrix;
extern fn MatrixInvert(mat: Matrix) Matrix;
extern fn MatrixLookAt(eye: Vector3, target: Vector3, up: Vector3) Matrix;
extern fn MatrixPerspective(fovy: f64, aspect: f64, nearPlane: f64, farPlane: f64) Matrix;
extern fn MatrixOrtho(left: f64, right: f64, bottom: f64, top: f64, nearPlane: f64, farPlane: f64) Matrix;
extern fn Vector3Transform(v: Vector3, mat: Matrix) Vector3;
extern fn Vector3Subtract(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3Add(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3Normalize(v: Vector3) Vector3;
extern fn Vector3Unproject(source: Vector3, projection: Matrix, view: Matrix) Vector3;
extern fn QuaternionTransform(q: Quaternion, mat: Matrix) Quaternion;

//----------------------------------------------------------------------------------
// rgestures externs (from src/rgestures.zig)
//----------------------------------------------------------------------------------
pub extern fn UpdateGestures() void;

// GESTURES.current is read for automation recording; rgestures exposes a getter.
extern fn GetGestureDetected() c_int;
const GESTURE_NONE: c_int = 0;

//----------------------------------------------------------------------------------
// rcamera externs (from src/rcamera.zig). UpdateCamera/UpdateCameraPro are ported here.
//----------------------------------------------------------------------------------
extern fn GetCameraUp(camera: *Camera) Vector3;
extern fn CameraMoveForward(camera: *Camera, distance: f32, moveInWorldPlane: bool) void;
extern fn CameraMoveUp(camera: *Camera, distance: f32) void;
extern fn CameraMoveRight(camera: *Camera, distance: f32, moveInWorldPlane: bool) void;
extern fn CameraMoveToTarget(camera: *Camera, delta: f32) void;
extern fn CameraYaw(camera: *Camera, angle: f32, rotateAroundTarget: bool) void;
extern fn CameraPitch(camera: *Camera, angle: f32, lockView: bool, rotateAroundTarget: bool, rotateUp: bool) void;
extern fn CameraRoll(camera: *Camera, angle: f32) void;

//----------------------------------------------------------------------------------
// Third-party externs (provided by src/c/rcore_impl.c)
//----------------------------------------------------------------------------------
const sdefl = anyopaque;
extern fn rl_sizeof_sdefl() usize;
extern fn sdefl_bound(in_len: c_int) c_int;
extern fn sdeflate(s: *sdefl, o: ?*anyopaque, i: ?*const anyopaque, n: c_int, lvl: c_int) c_int;
extern fn sinflate(o: ?*anyopaque, cap: c_int, i: ?*const anyopaque, size: c_int) c_int;
extern fn rprand_set_seed(seed: c_ulonglong) void;
extern fn rprand_get_value(min: c_int, max: c_int) c_int;
extern fn rprand_load_sequence(count: c_uint, min: c_int, max: c_int) [*c]c_int;
extern fn rprand_unload_sequence(sequence: [*c]c_int) void;

//----------------------------------------------------------------------------------
// Cross-module raylib symbols (other modules)
//----------------------------------------------------------------------------------
extern fn LoadFontDefault() void;
extern fn UnloadFontDefault() void;
extern fn GetFontDefault() Font;
extern fn SetShapesTexture(texture: Texture2D, source: Rectangle) void;
extern fn ExportImage(image: Image, fileName: [*c]const u8) bool;
pub extern fn TextFormat(text: [*c]const u8, ...) [*c]const u8;
extern fn TextReplaceAlloc(text: [*c]u8, search: [*c]const u8, replacement: [*c]const u8) [*c]u8;
extern fn GetFontDefaultRecs() [*c]Rectangle;

// Minimal Font layout (only `.recs` and `.texture` fields used by InitWindow)
const GlyphInfo = extern struct {
    value: c_int,
    offsetX: c_int,
    offsetY: c_int,
    advanceX: c_int,
    image: Image,
};
const Font = extern struct {
    baseSize: c_int,
    glyphCount: c_int,
    glyphPadding: c_int,
    texture: Texture2D,
    recs: [*c]Rectangle,
    glyphs: [*c]GlyphInfo,
};

//----------------------------------------------------------------------------------
// CoreData: private state (layout ours, every field of rcore.c's CoreData mirrored)
//----------------------------------------------------------------------------------
const Point = extern struct { x: c_int, y: c_int };
const Size = extern struct { width: c_uint, height: c_uint };

const WindowData = struct {
    title: [*c]const u8 = null,
    flags: c_uint = 0,
    ready: bool = false,
    shouldClose: bool = false,
    resizedLastFrame: bool = false,
    eventWaiting: bool = false,
    usingFbo: bool = false,

    display: Size = .{ .width = 0, .height = 0 },
    screen: Size = .{ .width = 0, .height = 0 },
    position: Point = .{ .x = 0, .y = 0 },
    previousScreen: Size = .{ .width = 0, .height = 0 },
    previousPosition: Point = .{ .x = 0, .y = 0 },
    render: Size = .{ .width = 0, .height = 0 },
    renderOffset: Point = .{ .x = 0, .y = 0 },
    currentFbo: Size = .{ .width = 0, .height = 0 },
    screenMin: Size = .{ .width = 0, .height = 0 },
    screenMax: Size = .{ .width = 0, .height = 0 },
    screenScale: Matrix = std.mem.zeroes(Matrix),

    dropFilepaths: [*c][*c]u8 = null,
    dropFileCount: c_uint = 0,
};

const StorageData = struct {
    basePath: [*c]const u8 = null,
};

const KeyboardData = struct {
    exitKey: c_int = 0,
    currentKeyState: [MAX_KEYBOARD_KEYS]u8 = std.mem.zeroes([MAX_KEYBOARD_KEYS]u8),
    previousKeyState: [MAX_KEYBOARD_KEYS]u8 = std.mem.zeroes([MAX_KEYBOARD_KEYS]u8),
    keyRepeatInFrame: [MAX_KEYBOARD_KEYS]u8 = std.mem.zeroes([MAX_KEYBOARD_KEYS]u8),
    keyPressedQueue: [MAX_KEY_PRESSED_QUEUE]c_int = std.mem.zeroes([MAX_KEY_PRESSED_QUEUE]c_int),
    keyPressedQueueCount: c_int = 0,
    charPressedQueue: [MAX_CHAR_PRESSED_QUEUE]c_int = std.mem.zeroes([MAX_CHAR_PRESSED_QUEUE]c_int),
    charPressedQueueCount: c_int = 0,
};

const MouseData = struct {
    offset: Vector2 = .{ .x = 0, .y = 0 },
    scale: Vector2 = .{ .x = 0, .y = 0 },
    currentPosition: Vector2 = .{ .x = 0, .y = 0 },
    previousPosition: Vector2 = .{ .x = 0, .y = 0 },
    lockedPosition: Vector2 = .{ .x = 0, .y = 0 },

    cursor: c_int = 0,
    cursorHidden: bool = false,
    cursorLocked: bool = false,
    cursorOnScreen: bool = false,

    currentButtonState: [MAX_MOUSE_BUTTONS]u8 = std.mem.zeroes([MAX_MOUSE_BUTTONS]u8),
    previousButtonState: [MAX_MOUSE_BUTTONS]u8 = std.mem.zeroes([MAX_MOUSE_BUTTONS]u8),
    currentWheelMove: Vector2 = .{ .x = 0, .y = 0 },
    previousWheelMove: Vector2 = .{ .x = 0, .y = 0 },
};

const TouchData = struct {
    pointCount: c_int = 0,
    pointId: [MAX_TOUCH_POINTS]c_int = std.mem.zeroes([MAX_TOUCH_POINTS]c_int),
    position: [MAX_TOUCH_POINTS]Vector2 = std.mem.zeroes([MAX_TOUCH_POINTS]Vector2),
    previousPosition: [MAX_TOUCH_POINTS]Vector2 = std.mem.zeroes([MAX_TOUCH_POINTS]Vector2),
    currentTouchState: [MAX_TOUCH_POINTS]u8 = std.mem.zeroes([MAX_TOUCH_POINTS]u8),
    previousTouchState: [MAX_TOUCH_POINTS]u8 = std.mem.zeroes([MAX_TOUCH_POINTS]u8),
};

const GamepadData = struct {
    lastButtonPressed: c_int = 0,
    axisCount: [MAX_GAMEPADS]c_int = std.mem.zeroes([MAX_GAMEPADS]c_int),
    ready: [MAX_GAMEPADS]bool = std.mem.zeroes([MAX_GAMEPADS]bool),
    name: [MAX_GAMEPADS][MAX_GAMEPAD_NAME_LENGTH]u8 = std.mem.zeroes([MAX_GAMEPADS][MAX_GAMEPAD_NAME_LENGTH]u8),
    currentButtonState: [MAX_GAMEPADS][MAX_GAMEPAD_BUTTONS]u8 = std.mem.zeroes([MAX_GAMEPADS][MAX_GAMEPAD_BUTTONS]u8),
    previousButtonState: [MAX_GAMEPADS][MAX_GAMEPAD_BUTTONS]u8 = std.mem.zeroes([MAX_GAMEPADS][MAX_GAMEPAD_BUTTONS]u8),
    axisState: [MAX_GAMEPADS][MAX_GAMEPAD_AXES]f32 = std.mem.zeroes([MAX_GAMEPADS][MAX_GAMEPAD_AXES]f32),
};

const InputData = struct {
    Keyboard: KeyboardData = .{},
    Mouse: MouseData = .{},
    Touch: TouchData = .{},
    Gamepad: GamepadData = .{},
};

const TimeData = struct {
    current: f64 = 0,
    previous: f64 = 0,
    update: f64 = 0,
    draw: f64 = 0,
    frame: f64 = 0,
    target: f64 = 0,
    base: c_ulonglong = 0,
    frameCounter: c_uint = 0,
};

const CoreData = struct {
    Window: WindowData = .{},
    Storage: StorageData = .{},
    Input: InputData = .{},
    Time: TimeData = .{},
};

//----------------------------------------------------------------------------------
// Global Variables
//----------------------------------------------------------------------------------
export const raylib_version: [*c]const u8 = RAYLIB_VERSION;

pub var CORE: CoreData = .{};

var logTypeLevel: c_int = LOG_INFO;

var traceLogCallbackPtr: TraceLogCallback = null;
var loadFileDataCallbackPtr: LoadFileDataCallback = null;
var saveFileDataCallbackPtr: SaveFileDataCallback = null;
var loadFileTextCallbackPtr: LoadFileTextCallback = null;
var saveFileTextCallbackPtr: SaveFileTextCallback = null;

var screenshotCounter: c_int = 0;

// Automation events
const EVENT_NONE: c_uint = 0;
const INPUT_KEY_UP: c_uint = 1;
const INPUT_KEY_DOWN: c_uint = 2;
const INPUT_KEY_PRESSED: c_uint = 3;
const INPUT_KEY_RELEASED: c_uint = 4;
const INPUT_MOUSE_BUTTON_UP: c_uint = 5;
const INPUT_MOUSE_BUTTON_DOWN: c_uint = 6;
const INPUT_MOUSE_POSITION: c_uint = 7;
const INPUT_MOUSE_WHEEL_MOTION: c_uint = 8;
const INPUT_GAMEPAD_CONNECT: c_uint = 9;
const INPUT_GAMEPAD_DISCONNECT: c_uint = 10;
const INPUT_GAMEPAD_BUTTON_UP: c_uint = 11;
const INPUT_GAMEPAD_BUTTON_DOWN: c_uint = 12;
const INPUT_GAMEPAD_AXIS_MOTION: c_uint = 13;
const INPUT_TOUCH_UP: c_uint = 14;
const INPUT_TOUCH_DOWN: c_uint = 15;
const INPUT_TOUCH_POSITION: c_uint = 16;
const INPUT_GESTURE: c_uint = 17;
const WINDOW_CLOSE: c_uint = 18;
const WINDOW_MAXIMIZE: c_uint = 19;
const WINDOW_MINIMIZE: c_uint = 20;
const WINDOW_RESIZE: c_uint = 21;
const ACTION_TAKE_SCREENSHOT: c_uint = 22;
const ACTION_SETTARGETFPS: c_uint = 23;

var currentEventList: ?*AutomationEventList = null;
var automationEventRecording: bool = false;

//----------------------------------------------------------------------------------
// Flag helpers
//----------------------------------------------------------------------------------
pub inline fn flagIsSet(n: c_uint, f: c_uint) bool {
    return (n & f) == f;
}
pub inline fn flagSet(n: *c_uint, f: c_uint) void {
    n.* |= f;
}
pub inline fn flagClear(n: *c_uint, f: c_uint) void {
    n.* &= ~f;
}

// TraceLog: variadic, forwarded to the C TraceLog defined in this module (export below)
// (Use the exported TraceLog directly via @This-level call.)

//----------------------------------------------------------------------------------
// Module Functions Definition: Window and Graphics Device
//----------------------------------------------------------------------------------

// Initialize window and OpenGL context
export fn InitWindow(width: c_int, height: c_int, title: [*c]const u8) callconv(.c) void {
    TraceLog(LOG_INFO, "Initializing raylib %s", RAYLIB_VERSION);
    TraceLog(LOG_INFO, "Platform backend: " ++ backend.backend_name);

    TraceLog(LOG_INFO, "Supported raylib modules:");
    TraceLog(LOG_INFO, "    > rcore:..... loaded (mandatory)");
    TraceLog(LOG_INFO, "    > rlgl:...... loaded (mandatory)");

    // Initialize window data
    CORE.Window.screen.width = @intCast(width);
    CORE.Window.screen.height = @intCast(height);

    CORE.Window.eventWaiting = false;
    CORE.Window.screenScale = MatrixIdentity();
    if ((title != null) and (title[0] != 0)) CORE.Window.title = title;

    // Initialize global input state to zero
    CORE.Input = .{};
    CORE.Input.Keyboard.exitKey = KEY_ESCAPE;
    CORE.Input.Mouse.scale = .{ .x = 1.0, .y = 1.0 };
    CORE.Input.Mouse.cursor = MOUSE_CURSOR_ARROW;
    CORE.Input.Gamepad.lastButtonPressed = GAMEPAD_BUTTON_UNKNOWN;

    // Initialize platform
    const result = InitPlatform();
    if (result != 0) {
        TraceLog(LOG_WARNING, "SYSTEM: Failed to initialize platform");
        return;
    }

    if ((CORE.Window.render.width == 0) or (CORE.Window.render.height == 0)) {
        CORE.Window.render.width = CORE.Window.screen.width;
        CORE.Window.render.height = CORE.Window.screen.height;
    }

    // Initialize rlgl default data
    rlglInit(@intCast(CORE.Window.render.width), @intCast(CORE.Window.render.height));

    // Setup default viewport
    SetupViewport(@intCast(CORE.Window.render.width), @intCast(CORE.Window.render.height));

    // Load default font (rtext)
    LoadFontDefault();
    const rec = GetFontDefault().recs[95];
    if (flagIsSet(CORE.Window.flags, FLAG_MSAA_4X_HINT)) {
        SetShapesTexture(GetFontDefault().texture, .{ .x = rec.x + 2, .y = rec.y + 2, .width = 1, .height = 1 });
    } else {
        SetShapesTexture(GetFontDefault().texture, .{ .x = rec.x + 1, .y = rec.y + 1, .width = rec.width - 2, .height = rec.height - 2 });
    }

    CORE.Time.frameCounter = 0;
    CORE.Window.shouldClose = false;

    // Initialize random seed
    SetRandomSeed(@truncate(@as(u64, @bitCast(@as(i64, time(null))))));

    TraceLog(LOG_INFO, "SYSTEM: Working Directory: %s", GetWorkingDirectory());
}

// Close window and unload OpenGL context
export fn CloseWindow() callconv(.c) void {
    UnloadFontDefault();
    rlglClose();
    ClosePlatform();
    CORE.Window.ready = false;
    TraceLog(LOG_INFO, "Window closed successfully");
}

export fn IsWindowReady() callconv(.c) bool {
    return CORE.Window.ready;
}
pub export fn IsWindowFullscreen() callconv(.c) bool {
    return flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE);
}
export fn IsWindowHidden() callconv(.c) bool {
    return flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIDDEN);
}
export fn IsWindowMinimized() callconv(.c) bool {
    return flagIsSet(CORE.Window.flags, FLAG_WINDOW_MINIMIZED);
}
export fn IsWindowMaximized() callconv(.c) bool {
    return flagIsSet(CORE.Window.flags, FLAG_WINDOW_MAXIMIZED);
}
export fn IsWindowFocused() callconv(.c) bool {
    return !flagIsSet(CORE.Window.flags, FLAG_WINDOW_UNFOCUSED);
}
export fn IsWindowResized() callconv(.c) bool {
    return CORE.Window.resizedLastFrame;
}
export fn IsWindowState(flag: c_uint) callconv(.c) bool {
    return flagIsSet(CORE.Window.flags, flag);
}
pub export fn GetScreenWidth() callconv(.c) c_int {
    return @intCast(CORE.Window.screen.width);
}
pub export fn GetScreenHeight() callconv(.c) c_int {
    return @intCast(CORE.Window.screen.height);
}
export fn GetRenderWidth() callconv(.c) c_int {
    if (CORE.Window.usingFbo) return @intCast(CORE.Window.currentFbo.width);
    return @intCast(CORE.Window.render.width);
}
export fn GetRenderHeight() callconv(.c) c_int {
    if (CORE.Window.usingFbo) return @intCast(CORE.Window.currentFbo.height);
    return @intCast(CORE.Window.render.height);
}
export fn EnableEventWaiting() callconv(.c) void {
    CORE.Window.eventWaiting = true;
}
export fn DisableEventWaiting() callconv(.c) void {
    CORE.Window.eventWaiting = false;
}
export fn IsCursorHidden() callconv(.c) bool {
    return CORE.Input.Mouse.cursorHidden;
}
export fn IsCursorOnScreen() callconv(.c) bool {
    return CORE.Input.Mouse.cursorOnScreen;
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Screen Drawing
//----------------------------------------------------------------------------------

export fn ClearBackground(color: Color) callconv(.c) void {
    rlClearColor(color.r, color.g, color.b, color.a);
    rlClearScreenBuffers();
}

export fn BeginDrawing() callconv(.c) void {
    CORE.Time.current = GetTime();
    CORE.Time.update = CORE.Time.current - CORE.Time.previous;
    CORE.Time.previous = CORE.Time.current;

    rlLoadIdentity();
    var f = matrixToFloat(CORE.Window.screenScale);
    rlMultMatrixf(&f);
}

export fn EndDrawing() callconv(.c) void {
    rlDrawRenderBatchActive();

    if (automationEventRecording) RecordAutomationEvent();

    SwapScreenBuffer();

    CORE.Time.current = GetTime();
    CORE.Time.draw = CORE.Time.current - CORE.Time.previous;
    CORE.Time.previous = CORE.Time.current;

    CORE.Time.frame = CORE.Time.update + CORE.Time.draw;

    if (CORE.Time.frame < CORE.Time.target) {
        WaitTime(CORE.Time.target - CORE.Time.frame);

        CORE.Time.current = GetTime();
        const waitTime = CORE.Time.current - CORE.Time.previous;
        CORE.Time.previous = CORE.Time.current;

        CORE.Time.frame += waitTime;
    }

    PollInputEvents();

    if (IsKeyPressed(KEY_F12)) {
        TakeScreenshot(TextFormat("screenshot%03i.png", screenshotCounter));
        screenshotCounter += 1;
    }

    CORE.Time.frameCounter += 1;
}

export fn BeginMode2D(camera: Camera2D) callconv(.c) void {
    rlDrawRenderBatchActive();
    rlLoadIdentity();
    var f = matrixToFloat(GetCameraMatrix2D(camera));
    rlMultMatrixf(&f);
}

export fn EndMode2D() callconv(.c) void {
    rlDrawRenderBatchActive();
    rlLoadIdentity();
    if (rlGetActiveFramebuffer() == 0) {
        var f = matrixToFloat(CORE.Window.screenScale);
        rlMultMatrixf(&f);
    }
}

export fn BeginMode3D(camera: Camera) callconv(.c) void {
    rlDrawRenderBatchActive();

    rlMatrixMode(RL_PROJECTION);
    rlPushMatrix();
    rlLoadIdentity();

    const aspect = @as(f32, @floatFromInt(CORE.Window.currentFbo.width)) / @as(f32, @floatFromInt(CORE.Window.currentFbo.height));

    if (camera.projection == CAMERA_PERSPECTIVE) {
        const top = rlGetCullDistanceNear() * tan(@as(f64, camera.fovy) * 0.5 * DEG2RAD);
        const right = top * @as(f64, aspect);
        rlFrustum(-right, right, -top, top, rlGetCullDistanceNear(), rlGetCullDistanceFar());
    } else if (camera.projection == CAMERA_ORTHOGRAPHIC) {
        const top = @as(f64, camera.fovy) / 2.0;
        const right = top * @as(f64, aspect);
        rlOrtho(-right, right, -top, top, rlGetCullDistanceNear(), rlGetCullDistanceFar());
    }

    rlMatrixMode(RL_MODELVIEW);
    rlLoadIdentity();

    const matView = MatrixLookAt(camera.position, camera.target, camera.up);
    var f = matrixToFloat(matView);
    rlMultMatrixf(&f);

    rlEnableDepthTest();
}

export fn EndMode3D() callconv(.c) void {
    rlDrawRenderBatchActive();

    rlMatrixMode(RL_PROJECTION);
    rlPopMatrix();

    rlMatrixMode(RL_MODELVIEW);
    rlLoadIdentity();

    if (rlGetActiveFramebuffer() == 0) {
        var f = matrixToFloat(CORE.Window.screenScale);
        rlMultMatrixf(&f);
    }

    rlDisableDepthTest();
}

export fn BeginTextureMode(target: RenderTexture2D) callconv(.c) void {
    rlDrawRenderBatchActive();

    rlEnableFramebuffer(target.id);

    rlViewport(0, 0, target.texture.width, target.texture.height);
    rlSetFramebufferWidth(target.texture.width);
    rlSetFramebufferHeight(target.texture.height);

    rlMatrixMode(RL_PROJECTION);
    rlLoadIdentity();

    rlOrtho(0, @floatFromInt(target.texture.width), @floatFromInt(target.texture.height), 0, 0.0, 1.0);

    rlMatrixMode(RL_MODELVIEW);
    rlLoadIdentity();

    CORE.Window.currentFbo.width = @intCast(target.texture.width);
    CORE.Window.currentFbo.height = @intCast(target.texture.height);
    CORE.Window.usingFbo = true;
}

export fn EndTextureMode() callconv(.c) void {
    rlDrawRenderBatchActive();

    rlDisableFramebuffer();

    SetupViewport(@intCast(CORE.Window.render.width), @intCast(CORE.Window.render.height));

    rlMatrixMode(RL_MODELVIEW);
    rlLoadIdentity();
    var f = matrixToFloat(CORE.Window.screenScale);
    rlMultMatrixf(&f);

    CORE.Window.currentFbo.width = CORE.Window.render.width;
    CORE.Window.currentFbo.height = CORE.Window.render.height;
    CORE.Window.usingFbo = false;
}

export fn BeginShaderMode(shader: Shader) callconv(.c) void {
    rlSetShader(shader.id, shader.locs);
}
export fn EndShaderMode() callconv(.c) void {
    rlSetShader(rlGetShaderIdDefault(), rlGetShaderLocsDefault());
}
export fn BeginBlendMode(mode: c_int) callconv(.c) void {
    rlSetBlendMode(mode);
}
export fn EndBlendMode() callconv(.c) void {
    rlSetBlendMode(BLEND_ALPHA);
}

export fn BeginScissorMode(x: c_int, y: c_int, width: c_int, height: c_int) callconv(.c) void {
    rlDrawRenderBatchActive();
    rlEnableScissorTest();

    if (!CORE.Window.usingFbo and flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) {
        const scale = GetWindowScaleDPI();
        rlScissor(
            @intFromFloat(@as(f32, @floatFromInt(x)) * scale.x),
            @as(c_int, @intCast(CORE.Window.currentFbo.height)) - @as(c_int, @intFromFloat((@as(f32, @floatFromInt(y)) + @as(f32, @floatFromInt(height))) * scale.y)),
            @intFromFloat(@as(f32, @floatFromInt(width)) * scale.x),
            @intFromFloat(@as(f32, @floatFromInt(height)) * scale.y),
        );
    } else {
        rlScissor(x, @as(c_int, @intCast(CORE.Window.currentFbo.height)) - (y + height), width, height);
    }
}
export fn EndScissorMode() callconv(.c) void {
    rlDrawRenderBatchActive();
    rlDisableScissorTest();
}

//----------------------------------------------------------------------------------
// Module Functions Definition: VR Stereo Rendering
//----------------------------------------------------------------------------------

export fn BeginVrStereoMode(config: VrStereoConfig) callconv(.c) void {
    rlEnableStereoRender();
    rlSetMatrixProjectionStereo(config.projection[0], config.projection[1]);
    rlSetMatrixViewOffsetStereo(config.viewOffset[0], config.viewOffset[1]);
}

export fn EndVrStereoMode() callconv(.c) void {
    rlDisableStereoRender();
}

export fn LoadVrStereoConfig(device: VrDeviceInfo) callconv(.c) VrStereoConfig {
    var config = std.mem.zeroes(VrStereoConfig);

    if (rlGetVersion() != RL_OPENGL_11) {
        const aspect = (@as(f32, @floatFromInt(device.hResolution)) * 0.5) / @as(f32, @floatFromInt(device.vResolution));

        const lensShift = (device.hScreenSize * 0.25 - device.lensSeparationDistance * 0.5) / device.hScreenSize;
        config.leftLensCenter[0] = 0.25 + lensShift;
        config.leftLensCenter[1] = 0.5;
        config.rightLensCenter[0] = 0.75 - lensShift;
        config.rightLensCenter[1] = 0.5;
        config.leftScreenCenter[0] = 0.25;
        config.leftScreenCenter[1] = 0.5;
        config.rightScreenCenter[0] = 0.75;
        config.rightScreenCenter[1] = 0.5;

        const lensRadius = @abs(-1.0 - 4.0 * lensShift);
        const lensRadiusSq = lensRadius * lensRadius;
        const distortionScale = device.lensDistortionValues[0] +
            device.lensDistortionValues[1] * lensRadiusSq +
            device.lensDistortionValues[2] * lensRadiusSq * lensRadiusSq +
            device.lensDistortionValues[3] * lensRadiusSq * lensRadiusSq * lensRadiusSq;

        const normScreenWidth: f32 = 0.5;
        const normScreenHeight: f32 = 1.0;
        config.scaleIn[0] = 2.0 / normScreenWidth;
        config.scaleIn[1] = 2.0 / normScreenHeight / aspect;
        config.scale[0] = normScreenWidth * 0.5 / distortionScale;
        config.scale[1] = normScreenHeight * 0.5 * aspect / distortionScale;

        const fovy = 2.0 * atan2f(device.vScreenSize * 0.5 * distortionScale, device.eyeToScreenDistance);

        const projOffset = 4.0 * lensShift;
        const proj = MatrixPerspective(fovy, aspect, rlGetCullDistanceNear(), rlGetCullDistanceFar());

        config.projection[0] = MatrixMultiply(proj, MatrixTranslate(projOffset, 0.0, 0.0));
        config.projection[1] = MatrixMultiply(proj, MatrixTranslate(-projOffset, 0.0, 0.0));

        config.viewOffset[0] = MatrixTranslate(device.interpupillaryDistance * 0.5, 0.075, 0.045);
        config.viewOffset[1] = MatrixTranslate(-device.interpupillaryDistance * 0.5, 0.075, 0.045);
    } else TraceLog(LOG_WARNING, "RLGL: VR Simulator not supported on OpenGL 1.1");

    return config;
}

export fn UnloadVrStereoConfig(config: VrStereoConfig) callconv(.c) void {
    _ = config;
    TraceLog(LOG_INFO, "UnloadVrStereoConfig not implemented in rcore.c");
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Shaders Management
//----------------------------------------------------------------------------------

export fn LoadShader(vsFileName: [*c]const u8, fsFileName: [*c]const u8) callconv(.c) Shader {
    var vShaderStr: [*c]u8 = null;
    var fShaderStr: [*c]u8 = null;

    if (vsFileName != null) vShaderStr = LoadFileText(vsFileName);
    if (fsFileName != null) fShaderStr = LoadFileText(fsFileName);

    if ((vShaderStr == null) and (fShaderStr == null)) TraceLog(LOG_WARNING, "SHADER: Shader files provided are not valid, using default shader");

    const shader = LoadShaderFromMemory(vShaderStr, fShaderStr);

    UnloadFileText(vShaderStr);
    UnloadFileText(fShaderStr);

    return shader;
}

export fn LoadShaderFromMemory(vsCode: [*c]const u8, fsCode: [*c]const u8) callconv(.c) Shader {
    var shader = std.mem.zeroes(Shader);

    shader.id = rlLoadShaderProgram(vsCode, fsCode);

    if (shader.id == 0) {
        shader.locs = newShaderLocations();
    } else if (shader.id == rlGetShaderIdDefault()) {
        shader.locs = rlGetShaderLocsDefault();
    } else if (shader.id > 0) {
        shader.locs = newShaderLocations();

        shader.locs[SHADER_LOC_VERTEX_POSITION] = rlGetLocationAttrib(shader.id, RL_DEFAULT_SHADER_ATTRIB_NAME_POSITION);
        shader.locs[SHADER_LOC_VERTEX_TEXCOORD01] = rlGetLocationAttrib(shader.id, RL_DEFAULT_SHADER_ATTRIB_NAME_TEXCOORD);
        shader.locs[SHADER_LOC_VERTEX_TEXCOORD02] = rlGetLocationAttrib(shader.id, RL_DEFAULT_SHADER_ATTRIB_NAME_TEXCOORD2);
        shader.locs[SHADER_LOC_VERTEX_NORMAL] = rlGetLocationAttrib(shader.id, RL_DEFAULT_SHADER_ATTRIB_NAME_NORMAL);
        shader.locs[SHADER_LOC_VERTEX_TANGENT] = rlGetLocationAttrib(shader.id, RL_DEFAULT_SHADER_ATTRIB_NAME_TANGENT);
        shader.locs[SHADER_LOC_VERTEX_COLOR] = rlGetLocationAttrib(shader.id, RL_DEFAULT_SHADER_ATTRIB_NAME_COLOR);
        shader.locs[SHADER_LOC_VERTEX_BONEIDS] = rlGetLocationAttrib(shader.id, RL_DEFAULT_SHADER_ATTRIB_NAME_BONEINDICES);
        shader.locs[SHADER_LOC_VERTEX_BONEWEIGHTS] = rlGetLocationAttrib(shader.id, RL_DEFAULT_SHADER_ATTRIB_NAME_BONEWEIGHTS);
        shader.locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM] = rlGetLocationAttrib(shader.id, RL_DEFAULT_SHADER_ATTRIB_NAME_INSTANCETRANSFORM);

        shader.locs[SHADER_LOC_MATRIX_MVP] = rlGetLocationUniform(shader.id, RL_DEFAULT_SHADER_UNIFORM_NAME_MVP);
        shader.locs[SHADER_LOC_MATRIX_VIEW] = rlGetLocationUniform(shader.id, RL_DEFAULT_SHADER_UNIFORM_NAME_VIEW);
        shader.locs[SHADER_LOC_MATRIX_PROJECTION] = rlGetLocationUniform(shader.id, RL_DEFAULT_SHADER_UNIFORM_NAME_PROJECTION);
        shader.locs[SHADER_LOC_MATRIX_MODEL] = rlGetLocationUniform(shader.id, RL_DEFAULT_SHADER_UNIFORM_NAME_MODEL);
        shader.locs[SHADER_LOC_MATRIX_NORMAL] = rlGetLocationUniform(shader.id, RL_DEFAULT_SHADER_UNIFORM_NAME_NORMAL);
        shader.locs[SHADER_LOC_MATRIX_BONETRANSFORMS] = rlGetLocationUniform(shader.id, RL_DEFAULT_SHADER_UNIFORM_NAME_BONEMATRICES);

        shader.locs[SHADER_LOC_COLOR_DIFFUSE] = rlGetLocationUniform(shader.id, RL_DEFAULT_SHADER_UNIFORM_NAME_COLOR);
        shader.locs[SHADER_LOC_MAP_DIFFUSE] = rlGetLocationUniform(shader.id, RL_DEFAULT_SHADER_SAMPLER2D_NAME_TEXTURE0);
        shader.locs[SHADER_LOC_MAP_SPECULAR] = rlGetLocationUniform(shader.id, RL_DEFAULT_SHADER_SAMPLER2D_NAME_TEXTURE1);
        shader.locs[SHADER_LOC_MAP_NORMAL] = rlGetLocationUniform(shader.id, RL_DEFAULT_SHADER_SAMPLER2D_NAME_TEXTURE2);
    }

    return shader;
}

/// A shader's location table with every entry unset (-1). UnloadShader frees it.
fn newShaderLocations() [*c]c_int {
    const locs = cmem.alloc(c_int, RL_MAX_SHADER_LOCATIONS) catch return null;
    @memset(locs, -1);
    return locs.ptr;
}

export fn IsShaderValid(shader: Shader) callconv(.c) bool {
    return (shader.id > 0) and (shader.locs != null);
}

export fn UnloadShader(shader: Shader) callconv(.c) void {
    if (shader.id != rlGetShaderIdDefault()) {
        rlUnloadShaderProgram(shader.id);
        cmem.free(shader.locs);
    }
}

export fn GetShaderLocation(shader: Shader, uniformName: [*c]const u8) callconv(.c) c_int {
    return rlGetLocationUniform(shader.id, uniformName);
}

export fn GetShaderLocationAttrib(shader: Shader, attribName: [*c]const u8) callconv(.c) c_int {
    return rlGetLocationAttrib(shader.id, attribName);
}

export fn SetShaderValue(shader: Shader, locIndex: c_int, value: ?*const anyopaque, uniformType: c_int) callconv(.c) void {
    SetShaderValueV(shader, locIndex, value, uniformType, 1);
}

export fn SetShaderValueV(shader: Shader, locIndex: c_int, value: ?*const anyopaque, uniformType: c_int, count: c_int) callconv(.c) void {
    if (locIndex > -1) {
        rlEnableShader(shader.id);
        rlSetUniform(locIndex, value, uniformType, count);
    }
}

export fn SetShaderValueMatrix(shader: Shader, locIndex: c_int, mat: Matrix) callconv(.c) void {
    if (locIndex > -1) {
        rlEnableShader(shader.id);
        rlSetUniformMatrix(locIndex, mat);
    }
}

export fn SetShaderValueTexture(shader: Shader, locIndex: c_int, texture: Texture2D) callconv(.c) void {
    if (locIndex > -1) {
        rlEnableShader(shader.id);
        rlSetUniformSampler(locIndex, texture.id);
    }
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Screen-space Queries
//----------------------------------------------------------------------------------

export fn GetScreenToWorldRay(position: Vector2, camera: Camera) callconv(.c) Ray {
    return GetScreenToWorldRayEx(position, camera, GetScreenWidth(), GetScreenHeight());
}

export fn GetScreenToWorldRayEx(position: Vector2, camera: Camera, width: c_int, height: c_int) callconv(.c) Ray {
    var ray = std.mem.zeroes(Ray);

    const x = (2.0 * position.x) / @as(f32, @floatFromInt(width)) - 1.0;
    const y = 1.0 - (2.0 * position.y) / @as(f32, @floatFromInt(height));
    const z: f32 = 1.0;

    const deviceCoords = Vector3{ .x = x, .y = y, .z = z };

    const matView = MatrixLookAt(camera.position, camera.target, camera.up);
    var matProj = MatrixIdentity();

    if (camera.projection == CAMERA_PERSPECTIVE) {
        matProj = MatrixPerspective(@as(f64, camera.fovy) * DEG2RAD, @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(height)), rlGetCullDistanceNear(), rlGetCullDistanceFar());
    } else if (camera.projection == CAMERA_ORTHOGRAPHIC) {
        const aspect = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(height));
        const top = @as(f64, camera.fovy) / 2.0;
        const right = top * aspect;
        matProj = MatrixOrtho(-right, right, -top, top, rlGetCullDistanceNear(), rlGetCullDistanceFar());
    }

    const nearPoint = Vector3Unproject(.{ .x = deviceCoords.x, .y = deviceCoords.y, .z = 0.0 }, matProj, matView);
    const farPoint = Vector3Unproject(.{ .x = deviceCoords.x, .y = deviceCoords.y, .z = 1.0 }, matProj, matView);
    const cameraPlanePointerPos = Vector3Unproject(.{ .x = deviceCoords.x, .y = deviceCoords.y, .z = -1.0 }, matProj, matView);

    const direction = Vector3Normalize(Vector3Subtract(farPoint, nearPoint));

    if (camera.projection == CAMERA_PERSPECTIVE) {
        ray.position = camera.position;
    } else if (camera.projection == CAMERA_ORTHOGRAPHIC) {
        ray.position = cameraPlanePointerPos;
    }

    ray.direction = direction;

    return ray;
}

export fn GetCameraMatrix(camera: Camera) callconv(.c) Matrix {
    return MatrixLookAt(camera.position, camera.target, camera.up);
}

export fn GetCameraMatrix2D(camera: Camera2D) callconv(.c) Matrix {
    const matOrigin = MatrixTranslate(-camera.target.x, -camera.target.y, 0.0);
    const matRotation = MatrixRotate(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, camera.rotation * DEG2RAD);
    const matScale = MatrixScale(camera.zoom, camera.zoom, 1.0);
    const matTranslation = MatrixTranslate(camera.offset.x, camera.offset.y, 0.0);

    return MatrixMultiply(MatrixMultiply(matOrigin, MatrixMultiply(matScale, matRotation)), matTranslation);
}

export fn GetWorldToScreen(position: Vector3, camera: Camera) callconv(.c) Vector2 {
    return GetWorldToScreenEx(position, camera, GetScreenWidth(), GetScreenHeight());
}

export fn GetWorldToScreenEx(position: Vector3, camera: Camera, width: c_int, height: c_int) callconv(.c) Vector2 {
    var matProj = MatrixIdentity();

    if (camera.projection == CAMERA_PERSPECTIVE) {
        matProj = MatrixPerspective(@as(f64, camera.fovy) * DEG2RAD, @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(height)), rlGetCullDistanceNear(), rlGetCullDistanceFar());
    } else if (camera.projection == CAMERA_ORTHOGRAPHIC) {
        const aspect = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(height));
        const top = @as(f64, camera.fovy) / 2.0;
        const right = top * aspect;
        matProj = MatrixOrtho(-right, right, -top, top, rlGetCullDistanceNear(), rlGetCullDistanceFar());
    }

    const matView = MatrixLookAt(camera.position, camera.target, camera.up);

    var worldPos = Quaternion{ .x = position.x, .y = position.y, .z = position.z, .w = 1.0 };
    worldPos = QuaternionTransform(worldPos, matView);
    worldPos = QuaternionTransform(worldPos, matProj);

    const ndcPos = Vector3{ .x = worldPos.x / worldPos.w, .y = -worldPos.y / worldPos.w, .z = worldPos.z / worldPos.w };

    return .{
        .x = (ndcPos.x + 1.0) / 2.0 * @as(f32, @floatFromInt(width)),
        .y = (ndcPos.y + 1.0) / 2.0 * @as(f32, @floatFromInt(height)),
    };
}

export fn GetWorldToScreen2D(position: Vector2, camera: Camera2D) callconv(.c) Vector2 {
    const matCamera = GetCameraMatrix2D(camera);
    const transform = Vector3Transform(.{ .x = position.x, .y = position.y, .z = 0 }, matCamera);
    return .{ .x = transform.x, .y = transform.y };
}

export fn GetScreenToWorld2D(position: Vector2, camera: Camera2D) callconv(.c) Vector2 {
    const invMatCamera = MatrixInvert(GetCameraMatrix2D(camera));
    const transform = Vector3Transform(.{ .x = position.x, .y = position.y, .z = 0 }, invMatCamera);
    return .{ .x = transform.x, .y = transform.y };
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Timing
//----------------------------------------------------------------------------------

export fn SetTargetFPS(fps: c_int) callconv(.c) void {
    if (fps < 1) CORE.Time.target = 0.0 else CORE.Time.target = 1.0 / @as(f64, @floatFromInt(fps));
    TraceLog(LOG_INFO, "TIMER: Target time per frame: %02.03f milliseconds", @as(f64, @floatCast(@as(f32, @floatCast(CORE.Time.target)) * 1000.0)));
}

var fps_index: c_int = 0;
var fps_capture_frames_counted: c_uint = 0;
var fps_history: [30]f32 = std.mem.zeroes([30]f32);
var fps_average: f32 = 0;
var fps_last: f32 = 0;

export fn GetFPS() callconv(.c) c_int {
    var fps: c_int = 0;
    const FPS_CAPTURE_FRAMES_COUNT: c_int = 30;
    const FPS_AVERAGE_TIME_SECONDS: f32 = 0.5;
    const FPS_STEP: f32 = FPS_AVERAGE_TIME_SECONDS / @as(f32, @floatFromInt(FPS_CAPTURE_FRAMES_COUNT));

    const fpsFrame = GetFrameTime();

    if (CORE.Time.frameCounter == 0) {
        fps_average = 0;
        fps_last = 0;
        fps_index = 0;
        fps_capture_frames_counted = 0;
        var i: usize = 0;
        while (i < FPS_CAPTURE_FRAMES_COUNT) : (i += 1) fps_history[i] = 0;
    }

    if (fpsFrame != 0) {
        if ((GetTime() - fps_last) > FPS_STEP) {
            fps_last = @floatCast(GetTime());
            fps_index = @rem(fps_index + 1, FPS_CAPTURE_FRAMES_COUNT);
            fps_average -= fps_history[@intCast(fps_index)];
            fps_history[@intCast(fps_index)] = fpsFrame / @as(f32, @floatFromInt(FPS_CAPTURE_FRAMES_COUNT));
            fps_average += fps_history[@intCast(fps_index)];

            if (fps_capture_frames_counted < FPS_CAPTURE_FRAMES_COUNT) fps_capture_frames_counted += 1;
        }

        if (fps_capture_frames_counted > 0) {
            const counted: f32 = @floatFromInt(fps_capture_frames_counted);
            fps = @intFromFloat(@round(counted / (fps_average * @as(f32, @floatFromInt(FPS_CAPTURE_FRAMES_COUNT)))));
        }
    } else fps = 0;

    return fps;
}

export fn GetFrameTime() callconv(.c) f32 {
    return @floatCast(CORE.Time.frame);
}

export fn WaitTime(seconds: f64) callconv(.c) void {
    if (seconds < 0) return;

    const destinationTime = GetTime() + seconds;

    // SUPPORT_PARTIALBUSY_WAIT_LOOP = 1 (config.h default)
    const sleepSeconds = seconds - seconds * 0.05;

    var req = std.mem.zeroes(timespec);
    const sec: std.c.time_t = @intFromFloat(sleepSeconds);
    const nsec: c_long = @intFromFloat((sleepSeconds - @as(f64, @floatFromInt(sec))) * 1000000000.0);
    req.sec = sec;
    req.nsec = nsec;
    while (std.c.nanosleep(&req, &req) == -1) continue;

    while (GetTime() < destinationTime) {}
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Misc / random / screenshot / config
//----------------------------------------------------------------------------------

export fn SetRandomSeed(seed: c_uint) callconv(.c) void {
    rprand_set_seed(seed);
}

export fn GetRandomValue(min_in: c_int, max_in: c_int) callconv(.c) c_int {
    var min = min_in;
    var max = max_in;
    if (min > max) {
        const tmp = max;
        max = min;
        min = tmp;
    }
    return rprand_get_value(min, max);
}

export fn LoadRandomSequence(count: c_uint, min: c_int, max: c_int) callconv(.c) [*c]c_int {
    return rprand_load_sequence(count, min, max);
}

export fn UnloadRandomSequence(sequence: [*c]c_int) callconv(.c) void {
    rprand_unload_sequence(sequence);
}

export fn TakeScreenshot(fileName: [*c]const u8) callconv(.c) void {
    if (std.mem.indexOfScalar(u8, std.mem.span(fileName), '\'') != null) {
        TraceLog(LOG_WARNING, "SYSTEM: Provided fileName could be potentially malicious, avoid ['] character");
        return;
    }

    var scale = Vector2{ .x = 1.0, .y = 1.0 };
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) scale = GetWindowScaleDPI();

    const w: c_int = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.render.width)) * scale.x);
    const h: c_int = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.render.height)) * scale.y);
    const imgData = rlReadScreenPixels(w, h);
    defer cmem.free(imgData);
    const image = Image{ .data = imgData, .width = w, .height = h, .mipmaps = 1, .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 };

    // TextFormat's own length limit applies to a relative name, as in raylib
    const fullPath = std.mem.span(if (IsPathAbsolute(fileName)) fileName else TextFormat("%s/%s", CORE.Storage.basePath, fileName));
    var pathBuffer: [MAX_FILEPATH_LENGTH]u8 = undefined;
    const path = returnInBuffer(&pathBuffer, fullPath[0..@min(fullPath.len, pathBuffer.len - 1)]);

    _ = ExportImage(image, path);

    if (FileExists(path)) TraceLog(LOG_INFO, "SYSTEM: [%s] Screenshot taken successfully", path) else TraceLog(LOG_WARNING, "SYSTEM: [%s] Screenshot could not be saved", path);
}

export fn SetConfigFlags(flags: c_uint) callconv(.c) void {
    if (CORE.Window.ready) TraceLog(LOG_WARNING, "WINDOW: SetConfigFlags called after window initialization, Use \"SetWindowState\" to set flags instead");
    flagSet(&CORE.Window.flags, flags);
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Logging system
//----------------------------------------------------------------------------------

export fn SetTraceLogLevel(logType: c_int) callconv(.c) void {
    logTypeLevel = logType;
}

pub export fn TraceLog(logType: c_int, text: [*c]const u8, ...) callconv(.c) void {
    if ((logType < logTypeLevel) or (text == null)) return;

    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    if (traceLogCallbackPtr) |cb| {
        cb(logType, text, c_va.ptr(&ap));
        return;
    }

    const prefix: []const u8 = switch (logType) {
        LOG_TRACE => "TRACE: ",
        LOG_DEBUG => "DEBUG: ",
        LOG_INFO => "INFO: ",
        LOG_WARNING => "WARNING: ",
        LOG_ERROR => "ERROR: ",
        LOG_FATAL => "FATAL: ",
        else => "",
    };
    const message = std.mem.span(text);
    const kept = message[0..@min(message.len, MAX_TRACELOG_MSG_LENGTH - 12)];
    var buffer: [MAX_TRACELOG_MSG_LENGTH]u8 = undefined;
    const format = std.fmt.bufPrint(&buffer, "{s}{s}\n\x00", .{ prefix, kept }) catch unreachable;

    // The message is a C printf format with C variadic arguments: only libc can format it
    _ = vprintf(format.ptr, c_va.arg(&ap));
    _ = fflush(null);

    if (logType == LOG_FATAL) std.process.exit(1);
}

export fn SetTraceLogCallback(callback: TraceLogCallback) callconv(.c) void {
    traceLogCallbackPtr = callback;
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Memory management
//----------------------------------------------------------------------------------

export fn MemAlloc(size: c_uint) callconv(.c) ?*anyopaque {
    const bytes = cmem.alloc(u8, size) catch return null;
    return bytes.ptr;
}
export fn MemRealloc(ptr: ?*anyopaque, size: c_uint) callconv(.c) ?*anyopaque {
    const bytes = cmem.realloc(u8, @ptrCast(ptr), size) catch return null;
    return bytes.ptr;
}
export fn MemFree(ptr: ?*anyopaque) callconv(.c) void {
    cmem.free(ptr);
}

//----------------------------------------------------------------------------------
// Module Functions Definition: File System management
//
// The C API over fs.zig. These wrappers turn C strings into slices, pass the
// process `Io` and the C allocator, and turn errors into raylib's log lines;
// the file system logic itself lives in fs.zig.
//----------------------------------------------------------------------------------

/// The `Io` for file system calls. Zig library code takes an `Io` from its
/// caller, but raylib's C API has no parameter to carry one, so the C ABI
/// edge uses std's process-wide instance.
pub fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

/// For memory handed to C callers, who release it with `free` (through
/// UnloadFileData, UnloadFileText, MemFree): at these alignments
/// `c_allocator` is `malloc`.
const c_allocator = std.heap.c_allocator;

fn cSpan(text: [*c]const u8) ?[:0]const u8 {
    return if (text == null) null else std.mem.span(text);
}

export fn LoadFileData(fileName: [*c]const u8, dataSize: [*c]c_int) callconv(.c) [*c]u8 {
    dataSize.* = 0;
    const path = cSpan(fileName) orelse {
        TraceLog(LOG_WARNING, "FILEIO: File name provided is not valid");
        return null;
    };
    if (loadFileDataCallbackPtr) |callback| return callback(fileName, dataSize);

    const contents = fs.loadFile(io(), c_allocator, path) catch |err| {
        switch (err) {
            error.OpenFailed => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to open file", fileName),
            error.Empty => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to read file", fileName),
            error.TooBig => TraceLog(LOG_WARNING, "FILEIO: [%s] File is bigger than 2147483647 bytes, avoid using LoadFileData()", fileName),
            // C sizes a directory with ftell, which reports LLONG_MAX on ext4: the allocation fails
            error.IsDir, error.OutOfMemory => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to allocated memory for file reading", fileName),
        }
        return null;
    };

    dataSize.* = @intCast(contents.read);
    if (contents.read != contents.data.len) {
        TraceLog(LOG_WARNING, "FILEIO: [%s] File partially loaded (%i bytes out of %i)", fileName, dataSize.*, @as(c_int, @intCast(contents.data.len)));
    } else {
        TraceLog(LOG_INFO, "FILEIO: [%s] File loaded successfully", fileName);
    }
    return contents.data.ptr;
}

export fn UnloadFileData(data: [*c]u8) callconv(.c) void {
    cmem.free(data);
}

export fn SaveFileData(fileName: [*c]const u8, data: ?*anyopaque, dataSize: c_int) callconv(.c) bool {
    const path = cSpan(fileName) orelse {
        TraceLog(LOG_WARNING, "FILEIO: File name provided is not valid");
        return false;
    };
    if (saveFileDataCallbackPtr) |callback| return callback(fileName, data, dataSize);

    const bytes: []const u8 = if (data != null and dataSize > 0) @as([*]const u8, @ptrCast(data.?))[0..@intCast(dataSize)] else &.{};
    fs.saveFile(io(), path, bytes) catch |err| {
        switch (err) {
            error.OpenFailed => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to open file", fileName),
            error.WriteFailed => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to write file", fileName),
        }
        return false;
    };

    // raylib reports writing zero bytes as a failed write, but the save succeeds
    if (bytes.len == 0) {
        TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to write file", fileName);
    } else {
        TraceLog(LOG_INFO, "FILEIO: [%s] File saved successfully", fileName);
    }
    return true;
}

export fn ExportDataAsCode(data: [*c]const u8, dataSize: c_int, fileName: [*c]const u8) callconv(.c) bool {
    const saved = saved: {
        const path = cSpan(fileName) orelse break :saved false;
        if (data == null or dataSize <= 0) break :saved false;
        const text = fs.dataAsCode(c_allocator, data[0..@intCast(dataSize)], path) catch break :saved false;
        defer c_allocator.free(text);
        break :saved SaveFileText(fileName, text.ptr);
    };

    if (saved) {
        TraceLog(LOG_INFO, "FILEIO: [%s] Data as code exported successfully", fileName);
    } else {
        TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export data as code", fileName);
    }
    return saved;
}

export fn LoadFileText(fileName: [*c]const u8) callconv(.c) [*c]u8 {
    const path = cSpan(fileName) orelse {
        TraceLog(LOG_WARNING, "FILEIO: File name provided is not valid");
        return null;
    };
    if (loadFileTextCallbackPtr) |callback| return callback(fileName);

    const text = fs.loadText(io(), c_allocator, path) catch |err| {
        switch (err) {
            error.OpenFailed => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to open text file", fileName),
            error.Empty, error.IsDir => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to read text file", fileName),
            error.TooBig, error.OutOfMemory => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to allocated memory for file reading", fileName),
        }
        return null;
    };

    TraceLog(LOG_INFO, "FILEIO: [%s] Text file loaded successfully", fileName);
    return text.ptr;
}

export fn UnloadFileText(text: [*c]u8) callconv(.c) void {
    cmem.free(text);
}

export fn SaveFileText(fileName: [*c]const u8, text: [*c]u8) callconv(.c) bool {
    const path = cSpan(fileName) orelse {
        TraceLog(LOG_WARNING, "FILEIO: File name provided is not valid");
        return false;
    };
    if (saveFileTextCallbackPtr) |callback| return callback(fileName, text);

    fs.saveFile(io(), path, cSpan(text) orelse "") catch |err| {
        switch (err) {
            error.OpenFailed => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to open text file", fileName),
            error.WriteFailed => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to write text file", fileName),
        }
        return false;
    };

    TraceLog(LOG_INFO, "FILEIO: [%s] Text file saved successfully", fileName);
    return true;
}

export fn SetLoadFileDataCallback(callback: LoadFileDataCallback) callconv(.c) void {
    loadFileDataCallbackPtr = callback;
}
export fn SetSaveFileDataCallback(callback: SaveFileDataCallback) callconv(.c) void {
    saveFileDataCallbackPtr = callback;
}
export fn SetLoadFileTextCallback(callback: LoadFileTextCallback) callconv(.c) void {
    loadFileTextCallbackPtr = callback;
}
export fn SetSaveFileTextCallback(callback: SaveFileTextCallback) callconv(.c) void {
    saveFileTextCallbackPtr = callback;
}

export fn FileRename(fileName: [*c]const u8, fileRename: [*c]const u8) callconv(.c) c_int {
    if (!FileExists(fileName)) return -1;
    const new_path = cSpan(fileRename) orelse return -1;
    const cwd = std.Io.Dir.cwd();
    cwd.rename(std.mem.span(fileName), cwd, new_path, io()) catch return -1;
    return 0;
}

export fn FileRemove(fileName: [*c]const u8) callconv(.c) c_int {
    if (!FileExists(fileName)) return -1;
    fs.remove(io(), std.mem.span(fileName)) catch return -1;
    return 0;
}

export fn FileCopy(srcPath: [*c]const u8, dstPath: [*c]const u8) callconv(.c) c_int {
    var size: c_int = 0;
    const data = LoadFileData(srcPath, &size);
    defer UnloadFileData(data);

    // raylib's result says only whether the destination directory exists or
    // could be made: a missing source or a failed write still returns 0
    const dstDir = GetDirectoryPath(dstPath);
    const result = if (DirectoryExists(dstDir)) 0 else MakeDirectory(dstDir);
    if (result == 0 and data != null and size > 0) _ = SaveFileData(dstPath, data, size);
    return result;
}

export fn FileMove(srcPath: [*c]const u8, dstPath: [*c]const u8) callconv(.c) c_int {
    if (!FileExists(srcPath)) {
        TraceLog(LOG_WARNING, "FILEIO: [%s] Source file does not exist", srcPath);
        return -1;
    }

    const copied = FileCopy(srcPath, dstPath);
    if (copied != 0) return copied;

    if (!FileExists(dstPath) or GetFileLength(srcPath) != GetFileLength(dstPath)) {
        TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to copy file to [%s]", srcPath, dstPath);
        return copied;
    }
    const removed = FileRemove(srcPath);
    if (removed != 0) TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to remove source file after copy", srcPath);
    return removed;
}

export fn FileTextReplace(fileName: [*c]const u8, search: [*c]const u8, replacement: [*c]const u8) callconv(.c) c_int {
    if (!FileExists(fileName)) return -1;

    const text = LoadFileText(fileName);
    defer UnloadFileText(text);
    const updated = TextReplaceAlloc(text, search, replacement);
    if (updated == null) return -1;
    defer MemFree(updated);

    return if (SaveFileText(fileName, updated)) 0 else -1;
}

export fn FileTextFindIndex(fileName: [*c]const u8, search: [*c]const u8) callconv(.c) c_int {
    if (!FileExists(fileName)) return -1;

    const text = LoadFileText(fileName);
    if (text == null) return -1;
    defer UnloadFileText(text);

    const index = std.mem.indexOf(u8, std.mem.span(text), std.mem.span(search)) orelse return -1;
    return @intCast(index);
}

export fn FileExists(fileName: [*c]const u8) callconv(.c) bool {
    const path = cSpan(fileName) orelse return false;
    return fs.exists(io(), path);
}

export fn IsFileExtension(fileName: [*c]const u8, ext: [*c]const u8) callconv(.c) bool {
    const path = cSpan(fileName) orelse return false;
    const extensions = cSpan(ext) orelse return false;
    return fs.hasExtension(path, extensions);
}

/// POSIX rule: a file or directory is hidden when its base name starts with '.'
/// (the "." and ".." entries excepted).
export fn IsFileHidden(filePath: [*c]const u8) callconv(.c) bool {
    const path = std.mem.span(filePath);
    const baseName = if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| path[slash + 1 ..] else path;

    return std.mem.startsWith(u8, baseName, ".") and
        !std.mem.eql(u8, baseName, ".") and !std.mem.eql(u8, baseName, "..");
}

export fn DirectoryExists(dirPath: [*c]const u8) callconv(.c) bool {
    const path = cSpan(dirPath) orelse return false;
    return fs.isDirectory(io(), path);
}

export fn GetFileLength(fileName: [*c]const u8) callconv(.c) c_int {
    const path = cSpan(fileName) orelse return 0;
    const size = fs.fileLength(io(), path) catch |err| switch (err) {
        error.OpenFailed => return 0,
        // C sizes a directory with ftell, which reports LLONG_MAX on ext4
        error.IsDir => std.math.maxInt(u64),
    };
    if (size > std.math.maxInt(c_int)) {
        TraceLog(LOG_WARNING, "[%s] File size overflows expected limit, do not use GetFileLength()", fileName);
        return 0;
    }
    return @intCast(size);
}

export fn GetFileModTime(fileName: [*c]const u8) callconv(.c) c_long {
    const path = cSpan(fileName) orelse return 0;
    const seconds = fs.modTime(io(), path) orelse return 0;
    return @truncate(seconds); // time_t -> long, as C
}

export fn GetFileExtension(fileName: [*c]const u8) callconv(.c) [*c]const u8 {
    const path = cSpan(fileName) orelse return null;
    const ext = fs.extension(path) orelse return null;
    return ext.ptr;
}

export fn GetFileName(filePath: [*c]const u8) callconv(.c) [*c]const u8 {
    const path = cSpan(filePath) orelse return null;
    return fs.fileName(path).ptr;
}

/// Copies `text` into `buf` with a terminator: the static buffers behind the
/// path functions that return `const char *`.
fn returnInBuffer(buf: []u8, text: []const u8) [*:0]const u8 {
    @memcpy(buf[0..text.len], text);
    buf[text.len] = 0;
    return buf[0..text.len :0];
}

var fileNameBuffer: [fs.max_file_name_len + 1]u8 = undefined;
export fn GetFileNameWithoutExt(filePath: [*c]const u8) callconv(.c) [*c]const u8 {
    const stem = if (cSpan(filePath)) |path| fs.fileStem(path) else "";
    return returnInBuffer(&fileNameBuffer, stem);
}

var dirPathBuffer: [MAX_FILEPATH_LENGTH]u8 = undefined;
export fn GetDirectoryPath(filePath: [*c]const u8) callconv(.c) [*c]const u8 {
    const dir = fs.directoryPath(dirPathBuffer[0 .. dirPathBuffer.len - 1], cSpan(filePath) orelse "");
    dirPathBuffer[dir.len] = 0;
    return &dirPathBuffer;
}

var gpdp_prevDirPath: [MAX_FILEPATH_LENGTH]u8 = std.mem.zeroes([MAX_FILEPATH_LENGTH]u8);
export fn GetPrevDirectoryPath(dirPath: [*c]const u8) callconv(.c) [*c]const u8 {
    @memset(&gpdp_prevDirPath, 0);

    const path = std.mem.span(dirPath);
    // A file path first drops its file name, then its last directory
    var isFile = IsPathFile(dirPath);
    var i: isize = @as(isize, @intCast(path.len)) - 1;
    while (i >= 0) : (i -= 1) {
        const idx: usize = @intCast(i);
        if ((path[idx] != '\\') and (path[idx] != '/')) continue;

        // A leading '/' ("/usr") or a drive root ("C:\\") is kept in the result;
        // a trailing separator ("/usr/bin/") is skipped
        if ((idx == 0) or ((idx == 2) and (path[1] == ':'))) {
            i += 1;
        } else if (idx == path.len - 1) continue;

        if (!isFile) {
            const len: usize = @intCast(i);
            @memcpy(gpdp_prevDirPath[0..len], path[0..len]);
            break;
        }
        isFile = false;
    }

    return &gpdp_prevDirPath;
}

var workingDirBuffer: [MAX_FILEPATH_LENGTH]u8 = undefined;
pub export fn GetWorkingDirectory() callconv(.c) [*c]const u8 {
    const len = std.process.currentPath(io(), workingDirBuffer[0 .. workingDirBuffer.len - 1]) catch return null;
    workingDirBuffer[len] = 0;
    return &workingDirBuffer;
}

var appDirBuffer: [MAX_FILEPATH_LENGTH]u8 = undefined;
export fn GetApplicationDirectory() callconv(.c) [*c]const u8 {
    var len = std.process.executableDirPath(io(), appDirBuffer[0 .. appDirBuffer.len - 2]) catch
        return returnInBuffer(&appDirBuffer, "./");
    if (appDirBuffer[len - 1] != '/') {
        appDirBuffer[len] = '/';
        len += 1;
    }
    appDirBuffer[len] = 0;
    return &appDirBuffer;
}

export fn LoadDirectoryFiles(dirPath: [*c]const u8) callconv(.c) FilePathList {
    return LoadDirectoryFilesEx(dirPath, FILE_FILTER_TAG_ALL, false);
}

export fn LoadDirectoryFilesEx(basePath: [*c]const u8, filter: [*c]const u8, scanSubdirs: bool) callconv(.c) FilePathList {
    if (!DirectoryExists(basePath)) {
        TraceLog(LOG_WARNING, "FILEIO: Directory cannot be opened (%s)", basePath);
        return .{ .count = 0, .paths = null };
    }

    // Unlike GetDirectoryFileCountEx, an empty filter here means no filter
    const effectiveFilter: [*c]const u8 = if (filter != null and filter[0] == 0) null else filter;

    // Count first, then fill a list of that size: raylib's two passes, each
    // logging what it skips
    const expected = GetDirectoryFileCountEx(basePath, effectiveFilter, scanSubdirs);
    if (expected == 0) return .{ .count = 0, .paths = null };
    const paths = allocPathList(expected) catch return .{ .count = 0, .paths = null };

    var filler: PathListFiller = .{ .paths = paths };
    directoryScan(effectiveFilter, scanSubdirs).walk(std.mem.span(basePath), &filler) catch |err| switch (err) {};
    if (filler.count != expected) {
        TraceLog(LOG_WARNING, "FILEIO: Read files count (%u) does not match capacity allocated (%u)", @as(c_uint, @intCast(filler.count)), expected);
    }
    return .{ .count = expected, .paths = paths.ptr };
}

// Memory C callers hand back is released with plain `free`: their struct's
// `count`/`capacity` may not be the allocation's length, and Allocator.free
// would write over that many bytes in safe builds.
export fn UnloadDirectoryFiles(files: FilePathList) callconv(.c) void {
    if (files.paths == null) return;
    for (files.paths[0..files.count]) |path| cmem.free(path);
    cmem.free(files.paths);
}

/// `count` paths, each a zeroed MAX_FILEPATH_LENGTH buffer as in raylib, so
/// C callers may rewrite a path in place.
fn allocPathList(count: usize) std.mem.Allocator.Error![][*c]u8 {
    const paths = try c_allocator.alloc([*c]u8, count);
    var allocated: usize = 0;
    errdefer {
        for (paths[0..allocated]) |path| c_allocator.free(path[0..MAX_FILEPATH_LENGTH]);
        c_allocator.free(paths);
    }
    for (paths) |*path| {
        const buf = try c_allocator.alloc(u8, MAX_FILEPATH_LENGTH);
        @memset(buf, 0);
        path.* = buf.ptr;
        allocated += 1;
    }
    return paths;
}

/// Copies scanned paths into a list from `allocPathList`, until it is full.
const PathListFiller = struct {
    paths: [][*c]u8,
    count: usize = 0,

    pub const Error = error{};

    pub fn full(filler: *const PathListFiller) bool {
        return filler.count == filler.paths.len;
    }

    pub fn visit(filler: *PathListFiller, path: [:0]const u8) Error!void {
        @memcpy(filler.paths[filler.count][0..path.len], path);
        filler.count += 1;
    }
};

fn directoryScan(filter: [*c]const u8, recursive: bool) fs.Scan {
    return .{ .io = io(), .filter = .parse(cSpan(filter)), .recursive = recursive, .on_skip = logSkippedPath };
}

fn logSkippedPath(skipped: fs.Skipped) void {
    switch (skipped) {
        .cannot_open => |dir| TraceLog(LOG_WARNING, "FILEIO: Directory cannot be opened (%s)", dir.ptr),
        .path_too_long => |dir| TraceLog(LOG_WARNING, "FILEIO: Path longer than %d characters (%s...)", @as(c_int, MAX_FILEPATH_LENGTH), dir.ptr),
    }
}

export fn MakeDirectory(dirPath: [*c]const u8) callconv(.c) c_int {
    const path = cSpan(dirPath) orelse return -1;
    if (path.len == 0) return -1;
    if (fs.isDirectory(io(), path)) return 0;

    // Checked against the path as given: "a\\b" makes "a/b" yet returns -1, as in raylib
    fs.makeDirectories(io(), path) catch return -1;
    return if (fs.isDirectory(io(), path)) 0 else -1;
}

export fn ChangeDirectory(dirPath: [*c]const u8) callconv(.c) c_int {
    const path = cSpan(dirPath) orelse "";
    std.process.setCurrentPath(io(), path) catch {
        TraceLog(LOG_WARNING, "SYSTEM: Failed to change to directory: %s", dirPath);
        return -1;
    };
    TraceLog(LOG_INFO, "SYSTEM: Working Directory: %s", dirPath);
    return 0;
}

export fn IsPathFile(path: [*c]const u8) callconv(.c) bool {
    const p = cSpan(path) orelse return false;
    return fs.isFile(io(), p);
}

/// NOTE: Mirrors raylib 6.2 exactly: any path that is not a regular file
/// (including a nonexistent one) is reported as a directory.
export fn IsPathDirectory(path: [*c]const u8) callconv(.c) bool {
    return !IsPathFile(path);
}

/// POSIX rule: an absolute path starts with '/'.
export fn IsPathAbsolute(path: [*c]const u8) callconv(.c) bool {
    return (path != null) and (path[0] == '/');
}

export fn IsFileNameValid(fileName: [*c]const u8) callconv(.c) bool {
    const name = cSpan(fileName) orelse return true;
    return fs.isValidFileName(name);
}

export fn IsFileDropped() callconv(.c) bool {
    return CORE.Window.dropFileCount > 0;
}

export fn LoadDroppedFiles() callconv(.c) FilePathList {
    return .{ .count = CORE.Window.dropFileCount, .paths = CORE.Window.dropFilepaths };
}

export fn UnloadDroppedFiles(files: FilePathList) callconv(.c) void {
    if (files.count == 0) return;
    for (files.paths[0..files.count]) |path| cmem.free(path);
    cmem.free(files.paths);
    CORE.Window.dropFileCount = 0;
    CORE.Window.dropFilepaths = null;
}

/// Replaces the dropped-file list with copies of `paths`, which the platform
/// frees when its callback returns. Each copy gets a MAX_FILEPATH_LENGTH
/// buffer, as in raylib.
pub fn setDroppedFiles(paths: []const [*c]const u8) void {
    clearDroppedFiles();
    const list = cmem.alloc([*c]u8, paths.len) catch return;
    var copied: usize = 0;
    for (list, paths) |*copy, path| {
        const buf = cmem.alloc(u8, MAX_FILEPATH_LENGTH) catch break;
        copyCString(buf, path);
        copy.* = buf.ptr;
        copied += 1;
    }
    CORE.Window.dropFilepaths = list.ptr;
    CORE.Window.dropFileCount = @intCast(copied);
}

/// Frees a dropped-file list the user did not unload.
pub fn clearDroppedFiles() void {
    UnloadDroppedFiles(.{ .count = CORE.Window.dropFileCount, .paths = CORE.Window.dropFilepaths });
}

/// Copies the C string `src` into `dst`, cut to leave room for the terminator
/// and zero-filled after it: C's `memset` + `strncpy(dst, src, len - 1)`.
pub fn copyCString(dst: []u8, src: [*c]const u8) void {
    @memset(dst, 0);
    const text = cSpan(src) orelse return;
    const len = @min(text.len, dst.len - 1);
    @memcpy(dst[0..len], text[0..len]);
}

export fn GetDirectoryFileCount(dirPath: [*c]const u8) callconv(.c) c_uint {
    return GetDirectoryFileCountEx(dirPath, FILE_FILTER_TAG_ALL, false);
}

export fn GetDirectoryFileCountEx(basePath: [*c]const u8, filter: [*c]const u8, scanSubdirs: bool) callconv(.c) c_uint {
    const base = cSpan(basePath) orelse {
        TraceLog(LOG_WARNING, "FILEIO: Directory cannot be opened (%s)", basePath);
        return 0;
    };
    return directoryScan(filter, scanSubdirs).count(base);
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Compression and Encoding
//----------------------------------------------------------------------------------

export fn CompressData(data: [*c]const u8, dataSize: c_int, compDataSize: [*c]c_int) callconv(.c) [*c]u8 {
    const quality = 8; // COMPRESSION_QUALITY_DEFLATE

    // sdefl's state is a C struct only rcore_impl.c knows the size of
    const state = std.heap.c_allocator.alignedAlloc(u8, .of(std.c.max_align_t), rl_sizeof_sdefl()) catch return null;
    defer std.heap.c_allocator.free(state);
    @memset(state, 0);

    const compressed = cmem.alloc(u8, @intCast(sdefl_bound(dataSize))) catch return null;
    compDataSize.* = sdeflate(@ptrCast(state.ptr), compressed.ptr, data, dataSize, quality);

    TraceLog(LOG_INFO, "SYSTEM: Compress data: Original size: %i -> Comp. size: %i", dataSize, compDataSize.*);
    return compressed.ptr;
}

export fn DecompressData(compData: [*c]const u8, compDataSize: c_int, dataSize: [*c]c_int) callconv(.c) [*c]u8 {
    const max_size = MAX_DECOMPRESSION_SIZE * 1024 * 1024;

    // Inflate into the largest buffer raylib allows, then keep only what was used
    const scratch = std.heap.c_allocator.alloc(u8, max_size) catch return null;
    defer std.heap.c_allocator.free(scratch);
    const size = sinflate(scratch.ptr, @intCast(max_size), compData, compDataSize);
    if (size < 0) return null;

    const data = cmem.alloc(u8, @intCast(size)) catch return null;
    @memcpy(data, scratch[0..data.len]);

    TraceLog(LOG_INFO, "SYSTEM: Decompress data: Comp. size: %i -> Original size: %i", compDataSize, size);
    dataSize.* = size;
    return data.ptr;
}

/// `size` bytes at `data` as a slice; empty for a null pointer or a size <= 0.
fn cBytes(data: [*c]const u8, size: c_int) []const u8 {
    return if (data == null or size <= 0) &.{} else data[0..@intCast(size)];
}

export fn EncodeDataBase64(data: [*c]const u8, dataSize: c_int, outputSize: [*c]c_int) callconv(.c) [*c]u8 {
    const encoder = std.base64.standard.Encoder;
    const input = cBytes(data, dataSize);

    // NUL-terminated, and the terminator counts in outputSize
    const encoded = cmem.alloc(u8, encoder.calcSize(input.len) + 1) catch return null;
    _ = encoder.encode(encoded[0 .. encoded.len - 1], input);

    outputSize.* = @intCast(encoded.len);
    return encoded.ptr;
}

/// Base64 sextet values; anything outside the alphabet decodes as 0, as in raylib.
const base64Values: [256]u8 = values: {
    var table: [256]u8 = @splat(0);
    for (std.base64.standard_alphabet_chars, 0..) |ch, value| table[ch] = value;
    break :values table;
};

/// raylib's own decoder rather than std's: raylib accepts input std rejects
/// (characters outside the alphabet, missing padding) and logs instead.
export fn DecodeDataBase64(text: [*c]const u8, outputSize: [*c]c_int) callconv(.c) [*c]u8 {
    outputSize.* = 0;
    const encoded = cSpan(text) orelse return null;

    const padding: c_int = @intCast(encoded.len - std.mem.trimEnd(u8, encoded, "=").len);
    const maxOutputSize: c_int = @intCast(3 * (encoded.len / 4));
    const estimatedOutputSize = maxOutputSize - padding;

    const decoded = cmem.alloc(u8, @intCast(maxOutputSize)) catch return null;
    var count: usize = 0;
    var i: usize = 0;
    while (i < encoded.len) : (i += 4) {
        if (i + 2 >= encoded.len) {
            TraceLog(LOG_WARNING, "BASE64: Decoding error: Input data size is not valid");
            break;
        }
        const sextet = struct {
            fn at(chars: []const u8, index: usize) u32 {
                if (index >= chars.len or chars[index] == '=') return 0;
                return base64Values[chars[index]];
            }
        }.at;
        const pack = (@as(u32, base64Values[encoded[i]]) << 18) | (@as(u32, base64Values[encoded[i + 1]]) << 12) |
            (sextet(encoded, i + 2) << 6) | sextet(encoded, i + 3);

        if (count + 3 > decoded.len) {
            TraceLog(LOG_WARNING, "BASE64: Decoding error: Output data size is too small");
            break;
        }
        decoded[count..][0..3].* = .{ @truncate(pack >> 16), @truncate(pack >> 8), @truncate(pack) };
        count += 3;
    }

    if (estimatedOutputSize != @as(c_int, @intCast(count)) - padding) TraceLog(LOG_WARNING, "BASE64: Decoded size differs from estimation");

    outputSize.* = estimatedOutputSize;
    return decoded.ptr;
}

export fn ComputeCRC32(data: [*c]const u8, dataSize: c_int) callconv(.c) c_uint {
    return std.hash.Crc32.hash(cBytes(data, dataSize));
}

/// A hash digest as raylib returns it: the hash state words, which MD5
/// serializes little-endian and the SHA family big-endian.
fn digestWords(comptime n: usize, digest: [4 * n]u8, endian: std.builtin.Endian) [n]c_uint {
    var words: [n]c_uint = undefined;
    for (&words, 0..) |*word, i| word.* = std.mem.readInt(u32, digest[4 * i ..][0..4], endian);
    return words;
}

// raylib returns the hashes in static storage, overwritten by the next call
var md5Hash: [4]c_uint = undefined;
var sha1Hash: [5]c_uint = undefined;
var sha256Hash: [8]c_uint = undefined;

export fn ComputeMD5(data: [*c]const u8, dataSize: c_int) callconv(.c) [*c]c_uint {
    const Md5 = std.crypto.hash.Md5;
    var digest: [Md5.digest_length]u8 = undefined;
    Md5.hash(cBytes(data, dataSize), &digest, .{});
    md5Hash = digestWords(4, digest, .little);
    return &md5Hash;
}

export fn ComputeSHA1(data: [*c]const u8, dataSize: c_int) callconv(.c) [*c]c_uint {
    const Sha1 = std.crypto.hash.Sha1;
    var digest: [Sha1.digest_length]u8 = undefined;
    Sha1.hash(cBytes(data, dataSize), &digest, .{});
    sha1Hash = digestWords(5, digest, .big);
    return &sha1Hash;
}

export fn ComputeSHA256(data: [*c]const u8, dataSize: c_int) callconv(.c) [*c]c_uint {
    const Sha256 = std.crypto.hash.sha2.Sha256;
    var digest: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(cBytes(data, dataSize), &digest, .{});
    sha256Hash = digestWords(8, digest, .big);
    return &sha256Hash;
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Automation Events Recording and Playing
//----------------------------------------------------------------------------------

export fn LoadAutomationEventList(fileName: [*c]const u8) callconv(.c) AutomationEventList {
    const events = c_allocator.alloc(AutomationEvent, MAX_AUTOMATION_EVENTS) catch
        return .{ .capacity = 0, .count = 0, .events = null };
    @memset(events, std.mem.zeroes(AutomationEvent));
    var list: AutomationEventList = .{ .capacity = MAX_AUTOMATION_EVENTS, .count = 0, .events = events.ptr };

    if (fileName == null) {
        TraceLog(LOG_INFO, "AUTOMATION: New empty events list loaded successfully");
        return list;
    }

    // Read directly, as raylib does: the user file callbacks are not involved
    var empty: [0]u8 = .{};
    const contents: fs.Contents = fs.loadFile(io(), c_allocator, std.mem.span(fileName)) catch |err| switch (err) {
        error.Empty => .{ .data = &empty, .read = 0 },
        else => {
            TraceLog(LOG_INFO, "AUTOMATION: Events loaded from file: %i", list.count);
            return list;
        },
    };
    defer c_allocator.free(contents.data);

    const parsed = automation.parse(contents.data[0..contents.read], events, AutomationLog{ .fileName = fileName });
    if (parsed.read != parsed.declared) {
        TraceLog(LOG_WARNING, "AUTOMATION: Events read from file [%i] do not mach event count specified [%i]", parsed.read, parsed.declared);
    }
    list.count = parsed.read;
    TraceLog(LOG_INFO, "AUTOMATION: Events file loaded successfully");
    TraceLog(LOG_INFO, "AUTOMATION: Events loaded from file: %i", list.count);
    return list;
}

/// raylib's log lines for `automation.parse`.
const AutomationLog = struct {
    fileName: [*c]const u8,

    pub fn readIssue(log: AutomationLog) void {
        TraceLog(LOG_WARNING, "AUTOMATION: [%s] Issue reading line to buffer", log.fileName);
    }

    pub fn beyondCapacity(_: AutomationLog, line: [:0]const u8) void {
        TraceLog(LOG_WARNING, "AUTOMATION: Event goes beyond automated list capacity (MAX: %u): %s", @as(c_uint, MAX_AUTOMATION_EVENTS), line.ptr);
    }
};

export fn UnloadAutomationEventList(list: AutomationEventList) callconv(.c) void {
    cmem.free(list.events);
}

export fn ExportAutomationEventList(list: AutomationEventList, fileName: [*c]const u8) callconv(.c) bool {
    const events: []const AutomationEvent = if (list.count == 0) &.{} else list.events[0..list.count];
    const text = automation.format(c_allocator, events) catch return false;
    defer c_allocator.free(text);
    return SaveFileText(fileName, text.ptr);
}

export fn SetAutomationEventList(list: ?*AutomationEventList) callconv(.c) void {
    currentEventList = list;
}

export fn SetAutomationEventBaseFrame(frame: c_int) callconv(.c) void {
    CORE.Time.frameCounter = @intCast(frame);
}

export fn StartAutomationEventRecording() callconv(.c) void {
    automationEventRecording = true;
}

export fn StopAutomationEventRecording() callconv(.c) void {
    automationEventRecording = false;
}

export fn PlayAutomationEvent(event: AutomationEvent) callconv(.c) void {
    if (!automationEventRecording) {
        switch (event.type) {
            INPUT_KEY_UP => CORE.Input.Keyboard.currentKeyState[@intCast(event.params[0])] = 0,
            INPUT_KEY_DOWN => {
                CORE.Input.Keyboard.currentKeyState[@intCast(event.params[0])] = 1;
                if (CORE.Input.Keyboard.previousKeyState[@intCast(event.params[0])] == 0) {
                    if (CORE.Input.Keyboard.keyPressedQueueCount < MAX_KEY_PRESSED_QUEUE) {
                        CORE.Input.Keyboard.keyPressedQueue[@intCast(CORE.Input.Keyboard.keyPressedQueueCount)] = event.params[0];
                        CORE.Input.Keyboard.keyPressedQueueCount += 1;
                    }
                }
            },
            INPUT_MOUSE_BUTTON_UP => CORE.Input.Mouse.currentButtonState[@intCast(event.params[0])] = 0,
            INPUT_MOUSE_BUTTON_DOWN => CORE.Input.Mouse.currentButtonState[@intCast(event.params[0])] = 1,
            INPUT_MOUSE_POSITION => {
                CORE.Input.Mouse.currentPosition.x = @floatFromInt(event.params[0]);
                CORE.Input.Mouse.currentPosition.y = @floatFromInt(event.params[1]);
            },
            INPUT_MOUSE_WHEEL_MOTION => {
                CORE.Input.Mouse.currentWheelMove.x = @floatFromInt(event.params[0]);
                CORE.Input.Mouse.currentWheelMove.y = @floatFromInt(event.params[1]);
            },
            INPUT_TOUCH_UP => CORE.Input.Touch.currentTouchState[@intCast(event.params[0])] = 0,
            INPUT_TOUCH_DOWN => CORE.Input.Touch.currentTouchState[@intCast(event.params[0])] = 1,
            INPUT_TOUCH_POSITION => {
                CORE.Input.Touch.position[@intCast(event.params[0])].x = @floatFromInt(event.params[1]);
                CORE.Input.Touch.position[@intCast(event.params[0])].y = @floatFromInt(event.params[2]);
            },
            INPUT_GAMEPAD_CONNECT => CORE.Input.Gamepad.ready[@intCast(event.params[0])] = true,
            INPUT_GAMEPAD_DISCONNECT => CORE.Input.Gamepad.ready[@intCast(event.params[0])] = false,
            INPUT_GAMEPAD_BUTTON_UP => CORE.Input.Gamepad.currentButtonState[@intCast(event.params[0])][@intCast(event.params[1])] = 0,
            INPUT_GAMEPAD_BUTTON_DOWN => CORE.Input.Gamepad.currentButtonState[@intCast(event.params[0])][@intCast(event.params[1])] = 1,
            INPUT_GAMEPAD_AXIS_MOTION => {
                CORE.Input.Gamepad.axisState[@intCast(event.params[0])][@intCast(event.params[1])] = @as(f32, @floatFromInt(event.params[2])) / 32768.0;
            },
            WINDOW_CLOSE => CORE.Window.shouldClose = true,
            WINDOW_MAXIMIZE => MaximizeWindow(),
            WINDOW_MINIMIZE => MinimizeWindow(),
            WINDOW_RESIZE => SetWindowSize(event.params[0], event.params[1]),
            ACTION_TAKE_SCREENSHOT => {
                TakeScreenshot(TextFormat("screenshot%03i.png", screenshotCounter));
                screenshotCounter += 1;
            },
            ACTION_SETTARGETFPS => SetTargetFPS(event.params[0]),
            else => {},
        }

        TraceLog(LOG_INFO, "AUTOMATION PLAY: Frame: %i | Event type: %i | Event parameters: %i, %i, %i", event.frame, event.type, event.params[0], event.params[1], event.params[2]);
    }
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Input Handling: Keyboard
//----------------------------------------------------------------------------------

export fn IsKeyPressed(key: c_int) callconv(.c) bool {
    var pressed = false;
    if ((key > 0) and (key < MAX_KEYBOARD_KEYS)) {
        if ((CORE.Input.Keyboard.previousKeyState[@intCast(key)] == 0) and (CORE.Input.Keyboard.currentKeyState[@intCast(key)] == 1)) pressed = true;
    }
    return pressed;
}

export fn IsKeyPressedRepeat(key: c_int) callconv(.c) bool {
    var repeat = false;
    if ((key > 0) and (key < MAX_KEYBOARD_KEYS)) {
        if (CORE.Input.Keyboard.keyRepeatInFrame[@intCast(key)] == 1) repeat = true;
    }
    return repeat;
}

export fn IsKeyDown(key: c_int) callconv(.c) bool {
    var down = false;
    if ((key > 0) and (key < MAX_KEYBOARD_KEYS)) {
        if (CORE.Input.Keyboard.currentKeyState[@intCast(key)] == 1) down = true;
    }
    return down;
}

export fn IsKeyReleased(key: c_int) callconv(.c) bool {
    var released = false;
    if ((key > 0) and (key < MAX_KEYBOARD_KEYS)) {
        if ((CORE.Input.Keyboard.previousKeyState[@intCast(key)] == 1) and (CORE.Input.Keyboard.currentKeyState[@intCast(key)] == 0)) released = true;
    }
    return released;
}

export fn IsKeyUp(key: c_int) callconv(.c) bool {
    var up = false;
    if ((key > 0) and (key < MAX_KEYBOARD_KEYS)) {
        if (CORE.Input.Keyboard.currentKeyState[@intCast(key)] == 0) up = true;
    }
    return up;
}

export fn GetKeyPressed() callconv(.c) c_int {
    var value: c_int = 0;
    if (CORE.Input.Keyboard.keyPressedQueueCount > 0) {
        value = CORE.Input.Keyboard.keyPressedQueue[0];
        var i: usize = 0;
        while (i < CORE.Input.Keyboard.keyPressedQueueCount - 1) : (i += 1) CORE.Input.Keyboard.keyPressedQueue[i] = CORE.Input.Keyboard.keyPressedQueue[i + 1];
        CORE.Input.Keyboard.keyPressedQueue[@intCast(CORE.Input.Keyboard.keyPressedQueueCount - 1)] = 0;
        CORE.Input.Keyboard.keyPressedQueueCount -= 1;
    }
    return value;
}

export fn GetCharPressed() callconv(.c) c_int {
    var value: c_int = 0;
    if (CORE.Input.Keyboard.charPressedQueueCount > 0) {
        value = CORE.Input.Keyboard.charPressedQueue[0];
        var i: usize = 0;
        while (i < CORE.Input.Keyboard.charPressedQueueCount - 1) : (i += 1) CORE.Input.Keyboard.charPressedQueue[i] = CORE.Input.Keyboard.charPressedQueue[i + 1];
        CORE.Input.Keyboard.charPressedQueue[@intCast(CORE.Input.Keyboard.charPressedQueueCount - 1)] = 0;
        CORE.Input.Keyboard.charPressedQueueCount -= 1;
    }
    return value;
}

export fn SetExitKey(key: c_int) callconv(.c) void {
    CORE.Input.Keyboard.exitKey = key;
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Input Handling: Gamepad
//----------------------------------------------------------------------------------

export fn IsGamepadAvailable(gamepad: c_int) callconv(.c) bool {
    var result = false;
    if ((gamepad >= 0) and (gamepad < MAX_GAMEPADS) and CORE.Input.Gamepad.ready[@intCast(gamepad)]) result = true;
    return result;
}

export fn GetGamepadName(gamepad: c_int) callconv(.c) [*c]const u8 {
    var name: [*c]const u8 = null;
    if ((gamepad >= 0) and (gamepad < MAX_GAMEPADS)) name = &CORE.Input.Gamepad.name[@intCast(gamepad)];
    return name;
}

export fn IsGamepadButtonPressed(gamepad: c_int, button: c_int) callconv(.c) bool {
    var pressed = false;
    if ((gamepad >= 0) and (gamepad < MAX_GAMEPADS) and CORE.Input.Gamepad.ready[@intCast(gamepad)] and (button < MAX_GAMEPAD_BUTTONS)) {
        if ((CORE.Input.Gamepad.previousButtonState[@intCast(gamepad)][@intCast(button)] == 0) and (CORE.Input.Gamepad.currentButtonState[@intCast(gamepad)][@intCast(button)] == 1)) pressed = true;
    }
    return pressed;
}

export fn IsGamepadButtonDown(gamepad: c_int, button: c_int) callconv(.c) bool {
    var down = false;
    if ((gamepad >= 0) and (gamepad < MAX_GAMEPADS) and CORE.Input.Gamepad.ready[@intCast(gamepad)] and (button < MAX_GAMEPAD_BUTTONS)) {
        if (CORE.Input.Gamepad.currentButtonState[@intCast(gamepad)][@intCast(button)] == 1) down = true;
    }
    return down;
}

export fn IsGamepadButtonReleased(gamepad: c_int, button: c_int) callconv(.c) bool {
    var released = false;
    if ((gamepad >= 0) and (gamepad < MAX_GAMEPADS) and CORE.Input.Gamepad.ready[@intCast(gamepad)] and (button < MAX_GAMEPAD_BUTTONS)) {
        if ((CORE.Input.Gamepad.previousButtonState[@intCast(gamepad)][@intCast(button)] == 1) and (CORE.Input.Gamepad.currentButtonState[@intCast(gamepad)][@intCast(button)] == 0)) released = true;
    }
    return released;
}

export fn IsGamepadButtonUp(gamepad: c_int, button: c_int) callconv(.c) bool {
    var up = false;
    if ((gamepad >= 0) and (gamepad < MAX_GAMEPADS) and CORE.Input.Gamepad.ready[@intCast(gamepad)] and (button < MAX_GAMEPAD_BUTTONS)) {
        if (CORE.Input.Gamepad.currentButtonState[@intCast(gamepad)][@intCast(button)] == 0) up = true;
    }
    return up;
}

export fn GetGamepadButtonPressed() callconv(.c) c_int {
    return CORE.Input.Gamepad.lastButtonPressed;
}

export fn GetGamepadAxisCount(gamepad: c_int) callconv(.c) c_int {
    var result: c_int = 0;
    if ((gamepad >= 0) and (gamepad < MAX_GAMEPADS)) result = CORE.Input.Gamepad.axisCount[@intCast(gamepad)];
    return result;
}

export fn GetGamepadAxisMovement(gamepad: c_int, axis: c_int) callconv(.c) f32 {
    var value: f32 = if ((axis == GAMEPAD_AXIS_LEFT_TRIGGER) or (axis == GAMEPAD_AXIS_RIGHT_TRIGGER)) -1.0 else 0.0;

    if ((gamepad >= 0) and (gamepad < MAX_GAMEPADS) and CORE.Input.Gamepad.ready[@intCast(gamepad)] and (axis < MAX_GAMEPAD_AXES)) {
        const movement = if (value < 0.0) CORE.Input.Gamepad.axisState[@intCast(gamepad)][@intCast(axis)] else @abs(CORE.Input.Gamepad.axisState[@intCast(gamepad)][@intCast(axis)]);
        if (movement > value) value = CORE.Input.Gamepad.axisState[@intCast(gamepad)][@intCast(axis)];
    }

    return value;
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Input Handling: Mouse
//----------------------------------------------------------------------------------

export fn IsMouseButtonPressed(button: c_int) callconv(.c) bool {
    var pressed = false;
    if ((button >= 0) and (button <= MOUSE_BUTTON_BACK)) {
        if ((CORE.Input.Mouse.currentButtonState[@intCast(button)] == 1) and (CORE.Input.Mouse.previousButtonState[@intCast(button)] == 0)) pressed = true;
        if ((CORE.Input.Touch.currentTouchState[@intCast(button)] == 1) and (CORE.Input.Touch.previousTouchState[@intCast(button)] == 0)) pressed = true;
    }
    return pressed;
}

export fn IsMouseButtonDown(button: c_int) callconv(.c) bool {
    var down = false;
    if ((button >= 0) and (button <= MOUSE_BUTTON_BACK)) {
        if (CORE.Input.Mouse.currentButtonState[@intCast(button)] == 1) down = true;
        if (CORE.Input.Touch.currentTouchState[@intCast(button)] == 1) down = true;
    }
    return down;
}

export fn IsMouseButtonReleased(button: c_int) callconv(.c) bool {
    var released = false;
    if ((button >= 0) and (button <= MOUSE_BUTTON_BACK)) {
        if ((CORE.Input.Mouse.currentButtonState[@intCast(button)] == 0) and (CORE.Input.Mouse.previousButtonState[@intCast(button)] == 1)) released = true;
        if ((CORE.Input.Touch.currentTouchState[@intCast(button)] == 0) and (CORE.Input.Touch.previousTouchState[@intCast(button)] == 1)) released = true;
    }
    return released;
}

export fn IsMouseButtonUp(button: c_int) callconv(.c) bool {
    var up = false;
    if ((button >= 0) and (button <= MOUSE_BUTTON_BACK)) {
        if (CORE.Input.Mouse.currentButtonState[@intCast(button)] == 0) up = true;
        if (CORE.Input.Touch.currentTouchState[@intCast(button)] == 0) up = true;
    }
    return up;
}

pub export fn GetMouseX() callconv(.c) c_int {
    return @intFromFloat((CORE.Input.Mouse.currentPosition.x + CORE.Input.Mouse.offset.x) * CORE.Input.Mouse.scale.x);
}
pub export fn GetMouseY() callconv(.c) c_int {
    return @intFromFloat((CORE.Input.Mouse.currentPosition.y + CORE.Input.Mouse.offset.y) * CORE.Input.Mouse.scale.y);
}

pub export fn GetMousePosition() callconv(.c) Vector2 {
    return .{
        .x = (CORE.Input.Mouse.currentPosition.x + CORE.Input.Mouse.offset.x) * CORE.Input.Mouse.scale.x,
        .y = (CORE.Input.Mouse.currentPosition.y + CORE.Input.Mouse.offset.y) * CORE.Input.Mouse.scale.y,
    };
}

export fn GetMouseDelta() callconv(.c) Vector2 {
    return .{
        .x = (CORE.Input.Mouse.currentPosition.x - CORE.Input.Mouse.previousPosition.x) * CORE.Input.Mouse.scale.x,
        .y = (CORE.Input.Mouse.currentPosition.y - CORE.Input.Mouse.previousPosition.y) * CORE.Input.Mouse.scale.y,
    };
}

export fn SetMouseOffset(offsetX: c_int, offsetY: c_int) callconv(.c) void {
    CORE.Input.Mouse.offset = .{ .x = @floatFromInt(offsetX), .y = @floatFromInt(offsetY) };
}

pub export fn SetMouseScale(scaleX: f32, scaleY: f32) callconv(.c) void {
    CORE.Input.Mouse.scale = .{ .x = scaleX, .y = scaleY };
}

export fn GetMouseWheelMove() callconv(.c) f32 {
    var result: f32 = 0.0;
    if (@abs(CORE.Input.Mouse.currentWheelMove.x) > @abs(CORE.Input.Mouse.currentWheelMove.y)) result = CORE.Input.Mouse.currentWheelMove.x else result = CORE.Input.Mouse.currentWheelMove.y;
    return result;
}

export fn GetMouseWheelMoveV() callconv(.c) Vector2 {
    return CORE.Input.Mouse.currentWheelMove;
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Input Handling: Touch
//----------------------------------------------------------------------------------

export fn GetTouchX() callconv(.c) c_int {
    return @intFromFloat(CORE.Input.Touch.position[0].x);
}
export fn GetTouchY() callconv(.c) c_int {
    return @intFromFloat(CORE.Input.Touch.position[0].y);
}

export fn GetTouchPosition(index: c_int) callconv(.c) Vector2 {
    var position = Vector2{ .x = -1.0, .y = -1.0 };
    if (index < MAX_TOUCH_POINTS) position = CORE.Input.Touch.position[@intCast(index)] else TraceLog(LOG_WARNING, "INPUT: Required touch point out of range (Max touch points: %i)", @as(c_int, MAX_TOUCH_POINTS));
    return position;
}

export fn GetTouchPointId(index: c_int) callconv(.c) c_int {
    var id: c_int = -1;
    if (index < MAX_TOUCH_POINTS) id = CORE.Input.Touch.pointId[@intCast(index)];
    return id;
}

export fn GetTouchPointCount() callconv(.c) c_int {
    return CORE.Input.Touch.pointCount;
}

//----------------------------------------------------------------------------------
// Module Internal Functions (common, non-platform)
//----------------------------------------------------------------------------------

// Initialize hi-resolution timer
pub fn InitTimer() void {
    var now = std.mem.zeroes(timespec);
    if (std.c.clock_gettime(.MONOTONIC, &now) == 0) {
        CORE.Time.base = @as(c_ulonglong, @intCast(now.sec)) * 1000000000 + @as(c_ulonglong, @intCast(now.nsec));
    } else TraceLog(LOG_WARNING, "TIMER: Hi-resolution timer not available");

    CORE.Time.previous = GetTime();
}

// Set viewport for a provided width and height
pub fn SetupViewport(width: c_int, height: c_int) void {
    CORE.Window.render.width = @intCast(width);
    CORE.Window.render.height = @intCast(height);

    rlViewport(@divTrunc(CORE.Window.renderOffset.x, 2), @divTrunc(CORE.Window.renderOffset.y, 2), @intCast(CORE.Window.render.width), @intCast(CORE.Window.render.height));

    rlMatrixMode(RL_PROJECTION);
    rlLoadIdentity();

    rlOrtho(0, @floatFromInt(CORE.Window.render.width), @floatFromInt(CORE.Window.render.height), 0, 0.0, 1.0);

    rlMatrixMode(RL_MODELVIEW);
    rlLoadIdentity();
}

// Automation event recording
fn RecordAutomationEvent() void {
    const list = currentEventList orelse return;
    if (list.count == list.capacity) return;

    // Keyboard
    var key: c_int = 0;
    while (key < MAX_KEYBOARD_KEYS) : (key += 1) {
        if ((CORE.Input.Keyboard.previousKeyState[@intCast(key)] != 0) and (CORE.Input.Keyboard.currentKeyState[@intCast(key)] == 0)) {
            list.events[list.count].frame = CORE.Time.frameCounter;
            list.events[list.count].type = INPUT_KEY_UP;
            list.events[list.count].params[0] = key;
            list.events[list.count].params[1] = 0;
            list.events[list.count].params[2] = 0;
            list.count += 1;
        }
        if (list.count == list.capacity) return;

        if (CORE.Input.Keyboard.currentKeyState[@intCast(key)] != 0) {
            list.events[list.count].frame = CORE.Time.frameCounter;
            list.events[list.count].type = INPUT_KEY_DOWN;
            list.events[list.count].params[0] = key;
            list.events[list.count].params[1] = 0;
            list.events[list.count].params[2] = 0;
            list.count += 1;
        }
        if (list.count == list.capacity) return;
    }

    // Mouse buttons
    var button: c_int = 0;
    while (button < MAX_MOUSE_BUTTONS) : (button += 1) {
        if ((CORE.Input.Mouse.previousButtonState[@intCast(button)] != 0) and (CORE.Input.Mouse.currentButtonState[@intCast(button)] == 0)) {
            list.events[list.count].frame = CORE.Time.frameCounter;
            list.events[list.count].type = INPUT_MOUSE_BUTTON_UP;
            list.events[list.count].params[0] = button;
            list.events[list.count].params[1] = 0;
            list.events[list.count].params[2] = 0;
            list.count += 1;
        }
        if (list.count == list.capacity) return;

        if (CORE.Input.Mouse.currentButtonState[@intCast(button)] != 0) {
            list.events[list.count].frame = CORE.Time.frameCounter;
            list.events[list.count].type = INPUT_MOUSE_BUTTON_DOWN;
            list.events[list.count].params[0] = button;
            list.events[list.count].params[1] = 0;
            list.events[list.count].params[2] = 0;
            list.count += 1;
        }
        if (list.count == list.capacity) return;
    }

    // Mouse position
    if ((@as(c_int, @intFromFloat(CORE.Input.Mouse.currentPosition.x)) != @as(c_int, @intFromFloat(CORE.Input.Mouse.previousPosition.x))) or
        (@as(c_int, @intFromFloat(CORE.Input.Mouse.currentPosition.y)) != @as(c_int, @intFromFloat(CORE.Input.Mouse.previousPosition.y))))
    {
        list.events[list.count].frame = CORE.Time.frameCounter;
        list.events[list.count].type = INPUT_MOUSE_POSITION;
        list.events[list.count].params[0] = @intFromFloat(CORE.Input.Mouse.currentPosition.x);
        list.events[list.count].params[1] = @intFromFloat(CORE.Input.Mouse.currentPosition.y);
        list.events[list.count].params[2] = 0;
        list.count += 1;
        if (list.count == list.capacity) return;
    }

    // Mouse wheel
    if ((@as(c_int, @intFromFloat(CORE.Input.Mouse.currentWheelMove.x)) != @as(c_int, @intFromFloat(CORE.Input.Mouse.previousWheelMove.x))) or
        (@as(c_int, @intFromFloat(CORE.Input.Mouse.currentWheelMove.y)) != @as(c_int, @intFromFloat(CORE.Input.Mouse.previousWheelMove.y))))
    {
        list.events[list.count].frame = CORE.Time.frameCounter;
        list.events[list.count].type = INPUT_MOUSE_WHEEL_MOTION;
        list.events[list.count].params[0] = @intFromFloat(CORE.Input.Mouse.currentWheelMove.x);
        list.events[list.count].params[1] = @intFromFloat(CORE.Input.Mouse.currentWheelMove.y);
        list.events[list.count].params[2] = 0;
        list.count += 1;
        if (list.count == list.capacity) return;
    }

    // Touch
    var id: c_int = 0;
    while (id < MAX_TOUCH_POINTS) : (id += 1) {
        if ((CORE.Input.Touch.previousTouchState[@intCast(id)] != 0) and (CORE.Input.Touch.currentTouchState[@intCast(id)] == 0)) {
            list.events[list.count].frame = CORE.Time.frameCounter;
            list.events[list.count].type = INPUT_TOUCH_UP;
            list.events[list.count].params[0] = id;
            list.events[list.count].params[1] = 0;
            list.events[list.count].params[2] = 0;
            list.count += 1;
        }
        if (list.count == list.capacity) return;

        if (CORE.Input.Touch.currentTouchState[@intCast(id)] != 0) {
            list.events[list.count].frame = CORE.Time.frameCounter;
            list.events[list.count].type = INPUT_TOUCH_DOWN;
            list.events[list.count].params[0] = id;
            list.events[list.count].params[1] = 0;
            list.events[list.count].params[2] = 0;
            list.count += 1;
        }
        if (list.count == list.capacity) return;

        if ((@as(c_int, @intFromFloat(CORE.Input.Touch.position[@intCast(id)].x)) != @as(c_int, @intFromFloat(CORE.Input.Touch.previousPosition[@intCast(id)].x))) or
            (@as(c_int, @intFromFloat(CORE.Input.Touch.position[@intCast(id)].y)) != @as(c_int, @intFromFloat(CORE.Input.Touch.previousPosition[@intCast(id)].y))))
        {
            list.events[list.count].frame = CORE.Time.frameCounter;
            list.events[list.count].type = INPUT_TOUCH_POSITION;
            list.events[list.count].params[0] = id;
            list.events[list.count].params[1] = @intFromFloat(CORE.Input.Touch.position[@intCast(id)].x);
            list.events[list.count].params[2] = @intFromFloat(CORE.Input.Touch.position[@intCast(id)].y);
            list.count += 1;
        }
        if (list.count == list.capacity) return;
    }

    // Gamepad
    var gamepad: c_int = 0;
    while (gamepad < MAX_GAMEPADS) : (gamepad += 1) {
        var b: c_int = 0;
        while (b < MAX_GAMEPAD_BUTTONS) : (b += 1) {
            if ((CORE.Input.Gamepad.previousButtonState[@intCast(gamepad)][@intCast(b)] != 0) and (CORE.Input.Gamepad.currentButtonState[@intCast(gamepad)][@intCast(b)] == 0)) {
                list.events[list.count].frame = CORE.Time.frameCounter;
                list.events[list.count].type = INPUT_GAMEPAD_BUTTON_UP;
                list.events[list.count].params[0] = gamepad;
                list.events[list.count].params[1] = b;
                list.events[list.count].params[2] = 0;
                list.count += 1;
            }
            if (list.count == list.capacity) return;

            if (CORE.Input.Gamepad.currentButtonState[@intCast(gamepad)][@intCast(b)] != 0) {
                list.events[list.count].frame = CORE.Time.frameCounter;
                list.events[list.count].type = INPUT_GAMEPAD_BUTTON_DOWN;
                list.events[list.count].params[0] = gamepad;
                list.events[list.count].params[1] = b;
                list.events[list.count].params[2] = 0;
                list.count += 1;
            }
            if (list.count == list.capacity) return;
        }

        var axis: c_int = 0;
        while (axis < MAX_GAMEPAD_AXES) : (axis += 1) {
            const defaultMovement: f32 = if ((axis == GAMEPAD_AXIS_LEFT_TRIGGER) or (axis == GAMEPAD_AXIS_RIGHT_TRIGGER)) -1.0 else 0.0;
            if (GetGamepadAxisMovement(gamepad, axis) != defaultMovement) {
                list.events[list.count].frame = CORE.Time.frameCounter;
                list.events[list.count].type = INPUT_GAMEPAD_AXIS_MOTION;
                list.events[list.count].params[0] = gamepad;
                list.events[list.count].params[1] = axis;
                list.events[list.count].params[2] = @intFromFloat(CORE.Input.Gamepad.axisState[@intCast(gamepad)][@intCast(axis)] * 32768.0);
                list.count += 1;
            }
            if (list.count == list.capacity) return;
        }
    }
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Camera System (ported from rcamera.h)
//----------------------------------------------------------------------------------

export fn UpdateCamera(camera: *Camera, mode: c_int) callconv(.c) void {
    const mousePositionDelta = GetMouseDelta();

    const moveInWorldPlane = (mode == CAMERA_FIRST_PERSON) or (mode == CAMERA_THIRD_PERSON);
    const rotateAroundTarget = (mode == CAMERA_THIRD_PERSON) or (mode == CAMERA_ORBITAL);
    const lockView = (mode == CAMERA_FREE) or (mode == CAMERA_FIRST_PERSON) or (mode == CAMERA_THIRD_PERSON) or (mode == CAMERA_ORBITAL);
    const rotateUp = false;

    const cameraMoveSpeed = CAMERA_MOVE_SPEED * GetFrameTime();
    const cameraRotationSpeed = CAMERA_ROTATION_SPEED * GetFrameTime();
    const cameraPanSpeed = CAMERA_PAN_SPEED * GetFrameTime();
    const cameraOrbitalSpeed = CAMERA_ORBITAL_SPEED * GetFrameTime();

    if (mode == CAMERA_CUSTOM) {} else if (mode == CAMERA_ORBITAL) {
        const rotation = MatrixRotate(GetCameraUp(camera), cameraOrbitalSpeed);
        var view = Vector3Subtract(camera.position, camera.target);
        view = Vector3Transform(view, rotation);
        camera.position = Vector3Add(camera.target, view);
    } else {
        if (IsKeyDown(KEY_DOWN)) CameraPitch(camera, -cameraRotationSpeed, lockView, rotateAroundTarget, rotateUp);
        if (IsKeyDown(KEY_UP)) CameraPitch(camera, cameraRotationSpeed, lockView, rotateAroundTarget, rotateUp);
        if (IsKeyDown(KEY_RIGHT)) CameraYaw(camera, -cameraRotationSpeed, rotateAroundTarget);
        if (IsKeyDown(KEY_LEFT)) CameraYaw(camera, cameraRotationSpeed, rotateAroundTarget);
        if (IsKeyDown(KEY_Q)) CameraRoll(camera, -cameraRotationSpeed);
        if (IsKeyDown(KEY_E)) CameraRoll(camera, cameraRotationSpeed);

        if ((mode == CAMERA_FREE) and IsMouseButtonDown(MOUSE_BUTTON_MIDDLE)) {
            const mouseDelta = GetMouseDelta();
            if (mouseDelta.x > 0.0) CameraMoveRight(camera, cameraPanSpeed, moveInWorldPlane);
            if (mouseDelta.x < 0.0) CameraMoveRight(camera, -cameraPanSpeed, moveInWorldPlane);
            if (mouseDelta.y > 0.0) CameraMoveUp(camera, -cameraPanSpeed);
            if (mouseDelta.y < 0.0) CameraMoveUp(camera, cameraPanSpeed);
        } else {
            CameraYaw(camera, -mousePositionDelta.x * CAMERA_MOUSE_MOVE_SENSITIVITY, rotateAroundTarget);
            CameraPitch(camera, -mousePositionDelta.y * CAMERA_MOUSE_MOVE_SENSITIVITY, lockView, rotateAroundTarget, rotateUp);
        }

        if (IsKeyDown(KEY_W)) CameraMoveForward(camera, cameraMoveSpeed, moveInWorldPlane);
        if (IsKeyDown(KEY_A)) CameraMoveRight(camera, -cameraMoveSpeed, moveInWorldPlane);
        if (IsKeyDown(KEY_S)) CameraMoveForward(camera, -cameraMoveSpeed, moveInWorldPlane);
        if (IsKeyDown(KEY_D)) CameraMoveRight(camera, cameraMoveSpeed, moveInWorldPlane);

        if (IsGamepadAvailable(0)) {
            CameraYaw(camera, -(GetGamepadAxisMovement(0, GAMEPAD_AXIS_RIGHT_X) * 2) * CAMERA_MOUSE_MOVE_SENSITIVITY, rotateAroundTarget);
            CameraPitch(camera, -(GetGamepadAxisMovement(0, GAMEPAD_AXIS_RIGHT_Y) * 2) * CAMERA_MOUSE_MOVE_SENSITIVITY, lockView, rotateAroundTarget, rotateUp);

            if (GetGamepadAxisMovement(0, GAMEPAD_AXIS_LEFT_Y) <= -0.25) CameraMoveForward(camera, cameraMoveSpeed, moveInWorldPlane);
            if (GetGamepadAxisMovement(0, GAMEPAD_AXIS_LEFT_X) <= -0.25) CameraMoveRight(camera, -cameraMoveSpeed, moveInWorldPlane);
            if (GetGamepadAxisMovement(0, GAMEPAD_AXIS_LEFT_Y) >= 0.25) CameraMoveForward(camera, -cameraMoveSpeed, moveInWorldPlane);
            if (GetGamepadAxisMovement(0, GAMEPAD_AXIS_LEFT_X) >= 0.25) CameraMoveRight(camera, cameraMoveSpeed, moveInWorldPlane);
        }

        if (mode == CAMERA_FREE) {
            if (IsKeyDown(KEY_SPACE)) CameraMoveUp(camera, cameraMoveSpeed);
            if (IsKeyDown(KEY_LEFT_CONTROL)) CameraMoveUp(camera, -cameraMoveSpeed);
        }
    }

    if ((mode == CAMERA_THIRD_PERSON) or (mode == CAMERA_ORBITAL) or (mode == CAMERA_FREE)) {
        CameraMoveToTarget(camera, -GetMouseWheelMove());
        if (IsKeyPressed(KEY_KP_SUBTRACT)) CameraMoveToTarget(camera, 2.0);
        if (IsKeyPressed(KEY_KP_ADD)) CameraMoveToTarget(camera, -2.0);
    }
}

export fn UpdateCameraPro(camera: *Camera, movement: Vector3, rotation: Vector3, zoom: f32) callconv(.c) void {
    const lockView = true;
    const rotateAroundTarget = false;
    const rotateUp = false;
    const moveInWorldPlane = true;

    CameraPitch(camera, -rotation.y * DEG2RAD, lockView, rotateAroundTarget, rotateUp);
    CameraYaw(camera, -rotation.x * DEG2RAD, rotateAroundTarget);
    CameraRoll(camera, rotation.z * DEG2RAD);

    CameraMoveForward(camera, movement.x, moveInWorldPlane);
    CameraMoveRight(camera, movement.y, moveInWorldPlane);
    CameraMoveUp(camera, movement.z);

    CameraMoveToTarget(camera, zoom);
}
