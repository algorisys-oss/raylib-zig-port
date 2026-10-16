//! raylib [shapes] example - rounded rectangle drawing
//!
//! Zig-API translation of examples/shapes/shapes_rounded_rectangle_drawing.c (raylib 6.2).
//! Example contributed by Vlad Adrian (@demizdor) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2018-2025 Vlad Adrian (@demizdor) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const gui = @import("raygui");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - rounded rectangle drawing");
    defer rl.closeWindow(); // Close window and OpenGL context

    var roundness: f32 = 0.2;
    var width: f32 = 200.0;
    var height: f32 = 100.0;
    var segments: f32 = 0.0;
    var line_thick: f32 = 1.0;

    var draw_rect = false;
    var draw_rounded_rect = true;
    var draw_rounded_lines = false;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
        const rec: rl.Rectangle = .{
            .x = (screen_w - width - 250) / 2,
            .y = (screen_h - height) / 2.0,
            .width = width,
            .height = height,
        };

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawLine(560, 0, 560, rl.getScreenHeight(), rl.fade(.light_gray, 0.6));
        rl.drawRectangle(560, 0, rl.getScreenWidth() - 500, rl.getScreenHeight(), rl.fade(.light_gray, 0.3));

        const segment_count: i32 = @intFromFloat(segments);
        if (draw_rect) rl.drawRectangleRec(rec, rl.fade(.gold, 0.6));
        if (draw_rounded_rect) rl.drawRectangleRounded(rec, roundness, segment_count, rl.fade(.maroon, 0.2));
        if (draw_rounded_lines) rl.drawRectangleRoundedLinesEx(rec, roundness, segment_count, line_thick, rl.fade(.maroon, 0.4));

        // Draw GUI controls
        _ = gui.sliderBar(.{ .x = 640, .y = 40, .width = 105, .height = 20 }, "Width", rl.textFormat("{d:.2}", .{width}), &width, 0, screen_w - 300);
        _ = gui.sliderBar(.{ .x = 640, .y = 70, .width = 105, .height = 20 }, "Height", rl.textFormat("{d:.2}", .{height}), &height, 0, screen_h - 50);
        _ = gui.sliderBar(.{ .x = 640, .y = 140, .width = 105, .height = 20 }, "Roundness", rl.textFormat("{d:.2}", .{roundness}), &roundness, 0.0, 1.0);
        _ = gui.sliderBar(.{ .x = 640, .y = 170, .width = 105, .height = 20 }, "Thickness", rl.textFormat("{d:.2}", .{line_thick}), &line_thick, 0, 20);
        _ = gui.sliderBar(.{ .x = 640, .y = 240, .width = 105, .height = 20 }, "Segments", rl.textFormat("{d:.2}", .{segments}), &segments, 0, 60);

        _ = gui.checkBox(.{ .x = 640, .y = 320, .width = 20, .height = 20 }, "DrawRoundedRect", &draw_rounded_rect);
        _ = gui.checkBox(.{ .x = 640, .y = 350, .width = 20, .height = 20 }, "DrawRoundedLines", &draw_rounded_lines);
        _ = gui.checkBox(.{ .x = 640, .y = 380, .width = 20, .height = 20 }, "DrawRect", &draw_rect);

        const manual = segments >= 4;
        rl.drawText(rl.textFormat("MODE: {s}", .{if (manual) "MANUAL" else "AUTO"}), 640, 280, 10, if (manual) .maroon else .dark_gray);

        rl.drawFPS(10, 10);
    }
}
