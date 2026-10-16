//! rcore_web - rcore's platform backend for the browser (HTML5, WebAssembly).
//!
//! Zig port of raylib's `platforms/rcore_web.c` (PLATFORM_WEB). Like the C file it
//! runs on Emscripten's GLFW (`-sUSE_GLFW=3`) for the canvas, the WebGL context and
//! keyboard/mouse input, and on Emscripten's HTML5 API for everything GLFW does not
//! cover (touch, gamepads, pointer lock, focus, resize). src/rcore.zig imports this
//! file instead of rcore_desktop_glfw.zig when the target OS is Emscripten.
//!
//! rcore_web.c's inline JavaScript (EM_ASM/EM_JS) lives in rcore_web.js next to this
//! file, as Emscripten library functions declared below as `extern fn rlWeb*`. Link
//! with `--js-library src/platforms/rcore_web.js`, and with `-sASYNCIFY`: examples
//! run raylib's usual `while (!WindowShouldClose())` loop, and WindowShouldClose
//! yields to the browser with emscripten_sleep.
//!
//! The HTML5 API's structs and functions come from emsdk's own headers through
//! translate-c (the `emscripten` module, see src/platforms/emscripten.h and build.zig),
//! so their layouts cannot drift from the Emscripten that links the program.

const std = @import("std");
const em = @import("emscripten");
const rcore = @import("../rcore.zig");

/// Shown in InitWindow's "Platform backend:" log line.
pub const backend_name = "WEB (HTML5)";

//----------------------------------------------------------------------------------
// rcore internals used by this backend
//----------------------------------------------------------------------------------
const CORE = &rcore.CORE;
const Image = rcore.Image;
const Vector2 = rcore.Vector2;
const TraceLog = rcore.TraceLog;
const TextFormat = rcore.TextFormat;
const flagIsSet = rcore.flagIsSet;
const flagSet = rcore.flagSet;
const flagClear = rcore.flagClear;
const InitTimer = rcore.InitTimer;
const SetupViewport = rcore.SetupViewport;
const GetWorkingDirectory = rcore.GetWorkingDirectory;
const IsWindowFullscreen = rcore.IsWindowFullscreen;
const GetScreenWidth = rcore.GetScreenWidth;
const GetScreenHeight = rcore.GetScreenHeight;
const GetMousePosition = rcore.GetMousePosition;
const GetMouseX = rcore.GetMouseX;
const GetMouseY = rcore.GetMouseY;
const UpdateGestures = rcore.UpdateGestures;
const MatrixScale = rcore.MatrixScale;
const rlGetVersion = rcore.rlGetVersion;
const rlLoadExtensions = rcore.rlLoadExtensions;
const RL_CALLOC = rcore.RL_CALLOC;
const RL_FREE = rcore.RL_FREE;
const snprintf = rcore.snprintf;
const strchr = rcore.strchr;

const LOG_INFO = rcore.LOG_INFO;
const LOG_WARNING = rcore.LOG_WARNING;

const RL_OPENGL_21 = rcore.RL_OPENGL_21;
const RL_OPENGL_33 = rcore.RL_OPENGL_33;
const RL_OPENGL_43 = rcore.RL_OPENGL_43;
const RL_OPENGL_ES_20 = rcore.RL_OPENGL_ES_20;
const RL_OPENGL_ES_30 = rcore.RL_OPENGL_ES_30;

const FLAG_VSYNC_HINT = rcore.FLAG_VSYNC_HINT;
const FLAG_FULLSCREEN_MODE = rcore.FLAG_FULLSCREEN_MODE;
const FLAG_WINDOW_RESIZABLE = rcore.FLAG_WINDOW_RESIZABLE;
const FLAG_WINDOW_UNDECORATED = rcore.FLAG_WINDOW_UNDECORATED;
const FLAG_WINDOW_HIDDEN = rcore.FLAG_WINDOW_HIDDEN;
const FLAG_WINDOW_MINIMIZED = rcore.FLAG_WINDOW_MINIMIZED;
const FLAG_WINDOW_MAXIMIZED = rcore.FLAG_WINDOW_MAXIMIZED;
const FLAG_WINDOW_UNFOCUSED = rcore.FLAG_WINDOW_UNFOCUSED;
const FLAG_WINDOW_TOPMOST = rcore.FLAG_WINDOW_TOPMOST;
const FLAG_WINDOW_ALWAYS_RUN = rcore.FLAG_WINDOW_ALWAYS_RUN;
const FLAG_WINDOW_TRANSPARENT = rcore.FLAG_WINDOW_TRANSPARENT;
const FLAG_WINDOW_HIGHDPI = rcore.FLAG_WINDOW_HIGHDPI;
const FLAG_WINDOW_MOUSE_PASSTHROUGH = rcore.FLAG_WINDOW_MOUSE_PASSTHROUGH;
const FLAG_BORDERLESS_WINDOWED_MODE = rcore.FLAG_BORDERLESS_WINDOWED_MODE;
const FLAG_MSAA_4X_HINT = rcore.FLAG_MSAA_4X_HINT;
const FLAG_INTERLACED_HINT = rcore.FLAG_INTERLACED_HINT;

const MAX_FILEPATH_LENGTH = rcore.MAX_FILEPATH_LENGTH;
const MAX_KEYBOARD_KEYS = rcore.MAX_KEYBOARD_KEYS;
const MAX_TOUCH_POINTS = rcore.MAX_TOUCH_POINTS;
const MAX_GAMEPADS = rcore.MAX_GAMEPADS;
const MAX_GAMEPAD_AXES = rcore.MAX_GAMEPAD_AXES;
const MAX_GAMEPAD_BUTTONS = rcore.MAX_GAMEPAD_BUTTONS;
const MAX_GAMEPAD_NAME_LENGTH = rcore.MAX_GAMEPAD_NAME_LENGTH;
const MAX_GAMEPAD_VIBRATION_TIME: f32 = 2.0; // Maximum vibration time in seconds (rcore.c)
const MAX_KEY_PRESSED_QUEUE = rcore.MAX_KEY_PRESSED_QUEUE;
const MAX_CHAR_PRESSED_QUEUE = rcore.MAX_CHAR_PRESSED_QUEUE;
const PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 = rcore.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;

const GAMEPAD_BUTTON_UNKNOWN = rcore.GAMEPAD_BUTTON_UNKNOWN;
const GAMEPAD_BUTTON_LEFT_FACE_UP = rcore.GAMEPAD_BUTTON_LEFT_FACE_UP;
const GAMEPAD_BUTTON_LEFT_FACE_RIGHT = rcore.GAMEPAD_BUTTON_LEFT_FACE_RIGHT;
const GAMEPAD_BUTTON_LEFT_FACE_DOWN = rcore.GAMEPAD_BUTTON_LEFT_FACE_DOWN;
const GAMEPAD_BUTTON_LEFT_FACE_LEFT = rcore.GAMEPAD_BUTTON_LEFT_FACE_LEFT;
const GAMEPAD_BUTTON_RIGHT_FACE_UP = rcore.GAMEPAD_BUTTON_RIGHT_FACE_UP;
const GAMEPAD_BUTTON_RIGHT_FACE_RIGHT = rcore.GAMEPAD_BUTTON_RIGHT_FACE_RIGHT;
const GAMEPAD_BUTTON_RIGHT_FACE_DOWN = rcore.GAMEPAD_BUTTON_RIGHT_FACE_DOWN;
const GAMEPAD_BUTTON_RIGHT_FACE_LEFT = rcore.GAMEPAD_BUTTON_RIGHT_FACE_LEFT;
const GAMEPAD_BUTTON_LEFT_TRIGGER_1 = rcore.GAMEPAD_BUTTON_LEFT_TRIGGER_1;
const GAMEPAD_BUTTON_LEFT_TRIGGER_2 = rcore.GAMEPAD_BUTTON_LEFT_TRIGGER_2;
const GAMEPAD_BUTTON_RIGHT_TRIGGER_1 = rcore.GAMEPAD_BUTTON_RIGHT_TRIGGER_1;
const GAMEPAD_BUTTON_RIGHT_TRIGGER_2 = rcore.GAMEPAD_BUTTON_RIGHT_TRIGGER_2;
const GAMEPAD_BUTTON_MIDDLE_LEFT = rcore.GAMEPAD_BUTTON_MIDDLE_LEFT;
const GAMEPAD_BUTTON_MIDDLE_RIGHT = rcore.GAMEPAD_BUTTON_MIDDLE_RIGHT;
const GAMEPAD_BUTTON_LEFT_THUMB = rcore.GAMEPAD_BUTTON_LEFT_THUMB;
const GAMEPAD_BUTTON_RIGHT_THUMB = rcore.GAMEPAD_BUTTON_RIGHT_THUMB;

// rgestures.h (src/rgestures.zig): gesture events from mouse and touch input
const GestureEvent = extern struct {
    touchAction: c_int,
    pointCount: c_int,
    pointId: [MAX_TOUCH_POINTS]c_int,
    position: [MAX_TOUCH_POINTS]Vector2,
};
extern fn ProcessGestureEvent(event: GestureEvent) void;

// rgestures.h TouchAction
const TOUCH_ACTION_UP: c_int = 0;
const TOUCH_ACTION_DOWN: c_int = 1;
const TOUCH_ACTION_MOVE: c_int = 2;
const TOUCH_ACTION_CANCEL: c_int = 3;

// config.h
const SUPPORT_GESTURES_SYSTEM = true;
const SUPPORT_MOUSE_GESTURES = true;

//----------------------------------------------------------------------------------
// GLFW (Emscripten's library_glfw.js): the subset this backend uses
//----------------------------------------------------------------------------------
const GLFWwindow = anyopaque;
const GLFWmonitor = anyopaque;
const GLFWvidmode = extern struct {
    width: c_int,
    height: c_int,
    redBits: c_int,
    greenBits: c_int,
    blueBits: c_int,
    refreshRate: c_int,
};

