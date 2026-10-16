//! raylib [textures] example - blend modes
//!
//! NOTE: Images are loaded in CPU memory (RAM); textures are loaded in GPU memory (VRAM)
//!
//! Zig-API translation of examples/textures/textures_blend_modes.c (raylib 6.2).
//! Example contributed by Karlo Licudine (@accidentalrebel) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2020-2025 Karlo Licudine (@accidentalrebel)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - blend modes");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)
    const bg_image = try rl.loadImage("resources/cyberpunk_street_background.png"); // Loaded in CPU memory (RAM)
    const bg_texture = try rl.loadTextureFromImage(bg_image); // Image converted to texture, GPU memory (VRAM)
    defer rl.unloadTexture(bg_texture);

    const fg_image = try rl.loadImage("resources/cyberpunk_street_foreground.png"); // Loaded in CPU memory (RAM)
    const fg_texture = try rl.loadTextureFromImage(fg_image); // Image converted to texture, GPU memory (VRAM)
    defer rl.unloadTexture(fg_texture);

    // Once image has been converted to texture and uploaded to VRAM, it can be unloaded from RAM
    rl.unloadImage(bg_image);
    rl.unloadImage(fg_image);

    // The blend modes cycled through with SPACE
    const blend_modes = [_]rl.BlendMode{ .alpha, .additive, .multiplied, .add_colors };
    var blend_index: usize = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.space)) blend_index = (blend_index + 1) % blend_modes.len;
        const blend_mode = blend_modes[blend_index];

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawTexture(bg_texture, @divTrunc(screen_width, 2) - @divTrunc(bg_texture.width, 2), @divTrunc(screen_height, 2) - @divTrunc(bg_texture.height, 2), .white);

        // Apply the blend mode and then draw the foreground texture
        rl.beginBlendMode(blend_mode);
        rl.drawTexture(fg_texture, @divTrunc(screen_width, 2) - @divTrunc(fg_texture.width, 2), @divTrunc(screen_height, 2) - @divTrunc(fg_texture.height, 2), .white);
        rl.endBlendMode();

        // Draw the texts
        rl.drawText("Press SPACE to change blend modes.", 310, 350, 10, .gray);

        const label: [:0]const u8 = switch (blend_mode) {
            .alpha => "Current: BLEND_ALPHA",
            .additive => "Current: BLEND_ADDITIVE",
            .multiplied => "Current: BLEND_MULTIPLIED",
            .add_colors => "Current: BLEND_ADD_COLORS",
            else => unreachable,
        };
        rl.drawText(label, (screen_width / 2) - 60, 370, 10, .gray);

        rl.drawText("(c) Cyberpunk Street Environment by Luis Zuno (@ansimuz)", screen_width - 330, screen_height - 20, 10, .gray);
    }
}
