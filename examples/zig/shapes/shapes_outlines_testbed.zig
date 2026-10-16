//! raylib [shapes] example - outlines testbed
//!
//! Zig-API translation of examples/shapes/shapes_outlines_testbed.c (raylib 6.2).
//! Example contributed by Matthew Roush (@MatthewRoush) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Matthew Roush (@MatthewRoush)

const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");

const color_filled: rl.Color = .dark_blue;
const color_outline: rl.Color = .yellow;

const shape_spacing: f32 = 14.0;
const shape_size: f32 = 46.0;
const box_spacing: f32 = 10.0;

const mouse_camera_zoom_speed: f32 = 0.3;
const keyboard_camera_move_speed: f32 = 10.0;
const keyboard_camera_zoom_speed: f32 = 0.1;

const camera_zoom_min: f32 = 0.1;
const camera_zoom_max: f32 = 1000.0;

/// The shapes are drawn in this order, left to right
const Shape = enum { rectangle, rectangle_rounded, circle, ellipse, circle_sector, ring, triangle, polygon };

/// The line style groups are drawn in this order, top to bottom
const LineStyle = enum {
    lines,
    lines_ex_world,
    lines_ex_screen,

    fn title(style: LineStyle) [:0]const u8 {
        return switch (style) {
            .lines => "Draw*Lines()",
            .lines_ex_world => "Draw*LinesEx() with *world space* pixel thickness",
            .lines_ex_screen => "Draw*LinesEx() with *screen space* pixel thickness",
        };
    }
};

const shape_count: f32 = @floatFromInt(std.enums.values(Shape).len);
const box_width = shape_size * shape_count + shape_spacing * (shape_count - 1) + box_spacing * 2.0;
const box_height = shape_size + box_spacing * 2.0;

const shape_offset = box_spacing * 2.0;
const shape_padding_x = shape_size + shape_spacing;
const shape_padding_y = shape_size + shape_spacing + box_spacing * 2.0;

const triangle_vertex_offsets = [3]rl.Vector2{
    .{ .x = 0.0, .y = shape_size * 0.8 },
    .{ .x = shape_size * 0.6, .y = shape_size },
    .{ .x = shape_size, .y = 0.0 },
};

/// User configurable options while running the program.
const Options = struct {
    line_opacity: f32 = 130,
    line_thickness: f32 = 4.0,
    rectangle_roundness: f32 = 0.4,
    rectangle_segments: f32 = 9,
    ellipse_radius_y: f32 = 0.5,
    circle_start_angle: f32 = 20.0,
    circle_end_angle: f32 = 270.0,
    circle_segments: f32 = 36,
    ring_inner_radius_scale: f32 = 0.3,
    polygon_sides: f32 = 6,
};

