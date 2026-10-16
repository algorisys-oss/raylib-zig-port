//! raylib [shapes] example - rectangle advanced
//!
//! Zig-API translation of examples/shapes/shapes_rectangle_advanced.c (raylib 6.2).
//! Example contributed by Everton Jr. (@evertonse) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2024-2025 Everton Jr. (@evertonse) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - rectangle advanced");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update rectangle bounds
        const sw: f32 = @floatFromInt(rl.getScreenWidth());
        const sh: f32 = @floatFromInt(rl.getScreenHeight());
        const width = sw / 2.0;
        const height = sh / 6.0;
        var rec: rl.Rectangle = .{
            .x = sw / 2.0 - width / 2,
            .y = sh / 2.0 - 5 * (height / 2),
            .width = width,
            .height = height,
        };

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw All Rectangles with different roundess  for each side and different gradients
        drawRectangleRoundedGradientH(rec, 0.8, 0.8, 36, .blue, .red);

        rec.y += rec.height + 1;
        drawRectangleRoundedGradientH(rec, 0.5, 1.0, 36, .red, .pink);

        rec.y += rec.height + 1;
        drawRectangleRoundedGradientH(rec, 1.0, 0.5, 36, .red, .blue);

        rec.y += rec.height + 1;
        drawRectangleRoundedGradientH(rec, 0.0, 1.0, 36, .blue, .black);

        rec.y += rec.height + 1;
        drawRectangleRoundedGradientH(rec, 1.0, 0.0, 36, .blue, .pink);
    }
}

/// Draw rectangle with rounded edges and horizontal gradient, with options to choose side of roundness
/// NOTE: Adapted from both 'DrawRectangleRounded()' and 'DrawRectangleGradientH()' raylib [rshapes] implementations
fn drawRectangleRoundedGradientH(rec: rl.Rectangle, roundness_left: f32, roundness_right: f32, segments: i32, left: rl.Color, right: rl.Color) void {
    // Neither side is rounded
    if ((roundness_left <= 0.0 and roundness_right <= 0.0) or rec.width < 1 or rec.height < 1) {
        rl.drawRectangleGradientEx(rec, left, left, right, right);
        return;
    }

    // Calculate corner radius both from right and left
    const rec_size = @min(rec.width, rec.height);
    const radius_left = @max((rec_size * @min(roundness_left, 1.0)) / 2, 0.0);
    const radius_right = @max((rec_size * @min(roundness_right, 1.0)) / 2, 0.0);

    if (radius_right <= 0.0 and radius_left <= 0.0) return;

    const step_length = 90.0 / @as(f32, @floatFromInt(segments));

    //       P0____________________P1
    //       /|                    |\
    //      /1|          2         |3\
    //  P7 /__|____________________|__\ P2
    //    |   |P8                P9|   |
    //    | 8 |          9         | 4 |
    //    | __|____________________|__ |
    //  P6 \  |P11              P10|  / P3
    //      \7|          6         |5/
    //       \|____________________|/
    //       P5                    P4
    //
    // Diagram copied here for reference, original at 'DrawRectangleRounded()' source code

    // Coordinates of the 12 points also apdated from `DrawRectangleRounded`
    const right_x = rec.x + rec.width;
    const bottom_y = rec.y + rec.height;
    const point = [12]rl.Vector2{
        // P0, P1, P2
        .{ .x = rec.x + radius_left, .y = rec.y },
        .{ .x = right_x - radius_right, .y = rec.y },
        .{ .x = right_x, .y = rec.y + radius_right },
        // P3, P4
        .{ .x = right_x, .y = bottom_y - radius_right },
        .{ .x = right_x - radius_right, .y = bottom_y },
        // P5, P6, P7
        .{ .x = rec.x + radius_left, .y = bottom_y },
        .{ .x = rec.x, .y = bottom_y - radius_left },
        .{ .x = rec.x, .y = rec.y + radius_left },
        // P8, P9
        .{ .x = rec.x + radius_left, .y = rec.y + radius_left },
        .{ .x = right_x - radius_right, .y = rec.y + radius_right },
        // P10, P11
        .{ .x = right_x - radius_right, .y = bottom_y - radius_right },
        .{ .x = rec.x + radius_left, .y = bottom_y - radius_left },
    };

    // Draw all of the 4 corners: [1] Upper Left Corner, [3] Upper Right Corner, [5] Lower Right Corner, [7] Lower Left Corner
    const Corner = struct { center: rl.Vector2, angle: f32, color: rl.Color, radius: f32 };
    const corners = [4]Corner{
        .{ .center = point[8], .angle = 180.0, .color = left, .radius = radius_left }, // [1] Upper Left Corner
        .{ .center = point[9], .angle = 270.0, .color = right, .radius = radius_right }, // [3] Upper Right Corner
        .{ .center = point[10], .angle = 0.0, .color = right, .radius = radius_right }, // [5] Lower Right Corner
        .{ .center = point[11], .angle = 90.0, .color = left, .radius = radius_left }, // [7] Lower Left Corner
    };

    // Here we use the 'Diagram' to guide ourselves to which point receives what color
    // By choosing the color correctly associated with a pointe the gradient effect
    // will naturally come from OpenGL interpolation
    // But this time instead of Quad, we think in triangles
    rl.gl.begin(rl.gl.triangles);
    defer rl.gl.end();

    for (corners) |corner| {
        const center = corner.center;
        var angle = corner.angle;
        for (0..@intCast(segments)) |_| {
            color(corner.color);
            rl.gl.vertex2f(center.x, center.y);
            rl.gl.vertex2f(center.x + @cos(rl.deg2rad * (angle + step_length)) * corner.radius, center.y + @sin(rl.deg2rad * (angle + step_length)) * corner.radius);
            rl.gl.vertex2f(center.x + @cos(rl.deg2rad * angle) * corner.radius, center.y + @sin(rl.deg2rad * angle) * corner.radius);
            angle += step_length;
        }
    }

    // [2] Upper Rectangle
    color(left);
    vertex(point[0]);
    vertex(point[8]);
    color(right);
    vertex(point[9]);
    vertex(point[1]);
    color(left);
    vertex(point[0]);
    color(right);
    vertex(point[9]);

    // [4] Right Rectangle
    color(right);
    vertex(point[9]);
    vertex(point[10]);
    vertex(point[3]);
    vertex(point[2]);
    vertex(point[9]);
    vertex(point[3]);

    // [6] Bottom Rectangle
    color(left);
    vertex(point[11]);
    vertex(point[5]);
    color(right);
    vertex(point[4]);
    vertex(point[10]);
    color(left);
    vertex(point[11]);
    color(right);
    vertex(point[4]);

    // [8] Left Rectangle
    color(left);
    vertex(point[7]);
    vertex(point[6]);
    vertex(point[11]);
    vertex(point[8]);
    vertex(point[7]);
    vertex(point[11]);

    // [9] Middle Rectangle
    color(left);
    vertex(point[8]);
    vertex(point[11]);
    color(right);
    vertex(point[10]);
    vertex(point[9]);
    color(left);
    vertex(point[8]);
    color(right);
    vertex(point[10]);
}

fn color(c: rl.Color) void {
    rl.gl.color4ub(c.r, c.g, c.b, c.a);
}

fn vertex(v: rl.Vector2) void {
    rl.gl.vertex2f(v.x, v.y);
}
