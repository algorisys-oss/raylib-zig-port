//! raylib [textures] example - image kernel
//!
//! NOTE: Images are loaded in CPU memory (RAM); textures are loaded in GPU memory (VRAM)
//!
//! Zig-API translation of examples/textures/textures_image_kernel.c (raylib 6.2).
//! Example contributed by Karim Salem (@kimo-s) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Karim Salem (@kimo-s)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - image kernel");
    defer rl.closeWindow(); // Close window and OpenGL context

    var image = try rl.loadImage("resources/cat.png"); // Loaded in CPU memory (RAM)

    var gaussian_kernel = [_]f32{
        1.0, 2.0, 1.0,
        2.0, 4.0, 2.0,
        1.0, 2.0, 1.0,
    };

    var sobel_kernel = [_]f32{
        1.0, 0.0, -1.0,
        2.0, 0.0, -2.0,
        1.0, 0.0, -1.0,
    };

    var sharpen_kernel = [_]f32{
        0.0,  -1.0, 0.0,
        -1.0, 5.0,  -1.0,
        0.0,  -1.0, 0.0,
    };

    normalizeKernel(&gaussian_kernel);
    normalizeKernel(&sharpen_kernel);
    normalizeKernel(&sobel_kernel);

    var cat_sharpend = rl.imageCopy(image);
    rl.imageKernelConvolution(&cat_sharpend, &sharpen_kernel);

    var cat_sobel = rl.imageCopy(image);
    rl.imageKernelConvolution(&cat_sobel, &sobel_kernel);

    var cat_gaussian = rl.imageCopy(image);
    for (0..6) |_| rl.imageKernelConvolution(&cat_gaussian, &gaussian_kernel);

    const crop: rl.Rectangle = .{ .x = 0, .y = 0, .width = 200, .height = 450 };
    rl.imageCrop(&image, crop);
    rl.imageCrop(&cat_gaussian, crop);
    rl.imageCrop(&cat_sobel, crop);
    rl.imageCrop(&cat_sharpend, crop);

    // Images converted to texture, GPU memory (VRAM)
    const texture = try rl.loadTextureFromImage(image);
    defer rl.unloadTexture(texture);
    const cat_sharpend_texture = try rl.loadTextureFromImage(cat_sharpend);
    defer rl.unloadTexture(cat_sharpend_texture);
    const cat_sobel_texture = try rl.loadTextureFromImage(cat_sobel);
    defer rl.unloadTexture(cat_sobel_texture);
    const cat_gaussian_texture = try rl.loadTextureFromImage(cat_gaussian);
    defer rl.unloadTexture(cat_gaussian_texture);

    // Once images have been converted to texture and uploaded to VRAM,
    // they can be unloaded from RAM
    rl.unloadImage(image);
    rl.unloadImage(cat_gaussian);
    rl.unloadImage(cat_sobel);
    rl.unloadImage(cat_sharpend);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawTexture(cat_sharpend_texture, 0, 0, .white);
        rl.drawTexture(cat_sobel_texture, 200, 0, .white);
        rl.drawTexture(cat_gaussian_texture, 400, 0, .white);
        rl.drawTexture(texture, 600, 0, .white);
    }
}

/// Scale the kernel so its weights sum to 1 (left as is when they sum to 0).
fn normalizeKernel(kernel: []f32) void {
    var sum: f32 = 0.0;
    for (kernel) |weight| sum += weight;

    if (sum != 0.0) {
        for (kernel) |*weight| weight.* /= sum;
    }
}