/// Draw one shape filled, then outlined in the given line style.
fn drawShape(shape: Shape, style: LineStyle, pos_x: f32, pos_y: f32, opts: Options, thick: f32, outline: rl.Color) void {
    const rec: rl.Rectangle = .{ .x = pos_x, .y = pos_y, .width = shape_size, .height = shape_size };
    const center: rl.Vector2 = .{ .x = pos_x + shape_size / 2.0, .y = pos_y + shape_size / 2.0 };

    const radius_x = shape_size / 2.0;
    const radius_y = radius_x * opts.ellipse_radius_y;

    const ring_outer_radius = shape_size / 2.0;
    const ring_inner_radius = ring_outer_radius * opts.ring_inner_radius_scale;

    const rec_segments: i32 = @intFromFloat(opts.rectangle_segments);
    const circle_segments: i32 = @intFromFloat(opts.circle_segments);
    const polygon_sides: i32 = @intFromFloat(opts.polygon_sides);
    const start_angle = opts.circle_start_angle;
    const end_angle = opts.circle_end_angle;

    switch (shape) {
        .rectangle => {
            rl.drawRectangleRec(rec, color_filled);
            switch (style) {
                .lines => rl.drawRectangleLines(@intFromFloat(pos_x), @intFromFloat(pos_y), @intFromFloat(shape_size), @intFromFloat(shape_size), outline),
                else => rl.drawRectangleLinesEx(rec, thick, outline),
            }
        },
        .rectangle_rounded => {
            rl.drawRectangleRounded(rec, opts.rectangle_roundness, rec_segments, color_filled);
            switch (style) {
                .lines => rl.drawRectangleRoundedLines(rec, opts.rectangle_roundness, rec_segments, outline),
                else => rl.drawRectangleRoundedLinesEx(rec, opts.rectangle_roundness, rec_segments, thick, outline),
            }
        },
        .circle => {
            rl.drawCircleV(center, radius_x, color_filled);
            switch (style) {
                .lines => rl.drawCircleLinesV(center, radius_x, outline),
                else => rl.drawCircleLinesEx(center, radius_x, thick, outline),
            }
        },
        .ellipse => {
            rl.drawEllipseV(center, radius_x, radius_y, color_filled);
            switch (style) {
                .lines => rl.drawEllipseLinesV(center, radius_x, radius_y, outline),
                else => rl.drawEllipseLinesEx(center, radius_x, radius_y, thick, outline),
            }
        },
        .circle_sector => {
            rl.drawCircleSector(center, radius_x, start_angle, end_angle, circle_segments, color_filled);
            switch (style) {
                .lines => rl.drawCircleSectorLines(center, radius_x, start_angle, end_angle, circle_segments, outline),
                else => rl.drawCircleSectorLinesEx(center, radius_x, start_angle, end_angle, circle_segments, thick, outline),
            }
        },
        .ring => {
            rl.drawRing(center, ring_inner_radius, ring_outer_radius, start_angle, end_angle, circle_segments, color_filled);
            switch (style) {
                .lines => rl.drawRingLines(center, ring_inner_radius, ring_outer_radius, start_angle, end_angle, circle_segments, outline),
                else => rl.drawRingLinesEx(center, ring_inner_radius, ring_outer_radius, start_angle, end_angle, circle_segments, thick, outline),
            }
        },
        .triangle => {
            var v: [3]rl.Vector2 = undefined;
            for (&v, triangle_vertex_offsets) |*vertex, offset| vertex.* = .{ .x = pos_x + offset.x, .y = pos_y + offset.y };
            rl.drawTriangle(v[0], v[1], v[2], color_filled);
            switch (style) {
                .lines => rl.drawTriangleLines(v[0], v[1], v[2], outline),
                else => rl.drawTriangleLinesEx(v[0], v[1], v[2], thick, outline),
            }
        },
        .polygon => {
            rl.drawPoly(center, polygon_sides, radius_x, 0.0, color_filled);
            switch (style) {
                .lines => rl.drawPolyLines(center, polygon_sides, radius_x, 0.0, outline),
                else => rl.drawPolyLinesEx(center, polygon_sides, radius_x, 0.0, thick, outline),
            }
        },
    }
}

