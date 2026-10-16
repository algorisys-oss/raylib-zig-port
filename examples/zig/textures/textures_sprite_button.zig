//! raylib [textures] example - sprite button
//!
//! Zig-API translation of examples/textures/textures_sprite_button.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

/// Button state; its value is the frame (rectangle) of the button sprite texture
const ButtonState = enum(u2) { normal, mouse_hover, pressed };

const num_frames = 3; // Number of frames (rectangles) for the button sprite texture

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - sprite button");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice(); // Initialize audio device
    defer rl.closeAudioDevice(); // Close audio device

    const fx_button = try rl.loadSound("resources/buttonfx.wav"); // Load button sound
    defer rl.unloadSound(fx_button); // Unload sound
    const button = try rl.loadTexture("resources/button.png"); // Load button texture
    defer rl.unloadTexture(button); // Unload button texture

    const button_width: f32 = @floatFromInt(button.width);
    const button_height: f32 = @floatFromInt(button.height);

    // Define frame rectangle for drawing
    const frame_height = button_height / num_frames;
    var source_rec: rl.Rectangle = .{ .x = 0, .y = 0, .width = button_width, .height = frame_height };

    // Define button bounds on screen
    const btn_bounds: rl.Rectangle = .{
        .x = screen_width / 2.0 - button_width / 2.0,
        .y = screen_height / 2.0 - button_height / num_frames / 2.0,
        .width = button_width,
        .height = frame_height,
    };

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_point = rl.getMousePosition();
        var btn_action = false; // Button action should be activated

        // Check button state
        var btn_state: ButtonState = .normal;
        if (rl.checkCollisionPointRec(mouse_point, btn_bounds)) {
            btn_state = if (rl.isMouseButtonDown(.left)) .pressed else .mouse_hover;

            if (rl.isMouseButtonReleased(.left)) btn_action = true;
        }

        if (btn_action) {
            rl.playSound(fx_button);

            // TODO: Any desired action
        }

        // Calculate button frame rectangle to draw depending on button state
        source_rec.y = @as(f32, @floatFromInt(@backingInt(btn_state))) * frame_height;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawTextureRec(button, source_rec, .{ .x = btn_bounds.x, .y = btn_bounds.y }, .white); // Draw button frame
    }
}
