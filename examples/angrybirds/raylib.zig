//! Minimal raylib bindings for the Angry Birds demo.
//!
//! This file is the C-ABI boundary: extern struct layouts and extern fn
//! declarations mirror vendor/raylib/src/raylib.h exactly, for just the
//! API surface the game uses. The library implementation behind these
//! symbols is the Zig port in src/ (zig-out/lib/libraylib.a).

const std = @import("std");

pub const Vector2 = extern struct {
    x: f32,
    y: f32,

    pub const zero: Vector2 = .{ .x = 0, .y = 0 };

    pub fn add(a: Vector2, b: Vector2) Vector2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn sub(a: Vector2, b: Vector2) Vector2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn scale(v: Vector2, s: f32) Vector2 {
        return .{ .x = v.x * s, .y = v.y * s };
    }

    pub fn dot(a: Vector2, b: Vector2) f32 {
        return a.x * b.x + a.y * b.y;
    }

    pub fn length(v: Vector2) f32 {
        return @sqrt(v.dot(v));
    }

    pub fn distance(a: Vector2, b: Vector2) f32 {
        return b.sub(a).length();
    }
};

pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const Rectangle = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

// Palette constants from raylib.h.
pub const red: Color = .{ .r = 230, .g = 41, .b = 55, .a = 255 };
pub const maroon: Color = .{ .r = 190, .g = 33, .b = 55, .a = 255 };
pub const lime: Color = .{ .r = 0, .g = 158, .b = 47, .a = 255 };
pub const dark_green: Color = .{ .r = 0, .g = 117, .b = 44, .a = 255 };
pub const sky_blue: Color = .{ .r = 102, .g = 191, .b = 255, .a = 255 };
pub const brown: Color = .{ .r = 127, .g = 106, .b = 79, .a = 255 };
pub const black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
pub const dark_gray: Color = .{ .r = 80, .g = 80, .b = 80, .a = 255 };
pub const ray_white: Color = .{ .r = 245, .g = 245, .b = 245, .a = 255 };

/// FLAG_WINDOW_HIDDEN from raylib.h's ConfigFlags.
pub const flag_window_hidden: c_uint = 0x0000_0080;

/// The subset of KeyboardKey the game reads (values from raylib.h).
pub const Key = enum(c_int) {
    space = 32,
    n = 78,
    r = 82,
};

/// The subset of MouseButton the game reads (values from raylib.h).
pub const MouseButton = enum(c_int) {
    left = 0,
};

// Window and frame control.
pub extern fn InitWindow(width: c_int, height: c_int, title: [*:0]const u8) void;
pub extern fn CloseWindow() void;
pub extern fn WindowShouldClose() bool;
pub extern fn SetConfigFlags(flags: c_uint) void;
pub extern fn SetTargetFPS(fps: c_int) void;
pub extern fn GetFrameTime() f32;
pub extern fn BeginDrawing() void;
pub extern fn EndDrawing() void;
pub extern fn TakeScreenshot(file_name: [*:0]const u8) void;

// Input.
pub extern fn IsKeyPressed(key: Key) bool;
pub extern fn IsMouseButtonPressed(button: MouseButton) bool;
pub extern fn IsMouseButtonReleased(button: MouseButton) bool;
pub extern fn GetMousePosition() Vector2;

// Shapes and text.
pub extern fn DrawLineEx(start: Vector2, end: Vector2, thick: f32, color: Color) void;
pub extern fn DrawCircleV(center: Vector2, radius: f32, color: Color) void;
pub extern fn DrawCircleLinesV(center: Vector2, radius: f32, color: Color) void;
pub extern fn DrawRectangle(x: c_int, y: c_int, width: c_int, height: c_int, color: Color) void;
pub extern fn DrawRectangleGradientV(x: c_int, y: c_int, width: c_int, height: c_int, top: Color, bottom: Color) void;
pub extern fn DrawRectangleRec(rec: Rectangle, color: Color) void;
pub extern fn DrawRectangleLinesEx(rec: Rectangle, thick: f32, color: Color) void;
pub extern fn DrawText(text: [*:0]const u8, x: c_int, y: c_int, font_size: c_int, color: Color) void;
pub extern fn MeasureText(text: [*:0]const u8, font_size: c_int) c_int;
