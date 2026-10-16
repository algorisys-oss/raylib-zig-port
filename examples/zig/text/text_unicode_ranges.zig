//! raylib [text] example - unicode ranges
//!
//! Zig-API translation of examples/text/text_unicode_ranges.c (raylib 6.2).
//! Example contributed by Vadim Gunko (@GuvaCode) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Vadim Gunko (@GuvaCode) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const font_path = "resources/NotoSansTC-Regular.ttf";

/// An inclusive range of codepoints
const Range = struct { start: i32, stop: i32 };

/// Codepoint ranges added for each level; a level also includes all the ranges below it.
const level_ranges = [_][]const Range{
    // 0: Basic ASCII [32-127] (font default)
    &.{},
    // 1: European Languages
    &.{
        .{ .start = 0xc0, .stop = 0x17f },
        .{ .start = 0x180, .stop = 0x24f },
        //.{ .start = 0x1e00, .stop = 0x1eff },
        //.{ .start = 0x2c60, .stop = 0x2c7f },
    },
    // 2: Greek
    &.{
        .{ .start = 0x370, .stop = 0x3ff },
        .{ .start = 0x1f00, .stop = 0x1fff },
    },
    // 3: Cyrillic
    &.{
        .{ .start = 0x400, .stop = 0x4ff },
        .{ .start = 0x500, .stop = 0x52f },
        .{ .start = 0x2de0, .stop = 0x2Dff },
        .{ .start = 0xa640, .stop = 0xA69f },
    },
    // 4: CJK (Japanese and Chinese)
    // WARNING: Loading thousands of codepoints requires lot of time!
    // A better strategy is prefilter the required codepoints for the text
    // in the game and just load the required ones
    &.{
        .{ .start = 0x4e00, .stop = 0x9fff },
        .{ .start = 0x3400, .stop = 0x4dbf },
        .{ .start = 0x3000, .stop = 0x303f },
        .{ .start = 0x3040, .stop = 0x309f },
        .{ .start = 0x30A0, .stop = 0x30ff },
        .{ .start = 0x31f0, .stop = 0x31ff },
        .{ .start = 0xff00, .stop = 0xffef },
        .{ .start = 0xac00, .stop = 0xd7af },
        .{ .start = 0x1100, .stop = 0x11ff },
    },
    // 5: Devanari, Arabic, Hebrew
    // WARNING: Glyphs not available on provided font!
    //&.{
    //    .{ .start = 0x900, .stop = 0x97f }, // Devanagari
    //    .{ .start = 0x600, .stop = 0x6ff }, // Arabic
    //    .{ .start = 0x5d0, .stop = 0x5ea }, // Hebrew
    //},
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - unicode ranges");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Load font with default Unicode range: Basic ASCII [32-127]
    var font = try rl.loadFont(font_path);
    defer rl.unloadFont(font); // Unload font resource
    rl.setTextureFilter(font.texture, .bilinear);

    var unicode_range: usize = 0; // Track the ranges of codepoints added to font
    var prev_unicode_range: usize = 0; // Previous Unicode range to avoid reloading every frame

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (unicode_range != prev_unicode_range) {
            // Reload font with default Unicode range: Basic ASCII [32-127]
            const reloaded = try rl.loadFont(font_path);
            rl.unloadFont(font);
            font = reloaded;

            // Add required ranges to loaded font, highest level first
            var level = unicode_range + 1;
            while (level > 0) {
                level -= 1;
                for (level_ranges[level]) |range| try addCodepointRange(allocator, &font, font_path, range);
            }

            prev_unicode_range = unicode_range;
            rl.setTextureFilter(font.texture, .bilinear); // Set font atlas scale filter
        }

        if (rl.isKeyPressed(.zero)) {
            unicode_range = 0;
        } else if (rl.isKeyPressed(.one)) {
            unicode_range = 1;
        } else if (rl.isKeyPressed(.two)) {
            unicode_range = 2;
        } else if (rl.isKeyPressed(.three)) {
            unicode_range = 3;
        } else if (rl.isKeyPressed(.four)) {
            unicode_range = 4;
        }
        //else if (rl.isKeyPressed(.five)) unicode_range = 5;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("ADD CODEPOINTS: [1][2][3][4]", 20, 20, 20, .maroon);

        // Render test strings in different languages
        rl.drawTextEx(font, "> English: Hello World!", .{ .x = 50, .y = 70 }, 32, 1, .dark_gray); // English
        rl.drawTextEx(font, "> Español: Hola mundo!", .{ .x = 50, .y = 120 }, 32, 1, .dark_gray); // Spanish
        rl.drawTextEx(font, "> Ελληνικά: Γειά σου κόσμε!", .{ .x = 50, .y = 170 }, 32, 1, .dark_gray); // Greek
        rl.drawTextEx(font, "> Русский: Привет мир!", .{ .x = 50, .y = 220 }, 32, 0, .dark_gray); // Russian
        rl.drawTextEx(font, "> 中文: 你好世界!", .{ .x = 50, .y = 270 }, 32, 1, .dark_gray); // Chinese
        rl.drawTextEx(font, "> 日本語: こんにちは世界!", .{ .x = 50, .y = 320 }, 32, 1, .dark_gray); // Japanese
        //rl.drawTextEx(font, "देवनागरी: होला मुंडो!", .{ .x = 50, .y = 350 }, 32, 1, .dark_gray); // Devanagari (glyphs not available in font)

        // Draw font texture scaled to screen
        const atlas_width: f32 = @floatFromInt(font.texture.width);
        const atlas_height: f32 = @floatFromInt(font.texture.height);
        const atlas_scale = 380.0 / atlas_width;
        const atlas_rec: rl.Rectangle = .{ .x = 400.0, .y = 16.0, .width = atlas_width * atlas_scale, .height = atlas_height * atlas_scale };
        rl.drawRectangleRec(atlas_rec, .black);
        rl.drawTexturePro(font.texture, .{ .x = 0, .y = 0, .width = atlas_width, .height = atlas_height }, atlas_rec, .{ .x = 0, .y = 0 }, 0.0, .white);
        rl.drawRectangleLines(400, 16, 380, 380, .red);

        rl.drawText(rl.textFormat("ATLAS SIZE: {d}x{d} px (x{d:.2})", .{ font.texture.width, font.texture.height, atlas_scale }), 20, 380, 20, .blue);
        rl.drawText(rl.textFormat("CODEPOINTS GLYPHS LOADED: {d}", .{font.glyphCount}), 20, 410, 20, .lime);

        // Display font attribution
        rl.drawText("Font: Noto Sans TC. License: SIL Open Font License 1.1", screen_width - 300, screen_height - 20, 10, .gray);

        if (prev_unicode_range != unicode_range) {
            rl.drawRectangle(0, 0, screen_width, screen_height, rl.fade(.white, 0.8));
            rl.drawRectangle(0, 125, screen_width, 200, .gray);
            rl.drawText("GENERATING FONT ATLAS...", 120, 210, 40, .black);
        }
    }
}

/// Add codepoint range to existing font, reloading it from `path` with the
/// current glyphs plus the provided range (regenerating font image and texture)
fn addCodepointRange(allocator: std.mem.Allocator, font: *rl.Font, path: [:0]const u8, range: Range) !void {
    const current_glyphs = font.glyphs.?[0..@intCast(font.glyphCount)];
    const range_size: usize = @intCast(range.stop - range.start + 1);

    const updated_codepoints = try allocator.alloc(i32, current_glyphs.len + range_size);
    defer allocator.free(updated_codepoints);

    // Get current codepoint list
    for (updated_codepoints[0..current_glyphs.len], current_glyphs) |*codepoint, glyph| codepoint.* = glyph.value;

    // Add new codepoints to list (provided range)
    for (updated_codepoints[current_glyphs.len..], 0..) |*codepoint, offset| codepoint.* = range.start + @as(i32, @intCast(offset));

    const updated = try rl.loadFontEx(path, 32, updated_codepoints);
    rl.unloadFont(font.*);
    font.* = updated;
}
