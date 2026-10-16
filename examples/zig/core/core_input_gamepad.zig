//! raylib [core] example - input gamepad
//!
//! Zig-API translation of examples/core/core_input_gamepad.c (raylib 6.2).
//! NOTE: This example requires a Gamepad connected to the system
//!       raylib is configured to work with the following gamepads:
//!       - Xbox 360 Controller (Xbox 360, Xbox One)
//!       - PLAYSTATION(R)3 Controller
//!       Check raylib.h for buttons configuration
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

// NOTE: Gamepad name ID depends on drivers and OS
const xbox_aliases = [_][]const u8{ "xbox", "x-box" };
const ps_aliases = [_][]const u8{ "playstation", "sony" };

// Axis deadzones
const left_stick_deadzone_x: f32 = 0.1;
const left_stick_deadzone_y: f32 = 0.1;
const right_stick_deadzone_x: f32 = 0.1;
const right_stick_deadzone_y: f32 = 0.1;
const left_trigger_deadzone: f32 = -0.9;
const right_trigger_deadzone: f32 = -0.9;

/// Gamepad axis values, with deadzones applied
const Axes = struct {
    left_stick_x: f32,
    left_stick_y: f32,
    right_stick_x: f32,
    right_stick_y: f32,
    left_trigger: f32,
    right_trigger: f32,

    fn read(gamepad: i32) Axes {
        var axes: Axes = .{
            .left_stick_x = rl.getGamepadAxisMovement(gamepad, .left_x),
            .left_stick_y = rl.getGamepadAxisMovement(gamepad, .left_y),
            .right_stick_x = rl.getGamepadAxisMovement(gamepad, .right_x),
            .right_stick_y = rl.getGamepadAxisMovement(gamepad, .right_y),
            .left_trigger = rl.getGamepadAxisMovement(gamepad, .left_trigger),
            .right_trigger = rl.getGamepadAxisMovement(gamepad, .right_trigger),
        };

        // Calculate deadzones
        if (axes.left_stick_x > -left_stick_deadzone_x and axes.left_stick_x < left_stick_deadzone_x) axes.left_stick_x = 0.0;
        if (axes.left_stick_y > -left_stick_deadzone_y and axes.left_stick_y < left_stick_deadzone_y) axes.left_stick_y = 0.0;
        if (axes.right_stick_x > -right_stick_deadzone_x and axes.right_stick_x < right_stick_deadzone_x) axes.right_stick_x = 0.0;
        if (axes.right_stick_y > -right_stick_deadzone_y and axes.right_stick_y < right_stick_deadzone_y) axes.right_stick_y = 0.0;
        if (axes.left_trigger < left_trigger_deadzone) axes.left_trigger = -1.0;
        if (axes.right_trigger < right_trigger_deadzone) axes.right_trigger = -1.0;

        return axes;
    }
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true }); // Set MSAA 4X hint before windows creation

    rl.initWindow(screen_width, screen_height, "raylib [core] example - input gamepad");
    defer rl.closeWindow(); // Close window and OpenGL context

    const tex_ps3_pad = try rl.loadTexture("resources/ps3.png");
    defer rl.unloadTexture(tex_ps3_pad);
    const tex_xbox_pad = try rl.loadTexture("resources/xbox.png");
    defer rl.unloadTexture(tex_xbox_pad);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    var gamepad: i32 = 0; // which gamepad to display

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.left) and gamepad > 0) gamepad -= 1;
        if (rl.isKeyPressed(.right)) gamepad += 1;
        const mouse_position = rl.getMousePosition();

        const vibrate_button: rl.Rectangle = .{
            .x = 10,
            .y = 70.0 + @as(f32, @floatFromInt(20 * rl.getGamepadAxisCount(gamepad))) + 20,
            .width = 75,
            .height = 24,
        };
        if (rl.isMouseButtonPressed(.left) and rl.checkCollisionPointRec(mouse_position, vibrate_button)) rl.setGamepadVibration(gamepad, 1.0, 1.0, 1.0);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        if (!rl.isGamepadAvailable(gamepad)) {
            rl.drawText(rl.textFormat("GP{d}: NOT DETECTED", .{gamepad}), 10, 10, 10, .gray);
            rl.drawTexture(tex_xbox_pad, 0, 0, .light_gray);
            continue;
        }

        const name = rl.getGamepadName(gamepad) orelse "";
        rl.drawText(rl.textFormat("GP{d}: {s}", .{ gamepad, name }), 10, 10, 10, .black);

        // Get axis values
        const axes: Axes = .read(gamepad);

        if (nameMatches(name, &xbox_aliases)) {
            drawXboxPad(gamepad, tex_xbox_pad, axes);
        } else if (nameMatches(name, &ps_aliases)) {
            drawPs3Pad(gamepad, tex_ps3_pad, axes);
        } else {
            drawGenericPad(gamepad, axes);
        }

        rl.drawText(rl.textFormat("DETECTED AXIS [{d}]:", .{rl.getGamepadAxisCount(gamepad)}), 10, 50, 10, .maroon);

        var i: i32 = 0;
        while (i < rl.getGamepadAxisCount(gamepad)) : (i += 1) {
            rl.drawText(rl.textFormat("AXIS {d}: {d:.2}", .{ i, rl.getGamepadAxisMovement(gamepad, @fromBackingInt(@intCast(i))) }), 20, 70 + 20 * i, 10, .dark_gray);
        }

        // Draw vibrate button
        rl.drawRectangleRec(vibrate_button, .sky_blue);
        rl.drawText("VIBRATE", @intFromFloat(vibrate_button.x + 14), @intFromFloat(vibrate_button.y + 1), 10, .dark_gray);

        if (rl.getGamepadButtonPressed() != .unknown) {
            rl.drawText(rl.textFormat("DETECTED BUTTON: {d}", .{@backingInt(rl.getGamepadButtonPressed())}), 10, 430, 10, .red);
        } else {
            rl.drawText("DETECTED BUTTON: NONE", 10, 430, 10, .gray);
        }
    }
}

