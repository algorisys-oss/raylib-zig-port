//! raylib [core] example - custom frame control
//!
//! Zig-API translation of examples/core/core_custom_frame_control.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2021-2025 Ramon Santamaria (@raysan5)
//!
//! NOTE: WARNING: This is an example for advanced users willing to have full control over
//! the frame processes. By default, endDrawing() calls the following processes:
//!     1. Draw remaining batch data: rl.gl.drawRenderBatchActive()
//!     2. swapScreenBuffer()
//!     3. Frame time control: waitTime()
//!     4. pollInputEvents()
//!
//! To avoid steps 2, 3 and 4, flag SUPPORT_CUSTOM_FRAME_CONTROL can be enabled in
//! config.h (it requires recompiling raylib). This way those steps are up to the user
//!
//! Note that enabling this flag invalidates some functions:
//!     - getFrameTime()
//!     - setTargetFPS()
//!     - getFPS()

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - custom frame control");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Custom timming variables
    var previous_time = rl.getTime(); // Previous time measure
    var delta_time: f32 = 0.0; // Frame time (Update + Draw + Wait time)

    var time_counter: f32 = 0.0; // Accumulative time counter (seconds)
    var position: f32 = 0.0; // Circle position
    var pause = false; // Pause control flag

    var target_fps: i32 = 60; // Our initial target fps

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // NOTE: On non web platforms the pollInputEvents just works before the inputs checks
        rl.pollInputEvents(); // Poll input events (SUPPORT_CUSTOM_FRAME_CONTROL)

        if (rl.isKeyPressed(.space)) pause = !pause;

        if (rl.isKeyPressed(.up)) {
            target_fps += 20;
        } else if (rl.isKeyPressed(.down)) {
            target_fps -= 20;
        }

        if (target_fps < 0) target_fps = 0;

        if (!pause) {
            position += 200 * delta_time; // We move at 200 pixels per second
            if (position >= @as(f32, @floatFromInt(rl.getScreenWidth()))) position = 0;
            time_counter += delta_time; // We count time (seconds)
        }

        // Draw
        draw(position, time_counter, target_fps, delta_time);

        // NOTE: In case raylib is configured to SUPPORT_CUSTOM_FRAME_CONTROL,
        // Events polling, screen buffer swap and frame time control must be managed by the user

        rl.swapScreenBuffer(); // Flip the back buffer to screen (front buffer)

        var current_time = rl.getTime();
        const update_draw_time = current_time - previous_time; // Update + Draw time

        if (target_fps > 0) { // We want a fixed frame rate
            const wait_time = (1.0 / @as(f32, @floatFromInt(target_fps))) - update_draw_time;
            if (wait_time > 0.0) {
                rl.waitTime(@as(f32, @floatCast(wait_time)));
                current_time = rl.getTime();
                delta_time = @floatCast(current_time - previous_time);
            }
        } else delta_time = @floatCast(update_draw_time); // Framerate could be variable

        previous_time = current_time;
    }
}

fn draw(position: f32, time_counter: f32, target_fps: i32, delta_time: f32) void {
    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(.ray_white);

    for (0..@intCast(@divTrunc(rl.getScreenWidth(), 200))) |i| {
        rl.drawRectangle(200 * @as(i32, @intCast(i)), 0, 1, rl.getScreenHeight(), .sky_blue);
    }

    const x: i32 = @intFromFloat(position);
    const center_y = @divTrunc(rl.getScreenHeight(), 2);
    rl.drawCircle(x, center_y - 25, 50, .red);

    rl.drawText(rl.textFormat("{d:0>3.0} ms", .{time_counter * 1000.0}), x - 40, center_y - 100, 20, .maroon);
    rl.drawText(rl.textFormat("PosX: {d:0>3.0}", .{position}), x - 50, center_y + 40, 20, .black);

    rl.drawText("Circle is moving at a constant 200 pixels/sec,\nindependently of the frame rate.", 10, 10, 20, .dark_gray);
    rl.drawText("PRESS SPACE to PAUSE MOVEMENT", 10, rl.getScreenHeight() - 60, 20, .gray);
    rl.drawText("PRESS UP | DOWN to CHANGE TARGET FPS", 10, rl.getScreenHeight() - 30, 20, .gray);
    rl.drawText(rl.textFormat("TARGET FPS: {d}", .{target_fps}), rl.getScreenWidth() - 220, 10, 20, .lime);
    if (delta_time != 0) {
        const current_fps: i32 = @intFromFloat(1.0 / delta_time);
        rl.drawText(rl.textFormat("CURRENT FPS: {d}", .{current_fps}), rl.getScreenWidth() - 220, 40, 20, .green);
    }
}
