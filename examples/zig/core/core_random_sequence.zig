//! raylib [core] example - random sequence
//!
//! Zig-API translation of examples/core/core_random_sequence.c (raylib 6.2).
//! Example contributed by Dalton Overmyer (@REDl3east) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 Dalton Overmyer (@REDl3east)

const std = @import("std");
const rl = @import("raylib");

const ColorRect = struct {
    color: rl.Color,
    rect: rl.Rectangle,
};

const screen_width = 800;
const screen_height = 450;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [core] example - random sequence");
    defer rl.closeWindow(); // Close window and OpenGL context

    var rect_count: usize = 20;
    var rectangles = try generateRandomColorRectSequence(gpa, rect_count);
    defer gpa.free(rectangles);

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.space)) try shuffleColorRectSequence(rectangles);

        if (rl.isKeyPressed(.up)) {
            rect_count += 1;

            // Re-generate random sequence with new count
            gpa.free(rectangles);
            rectangles = try generateRandomColorRectSequence(gpa, rect_count);
        }

        if (rl.isKeyPressed(.down)) {
            if (rect_count >= 4) {
                rect_count -= 1;

                // Re-generate random sequence with new count
                gpa.free(rectangles);
                rectangles = try generateRandomColorRectSequence(gpa, rect_count);
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        for (rectangles) |rectangle| {
            rl.drawRectangleRec(rectangle.rect, rectangle.color);

            rl.drawText("Press SPACE to shuffle the current sequence", 10, screen_height - 96, 20, .black);
            rl.drawText("Press UP to add a rectangle and generate a new sequence", 10, screen_height - 64, 20, .black);
            rl.drawText("Press DOWN to remove a rectangle and generate a new sequence", 10, screen_height - 32, 20, .black);
        }

        rl.drawText(rl.textFormat("Count: {d} rectangles", .{rect_count}), 10, 10, 20, .maroon);

        rl.drawFPS(screen_width - 80, 10);
    }
}

fn generateRandomColor() rl.Color {
    return .{
        .r = @intCast(rl.getRandomValue(0, 255)),
        .g = @intCast(rl.getRandomValue(0, 255)),
        .b = @intCast(rl.getRandomValue(0, 255)),
        .a = 255,
    };
}

/// Bars of random heights (a shuffled 0..count-1 ramp) spanning the screen width.
fn generateRandomColorRectSequence(gpa: std.mem.Allocator, count: usize) ![]ColorRect {
    const rect_count: f32 = @floatFromInt(count);
    const rect_width = @as(f32, screen_width) / rect_count;
    const height = 0.75 * @as(f32, screen_height);

    const rectangles = try gpa.alloc(ColorRect, count);
    errdefer gpa.free(rectangles);

    const seq = try rl.loadRandomSequence(@intCast(count), 0, @intCast(count - 1));
    defer rl.unloadRandomSequence(seq);

    const rect_seq_width = rect_count * rect_width;
    const start_x = (screen_width - rect_seq_width) * 0.5;

    for (rectangles, seq, 0..) |*rectangle, value, i| {
        const rect_height: i32 = @intFromFloat(rl.math.remap(@floatFromInt(value), 0, rect_count - 1, 0, height));
        const rect_h: f32 = @floatFromInt(rect_height);

        rectangle.color = generateRandomColor();
        rectangle.rect = .{
            .x = start_x + @as(f32, @floatFromInt(i)) * rect_width,
            .y = height - rect_h,
            .width = rect_width,
            .height = rect_h,
        };
    }

    return rectangles;
}

/// Shuffle the bars: swap only the color and height.
fn shuffleColorRectSequence(rectangles: []ColorRect) !void {
    const seq = try rl.loadRandomSequence(@intCast(rectangles.len), 0, @intCast(rectangles.len - 1));
    defer rl.unloadRandomSequence(seq);

    for (rectangles, seq) |*r1, index| {
        const r2 = &rectangles[@intCast(index)];

        const tmp = r1.*;
        r1.color = r2.color;
        r1.rect.height = r2.rect.height;
        r1.rect.y = r2.rect.y;
        r2.color = tmp.color;
        r2.rect.height = tmp.rect.height;
        r2.rect.y = tmp.rect.y;
    }
}
