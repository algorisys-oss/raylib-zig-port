//! raylib [shapes] example - easings ball
//!
//! Zig-API translation of examples/shapes/shapes_easings_ball.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const reasings = @import("reasings"); // Required for easing functions

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - easings ball");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Ball variable value to be animated with easings
    var ball_position_x: i32 = -100;
    var ball_radius: i32 = 20;
    var ball_alpha: f32 = 0.0;

    var state: u32 = 0;
    var frames_counter: i32 = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        switch (state) {
            0 => { // Move ball position X with easing
                frames_counter += 1;
                ball_position_x = @intFromFloat(reasings.easeElasticOut(@floatFromInt(frames_counter), -100, screen_width / 2.0 + 100, 120));

                if (frames_counter >= 120) {
                    frames_counter = 0;
                    state = 1;
                }
            },
            1 => { // Increase ball radius with easing
                frames_counter += 1;
                ball_radius = @intFromFloat(reasings.easeElasticIn(@floatFromInt(frames_counter), 20, 500, 200));

                if (frames_counter >= 200) {
                    frames_counter = 0;
                    state = 2;
                }
            },
            2 => { // Change ball alpha with easing (background color blending)
                frames_counter += 1;
                ball_alpha = reasings.easeCubicOut(@floatFromInt(frames_counter), 0.0, 1.0, 200);

                if (frames_counter >= 200) {
                    frames_counter = 0;
                    state = 3;
                }
            },
            3 => { // Reset state to play again
                if (rl.isKeyPressed(.enter)) {
                    // Reset required variables to play again
                    ball_position_x = -100;
                    ball_radius = 20;
                    ball_alpha = 0.0;
                    state = 0;
                }
            },
            else => {},
        }

        if (rl.isKeyPressed(.r)) frames_counter = 0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        if (state >= 2) rl.drawRectangle(0, 0, screen_width, screen_height, .green);
        rl.drawCircle(ball_position_x, 200, @floatFromInt(ball_radius), rl.fade(.red, 1.0 - ball_alpha));

        if (state == 3) rl.drawText("PRESS [ENTER] TO PLAY AGAIN!", 240, 200, 20, .black);
    }
}
