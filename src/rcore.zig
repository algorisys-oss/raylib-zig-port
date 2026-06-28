//! rcore - Window/display, graphics-context and input management (GLFW desktop backend).
//!
//! Zig port of raylib's `rcore.c` together with the platform backend it `#include`s,
//! `platforms/rcore_desktop_glfw.c` (PLATFORM_DESKTOP_GLFW). The two C files form ONE
//! translation unit sharing the file-global `CoreData CORE` and static helpers, so they
//! are ported into this single Zig module.
//!
//! Every public raylib window/input/timing/data/file/shader function is exported with its
//! exact C name, byte-compatible signature and C calling convention, so the rest of raylib
//! (still C) links against it unchanged.
//!
//! GLFW (~75 functions), rlgl, raymath, rgestures and rcamera are still C/other-Zig-modules
//! and are `extern`-declared here. The compression (sdefl/sinfl) and random (rprand)
//! single-file libs are instantiated by `src/c/rcore_impl.c` and reached via extern.
//!
//! `CoreData CORE` is global but read only by rcore+platform, so it is modelled as a private
//! Zig struct (layout is ours, every sub-field mirrored faithfully).

const std = @import("std");
const builtin = @import("builtin");

//----------------------------------------------------------------------------------
// libc
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
extern fn strcat([*c]u8, [*c]const u8) [*c]u8;
extern fn strrchr([*c]const u8, c_int) [*c]u8;
extern fn strpbrk([*c]const u8, [*c]const u8) [*c]u8;
extern fn strstr([*c]const u8, [*c]const u8) [*c]u8;
extern fn strchr([*c]const u8, c_int) [*c]u8;
extern fn sprintf(noalias [*c]u8, noalias [*c]const u8, ...) c_int;
extern fn snprintf(noalias [*c]u8, usize, noalias [*c]const u8, ...) c_int;
extern fn vprintf([*c]const u8, *anyopaque) c_int;
extern fn rename([*c]const u8, [*c]const u8) c_int;
extern fn remove([*c]const u8) c_int;
extern fn system([*c]const u8) c_int;
extern fn exit(c_int) noreturn;
extern fn time(?*c_long) c_long;
extern fn fabsf(f32) f32;
extern fn roundf(f32) f32;
extern fn tan(f64) f64;
extern fn atan2f(f32, f32) f32;
extern fn fflush(?*anyopaque) c_int;

// stdio FILE handling via opaque pointer
const FILE = anyopaque;
extern fn fopen([*c]const u8, [*c]const u8) ?*FILE;
extern fn fclose(?*FILE) c_int;
extern fn fseek(?*FILE, c_long, c_int) c_int;
extern fn ftell(?*FILE) c_long;
extern fn fread(?*anyopaque, usize, usize, ?*FILE) usize;
extern fn fwrite(?*const anyopaque, usize, usize, ?*FILE) usize;
extern fn fprintf(?*FILE, [*c]const u8, ...) c_int;
extern fn fgets([*c]u8, c_int, ?*FILE) [*c]u8;
extern fn feof(?*FILE) c_int;
extern fn sscanf([*c]const u8, [*c]const u8, ...) c_int;
const SEEK_SET: c_int = 0;
const SEEK_END: c_int = 2;

// POSIX file/dir
extern fn access([*c]const u8, c_int) c_int;
extern fn getcwd([*c]u8, usize) [*c]u8;
extern fn chdir([*c]const u8) c_int;
extern fn mkdir([*c]const u8, c_uint) c_int;
extern fn readlink([*c]const u8, [*c]u8, usize) isize;
const F_OK: c_int = 0;

// dirent
const DIR = anyopaque;
extern fn opendir([*c]const u8) ?*DIR;
extern fn closedir(?*DIR) c_int;
extern fn readdir(?*DIR) ?*dirent;
const dirent = extern struct {
    d_ino: c_ulong,
    d_off: c_long,
    d_reclen: c_ushort,
    d_type: u8,
    d_name: [256]u8,
};

// stat (Linux x86-64 layout)
const stat_t = extern struct {
    st_dev: c_ulong,
    st_ino: c_ulong,
    st_nlink: c_ulong,
    st_mode: c_uint,
    st_uid: c_uint,
    st_gid: c_uint,
    __pad0: c_uint,
    st_rdev: c_ulong,
    st_size: c_long,
    st_blksize: c_long,
    st_blocks: c_long,
    st_atim_sec: c_long,
    st_atim_nsec: c_long,
    st_mtim_sec: c_long,
    st_mtim_nsec: c_long,
    st_ctim_sec: c_long,
    st_ctim_nsec: c_long,
    __glibc_reserved: [3]c_long,
};
extern fn stat([*c]const u8, *stat_t) c_int;
const S_IFMT: c_uint = 0o170000;
const S_IFREG: c_uint = 0o100000;

// clock / sleep
const timespec = extern struct {
    tv_sec: c_long,
    tv_nsec: c_long,
};
extern fn clock_gettime(c_int, *timespec) c_int;
extern fn nanosleep(*const timespec, ?*timespec) c_int;
const CLOCK_MONOTONIC: c_int = 1;

inline fn RL_FREE(p: anytype) void {
    free(@ptrCast(@constCast(p)));
}
inline fn RL_CALLOC(count: usize, sz: usize) ?*anyopaque {
    return calloc(count, sz);
}
inline fn RL_REALLOC(p: ?*anyopaque, sz: usize) ?*anyopaque {
    return realloc(p, sz);
}

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
pub const AutomationEvent = extern struct {
    frame: c_uint,
    type: c_uint,
    params: [4]c_int,
};
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
const RAYLIB_VERSION = "5.6-dev";

const MAX_TRACELOG_MSG_LENGTH: usize = 256;
const MAX_FILEPATH_CAPACITY: usize = 8192;
const MAX_FILEPATH_LENGTH: usize = 4096;
const MAX_KEYBOARD_KEYS: usize = 512;
const MAX_MOUSE_BUTTONS: usize = 8;
const MAX_GAMEPADS: usize = 4;
const MAX_GAMEPAD_NAME_LENGTH: usize = 128;
const MAX_GAMEPAD_AXES: usize = 8;
const MAX_GAMEPAD_BUTTONS: usize = 32;
const MAX_TOUCH_POINTS: usize = 8;
const MAX_KEY_PRESSED_QUEUE: usize = 16;
const MAX_CHAR_PRESSED_QUEUE: usize = 16;
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
const LOG_INFO: c_int = 3;
const LOG_WARNING: c_int = 4;
const LOG_ERROR: c_int = 5;
const LOG_FATAL: c_int = 6;
const LOG_NONE: c_int = 7;

// ConfigFlags
const FLAG_VSYNC_HINT: c_uint = 0x00000040;
const FLAG_FULLSCREEN_MODE: c_uint = 0x00000002;
const FLAG_WINDOW_RESIZABLE: c_uint = 0x00000004;
const FLAG_WINDOW_UNDECORATED: c_uint = 0x00000008;
const FLAG_WINDOW_HIDDEN: c_uint = 0x00000080;
const FLAG_WINDOW_MINIMIZED: c_uint = 0x00000200;
const FLAG_WINDOW_MAXIMIZED: c_uint = 0x00000400;
const FLAG_WINDOW_UNFOCUSED: c_uint = 0x00000800;
const FLAG_WINDOW_TOPMOST: c_uint = 0x00001000;
const FLAG_WINDOW_ALWAYS_RUN: c_uint = 0x00000100;
const FLAG_WINDOW_TRANSPARENT: c_uint = 0x00000010;
const FLAG_WINDOW_HIGHDPI: c_uint = 0x00002000;
const FLAG_WINDOW_MOUSE_PASSTHROUGH: c_uint = 0x00004000;
const FLAG_BORDERLESS_WINDOWED_MODE: c_uint = 0x00008000;
const FLAG_MSAA_4X_HINT: c_uint = 0x00000020;
const FLAG_INTERLACED_HINT: c_uint = 0x00010000;

// Keys (subset used internally)
const KEY_ESCAPE: c_int = 256;
const KEY_F12: c_int = 301;
const KEY_CAPS_LOCK: c_int = 280;
const KEY_NUM_LOCK: c_int = 282;
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
const MOUSE_CURSOR_DEFAULT: c_int = 0;
const MOUSE_CURSOR_ARROW: c_int = 1;

// Gamepad buttons (raylib enum values)
const GAMEPAD_BUTTON_UNKNOWN: c_int = 0;
const GAMEPAD_BUTTON_LEFT_FACE_UP: c_int = 1;
const GAMEPAD_BUTTON_LEFT_FACE_RIGHT: c_int = 2;
const GAMEPAD_BUTTON_LEFT_FACE_DOWN: c_int = 3;
const GAMEPAD_BUTTON_LEFT_FACE_LEFT: c_int = 4;
const GAMEPAD_BUTTON_RIGHT_FACE_UP: c_int = 5;
const GAMEPAD_BUTTON_RIGHT_FACE_RIGHT: c_int = 6;
const GAMEPAD_BUTTON_RIGHT_FACE_DOWN: c_int = 7;
const GAMEPAD_BUTTON_RIGHT_FACE_LEFT: c_int = 8;
const GAMEPAD_BUTTON_LEFT_TRIGGER_1: c_int = 9;
const GAMEPAD_BUTTON_LEFT_TRIGGER_2: c_int = 10;
const GAMEPAD_BUTTON_RIGHT_TRIGGER_1: c_int = 11;
const GAMEPAD_BUTTON_RIGHT_TRIGGER_2: c_int = 12;
const GAMEPAD_BUTTON_MIDDLE_LEFT: c_int = 13;
const GAMEPAD_BUTTON_MIDDLE: c_int = 14;
const GAMEPAD_BUTTON_MIDDLE_RIGHT: c_int = 15;
const GAMEPAD_BUTTON_LEFT_THUMB: c_int = 16;
const GAMEPAD_BUTTON_RIGHT_THUMB: c_int = 17;
// Gamepad axes
const GAMEPAD_AXIS_LEFT_X: c_int = 0;
const GAMEPAD_AXIS_LEFT_Y: c_int = 1;
const GAMEPAD_AXIS_RIGHT_X: c_int = 2;
const GAMEPAD_AXIS_RIGHT_Y: c_int = 3;
const GAMEPAD_AXIS_LEFT_TRIGGER: c_int = 4;
const GAMEPAD_AXIS_RIGHT_TRIGGER: c_int = 5;

// Camera modes / projections
const CAMERA_CUSTOM: c_int = 0;
const CAMERA_FREE: c_int = 1;
const CAMERA_ORBITAL: c_int = 2;
const CAMERA_FIRST_PERSON: c_int = 3;
const CAMERA_THIRD_PERSON: c_int = 4;
const CAMERA_PERSPECTIVE: c_int = 0;
const CAMERA_ORTHOGRAPHIC: c_int = 1;

const BLEND_ALPHA: c_int = 0;
const PIXELFORMAT_UNCOMPRESSED_R8G8B8A8: c_int = 7;

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
const RL_OPENGL_21: c_int = 2;
const RL_OPENGL_33: c_int = 3;
const RL_OPENGL_43: c_int = 4;
const RL_OPENGL_ES_20: c_int = 5;
const RL_OPENGL_ES_30: c_int = 6;

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
const SHADER_LOC_MATRIX_BONETRANSFORMS: usize = 29;
const SHADER_LOC_VERTEX_BONEIDS: usize = 27;
const SHADER_LOC_VERTEX_BONEWEIGHTS: usize = 28;
const SHADER_LOC_VERTEX_INSTANCETRANSFORM: usize = 30;

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
// GLFW types and constants
//----------------------------------------------------------------------------------
const GLFWwindow = anyopaque;
const GLFWmonitor = anyopaque;
const GLFWcursor = anyopaque;
const GLFWvidmode = extern struct {
    width: c_int,
    height: c_int,
    redBits: c_int,
    greenBits: c_int,
    blueBits: c_int,
    refreshRate: c_int,
};
const GLFWgamepadstate = extern struct {
    buttons: [15]u8,
    axes: [6]f32,
};
const GLFWimage = extern struct {
    width: c_int,
    height: c_int,
    pixels: [*c]u8,
};
const GLFWallocator = extern struct {
    allocate: ?*const fn (size: usize, user: ?*anyopaque) callconv(.c) ?*anyopaque,
    reallocate: ?*const fn (block: ?*anyopaque, size: usize, user: ?*anyopaque) callconv(.c) ?*anyopaque,
    deallocate: ?*const fn (block: ?*anyopaque, user: ?*anyopaque) callconv(.c) void,
    user: ?*anyopaque,
};

const GLFW_TRUE: c_int = 1;
const GLFW_FALSE: c_int = 0;
const GLFW_DONT_CARE: c_int = -1;
const GLFW_RELEASE: c_int = 0;
const GLFW_PRESS: c_int = 1;
const GLFW_REPEAT: c_int = 2;
const GLFW_CONNECTED: c_int = 0x00040001;
const GLFW_DISCONNECTED: c_int = 0x00040002;
const GLFW_MOD_CAPS_LOCK: c_int = 0x0010;
const GLFW_MOD_NUM_LOCK: c_int = 0x0020;
const GLFW_NO_ERROR: c_int = 0;
const GLFW_PLATFORM_ERROR: c_int = 0x00010008;
const GLFW_NO_WINDOW_CONTEXT: c_int = 0x0001000A;
const GLFW_FOCUSED: c_int = 0x00020001;
const GLFW_RESIZABLE: c_int = 0x00020003;
const GLFW_VISIBLE: c_int = 0x00020004;
const GLFW_DECORATED: c_int = 0x00020005;
const GLFW_AUTO_ICONIFY: c_int = 0x00020006;
const GLFW_FLOATING: c_int = 0x00020007;
const GLFW_TRANSPARENT_FRAMEBUFFER: c_int = 0x0002000A;
const GLFW_FOCUS_ON_SHOW: c_int = 0x0002000C;
const GLFW_MOUSE_PASSTHROUGH: c_int = 0x0002000D;
const GLFW_SAMPLES: c_int = 0x0002100D;
const GLFW_CLIENT_API: c_int = 0x00022001;
const GLFW_CONTEXT_VERSION_MAJOR: c_int = 0x00022002;
const GLFW_CONTEXT_VERSION_MINOR: c_int = 0x00022003;
const GLFW_OPENGL_FORWARD_COMPAT: c_int = 0x00022006;
const GLFW_OPENGL_PROFILE: c_int = 0x00022008;
const GLFW_CONTEXT_CREATION_API: c_int = 0x0002200B;
const GLFW_SCALE_TO_MONITOR: c_int = 0x0002200C;
const GLFW_SCALE_FRAMEBUFFER: c_int = 0x0002200D;
const GLFW_OPENGL_ES_API: c_int = 0x00030002;
const GLFW_OPENGL_CORE_PROFILE: c_int = 0x00032001;
const GLFW_CURSOR: c_int = 0x00033001;
const GLFW_LOCK_KEY_MODS: c_int = 0x00033004;
const GLFW_RAW_MOUSE_MOTION: c_int = 0x00033005;
const GLFW_CURSOR_NORMAL: c_int = 0x00034001;
const GLFW_CURSOR_HIDDEN: c_int = 0x00034002;
const GLFW_CURSOR_DISABLED: c_int = 0x00034003;
const GLFW_EGL_CONTEXT_API: c_int = 0x00036002;
const GLFW_PLATFORM_WIN32: c_int = 0x00060001;
const GLFW_PLATFORM_COCOA: c_int = 0x00060002;
const GLFW_PLATFORM_WAYLAND: c_int = 0x00060003;
const GLFW_PLATFORM_X11: c_int = 0x00060004;
const GLFW_PLATFORM_NULL: c_int = 0x00060005;
const GLFW_GAMEPAD_AXIS_LAST: c_int = 5;
// GLFW gamepad button enum (native order)
const GLFW_GAMEPAD_BUTTON_A: c_int = 0;
const GLFW_GAMEPAD_BUTTON_B: c_int = 1;
const GLFW_GAMEPAD_BUTTON_X: c_int = 2;
const GLFW_GAMEPAD_BUTTON_Y: c_int = 3;
const GLFW_GAMEPAD_BUTTON_LEFT_BUMPER: c_int = 4;
const GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER: c_int = 5;
const GLFW_GAMEPAD_BUTTON_BACK: c_int = 6;
const GLFW_GAMEPAD_BUTTON_START: c_int = 7;
const GLFW_GAMEPAD_BUTTON_GUIDE: c_int = 8;
const GLFW_GAMEPAD_BUTTON_LEFT_THUMB: c_int = 9;
const GLFW_GAMEPAD_BUTTON_RIGHT_THUMB: c_int = 10;
const GLFW_GAMEPAD_BUTTON_DPAD_UP: c_int = 11;
const GLFW_GAMEPAD_BUTTON_DPAD_RIGHT: c_int = 12;
const GLFW_GAMEPAD_BUTTON_DPAD_DOWN: c_int = 13;
const GLFW_GAMEPAD_BUTTON_DPAD_LEFT: c_int = 14;