const GLFW_TRUE: c_int = 1;
const GLFW_FALSE: c_int = 0;
const GLFW_RELEASE: c_int = 0;
const GLFW_PRESS: c_int = 1;
const GLFW_REPEAT: c_int = 2;
const GLFW_FOCUSED: c_int = 0x00020001;
const GLFW_RESIZABLE: c_int = 0x00020003;
const GLFW_VISIBLE: c_int = 0x00020004;
const GLFW_DECORATED: c_int = 0x00020005;
const GLFW_FLOATING: c_int = 0x00020007;
const GLFW_SAMPLES: c_int = 0x0002100D;
const GLFW_CLIENT_API: c_int = 0x00022001;
const GLFW_CONTEXT_VERSION_MAJOR: c_int = 0x00022002;
const GLFW_CONTEXT_VERSION_MINOR: c_int = 0x00022003;
const GLFW_OPENGL_FORWARD_COMPAT: c_int = 0x00022006;
const GLFW_OPENGL_PROFILE: c_int = 0x00022008;
const GLFW_CONTEXT_CREATION_API: c_int = 0x0002200B;
const GLFW_OPENGL_ES_API: c_int = 0x00030002;
const GLFW_OPENGL_CORE_PROFILE: c_int = 0x00032001;
const GLFW_NATIVE_CONTEXT_API: c_int = 0x00036001;

const GLFWerrorfun = ?*const fn (c_int, [*c]const u8) callconv(.c) void;
const GLFWwindowsizefun = ?*const fn (?*GLFWwindow, c_int, c_int) callconv(.c) void;
const GLFWwindowcontentscalefun = ?*const fn (?*GLFWwindow, f32, f32) callconv(.c) void;
const GLFWwindowiconifyfun = ?*const fn (?*GLFWwindow, c_int) callconv(.c) void;
const GLFWwindowfocusfun = ?*const fn (?*GLFWwindow, c_int) callconv(.c) void;
const GLFWdropfun = ?*const fn (?*GLFWwindow, c_int, [*c][*c]const u8) callconv(.c) void;
const GLFWkeyfun = ?*const fn (?*GLFWwindow, c_int, c_int, c_int, c_int) callconv(.c) void;
const GLFWcharfun = ?*const fn (?*GLFWwindow, c_uint) callconv(.c) void;
const GLFWmousebuttonfun = ?*const fn (?*GLFWwindow, c_int, c_int, c_int) callconv(.c) void;
const GLFWcursorposfun = ?*const fn (?*GLFWwindow, f64, f64) callconv(.c) void;
const GLFWscrollfun = ?*const fn (?*GLFWwindow, f64, f64) callconv(.c) void;
const GLFWcursorenterfun = ?*const fn (?*GLFWwindow, c_int) callconv(.c) void;

extern fn glfwInit() c_int;
extern fn glfwTerminate() void;
extern fn glfwSetErrorCallback(GLFWerrorfun) GLFWerrorfun;
extern fn glfwDefaultWindowHints() void;
extern fn glfwWindowHint(c_int, c_int) void;
extern fn glfwCreateWindow(c_int, c_int, [*c]const u8, ?*GLFWmonitor, ?*GLFWwindow) ?*GLFWwindow;
extern fn glfwDestroyWindow(?*GLFWwindow) void;
extern fn glfwMakeContextCurrent(?*GLFWwindow) void;
extern fn glfwSwapBuffers(?*GLFWwindow) void;
extern fn glfwGetTime() f64;
extern fn glfwGetPrimaryMonitor() ?*GLFWmonitor;
extern fn glfwGetVideoModes(?*GLFWmonitor, *c_int) [*c]const GLFWvidmode;
extern fn glfwSetWindowShouldClose(?*GLFWwindow, c_int) void;
extern fn glfwSetWindowSize(?*GLFWwindow, c_int, c_int) void;
extern fn glfwGetWindowAttrib(?*GLFWwindow, c_int) c_int;
extern fn glfwSetWindowAttrib(?*GLFWwindow, c_int, c_int) void;
extern fn glfwSetCursorPos(?*GLFWwindow, f64, f64) void;
extern fn glfwSetWindowSizeCallback(?*GLFWwindow, GLFWwindowsizefun) GLFWwindowsizefun;
extern fn glfwSetWindowContentScaleCallback(?*GLFWwindow, GLFWwindowcontentscalefun) GLFWwindowcontentscalefun;
extern fn glfwSetWindowIconifyCallback(?*GLFWwindow, GLFWwindowiconifyfun) GLFWwindowiconifyfun;
extern fn glfwSetWindowFocusCallback(?*GLFWwindow, GLFWwindowfocusfun) GLFWwindowfocusfun;
extern fn glfwSetDropCallback(?*GLFWwindow, GLFWdropfun) GLFWdropfun;
extern fn glfwSetKeyCallback(?*GLFWwindow, GLFWkeyfun) GLFWkeyfun;
extern fn glfwSetCharCallback(?*GLFWwindow, GLFWcharfun) GLFWcharfun;
extern fn glfwSetMouseButtonCallback(?*GLFWwindow, GLFWmousebuttonfun) GLFWmousebuttonfun;
extern fn glfwSetCursorPosCallback(?*GLFWwindow, GLFWcursorposfun) GLFWcursorposfun;
extern fn glfwSetScrollCallback(?*GLFWwindow, GLFWscrollfun) GLFWscrollfun;
extern fn glfwSetCursorEnterCallback(?*GLFWwindow, GLFWcursorenterfun) GLFWcursorenterfun;

//----------------------------------------------------------------------------------
// rcore_web.js: rcore_web.c's inline JavaScript, one function per snippet
//----------------------------------------------------------------------------------
extern fn rlWebCanvasId(out: [*]u8, outSize: c_int) void;
extern fn rlWebIsFullscreen() c_int;
extern fn rlWebExitFullscreen() void;
extern fn rlWebCanvasWidth() c_int;
extern fn rlWebCanvasStyleWidth() c_int;
extern fn rlWebScreenWidth() c_int;
extern fn rlWebScreenHeight() c_int;
extern fn rlWebInnerWidth() c_int;
extern fn rlWebInnerHeight() c_int;
extern fn rlWebScreenX() c_int;
extern fn rlWebScreenY() c_int;
extern fn rlWebDevicePixelRatio() f64;
extern fn rlWebRequestFullscreen() void;
extern fn rlWebRequestBorderless(canvasId: [*:0]const u8) void;
extern fn rlWebSetCanvasOpacity(opacity: f32) void;
extern fn rlWebSetCanvasCursor(cursor: [*:0]const u8) void;
extern fn rlWebPointerLocked() c_int;
extern fn rlWebClipboardWriteText(text: [*c]const u8) void;
extern fn rlWebRequestClipboardData() void;
extern fn rlWebLastPastedText() [*c]u8;
extern fn rlWebLastPastedImage(width: *c_int, height: *c_int) ?*anyopaque;
extern fn rlWebGamepadVibrate(gamepad: c_int, leftMotor: f32, rightMotor: f32, duration: f32) void;

// html5.h targets that translate-c cannot express (`(const char *)2` and friends).
const EMSCRIPTEN_EVENT_TARGET_WINDOW: [*c]const u8 = @ptrFromInt(2);
const on_calling_thread = em.EM_CALLBACK_THREAD_CONTEXT_CALLING_THREAD;

//----------------------------------------------------------------------------------
// Types and Structures Definition
//----------------------------------------------------------------------------------
const PlatformData = struct {
    handle: ?*GLFWwindow = null, // GLFW window handle (graphic device)
    ourFullscreen: bool = false, // Internal var to filter our handling of fullscreen vs the user handling of fullscreen
    unmaximizedWidth: c_int = 0, // Internal var to store the unmaximized window (canvas) width
    unmaximizedHeight: c_int = 0, // Internal var to store the unmaximized window (canvas) height

    // Keep current canvas id where wasm app is running
    // NOTE: Useful when trying to run multiple wasms in different canvases in same webpage
    canvasId: [64:0]u8 = @splat(0),
};

var platform: PlatformData = .{};

/// CSS cursor names, indexed by MouseCursor.
const cursorLUT = [11][:0]const u8{
    "default", // 0  MOUSE_CURSOR_DEFAULT
    "default", // 1  MOUSE_CURSOR_ARROW
    "text", // 2  MOUSE_CURSOR_IBEAM
    "crosshair", // 3  MOUSE_CURSOR_CROSSHAIR
    "pointer", // 4  MOUSE_CURSOR_POINTING_HAND
    "ew-resize", // 5  MOUSE_CURSOR_RESIZE_EW
    "ns-resize", // 6  MOUSE_CURSOR_RESIZE_NS
    "nwse-resize", // 7  MOUSE_CURSOR_RESIZE_NWSE
    "nesw-resize", // 8  MOUSE_CURSOR_RESIZE_NESW
    "move", // 9  MOUSE_CURSOR_RESIZE_ALL
    "not-allowed", // 10 MOUSE_CURSOR_NOT_ALLOWED
};

//----------------------------------------------------------------------------------
// Module Functions Definition: Window and Graphics Device
//----------------------------------------------------------------------------------

// Check if application should close
// This will always return false on a web-build as web builds have no control over this functionality
// Sleep is handled in EndDrawing() for synchronous code
pub export fn WindowShouldClose() callconv(.c) bool {
    // Emscripten Asyncify is required to run synchronous code in asynchronous JS
    // REF: https://emscripten.org/docs/porting/asyncify.html

    // WindowShouldClose() is not called on a web-ready raylib application if using emscripten_set_main_loop()
    // and encapsulating one frame execution on a UpdateDrawFrame() function,
    // allowing the browser to manage execution asynchronously

    // Optionally, time to give-control-back-to-browser can be managed here,
    // but it seems below line could generate stuttering on some browsers
    em.emscripten_sleep(12);

    return false;
}

// Toggle fullscreen mode
pub export fn ToggleFullscreen() callconv(.c) void {
    platform.ourFullscreen = true;
    var enterFullscreen = false;

    const wasFullscreen = rlWebIsFullscreen() != 0;
    if (wasFullscreen) {
        if (flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE)) {
            enterFullscreen = false;
        } else if (flagIsSet(CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE)) {
            enterFullscreen = true;
        } else {
            const canvasWidth = rlWebCanvasWidth();
            const canvasStyleWidth = rlWebCanvasStyleWidth();
            enterFullscreen = !(canvasStyleWidth > canvasWidth);
        }

        rlWebExitFullscreen();

        flagClear(&CORE.Window.flags, FLAG_FULLSCREEN_MODE);
        flagClear(&CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE);
    } else enterFullscreen = true;

    if (enterFullscreen) {
        rlWebRequestFullscreen();
        flagSet(&CORE.Window.flags, FLAG_FULLSCREEN_MODE);
    }
}

