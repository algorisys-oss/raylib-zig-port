//! raylib [shapes] example - math angle rotation
//!
//! Zig-API translation of examples/shapes/shapes_math_angle_rotation.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Kris (@krispy-snacc)

const rl = @import("raylib");

/// Predefined angles for fixed lines, with a gradient color green -> orange -> blue -> magenta.
const fixed_lines = [_]struct { angle: i32, color: rl.Color }{
    .{ .angle = 0, .color = .green },
    .{ .angle = 30, .color = .orange },
    .{ .angle = 60, .color = .blue },
    .{ .angle = 90, .color = .magenta },
};

pub fn main() void {
    // Initialization
    const screen_width = 720;
    const screen_height = 400;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - math angle rotation");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    const center: rl.Vector2 = .{ .x = screen_width / 2.0, .y = screen_height / 2.0 };
    const line_length: f32 = 150.0;

    var total_angle: f32 = 0.0; // Animated rotation angle

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        total_angle += 1.0; // degrees per frame
        if (total_angle >= 360.0) total_angle -= 360.0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);

        rl.drawText("Fixed angles + rotating line", 10, 10, 20, .light_gray);

        // Draw fixed-angle lines with colorful gradient
        for (fixed_lines) |line| {
            const rad = @as(f32, @floatFromInt(line.angle)) * rl.deg2rad;
            const end: rl.Vector2 = .{
                .x = center.x + @cos(rad) * line_length,
                .y = center.y + @sin(rad) * line_length,
            };

            rl.drawLineEx(center, end, 5.0, line.color);

            // Draw angle label slightly offset along the line
            const text_pos: rl.Vector2 = .{
                .x = center.x + @cos(rad) * (line_length + 20),
                .y = center.y + @sin(rad) * (line_length + 20),
            };
            rl.drawText(rl.textFormat("{d}°", .{line.angle}), @intFromFloat(text_pos.x), @intFromFloat(text_pos.y), 20, line.color);
        }

        // Draw animated rotating line with changing color
        const anim_rad = total_angle * rl.deg2rad;
        const anim_end: rl.Vector2 = .{
            .x = center.x + @cos(anim_rad) * line_length,
            .y = center.y + @sin(anim_rad) * line_length,
        };

        // Cycle through HSV colors for animated line
        const anim_col = rl.colorFromHSV(@rem(total_angle, 360.0), 0.8, 0.9);
        rl.drawLineEx(center, anim_end, 5.0, anim_col);
    }
}
