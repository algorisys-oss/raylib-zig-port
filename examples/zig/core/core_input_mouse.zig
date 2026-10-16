//! raylib [core] example - input mouse
//!
//! Zig-API translation of examples/core/core_input_mouse.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - input mouse");
    defer rl.closeWindow(); // Close window and OpenGL context

    var ball_position: rl.Vector2 = .{ .x = -100.0, .y = -100.0 };
    var ball_color: rl.Color = .dark_blue;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.h)) {
            if (rl.isCursorHidden()) rl.showCursor() else rl.hideCursor();
        }

        ball_position = rl.getMousePosition();

        if (rl.isMouseButtonPressed(.left)) {
            ball_color = .maroon;
        } else if (rl.isMouseButtonPressed(.middle)) {
            ball_color = .lime;
        } else if (rl.isMouseButtonPressed(.right)) {
            ball_color = .dark_blue;
        } else if (rl.isMouseButtonPressed(.side)) {
            ball_color = .purple;
        } else if (rl.isMouseButtonPressed(.extra)) {
            ball_color = .yellow;
        } else if (rl.isMouseButtonPressed(.forward)) {
            ball_color = .orange;
        } else if (rl.isMouseButtonPressed(.back)) {
            ball_color = .beige;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawCircleV(ball_position, 40, ball_color);

        rl.drawText("move ball with mouse and click mouse button to change color", 10, 10, 20, .dark_gray);
        rl.drawText("Press 'H' to toggle cursor visibility", 10, 30, 20, .dark_gray);

        if (rl.isCursorHidden()) {
            rl.drawText("CURSOR HIDDEN", 20, 60, 20, .red);
        } else {
            rl.drawText("CURSOR VISIBLE", 20, 60, 20, .lime);
        }
    }
}
