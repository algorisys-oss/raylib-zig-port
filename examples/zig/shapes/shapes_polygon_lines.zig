//! raylib [shapes] example - polygon lines
//!
//! Zig-API translation of examples/shapes/shapes_polygon_lines.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Matthew Roush (@MatthewRoush)

const std = @import("std");
const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - polygon lines");
    defer rl.closeWindow(); // Close window and OpenGL context

    var thick: i32 = 2;
    var rotation: f32 = 0.0;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.up)) thick += 1;
        if (rl.isKeyPressed(.down)) thick -= 1;

        thick = std.math.clamp(thick, 1, 60);

        rotation += (360.0 / 10.0) * rl.getFrameTime();

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText(rl.textFormat("thick = {d}", .{thick}), 10, 280, 20, .lime);

        // The square and circle outlines in the top left should match
        // The fist pair of outlines are drawn using `DrawRectangleLinesEx()` and `DrawCircleLinesEx()`
        // The second pair are drawn using `DrawPolyLinesEx()` with parameters that should visually match the first pair

        rl.drawText("These should look identical!", 10, 10, 20, .maroon);

        const line_thick: f32 = @floatFromInt(thick);

        // Outline pair 1
        rl.drawRectangle(10, 40, 50, 50, .light_gray);
        rl.drawRectangleLinesEx(.{ .x = 10, .y = 40, .width = 50, .height = 50 }, line_thick, .red);

        rl.drawCircle(95, 65, 25, .light_gray);
        rl.drawCircleLinesEx(.{ .x = 95, .y = 65 }, 25, line_thick, .red);

        rl.drawText("DrawRectangleLinesEx() and DrawCircleLinesEx()", 130, 60, 10, .black);

        // Outline pair 2
        rl.drawPoly(.{ .x = 35, .y = 125 }, 4, 35.355, 45, .light_gray);
        rl.drawPolyLinesEx(.{ .x = 35, .y = 125 }, 4, 35.355, 45, line_thick, .red);

        rl.drawPoly(.{ .x = 95, .y = 125 }, 36, 25, 0, .light_gray);
        rl.drawPolyLinesEx(.{ .x = 95, .y = 125 }, 36, 25, 0, line_thick, .red);

        rl.drawText("DrawPolyLinesEx()", 130, 120, 10, .black);

        // Some other shapes, all of these outlines should have the same looking thickness
        const centers = [_]rl.Vector2{
            .{ .x = 290, .y = 220 }, .{ .x = 430, .y = 220 }, .{ .x = 570, .y = 220 }, .{ .x = 710, .y = 220 },
            .{ .x = 290, .y = 360 }, .{ .x = 430, .y = 360 }, .{ .x = 570, .y = 360 }, .{ .x = 710, .y = 360 },
        };
        for (centers, 3..) |center, sides| {
            rl.drawPoly(center, @intCast(sides), 60, rotation, .light_gray);
            rl.drawPolyLinesEx(center, @intCast(sides), 60, rotation, line_thick, .blue);
        }
    }
}
