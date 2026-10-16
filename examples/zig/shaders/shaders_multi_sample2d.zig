//! raylib [shaders] example - multi sample2d
//!
//! Zig-API translation of examples/shaders/shaders_multi_sample2d.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2020-2025 Ramon Santamaria (@raysan5)
//!
//! NOTE: Shaders used in this example are #version 330 (OpenGL 3.3).

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - multi sample2d");
    defer rl.closeWindow(); // Close window and OpenGL context

    const im_red = rl.genImageColor(800, 450, .{ .r = 255, .g = 0, .b = 0, .a = 255 });
    const tex_red = try rl.loadTextureFromImage(im_red);
    defer rl.unloadTexture(tex_red);
    rl.unloadImage(im_red);

    const im_blue = rl.genImageColor(800, 450, .{ .r = 0, .g = 0, .b = 255, .a = 255 });
    const tex_blue = try rl.loadTextureFromImage(im_blue);
    defer rl.unloadTexture(tex_blue);
    rl.unloadImage(im_blue);

    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/color_mix.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    // Get an additional sampler2D location to be enabled on drawing
    const tex_blue_loc = rl.getShaderLocation(shader, "texture1");

    // Get shader uniform for divider
    const divider_loc = rl.getShaderLocation(shader, "divider");
    var divider_value: f32 = 0.5;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyDown(.right)) {
            divider_value += 0.01;
        } else if (rl.isKeyDown(.left)) {
            divider_value -= 0.01;
        }
        divider_value = std.math.clamp(divider_value, 0.0, 1.0);

        rl.setShaderValue(shader, divider_loc, divider_value);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginShaderMode(shader);
            // Texture sampler2D is reseted, needs to be set again for next frame
            defer rl.endShaderMode();

            // WARNING: Additional textures (sampler2D) are enabled for ALL draw calls in the batch,
            // but endShaderMode() forces batch drawing and resets active textures, this way
            // other textures (sampler2D) can be activated on consequent drawings (if required)
            // The downside of this approach is that setShaderValue() must be called inside the loop,
            // to be set again after every endShaderMode() reset
            rl.setShaderValueTexture(shader, tex_blue_loc, tex_blue);

            // We are drawing tex_red using default [sampler2D texture0] but
            // an additional texture units is enabled for tex_blue [sampler2D texture1]
            rl.drawTexture(tex_red, 0, 0, .white);
        }

        rl.drawText("Use KEY_LEFT/KEY_RIGHT to move texture mixing in shader!", 80, rl.getScreenHeight() - 40, 20, .ray_white);
    }
}