fn nameMatches(name: [:0]const u8, aliases: []const []const u8) bool {
    const lower = rl.textToLower(name);
    for (aliases) |alias| {
        if (std.mem.indexOf(u8, lower, alias) != null) return true;
    }
    return false;
}

fn down(gamepad: i32, button: rl.GamepadButton) bool {
    return rl.isGamepadButtonDown(gamepad, button);
}

/// Stick deflection in pixels
fn deflection(value: f32) i32 {
    return @intFromFloat(value * 20);
}

/// Trigger bar height in pixels
fn triggerHeight(value: f32) i32 {
    return @intFromFloat(((1 + value) / 2) * 70);
}

fn thumbColor(gamepad: i32, thumb: rl.GamepadButton) rl.Color {
    return if (down(gamepad, thumb)) .red else .black;
}

fn drawXboxPad(gamepad: i32, texture: rl.Texture2D, axes: Axes) void {
    rl.drawTexture(texture, 0, 0, .dark_gray);

    // Draw buttons: xbox home
    if (down(gamepad, .middle)) rl.drawCircle(394, 89, 19, .red);

    // Draw buttons: basic
    if (down(gamepad, .middle_right)) rl.drawCircle(436, 150, 9, .red);
    if (down(gamepad, .middle_left)) rl.drawCircle(352, 150, 9, .red);
    if (down(gamepad, .right_face_left)) rl.drawCircle(501, 151, 15, .blue);
    if (down(gamepad, .right_face_down)) rl.drawCircle(536, 187, 15, .lime);
    if (down(gamepad, .right_face_right)) rl.drawCircle(572, 151, 15, .maroon);
    if (down(gamepad, .right_face_up)) rl.drawCircle(536, 115, 15, .gold);

    // Draw buttons: d-pad
    rl.drawRectangle(317, 202, 19, 71, .black);
    rl.drawRectangle(293, 228, 69, 19, .black);
    if (down(gamepad, .left_face_up)) rl.drawRectangle(317, 202, 19, 26, .red);
    if (down(gamepad, .left_face_down)) rl.drawRectangle(317, 202 + 45, 19, 26, .red);
    if (down(gamepad, .left_face_left)) rl.drawRectangle(292, 228, 25, 19, .red);
    if (down(gamepad, .left_face_right)) rl.drawRectangle(292 + 44, 228, 26, 19, .red);

    // Draw buttons: left-right back
    if (down(gamepad, .left_trigger_1)) rl.drawCircle(259, 61, 20, .red);
    if (down(gamepad, .right_trigger_1)) rl.drawCircle(536, 61, 20, .red);

    // Draw axis: left joystick
    rl.drawCircle(259, 152, 39, .black);
    rl.drawCircle(259, 152, 34, .light_gray);
    rl.drawCircle(259 + deflection(axes.left_stick_x), 152 + deflection(axes.left_stick_y), 25, thumbColor(gamepad, .left_thumb));

    // Draw axis: right joystick
    rl.drawCircle(461, 237, 38, .black);
    rl.drawCircle(461, 237, 33, .light_gray);
    rl.drawCircle(461 + deflection(axes.right_stick_x), 237 + deflection(axes.right_stick_y), 25, thumbColor(gamepad, .right_thumb));

    // Draw axis: left-right triggers
    rl.drawRectangle(170, 30, 15, 70, .gray);
    rl.drawRectangle(604, 30, 15, 70, .gray);
    rl.drawRectangle(170, 30, 15, triggerHeight(axes.left_trigger), .red);
    rl.drawRectangle(604, 30, 15, triggerHeight(axes.right_trigger), .red);

    //rl.drawText(rl.textFormat("Xbox axis LT: {d:.2}", .{rl.getGamepadAxisMovement(gamepad, .left_trigger)}), 10, 40, 10, .black);
    //rl.drawText(rl.textFormat("Xbox axis RT: {d:.2}", .{rl.getGamepadAxisMovement(gamepad, .right_trigger)}), 10, 60, 10, .black);
}

