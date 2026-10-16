//! raylib [textures] example - cellular automata
//!
//! Zig-API translation of examples/textures/textures_cellular_automata.c (raylib 6.2).
//! Example contributed by Jordi Santonja (@JordSant) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jordi Santonja (@JordSant)

const rl = @import("raylib");

// Initialization constants
const screen_width = 800;
const screen_height = 450;
const image_width = 800;
const image_height = 800 / 2;

// Rule button sizes and positions
const draw_rule_start_x = 585;
const draw_rule_start_y = 10;
const draw_rule_spacing = 15;
const draw_rule_group_spacing = 50;
const draw_rule_size = 14;
const draw_rule_inner_size = 10;

// Preset button sizes
const presets_size_x = 42;
const presets_size_y = 22;

const lines_updated_per_frame = 4;

// Some interesting rules
const preset_values = [_]i32{ 18, 30, 60, 86, 102, 124, 126, 150, 182, 225 };

/// Compute next line pixels. Boundaries are not computed, always 0
fn computeLine(image: *rl.Image, line: i32, rule: i32) void {
    var i: i32 = 1;
    while (i < image_width - 1) : (i += 1) {
        // Get, from the previous line, the 3 pixels states as a binary value
        const prev_value: u5 = (if (rl.getImageColor(image.*, i - 1, line - 1).r < 5) @as(u5, 4) else 0) + // Left pixel
            (if (rl.getImageColor(image.*, i, line - 1).r < 5) @as(u5, 2) else 0) + // Center pixel
            (if (rl.getImageColor(image.*, i + 1, line - 1).r < 5) @as(u5, 1) else 0); // Right pixel
        // Get next value from rule bitmask
        const curr_value = (rule & (@as(i32, 1) << prev_value)) != 0;
        // Update pixel color
        rl.imageDrawPixel(image, i, line, if (curr_value) .black else .ray_white);
    }
}

/// True when `point` lies within the box [x, x+w] x [y, y+h] (edges inclusive).
fn mouseInBox(point: rl.Vector2, x: i32, y: i32, w: i32, h: i32) bool {
    const fx: f32 = @floatFromInt(x);
    const fy: f32 = @floatFromInt(y);
    return (point.x >= fx) and (point.x <= @as(f32, @floatFromInt(x + w))) and
        (point.y >= fy) and (point.y <= @as(f32, @floatFromInt(y + h)));
}

fn presetX(i: i32) i32 {
    return (presets_size_x + 2) * @divTrunc(i, 2);
}

fn presetY(i: i32) i32 {
    return (presets_size_y + 2) * @rem(i, 2);
}

fn ruleX(i: i32) i32 {
    return draw_rule_start_x - draw_rule_group_spacing * i;
}

