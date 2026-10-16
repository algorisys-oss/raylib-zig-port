//! raylib [textures] example - image drawing
//!
//! NOTE: Images are loaded in CPU memory (RAM); textures are loaded in GPU memory (VRAM)
//!
//! Zig-API translation of examples/textures/textures_image_drawing.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - image drawing");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)

    var cat = try rl.loadImage("resources/cat.png"); // Load image in CPU memory (RAM)
    rl.imageCrop(&cat, .{ .x = 100, .y = 10, .width = 280, .height = 380 }); // Crop an image piece
    rl.imageFlipHorizontal(&cat); // Flip cropped image horizontally
    rl.imageResize(&cat, 150, 200); // Resize flipped-cropped image

    var parrots = try rl.loadImage("resources/parrots.png"); // Load image in CPU memory (RAM)

    // Draw one image over the other with a scaling of 1.5f
    const cat_width: f32 = @floatFromInt(cat.width);
    const cat_height: f32 = @floatFromInt(cat.height);
    rl.imageDrawImagePro(
        &parrots,
        cat,
        .{ .x = 0, .y = 0, .width = cat_width, .height = cat_height },
        .{ .x = 30, .y = 40, .width = cat_width * 1.5, .height = cat_height * 1.5 },
        .{ .x = 0, .y = 0 },
        0.0,
        .white,
    );
    // Crop resulting image
    rl.imageCrop(&parrots, .{
        .x = 0,
        .y = 50,
        .width = @floatFromInt(parrots.width),
        .height = @as(f32, @floatFromInt(parrots.height)) - 100,
    });

    // Draw on the image with a few image draw methods
    rl.imageDrawPixel(&parrots, 10, 10, .ray_white);
    rl.imageDrawCircleLines(&parrots, 10, 10, 5, .ray_white);
    rl.imageDrawRectangle(&parrots, 5, 20, 10, 10, .ray_white);

    rl.unloadImage(cat); // Unload image from RAM

    // Load custom font for drawing on image
    const font = try rl.loadFont("resources/custom_jupiter_crash.png");

    // Draw over image using custom font
    rl.imageDrawTextEx(&parrots, font, "PARROTS & CAT", .{ .x = 300, .y = 230 }, @floatFromInt(font.baseSize), -2, .white);

    rl.unloadFont(font); // Unload custom font (already drawn used on image)

    const texture = try rl.loadTextureFromImage(parrots); // Image converted to texture, uploaded to GPU memory (VRAM)
    defer rl.unloadTexture(texture);
    rl.unloadImage(parrots); // Once image has been converted to texture and uploaded to VRAM, it can be unloaded from RAM

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        const x = screen_width / 2 - @divTrunc(texture.width, 2);
        const y = screen_height / 2 - @divTrunc(texture.height, 2) - 40;
        rl.drawTexture(texture, x, y, .white);
        rl.drawRectangleLines(x, y, texture.width, texture.height, .dark_gray);

        rl.drawText("We are drawing only one texture from various images composed!", 240, 350, 10, .dark_gray);
        rl.drawText("Source images have been cropped, scaled, flipped and copied one over the other.", 190, 370, 10, .dark_gray);
    }
}
