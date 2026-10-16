//! raylib [textures] example - sprite explosion
//!
//! Zig-API translation of examples/textures/textures_sprite_explosion.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const num_frames_per_line = 5;
const num_lines = 5;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - sprite explosion");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    // Load explosion sound
    const fx_boom = try rl.loadSound("resources/boom.wav");
    defer rl.unloadSound(fx_boom); // Unload sound

    // Load explosion texture
    const explosion = try rl.loadTexture("resources/explosion.png");
    defer rl.unloadTexture(explosion); // Unload texture

    // Init variables for animation
    const frame_width = @as(f32, @floatFromInt(explosion.width)) / num_frames_per_line; // Sprite one frame rectangle width
    const frame_height = @as(f32, @floatFromInt(explosion.height)) / num_lines; // Sprite one frame rectangle height
    var current_frame: u32 = 0;
    var current_line: u32 = 0;

    var frame_rec: rl.Rectangle = .{ .x = 0, .y = 0, .width = frame_width, .height = frame_height };
    var position: rl.Vector2 = .{ .x = 0.0, .y = 0.0 };

    var active = false;
    var frames_counter: u32 = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update

        // Check for mouse button pressed and activate explosion (if not active)
        if (rl.isMouseButtonPressed(.left) and !active) {
            position = rl.getMousePosition();
            active = true;

            position.x -= frame_width / 2.0;
            position.y -= frame_height / 2.0;

            rl.playSound(fx_boom);
        }

        // Compute explosion animation frames
        if (active) {
            frames_counter += 1;

            if (frames_counter > 2) {
                current_frame += 1;

                if (current_frame >= num_frames_per_line) {
                    current_frame = 0;
                    current_line += 1;

                    if (current_line >= num_lines) {
                        current_line = 0;
                        active = false;
                    }
                }

                frames_counter = 0;
            }
        }

        frame_rec.x = frame_width * @as(f32, @floatFromInt(current_frame));
        frame_rec.y = frame_height * @as(f32, @floatFromInt(current_line));

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw explosion required frame rectangle
        if (active) rl.drawTextureRec(explosion, frame_rec, position, .white);
    }
}
