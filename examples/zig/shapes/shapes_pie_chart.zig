//! raylib [shapes] example - pie chart
//!
//! Zig-API translation of examples/shapes/shapes_pie_chart.c (raylib 6.2).
//! Example contributed by Gideon Serfontein (@GideonSerf) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Gideon Serfontein (@GideonSerf)

const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");

const max_pie_slices = 10; // Max pie slices

/// The color of slice `i` out of `count`.
fn sliceColor(i: usize, count: usize) rl.Color {
    const hue = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count)) * 360.0;
    return rl.colorFromHSV(hue, 0.75, 0.9);
}

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - pie chart");
    defer rl.closeWindow(); // Close window and OpenGL context

    var slice_count: i32 = 7;
    var donut_inner_radius: f32 = 25.0;
    var values: [max_pie_slices]f32 = .{ 300.0, 100.0, 450.0, 350.0, 600.0, 380.0, 750.0, 0, 0, 0 }; // Initial slice values
    var editing_label: [max_pie_slices]bool = @splat(false);

    var show_values = true;
    var show_percentages = false;
    var show_donut = false;
    var scroll_content_offset: rl.Vector2 = .{ .x = 0, .y = 0 };
    var view: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 };

    // UI layout parameters
    const panel_width = 270;
    const panel_margin = 5;

    // UI Panel top-left anchor
    const panel_pos: rl.Vector2 = .{ .x = screen_width - panel_margin - panel_width, .y = panel_margin };

    // UI Panel rectangle
    const panel_rect: rl.Rectangle = .{
        .x = panel_pos.x,
        .y = panel_pos.y,
        .width = panel_width,
        .height = screen_height - 2.0 * panel_margin,
    };

    // Pie chart geometry
    const canvas: rl.Rectangle = .{ .x = 0, .y = 0, .width = panel_pos.x, .height = screen_height };
    const center: rl.Vector2 = .{ .x = canvas.width / 2.0, .y = canvas.height / 2.0 };
    const radius: f32 = 205.0;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        const count: usize = @intCast(slice_count);
        const slices = values[0..count];

        // Calculate total value for percentage calculations
        var total_value: f32 = 0.0;
        for (slices) |value| total_value += value;

        // Check for mouse hover over slices
        var hovered_slice: ?usize = null;
        const mouse_pos = rl.getMousePosition();

        if (rl.checkCollisionPointRec(mouse_pos, canvas)) { // Only check if mouse is inside the canvas
            const dx = mouse_pos.x - center.x;
            const dy = mouse_pos.y - center.y;
            const distance = @sqrt(dx * dx + dy * dy);

            if (distance <= radius) { // Inside the pie radius
                var angle = std.math.atan2(dy, dx) * rl.rad2deg;
                if (angle < 0) angle += 360;

                var current_angle: f32 = 0.0;
                for (slices, 0..) |value, i| {
                    const sweep = if (total_value > 0) (value / total_value) * 360.0 else 0.0;

                    if ((angle >= current_angle) and (angle < (current_angle + sweep))) {
                        hovered_slice = i;
                        break;
                    }

                    current_angle += sweep;
                }
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw the pie chart on the canvas
        var start_angle: f32 = 0.0;
        for (slices, 0..) |value, i| {
            const sweep_angle = if (total_value > 0) (value / total_value) * 360.0 else 0.0;
            const mid_angle = start_angle + sweep_angle / 2.0; // Middle angle for label positioning

            // Make the hovered slice pop out by adding 20 pixels to its radius
            const current_radius = if (hovered_slice == i) radius + 20.0 else radius;

            // Draw the pie slice using raylib's DrawCircleSector function
            rl.drawCircleSector(center, current_radius, start_angle, start_angle + sweep_angle, 120, sliceColor(i, count));

            // Draw the label for the current slice
            if (value > 0) {
                const percentage = (value / total_value) * 100.0;
                var label_buffer: [64]u8 = undefined;
                const label_text = (if (show_values and show_percentages)
                    std.fmt.bufPrintSentinel(&label_buffer, "{d:.1} ({d:.0}%)", .{ value, percentage }, 0)
                else if (show_values)
                    std.fmt.bufPrintSentinel(&label_buffer, "{d:.1}", .{value}, 0)
                else if (show_percentages)
                    std.fmt.bufPrintSentinel(&label_buffer, "{d:.0}%", .{percentage}, 0)
                else
                    std.fmt.bufPrintSentinel(&label_buffer, "", .{}, 0)) catch unreachable;

                const text_size = rl.measureTextEx(rl.getFontDefault(), label_text, 20, 1);
                const label_radius = radius * 0.7;
                const label_pos: rl.Vector2 = .{
                    .x = center.x + @cos(mid_angle * rl.deg2rad) * label_radius - text_size.x / 2.0,
                    .y = center.y + @sin(mid_angle * rl.deg2rad) * label_radius - text_size.y / 2.0,
                };
                rl.drawText(label_text, @intFromFloat(label_pos.x), @intFromFloat(label_pos.y), 20, .white);
            }

            // Draw inner circle to create donut effect
            // TODO: This is a hacky solution, better use DrawRing()
            if (show_donut) rl.drawCircleV(center, donut_inner_radius, .ray_white);

            start_angle += sweep_angle;
        }

        // UI control panel
        rl.drawRectangleRec(panel_rect, rl.fade(.light_gray, 0.5));
        rl.drawRectangleLinesEx(panel_rect, 1.0, .gray);

        _ = gui.spinner(.{ .x = panel_pos.x + 95, .y = panel_pos.y + 12, .width = 125, .height = 25 }, "Slices ", &slice_count, 1, max_pie_slices, false);
        _ = gui.checkBox(.{ .x = panel_pos.x + 20, .y = panel_pos.y + 12 + 40, .width = 20, .height = 20 }, "Show Values", &show_values);
        _ = gui.checkBox(.{ .x = panel_pos.x + 20, .y = panel_pos.y + 12 + 70, .width = 20, .height = 20 }, "Show Percentages", &show_percentages);
        _ = gui.checkBox(.{ .x = panel_pos.x + 20, .y = panel_pos.y + 12 + 100, .width = 20, .height = 20 }, "Make Donut", &show_donut);

        if (show_donut) gui.disable();
        _ = gui.sliderBar(.{ .x = panel_pos.x + 80, .y = panel_pos.y + 12 + 130, .width = panel_rect.width - 100, .height = 30 }, "Inner Radius", null, &donut_inner_radius, 5.0, radius - 10.0);
        gui.enable();

        _ = gui.line(.{ .x = panel_pos.x + 10, .y = panel_pos.y + 12 + 170, .width = panel_rect.width - 20, .height = 1 }, null);

        // Scrollable area for slice editors
        const scroll_panel_bounds: rl.Rectangle = .{
            .x = panel_pos.x + panel_margin,
            .y = panel_pos.y + 12 + 190,
            .width = panel_rect.width - panel_margin * 2,
            .height = panel_rect.y + panel_rect.height - panel_pos.y + 12 + 190 - panel_margin,
        };
        const content_height: f32 = @floatFromInt(slice_count * 35);

        _ = gui.scrollPanel(scroll_panel_bounds, null, .{ .x = 0, .y = 0, .width = panel_rect.width - 25, .height = content_height }, &scroll_content_offset, &view);

        const content_x = view.x + scroll_content_offset.x; // Left of content
        const content_y = view.y + scroll_content_offset.y; // Top of content

        rl.beginScissorMode(@intFromFloat(view.x), @intFromFloat(view.y), @intFromFloat(view.width), @intFromFloat(view.height));
        defer rl.endScissorMode();

        // The slice count may have changed in the spinner above
        const row_count: usize = @intCast(slice_count);
        for (values[0..row_count], editing_label[0..row_count], 0..) |*value, *editing, i| {
            const row_y: i32 = @intFromFloat(content_y + 5 + @as(f32, @floatFromInt(i * 35)));
            const row_top: f32 = @floatFromInt(row_y);

            // Color indicator
            rl.drawRectangle(@intFromFloat(content_x + 15), row_y + 5, 20, 20, sliceColor(i, row_count));

            // Label textbox
            var label_buffer: [32]u8 = undefined;
            _ = std.fmt.bufPrintSentinel(&label_buffer, "Slice {d:0>2}", .{i + 1}, 0) catch unreachable;
            if (gui.textBox(.{ .x = content_x + 45, .y = row_top, .width = 75, .height = 30 }, &label_buffer, editing.*) != 0) editing.* = !editing.*;

            _ = gui.sliderBar(.{ .x = content_x + 130, .y = row_top, .width = 110, .height = 30 }, null, null, value, 0.0, 1000.0);
        }
    }
}
