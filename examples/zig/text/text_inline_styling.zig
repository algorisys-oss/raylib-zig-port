//! raylib [text] example - inline styling
//!
//! Zig-API translation of examples/text/text_inline_styling.c (raylib 6.2).
//! Example contributed by Wagner Barongello (@SultansOfCode) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Wagner Barongello (@SultansOfCode) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - inline styling");
    defer rl.closeWindow(); // Close window and OpenGL context

    var col_random: rl.Color = .red; // Random color used on text
    var frame_counter: u32 = 0; // Used to generate a new random color every certain frames

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        frame_counter += 1;

        if (frame_counter % 20 == 0) {
            col_random.r = @intCast(rl.getRandomValue(0, 255));
            col_random.g = @intCast(rl.getRandomValue(0, 255));
            col_random.b = @intCast(rl.getRandomValue(0, 255));
            col_random.a = 255;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Text inline styling strategy used: [ ] delimiters for format
        // - Define foreground color:      [cRRGGBBAA]
        // - Define background color:      [bRRGGBBAA]
        // - Reset formating:              [r]
        // Colors defined with [cRRGGBBAA] or [bRRGGBBAA] are multiplied by the base color alpha
        // This allows global transparency control while keeping per-section styling (ex. text fade effects)
        // Example: [bAA00AAFF][cFF0000FF]red text on gray background[r] normal text

        drawTextStyled(rl.getFontDefault(), "This changes the [cFF0000FF]foreground color[r] of provided text!!!", .{ .x = 100, .y = 80 }, 20.0, 2.0, .black);

        drawTextStyled(rl.getFontDefault(), "This changes the [bFF00FFFF]background color[r] of provided text!!!", .{ .x = 100, .y = 120 }, 20.0, 2.0, .black);

        drawTextStyled(rl.getFontDefault(), "This changes the [c00ff00ff][bff0000ff]foreground and background colors[r]!!!", .{ .x = 100, .y = 160 }, 20.0, 2.0, .black);

        drawTextStyled(rl.getFontDefault(), "This changes the [c00ff00ff]alpha[r] relative [cffffffff][b000000ff]from source[r] [cff000088]color[r]!!!", .{ .x = 100, .y = 200 }, 20.0, 2.0, .{ .r = 0, .g = 0, .b = 0, .a = 100 });

        // Get formated text
        const text = rl.textFormat("Let's be [c{x:0>2}{x:0>2}{x:0>2}FF]CREATIVE[r] !!!", .{ col_random.r, col_random.g, col_random.b });
        drawTextStyled(rl.getFontDefault(), text, .{ .x = 100, .y = 240 }, 40.0, 2.0, .black);

        const text_size = measureTextStyled(rl.getFontDefault(), text, 40.0, 2.0);
        rl.drawRectangleLines(100, 240, @intFromFloat(text_size.x), @intFromFloat(text_size.y), .green);
    }
}

/// An inline style tag found at the start of a text: `[r]`, `[cRRGGBBAA]` or `[bRRGGBBAA]`.
const StyleTag = struct {
    kind: enum { reset, foreground, background },
    color: rl.Color = .blank,
    len: usize, // Bytes to skip
};

/// Parse the inline style tag at the start of `text` (which begins with '['), if any.
fn parseStyleTag(text: []const u8) ?StyleTag {
    if (text.len > 2 and text[1] == 'r' and text[2] == ']') return .{ .kind = .reset, .len = 3 };
    if (text.len > 1 and (text[1] == 'c' or text[1] == 'b')) {
        // Parse following color: hex digits up to ']'
        const hex = text[2..];
        const hex_count = for (hex, 0..) |char, n| {
            if (!std.ascii.isHex(char)) break n;
        } else hex.len;

        // Convert hex color text into actual Color
        const value = std.fmt.parseInt(u32, hex[0..hex_count], 16) catch 0;
        return .{
            .kind = if (text[1] == 'c') .foreground else .background,
            .color = rl.getColor(value),
            .len = 2 + hex_count + 1, // Skip "[c" or "[b", color value and ']'
        };
    }
    return null;
}

