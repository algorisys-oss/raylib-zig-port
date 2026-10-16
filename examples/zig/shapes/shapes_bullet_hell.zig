//! raylib [shapes] example - bullet hell
//!
//! Zig-API translation of examples/shapes/shapes_bullet_hell.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Zero (@zerohorsepower)

const std = @import("std");
const rl = @import("raylib");

const max_bullets = 500000; // Max bullets to be processed

const Bullet = struct {
    position: rl.Vector2, // Bullet position on screen
    acceleration: rl.Vector2, // Amount of pixels to be incremented to position every frame
    disabled: bool, // Skip processing and draw case out of screen
    color: rl.Color, // Bullet color
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - bullet hell");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Bullets definition
    const bullets = try std.heap.page_allocator.alloc(Bullet, max_bullets); // Bullets array
    defer std.heap.page_allocator.free(bullets);
    var bullet_count: usize = 0;
    var bullet_disabled_count: usize = 0; // Used to calculate how many bullets are on screen
    const bullet_radius = 10;
    var bullet_speed: f32 = 3.0;
    var bullet_rows: i32 = 6;
    const bullet_color = [2]rl.Color{ .red, .blue };

    // Spawner variables
    var base_direction: f32 = 0;
    var angle_increment: i32 = 5; // After spawn all bullet rows, increment this value on the base_direction for next the frame
    var spawn_cooldown: f32 = 2;
    var spawn_cooldown_timer = spawn_cooldown;

    // Magic circle
    var magic_circle_rotation: f32 = 0;

    // Used on performance drawing
    const bullet_texture = try rl.loadRenderTexture(24, 24);
    defer rl.unloadRenderTexture(bullet_texture); // Unload bullet texture

    // Draw circle to bullet texture, then draw bullet using DrawTexture()
    // NOTE: This is done to improve the performance, since DrawCircle() is very slow
    rl.beginTextureMode(bullet_texture);
    rl.drawCircle(12, 12, bullet_radius, .white);
    rl.drawCircleLines(12, 12, bullet_radius, .black);
    rl.endTextureMode();

    var draw_in_performance_mode = true; // Switch between DrawCircle() and DrawTexture()

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Reset the bullet index
        // New bullets will replace the old ones that are already disabled due to out-of-screen
        if (bullet_count >= max_bullets) {
            bullet_count = 0;
            bullet_disabled_count = 0;
        }

        spawn_cooldown_timer -= 1;
        if (spawn_cooldown_timer < 0) {
            spawn_cooldown_timer = spawn_cooldown;

            // Spawn bullets
            const degrees_per_row = 360.0 / @as(f32, @floatFromInt(bullet_rows));
            for (0..@intCast(bullet_rows)) |row| {
                if (bullet_count >= max_bullets) continue;

                // Bullet speed*bullet direction, this will determine how much pixels will be incremented/decremented
                // from the bullet position every frame. Since the bullets doesn't change its direction and speed,
                // only need to calculate it at the spawning time
                // 0 degrees = right, 90 degrees = down, 180 degrees = left and 270 degrees = up, basically clockwise
                // Case you want it to be anti-clockwise, add "* -1" at the y acceleration
                const bullet_direction = base_direction + degrees_per_row * @as(f32, @floatFromInt(row));
                bullets[bullet_count] = .{
                    .position = .{ .x = screen_width / 2.0, .y = screen_height / 2.0 },
                    .acceleration = .{
                        .x = bullet_speed * @cos(bullet_direction * rl.deg2rad),
                        .y = bullet_speed * @sin(bullet_direction * rl.deg2rad),
                    },
                    .disabled = false,
                    .color = bullet_color[row % 2],
                };
                bullet_count += 1;
            }

            base_direction += @floatFromInt(angle_increment);
        }

        // Update bullets position based on its acceleration
        for (bullets[0..bullet_count]) |*bullet| {
            // Only update bullet if inside the screen
            if (bullet.disabled) continue;

            bullet.position.x += bullet.acceleration.x;
            bullet.position.y += bullet.acceleration.y;

            // Disable bullet if out of screen
            if (bullet.position.x < -bullet_radius * 2 or
                bullet.position.x > screen_width + bullet_radius * 2 or
                bullet.position.y < -bullet_radius * 2 or
                bullet.position.y > screen_height + bullet_radius * 2)
            {
                bullet.disabled = true;
                bullet_disabled_count += 1;
            }
        }

        // Input logic
        if ((rl.isKeyPressed(.right) or rl.isKeyPressed(.d)) and bullet_rows < 359) bullet_rows += 1;
        if ((rl.isKeyPressed(.left) or rl.isKeyPressed(.a)) and bullet_rows > 1) bullet_rows -= 1;
        if (rl.isKeyPressed(.up) or rl.isKeyPressed(.w)) bullet_speed += 0.25;
        if ((rl.isKeyPressed(.down) or rl.isKeyPressed(.s)) and bullet_speed > 0.50) bullet_speed -= 0.25;
        if (rl.isKeyPressed(.z) and spawn_cooldown > 1) spawn_cooldown -= 1;
        if (rl.isKeyPressed(.x)) spawn_cooldown += 1;
        if (rl.isKeyPressed(.enter)) draw_in_performance_mode = !draw_in_performance_mode;

        if (rl.isKeyDown(.space)) angle_increment = @mod(angle_increment + 1, 360);

        if (rl.isKeyPressed(.c)) {
            bullet_count = 0;
            bullet_disabled_count = 0;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw magic circle
        magic_circle_rotation += 1;
        const magic_rec: rl.Rectangle = .{ .x = screen_width / 2.0, .y = screen_height / 2.0, .width = 120, .height = 120 };
        rl.drawRectanglePro(magic_rec, .{ .x = 60.0, .y = 60.0 }, magic_circle_rotation, .purple);
        rl.drawRectanglePro(magic_rec, .{ .x = 60.0, .y = 60.0 }, magic_circle_rotation + 45, .purple);
        rl.drawCircleLines(screen_width / 2, screen_height / 2, 70, .black);
        rl.drawCircleLines(screen_width / 2, screen_height / 2, 50, .black);
        rl.drawCircleLines(screen_width / 2, screen_height / 2, 30, .black);

        // Draw bullets (disabled bullets are out of screen: not drawn)
        if (draw_in_performance_mode) {
            // Draw bullets using pre-rendered texture containing circle
            const texture = bullet_texture.texture;
            const half_width = @as(f32, @floatFromInt(texture.width)) * 0.5;
            const half_height = @as(f32, @floatFromInt(texture.height)) * 0.5;
            for (bullets[0..bullet_count]) |bullet| {
                if (bullet.disabled) continue;
                rl.drawTexture(texture, @intFromFloat(bullet.position.x - half_width), @intFromFloat(bullet.position.y - half_height), bullet.color);
            }
        } else {
            // Draw bullets using DrawCircle(), less performant
            for (bullets[0..bullet_count]) |bullet| {
                if (bullet.disabled) continue;
                rl.drawCircleV(bullet.position, bullet_radius, bullet.color);
                rl.drawCircleLinesV(bullet.position, bullet_radius, .black);
            }
        }

        // Draw UI
        const panel_color: rl.Color = .{ .r = 0, .g = 0, .b = 0, .a = 200 };
        rl.drawRectangle(10, 10, 280, 150, panel_color);
        rl.drawText("Controls:", 20, 20, 10, .light_gray);
        rl.drawText("- Right/Left or A/D: Change rows number", 40, 40, 10, .light_gray);
        rl.drawText("- Up/Down or W/S: Change bullet speed", 40, 60, 10, .light_gray);
        rl.drawText("- Z or X: Change spawn cooldown", 40, 80, 10, .light_gray);
        rl.drawText("- Space (Hold): Change the angle increment", 40, 100, 10, .light_gray);
        rl.drawText("- Enter: Switch draw method (Performance)", 40, 120, 10, .light_gray);
        rl.drawText("- C: Clear bullets", 40, 140, 10, .light_gray);

        rl.drawRectangle(610, 10, 170, 30, panel_color);
        if (draw_in_performance_mode) {
            rl.drawText("Draw method: DrawTexture(*)", 620, 20, 10, .green);
        } else {
            rl.drawText("Draw method: DrawCircle(*)", 620, 20, 10, .red);
        }

        rl.drawRectangle(135, 410, 530, 30, panel_color);
        rl.drawText(rl.textFormat(
            "[ FPS: {d}, Bullets: {d}, Rows: {d}, Bullet speed: {d:.2}, Angle increment per frame: {d}, Cooldown: {d:.0} ]",
            .{ rl.getFPS(), bullet_count - bullet_disabled_count, bullet_rows, bullet_speed, angle_increment, spawn_cooldown },
        ), 155, 420, 10, .green);
    }
}
