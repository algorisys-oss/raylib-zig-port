//! raylib [text] example - font sdf
//!
//! Zig-API translation of examples/text/text_font_sdf.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330; // Desktop GLSL version

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - font sdf");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures/Fonts MUST be loaded after Window initialization (OpenGL context is required)

    const msg = "Signed Distance Fields";

    // Loading file to memory
    const file_data = try rl.loadFileData("resources/anonymous_pro_bold.ttf");

    // Default font generation from TTF font
    // Parameters > font size: 16, glyphs padding in image: 4 px, pack method: 0 (default)
    const font_default = try fontFromData(file_data, .default, 4, 0);
    defer rl.unloadFont(font_default); // Default font unloading

    // SDF font generation from TTF font
    // Parameters > font size: 16, glyphs padding in image: 0 px, pack method: 1 (Skyline algorythm)
    const font_sdf = try fontFromData(file_data, .sdf, 0, 1);
    defer rl.unloadFont(font_sdf); // SDF font unloading

    rl.unloadFileData(file_data); // Free memory from loaded file

    // Load SDF required shader (we use default vertex shader)
    const shader = try rl.loadShader(null, rl.textFormat("resources/shaders/glsl{d}/sdf.fs", .{glsl_version}));
    defer rl.unloadShader(shader); // Unload SDF shader
    rl.setTextureFilter(font_sdf.texture, .bilinear); // Required for SDF font

    var font_position: rl.Vector2 = .{ .x = 40, .y = screen_height / 2.0 - 50 };
    var text_size: rl.Vector2 = .{ .x = 0.0, .y = 0.0 };
    var font_size: f32 = 16.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        font_size += rl.getMouseWheelMove() * 8.0;

        if (font_size < 6) font_size = 6;

        const use_sdf = rl.isKeyDown(.space);
        const font = if (use_sdf) font_sdf else font_default;

        text_size = rl.measureTextEx(font, msg, font_size, 0);

        font_position.x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2 - text_size.x / 2;
        font_position.y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2 - text_size.y / 2 + 80;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        if (use_sdf) {
            // NOTE: SDF fonts require a custom SDf shader to compute fragment color
            rl.beginShaderMode(shader); // Activate SDF font shader
            rl.drawTextEx(font_sdf, msg, font_position, font_size, 0, .black);
            rl.endShaderMode(); // Activate our default shader for next drawings

            rl.drawTexture(font_sdf.texture, 10, 10, .black);
        } else {
            rl.drawTextEx(font_default, msg, font_position, font_size, 0, .black);
            rl.drawTexture(font_default.texture, 10, 10, .black);
        }

        if (use_sdf) {
            rl.drawText("SDF!", 320, 20, 80, .red);
        } else {
            rl.drawText("default font", 315, 40, 30, .gray);
        }

        rl.drawText("FONT SIZE: 16.0", rl.getScreenWidth() - 240, 20, 20, .dark_gray);
        rl.drawText(rl.textFormat("RENDER SIZE: {d:.2}", .{font_size}), rl.getScreenWidth() - 240, 50, 20, .dark_gray);
        rl.drawText("Use MOUSE WHEEL to SCALE TEXT!", rl.getScreenWidth() - 240, 90, 10, .dark_gray);

        rl.drawText("HOLD SPACE to USE SDF FONT VERSION!", 340, rl.getScreenHeight() - 30, 20, .maroon);
    }
}

/// Build a 16 px font from TTF file data: the default 95 glyphs (from 32, Space)
/// rasterized as `font_type`, packed into an atlas texture.
fn fontFromData(file_data: []const u8, font_type: rl.FontType, padding: i32, pack_method: i32) !rl.Font {
    const font_size = 16;

    // Loading font data from memory data
    // No glyphs array provided (null): the 95 default glyphs are generated
    const glyphs = try rl.loadFontData(file_data, font_size, null, font_type);

    var font = std.mem.zeroes(rl.Font);
    font.baseSize = font_size;
    font.glyphCount = @intCast(glyphs.len);
    font.glyphs = glyphs.ptr;

    const atlas = rl.genImageFontAtlas(glyphs, &font.recs, font_size, padding, pack_method);
    defer rl.unloadImage(atlas);
    font.texture = try rl.loadTextureFromImage(atlas);

    return font;
}