// Toggle borderless windowed mode
pub export fn ToggleBorderlessWindowed() callconv(.c) void {
    platform.ourFullscreen = true;
    var enterBorderless = false;

    const wasFullscreen = rlWebIsFullscreen() != 0;
    if (wasFullscreen) {
        if (flagIsSet(CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE)) {
            enterBorderless = false;
        } else if (flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE)) {
            enterBorderless = true;
        } else {
            const canvasWidth = rlWebCanvasWidth();
            const screenWidth = rlWebScreenWidth();
            enterBorderless = screenWidth != canvasWidth;
        }

        rlWebExitFullscreen();

        flagClear(&CORE.Window.flags, FLAG_FULLSCREEN_MODE);
        flagClear(&CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE);
    } else enterBorderless = true;

    if (enterBorderless) {
        rlWebRequestBorderless(&platform.canvasId);
        flagSet(&CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE);
    }
}

/// Grow the canvas to the browser tab (MaximizeWindow and SetWindowState).
fn maximizeToTab() void {
    platform.unmaximizedWidth = @intCast(CORE.Window.screen.width);
    platform.unmaximizedHeight = @intCast(CORE.Window.screen.height);

    const tabWidth = rlWebInnerWidth();
    const tabHeight = rlWebInnerHeight();

    if (tabWidth != 0 and tabHeight != 0) glfwSetWindowSize(platform.handle, tabWidth, tabHeight);

    flagSet(&CORE.Window.flags, FLAG_WINDOW_MAXIMIZED);
}

// Set window state: maximized, if resizable
pub export fn MaximizeWindow() callconv(.c) void {
    if ((glfwGetWindowAttrib(platform.handle, GLFW_RESIZABLE) == GLFW_TRUE) and !flagIsSet(CORE.Window.flags, FLAG_WINDOW_MAXIMIZED)) {
        maximizeToTab();
    }
}

// Set window state: minimized
pub export fn MinimizeWindow() callconv(.c) void {
    TraceLog(LOG_WARNING, "MinimizeWindow() not available on target platform");
}

// Restore window from being minimized/maximized
export fn RestoreWindow() callconv(.c) void {
    if ((glfwGetWindowAttrib(platform.handle, GLFW_RESIZABLE) == GLFW_TRUE) and flagIsSet(CORE.Window.flags, FLAG_WINDOW_MAXIMIZED)) {
        if (platform.unmaximizedWidth != 0 and platform.unmaximizedHeight != 0) glfwSetWindowSize(platform.handle, platform.unmaximizedWidth, platform.unmaximizedHeight);

        flagClear(&CORE.Window.flags, FLAG_WINDOW_MAXIMIZED);
    }
}

// Set window configuration state using flags
export fn SetWindowState(flags: c_uint) callconv(.c) void {
    if (!CORE.Window.ready) TraceLog(LOG_WARNING, "WINDOW: SetWindowState does nothing before window initialization, Use \"SetConfigFlags\" instead");

    // Check previous state and requested state to apply required changes
    // NOTE: In most cases the functions already change the flags internally

    // State change: FLAG_VSYNC_HINT
    if (flagIsSet(flags, FLAG_VSYNC_HINT)) {
        TraceLog(LOG_WARNING, "SetWindowState(FLAG_VSYNC_HINT) not available on target platform");
    }

    // State change: FLAG_BORDERLESS_WINDOWED_MODE
    if (flagIsSet(flags, FLAG_BORDERLESS_WINDOWED_MODE)) {
        // NOTE: Window state flag updated inside ToggleBorderlessWindowed() function
        const wasFullscreen = rlWebIsFullscreen() != 0;
        if (wasFullscreen) {
            const canvasWidth = rlWebCanvasWidth();
            const canvasStyleWidth = rlWebCanvasStyleWidth();
            if (flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE) or canvasStyleWidth > canvasWidth) ToggleBorderlessWindowed();
        } else ToggleBorderlessWindowed();
    }

    // State change: FLAG_FULLSCREEN_MODE
    if (flagIsSet(flags, FLAG_FULLSCREEN_MODE)) {
        // NOTE: Window state flag updated inside ToggleFullscreen() function
        const wasFullscreen = rlWebIsFullscreen() != 0;
        if (wasFullscreen) {
            const canvasWidth = rlWebCanvasWidth();
            const screenWidth = rlWebScreenWidth();
            if (flagIsSet(CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE) or screenWidth == canvasWidth) ToggleFullscreen();
        } else ToggleFullscreen();
    }

    // State change: FLAG_WINDOW_RESIZABLE
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_RESIZABLE) != flagIsSet(flags, FLAG_WINDOW_RESIZABLE)) and flagIsSet(flags, FLAG_WINDOW_RESIZABLE)) {
        glfwSetWindowAttrib(platform.handle, GLFW_RESIZABLE, GLFW_TRUE);
        flagSet(&CORE.Window.flags, FLAG_WINDOW_RESIZABLE);
    }

    // State change: FLAG_WINDOW_UNDECORATED, FLAG_WINDOW_HIDDEN, FLAG_WINDOW_MINIMIZED
    inline for (.{
        .{ FLAG_WINDOW_UNDECORATED, "FLAG_WINDOW_UNDECORATED" },
        .{ FLAG_WINDOW_HIDDEN, "FLAG_WINDOW_HIDDEN" },
        .{ FLAG_WINDOW_MINIMIZED, "FLAG_WINDOW_MINIMIZED" },
    }) |f| {
        if (flagIsSet(flags, f[0])) TraceLog(LOG_WARNING, "SetWindowState(" ++ f[1] ++ ") not available on target platform");
    }

    // State change: FLAG_WINDOW_MAXIMIZED
    if ((flagIsSet(CORE.Window.flags, FLAG_WINDOW_MAXIMIZED) != flagIsSet(flags, FLAG_WINDOW_MAXIMIZED)) and flagIsSet(flags, FLAG_WINDOW_MAXIMIZED)) {
        if (glfwGetWindowAttrib(platform.handle, GLFW_RESIZABLE) == GLFW_TRUE) maximizeToTab();
    }

    // The remaining states can not be changed on the web (several can not be changed
    // after window creation at all).
    inline for (.{
        .{ FLAG_WINDOW_UNFOCUSED, "FLAG_WINDOW_UNFOCUSED" },
        .{ FLAG_WINDOW_TOPMOST, "FLAG_WINDOW_TOPMOST" },
        .{ FLAG_WINDOW_ALWAYS_RUN, "FLAG_WINDOW_ALWAYS_RUN" },
        .{ FLAG_WINDOW_TRANSPARENT, "FLAG_WINDOW_TRANSPARENT" },
        .{ FLAG_WINDOW_HIGHDPI, "FLAG_WINDOW_HIGHDPI" },
        .{ FLAG_WINDOW_MOUSE_PASSTHROUGH, "FLAG_WINDOW_MOUSE_PASSTHROUGH" },
        .{ FLAG_MSAA_4X_HINT, "FLAG_MSAA_4X_HINT" },
        .{ FLAG_INTERLACED_HINT, "FLAG_INTERLACED_HINT" },
    }) |f| {
        if (flagIsSet(flags, f[0])) TraceLog(LOG_WARNING, "SetWindowState(" ++ f[1] ++ ") not available on target platform");
    }
}

// Clear window configuration state flags
export fn ClearWindowState(flags: c_uint) callconv(.c) void {
    // Check previous state and requested state to apply required changes
    // NOTE: In most cases the functions already change the flags internally

    // State change: FLAG_VSYNC_HINT
    if (flagIsSet(flags, FLAG_VSYNC_HINT)) {
        TraceLog(LOG_WARNING, "ClearWindowState(FLAG_VSYNC_HINT) not available on target platform");
    }

    // State change: FLAG_BORDERLESS_WINDOWED_MODE
    if (flagIsSet(flags, FLAG_BORDERLESS_WINDOWED_MODE)) {
        const wasFullscreen = rlWebIsFullscreen() != 0;
        if (wasFullscreen) {
            const canvasWidth = rlWebCanvasWidth();
            const screenWidth = rlWebScreenWidth();
            if (flagIsSet(CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE) or (screenWidth == canvasWidth)) rlWebExitFullscreen();
        }

        flagClear(&CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE);
    }

    // State change: FLAG_FULLSCREEN_MODE
    if (flagIsSet(flags, FLAG_FULLSCREEN_MODE)) {
        const wasFullscreen = rlWebIsFullscreen() != 0;
        if (wasFullscreen) {
            const canvasWidth = rlWebCanvasWidth();
            const canvasStyleWidth = rlWebCanvasStyleWidth();
            if (flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE) or (canvasStyleWidth > canvasWidth)) rlWebExitFullscreen();
        }

        flagClear(&CORE.Window.flags, FLAG_FULLSCREEN_MODE);
    }

    // State change: FLAG_WINDOW_RESIZABLE
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_RESIZABLE) and flagIsSet(flags, FLAG_WINDOW_RESIZABLE)) {
        glfwSetWindowAttrib(platform.handle, GLFW_RESIZABLE, GLFW_FALSE);
        flagClear(&CORE.Window.flags, FLAG_WINDOW_RESIZABLE);
    }

    // State change: FLAG_WINDOW_HIDDEN, FLAG_WINDOW_MINIMIZED
    inline for (.{
        .{ FLAG_WINDOW_HIDDEN, "FLAG_WINDOW_HIDDEN" },
        .{ FLAG_WINDOW_MINIMIZED, "FLAG_WINDOW_MINIMIZED" },
    }) |f| {
        if (flagIsSet(flags, f[0])) TraceLog(LOG_WARNING, "ClearWindowState(" ++ f[1] ++ ") not available on target platform");
    }

    // State change: FLAG_WINDOW_MAXIMIZED
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_MAXIMIZED) and flagIsSet(flags, FLAG_WINDOW_MAXIMIZED)) {
        if (glfwGetWindowAttrib(platform.handle, GLFW_RESIZABLE) == GLFW_TRUE) {
            if (platform.unmaximizedWidth != 0 and platform.unmaximizedHeight != 0) glfwSetWindowSize(platform.handle, platform.unmaximizedWidth, platform.unmaximizedHeight);

            flagClear(&CORE.Window.flags, FLAG_WINDOW_MAXIMIZED);
        }
    }

    // The remaining states can not be changed on the web.
    inline for (.{
        .{ FLAG_WINDOW_UNDECORATED, "FLAG_WINDOW_UNDECORATED" },
        .{ FLAG_WINDOW_UNFOCUSED, "FLAG_WINDOW_UNFOCUSED" },
        .{ FLAG_WINDOW_TOPMOST, "FLAG_WINDOW_TOPMOST" },
        .{ FLAG_WINDOW_ALWAYS_RUN, "FLAG_WINDOW_ALWAYS_RUN" },
        .{ FLAG_WINDOW_TRANSPARENT, "FLAG_WINDOW_TRANSPARENT" },
        .{ FLAG_WINDOW_HIGHDPI, "FLAG_WINDOW_HIGHDPI" },
        .{ FLAG_WINDOW_MOUSE_PASSTHROUGH, "FLAG_WINDOW_MOUSE_PASSTHROUGH" },
        .{ FLAG_MSAA_4X_HINT, "FLAG_MSAA_4X_HINT" },
        .{ FLAG_INTERLACED_HINT, "FLAG_INTERLACED_HINT" },
    }) |f| {
        if (flagIsSet(flags, f[0])) TraceLog(LOG_WARNING, "ClearWindowState(" ++ f[1] ++ ") not available on target platform");
    }
}

