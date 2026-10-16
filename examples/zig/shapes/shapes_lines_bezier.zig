//! raylib [shapes] example - lines bezier
//!
//! Zig-API translation of examples/shapes/shapes_lines_bezier.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - lines bezier");
    defer rl.closeWindow(); // Close window and OpenGL context

    var start_point: rl.Vector2 = .{ .x = 30, .y = 30 };
    var end_point: rl.Vector2 = .{ .x = screen_width - 30, .y = screen_height - 30 };
    var move_start_point = false;
    var move_end_point = false;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse = rl.getMousePosition();

        if (rl.checkCollisionPointCircle(mouse, start_point, 10.0) and rl.isMouseButtonDown(.left)) {
            move_start_point = true;
        } else if (rl.checkCollisionPointCircle(mouse, end_point, 10.0) and rl.isMouseButtonDown(.left)) {
            move_end_point = true;
        }

        if (move_start_point) {
            start_point = mouse;
            if (rl.isMouseButtonReleased(.left)) move_start_point = false;
        }

        if (move_end_point) {
            end_point = mouse;
            if (rl.isMouseButtonReleased(.left)) move_end_point = false;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("MOVE START-END POINTS WITH MOUSE", 15, 20, 20, .gray);

        // Draw line Cubic Bezier, in-out interpolation (easing), no control points
        rl.drawLineBezier(start_point, end_point, 4.0, .blue);

        // Draw start-end spline circles with some details
        const start_hover = rl.checkCollisionPointCircle(mouse, start_point, 10.0);
        const end_hover = rl.checkCollisionPointCircle(mouse, end_point, 10.0);
        rl.drawCircleV(start_point, if (start_hover) 14.0 else 8.0, if (move_start_point) .red else .blue);
        rl.drawCircleV(end_point, if (end_hover) 14.0 else 8.0, if (move_end_point) .red else .blue);
    }
}
