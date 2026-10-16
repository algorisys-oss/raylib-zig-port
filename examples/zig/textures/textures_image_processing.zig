//! raylib [textures] example - image processing
//!
//! NOTE: Images are loaded in CPU memory (RAM); textures are loaded in GPU memory (VRAM)
//!
//! Zig-API translation of examples/textures/textures_image_processing.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const ImageProcess = enum {
    none,
    color_grayscale,
    color_tint,
    color_invert,
    color_contrast,
    color_brightness,
    gaussian_blur,
    flip_vertical,
    flip_horizontal,

    const all = std.enums.values(ImageProcess);

    fn text(process: ImageProcess) [:0]const u8 {
        return switch (process) {
            .none => "NO PROCESSING",
            .color_grayscale => "COLOR GRAYSCALE",
            .color_tint => "COLOR TINT",
            .color_invert => "COLOR INVERT",
            .color_contrast => "COLOR CONTRAST",
            .color_brightness => "COLOR BRIGHTNESS",
            .gaussian_blur => "GAUSSIAN BLUR",
            .flip_vertical => "FLIP VERTICAL",
            .flip_horizontal => "FLIP HORIZONTAL",
        };
    }

    /// Apply this process to `image` in place.
    fn apply(process: ImageProcess, image: *rl.Image) void {
        switch (process) {
            .none => {},
            .color_grayscale => rl.imageColorGrayscale(image),
            .color_tint => rl.imageColorTint(image, .green),
            .color_invert => rl.imageColorInvert(image),
            .color_contrast => rl.imageColorContrast(image, -40),
            .color_brightness => rl.imageColorBrightness(image, -80),
            .gaussian_blur => rl.imageBlurGaussian(image, 10),
            .flip_vertical => rl.imageFlipVertical(image),
            .flip_horizontal => rl.imageFlipHorizontal(image),
        }
    }

    /// The process `offset` places away, wrapping around.
    fn cycle(process: ImageProcess, offset: isize) ImageProcess {
        const index: isize = @backingInt(process);
        return @fromBackingInt(@intCast(@mod(index + offset, all.len)));
    }
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - image processing");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)

    var im_origin = try rl.loadImage("resources/parrots.png"); // Loaded in CPU memory (RAM)
    defer rl.unloadImage(im_origin); // Unload image-origin from RAM
    rl.imageFormat(&im_origin, .uncompressed_r8g8b8a8); // Format image to RGBA 32bit (required for texture update) <-- ISSUE
    const texture = try rl.loadTextureFromImage(im_origin); // Image converted to texture, GPU memory (VRAM)
    defer rl.unloadTexture(texture); // Unload texture from VRAM

    var im_copy = rl.imageCopy(im_origin);
    defer rl.unloadImage(im_copy); // Unload image-copy from RAM

    var current_process: ImageProcess = .none;
    var texture_reload = false;

    var toggle_recs: [ImageProcess.all.len]rl.Rectangle = undefined;
    for (&toggle_recs, 0..) |*rec, i| {
        rec.* = .{ .x = 40.0, .y = @floatFromInt(50 + 32 * i), .width = 150.0, .height = 30.0 };
    }

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update

        // Mouse toggle group logic
        const mouse_hover_rec: ?usize = for (toggle_recs, 0..) |rec, i| {
            if (rl.checkCollisionPointRec(rl.getMousePosition(), rec)) break i;
        } else null;

        if (mouse_hover_rec) |i| {
            if (rl.isMouseButtonReleased(.left)) {
                current_process = ImageProcess.all[i];
                texture_reload = true;
            }
        }

        // Keyboard toggle group logic
        if (rl.isKeyPressed(.down)) {
            current_process = current_process.cycle(1);
            texture_reload = true;
        } else if (rl.isKeyPressed(.up)) {
            current_process = current_process.cycle(-1);
            texture_reload = true;
        }

        // Reload texture when required
        if (texture_reload) {
            rl.unloadImage(im_copy); // Unload image-copy data
            im_copy = rl.imageCopy(im_origin); // Restore image-copy from image-origin

            // NOTE: Image processing is a costly CPU process to be done every frame,
            // If image processing is required in a frame-basis, it should be done
            // with a texture and by shaders
            current_process.apply(&im_copy);

            const pixels = try rl.loadImageColors(im_copy); // Load pixel data from image (RGBA 32bit)
            rl.updateTexture(texture, pixels.ptr); // Update texture with new image data
            rl.unloadImageColors(pixels); // Unload pixels data from RAM

            texture_reload = false;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("IMAGE PROCESSING:", 40, 30, 10, .dark_gray);

        // Draw rectangles
        for (toggle_recs, ImageProcess.all, 0..) |rec, process, i| {
            const active = (process == current_process) or (i == mouse_hover_rec);
            const label = process.text();
            rl.drawRectangleRec(rec, if (active) .sky_blue else .light_gray);
            rl.drawRectangleLines(@intFromFloat(rec.x), @intFromFloat(rec.y), @intFromFloat(rec.width), @intFromFloat(rec.height), if (active) .blue else .gray);
            const label_x = rec.x + rec.width / 2 - @as(f32, @floatFromInt(rl.measureText(label, 10))) / 2;
            rl.drawText(label, @intFromFloat(label_x), @as(i32, @intFromFloat(rec.y)) + 11, 10, if (active) .dark_blue else .dark_gray);
        }

        rl.drawTexture(texture, screen_width - texture.width - 60, screen_height / 2 - @divTrunc(texture.height, 2), .white);
        rl.drawRectangleLines(screen_width - texture.width - 60, screen_height / 2 - @divTrunc(texture.height, 2), texture.width, texture.height, .black);
    }
}
