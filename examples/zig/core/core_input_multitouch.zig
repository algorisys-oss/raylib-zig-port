//! raylib [core] example - input multitouch
//!
//! Zig-API translation of examples/core/core_input_multitouch.c (raylib 6.2).
//! Example contributed by Berni (@Berni8k) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Berni (@Berni8k) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const max_touch_points = 10;

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - input multitouch");
    defer rl.closeWindow(); // Close window and OpenGL context

    var touch_positions: [max_touch_points]rl.Vector2 = @splat(.{ .x = 0, .y = 0 });

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Get the touch point count ( how many fingers are touching the screen ),
        // clamped to the maximum touch points allowed
        const touch_count: usize = @intCast(@min(rl.getTouchPointCount(), max_touch_points));
        const touches = touch_positions[0..touch_count];
        // Get touch points positions
        for (touches, 0..) |*position, i| position.* = rl.getTouchPosition(@intCast(i));

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        for (touches, 0..) |position, i| {
            // Make sure point is not (0, 0) as this means there is no touch for it
            if (position.x > 0 and position.y > 0) {
                // Draw circle and touch index number
                rl.drawCircleV(position, 34, .orange);
                const x: i32 = @intFromFloat(position.x);
                const y: i32 = @intFromFloat(position.y);
                rl.drawText(rl.textFormat("{d}", .{i}), x - 10, y - 70, 40, .black);
            }
        }

        rl.drawText("touch the screen at multiple locations to get multiple balls", 10, 10, 20, .dark_gray);
    }
}
