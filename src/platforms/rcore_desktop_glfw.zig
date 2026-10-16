//! rcore_desktop_glfw - rcore's platform backend for desktops, on GLFW.
//!
//! Zig port of raylib's `platforms/rcore_desktop_glfw.c` (PLATFORM_DESKTOP_GLFW).
//! In C, rcore.c `#include`s exactly one platform file, so the two share one
//! translation unit. Here src/rcore.zig imports one backend at comptime (see
//! `backend` there) and the backend imports rcore back for `CORE` and the helpers
//! both halves use. GLFW itself stays C (vendored, linked).

const std = @import("std");
const rcore = @import("../rcore.zig");

/// Shown in InitWindow's "Platform backend:" log line.
pub const backend_name = "DESKTOP (GLFW)";

//----------------------------------------------------------------------------------
// rcore internals used by this backend
//----------------------------------------------------------------------------------
const CORE = &rcore.CORE;
const FLAG_BORDERLESS_WINDOWED_MODE = rcore.FLAG_BORDERLESS_WINDOWED_MODE;
const FLAG_FULLSCREEN_MODE = rcore.FLAG_FULLSCREEN_MODE;
const FLAG_INTERLACED_HINT = rcore.FLAG_INTERLACED_HINT;
const FLAG_MSAA_4X_HINT = rcore.FLAG_MSAA_4X_HINT;
const FLAG_VSYNC_HINT = rcore.FLAG_VSYNC_HINT;
const FLAG_WINDOW_ALWAYS_RUN = rcore.FLAG_WINDOW_ALWAYS_RUN;
const FLAG_WINDOW_HIDDEN = rcore.FLAG_WINDOW_HIDDEN;
const FLAG_WINDOW_HIGHDPI = rcore.FLAG_WINDOW_HIGHDPI;
const FLAG_WINDOW_MAXIMIZED = rcore.FLAG_WINDOW_MAXIMIZED;
const FLAG_WINDOW_MINIMIZED = rcore.FLAG_WINDOW_MINIMIZED;
const FLAG_WINDOW_MOUSE_PASSTHROUGH = rcore.FLAG_WINDOW_MOUSE_PASSTHROUGH;
const FLAG_WINDOW_RESIZABLE = rcore.FLAG_WINDOW_RESIZABLE;
const FLAG_WINDOW_TOPMOST = rcore.FLAG_WINDOW_TOPMOST;
const FLAG_WINDOW_TRANSPARENT = rcore.FLAG_WINDOW_TRANSPARENT;
const FLAG_WINDOW_UNDECORATED = rcore.FLAG_WINDOW_UNDECORATED;
const FLAG_WINDOW_UNFOCUSED = rcore.FLAG_WINDOW_UNFOCUSED;
const GAMEPAD_AXIS_LEFT_TRIGGER = rcore.GAMEPAD_AXIS_LEFT_TRIGGER;
const GAMEPAD_AXIS_RIGHT_TRIGGER = rcore.GAMEPAD_AXIS_RIGHT_TRIGGER;
const GAMEPAD_BUTTON_LEFT_FACE_DOWN = rcore.GAMEPAD_BUTTON_LEFT_FACE_DOWN;
const GAMEPAD_BUTTON_LEFT_FACE_LEFT = rcore.GAMEPAD_BUTTON_LEFT_FACE_LEFT;
const GAMEPAD_BUTTON_LEFT_FACE_RIGHT = rcore.GAMEPAD_BUTTON_LEFT_FACE_RIGHT;
const GAMEPAD_BUTTON_LEFT_FACE_UP = rcore.GAMEPAD_BUTTON_LEFT_FACE_UP;
const GAMEPAD_BUTTON_LEFT_THUMB = rcore.GAMEPAD_BUTTON_LEFT_THUMB;
const GAMEPAD_BUTTON_LEFT_TRIGGER_1 = rcore.GAMEPAD_BUTTON_LEFT_TRIGGER_1;
const GAMEPAD_BUTTON_LEFT_TRIGGER_2 = rcore.GAMEPAD_BUTTON_LEFT_TRIGGER_2;
const GAMEPAD_BUTTON_MIDDLE = rcore.GAMEPAD_BUTTON_MIDDLE;
const GAMEPAD_BUTTON_MIDDLE_LEFT = rcore.GAMEPAD_BUTTON_MIDDLE_LEFT;
const GAMEPAD_BUTTON_MIDDLE_RIGHT = rcore.GAMEPAD_BUTTON_MIDDLE_RIGHT;
const GAMEPAD_BUTTON_RIGHT_FACE_DOWN = rcore.GAMEPAD_BUTTON_RIGHT_FACE_DOWN;
const GAMEPAD_BUTTON_RIGHT_FACE_LEFT = rcore.GAMEPAD_BUTTON_RIGHT_FACE_LEFT;
const GAMEPAD_BUTTON_RIGHT_FACE_RIGHT = rcore.GAMEPAD_BUTTON_RIGHT_FACE_RIGHT;
const GAMEPAD_BUTTON_RIGHT_FACE_UP = rcore.GAMEPAD_BUTTON_RIGHT_FACE_UP;
const GAMEPAD_BUTTON_RIGHT_THUMB = rcore.GAMEPAD_BUTTON_RIGHT_THUMB;
const GAMEPAD_BUTTON_RIGHT_TRIGGER_1 = rcore.GAMEPAD_BUTTON_RIGHT_TRIGGER_1;
const GAMEPAD_BUTTON_RIGHT_TRIGGER_2 = rcore.GAMEPAD_BUTTON_RIGHT_TRIGGER_2;
const GAMEPAD_BUTTON_UNKNOWN = rcore.GAMEPAD_BUTTON_UNKNOWN;
const GetWorkingDirectory = rcore.GetWorkingDirectory;
const Image = rcore.Image;
const InitTimer = rcore.InitTimer;
const IsWindowFullscreen = rcore.IsWindowFullscreen;
const KEY_CAPS_LOCK = rcore.KEY_CAPS_LOCK;
const KEY_NUM_LOCK = rcore.KEY_NUM_LOCK;
const LOG_FATAL = rcore.LOG_FATAL;
const LOG_INFO = rcore.LOG_INFO;
const LOG_WARNING = rcore.LOG_WARNING;
const MAX_CHAR_PRESSED_QUEUE = rcore.MAX_CHAR_PRESSED_QUEUE;
const MAX_FILEPATH_LENGTH = rcore.MAX_FILEPATH_LENGTH;
const MAX_GAMEPADS = rcore.MAX_GAMEPADS;
const MAX_GAMEPAD_BUTTONS = rcore.MAX_GAMEPAD_BUTTONS;
const MAX_GAMEPAD_NAME_LENGTH = rcore.MAX_GAMEPAD_NAME_LENGTH;
const MAX_KEYBOARD_KEYS = rcore.MAX_KEYBOARD_KEYS;
const MAX_KEY_PRESSED_QUEUE = rcore.MAX_KEY_PRESSED_QUEUE;
const MAX_MOUSE_BUTTONS = rcore.MAX_MOUSE_BUTTONS;
const MAX_TOUCH_POINTS = rcore.MAX_TOUCH_POINTS;
const MOUSE_CURSOR_DEFAULT = rcore.MOUSE_CURSOR_DEFAULT;
const MatrixScale = rcore.MatrixScale;
const PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 = rcore.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
const RL_CALLOC = rcore.RL_CALLOC;
const RL_FREE = rcore.RL_FREE;
const RL_OPENGL_21 = rcore.RL_OPENGL_21;
const RL_OPENGL_33 = rcore.RL_OPENGL_33;
const RL_OPENGL_43 = rcore.RL_OPENGL_43;
const RL_OPENGL_ES_20 = rcore.RL_OPENGL_ES_20;
const RL_OPENGL_ES_30 = rcore.RL_OPENGL_ES_30;
const RL_REALLOC = rcore.RL_REALLOC;
const SetMouseScale = rcore.SetMouseScale;
const SetupViewport = rcore.SetupViewport;
const TraceLog = rcore.TraceLog;
const UpdateGestures = rcore.UpdateGestures;
const Vector2 = rcore.Vector2;
const flagClear = rcore.flagClear;
const flagIsSet = rcore.flagIsSet;
const flagSet = rcore.flagSet;
const memset = rcore.memset;
const rlGetVersion = rcore.rlGetVersion;
const rlLoadExtensions = rcore.rlLoadExtensions;
const sprintf = rcore.sprintf;
const strncpy = rcore.strncpy;
const system = rcore.system;

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
// Platform data
const PlatformData = struct {
    handle: ?*GLFWwindow = null,
};
var platform: PlatformData = .{};
//----------------------------------------------------------------------------------
// Module Functions Definition: platform
//----------------------------------------------------------------------------------

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
                // Decorating resizes the window and fires FramebufferSizeCallback(), which
                // overwrites screen size and position: decorate before restoring them
                glfwSetWindowAttrib(platform.handle, GLFW_DECORATED, GLFW_TRUE);
                flagClear(&CORE.Window.flags, FLAG_WINDOW_UNDECORATED);

                CORE.Window.position = CORE.Window.previousPosition;
                CORE.Window.screen = CORE.Window.previousScreen;

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

