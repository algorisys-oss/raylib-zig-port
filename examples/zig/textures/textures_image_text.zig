//! raylib [textures] example - image text
//!
//! Zig-API translation of examples/textures/textures_image_text.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - image text");
    defer rl.closeWindow(); // Close window and OpenGL context

    var parrots = try rl.loadImage("resources/parrots.png"); // Load image in CPU memory (RAM)

    // When no codepoints are provided, LoadFontEx() loads a default set of codepoints
    // This set includes '@', which "KAISG.ttf" doesn't have a glyph for, causing a warning to be logged
    // We avoid this by just excluding it from the list of codepoints we load
    const codepoints = try rl.loadCodepoints(" !\"#$%&'()*+,-./0123456789:;<=>?ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~");

    // TTF Font loading with custom generation parameters
    const font = try rl.loadFontEx("resources/KAISG.ttf", 64, codepoints);
    defer rl.unloadFont(font); // Unload custom font
    rl.unloadCodepoints(codepoints);

    const font_size: f32 = @floatFromInt(font.baseSize);

    // Draw over image using custom font
    rl.imageDrawTextEx(&parrots, font, "[Parrots font drawing]", .{ .x = 20.0, .y = 20.0 }, font_size, 0.0, .red);

    const texture = try rl.loadTextureFromImage(parrots); // Image converted to texture, uploaded to GPU memory (VRAM)
    defer rl.unloadTexture(texture); // Texture unloading
    rl.unloadImage(parrots); // Once image has been converted to texture and uploaded to VRAM, it can be unloaded from RAM

    const position: rl.Vector2 = .{
        .x = @as(f32, screen_width) / 2 - @as(f32, @floatFromInt(texture.width)) / 2,
        .y = @as(f32, screen_height) / 2 - @as(f32, @floatFromInt(texture.height)) / 2 - 20,
    };

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const show_font = rl.isKeyDown(.space);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        if (!show_font) {
            // Draw texture with text already drawn inside
            rl.drawTextureV(texture, position, .white);

            // Draw text directly using sprite font
            rl.drawTextEx(font, "[Parrots font drawing]", .{ .x = position.x + 20, .y = position.y + 20 + 280 }, font_size, 0.0, .white);
        } else {
            // Make the font atlas texture fit the screen, so we can see the whole thing
            const atlas_width: f32 = @floatFromInt(font.texture.width);
            const atlas_height: f32 = @floatFromInt(font.texture.height);
            const atlas_ratio = atlas_width / atlas_height;
            const screen_ratio = @as(f32, screen_width) / @as(f32, screen_height);
            const scale = if (atlas_ratio >= screen_ratio) screen_width / atlas_width else screen_height / atlas_height;

            const width = atlas_width * scale;
            const height = atlas_height * scale;
            rl.drawTextureEx(font.texture, .{ .x = (screen_width - width) / 2, .y = (screen_height - height) / 2 }, 0, scale, .black);
        }

        rl.drawText("PRESS SPACE to SHOW FONT ATLAS USED", 290, 420, 10, .dark_gray);
    }
}
