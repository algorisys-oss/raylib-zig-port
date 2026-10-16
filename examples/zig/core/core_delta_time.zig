//! raylib [core] example - delta time
//!
//! Zig-API translation of examples/core/core_delta_time.c (raylib 6.2).
//! Example contributed by Robin (@RobinsAviary) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Robin (@RobinsAviary)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - delta time");
    defer rl.closeWindow(); // Close window and OpenGL context

    var current_fps: i32 = 60;

    // Store the position for the both of the circles
    var delta_circle: rl.Vector2 = .{ .x = 0, .y = screen_height / 3.0 };
    var frame_circle: rl.Vector2 = .{ .x = 0, .y = screen_height * (2.0 / 3.0) };

    // The speed applied to both circles
    const speed: f32 = 10.0;
    const circle_radius: f32 = 32.0;

    rl.setTargetFPS(current_fps);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Adjust the FPS target based on the mouse wheel
        const mouse_wheel = rl.getMouseWheelMove();
        if (mouse_wheel != 0) {
            current_fps = @max(current_fps + @as(i32, @intFromFloat(mouse_wheel)), 0);
            rl.setTargetFPS(current_fps);
        }

        // getFrameTime() returns the time it took to draw the last frame, in seconds (usually called delta time)
        // Uses the delta time to make the circle look like it's moving at a "consistent" speed regardless of FPS

        // Multiply by 6.0 (an arbitrary value) in order to make the speed
        // visually closer to the other circle (at 60 fps), for comparison
        delta_circle.x += rl.getFrameTime() * 6.0 * speed;
        // This circle can move faster or slower visually depending on the FPS
        frame_circle.x += 0.1 * speed;

        // If either circle is off the screen, reset it back to the start
        if (delta_circle.x > screen_width) delta_circle.x = 0;
        if (frame_circle.x > screen_width) frame_circle.x = 0;

        // Reset both circles positions
        if (rl.isKeyPressed(.r)) {
            delta_circle.x = 0;
            frame_circle.x = 0;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw both circles to the screen
        rl.drawCircleV(delta_circle, circle_radius, .red);
        rl.drawCircleV(frame_circle, circle_radius, .blue);

        // Draw the help text
        // Determine what help text to show depending on the current FPS target
        const fps_text = if (current_fps <= 0)
            rl.textFormat("FPS: unlimited ({d})", .{rl.getFPS()})
        else
            rl.textFormat("FPS: {d} (target: {d})", .{ rl.getFPS(), current_fps });
        rl.drawText(fps_text, 10, 10, 20, .dark_gray);
        rl.drawText(rl.textFormat("Frame time: {d:.2} ms", .{rl.getFrameTime() * 1000.0}), 10, 30, 20, .dark_gray);
        rl.drawText("Use the scroll wheel to change the fps limit, r to reset", 10, 50, 20, .dark_gray);

        // Draw the text above the circles
        rl.drawText("FUNC: x += GetFrameTime()*speed", 10, 90, 20, .red);
        rl.drawText("FUNC: x += speed", 10, 240, 20, .blue);
    }
}
