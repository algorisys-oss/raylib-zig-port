//! raylib [shapes] example - logo raylib
//!
//! Zig-API translation of examples/shapes/shapes_logo_raylib.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - logo raylib");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawRectangle(screen_width / 2 - 128, screen_height / 2 - 128, 256, 256, .black);
        rl.drawRectangle(screen_width / 2 - 112, screen_height / 2 - 112, 224, 224, .ray_white);
        rl.drawText("raylib", screen_width / 2 - 44, screen_height / 2 + 48, 50, .black);

        rl.drawText("this is NOT a texture!", 350, 370, 10, .gray);
    }
}