pub fn main() !void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [textures] example - cellular automata");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Image that contains the cellular automaton
    var image = rl.genImageColor(image_width, image_height, .ray_white);
    defer rl.unloadImage(image);
    // The top central pixel set as black
    rl.imageDrawPixel(&image, image_width / 2, 0, .black);

    const texture = try rl.loadTextureFromImage(image);
    defer rl.unloadTexture(texture);

    // Variables
    var rule: i32 = 30; // Starting rule
    var line: i32 = 1; // Line to compute, starting from line 1. One point in line 0 is already set

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Handle mouse
        const mouse = rl.getMousePosition();
        // null: outside any button; 0-7: rule cells; 8+: preset cells
        const mouse_in_cell: ?i32 = blk: {
            // Check mouse on rule cells
            for (0..8) |n| {
                const i: i32 = @intCast(n);
                if (mouseInBox(mouse, ruleX(i) + draw_rule_spacing, draw_rule_start_y + draw_rule_spacing, draw_rule_size, draw_rule_size)) {
                    break :blk i; // 0-7: rule cells
                }
            }
            // Check mouse on preset cells
            for (0..preset_values.len) |n| {
                const i: i32 = @intCast(n);
                if (mouseInBox(mouse, 4 + presetX(i), 2 + presetY(i), presets_size_x, presets_size_y)) {
                    break :blk i + 8; // 8+: preset cells
                }
            }
            break :blk null;
        };

        if (rl.isMouseButtonPressed(.left)) {
            if (mouse_in_cell) |cell| {
                // Rule changed both by selecting a preset or toggling a bit
                if (cell < 8) {
                    rule ^= @as(i32, 1) << @intCast(cell);
                } else {
                    rule = preset_values[@intCast(cell - 8)];
                }

                // Reset image
                rl.imageClearBackground(&image, .ray_white);
                rl.imageDrawPixel(&image, image_width / 2, 0, .black);
                line = 1;
            }
        }

        // Compute next lines
        if (line < image_height) {
            var i: i32 = 0;
            while ((i < lines_updated_per_frame) and (line + i < image_height)) : (i += 1) {
                computeLine(&image, line + i, rule);
            }
            line += lines_updated_per_frame;

            rl.updateTexture(texture, image.data.?);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw cellular automaton texture
        rl.drawTexture(texture, 0, screen_height - image_height, .white);

        // Draw preset values
        for (preset_values, 0..) |value, n| {
            const i: i32 = @intCast(n);
            rl.drawText(rl.textFormat("{d}", .{value}), 8 + presetX(i), 4 + presetY(i), 20, .gray);
            rl.drawRectangleLines(4 + presetX(i), 2 + presetY(i), presets_size_x, presets_size_y, .blue);

            // If the mouse is on this preset, highlight it
            if (mouse_in_cell == i + 8) {
                rl.drawRectangleLinesEx(.{
                    .x = 2 + (presets_size_x + 2.0) * @as(f32, @floatFromInt(@divTrunc(i, 2))),
                    .y = (presets_size_y + 2.0) * @as(f32, @floatFromInt(@rem(i, 2))),
                    .width = presets_size_x + 4.0,
                    .height = presets_size_y + 4.0,
                }, 3, .red);
            }
        }

        // Draw rule bits
        for (0..8) |n| {
            const i: i32 = @intCast(n);
            // The three input bits
            for (0..3) |j_index| {
                const j: i32 = @intCast(j_index);
                rl.drawRectangleLines(ruleX(i) + draw_rule_spacing * j, draw_rule_start_y, draw_rule_size, draw_rule_size, .gray);
                if (i & (@as(i32, 4) >> @intCast(j)) != 0) {
                    rl.drawRectangle(ruleX(i) + 2 + draw_rule_spacing * j, draw_rule_start_y + 2, draw_rule_inner_size, draw_rule_inner_size, .black);
                }
            }

            // The output bit
            rl.drawRectangleLines(ruleX(i) + draw_rule_spacing, draw_rule_start_y + draw_rule_spacing, draw_rule_size, draw_rule_size, .blue);
            if (rule & (@as(i32, 1) << @intCast(i)) != 0) {
                rl.drawRectangle(ruleX(i) + 2 + draw_rule_spacing, draw_rule_start_y + 2 + draw_rule_spacing, draw_rule_inner_size, draw_rule_inner_size, .black);
            }

            // If the mouse is on this rule bit, highlight it
            if (mouse_in_cell == i) {
                rl.drawRectangleLinesEx(.{
                    .x = @as(f32, @floatFromInt(ruleX(i) + draw_rule_spacing)) - 2.0,
                    .y = draw_rule_start_y + draw_rule_spacing - 2.0,
                    .width = draw_rule_size + 4.0,
                    .height = draw_rule_size + 4.0,
                }, 3, .red);
            }
        }

        rl.drawText(rl.textFormat("RULE: {d}", .{rule}), draw_rule_start_x + draw_rule_spacing * 4, draw_rule_start_y + 1, 30, .gray);
    }
}
