//! raylib [shapes] example - logo raylib anim
//!
//! Zig-API translation of examples/shapes/shapes_logo_raylib_anim.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

/// Animation states (state machine).
const State = enum {
    blinking, // Small box blinking
    top_left_bars, // Top and left bars growing
    bottom_right_bars, // Bottom and right bars growing
    letters, // Letters appearing (one by one)
    replay, // Reset and replay
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - logo raylib anim");
    defer rl.closeWindow(); // Close window and OpenGL context

    const logo_position_x = screen_width / 2 - 128;
    const logo_position_y = screen_height / 2 - 128;

    var frames_counter: i32 = 0;
    var letters_count: i32 = 0;

    var top_side_rec_width: i32 = 16;
    var left_side_rec_height: i32 = 16;

    var bottom_side_rec_width: i32 = 16;
    var right_side_rec_height: i32 = 16;

    var state: State = .blinking; // Tracking animation states (State Machine)
    var alpha: f32 = 1.0; // Useful for fading

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        switch (state) {
            .blinking => {
                frames_counter += 1;

                if (frames_counter == 120) {
                    state = .top_left_bars;
                    frames_counter = 0; // Reset counter... will be used later...
                }
            },
            .top_left_bars => {
                top_side_rec_width += 4;
                left_side_rec_height += 4;

                if (top_side_rec_width == 256) state = .bottom_right_bars;
            },
            .bottom_right_bars => {
                bottom_side_rec_width += 4;
                right_side_rec_height += 4;

                if (bottom_side_rec_width == 256) state = .letters;
            },
            .letters => {
                frames_counter += 1;

                if (frames_counter >= 12) { // Every 12 frames, one more letter!
                    letters_count += 1;
                    frames_counter = 0;
                }

                if (letters_count >= 10) { // When all letters have appeared, just fade out everything
                    alpha -= 0.02;

                    if (alpha <= 0.0) {
                        alpha = 0.0;
                        state = .replay;
                    }
                }
            },
            .replay => {
                if (rl.isKeyPressed(.r)) {
                    frames_counter = 0;
                    letters_count = 0;

                    top_side_rec_width = 16;
                    left_side_rec_height = 16;

                    bottom_side_rec_width = 16;
                    right_side_rec_height = 16;

                    alpha = 1.0;
                    state = .blinking; // Return to State 0
                }
            },
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        switch (state) {
            .blinking => {
                if (@mod(@divTrunc(frames_counter, 15), 2) == 1) rl.drawRectangle(logo_position_x, logo_position_y, 16, 16, .black);
            },
            .top_left_bars => {
                rl.drawRectangle(logo_position_x, logo_position_y, top_side_rec_width, 16, .black);
                rl.drawRectangle(logo_position_x, logo_position_y, 16, left_side_rec_height, .black);
            },
            .bottom_right_bars => {
                rl.drawRectangle(logo_position_x, logo_position_y, top_side_rec_width, 16, .black);
                rl.drawRectangle(logo_position_x, logo_position_y, 16, left_side_rec_height, .black);

                rl.drawRectangle(logo_position_x + 240, logo_position_y, 16, right_side_rec_height, .black);
                rl.drawRectangle(logo_position_x, logo_position_y + 240, bottom_side_rec_width, 16, .black);
            },
            .letters => {
                const black = rl.fade(.black, alpha);
                rl.drawRectangle(logo_position_x, logo_position_y, top_side_rec_width, 16, black);
                rl.drawRectangle(logo_position_x, logo_position_y + 16, 16, left_side_rec_height - 32, black);

                rl.drawRectangle(logo_position_x + 240, logo_position_y + 16, 16, right_side_rec_height - 32, black);
                rl.drawRectangle(logo_position_x, logo_position_y + 240, bottom_side_rec_width, 16, black);

                const center_x = @divTrunc(rl.getScreenWidth(), 2);
                const center_y = @divTrunc(rl.getScreenHeight(), 2);
                rl.drawRectangle(center_x - 112, center_y - 112, 224, 224, rl.fade(.ray_white, alpha));

                rl.drawText(rl.textSubtext("raylib", 0, letters_count), center_x - 44, center_y + 48, 50, black);
            },
            .replay => rl.drawText("[R] REPLAY", 340, 200, 20, .gray),
        }
    }
}
