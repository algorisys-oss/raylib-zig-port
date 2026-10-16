//! raylib [shapes] example - circle sector drawing
//!
//! Zig-API translation of examples/shapes/shapes_circle_sector_drawing.c (raylib 6.2).
//! Example contributed by Vlad Adrian (@demizdor) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2018-2025 Vlad Adrian (@demizdor) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const gui = @import("raygui");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - circle sector drawing");
    defer rl.closeWindow(); // Close window and OpenGL context

    const center: rl.Vector2 = .{
        .x = @as(f32, @floatFromInt(rl.getScreenWidth() - 300)) / 2.0,
        .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
    };

    var outer_radius: f32 = 180.0;
    var start_angle: f32 = 0.0;
    var end_angle: f32 = 180.0;
    var segments: f32 = 10.0;

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

        rl.drawCircleSector(center, outer_radius, start_angle, end_angle, @intFromFloat(segments), rl.fade(.maroon, 0.3));
        rl.drawCircleSectorLines(center, outer_radius, start_angle, end_angle, @intFromFloat(segments), rl.fade(.maroon, 0.6));

        // Draw GUI controls
        _ = gui.sliderBar(.{ .x = 600, .y = 40, .width = 120, .height = 20 }, "StartAngle", rl.textFormat("{d:.2}", .{start_angle}), &start_angle, 0, 720);
        _ = gui.sliderBar(.{ .x = 600, .y = 70, .width = 120, .height = 20 }, "EndAngle", rl.textFormat("{d:.2}", .{end_angle}), &end_angle, 0, 720);

        _ = gui.sliderBar(.{ .x = 600, .y = 140, .width = 120, .height = 20 }, "Radius", rl.textFormat("{d:.2}", .{outer_radius}), &outer_radius, 0, 200);
        _ = gui.sliderBar(.{ .x = 600, .y = 170, .width = 120, .height = 20 }, "Segments", rl.textFormat("{d:.2}", .{segments}), &segments, 0, 100);

        const min_segments = @trunc(@ceil((end_angle - start_angle) / 90));
        const manual = segments >= min_segments;
        rl.drawText(rl.textFormat("MODE: {s}", .{if (manual) "MANUAL" else "AUTO"}), 600, 200, 10, if (manual) .maroon else .dark_gray);

        rl.drawFPS(10, 10);
    }
}
