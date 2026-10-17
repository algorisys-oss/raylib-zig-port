//! raylib [shaders] example - ascii rendering
//!
//! Zig-API translation of examples/shaders/shaders_ascii_rendering.c (raylib 6.2).
//! Example contributed by Maicon Santana (@maiconpintoabreu) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Maicon Santana (@maiconpintoabreu)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - ascii rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Texture to test static drawing
    const fudesumi = try rl.loadTexture("resources/fudesumi.png");
    defer rl.unloadTexture(fudesumi);
    // Texture to test moving drawing
    const raysan = try rl.loadTexture("resources/raysan.png");
    defer rl.unloadTexture(raysan);

    // Load shader to be used on postprocessing
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/ascii.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    // These locations are used to send data to the GPU
    const resolution_loc = rl.getShaderLocation(shader, "resolution");
    const font_size_loc = rl.getShaderLocation(shader, "fontSize");

    // Set the character size for the ASCII effect
    // Fontsize should be 9 or more
    var font_size: f32 = 9.0;

    // Send the updated values to the shader
    const resolution = [2]f32{ screen_width, screen_height };
    rl.setShaderValue(shader, resolution_loc, resolution);

    var circle_pos: rl.Vector2 = .{ .x = 40.0, .y = @as(f32, screen_height) * 0.5 };
    var circle_speed: f32 = 1.0;

    // RenderTexture to apply the postprocessing later
    const target = try rl.loadRenderTexture(screen_width, screen_height);
    defer rl.unloadRenderTexture(target);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        circle_pos.x += circle_speed;
        if (circle_pos.x > 200.0 or circle_pos.x < 40.0) circle_speed *= -1; // Revert speed

        if (rl.isKeyPressed(.left) and font_size > 9.0) font_size -= 1; // Reduce fontSize
        if (rl.isKeyPressed(.right) and font_size < 15.0) font_size += 1; // Increase fontSize

        // Set fontsize for the shader
        rl.setShaderValue(shader, font_size_loc, font_size);

        // Draw
        {
            rl.beginTextureMode(target);
            defer rl.endTextureMode();

            rl.clearBackground(.white);

            // Draw scene in our render texture
            rl.drawTexture(fudesumi, 500, -30, .white);
            rl.drawTextureV(raysan, circle_pos, .white);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginShaderMode(shader);
            defer rl.endShaderMode();

            // Draw the scene texture (that we rendered earlier) to the screen
            // The shader will process every pixel of this texture
            const source: rl.Rectangle = .{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(target.texture.width),
                .height = @floatFromInt(-target.texture.height),
            };
            rl.drawTextureRec(target.texture, source, .{ .x = 0, .y = 0 }, .white);
        }

        rl.drawRectangle(0, 0, screen_width, 40, .black);
        rl.drawText(rl.textFormat("Ascii effect - FontSize:{d:2.0} - [Left] -1 [Right] +1 ", .{font_size}), 120, 10, 20, .light_gray);
        rl.drawFPS(10, 10);
    }
}
