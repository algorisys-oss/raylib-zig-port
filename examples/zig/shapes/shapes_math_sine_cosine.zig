//! raylib [shapes] example - math sine cosine
//!
//! Zig-API translation of examples/shapes/shapes_math_sine_cosine.c (raylib 6.2).
//! Example contributed by Jopestpe (@jopestpe) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jopestpe (@jopestpe)

const rl = @import("raylib");
const gui = @import("raygui");

// libm tanf(), as in the C example (keeps the tangent bit-identical)
extern "c" fn tanf(x: f32) f32;

// Wave points for sine/cosine visualization
const wave_points = 36;

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - math sine cosine");
    defer rl.closeWindow(); // Close window and OpenGL context

    var sine_points: [wave_points]rl.Vector2 = undefined;
    var cos_points: [wave_points]rl.Vector2 = undefined;
    const center: rl.Vector2 = .{ .x = (screen_width / 2.0) - 30.0, .y = screen_height / 2.0 };
    const start: rl.Rectangle = .{ .x = 20.0, .y = screen_height - 120.0, .width = 200.0, .height = 100.0 };
    const radius: f32 = 130.0;
    var angle: f32 = 0.0;
    var pause = false;

    for (&sine_points, &cos_points, 0..) |*sine_point, *cos_point, i| {
        const t = @as(f32, @floatFromInt(i)) / (wave_points - 1);
        const current_angle = t * 360.0 * rl.deg2rad;
        sine_point.* = .{ .x = start.x + t * start.width, .y = start.y + start.height / 2.0 - @sin(current_angle) * (start.height / 2.0) };
        cos_point.* = .{ .x = start.x + t * start.width, .y = start.y + start.height / 2.0 - @cos(current_angle) * (start.height / 2.0) };
    }

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const angle_rad = angle * rl.deg2rad;
        const cos_rad = @cos(angle_rad);
        const sin_rad = @sin(angle_rad);

        const point: rl.Vector2 = .{ .x = center.x + cos_rad * radius, .y = center.y - sin_rad * radius };
        const limit_min: rl.Vector2 = .{ .x = center.x - radius, .y = center.y - radius };
        const limit_max: rl.Vector2 = .{ .x = center.x + radius, .y = center.y + radius };

        const complementary = 90.0 - angle;
        const supplementary = 180.0 - angle;
        const explementary = 360.0 - angle;

        const tangent = rl.math.clamp(tanf(angle_rad), -10.0, 10.0);
        const cotangent = if (@abs(tangent) > 0.001) rl.math.clamp(1.0 / tangent, -radius, radius) else 0.0;
        const tangent_point: rl.Vector2 = .{ .x = center.x + radius, .y = center.y - tangent * radius };
        const cotangent_point: rl.Vector2 = .{ .x = center.x + cotangent * radius, .y = center.y - radius };

        angle = rl.math.wrap(angle + @as(f32, if (!pause) 1.0 else 0.0), 0.0, 360.0);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Cotangent (orange)
        rl.drawLineEx(.{ .x = center.x, .y = limit_min.y }, .{ .x = cotangent_point.x, .y = limit_min.y }, 2.0, .orange);
        rl.drawLineDashed(center, cotangent_point, 10, 4, .orange);

        // Side background
        rl.drawLine(580, 0, 580, rl.getScreenHeight(), .{ .r = 218, .g = 218, .b = 218, .a = 255 });
        rl.drawRectangle(580, 0, rl.getScreenWidth(), rl.getScreenHeight(), .{ .r = 232, .g = 232, .b = 232, .a = 255 });

        // Base circle and axes
        rl.drawCircleLinesV(center, radius, .gray);
        rl.drawLineEx(.{ .x = center.x, .y = limit_min.y }, .{ .x = center.x, .y = limit_max.y }, 1.0, .gray);
        rl.drawLineEx(.{ .x = limit_min.x, .y = center.y }, .{ .x = limit_max.x, .y = center.y }, 1.0, .gray);

        // Wave graph axes
        rl.drawLineEx(.{ .x = start.x, .y = start.y }, .{ .x = start.x, .y = start.y + start.height }, 2.0, .gray);
        rl.drawLineEx(.{ .x = start.x + start.width, .y = start.y }, .{ .x = start.x + start.width, .y = start.y + start.height }, 2.0, .gray);
        rl.drawLineEx(.{ .x = start.x, .y = start.y + start.height / 2 }, .{ .x = start.x + start.width, .y = start.y + start.height / 2 }, 2.0, .gray);

        // Wave graph axis labels
        const start_x: i32 = @intFromFloat(start.x);
        const start_y: i32 = @intFromFloat(start.y);
        const start_width: i32 = @intFromFloat(start.width);
        const start_height: i32 = @intFromFloat(start.height);
        rl.drawText("1", start_x - 8, start_y, 6, .gray);
        rl.drawText("0", start_x - 8, start_y + @divTrunc(start_height, 2) - 6, 6, .gray);
        rl.drawText("-1", start_x - 12, start_y + start_height - 8, 6, .gray);
        rl.drawText("0", start_x - 2, start_y + start_height + 4, 6, .gray);
        rl.drawText("360", start_x + start_width - 8, start_y + start_height + 4, 6, .gray);

        // Sine (red - vertical)
        rl.drawLineEx(.{ .x = center.x, .y = center.y }, .{ .x = center.x, .y = point.y }, 2.0, .red);
        rl.drawLineDashed(.{ .x = point.x, .y = center.y }, .{ .x = point.x, .y = point.y }, 10, 4, .red);
        rl.drawText(rl.textFormat("Sine {d:.2}", .{sin_rad}), 640, 190, 6, .red);
        rl.drawCircleV(.{ .x = start.x + (angle / 360.0) * start.width, .y = start.y + ((-sin_rad + 1) * start.height / 2.0) }, 4.0, .red);
        rl.drawSplineLinear(&sine_points, 1.0, .red);

        // Cosine (blue - horizontal)
        rl.drawLineEx(.{ .x = center.x, .y = center.y }, .{ .x = point.x, .y = center.y }, 2.0, .blue);
        rl.drawLineDashed(.{ .x = center.x, .y = point.y }, .{ .x = point.x, .y = point.y }, 10, 4, .blue);
        rl.drawText(rl.textFormat("Cosine {d:.2}", .{cos_rad}), 640, 210, 6, .blue);
        rl.drawCircleV(.{ .x = start.x + (angle / 360.0) * start.width, .y = start.y + ((-cos_rad + 1) * start.height / 2.0) }, 4.0, .blue);
        rl.drawSplineLinear(&cos_points, 1.0, .blue);

        // Tangent (purple)
        rl.drawLineEx(.{ .x = limit_max.x, .y = center.y }, .{ .x = limit_max.x, .y = tangent_point.y }, 2.0, .purple);
        rl.drawLineDashed(center, tangent_point, 10, 4, .purple);
        rl.drawText(rl.textFormat("Tangent {d:.2}", .{tangent}), 640, 230, 6, .purple);

        // Cotangent (orange)
        rl.drawText(rl.textFormat("Cotangent {d:.2}", .{cotangent}), 640, 250, 6, .orange);

        // Complementary angle (beige)
        rl.drawCircleSectorLines(center, radius * 0.6, -angle, -90.0, 36, .beige);
        rl.drawText(rl.textFormat("Complementary  {d:.0}°", .{complementary}), 640, 150, 6, .beige);

        // Supplementary angle (darkblue)
        rl.drawCircleSectorLines(center, radius * 0.5, -angle, -180.0, 36, .dark_blue);
        rl.drawText(rl.textFormat("Supplementary  {d:.0}°", .{supplementary}), 640, 130, 6, .dark_blue);

        // Explementary angle (pink)
        rl.drawCircleSectorLines(center, radius * 0.4, -angle, -360.0, 36, .pink);
        rl.drawText(rl.textFormat("Explementary  {d:.0}°", .{explementary}), 640, 170, 6, .pink);

        // Current angle - arc (lime), radius (black), endpoint (black)
        rl.drawCircleSectorLines(center, radius * 0.7, -angle, 0.0, 36, .lime);
        rl.drawLineEx(.{ .x = center.x, .y = center.y }, point, 2.0, .black);
        rl.drawCircleV(point, 4.0, .black);

        // Draw GUI controls
        gui.setStyle(.label, gui.ControlProperty.text_color_normal, rl.colorToInt(.gray));
        _ = gui.toggle(.{ .x = 640, .y = 70, .width = 120, .height = 20 }, "Pause", &pause);
        gui.setStyle(.label, gui.ControlProperty.text_color_normal, rl.colorToInt(.lime));
        _ = gui.sliderBar(.{ .x = 640, .y = 40, .width = 120, .height = 20 }, "Angle", rl.textFormat("{d:.0}°", .{angle}), &angle, 0.0, 360.0);

        // Angle values panel
        _ = gui.groupBox(.{ .x = 620, .y = 110, .width = 140, .height = 170 }, "Angle Values");

        rl.drawFPS(10, 10);
    }
}
