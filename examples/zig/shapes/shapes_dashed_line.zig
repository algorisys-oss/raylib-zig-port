//! raylib [shapes] example - dashed line
//!
//! Zig-API translation of examples/shapes/shapes_dashed_line.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Luís Almeida (@luis605)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - dashed line");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Line Properties
    const line_start_position: rl.Vector2 = .{ .x = 20.0, .y = 50.0 };
    var dash_length: f32 = 25.0;
    var blank_length: f32 = 15.0;

    // Color selection
    const line_colors = [_]rl.Color{ .red, .orange, .gold, .green, .blue, .violet, .pink, .black };
    var color_index: usize = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const line_end_position = rl.getMousePosition(); // Line endpoint follows the mouse

        // Change Dash Length (UP/DOWN arrows)
        if (rl.isKeyDown(.up)) dash_length += 1.0;
        if (rl.isKeyDown(.down) and dash_length > 1.0) dash_length -= 1.0;

        // Change Space Length (LEFT/RIGHT arrows)
        if (rl.isKeyDown(.right)) blank_length += 1.0;
        if (rl.isKeyDown(.left) and blank_length > 1.0) blank_length -= 1.0;

        // Cycle through colors ('C' key)
        if (rl.isKeyPressed(.c)) color_index = (color_index + 1) % line_colors.len;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw the dashed line with the current properties
        rl.drawLineDashed(line_start_position, line_end_position, @intFromFloat(dash_length), @intFromFloat(blank_length), line_colors[color_index]);

        // Draw UI and Instructions
        rl.drawRectangle(5, 5, 265, 95, rl.fade(.sky_blue, 0.5));
        rl.drawRectangleLines(5, 5, 265, 95, .blue);

        rl.drawText("CONTROLS:", 15, 15, 10, .black);
        rl.drawText("UP/DOWN: Change Dash Length", 15, 35, 10, .black);
        rl.drawText("LEFT/RIGHT: Change Space Length", 15, 55, 10, .black);
        rl.drawText("C: Cycle Color", 15, 75, 10, .black);

        rl.drawText(rl.textFormat("Dash: {d:.0} | Space: {d:.0}", .{ dash_length, blank_length }), 15, 115, 10, .dark_gray);

        rl.drawFPS(screen_width - 80, 10);
    }
}
