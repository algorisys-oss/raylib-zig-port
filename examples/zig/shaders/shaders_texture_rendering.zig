//! raylib [shaders] example - texture rendering
//!
//! Zig-API translation of examples/shaders/shaders_texture_rendering.c (raylib 6.2).
//! Example contributed by Michał Ciesielski (@ciessielski) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Michał Ciesielski (@ciessielski) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - texture rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    const im_blank = rl.genImageColor(1024, 1024, .blank);
    const texture = try rl.loadTextureFromImage(im_blank); // Load blank texture to fill on shader
    defer rl.unloadTexture(texture);
    rl.unloadImage(im_blank);

    // NOTE: Using GLSL 330 shader version, on OpenGL ES 2.0 use GLSL 100 shader version
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/cubes_panning.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    var time: f32 = 0.0;
    const time_loc = rl.getShaderLocation(shader, "uTime");
    rl.setShaderValue(shader, time_loc, &time, .float);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        time = @floatCast(rl.getTime());
        rl.setShaderValue(shader, time_loc, &time, .float);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginShaderMode(shader); // Enable our custom shader for next shapes/textures drawings
            defer rl.endShaderMode(); // Disable our custom shader, return to default shader

            rl.drawTexture(texture, 0, 0, .white); // Drawing BLANK texture, all rendering magic happens on shader
        }

        rl.drawText("BACKGROUND is PAINTED and ANIMATED on SHADER!", 10, 10, 20, .maroon);
    }
}