fn drawPs3Pad(gamepad: i32, texture: rl.Texture2D, axes: Axes) void {
    rl.drawTexture(texture, 0, 0, .dark_gray);

    // Draw buttons: ps
    if (down(gamepad, .middle)) rl.drawCircle(396, 222, 13, .red);

    // Draw buttons: basic
    if (down(gamepad, .middle_left)) rl.drawRectangle(328, 170, 32, 13, .red);
    if (down(gamepad, .middle_right)) rl.drawTriangle(.{ .x = 436, .y = 168 }, .{ .x = 436, .y = 185 }, .{ .x = 464, .y = 177 }, .red);
    if (down(gamepad, .right_face_up)) rl.drawCircle(557, 144, 13, .lime);
    if (down(gamepad, .right_face_right)) rl.drawCircle(586, 173, 13, .red);
    if (down(gamepad, .right_face_down)) rl.drawCircle(557, 203, 13, .violet);
    if (down(gamepad, .right_face_left)) rl.drawCircle(527, 173, 13, .pink);

    // Draw buttons: d-pad
    rl.drawRectangle(225, 132, 24, 84, .black);
    rl.drawRectangle(195, 161, 84, 25, .black);
    if (down(gamepad, .left_face_up)) rl.drawRectangle(225, 132, 24, 29, .red);
    if (down(gamepad, .left_face_down)) rl.drawRectangle(225, 132 + 54, 24, 30, .red);
    if (down(gamepad, .left_face_left)) rl.drawRectangle(195, 161, 30, 25, .red);
    if (down(gamepad, .left_face_right)) rl.drawRectangle(195 + 54, 161, 30, 25, .red);

    // Draw buttons: left-right back buttons
    if (down(gamepad, .left_trigger_1)) rl.drawCircle(239, 82, 20, .red);
    if (down(gamepad, .right_trigger_1)) rl.drawCircle(557, 82, 20, .red);

    // Draw axis: left joystick
    rl.drawCircle(319, 255, 35, .black);
    rl.drawCircle(319, 255, 31, .light_gray);
    rl.drawCircle(319 + deflection(axes.left_stick_x), 255 + deflection(axes.left_stick_y), 25, thumbColor(gamepad, .left_thumb));

    // Draw axis: right joystick
    rl.drawCircle(475, 255, 35, .black);
    rl.drawCircle(475, 255, 31, .light_gray);
    rl.drawCircle(475 + deflection(axes.right_stick_x), 255 + deflection(axes.right_stick_y), 25, thumbColor(gamepad, .right_thumb));

    // Draw axis: left-right triggers
    rl.drawRectangle(169, 48, 15, 70, .gray);
    rl.drawRectangle(611, 48, 15, 70, .gray);
    rl.drawRectangle(169, 48, 15, triggerHeight(axes.left_trigger), .red);
    rl.drawRectangle(611, 48, 15, triggerHeight(axes.right_trigger), .red);
}

