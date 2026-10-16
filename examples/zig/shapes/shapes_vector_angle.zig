//! raylib [shapes] example - vector angle
//!
//! Zig-API translation of examples/shapes/shapes_vector_angle.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const rm = rl.math;

const AngleMode = enum {
    between_vectors, // Vector2Angle()
    line_to_horizontal, // Vector2LineAngle()
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - vector angle");
    defer rl.closeWindow(); // Close window and OpenGL context

    const v0: rl.Vector2 = .{ .x = screen_width / 2.0, .y = screen_height / 2.0 };
    var v1 = rm.vector2Add(v0, .{ .x = 100.0, .y = 80.0 });

    var angle: f32 = 0.0; // Angle in degrees
    var angle_mode: AngleMode = .between_vectors;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const start_angle: f32 = switch (angle_mode) {
            .between_vectors => -rm.vector2LineAngle(v0, v1) * rl.rad2deg,
            .line_to_horizontal => 0.0,
        };

        const v2 = rl.getMousePosition();

        if (rl.isKeyPressed(.space)) angle_mode = switch (angle_mode) {
            .between_vectors => .line_to_horizontal,
            .line_to_horizontal => .between_vectors,
        };

        if (angle_mode == .between_vectors and rl.isMouseButtonDown(.right)) v1 = rl.getMousePosition();

        switch (angle_mode) {
            .between_vectors => {
                // Calculate angle between two vectors, considering a common origin (v0)
                const v1_normal = rm.vector2Normalize(rm.vector2Subtract(v1, v0));
                const v2_normal = rm.vector2Normalize(rm.vector2Subtract(v2, v0));

                angle = rm.vector2Angle(v1_normal, v2_normal) * rl.rad2deg;
            },
            .line_to_horizontal => {
                // Calculate angle defined by a two vectors line, in reference to horizontal line
                angle = rm.vector2LineAngle(v0, v2) * rl.rad2deg;
            },
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        switch (angle_mode) {
            .between_vectors => {
                rl.drawText("MODE 0: Angle between V1 and V2", 10, 10, 20, .black);
                rl.drawText("Right Click to Move V2", 10, 30, 20, .dark_gray);

                rl.drawLineEx(v0, v1, 2.0, .black);
                rl.drawLineEx(v0, v2, 2.0, .red);

                rl.drawCircleSector(v0, 40.0, start_angle, start_angle + angle, 32, rl.fade(.green, 0.6));
            },
            .line_to_horizontal => {
                rl.drawText("MODE 1: Angle formed by line V1 to V2", 10, 10, 20, .black);

                rl.drawLine(0, screen_height / 2, screen_width, screen_height / 2, .light_gray);
                rl.drawLineEx(v0, v2, 2.0, .red);

                rl.drawCircleSector(v0, 40.0, start_angle, start_angle - angle, 32, rl.fade(.green, 0.6));
            },
        }

        const v0_x: i32 = @intFromFloat(v0.x);
        const v0_y: i32 = @intFromFloat(v0.y);
        rl.drawText("v0", v0_x, v0_y, 10, .dark_gray);

        switch (angle_mode) {
            .between_vectors => {
                // If the line from v0 to v1 would overlap the text, move it's position up 10
                const dy = rm.vector2Subtract(v0, v1).y;
                const v1_x: i32 = @intFromFloat(v1.x);
                const v1_y: i32 = @intFromFloat(v1.y);
                if (dy > 0.0) rl.drawText("v1", v1_x, v1_y - 10, 10, .dark_gray);
                if (dy < 0.0) rl.drawText("v1", v1_x, v1_y, 10, .dark_gray);
            },
            // Use v1 to emphasize the horizontal line
            .line_to_horizontal => rl.drawText("v1", v0_x + 40, v0_y, 10, .dark_gray),
        }

        // position adjusted by -10 so it isn't hidden by cursor
        rl.drawText("v2", @as(i32, @intFromFloat(v2.x)) - 10, @as(i32, @intFromFloat(v2.y)) - 10, 10, .dark_gray);

        rl.drawText("Press SPACE to change MODE", 460, 10, 20, .dark_gray);
        rl.drawText(rl.textFormat("ANGLE: {d:.2}", .{angle}), 10, 70, 20, .lime);
    }
}