// Set icon for window
export fn SetWindowIcon(image: Image) callconv(.c) void {
    _ = image;
    TraceLog(LOG_WARNING, "SetWindowIcon() not available on target platform");
}

// Set icon for window, multiple images
export fn SetWindowIcons(images: [*c]Image, count: c_int) callconv(.c) void {
    _ = images;
    _ = count;
    TraceLog(LOG_WARNING, "SetWindowIcons() not available on target platform");
}

// Set title for window
export fn SetWindowTitle(title: [*c]const u8) callconv(.c) void {
    CORE.Window.title = title;
    em.emscripten_set_window_title(title);
}

// Set window position on screen (windowed mode)
export fn SetWindowPosition(x: c_int, y: c_int) callconv(.c) void {
    _ = x;
    _ = y;
    TraceLog(LOG_WARNING, "SetWindowPosition() not available on target platform");
}

// Set monitor for the current window
export fn SetWindowMonitor(monitor: c_int) callconv(.c) void {
    _ = monitor;
    TraceLog(LOG_WARNING, "SetWindowMonitor() not available on target platform");
}

// Set window minimum dimensions (FLAG_WINDOW_RESIZABLE)
export fn SetWindowMinSize(width: c_int, height: c_int) callconv(.c) void {
    CORE.Window.screenMin.width = @bitCast(width);
    CORE.Window.screenMin.height = @bitCast(height);

    // Trigger the resize event once to update the window minimum width and height
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_RESIZABLE)) _ = EmscriptenResizeCallback(em.EMSCRIPTEN_EVENT_RESIZE, null, null);
}

// Set window maximum dimensions (FLAG_WINDOW_RESIZABLE)
export fn SetWindowMaxSize(width: c_int, height: c_int) callconv(.c) void {
    CORE.Window.screenMax.width = @bitCast(width);
    CORE.Window.screenMax.height = @bitCast(height);

    // Trigger the resize event once to update the window maximum width and height
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_RESIZABLE)) _ = EmscriptenResizeCallback(em.EMSCRIPTEN_EVENT_RESIZE, null, null);
}

// Set window dimensions
pub export fn SetWindowSize(width: c_int, height: c_int) callconv(.c) void {
    glfwSetWindowSize(platform.handle, width, height);
}

// Set window opacity, value opacity is between 0.0 and 1.0
export fn SetWindowOpacity(opacity: f32) callconv(.c) void {
    rlWebSetCanvasOpacity(std.math.clamp(opacity, 0.0, 1.0));
}

// Set window focused
export fn SetWindowFocused() callconv(.c) void {
    TraceLog(LOG_WARNING, "SetWindowFocused() not available on target platform");
}

// Get native window handle
export fn GetWindowHandle() callconv(.c) ?*anyopaque {
    TraceLog(LOG_WARNING, "GetWindowHandle() not implemented on target platform");
    return null;
}

// Get number of monitors
export fn GetMonitorCount() callconv(.c) c_int {
    TraceLog(LOG_WARNING, "GetMonitorCount() not implemented on target platform");
    return 1;
}

// Get current monitor where window is placed
export fn GetCurrentMonitor() callconv(.c) c_int {
    TraceLog(LOG_WARNING, "GetCurrentMonitor() not implemented on target platform");
    return 0;
}

// Get selected monitor position
export fn GetMonitorPosition(monitor: c_int) callconv(.c) Vector2 {
    _ = monitor;
    TraceLog(LOG_WARNING, "GetMonitorPosition() not implemented on target platform");
    return .{ .x = 0, .y = 0 };
}

// Get selected monitor width (currently used by monitor)
// NOTE: Returned value is limited to the current monitor where the browser window is located
export fn GetMonitorWidth(monitor: c_int) callconv(.c) c_int {
    _ = monitor;
    return rlWebScreenWidth();
}

// Get selected monitor height (currently used by monitor)
// NOTE: Returned value is limited to the current monitor where the browser window is located
export fn GetMonitorHeight(monitor: c_int) callconv(.c) c_int {
    _ = monitor;
    return rlWebScreenHeight();
}

// Get selected monitor physical width in millimetres
export fn GetMonitorPhysicalWidth(monitor: c_int) callconv(.c) c_int {
    _ = monitor;
    TraceLog(LOG_WARNING, "GetMonitorPhysicalWidth() not implemented on target platform");
    return 0;
}

// Get selected monitor physical height in millimetres
export fn GetMonitorPhysicalHeight(monitor: c_int) callconv(.c) c_int {
    _ = monitor;
    TraceLog(LOG_WARNING, "GetMonitorPhysicalHeight() not implemented on target platform");
    return 0;
}

// Get selected monitor refresh rate
export fn GetMonitorRefreshRate(monitor: c_int) callconv(.c) c_int {
    _ = monitor;
    TraceLog(LOG_WARNING, "GetMonitorRefreshRate() not implemented on target platform");
    return 0;
}

// Get the human-readable, UTF-8 encoded name of the selected monitor
export fn GetMonitorName(monitor: c_int) callconv(.c) [*c]const u8 {
    _ = monitor;
    TraceLog(LOG_WARNING, "GetMonitorName() not implemented on target platform");
    return "";
}

// Get window position XY on monitor
// NOTE: Returned position is relative to the current monitor where the browser window is located
export fn GetWindowPosition() callconv(.c) Vector2 {
    return .{ .x = @floatFromInt(rlWebScreenX()), .y = @floatFromInt(rlWebScreenY()) };
}

// Get window scale DPI factor for current monitor
// NOTE: Returned scale is relative to the current monitor where the browser window is located
pub export fn GetWindowScaleDPI() callconv(.c) Vector2 {
    const scale: f32 = @floatCast(rlWebDevicePixelRatio());
    return .{ .x = scale, .y = scale };
}

// Set clipboard text content
export fn SetClipboardText(text: [*c]const u8) callconv(.c) void {
    // Security check to (partially) avoid malicious code
    if (strchr(text, '\'') != null) {
        TraceLog(LOG_WARNING, "SYSTEM: Provided Clipboard could be potentially malicious, avoid [\\'] character");
    } else rlWebClipboardWriteText(text);
}

// Get clipboard text content
// NOTE: returned string is allocated with malloc in rcore_web.js
export fn GetClipboardText() callconv(.c) [*c]const u8 {
    rlWebRequestClipboardData();
    return rlWebLastPastedText();
}

// Get clipboard image
export fn GetClipboardImage() callconv(.c) Image {
    var image = std.mem.zeroes(Image);
    var w: c_int = 0;
    var h: c_int = 0;
    rlWebRequestClipboardData();
    if (rlWebLastPastedImage(&w, &h)) |data| {
        image.data = data;
        image.width = w;
        image.height = h;
        image.mipmaps = 1;
        image.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
    }

    return image;
}

// Show mouse cursor
export fn ShowCursor() callconv(.c) void {
    if (CORE.Input.Mouse.cursorHidden) {
        rlWebSetCanvasCursor(cursorLUT[@intCast(CORE.Input.Mouse.cursor)]);

        CORE.Input.Mouse.cursorHidden = false;
    }
}

// Hide mouse cursor
export fn HideCursor() callconv(.c) void {
    if (!CORE.Input.Mouse.cursorHidden) {
        rlWebSetCanvasCursor("none");

        CORE.Input.Mouse.cursorHidden = true;
    }
}

// Enable cursor (unlock cursor)
export fn EnableCursor() callconv(.c) void {
    _ = em.emscripten_exit_pointerlock();

    // Set cursor position in the middle
    SetMousePosition(@intCast(CORE.Window.screen.width / 2), @intCast(CORE.Window.screen.height / 2));

    // NOTE: CORE.Input.Mouse.cursorLocked handled by EmscriptenPointerlockCallback()
}

// Disable cursor (lock cursor)
export fn DisableCursor() callconv(.c) void {
    _ = em.emscripten_request_pointerlock(&platform.canvasId, true);

    // Set cursor position in the middle
    SetMousePosition(@intCast(CORE.Window.screen.width / 2), @intCast(CORE.Window.screen.height / 2));

    // NOTE: CORE.Input.Mouse.cursorLocked handled by EmscriptenPointerlockCallback()
}

