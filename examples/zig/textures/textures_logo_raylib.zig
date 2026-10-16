//! raylib [textures] example - logo raylib
//!
//! Zig-API translation of examples/textures/textures_logo_raylib.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - logo raylib");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)
    const texture = try rl.loadTexture("resources/raylib_logo.png"); // Texture loading
    defer rl.unloadTexture(texture); // Texture unloading

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawTexture(texture, screen_width / 2 - @divTrunc(texture.width, 2), screen_height / 2 - @divTrunc(texture.height, 2), .white);

        rl.drawText("this IS a texture!", 360, 370, 10, .gray);
    }
}
