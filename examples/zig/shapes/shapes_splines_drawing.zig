//! raylib [shapes] example - splines drawing
//!
//! Zig-API translation of examples/shapes/shapes_splines_drawing.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const gui = @import("raygui");

const max_spline_points = 32;

/// Cubic Bezier spline control points
/// NOTE: Every segment has two control points
const ControlPoint = struct {
    start: rl.Vector2,
    end: rl.Vector2,

    /// Default control points for the segment from `a` to `b`.
    fn init(a: rl.Vector2, b: rl.Vector2) ControlPoint {
        return .{
            .start = .{ .x = a.x + 50, .y = a.y },
            .end = .{ .x = b.x - 50, .y = b.y },
        };
    }
};

/// Spline types, in dropdown order
const SplineType = enum(i32) {
    linear = 0, // Linear
    basis, // B-Spline
    catmull_rom, // Catmull-Rom
    bezier, // Cubic Bezier
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - splines drawing");
    defer rl.closeWindow(); // Close window and OpenGL context

    var points: [max_spline_points]rl.Vector2 = undefined;
    points[0..5].* = .{
        .{ .x = 50.0, .y = 400.0 },
        .{ .x = 160.0, .y = 220.0 },
        .{ .x = 340.0, .y = 380.0 },
        .{ .x = 520.0, .y = 60.0 },
        .{ .x = 710.0, .y = 260.0 },
    };

    // Array required for spline bezier-cubic,
    // including control points interleaved with start-end segment points
    var points_interleaved: [3 * (max_spline_points - 1) + 1]rl.Vector2 = undefined;

    var point_count: usize = 5;
    var selected_point: ?usize = null;
    var focused_point: ?usize = null;
    var selected_control_point: ?*rl.Vector2 = null;
    var focused_control_point: ?*rl.Vector2 = null;

    // Cubic Bezier control points initialization
    var control: [max_spline_points - 1]ControlPoint = undefined;
    for (control[0 .. point_count - 1], 0..) |*cp, i| cp.* = .init(points[i], points[i + 1]);

    // Spline config variables
    var spline_thickness: f32 = 8.0;
    var spline_type_active: i32 = @backingInt(SplineType.linear); // 0-Linear, 1-BSpline, 2-CatmullRom, 3-Bezier
    var spline_type_edit_mode = false;
    var spline_helpers_active = true;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Spline points creation logic (at the end of spline)
        if (rl.isMouseButtonPressed(.right) and point_count < max_spline_points) {
            points[point_count] = rl.getMousePosition();
            const i = point_count - 1;
            control[i] = .init(points[i], points[i + 1]);
            point_count += 1;
        }

        var spline_type: SplineType = @fromBackingInt(@intCast(spline_type_active));

        // Spline point focus and selection logic
        if (selected_point == null and (spline_type != .bezier or selected_control_point == null)) {
            focused_point = for (points[0..point_count], 0..) |point, i| {
                if (rl.checkCollisionPointCircle(rl.getMousePosition(), point, 8.0)) break i;
            } else null;
            if (rl.isMouseButtonPressed(.left)) selected_point = focused_point;
        }

        // Spline point movement logic
        if (selected_point) |i| {
            points[i] = rl.getMousePosition();
            if (rl.isMouseButtonReleased(.left)) selected_point = null;
        }

        // Cubic Bezier spline control points logic
        if (spline_type == .bezier and focused_point == null) {
            // Spline control point focus and selection logic
            if (selected_control_point == null) {
                focused_control_point = for (control[0 .. point_count - 1]) |*cp| {
                    if (rl.checkCollisionPointCircle(rl.getMousePosition(), cp.start, 6.0)) break &cp.start;
                    if (rl.checkCollisionPointCircle(rl.getMousePosition(), cp.end, 6.0)) break &cp.end;
                } else null;
                if (rl.isMouseButtonPressed(.left)) selected_control_point = focused_control_point;
            }

            // Spline control point movement logic
            if (selected_control_point) |cp| {
                cp.* = rl.getMousePosition();
                if (rl.isMouseButtonReleased(.left)) selected_control_point = null;
            }
        }

        // Spline selection logic
        if (rl.isKeyPressed(.one)) {
            spline_type = .linear;
        } else if (rl.isKeyPressed(.two)) {
            spline_type = .basis;
        } else if (rl.isKeyPressed(.three)) {
            spline_type = .catmull_rom;
        } else if (rl.isKeyPressed(.four)) {
            spline_type = .bezier;
        }
        spline_type_active = @backingInt(spline_type);

        // Clear selection when changing to a spline without control points
        if (rl.isKeyPressed(.one) or rl.isKeyPressed(.two) or rl.isKeyPressed(.three)) selected_control_point = null;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        const spline_points = points[0..point_count];
        switch (spline_type) {
            // Draw spline: linear
            .linear => rl.drawSplineLinear(spline_points, spline_thickness, .red),
            // Draw spline: basis
            .basis => rl.drawSplineBasis(spline_points, spline_thickness, .red), // Provide connected points array
            // Draw spline: catmull-rom
            .catmull_rom => rl.drawSplineCatmullRom(spline_points, spline_thickness, .red), // Provide connected points array
            .bezier => {
                // NOTE: Cubic-bezier spline requires the 2 control points of each segnment to be
                // provided interleaved with the start and end point of every segment
                const segments = control[0 .. point_count - 1];
                for (segments, 0..) |cp, i| {
                    points_interleaved[3 * i] = points[i];
                    points_interleaved[3 * i + 1] = cp.start;
                    points_interleaved[3 * i + 2] = cp.end;
                }

                points_interleaved[3 * (point_count - 1)] = points[point_count - 1];

                // Draw spline: cubic-bezier (with control points)
                rl.drawSplineBezierCubic(points_interleaved[0 .. 3 * (point_count - 1) + 1], spline_thickness, .red);

                // Draw spline control points
                for (segments, 0..) |*cp, i| {
                    // Every cubic bezier point have two control points
                    rl.drawCircleV(cp.start, 6, .gold);
                    rl.drawCircleV(cp.end, 6, .gold);
                    if (focused_control_point == &cp.start) {
                        rl.drawCircleV(cp.start, 8, .green);
                    } else if (focused_control_point == &cp.end) {
                        rl.drawCircleV(cp.end, 8, .green);
                    }
                    rl.drawLineEx(points[i], cp.start, 1.0, .light_gray);
                    rl.drawLineEx(points[i + 1], cp.end, 1.0, .light_gray);

                    // Draw spline control lines
                    rl.drawLineV(points[i], cp.start, .gray);
                    rl.drawLineV(cp.end, points[i + 1], .gray);
                }
            },
        }

        if (spline_helpers_active) {
            // Draw spline point helpers
            for (spline_points, 0..) |point, i| {
                const focused = focused_point == i;
                rl.drawCircleLinesV(point, if (focused) 12.0 else 8.0, if (focused) .blue else .dark_blue);
                if (spline_type != .linear and spline_type != .bezier and i < point_count - 1) {
                    rl.drawLineV(point, points[i + 1], .gray);
                }

                rl.drawText(rl.textFormat("[{d:.0}, {d:.0}]", .{ point.x, point.y }), @intFromFloat(point.x), @as(i32, @intFromFloat(point.y)) + 10, 10, .black);
            }
        }

        // Check all possible UI states that require controls lock
        if (spline_type_edit_mode or selected_point != null or selected_control_point != null) gui.lock();

        // Draw spline config
        _ = gui.label(.{ .x = 12, .y = 62, .width = 140, .height = 24 }, rl.textFormat("Spline thickness: {d}", .{@as(i32, @intFromFloat(spline_thickness))}));
        _ = gui.sliderBar(.{ .x = 12, .y = 60 + 24, .width = 140, .height = 16 }, null, null, &spline_thickness, 1.0, 40.0);

        _ = gui.checkBox(.{ .x = 12, .y = 110, .width = 20, .height = 20 }, "Show point helpers", &spline_helpers_active);

        if (spline_type_edit_mode) gui.unlock();

        _ = gui.label(.{ .x = 12, .y = 10, .width = 140, .height = 24 }, "Spline type:");
        if (gui.dropdownBox(.{ .x = 12, .y = 8 + 24, .width = 140, .height = 28 }, "LINEAR;BSPLINE;CATMULLROM;BEZIER", &spline_type_active, spline_type_edit_mode) != 0) {
            spline_type_edit_mode = !spline_type_edit_mode;
        }

        gui.unlock();
    }
}
