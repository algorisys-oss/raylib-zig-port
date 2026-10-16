//! raylib [text] example - font spritefont
//!
//! NOTE: Sprite fonts should be generated following this conventions:
//!   - Characters must be ordered starting with character 32 (Space)
//!   - Every character must be contained within the same Rectangle height
//!   - Every character and every line must be separated by the same distance (margin/padding)
//!   - Rectangles must be defined by a MAGENTA color background
//!
//! Following those constraints, a font can be provided just by an image,
//! this is quite handy to avoid additional font descriptor files (like BMFonts use)
//!
//! Zig-API translation of examples/text/text_font_spritefont.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - font spritefont");
    defer rl.closeWindow(); // Close window and OpenGL context

    const msg1 = "THIS IS A custom SPRITE FONT...";
    const msg2 = "...and this is ANOTHER CUSTOM font...";
    const msg3 = "...and a THIRD one! GREAT! :D";

    // NOTE: Textures/Fonts MUST be loaded after Window initialization (OpenGL context is required)
    const font1 = try rl.loadFont("resources/custom_mecha.png"); // Font loading
    defer rl.unloadFont(font1);
    const font2 = try rl.loadFont("resources/custom_alagard.png"); // Font loading
    defer rl.unloadFont(font2);
    const font3 = try rl.loadFont("resources/custom_jupiter_crash.png"); // Font loading
    defer rl.unloadFont(font3);

    const font_position1: rl.Vector2 = .{
        .x = screen_width / 2.0 - rl.measureTextEx(font1, msg1, @floatFromInt(font1.baseSize), -3).x / 2,
        .y = screen_height / 2.0 - @as(f32, @floatFromInt(font1.baseSize)) / 2.0 - 80.0,
    };

    const font_position2: rl.Vector2 = .{
        .x = screen_width / 2.0 - rl.measureTextEx(font2, msg2, @floatFromInt(font2.baseSize), -2.0).x / 2.0,
        .y = screen_height / 2.0 - @as(f32, @floatFromInt(font2.baseSize)) / 2.0 - 10.0,
    };

    const font_position3: rl.Vector2 = .{
        .x = screen_width / 2.0 - rl.measureTextEx(font3, msg3, @floatFromInt(font3.baseSize), 2.0).x / 2.0,
        .y = screen_height / 2.0 - @as(f32, @floatFromInt(font3.baseSize)) / 2.0 + 50.0,
    };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawTextEx(font1, msg1, font_position1, @floatFromInt(font1.baseSize), -3, .white);
        rl.drawTextEx(font2, msg2, font_position2, @floatFromInt(font2.baseSize), -2, .white);
        rl.drawTextEx(font3, msg3, font_position3, @floatFromInt(font3.baseSize), 2, .white);
    }
}
