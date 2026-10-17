//! raylib [shaders] example - shapes textures
//!
//! Zig-API translation of examples/shaders/shaders_shapes_textures.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)
//!
//! NOTE: Shaders used in this example are #version 330 (OpenGL 3.3).

const std = @import("std");
const rl = @import("raylib");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - shapes textures");
    defer rl.closeWindow(); // Close window and OpenGL context

    const fudesumi = try rl.loadTexture("resources/fudesumi.png");
    defer rl.unloadTexture(fudesumi);

    // Load shader to be used on some parts drawing
    // NOTE: Defining null for vertex shader forces usage of internal default vertex shader
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/grayscale.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Start drawing with default shader
        rl.drawText("USING DEFAULT SHADER", 20, 40, 10, .red);

        rl.drawCircle(80, 120, 35, .dark_blue);
        rl.drawCircleGradient(.{ .x = 80.0, .y = 220.0 }, 60, .green, .sky_blue);
        rl.drawCircleLines(80, 340, 80, .dark_blue);

        // Activate our custom shader to be applied on next shapes/textures drawings
        {
            rl.beginShaderMode(shader);
            // Activate our default shader for next drawings
            defer rl.endShaderMode();

            rl.drawText("USING CUSTOM SHADER", 190, 40, 10, .red);

            rl.drawRectangle(250 - 60, 90, 120, 60, .red);
            rl.drawRectangleGradientH(250 - 90, 170, 180, 130, .maroon, .gold);
            rl.drawRectangleLines(250 - 40, 320, 80, 60, .orange);
        }

        rl.drawText("USING DEFAULT SHADER", 370, 40, 10, .red);

        rl.drawTriangle(.{ .x = 430, .y = 80 }, .{ .x = 430 - 60, .y = 150 }, .{ .x = 430 + 60, .y = 150 }, .violet);

        rl.drawTriangleLines(.{ .x = 430, .y = 160 }, .{ .x = 430 - 20, .y = 230 }, .{ .x = 430 + 20, .y = 230 }, .dark_blue);

        rl.drawPoly(.{ .x = 430, .y = 320 }, 6, 80, 0, .brown);

        // Activate our custom shader to be applied on next shapes/textures drawings
        {
            rl.beginShaderMode(shader);
            // Activate our default shader for next drawings
            defer rl.endShaderMode();

            rl.drawTexture(fudesumi, 500, -30, .white); // Using custom shader
        }

        rl.drawText("(c) Fudesumi sprite by Eiden Marsal", 380, screen_height - 20, 10, .gray);
    }
}
