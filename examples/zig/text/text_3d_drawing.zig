//! raylib [text] example - 3d drawing
//!
//! Zig-API translation of examples/text/text_3d_drawing.c (raylib 6.2).
//! Example contributed by Vlad Adrian (@demizdor) and reviewed by Ramon Santamaria (@raysan5)
//! Additional contributions: @Nighten for the DrawTextStyle() code
//! (https://github.com/NightenDushi/Raylib_DrawTextStyle), Chris Camacho
//! (codifies - http://bedroomcoders.co.uk/) for the alpha discard shader
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2021-2025 Vlad Adrian (@demizdor)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

const letter_boundry_size = 0.25;
const text_max_layers = 32;
const letter_boundry_color: rl.Color = .violet;

/// Configuration structure for waving the text
const WaveTextConfig = struct {
    wave_range: rl.Vector3,
    wave_speed: rl.Vector3,
    wave_offset: rl.Vector3,
};

/// How a text is laid out and drawn in 3D space
const Text3DStyle = struct {
    font_size: f32,
    font_spacing: f32,
    line_spacing: f32,
    backface: bool,
    letter_boundry: bool = false, // Draw each letter's bounding box
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true, .vsync_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [text] example - 3d drawing");
    defer rl.closeWindow(); // Close window and OpenGL context

    var spin = true; // Spin the camera?
    var multicolor = false; // Multicolor mode
    var show_letter_boundry = false;
    var show_text_boundry = false;

    // Define the camera to look into our 3d world
    var camera: rl.Camera3D = .{
        .position = .{ .x = -10.0, .y = 15.0, .z = -10.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    var camera_mode: rl.CameraMode = .orbital;

    const cube_position: rl.Vector3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 };
    const cube_size: rl.Vector3 = .{ .x = 2.0, .y = 2.0, .z = 2.0 };

    // Use the default font
    var font = rl.getFontDefault();
    defer rl.unloadFont(font);
    var font_size: f32 = 0.8;
    var font_spacing: f32 = 0.05;
    var line_spacing: f32 = -0.1;

    // Set the text (using markdown!)
    var text_buffer: [64]u8 = undefined;
    const initial_text = "Hello ~~World~~ in 3D!";
    var text_len: usize = initial_text.len;
    @memcpy(text_buffer[0..text_len], initial_text);
    text_buffer[text_len] = 0;

    var layers: i32 = 1;
    var layer_distance: f32 = 0.01;

    const wcfg: WaveTextConfig = .{
        .wave_speed = .{ .x = 3.0, .y = 3.0, .z = 0.5 },
        .wave_offset = .{ .x = 0.35, .y = 0.35, .z = 0.35 },
        .wave_range = .{ .x = 0.45, .y = 0.45, .z = 0.45 },
    };

    var time: f32 = 0.0;

    // Setup a light and dark color
    var light: rl.Color = .maroon;
    var dark: rl.Color = .red;

    // Load the alpha discard shader
    const alpha_discard = try rl.loadShader(null, rl.textFormat("resources/shaders/glsl{d}/alpha_discard.fs", .{glsl_version}));
    defer rl.unloadShader(alpha_discard);

    // Array filled with multiple random colors (when multicolor mode is set)
    var multi: [text_max_layers]rl.Color = @splat(.blank);

    rl.disableCursor(); // Limit cursor to relative movement inside the window

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, camera_mode);

        // Handle font files dropped
        if (rl.isFileDropped()) {
            const dropped_files = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(dropped_files); // Unload filepaths from memory

            // NOTE: We only support first ttf file dropped
            const path = std.mem.span(dropped_files.paths.?[0]);
            if (rl.isFileExtension(path, ".ttf")) {
                rl.unloadFont(font);
                font = try rl.loadFontEx(path, @intFromFloat(font_size), null);
            } else if (rl.isFileExtension(path, ".fnt")) {
                rl.unloadFont(font);
                font = try rl.loadFont(path);
                font_size = @floatFromInt(font.baseSize);
            }
        }

        // Handle Events
        if (rl.isKeyPressed(.f1)) show_letter_boundry = !show_letter_boundry;
        if (rl.isKeyPressed(.f2)) show_text_boundry = !show_text_boundry;
        if (rl.isKeyPressed(.f3)) {
            // Handle camera change
            spin = !spin;
            // we need to reset the camera when changing modes
            camera = .{
                .position = if (spin) .{ .x = -10.0, .y = 15.0, .z = -10.0 } else .{ .x = 10.0, .y = 10.0, .z = -10.0 }, // Camera position
                .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
                .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
                .fovy = 45.0, // Camera field-of-view Y
                .projection = .perspective, // Camera mode type
            };
            camera_mode = if (spin) .orbital else .free;
        }

        // Handle clicking the cube
        if (rl.isMouseButtonPressed(.left)) {
            const ray = rl.getScreenToWorldRay(rl.getMousePosition(), camera);

            // Check collision between ray and box
            const collision = rl.getRayCollisionBox(ray, .{
                .min = .{ .x = cube_position.x - cube_size.x / 2, .y = cube_position.y - cube_size.y / 2, .z = cube_position.z - cube_size.z / 2 },
                .max = .{ .x = cube_position.x + cube_size.x / 2, .y = cube_position.y + cube_size.y / 2, .z = cube_position.z + cube_size.z / 2 },
            });
            if (collision.hit) {
                // Generate new random colors
                light = generateRandomColor(0.5, 0.78);
                dark = generateRandomColor(0.4, 0.58);
            }
        }

        // Handle text layers changes
        if (rl.isKeyPressed(.home)) {
            if (layers > 1) layers -= 1;
        } else if (rl.isKeyPressed(.end)) {
            if (layers < text_max_layers) layers += 1;
        }

        // Handle text changes
        if (rl.isKeyPressed(.left)) {
            font_size -= 0.5;
        } else if (rl.isKeyPressed(.right)) {
            font_size += 0.5;
        } else if (rl.isKeyPressed(.up)) {
            font_spacing -= 0.1;
        } else if (rl.isKeyPressed(.down)) {
            font_spacing += 0.1;
        } else if (rl.isKeyPressed(.page_up)) {
            line_spacing -= 0.1;
        } else if (rl.isKeyPressed(.page_down)) {
            line_spacing += 0.1;
        } else if (rl.isKeyDown(.insert)) {
            layer_distance -= 0.001;
        } else if (rl.isKeyDown(.delete)) {
            layer_distance += 0.001;
        } else if (rl.isKeyPressed(.tab)) {
            multicolor = !multicolor; // Enable /disable multicolor mode

            if (multicolor) {
                // Fill color array with random colors
                for (&multi) |*color| {
                    color.* = generateRandomColor(0.5, 0.8);
                    color.a = @truncate(@as(u32, @bitCast(rl.getRandomValue(0, 255))));
                }
            }
        }

        // Handle text input
        const ch = rl.getCharPressed();
        if (rl.isKeyPressed(.backspace)) {
            // Remove last char
            if (text_len > 0) text_len -= 1;
        } else if (rl.isKeyPressed(.enter)) {
            // handle newline
            if (text_len < text_buffer.len - 1) {
                text_buffer[text_len] = '\n';
                text_len += 1;
            }
        } else if (ch != 0) {
            // append only printable chars
            if (text_len < text_buffer.len - 1) {
                text_buffer[text_len] = @truncate(@as(u32, @bitCast(ch)));
                text_len += 1;
            }
        }
        text_buffer[text_len] = 0;
        const text = text_buffer[0..text_len :0];

        const style: Text3DStyle = .{
            .font_size = font_size,
            .font_spacing = font_spacing,
            .line_spacing = line_spacing,
            .backface = true,
            .letter_boundry = show_letter_boundry,
        };

        // Measure 3D text so we can center it
        const tbox = measureTextWave3D(font, text, style);

        var quads: usize = 0; // Reset quad counter
        time += rl.getFrameTime(); // Update timer needed by `drawTextWave3D()`

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawCubeV(cube_position, cube_size, dark);
            rl.drawCubeWires(cube_position, 2.1, 2.1, 2.1, light);

            rl.drawGrid(10, 2.0);

            // Use a shader to handle the depth buffer issue with transparent textures
            // NOTE: more info at https://bedroomcoders.co.uk/posts/198
            rl.beginShaderMode(alpha_discard);
            defer rl.endShaderMode();

            // Draw the 3D text above the red cube
            rl.gl.pushMatrix();
            rl.gl.rotatef(90.0, 1.0, 0.0, 0.0);
            rl.gl.rotatef(90.0, 0.0, 0.0, -1.0);

            for (0..@intCast(layers)) |i| {
                const clr = if (multicolor) multi[i] else light;
                const position: rl.Vector3 = .{ .x = -tbox.x / 2.0, .y = layer_distance * @as(f32, @floatFromInt(i)), .z = -4.5 };
                drawTextWave3D(font, text, position, style, wcfg, time, clr);
            }

            // Draw the text boundry if set
            if (show_text_boundry) rl.drawCubeWiresV(.{ .x = 0.0, .y = 0.0, .z = -4.5 + tbox.z / 2 }, tbox, dark);
            rl.gl.popMatrix();

            // Draw 3D options (use default font)
            // NOTE: letter boundries are not drawn for the 3D text below
            {
                rl.gl.pushMatrix();
                defer rl.gl.popMatrix();
                rl.gl.rotatef(180.0, 0.0, 1.0, 0.0);

                // NOTE: textFormat() reuses a few static buffers: each line is drawn before the next is formatted
                var lines: OptionLines = .{ .pos = .{ .x = 0, .y = 0.01, .z = 2.0 }, .quads = &quads };
                lines.draw(rl.textFormat("< SIZE: {d:2.1} >", .{font_size}), .blue);
                lines.draw(rl.textFormat("< SPACING: {d:2.1} >", .{font_spacing}), .blue);
                lines.draw(rl.textFormat("< LINE: {d:2.1} >", .{line_spacing}), .blue);
                lines.draw(rl.textFormat("< LBOX: {s:>3} >", .{onOff(show_letter_boundry)}), .red);
                lines.draw(rl.textFormat("< TBOX: {s:>3} >", .{onOff(show_text_boundry)}), .red);
                lines.draw(rl.textFormat("< LAYER DISTANCE: {d:.3} >", .{layer_distance}), .dark_purple);
            }

            // Draw 3D info text (use default font)
            const info_lines = [_][:0]const u8{
                "press [Left]/[Right] to change the font size",
                "press [Up]/[Down] to change the font spacing",
                "press [PgUp]/[PgDown] to change the line spacing",
                "press [F1] to toggle the letter boundry",
                "press [F2] to toggle the text boundry",
            };
            const title = "All the text displayed here is in 3D";
            quads += title.len;
            var m = rl.measureTextEx(rl.getFontDefault(), title, 1.0, 0.05);
            var pos: rl.Vector3 = .{ .x = -m.x / 2.0, .y = 0.01, .z = 2.0 };
            drawText3D(rl.getFontDefault(), title, pos, .{ .font_size = 1.0, .font_spacing = 0.05, .line_spacing = 0.0, .backface = false }, .dark_blue);
            pos.z += 1.5 + m.y;

            const info_style: Text3DStyle = .{ .font_size = 0.6, .font_spacing = 0.05, .line_spacing = 0.0, .backface = false };
            for (info_lines) |line| {
                quads += line.len;
                m = rl.measureTextEx(rl.getFontDefault(), line, info_style.font_size, info_style.font_spacing);
                pos.x = -m.x / 2.0;
                drawText3D(rl.getFontDefault(), line, pos, info_style, .dark_blue);
                pos.z += 0.5 + m.y;
            }
        }

        // Draw 2D info text & stats
        rl.drawText("Drag & drop a font file to change the font!\nType something, see what happens!\n\n" ++
            "Press [F3] to toggle the camera", 10, 35, 10, .black);

        quads += text.len * 2 * @as(usize, @intCast(layers));
        const stats = rl.textFormat("{d:>2} layer(s) | {s} camera | {d:>4} quads ({d:>4} verts)", .{ @as(u32, @intCast(layers)), if (spin) "ORBITAL" else "FREE", quads, quads * 4 });
        rl.drawText(stats, screen_width - 20 - rl.measureText(stats, 10), 10, 10, .dark_green);

        const help = [_][:0]const u8{
            "[Home]/[End] to add/remove 3D text layers",
            "[Insert]/[Delete] to increase/decrease distance between layers",
            "click the [CUBE] for a random color",
            "[Tab] to toggle multicolor mode",
        };
        for (help, 0..) |line, i| {
            rl.drawText(line, screen_width - 20 - rl.measureText(line, 10), 25 + 15 * @as(i32, @intCast(i)), 10, .dark_gray);
        }

        rl.drawFPS(10, 10);
    }
}

