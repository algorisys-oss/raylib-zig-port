//! raylib [textures] example - sprite animation
//!
//! Zig-API translation of examples/textures/textures_sprite_animation.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const max_frame_speed = 15;
const min_frame_speed = 1;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - sprite animation");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)
    const scarfy = try rl.loadTexture("resources/scarfy.png"); // Texture loading
    defer rl.unloadTexture(scarfy); // Texture unloading
    const scarfy_width: f32 = @floatFromInt(scarfy.width);

    const position: rl.Vector2 = .{ .x = 350.0, .y = 280.0 };
    var frame_rec: rl.Rectangle = .{ .x = 0.0, .y = 0.0, .width = scarfy_width / 6, .height = @floatFromInt(scarfy.height) };
    var current_frame: u32 = 0;

    var frames_counter: u32 = 0;
    var frames_speed: u32 = 8; // Number of spritesheet frames shown by second

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        frames_counter += 1;

        if (frames_counter >= (60 / frames_speed)) {
            frames_counter = 0;
            current_frame += 1;

            if (current_frame > 5) current_frame = 0;

            frame_rec.x = @as(f32, @floatFromInt(current_frame)) * scarfy_width / 6;
        }

        // Control frames speed
        if (rl.isKeyPressed(.right)) {
            frames_speed = @min(frames_speed + 1, max_frame_speed);
        } else if (rl.isKeyPressed(.left)) {
            frames_speed = @max(frames_speed - 1, min_frame_speed);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawTexture(scarfy, 15, 40, .white);
        rl.drawRectangleLines(15, 40, scarfy.width, scarfy.height, .lime);
        rl.drawRectangleLines(
            15 + @as(i32, @intFromFloat(frame_rec.x)),
            40 + @as(i32, @intFromFloat(frame_rec.y)),
            @intFromFloat(frame_rec.width),
            @intFromFloat(frame_rec.height),
            .red,
        );

        rl.drawText("FRAME SPEED: ", 165, 210, 10, .dark_gray);
        rl.drawText(rl.textFormat("{d:0>2} FPS", .{frames_speed}), 575, 210, 10, .dark_gray);
        rl.drawText("PRESS RIGHT/LEFT KEYS to CHANGE SPEED!", 290, 240, 10, .dark_gray);

        for (0..max_frame_speed) |n| {
            const i: i32 = @intCast(n);
            if (n < frames_speed) rl.drawRectangle(250 + 21 * i, 205, 20, 20, .red);
            rl.drawRectangleLines(250 + 21 * i, 205, 20, 20, .maroon);
        }

        rl.drawTextureRec(scarfy, frame_rec, position, .white); // Draw part of the texture

        rl.drawText("(c) Scarfy sprite by Eiden Marsal", screen_width - 200, screen_height - 20, 10, .gray);
    }
}
