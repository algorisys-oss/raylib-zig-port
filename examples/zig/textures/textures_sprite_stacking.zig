//! raylib [textures] example - sprite stacking
//!
//! Zig-API translation of examples/textures/textures_sprite_stacking.c (raylib 6.2).
//! Example contributed by Robin (@RobinsAviary) and reviewed by Ramon Santamaria (@raysan5)
//! Redbooth model (c) 2017-2025 @kluchek under https://creativecommons.org/licenses/by/4.0/ https://github.com/kluchek/vox-models/
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Robin (@RobinsAviary)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - sprite stacking");
    defer rl.closeWindow(); // Close window and OpenGL context

    const booth = try rl.loadTexture("resources/booth.png");
    defer rl.unloadTexture(booth);

    const stack_scale: f32 = 3.0; // Overall scale of the stacked sprite
    var stack_spacing: f32 = 2.0; // Vertical spacing between each layer
    const stack_count: u32 = 122; // Number of layers, used for calculating the size of a single slice
    var rotation_speed: f32 = 30.0; // Stacked sprites rotation speed
    var rotation: f32 = 0.0; // Current rotation of the stacked sprite
    const speed_change: f32 = 0.25; // Amount speed will change by when the user presses A/D

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Use mouse wheel to affect stack separation
        stack_spacing += rl.getMouseWheelMove() * 0.1;
        stack_spacing = rl.math.clamp(stack_spacing, 0.0, 5.0);

        // Add a positive/negative offset to spin right/left at different speeds
        if (rl.isKeyDown(.left) or rl.isKeyDown(.a)) rotation_speed -= speed_change;
        if (rl.isKeyDown(.right) or rl.isKeyDown(.d)) rotation_speed += speed_change;

        rotation += rotation_speed * rl.getFrameTime();

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Get the size of a single slice
        const frame_width: f32 = @floatFromInt(booth.width);
        const frame_height = @as(f32, @floatFromInt(booth.height)) / @as(f32, stack_count);

        // Get the scaled resolution to draw at
        const scaled_width = frame_width * stack_scale;
        const scaled_height = frame_height * stack_scale;

        // Draw the stacked sprite, rotated to the correct angle, with an vertical offset applied based on its y location
        var layer: u32 = stack_count;
        while (layer > 0) {
            layer -= 1;
            const i: f32 = @floatFromInt(layer);
            // Center vertically
            const source: rl.Rectangle = .{ .x = 0.0, .y = i * frame_height, .width = frame_width, .height = frame_height };
            const dest: rl.Rectangle = .{
                .x = screen_width / 2.0,
                .y = (screen_height / 2.0) + (i * stack_spacing) - (stack_spacing * stack_count / 2.0),
                .width = scaled_width,
                .height = scaled_height,
            };
            const origin: rl.Vector2 = .{ .x = scaled_width / 2.0, .y = scaled_height / 2.0 };

            rl.drawTexturePro(booth, source, dest, origin, rotation, .white);
        }

        rl.drawText("A/D to spin\nmouse wheel to change separation (aka 'angle')", 10, 10, 20, .dark_gray);
        rl.drawText(rl.textFormat("current spacing: {d:.1}", .{stack_spacing}), 10, 50, 20, .dark_gray);
        rl.drawText(rl.textFormat("current speed: {d:.2}", .{rotation_speed}), 10, 70, 20, .dark_gray);
        rl.drawText("redbooth model (c) kluchek under cc 4.0", 10, 420, 20, .dark_gray);
    }
}
