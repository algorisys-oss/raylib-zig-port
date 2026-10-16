//! raylib [core] example - monitor detector
//!
//! Zig-API translation of examples/core/core_monitor_detector.c (raylib 6.2).
//! Example contributed by Maicon Santana (@maiconpintoabreu) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Maicon Santana (@maiconpintoabreu)

const rl = @import("raylib");

const max_monitors = 10;

/// Monitor info
const MonitorInfo = struct {
    position: rl.Vector2,
    name: [:0]const u8,
    width: i32,
    height: i32,
    physical_width: i32,
    physical_height: i32,
    refresh_rate: i32,

    fn query(monitor: i32) MonitorInfo {
        return .{
            .position = rl.getMonitorPosition(monitor),
            .name = rl.getMonitorName(monitor),
            .width = rl.getMonitorWidth(monitor),
            .height = rl.getMonitorHeight(monitor),
            .physical_width = rl.getMonitorPhysicalWidth(monitor),
            .physical_height = rl.getMonitorPhysicalHeight(monitor),
            .refresh_rate = rl.getMonitorRefreshRate(monitor),
        };
    }
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - monitor detector");
    defer rl.closeWindow(); // Close window and OpenGL context

    var monitors: [max_monitors]MonitorInfo = undefined;
    var current_monitor_index = rl.getCurrentMonitor();

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Variables to find the max x and Y to calculate the scale
        var max_width: i32 = 1;
        var max_height: i32 = 1;

        // Monitor offset is to fix when monitor position x is negative
        var monitor_offset_x: i32 = 0;

        // Rebuild monitors array every frame
        const monitor_count = rl.getMonitorCount();
        const active_monitors = monitors[0..@intCast(monitor_count)];
        for (active_monitors, 0..) |*monitor, i| {
            monitor.* = .query(@intCast(i));

            if (monitor.position.x < @as(f32, @floatFromInt(monitor_offset_x))) {
                monitor_offset_x = -@as(i32, @intFromFloat(monitor.position.x));
            }

            const width = @as(i32, @intFromFloat(monitor.position.x)) + monitor.width;
            const height = @as(i32, @intFromFloat(monitor.position.y)) + monitor.height;

            max_width = @max(max_width, width);
            max_height = @max(max_height, height);
        }

        if (rl.isKeyPressed(.enter) and monitor_count > 1) {
            current_monitor_index += 1;

            // Set index to 0 if the last one
            if (current_monitor_index == monitor_count) current_monitor_index = 0;

            rl.setWindowMonitor(current_monitor_index); // Move window to current_monitor_index
        } else current_monitor_index = rl.getCurrentMonitor(); // Get current_monitor_index if manually moved

        var monitor_scale: f32 = 0.6;

        if (max_height > max_width + monitor_offset_x) {
            monitor_scale *= @as(f32, screen_height) / @as(f32, @floatFromInt(max_height));
        } else {
            monitor_scale *= @as(f32, screen_width) / @as(f32, @floatFromInt(max_width + monitor_offset_x));
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("Press [Enter] to move window to next monitor available", 20, 20, 20, .dark_gray);

        rl.drawRectangleLines(20, 60, screen_width - 40, screen_height - 100, .dark_gray);

        // Draw Monitor Rectangles with information inside
        const offset_x: f32 = @floatFromInt(monitor_offset_x);
        for (active_monitors, 0..) |monitor, i| {
            // Calculate retangle position and size using monitor_scale
            const rec: rl.Rectangle = .{
                .x = (monitor.position.x + offset_x) * monitor_scale + 140,
                .y = monitor.position.y * monitor_scale + 80,
                .width = @as(f32, @floatFromInt(monitor.width)) * monitor_scale,
                .height = @as(f32, @floatFromInt(monitor.height)) * monitor_scale,
            };
            const rec_x: i32 = @intFromFloat(rec.x);
            const rec_y: i32 = @intFromFloat(rec.y);
            const font_size: i32 = @intFromFloat(120 * monitor_scale);

            // Draw monitor name and information inside the rectangle
            rl.drawText(rl.textFormat("[{d}] {s}", .{ i, monitor.name }), rec_x + 10, rec_y + @as(i32, @intFromFloat(100 * monitor_scale)), font_size, .blue);
            rl.drawText(
                rl.textFormat("Resolution: [{d}px x {d}px]\nRefreshRate: [{d}hz]\nPhysical Size: [{d}mm x {d}mm]\nPosition: {d:>3.0} x {d:>3.0}", .{
                    monitor.width,
                    monitor.height,
                    monitor.refresh_rate,
                    monitor.physical_width,
                    monitor.physical_height,
                    monitor.position.x,
                    monitor.position.y,
                }),
                rec_x + 10,
                rec_y + @as(i32, @intFromFloat(200 * monitor_scale)),
                font_size,
                .dark_gray,
            );

            // Highlight current monitor
            if (i == current_monitor_index) {
                rl.drawRectangleLinesEx(rec, 5, .red);
                const window_position: rl.Vector2 = .{
                    .x = (rl.getWindowPosition().x + offset_x) * monitor_scale + 140,
                    .y = rl.getWindowPosition().y * monitor_scale + 80,
                };

                // Draw window position based on monitors
                rl.drawRectangleV(window_position, .{ .x = screen_width * monitor_scale, .y = screen_height * monitor_scale }, rl.fade(.green, 0.5));
            } else rl.drawRectangleLinesEx(rec, 5, .gray);
        }
    }
}
