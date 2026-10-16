//! raylib [core] example - text file loading
//!
//! Zig-API translation of examples/core/core_text_file_loading.c (raylib 6.2).
//! Example contributed by Aanjishnu Bhattacharyya (@NimComPoo-04) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 0 Aanjishnu Bhattacharyya (@NimComPoo-04)

const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - text file loading");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Setting up the camera
    var cam: rl.Camera2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .target = .{ .x = 0, .y = 0 },
        .rotation = 0,
        .zoom = 1,
    };

    // Loading text file from resources/text_file.txt
    const file_name = "resources/text_file.txt";
    const text = try rl.loadFileText(file_name);
    defer rl.unloadFileText(text);

    // Loading all the text lines
    const lines = try rl.loadTextLines(text);
    defer rl.unloadTextLines(lines);

    // Stylistic choises
    const font_size = 20;
    const text_top = 25 + font_size; // Top of the screen from where the text is rendered
    const wrap_width = screen_width - 20;

    // Wrap the lines as needed
    for (lines) |line_ptr| wrapLine(std.mem.span(line_ptr), font_size, wrap_width);

    // Calculating the total height so that we can show a scrollbar
    var text_height: i32 = 0;

    for (lines) |line| {
        const size = rl.measureTextEx(rl.getFontDefault(), std.mem.span(line), font_size, 2);
        text_height += @as(i32, @intFromFloat(size.y)) + 10;
    }

    // A simple scrollbar on the side to show how far we have read into the file
    const scroll_range: f32 = @floatFromInt(text_height - screen_height);
    var scroll_bar: rl.Rectangle = .{
        .x = screen_width - 5,
        .y = 0,
        .width = 5,
        .height = screen_height * 100.0 / scroll_range, // Scrollbar height is just a percentage
    };

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const scroll = rl.getMouseWheelMove();
        cam.target.y -= scroll * font_size * 1.5; // Choosing an arbitrary speed for scroll

        if (cam.target.y < 0) cam.target.y = 0; // Snapping to 0 if we go too far back

        // Ensuring that the camera does not scroll past all text
        if (cam.target.y > @as(f32, @floatFromInt(text_height - screen_height + text_top))) {
            cam.target.y = @as(f32, @floatFromInt(text_height)) - screen_height + text_top;
        }

        // Computing the position of the scrollBar depending on the percentage of text covered
        scroll_bar.y = rl.math.lerp(text_top, screen_height - scroll_bar.height, (cam.target.y - text_top) / scroll_range);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode2D(cam);
            defer rl.endMode2D();

            // Going through all the read lines
            var t: i32 = text_top;
            for (lines) |line_ptr| {
                const line = std.mem.span(line_ptr);

                // Each time we go through and calculate the height of the text to move the cursor appropriately
                // (an empty line is measured as a space)
                const size = rl.measureTextEx(rl.getFontDefault(), if (line.len > 0) line else " ", font_size, 2);

                rl.drawText(line, 10, t, font_size, .red);

                // Inserting extra space for real newlines,
                // wrapped lines are rendered closer together
                t += @as(i32, @intFromFloat(size.y)) + 10;
            }
        }

        // Header displaying which file is being read currently
        rl.drawRectangle(0, 0, screen_width, text_top - 10, .beige);
        rl.drawText(rl.textFormat("File: {s}", .{file_name}), 10, 10, font_size, .maroon);

        rl.drawRectangleRec(scroll_bar, .maroon);
    }
}

/// Word-wrap `line` in place: a space is replaced by '\n' wherever the text
/// since the last wrap would get wider than `wrap_width`.
fn wrapLine(line: [:0]u8, font_size: i32, wrap_width: i32) void {
    var last_space: usize = 0; // Keeping track of last valid space to insert '\n'
    var last_wrap_start: usize = 0; // Keeping track of the start of this wrapped line

    for (0..line.len + 1) |j| {
        const before = line[j];
        if (before != ' ' and before != 0) continue;

        // Terminate the string here so that we can use the measureText function
        line[j] = 0;

        // Checking if the text has crossed the wrap_width, then going back and inserting a newline
        if (rl.measureText(line[last_wrap_start..j :0], font_size) > wrap_width) {
            line[last_space] = '\n';

            // Since we added a newline the place of wrap changed so we update our last_wrap_start
            last_wrap_start = last_space + 1;
        }

        line[j] = before; // Resetting the space back
        last_space = j; // Since we encountered a new space we update our last encountered space location
    }
}
