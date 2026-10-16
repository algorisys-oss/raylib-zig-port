//! raylib [core] example - basic screen manager
//!
//! Zig-API translation of examples/core/core_basic_screen_manager.c (raylib 6.2).
//! NOTE: This example illustrates a very simple screen manager based on a states machines
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2021-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const GameScreen = enum { logo, title, gameplay, ending };

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - basic screen manager");
    defer rl.closeWindow(); // Close window and OpenGL context

    var current_screen: GameScreen = .logo;

    // TODO: Initialize all required variables and load all required data here!

    var frames_counter: i32 = 0; // Useful to count frames

    rl.setTargetFPS(60); // Set desired framerate (frames-per-second)

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const advance = rl.isKeyPressed(.enter) or rl.isGestureDetected(.tap);
        switch (current_screen) {
            .logo => {
                // TODO: Update LOGO screen variables here!

                frames_counter += 1; // Count frames

                // Wait for 2 seconds (120 frames) before jumping to TITLE screen
                if (frames_counter > 120) current_screen = .title;
            },
            // TODO: Update TITLE screen variables here!
            // Press enter to change to GAMEPLAY screen
            .title => if (advance) {
                current_screen = .gameplay;
            },
            // TODO: Update GAMEPLAY screen variables here!
            // Press enter to change to ENDING screen
            .gameplay => if (advance) {
                current_screen = .ending;
            },
            // TODO: Update ENDING screen variables here!
            // Press enter to return to TITLE screen
            .ending => if (advance) {
                current_screen = .title;
            },
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        switch (current_screen) {
            .logo => {
                // TODO: Draw LOGO screen here!
                rl.drawText("LOGO SCREEN", 20, 20, 40, .light_gray);
                rl.drawText("WAIT for 2 SECONDS...", 290, 220, 20, .gray);
            },
            .title => {
                // TODO: Draw TITLE screen here!
                rl.drawRectangle(0, 0, screen_width, screen_height, .green);
                rl.drawText("TITLE SCREEN", 20, 20, 40, .dark_green);
                rl.drawText("PRESS ENTER or TAP to JUMP to GAMEPLAY SCREEN", 120, 220, 20, .dark_green);
            },
            .gameplay => {
                // TODO: Draw GAMEPLAY screen here!
                rl.drawRectangle(0, 0, screen_width, screen_height, .purple);
                rl.drawText("GAMEPLAY SCREEN", 20, 20, 40, .maroon);
                rl.drawText("PRESS ENTER or TAP to JUMP to ENDING SCREEN", 130, 220, 20, .maroon);
            },
            .ending => {
                // TODO: Draw ENDING screen here!
                rl.drawRectangle(0, 0, screen_width, screen_height, .blue);
                rl.drawText("ENDING SCREEN", 20, 20, 40, .dark_blue);
                rl.drawText("PRESS ENTER or TAP to RETURN to TITLE SCREEN", 120, 220, 20, .dark_blue);
            },
        }
    }

    // TODO: Unload all loaded data (textures, fonts, audio) here!
}
