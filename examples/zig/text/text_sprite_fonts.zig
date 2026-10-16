//! raylib [text] example - sprite fonts
//!
//! NOTE: raylib is distributed with some free to use fonts (even for commercial pourposes!)
//!       To view details and credits for those fonts, check raylib license file
//!
//! Zig-API translation of examples/text/text_sprite_fonts.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const FontSample = struct {
    file: [:0]const u8,
    message: [:0]const u8,
    spacing: f32,
    color: rl.Color,
};

const samples = [_]FontSample{
    .{ .file = "resources/sprite_fonts/alagard.png", .message = "ALAGARD FONT designed by Hewett Tsoi", .spacing = 2, .color = .maroon },
    .{ .file = "resources/sprite_fonts/pixelplay.png", .message = "PIXELPLAY FONT designed by Aleksander Shevchuk", .spacing = 4, .color = .orange },
    .{ .file = "resources/sprite_fonts/mecha.png", .message = "MECHA FONT designed by Captain Falcon", .spacing = 8, .color = .dark_green },
    .{ .file = "resources/sprite_fonts/setback.png", .message = "SETBACK FONT designed by Brian Kent (AEnigma)", .spacing = 4, .color = .dark_blue },
    .{ .file = "resources/sprite_fonts/romulus.png", .message = "ROMULUS FONT designed by Hewett Tsoi", .spacing = 3, .color = .dark_purple },
    .{ .file = "resources/sprite_fonts/pixantiqua.png", .message = "PIXANTIQUA FONT designed by Gerhard Grossmann", .spacing = 4, .color = .lime },
    .{ .file = "resources/sprite_fonts/alpha_beta.png", .message = "ALPHA_BETA FONT designed by Brian Kent (AEnigma)", .spacing = 4, .color = .gold },
    .{ .file = "resources/sprite_fonts/jupiter_crash.png", .message = "JUPITER_CRASH FONT designed by Brian Kent (AEnigma)", .spacing = 1, .color = .red },
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - sprite fonts");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)
    var fonts: [samples.len]rl.Font = undefined;
    for (&fonts, samples) |*font, sample| font.* = try rl.loadFont(sample.file);
    defer for (fonts) |font| rl.unloadFont(font); // Fonts unloading

    var positions: [samples.len]rl.Vector2 = undefined;
    for (&positions, fonts, samples, 0..) |*position, font, sample, i| {
        const base_size: f32 = @floatFromInt(font.baseSize);
        position.x = screen_width / 2.0 - rl.measureTextEx(font, sample.message, base_size * 2.0, sample.spacing).x / 2.0;
        position.y = 60.0 + base_size + 45.0 * @as(f32, @floatFromInt(i));
    }

    // Small Y position corrections
    positions[3].y += 8;
    positions[4].y += 2;
    positions[7].y -= 8;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("free sprite fonts included with raylib", 220, 20, 20, .dark_gray);
        rl.drawLine(220, 50, 600, 50, .dark_gray);

        for (fonts, samples, positions) |font, sample, position| {
            const base_size: f32 = @floatFromInt(font.baseSize);
            rl.drawTextEx(font, sample.message, position, base_size * 2.0, sample.spacing, sample.color);
        }
    }
}