//----------------------------------------------------------------------------------
// GLFW function externs (~75)
//----------------------------------------------------------------------------------
const GLFWerrorfun = ?*const fn (c_int, [*c]const u8) callconv(.c) void;
const GLFWwindowsizefun = ?*const fn (?*GLFWwindow, c_int, c_int) callconv(.c) void;
const GLFWframebuffersizefun = ?*const fn (?*GLFWwindow, c_int, c_int) callconv(.c) void;
const GLFWwindowcontentscalefun = ?*const fn (?*GLFWwindow, f32, f32) callconv(.c) void;
const GLFWwindowposfun = ?*const fn (?*GLFWwindow, c_int, c_int) callconv(.c) void;
const GLFWwindowiconifyfun = ?*const fn (?*GLFWwindow, c_int) callconv(.c) void;
const GLFWwindowmaximizefun = ?*const fn (?*GLFWwindow, c_int) callconv(.c) void;
const GLFWwindowfocusfun = ?*const fn (?*GLFWwindow, c_int) callconv(.c) void;
const GLFWdropfun = ?*const fn (?*GLFWwindow, c_int, [*c][*c]const u8) callconv(.c) void;
const GLFWkeyfun = ?*const fn (?*GLFWwindow, c_int, c_int, c_int, c_int) callconv(.c) void;
const GLFWcharfun = ?*const fn (?*GLFWwindow, c_uint) callconv(.c) void;
const GLFWmousebuttonfun = ?*const fn (?*GLFWwindow, c_int, c_int, c_int) callconv(.c) void;
const GLFWcursorposfun = ?*const fn (?*GLFWwindow, f64, f64) callconv(.c) void;
const GLFWscrollfun = ?*const fn (?*GLFWwindow, f64, f64) callconv(.c) void;
const GLFWcursorenterfun = ?*const fn (?*GLFWwindow, c_int) callconv(.c) void;
const GLFWjoystickfun = ?*const fn (c_int, c_int) callconv(.c) void;
const GLFWglproc = ?*const fn () callconv(.c) void;

extern fn glfwInit() c_int;
extern fn glfwTerminate() void;
extern fn glfwInitAllocator(*const GLFWallocator) void;
extern fn glfwInitHint(c_int, c_int) void;
extern fn glfwGetError(?*[*c]const u8) c_int;
extern fn glfwSetErrorCallback(GLFWerrorfun) GLFWerrorfun;
extern fn glfwGetPlatform() c_int;
extern fn glfwDefaultWindowHints() void;
extern fn glfwWindowHint(c_int, c_int) void;
extern fn glfwCreateWindow(c_int, c_int, [*c]const u8, ?*GLFWmonitor, ?*GLFWwindow) ?*GLFWwindow;
extern fn glfwDestroyWindow(?*GLFWwindow) void;
extern fn glfwMakeContextCurrent(?*GLFWwindow) void;
extern fn glfwSwapInterval(c_int) void;
extern fn glfwSwapBuffers(?*GLFWwindow) void;
extern fn glfwGetProcAddress([*c]const u8) GLFWglproc;
extern fn glfwGetTime() f64;
extern fn glfwPollEvents() void;
extern fn glfwWaitEvents() void;
extern fn glfwWindowShouldClose(?*GLFWwindow) c_int;
extern fn glfwSetWindowShouldClose(?*GLFWwindow, c_int) void;
extern fn glfwGetPrimaryMonitor() ?*GLFWmonitor;
extern fn glfwGetMonitors(*c_int) ?[*]?*GLFWmonitor;
extern fn glfwGetWindowMonitor(?*GLFWwindow) ?*GLFWmonitor;
extern fn glfwGetVideoMode(?*GLFWmonitor) ?*const GLFWvidmode;
extern fn glfwGetMonitorPos(?*GLFWmonitor, *c_int, *c_int) void;
extern fn glfwGetMonitorWorkarea(?*GLFWmonitor, *c_int, *c_int, *c_int, *c_int) void;
extern fn glfwGetMonitorPhysicalSize(?*GLFWmonitor, ?*c_int, ?*c_int) void;
extern fn glfwGetMonitorName(?*GLFWmonitor) [*c]const u8;
extern fn glfwSetWindowMonitor(?*GLFWwindow, ?*GLFWmonitor, c_int, c_int, c_int, c_int, c_int) void;
extern fn glfwSetWindowTitle(?*GLFWwindow, [*c]const u8) void;
extern fn glfwSetWindowPos(?*GLFWwindow, c_int, c_int) void;
extern fn glfwGetWindowPos(?*GLFWwindow, *c_int, *c_int) void;
extern fn glfwSetWindowSize(?*GLFWwindow, c_int, c_int) void;
extern fn glfwGetWindowSize(?*GLFWwindow, *c_int, *c_int) void;
extern fn glfwSetWindowSizeLimits(?*GLFWwindow, c_int, c_int, c_int, c_int) void;
extern fn glfwGetFramebufferSize(?*GLFWwindow, *c_int, *c_int) void;
extern fn glfwSetWindowOpacity(?*GLFWwindow, f32) void;
extern fn glfwFocusWindow(?*GLFWwindow) void;
extern fn glfwMaximizeWindow(?*GLFWwindow) void;
extern fn glfwIconifyWindow(?*GLFWwindow) void;
extern fn glfwRestoreWindow(?*GLFWwindow) void;
extern fn glfwHideWindow(?*GLFWwindow) void;
extern fn glfwShowWindow(?*GLFWwindow) void;
extern fn glfwSetWindowAttrib(?*GLFWwindow, c_int, c_int) void;
extern fn glfwGetWindowAttrib(?*GLFWwindow, c_int) c_int;
extern fn glfwSetWindowIcon(?*GLFWwindow, c_int, ?[*]const GLFWimage) void;
extern fn glfwGetWindowContentScale(?*GLFWwindow, *f32, *f32) void;
extern fn glfwSetClipboardString(?*GLFWwindow, [*c]const u8) void;
extern fn glfwGetClipboardString(?*GLFWwindow) [*c]const u8;
extern fn glfwSetInputMode(?*GLFWwindow, c_int, c_int) void;
extern fn glfwSetCursorPos(?*GLFWwindow, f64, f64) void;
extern fn glfwSetCursor(?*GLFWwindow, ?*GLFWcursor) void;
extern fn glfwCreateStandardCursor(c_int) ?*GLFWcursor;
extern fn glfwRawMouseMotionSupported() c_int;
extern fn glfwGetKeyName(c_int, c_int) [*c]const u8;
extern fn glfwGetKeyScancode(c_int) c_int;
extern fn glfwJoystickPresent(c_int) c_int;
extern fn glfwGetJoystickName(c_int) [*c]const u8;
extern fn glfwGetGamepadState(c_int, *GLFWgamepadstate) c_int;
extern fn glfwUpdateGamepadMappings([*c]const u8) c_int;
extern fn glfwSetWindowSizeCallback(?*GLFWwindow, GLFWwindowsizefun) GLFWwindowsizefun;
extern fn glfwSetFramebufferSizeCallback(?*GLFWwindow, GLFWframebuffersizefun) GLFWframebuffersizefun;
extern fn glfwSetWindowContentScaleCallback(?*GLFWwindow, GLFWwindowcontentscalefun) GLFWwindowcontentscalefun;
extern fn glfwSetWindowPosCallback(?*GLFWwindow, GLFWwindowposfun) GLFWwindowposfun;
extern fn glfwSetWindowMaximizeCallback(?*GLFWwindow, GLFWwindowmaximizefun) GLFWwindowmaximizefun;
extern fn glfwSetWindowIconifyCallback(?*GLFWwindow, GLFWwindowiconifyfun) GLFWwindowiconifyfun;
extern fn glfwSetWindowFocusCallback(?*GLFWwindow, GLFWwindowfocusfun) GLFWwindowfocusfun;
extern fn glfwSetDropCallback(?*GLFWwindow, GLFWdropfun) GLFWdropfun;
extern fn glfwSetKeyCallback(?*GLFWwindow, GLFWkeyfun) GLFWkeyfun;
extern fn glfwSetCharCallback(?*GLFWwindow, GLFWcharfun) GLFWcharfun;
extern fn glfwSetMouseButtonCallback(?*GLFWwindow, GLFWmousebuttonfun) GLFWmousebuttonfun;
extern fn glfwSetCursorPosCallback(?*GLFWwindow, GLFWcursorposfun) GLFWcursorposfun;
extern fn glfwSetScrollCallback(?*GLFWwindow, GLFWscrollfun) GLFWscrollfun;
extern fn glfwSetCursorEnterCallback(?*GLFWwindow, GLFWcursorenterfun) GLFWcursorenterfun;
extern fn glfwSetJoystickCallback(GLFWjoystickfun) GLFWjoystickfun;

//----------------------------------------------------------------------------------
// rlgl externs (from src/rlgl.zig)
//----------------------------------------------------------------------------------
extern fn rlglInit(width: c_int, height: c_int) void;
extern fn rlglClose() void;
extern fn rlLoadExtensions(loader: ?*anyopaque) void;
extern fn rlGetVersion() c_int;
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
extern fn MatrixScale(x: f32, y: f32, z: f32) Matrix;
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
extern fn UpdateGestures() void;

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
extern fn TextFormat(text: [*c]const u8, ...) [*c]const u8;
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

var CORE: CoreData = .{};

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

const autoEventTypeName = [_][*c]const u8{
    "EVENT_NONE",                "INPUT_KEY_UP",
    "INPUT_KEY_DOWN",            "INPUT_KEY_PRESSED",
    "INPUT_KEY_RELEASED",        "INPUT_MOUSE_BUTTON_UP",
    "INPUT_MOUSE_BUTTON_DOWN",   "INPUT_MOUSE_POSITION",
    "INPUT_MOUSE_WHEEL_MOTION",  "INPUT_GAMEPAD_CONNECT",
    "INPUT_GAMEPAD_DISCONNECT",  "INPUT_GAMEPAD_BUTTON_UP",
    "INPUT_GAMEPAD_BUTTON_DOWN", "INPUT_GAMEPAD_AXIS_MOTION",
    "INPUT_TOUCH_UP",            "INPUT_TOUCH_DOWN",
    "INPUT_TOUCH_POSITION",      "INPUT_GESTURE",
    "WINDOW_CLOSE",              "WINDOW_MAXIMIZE",
    "WINDOW_MINIMIZE",           "WINDOW_RESIZE",
    "ACTION_TAKE_SCREENSHOT",    "ACTION_SETTARGETFPS",
};

var currentEventList: ?*AutomationEventList = null;
var automationEventRecording: bool = false;

// Platform data
const PlatformData = struct {
    handle: ?*GLFWwindow = null,
};
var platform: PlatformData = .{};

//----------------------------------------------------------------------------------
// Flag helpers
//----------------------------------------------------------------------------------
inline fn flagIsSet(n: c_uint, f: c_uint) bool {
    return (n & f) == f;
}
inline fn flagSet(n: *c_uint, f: c_uint) void {
    n.* |= f;
}
inline fn flagClear(n: *c_uint, f: c_uint) void {
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
    TraceLog(LOG_INFO, "Platform backend: DESKTOP (GLFW)");

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
    SetRandomSeed(@intCast(@as(c_long, @bitCast(time(null)))));

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
export fn IsWindowFullscreen() callconv(.c) bool {
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
export fn GetScreenWidth() callconv(.c) c_int {
    return @intCast(CORE.Window.screen.width);
}
export fn GetScreenHeight() callconv(.c) c_int {
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

        const lensRadius = fabsf(-1.0 - 4.0 * lensShift);
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
        shader.locs = @ptrCast(@alignCast(RL_CALLOC(@intCast(RL_MAX_SHADER_LOCATIONS), @sizeOf(c_int))));
        var i: usize = 0;
        while (i < RL_MAX_SHADER_LOCATIONS) : (i += 1) shader.locs[i] = -1;
    } else if (shader.id == rlGetShaderIdDefault()) {
        shader.locs = rlGetShaderLocsDefault();
    } else if (shader.id > 0) {
        shader.locs = @ptrCast(@alignCast(RL_CALLOC(@intCast(RL_MAX_SHADER_LOCATIONS), @sizeOf(c_int))));
        var i: usize = 0;
        while (i < RL_MAX_SHADER_LOCATIONS) : (i += 1) shader.locs[i] = -1;

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

export fn IsShaderValid(shader: Shader) callconv(.c) bool {
    return (shader.id > 0) and (shader.locs != null);
}

export fn UnloadShader(shader: Shader) callconv(.c) void {
    if (shader.id != rlGetShaderIdDefault()) {
        rlUnloadShaderProgram(shader.id);
        RL_FREE(shader.locs);
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
        }
        fps = @intFromFloat(roundf(1.0 / fps_average));
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
    const sec: c_long = @intFromFloat(sleepSeconds);
    const nsec: c_long = @intFromFloat((sleepSeconds - @as(f64, @floatFromInt(sec))) * 1000000000.0);
    req.tv_sec = sec;
    req.tv_nsec = nsec;
    while (nanosleep(&req, &req) == -1) continue;

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
    if (strchr(fileName, '\'') != null) {
        TraceLog(LOG_WARNING, "SYSTEM: Provided fileName could be potentially malicious, avoid ['] character");
        return;
    }

    var scale = Vector2{ .x = 1.0, .y = 1.0 };
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) scale = GetWindowScaleDPI();

    const w: c_int = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.render.width)) * scale.x);
    const h: c_int = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.render.height)) * scale.y);
    const imgData = rlReadScreenPixels(w, h);
    const image = Image{ .data = imgData, .width = w, .height = h, .mipmaps = 1, .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 };

    var path: [MAX_FILEPATH_LENGTH]u8 = std.mem.zeroes([MAX_FILEPATH_LENGTH]u8);
    _ = strncpy(&path, TextFormat("%s/%s", CORE.Storage.basePath, fileName), MAX_FILEPATH_LENGTH - 1);

    _ = ExportImage(image, &path);
    RL_FREE(imgData);

    if (FileExists(&path)) TraceLog(LOG_INFO, "SYSTEM: [%s] Screenshot taken successfully", &path) else TraceLog(LOG_WARNING, "SYSTEM: [%s] Screenshot could not be saved", &path);
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

export fn TraceLog(logType: c_int, text: [*c]const u8, ...) callconv(.c) void {
    if ((logType < logTypeLevel) or (text == null)) return;

    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    if (traceLogCallbackPtr) |cb| {
        cb(logType, text, @ptrCast(&ap));
        return;
    }

    var buffer: [MAX_TRACELOG_MSG_LENGTH]u8 = std.mem.zeroes([MAX_TRACELOG_MSG_LENGTH]u8);

    switch (logType) {
        LOG_TRACE => _ = strncpy(&buffer, "TRACE: ", 8),
        LOG_DEBUG => _ = strncpy(&buffer, "DEBUG: ", 8),
        LOG_INFO => _ = strncpy(&buffer, "INFO: ", 7),
        LOG_WARNING => _ = strncpy(&buffer, "WARNING: ", 10),
        LOG_ERROR => _ = strncpy(&buffer, "ERROR: ", 8),
        LOG_FATAL => _ = strncpy(&buffer, "FATAL: ", 8),
        else => {},
    }

    const textLength: c_uint = @intCast(strlen(text));
    const blen = strlen(&buffer);
    const copyLen: usize = if (textLength < (MAX_TRACELOG_MSG_LENGTH - 12)) @intCast(textLength) else (MAX_TRACELOG_MSG_LENGTH - 12);
    _ = memcpy(@ptrCast(&buffer[blen]), @ptrCast(text), copyLen);
    _ = strcat(&buffer, "\n");
    _ = vprintf(&buffer, @ptrCast(&ap));
    _ = fflush(null);

    if (logType == LOG_FATAL) exit(1);
}

export fn SetTraceLogCallback(callback: TraceLogCallback) callconv(.c) void {
    traceLogCallbackPtr = callback;
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Memory management
//----------------------------------------------------------------------------------

export fn MemAlloc(size: c_uint) callconv(.c) ?*anyopaque {
    return RL_CALLOC(size, 1);
}
export fn MemRealloc(ptr: ?*anyopaque, size: c_uint) callconv(.c) ?*anyopaque {
    return RL_REALLOC(ptr, size);
}
export fn MemFree(ptr: ?*anyopaque) callconv(.c) void {
    RL_FREE(ptr);
}

//----------------------------------------------------------------------------------
// Module Functions Definition: File System management - File I/O
//----------------------------------------------------------------------------------

export fn LoadFileData(fileName: [*c]const u8, dataSize: [*c]c_int) callconv(.c) [*c]u8 {
    var data: [*c]u8 = null;
    dataSize.* = 0;

    if (fileName != null) {
        if (loadFileDataCallbackPtr) |cb| return cb(fileName, dataSize);

        const file = fopen(fileName, "rb");
        if (file != null) {
            _ = fseek(file, 0, SEEK_END);
            const size = ftell(file);
            _ = fseek(file, 0, SEEK_SET);

            if (size > 0) {
                data = @ptrCast(@alignCast(RL_CALLOC(@intCast(size), 1)));
                if (data != null) {
                    const count = fread(@ptrCast(data), 1, @intCast(size), file);
                    if (count > 2147483647) {
                        TraceLog(LOG_WARNING, "FILEIO: [%s] File is bigger than 2147483647 bytes, avoid using LoadFileData()", fileName);
                        RL_FREE(data);
                        data = null;
                    } else {
                        dataSize.* = @intCast(count);
                        if (dataSize.* != @as(c_int, @intCast(size))) TraceLog(LOG_WARNING, "FILEIO: [%s] File partially loaded (%i bytes out of %i)", fileName, dataSize.*, @as(c_int, @intCast(size))) else TraceLog(LOG_INFO, "FILEIO: [%s] File loaded successfully", fileName);
                    }
                } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to allocated memory for file reading", fileName);
            } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to read file", fileName);

            _ = fclose(file);
        } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to open file", fileName);
    } else TraceLog(LOG_WARNING, "FILEIO: File name provided is not valid");

    return data;
}

export fn UnloadFileData(data: [*c]u8) callconv(.c) void {
    RL_FREE(data);
}

export fn SaveFileData(fileName: [*c]const u8, data: ?*anyopaque, dataSize: c_int) callconv(.c) bool {
    var result = false;

    if (fileName != null) {
        if (saveFileDataCallbackPtr) |cb| return cb(fileName, data, dataSize);

        const file = fopen(fileName, "wb");
        if (file != null) {
            const count: c_int = @intCast(fwrite(data, 1, @intCast(dataSize), file));
            if (count == 0) TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to write file", fileName) else if (count != dataSize) TraceLog(LOG_WARNING, "FILEIO: [%s] File partially written", fileName) else TraceLog(LOG_INFO, "FILEIO: [%s] File saved successfully", fileName);

            const closed = fclose(file);
            if (closed == 0) result = true;
        } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to open file", fileName);
    } else TraceLog(LOG_WARNING, "FILEIO: File name provided is not valid");

    return result;
}

export fn ExportDataAsCode(data: [*c]const u8, dataSize: c_int, fileName: [*c]const u8) callconv(.c) bool {
    var result = false;
    const TEXT_BYTES_PER_LINE: c_int = 20;

    const txtData: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(@intCast(dataSize * 6 + 2000), 1)));

    var byteCount: c_int = 0;
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "////////////////////////////////////////////////////////////////////////////////////////\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                                    //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// DataAsCode exporter v1.0 - Raw data exported as an array of bytes                  //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                                    //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// more info and bugs-report:  github.com/raysan5/raylib                              //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// feedback and support:       ray[at]raylib.com                                      //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                                    //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// Copyright (c) 2022-2026 Ramon Santamaria (@raysan5)                                //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                                    //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "////////////////////////////////////////////////////////////////////////////////////////\n\n");

    var varFileName: [256]u8 = std.mem.zeroes([256]u8);
    _ = strncpy(&varFileName, GetFileNameWithoutExt(fileName), 256 - 1);
    var i: usize = 0;
    while (varFileName[i] != 0) : (i += 1) {
        if ((varFileName[i] >= 'a') and (varFileName[i] <= 'z')) {
            varFileName[i] = varFileName[i] - 32;
        } else if (varFileName[i] == '.' or varFileName[i] == '-' or varFileName[i] == '?' or varFileName[i] == '!' or varFileName[i] == '+') {
            varFileName[i] = '_';
        }
    }

    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#define %s_DATA_SIZE     %i\n\n", &varFileName, dataSize);
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "static unsigned char %s_DATA[%s_DATA_SIZE] = { ", &varFileName, &varFileName);
    var k: c_int = 0;
    while (k < (dataSize - 1)) : (k += 1) {
        const fmt: [*c]const u8 = if (@rem(k, TEXT_BYTES_PER_LINE) == 0) "0x%x,\n" else "0x%x, ";
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), fmt, @as(c_int, data[@intCast(k)]));
    }
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "0x%x };\n", @as(c_int, data[@intCast(dataSize - 1)]));

    result = SaveFileText(fileName, txtData);

    RL_FREE(txtData);

    if (result) TraceLog(LOG_INFO, "FILEIO: [%s] Data as code exported successfully", fileName) else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export data as code", fileName);

    return result;
}

