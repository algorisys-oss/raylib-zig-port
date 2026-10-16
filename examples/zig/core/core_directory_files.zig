//! raylib [core] example - directory files
//!
//! Zig-API translation of examples/core/core_directory_files.c (raylib 6.2).
//! Example contributed by Hugo ARNAL (@hugoarnal) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Hugo ARNAL (@hugoarnal)

const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");

const max_filepath_size = 1024;
const file_filter = "DIRS*;.png;.c";

/// Scroll/selection state of the file list view.
const ListState = struct {
    scroll_index: i32 = 0,
    item_active: i32 = -1,
    item_focused: i32 = -1,
};

/// Replace `files` with the filtered listing of `directory`.
fn reloadFiles(files: *rl.FilePathList, directory: *const [max_filepath_size:0]u8) void {
    rl.unloadDirectoryFiles(files.*);
    files.* = rl.loadDirectoryFilesEx(std.mem.sliceTo(directory, 0), file_filter, false);
}

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - directory files");
    defer rl.closeWindow(); // Close window and OpenGL context

    var directory: [max_filepath_size:0]u8 = @splat(0);
    _ = rl.textCopy(&directory, rl.getWorkingDirectory());

    // Load file-paths on current working directory
    // NOTE: loadDirectoryFiles() loads files and directories by default,
    // use loadDirectoryFilesEx() for custom filters and recursive directories loading
    var files = rl.loadDirectoryFilesEx(std.mem.sliceTo(&directory, 0), file_filter, false);
    defer rl.unloadDirectoryFiles(files);

    var btn_back_pressed = false;
    var list: ListState = .{};

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (btn_back_pressed) {
            _ = rl.textCopy(&directory, rl.getPrevDirectoryPath(std.mem.sliceTo(&directory, 0)));
            reloadFiles(&files, &directory);
            list = .{};
        }

        const paths = files.slice();
        if (list.item_active >= 0 and list.item_active < paths.len) {
            const path = std.mem.span(paths[@intCast(list.item_active)]);
            if (rl.directoryExists(path)) {
                _ = rl.textCopy(&directory, path);
                reloadFiles(&files, &directory);
                list = .{};
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        btn_back_pressed = gui.button(.{ .x = 40.0, .y = 10.0, .width = 48, .height = 28 }, "<") != 0;

        gui.setStyle(.default, gui.DefaultProperty.text_size, gui.getFont().baseSize * 2);
        _ = gui.label(.{ .x = 40 + 48 + 10, .y = 10, .width = 700, .height = 28 }, std.mem.sliceTo(&directory, 0));
        gui.setStyle(.default, gui.DefaultProperty.text_size, gui.getFont().baseSize);

        gui.setStyle(.listview, gui.ControlProperty.text_alignment, @backingInt(gui.TextAlignment.left));
        gui.setStyle(.listview, gui.ControlProperty.text_padding, 40);
        const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
        _ = gui.listViewEx(.{ .x = 0, .y = 50, .width = screen_w, .height = screen_h - 50 }, files.slice(), &list.scroll_index, &list.item_active, &list.item_focused);
    }
}
