//! raylib [textures] example - textured curve
//!
//! Zig-API translation of examples/textures/textures_textured_curve.c (raylib 6.2).
//! Example contributed by Jeffery Myers (@JeffM2501) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2022-2025 Jeffery Myers (@JeffM2501) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const rm = rl.math;

// libm powf(), as in the C example (keeps the curve bit-identical)
extern "c" fn powf(x: f32, y: f32) f32;

/// Spline Cubic Bezier curve with its drawing options
const Curve = struct {
    start_position: rl.Vector2,
    start_position_tangent: rl.Vector2,
    end_position: rl.Vector2,
    end_position_tangent: rl.Vector2,
    width: f32 = 50,
    segments: i32 = 24,

    /// Draw textured curve using Spline Cubic Bezier
    fn drawTextured(curve: Curve, tex_road: rl.Texture) void {
        const step = 1.0 / @as(f32, @floatFromInt(curve.segments));

        var previous = curve.start_position;
        var previous_v: f32 = 0;

        // We can't compute a tangent for the first point, so we need to reuse the tangent from the first segment
        var previous_tangent: ?rl.Vector2 = null;

        for (1..@intCast(curve.segments + 1)) |i| {
            const t = step * @as(f32, @floatFromInt(i));

            const a = powf(1.0 - t, 3);
            const b = 3.0 * powf(1.0 - t, 2) * t;
            const c = 3.0 * (1.0 - t) * powf(t, 2);
            const d = powf(t, 3);

            // Compute the endpoint for this segment: a*p0 + b*p1 + c*p2 + d*p3
            const current: rl.Vector2 = .{
                .x = a * curve.start_position.x + b * curve.start_position_tangent.x + c * curve.end_position_tangent.x + d * curve.end_position.x,
                .y = a * curve.start_position.y + b * curve.start_position_tangent.y + c * curve.end_position_tangent.y + d * curve.end_position.y,
            };

            // Vector from previous to current
            const delta: rl.Vector2 = .{ .x = current.x - previous.x, .y = current.y - previous.y };

            // The right hand normal to the delta vector
            const normal = rm.vector2Normalize(.{ .x = -delta.y, .y = delta.x });

            // The v texture coordinate of the segment (add up the length of all the segments so far)
            const v = previous_v + rm.vector2Length(delta) / @as(f32, @floatFromInt(tex_road.height * 2));

            // Make sure the start point has a normal
            const prev_tangent = previous_tangent orelse normal;

            // Extend out the normals from the previous and current points to get the quad for this segment
            const prev_pos_normal = rm.vector2Add(previous, rm.vector2Scale(prev_tangent, curve.width));
            const prev_neg_normal = rm.vector2Add(previous, rm.vector2Scale(prev_tangent, -curve.width));

            const current_pos_normal = rm.vector2Add(current, rm.vector2Scale(normal, curve.width));
            const current_neg_normal = rm.vector2Add(current, rm.vector2Scale(normal, -curve.width));

            // Draw the segment as a quad
            rl.gl.setTexture(tex_road.id);
            rl.gl.begin(rl.gl.quads);
            rl.gl.color4ub(255, 255, 255, 255);
            rl.gl.normal3f(0.0, 0.0, 1.0);

            rl.gl.texCoord2f(0, previous_v);
            rl.gl.vertex2f(prev_neg_normal.x, prev_neg_normal.y);

            rl.gl.texCoord2f(1, previous_v);
            rl.gl.vertex2f(prev_pos_normal.x, prev_pos_normal.y);

            rl.gl.texCoord2f(1, v);
            rl.gl.vertex2f(current_pos_normal.x, current_pos_normal.y);

            rl.gl.texCoord2f(0, v);
            rl.gl.vertex2f(current_neg_normal.x, current_neg_normal.y);
            rl.gl.end();

            // The current step is the start of the next step
            previous = current;
            previous_tangent = normal;
            previous_v = v;
        }
    }
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .vsync_hint = true, .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [textures] example - textured curve");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Load the road texture
    const tex_road = try rl.loadTexture("resources/road.png");
    defer rl.unloadTexture(tex_road);
    rl.setTextureFilter(tex_road, .bilinear);

    // Setup the curve
    var curve: Curve = .{
        .start_position = .{ .x = 80, .y = 100 },
        .start_position_tangent = .{ .x = 100, .y = 300 },
        .end_position = .{ .x = 700, .y = 350 },
        .end_position_tangent = .{ .x = 600, .y = 100 },
    };
    var show_curve = false;
    var curve_selected_point: ?*rl.Vector2 = null;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Curve config options
        if (rl.isKeyPressed(.space)) show_curve = !show_curve;
        if (rl.isKeyPressed(.equal)) curve.width += 2;
        if (rl.isKeyPressed(.minus)) curve.width -= 2;
        if (curve.width < 2) curve.width = 2;

        // Update segments
        if (rl.isKeyPressed(.left)) curve.segments -= 2;
        if (rl.isKeyPressed(.right)) curve.segments += 2;

        if (curve.segments < 2) curve.segments = 2;

        // Update curve logic
        // If the mouse is not down, we are not editing the curve so clear the selection
        if (!rl.isMouseButtonDown(.left)) curve_selected_point = null;

        // If a point was selected, move it
        if (curve_selected_point) |point| point.* = rm.vector2Add(point.*, rl.getMouseDelta());

        // The mouse is down, and nothing was selected, so see if anything was picked
        const mouse = rl.getMousePosition();
        if (rl.checkCollisionPointCircle(mouse, curve.start_position, 6)) {
            curve_selected_point = &curve.start_position;
        } else if (rl.checkCollisionPointCircle(mouse, curve.start_position_tangent, 6)) {
            curve_selected_point = &curve.start_position_tangent;
        } else if (rl.checkCollisionPointCircle(mouse, curve.end_position, 6)) {
            curve_selected_point = &curve.end_position;
        } else if (rl.checkCollisionPointCircle(mouse, curve.end_position_tangent, 6)) {
            curve_selected_point = &curve.end_position_tangent;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        curve.drawTextured(tex_road); // Draw a textured Spline Cubic Bezier

        // Draw spline for reference
        if (show_curve) rl.drawSplineSegmentBezierCubic(curve.start_position, curve.end_position, curve.start_position_tangent, curve.end_position_tangent, 2, .blue);

        // Draw the various control points and highlight where the mouse is
        rl.drawLineV(curve.start_position, curve.start_position_tangent, .sky_blue);
        rl.drawLineV(curve.start_position_tangent, curve.end_position_tangent, rl.fade(.light_gray, 0.4));
        rl.drawLineV(curve.end_position, curve.end_position_tangent, .purple);

        const handles = [_]struct { point: rl.Vector2, color: rl.Color }{
            .{ .point = curve.start_position, .color = .red },
            .{ .point = curve.start_position_tangent, .color = .maroon },
            .{ .point = curve.end_position, .color = .green },
            .{ .point = curve.end_position_tangent, .color = .dark_green },
        };
        for (handles) |handle| {
            if (rl.checkCollisionPointCircle(mouse, handle.point, 6)) rl.drawCircleV(handle.point, 7, .yellow);
            rl.drawCircleV(handle.point, 5, handle.color);
        }

        // Draw usage info
        rl.drawText("Drag points to move curve, press SPACE to show/hide base curve", 10, 10, 10, .dark_gray);
        rl.drawText(rl.textFormat("Curve width: {d:2.0} (Use + and - to adjust)", .{curve.width}), 10, 30, 10, .dark_gray);
        rl.drawText(rl.textFormat("Curve segments: {d} (Use LEFT and RIGHT to adjust)", .{curve.segments}), 10, 50, 10, .dark_gray);
    }
}
