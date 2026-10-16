//! raylib [text] example - font loading
//!
//! NOTE: raylib can load fonts from multiple input file formats:
//!
//!   - TTF/OTF > Sprite font atlas is generated on loading, user can configure
//!               some of the generation parameters (size, characters to include)
//!   - BMFonts > Angel code font fileformat, sprite font image must be provided
//!               together with the .fnt file, font generation can not be configured
//!   - XNA Spritefont > Sprite font image, following XNA Spritefont conventions,
//!               Characters in image must follow some spacing and order rules
//!
//! Zig-API translation of examples/text/text_font_loading.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

/// The first 250 codepoints from 32 (Space): what C's LoadFontEx(path, size, NULL, 250) loads.
const codepoints = blk: {
    var result: [250]i32 = undefined;
    for (&result, 32..) |*codepoint, value| codepoint.* = value;
    break :blk result;
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - font loading");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define characters to draw
    // NOTE: raylib supports UTF-8 encoding, following list is actually codified as UTF8 internally
    const msg = "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHI\nJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklm\nnopqrstuvwxyz{|}~¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒ\nÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö\n÷øùúûüýþÿ";

    // NOTE: Textures/Fonts MUST be loaded after Window initialization (OpenGL context is required)

    // BMFont (AngelCode) : Font data and image atlas have been generated using external program
    const font_bm = try rl.loadFont("resources/pixantiqua.fnt"); // Requires "resources/pixantiqua.png"
    defer rl.unloadFont(font_bm); // AngelCode Font unloading

    // TTF font : Font data and atlas are generated directly from TTF
    // NOTE: We define a font base size of 32 pixels tall and up-to 250 characters
    const font_ttf = try rl.loadFontEx("resources/pixantiqua.ttf", 32, &codepoints);
    defer rl.unloadFont(font_ttf); // TTF Font unloading

    rl.setTextLineSpacing(16); // Set line spacing for multiline text (when line breaks are included '\n')

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const use_ttf = rl.isKeyDown(.space);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("Hold SPACE to use TTF generated font", 20, 20, 20, .light_gray);

        if (!use_ttf) {
            rl.drawTextEx(font_bm, msg, .{ .x = 20.0, .y = 100.0 }, @floatFromInt(font_bm.baseSize), 2, .maroon);
            rl.drawText("Using BMFont (Angelcode) imported", 20, rl.getScreenHeight() - 30, 20, .gray);
        } else {
            rl.drawTextEx(font_ttf, msg, .{ .x = 20.0, .y = 100.0 }, @floatFromInt(font_ttf.baseSize), 2, .lime);
            rl.drawText("Using TTF font generated", 20, rl.getScreenHeight() - 30, 20, .gray);
        }
    }
}
