//! raylib [shapes] example - easings rectangles
//!
//! Zig-API translation of examples/shapes/shapes_easings_rectangles.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const reasings = @import("reasings"); // Required for easing functions

const recs_width = 50;
const recs_height = 50;

const max_recs_x = 800 / recs_width;
const max_recs_y = 450 / recs_height;

const play_time_in_frames = 240; // At 60 fps = 4 seconds

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - easings rectangles");
    defer rl.closeWindow(); // Close window and OpenGL context

    var recs: [max_recs_x * max_recs_y]rl.Rectangle = undefined;
    for (&recs, 0..) |*rec, i| {
        const x: f32 = @floatFromInt(i % max_recs_x);
        const y: f32 = @floatFromInt(i / max_recs_x);
        rec.* = .{
            .x = recs_width / 2.0 + recs_width * x,
            .y = recs_height / 2.0 + recs_height * y,
            .width = recs_width,
            .height = recs_height,
        };
    }

    var rotation: f32 = 0.0;
    var frames_counter: i32 = 0;
    var finished = false; // Rectangles animation state: playing or finished

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (!finished) {
            frames_counter += 1;
            const t: f32 = @floatFromInt(frames_counter);

            for (&recs) |*rec| {
                rec.height = @max(reasings.easeCircOut(t, recs_height, -recs_height, play_time_in_frames), 0);
                rec.width = @max(reasings.easeCircOut(t, recs_width, -recs_width, play_time_in_frames), 0);

                if (rec.height == 0 and rec.width == 0) finished = true; // Finish playing

                rotation = reasings.easeLinearIn(t, 0.0, 360.0, play_time_in_frames);
            }
        } else if (rl.isKeyPressed(.space)) {
            // When animation has finished, press space to restart
            frames_counter = 0;

            for (&recs) |*rec| {
                rec.height = recs_height;
                rec.width = recs_width;
            }

            finished = false;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        if (!finished) {
            for (recs) |rec| {
                rl.drawRectanglePro(rec, .{ .x = rec.width / 2, .y = rec.height / 2 }, rotation, .red);
            }
        } else rl.drawText("PRESS [SPACE] TO PLAY AGAIN!", 240, 200, 20, .gray);
    }
}
