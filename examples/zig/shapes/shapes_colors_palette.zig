//! raylib [shapes] example - colors palette
//!
//! Zig-API translation of examples/shapes/shapes_colors_palette.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const NamedColor = struct { color: rl.Color, name: [:0]const u8 };

const palette = [_]NamedColor{
    .{ .color = .dark_gray, .name = "DARKGRAY" },
    .{ .color = .maroon, .name = "MAROON" },
    .{ .color = .orange, .name = "ORANGE" },
    .{ .color = .dark_green, .name = "DARKGREEN" },
    .{ .color = .dark_blue, .name = "DARKBLUE" },
    .{ .color = .dark_purple, .name = "DARKPURPLE" },
    .{ .color = .dark_brown, .name = "DARKBROWN" },
    .{ .color = .gray, .name = "GRAY" },
    .{ .color = .red, .name = "RED" },
    .{ .color = .gold, .name = "GOLD" },
    .{ .color = .lime, .name = "LIME" },
    .{ .color = .blue, .name = "BLUE" },
    .{ .color = .violet, .name = "VIOLET" },
    .{ .color = .brown, .name = "BROWN" },
    .{ .color = .light_gray, .name = "LIGHTGRAY" },
    .{ .color = .pink, .name = "PINK" },
    .{ .color = .yellow, .name = "YELLOW" },
    .{ .color = .green, .name = "GREEN" },
    .{ .color = .sky_blue, .name = "SKYBLUE" },
    .{ .color = .purple, .name = "PURPLE" },
    .{ .color = .beige, .name = "BEIGE" },
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - colors palette");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Fills colors_recs data (for every rectangle)
    var colors_recs: [palette.len]rl.Rectangle = undefined;
    for (&colors_recs, 0..) |*rec, i| {
        const col: f32 = @floatFromInt(i % 7);
        const row: f32 = @floatFromInt(i / 7);
        const fi: f32 = @floatFromInt(i);
        rec.* = .{
            .x = 20.0 + 100.0 * col + 10.0 * col,
            .y = 80.0 + 100.0 * row + 10.0 * (fi / 7),
            .width = 100.0,
            .height = 100.0,
        };
    }

    var hovered: [palette.len]bool = @splat(false); // Color state: mouse hover

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_point = rl.getMousePosition();

        for (&hovered, colors_recs) |*h, rec| h.* = rl.checkCollisionPointRec(mouse_point, rec);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("raylib colors palette", 28, 42, 20, .black);
        rl.drawText("press SPACE to see all colors", rl.getScreenWidth() - 180, rl.getScreenHeight() - 40, 10, .gray);

        for (palette, colors_recs, hovered) |entry, rec, hover| { // Draw all rectangles
            rl.drawRectangleRec(rec, rl.fade(entry.color, if (hover) 0.6 else 1.0));

            if (rl.isKeyDown(.space) or hover) {
                rl.drawRectangle(@intFromFloat(rec.x), @intFromFloat(rec.y + rec.height - 26), @intFromFloat(rec.width), 20, .black);
                rl.drawRectangleLinesEx(rec, 6, rl.fade(.black, 0.3));
                const text_width: f32 = @floatFromInt(rl.measureText(entry.name, 10));
                rl.drawText(entry.name, @intFromFloat(rec.x + rec.width - text_width - 12), @intFromFloat(rec.y + rec.height - 20), 10, entry.color);
            }
        }
    }
}
