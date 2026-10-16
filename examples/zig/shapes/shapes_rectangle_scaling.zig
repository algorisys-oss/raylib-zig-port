//! raylib [shapes] example - rectangle scaling
//!
//! Zig-API translation of examples/shapes/shapes_rectangle_scaling.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2018-2025 Vlad Adrian (@demizdor) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const mouse_scale_mark_size = 12;

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - rectangle scaling");
    defer rl.closeWindow(); // Close window and OpenGL context

    var rec: rl.Rectangle = .{ .x = 100, .y = 100, .width = 200, .height = 80 };

    var mouse_scale_ready = false;
    var mouse_scale_mode = false;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_position = rl.getMousePosition();

        const scale_mark: rl.Rectangle = .{
            .x = rec.x + rec.width - mouse_scale_mark_size,
            .y = rec.y + rec.height - mouse_scale_mark_size,
            .width = mouse_scale_mark_size,
            .height = mouse_scale_mark_size,
        };
        if (rl.checkCollisionPointRec(mouse_position, scale_mark)) {
            mouse_scale_ready = true;
            if (rl.isMouseButtonPressed(.left)) mouse_scale_mode = true;
        } else mouse_scale_ready = false;

        if (mouse_scale_mode) {
            mouse_scale_ready = true;

            rec.width = mouse_position.x - rec.x;
            rec.height = mouse_position.y - rec.y;

            // Check minimum rec size
            if (rec.width < mouse_scale_mark_size) rec.width = mouse_scale_mark_size;
            if (rec.height < mouse_scale_mark_size) rec.height = mouse_scale_mark_size;

            // Check maximum rec size
            const max_width = @as(f32, @floatFromInt(rl.getScreenWidth())) - rec.x;
            const max_height = @as(f32, @floatFromInt(rl.getScreenHeight())) - rec.y;
            if (rec.width > max_width) rec.width = max_width;
            if (rec.height > max_height) rec.height = max_height;

            if (rl.isMouseButtonReleased(.left)) mouse_scale_mode = false;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("Scale rectangle dragging from bottom-right corner!", 10, 10, 20, .gray);

        rl.drawRectangleRec(rec, rl.fade(.green, 0.5));

        if (mouse_scale_ready) {
            rl.drawRectangleLinesEx(rec, 1, .red);
            rl.drawTriangle(
                .{ .x = rec.x + rec.width - mouse_scale_mark_size, .y = rec.y + rec.height },
                .{ .x = rec.x + rec.width, .y = rec.y + rec.height },
                .{ .x = rec.x + rec.width, .y = rec.y + rec.height - mouse_scale_mark_size },
                .red,
            );
        }
    }
}
