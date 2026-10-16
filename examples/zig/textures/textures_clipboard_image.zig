//! raylib [textures] example - clipboard image
//!
//! Zig-API translation of examples/textures/textures_clipboard_image.c (raylib 6.2).
//! Example contributed by Maicon Santana (@maiconpintoabreu) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Maicon Santana (@maiconpintoabreu)

const rl = @import("raylib");

const max_texture_collection = 20;

const TextureCollection = struct {
    texture: rl.Texture2D,
    position: rl.Vector2,
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - clipboard image");
    defer rl.closeWindow(); // Close window and OpenGL context

    var collection: [max_texture_collection]TextureCollection = undefined;
    var collection_count: usize = 0;
    defer for (collection[0..collection_count]) |item| rl.unloadTexture(item.texture);

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.r)) { // Reset image collection
            // Unload textures to avoid memory leaks
            for (collection[0..collection_count]) |item| rl.unloadTexture(item.texture);

            collection_count = 0;
        }

        if (rl.isKeyDown(.left_control) and rl.isKeyPressed(.v) and
            (collection_count < max_texture_collection))
        {
            const image = rl.getClipboardImage();

            if (rl.isImageValid(image)) {
                defer rl.unloadImage(image);
                if (rl.loadTextureFromImage(image)) |texture| {
                    collection[collection_count] = .{ .texture = texture, .position = rl.getMousePosition() };
                    collection_count += 1;
                } else |_| {}
            } else rl.traceLog(.info, "IMAGE: Could not retrieve image from clipboard", .{});
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        for (collection[0..collection_count]) |item| {
            if (rl.isTextureValid(item.texture)) {
                const width: f32 = @floatFromInt(item.texture.width);
                const height: f32 = @floatFromInt(item.texture.height);
                rl.drawTexturePro(
                    item.texture,
                    .{ .x = 0, .y = 0, .width = width, .height = height },
                    .{ .x = item.position.x, .y = item.position.y, .width = width, .height = height },
                    .{ .x = width * 0.5, .y = height * 0.5 },
                    0.0,
                    .white,
                );
            }
        }

        rl.drawRectangle(0, 0, screen_width, 40, .black);
        rl.drawText("Clipboard Image - Ctrl+V to Paste and R to Reset ", 120, 10, 20, .light_gray);
    }
}
