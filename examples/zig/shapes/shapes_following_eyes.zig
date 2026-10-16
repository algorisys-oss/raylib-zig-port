//! raylib [shapes] example - following eyes
//!
//! Zig-API translation of examples/shapes/shapes_following_eyes.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

/// Keep the iris inside the sclera: if it would leave, clamp it to the rim
/// along the direction from the sclera center.
fn clampIris(iris: rl.Vector2, sclera: rl.Vector2, max_distance: f32) rl.Vector2 {
    if (rl.checkCollisionPointCircle(iris, sclera, max_distance)) return iris;

    const angle = std.math.atan2(iris.y - sclera.y, iris.x - sclera.x);
    return .{
        .x = sclera.x + max_distance * @cos(angle),
        .y = sclera.y + max_distance * @sin(angle),
    };
}

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - following eyes");
    defer rl.closeWindow(); // Close window and OpenGL context

    const half_width = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0;
    const half_height = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0;

    const sclera_left_position: rl.Vector2 = .{ .x = half_width - 100.0, .y = half_height };
    const sclera_right_position: rl.Vector2 = .{ .x = half_width + 100.0, .y = half_height };
    const sclera_radius: f32 = 80;
    const iris_radius: f32 = 24;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const iris_left_position = clampIris(rl.getMousePosition(), sclera_left_position, sclera_radius - iris_radius);
        const iris_right_position = clampIris(rl.getMousePosition(), sclera_right_position, sclera_radius - iris_radius);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawCircleV(sclera_left_position, sclera_radius, .light_gray);
        rl.drawCircleV(iris_left_position, iris_radius, .brown);
        rl.drawCircleV(iris_left_position, 10, .black);

        rl.drawCircleV(sclera_right_position, sclera_radius, .light_gray);
        rl.drawCircleV(iris_right_position, iris_radius, .dark_green);
        rl.drawCircleV(iris_right_position, 10, .black);

        rl.drawFPS(10, 10);
    }
}
