//! raylib [core] example - random values
//!
//! Zig-API translation of examples/core/core_random_values.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - random values");
    defer rl.closeWindow(); // Close window and OpenGL context

    // rl.setRandomSeed(0xaabbccff); // Set a custom random seed if desired, by default: "time(NULL)"

    var rand_value = rl.getRandomValue(-8, 5); // Get a random integer number between -8 and 5 (both included)

    var frames_counter: u32 = 0; // Variable used to count frames

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        frames_counter += 1;

        // Every two seconds (120 frames) a new random value is generated
        if ((frames_counter / 120) % 2 == 1) {
            rand_value = rl.getRandomValue(-8, 5);
            frames_counter = 0;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("Every 2 seconds a new random value is generated:", 130, 100, 20, .maroon);

        rl.drawText(rl.textFormat("{d}", .{rand_value}), 360, 180, 80, .light_gray);
    }
}
