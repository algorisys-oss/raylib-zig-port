//! raylib [core] example - window web
//!
//! Zig-API translation of examples/core/core_window_web.c (raylib 6.2).
//! The emscripten main-loop path (PLATFORM_WEB) is not translated: this is the
//! desktop build of the same structure (one UpdateDrawFrame per loop iteration).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const screen_width = 800;
const screen_height = 450;

pub fn main() void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [core] example - window web");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        updateDrawFrame();
    }
}

/// Update and draw one frame
fn updateDrawFrame() void {
    // Update
    // TODO: Update your variables here

    // Draw
    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(.ray_white);

    rl.drawText("Welcome to raylib web structure!", 220, 200, 20, .sky_blue);
}
