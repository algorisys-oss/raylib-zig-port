//! raylib [shapes] example - starfield effect
//!
//! Zig-API translation of examples/shapes/shapes_starfield_effect.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 JP Mortiboys (@themushroompirates)

const rl = @import("raylib");
const rm = rl.math;

const star_count = 420;

const screen_width = 800;
const screen_height = 450;

/// A star with a random position, at the start of its life (z = 1)
fn randomStar() rl.Vector3 {
    const x: f32 = @floatFromInt(rl.getRandomValue(-screen_width / 2, screen_width / 2));
    const y: f32 = @floatFromInt(rl.getRandomValue(-screen_height / 2, screen_height / 2));
    return .{ .x = x, .y = y, .z = 1.0 };
}

pub fn main() void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - starfield effect");
    defer rl.closeWindow(); // Close window and OpenGL context

    const bg_color = rl.colorLerp(.dark_blue, .black, 0.69);

    // Speed at which we fly forward
    var speed: f32 = 10.0 / 9.0;

    // We're either drawing lines or circles
    var draw_lines = true;

    // Setup the stars with a random position
    var stars: [star_count]rl.Vector3 = undefined;
    for (&stars) |*star| star.* = randomStar();
    var stars_screen_pos: [star_count]rl.Vector2 = @splat(.{ .x = 0, .y = 0 });

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Change speed based on mouse
        const mouse_move = rl.getMouseWheelMove();
        if (@as(i32, @intFromFloat(mouse_move)) != 0) speed += 2.0 * mouse_move / 9.0;
        if (speed < 0.0) {
            speed = 0.1;
        } else if (speed > 2.0) speed = 2.0;

        // Toggle lines / points with space bar
        if (rl.isKeyPressed(.space)) draw_lines = !draw_lines;

        const dt = rl.getFrameTime();
        for (&stars, &stars_screen_pos) |*star, *screen_pos| {
            // Update star's timer
            star.z -= dt * speed;

            // Calculate the screen position
            screen_pos.* = .{
                .x = screen_width * 0.5 + star.x / star.z,
                .y = screen_height * 0.5 + star.y / star.z,
            };

            // If the star is too old, or offscreen, it dies and we make a new random one
            if (star.z < 0.0 or screen_pos.x < 0 or screen_pos.y < 0.0 or
                screen_pos.x > screen_width or screen_pos.y > screen_height)
            {
                star.* = randomStar();
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(bg_color);

        for (stars, stars_screen_pos) |star, screen_pos| {
            if (draw_lines) {
                // Get the time a little while ago for this star, but clamp it
                const t = rm.clamp(star.z + 1.0 / 32.0, 0.0, 1.0);

                // If it's different enough from the current time, we proceed
                // (compared in double precision, as the C `1e-3` literal is a double)
                if (@as(f64, t - star.z) > 1e-3) {
                    // Calculate the screen position of the old point
                    const start_pos: rl.Vector2 = .{
                        .x = screen_width * 0.5 + star.x / t,
                        .y = screen_height * 0.5 + star.y / t,
                    };

                    // Draw a line connecting the old point to the current point
                    rl.drawLineV(start_pos, screen_pos, .ray_white);
                }
            } else {
                // Make the radius grow as the star ages
                const radius = rm.lerp(star.z, 1.0, 5.0);

                // Draw the circle
                rl.drawCircleV(screen_pos, radius, .ray_white);
            }
        }

        rl.drawText(rl.textFormat("[MOUSE WHEEL] Current Speed: {d:.0}", .{9.0 * speed / 2.0}), 10, 40, 20, .ray_white);
        rl.drawText(rl.textFormat("[SPACE] Current draw mode: {s}", .{if (draw_lines) "Lines" else "Circles"}), 10, 70, 20, .ray_white);

        rl.drawFPS(10, 10);
    }
}