export fn LoadFileText(fileName: [*c]const u8) callconv(.c) [*c]u8 {
    var text: [*c]u8 = null;

    if (fileName != null) {
        if (loadFileTextCallbackPtr) |cb| return cb(fileName);

        const file = fopen(fileName, "rt");
        if (file != null) {
            _ = fseek(file, 0, SEEK_END);
            const size: c_uint = @intCast(ftell(file));
            _ = fseek(file, 0, SEEK_SET);

            if (size > 0) {
                text = @ptrCast(@alignCast(RL_CALLOC(size + 1, 1)));
                if (text != null) {
                    const count: c_uint = @intCast(fread(@ptrCast(text), 1, size, file));
                    if (count < size) text = @ptrCast(@alignCast(RL_REALLOC(@ptrCast(text), count + 1)));
                    text[count] = 0;
                    TraceLog(LOG_INFO, "FILEIO: [%s] Text file loaded successfully", fileName);
                } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to allocated memory for file reading", fileName);
            } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to read text file", fileName);

            _ = fclose(file);
        } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to open text file", fileName);
    } else TraceLog(LOG_WARNING, "FILEIO: File name provided is not valid");

    return text;
}

export fn UnloadFileText(text: [*c]u8) callconv(.c) void {
    RL_FREE(text);
}

export fn SaveFileText(fileName: [*c]const u8, text: [*c]u8) callconv(.c) bool {
    var result = false;

    if (fileName != null) {
        if (saveFileTextCallbackPtr) |cb| return cb(fileName, text);

        const file = fopen(fileName, "wt");
        if (file != null) {
            const count = fprintf(file, "%s", text);
            if (count < 0) TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to write text file", fileName) else TraceLog(LOG_INFO, "FILEIO: [%s] Text file saved successfully", fileName);

            const closed = fclose(file);
            if (closed == 0) result = true;
        } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to open text file", fileName);
    } else TraceLog(LOG_WARNING, "FILEIO: File name provided is not valid");

    return result;
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
    var result: c_int = -1;
    if (FileExists(fileName)) result = rename(fileName, fileRename);
    return result;
}

export fn FileRemove(fileName: [*c]const u8) callconv(.c) c_int {
    var result: c_int = -1;
    if (FileExists(fileName)) result = remove(fileName);
    return result;
}

export fn FileCopy(srcPath: [*c]const u8, dstPath: [*c]const u8) callconv(.c) c_int {
    var result: c_int = -1;
    var srcDataSize: c_int = 0;
    const srcFileData = LoadFileData(srcPath, &srcDataSize);

    if (DirectoryExists(GetDirectoryPath(dstPath))) result = 0 else result = MakeDirectory(GetDirectoryPath(dstPath));

    if (result == 0) {
        if ((srcFileData != null) and (srcDataSize > 0)) {
            const saved = SaveFileData(dstPath, @ptrCast(srcFileData), srcDataSize);
            if (saved) result = 0;
        }
    }

    UnloadFileData(srcFileData);
    return result;
}

export fn FileMove(srcPath: [*c]const u8, dstPath: [*c]const u8) callconv(.c) c_int {
    var result: c_int = -1;

    if (FileExists(srcPath)) {
        result = FileCopy(srcPath, dstPath);
        if (result == 0) {
            if (FileExists(dstPath) and (GetFileLength(srcPath) == GetFileLength(dstPath))) {
                result = FileRemove(srcPath);
                if (result != 0) TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to remove source file after copy", srcPath);
            } else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to copy file to [%s]", srcPath, dstPath);
        }
    } else TraceLog(LOG_WARNING, "FILEIO: [%s] Source file does not exist", srcPath);

    return result;
}

export fn FileTextReplace(fileName: [*c]const u8, search: [*c]const u8, replacement: [*c]const u8) callconv(.c) c_int {
    var result: c_int = -1;

    if (FileExists(fileName)) {
        const fileText = LoadFileText(fileName);
        const fileTextUpdated = TextReplaceAlloc(fileText, search, replacement);
        const saved = SaveFileText(fileName, fileTextUpdated);
        if (saved) result = 0;
        MemFree(@ptrCast(fileTextUpdated));
        UnloadFileText(fileText);
    }

    return result;
}

export fn FileTextFindIndex(fileName: [*c]const u8, search: [*c]const u8) callconv(.c) c_int {
    var result: c_int = -1;
    if (FileExists(fileName)) {
        const fileText = LoadFileText(fileName);
        const ptr = strstr(fileText, search);
        if (ptr != null) result = @intCast(@intFromPtr(ptr) - @intFromPtr(fileText));
        UnloadFileText(fileText);
    }
    return result;
}

export fn FileExists(fileName: [*c]const u8) callconv(.c) bool {
    var result = false;
    if ((fileName != null) and (access(fileName, F_OK) != -1)) result = true;
    return result;
}

export fn IsFileExtension(fileName: [*c]const u8, ext: [*c]const u8) callconv(.c) bool {
    const MAX_FILE_EXTENSIONS: usize = 32;
    var result = false;
    const fileExt = GetFileExtension(fileName);

    if (fileExt != null) {
        const fileExtLength: usize = strlen(fileExt);
        var fileExtLower: [16]u8 = std.mem.zeroes([16]u8);
        var i: usize = 0;
        while ((i < fileExtLength) and (i < 15)) : (i += 1) {
            if ((fileExt[i] >= 'A') and (fileExt[i] <= 'Z')) fileExtLower[i] = fileExt[i] + 32 else fileExtLower[i] = fileExt[i];
        }

        var extCount: usize = 1;
        const extLength: usize = strlen(ext);
        const extList: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(extLength + 1, 1)));
        var extListPtrs: [MAX_FILE_EXTENSIONS][*c]u8 = std.mem.zeroes([MAX_FILE_EXTENSIONS][*c]u8);
        _ = memcpy(@ptrCast(extList), @ptrCast(ext), extLength);
        extListPtrs[0] = extList;

        var j: usize = 0;
        while (j < extLength) : (j += 1) {
            if ((extList[j] >= 'A') and (extList[j] <= 'Z')) extList[j] += 32;
            if (extList[j] == ';') {
                extList[j] = 0;
                if (extCount < MAX_FILE_EXTENSIONS) {
                    extListPtrs[extCount] = extList + j + 1;
                    extCount += 1;
                }
            }
        }

        var m: usize = 0;
        while (m < extCount) : (m += 1) {
            var fileExtLowerPtr: [*c]u8 = &fileExtLower;
            if (extListPtrs[m][0] != '.') fileExtLowerPtr += 1;
            if (strcmp(fileExtLowerPtr, extListPtrs[m]) == 0) {
                result = true;
                break;
            }
        }

        RL_FREE(extList);
    }

    return result;
}

export fn DirectoryExists(dirPath: [*c]const u8) callconv(.c) bool {
    var result = false;
    const dir = opendir(dirPath);
    if (dir != null) {
        result = true;
        _ = closedir(dir);
    }
    return result;
}

export fn GetFileLength(fileName: [*c]const u8) callconv(.c) c_int {
    var size: c_int = 0;
    const file = fopen(fileName, "rb");
    if (file != null) {
        _ = fseek(file, 0, SEEK_END);
        const fileSize = ftell(file);
        if (fileSize > 2147483647) TraceLog(LOG_WARNING, "[%s] File size overflows expected limit, do not use GetFileLength()", fileName) else size = @intCast(fileSize);
        _ = fclose(file);
    }
    return size;
}

export fn GetFileModTime(fileName: [*c]const u8) callconv(.c) c_long {
    var result = std.mem.zeroes(stat_t);
    var modTime: c_long = 0;
    if (stat(fileName, &result) == 0) modTime = result.st_mtim_sec;
    return modTime;
}

export fn GetFileExtension(fileName: [*c]const u8) callconv(.c) [*c]const u8 {
    const dot = strrchr(fileName, '.');
    if (dot == null or (dot == fileName)) return null;
    return dot;
}

// String pointer reverse break: rightmost occurrence of charset in text
fn strprbrk(text_in: [*c]const u8, charset: [*c]const u8) [*c]const u8 {
    var latestMatch: [*c]const u8 = null;
    var text = text_in;
    while (text != null) {
        text = strpbrk(text, charset);
        if (text == null) break;
        latestMatch = text;
        text += 1;
    }
    return latestMatch;
}

export fn GetFileName(filePath: [*c]const u8) callconv(.c) [*c]const u8 {
    var fileName: [*c]const u8 = null;
    if (filePath != null) fileName = strprbrk(filePath, "\\/");
    if (fileName == null) return filePath;
    return fileName + 1;
}

var gfnwe_fileName: [256]u8 = std.mem.zeroes([256]u8);
export fn GetFileNameWithoutExt(filePath: [*c]const u8) callconv(.c) [*c]const u8 {
    const MAX_FILENAME_LENGTH: usize = 256;
    _ = memset(@ptrCast(&gfnwe_fileName), 0, MAX_FILENAME_LENGTH);

    if (filePath != null) {
        _ = strncpy(&gfnwe_fileName, GetFileName(filePath), MAX_FILENAME_LENGTH - 1);
        const fileNameLength: c_int = @intCast(strlen(&gfnwe_fileName));
        var i: c_int = fileNameLength;
        while (i > 0) : (i -= 1) {
            if (gfnwe_fileName[@intCast(i)] == '.') {
                gfnwe_fileName[@intCast(i)] = 0;
                break;
            }
        }
    }
    return &gfnwe_fileName;
}

var gdp_dirPath: [MAX_FILEPATH_LENGTH]u8 = std.mem.zeroes([MAX_FILEPATH_LENGTH]u8);
export fn GetDirectoryPath(filePath: [*c]const u8) callconv(.c) [*c]const u8 {
    _ = memset(@ptrCast(&gdp_dirPath), 0, MAX_FILEPATH_LENGTH);

    if ((filePath[1] != ':') and (filePath[0] != '\\') and (filePath[0] != '/')) {
        gdp_dirPath[0] = '.';
        gdp_dirPath[1] = '/';
    }

    const lastSlash = strprbrk(filePath, "\\/");
    if (lastSlash != null) {
        if (lastSlash == filePath) {
            gdp_dirPath[0] = filePath[0];
            gdp_dirPath[1] = 0;
        } else {
            var dirPathPtr: [*c]u8 = &gdp_dirPath;
            const hasNoRoot = (filePath[1] != ':') and (filePath[0] != '\\') and (filePath[0] != '/');
            if (hasNoRoot) dirPathPtr += 2;
            const copyLen = strlen(filePath) - (strlen(lastSlash) - 1);
            _ = memcpy(@ptrCast(dirPathPtr), @ptrCast(filePath), copyLen);
            const idx = strlen(filePath) - strlen(lastSlash) + (if (hasNoRoot) @as(usize, 2) else @as(usize, 0));
            gdp_dirPath[idx] = 0;
        }
    }

    return &gdp_dirPath;
}

var gpdp_prevDirPath: [MAX_FILEPATH_LENGTH]u8 = std.mem.zeroes([MAX_FILEPATH_LENGTH]u8);
export fn GetPrevDirectoryPath(dirPath: [*c]const u8) callconv(.c) [*c]const u8 {
    _ = memset(@ptrCast(&gpdp_prevDirPath), 0, MAX_FILEPATH_LENGTH);
    const dirPathLength: c_int = @intCast(strlen(dirPath));

    if (dirPathLength <= 3) _ = strncpy(&gpdp_prevDirPath, dirPath, MAX_FILEPATH_LENGTH - 1);

    var i: c_int = dirPathLength - 1;
    while ((i >= 0) and (dirPathLength > 3)) : (i -= 1) {
        if ((dirPath[@intCast(i)] == '\\') or (dirPath[@intCast(i)] == '/')) {
            if (((i == 2) and (dirPath[1] == ':')) or (i == 0)) i += 1;
            _ = strncpy(&gpdp_prevDirPath, dirPath, @intCast(i));
            break;
        }
    }

    return &gpdp_prevDirPath;
}

var gwd_currentDir: [MAX_FILEPATH_LENGTH]u8 = std.mem.zeroes([MAX_FILEPATH_LENGTH]u8);
export fn GetWorkingDirectory() callconv(.c) [*c]const u8 {
    _ = memset(@ptrCast(&gwd_currentDir), 0, MAX_FILEPATH_LENGTH);
    return getcwd(&gwd_currentDir, MAX_FILEPATH_LENGTH);
}

var gad_appDir: [MAX_FILEPATH_LENGTH]u8 = std.mem.zeroes([MAX_FILEPATH_LENGTH]u8);
export fn GetApplicationDirectory() callconv(.c) [*c]const u8 {
    _ = memset(@ptrCast(&gad_appDir), 0, MAX_FILEPATH_LENGTH);

    const size = MAX_FILEPATH_LENGTH;
    const len = readlink("/proc/self/exe", &gad_appDir, size);
    if (len > 0) {
        var i: isize = len;
        while (i >= 0) : (i -= 1) {
            if (gad_appDir[@intCast(i)] == '/') {
                gad_appDir[@intCast(i + 1)] = 0;
                break;
            }
        }
    } else {
        gad_appDir[0] = '.';
        gad_appDir[1] = '/';
    }

    return &gad_appDir;
}

export fn LoadDirectoryFiles(dirPath: [*c]const u8) callconv(.c) FilePathList {
    return LoadDirectoryFilesEx(dirPath, FILE_FILTER_TAG_ALL, false);
}

export fn LoadDirectoryFilesEx(basePath: [*c]const u8, filter_in: [*c]const u8, scanSubdirs: bool) callconv(.c) FilePathList {
    var files = std.mem.zeroes(FilePathList);
    var filter = filter_in;

    if (DirectoryExists(basePath)) {
        if ((filter != null) and (filter[0] == 0)) filter = null;

        const fileCounter = GetDirectoryFileCountEx(basePath, filter, scanSubdirs);

        files.paths = @ptrCast(@alignCast(RL_CALLOC(fileCounter, @sizeOf([*c]u8))));
        var i: c_uint = 0;
        while (i < fileCounter) : (i += 1) files.paths[i] = @ptrCast(@alignCast(RL_CALLOC(MAX_FILEPATH_LENGTH, 1)));

        ScanDirectoryFiles(basePath, &files, filter, fileCounter, scanSubdirs);

        if (files.count != fileCounter) {
            TraceLog(LOG_WARNING, "FILEIO: Read files count (%u) does not match capacity allocated (%u)", files.count, fileCounter);
            files.count = fileCounter;
        }
    } else TraceLog(LOG_WARNING, "FILEIO: Directory cannot be opened (%s)", basePath);

    return files;
}

export fn UnloadDirectoryFiles(files: FilePathList) callconv(.c) void {
    if (files.paths != null) {
        var i: c_uint = 0;
        while (i < files.count) : (i += 1) RL_FREE(files.paths[i]);
        RL_FREE(files.paths);
    }
}

export fn MakeDirectory(dirPath: [*c]const u8) callconv(.c) c_int {
    if ((dirPath == null) or (dirPath[0] == 0)) return -1;
    if (DirectoryExists(dirPath)) return 0;

    const dirPathLength: usize = strlen(dirPath) + 1;
    const pathcpy: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(dirPathLength, 1)));
    _ = memcpy(@ptrCast(pathcpy), @ptrCast(dirPath), dirPathLength);

    var i: usize = 0;
    while ((i < dirPathLength) and (pathcpy[i] != 0)) : (i += 1) {
        if (pathcpy[i] == ':') {
            i += 1;
        } else {
            if ((pathcpy[i] == '\\') or (pathcpy[i] == '/')) {
                pathcpy[i] = 0;
                if (!DirectoryExists(pathcpy)) _ = mkdir(pathcpy, 0o777);
                pathcpy[i] = '/';
            }
        }
    }

    if (!DirectoryExists(pathcpy)) _ = mkdir(pathcpy, 0o777);
    RL_FREE(pathcpy);

    if (!DirectoryExists(dirPath)) return -1;
    return 0;
}

