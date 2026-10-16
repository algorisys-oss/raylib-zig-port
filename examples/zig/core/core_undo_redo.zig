//! raylib [core] example - undo redo
//!
//! Zig-API translation of examples/core/core_undo_redo.c (raylib 6.2).
//! Example contributed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const max_undo_states = 26; // Maximum undo states supported for the ring buffer

const grid_cell_size = 24;
const max_grid_cells_x = 30;
const max_grid_cells_y = 13;

/// Point struct, like Vector2 but using int
const Point = struct {
    x: i32,
    y: i32,
};

/// Player state struct
/// NOTE: Contains all player data that needs to be affected by undo/redo
const PlayerState = struct {
    cell: Point,
    color: rl.Color,
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    // We have multiple options to implement an Undo/Redo system
    // Probably the most professional one is using the Command pattern to
    // define Actions and store those actions into an array as the events happen,
    // raylib internal Automation System actually uses a similar approach,
    // but in this example we are using another more simple solution,
    // just record PlayerState changes when detected, checking for changes every certain frames
    // This approach requires more memory and is more performance costly but it is quite simple to implement

    rl.initWindow(screen_width, screen_height, "raylib [core] example - undo redo");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Undo/redo system variables
    var current_undo_index: usize = 0;
    var first_undo_index: usize = 0;
    var last_undo_index: usize = 0;
    var undo_frame_counter: i32 = 0;
    const undo_info_pos: rl.Vector2 = .{ .x = 110, .y = 400 };

    // Init current player state and undo/redo recorded states array
    var player: PlayerState = .{ .cell = .{ .x = 10, .y = 10 }, .color = .red };

    // Init all undo states (ring buffer of max_undo_states) to current state
    var states: [max_undo_states]PlayerState = @splat(player);

    // Grid variables
    const grid_position: rl.Vector2 = .{ .x = 40, .y = 60 };
    const grid_x: i32 = @intFromFloat(grid_position.x);
    const grid_y: i32 = @intFromFloat(grid_position.y);

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Player movement logic
        if (rl.isKeyPressed(.right)) {
            player.cell.x += 1;
        } else if (rl.isKeyPressed(.left)) {
            player.cell.x -= 1;
        } else if (rl.isKeyPressed(.up)) {
            player.cell.y -= 1;
        } else if (rl.isKeyPressed(.down)) {
            player.cell.y += 1;
        }

        // Make sure player does not go out of bounds
        player.cell.x = std.math.clamp(player.cell.x, 0, max_grid_cells_x - 1);
        player.cell.y = std.math.clamp(player.cell.y, 0, max_grid_cells_y - 1);

        // Player color change logic
        if (rl.isKeyPressed(.space)) {
            player.color.r = @intCast(rl.getRandomValue(20, 255));
            player.color.g = @intCast(rl.getRandomValue(20, 220));
            player.color.b = @intCast(rl.getRandomValue(20, 240));
        }

        // Undo state change logic
        undo_frame_counter += 1;

        // Waiting a number of frames before checking if we should store a new state snapshot
        if (undo_frame_counter >= 2) { // Checking every 2 frames
            if (!std.meta.eql(states[current_undo_index], player)) {
                // Move cursor to next available position of the undo ring buffer to record state
                current_undo_index = (current_undo_index + 1) % max_undo_states;
                if (current_undo_index == first_undo_index) first_undo_index = (first_undo_index + 1) % max_undo_states;

                states[current_undo_index] = player;
                last_undo_index = current_undo_index;
            }

            undo_frame_counter = 0;
        }

        // Recover previous state from buffer: CTRL+Z
        if (rl.isKeyDown(.left_control) and rl.isKeyPressed(.z)) {
            if (current_undo_index != first_undo_index) {
                current_undo_index = (current_undo_index + max_undo_states - 1) % max_undo_states;
                player = states[current_undo_index];
            }
        }

        // Recover next state from buffer: CTRL+Y
        if (rl.isKeyDown(.left_control) and rl.isKeyPressed(.y)) {
            if (current_undo_index != last_undo_index) {
                const next_undo_index = (current_undo_index + 1) % max_undo_states;

                if (next_undo_index != first_undo_index) {
                    current_undo_index = next_undo_index;
                    player = states[current_undo_index];
                }
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw controls info
        rl.drawText("[ARROWS] MOVE PLAYER - [SPACE] CHANGE PLAYER COLOR", 40, 20, 20, .dark_gray);

        // Draw player visited cells recorded by undo
        // NOTE: Remember we are using a ring buffer approach so,
        // some cells info could start at the end of the array and end at the beginning
        if (last_undo_index > first_undo_index) {
            for (states[first_undo_index..current_undo_index]) |state| drawVisitedCell(grid_position, state.cell);
        } else if (first_undo_index > last_undo_index) {
            if (current_undo_index > last_undo_index) {
                for (states[first_undo_index..current_undo_index]) |state| drawVisitedCell(grid_position, state.cell);
            } else {
                for (states[first_undo_index..]) |state| {
                    rl.drawRectangle(grid_x + state.cell.x * grid_cell_size, grid_y + state.cell.y * grid_cell_size, grid_cell_size, grid_cell_size, .light_gray);
                }
                for (states[0..current_undo_index]) |state| {
                    rl.drawRectangle(grid_x + state.cell.x * grid_cell_size, grid_y + state.cell.y * grid_cell_size, grid_cell_size, grid_cell_size, .light_gray);
                }
            }
        }

        // Draw game grid
        for (0..max_grid_cells_y + 1) |y| {
            const line_y = grid_y + @as(i32, @intCast(y)) * grid_cell_size;
            rl.drawLine(grid_x, line_y, grid_x + max_grid_cells_x * grid_cell_size, line_y, .gray);
        }
        for (0..max_grid_cells_x + 1) |x| {
            const line_x = grid_x + @as(i32, @intCast(x)) * grid_cell_size;
            rl.drawLine(line_x, grid_y, line_x, grid_y + max_grid_cells_y * grid_cell_size, .gray);
        }

        // Draw player
        rl.drawRectangle(grid_x + player.cell.x * grid_cell_size, grid_y + player.cell.y * grid_cell_size, grid_cell_size + 1, grid_cell_size + 1, player.color);

        // Draw undo system buffer info
        rl.drawText("UNDO STATES:", @as(i32, @intFromFloat(undo_info_pos.x)) - 85, @as(i32, @intFromFloat(undo_info_pos.y)) + 9, 10, .dark_gray);
        drawUndoBuffer(undo_info_pos, first_undo_index, last_undo_index, current_undo_index, 24);
    }
}

fn drawVisitedCell(grid_position: rl.Vector2, cell: Point) void {
    rl.drawRectangleRec(.{
        .x = grid_position.x + @as(f32, @floatFromInt(cell.x * grid_cell_size)),
        .y = grid_position.y + @as(f32, @floatFromInt(cell.y * grid_cell_size)),
        .width = grid_cell_size,
        .height = grid_cell_size,
    }, .light_gray);
}

/// Draw undo system visualization logic
/// NOTE: Visualizing the ring buffer array, every square can store a player state
fn drawUndoBuffer(position: rl.Vector2, first_undo_index: usize, last_undo_index: usize, current_undo_index: usize, slot_size: i32) void {
    const x: i32 = @intFromFloat(position.x);
    const y: i32 = @intFromFloat(position.y);

    // Draw index marks
    rl.drawRectangle(x + 8 + slot_size * index(current_undo_index), y - 10, 8, 8, .red);
    rl.drawRectangleLines(x + 2 + slot_size * index(first_undo_index), y + 27, 8, 8, .black);
    rl.drawRectangle(x + 14 + slot_size * index(last_undo_index), y + 27, 8, 8, .black);

    // Draw background gray slots
    drawSlots(x, y, slot_size, 0, max_undo_states, .light_gray, .gray);

    // Draw occupied slots: first_undo_index --> last_undo_index
    if (first_undo_index <= last_undo_index) {
        drawSlots(x, y, slot_size, first_undo_index, last_undo_index + 1, .sky_blue, .blue);
    } else {
        drawSlots(x, y, slot_size, first_undo_index, max_undo_states, .sky_blue, .blue);
        drawSlots(x, y, slot_size, 0, last_undo_index + 1, .sky_blue, .blue);
    }

    // Draw occupied slots: first_undo_index --> current_undo_index
    if (first_undo_index < current_undo_index) {
        drawSlots(x, y, slot_size, first_undo_index, current_undo_index, .green, .lime);
    } else if (current_undo_index < first_undo_index) {
        drawSlots(x, y, slot_size, first_undo_index, max_undo_states, .green, .lime);
        drawSlots(x, y, slot_size, 0, current_undo_index, .green, .lime);
    }

    // Draw current selected UNDO slot
    drawSlots(x, y, slot_size, current_undo_index, current_undo_index + 1, .gold, .orange);
}

/// Draw the ring buffer slots [start, end) filled with `fill`, outlined with `outline`.
fn drawSlots(x: i32, y: i32, slot_size: i32, start: usize, end: usize, fill: rl.Color, outline: rl.Color) void {
    for (start..end) |i| {
        rl.drawRectangle(x + slot_size * index(i), y, slot_size, slot_size, fill);
        rl.drawRectangleLines(x + slot_size * index(i), y, slot_size, slot_size, outline);
    }
}

fn index(i: usize) i32 {
    return @intCast(i);
}
