//! raylib [core] example - smooth pixelperfect
//!
//! Zig-API translation of examples/core/core_smooth_pixelperfect.c (raylib 6.2).
//! Example contributed by Giancamillo Alessandroni (@NotManyIdeasDev) and
//! reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2021-2025 Giancamillo Alessandroni (@NotManyIdeasDev) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    const virtual_screen_width = 160;
    const virtual_screen_height = 90;

    const virtual_ratio: f32 = @as(f32, screen_width) / @as(f32, virtual_screen_width);

    rl.initWindow(screen_width, screen_height, "raylib [core] example - smooth pixelperfect");
    defer rl.closeWindow(); // Close window and OpenGL context

    var world_space_camera: rl.Camera2D = .{ // Game world camera
        .offset = .{ .x = 0, .y = 0 },
        .target = .{ .x = 0, .y = 0 },
        .rotation = 0,
        .zoom = 1.0,
    };
    var screen_space_camera: rl.Camera2D = world_space_camera; // Smoothing camera

    // Load render texture to draw all our objects
    const target = try rl.loadRenderTexture(virtual_screen_width, virtual_screen_height);
    defer rl.unloadRenderTexture(target); // Unload render texture

    const rec01: rl.Rectangle = .{ .x = 70.0, .y = 35.0, .width = 20.0, .height = 20.0 };
    const rec02: rl.Rectangle = .{ .x = 90.0, .y = 55.0, .width = 30.0, .height = 10.0 };
    const rec03: rl.Rectangle = .{ .x = 80.0, .y = 65.0, .width = 15.0, .height = 25.0 };

    // The target's height is flipped (in the source Rectangle), due to OpenGL reasons
    const source_rec: rl.Rectangle = .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(target.texture.width),
        .height = -@as(f32, @floatFromInt(target.texture.height)),
    };
    const window_rec: rl.Rectangle = .{
        .x = (screen_width - screen_width / 1.25) / 2.0,
        .y = (screen_height - screen_height / 1.25) / 2.0,
        .width = screen_width / 1.25,
        .height = screen_height / 1.25,
    };
    const overscan_rec: rl.Rectangle = .{
        .x = -virtual_ratio,
        .y = -virtual_ratio,
        .width = screen_width + virtual_ratio * 2,
        .height = screen_height + virtual_ratio * 2,
    };

    const origin: rl.Vector2 = .{ .x = 0.0, .y = 0.0 };

    var rotation: f32 = 0.0;

    var smooth_on = true;
    var overscan = false;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rotation += 60.0 * rl.getFrameTime(); // Rotate the rectangles, 60 degrees per second

        // Make the camera move to demonstrate the effect
        const time: f32 = @floatCast(rl.getTime());
        const camera_x = @sin(time) * 50.0 - 10.0;
        const camera_y = @cos(time) * 30.0;

        // Set the camera's target to the values computed above
        screen_space_camera.target = .{ .x = camera_x, .y = camera_y };

        // Round worldSpace coordinates, keep decimals into screenSpace coordinates
        world_space_camera.target.x = @trunc(screen_space_camera.target.x);
        screen_space_camera.target.x -= world_space_camera.target.x;
        screen_space_camera.target.x *= virtual_ratio;

        world_space_camera.target.y = @trunc(screen_space_camera.target.y);
        screen_space_camera.target.y -= world_space_camera.target.y;
        screen_space_camera.target.y *= virtual_ratio;

        if (rl.isKeyPressed(.s)) smooth_on = !smooth_on;
        if (rl.isKeyPressed(.o)) overscan = !overscan;

        const dest_rec = if (overscan) overscan_rec else window_rec;

        // Draw
        {
            rl.beginTextureMode(target);
            defer rl.endTextureMode();

            rl.clearBackground(.ray_white);

            rl.beginMode2D(world_space_camera);
            defer rl.endMode2D();

            rl.drawRectanglePro(rec01, origin, rotation, .black);
            rl.drawRectanglePro(rec02, origin, -rotation, .red);
            rl.drawRectanglePro(rec03, origin, rotation + 45.0, .blue);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.light_gray);

        if (smooth_on) {
            rl.beginMode2D(screen_space_camera);
            defer rl.endMode2D();

            rl.drawTexturePro(target.texture, source_rec, dest_rec, origin, 0.0, .white);
        } else {
            rl.drawTexturePro(target.texture, source_rec, dest_rec, origin, 0.0, .white);
        }

        rl.drawText(rl.textFormat("Screen resolution: {d}x{d}", .{ screen_width, screen_height }), 10, 10, 20, .dark_blue);
        rl.drawText(rl.textFormat("World resolution: {d}x{d}", .{ virtual_screen_width, virtual_screen_height }), 10, 40, 20, .dark_green);
        rl.drawText(rl.textFormat("Smooth: {s}", .{if (smooth_on) "ON" else "OFF"}), 10, screen_height - 60, 20, .red);
        rl.drawText(rl.textFormat("Overscan: {s}", .{if (overscan) "ON" else "OFF"}), 10, screen_height - 30, 20, .red);
        rl.drawFPS(rl.getScreenWidth() - 95, 10);
    }
}
