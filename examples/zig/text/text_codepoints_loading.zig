//! raylib [text] example - codepoints loading
//!
//! Zig-API translation of examples/text/text_codepoints_loading.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2022-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

// Text to be displayed, must be UTF-8 (save this code file as UTF-8)
// NOTE: It can contain all the required text for the game,
// this text will be scanned to get all the required codepoints
const text = "いろはにほへと　ちりぬるを\nわかよたれそ　つねならむ\nうゐのおくやま　けふこえて\nあさきゆめみし　ゑひもせす";

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - codepoints loading");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Convert each utf-8 character into its
    // corresponding codepoint in the font file
    const codepoints = try rl.loadCodepoints(text);
    const codepoint_count = codepoints.len;

    // Removed duplicate codepoints to generate smaller font atlas
    const codepoints_no_dups = try codepointRemoveDuplicates(allocator, codepoints);
    const codepoints_no_dups_count = codepoints_no_dups.len;
    rl.unloadCodepoints(codepoints);

    // Load font containing all the provided codepoint glyphs
    // A texture font atlas is automatically generated
    const font = try rl.loadFontEx("resources/DotGothic16-Regular.ttf", 36, codepoints_no_dups);
    defer rl.unloadFont(font); // Unload font

    // Set bilinear scale filter for better font scaling
    rl.setTextureFilter(font.texture, .bilinear);

    rl.setTextLineSpacing(20); // Set line spacing for multiline text (when line breaks are included '\n')

    // Free codepoints, atlas has already been generated
    allocator.free(codepoints_no_dups);

    var show_font_atlas = false;

    var position: usize = 0; // Byte position in text, moved by codepoints

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.space)) show_font_atlas = !show_font_atlas;

        // Testing code: getting next and previous codepoints on provided text
        if (rl.isKeyPressed(.right) and position < text.len) {
            // Get next codepoint in string and move position
            position += @intCast(rl.getCodepointNext(text[position..]).size);
        } else if (rl.isKeyPressed(.left) and position > 0) {
            // Get previous codepoint in string and move position
            position -= @intCast(rl.getCodepointPrevious(text[position..]).size);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawRectangle(0, 0, rl.getScreenWidth(), 70, .black);
        rl.drawText(rl.textFormat("Total codepoints contained in provided text: {d}", .{codepoint_count}), 10, 10, 20, .green);
        rl.drawText(rl.textFormat("Total codepoints required for font atlas (duplicates excluded): {d}", .{codepoints_no_dups_count}), 10, 40, 20, .green);

        if (show_font_atlas) {
            // Draw generated font texture atlas containing provided codepoints
            rl.drawTexture(font.texture, 150, 100, .black);
            rl.drawRectangleLines(150, 100, font.texture.width, font.texture.height, .black);
        } else {
            // Draw provided text with loaded font, containing all required codepoint glyphs
            rl.drawTextEx(font, text, .{ .x = 160, .y = 110 }, 48, 5, .black);
        }

        rl.drawText("Press SPACE to toggle font atlas view!", 10, rl.getScreenHeight() - 30, 20, .gray);
    }
}

/// Remove codepoint duplicates, keeping the first occurrence of each.
/// Caller owns the returned slice.
/// WARNING: This process could be a bit slow if the text to process is very long
fn codepointRemoveDuplicates(allocator: std.mem.Allocator, codepoints: []const i32) ![]i32 {
    var unique: std.ArrayList(i32) = try .initCapacity(allocator, codepoints.len);
    errdefer unique.deinit(allocator);

    for (codepoints) |codepoint| {
        if (std.mem.indexOfScalar(i32, unique.items, codepoint) == null) unique.appendAssumeCapacity(codepoint);
    }

    return unique.toOwnedSlice(allocator);
}
