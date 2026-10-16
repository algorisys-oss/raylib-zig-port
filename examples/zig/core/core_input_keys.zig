//! raylib [core] example - input keys
//!
//! Zig-API translation of examples/core/core_input_keys.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - input keys");
    defer rl.closeWindow(); // Close window and OpenGL context

    var ball_position: rl.Vector2 = .{ .x = screen_width / 2.0, .y = screen_height / 2.0 };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyDown(.right)) ball_position.x += 2.0;
        if (rl.isKeyDown(.left)) ball_position.x -= 2.0;
        if (rl.isKeyDown(.up)) ball_position.y -= 2.0;
        if (rl.isKeyDown(.down)) ball_position.y += 2.0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("move the ball with arrow keys", 10, 10, 20, .dark_gray);

        rl.drawCircleV(ball_position, 50, .maroon);
    }
}
