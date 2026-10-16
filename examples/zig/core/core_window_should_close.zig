//! raylib [core] example - window should close
//!
//! Zig-API translation of examples/core/core_window_should_close.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - window should close");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setExitKey(.null); // Disable KEY_ESCAPE to close window, X-button still works

    var exit_window_requested = false; // Flag to request window to exit
    var exit_window = false; // Flag to set window to exit

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!exit_window) {
        // Update
        // Detect if X-button or KEY_ESCAPE have been pressed to close window
        if (rl.windowShouldClose() or rl.isKeyPressed(.escape)) exit_window_requested = true;

        if (exit_window_requested) {
            // A request for close window has been issued, we can save data before closing
            // or just show a message asking for confirmation
            if (rl.isKeyPressed(.y)) {
                exit_window = true;
            } else if (rl.isKeyPressed(.n)) {
                exit_window_requested = false;
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        if (exit_window_requested) {
            rl.drawRectangle(0, 100, screen_width, 200, .black);
            rl.drawText("Are you sure you want to exit program? [Y/N]", 40, 180, 30, .white);
        } else {
            rl.drawText("Try to close the window to get confirmation message!", 120, 200, 20, .light_gray);
        }
    }
}
