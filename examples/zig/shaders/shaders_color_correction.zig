//! raylib [shaders] example - color correction
//!
//! Zig-API translation of examples/shaders/shaders_color_correction.c (raylib 6.2).
//! Example contributed by Jordi Santonja (@JordSant) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jordi Santonja (@JordSant)
//!
//! NOTE: This example requires raylib OpenGL 3.3 or ES2 versions for shaders support,
//!       OpenGL 1.1 does not support shaders, recompile raylib to OpenGL 3.3 version

const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

const texture_paths = [_][:0]const u8{
    "resources/parrots.png",
    "resources/cat.png",
    "resources/mandrill.png",
    "resources/fudesumi.png",
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - color correction");
    defer rl.closeWindow(); // Close window and OpenGL context

    var textures: [texture_paths.len]rl.Texture2D = undefined;
    var textures_loaded: usize = 0;
    defer for (textures[0..textures_loaded]) |texture| rl.unloadTexture(texture);
    for (&textures, texture_paths) |*texture, path| {
        texture.* = try rl.loadTexture(path);
        textures_loaded += 1;
    }

    const shdr_color_correction = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/color_correction.fs", .{glsl_version}));
    defer rl.unloadShader(shdr_color_correction);

    var image_index: i32 = 0;
    var reset_button_clicked = false;

    var contrast: f32 = 0.0;
    var saturation: f32 = 0.0;
    var brightness: f32 = 0.0;

    // Get shader locations
    const contrast_loc = rl.getShaderLocation(shdr_color_correction, "contrast");
    const saturation_loc = rl.getShaderLocation(shdr_color_correction, "saturation");
    const brightness_loc = rl.getShaderLocation(shdr_color_correction, "brightness");

    // Set shader values (they can be changed later)
    rl.setShaderValue(shdr_color_correction, contrast_loc, contrast);
    rl.setShaderValue(shdr_color_correction, saturation_loc, saturation);
    rl.setShaderValue(shdr_color_correction, brightness_loc, brightness);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Select texture to draw
        if (rl.isKeyPressed(.one)) {
            image_index = 0;
        } else if (rl.isKeyPressed(.two)) {
            image_index = 1;
        } else if (rl.isKeyPressed(.three)) {
            image_index = 2;
        } else if (rl.isKeyPressed(.four)) {
            image_index = 3;
        }

        // Reset values to 0
        if (rl.isKeyPressed(.r) or reset_button_clicked) {
            contrast = 0.0;
            saturation = 0.0;
            brightness = 0.0;
        }

        // Send the values to the shader
        rl.setShaderValue(shdr_color_correction, contrast_loc, contrast);
        rl.setShaderValue(shdr_color_correction, saturation_loc, saturation);
        rl.setShaderValue(shdr_color_correction, brightness_loc, brightness);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginShaderMode(shdr_color_correction);
            defer rl.endShaderMode();

            const texture = textures[@intCast(image_index)];
            rl.drawTexture(texture, 580 / 2 - @divTrunc(texture.width, 2), @divTrunc(rl.getScreenHeight(), 2) - @divTrunc(texture.height, 2), .white);
        }

        rl.drawLine(580, 0, 580, rl.getScreenHeight(), .{ .r = 218, .g = 218, .b = 218, .a = 255 });
        rl.drawRectangle(580, 0, rl.getScreenWidth(), rl.getScreenHeight(), .{ .r = 232, .g = 232, .b = 232, .a = 255 });

        // Draw UI info text
        rl.drawText("Color Correction", 585, 40, 20, .gray);

        rl.drawText("Picture", 602, 75, 10, .gray);
        rl.drawText("Press [1] - [4] to Change Picture", 600, 230, 8, .gray);
        rl.drawText("Press [R] to Reset Values", 600, 250, 8, .gray);

        // Draw GUI controls
        _ = gui.toggleGroup(.{ .x = 645, .y = 70, .width = 20, .height = 20 }, "1;2;3;4", &image_index);

        _ = gui.sliderBar(.{ .x = 645, .y = 100, .width = 120, .height = 20 }, "Contrast", rl.textFormat("{d:.0}", .{contrast}), &contrast, -100.0, 100.0);
        _ = gui.sliderBar(.{ .x = 645, .y = 130, .width = 120, .height = 20 }, "Saturation", rl.textFormat("{d:.0}", .{saturation}), &saturation, -100.0, 100.0);
        _ = gui.sliderBar(.{ .x = 645, .y = 160, .width = 120, .height = 20 }, "Brightness", rl.textFormat("{d:.0}", .{brightness}), &brightness, -100.0, 100.0);

        reset_button_clicked = gui.button(.{ .x = 645, .y = 190, .width = 40, .height = 20 }, "Reset") != 0;

        rl.drawFPS(710, 10);
    }
}
