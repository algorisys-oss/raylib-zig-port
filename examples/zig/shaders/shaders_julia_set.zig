//! raylib [shaders] example - julia set
//!
//! Zig-API translation of examples/shaders/shaders_julia_set.c (raylib 6.2).
//! Example contributed by Josh Colclough (@joshcol9232) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Josh Colclough (@joshcol9232) and Ramon Santamaria (@raysan5)
//!
//! NOTE: Shaders used in this example are #version 330 (OpenGL 3.3).

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

// A few good julia sets
const points_of_interest = [_][2]f32{
    .{ -0.348827, 0.607167 },
    .{ -0.786268, 0.169728 },
    .{ -0.8, 0.156 },
    .{ 0.285, 0.0 },
    .{ -0.835, -0.2321 },
    .{ -0.70176, -0.3842 },
};
// Keys [1 - 6] select the matching point of interest
const point_keys = [points_of_interest.len]rl.KeyboardKey{ .one, .two, .three, .four, .five, .six };

const screen_width = 800;
const screen_height = 450;
const zoom_speed: f32 = 1.01;
const offset_speed_mul: f32 = 2.0;
const starting_zoom: f32 = 0.75;

pub fn main() !void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - julia set");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Load julia set shader
    // NOTE: Defining null for vertex shader forces usage of internal default vertex shader
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/julia_set.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    // Create a RenderTexture2D to be used for render to texture
    const target = try rl.loadRenderTexture(rl.getScreenWidth(), rl.getScreenHeight());
    defer rl.unloadRenderTexture(target);

    // c constant to use in z^2 + c
    var c = points_of_interest[0];

    // Offset and zoom to draw the julia set at. (centered on screen and default size)
    var offset = [2]f32{ 0.0, 0.0 };
    var zoom = starting_zoom;

    // Get variable (uniform) locations on the shader to connect with the program
    // NOTE: If uniform variable could not be found in the shader, function returns -1
    const c_loc = rl.getShaderLocation(shader, "c");
    const zoom_loc = rl.getShaderLocation(shader, "zoom");
    const offset_loc = rl.getShaderLocation(shader, "offset");

    // Upload the shader uniform values!
    rl.setShaderValue(shader, c_loc, &c, .vec2);
    rl.setShaderValue(shader, zoom_loc, &zoom, .float);
    rl.setShaderValue(shader, offset_loc, &offset, .vec2);

    var increment_speed: i32 = 0; // Multiplier of speed to change c value
    var show_controls = true; // Show controls

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Press [1 - 6] to reset c to a point of interest
        for (point_keys, points_of_interest) |key, point| {
            if (rl.isKeyPressed(key)) {
                c = point;
                rl.setShaderValue(shader, c_loc, &c, .vec2);
                break;
            }
        }

        // If "R" is pressed, reset zoom and offset
        if (rl.isKeyPressed(.r)) {
            zoom = starting_zoom;
            offset = .{ 0.0, 0.0 };
            rl.setShaderValue(shader, zoom_loc, &zoom, .float);
            rl.setShaderValue(shader, offset_loc, &offset, .vec2);
        }

        if (rl.isKeyPressed(.space)) increment_speed = 0; // Pause animation (c change)
        if (rl.isKeyPressed(.f1)) show_controls = !show_controls; // Toggle whether or not to show controls

        if (rl.isKeyPressed(.right)) {
            increment_speed += 1;
        } else if (rl.isKeyPressed(.left)) {
            increment_speed -= 1;
        }

        // If either left or right button is pressed, zoom in/out
        if (rl.isMouseButtonDown(.left) or rl.isMouseButtonDown(.right)) {
            // Change zoom. If Mouse left -> zoom in. Mouse right -> zoom out
            zoom *= if (rl.isMouseButtonDown(.left)) zoom_speed else 1.0 / zoom_speed;

            const mouse_pos = rl.getMousePosition();

            // Find the velocity at which to change the camera. Take the distance of the mouse
            // from the center of the screen as the direction, and adjust magnitude based on the current zoom
            const offset_velocity: rl.Vector2 = .{
                .x = (mouse_pos.x / @as(f32, screen_width) - 0.5) * offset_speed_mul / zoom,
                .y = (mouse_pos.y / @as(f32, screen_height) - 0.5) * offset_speed_mul / zoom,
            };

            // Apply move velocity to camera
            offset[0] += rl.getFrameTime() * offset_velocity.x;
            offset[1] += rl.getFrameTime() * offset_velocity.y;

            // Update the shader uniform values!
            rl.setShaderValue(shader, zoom_loc, &zoom, .float);
            rl.setShaderValue(shader, offset_loc, &offset, .vec2);
        }

        // Increment c value with time
        const dc = rl.getFrameTime() * @as(f32, @floatFromInt(increment_speed)) * 0.0005;
        c[0] += dc;
        c[1] += dc;
        rl.setShaderValue(shader, c_loc, &c, .vec2);

        // Draw
        // Using a render texture to draw Julia set
        {
            rl.beginTextureMode(target); // Enable drawing to texture
            defer rl.endTextureMode();

            rl.clearBackground(.black); // Clear the render texture

            // Draw a rectangle in shader mode to be used as shader canvas
            // NOTE: Rectangle uses font white character texture coordinates,
            // so shader can not be applied here directly because input vertexTexCoord
            // do not represent full screen coordinates (space where want to apply shader)
            rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), .black);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black); // Clear screen background

        // Draw the saved texture and rendered julia set with shader
        // NOTE: We do not invert texture on Y, already considered inside shader
        {
            rl.beginShaderMode(shader);
            defer rl.endShaderMode();

            // WARNING: If FLAG_WINDOW_HIGHDPI is enabled, HighDPI monitor scaling should be considered
            // when rendering the RenderTexture2D to fit in the HighDPI scaled Window
            rl.drawTextureEx(target.texture, .{ .x = 0.0, .y = 0.0 }, 0.0, 1.0, .white);
        }

        if (show_controls) {
            rl.drawText("Press Mouse buttons right/left to zoom in/out and move", 10, 15, 10, .ray_white);
            rl.drawText("Press KEY_F1 to toggle these controls", 10, 30, 10, .ray_white);
            rl.drawText("Press KEYS [1 - 6] to change point of interest", 10, 45, 10, .ray_white);
            rl.drawText("Press KEY_LEFT | KEY_RIGHT to change speed", 10, 60, 10, .ray_white);
            rl.drawText("Press KEY_SPACE to stop movement animation", 10, 75, 10, .ray_white);
            rl.drawText("Press KEY_R to recenter the camera", 10, 90, 10, .ray_white);
        }
    }
}
