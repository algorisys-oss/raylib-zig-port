//! raylib [shapes] example - outlines thickness
//!
//! Zig-API translation of examples/shapes/shapes_outlines_thickness.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const gui = @import("raygui");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - outlines thickness");
    defer rl.closeWindow(); // Close window and OpenGL context

    var thick: f32 = 5.0;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        _ = gui.sliderBar(.{ .x = 290, .y = 50, .width = 220, .height = 24 }, "Thickness", rl.textFormat("{d:.2}", .{thick}), &thick, -30.0, 30.0);

        rl.drawRectangle(35, 180, 220, 220, .light_gray);
        rl.drawRectangleLinesEx(.{ .x = 35, .y = 180, .width = 220, .height = 220 }, thick, .blue);
        rl.drawText("DrawRectangleLinesEx()", 35, 160, 10, .black);

        rl.drawRectangleRounded(.{ .x = 290, .y = 180, .width = 220, .height = 220 }, 0.2, 9, .light_gray);
        rl.drawRectangleRoundedLinesEx(.{ .x = 290, .y = 180, .width = 220, .height = 220 }, 0.2, 9, thick, .blue);
        rl.drawText("DrawRectangleRoundedLinesEx()", 290, 160, 10, .black);

        rl.drawCircle(655, 290, 110, .light_gray);
        rl.drawCircleLinesEx(.{ .x = 655, .y = 290 }, 110, thick, .blue);
        rl.drawText("DrawCircleLinesEx()", 545, 160, 10, .black);
    }
}
