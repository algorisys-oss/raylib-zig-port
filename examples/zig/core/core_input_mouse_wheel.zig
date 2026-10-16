//! raylib [core] example - input mouse wheel
//!
//! Zig-API translation of examples/core/core_input_mouse_wheel.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - input mouse wheel");
    defer rl.closeWindow(); // Close window and OpenGL context

    var box_position_y: i32 = screen_height / 2 - 40;
    const scroll_speed: f32 = 4; // Scrolling speed in pixels

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        box_position_y -= @intFromFloat(rl.getMouseWheelMove() * scroll_speed);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawRectangle(screen_width / 2 - 40, box_position_y, 80, 80, .maroon);

        rl.drawText("Use mouse wheel to move the cube up and down!", 10, 10, 20, .gray);
        // C's "%03i": zero-padded to 3 columns, the sign included in the width
        // (std.fmt would print a '+' for a padded signed integer, so pad the magnitude)
        const sign: []const u8 = if (box_position_y < 0) "-" else "";
        const text = rl.textFormat("Box position Y: {s}{d:0>[2]}", .{ sign, @abs(box_position_y), 3 - sign.len });
        rl.drawText(text, 10, 40, 20, .light_gray);
    }
}
