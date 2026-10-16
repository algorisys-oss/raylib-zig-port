//! raylib [core] example - render texture
//!
//! Zig-API translation of examples/core/core_render_texture.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - render texture");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define a render texture to render
    const render_texture_width = 300;
    const render_texture_height = 300;
    const target = try rl.loadRenderTexture(render_texture_width, render_texture_height);
    defer rl.unloadRenderTexture(target);

    var ball_position: rl.Vector2 = .{ .x = render_texture_width / 2.0, .y = render_texture_height / 2.0 };
    var ball_speed: rl.Vector2 = .{ .x = 5.0, .y = 4.0 };
    const ball_radius = 20;

    var rotation: f32 = 0.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Ball movement logic
        ball_position.x += ball_speed.x;
        ball_position.y += ball_speed.y;

        // Check walls collision for bouncing
        if (ball_position.x >= render_texture_width - ball_radius or ball_position.x <= ball_radius) ball_speed.x *= -1.0;
        if (ball_position.y >= render_texture_height - ball_radius or ball_position.y <= ball_radius) ball_speed.y *= -1.0;

        // Render texture rotation
        rotation += 0.5;

        // Draw
        // Draw our scene to the render texture
        {
            rl.beginTextureMode(target);
            defer rl.endTextureMode();

            rl.clearBackground(.sky_blue);

            rl.drawRectangle(0, 0, 20, 20, .red);
            rl.drawCircleV(ball_position, ball_radius, .maroon);
        }

        // Draw render texture to main framebuffer
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw our render texture with rotation applied
        // NOTE 1: We set the origin of the texture to the center of the render texture
        // NOTE 2: We flip vertically the texture setting negative source rectangle height
        const width: f32 = @floatFromInt(target.texture.width);
        const height: f32 = @floatFromInt(target.texture.height);
        rl.drawTexturePro(
            target.texture,
            .{ .x = 0, .y = 0, .width = width, .height = -height },
            .{ .x = screen_width / 2.0, .y = screen_height / 2.0, .width = width, .height = height },
            .{ .x = width / 2.0, .y = height / 2.0 },
            rotation,
            .white,
        );

        rl.drawText("DRAWING BOUNCING BALL INSIDE RENDER TEXTURE!", 10, screen_height - 40, 20, .black);

        rl.drawFPS(10, 10);
    }
}
