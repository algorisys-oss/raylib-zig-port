//! raylib [shapes] example - hilbert curve
//!
//! Zig-API translation of examples/shapes/shapes_hilbert_curve.c (raylib 6.2).
//! Example contributed by Hamza RAHAL (@hmz-rhl) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Hamza RAHAL (@hmz-rhl)

const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - hilbert curve");
    defer rl.closeWindow(); // Close window and OpenGL context

    var order: i32 = 2;
    var size: f32 = @floatFromInt(rl.getScreenHeight());
    var hilbert_path = try loadHilbertPath(gpa, order, size);
    defer gpa.free(hilbert_path);

    var prev_order = order;
    var prev_size: i32 = @intFromFloat(size); // NOTE: Size from slider is float but for comparison we use int
    var counter: usize = 0;
    var thick: f32 = 2.0;
    var animate = true;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Check if order or size have changed to regenerate
        // NOTE: Size from slider is float but for comparison we use int
        const int_size: i32 = @intFromFloat(size);
        if (prev_order != order or prev_size != int_size) {
            gpa.free(hilbert_path);
            hilbert_path = try loadHilbertPath(gpa, order, size);

            counter = if (animate) 0 else hilbert_path.len;

            prev_order = order;
            prev_size = int_size;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        if (counter < hilbert_path.len) {
            // Draw Hilbert path animation, one stroke every frame
            drawHilbertPath(hilbert_path, counter + 1, thick);
            counter += 1;
        } else {
            // Draw full Hilbert path
            drawHilbertPath(hilbert_path, hilbert_path.len, thick);
        }

        // Draw UI using raygui
        _ = gui.checkBox(.{ .x = 450, .y = 50, .width = 20, .height = 20 }, "ANIMATE GENERATION ON CHANGE", &animate);
        _ = gui.spinner(.{ .x = 585, .y = 100, .width = 180, .height = 30 }, "HILBERT CURVE ORDER:  ", &order, 2, 8, false);
        _ = gui.slider(.{ .x = 524, .y = 150, .width = 240, .height = 24 }, "THICKNESS:  ", null, &thick, 1.0, 10.0);
        _ = gui.slider(.{ .x = 524, .y = 190, .width = 240, .height = 24 }, "TOTAL SIZE: ", null, &size, 10.0, @as(f32, @floatFromInt(rl.getScreenHeight())) * 1.5);
    }
}

/// Draw the strokes joining the first `point_count` points of the path,
/// colored by their position along the whole path.
fn drawHilbertPath(path: []const rl.Vector2, point_count: usize, thick: f32) void {
    const stroke_count: f32 = @floatFromInt(path.len);
    for (1..point_count) |i| {
        const hue = (@as(f32, @floatFromInt(i)) / stroke_count) * 360.0;
        rl.drawLineEx(path[i], path[i - 1], thick, rl.colorFromHSV(hue, 1.0, 1.0));
    }
}

/// Load the whole Hilbert path (including each U and their link).
fn loadHilbertPath(gpa: std.mem.Allocator, order: i32, size: f32) ![]rl.Vector2 {
    const n = @as(i32, 1) << @intCast(order);
    const len = size / @as(f32, @floatFromInt(n));

    const path = try gpa.alloc(rl.Vector2, @intCast(n * n));
    for (path, 0..) |*point, i| {
        const step = computeHilbertStep(order, @intCast(i));
        point.* = .{
            .x = step.x * len + len / 2.0,
            .y = step.y * len + len / 2.0,
        };
    }
    return path;
}

/// Compute Hilbert path U positions.
fn computeHilbertStep(order: i32, index: u32) rl.Vector2 {
    // Hilbert points base pattern
    const hilbert_points = [4]rl.Vector2{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 1 },
        .{ .x = 1, .y = 1 },
        .{ .x = 1, .y = 0 },
    };

    var vect = hilbert_points[index & 3];
    var remaining = index;

    var j: u5 = 1;
    while (j < order) : (j += 1) {
        remaining >>= 2;
        const len: f32 = @floatFromInt(@as(i32, 1) << j);

        const prev = vect; // Snapshot: the swaps below read the old coordinates
        switch (remaining & 3) {
            0 => vect = .{ .x = prev.y, .y = prev.x },
            1 => vect.y += len,
            2 => {
                vect.x += len;
                vect.y += len;
            },
            3 => vect = .{ .x = 2 * len - 1 - prev.y, .y = len - 1 - prev.x },
            else => unreachable,
        }
    }

    return vect;
}
