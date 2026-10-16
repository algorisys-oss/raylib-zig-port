//! raylib [text] example - format text
//!
//! Zig-API translation of examples/text/text_format_text.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - format text");
    defer rl.closeWindow(); // Close window and OpenGL context

    const score = 100020;
    const hiscore = 200450;
    const lives = 5;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText(rl.textFormat("Score: {d:0>8}", .{score}), 200, 80, 20, .red);

        rl.drawText(rl.textFormat("HiScore: {d:0>8}", .{hiscore}), 200, 120, 20, .green);

        rl.drawText(rl.textFormat("Lives: {d:0>2}", .{lives}), 200, 160, 40, .blue);

        rl.drawText(rl.textFormat("Elapsed Time: {d:.2} ms", .{rl.getFrameTime() * 1000}), 200, 220, 20, .black);
    }
}
