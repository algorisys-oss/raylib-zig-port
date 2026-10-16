//! raylib [shapes] example - ring drawing
//!
//! Zig-API translation of examples/shapes/shapes_ring_drawing.c (raylib 6.2).
//! Example contributed by Vlad Adrian (@demizdor) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2018-2025 Vlad Adrian (@demizdor) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const gui = @import("raygui");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - ring drawing");
    defer rl.closeWindow(); // Close window and OpenGL context

    const center: rl.Vector2 = .{
        .x = @as(f32, @floatFromInt(rl.getScreenWidth() - 300)) / 2.0,
        .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
    };

    var inner_radius: f32 = 80.0;
    var outer_radius: f32 = 190.0;

    var start_angle: f32 = 0.0;
    var end_angle: f32 = 360.0;
    var segments: f32 = 0.0;

    var draw_ring = true;
    var draw_ring_lines = false;
    var draw_circle_lines = false;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // NOTE: All variables update happens inside GUI control functions

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawLine(500, 0, 500, rl.getScreenHeight(), rl.fade(.light_gray, 0.6));
        rl.drawRectangle(500, 0, rl.getScreenWidth() - 500, rl.getScreenHeight(), rl.fade(.light_gray, 0.3));

        const segment_count: i32 = @intFromFloat(segments);
        if (draw_ring) rl.drawRing(center, inner_radius, outer_radius, start_angle, end_angle, segment_count, rl.fade(.maroon, 0.3));
        if (draw_ring_lines) rl.drawRingLines(center, inner_radius, outer_radius, start_angle, end_angle, segment_count, rl.fade(.black, 0.4));
        if (draw_circle_lines) rl.drawCircleSectorLines(center, outer_radius, start_angle, end_angle, segment_count, rl.fade(.black, 0.4));

        // Draw GUI controls
        _ = gui.sliderBar(.{ .x = 600, .y = 40, .width = 120, .height = 20 }, "StartAngle", rl.textFormat("{d:.2}", .{start_angle}), &start_angle, -450, 450);
        _ = gui.sliderBar(.{ .x = 600, .y = 70, .width = 120, .height = 20 }, "EndAngle", rl.textFormat("{d:.2}", .{end_angle}), &end_angle, -450, 450);

        _ = gui.sliderBar(.{ .x = 600, .y = 140, .width = 120, .height = 20 }, "InnerRadius", rl.textFormat("{d:.2}", .{inner_radius}), &inner_radius, 0, 100);
        _ = gui.sliderBar(.{ .x = 600, .y = 170, .width = 120, .height = 20 }, "OuterRadius", rl.textFormat("{d:.2}", .{outer_radius}), &outer_radius, 0, 200);

        _ = gui.sliderBar(.{ .x = 600, .y = 240, .width = 120, .height = 20 }, "Segments", rl.textFormat("{d:.2}", .{segments}), &segments, 0, 100);

        _ = gui.checkBox(.{ .x = 600, .y = 320, .width = 20, .height = 20 }, "Draw Ring", &draw_ring);
        _ = gui.checkBox(.{ .x = 600, .y = 350, .width = 20, .height = 20 }, "Draw RingLines", &draw_ring_lines);
        _ = gui.checkBox(.{ .x = 600, .y = 380, .width = 20, .height = 20 }, "Draw CircleLines", &draw_circle_lines);

        const min_segments: i32 = @intFromFloat(@ceil((end_angle - start_angle) / 90));
        const manual = segments >= @as(f32, @floatFromInt(min_segments));
        rl.drawText(rl.textFormat("MODE: {s}", .{if (manual) "MANUAL" else "AUTO"}), 600, 270, 10, if (manual) .maroon else .dark_gray);

        rl.drawFPS(10, 10);
    }
}
