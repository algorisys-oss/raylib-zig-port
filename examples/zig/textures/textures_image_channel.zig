//! raylib [textures] example - image channel
//!
//! NOTE: Images are loaded in CPU memory (RAM); textures are loaded in GPU memory (VRAM)
//!
//! Zig-API translation of examples/textures/textures_image_channel.c (raylib 6.2).
//! Example contributed by Bruno Cabral (@brccabral) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2024-2025 Bruno Cabral (@brccabral) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - image channel");
    defer rl.closeWindow(); // Close window and OpenGL context

    const fudesumi_image = try rl.loadImage("resources/fudesumi.png");

    var image_alpha = rl.imageFromChannel(fudesumi_image, 3);
    rl.imageAlphaMask(&image_alpha, image_alpha);

    var image_red = rl.imageFromChannel(fudesumi_image, 0);
    rl.imageAlphaMask(&image_red, image_alpha);

    var image_green = rl.imageFromChannel(fudesumi_image, 1);
    rl.imageAlphaMask(&image_green, image_alpha);

    var image_blue = rl.imageFromChannel(fudesumi_image, 2);
    rl.imageAlphaMask(&image_blue, image_alpha);

    const background_image = rl.genImageChecked(screen_width, screen_height, screen_width / 20, screen_height / 20, .orange, .yellow);

    const fudesumi_texture = try rl.loadTextureFromImage(fudesumi_image);
    defer rl.unloadTexture(fudesumi_texture);
    const texture_alpha = try rl.loadTextureFromImage(image_alpha);
    defer rl.unloadTexture(texture_alpha);
    const texture_red = try rl.loadTextureFromImage(image_red);
    defer rl.unloadTexture(texture_red);
    const texture_green = try rl.loadTextureFromImage(image_green);
    defer rl.unloadTexture(texture_green);
    const texture_blue = try rl.loadTextureFromImage(image_blue);
    defer rl.unloadTexture(texture_blue);
    const background_texture = try rl.loadTextureFromImage(background_image);
    defer rl.unloadTexture(background_texture);

    rl.unloadImage(fudesumi_image);
    rl.unloadImage(image_alpha);
    rl.unloadImage(image_red);
    rl.unloadImage(image_green);
    rl.unloadImage(image_blue);
    rl.unloadImage(background_image);

    const fudesumi_width: f32 = @floatFromInt(fudesumi_image.width);
    const fudesumi_height: f32 = @floatFromInt(fudesumi_image.height);
    const fudesumi_rec: rl.Rectangle = .{ .x = 0, .y = 0, .width = fudesumi_width, .height = fudesumi_height };

    const fudesumi_pos: rl.Rectangle = .{ .x = 50, .y = 10, .width = fudesumi_width * 0.8, .height = fudesumi_height * 0.8 };
    const half_width = fudesumi_pos.width / 2.0;
    const half_height = fudesumi_pos.height / 2.0;
    const red_pos: rl.Rectangle = .{ .x = 410, .y = 10, .width = half_width, .height = half_height };
    const green_pos: rl.Rectangle = .{ .x = 600, .y = 10, .width = half_width, .height = half_height };
    const blue_pos: rl.Rectangle = .{ .x = 410, .y = 230, .width = half_width, .height = half_height };
    const alpha_pos: rl.Rectangle = .{ .x = 600, .y = 230, .width = half_width, .height = half_height };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Nothing to update...

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        const origin: rl.Vector2 = .{ .x = 0, .y = 0 };
        rl.drawTexture(background_texture, 0, 0, .white);
        rl.drawTexturePro(fudesumi_texture, fudesumi_rec, fudesumi_pos, origin, 0, .white);

        rl.drawTexturePro(texture_red, fudesumi_rec, red_pos, origin, 0, .red);
        rl.drawTexturePro(texture_green, fudesumi_rec, green_pos, origin, 0, .green);
        rl.drawTexturePro(texture_blue, fudesumi_rec, blue_pos, origin, 0, .blue);
        rl.drawTexturePro(texture_alpha, fudesumi_rec, alpha_pos, origin, 0, .white);
    }
}
