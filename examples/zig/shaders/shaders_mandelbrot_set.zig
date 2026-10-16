//! raylib [shaders] example - mandelbrot set
//!
//! Zig-API translation of examples/shaders/shaders_mandelbrot_set.c (raylib 6.2).
//! Example contributed by Jordi Santonja (@JordSant)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jordi Santonja (@JordSant)
//!
//! NOTE: Shaders used in this example are #version 330 (OpenGL 3.3).

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

// A few good interesting places: offset x, offset y, zoom
const points_of_interest = [_][3]f32{
    .{ -1.76826775, -0.00422996283, 28435.9238 },
    .{ 0.322004497, -0.0357099883, 56499.7266 },
    .{ -0.748880744, -0.0562955774, 9237.59082 },
    .{ -1.78385007, -0.0156200649, 14599.5283 },
    .{ -0.0985441282, -0.924688697, 26259.8535 },
    .{ 0.317785531, -0.0322612226, 29297.9258 },
};
// Keys [1 - 6] select the matching point of interest
const point_keys = [points_of_interest.len]rl.KeyboardKey{ .one, .two, .three, .four, .five, .six };

const screen_width = 800;
const screen_height = 450;
const zoom_speed: f32 = 1.01;
const offset_speed_mul: f32 = 2.0;
const starting_zoom: f32 = 0.6;
const starting_offset = [2]f32{ -0.5, 0.0 };

pub fn main() !void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - mandelbrot set");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Load mandelbrot set shader
    // NOTE: Defining null for vertex shader forces usage of internal default vertex shader
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/mandelbrot_set.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    // Create a RenderTexture2D to be used for render to texture
    const target = try rl.loadRenderTexture(rl.getScreenWidth(), rl.getScreenHeight());
    defer rl.unloadRenderTexture(target);

    // Offset and zoom to draw the mandelbrot set at. (centered on screen and default size)
    var offset = starting_offset;
    var zoom = starting_zoom;

    // Depending on the zoom the maximum number of iterations must be adapted to get more detail as we zoom in
    // The solution is not perfect, so a control has been added to increase/decrease the number of iterations with UP/DOWN keys
    var max_iterations: i32 = 333;
    var max_iterations_multiplier: f32 = 166.5;

    // Get variable (uniform) locations on the shader to connect with the program
    // NOTE: If uniform variable could not be found in the shader, function returns -1
    const zoom_loc = rl.getShaderLocation(shader, "zoom");
    const offset_loc = rl.getShaderLocation(shader, "offset");
    const max_iterations_loc = rl.getShaderLocation(shader, "maxIterations");

    // Upload the shader uniform values!
    rl.setShaderValue(shader, zoom_loc, &zoom, .float);
    rl.setShaderValue(shader, offset_loc, &offset, .vec2);
    rl.setShaderValue(shader, max_iterations_loc, &max_iterations, .int);

    var show_controls = true; // Show controls

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        var update_shader = false;

        // Press [1 - 6] to reset c to a point of interest
        for (point_keys, points_of_interest) |key, point| {
            if (rl.isKeyPressed(key)) {
                offset = .{ point[0], point[1] };
                zoom = point[2];
                update_shader = true;
                break;
            }
        }

        // If "R" is pressed, reset zoom and offset
        if (rl.isKeyPressed(.r)) {
            offset = starting_offset;
            zoom = starting_zoom;
            update_shader = true;
        }

        if (rl.isKeyPressed(.f1)) show_controls = !show_controls; // Toggle whether or not to show controls

        // Change number of max iterations with UP and DOWN keys
        // WARNING: Increasing the number of max iterations greatly impacts performance
        if (rl.isKeyPressed(.up)) {
            max_iterations_multiplier *= 1.4;
            update_shader = true;
        } else if (rl.isKeyPressed(.down)) {
            max_iterations_multiplier /= 1.4;
            update_shader = true;
        }

        // If either left or right button is pressed, zoom in/out
        if (rl.isMouseButtonDown(.left) or rl.isMouseButtonDown(.right)) {
            // Change zoom. If Mouse left -> zoom in. Mouse right -> zoom out
            zoom *= if (rl.isMouseButtonDown(.left)) zoom_speed else 1.0 / zoom_speed;

            const mouse_pos = rl.getMousePosition();

            // Find the velocity at which to change the camera. Take the distance of the mouse
            // From the center of the screen as the direction, and adjust magnitude based on the current zoom
            const offset_velocity: rl.Vector2 = .{
                .x = (mouse_pos.x / @as(f32, screen_width) - 0.5) * offset_speed_mul / zoom,
                .y = (mouse_pos.y / @as(f32, screen_height) - 0.5) * offset_speed_mul / zoom,
            };

            // Apply move velocity to camera
            offset[0] += rl.getFrameTime() * offset_velocity.x;
            offset[1] += rl.getFrameTime() * offset_velocity.y;

            update_shader = true;
        }

        // In case a parameter has been changed, update the shader values
        if (update_shader) {
            // As we zoom in, increase the number of max iterations to get more detail
            // Aproximate formula, but it works-ish
            max_iterations = @intFromFloat(@sqrt(2.0 * @sqrt(@abs(1.0 - @sqrt(37.5 * zoom)))) * max_iterations_multiplier);

            // Update the shader uniform values!
            rl.setShaderValue(shader, zoom_loc, &zoom, .float);
            rl.setShaderValue(shader, offset_loc, &offset, .vec2);
            rl.setShaderValue(shader, max_iterations_loc, &max_iterations, .int);
        }

        // Draw
        // Using a render texture to draw Mandelbrot set
        {
            rl.beginTextureMode(target); // Enable drawing to texture
            defer rl.endTextureMode();

            rl.clearBackground(.black); // Clear the render texture

            // Draw a rectangle in shader mode to be used as shader canvas
            // NOTE: Rectangle uses font white character texture coordinates,
            // So shader can not be applied here directly because input vertexTexCoord
            // Do not represent full screen coordinates (space where want to apply shader)
            rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), .black);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black); // Clear screen background

        // Draw the saved texture and rendered mandelbrot set with shader
        // NOTE: We do not invert texture on Y, already considered inside shader
        {
            rl.beginShaderMode(shader);
            defer rl.endShaderMode();

            // WARNING: If FLAG_WINDOW_HIGHDPI is enabled, HighDPI monitor scaling should be considered
            // When rendering the RenderTexture2D to fit in the HighDPI scaled Window
            rl.drawTextureEx(target.texture, .{ .x = 0.0, .y = 0.0 }, 0.0, 1.0, .white);
        }

        if (show_controls) {
            rl.drawText("Press Mouse buttons right/left to zoom in/out and move", 10, 15, 10, .ray_white);
            rl.drawText("Press F1 to toggle these controls", 10, 30, 10, .ray_white);
            rl.drawText("Press [1 - 6] to change point of interest", 10, 45, 10, .ray_white);
            rl.drawText("Press UP | DOWN to change number of iterations", 10, 60, 10, .ray_white);
            rl.drawText("Press R to recenter the camera", 10, 75, 10, .ray_white);
        }
    }
}