// Swap back buffer with front buffer (screen drawing)
pub export fn SwapScreenBuffer() callconv(.c) void {
    glfwSwapBuffers(platform.handle);
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Misc
//----------------------------------------------------------------------------------

// Get elapsed time measure in seconds since InitTimer()
pub export fn GetTime() callconv(.c) f64 {
    return glfwGetTime(); // Elapsed time since glfwInit()
}

// Open URL with default system browser (if available)
// NOTE: This function is only safe to use if the provided URL is safe
// A user could craft a malicious string performing another action
// Avoid calling this function with user input non-validated strings
export fn OpenURL(url: [*c]const u8) callconv(.c) void {
    // Security check to (partially) avoid malicious code on target platform
    if (strchr(url, '\'') != null) {
        TraceLog(LOG_WARNING, "SYSTEM: Provided URL could be potentially malicious, avoid [\\'] character");
    } else em.emscripten_run_script(TextFormat("window.open('%s', '_blank')", url));
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Inputs
//----------------------------------------------------------------------------------

// Set internal gamepad mappings
export fn SetGamepadMappings(mappings: [*c]const u8) callconv(.c) c_int {
    _ = mappings;
    TraceLog(LOG_INFO, "SetGamepadMappings not implemented in rcore_web.c");
    return 0;
}

// Set gamepad vibration
export fn SetGamepadVibration(gamepad: c_int, leftMotor: f32, rightMotor: f32, duration: f32) callconv(.c) void {
    if ((gamepad < MAX_GAMEPADS) and CORE.Input.Gamepad.ready[@intCast(gamepad)] and (duration > 0.0)) {
        const left = std.math.clamp(leftMotor, 0.0, 1.0);
        const right = std.math.clamp(rightMotor, 0.0, 1.0);
        const seconds = @min(duration, MAX_GAMEPAD_VIBRATION_TIME);
        rlWebGamepadVibrate(gamepad, left, right, seconds * 1000.0); // duration in ms
    }
}

// Set mouse position XY
export fn SetMousePosition(x: c_int, y: c_int) callconv(.c) void {
    CORE.Input.Mouse.currentPosition = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };

    if (CORE.Input.Mouse.cursorLocked) CORE.Input.Mouse.lockedPosition = CORE.Input.Mouse.currentPosition;

    // NOTE: emscripten not implemented
    glfwSetCursorPos(platform.handle, CORE.Input.Mouse.currentPosition.x, CORE.Input.Mouse.currentPosition.y);
}

// Set mouse cursor
export fn SetMouseCursor(cursor: c_int) callconv(.c) void {
    if (CORE.Input.Mouse.cursor != cursor) {
        if (!CORE.Input.Mouse.cursorLocked) rlWebSetCanvasCursor(cursorLUT[@intCast(cursor)]);

        CORE.Input.Mouse.cursor = cursor;
    }
}

// Get physical key name
export fn GetKeyName(key: c_int) callconv(.c) [*c]const u8 {
    _ = key;
    TraceLog(LOG_WARNING, "GetKeyName() not implemented on target platform");
    return "";
}

/// Gamepad Buttons reference: https://www.w3.org/TR/gamepad/#gamepad-interface
/// (index = standard-mapping button, value = raylib GamepadButton)
const gamepadButtonLUT = [16]c_int{
    GAMEPAD_BUTTON_RIGHT_FACE_DOWN,
    GAMEPAD_BUTTON_RIGHT_FACE_RIGHT,
    GAMEPAD_BUTTON_RIGHT_FACE_LEFT,
    GAMEPAD_BUTTON_RIGHT_FACE_UP,
    GAMEPAD_BUTTON_LEFT_TRIGGER_1,
    GAMEPAD_BUTTON_RIGHT_TRIGGER_1,
    GAMEPAD_BUTTON_LEFT_TRIGGER_2,
    GAMEPAD_BUTTON_RIGHT_TRIGGER_2,
    GAMEPAD_BUTTON_MIDDLE_LEFT,
    GAMEPAD_BUTTON_MIDDLE_RIGHT,
    GAMEPAD_BUTTON_LEFT_THUMB,
    GAMEPAD_BUTTON_RIGHT_THUMB,
    GAMEPAD_BUTTON_LEFT_FACE_UP,
    GAMEPAD_BUTTON_LEFT_FACE_DOWN,
    GAMEPAD_BUTTON_LEFT_FACE_LEFT,
    GAMEPAD_BUTTON_LEFT_FACE_RIGHT,
};

// Register all input events
pub export fn PollInputEvents() callconv(.c) void {
    // NOTE: Gestures update must be called every frame to reset gestures correctly
    // because ProcessGestureEvent() is called on an event, not every frame
    if (SUPPORT_GESTURES_SYSTEM) UpdateGestures();

    // Reset keys/chars pressed registered
    CORE.Input.Keyboard.keyPressedQueueCount = 0;
    CORE.Input.Keyboard.charPressedQueueCount = 0;

    // Reset last gamepad button/axis registered state
    CORE.Input.Gamepad.lastButtonPressed = GAMEPAD_BUTTON_UNKNOWN;

    // Keyboard/Mouse input polling (automatically managed by GLFW3 through callback)

    // Register previous keys states
    CORE.Input.Keyboard.previousKeyState = CORE.Input.Keyboard.currentKeyState;
    CORE.Input.Keyboard.keyRepeatInFrame = @splat(0);

    // Register previous mouse states
    CORE.Input.Mouse.previousButtonState = CORE.Input.Mouse.currentButtonState;

    // Register previous mouse wheel state
    CORE.Input.Mouse.previousWheelMove = CORE.Input.Mouse.currentWheelMove;
    CORE.Input.Mouse.currentWheelMove = .{ .x = 0.0, .y = 0.0 };

    // Register previous mouse position
    CORE.Input.Mouse.previousPosition = CORE.Input.Mouse.currentPosition;

    // Register previous touch states
    CORE.Input.Touch.previousTouchState = CORE.Input.Touch.currentTouchState;

    // Gamepad support using emscripten API
    // NOTE: GLFW3 joystick functionality not available in web

    // Get number of gamepads connected
    var numGamepads: c_int = 0;
    if (em.emscripten_sample_gamepad_data() == em.EMSCRIPTEN_RESULT_SUCCESS) numGamepads = em.emscripten_get_num_gamepads();

    const gamepads: usize = @min(@as(usize, @intCast(@max(numGamepads, 0))), MAX_GAMEPADS);
    for (0..gamepads) |i| {
        // Register previous gamepad button states
        CORE.Input.Gamepad.previousButtonState[i] = CORE.Input.Gamepad.currentButtonState[i];

        var gamepadState = std.mem.zeroes(em.EmscriptenGamepadEvent);

        const result = em.emscripten_get_gamepad_status(@intCast(i), &gamepadState);

        if (result == em.EMSCRIPTEN_RESULT_SUCCESS) {
            // Register buttons data for every connected gamepad
            const numButtons: usize = @intCast(@max(gamepadState.numButtons, 0));
            for (0..@min(numButtons, MAX_GAMEPAD_BUTTONS)) |j| {
                if (j >= gamepadButtonLUT.len) continue; // Check for valid button
                const button: usize = @intCast(gamepadButtonLUT[j]);

                if (gamepadState.digitalButton[j]) {
                    CORE.Input.Gamepad.currentButtonState[i][button] = 1;
                    CORE.Input.Gamepad.lastButtonPressed = @intCast(button);
                } else CORE.Input.Gamepad.currentButtonState[i][button] = 0;
            }

            // Register axis data for every connected gamepad
            const numAxes: usize = @intCast(@max(gamepadState.numAxes, 0));
            for (0..@min(numAxes, MAX_GAMEPAD_AXES)) |j| {
                CORE.Input.Gamepad.axisState[i][j] = @floatCast(gamepadState.axis[j]);
            }

            CORE.Input.Gamepad.axisCount[i] = gamepadState.numAxes;
        }
    }

    CORE.Window.resizedLastFrame = false;
}

//----------------------------------------------------------------------------------
// Module Internal Functions Definition
//----------------------------------------------------------------------------------

// Initialize platform: graphics, inputs and more
pub export fn InitPlatform() callconv(.c) c_int {
    rlWebCanvasId(&platform.canvasId, platform.canvasId.len); // Get the current canvas id

    _ = glfwSetErrorCallback(ErrorCallback);

    // Initialize GLFW internal global state
    if (glfwInit() == GLFW_FALSE) {
        TraceLog(LOG_WARNING, "GLFW: Failed to initialize GLFW");
        return -1;
    }

    // Initialize graphic device: display/window and graphic context
    //----------------------------------------------------------------------------
    glfwDefaultWindowHints(); // Set default windows hints

    // Check window creation flags
    glfwWindowHint(GLFW_VISIBLE, if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIDDEN)) GLFW_FALSE else GLFW_TRUE);
    glfwWindowHint(GLFW_DECORATED, if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_UNDECORATED)) GLFW_FALSE else GLFW_TRUE);
    glfwWindowHint(GLFW_RESIZABLE, if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_RESIZABLE)) GLFW_TRUE else GLFW_FALSE);

    // Disable FLAG_WINDOW_MINIMIZED and FLAG_WINDOW_MAXIMIZED, not supported on initialization
    flagClear(&CORE.Window.flags, FLAG_WINDOW_MINIMIZED);
    flagClear(&CORE.Window.flags, FLAG_WINDOW_MAXIMIZED);

    glfwWindowHint(GLFW_FOCUSED, if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_UNFOCUSED)) GLFW_FALSE else GLFW_TRUE);
    glfwWindowHint(GLFW_FLOATING, if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_TOPMOST)) GLFW_TRUE else GLFW_FALSE);

    // NOTE: Some GLFW flags are not supported on HTML5
    // e.g.: GLFW_TRANSPARENT_FRAMEBUFFER, GLFW_COCOA_RETINA_FRAMEBUFFER, GLFW_MOUSE_PASSTHROUGH

    if (flagIsSet(CORE.Window.flags, FLAG_MSAA_4X_HINT)) {
        // NOTE: MSAA is only enabled for main framebuffer, not user-created FBOs
        TraceLog(LOG_INFO, "DISPLAY: Trying to enable MSAA x4");
        glfwWindowHint(GLFW_SAMPLES, 4); // Tries to enable multisampling x4 (MSAA), default is 0
    }

    // Check selection OpenGL version (rlgl.zig is always OpenGL ES 3.0 on the web)
    const glVersion = rlGetVersion();
    if (glVersion == RL_OPENGL_21) {
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
    } else if (glVersion == RL_OPENGL_33 or glVersion == RL_OPENGL_43) {
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, if (glVersion == RL_OPENGL_33) 3 else 4);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_FALSE);
    } else if (glVersion == RL_OPENGL_ES_20 or glVersion == RL_OPENGL_ES_30) {
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, if (glVersion == RL_OPENGL_ES_20) 2 else 3);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
        glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
        glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_NATIVE_CONTEXT_API);
    }

    // NOTE: Getting video modes is not implemented in emscripten GLFW3 version
    CORE.Window.display.width = CORE.Window.screen.width;
    CORE.Window.display.height = CORE.Window.screen.height;

    // Init fullscreen toggle required var:
    platform.ourFullscreen = false;

    const title: [*c]const u8 = if (CORE.Window.title != null) CORE.Window.title else " ";

    if (flagIsSet(CORE.Window.flags, FLAG_FULLSCREEN_MODE)) {
        // Remember center for switchinging from fullscreen to window
        if ((CORE.Window.screen.height == CORE.Window.display.height) and (CORE.Window.screen.width == CORE.Window.display.width)) {
            // If screen width/height equal to the display, it's not possible to
            // calculate the window position for toggling full-screened/windowed
            CORE.Window.position.x = @intCast(CORE.Window.display.width / 4);
            CORE.Window.position.y = @intCast(CORE.Window.display.height / 4);
        } else {
            CORE.Window.position.x = @as(c_int, @intCast(CORE.Window.display.width / 2)) - @as(c_int, @intCast(CORE.Window.screen.width / 2));
            CORE.Window.position.y = @as(c_int, @intCast(CORE.Window.display.height / 2)) - @as(c_int, @intCast(CORE.Window.screen.height / 2));
        }

        if (CORE.Window.position.x < 0) CORE.Window.position.x = 0;
        if (CORE.Window.position.y < 0) CORE.Window.position.y = 0;

        // Obtain recommended CORE.Window.display.width/CORE.Window.display.height from a valid videomode for the monitor
        var count: c_int = 0;
        const modes = glfwGetVideoModes(glfwGetPrimaryMonitor(), &count);

        // Get closest video mode to desired CORE.Window.screen.width/CORE.Window.screen.height
        for (0..@intCast(@max(count, 0))) |i| {
            if (@as(c_uint, @bitCast(modes[i].width)) >= CORE.Window.screen.width and
                @as(c_uint, @bitCast(modes[i].height)) >= CORE.Window.screen.height)
            {
                CORE.Window.display.width = @bitCast(modes[i].width);
                CORE.Window.display.height = @bitCast(modes[i].height);
                break;
            }
        }

        TraceLog(LOG_WARNING, "SYSTEM: Closest fullscreen videomode: %i x %i", CORE.Window.display.width, CORE.Window.display.height);

        platform.handle = glfwCreateWindow(@intCast(CORE.Window.display.width), @intCast(CORE.Window.display.height), title, glfwGetPrimaryMonitor(), null);
    } else {
        // No-fullscreen window creation
        platform.handle = glfwCreateWindow(@intCast(CORE.Window.screen.width), @intCast(CORE.Window.screen.height), title, null, null);

        if (platform.handle != null) {
            CORE.Window.render.width = CORE.Window.screen.width;
            CORE.Window.render.height = CORE.Window.screen.height;
        }
    }

    if (platform.handle == null) {
        glfwTerminate();
        TraceLog(LOG_WARNING, "GLFW: Failed to initialize Window");
        return -1;
    }

    // WARNING: glfwCreateWindow() title doesn't work with emscripten
    em.emscripten_set_window_title(title);

    // Set window callback events
    _ = glfwSetWindowSizeCallback(platform.handle, WindowSizeCallback);
    _ = glfwSetWindowIconifyCallback(platform.handle, WindowIconifyCallback);
    _ = glfwSetWindowFocusCallback(platform.handle, WindowFocusCallback);
    _ = glfwSetDropCallback(platform.handle, WindowDropCallback);

    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) {
        // Window content (framebuffer) scale callback
        _ = glfwSetWindowContentScaleCallback(platform.handle, WindowContentScaleCallback);
    }

    // Set input callback events
    _ = glfwSetKeyCallback(platform.handle, KeyCallback);
    _ = glfwSetCharCallback(platform.handle, CharCallback);
    _ = glfwSetMouseButtonCallback(platform.handle, MouseButtonCallback);
    _ = glfwSetCursorPosCallback(platform.handle, MouseMoveCallback);
    _ = glfwSetScrollCallback(platform.handle, MouseScrollCallback);
    _ = glfwSetCursorEnterCallback(platform.handle, MouseEnterCallback);

    glfwMakeContextCurrent(platform.handle);

    // WARNING: glfwGetError(NULL) can not be found in GLFW Web, so the context is
    // taken as active, as rcore_web.c does
    CORE.Window.ready = true;

    const fbWidth = CORE.Window.screen.width;
    const fbHeight = CORE.Window.screen.height;

    CORE.Window.render.width = fbWidth;
    CORE.Window.render.height = fbHeight;
    CORE.Window.currentFbo.width = fbWidth;
    CORE.Window.currentFbo.height = fbHeight;

    const highDpi: [*:0]const u8 = if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) "(HighDPI)" else "";
    TraceLog(LOG_INFO, "DISPLAY: Device initialized successfully %s", highDpi);
    TraceLog(LOG_INFO, "    > Display size: %i x %i", CORE.Window.display.width, CORE.Window.display.height);
    TraceLog(LOG_INFO, "    > Screen size:  %i x %i", CORE.Window.screen.width, CORE.Window.screen.height);
    TraceLog(LOG_INFO, "    > Render size:  %i x %i", CORE.Window.render.width, CORE.Window.render.height);
    TraceLog(LOG_INFO, "    > Viewport offsets: %i, %i", CORE.Window.renderOffset.x, CORE.Window.renderOffset.y);

    // Load OpenGL extensions
    // NOTE: GL procedures address loader is required to load extensions
    rlLoadExtensions(@ptrCast(@constCast(&WebGLGetProcAddress)));
    //----------------------------------------------------------------------------

    // Initialize events callbacks
    //----------------------------------------------------------------------------
    // Setup window events callbacks
    _ = em.emscripten_set_fullscreenchange_callback_on_thread(EMSCRIPTEN_EVENT_TARGET_WINDOW, null, true, EmscriptenFullscreenChangeCallback, on_calling_thread);
    _ = em.emscripten_set_blur_callback_on_thread(&platform.canvasId, platform.handle, true, EmscriptenFocusCallback, on_calling_thread);
    _ = em.emscripten_set_focus_callback_on_thread(&platform.canvasId, platform.handle, true, EmscriptenFocusCallback, on_calling_thread);
    _ = em.emscripten_set_visibilitychange_callback_on_thread(null, true, EmscriptenVisibilityChangeCallback, on_calling_thread);

    // Check Resize event (note this is done on the window since most browsers don't support this on canvas)
    _ = em.emscripten_set_resize_callback_on_thread(EMSCRIPTEN_EVENT_TARGET_WINDOW, null, true, EmscriptenResizeCallback, on_calling_thread);

    // Trigger resize callback to force initial size
    _ = EmscriptenResizeCallback(em.EMSCRIPTEN_EVENT_RESIZE, null, null);

    // Setup input events
    // NOTE: Keyboard callbacks are not registered, libglfw.js takes care of keyboard input
    _ = em.emscripten_set_click_callback_on_thread(&platform.canvasId, null, true, EmscriptenMouseCallback, on_calling_thread);
    _ = em.emscripten_set_pointerlockchange_callback_on_thread(EMSCRIPTEN_EVENT_TARGET_WINDOW, null, true, EmscriptenPointerlockCallback, on_calling_thread);
    _ = em.emscripten_set_mousemove_callback_on_thread(&platform.canvasId, null, true, EmscriptenMouseMoveCallback, on_calling_thread);
    _ = em.emscripten_set_touchstart_callback_on_thread(&platform.canvasId, null, true, EmscriptenTouchCallback, on_calling_thread);
    _ = em.emscripten_set_touchend_callback_on_thread(&platform.canvasId, null, true, EmscriptenTouchCallback, on_calling_thread);
    _ = em.emscripten_set_touchmove_callback_on_thread(&platform.canvasId, null, true, EmscriptenTouchCallback, on_calling_thread);
    _ = em.emscripten_set_touchcancel_callback_on_thread(&platform.canvasId, null, true, EmscriptenTouchCallback, on_calling_thread);
    _ = em.emscripten_set_gamepadconnected_callback_on_thread(null, true, EmscriptenGamepadCallback, on_calling_thread);
    _ = em.emscripten_set_gamepaddisconnected_callback_on_thread(null, true, EmscriptenGamepadCallback, on_calling_thread);
    //----------------------------------------------------------------------------

    // Initialize timing system
    InitTimer();

    // Initialize storage system
    CORE.Storage.basePath = GetWorkingDirectory();

    TraceLog(LOG_INFO, "PLATFORM: WEB: Initialized successfully");

    return 0;
}