/// Draw text using inline styling
/// PARAM: color is the default text color, background color is BLANK by default
/// NOTE: Using input color as the base alpha multiplied to inline styles
fn drawTextStyled(font_in: rl.Font, text: [:0]const u8, position: rl.Vector2, font_size: f32, spacing: f32, color: rl.Color) void {
    const font = if (font_in.texture.id == 0) rl.getFontDefault() else font_in;

    var col_front = color;
    var col_back: rl.Color = .blank;
    const back_rec_padding = 4; // Background rectangle padding

    var text_offset_y: f32 = 0.0;
    var text_offset_x: f32 = 0.0;
    const text_line_spacing: f32 = 0.0;
    const scale_factor = font_size / @as(f32, @floatFromInt(font.baseSize));

    var i: usize = 0;
    while (i < text.len) {
        const next = rl.getCodepointNext(text[i..]);
        const codepoint = next.codepoint;

        if (codepoint == '\n') {
            text_offset_y += (font_size + text_line_spacing);
            text_offset_x = 0.0;
        } else {
            if (codepoint == '[') { // Process pipe styling
                if (parseStyleTag(text[i..])) |tag| {
                    switch (tag.kind) {
                        .reset => {
                            col_front = color;
                            col_back = .blank;
                        },
                        .foreground => col_front = tag.color,
                        .background => col_back = tag.color,
                    }
                    i += tag.len;
                    continue; // Do not draw characters
                }
            }

            const index: usize = @intCast(rl.getGlyphIndex(font, codepoint));
            const advance_x = font.glyphs.?[index].advanceX;
            const increase_x = if (advance_x == 0)
                font.recs.?[index].width * scale_factor + spacing
            else
                @as(f32, @floatFromInt(advance_x)) * scale_factor + spacing;

            // Draw background rectangle color (if required)
            if (col_back.a > 0) rl.drawRectangleRec(.{
                .x = position.x + text_offset_x,
                .y = position.y + text_offset_y - back_rec_padding,
                .width = increase_x,
                .height = font_size + 2 * back_rec_padding,
            }, col_back);

            if (codepoint != ' ' and codepoint != '\t') {
                rl.drawTextCodepoint(font, codepoint, .{ .x = position.x + text_offset_x, .y = position.y + text_offset_y }, font_size, col_front);
            }

            text_offset_x += increase_x;
        }

        i += @intCast(next.size);
    }
}

/// Measure inline styled text
/// NOTE: Measuring styled text requires skipping styling data
/// WARNING: Not considering line breaks
fn measureTextStyled(font: rl.Font, text: [:0]const u8, font_size: f32, spacing: f32) rl.Vector2 {
    if (font.texture.id == 0 or text.len == 0) return .{ .x = 0, .y = 0 }; // Security check

    var text_width: f32 = 0.0;
    const text_height = font_size;
    const scale_factor = font_size / @as(f32, @floatFromInt(font.baseSize));

    var valid_codepoint_counter: i32 = 0;

    var i: usize = 0;
    while (i < text.len) {
        const next = rl.getCodepointNext(text[i..]);
        const codepoint = next.codepoint;

        if (codepoint == '[') { // Ignore pipe inline styling
            if (parseStyleTag(text[i..])) |tag| {
                i += tag.len;
                continue; // Do not measure characters
            }
        } else if (codepoint != '\n') {
            const index: usize = @intCast(rl.getGlyphIndex(font, codepoint));
            const glyph = font.glyphs.?[index];

            if (glyph.advanceX > 0) {
                text_width += @floatFromInt(glyph.advanceX);
            } else {
                text_width += (font.recs.?[index].width + @as(f32, @floatFromInt(glyph.offsetX)));
            }

            valid_codepoint_counter += 1;
        }

        i += @intCast(next.size);
    }

    return .{
        .x = text_width * scale_factor + @as(f32, @floatFromInt(valid_codepoint_counter - 1)) * spacing,
        .y = text_height,
    };
}
