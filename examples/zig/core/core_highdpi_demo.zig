//! raylib [core] example - highdpi demo
//!
//! Zig-API translation of examples/core/core_highdpi_demo.c (raylib 6.2).
//! Example contributed by Jonathan Marler (@marler8997) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jonathan Marler (@marler8997)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .window_highdpi = true, .window_resizable = true });
    rl.initWindow(screen_width, screen_height, "raylib [core] example - highdpi demo");
    defer rl.closeWindow(); // Close window and OpenGL context
    rl.setWindowMinSize(450, 450);

    const logical_grid_desc_y = 120;
    const logical_grid_label_y = logical_grid_desc_y + 30;
    const logical_grid_top = logical_grid_label_y + 30;
    const logical_grid_bottom = logical_grid_top + 80;
    const pixel_grid_top = logical_grid_bottom - 20;
    const pixel_grid_bottom = pixel_grid_top + 80;
    const pixel_grid_label_y = pixel_grid_bottom + 30;
    const pixel_grid_desc_y = pixel_grid_label_y + 30;
    const cell_size = 50;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const monitor_count = rl.getMonitorCount();

        if (monitor_count > 1 and rl.isKeyPressed(.n)) {
            rl.setWindowMonitor(@mod(rl.getCurrentMonitor() + 1, monitor_count));
        }

        const current_monitor = rl.getCurrentMonitor();
        const dpi_scale = rl.getWindowScaleDPI();
        const cell_size_px = @as(f32, cell_size) / dpi_scale.x;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        const window_center = @divTrunc(rl.getScreenWidth(), 2);
        drawTextCenter(rl.textFormat("Dpi Scale: {d:.6}", .{dpi_scale.x}), window_center, 30, 40, .dark_gray);
        drawTextCenter(rl.textFormat("Monitor: {d}/{d} ([N] next monitor)", .{ current_monitor + 1, monitor_count }), window_center, 70, 20, .light_gray);
        drawTextCenter(rl.textFormat("Window is {d} \"logical points\" wide", .{rl.getScreenWidth()}), window_center, logical_grid_desc_y, 20, .orange);

        var odd = true;
        var i: i32 = cell_size;
        while (i < rl.getScreenWidth()) : ({
            i += cell_size;
            odd = !odd;
        }) {
            if (odd) rl.drawRectangle(i, logical_grid_top, cell_size, logical_grid_bottom - logical_grid_top, .orange);

            drawTextCenter(rl.textFormat("{d}", .{i}), i, logical_grid_label_y, 10, .light_gray);
            rl.drawLine(i, logical_grid_label_y + 10, i, logical_grid_bottom, .gray);
        }

        odd = true;
        const min_text_space = 30;
        var last_text_x: i32 = -min_text_space;
        i = cell_size;
        while (i < rl.getRenderWidth()) : ({
            i += cell_size;
            odd = !odd;
        }) {
            const x: i32 = @intFromFloat(@as(f32, @floatFromInt(i)) / dpi_scale.x);
            if (odd) rl.drawRectangle(x, pixel_grid_top, @intFromFloat(cell_size_px), pixel_grid_bottom - pixel_grid_top, .{ .r = 0, .g = 121, .b = 241, .a = 100 });

            rl.drawLine(x, pixel_grid_top, x, pixel_grid_label_y - 10, .gray);

            if (x - last_text_x >= min_text_space) {
                drawTextCenter(rl.textFormat("{d}", .{i}), x, pixel_grid_label_y, 10, .light_gray);
                last_text_x = x;
            }
        }

        drawTextCenter(rl.textFormat("Window is {d} \"physical pixels\" wide", .{rl.getRenderWidth()}), window_center, pixel_grid_desc_y, 20, .blue);

        const text = "Can you see this?";
        const size = rl.measureTextEx(rl.getFontDefault(), text, 20, 3);
        const pos: rl.Vector2 = .{
            .x = @as(f32, @floatFromInt(rl.getScreenWidth())) - size.x - 5,
            .y = @as(f32, @floatFromInt(rl.getScreenHeight())) - size.y - 5,
        };
        rl.drawTextEx(rl.getFontDefault(), text, pos, 20, 3, .light_gray);
    }
}

fn drawTextCenter(text: [:0]const u8, x: i32, y: i32, font_size: i32, color: rl.Color) void {
    const size = rl.measureTextEx(rl.getFontDefault(), text, @floatFromInt(font_size), 3);
    const pos: rl.Vector2 = .{
        .x = @as(f32, @floatFromInt(x)) - size.x / 2,
        .y = @as(f32, @floatFromInt(y)) - size.y / 2,
    };
    rl.drawTextEx(rl.getFontDefault(), text, pos, @floatFromInt(font_size), 3, color);
}