// Close platform
pub export fn ClosePlatform() callconv(.c) void {
    glfwDestroyWindow(platform.handle);
    glfwTerminate();
}

// Get WebGL extension procedure address
// WARNING: rlGetProcAddress() uses this loader. On OpenGL ES 3.0 rcore_web.c lists no
// functions (its list is the ES 2.0 OES/ANGLE extensions), so it always returns null.
fn WebGLGetProcAddress(procName: [*c]const u8) callconv(.c) ?*anyopaque {
    _ = procName;
    return null;
}

// GLFW3 callback functions, called on GLFW registered events
//-------------------------------------------------------------------------------------------------------

// GLFW3: Called on errors
fn ErrorCallback(error_code: c_int, description: [*c]const u8) callconv(.c) void {
    TraceLog(LOG_WARNING, "GLFW: Error: %i Description: %s", error_code, description);
}

// GLFW3: Called on window resizing, runs when window is resizedLastFrame
fn WindowSizeCallback(window: ?*GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    _ = window;
    // Reset viewport and projection matrix for new size
    SetupViewport(width, height);

    CORE.Window.currentFbo.width = @bitCast(width);
    CORE.Window.currentFbo.height = @bitCast(height);
    CORE.Window.resizedLastFrame = true;

    if (IsWindowFullscreen()) return;

    // Set current screen size
    if (flagIsSet(CORE.Window.flags, FLAG_WINDOW_HIGHDPI)) {
        const windowScaleDPI = GetWindowScaleDPI();

        CORE.Window.screen.width = @intFromFloat(@as(f32, @floatFromInt(width)) / windowScaleDPI.x);
        CORE.Window.screen.height = @intFromFloat(@as(f32, @floatFromInt(height)) / windowScaleDPI.y);
    } else {
        CORE.Window.screen.width = @bitCast(width);
        CORE.Window.screen.height = @bitCast(height);
    }

    // NOTE: Postprocessing texture is not scaled to new size
}

