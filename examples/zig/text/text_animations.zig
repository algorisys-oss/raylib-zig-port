//! raylib [text] example - animations
//!
//! Zig-API translation of examples/text/text_animations.c (raylib 6.2).
//! Example contributed by Gabriel Piangers (@gabriel-piangers) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Gabriel Piangers (@gabriel-piangers)

const rl = @import("raylib");
const reasings = @import("reasings"); // Required for: Easing functions

const max_text_length = 64;
const text_spacing = 4;

/// Animated text type
const AnimatedText = struct {
    str: [:0]const u8, // Text to animate
    position: rl.Vector2, // Text position on screen
    delta: f32, // Intensity of the effect (does not apply for flashing)
    offset: f32, // Time offset (in frames) between each char
    duration: f32, // Time duration (in frames) of the animation
};

const animations = [_][:0]const u8{ "Waving", "Flashing", "Shaking" };

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - animations");
    defer rl.closeWindow(); // Close window and OpenGL context

    var current_animation: usize = 0;

    var text: AnimatedText = .{
        .str = "This is an animated text!",
        .position = .{ .x = 200, .y = 250 },
        .delta = 24.0,
        .offset = 6,
        .duration = 60,
    };
    var frame_count: i32 = 0;

    var glyph_position: [max_text_length]rl.Vector2 = undefined;
    var glyph_alpha: [max_text_length]u8 = undefined;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        frame_count += 1;

        if (rl.isKeyPressed(.s)) {
            text.delta = rl.math.clamp(text.delta - 2.0, 10.0, 60.0);
        } else if (rl.isKeyPressed(.w)) {
            text.delta = rl.math.clamp(text.delta + 2.0, 10.0, 60.0);
        }
        if (rl.isKeyPressed(.a)) {
            text.duration = @trunc(rl.math.clamp(text.duration - 5.0, 20.0, 120.0));
        } else if (rl.isKeyPressed(.d)) {
            text.duration = @trunc(rl.math.clamp(text.duration + 5.0, 20.0, 120.0));
        }
        if (rl.isKeyPressed(.z)) {
            text.offset = rl.math.clamp(text.offset - 1.0, 0.0, 15.0);
        } else if (rl.isKeyPressed(.x)) {
            text.offset = rl.math.clamp(text.offset + 1.0, 0.0, 15.0);
        }
        if (rl.isKeyPressed(.q)) {
            current_animation = if (current_animation == 0) animations.len - 1 else current_animation - 1;
        } else if (rl.isKeyPressed(.e)) {
            current_animation = (current_animation + 1) % animations.len;
        }

        const glyph_count = text.str.len;

        // NOTE: Calculating every glyph position by its width
        var offset_x: u32 = 0;
        for (text.str, glyph_position[0..glyph_count], glyph_alpha[0..glyph_count]) |char, *position, *alpha| {
            position.* = .{ .x = text.position.x + @as(f32, @floatFromInt(offset_x)), .y = text.position.y };
            alpha.* = 255;

            const glyph = [1:0]u8{char};
            offset_x += @intCast(rl.measureText(&glyph, 30) + text_spacing);
        }

        const duration: i32 = @intFromFloat(text.duration);
        for (glyph_position[0..glyph_count], glyph_alpha[0..glyph_count], 0..) |*position, *alpha, i| {
            const char_frame = @as(f32, @floatFromInt(frame_count)) + @as(f32, @floatFromInt(i)) * text.offset;
            const time: f32 = @floatFromInt(@rem(@as(i32, @intFromFloat(char_frame)), duration));

            switch (current_animation) {
                0 => { // Waving animation
                    if (time < text.duration / 2) {
                        position.y = reasings.easeSineIn(time, text.position.y, text.delta, text.duration);
                    } else {
                        position.y = reasings.easeSineOut(time, text.position.y + text.delta, -text.delta, text.duration);
                    }
                },
                1 => { // Flashing animation
                    alpha.* = @intFromFloat(reasings.easeSineInOut(time, 255.0, -255.0, text.duration));
                },
                2 => { // Shaking animation
                    const shake: i32 = @intFromFloat(text.delta / 10);
                    const shake_min: i32 = @intFromFloat(-text.delta / 10);
                    const delta_x: f32 = @floatFromInt(rl.getRandomValue(shake_min, shake));
                    const delta_y: f32 = @floatFromInt(rl.getRandomValue(shake_min, shake));
                    const half = text.duration / 2;

                    if (time < half) {
                        position.x = reasings.easeLinearNone(time, position.x, delta_x, half);
                        position.y = reasings.easeLinearNone(time, text.position.y, delta_y, half);
                    } else {
                        position.x = reasings.easeLinearNone(time - half, position.x + delta_x, -delta_x, half);
                        position.y = reasings.easeLinearNone(time - half, text.position.y + delta_y, -delta_y, half);
                    }
                },
                else => unreachable,
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText(rl.textFormat("Duration (A | D): {d}", .{duration}), 20, 20, 20, .gray);
        rl.drawText(rl.textFormat("Delta (W | S): {d:.1}", .{text.delta}), 20, 50, 20, .gray);
        rl.drawText(rl.textFormat("Offset (Z | X): {d:.1}", .{text.offset}), 20, 80, 20, .gray);
        rl.drawText(rl.textFormat("Curent Animation (Q | E): {s}", .{animations[current_animation]}), 20, 110, 20, .gray);

        const font = rl.getFontDefault();
        for (text.str, glyph_position[0..glyph_count], glyph_alpha[0..glyph_count]) |char, position, alpha| {
            // NOTE: Drawing text glyph by glyph, so, spacing is actually not used
            const glyph = [1:0]u8{char};
            const font_size = @as(f32, @floatFromInt(font.baseSize)) * 3.0;
            rl.drawTextEx(font, &glyph, position, font_size, 0, .{ .r = 200, .g = 122, .b = 255, .a = alpha });
        }
    }
}
