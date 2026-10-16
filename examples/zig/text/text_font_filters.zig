//! raylib [text] example - font filters
//!
//! NOTE: After font loading, font texture atlas filter could be configured for a softer
//! display of the font when scaling it to different sizes, that way, it's not required
//! to generate multiple fonts at multiple sizes (as long as the scaling is not very different)
//!
//! Zig-API translation of examples/text/text_font_filters.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [text] example - font filters");
    defer rl.closeWindow(); // Close window and OpenGL context

    const msg = "Loaded Font";

    // NOTE: Textures/Fonts MUST be loaded after Window initialization (OpenGL context is required)

    // TTF Font loading with custom generation parameters
    var font = try rl.loadFontEx("resources/KAISG.ttf", 96, null);
    defer rl.unloadFont(font); // Font unloading

    // Generate mipmap levels to use trilinear filtering
    // NOTE: On 2D drawing it won't be noticeable, it looks like FILTER_BILINEAR
    rl.genTextureMipmaps(&font.texture);

    var font_size: f32 = @floatFromInt(font.baseSize);
    var font_position: rl.Vector2 = .{ .x = 40.0, .y = screen_height / 2.0 - 80.0 };
    var text_size: rl.Vector2 = .{ .x = 0.0, .y = 0.0 };

    // Setup texture scaling filter
    var current_font_filter: rl.TextureFilter = .point;
    rl.setTextureFilter(font.texture, current_font_filter);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        font_size += rl.getMouseWheelMove() * 4.0;

        // Choose font texture filter method
        // NOTE: Trilinear filter won't be noticed on 2D drawing
        if (rl.isKeyPressed(.one)) {
            current_font_filter = .point;
            rl.setTextureFilter(font.texture, current_font_filter);
        } else if (rl.isKeyPressed(.two)) {
            current_font_filter = .bilinear;
            rl.setTextureFilter(font.texture, current_font_filter);
        } else if (rl.isKeyPressed(.three)) {
            current_font_filter = .trilinear;
            rl.setTextureFilter(font.texture, current_font_filter);
        }

        text_size = rl.measureTextEx(font, msg, font_size, 0);

        if (rl.isKeyDown(.left)) {
            font_position.x -= 10;
        } else if (rl.isKeyDown(.right)) {
            font_position.x += 10;
        }

        // Load a dropped TTF file dynamically (at current fontSize)
        if (rl.isFileDropped()) {
            const dropped_files = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(dropped_files); // Unload filepaths from memory

            // NOTE: We only support first ttf file dropped
            const path = std.mem.span(dropped_files.paths.?[0]);
            if (rl.isFileExtension(path, ".ttf")) {
                rl.unloadFont(font);
                font = rl.loadFontEx(path, @intFromFloat(font_size), null) catch rl.getFontDefault();
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("Use mouse wheel to change font size", 20, 20, 10, .gray);
        rl.drawText("Use KEY_RIGHT and KEY_LEFT to move text", 20, 40, 10, .gray);
        rl.drawText("Use 1, 2, 3 to change texture filter", 20, 60, 10, .gray);
        rl.drawText("Drop a new TTF font for dynamic loading", 20, 80, 10, .dark_gray);

        rl.drawTextEx(font, msg, font_position, font_size, 0, .black);

        // TODO: It seems texSize measurement is not accurate due to chars offsets...
        //rl.drawRectangleLines(font_position.x, font_position.y, text_size.x, text_size.y, .red);

        rl.drawRectangle(0, screen_height - 80, screen_width, 80, .light_gray);
        rl.drawText(rl.textFormat("Font size: {d:.2}", .{font_size}), 20, screen_height - 50, 10, .dark_gray);
        rl.drawText(rl.textFormat("Text size: [{d:.2}, {d:.2}]", .{ text_size.x, text_size.y }), 20, screen_height - 30, 10, .dark_gray);
        rl.drawText("CURRENT TEXTURE FILTER:", 250, 400, 20, .gray);

        const filter_name = switch (current_font_filter) {
            .point => "POINT",
            .bilinear => "BILINEAR",
            .trilinear => "TRILINEAR",
            else => unreachable,
        };
        rl.drawText(filter_name, 570, 400, 20, .black);
    }
}
