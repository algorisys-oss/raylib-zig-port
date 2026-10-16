//! raylib [textures] example - npatch drawing
//!
//! NOTE: Images are loaded in CPU memory (RAM); textures are loaded in GPU memory (VRAM)
//!
//! Zig-API translation of examples/textures/textures_npatch_drawing.c (raylib 6.2).
//! Example contributed by Jorge A. Gomes (@overdev) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2018-2025 Jorge A. Gomes (@overdev) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - npatch drawing");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)
    const n_patch_texture = try rl.loadTexture("resources/ninepatch_button.png");
    defer rl.unloadTexture(n_patch_texture); // Texture unloading

    const origin: rl.Vector2 = .{ .x = 0.0, .y = 0.0 };

    // Position and size of the n-patches
    var dst_rec1: rl.Rectangle = .{ .x = 480.0, .y = 160.0, .width = 32.0, .height = 32.0 };
    var dst_rec2: rl.Rectangle = .{ .x = 160.0, .y = 160.0, .width = 32.0, .height = 32.0 };
    var dst_rec_h: rl.Rectangle = .{ .x = 160.0, .y = 93.0, .width = 32.0, .height = 32.0 };
    var dst_rec_v: rl.Rectangle = .{ .x = 92.0, .y = 160.0, .width = 32.0, .height = 32.0 };

    // A 9-patch (NPATCH_NINE_PATCH) changes its sizes in both axis
    const nine_patch_info1: rl.NPatchInfo = .{
        .source = .{ .x = 0.0, .y = 0.0, .width = 64.0, .height = 64.0 },
        .left = 12,
        .top = 40,
        .right = 12,
        .bottom = 12,
        .layout = .nine_patch,
    };
    const nine_patch_info2: rl.NPatchInfo = .{
        .source = .{ .x = 0.0, .y = 128.0, .width = 64.0, .height = 64.0 },
        .left = 16,
        .top = 16,
        .right = 16,
        .bottom = 16,
        .layout = .nine_patch,
    };

    // A horizontal 3-patch (NPATCH_THREE_PATCH_HORIZONTAL) changes its sizes along the x axis only
    const h3_patch_info: rl.NPatchInfo = .{
        .source = .{ .x = 0.0, .y = 64.0, .width = 64.0, .height = 64.0 },
        .left = 8,
        .top = 8,
        .right = 8,
        .bottom = 8,
        .layout = .three_patch_horizontal,
    };

    // A vertical 3-patch (NPATCH_THREE_PATCH_VERTICAL) changes its sizes along the y axis only
    const v3_patch_info: rl.NPatchInfo = .{
        .source = .{ .x = 0.0, .y = 192.0, .width = 64.0, .height = 64.0 },
        .left = 6,
        .top = 6,
        .right = 6,
        .bottom = 6,
        .layout = .three_patch_vertical,
    };

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_position = rl.getMousePosition();

        // Resize the n-patches based on mouse position
        dst_rec1.width = mouse_position.x - dst_rec1.x;
        dst_rec1.height = mouse_position.y - dst_rec1.y;
        dst_rec2.width = mouse_position.x - dst_rec2.x;
        dst_rec2.height = mouse_position.y - dst_rec2.y;
        dst_rec_h.width = mouse_position.x - dst_rec_h.x;
        dst_rec_v.height = mouse_position.y - dst_rec_v.y;

        // Set a minimum width and/or height
        dst_rec1.width = @min(@max(dst_rec1.width, 1.0), 300.0);
        dst_rec1.height = @max(dst_rec1.height, 1.0);
        dst_rec2.width = @min(@max(dst_rec2.width, 1.0), 300.0);
        dst_rec2.height = @max(dst_rec2.height, 1.0);
        dst_rec_h.width = @max(dst_rec_h.width, 1.0);
        dst_rec_v.height = @max(dst_rec_v.height, 1.0);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw the n-patches
        rl.drawTextureNPatch(n_patch_texture, nine_patch_info2, dst_rec2, origin, 0.0, .white);
        rl.drawTextureNPatch(n_patch_texture, nine_patch_info1, dst_rec1, origin, 0.0, .white);
        rl.drawTextureNPatch(n_patch_texture, h3_patch_info, dst_rec_h, origin, 0.0, .white);
        rl.drawTextureNPatch(n_patch_texture, v3_patch_info, dst_rec_v, origin, 0.0, .white);

        // Draw the source texture
        rl.drawRectangleLines(5, 88, 74, 266, .blue);
        rl.drawTexture(n_patch_texture, 10, 93, .white);
        rl.drawText("TEXTURE", 15, 360, 10, .dark_gray);

        rl.drawText("Move the mouse to stretch or shrink the n-patches", 10, 20, 20, .dark_gray);
    }
}
