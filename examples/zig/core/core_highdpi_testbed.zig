//! raylib [core] example - highdpi testbed
//!
//! Zig-API translation of examples/core/core_highdpi_testbed.c (raylib 6.2).
//! Example contributed by Ramon Santamaria (@raysan5) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .window_resizable = true, .window_highdpi = true });
    rl.initWindow(screen_width, screen_height, "raylib [core] example - highdpi testbed");
    defer rl.closeWindow(); // Close window and OpenGL context

    const grid_spacing = 40; // Grid spacing in pixels

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_pos = rl.getMousePosition();
        const current_monitor = rl.getCurrentMonitor();
        const scale_dpi = rl.getWindowScaleDPI();
        const window_pos = rl.getWindowPosition();

        if (rl.isKeyPressed(.space)) rl.toggleBorderlessWindowed();
        if (rl.isKeyPressed(.f)) rl.toggleFullscreen();

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw grid
        const rows: usize = @intCast(@divTrunc(rl.getScreenHeight(), grid_spacing) + 1);
        for (0..rows) |h| {
            const y: i32 = @intCast(h * grid_spacing);
            rl.drawText(rl.textFormat("{d:0>2}", .{h * grid_spacing}), 4, y - 4, 10, .gray);
            rl.drawLine(24, y, rl.getScreenWidth(), y, .light_gray);
        }
        const columns: usize = @intCast(@divTrunc(rl.getScreenWidth(), grid_spacing) + 1);
        for (0..columns) |v| {
            const x: i32 = @intCast(v * grid_spacing);
            rl.drawText(rl.textFormat("{d:0>2}", .{v * grid_spacing}), x - 10, 4, 10, .gray);
            rl.drawLine(x, 20, x, rl.getScreenHeight(), .light_gray);
        }

        // Draw UI info
        rl.drawText(rl.textFormat("CURRENT MONITOR: {d}/{d} ({d}x{d})", .{
            current_monitor + 1,
            rl.getMonitorCount(),
            rl.getMonitorWidth(current_monitor),
            rl.getMonitorHeight(current_monitor),
        }), 50, 50, 20, .dark_gray);
        rl.drawText(rl.textFormat("WINDOW POSITION: {d}x{d}", .{
            @as(i32, @intFromFloat(window_pos.x)),
            @as(i32, @intFromFloat(window_pos.y)),
        }), 50, 90, 20, .dark_gray);
        rl.drawText(rl.textFormat("SCREEN SIZE: {d}x{d}", .{ rl.getScreenWidth(), rl.getScreenHeight() }), 50, 130, 20, .dark_gray);
        rl.drawText(rl.textFormat("RENDER SIZE: {d}x{d}", .{ rl.getRenderWidth(), rl.getRenderHeight() }), 50, 170, 20, .dark_gray);
        rl.drawText(rl.textFormat("SCALE FACTOR: {d:.2}x{d:.2}", .{ scale_dpi.x, scale_dpi.y }), 50, 210, 20, .gray);

        // Draw reference rectangles, top-left and bottom-right corners
        rl.drawRectangle(0, 0, 30, 60, .red);
        rl.drawRectangle(rl.getScreenWidth() - 30, rl.getScreenHeight() - 60, 30, 60, .blue);

        // Draw mouse position
        rl.drawCircleV(rl.getMousePosition(), 20, .maroon);
        rl.drawRectangleRec(.{ .x = mouse_pos.x - 25, .y = mouse_pos.y, .width = 50, .height = 2 }, .black);
        rl.drawRectangleRec(.{ .x = mouse_pos.x, .y = mouse_pos.y - 25, .width = 2, .height = 50 }, .black);
        const mouse_x: i32 = @intFromFloat(mouse_pos.x);
        const mouse_y: i32 = @intFromFloat(mouse_pos.y);
        const near_bottom = mouse_pos.y > @as(f32, @floatFromInt(rl.getScreenHeight() - 60));
        rl.drawText(
            rl.textFormat("[{d},{d}]", .{ rl.getMouseX(), rl.getMouseY() }),
            mouse_x - 44,
            if (near_bottom) mouse_y - 46 else mouse_y + 30,
            20,
            .black,
        );
    }
}
