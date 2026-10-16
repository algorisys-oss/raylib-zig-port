//! raylib [textures] example - image rotate
//!
//! Zig-API translation of examples/textures/textures_image_rotate.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - image rotate");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)
    const rotations = [_]i32{ 45, 90, -90 };

    var textures: [rotations.len]rl.Texture2D = undefined;
    var loaded: usize = 0;
    defer for (textures[0..loaded]) |texture| rl.unloadTexture(texture);
    for (rotations) |degrees| {
        var image = try rl.loadImage("resources/raylib_logo.png");
        defer rl.unloadImage(image);
        rl.imageRotate(&image, degrees);
        textures[loaded] = try rl.loadTextureFromImage(image);
        loaded += 1;
    }

    var current_texture: usize = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isMouseButtonPressed(.left) or rl.isKeyPressed(.right)) {
            current_texture = (current_texture + 1) % textures.len; // Cycle between the textures
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        const texture = textures[current_texture];
        rl.drawTexture(texture, screen_width / 2 - @divTrunc(texture.width, 2), screen_height / 2 - @divTrunc(texture.height, 2), .white);

        rl.drawText("Press LEFT MOUSE BUTTON to rotate the image clockwise", 250, 420, 10, .dark_gray);
    }
}
