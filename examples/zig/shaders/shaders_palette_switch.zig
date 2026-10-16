//! raylib [shaders] example - palette switch
//!
//! Zig-API translation of examples/shaders/shaders_palette_switch.c (raylib 6.2).
//! Example contributed by Marco Lizza (@MarcoLizza) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Marco Lizza (@MarcoLizza) and Ramon Santamaria (@raysan5)
//!
//! NOTE: Shaders used in this example are #version 330 (OpenGL 3.3).

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

const colors_per_palette = 8;
const values_per_color = 3;

const Palette = struct {
    name: [:0]const u8,
    colors: [colors_per_palette * values_per_color]i32,
};

const palettes = [_]Palette{
    .{ .name = "3-BIT RGB", .colors = .{
        0,   0,   0,
        255, 0,   0,
        0,   255, 0,
        0,   0,   255,
        0,   255, 255,
        255, 0,   255,
        255, 255, 0,
        255, 255, 255,
    } },
    .{ .name = "AMMO-8 (GameBoy-like)", .colors = .{
        4,   12,  6,
        17,  35,  24,
        30,  58,  41,
        48,  93,  66,
        77,  128, 97,
        137, 162, 87,
        190, 220, 127,
        238, 255, 204,
    } },
    .{ .name = "RKBV (2-strip film)", .colors = .{
        21,  25,  26,
        138, 76,  88,
        217, 98,  117,
        230, 184, 193,
        69,  107, 115,
        75,  151, 166,
        165, 189, 194,
        255, 245, 247,
    } },
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - palette switch");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Load shader to be used on some parts drawing
    // NOTE: Defining null for vertex shader forces usage of internal default vertex shader
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/palette_switch.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    // Get variable (uniform) location on the shader to connect with the program
    // NOTE: If uniform variable could not be found in the shader, function returns -1
    const palette_loc = rl.getShaderLocation(shader, "palette");

    var current_palette: usize = 0;
    const line_height = screen_height / colors_per_palette;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.right)) {
            current_palette = (current_palette + 1) % palettes.len;
        } else if (rl.isKeyPressed(.left)) {
            current_palette = (current_palette + palettes.len - 1) % palettes.len;
        }

        // Send palette data to the shader to be used on drawing
        // NOTE: We are sending RGB triplets w/o the alpha channel
        rl.setShaderValueV(shader, palette_loc, &palettes[current_palette].colors, .ivec3, colors_per_palette);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginShaderMode(shader);
            defer rl.endShaderMode();

            for (0..colors_per_palette) |i| {
                // Draw horizontal screen-wide rectangles with increasing "palette index"
                // The used palette index is encoded in the RGB components of the pixel
                const index: u8 = @intCast(i);
                rl.drawRectangle(0, line_height * @as(i32, index), rl.getScreenWidth(), line_height, .{ .r = index, .g = index, .b = index, .a = 255 });
            }
        }

        rl.drawText("< >", 10, 10, 30, .dark_blue);
        rl.drawText("CURRENT PALETTE:", 60, 15, 20, .ray_white);
        rl.drawText(palettes[current_palette].name, 300, 15, 20, .red);

        rl.drawFPS(700, 15);
    }
}
