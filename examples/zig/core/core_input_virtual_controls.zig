//! raylib [core] example - input virtual controls
//!
//! Zig-API translation of examples/core/core_input_virtual_controls.c (raylib 6.2).
//! Example contributed by GreenSnakeLinux (@GreenSnakeLinux),
//! reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2024-2025 GreenSnakeLinux (@GreenSnakeLinux) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const PadButton = enum { up, left, right, down };

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - input virtual controls");
    defer rl.closeWindow(); // Close window and OpenGL context

    const pad_position: rl.Vector2 = .{ .x = 100, .y = 350 };
    const button_radius: f32 = 30;

    const button_positions = [_]rl.Vector2{
        .{ .x = pad_position.x, .y = pad_position.y - button_radius * 1.5 }, // Up
        .{ .x = pad_position.x - button_radius * 1.5, .y = pad_position.y }, // Left
        .{ .x = pad_position.x + button_radius * 1.5, .y = pad_position.y }, // Right
        .{ .x = pad_position.x, .y = pad_position.y + button_radius * 1.5 }, // Down
    };

    const up = button_positions[0];
    const left = button_positions[1];
    const right = button_positions[2];
    const down = button_positions[3];
    const arrow_tris = [_][3]rl.Vector2{
        // Up
        .{
            .{ .x = up.x, .y = up.y - 12 },
            .{ .x = up.x - 9, .y = up.y + 9 },
            .{ .x = up.x + 9, .y = up.y + 9 },
        },
        // Left
        .{
            .{ .x = left.x + 9, .y = left.y - 9 },
            .{ .x = left.x - 12, .y = left.y },
            .{ .x = left.x + 9, .y = left.y + 9 },
        },
        // Right
        .{
            .{ .x = right.x + 12, .y = right.y },
            .{ .x = right.x - 9, .y = right.y - 9 },
            .{ .x = right.x - 9, .y = right.y + 9 },
        },
        // Down
        .{
            .{ .x = down.x - 9, .y = down.y - 9 },
            .{ .x = down.x, .y = down.y + 12 },
            .{ .x = down.x + 9, .y = down.y - 9 },
        },
    };

    const button_label_colors = [_]rl.Color{
        .yellow, // Up
        .blue, // Left
        .red, // Right
        .green, // Down
    };

    var player_position: rl.Vector2 = .{ .x = screen_width / 2.0, .y = screen_height / 2.0 };
    const player_speed: f32 = 75;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const touching = rl.getTouchPointCount() > 0;
        // Use touch position, or mouse position
        const input_position = if (touching) rl.getTouchPosition(0) else rl.getMousePosition();

        // Make sure user is pressing left mouse button if they're from desktop
        var pressed_button: ?PadButton = null;
        if (touching or rl.isMouseButtonDown(.left)) {
            // Find nearest D-Pad button to the input position
            for (button_positions, 0..) |position, i| {
                const dist_x = @abs(position.x - input_position.x);
                const dist_y = @abs(position.y - input_position.y);

                if (dist_x + dist_y < button_radius) {
                    pressed_button = @fromBackingInt(@intCast(i));
                    break;
                }
            }
        }

        // Move player according to pressed button
        if (pressed_button) |button| switch (button) {
            .up => player_position.y -= player_speed * rl.getFrameTime(),
            .left => player_position.x -= player_speed * rl.getFrameTime(),
            .right => player_position.x += player_speed * rl.getFrameTime(),
            .down => player_position.y += player_speed * rl.getFrameTime(),
        };

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw world
        rl.drawCircleV(player_position, 50, .maroon);

        // Draw GUI
        for (button_positions, arrow_tris, button_label_colors, 0..) |position, tri, label_color, i| {
            const pressed = if (pressed_button) |button| @backingInt(button) == i else false;
            rl.drawCircleV(position, button_radius, if (pressed) .dark_gray else .black);

            rl.drawTriangle(tri[0], tri[1], tri[2], label_color);
        }

        rl.drawText("move the player with D-Pad buttons", 10, 10, 20, .dark_gray);
    }
}