fn drawGenericPad(gamepad: i32, axes: Axes) void {
    // Draw background: generic
    rl.drawRectangleRounded(.{ .x = 175, .y = 110, .width = 460, .height = 220 }, 0.3, 16, .dark_gray);

    // Draw buttons: basic
    rl.drawCircle(365, 170, 12, .ray_white);
    rl.drawCircle(405, 170, 12, .ray_white);
    rl.drawCircle(445, 170, 12, .ray_white);
    rl.drawCircle(516, 191, 17, .ray_white);
    rl.drawCircle(551, 227, 17, .ray_white);
    rl.drawCircle(587, 191, 17, .ray_white);
    rl.drawCircle(551, 155, 17, .ray_white);
    if (down(gamepad, .middle_left)) rl.drawCircle(365, 170, 10, .red);
    if (down(gamepad, .middle)) rl.drawCircle(405, 170, 10, .green);
    if (down(gamepad, .middle_right)) rl.drawCircle(445, 170, 10, .blue);
    if (down(gamepad, .right_face_left)) rl.drawCircle(516, 191, 15, .gold);
    if (down(gamepad, .right_face_down)) rl.drawCircle(551, 227, 15, .blue);
    if (down(gamepad, .right_face_right)) rl.drawCircle(587, 191, 15, .green);
    if (down(gamepad, .right_face_up)) rl.drawCircle(551, 155, 15, .red);

    // Draw buttons: d-pad
    rl.drawRectangle(245, 145, 28, 88, .ray_white);
    rl.drawRectangle(215, 174, 88, 29, .ray_white);
    rl.drawRectangle(247, 147, 24, 84, .black);
    rl.drawRectangle(217, 176, 84, 25, .black);
    if (down(gamepad, .left_face_up)) rl.drawRectangle(247, 147, 24, 29, .red);
    if (down(gamepad, .left_face_down)) rl.drawRectangle(247, 147 + 54, 24, 30, .red);
    if (down(gamepad, .left_face_left)) rl.drawRectangle(217, 176, 30, 25, .red);
    if (down(gamepad, .left_face_right)) rl.drawRectangle(217 + 54, 176, 30, 25, .red);

    // Draw buttons: left-right back
    const left_back: rl.Rectangle = .{ .x = 215, .y = 98, .width = 100, .height = 10 };
    const right_back: rl.Rectangle = .{ .x = 495, .y = 98, .width = 100, .height = 10 };
    rl.drawRectangleRounded(left_back, 0.5, 16, .dark_gray);
    rl.drawRectangleRounded(right_back, 0.5, 16, .dark_gray);
    if (down(gamepad, .left_trigger_1)) rl.drawRectangleRounded(left_back, 0.5, 16, .red);
    if (down(gamepad, .right_trigger_1)) rl.drawRectangleRounded(right_back, 0.5, 16, .red);

    // Draw axis: left joystick
    rl.drawCircle(345, 260, 40, .black);
    rl.drawCircle(345, 260, 35, .light_gray);
    rl.drawCircle(345 + deflection(axes.left_stick_x), 260 + deflection(axes.left_stick_y), 25, thumbColor(gamepad, .left_thumb));

    // Draw axis: right joystick
    rl.drawCircle(465, 260, 40, .black);
    rl.drawCircle(465, 260, 35, .light_gray);
    rl.drawCircle(465 + deflection(axes.right_stick_x), 260 + deflection(axes.right_stick_y), 25, thumbColor(gamepad, .right_thumb));

    // Draw axis: left-right triggers
    rl.drawRectangle(151, 110, 15, 70, .gray);
    rl.drawRectangle(644, 110, 15, 70, .gray);
    rl.drawRectangle(151, 110, 15, triggerHeight(axes.left_trigger), .red);
    rl.drawRectangle(644, 110, 15, triggerHeight(axes.right_trigger), .red);
}