/// Stacked, centered lines of 3D option text (default font)
const OptionLines = struct {
    const style: Text3DStyle = .{ .font_size = 0.8, .font_spacing = 0.1, .line_spacing = 0.0, .backface = false };

    pos: rl.Vector3,
    quads: *usize,

    fn draw(lines: *OptionLines, text: [:0]const u8, color: rl.Color) void {
        lines.quads.* += text.len;
        const m = rl.measureTextEx(rl.getFontDefault(), text, style.font_size, style.font_spacing);
        lines.pos.x = -m.x / 2.0;
        drawText3D(rl.getFontDefault(), text, lines.pos, style, color);
        lines.pos.z += 0.5 + m.y;
    }
};

fn onOff(on: bool) []const u8 {
    return if (on) "ON" else "OFF";
}

/// Draw codepoint at specified position in 3D space
fn drawTextCodepoint3D(font: rl.Font, codepoint: i32, position: rl.Vector3, style: Text3DStyle, tint: rl.Color) void {
    // Character index position in sprite font
    // NOTE: In case a codepoint is not available in the font, index returned points to '?'
    const index: usize = @intCast(rl.getGlyphIndex(font, codepoint));
    const glyph = font.glyphs.?[index];
    const rec = font.recs.?[index];
    const padding: f32 = @floatFromInt(font.glyphPadding);
    const scale = style.font_size / @as(f32, @floatFromInt(font.baseSize));

    // Character destination rectangle on screen
    // NOTE: We consider charsPadding on drawing
    var pos = position;
    pos.x += @as(f32, @floatFromInt(glyph.offsetX - font.glyphPadding)) * scale;
    pos.z += @as(f32, @floatFromInt(glyph.offsetY - font.glyphPadding)) * scale;

    // Character source rectangle from font texture atlas
    // NOTE: We consider chars padding when drawing, it could be required for outline/glow shader effects
    const src_rec: rl.Rectangle = .{
        .x = rec.x - padding,
        .y = rec.y - padding,
        .width = rec.width + 2.0 * padding,
        .height = rec.height + 2.0 * padding,
    };

    const width = src_rec.width * scale;
    const height = src_rec.height * scale;

    if (font.texture.id == 0) return;

    const x = 0.0;
    const y = 0.0;
    const z = 0.0;

    // normalized texture coordinates of the glyph inside the font texture (0.0 -> 1.0)
    const tex_width: f32 = @floatFromInt(font.texture.width);
    const tex_height: f32 = @floatFromInt(font.texture.height);
    const tx = src_rec.x / tex_width;
    const ty = src_rec.y / tex_height;
    const tw = (src_rec.x + src_rec.width) / tex_width;
    const th = (src_rec.y + src_rec.height) / tex_height;

    if (style.letter_boundry) rl.drawCubeWiresV(.{ .x = pos.x + width / 2, .y = pos.y, .z = pos.z + height / 2 }, .{ .x = width, .y = letter_boundry_size, .z = height }, letter_boundry_color);

    _ = rl.gl.checkRenderBatchLimit(4 + 4 * @as(i32, @intFromBool(style.backface)));
    rl.gl.setTexture(font.texture.id);
    defer rl.gl.setTexture(0);

    rl.gl.pushMatrix();
    defer rl.gl.popMatrix();
    rl.gl.translatef(pos.x, pos.y, pos.z);

    rl.gl.begin(rl.gl.quads);
    defer rl.gl.end();
    rl.gl.color4ub(tint.r, tint.g, tint.b, tint.a);

    // Front Face
    rl.gl.normal3f(0.0, 1.0, 0.0); // Normal Pointing Up
    rl.gl.texCoord2f(tx, ty);
    rl.gl.vertex3f(x, y, z); // Top Left Of The Texture and Quad
    rl.gl.texCoord2f(tx, th);
    rl.gl.vertex3f(x, y, z + height); // Bottom Left Of The Texture and Quad
    rl.gl.texCoord2f(tw, th);
    rl.gl.vertex3f(x + width, y, z + height); // Bottom Right Of The Texture and Quad
    rl.gl.texCoord2f(tw, ty);
    rl.gl.vertex3f(x + width, y, z); // Top Right Of The Texture and Quad

    if (style.backface) {
        // Back Face
        rl.gl.normal3f(0.0, -1.0, 0.0); // Normal Pointing Down
        rl.gl.texCoord2f(tx, ty);
        rl.gl.vertex3f(x, y, z); // Top Right Of The Texture and Quad
        rl.gl.texCoord2f(tw, ty);
        rl.gl.vertex3f(x + width, y, z); // Top Left Of The Texture and Quad
        rl.gl.texCoord2f(tw, th);
        rl.gl.vertex3f(x + width, y, z + height); // Bottom Left Of The Texture and Quad
        rl.gl.texCoord2f(tx, th);
        rl.gl.vertex3f(x, y, z + height); // Bottom Right Of The Texture and Quad
    }
}

