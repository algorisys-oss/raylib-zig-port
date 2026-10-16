//! raylib [core] example - clipboard text
//!
//! Zig-API translation of examples/core/core_clipboard_text.c (raylib 6.2).
//! Example contributed by Ananth S (@Ananth1839) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Ananth S (@Ananth1839)

const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");

// Define some sample texts
const sample_texts = [_][:0]const u8{
    "Hello from raylib!",
    "The quick brown fox jumps over the lazy dog",
    "Clipboard operations are useful!",
    "raylib is a simple and easy-to-use library",
    "Copy and paste me!",
};

/// Copy `text` into the NUL-terminated `buffer`, truncating if needed.
fn setText(buffer: []u8, text: []const u8) void {
    const len = @min(text.len, buffer.len - 1);
    @memcpy(buffer[0..len], text[0..len]);
    buffer[len] = 0;
}

/// The text held in the NUL-terminated `buffer`.
fn getText(buffer: []u8) [:0]const u8 {
    return buffer[0..std.mem.indexOfScalar(u8, buffer, 0).? :0];
}

/// Read the clipboard into `buffer` for display; null if it holds no text.
fn readClipboard(buffer: []u8) ?[]u8 {
    const text = rl.getClipboardText() orelse return null;
    setText(buffer, text);
    return buffer;
}

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - clipboard text");
    defer rl.closeWindow(); // Close window and OpenGL context

    var clipboard_buffer: [256]u8 = undefined;
    var clipboard_text: ?[]u8 = null; // Last text read from the clipboard
    var input_buffer: [256]u8 = undefined;
    setText(&input_buffer, "Hello from raylib!"); // Random initial string

    // UI required variables
    var text_box_edit_mode = false;

    var btn_cut_pressed = false;
    var btn_copy_pressed = false;
    var btn_paste_pressed = false;
    var btn_clear_pressed = false;
    var btn_random_pressed = false;

    // Set UI style
    gui.setStyle(.default, gui.DefaultProperty.text_size, 20);
    gui.setIconScale(2);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const input_text = getText(&input_buffer);

        // Handle button interactions
        if (btn_cut_pressed) {
            rl.setClipboardText(input_text);
            clipboard_text = readClipboard(&clipboard_buffer);
            input_buffer[0] = 0; // Quick solution to clear text
        }

        if (btn_copy_pressed) {
            rl.setClipboardText(input_text); // Copy text to clipboard
            clipboard_text = readClipboard(&clipboard_buffer); // Get text from clipboard
        }

        if (btn_paste_pressed) {
            // Paste text from clipboard
            clipboard_text = readClipboard(&clipboard_buffer);
            if (clipboard_text) |text| setText(&input_buffer, text);
        }

        if (btn_clear_pressed) {
            input_buffer[0] = 0; // Quick solution to clear text
        }

        if (btn_random_pressed) {
            // Get random text from sample list
            const index: usize = @intCast(rl.getRandomValue(0, sample_texts.len - 1));
            setText(&input_buffer, sample_texts[index]);
        }

        // Quick cut/copy/paste with keyboard shortcuts
        if (rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control)) {
            if (rl.isKeyPressed(.x)) {
                rl.setClipboardText(input_text);
                input_buffer[0] = 0; // Quick solution to clear text
            }

            if (rl.isKeyPressed(.c)) rl.setClipboardText(input_text);

            if (rl.isKeyPressed(.v)) {
                clipboard_text = readClipboard(&clipboard_buffer);
                if (clipboard_text) |text| setText(&input_buffer, text);
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw instructions
        _ = gui.label(.{ .x = 50, .y = 20, .width = 700, .height = 36 }, "Use the BUTTONS or KEY SHORTCUTS:");
        rl.drawText("[CTRL+X] - CUT | [CTRL+C] COPY | [CTRL+V] | PASTE", 50, 60, 20, .maroon);

        // Draw text box
        if (gui.textBox(.{ .x = 50, .y = 120, .width = 652, .height = 40 }, &input_buffer, text_box_edit_mode) != 0) text_box_edit_mode = !text_box_edit_mode;

        // Random text button
        btn_random_pressed = gui.button(.{ .x = 50 + 652 + 8, .y = 120, .width = 40, .height = 40 }, "#77#") != 0;

        // Draw buttons
        btn_cut_pressed = gui.button(.{ .x = 50, .y = 180, .width = 158, .height = 40 }, "#17#CUT") != 0;
        btn_copy_pressed = gui.button(.{ .x = 50 + 165, .y = 180, .width = 158, .height = 40 }, "#16#COPY") != 0;
        btn_paste_pressed = gui.button(.{ .x = 50 + 165 * 2, .y = 180, .width = 158, .height = 40 }, "#18#PASTE") != 0;
        btn_clear_pressed = gui.button(.{ .x = 50 + 165 * 3, .y = 180, .width = 158, .height = 40 }, "#143#CLEAR") != 0;

        // Draw clipboard status
        gui.setState(.disabled);
        _ = gui.label(.{ .x = 50, .y = 260, .width = 700, .height = 40 }, "Clipboard current text data:");
        gui.setStyle(.textbox, gui.TextBoxProperty.text_readonly, 1);
        _ = gui.textBox(.{ .x = 50, .y = 300, .width = 700, .height = 40 }, clipboard_text, false);
        gui.setStyle(.textbox, gui.TextBoxProperty.text_readonly, 0);
        _ = gui.label(.{ .x = 50, .y = 360, .width = 700, .height = 40 }, "Try copying text from other applications and pasting here!");
        gui.setState(.normal);
    }
}
