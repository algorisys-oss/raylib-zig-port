//! raylib [shapes] example - triangle strip
//!
//! Zig-API translation of examples/shapes/shapes_triangle_strip.c (raylib 6.2).
//! Example contributed by Jopestpe (@jopestpe)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jopestpe (@jopestpe)

const rl = @import("raylib");
const gui = @import("raygui");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - triangle strip");
    defer rl.closeWindow(); // Close window and OpenGL context

    var points: [122]rl.Vector2 = @splat(.{ .x = 0, .y = 0 });
    const center: rl.Vector2 = .{ .x = (screen_width / 2.0) - 125.0, .y = screen_height / 2.0 };
    var segments: f32 = 6.0;
    const inside_radius: f32 = 100.0;
    const outside_radius: f32 = 150.0;
    var outline = true;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const point_count: usize = @intFromFloat(segments);
        const angle_step = (360.0 / @as(f32, @floatFromInt(point_count))) * rl.deg2rad;

        for (0..point_count) |i| {
            const angle1 = @as(f32, @floatFromInt(i)) * angle_step;
            points[2 * i] = .{ .x = center.x + @cos(angle1) * inside_radius, .y = center.y + @sin(angle1) * inside_radius };
            const angle2 = angle1 + angle_step / 2.0;
            points[2 * i + 1] = .{ .x = center.x + @cos(angle2) * outside_radius, .y = center.y + @sin(angle2) * outside_radius };
        }

        points[point_count * 2] = points[0];
        points[point_count * 2 + 1] = points[1];

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        for (0..point_count) |i| {
            const a = points[i * 2];
            const b = points[i * 2 + 1];
            const c = points[i * 2 + 2];
            const d = points[i * 2 + 3];

            const angle1 = @as(f32, @floatFromInt(i)) * angle_step;
            rl.drawTriangle(c, b, a, rl.colorFromHSV(angle1 * rl.rad2deg, 1.0, 1.0));
            rl.drawTriangle(d, b, c, rl.colorFromHSV((angle1 + angle_step / 2) * rl.rad2deg, 1.0, 1.0));

            if (outline) {
                rl.drawTriangleLines(a, b, c, .black);
                rl.drawTriangleLines(c, b, d, .black);
            }
        }

        rl.drawLine(580, 0, 580, rl.getScreenHeight(), .{ .r = 218, .g = 218, .b = 218, .a = 255 });
        rl.drawRectangle(580, 0, rl.getScreenWidth(), rl.getScreenHeight(), .{ .r = 232, .g = 232, .b = 232, .a = 255 });

        // Draw GUI controls
        _ = gui.sliderBar(.{ .x = 640, .y = 40, .width = 120, .height = 20 }, "Segments", rl.textFormat("{d:.0}", .{segments}), &segments, 6.0, 60.0);
        _ = gui.checkBox(.{ .x = 640, .y = 70, .width = 20, .height = 20 }, "Outline", &outline);

        rl.drawFPS(10, 10);
    }
}