/// Horizontal advance of the glyph at `index` (unscaled)
fn glyphAdvance(font: rl.Font, index: usize) f32 {
    const advance_x = font.glyphs.?[index].advanceX;
    if (advance_x == 0) return font.recs.?[index].width;
    return @floatFromInt(advance_x);
}

/// Draw a 2D text in 3D space
fn drawText3D(font: rl.Font, text: [:0]const u8, position: rl.Vector3, style: Text3DStyle, tint: rl.Color) void {
    var text_offset_y: f32 = 0.0; // Offset between lines (on line break '\n')
    var text_offset_x: f32 = 0.0; // Offset X to next character to draw

    const scale = style.font_size / @as(f32, @floatFromInt(font.baseSize));

    var i: usize = 0;
    while (i < text.len) {
        // Get next codepoint from byte string and glyph index in font
        const next = rl.getCodepoint(text[i..]);
        const index: usize = @intCast(rl.getGlyphIndex(font, next.codepoint));

        // NOTE: Normally we exit the decoding sequence as soon as a bad byte is found (and return 0x3f)
        // but we need to draw all of the bad bytes using the '?' symbol moving one byte
        const codepoint_byte_count: usize = if (next.codepoint == 0x3f) 1 else @intCast(next.size);

        if (next.codepoint == '\n') {
            // NOTE: Fixed line spacing of 1.5 line-height
            // TODO: Support custom line spacing defined by user
            text_offset_y += style.font_size + style.line_spacing;
            text_offset_x = 0.0;
        } else {
            if (next.codepoint != ' ' and next.codepoint != '\t') {
                drawTextCodepoint3D(font, next.codepoint, .{ .x = position.x + text_offset_x, .y = position.y, .z = position.z + text_offset_y }, style, tint);
            }

            text_offset_x += glyphAdvance(font, index) * scale + style.font_spacing;
        }

        i += codepoint_byte_count; // Move text bytes counter to next codepoint
    }
}

