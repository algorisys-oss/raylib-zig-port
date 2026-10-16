//! raylib [textures] example - screen buffer
//!
//! Zig-API translation of examples/textures/textures_screen_buffer.c (raylib 6.2).
//! Example contributed by Agnis Aldiņš (@nezvers) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Agnis Aldiņš (@nezvers)

const rl = @import("raylib");

const max_colors = 256;
const scale_factor = 2;

const screen_width = 800;
const screen_height = 450;

const image_width = screen_width / scale_factor;
const image_height = screen_height / scale_factor;
const flame_width = screen_width / scale_factor;

pub fn main() !void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [textures] example - screen buffer");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Palette index of every pixel, and the flame intensity along the bottom row
    var index_buffer: [image_height][image_width]u8 = @splat(@splat(0));
    var flame_root_buffer: [flame_width]u8 = @splat(0);

    var screen_image = rl.genImageColor(image_width, image_height, .black);
    defer rl.unloadImage(screen_image);
    const screen_texture = try rl.loadTextureFromImage(screen_image);
    defer rl.unloadTexture(screen_texture);

    // Generate flame color palette
    var palette: [max_colors]rl.Color = undefined;
    for (&palette, 0..) |*color, i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, max_colors - 1);
        const hue = t * t;
        const saturation = t;
        const value = t;
        color.* = rl.colorFromHSV(250.0 + 150.0 * hue, saturation, value);
    }

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update

        // Grow flameRoot
        for (flame_root_buffer[2..]) |*flame| {
            const grown = @as(i32, flame.*) + rl.getRandomValue(0, 2);
            flame.* = @intCast(@min(grown, 255));
        }

        // Transfer flameRoot to indexBuffer
        index_buffer[image_height - 1] = flame_root_buffer;

        // Clear top row, because it can't move any higher
        index_buffer[0] = @splat(0);

        // Skip top row, it is already cleared
        for (1..image_height) |y| {
            for (0..image_width) |x| {
                var color_index = index_buffer[y][x];

                if (color_index != 0) {
                    // Move pixel a row above
                    index_buffer[y][x] = 0;
                    const move_x = rl.getRandomValue(0, 2) - 1;
                    const new_x = @as(i32, @intCast(x)) + move_x;

                    if ((new_x > 0) and (new_x < image_width)) {
                        const decay = rl.getRandomValue(0, 3);
                        color_index -|= @intCast(decay);
                        index_buffer[y - 1][@intCast(new_x)] = color_index;
                    }
                }
            }
        }

        // Update screenImage with palette colors
        for (index_buffer[1..], 1..) |row, y| {
            for (row, 0..) |color_index, x| {
                rl.imageDrawPixel(&screen_image, @intCast(x), @intCast(y), palette[color_index]);
            }
        }

        rl.updateTexture(screen_texture, screen_image.data.?);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);
        rl.drawTextureEx(screen_texture, .{ .x = 0, .y = 0 }, 0.0, 2.0, .white);
    }
}
