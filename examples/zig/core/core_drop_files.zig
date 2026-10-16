//! raylib [core] example - drop files
//!
//! Zig-API translation of examples/core/core_drop_files.c (raylib 6.2).
//! NOTE: This example only works on platforms that support drag & drop (Windows, Linux, OSX, Html5?)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const max_filepath_recorded = 4096;
const max_filepath_size = 2048;

pub fn main(init: std.process.Init) !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - drop files");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Allocate space for the required file paths: we will register a maximum of filepaths
    const file_paths = try init.gpa.alloc([max_filepath_size:0]u8, max_filepath_recorded);
    defer init.gpa.free(file_paths);
    var file_path_counter: usize = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isFileDropped()) {
            const dropped_files = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(dropped_files); // Unload filepaths from memory

            for (dropped_files.slice()) |path| {
                if (file_path_counter >= max_filepath_recorded - 1) break;
                _ = rl.textCopy(&file_paths[file_path_counter], std.mem.span(path));
                file_path_counter += 1;
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        if (file_path_counter == 0) {
            rl.drawText("Drop your files to this window!", 100, 40, 20, .dark_gray);
        } else {
            rl.drawText("Dropped files:", 100, 40, 20, .dark_gray);

            for (file_paths[0..file_path_counter], 0..) |*path, i| {
                const y: i32 = @intCast(40 * i);
                const alpha: f32 = if (i % 2 == 0) 0.5 else 0.3;
                rl.drawRectangle(0, 85 + y, screen_width, 40, rl.fade(.light_gray, alpha));

                rl.drawText(std.mem.sliceTo(path, 0), 120, 100 + y, 10, .gray);
            }

            rl.drawText("Drop new files...", 100, 110 + 40 * @as(i32, @intCast(file_path_counter)), 20, .dark_gray);
        }
    }
}