export fn ChangeDirectory(dirPath: [*c]const u8) callconv(.c) c_int {
    const result = chdir(dirPath);
    if (result != 0) TraceLog(LOG_WARNING, "SYSTEM: Failed to change to directory: %s", dirPath) else TraceLog(LOG_INFO, "SYSTEM: Working Directory: %s", dirPath);
    return result;
}

export fn IsPathFile(path: [*c]const u8) callconv(.c) bool {
    var result = std.mem.zeroes(stat_t);
    _ = stat(path, &result);
    return (result.st_mode & S_IFMT) == S_IFREG;
}

export fn IsFileNameValid(fileName: [*c]const u8) callconv(.c) bool {
    var valid = true;

    if ((fileName != null) and (fileName[0] != 0)) {
        const fileNameLength: c_int = @intCast(strlen(fileName));
        var allPeriods = true;

        var i: c_int = 0;
        while (i < fileNameLength) : (i += 1) {
            const ch = fileName[@intCast(i)];
            if ((ch == '<') or (ch == '>') or (ch == ':') or (ch == '\"') or (ch == '/') or (ch == '\\') or (ch == '|') or (ch == '?') or (ch == '*')) {
                valid = false;
                break;
            }
            if (ch < 32) {
                valid = false;
                break;
            }
            if (ch != '.') allPeriods = false;
        }

        if (allPeriods) valid = false;
    }

    return valid;
}

export fn IsFileDropped() callconv(.c) bool {
    return CORE.Window.dropFileCount > 0;
}

export fn LoadDroppedFiles() callconv(.c) FilePathList {
    var files = std.mem.zeroes(FilePathList);
    files.count = CORE.Window.dropFileCount;
    files.paths = CORE.Window.dropFilepaths;
    return files;
}

export fn UnloadDroppedFiles(files: FilePathList) callconv(.c) void {
    if (files.count > 0) {
        var i: c_uint = 0;
        while (i < files.count) : (i += 1) RL_FREE(files.paths[i]);
        RL_FREE(files.paths);
        CORE.Window.dropFileCount = 0;
        CORE.Window.dropFilepaths = null;
    }
}

export fn GetDirectoryFileCount(dirPath: [*c]const u8) callconv(.c) c_uint {
    return GetDirectoryFileCountEx(dirPath, FILE_FILTER_TAG_ALL, false);
}

export fn GetDirectoryFileCountEx(basePath: [*c]const u8, filter: [*c]const u8, scanSubdirs: bool) callconv(.c) c_uint {
    var fileCounter: c_uint = 0;
    var path: [MAX_FILEPATH_LENGTH]u8 = std.mem.zeroes([MAX_FILEPATH_LENGTH]u8);

    const dir = opendir(basePath);
    if (dir != null) {
        while (readdir(dir)) |entity| {
            if ((strcmp(&entity.d_name, ".") != 0) and (strcmp(&entity.d_name, "..") != 0)) {
                const pathLength = snprintf(&path, MAX_FILEPATH_LENGTH, "%s/%s", basePath, &entity.d_name);
                if ((pathLength < 0) or (pathLength >= MAX_FILEPATH_LENGTH)) {
                    TraceLog(LOG_WARNING, "FILEIO: Path longer than %d characters (%s...)", @as(c_int, MAX_FILEPATH_LENGTH), basePath);
                } else if (IsPathFile(&path)) {
                    if ((filter == null) or (strstr(filter, FILE_FILTER_TAG_ALL) != null) or (strstr(filter, FILE_FILTER_TAG_FILE_ONLY) != null) or IsFileExtension(&path, filter)) fileCounter += 1;
                } else {
                    if ((filter != null) and ((strstr(filter, FILE_FILTER_TAG_ALL) != null) or (strstr(filter, FILE_FILTER_TAG_DIR_ONLY) != null))) fileCounter += 1;
                    if (scanSubdirs) fileCounter += GetDirectoryFileCountEx(&path, filter, scanSubdirs);
                }
            }
        }
        _ = closedir(dir);
    } else TraceLog(LOG_WARNING, "FILEIO: Directory cannot be opened (%s)", basePath);

    return fileCounter;
}

// Scan all files and directories in a base path (internal helper)
fn ScanDirectoryFiles(basePath: [*c]const u8, files: *FilePathList, filter: [*c]const u8, expectedFileCount: c_uint, scanSubdirs: bool) void {
    var path: [MAX_FILEPATH_LENGTH]u8 = std.mem.zeroes([MAX_FILEPATH_LENGTH]u8);

    const dir = opendir(basePath);
    if (dir != null) {
        while (files.count < expectedFileCount) {
            const dp = readdir(dir) orelse break;
            if ((strcmp(&dp.d_name, ".") != 0) and (strcmp(&dp.d_name, "..") != 0)) {
                const pathLength = snprintf(&path, MAX_FILEPATH_LENGTH, "%s/%s", basePath, &dp.d_name);
                if ((pathLength < 0) or (pathLength >= MAX_FILEPATH_LENGTH)) {
                    TraceLog(LOG_WARNING, "FILEIO: Path longer than %d characters (%s...)", @as(c_int, MAX_FILEPATH_LENGTH), basePath);
                } else if (IsPathFile(&path)) {
                    if ((filter == null) or (strstr(filter, FILE_FILTER_TAG_ALL) != null) or (strstr(filter, FILE_FILTER_TAG_FILE_ONLY) != null) or IsFileExtension(&path, filter)) {
                        _ = memcpy(@ptrCast(files.paths[files.count]), @ptrCast(&path), @intCast(pathLength));
                        files.count += 1;
                    }
                } else {
                    if ((filter != null) and ((strstr(filter, FILE_FILTER_TAG_DIR_ONLY) != null) or (strstr(filter, FILE_FILTER_TAG_ALL) != null))) {
                        _ = memcpy(@ptrCast(files.paths[files.count]), @ptrCast(&path), @intCast(pathLength));
                        files.count += 1;
                    }
                    if (scanSubdirs) ScanDirectoryFiles(&path, files, filter, expectedFileCount, scanSubdirs);
                }
            }
        }
        _ = closedir(dir);
    } else TraceLog(LOG_WARNING, "FILEIO: Directory cannot be opened (%s)", basePath);
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Compression and Encoding
//----------------------------------------------------------------------------------

export fn CompressData(data: [*c]const u8, dataSize: c_int, compDataSize: [*c]c_int) callconv(.c) [*c]u8 {
    const COMPRESSION_QUALITY_DEFLATE: c_int = 8;
    var compData: [*c]u8 = null;

    const sdeflPtr: *sdefl = @ptrCast(@alignCast(RL_CALLOC(1, rl_sizeof_sdefl())));
    const bounds = sdefl_bound(dataSize);
    compData = @ptrCast(@alignCast(RL_CALLOC(@intCast(bounds), 1)));

    compDataSize.* = sdeflate(sdeflPtr, @ptrCast(compData), @ptrCast(data), dataSize, COMPRESSION_QUALITY_DEFLATE);
    RL_FREE(sdeflPtr);

    TraceLog(LOG_INFO, "SYSTEM: Compress data: Original size: %i -> Comp. size: %i", dataSize, compDataSize.*);
    return compData;
}

export fn DecompressData(compData: [*c]const u8, compDataSize: c_int, dataSize: [*c]c_int) callconv(.c) [*c]u8 {
    var data: [*c]u8 = null;
    const maxSize: c_int = @intCast(MAX_DECOMPRESSION_SIZE * 1024 * 1024);

    const data0: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(@intCast(maxSize), 1)));
    const size = sinflate(@ptrCast(data0), maxSize, @ptrCast(compData), compDataSize);

    data = @ptrCast(@alignCast(RL_CALLOC(@intCast(size), 1)));
    _ = memcpy(@ptrCast(data), @ptrCast(data0), @intCast(size));
    _ = memset(@ptrCast(data0), 0, @intCast(maxSize));
    RL_FREE(data0);

    TraceLog(LOG_INFO, "SYSTEM: Decompress data: Comp. size: %i -> Original size: %i", compDataSize, size);

    dataSize.* = size;
    return data;
}

export fn EncodeDataBase64(data: [*c]const u8, dataSize: c_int, outputSize: [*c]c_int) callconv(.c) [*c]u8 {
    const base64EncodeTable = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    var paddedSize = dataSize;
    while (@rem(paddedSize, 3) != 0) paddedSize += 1;
    var estimatedOutputSize = 4 * @divTrunc(paddedSize, 3);
    const padding = paddedSize - dataSize;

    estimatedOutputSize += 1;

    const encodedData: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(@intCast(estimatedOutputSize), 1)));
    if (encodedData == null) return null;

    var outputCount: usize = 0;
    var i: c_int = 0;
    while (i < dataSize) {
        const octetA: c_uint = data[@intCast(i)];
        const octetB: c_uint = if ((i + 1) < dataSize) data[@intCast(i + 1)] else 0;
        const octetC: c_uint = if ((i + 2) < dataSize) data[@intCast(i + 2)] else 0;

        const octetPack: c_uint = (octetA << 16) | (octetB << 8) | octetC;

        encodedData[outputCount + 0] = base64EncodeTable[(octetPack >> 18) & 0x3f];
        encodedData[outputCount + 1] = base64EncodeTable[(octetPack >> 12) & 0x3f];
        encodedData[outputCount + 2] = base64EncodeTable[(octetPack >> 6) & 0x3f];
        encodedData[outputCount + 3] = base64EncodeTable[octetPack & 0x3f];
        outputCount += 4;
        i += 3;
    }

    var p: c_int = 0;
    while (p < padding) : (p += 1) encodedData[outputCount - @as(usize, @intCast(p)) - 1] = '=';

    encodedData[outputCount] = 0;
    outputCount += 1;

    if (outputCount != estimatedOutputSize) TraceLog(LOG_WARNING, "BASE64: Output size differs from estimation");

    outputSize.* = estimatedOutputSize;
    return encodedData;
}

export fn DecodeDataBase64(text: [*c]const u8, outputSize: [*c]c_int) callconv(.c) [*c]u8 {
    var base64DecodeTable: [256]u8 = std.mem.zeroes([256]u8);
    {
        var c: u8 = 'A';
        while (c <= 'Z') : (c += 1) base64DecodeTable[c] = c - 'A';
        c = 'a';
        while (c <= 'z') : (c += 1) base64DecodeTable[c] = c - 'a' + 26;
        c = '0';
        while (c <= '9') : (c += 1) base64DecodeTable[c] = c - '0' + 52;
        base64DecodeTable['+'] = 62;
        base64DecodeTable['/'] = 63;
    }

    outputSize.* = 0;
    if (text == null) return null;

    const dataSize: c_int = @intCast(strlen(text));
    var ending = dataSize - 1;
    var padding: c_int = 0;
    while (text[@intCast(ending)] == '=') {
        padding += 1;
        ending -= 1;
    }
    const estimatedOutputSize = 3 * @divTrunc(dataSize, 4) - padding;
    const maxOutputSize = 3 * @divTrunc(dataSize, 4);

    const decodedData: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(@intCast(maxOutputSize), 1)));
    if (decodedData == null) return null;

    var outputCount: c_int = 0;
    var i: c_int = 0;
    while (i < dataSize) {
        if ((i + 2) >= dataSize) {
            TraceLog(LOG_WARNING, "BASE64: Decoding error: Input data size is not valid");
            break;
        }

        const sixtetA: c_uint = base64DecodeTable[text[@intCast(i)]];
        const sixtetB: c_uint = base64DecodeTable[text[@intCast(i + 1)]];
        const sixtetC: c_uint = if (((i + 2) < dataSize) and (text[@intCast(i + 2)] != '=')) base64DecodeTable[text[@intCast(i + 2)]] else 0;
        const sixtetD: c_uint = if (((i + 3) < dataSize) and (text[@intCast(i + 3)] != '=')) base64DecodeTable[text[@intCast(i + 3)]] else 0;

        const octetPack: c_uint = (sixtetA << 18) | (sixtetB << 12) | (sixtetC << 6) | sixtetD;

        if ((outputCount + 3) > maxOutputSize) {
            TraceLog(LOG_WARNING, "BASE64: Decoding error: Output data size is too small");
            break;
        }

        decodedData[@intCast(outputCount + 0)] = @intCast((octetPack >> 16) & 0xff);
        decodedData[@intCast(outputCount + 1)] = @intCast((octetPack >> 8) & 0xff);
        decodedData[@intCast(outputCount + 2)] = @intCast(octetPack & 0xff);
        outputCount += 3;
        i += 4;
    }

    if (estimatedOutputSize != (outputCount - padding)) TraceLog(LOG_WARNING, "BASE64: Decoded size differs from estimation");

    outputSize.* = estimatedOutputSize;
    return decodedData;
}

// CRC32 table (computed at comptime, standard reflected polynomial 0xEDB88320)
const crcTable: [256]u32 = blk: {
    @setEvalBranchQuota(20000);
    var t: [256]u32 = undefined;
    var n: u32 = 0;
    while (n < 256) : (n += 1) {
        var c: u32 = n;
        var k: u32 = 0;
        while (k < 8) : (k += 1) {
            c = if ((c & 1) != 0) 0xedb88320 ^ (c >> 1) else (c >> 1);
        }
        t[n] = c;
    }
    break :blk t;
};

export fn ComputeCRC32(data: [*c]const u8, dataSize: c_int) callconv(.c) c_uint {
    var crc: u32 = ~@as(u32, 0);
    var i: c_int = 0;
    while (i < dataSize) : (i += 1) {
        crc = (crc >> 8) ^ crcTable[(data[@intCast(i)] ^ (crc & 0xff))];
    }
    return ~crc;
}

inline fn rotl32(x: u32, c: u5) u32 {
    return (x << c) | (x >> @intCast(32 - @as(u32, c)));
}

var md5_hash: [4]c_uint = std.mem.zeroes([4]c_uint);
export fn ComputeMD5(data: [*c]const u8, dataSize: c_int) callconv(.c) [*c]c_uint {
    const r = [_]u5{
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9,  14, 20, 5, 9,  14, 20, 5, 9,  14, 20, 5, 9,  14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    };
    const k = [_]u32{
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    };

    var hash = &md5_hash;
    hash[0] = 0x67452301;
    hash[1] = 0xefcdab89;
    hash[2] = 0x98badcfe;
    hash[3] = 0x10325476;

    const newDataSize: c_int = ((@divTrunc(dataSize + 8, 64) + 1) * 64) - 8;

    const msg: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(@intCast(newDataSize + 64), 1)));
    _ = memcpy(@ptrCast(msg), @ptrCast(data), @intCast(dataSize));
    msg[@intCast(dataSize)] = 128;

    const bitsLen: u32 = @bitCast(@as(i32, @intCast(8 * dataSize)));
    _ = memcpy(@ptrCast(msg + @as(usize, @intCast(newDataSize))), @ptrCast(&bitsLen), 4);

    var offset: c_int = 0;
    while (offset < newDataSize) : (offset += 64) {
        const w: [*c]align(1) u32 = @ptrCast(msg + @as(usize, @intCast(offset)));

        var a: u32 = hash[0];
        var b: u32 = hash[1];
        var c: u32 = hash[2];
        var d: u32 = hash[3];

        var i: usize = 0;
        while (i < 64) : (i += 1) {
            var f: u32 = 0;
            var g: usize = 0;
            if (i < 16) {
                f = (b & c) | ((~b) & d);
                g = i;
            } else if (i < 32) {
                f = (d & b) | ((~d) & c);
                g = (5 * i + 1) % 16;
            } else if (i < 48) {
                f = b ^ c ^ d;
                g = (3 * i + 5) % 16;
            } else {
                f = c ^ (b | (~d));
                g = (7 * i) % 16;
            }

            const temp = d;
            d = c;
            c = b;
            b = b +% rotl32(a +% f +% k[i] +% w[g], r[i]);
            a = temp;
        }

        hash[0] +%= a;
        hash[1] +%= b;
        hash[2] +%= c;
        hash[3] +%= d;
    }

    RL_FREE(msg);
    return @ptrCast(hash);
}

inline fn rotl32s(x: u32, c: u5) u32 {
    return (x << c) | (x >> @intCast(32 - @as(u32, c)));
}

