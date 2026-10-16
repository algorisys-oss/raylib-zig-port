//! raylib [textures] example - image generation
//!
//! Zig-API translation of examples/textures/textures_image_generation.c (raylib 6.2).
//! Example contributed by Wilhem Barbier (@nounoursheureux) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2017-2025 Wilhem Barbier (@nounoursheureux) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

/// On-screen label of each generated texture
const Label = struct { text: [:0]const u8, x: i32, color: rl.Color };

// Currently we have 8 generation algorithms but some have multiple purposes (Linear and Square Gradients)
const labels = [_]Label{
    .{ .text = "VERTICAL GRADIENT", .x = 560, .color = .ray_white },
    .{ .text = "HORIZONTAL GRADIENT", .x = 540, .color = .ray_white },
    .{ .text = "DIAGONAL GRADIENT", .x = 540, .color = .ray_white },
    .{ .text = "RADIAL GRADIENT", .x = 580, .color = .light_gray },
    .{ .text = "SQUARE GRADIENT", .x = 580, .color = .light_gray },
    .{ .text = "CHECKED", .x = 680, .color = .ray_white },
    .{ .text = "WHITE NOISE", .x = 640, .color = .red },
    .{ .text = "PERLIN NOISE", .x = 640, .color = .red },
    .{ .text = "CELLULAR", .x = 670, .color = .ray_white },
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - image generation");
    defer rl.closeWindow(); // Close window and OpenGL context

    const images = [labels.len]rl.Image{
        rl.genImageGradientLinear(screen_width, screen_height, 0, .red, .blue), // vertical
        rl.genImageGradientLinear(screen_width, screen_height, 90, .red, .blue), // horizontal
        rl.genImageGradientLinear(screen_width, screen_height, 45, .red, .blue), // diagonal
        rl.genImageGradientRadial(screen_width, screen_height, 0.0, .white, .black),
        rl.genImageGradientSquare(screen_width, screen_height, 0.0, .white, .black),
        rl.genImageChecked(screen_width, screen_height, 32, 32, .red, .blue),
        rl.genImageWhiteNoise(screen_width, screen_height, 0.5),
        rl.genImagePerlinNoise(screen_width, screen_height, 50, 50, 4.0),
        rl.genImageCellular(screen_width, screen_height, 32),
    };

    var textures: [labels.len]rl.Texture2D = undefined;
    var loaded: usize = 0;
    // Unload textures data (GPU VRAM)
    defer for (textures[0..loaded]) |texture| rl.unloadTexture(texture);
    for (images) |image| {
        textures[loaded] = try rl.loadTextureFromImage(image);
        loaded += 1;
    }

    // Unload image data (CPU RAM)
    for (images) |image| rl.unloadImage(image);

    var current_texture: usize = 0;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        if (rl.isMouseButtonPressed(.left) or rl.isKeyPressed(.right)) {
            current_texture = (current_texture + 1) % textures.len; // Cycle between the textures
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawTexture(textures[current_texture], 0, 0, .white);

        rl.drawRectangle(30, 400, 325, 30, rl.fade(.sky_blue, 0.5));
        rl.drawRectangleLines(30, 400, 325, 30, rl.fade(.white, 0.5));
        rl.drawText("MOUSE LEFT BUTTON to CYCLE PROCEDURAL TEXTURES", 40, 410, 10, .white);

        const label = labels[current_texture];
        rl.drawText(label.text, label.x, 10, 20, label.color);
    }
}
