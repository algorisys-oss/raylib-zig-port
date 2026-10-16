//! raylib [shapes] example - kaleidoscope
//!
//! Zig-API translation of examples/shapes/shapes_kaleidoscope.c (raylib 6.2).
//! Example contributed by Hugo ARNAL (@hugoarnal) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Hugo ARNAL (@hugoarnal) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const gui = @import("raygui");

const max_draw_lines = 8192;

/// Line data type
const Line = struct {
    start: rl.Vector2 = .{ .x = 0, .y = 0 },
    end: rl.Vector2 = .{ .x = 0, .y = 0 },
};

// Lines array as a global variable to be stored in static memory
// and avoid potential stack overflow (on Web platform)
var lines: [max_draw_lines]Line = @splat(.{});

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - kaleidoscope");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Line drawing properties
    const symmetry = 6;
    const angle: f32 = 360.0 / @as(f32, symmetry);
    const thickness: f32 = 3.0;
    const reset_button_rec: rl.Rectangle = .{ .x = screen_width - 55.0, .y = 5.0, .width = 50, .height = 25 };
    const back_button_rec: rl.Rectangle = .{ .x = screen_width - 55.0, .y = screen_height - 30.0, .width = 25, .height = 25 };
    const next_button_rec: rl.Rectangle = .{ .x = screen_width - 30.0, .y = screen_height - 30.0, .width = 25, .height = 25 };
    var mouse_pos: rl.Vector2 = .{ .x = 0, .y = 0 };
    const scale_vector: rl.Vector2 = .{ .x = 1.0, .y = -1.0 };
    const offset: rl.Vector2 = .{
        .x = @as(f32, @floatFromInt(rl.getRenderWidth())) / 2.0,
        .y = @as(f32, @floatFromInt(rl.getRenderHeight())) / 2.0,
    };

    const camera: rl.Camera2D = .{
        .target = .{ .x = 0, .y = 0 },
        .offset = offset,
        .rotation = 0.0,
        .zoom = 1.0,
    };

    var current_line_counter: usize = 0;
    var total_line_counter: usize = 0;
    var reset_button_clicked = false;
    var back_button_clicked = false;
    var next_button_clicked = false;

    rl.setTargetFPS(20);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const prev_mouse_pos = mouse_pos;
        mouse_pos = rl.getMousePosition();

        var line_start = rl.math.vector2Subtract(mouse_pos, offset);
        var line_end = rl.math.vector2Subtract(prev_mouse_pos, offset);

        if (rl.isMouseButtonDown(.left) and
            !rl.checkCollisionPointRec(mouse_pos, reset_button_rec) and
            !rl.checkCollisionPointRec(mouse_pos, back_button_rec) and
            !rl.checkCollisionPointRec(mouse_pos, next_button_rec))
        {
            for (0..symmetry) |_| {
                if (total_line_counter >= max_draw_lines - 1) break;

                line_start = rl.math.vector2Rotate(line_start, angle * rl.deg2rad);
                line_end = rl.math.vector2Rotate(line_end, angle * rl.deg2rad);

                // Store mouse line
                lines[total_line_counter] = .{ .start = line_start, .end = line_end };

                // Store reflective line
                lines[total_line_counter + 1] = .{
                    .start = rl.math.vector2Multiply(line_start, scale_vector),
                    .end = rl.math.vector2Multiply(line_end, scale_vector),
                };

                total_line_counter += 2;
                current_line_counter = total_line_counter;
            }
        }

        if (reset_button_clicked) {
            @memset(&lines, .{});
            current_line_counter = 0;
            total_line_counter = 0;
        }

        if (back_button_clicked and current_line_counter > 0) {
            current_line_counter -= 1;
        }

        if (next_button_clicked and current_line_counter < max_draw_lines and current_line_counter + 1 <= total_line_counter) {
            current_line_counter += 1;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode2D(camera);
            defer rl.endMode2D();

            for (0..symmetry) |_| {
                var i: usize = 0;
                while (i < current_line_counter) : (i += 2) {
                    rl.drawLineEx(lines[i].start, lines[i].end, thickness, .black);
                    rl.drawLineEx(lines[i + 1].start, lines[i + 1].end, thickness, .black);
                }
            }
        }

        if (current_line_counter == 0) gui.disable();

        back_button_clicked = gui.button(back_button_rec, "<") != 0;
        gui.enable();

        if (current_line_counter + 1 > total_line_counter) gui.disable();

        next_button_clicked = gui.button(next_button_rec, ">") != 0;
        gui.enable();
        reset_button_clicked = gui.button(reset_button_rec, "Reset") != 0;

        rl.drawText(rl.textFormat("LINES: {d}/{d}", .{ current_line_counter, max_draw_lines }), 10, screen_height - 30, 20, .maroon);
        rl.drawFPS(10, 10);
    }
}
