//! raylib [shapes] example - easings box
//!
//! Zig-API translation of examples/shapes/shapes_easings_box.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const reasings = @import("reasings"); // Required for easing functions

fn initialBox() rl.Rectangle {
    return .{ .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0, .y = -100, .width = 100, .height = 100 };
}

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - easings box");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Box variables to be animated with easings
    var rec = initialBox();
    var rotation: f32 = 0.0;
    var alpha: f32 = 1.0;

    var state: u32 = 0;
    var frames_counter: i32 = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
        switch (state) {
            0 => { // Move box down to center of screen
                frames_counter += 1;

                // NOTE: Remember that 3rd parameter of easing function refers to
                // desired value variation, do not confuse it with expected final value!
                const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
                rec.y = reasings.easeElasticOut(@floatFromInt(frames_counter), -100, screen_h / 2.0 + 100, 120);

                if (frames_counter >= 120) {
                    frames_counter = 0;
                    state = 1;
                }
            },
            1 => { // Scale box to an horizontal bar
                frames_counter += 1;
                rec.height = reasings.easeBounceOut(@floatFromInt(frames_counter), 100, -90, 120);
                rec.width = reasings.easeBounceOut(@floatFromInt(frames_counter), 100, screen_w, 120);

                if (frames_counter >= 120) {
                    frames_counter = 0;
                    state = 2;
                }
            },
            2 => { // Rotate horizontal bar rectangle
                frames_counter += 1;
                rotation = reasings.easeQuadOut(@floatFromInt(frames_counter), 0.0, 270.0, 240);

                if (frames_counter >= 240) {
                    frames_counter = 0;
                    state = 3;
                }
            },
            3 => { // Increase bar size to fill all screen
                frames_counter += 1;
                rec.height = reasings.easeCircOut(@floatFromInt(frames_counter), 10, screen_w, 120);

                if (frames_counter >= 120) {
                    frames_counter = 0;
                    state = 4;
                }
            },
            4 => { // Fade out animation
                frames_counter += 1;
                alpha = reasings.easeSineOut(@floatFromInt(frames_counter), 1.0, -1.0, 160);

                if (frames_counter >= 160) {
                    frames_counter = 0;
                    state = 5;
                }
            },
            else => {},
        }

        // Reset animation at any moment
        if (rl.isKeyPressed(.space)) {
            rec = initialBox();
            rotation = 0.0;
            alpha = 1.0;
            state = 0;
            frames_counter = 0;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawRectanglePro(rec, .{ .x = rec.width / 2, .y = rec.height / 2 }, rotation, rl.fade(.black, alpha));

        rl.drawText("PRESS [SPACE] TO RESET BOX ANIMATION!", 10, rl.getScreenHeight() - 25, 20, .light_gray);
    }
}
