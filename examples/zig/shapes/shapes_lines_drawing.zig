//! raylib [shapes] example - lines drawing
//!
//! Zig-API translation of examples/shapes/shapes_lines_drawing.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Robin (@RobinsAviary)

const rl = @import("raylib");
const rm = rl.math;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - lines drawing");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Hint text that shows before you click the screen
    var start_text = true;

    // The mouse's position on the previous frame
    var mouse_position_previous = rl.getMousePosition();

    // The canvas to draw lines on
    const canvas = try rl.loadRenderTexture(screen_width, screen_height);
    defer rl.unloadRenderTexture(canvas); // Unload the canvas render texture

    // The line's thickness
    var line_thickness: f32 = 8.0;
    // The lines hue (in HSV, from 0-360)
    var line_hue: f32 = 0.0;

    // Clear the canvas to the background color
    rl.beginTextureMode(canvas);
    rl.clearBackground(.ray_white);
    rl.endTextureMode();

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Disable the hint text once the user clicks
        if (rl.isMouseButtonPressed(.left) and start_text) start_text = false;

        // Clear the canvas when the user middle-clicks
        if (rl.isMouseButtonPressed(.middle)) {
            rl.beginTextureMode(canvas);
            rl.clearBackground(.ray_white);
            rl.endTextureMode();
        }

        // Store whether the left and right buttons are down
        const left_button_down = rl.isMouseButtonDown(.left);
        const right_button_down = rl.isMouseButtonDown(.right);

        if (left_button_down or right_button_down) {
            // The color for the line
            var draw_color: rl.Color = .white;

            if (left_button_down) {
                // Increase the hue value by the distance our cursor has moved since the last frame (divided by 3)
                line_hue += rm.vector2Distance(mouse_position_previous, rl.getMousePosition()) / 3.0;

                // While the hue is >=360, subtract it to bring it down into the range 0-360
                // This is more visually accurate than resetting to zero
                while (line_hue >= 360.0) line_hue -= 360.0;

                // Create the final color
                draw_color = rl.colorFromHSV(line_hue, 1.0, 1.0);
            } else if (right_button_down) draw_color = .ray_white; // Use the background color as an "eraser"

            // Draw the line onto the canvas
            rl.beginTextureMode(canvas);
            defer rl.endTextureMode();

            // Circles act as "caps", smoothing corners
            rl.drawCircleV(mouse_position_previous, line_thickness / 2.0, draw_color);
            rl.drawCircleV(rl.getMousePosition(), line_thickness / 2.0, draw_color);
            rl.drawLineEx(mouse_position_previous, rl.getMousePosition(), line_thickness, draw_color);
        }

        // Update line thickness based on mousewheel
        line_thickness += rl.getMouseWheelMove();
        line_thickness = rm.clamp(line_thickness, 1.0, 500.0);

        // Update mouse's previous position
        mouse_position_previous = rl.getMousePosition();

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        // Draw the render texture to the screen, flipped vertically to make it appear top-side up
        const texture = canvas.texture;
        rl.drawTextureRec(texture, .{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(texture.width),
            .height = @floatFromInt(-texture.height),
        }, rm.vector2Zero(), .white);

        // Draw the preview circle
        if (!left_button_down) rl.drawCircleLinesV(rl.getMousePosition(), line_thickness / 2.0, .{ .r = 127, .g = 127, .b = 127, .a = 127 });

        // Draw the hint text
        if (start_text) rl.drawText("try clicking and dragging!", 275, 215, 20, .light_gray);
    }
}
