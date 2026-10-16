//! raylib [textures] example - background scrolling
//!
//! Zig-API translation of examples/textures/textures_background_scrolling.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - background scrolling");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Be careful, background width must be equal or bigger than screen width
    // if not, texture should be draw more than two times for scrolling effect
    const background = try rl.loadTexture("resources/cyberpunk_street_background.png");
    defer rl.unloadTexture(background);
    const midground = try rl.loadTexture("resources/cyberpunk_street_midground.png");
    defer rl.unloadTexture(midground);
    const foreground = try rl.loadTexture("resources/cyberpunk_street_foreground.png");
    defer rl.unloadTexture(foreground);

    var scrolling_back: f32 = 0.0;
    var scrolling_mid: f32 = 0.0;
    var scrolling_fore: f32 = 0.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        scrolling_back -= 0.1;
        scrolling_mid -= 0.5;
        scrolling_fore -= 1.0;

        // NOTE: Texture is scaled twice its size, so it sould be considered on scrolling
        if (scrolling_back <= @as(f32, @floatFromInt(-background.width * 2))) scrolling_back = 0;
        if (scrolling_mid <= @as(f32, @floatFromInt(-midground.width * 2))) scrolling_mid = 0;
        if (scrolling_fore <= @as(f32, @floatFromInt(-foreground.width * 2))) scrolling_fore = 0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.getColor(0x052c46ff));

        // Draw each layer twice, side by side
        // NOTE: Texture is scaled twice its size
        drawLayer(background, scrolling_back, 20);
        drawLayer(midground, scrolling_mid, 20);
        drawLayer(foreground, scrolling_fore, 70);

        rl.drawText("BACKGROUND SCROLLING & PARALLAX", 10, 10, 20, .red);
        rl.drawText("(c) Cyberpunk Street Environment by Luis Zuno (@ansimuz)", screen_width - 330, screen_height - 20, 10, .ray_white);
    }
}

/// Draw a texture twice at 2x scale, the second copy right after the first.
fn drawLayer(texture: rl.Texture2D, scrolling: f32, y: f32) void {
    const width: f32 = @floatFromInt(texture.width * 2);
    rl.drawTextureEx(texture, .{ .x = scrolling, .y = y }, 0.0, 2.0, .white);
    rl.drawTextureEx(texture, .{ .x = width + scrolling, .y = y }, 0.0, 2.0, .white);
}