pub export fn MaximizeWindow() callconv(.c) void {
    if (glfwGetWindowAttrib(platform.handle, GLFW_RESIZABLE) == GLFW_TRUE) {
        glfwMaximizeWindow(platform.handle);
        flagSet(&CORE.Window.flags, FLAG_WINDOW_MAXIMIZED);
    }
}

pub export fn MinimizeWindow() callconv(.c) void {
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

pub export fn SetWindowSize(width: c_int, height: c_int) callconv(.c) void {
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
    glfwGetWindowPos(platform.handle, &CORE.Window.position.x, &CORE.Window.position.y);

    return .{ .x = @floatFromInt(CORE.Window.position.x), .y = @floatFromInt(CORE.Window.position.y) };
}

pub export fn GetWindowScaleDPI() callconv(.c) Vector2 {
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

pub export fn SwapScreenBuffer() callconv(.c) void {
    glfwSwapBuffers(platform.handle);
}

pub export fn GetTime() callconv(.c) f64 {
    return glfwGetTime();
}

export fn OpenURL(url: [*c]const u8) callconv(.c) void {
    const urlText = std.mem.span(url);
    if (std.mem.indexOfAny(u8, urlText, "'\"") != null) {
        TraceLog(LOG_WARNING, "SYSTEM: Provided URL could be potentially malicious, avoid ['\"] characters");
    } else if (!std.mem.startsWith(u8, urlText, "http://") and !std.mem.startsWith(u8, urlText, "https://")) {
        TraceLog(LOG_WARNING, "SYSTEM: Provided URL must start with 'http://' or 'https://' protocols");
    } else {
        const cmd: [*c]u8 = @ptrCast(@alignCast(RL_CALLOC(urlText.len + 16, 1)));
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

pub export fn PollInputEvents() callconv(.c) void {
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
    if ((key < 0) or (key >= MAX_KEYBOARD_KEYS)) return; // macOS fn key generates -1

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

pub export fn InitPlatform() callconv(.c) c_int {
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

    // NOTE: Fullscreen applications default to the primary monitor
    const monitor = glfwGetPrimaryMonitor();
    if (monitor == null) {
        TraceLog(LOG_WARNING, "GLFW: Failed to get primary monitor");
        return -1;
    }

    if (flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE)) {
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

        // GLFW won't show a non-fullscreen window larger than the monitor work area
        // (screen minus taskbar/docks), so clamp the requested size to it.
        // C compares unsigned against (unsigned int)work size: replicate the bitcast.
        var workX: c_int = 0;
        var workY: c_int = 0;
        var workWidth: c_int = 0;
        var workHeight: c_int = 0;
        glfwGetMonitorWorkarea(monitor, &workX, &workY, &workWidth, &workHeight);
        CORE.Window.screen.width = @min(CORE.Window.screen.width, @as(c_uint, @bitCast(workWidth)));
        CORE.Window.screen.height = @min(CORE.Window.screen.height, @as(c_uint, @bitCast(workHeight)));

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
            const current = monitors.?[@intCast(monitorIndex)];
            const mode = glfwGetVideoMode(current).?;

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
        const current = monitors.?[@intCast(monitorIndex)];

        var monitorX: c_int = 0;
        var monitorY: c_int = 0;
        var monitorWidth: c_int = 0;
        var monitorHeight: c_int = 0;
        glfwGetMonitorWorkarea(current, &monitorX, &monitorY, &monitorWidth, &monitorHeight);

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

pub export fn ClosePlatform() callconv(.c) void {
    glfwDestroyWindow(platform.handle);
    glfwTerminate();
}
