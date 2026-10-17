//! raylib [shaders] example - texture outline
//!
//! Zig-API translation of examples/shaders/shaders_texture_outline.c (raylib 6.2).
//! Example contributed by Serenity Skiff (@GoldenThumbs) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2021-2025 Serenity Skiff (@GoldenThumbs) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - texture outline");
    defer rl.closeWindow(); // Close window and OpenGL context

    const texture = try rl.loadTexture("resources/fudesumi.png");
    defer rl.unloadTexture(texture);

    const shdr_outline = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/outline.fs", .{glsl_version}));
    defer rl.unloadShader(shdr_outline);

    var outline_size: f32 = 2.0;
    const outline_color = [4]f32{ 1.0, 0.0, 0.0, 1.0 }; // Normalized RED color
    const texture_size = [2]f32{ @floatFromInt(texture.width), @floatFromInt(texture.height) };

    // Get shader locations
    const outline_size_loc = rl.getShaderLocation(shdr_outline, "outlineSize");
    const outline_color_loc = rl.getShaderLocation(shdr_outline, "outlineColor");
    const texture_size_loc = rl.getShaderLocation(shdr_outline, "textureSize");

    // Set shader values (they can be changed later)
    rl.setShaderValue(shdr_outline, outline_size_loc, outline_size);
    rl.setShaderValue(shdr_outline, outline_color_loc, outline_color);
    rl.setShaderValue(shdr_outline, texture_size_loc, texture_size);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        outline_size += rl.getMouseWheelMove();
        if (outline_size < 1.0) outline_size = 1.0;

        rl.setShaderValue(shdr_outline, outline_size_loc, outline_size);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginShaderMode(shdr_outline);
            defer rl.endShaderMode();

            rl.drawTexture(texture, @divTrunc(rl.getScreenWidth(), 2) - @divTrunc(texture.width, 2), -30, .white);
        }

        rl.drawText("Shader-based\ntexture\noutline", 10, 10, 20, .gray);
        rl.drawText("Scroll mouse wheel to\nchange outline size", 10, 72, 20, .gray);
        rl.drawText(rl.textFormat("Outline size: {d} px", .{@as(i32, @intFromFloat(outline_size))}), 10, 120, 20, .maroon);

        rl.drawFPS(710, 10);
    }
}
