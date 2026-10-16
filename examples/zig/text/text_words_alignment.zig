//! raylib [text] example - words alignment
//!
//! Zig-API translation of examples/text/text_words_alignment.c (raylib 6.2).
//! Example contributed by JP Mortiboys (@themushroompirates) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 JP Mortiboys (@themushroompirates)

const std = @import("std");
const rl = @import("raylib");

/// Alignment along one axis: left/top, centre/middle, right/bottom.
const TextAlignment = enum {
    start,
    centre,
    end,

    fn prev(alignment: TextAlignment) TextAlignment {
        return if (alignment == .start) .start else @fromBackingInt(@intCast(@backingInt(alignment) - 1));
    }

    fn next(alignment: TextAlignment) TextAlignment {
        return if (alignment == .end) .end else @fromBackingInt(@intCast(@backingInt(alignment) + 1));
    }

    /// Fraction of the free space placed before the text.
    fn factor(alignment: TextAlignment) f32 {
        return @as(f32, @floatFromInt(@backingInt(alignment))) * 0.5;
    }
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - words alignment");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the rectangle we will draw the text in
    const text_container_rect: rl.Rectangle = .{
        .x = @as(f32, screen_width) / 2 - @as(f32, screen_width) / 4,
        .y = @as(f32, screen_height) / 2 - @as(f32, screen_height) / 3,
        .width = @as(f32, screen_width) / 2,
        .height = @as(f32, screen_height) * 2 / 3,
    };

    // Some text to display the current alignment
    const text_align_name_h = [_][]const u8{ "Left", "Centre", "Right" };
    const text_align_name_v = [_][]const u8{ "Top", "Middle", "Bottom" };

    // Define the text we're going to draw in the rectangle
    const words = rl.textSplit("raylib is a simple and easy-to-use library to enjoy videogames programming", ' ');

    // Initialize the font size we're going to use
    const font_size = 40;

    // And of course the font...
    const font = rl.getFontDefault();

    // Initialize the alignment variables
    var h_align: TextAlignment = .centre;
    var v_align: TextAlignment = .centre;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.left)) h_align = h_align.prev();
        if (rl.isKeyPressed(.right)) h_align = h_align.next();
        if (rl.isKeyPressed(.up)) v_align = v_align.prev();
        if (rl.isKeyPressed(.down)) v_align = v_align.next();

        // One word per second
        const word_index: usize = if (words.len > 0) @as(usize, @intFromFloat(rl.getTime())) % words.len else 0;
        const word = std.mem.span(words[word_index]);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.dark_blue);

        rl.drawText("Use Arrow Keys to change the text alignment", 20, 20, 20, .light_gray);
        rl.drawText(rl.textFormat("Alignment: Horizontal = {s}, Vertical = {s}", .{
            text_align_name_h[@backingInt(h_align)],
            text_align_name_v[@backingInt(v_align)],
        }), 20, 40, 20, .light_gray);

        rl.drawRectangleRec(text_container_rect, .blue);

        // Get the size of the text to draw
        const text_size = rl.measureTextEx(font, word, font_size, font_size * 0.1);

        // Calculate the top-left text position based on the rectangle and alignment
        const text_pos: rl.Vector2 = .{
            .x = text_container_rect.x + rl.math.lerp(0.0, text_container_rect.width - text_size.x, h_align.factor()),
            .y = text_container_rect.y + rl.math.lerp(0.0, text_container_rect.height - text_size.y, v_align.factor()),
        };

        // Draw the text
        rl.drawTextEx(font, word, text_pos, font_size, font_size * 0.1, .ray_white);
    }
}
