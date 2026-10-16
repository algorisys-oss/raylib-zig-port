//! raylib [textures] example - to image
//!
//! NOTE: Images are loaded in CPU memory (RAM); textures are loaded in GPU memory (VRAM)
//!
//! Zig-API translation of examples/textures/textures_to_image.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - to image");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)

    const texture = blk: {
        const image = try rl.loadImage("resources/raylib_logo.png"); // Load image data into CPU memory (RAM)
        const original = try rl.loadTextureFromImage(image); // Image converted to texture, GPU memory (RAM -> VRAM)
        rl.unloadImage(image); // Unload image data from CPU memory (RAM)

        const retrieved = try rl.loadImageFromTexture(original); // Load image from GPU texture (VRAM -> RAM)
        defer rl.unloadImage(retrieved); // Unload retrieved image data from CPU memory (RAM)
        rl.unloadTexture(original); // Unload texture from GPU memory (VRAM)

        break :blk try rl.loadTextureFromImage(retrieved); // Recreate texture from retrieved image data (RAM -> VRAM)
    };
    defer rl.unloadTexture(texture); // Texture unloading

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawTexture(texture, screen_width / 2 - @divTrunc(texture.width, 2), screen_height / 2 - @divTrunc(texture.height, 2), .white);

        rl.drawText("this IS a texture loaded from an image!", 300, 370, 10, .gray);
    }
}
