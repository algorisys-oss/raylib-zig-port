//! raylib [textures] example - gif player
//!
//! Zig-API translation of examples/textures/textures_gif_player.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2021-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const max_frame_delay = 20;
const min_frame_delay = 1;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - gif player");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Load all GIF animation frames into a single Image
    // NOTE: GIF data is always loaded as RGBA (32bit) by default
    // NOTE: Frames are just appended one after another in image.data memory
    const scarfy_anim = try rl.loadImageAnim("resources/scarfy_run.gif");
    const im_scarfy_anim = scarfy_anim.image;
    defer rl.unloadImage(im_scarfy_anim); // Unload image (contains all frames)
    const anim_frames: u32 = @intCast(scarfy_anim.frames);
    const frame_data: [*]const u8 = @ptrCast(im_scarfy_anim.data.?);

    // Load texture from image
    // NOTE: We will update this texture when required with next frame data
    // WARNING: It's not recommended to use this technique for sprites animation,
    // use spritesheets instead, like illustrated in textures_sprite_anim example
    const tex_scarfy_anim = try rl.loadTextureFromImage(im_scarfy_anim);
    defer rl.unloadTexture(tex_scarfy_anim);

    var next_frame_data_offset: u32 = 0; // Current byte offset to next frame in image.data

    var current_anim_frame: u32 = 0; // Current animation frame to load and draw
    var frame_delay: u32 = 8; // Frame delay to switch between animation frames
    var frame_counter: u32 = 0; // General frames counter

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        frame_counter += 1;
        if (frame_counter >= frame_delay) {
            // Move to next frame
            // NOTE: If final frame is reached we return to first frame
            current_anim_frame += 1;
            if (current_anim_frame >= anim_frames) current_anim_frame = 0;

            // Get memory offset position for next frame data in image.data
            const frame_size: u32 = @intCast(im_scarfy_anim.width * im_scarfy_anim.height * 4);
            next_frame_data_offset = frame_size * current_anim_frame;

            // Update GPU texture data with next frame image data
            // WARNING: Data size (frame size) and pixel format must match already created texture
            rl.updateTexture(tex_scarfy_anim, frame_data + next_frame_data_offset);

            frame_counter = 0;
        }

        // Control frames delay
        if (rl.isKeyPressed(.right)) {
            frame_delay = @min(frame_delay + 1, max_frame_delay);
        } else if (rl.isKeyPressed(.left)) {
            frame_delay = @max(frame_delay - 1, min_frame_delay);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText(rl.textFormat("TOTAL GIF FRAMES:  {d:0>2}", .{anim_frames}), 50, 30, 20, .light_gray);
        rl.drawText(rl.textFormat("CURRENT FRAME: {d:0>2}", .{current_anim_frame}), 50, 60, 20, .gray);
        rl.drawText(rl.textFormat("CURRENT FRAME IMAGE.DATA OFFSET: {d:0>2}", .{next_frame_data_offset}), 50, 90, 20, .gray);

        rl.drawText("FRAMES DELAY: ", 100, 305, 10, .dark_gray);
        rl.drawText(rl.textFormat("{d:0>2} frames", .{frame_delay}), 620, 305, 10, .dark_gray);
        rl.drawText("PRESS RIGHT/LEFT KEYS to CHANGE SPEED!", 290, 350, 10, .dark_gray);

        for (0..max_frame_delay) |n| {
            const i: i32 = @intCast(n);
            if (n < frame_delay) rl.drawRectangle(190 + 21 * i, 300, 20, 20, .red);
            rl.drawRectangleLines(190 + 21 * i, 300, 20, 20, .maroon);
        }

        rl.drawTexture(tex_scarfy_anim, @divTrunc(rl.getScreenWidth(), 2) - @divTrunc(tex_scarfy_anim.width, 2), 140, .white);

        rl.drawText("(c) Scarfy sprite by Eiden Marsal", screen_width - 200, screen_height - 20, 10, .gray);
    }
}