/// Set the camera zoom while keeping the world point under `zoom_point` fixed on screen.
fn zoomAround(camera: *rl.Camera2D, zoom_point: rl.Vector2, zoom: f32) void {
    const prev_world_zoom_point = rl.getScreenToWorld2D(zoom_point, camera.*);

    camera.zoom = zoom;

    const world_zoom_point = rl.getScreenToWorld2D(zoom_point, camera.*);
    camera.target = rl.math.vector2Add(camera.target, rl.math.vector2Subtract(prev_world_zoom_point, world_zoom_point));
}

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - outlines testbed");
    defer rl.closeWindow(); // Close window and OpenGL context

    var camera: rl.Camera2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .target = .{ .x = 0, .y = 0 },
        .rotation = 0,
        .zoom = 1,
    };

    var opts: Options = .{};

    var disable_mouse_control = false;

    const options_background: rl.Rectangle = .{ .x = 510, .y = 0, .width = 290, .height = 450 };

    const zoom_point: rl.Vector2 = .{
        .x = (@as(f32, screen_width) - options_background.width) / 2.0,
        .y = @as(f32, screen_height) / 2.0,
    };

    gui.setStyle(.label, gui.ControlProperty.text_color_normal, rl.colorToInt(.white));

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_pos_screen = rl.getMousePosition();
        const mouse_wheel_vec = rl.getMouseWheelMoveV();

        if (rl.isMouseButtonPressed(.left) and rl.checkCollisionPointRec(mouse_pos_screen, options_background)) disable_mouse_control = true;

        if (rl.isMouseButtonReleased(.left)) disable_mouse_control = false;

        if (!disable_mouse_control) {
            if (mouse_wheel_vec.y != 0.0) {
                // Constant zoom rate
                const zoom = camera.zoom * @exp2(mouse_camera_zoom_speed * mouse_wheel_vec.y);
                zoomAround(&camera, zoom_point, rl.math.clamp(zoom, camera_zoom_min, camera_zoom_max));
            }

            if (rl.isMouseButtonDown(.left)) {
                const mouse_delta = rl.getMouseDelta();
                camera.target.x -= mouse_delta.x / camera.zoom;
                camera.target.y -= mouse_delta.y / camera.zoom;

                // Wrap the mouse around the drawing area
                const mouse_max_x: i32 = @intFromFloat(options_background.x);
                const mouse_max_y: i32 = screen_height;

                const x: i32 = @intFromFloat(mouse_pos_screen.x);
                const y: i32 = @intFromFloat(mouse_pos_screen.y);
                const new_x = @mod(x, mouse_max_x);
                const new_y = @mod(y, mouse_max_y);

                if (new_x != x or new_y != y) rl.setMousePosition(new_x, new_y);
            }
        }

        if (rl.isKeyDown(.a)) camera.target.x -= keyboard_camera_move_speed / camera.zoom;
        if (rl.isKeyDown(.d)) camera.target.x += keyboard_camera_move_speed / camera.zoom;
        if (rl.isKeyDown(.w)) camera.target.y -= keyboard_camera_move_speed / camera.zoom;
        if (rl.isKeyDown(.s)) camera.target.y += keyboard_camera_move_speed / camera.zoom;

        if (rl.isKeyDown(.up)) {
            const zoom = camera.zoom * @exp2(keyboard_camera_zoom_speed);
            zoomAround(&camera, zoom_point, rl.math.clamp(zoom, camera_zoom_min, camera_zoom_max));
        }
        if (rl.isKeyDown(.down)) {
            const zoom = camera.zoom * @exp2(-keyboard_camera_zoom_speed);
            zoomAround(&camera, zoom_point, rl.math.clamp(zoom, camera_zoom_min, camera_zoom_max));
        }

        if (rl.isKeyPressed(.z)) zoomAround(&camera, zoom_point, 1.0);

        if (rl.isKeyPressed(.c)) camera.target = .{ .x = 0, .y = 0 };

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.{ .r = 50, .g = 50, .b = 55, .a = 255 });

        var outline = color_outline;
        outline.a = @intFromFloat(opts.line_opacity);

        {
            rl.beginMode2D(camera);
            defer rl.endMode2D();

            for (std.enums.values(LineStyle)) |style| {
                const pos_y = shape_offset + shape_padding_y * @as(f32, @floatFromInt(@backingInt(style)));
                const thick = switch (style) {
                    .lines => 0.0, // Draw*Lines() take no thickness
                    .lines_ex_world => opts.line_thickness,
                    .lines_ex_screen => opts.line_thickness / camera.zoom,
                };

                for (std.enums.values(Shape)) |shape| {
                    const pos_x = shape_offset + shape_padding_x * @as(f32, @floatFromInt(@backingInt(shape)));
                    drawShape(shape, style, pos_x, pos_y, opts, thick, outline);
                }

                // Group the shapes
                _ = gui.groupBox(.{ .x = shape_offset - box_spacing, .y = pos_y - box_spacing, .width = box_width, .height = box_height }, style.title());
            }
        }

        rl.drawRectangleRec(options_background, rl.fade(.dark_gray, 0.75));

        rl.drawRectangleRec(.{ .x = options_background.x, .y = 360, .width = options_background.width, .height = 90 }, rl.fade(.black, 0.4));
        rl.drawLineEx(.{ .x = options_background.x, .y = 360 }, .{ .x = options_background.x + options_background.width, .y = 360 }, 1.0, .black);

        const text_x: i32 = @as(i32, @intFromFloat(options_background.x)) + 10;
        rl.drawText("Move with the mouse or WASD keys", text_x, 370, 10, .orange);
        rl.drawText("Zoom with the mouse or UP and DOWN keys", text_x, 390, 10, .orange);
        rl.drawText("Press C to reset position", text_x, 410, 10, .orange);
        rl.drawText("Press Z to reset zoom", text_x, 430, 10, .orange);

        rl.drawLineEx(.{ .x = options_background.x, .y = options_background.y }, .{ .x = options_background.x, .y = options_background.y + options_background.height }, 1.0, .black);

        _ = gui.sliderBar(.{ .x = 605, .y = 10, .width = 150, .height = 25 }, "Line Opacity", rl.textFormat("{d}", .{@as(i32, @intFromFloat(opts.line_opacity))}), &opts.line_opacity, 0, 255);
        _ = gui.sliderBar(.{ .x = 605, .y = 45, .width = 150, .height = 25 }, "Thickness", rl.textFormat("{d:.2}", .{opts.line_thickness}), &opts.line_thickness, -20.0, 40.0);
        _ = gui.sliderBar(.{ .x = 605, .y = 80, .width = 150, .height = 25 }, "Rect Roundness", rl.textFormat("{d:.2}", .{opts.rectangle_roundness}), &opts.rectangle_roundness, -1.0, 2.0);
        _ = gui.sliderBar(.{ .x = 605, .y = 115, .width = 150, .height = 25 }, "Rect Segments", rl.textFormat("{d}", .{@as(i32, @intFromFloat(opts.rectangle_segments))}), &opts.rectangle_segments, -1, 100);
        _ = gui.sliderBar(.{ .x = 605, .y = 150, .width = 150, .height = 25 }, "Ellipse Radius Y", rl.textFormat("{d:.2}", .{opts.ellipse_radius_y}), &opts.ellipse_radius_y, 0.0, 1.25);
        _ = gui.sliderBar(.{ .x = 605, .y = 185, .width = 150, .height = 25 }, "Start Angle", rl.textFormat("{d:.2}", .{opts.circle_start_angle}), &opts.circle_start_angle, -360.0, 360.0);
        _ = gui.sliderBar(.{ .x = 605, .y = 220, .width = 150, .height = 25 }, "End Angle", rl.textFormat("{d:.2}", .{opts.circle_end_angle}), &opts.circle_end_angle, -360.0, 360.0);
        _ = gui.sliderBar(.{ .x = 605, .y = 255, .width = 150, .height = 25 }, "Circle Segments", rl.textFormat("{d}", .{@as(i32, @intFromFloat(opts.circle_segments))}), &opts.circle_segments, -1, 100);
        _ = gui.sliderBar(.{ .x = 605, .y = 290, .width = 150, .height = 25 }, "Ring Radius", rl.textFormat("{d:.2}", .{opts.ring_inner_radius_scale}), &opts.ring_inner_radius_scale, -1.0, 2.0);
        _ = gui.sliderBar(.{ .x = 605, .y = 325, .width = 150, .height = 25 }, "Poly Sides", rl.textFormat("{d}", .{@as(i32, @intFromFloat(opts.polygon_sides))}), &opts.polygon_sides, -1, 100);
    }
}
