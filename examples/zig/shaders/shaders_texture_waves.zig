//! raylib [shaders] example - texture waves
//!
//! Zig-API translation of examples/shaders/shaders_texture_waves.c (raylib 6.2).
//! Example contributed by Anata (@anatagawa) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Anata (@anatagawa) and Ramon Santamaria (@raysan5)
//!
//! NOTE: Shaders used in this example are #version 330 (OpenGL 3.3).

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - texture waves");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Load texture texture to apply shaders
    const texture = try rl.loadTexture("resources/space.png");
    defer rl.unloadTexture(texture);

    // Load shader and setup location points and values
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/wave.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    const seconds_loc = rl.getShaderLocation(shader, "seconds");
    const freq_x_loc = rl.getShaderLocation(shader, "freqX");
    const freq_y_loc = rl.getShaderLocation(shader, "freqY");
    const amp_x_loc = rl.getShaderLocation(shader, "ampX");
    const amp_y_loc = rl.getShaderLocation(shader, "ampY");
    const speed_x_loc = rl.getShaderLocation(shader, "speedX");
    const speed_y_loc = rl.getShaderLocation(shader, "speedY");

    // Shader uniform values that can be updated at any time
    const freq_x: f32 = 25.0;
    const freq_y: f32 = 25.0;
    const amp_x: f32 = 5.0;
    const amp_y: f32 = 5.0;
    const speed_x: f32 = 8.0;
    const speed_y: f32 = 8.0;

    const screen_size = [2]f32{ @floatFromInt(rl.getScreenWidth()), @floatFromInt(rl.getScreenHeight()) };
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "size"), screen_size);
    rl.setShaderValue(shader, freq_x_loc, freq_x);
    rl.setShaderValue(shader, freq_y_loc, freq_y);
    rl.setShaderValue(shader, amp_x_loc, amp_x);
    rl.setShaderValue(shader, amp_y_loc, amp_y);
    rl.setShaderValue(shader, speed_x_loc, speed_x);
    rl.setShaderValue(shader, speed_y_loc, speed_y);

    var seconds: f32 = 0.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        seconds += rl.getFrameTime();

        rl.setShaderValue(shader, seconds_loc, seconds);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.beginShaderMode(shader);
        defer rl.endShaderMode();

        rl.drawTexture(texture, 0, 0, .white);
        rl.drawTexture(texture, texture.width, 0, .white);
    }
}