var sha1_hash: [5]c_uint = std.mem.zeroes([5]c_uint);
export fn ComputeSHA1(data: [*c]const u8, dataSize: c_int) callconv(.c) [*c]c_uint {
    var hash = &sha1_hash;
    hash[0] = 0x67452301;
    hash[1] = 0xEFCDAB89;
    hash[2] = 0x98BADCFE;
    hash[3] = 0x10325476;
    hash[4] = 0xC3D2E1F0;

    const newDataSize: c_int = ((@divTrunc(dataSize + 8, 64) + 1) * 64);

    const msg: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(@intCast(newDataSize), 1)));
    _ = memcpy(@ptrCast(msg), @ptrCast(data), @intCast(dataSize));
    msg[@intCast(dataSize)] = 128;

    const bitsLen: u64 = 8 *% @as(u64, @intCast(dataSize));
    msg[@intCast(newDataSize - 1)] = @truncate(bitsLen);
    msg[@intCast(newDataSize - 2)] = @truncate(bitsLen >> 8);
    msg[@intCast(newDataSize - 3)] = @truncate(bitsLen >> 16);
    msg[@intCast(newDataSize - 4)] = @truncate(bitsLen >> 24);
    msg[@intCast(newDataSize - 5)] = @truncate(bitsLen >> 32);
    msg[@intCast(newDataSize - 6)] = @truncate(bitsLen >> 40);
    msg[@intCast(newDataSize - 7)] = @truncate(bitsLen >> 48);
    msg[@intCast(newDataSize - 8)] = @truncate(bitsLen >> 56);

    var offset: c_int = 0;
    while (offset < newDataSize) : (offset += 64) {
        var w: [80]u32 = std.mem.zeroes([80]u32);
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            const o: usize = @as(usize, @intCast(offset)) + i * 4;
            w[i] = (@as(u32, msg[o + 0]) << 24) | (@as(u32, msg[o + 1]) << 16) | (@as(u32, msg[o + 2]) << 8) | (@as(u32, msg[o + 3]));
        }
        i = 16;
        while (i < 80) : (i += 1) w[i] = rotl32s(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);

        var a: u32 = hash[0];
        var b: u32 = hash[1];
        var c: u32 = hash[2];
        var d: u32 = hash[3];
        var e: u32 = hash[4];

        i = 0;
        while (i < 80) : (i += 1) {
            var f: u32 = 0;
            var k: u32 = 0;
            if (i < 20) {
                f = (b & c) | ((~b) & d);
                k = 0x5A827999;
            } else if (i < 40) {
                f = b ^ c ^ d;
                k = 0x6ED9EBA1;
            } else if (i < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8F1BBCDC;
            } else {
                f = b ^ c ^ d;
                k = 0xCA62C1D6;
            }

            const temp = rotl32s(a, 5) +% f +% e +% k +% w[i];
            e = d;
            d = c;
            c = rotl32s(b, 30);
            b = a;
            a = temp;
        }

        hash[0] +%= a;
        hash[1] +%= b;
        hash[2] +%= c;
        hash[3] +%= d;
        hash[4] +%= e;
    }

    RL_FREE(msg);
    return @ptrCast(hash);
}

inline fn rotr32(x: u32, c: u5) u32 {
    return (x >> c) | (x << @intCast(32 - @as(u32, c)));
}
inline fn sha256_a0(x: u32) u32 {
    return rotr32(x, 7) ^ rotr32(x, 18) ^ (x >> 3);
}
inline fn sha256_a1(x: u32) u32 {
    return rotr32(x, 17) ^ rotr32(x, 19) ^ (x >> 10);
}

var sha256_hash: [8]c_uint = std.mem.zeroes([8]c_uint);
export fn ComputeSHA256(data: [*c]const u8, dataSize: c_int) callconv(.c) [*c]c_uint {
    const k = [_]u32{
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    };

    var hash = &sha256_hash;
    hash[0] = 0x6A09e667;
    hash[1] = 0xbb67ae85;
    hash[2] = 0x3c6ef372;
    hash[3] = 0xa54ff53a;
    hash[4] = 0x510e527f;
    hash[5] = 0x9b05688c;
    hash[6] = 0x1f83d9ab;
    hash[7] = 0x5be0cd19;

    const bitLen: u64 = 8 *% @as(u64, @intCast(dataSize));
    var paddedSize: u64 = @as(u64, @intCast(dataSize)) + @sizeOf(c_int);
    paddedSize += (64 - (paddedSize % 64));
    const buffer: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(@intCast(paddedSize), 1)));

    _ = memcpy(@ptrCast(buffer), @ptrCast(data), @intCast(dataSize));
    buffer[@intCast(dataSize)] = 0x80;
    var ib: usize = 1;
    while (ib <= @sizeOf(u64)) : (ib += 1) {
        buffer[@intCast(paddedSize - @sizeOf(u64) + (ib - 1))] = @truncate((bitLen >> @intCast(8 * (@sizeOf(u64) - ib))) & 0xFF);
    }

    var blockN: u64 = 0;
    while (blockN < paddedSize / 64) : (blockN += 1) {
        var a: u32 = hash[0];
        var b: u32 = hash[1];
        var c: u32 = hash[2];
        var d: u32 = hash[3];
        var e: u32 = hash[4];
        var f: u32 = hash[5];
        var g: u32 = hash[6];
        var h: u32 = hash[7];

        const block = buffer + @as(usize, @intCast(blockN * 64));
        var w: [64]u32 = std.mem.zeroes([64]u32);
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            w[i] = (@as(u32, block[i * 4 + 0]) << 24) | (@as(u32, block[i * 4 + 1]) << 16) | (@as(u32, block[i * 4 + 2]) << 8) | (@as(u32, block[i * 4 + 3]));
        }
        var t: usize = 16;
        while (t < 64) : (t += 1) w[t] = sha256_a1(w[t - 2]) +% w[t - 7] +% sha256_a0(w[t - 15]) +% w[t - 16];

        t = 0;
        while (t < 64) : (t += 1) {
            const e1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
            const ch = (e & f) ^ (~e & g);
            const t1 = h +% e1 +% ch +% k[t] +% w[t];
            const e0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
            const maj = (a & b) ^ (a & c) ^ (b & c);
            const t2 = e0 +% maj;

            h = g;
            g = f;
            f = e;
            e = d +% t1;
            d = c;
            c = b;
            b = a;
            a = t1 +% t2;
        }

        hash[0] +%= a;
        hash[1] +%= b;
        hash[2] +%= c;
        hash[3] +%= d;
        hash[4] +%= e;
        hash[5] +%= f;
        hash[6] +%= g;
        hash[7] +%= h;
    }

    RL_FREE(buffer);
    return @ptrCast(hash);
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Automation Events Recording and Playing
//----------------------------------------------------------------------------------

export fn LoadAutomationEventList(fileName: [*c]const u8) callconv(.c) AutomationEventList {
    var list = std.mem.zeroes(AutomationEventList);

    list.events = @ptrCast(@alignCast(RL_CALLOC(MAX_AUTOMATION_EVENTS, @sizeOf(AutomationEvent))));
    list.capacity = MAX_AUTOMATION_EVENTS;

    if (fileName == null) {
        TraceLog(LOG_INFO, "AUTOMATION: New empty events list loaded successfully");
    } else {
        const raeFile = fopen(fileName, "rt");
        if (raeFile != null) {
            var counter: c_uint = 0;
            var buffer: [256]u8 = std.mem.zeroes([256]u8);
            var eventDesc: [64]u8 = std.mem.zeroes([64]u8);

            var result = fgets(&buffer, 256, raeFile);
            if (result != @as([*c]u8, &buffer)) TraceLog(LOG_WARNING, "AUTOMATION: [%s] Issue reading line to buffer", fileName);

            while (feof(raeFile) == 0) {
                switch (buffer[0]) {
                    'c' => _ = sscanf(&buffer, "c %i", &list.count),
                    'e' => {
                        _ = sscanf(&buffer, "e %d %d %d %d %d %d %[^\n]s", &list.events[counter].frame, &list.events[counter].type, &list.events[counter].params[0], &list.events[counter].params[1], &list.events[counter].params[2], &list.events[counter].params[3], &eventDesc);
                        counter += 1;
                    },
                    else => {},
                }
                result = fgets(&buffer, 256, raeFile);
                if (result != @as([*c]u8, &buffer)) TraceLog(LOG_WARNING, "AUTOMATION: [%s] Issue reading line to buffer", fileName);
            }

            if (counter != list.count) {
                TraceLog(LOG_WARNING, "AUTOMATION: Events read from file [%i] do not mach event count specified [%i]", counter, list.count);
                list.count = counter;
            }

            _ = fclose(raeFile);
            TraceLog(LOG_INFO, "AUTOMATION: Events file loaded successfully");
        }
        TraceLog(LOG_INFO, "AUTOMATION: Events loaded from file: %i", list.count);
    }

    return list;
}

export fn UnloadAutomationEventList(list: AutomationEventList) callconv(.c) void {
    RL_FREE(list.events);
}

export fn ExportAutomationEventList(list: AutomationEventList, fileName: [*c]const u8) callconv(.c) bool {
    var result = false;

    const txtData: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(256 * list.count + 2048, 1)));

    var byteCount: c_int = 0;
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# Automation events exporter v1.0 - raylib automation events list\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#    c <events_count>\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#    e <frame> <event_type> <param0> <param1> <param2> <param3> // <event_type_name>\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# more info and bugs-report:  github.com/raysan5/raylib\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# feedback and support:       ray[at]raylib.com\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "# Copyright (c) 2023-2026 Ramon Santamaria (@raysan5)\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#\n\n");

    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "c %i\n", list.count);
    var i: c_uint = 0;
    while (i < list.count) : (i += 1) {
        byteCount += snprintf(txtData + @as(usize, @intCast(byteCount)), 256, "e %i %i %i %i %i %i // Event: %s\n", list.events[i].frame, list.events[i].type, list.events[i].params[0], list.events[i].params[1], list.events[i].params[2], list.events[i].params[3], autoEventTypeName[list.events[i].type]);
    }

    result = SaveFileText(fileName, txtData);
    RL_FREE(txtData);

    return result;
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
        const movement = if (value < 0.0) CORE.Input.Gamepad.axisState[@intCast(gamepad)][@intCast(axis)] else fabsf(CORE.Input.Gamepad.axisState[@intCast(gamepad)][@intCast(axis)]);
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

export fn GetMouseX() callconv(.c) c_int {
    return @intFromFloat((CORE.Input.Mouse.currentPosition.x + CORE.Input.Mouse.offset.x) * CORE.Input.Mouse.scale.x);
}
export fn GetMouseY() callconv(.c) c_int {
    return @intFromFloat((CORE.Input.Mouse.currentPosition.y + CORE.Input.Mouse.offset.y) * CORE.Input.Mouse.scale.y);
}

export fn GetMousePosition() callconv(.c) Vector2 {
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

export fn SetMouseScale(scaleX: f32, scaleY: f32) callconv(.c) void {
    CORE.Input.Mouse.scale = .{ .x = scaleX, .y = scaleY };
}

export fn GetMouseWheelMove() callconv(.c) f32 {
    var result: f32 = 0.0;
    if (fabsf(CORE.Input.Mouse.currentWheelMove.x) > fabsf(CORE.Input.Mouse.currentWheelMove.y)) result = CORE.Input.Mouse.currentWheelMove.x else result = CORE.Input.Mouse.currentWheelMove.y;
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
fn InitTimer() void {
    var now = std.mem.zeroes(timespec);
    if (clock_gettime(CLOCK_MONOTONIC, &now) == 0) {
        CORE.Time.base = @as(c_ulonglong, @intCast(now.tv_sec)) * 1000000000 + @as(c_ulonglong, @intCast(now.tv_nsec));
    } else TraceLog(LOG_WARNING, "TIMER: Hi-resolution timer not available");

    CORE.Time.previous = GetTime();
}

// Set viewport for a provided width and height
fn SetupViewport(width: c_int, height: c_int) void {
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

//==================================================================================
// PLATFORM: DESKTOP (GLFW)  — ported from platforms/rcore_desktop_glfw.c
//==================================================================================

export fn WindowShouldClose() callconv(.c) bool {
    if (CORE.Window.ready) return CORE.Window.shouldClose;
    return true;
}

export fn ToggleFullscreen() callconv(.c) void {
    if (!flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE)) {
        CORE.Window.previousPosition = CORE.Window.position;
        CORE.Window.previousScreen = CORE.Window.screen;

        var monitorCount: c_int = 0;
        const monitorIndex = GetCurrentMonitor();
        const monitors = glfwGetMonitors(&monitorCount);
        const monitor: ?*GLFWmonitor = if (monitorIndex < monitorCount) monitors.?[@intCast(monitorIndex)] else null;

        if (monitor != null) {
            const mode = glfwGetVideoMode(monitors.?[@intCast(monitorIndex)]).?;
            CORE.Window.display.width = @intCast(mode.width);
            CORE.Window.display.height = @intCast(mode.height);

            CORE.Window.position = .{ .x = 0, .y = 0 };
            CORE.Window.screen = CORE.Window.display;

            flagSet(&CORE.Window.flags, FLAG_FULLSCREEN_MODE);

            glfwSetWindowMonitor(platform.handle, monitor, 0, 0, @intCast(CORE.Window.screen.width), @intCast(CORE.Window.screen.height), GLFW_DONT_CARE);
        } else TraceLog(LOG_WARNING, "GLFW: Failed to get monitor");
    } else {
        CORE.Window.position = CORE.Window.previousPosition;
        CORE.Window.screen = CORE.Window.previousScreen;

        flagClear(&CORE.Window.flags, FLAG_FULLSCREEN_MODE);

        if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) {
            const scaleDpi = GetWindowScaleDPI();
            CORE.Window.screen.width = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.screen.width)) * scaleDpi.x);
            CORE.Window.screen.height = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.screen.height)) * scaleDpi.y);
        }

        glfwSetWindowMonitor(platform.handle, null, CORE.Window.position.x, CORE.Window.position.y, @intCast(CORE.Window.screen.width), @intCast(CORE.Window.screen.height), GLFW_DONT_CARE);
    }

    if (flagIsSet(CORE.Window.flags, FLAG_VSYNC_HINT)) glfwSwapInterval(1);
}

export fn ToggleBorderlessWindowed() callconv(.c) void {
    if (flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE)) ToggleFullscreen();

    var monitorCount: c_int = 0;
    const monitors = glfwGetMonitors(&monitorCount);
    const monitor = GetCurrentMonitor();

    if ((monitor >= 0) and (monitor < monitorCount)) {
        const mode = glfwGetVideoMode(monitors.?[@intCast(monitor)]);
        if (mode != null) {
            if (!flagIsSet(CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE)) {
                CORE.Window.previousPosition = CORE.Window.position;
                CORE.Window.previousScreen = CORE.Window.screen;

                glfwSetWindowAttrib(platform.handle, GLFW_DECORATED, GLFW_FALSE);
                flagSet(&CORE.Window.flags, FLAG_WINDOW_UNDECORATED);

                glfwGetMonitorPos(monitors.?[@intCast(monitor)], &CORE.Window.position.x, &CORE.Window.position.y);
                CORE.Window.screen.width = @intCast(mode.?.width);
                CORE.Window.screen.height = @intCast(mode.?.height);

                glfwSetWindowMonitor(platform.handle, monitors.?[@intCast(monitor)], CORE.Window.position.x, CORE.Window.position.y, @intCast(CORE.Window.screen.width), @intCast(CORE.Window.screen.height), mode.?.refreshRate);

                glfwFocusWindow(platform.handle);
                flagSet(&CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE);
            } else {
                CORE.Window.position = CORE.Window.previousPosition;
                CORE.Window.screen = CORE.Window.previousScreen;

                glfwSetWindowAttrib(platform.handle, GLFW_DECORATED, GLFW_TRUE);
                flagClear(&CORE.Window.flags, FLAG_WINDOW_UNDECORATED);

                if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) {
                    const scaleDpi = GetWindowScaleDPI();
                    CORE.Window.screen.width = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.screen.width)) * scaleDpi.x);
                    CORE.Window.screen.height = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.screen.height)) * scaleDpi.y);
                }

                glfwSetWindowMonitor(platform.handle, null, CORE.Window.position.x, CORE.Window.position.y, @intCast(CORE.Window.screen.width), @intCast(CORE.Window.screen.height), mode.?.refreshRate);

                glfwFocusWindow(platform.handle);
                flagClear(&CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE);
            }
        } else TraceLog(LOG_WARNING, "GLFW: Failed to find video mode for selected monitor");
    } else TraceLog(LOG_WARNING, "GLFW: Failed to find selected monitor");
}

export fn MaximizeWindow() callconv(.c) void {
    if (glfwGetWindowAttrib(platform.handle, GLFW_RESIZABLE) == GLFW_TRUE) {
        glfwMaximizeWindow(platform.handle);
        flagSet(&CORE.Window.flags, FLAG_WINDOW_MAXIMIZED);
    }
}

export fn MinimizeWindow() callconv(.c) void {
    glfwIconifyWindow(platform.handle);
}

export fn RestoreWindow() callconv(.c) void {
    if (glfwGetWindowAttrib(platform.handle, GLFW_RESIZABLE) == GLFW_TRUE) {
        glfwRestoreWindow(platform.handle);
        flagClear(&CORE.Window.flags, FLAG_WINDOW_MINIMIZED);
        flagClear(&CORE.Window.flags, FLAG_WINDOW_MAXIMIZED);
    }
}

