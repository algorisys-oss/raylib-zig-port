//! raylib [text] example - input box
//!
//! Zig-API translation of examples/text/text_input_box.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const max_input_chars = 9;

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - input box");
    defer rl.closeWindow(); // Close window and OpenGL context

    var name: [max_input_chars + 1]u8 = @splat(0); // NOTE: One extra space required for null terminator char '\0'
    var letter_count: usize = 0;

    const text_box: rl.Rectangle = .{ .x = screen_width / 2.0 - 100, .y = 180, .width = 225, .height = 50 };

    var frames_counter: u32 = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_on_text = rl.checkCollisionPointRec(rl.getMousePosition(), text_box);

        if (mouse_on_text) {
            // Set the window's cursor to the I-Beam
            rl.setMouseCursor(.ibeam);

            // Get char pressed (unicode character) on the queue,
            // checking if more characters have been pressed on the same frame
            var key = rl.getCharPressed();
            while (key > 0) : (key = rl.getCharPressed()) {
                // NOTE: Only allow keys in range [32..125]
                if (key >= 32 and key <= 125 and letter_count < max_input_chars) {
                    name[letter_count] = @intCast(key);
                    name[letter_count + 1] = 0; // Add null terminator at the end of the string
                    letter_count += 1;
                }
            }

            if (rl.isKeyPressed(.backspace)) {
                letter_count -|= 1;
                name[letter_count] = 0;
            }
        } else rl.setMouseCursor(.default);

        if (mouse_on_text) frames_counter += 1 else frames_counter = 0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("PLACE MOUSE OVER INPUT BOX!", 240, 140, 20, .gray);

        const box_x: i32 = @intFromFloat(text_box.x);
        const box_y: i32 = @intFromFloat(text_box.y);
        rl.drawRectangleRec(text_box, .light_gray);
        const border: rl.Color = if (mouse_on_text) .red else .dark_gray;
        rl.drawRectangleLines(box_x, box_y, @intFromFloat(text_box.width), @intFromFloat(text_box.height), border);

        const text = name[0..letter_count :0];
        rl.drawText(text, box_x + 5, box_y + 8, 40, .maroon);

        rl.drawText(rl.textFormat("INPUT CHARS: {d}/{d}", .{ letter_count, max_input_chars }), 315, 250, 20, .dark_gray);

        if (mouse_on_text) {
            if (letter_count < max_input_chars) {
                // Draw blinking underscore char
                if ((frames_counter / 20) % 2 == 0) rl.drawText("_", box_x + 8 + rl.measureText(text, 40), box_y + 12, 40, .maroon);
            } else rl.drawText("Press BACKSPACE to delete chars...", 230, 300, 20, .gray);
        }
    }
}