// GLFW3: Called on window content (framebuffer) scaled
fn WindowContentScaleCallback(window: ?*GLFWwindow, scalex: f32, scaley: f32) callconv(.c) void {
    _ = window;
    CORE.Window.screenScale = MatrixScale(scalex, scaley, 1.0);
}

// GLFW3: Called on windows minimized/restored
fn WindowIconifyCallback(window: ?*GLFWwindow, iconified: c_int) callconv(.c) void {
    _ = window;
    if (iconified != 0) {
        flagSet(&CORE.Window.flags, FLAG_WINDOW_MINIMIZED); // The window was iconified
    } else flagClear(&CORE.Window.flags, FLAG_WINDOW_MINIMIZED); // The window was restored
}

// GLFW3: Called on windows get/lose focus
fn WindowFocusCallback(window: ?*GLFWwindow, focused: c_int) callconv(.c) void {
    _ = window;
    if (focused != 0) {
        flagClear(&CORE.Window.flags, FLAG_WINDOW_UNFOCUSED); // The window was focused
    } else flagSet(&CORE.Window.flags, FLAG_WINDOW_UNFOCUSED); // The window lost focus
}

// GLFW3: Called on file-drop over the window
fn WindowDropCallback(window: ?*GLFWwindow, count: c_int, paths: [*c][*c]const u8) callconv(.c) void {
    _ = window;
    if (count <= 0) return;

    // In case previous dropped filepaths have not been freed, free them
    if (CORE.Window.dropFileCount > 0) {
        for (0..CORE.Window.dropFileCount) |i| RL_FREE(CORE.Window.dropFilepaths[i]);

        RL_FREE(CORE.Window.dropFilepaths);

        CORE.Window.dropFileCount = 0;
        CORE.Window.dropFilepaths = null;
    }

    // WARNING: Paths are freed by GLFW when the callback returns, an internal copy must freed
    CORE.Window.dropFileCount = @intCast(count);
    CORE.Window.dropFilepaths = @ptrCast(@alignCast(RL_CALLOC(CORE.Window.dropFileCount, @sizeOf([*c]u8))));

    for (0..CORE.Window.dropFileCount) |i| {
        CORE.Window.dropFilepaths[i] = @ptrCast(RL_CALLOC(MAX_FILEPATH_LENGTH, @sizeOf(u8)));
        _ = snprintf(CORE.Window.dropFilepaths[i], MAX_FILEPATH_LENGTH, "%s", paths[i]);
    }
}

// GLFW3: Called on keyboard interaction
fn KeyCallback(window: ?*GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = window;
    _ = scancode;
    _ = mods;
    if ((key < 0) or (key >= MAX_KEYBOARD_KEYS)) return; // Security check, macOS fn key generates -1
    const k: usize = @intCast(key);

    // WARNING: GLFW could return GLFW_REPEAT, it needs to be considered as 1
    // to work properly with our implementation (IsKeyDown/IsKeyUp checks)
    if (action == GLFW_RELEASE) {
        CORE.Input.Keyboard.currentKeyState[k] = 0;
    } else if (action == GLFW_PRESS) {
        CORE.Input.Keyboard.currentKeyState[k] = 1;
    } else if (action == GLFW_REPEAT) CORE.Input.Keyboard.keyRepeatInFrame[k] = 1;

    // Check if there is space available in the key queue
    if ((CORE.Input.Keyboard.keyPressedQueueCount < MAX_KEY_PRESSED_QUEUE) and (action == GLFW_PRESS)) {
        // Add character to the queue
        CORE.Input.Keyboard.keyPressedQueue[@intCast(CORE.Input.Keyboard.keyPressedQueueCount)] = key;
        CORE.Input.Keyboard.keyPressedQueueCount += 1;
    }

    // Check the exit key to set close window
    if ((key == CORE.Input.Keyboard.exitKey) and (action == GLFW_PRESS)) glfwSetWindowShouldClose(platform.handle, GLFW_TRUE);
}

// GLFW3: Called on key down interaction, gets equivalent unicode char value for the key
fn CharCallback(window: ?*GLFWwindow, key: c_uint) callconv(.c) void {
    _ = window;
    // NOTE: Registers any key down considering OS keyboard layout but
    // does not detect action events, those should be managed by user...
    // REF: https://github.com/glfw/glfw/issues/668#issuecomment-166794907
    // REF: https://www.glfw.org/docs/latest/input_guide.html#input_char

    // Check if there is space available in the queue
    if (CORE.Input.Keyboard.charPressedQueueCount < MAX_CHAR_PRESSED_QUEUE) {
        // Add character to the queue
        CORE.Input.Keyboard.charPressedQueue[@intCast(CORE.Input.Keyboard.charPressedQueueCount)] = @bitCast(key);
        CORE.Input.Keyboard.charPressedQueueCount += 1;
    }
}

/// Mouse gestures: one touch point at the mouse position, normalized to the screen.
fn mouseGestureEvent(touchAction: c_int, position: Vector2) GestureEvent {
    var gestureEvent = std.mem.zeroes(GestureEvent);
    gestureEvent.touchAction = touchAction;
    gestureEvent.pointId[0] = 0; // Assign a pointer ID
    gestureEvent.pointCount = 1; // Register touch points count

    // Register touch points position, only one point registered, normalized
    // for CORE.Window.screen.width and CORE.Window.screen.height
    gestureEvent.position[0] = .{
        .x = position.x / @as(f32, @floatFromInt(GetScreenWidth())),
        .y = position.y / @as(f32, @floatFromInt(GetScreenHeight())),
    };
    return gestureEvent;
}

// GLFW3: Called on mouse button interaction
fn MouseButtonCallback(window: ?*GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = window;
    _ = mods;
    const b: usize = @intCast(button);
    // WARNING: GLFW could only return GLFW_PRESS (1) or GLFW_RELEASE (0) for now,
    // but future releases may add more actions (i.e. GLFW_REPEAT)
    CORE.Input.Mouse.currentButtonState[b] = @intCast(action);
    CORE.Input.Touch.currentTouchState[b] = @intCast(action);

    if (SUPPORT_GESTURES_SYSTEM and SUPPORT_MOUSE_GESTURES) {
        // Process mouse events as touches to be able to use mouse-gestures

        // Register touch actions
        // NOTE: TOUCH_ACTION_MOVE event is registered in MouseMoveCallback()
        var touchAction: c_int = 0;
        if ((CORE.Input.Mouse.currentButtonState[b] == 1) and (CORE.Input.Mouse.previousButtonState[b] == 0)) {
            touchAction = TOUCH_ACTION_DOWN;
        } else if ((CORE.Input.Mouse.currentButtonState[b] == 0) and (CORE.Input.Mouse.previousButtonState[b] == 1)) touchAction = TOUCH_ACTION_UP;

        // Gesture data is sent to gestures-system for processing
        // Prevent calling ProcessGestureEvent() when Emscripten is present and there's a touch gesture, so EmscriptenTouchCallback() can handle it itself
        if (GetMouseX() != 0 or GetMouseY() != 0) ProcessGestureEvent(mouseGestureEvent(touchAction, GetMousePosition()));
    }
}

// GLFW3: Called on mouse move
fn MouseMoveCallback(window: ?*GLFWwindow, x: f64, y: f64) callconv(.c) void {
    _ = window;
    // If the pointer is not locked, follow the position
    if (!CORE.Input.Mouse.cursorLocked) {
        CORE.Input.Mouse.currentPosition.x = @floatCast(x);
        CORE.Input.Mouse.currentPosition.y = @floatCast(y);
        CORE.Input.Touch.position[0] = CORE.Input.Mouse.currentPosition;
    }

    if (SUPPORT_GESTURES_SYSTEM and SUPPORT_MOUSE_GESTURES) {
        // Process mouse events as touches to be able to use mouse-gestures
        ProcessGestureEvent(mouseGestureEvent(TOUCH_ACTION_MOVE, CORE.Input.Touch.position[0]));
    }
}

// GLFW3: Called on mouse wheel scrolling
fn MouseScrollCallback(window: ?*GLFWwindow, xoffset: f64, yoffset: f64) callconv(.c) void {
    _ = window;
    CORE.Input.Mouse.currentWheelMove = .{ .x = @floatCast(xoffset), .y = @floatCast(yoffset) };
}

// GLFW3: Called on mouse entering the window
fn MouseEnterCallback(window: ?*GLFWwindow, enter: c_int) callconv(.c) void {
    _ = window;
    CORE.Input.Mouse.cursorOnScreen = enter != 0;
}

// Emscripten callback functions, called on specific browser events
//-------------------------------------------------------------------------------------------------------

// Emscripten: Called on mouse input events
fn EmscriptenMouseCallback(eventType: c_int, mouseEvent: [*c]const em.EmscriptenMouseEvent, userData: ?*anyopaque) callconv(.c) bool {
    _ = eventType;
    _ = mouseEvent;
    _ = userData;
    // This is only for registering mouse click events with emscripten and doesn't need to do anything
    return true; // The event was consumed by the callback handler
}

// Emscripten: Called on mouse move events
fn EmscriptenMouseMoveCallback(eventType: c_int, mouseEvent: [*c]const em.EmscriptenMouseEvent, userData: ?*anyopaque) callconv(.c) bool {
    _ = eventType;
    _ = userData;
    // To emulate the GLFW_RAW_MOUSE_MOTION property
    if (CORE.Input.Mouse.cursorLocked) {
        CORE.Input.Mouse.previousPosition.x = CORE.Input.Mouse.lockedPosition.x - @as(f32, @floatFromInt(mouseEvent.*.movementX));
        CORE.Input.Mouse.previousPosition.y = CORE.Input.Mouse.lockedPosition.y - @as(f32, @floatFromInt(mouseEvent.*.movementY));
    }

    return true; // The event was consumed by the callback handler
}

