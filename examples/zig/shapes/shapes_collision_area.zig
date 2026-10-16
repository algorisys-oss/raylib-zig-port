//! raylib [shapes] example - collision area
//!
//! Zig-API translation of examples/shapes/shapes_collision_area.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - collision area");
    defer rl.closeWindow(); // Close window and OpenGL context

    const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
    const screen_h: f32 = @floatFromInt(rl.getScreenHeight());

    // Box A: Moving box
    var box_a: rl.Rectangle = .{ .x = 10, .y = screen_h / 2.0 - 50, .width = 200, .height = 100 };
    var box_a_speed_x: f32 = 4;

    // Box B: Mouse moved box
    var box_b: rl.Rectangle = .{ .x = screen_w / 2.0 - 30, .y = screen_h / 2.0 - 30, .width = 60, .height = 60 };

    var box_collision: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 }; // Collision rectangle

    const screen_upper_limit = 40; // Top menu limits

    var pause = false; // Movement pause

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const width: f32 = @floatFromInt(rl.getScreenWidth());
        const height: f32 = @floatFromInt(rl.getScreenHeight());

        // Move box if not paused
        if (!pause) box_a.x += box_a_speed_x;

        // Bounce box on x screen limits
        if (box_a.x + box_a.width >= width or box_a.x <= 0) box_a_speed_x *= -1;

        // Update player-controlled-box (box02)
        box_b.x = @as(f32, @floatFromInt(rl.getMouseX())) - box_b.width / 2;
        box_b.y = @as(f32, @floatFromInt(rl.getMouseY())) - box_b.height / 2;

        // Make sure Box B does not go out of move area limits
        if (box_b.x + box_b.width >= width) {
            box_b.x = width - box_b.width;
        } else if (box_b.x <= 0) box_b.x = 0;

        if (box_b.y + box_b.height >= height) {
            box_b.y = height - box_b.height;
        } else if (box_b.y <= screen_upper_limit) box_b.y = screen_upper_limit;

        // Check boxes collision
        const collision = rl.checkCollisionRecs(box_a, box_b);

        // Get collision rectangle (only on collision)
        if (collision) box_collision = rl.getCollisionRec(box_a, box_b);

        // Pause Box A movement
        if (rl.isKeyPressed(.space)) pause = !pause;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawRectangle(0, 0, screen_width, screen_upper_limit, if (collision) .red else .black);

        rl.drawRectangleRec(box_a, .gold);
        rl.drawRectangleRec(box_b, .blue);

        if (collision) {
            // Draw collision area
            rl.drawRectangleRec(box_collision, .lime);

            // Draw collision message
            rl.drawText("COLLISION!", @divTrunc(rl.getScreenWidth(), 2) - @divTrunc(rl.measureText("COLLISION!", 20), 2), screen_upper_limit / 2 - 10, 20, .black);

            // Draw collision area
            const area = @as(i32, @intFromFloat(box_collision.width)) * @as(i32, @intFromFloat(box_collision.height));
            rl.drawText(rl.textFormat("Collision Area: {d}", .{area}), @divTrunc(rl.getScreenWidth(), 2) - 100, screen_upper_limit + 10, 20, .black);
        }

        // Draw help instructions
        rl.drawText("Press SPACE to PAUSE/RESUME", 20, screen_height - 35, 20, .light_gray);

        rl.drawFPS(10, 10);
    }
}
