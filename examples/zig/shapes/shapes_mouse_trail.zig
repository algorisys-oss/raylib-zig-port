//! raylib [shapes] example - Draw a mouse trail (position history)
//!
//! Zig-API translation of examples/shapes/shapes_mouse_trail.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Balamurugan R (@Bala050814)

const std = @import("std");
const rl = @import("raylib");

/// The maximum number of positions to store in the trail
const max_trail_length = 30;

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - mouse trail");
    defer rl.closeWindow(); // Close window and OpenGL context

    // History of mouse positions (our fixed-size queue), newest first
    var trail_positions: [max_trail_length]rl.Vector2 = @splat(.{ .x = 0, .y = 0 });

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_position = rl.getMousePosition();

        // Shift all existing positions backward by one slot in the array
        // The last element (the oldest position) is dropped
        std.mem.copyBackwards(rl.Vector2, trail_positions[1..], trail_positions[0 .. max_trail_length - 1]);

        // Store the new, current mouse position at the start of the array (Index 0)
        trail_positions[0] = mouse_position;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        // Draw the trail by looping through the history array
        for (trail_positions, 0..) |position, i| {
            // Ensure we skip drawing if the array hasn't been fully filled on startup
            if (position.x == 0.0 and position.y == 0.0) continue;

            // Calculate relative trail strength (ratio is near 1.0 for new, near 0.0 for old)
            const ratio = @as(f32, @floatFromInt(max_trail_length - i)) / max_trail_length;

            // Fade effect: oldest positions are more transparent
            // Fade (color, alpha) - alpha is 0.5 to 1.0 based on ratio
            const trail_color = rl.fade(.sky_blue, ratio * 0.5 + 0.5);

            // Size effect: oldest positions are smaller
            const trail_radius = 15.0 * ratio;

            rl.drawCircleV(position, trail_radius, trail_color);
        }

        // Draw a distinct white circle for the current mouse position (Index 0)
        rl.drawCircleV(mouse_position, 15.0, .white);

        rl.drawText("Move the mouse to see the trail effect!", 10, screen_height - 30, 20, .light_gray);
    }
}