export fn SetWindowState(flags: c_uint) callconv(.c) void {
    if (!CORE.Window.ready) TraceLog(LOG_WARNING, "WINDOW: SetWindowState does nothing before window initialization, Use \"SetConfigFlags\" instead");

    if ((flagIsSet(CORE.Window.flags, FLAG_VSYNC_HINT) != flagIsSet(flags, FLAG_VSYNC_HINT)) and flagIsSet(flags, FLAG_VSYNC_HINT)) {
        glfwSwapInterval(1);
        flagSet(&CORE.Window.flags, FLAG_VSYNC_HINT);
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE) != flagIsSet(flags, FLAG_BORDERLESS_WINDOWED_MODE)) and flagIsSet(flags, FLAG_BORDERLESS_WINDOWED_MODE)) {
        ToggleBorderlessWindowed();
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE) != flagIsSet(flags, FLAG_FULLSCREEN_MODE)) and flagIsSet(flags, FLAG_FULLSCREEN_MODE)) {
        ToggleFullscreen();
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_RESIZABLE) != flagIsSet(flags, FLAG_WINDOW_RESIZABLE)) and flagIsSet(flags, FLAG_WINDOW_RESIZABLE)) {
        glfwSetWindowAttrib(platform.handle, GLFW_RESIZABLE, GLFW_TRUE);
        flagSet(&CORE.Window.flags, FLAG_WINDOW_RESIZABLE);
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_UNDECORATED) != flagIsSet(flags, FLAG_WINDOW_UNDECORATED)) and flagIsSet(flags, FLAG_WINDOW_UNDECORATED)) {
        glfwSetWindowAttrib(platform.handle, GLFW_DECORATED, GLFW_FALSE);
        flagSet(&CORE.Window.flags, FLAG_WINDOW_UNDECORATED);
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIDDEN) != flagIsSet(flags, FLAG_WINDOW_HIDDEN)) and flagIsSet(flags, FLAG_WINDOW_HIDDEN)) {
        glfwHideWindow(platform.handle);
        flagSet(&CORE.Window.flags, FLAG_WINDOW_HIDDEN);
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_MINIMIZED) != flagIsSet(flags, FLAG_WINDOW_MINIMIZED)) and flagIsSet(flags, FLAG_WINDOW_MINIMIZED)) {
        MinimizeWindow();
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_MAXIMIZED) != flagIsSet(flags, FLAG_WINDOW_MAXIMIZED)) and flagIsSet(flags, FLAG_WINDOW_MAXIMIZED)) {
        MaximizeWindow();
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_UNFOCUSED) != flagIsSet(flags, FLAG_WINDOW_UNFOCUSED)) and flagIsSet(flags, FLAG_WINDOW_UNFOCUSED)) {
        glfwSetWindowAttrib(platform.handle, GLFW_FOCUS_ON_SHOW, GLFW_FALSE);
        flagSet(&CORE.Window.flags, FLAG_WINDOW_UNFOCUSED);
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_TOPMOST) != flagIsSet(flags, FLAG_WINDOW_TOPMOST)) and flagIsSet(flags, FLAG_WINDOW_TOPMOST)) {
        glfwSetWindowAttrib(platform.handle, GLFW_FLOATING, GLFW_TRUE);
        flagSet(&CORE.Window.flags, FLAG_WINDOW_TOPMOST);
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_ALWAYS_RUN) != flagIsSet(flags, FLAG_WINDOW_ALWAYS_RUN)) and flagIsSet(flags, FLAG_WINDOW_ALWAYS_RUN)) {
        flagSet(&CORE.Window.flags, FLAG_WINDOW_ALWAYS_RUN);
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_TRANSPARENT) != flagIsSet(flags, FLAG_WINDOW_TRANSPARENT)) and flagIsSet(flags, FLAG_WINDOW_TRANSPARENT)) {
        TraceLog(LOG_WARNING, "WINDOW: Framebuffer transparency can only be configured before window initialization");
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI) != flagIsSet(flags, FLAG_WINDOW_HIGHDPI)) and flagIsSet(flags, FLAG_WINDOW_HIGHDPI)) {
        TraceLog(LOG_WARNING, "WINDOW: High DPI can only be configured before window initialization");
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_MOUSE_PASSTHROUGH) != flagIsSet(flags, FLAG_WINDOW_MOUSE_PASSTHROUGH)) and flagIsSet(flags, FLAG_WINDOW_MOUSE_PASSTHROUGH)) {
        glfwSetWindowAttrib(platform.handle, GLFW_MOUSE_PASSTHROUGH, GLFW_TRUE);
        flagSet(&CORE.Window.flags, FLAG_WINDOW_MOUSE_PASSTHROUGH);
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_MSAA_4X_HINT) != flagIsSet(flags, FLAG_MSAA_4X_HINT)) and flagIsSet(flags, FLAG_MSAA_4X_HINT)) {
        TraceLog(LOG_WARNING, "WINDOW: MSAA can only be configured before window initialization");
    }
    if ((flagIsSet(CORE.Window.flags, FLAG_INTERLACED_HINT) != flagIsSet(flags, FLAG_INTERLACED_HINT)) and flagIsSet(flags, FLAG_INTERLACED_HINT)) {
        TraceLog(LOG_WARNING, "WINDOW: Interlaced mode can only be configured before window initialization");
    }
}

export fn ClearWindowState(flags: c_uint) callconv(.c) void {
    if (flagIsSet(CORE.Window.flags, FLAG_VSYNC_HINT) and flagIsSet(flags, FLAG_VSYNC_HINT)) {
        glfwSwapInterval(0);
        flagClear(&CORE.Window.flags, FLAG_VSYNC_HINT);
    }
    if (flagIsSet(CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE) and flagIsSet(flags, FLAG_BORDERLESS_WINDOWED_MODE)) {
        ToggleBorderlessWindowed();
    }
    if (flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE) and flagIsSet(flags, FLAG_FULLSCREEN_MODE)) {
        ToggleFullscreen();
    }
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_RESIZABLE) and flagIsSet(flags, FLAG_WINDOW_RESIZABLE)) {
        glfwSetWindowAttrib(platform.handle, GLFW_RESIZABLE, GLFW_FALSE);
        flagClear(&CORE.Window.flags, FLAG_WINDOW_RESIZABLE);
    }
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIDDEN) and flagIsSet(flags, FLAG_WINDOW_HIDDEN)) {
        glfwShowWindow(platform.handle);
        flagClear(&CORE.Window.flags, FLAG_WINDOW_HIDDEN);
    }
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_MINIMIZED) and flagIsSet(flags, FLAG_WINDOW_MINIMIZED)) {
        RestoreWindow();
    }
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_MAXIMIZED) and flagIsSet(flags, FLAG_WINDOW_MAXIMIZED)) {
        RestoreWindow();
    }
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_UNDECORATED) and flagIsSet(flags, FLAG_WINDOW_UNDECORATED)) {
        glfwSetWindowAttrib(platform.handle, GLFW_DECORATED, GLFW_TRUE);
        flagClear(&CORE.Window.flags, FLAG_WINDOW_UNDECORATED);
    }
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_UNFOCUSED) and flagIsSet(flags, FLAG_WINDOW_UNFOCUSED)) {
        glfwSetWindowAttrib(platform.handle, GLFW_FOCUS_ON_SHOW, GLFW_TRUE);
        flagClear(&CORE.Window.flags, FLAG_WINDOW_UNFOCUSED);
    }
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_TOPMOST) and flagIsSet(flags, FLAG_WINDOW_TOPMOST)) {
        glfwSetWindowAttrib(platform.handle, GLFW_FLOATING, GLFW_FALSE);
        flagClear(&CORE.Window.flags, FLAG_WINDOW_TOPMOST);
    }
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_ALWAYS_RUN) and flagIsSet(flags, FLAG_WINDOW_ALWAYS_RUN)) {
        flagClear(&CORE.Window.flags, FLAG_WINDOW_ALWAYS_RUN);
    }
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_TRANSPARENT) and flagIsSet(flags, FLAG_WINDOW_TRANSPARENT)) {
        TraceLog(LOG_WARNING, "WINDOW: Framebuffer transparency can only be configured before window initialization");
    }
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI) and flagIsSet(flags, FLAG_WINDOW_HIGHDPI)) {
        TraceLog(LOG_WARNING, "WINDOW: High DPI can only be configured before window initialization");
    }
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_MOUSE_PASSTHROUGH) and flagIsSet(flags, FLAG_WINDOW_MOUSE_PASSTHROUGH)) {
        glfwSetWindowAttrib(platform.handle, GLFW_MOUSE_PASSTHROUGH, GLFW_FALSE);
        flagClear(&CORE.Window.flags, FLAG_WINDOW_MOUSE_PASSTHROUGH);
    }
    if (flagIsSet(CORE.Window.flags, FLAG_MSAA_4X_HINT) and flagIsSet(flags, FLAG_MSAA_4X_HINT)) {
        TraceLog(LOG_WARNING, "WINDOW: MSAA can only be configured before window initialization");
    }
    if (flagIsSet(CORE.Window.flags, FLAG_INTERLACED_HINT) and flagIsSet(flags, FLAG_INTERLACED_HINT)) {
        TraceLog(LOG_WARNING, "RPI: Interlaced mode can only be configured before window initialization");
    }
}

export fn SetWindowIcon(image: Image) callconv(.c) void {
    if (image.data == null) {
        glfwSetWindowIcon(platform.handle, 0, null);
    } else {
        if (image.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) {
            var icon: [1]GLFWimage = undefined;
            icon[0].width = image.width;
            icon[0].height = image.height;
            icon[0].pixels = @ptrCast(image.data);
            glfwSetWindowIcon(platform.handle, 1, &icon);
        } else TraceLog(LOG_WARNING, "GLFW: Window icon image must be in R8G8B8A8 pixel format");
    }
}

export fn SetWindowIcons(images: [*c]Image, count: c_int) callconv(.c) void {
    if ((images == null) or (count <= 0)) {
        glfwSetWindowIcon(platform.handle, 0, null);
    } else {
        var valid: c_int = 0;
        const icons: [*c]GLFWimage = @ptrCast(@alignCast(RL_CALLOC(@intCast(count), @sizeOf(GLFWimage))));

        var i: c_int = 0;
        while (i < count) : (i += 1) {
            if (images[@intCast(i)].format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) {
                icons[@intCast(valid)].width = images[@intCast(i)].width;
                icons[@intCast(valid)].height = images[@intCast(i)].height;
                icons[@intCast(valid)].pixels = @ptrCast(images[@intCast(i)].data);
                valid += 1;
            } else TraceLog(LOG_WARNING, "GLFW: Window icon image must be in R8G8B8A8 pixel format");
        }
        glfwSetWindowIcon(platform.handle, valid, icons);
        RL_FREE(icons);
    }
}

export fn SetWindowTitle(title: [*c]const u8) callconv(.c) void {
    CORE.Window.title = title;
    glfwSetWindowTitle(platform.handle, title);
}

export fn SetWindowPosition(x: c_int, y: c_int) callconv(.c) void {
    CORE.Window.position.x = x;
    CORE.Window.position.y = y;
    glfwSetWindowPos(platform.handle, x, y);
}

export fn SetWindowMonitor(monitor: c_int) callconv(.c) void {
    var monitorCount: c_int = 0;
    const monitors = glfwGetMonitors(&monitorCount);

    if ((monitor >= 0) and (monitor < monitorCount)) {
        if (flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE)) {
            TraceLog(LOG_INFO, "GLFW: Selected fullscreen monitor: [%i] %s", monitor, glfwGetMonitorName(monitors.?[@intCast(monitor)]));
            const mode = glfwGetVideoMode(monitors.?[@intCast(monitor)]).?;
            glfwSetWindowMonitor(platform.handle, monitors.?[@intCast(monitor)], 0, 0, mode.width, mode.height, mode.refreshRate);
        } else {
            TraceLog(LOG_INFO, "GLFW: Selected monitor: [%i] %s", monitor, glfwGetMonitorName(monitors.?[@intCast(monitor)]));

            const screenWidth: c_int = @intCast(CORE.Window.render.width);
            const screenHeight: c_int = @intCast(CORE.Window.render.height);
            var monitorWorkareaX: c_int = 0;
            var monitorWorkareaY: c_int = 0;
            var monitorWorkareaWidth: c_int = 0;
            var monitorWorkareaHeight: c_int = 0;
            glfwGetMonitorWorkarea(monitors.?[@intCast(monitor)], &monitorWorkareaX, &monitorWorkareaY, &monitorWorkareaWidth, &monitorWorkareaHeight);

            if ((screenWidth >= monitorWorkareaWidth) or (screenHeight >= monitorWorkareaHeight)) {
                glfwSetWindowPos(platform.handle, monitorWorkareaX, monitorWorkareaY);
            } else {
                const x = monitorWorkareaX + @divTrunc(monitorWorkareaWidth, 2) - @divTrunc(screenWidth, 2);
                const y = monitorWorkareaY + @divTrunc(monitorWorkareaHeight, 2) - @divTrunc(screenHeight, 2);
                glfwSetWindowPos(platform.handle, x, y);
            }
        }
    } else TraceLog(LOG_WARNING, "GLFW: Failed to find selected monitor");
}

export fn SetWindowMinSize(width: c_int, height: c_int) callconv(.c) void {
    CORE.Window.screenMin.width = @intCast(width);
    CORE.Window.screenMin.height = @intCast(height);

    const minWidth: c_int = if (CORE.Window.screenMin.width == 0) GLFW_DONT_CARE else @intCast(CORE.Window.screenMin.width);
    const minHeight: c_int = if (CORE.Window.screenMin.height == 0) GLFW_DONT_CARE else @intCast(CORE.Window.screenMin.height);
    const maxWidth: c_int = if (CORE.Window.screenMax.width == 0) GLFW_DONT_CARE else @intCast(CORE.Window.screenMax.width);
    const maxHeight: c_int = if (CORE.Window.screenMax.height == 0) GLFW_DONT_CARE else @intCast(CORE.Window.screenMax.height);
    glfwSetWindowSizeLimits(platform.handle, minWidth, minHeight, maxWidth, maxHeight);
}

export fn SetWindowMaxSize(width: c_int, height: c_int) callconv(.c) void {
    CORE.Window.screenMax.width = @intCast(width);
    CORE.Window.screenMax.height = @intCast(height);

    const minWidth: c_int = if (CORE.Window.screenMin.width == 0) GLFW_DONT_CARE else @intCast(CORE.Window.screenMin.width);
    const minHeight: c_int = if (CORE.Window.screenMin.height == 0) GLFW_DONT_CARE else @intCast(CORE.Window.screenMin.height);
    const maxWidth: c_int = if (CORE.Window.screenMax.width == 0) GLFW_DONT_CARE else @intCast(CORE.Window.screenMax.width);
    const maxHeight: c_int = if (CORE.Window.screenMax.height == 0) GLFW_DONT_CARE else @intCast(CORE.Window.screenMax.height);
    glfwSetWindowSizeLimits(platform.handle, minWidth, minHeight, maxWidth, maxHeight);
}

export fn SetWindowSize(width: c_int, height: c_int) callconv(.c) void {
    CORE.Window.screen.width = @intCast(width);
    CORE.Window.screen.height = @intCast(height);
    glfwSetWindowSize(platform.handle, width, height);
}

export fn SetWindowOpacity(opacity_in: f32) callconv(.c) void {
    var opacity = opacity_in;
    if (opacity >= 1.0) opacity = 1.0 else if (opacity <= 0.0) opacity = 0.0;
    glfwSetWindowOpacity(platform.handle, opacity);
}

export fn SetWindowFocused() callconv(.c) void {
    glfwFocusWindow(platform.handle);
}

export fn GetWindowHandle() callconv(.c) ?*anyopaque {
    return platform.handle;
}

export fn GetMonitorCount() callconv(.c) c_int {
    var monitorCount: c_int = 0;
    _ = glfwGetMonitors(&monitorCount);
    return monitorCount;
}

export fn GetCurrentMonitor() callconv(.c) c_int {
    var index: c_int = 0;
    var monitorCount: c_int = 0;
    const monitors = glfwGetMonitors(&monitorCount);
    var monitor: ?*GLFWmonitor = null;

    if (monitorCount >= 1) {
        if (IsWindowFullscreen()) {
            monitor = glfwGetWindowMonitor(platform.handle);
            var i: c_int = 0;
            while (i < monitorCount) : (i += 1) {
                if (monitors.?[@intCast(i)] == monitor) {
                    index = i;
                    break;
                }
            }
        } else {
            var closestDist: c_uint = 0xFFFFFFFF;
            var wcx: c_int = 0;
            var wcy: c_int = 0;
            glfwGetWindowPos(platform.handle, &wcx, &wcy);
            wcx += @as(c_int, @intCast(CORE.Window.screen.width)) >> 1;
            wcy += @as(c_int, @intCast(CORE.Window.screen.height)) >> 1;

            var i: c_int = 0;
            while (i < monitorCount) : (i += 1) {
                var mx: c_int = 0;
                var my: c_int = 0;
                monitor = monitors.?[@intCast(i)];
                glfwGetMonitorPos(monitor, &mx, &my);
                const mode = glfwGetVideoMode(monitor);

                if (mode != null) {
                    const right = mx + mode.?.width - 1;
                    const bottom = my + mode.?.height - 1;

                    if ((wcx >= mx) and (wcx <= right) and (wcy >= my) and (wcy <= bottom)) {
                        index = i;
                        break;
                    }

                    var xclosest = wcx;
                    if (wcx < mx) xclosest = mx else if (wcx > right) xclosest = right;
                    var yclosest = wcy;
                    if (wcy < my) yclosest = my else if (wcy > bottom) yclosest = bottom;

                    const dx = wcx - xclosest;
                    const dy = wcy - yclosest;
                    const ux: c_uint = @bitCast(dx);
                    const uy: c_uint = @bitCast(dy);
                    const dist: c_uint = ux *% ux +% uy *% uy;

                    if (dist < closestDist) {
                        index = i;
                        closestDist = dist;
                    }
                } else TraceLog(LOG_WARNING, "GLFW: Failed to find video mode for selected monitor");
            }
        }
    }

    return index;
}

export fn GetMonitorPosition(monitor: c_int) callconv(.c) Vector2 {
    var monitorCount: c_int = 0;
    const monitors = glfwGetMonitors(&monitorCount);
    if ((monitor >= 0) and (monitor < monitorCount)) {
        var x: c_int = 0;
        var y: c_int = 0;
        glfwGetMonitorPos(monitors.?[@intCast(monitor)], &x, &y);
        return .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
    } else TraceLog(LOG_WARNING, "GLFW: Failed to find selected monitor");
    return .{ .x = 0, .y = 0 };
}

export fn GetMonitorWidth(monitor: c_int) callconv(.c) c_int {
    var width: c_int = 0;
    var monitorCount: c_int = 0;
    const monitors = glfwGetMonitors(&monitorCount);
    if ((monitor >= 0) and (monitor < monitorCount)) {
        const mode = glfwGetVideoMode(monitors.?[@intCast(monitor)]);
        if (mode != null) width = mode.?.width else TraceLog(LOG_WARNING, "GLFW: Failed to find video mode for selected monitor");
    } else TraceLog(LOG_WARNING, "GLFW: Failed to find selected monitor");
    return width;
}

export fn GetMonitorHeight(monitor: c_int) callconv(.c) c_int {
    var height: c_int = 0;
    var monitorCount: c_int = 0;
    const monitors = glfwGetMonitors(&monitorCount);
    if ((monitor >= 0) and (monitor < monitorCount)) {
        const mode = glfwGetVideoMode(monitors.?[@intCast(monitor)]);
        if (mode != null) height = mode.?.height else TraceLog(LOG_WARNING, "GLFW: Failed to find video mode for selected monitor");
    } else TraceLog(LOG_WARNING, "GLFW: Failed to find selected monitor");
    return height;
}

