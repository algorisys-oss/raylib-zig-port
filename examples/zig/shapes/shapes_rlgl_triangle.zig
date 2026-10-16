//! raylib [shapes] example - rlgl triangle
//!
//! Zig-API translation of examples/shapes/shapes_rlgl_triangle.c (raylib 6.2).
//! Example contributed by Robin (@RobinsAviary) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Robin (@RobinsAviary)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - rlgl triangle");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Starting postions and rendered triangle positions
    const starting_positions = [3]rl.Vector2{ .{ .x = 400.0, .y = 150.0 }, .{ .x = 300.0, .y = 300.0 }, .{ .x = 500.0, .y = 300.0 } };
    var triangle_positions = starting_positions;

    // Currently selected vertex, null means none
    var triangle_index: ?usize = null;
    var lines_mode = false;
    const handle_radius: f32 = 8.0;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.space)) lines_mode = !lines_mode;

        // Check selected vertex
        for (triangle_positions, 0..) |position, i| {
            // If the mouse is within the handle circle
            if (rl.checkCollisionPointCircle(rl.getMousePosition(), position, handle_radius) and
                rl.isMouseButtonDown(.left))
            {
                triangle_index = i;
                break;
            }
        }

        // If the user has selected a vertex, offset it by the mouse's delta this frame
        if (triangle_index) |i| {
            const position = &triangle_positions[i];

            const mouse_delta = rl.getMouseDelta();
            position.x += mouse_delta.x;
            position.y += mouse_delta.y;
        }

        // Reset index on release
        if (rl.isMouseButtonReleased(.left)) triangle_index = null;

        // Enable/disable backface culling (2-sided triangles, slower to render)
        if (rl.isKeyPressed(.left)) rl.gl.enableBackfaceCulling();
        if (rl.isKeyPressed(.right)) rl.gl.disableBackfaceCulling();

        // Reset triangle vertices to starting positions and reset backface culling
        if (rl.isKeyPressed(.r)) {
            triangle_positions = starting_positions;

            rl.gl.enableBackfaceCulling();
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        const p = triangle_positions;
        if (lines_mode) {
            // Draw triangle with lines
            rl.gl.begin(rl.gl.lines);
            // Three lines, six points
            // Define color for next vertex
            rl.gl.color4ub(255, 0, 0, 255);
            // Define vertex
            rl.gl.vertex2f(p[0].x, p[0].y);
            rl.gl.color4ub(0, 255, 0, 255);
            rl.gl.vertex2f(p[1].x, p[1].y);

            rl.gl.color4ub(0, 255, 0, 255);
            rl.gl.vertex2f(p[1].x, p[1].y);
            rl.gl.color4ub(0, 0, 255, 255);
            rl.gl.vertex2f(p[2].x, p[2].y);

            rl.gl.color4ub(0, 0, 255, 255);
            rl.gl.vertex2f(p[2].x, p[2].y);
            rl.gl.color4ub(255, 0, 0, 255);
            rl.gl.vertex2f(p[0].x, p[0].y);
            rl.gl.end();
        } else {
            // Draw triangle as a triangle
            rl.gl.begin(rl.gl.triangles);
            // One triangle, three points
            // Define color for next vertex
            rl.gl.color4ub(255, 0, 0, 255);
            // Define vertex
            rl.gl.vertex2f(p[0].x, p[0].y);
            rl.gl.color4ub(0, 255, 0, 255);
            rl.gl.vertex2f(p[1].x, p[1].y);
            rl.gl.color4ub(0, 0, 255, 255);
            rl.gl.vertex2f(p[2].x, p[2].y);
            rl.gl.end();
        }

        // Render the vertex handles, reacting to mouse movement/input
        for (triangle_positions, 0..) |position, i| {
            // Draw handle fill focused by mouse
            if (rl.checkCollisionPointCircle(rl.getMousePosition(), position, handle_radius))
                rl.drawCircleV(position, handle_radius, rl.colorAlpha(.dark_gray, 0.5));

            // Draw handle fill selected
            if (triangle_index == i) rl.drawCircleV(position, handle_radius, .dark_gray);

            // Draw handle outline
            rl.drawCircleLinesV(position, handle_radius, .black);
        }

        // Draw controls
        rl.drawText("SPACE: Toggle lines mode", 10, 10, 20, .dark_gray);
        rl.drawText("LEFT-RIGHT: Toggle backface culling", 10, 40, 20, .dark_gray);
        rl.drawText("MOUSE: Click and drag vertex points", 10, 70, 20, .dark_gray);
        rl.drawText("R: Reset triangle to start positions", 10, 100, 20, .dark_gray);
    }
}