/// Draw a 2D text in 3D space and wave the parts that start with `~~` and end with `~~`
/// This is a modified version of the original code by @Nighten found here https://github.com/NightenDushi/Raylib_DrawTextStyle
fn drawTextWave3D(font: rl.Font, text: [:0]const u8, position: rl.Vector3, style: Text3DStyle, config: WaveTextConfig, time: f32, tint: rl.Color) void {
    var text_offset_y: f32 = 0.0; // Offset between lines (on line break '\n')
    var text_offset_x: f32 = 0.0; // Offset X to next character to draw

    const scale = style.font_size / @as(f32, @floatFromInt(font.baseSize));

    var wave = false;

    var i: usize = 0;
    var k: i32 = 0;
    while (i < text.len) : (k += 1) {
        // Get next codepoint from byte string and glyph index in font
        const next = rl.getCodepoint(text[i..]);
        const index: usize = @intCast(rl.getGlyphIndex(font, next.codepoint));

        // NOTE: Normally we exit the decoding sequence as soon as a bad byte is found (and return 0x3f)
        // but we need to draw all of the bad bytes using the '?' symbol moving one byte
        var codepoint_byte_count: usize = if (next.codepoint == 0x3f) 1 else @intCast(next.size);

        if (next.codepoint == '\n') {
            // NOTE: Fixed line spacing of 1.5 line-height
            // TODO: Support custom line spacing defined by user
            text_offset_y += style.font_size + style.line_spacing;
            text_offset_x = 0.0;
            k = 0;
        } else if (next.codepoint == '~') {
            // NOTE: Like the C original, the byte count becomes the following codepoint's size
            const following = rl.getCodepoint(text[i + 1 ..]);
            codepoint_byte_count = @intCast(following.size);
            if (following.codepoint == '~') {
                codepoint_byte_count += 1;
                wave = !wave;
            }
        } else {
            if (next.codepoint != ' ' and next.codepoint != '\t') {
                var pos = position;
                if (wave) { // Apply the wave effect
                    const fk: f32 = @floatFromInt(k);
                    pos.x += @sin(time * config.wave_speed.x - fk * config.wave_offset.x) * config.wave_range.x;
                    pos.y += @sin(time * config.wave_speed.y - fk * config.wave_offset.y) * config.wave_range.y;
                    pos.z += @sin(time * config.wave_speed.z - fk * config.wave_offset.z) * config.wave_range.z;
                }

                drawTextCodepoint3D(font, next.codepoint, .{ .x = pos.x + text_offset_x, .y = pos.y, .z = pos.z + text_offset_y }, style, tint);
            }

            text_offset_x += glyphAdvance(font, index) * scale + style.font_spacing;
        }

        i += codepoint_byte_count; // Move text bytes counter to next codepoint
    }
}

