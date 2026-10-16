//! raylib [shapes] example - bouncing ball
//!
//! Zig-API translation of examples/shapes/shapes_bouncing_ball.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - bouncing ball");
    defer rl.closeWindow(); // Close window and OpenGL context

    var ball_position: rl.Vector2 = .{
        .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
        .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
    };
    var ball_speed: rl.Vector2 = .{ .x = 5.0, .y = 4.0 };
    const ball_radius = 20;
    const gravity = 0.2;

    var use_gravity = true;
    var pause = false;
    var frames_counter: u32 = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.g)) use_gravity = !use_gravity;
        if (rl.isKeyPressed(.space)) pause = !pause;

        if (!pause) {
            ball_position.x += ball_speed.x;
            ball_position.y += ball_speed.y;

            if (use_gravity) ball_speed.y += gravity;

            // Check walls collision for bouncing
            const max_x: f32 = @floatFromInt(rl.getScreenWidth() - ball_radius);
            const max_y: f32 = @floatFromInt(rl.getScreenHeight() - ball_radius);
            if (ball_position.x >= max_x or ball_position.x <= ball_radius) ball_speed.x *= -1.0;
            if (ball_position.y >= max_y or ball_position.y <= ball_radius) ball_speed.y *= -0.95;
        } else frames_counter += 1;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawCircleV(ball_position, ball_radius, .maroon);
        rl.drawText("PRESS SPACE to PAUSE BALL MOVEMENT", 10, rl.getScreenHeight() - 25, 20, .light_gray);

        if (use_gravity) {
            rl.drawText("GRAVITY: ON (Press G to disable)", 10, rl.getScreenHeight() - 50, 20, .dark_green);
        } else {
            rl.drawText("GRAVITY: OFF (Press G to enable)", 10, rl.getScreenHeight() - 50, 20, .red);
        }

        // On pause, we draw a blinking message
        if (pause and (frames_counter / 30) % 2 == 1) rl.drawText("PAUSED", 350, 200, 30, .gray);

        rl.drawFPS(10, 10);
    }
}