// Emscripten: Called on pointer lock events
fn EmscriptenPointerlockCallback(eventType: c_int, pointerlockChangeEvent: [*c]const em.EmscriptenPointerlockChangeEvent, userData: ?*anyopaque) callconv(.c) bool {
    _ = eventType;
    _ = pointerlockChangeEvent;
    _ = userData;
    CORE.Input.Mouse.cursorLocked = rlWebPointerLocked() != 0;

    if (CORE.Input.Mouse.cursorLocked) {
        CORE.Input.Mouse.lockedPosition = CORE.Input.Mouse.currentPosition;
        CORE.Input.Mouse.previousPosition = CORE.Input.Mouse.lockedPosition;
    }

    return true; // The event was consumed by the callback handler
}

// Emscripten: Called on connect/disconnect gamepads events
fn EmscriptenGamepadCallback(eventType: c_int, gamepadEvent: [*c]const em.EmscriptenGamepadEvent, userData: ?*anyopaque) callconv(.c) bool {
    _ = eventType;
    _ = userData;
    const event = gamepadEvent.*;
    const index: usize = @intCast(event.index);
    if (event.connected and (index < MAX_GAMEPADS)) {
        CORE.Input.Gamepad.ready[index] = true;
        _ = snprintf(&CORE.Input.Gamepad.name[index], MAX_GAMEPAD_NAME_LENGTH, "%s", &event.id);
    } else if (index < MAX_GAMEPADS) CORE.Input.Gamepad.ready[index] = false;

    return true; // The event was consumed by the callback handler
}

// Emscripten: Called on touch input events
fn EmscriptenTouchCallback(eventType: c_int, touchEvent: [*c]const em.EmscriptenTouchEvent, userData: ?*anyopaque) callconv(.c) bool {
    _ = userData;
    const event = touchEvent.*;

    // Register touch points count
    CORE.Input.Touch.pointCount = event.numTouches;

    // NOTE: emscripten_get_canvas_element_size() returns canvas.width and canvas.height but
    // actual CSS size needs to be considered: canvas.style.width and canvas.style.height
    var canvasWidth: f64 = 0.0;
    var canvasHeight: f64 = 0.0;
    _ = em.emscripten_get_element_css_size(&platform.canvasId, &canvasWidth, &canvasHeight);

    const screenWidth: f32 = @floatFromInt(GetScreenWidth());
    const screenHeight: f32 = @floatFromInt(GetScreenHeight());
    const touches: usize = @min(@as(usize, @intCast(@max(CORE.Input.Touch.pointCount, 0))), MAX_TOUCH_POINTS);
    for (0..touches) |i| {
        // Register touch points id
        CORE.Input.Touch.pointId[i] = event.touches[i].identifier;

        // Register touch points position, normalized for CORE.Window.screen.width and CORE.Window.screen.height
        CORE.Input.Touch.position[i] = .{
            .x = @as(f32, @floatFromInt(event.touches[i].targetX)) * (screenWidth / @as(f32, @floatCast(canvasWidth))),
            .y = @as(f32, @floatFromInt(event.touches[i].targetY)) * (screenHeight / @as(f32, @floatCast(canvasHeight))),
        };

        if (eventType == em.EMSCRIPTEN_EVENT_TOUCHSTART) {
            CORE.Input.Touch.currentTouchState[i] = 1;
        } else if (eventType == em.EMSCRIPTEN_EVENT_TOUCHEND) CORE.Input.Touch.currentTouchState[i] = 0;
    }

    // Update mouse position when single touch detected
    if (CORE.Input.Touch.pointCount == 1) {
        CORE.Input.Mouse.currentPosition.x = CORE.Input.Touch.position[0].x;
        CORE.Input.Mouse.currentPosition.y = CORE.Input.Touch.position[0].y;
    }

    if (SUPPORT_GESTURES_SYSTEM) {
        var gestureEvent = std.mem.zeroes(GestureEvent);
        gestureEvent.pointCount = CORE.Input.Touch.pointCount;

        // Register touch actions
        gestureEvent.touchAction = switch (eventType) {
            em.EMSCRIPTEN_EVENT_TOUCHSTART => TOUCH_ACTION_DOWN,
            em.EMSCRIPTEN_EVENT_TOUCHEND => TOUCH_ACTION_UP,
            em.EMSCRIPTEN_EVENT_TOUCHMOVE => TOUCH_ACTION_MOVE,
            em.EMSCRIPTEN_EVENT_TOUCHCANCEL => TOUCH_ACTION_CANCEL,
            else => 0,
        };

        const points: usize = @min(@as(usize, @intCast(@max(gestureEvent.pointCount, 0))), MAX_TOUCH_POINTS);
        for (0..points) |i| {
            gestureEvent.pointId[i] = CORE.Input.Touch.pointId[i];
            gestureEvent.position[i] = .{
                .x = CORE.Input.Touch.position[i].x / screenWidth,
                .y = CORE.Input.Touch.position[i].y / screenHeight,
            };
        }

        // Gesture data is sent to gestures system for processing
        ProcessGestureEvent(gestureEvent);
    }

    if (eventType == em.EMSCRIPTEN_EVENT_TOUCHEND) {
        // Identify the EMSCRIPTEN_EVENT_TOUCHEND and remove it from the list
        const count: usize = @intCast(@max(CORE.Input.Touch.pointCount, 0));
        for (0..count) |i| {
            if (event.touches[i].isChanged) {
                // Move all touch points one position up
                for (i..count - 1) |j| {
                    CORE.Input.Touch.pointId[j] = CORE.Input.Touch.pointId[j + 1];
                    CORE.Input.Touch.position[j] = CORE.Input.Touch.position[j + 1];
                }
                // Decrease touch points count to remove the last one
                CORE.Input.Touch.pointCount -= 1;
                break;
            }
        }
        // Clamp pointCount to avoid negative values
        if (CORE.Input.Touch.pointCount < 0) CORE.Input.Touch.pointCount = 0;
    }

    return true; // The event was consumed by the callback handler
}

// Emscripten: Called on fullscreen change events
fn EmscriptenFullscreenChangeCallback(eventType: c_int, event: [*c]const em.EmscriptenFullscreenChangeEvent, userData: ?*anyopaque) callconv(.c) bool {
    _ = eventType;
    _ = event;
    _ = userData;
    // NOTE 1: Reset the fullscreen flags if the user left fullscreen manually by pressing the Escape key
    // NOTE 2: Which is a necessary safeguard because that case will bypass the toggles CORE.Window.flags resets
    if (platform.ourFullscreen) {
        platform.ourFullscreen = false;
    } else {
        const wasFullscreen = rlWebIsFullscreen() != 0;
        if (!wasFullscreen) {
            flagClear(&CORE.Window.flags, FLAG_FULLSCREEN_MODE);
            flagClear(&CORE.Window.flags, FLAG_BORDERLESS_WINDOWED_MODE);
        }
    }

    return true; // The event was consumed by the callback handler
}

// Emscripten: Called on resize event
fn EmscriptenResizeCallback(eventType: c_int, event: [*c]const em.EmscriptenUiEvent, userData: ?*anyopaque) callconv(.c) bool {
    _ = eventType;
    _ = event;
    _ = userData;
    // Don't resize non-resizeable windows
    if (!flagIsSet(CORE.Window.flags, FLAG_WINDOW_RESIZABLE)) return true;

    // This event is called whenever the window changes sizes,
    // so the size of the canvas object is explicitly retrieved below
    var width = rlWebInnerWidth();
    var height = rlWebInnerHeight();

    const minWidth: c_int = @intCast(CORE.Window.screenMin.width);
    const minHeight: c_int = @intCast(CORE.Window.screenMin.height);
    const maxWidth: c_int = @intCast(CORE.Window.screenMax.width);
    const maxHeight: c_int = @intCast(CORE.Window.screenMax.height);

    if (width < minWidth) {
        width = minWidth;
    } else if ((width > maxWidth) and (maxWidth > 0)) width = maxWidth;

    if (height < minHeight) {
        height = minHeight;
    } else if ((height > maxHeight) and (maxHeight > 0)) height = maxHeight;

    _ = em.emscripten_set_canvas_element_size(&platform.canvasId, width, height);

    SetupViewport(width, height); // Reset viewport and projection matrix for new size

    CORE.Window.currentFbo.width = @intCast(width);
    CORE.Window.currentFbo.height = @intCast(height);
    CORE.Window.resizedLastFrame = true;

    if (IsWindowFullscreen()) return true;

    // Set current screen size
    CORE.Window.screen.width = @intCast(width);
    CORE.Window.screen.height = @intCast(height);

    glfwSetWindowSize(platform.handle, @intCast(CORE.Window.screen.width), @intCast(CORE.Window.screen.height));

    // NOTE: Postprocessing texture is not scaled to new size

    return false;
}

// Emscripten: Called on windows focus change events
fn EmscriptenFocusCallback(eventType: c_int, focusEvent: [*c]const em.EmscriptenFocusEvent, userData: ?*anyopaque) callconv(.c) bool {
    _ = focusEvent;
    switch (eventType) {
        em.EMSCRIPTEN_EVENT_BLUR => WindowFocusCallback(userData, 0),
        em.EMSCRIPTEN_EVENT_FOCUS => WindowFocusCallback(userData, 1),
        else => return false,
    }
    return true;
}

// Emscripten: Called on visibility change events
fn EmscriptenVisibilityChangeCallback(eventType: c_int, visibilityChangeEvent: [*c]const em.EmscriptenVisibilityChangeEvent, userData: ?*anyopaque) callconv(.c) bool {
    _ = eventType;
    _ = userData;
    if (visibilityChangeEvent.*.hidden) {
        flagSet(&CORE.Window.flags, FLAG_WINDOW_HIDDEN); // The window was hidden
    } else flagClear(&CORE.Window.flags, FLAG_WINDOW_HIDDEN); // The window was restored
    return true; // The event was consumed by the callback handler
}