export fn GetMonitorPhysicalWidth(monitor: c_int) callconv(.c) c_int {
    var width: c_int = 0;
    var monitorCount: c_int = 0;
    const monitors = glfwGetMonitors(&monitorCount);
    if ((monitor >= 0) and (monitor < monitorCount)) glfwGetMonitorPhysicalSize(monitors.?[@intCast(monitor)], &width, null) else TraceLog(LOG_WARNING, "GLFW: Failed to find selected monitor");
    return width;
}

export fn GetMonitorPhysicalHeight(monitor: c_int) callconv(.c) c_int {
    var height: c_int = 0;
    var monitorCount: c_int = 0;
    const monitors = glfwGetMonitors(&monitorCount);
    if ((monitor >= 0) and (monitor < monitorCount)) glfwGetMonitorPhysicalSize(monitors.?[@intCast(monitor)], null, &height) else TraceLog(LOG_WARNING, "GLFW: Failed to find selected monitor");
    return height;
}

export fn GetMonitorRefreshRate(monitor: c_int) callconv(.c) c_int {
    var refresh: c_int = 0;
    var monitorCount: c_int = 0;
    const monitors = glfwGetMonitors(&monitorCount);
    if ((monitor >= 0) and (monitor < monitorCount)) {
        const mode = glfwGetVideoMode(monitors.?[@intCast(monitor)]);
        if (mode != null) refresh = mode.?.refreshRate else TraceLog(LOG_WARNING, "GLFW: Failed to find video mode for selected monitor");
    } else TraceLog(LOG_WARNING, "GLFW: Failed to find selected monitor");
    return refresh;
}

export fn GetMonitorName(monitor: c_int) callconv(.c) [*c]const u8 {
    var monitorCount: c_int = 0;
    const monitors = glfwGetMonitors(&monitorCount);
    if ((monitor >= 0) and (monitor < monitorCount)) {
        return glfwGetMonitorName(monitors.?[@intCast(monitor)]);
    } else TraceLog(LOG_WARNING, "GLFW: Failed to find selected monitor");
    return "";
}

export fn GetWindowPosition() callconv(.c) Vector2 {
    return .{ .x = @floatFromInt(CORE.Window.position.x), .y = @floatFromInt(CORE.Window.position.y) };
}

export fn GetWindowScaleDPI() callconv(.c) Vector2 {
    var scale = Vector2{ .x = 1.0, .y = 1.0 };
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI) and !flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE))
        glfwGetWindowContentScale(platform.handle, &scale.x, &scale.y);
    return scale;
}

export fn SetClipboardText(text: [*c]const u8) callconv(.c) void {
    glfwSetClipboardString(platform.handle, text);
}

export fn GetClipboardText() callconv(.c) [*c]const u8 {
    return glfwGetClipboardString(platform.handle);
}

export fn GetClipboardImage() callconv(.c) Image {
    const image = std.mem.zeroes(Image);
    TraceLog(LOG_WARNING, "GetClipboardImage() not implemented on target platform");
    return image;
}

export fn ShowCursor() callconv(.c) void {
    glfwSetInputMode(platform.handle, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    CORE.Input.Mouse.cursorHidden = false;
}

export fn HideCursor() callconv(.c) void {
    glfwSetInputMode(platform.handle, GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
    CORE.Input.Mouse.cursorHidden = true;
}

export fn EnableCursor() callconv(.c) void {
    glfwSetInputMode(platform.handle, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    SetMousePosition(@intCast(CORE.Window.screen.width / 2), @intCast(CORE.Window.screen.height / 2));
    if (glfwRawMouseMotionSupported() != 0) glfwSetInputMode(platform.handle, GLFW_RAW_MOUSE_MOTION, GLFW_FALSE);
    CORE.Input.Mouse.cursorHidden = false;
    CORE.Input.Mouse.cursorLocked = false;
}

export fn DisableCursor() callconv(.c) void {
    SetMousePosition(@intCast(CORE.Window.screen.width / 2), @intCast(CORE.Window.screen.height / 2));
    glfwSetInputMode(platform.handle, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    if (glfwRawMouseMotionSupported() != 0) glfwSetInputMode(platform.handle, GLFW_RAW_MOUSE_MOTION, GLFW_TRUE);
    CORE.Input.Mouse.cursorHidden = true;
    CORE.Input.Mouse.cursorLocked = true;
}

export fn SwapScreenBuffer() callconv(.c) void {
    glfwSwapBuffers(platform.handle);
}

export fn GetTime() callconv(.c) f64 {
    return glfwGetTime();
}

export fn OpenURL(url: [*c]const u8) callconv(.c) void {
    if (strchr(url, '\'') != null) {
        TraceLog(LOG_WARNING, "SYSTEM: Provided URL could be potentially malicious, avoid ['] character");
    } else {
        const cmd: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(strlen(url) + 32, 1)));
        _ = sprintf(cmd, "xdg-open '%s'", url);
        const result = system(cmd);
        if (result == -1) TraceLog(LOG_WARNING, "OpenURL() child process could not be created");
        RL_FREE(cmd);
    }
}

//----------------------------------------------------------------------------------
// Inputs (platform)
//----------------------------------------------------------------------------------

export fn SetGamepadMappings(mappings: [*c]const u8) callconv(.c) c_int {
    return glfwUpdateGamepadMappings(mappings);
}

export fn SetGamepadVibration(gamepad: c_int, leftMotor: f32, rightMotor: f32, duration: f32) callconv(.c) void {
    _ = gamepad;
    _ = leftMotor;
    _ = rightMotor;
    _ = duration;
    TraceLog(LOG_WARNING, "SetGamepadVibration() not available on target platform");
}

export fn SetMousePosition(x: c_int, y: c_int) callconv(.c) void {
    CORE.Input.Mouse.currentPosition = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
    CORE.Input.Mouse.previousPosition = CORE.Input.Mouse.currentPosition;
    glfwSetCursorPos(platform.handle, CORE.Input.Mouse.currentPosition.x, CORE.Input.Mouse.currentPosition.y);
}

export fn SetMouseCursor(cursor: c_int) callconv(.c) void {
    CORE.Input.Mouse.cursor = cursor;
    if (cursor == MOUSE_CURSOR_DEFAULT) {
        glfwSetCursor(platform.handle, null);
    } else {
        glfwSetCursor(platform.handle, glfwCreateStandardCursor(0x00036000 + cursor));
    }
}

export fn GetKeyName(key: c_int) callconv(.c) [*c]const u8 {
    return glfwGetKeyName(key, glfwGetKeyScancode(key));
}

export fn PollInputEvents() callconv(.c) void {
    UpdateGestures();

    CORE.Input.Keyboard.keyPressedQueueCount = 0;
    CORE.Input.Keyboard.charPressedQueueCount = 0;

    CORE.Input.Gamepad.lastButtonPressed = GAMEPAD_BUTTON_UNKNOWN;

    var i: usize = 0;
    while (i < MAX_KEYBOARD_KEYS) : (i += 1) {
        CORE.Input.Keyboard.previousKeyState[i] = CORE.Input.Keyboard.currentKeyState[i];
        CORE.Input.Keyboard.keyRepeatInFrame[i] = 0;
    }

    i = 0;
    while (i < MAX_MOUSE_BUTTONS) : (i += 1) CORE.Input.Mouse.previousButtonState[i] = CORE.Input.Mouse.currentButtonState[i];

    CORE.Input.Mouse.previousWheelMove = CORE.Input.Mouse.currentWheelMove;
    CORE.Input.Mouse.currentWheelMove = .{ .x = 0.0, .y = 0.0 };

    CORE.Input.Mouse.previousPosition = CORE.Input.Mouse.currentPosition;

    i = 0;
    while (i < MAX_TOUCH_POINTS) : (i += 1) CORE.Input.Touch.previousTouchState[i] = CORE.Input.Touch.currentTouchState[i];

    CORE.Input.Touch.position[0] = CORE.Input.Mouse.currentPosition;

    var g: c_int = 0;
    while (g < MAX_GAMEPADS) : (g += 1) {
        if (glfwJoystickPresent(g) != 0) CORE.Input.Gamepad.ready[@intCast(g)] = true else CORE.Input.Gamepad.ready[@intCast(g)] = false;
    }

    g = 0;
    while (g < MAX_GAMEPADS) : (g += 1) {
        if (CORE.Input.Gamepad.ready[@intCast(g)]) {
            var k: usize = 0;
            while (k < MAX_GAMEPAD_BUTTONS) : (k += 1) CORE.Input.Gamepad.previousButtonState[@intCast(g)][k] = CORE.Input.Gamepad.currentButtonState[@intCast(g)][k];

            var state = std.mem.zeroes(GLFWgamepadstate);
            const result = glfwGetGamepadState(g, &state);
            if (result == GLFW_FALSE) {
                state.axes[@intCast(GAMEPAD_AXIS_LEFT_TRIGGER)] = -1.0;
                state.axes[@intCast(GAMEPAD_AXIS_RIGHT_TRIGGER)] = -1.0;
            }

            var kk: c_int = 0;
            while (kk < MAX_GAMEPAD_BUTTONS) : (kk += 1) {
                var btn: c_int = -1;
                if (kk < 15) {
                    btn = switch (kk) {
                        GLFW_GAMEPAD_BUTTON_Y => GAMEPAD_BUTTON_RIGHT_FACE_UP,
                        GLFW_GAMEPAD_BUTTON_B => GAMEPAD_BUTTON_RIGHT_FACE_RIGHT,
                        GLFW_GAMEPAD_BUTTON_A => GAMEPAD_BUTTON_RIGHT_FACE_DOWN,
                        GLFW_GAMEPAD_BUTTON_X => GAMEPAD_BUTTON_RIGHT_FACE_LEFT,
                        GLFW_GAMEPAD_BUTTON_LEFT_BUMPER => GAMEPAD_BUTTON_LEFT_TRIGGER_1,
                        GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER => GAMEPAD_BUTTON_RIGHT_TRIGGER_1,
                        GLFW_GAMEPAD_BUTTON_BACK => GAMEPAD_BUTTON_MIDDLE_LEFT,
                        GLFW_GAMEPAD_BUTTON_GUIDE => GAMEPAD_BUTTON_MIDDLE,
                        GLFW_GAMEPAD_BUTTON_START => GAMEPAD_BUTTON_MIDDLE_RIGHT,
                        GLFW_GAMEPAD_BUTTON_DPAD_UP => GAMEPAD_BUTTON_LEFT_FACE_UP,
                        GLFW_GAMEPAD_BUTTON_DPAD_RIGHT => GAMEPAD_BUTTON_LEFT_FACE_RIGHT,
                        GLFW_GAMEPAD_BUTTON_DPAD_DOWN => GAMEPAD_BUTTON_LEFT_FACE_DOWN,
                        GLFW_GAMEPAD_BUTTON_DPAD_LEFT => GAMEPAD_BUTTON_LEFT_FACE_LEFT,
                        GLFW_GAMEPAD_BUTTON_LEFT_THUMB => GAMEPAD_BUTTON_LEFT_THUMB,
                        GLFW_GAMEPAD_BUTTON_RIGHT_THUMB => GAMEPAD_BUTTON_RIGHT_THUMB,
                        else => -1,
                    };
                }

                if (btn != -1) {
                    if (state.buttons[@intCast(kk)] == GLFW_PRESS) {
                        CORE.Input.Gamepad.currentButtonState[@intCast(g)][@intCast(btn)] = 1;
                        CORE.Input.Gamepad.lastButtonPressed = btn;
                    } else CORE.Input.Gamepad.currentButtonState[@intCast(g)][@intCast(btn)] = 0;
                }
            }

            var ax: c_int = 0;
            while (ax < (GLFW_GAMEPAD_AXIS_LAST + 1)) : (ax += 1) {
                CORE.Input.Gamepad.axisState[@intCast(g)][@intCast(ax)] = state.axes[@intCast(ax)];
            }

            if (CORE.Input.Gamepad.axisState[@intCast(g)][@intCast(GAMEPAD_AXIS_LEFT_TRIGGER)] > 0.1) {
                CORE.Input.Gamepad.currentButtonState[@intCast(g)][@intCast(GAMEPAD_BUTTON_LEFT_TRIGGER_2)] = 1;
                CORE.Input.Gamepad.lastButtonPressed = GAMEPAD_BUTTON_LEFT_TRIGGER_2;
            } else CORE.Input.Gamepad.currentButtonState[@intCast(g)][@intCast(GAMEPAD_BUTTON_LEFT_TRIGGER_2)] = 0;

            if (CORE.Input.Gamepad.axisState[@intCast(g)][@intCast(GAMEPAD_AXIS_RIGHT_TRIGGER)] > 0.1) {
                CORE.Input.Gamepad.currentButtonState[@intCast(g)][@intCast(GAMEPAD_BUTTON_RIGHT_TRIGGER_2)] = 1;
                CORE.Input.Gamepad.lastButtonPressed = GAMEPAD_BUTTON_RIGHT_TRIGGER_2;
            } else CORE.Input.Gamepad.currentButtonState[@intCast(g)][@intCast(GAMEPAD_BUTTON_RIGHT_TRIGGER_2)] = 0;

            CORE.Input.Gamepad.axisCount[@intCast(g)] = GLFW_GAMEPAD_AXIS_LAST + 1;
        }
    }

    CORE.Window.resizedLastFrame = false;

    if (CORE.Window.eventWaiting or (flagIsSet(CORE.Window.flags, FLAG_WINDOW_MINIMIZED) and !flagIsSet(CORE.Window.flags, FLAG_WINDOW_ALWAYS_RUN))) {
        glfwWaitEvents();
        CORE.Time.previous = GetTime();
    } else glfwPollEvents();

    CORE.Window.shouldClose = (glfwWindowShouldClose(platform.handle) != 0);

    glfwSetWindowShouldClose(platform.handle, GLFW_FALSE);
}

//----------------------------------------------------------------------------------
// GLFW callbacks
//----------------------------------------------------------------------------------

fn ErrorCallback(error_code: c_int, description: [*c]const u8) callconv(.c) void {
    TraceLog(LOG_WARNING, "GLFW: Error: %i Description: %s", error_code, description);
}

fn WindowSizeCallback(window: ?*GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    _ = window;
    _ = width;
    _ = height;
}

fn FramebufferSizeCallback(window: ?*GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    _ = window;
    if ((width == 0) or (height == 0)) return;

    SetupViewport(width, height);

    CORE.Window.render.width = @intCast(width);
    CORE.Window.render.height = @intCast(height);
    CORE.Window.currentFbo = CORE.Window.render;
    CORE.Window.resizedLastFrame = true;

    if (flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE)) {
        CORE.Window.screen.width = @intCast(width);
        CORE.Window.screen.height = @intCast(height);
        CORE.Window.screenScale = MatrixScale(1.0, 1.0, 1.0);
        SetMouseScale(1.0, 1.0);
    } else {
        if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) {
            const scaleDpi = GetWindowScaleDPI();
            CORE.Window.screen.width = @intFromFloat(@as(f32, @floatFromInt(width)) / scaleDpi.x);
            CORE.Window.screen.height = @intFromFloat(@as(f32, @floatFromInt(height)) / scaleDpi.y);
            CORE.Window.screenScale = MatrixScale(scaleDpi.x, scaleDpi.y, 1.0);
            SetMouseScale(1.0 / scaleDpi.x, 1.0 / scaleDpi.y);
        } else {
            CORE.Window.screen.width = @intCast(width);
            CORE.Window.screen.height = @intCast(height);
        }
    }
}

fn WindowContentScaleCallback(window: ?*GLFWwindow, scalex: f32, scaley: f32) callconv(.c) void {
    _ = window;
    CORE.Window.render.width = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.screen.width)) * scalex);
    CORE.Window.render.height = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.screen.height)) * scaley);
    CORE.Window.currentFbo = CORE.Window.render;
    CORE.Window.screenScale = MatrixScale(scalex, scaley, 1.0);
    SetMouseScale(1.0 / scalex, 1.0 / scaley);
}

fn WindowPosCallback(window: ?*GLFWwindow, x: c_int, y: c_int) callconv(.c) void {
    _ = window;
    CORE.Window.position.x = x;
    CORE.Window.position.y = y;
}

fn WindowIconifyCallback(window: ?*GLFWwindow, iconified: c_int) callconv(.c) void {
    _ = window;
    if (iconified != 0) flagSet(&CORE.Window.flags, FLAG_WINDOW_MINIMIZED) else flagClear(&CORE.Window.flags, FLAG_WINDOW_MINIMIZED);
}

fn WindowMaximizeCallback(window: ?*GLFWwindow, maximized: c_int) callconv(.c) void {
    _ = window;
    if (maximized != 0) flagSet(&CORE.Window.flags, FLAG_WINDOW_MAXIMIZED) else flagClear(&CORE.Window.flags, FLAG_WINDOW_MAXIMIZED);
}

fn WindowFocusCallback(window: ?*GLFWwindow, focused: c_int) callconv(.c) void {
    _ = window;
    if (focused != 0) flagClear(&CORE.Window.flags, FLAG_WINDOW_UNFOCUSED) else flagSet(&CORE.Window.flags, FLAG_WINDOW_UNFOCUSED);
}

fn WindowDropCallback(window: ?*GLFWwindow, count: c_int, paths: [*c][*c]const u8) callconv(.c) void {
    _ = window;
    if (count > 0) {
        if (CORE.Window.dropFileCount > 0) {
            var i: c_uint = 0;
            while (i < CORE.Window.dropFileCount) : (i += 1) RL_FREE(CORE.Window.dropFilepaths[i]);
            RL_FREE(CORE.Window.dropFilepaths);
            CORE.Window.dropFileCount = 0;
            CORE.Window.dropFilepaths = null;
        }

        CORE.Window.dropFileCount = @intCast(count);
        CORE.Window.dropFilepaths = @ptrCast(@alignCast(RL_CALLOC(CORE.Window.dropFileCount, @sizeOf([*c]u8))));

        var i: c_uint = 0;
        while (i < CORE.Window.dropFileCount) : (i += 1) {
            CORE.Window.dropFilepaths[i] = @ptrCast(@alignCast(RL_CALLOC(MAX_FILEPATH_LENGTH, 1)));
            _ = strncpy(CORE.Window.dropFilepaths[i], paths[i], MAX_FILEPATH_LENGTH - 1);
        }
    }
}

