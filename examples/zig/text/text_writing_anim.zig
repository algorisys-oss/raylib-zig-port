//! raylib [text] example - writing anim
//!
//! Zig-API translation of examples/text/text_writing_anim.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - writing anim");
    defer rl.closeWindow(); // Close window and OpenGL context

    const message = "This sample illustrates a text writing\nanimation effect! Check it out! ;)";

    var frames_counter: i32 = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        frames_counter += if (rl.isKeyDown(.space)) 8 else 1;

        if (rl.isKeyPressed(.enter)) frames_counter = 0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText(rl.textSubtext(message, 0, @divTrunc(frames_counter, 10)), 210, 160, 20, .maroon);

        rl.drawText("PRESS [ENTER] to RESTART!", 240, 260, 20, .light_gray);
        rl.drawText("HOLD [SPACE] to SPEED UP!", 239, 300, 20, .light_gray);
    }
}
