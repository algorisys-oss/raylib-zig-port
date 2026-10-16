//! raylib [shapes] example - recursive tree
//!
//! Zig-API translation of examples/shapes/shapes_recursive_tree.c (raylib 6.2).
//! Example contributed by Jopestpe (@jopestpe)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jopestpe (@jopestpe)

const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");

const Branch = struct {
    start: rl.Vector2,
    end: rl.Vector2,
    angle: f32,
    length: f32,

    /// The branch growing from `start` at `angle` (radians from vertical).
    fn grow(start: rl.Vector2, angle: f32, length: f32) Branch {
        return .{
            .start = start,
            .end = .{ .x = start.x + length * @sin(angle), .y = start.y - length * @cos(angle) },
            .angle = angle,
            .length = length,
        };
    }
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - recursive tree");
    defer rl.closeWindow(); // Close window and OpenGL context

    const start: rl.Vector2 = .{ .x = (screen_width / 2.0) - 125.0, .y = screen_height };
    var angle: f32 = 40.0;
    var thick: f32 = 1.0;
    var tree_depth: f32 = 10.0;
    var branch_decay: f32 = 0.66;
    var length: f32 = 120.0;
    var bezier = false;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const theta = angle * rl.deg2rad;
        const max_branches = std.math.pow(usize, 2, @intFromFloat(@floor(tree_depth)));
        var buffer: [1030]Branch = undefined;
        var branches: std.ArrayList(Branch) = .initBuffer(&buffer);

        branches.appendAssumeCapacity(.grow(start, 0.0, length));

        // Breadth-first: the list grows while it is being walked
        var i: usize = 0;
        while (i < branches.items.len) : (i += 1) {
            const branch = branches.items[i];
            if (branch.length < 2) continue;

            const next_length = branch.length * branch_decay;

            if (branches.items.len < max_branches and next_length >= 2) {
                branches.appendAssumeCapacity(.grow(branch.end, branch.angle + theta, next_length));
                branches.appendAssumeCapacity(.grow(branch.end, branch.angle - theta, next_length));
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        for (branches.items) |branch| {
            if (branch.length >= 2) {
                if (bezier) {
                    rl.drawLineBezier(branch.start, branch.end, thick, .red);
                } else {
                    rl.drawLineEx(branch.start, branch.end, thick, .red);
                }
            }
        }

        rl.drawLine(580, 0, 580, rl.getScreenHeight(), .{ .r = 218, .g = 218, .b = 218, .a = 255 });
        rl.drawRectangle(580, 0, rl.getScreenWidth(), rl.getScreenHeight(), .{ .r = 232, .g = 232, .b = 232, .a = 255 });

        // Draw GUI controls
        _ = gui.sliderBar(.{ .x = 640, .y = 40, .width = 120, .height = 20 }, "Angle", rl.textFormat("{d:.0}", .{angle}), &angle, 0, 180);
        _ = gui.sliderBar(.{ .x = 640, .y = 70, .width = 120, .height = 20 }, "Length", rl.textFormat("{d:.0}", .{length}), &length, 12.0, 240.0);
        _ = gui.sliderBar(.{ .x = 640, .y = 100, .width = 120, .height = 20 }, "Decay", rl.textFormat("{d:.2}", .{branch_decay}), &branch_decay, 0.1, 0.78);
        _ = gui.sliderBar(.{ .x = 640, .y = 130, .width = 120, .height = 20 }, "Depth", rl.textFormat("{d:.0}", .{tree_depth}), &tree_depth, 1.0, 10.0);
        _ = gui.sliderBar(.{ .x = 640, .y = 160, .width = 120, .height = 20 }, "Thick", rl.textFormat("{d:.0}", .{thick}), &thick, 1, 8);
        _ = gui.checkBox(.{ .x = 640, .y = 190, .width = 20, .height = 20 }, "Bezier", &bezier);

        rl.drawFPS(10, 10);
    }
}