/// Measure a text in 3D ignoring the `~~` chars
fn measureTextWave3D(font: rl.Font, text: [:0]const u8, style: Text3DStyle) rl.Vector3 {
    var temp_len: i32 = 0; // Used to count longer text line num chars
    var len_counter: i32 = 0;

    var temp_text_width: f32 = 0.0; // Used to count longer text line width

    const scale = style.font_size / @as(f32, @floatFromInt(font.baseSize));
    var text_height = scale;
    var text_width: f32 = 0.0;

    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const next = rl.getCodepoint(text[i..]);
        const letter = next.codepoint; // Current character
        const index: usize = @intCast(rl.getGlyphIndex(font, letter)); // Index position in sprite font

        // NOTE: normally we exit the decoding sequence as soon as a bad byte is found (and return 0x3f)
        // but we need to draw all of the bad bytes using the '?' symbol so to not skip any we set next = 1
        const size: usize = if (letter == 0x3f) 1 else @intCast(next.size);
        i += size - 1;

        if (letter != '\n') {
            if (letter == '~' and rl.getCodepoint(text[i + 1 ..]).codepoint == '~') {
                i += 1;
            } else {
                len_counter += 1;
                const glyph = font.glyphs.?[index];
                if (glyph.advanceX != 0) {
                    text_width += @as(f32, @floatFromInt(glyph.advanceX)) * scale;
                } else {
                    text_width += (font.recs.?[index].width + @as(f32, @floatFromInt(glyph.offsetX))) * scale;
                }
            }
        } else {
            temp_text_width = @max(temp_text_width, text_width);
            len_counter = 0;
            text_width = 0.0;
            text_height += style.font_size + style.line_spacing;
        }

        temp_len = @max(temp_len, len_counter);
    }

    temp_text_width = @max(temp_text_width, text_width);

    return .{
        .x = temp_text_width + @as(f32, @floatFromInt(temp_len - 1)) * style.font_spacing, // Adds chars spacing to measure
        .y = 0.25,
        .z = text_height,
    };
}

/// Generates a nice color with a random hue
fn generateRandomColor(s: f32, v: f32) rl.Color {
    const phi: f32 = 0.618033988749895; // Golden ratio conjugate
    var h: f32 = @floatFromInt(rl.getRandomValue(0, 360));
    h = @rem(h + h * phi, 360.0);
    return rl.colorFromHSV(h, s, v);
}
