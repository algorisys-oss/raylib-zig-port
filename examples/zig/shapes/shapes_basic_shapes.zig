//! raylib [shapes] example - basic shapes
//!
//! Zig-API translation of examples/shapes/shapes_basic_shapes.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - basic shapes");
    defer rl.closeWindow(); // Close window and OpenGL context

    var rotation: f32 = 0.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rotation += 0.2;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("some basic shapes available on raylib", 20, 20, 20, .dark_gray);

        // Circle shapes and lines
        rl.drawCircle(screen_width / 5, 120, 35, .dark_blue);
        rl.drawCircleGradient(.{ .x = screen_width / 5.0, .y = 220.0 }, 60, .green, .sky_blue);
        rl.drawCircleLines(screen_width / 5, 340, 80, .dark_blue);
        rl.drawEllipse(screen_width / 5, 120, 25, 20, .yellow);
        rl.drawEllipseLines(screen_width / 5, 120, 30, 25, .yellow);

        // Rectangle shapes and lines
        rl.drawRectangle(screen_width / 4 * 2 - 60, 100, 120, 60, .red);
        rl.drawRectangleGradientH(screen_width / 4 * 2 - 90, 170, 180, 130, .maroon, .gold);
        rl.drawRectangleLines(screen_width / 4 * 2 - 40, 320, 80, 60, .orange); // NOTE: Uses QUADS internally, not lines

        // Triangle shapes and lines
        const tri_x = screen_width / 4.0 * 3.0;
        rl.drawTriangle(
            .{ .x = tri_x, .y = 80.0 },
            .{ .x = tri_x - 60.0, .y = 150.0 },
            .{ .x = tri_x + 60.0, .y = 150.0 },
            .violet,
        );
        rl.drawTriangleLines(
            .{ .x = tri_x, .y = 160.0 },
            .{ .x = tri_x - 20.0, .y = 230.0 },
            .{ .x = tri_x + 20.0, .y = 230.0 },
            .dark_blue,
        );

        // Polygon shapes and lines
        const poly_center: rl.Vector2 = .{ .x = tri_x, .y = 330 };
        rl.drawPoly(poly_center, 6, 80, rotation, .brown);
        rl.drawPolyLines(poly_center, 6, 90, rotation, .brown);
        rl.drawPolyLinesEx(poly_center, 6, 85, rotation, 6, .beige);

        // NOTE: We draw all LINES based shapes together to optimize internal drawing,
        // this way, all LINES are rendered in a single draw pass
        rl.drawLine(18, 42, screen_width - 18, 42, .black);
    }
}