fn KeyCallback(window: ?*GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = window;
    _ = scancode;
    if (key < 0) return;

    if (action == GLFW_RELEASE) CORE.Input.Keyboard.currentKeyState[@intCast(key)] = 0 else if (action == GLFW_PRESS) CORE.Input.Keyboard.currentKeyState[@intCast(key)] = 1 else if (action == GLFW_REPEAT) CORE.Input.Keyboard.keyRepeatInFrame[@intCast(key)] = 1;

    if (((key == KEY_CAPS_LOCK) and flagIsSet(@intCast(mods), @intCast(GLFW_MOD_CAPS_LOCK))) or
        ((key == KEY_NUM_LOCK) and flagIsSet(@intCast(mods), @intCast(GLFW_MOD_NUM_LOCK)))) CORE.Input.Keyboard.currentKeyState[@intCast(key)] = 1;

    if ((CORE.Input.Keyboard.keyPressedQueueCount < MAX_KEY_PRESSED_QUEUE) and (action == GLFW_PRESS)) {
        CORE.Input.Keyboard.keyPressedQueue[@intCast(CORE.Input.Keyboard.keyPressedQueueCount)] = key;
        CORE.Input.Keyboard.keyPressedQueueCount += 1;
    }

    if ((key == CORE.Input.Keyboard.exitKey) and (action == GLFW_PRESS)) glfwSetWindowShouldClose(platform.handle, GLFW_TRUE);
}

fn CharCallback(window: ?*GLFWwindow, codepoint: c_uint) callconv(.c) void {
    _ = window;
    if (CORE.Input.Keyboard.charPressedQueueCount < MAX_CHAR_PRESSED_QUEUE) {
        CORE.Input.Keyboard.charPressedQueue[@intCast(CORE.Input.Keyboard.charPressedQueueCount)] = @intCast(codepoint);
        CORE.Input.Keyboard.charPressedQueueCount += 1;
    }
}

fn MouseButtonCallback(window: ?*GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = window;
    _ = mods;
    CORE.Input.Mouse.currentButtonState[@intCast(button)] = @intCast(action);
    CORE.Input.Touch.currentTouchState[@intCast(button)] = @intCast(action);
}

fn MouseCursorPosCallback(window: ?*GLFWwindow, x: f64, y: f64) callconv(.c) void {
    _ = window;
    CORE.Input.Mouse.currentPosition.x = @floatCast(x);
    CORE.Input.Mouse.currentPosition.y = @floatCast(y);
    CORE.Input.Touch.position[0] = CORE.Input.Mouse.currentPosition;
}

fn MouseScrollCallback(window: ?*GLFWwindow, xoffset: f64, yoffset: f64) callconv(.c) void {
    _ = window;
    CORE.Input.Mouse.currentWheelMove = .{ .x = @floatCast(xoffset), .y = @floatCast(yoffset) };
}

fn CursorEnterCallback(window: ?*GLFWwindow, enter: c_int) callconv(.c) void {
    _ = window;
    if (enter != 0) CORE.Input.Mouse.cursorOnScreen = true else CORE.Input.Mouse.cursorOnScreen = false;
}

fn JoystickCallback(jid: c_int, event: c_int) callconv(.c) void {
    if (jid < MAX_GAMEPADS) {
        if (event == GLFW_CONNECTED) {
            _ = memset(@ptrCast(&CORE.Input.Gamepad.name[@intCast(jid)]), 0, MAX_GAMEPAD_NAME_LENGTH);
            _ = strncpy(&CORE.Input.Gamepad.name[@intCast(jid)], glfwGetJoystickName(jid), MAX_GAMEPAD_NAME_LENGTH - 1);
        } else if (event == GLFW_DISCONNECTED) {
            _ = memset(@ptrCast(&CORE.Input.Gamepad.name[@intCast(jid)]), 0, MAX_GAMEPAD_NAME_LENGTH);
        }
    }
}

//----------------------------------------------------------------------------------
// GLFW allocator wrappers
//----------------------------------------------------------------------------------

fn AllocateWrapper(size: usize, user: ?*anyopaque) callconv(.c) ?*anyopaque {
    _ = user;
    return RL_CALLOC(size, 1);
}
fn ReallocateWrapper(block: ?*anyopaque, size: usize, user: ?*anyopaque) callconv(.c) ?*anyopaque {
    _ = user;
    return RL_REALLOC(block, size);
}
fn DeallocateWrapper(block: ?*anyopaque, user: ?*anyopaque) callconv(.c) void {
    _ = user;
    RL_FREE(block);
}

//----------------------------------------------------------------------------------
// Initialize platform: graphics, inputs and more
//----------------------------------------------------------------------------------

export fn InitPlatform() callconv(.c) c_int {
    _ = glfwSetErrorCallback(ErrorCallback);

    const allocator = GLFWallocator{
        .allocate = AllocateWrapper,
        .reallocate = ReallocateWrapper,
        .deallocate = DeallocateWrapper,
        .user = null,
    };
    glfwInitAllocator(&allocator);

    var result = glfwInit();
    if (result == GLFW_FALSE) {
        TraceLog(LOG_WARNING, "GLFW: Failed to initialize GLFW");
        return -1;
    }

    glfwDefaultWindowHints();
    glfwWindowHint(GLFW_AUTO_ICONIFY, 0);

    const requestedWindowFlags = CORE.Window.flags;

    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIDDEN)) glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE) else glfwWindowHint(GLFW_VISIBLE, GLFW_TRUE);
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_UNDECORATED)) glfwWindowHint(GLFW_DECORATED, GLFW_FALSE) else glfwWindowHint(GLFW_DECORATED, GLFW_TRUE);
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_RESIZABLE)) glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE) else glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);

    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_MINIMIZED)) flagClear(&CORE.Window.flags, FLAG_WINDOW_MINIMIZED);
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_MAXIMIZED)) flagClear(&CORE.Window.flags, FLAG_WINDOW_MAXIMIZED);

    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_UNFOCUSED)) glfwWindowHint(GLFW_FOCUSED, GLFW_FALSE) else glfwWindowHint(GLFW_FOCUSED, GLFW_TRUE);
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_TOPMOST)) glfwWindowHint(GLFW_FLOATING, GLFW_TRUE) else glfwWindowHint(GLFW_FLOATING, GLFW_FALSE);
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_TRANSPARENT)) glfwWindowHint(GLFW_TRANSPARENT_FRAMEBUFFER, GLFW_TRUE) else glfwWindowHint(GLFW_TRANSPARENT_FRAMEBUFFER, GLFW_FALSE);

    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) {
        glfwWindowHint(GLFW_SCALE_TO_MONITOR, GLFW_TRUE);
    } else {
        glfwWindowHint(GLFW_SCALE_TO_MONITOR, GLFW_FALSE);
    }

    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_MOUSE_PASSTHROUGH)) glfwWindowHint(GLFW_MOUSE_PASSTHROUGH, GLFW_TRUE) else glfwWindowHint(GLFW_MOUSE_PASSTHROUGH, GLFW_FALSE);

    if (flagIsSet(CORE.Window.flags, FLAG_MSAA_4X_HINT)) {
        TraceLog(LOG_INFO, "DISPLAY: Trying to enable MSAA x4");
        glfwWindowHint(GLFW_SAMPLES, 4);
    }

    if (rlGetVersion() == RL_OPENGL_21) {
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
    } else if (rlGetVersion() == RL_OPENGL_33) {
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_FALSE);
    } else if (rlGetVersion() == RL_OPENGL_43) {
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_FALSE);
    } else if (rlGetVersion() == RL_OPENGL_ES_20) {
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
        glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
        glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_EGL_CONTEXT_API);
    } else if (rlGetVersion() == RL_OPENGL_ES_30) {
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
        glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
        glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_EGL_CONTEXT_API);
    }

    _ = glfwSetJoystickCallback(null);

    if ((CORE.Window.screen.width == 0) or (CORE.Window.screen.height == 0)) flagSet(&CORE.Window.flags, FLAG_FULLSCREEN_MODE);

    if (flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE)) {
        const monitor = glfwGetPrimaryMonitor();
        if (monitor == null) {
            TraceLog(LOG_WARNING, "GLFW: Failed to get primary monitor");
            return -1;
        }

        const mode = glfwGetVideoMode(monitor).?;
        CORE.Window.display.width = @intCast(mode.width);
        CORE.Window.display.height = @intCast(mode.height);

        if ((CORE.Window.screen.width == 0) or (CORE.Window.screen.height == 0)) {
            CORE.Window.previousScreen.width = 800;
            CORE.Window.previousScreen.height = 450;
            CORE.Window.previousPosition.x = @divTrunc(@as(c_int, @intCast(CORE.Window.display.width)), 2) - 400;
            CORE.Window.previousPosition.y = @divTrunc(@as(c_int, @intCast(CORE.Window.display.height)), 2) - 225;

            if (CORE.Window.screen.width == 0) CORE.Window.screen.width = CORE.Window.display.width;
            if (CORE.Window.screen.height == 0) CORE.Window.screen.height = CORE.Window.display.height;
        } else {
            CORE.Window.previousScreen = CORE.Window.screen;
            CORE.Window.screen = CORE.Window.display;
        }

        platform.handle = glfwCreateWindow(@intCast(CORE.Window.screen.width), @intCast(CORE.Window.screen.height), if (CORE.Window.title != null) CORE.Window.title else " ", monitor, null);
        if (platform.handle == null) {
            glfwTerminate();
            TraceLog(LOG_WARNING, "GLFW: Failed to initialize Window");
            return -1;
        }
    } else {
        if (CORE.Window.screen.width == 0) CORE.Window.screen.width = 1;
        if (CORE.Window.screen.height == 0) CORE.Window.screen.height = 1;

        platform.handle = glfwCreateWindow(@intCast(CORE.Window.screen.width), @intCast(CORE.Window.screen.height), if (CORE.Window.title != null) CORE.Window.title else " ", null, null);
        if (platform.handle == null) {
            glfwTerminate();
            TraceLog(LOG_WARNING, "GLFW: Failed to initialize Window");
            return -1;
        }

        var monitorCount: c_int = 0;
        const monitorIndex = GetCurrentMonitor();
        const monitors = glfwGetMonitors(&monitorCount);

        if (monitorIndex < monitorCount) {
            const monitor = monitors.?[@intCast(monitorIndex)];
            const mode = glfwGetVideoMode(monitor).?;

            CORE.Window.display.width = @intCast(mode.width);
            CORE.Window.display.height = @intCast(mode.height);

            if (CORE.Window.screen.width == 0) CORE.Window.screen.width = CORE.Window.display.width;
            if (CORE.Window.screen.height == 0) CORE.Window.screen.height = CORE.Window.display.height;

            glfwSetWindowSize(platform.handle, @intCast(CORE.Window.screen.width), @intCast(CORE.Window.screen.height));
        } else {
            glfwTerminate();
            TraceLog(LOG_WARNING, "GLFW: Failed to determine Monitor to center Window");
            return -1;
        }

        CORE.Window.render.width = CORE.Window.screen.width;
        CORE.Window.render.height = CORE.Window.screen.height;
    }

    glfwMakeContextCurrent(platform.handle);
    result = glfwGetError(null);
    if ((result != GLFW_NO_WINDOW_CONTEXT) and (result != GLFW_PLATFORM_ERROR)) CORE.Window.ready = true;

    if (CORE.Window.ready) {
        glfwSwapInterval(0);

        if (flagIsSet(CORE.Window.flags, FLAG_VSYNC_HINT)) {
            glfwSwapInterval(1);
            TraceLog(LOG_INFO, "DISPLAY: Trying to enable VSYNC");
        }

        if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) {
            const scaleDpi = GetWindowScaleDPI();
            CORE.Window.render.width = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.screen.width)) * scaleDpi.x);
            CORE.Window.render.height = @intFromFloat(@as(f32, @floatFromInt(CORE.Window.screen.height)) * scaleDpi.y);

            CORE.Window.screenScale = MatrixScale(scaleDpi.x, scaleDpi.y, 1.0);

            if (glfwGetPlatform() == GLFW_PLATFORM_WAYLAND) {
                var fbWidth: c_int = 0;
                var fbHeight: c_int = 0;
                glfwGetFramebufferSize(platform.handle, &fbWidth, &fbHeight);
                CORE.Window.render.width = @intCast(fbWidth);
                CORE.Window.render.height = @intCast(fbHeight);
            } else {
                SetMouseScale(1.0 / scaleDpi.x, 1.0 / scaleDpi.y);
                glfwSetWindowSize(platform.handle, @intCast(CORE.Window.render.width), @intCast(CORE.Window.render.height));
            }
        } else CORE.Window.render = CORE.Window.screen;

        CORE.Window.currentFbo = CORE.Window.render;

        const hidpiStr: [*c]const u8 = if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) "(HighDPI)" else "";
        TraceLog(LOG_INFO, "DISPLAY: Device initialized successfully %s", hidpiStr);
        TraceLog(LOG_INFO, "    > Display size: %i x %i", @as(c_int, @intCast(CORE.Window.display.width)), @as(c_int, @intCast(CORE.Window.display.height)));
        TraceLog(LOG_INFO, "    > Screen size:  %i x %i", @as(c_int, @intCast(CORE.Window.screen.width)), @as(c_int, @intCast(CORE.Window.screen.height)));
        TraceLog(LOG_INFO, "    > Render size:  %i x %i", @as(c_int, @intCast(CORE.Window.render.width)), @as(c_int, @intCast(CORE.Window.render.height)));
        TraceLog(LOG_INFO, "    > Viewport offsets: %i, %i", CORE.Window.renderOffset.x, CORE.Window.renderOffset.y);

        var monitorCount: c_int = 0;
        const monitorIndex = GetCurrentMonitor();
        const monitors = glfwGetMonitors(&monitorCount);
        const monitor = monitors.?[@intCast(monitorIndex)];

        var monitorX: c_int = 0;
        var monitorY: c_int = 0;
        var monitorWidth: c_int = 0;
        var monitorHeight: c_int = 0;
        glfwGetMonitorWorkarea(monitor, &monitorX, &monitorY, &monitorWidth, &monitorHeight);

        CORE.Window.position.x = monitorX + @divTrunc(monitorWidth - @as(c_int, @intCast(CORE.Window.render.width)), 2);
        CORE.Window.position.y = monitorY + @divTrunc(monitorHeight - @as(c_int, @intCast(CORE.Window.render.height)), 2);
        SetWindowPosition(CORE.Window.position.x, CORE.Window.position.y);

        if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_MINIMIZED)) MinimizeWindow();
    } else {
        TraceLog(LOG_FATAL, "PLATFORM: Failed to initialize graphics device");
        return -1;
    }

    SetWindowState(requestedWindowFlags);

    rlLoadExtensions(@ptrCast(@constCast(&glfwGetProcAddress)));

    _ = glfwSetWindowSizeCallback(platform.handle, WindowSizeCallback);
    _ = glfwSetFramebufferSizeCallback(platform.handle, FramebufferSizeCallback);
    _ = glfwSetWindowPosCallback(platform.handle, WindowPosCallback);
    _ = glfwSetWindowMaximizeCallback(platform.handle, WindowMaximizeCallback);
    _ = glfwSetWindowIconifyCallback(platform.handle, WindowIconifyCallback);
    _ = glfwSetWindowFocusCallback(platform.handle, WindowFocusCallback);
    _ = glfwSetDropCallback(platform.handle, WindowDropCallback);
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) _ = glfwSetWindowContentScaleCallback(platform.handle, WindowContentScaleCallback);

    _ = glfwSetKeyCallback(platform.handle, KeyCallback);
    _ = glfwSetCharCallback(platform.handle, CharCallback);
    _ = glfwSetMouseButtonCallback(platform.handle, MouseButtonCallback);
    _ = glfwSetCursorPosCallback(platform.handle, MouseCursorPosCallback);
    _ = glfwSetScrollCallback(platform.handle, MouseScrollCallback);
    _ = glfwSetCursorEnterCallback(platform.handle, CursorEnterCallback);
    _ = glfwSetJoystickCallback(JoystickCallback);
    glfwSetInputMode(platform.handle, GLFW_LOCK_KEY_MODS, GLFW_TRUE);

    var i: c_int = 0;
    while (i < MAX_GAMEPADS) : (i += 1) {
        if (glfwJoystickPresent(i) != 0) {
            CORE.Input.Gamepad.ready[@intCast(i)] = true;
            CORE.Input.Gamepad.axisCount[@intCast(i)] = GLFW_GAMEPAD_AXIS_LAST + 1;
            _ = strncpy(&CORE.Input.Gamepad.name[@intCast(i)], glfwGetJoystickName(i), MAX_GAMEPAD_NAME_LENGTH - 1);
        }
    }

    InitTimer();

    CORE.Storage.basePath = GetWorkingDirectory();

    var glfwPlatform: [*c]const u8 = "";
    switch (glfwGetPlatform()) {
        GLFW_PLATFORM_WIN32 => glfwPlatform = "Win32",
        GLFW_PLATFORM_COCOA => glfwPlatform = "Cocoa",
        GLFW_PLATFORM_WAYLAND => glfwPlatform = "Wayland",
        GLFW_PLATFORM_X11 => glfwPlatform = "X11",
        GLFW_PLATFORM_NULL => glfwPlatform = "Null",
        else => {},
    }

    TraceLog(LOG_INFO, "PLATFORM: DESKTOP (GLFW - %s): Initialized successfully", glfwPlatform);

    return 0;
}

export fn ClosePlatform() callconv(.c) void {
    glfwDestroyWindow(platform.handle);
    glfwTerminate();
}
