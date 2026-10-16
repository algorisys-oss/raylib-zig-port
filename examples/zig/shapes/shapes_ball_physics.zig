//! raylib [shapes] example - ball physics
//!
//! Zig-API translation of examples/shapes/shapes_ball_physics.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 David Buzatto (@davidbuzatto)

const std = @import("std");
const rl = @import("raylib");
const rm = rl.math;

const max_balls = 5000; // Maximum quantity of balls

const Ball = struct {
    position: rl.Vector2,
    speed: rl.Vector2,
    prev_position: rl.Vector2 = .{ .x = 0, .y = 0 },
    radius: f32,
    friction: f32 = 0.99,
    elasticity: f32 = 0.9,
    color: rl.Color,
    grabbed: bool = false,
};

fn randomFloat(min: i32, max: i32) f32 {
    return @floatFromInt(rl.getRandomValue(min, max));
}

fn randomByte() u8 {
    return @intCast(rl.getRandomValue(0, 255));
}

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - ball physics");
    defer rl.closeWindow(); // Close window and OpenGL context

    const ball_storage = try std.heap.c_allocator.alloc(Ball, max_balls);
    defer std.heap.c_allocator.free(ball_storage);

    // Init first ball in the array
    ball_storage[0] = .{
        .position = .{
            .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
            .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
        },
        .speed = .{ .x = 200, .y = 200 },
        .radius = 40,
        .color = .blue,
    };

    var ball_count: usize = 1;
    var grabbed_ball: ?*Ball = null; // The ball currently grabbed
    var press_offset: rl.Vector2 = .{ .x = 0, .y = 0 }; // Mouse press offset relative to the grabbed ball

    var gravity: f32 = 100; // World gravity

    var window_position = rl.getWindowPosition();

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const delta = rl.getFrameTime();
        const mouse_pos = rl.getMousePosition();

        // Checks if a ball was grabbed (topmost first)
        if (rl.isMouseButtonPressed(.left)) {
            var i = ball_count;
            while (i > 0) {
                i -= 1;
                const ball = &ball_storage[i];
                press_offset.x = mouse_pos.x - ball.position.x;
                press_offset.y = mouse_pos.y - ball.position.y;

                // If the distance between the ball position and the mouse press position
                // is less than or equal to the ball radius, the event occurred inside the ball
                if (std.math.hypot(@as(f64, press_offset.x), @as(f64, press_offset.y)) <= ball.radius) {
                    ball.grabbed = true;
                    grabbed_ball = ball;
                    break;
                }
            }
        }

        // Releases any ball the was grabbed
        if (rl.isMouseButtonReleased(.left)) {
            if (grabbed_ball) |ball| {
                ball.grabbed = false;
                grabbed_ball = null;
            }
        }

        // Creates a new ball
        if (rl.isMouseButtonPressed(.right) or (rl.isKeyDown(.left_control) and rl.isMouseButtonDown(.right))) {
            if (ball_count < max_balls) {
                const speed_x = randomFloat(-300, 300);
                const speed_y = randomFloat(-300, 300);
                const radius = 20.0 + randomFloat(0, 30);
                const r = randomByte();
                const g = randomByte();
                const b = randomByte();
                ball_storage[ball_count] = .{
                    .position = mouse_pos,
                    .speed = .{ .x = speed_x, .y = speed_y },
                    .radius = radius,
                    .color = .{ .r = r, .g = g, .b = b, .a = 255 },
                };
                ball_count += 1;
            }
        }

        const balls = ball_storage[0..ball_count];

        // Get window position change for shaking
        const window_position_delta = rm.vector2Subtract(window_position, rl.getWindowPosition());

        if (rm.vector2Length(window_position_delta) > 5.0) {
            for (balls) |*ball| {
                if (!ball.grabbed) ball.speed = rm.vector2Add(ball.speed, rm.vector2Scale(window_position_delta, 10.0));
            }
        }

        // Shake balls
        if (rl.isMouseButtonPressed(.middle)) {
            for (balls) |*ball| {
                if (!ball.grabbed) {
                    const x = randomFloat(-2000, 2000);
                    const y = randomFloat(-2000, 2000);
                    ball.speed = .{ .x = x, .y = y };
                }
            }
        }

        // Changes gravity
        gravity += rl.getMouseWheelMove() * 5;

        // Updates each ball state
        for (balls) |*ball| {
            if (!ball.grabbed) {
                // Ball repositioning using the velocity
                ball.position.x += ball.speed.x * delta;
                ball.position.y += ball.speed.y * delta;

                // Does the ball hit the screen right boundary?
                if (ball.position.x + ball.radius >= screen_width) {
                    ball.position.x = screen_width - ball.radius; // Ball repositioning
                    ball.speed.x = -ball.speed.x * ball.elasticity; // Elasticity makes the ball lose 10% of its velocity on hit
                }
                // Does the ball hit the screen left boundary?
                else if (ball.position.x - ball.radius <= 0) {
                    ball.position.x = ball.radius;
                    ball.speed.x = -ball.speed.x * ball.elasticity;
                }

                // The same for y axis
                if (ball.position.y + ball.radius >= screen_height) {
                    ball.position.y = screen_height - ball.radius;
                    ball.speed.y = -ball.speed.y * ball.elasticity;
                } else if (ball.position.y - ball.radius <= 0) {
                    ball.position.y = ball.radius;
                    ball.speed.y = -ball.speed.y * ball.elasticity;
                }

                // Friction makes the ball lose 1% of its velocity each frame
                ball.speed.x = ball.speed.x * ball.friction;
                // Gravity affects only the y axis
                ball.speed.y = ball.speed.y * ball.friction + gravity;
            } else {
                // Ball repositioning using the mouse position
                ball.position.x = mouse_pos.x - press_offset.x;
                ball.position.y = mouse_pos.y - press_offset.y;

                // While the ball is grabbed, recalculates its velocity
                ball.speed.x = (ball.position.x - ball.prev_position.x) / delta;
                ball.speed.y = (ball.position.y - ball.prev_position.y) / delta;
                ball.prev_position = ball.position;
            }
        }

        window_position = rl.getWindowPosition();

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        for (balls) |ball| {
            rl.drawCircleV(ball.position, ball.radius, ball.color);
            rl.drawCircleLinesV(ball.position, ball.radius, .black);
        }

        rl.drawText("grab a ball by pressing with the mouse and throw it by releasing", 10, 10, 10, .dark_gray);
        rl.drawText("right click to create new balls (keep left control pressed to create a lot)", 10, 30, 10, .dark_gray);
        rl.drawText("use mouse wheel to change gravity", 10, 50, 10, .dark_gray);
        rl.drawText("middle click to shake", 10, 70, 10, .dark_gray);
        rl.drawText(rl.textFormat("BALL COUNT: {d}", .{ball_count}), 10, rl.getScreenHeight() - 70, 20, .black);
        rl.drawText(rl.textFormat("GRAVITY: {d:.2}", .{gravity}), 10, rl.getScreenHeight() - 40, 20, .black);
    }
}
