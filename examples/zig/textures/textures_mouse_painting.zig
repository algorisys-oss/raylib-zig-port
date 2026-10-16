//! raylib [textures] example - mouse painting
//!
//! Zig-API translation of examples/textures/textures_mouse_painting.c (raylib 6.2).
//! Example contributed by Chris Dill (@MysteriousSpace) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Chris Dill (@MysteriousSpace) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

// Colors to choose from
const colors = [_]rl.Color{
    .ray_white, .yellow,     .gold,       .orange,     .pink,      .red,       .maroon, .green,
    .lime,      .dark_green, .sky_blue,   .blue,       .dark_blue, .purple,    .violet, .dark_purple,
    .beige,     .brown,      .dark_brown, .light_gray, .gray,      .dark_gray, .black,
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - mouse painting");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define colors_recs data (for every rectangle)
    var colors_recs: [colors.len]rl.Rectangle = undefined;
    for (&colors_recs, 0..) |*rec, i| {
        rec.* = .{
            .x = 10 + 30.0 * @as(f32, @floatFromInt(i)) + @as(f32, @floatFromInt(2 * i)),
            .y = 10,
            .width = 30,
            .height = 30,
        };
    }

    var color_selected: usize = 0;
    var color_selected_prev = color_selected;
    var brush_size: f32 = 20.0;
    var mouse_was_pressed = false;

    const btn_save_rec: rl.Rectangle = .{ .x = 750, .y = 10, .width = 40, .height = 30 };
    var show_save_message = false;
    var save_message_counter: i32 = 0;

    // Create a RenderTexture2D to use as a canvas
    const target = try rl.loadRenderTexture(screen_width, screen_height);
    defer rl.unloadRenderTexture(target); // Unload render texture

    // Clear render texture before entering the game loop
    rl.beginTextureMode(target);
    rl.clearBackground(colors[0]);
    rl.endTextureMode();

    rl.setTargetFPS(120); // Set our game to run at 120 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_pos = rl.getMousePosition();

        // Move between colors with keys
        if (rl.isKeyPressed(.right)) {
            color_selected = @min(color_selected + 1, colors.len - 1);
        } else if (rl.isKeyPressed(.left)) {
            color_selected -|= 1;
        }

        // Choose color with mouse
        const color_mouse_hover: ?usize = for (colors_recs, 0..) |rec, i| {
            if (rl.checkCollisionPointRec(mouse_pos, rec)) break i;
        } else null;

        if (color_mouse_hover) |hover| {
            if (rl.isMouseButtonPressed(.left)) {
                color_selected = hover;
                color_selected_prev = color_selected;
            }
        }

        // Change brush size
        brush_size += rl.getMouseWheelMove() * 5;
        if (brush_size < 2) brush_size = 2;
        if (brush_size > 50) brush_size = 50;

        if (rl.isKeyPressed(.c)) {
            // Clear render texture to clear color
            rl.beginTextureMode(target);
            rl.clearBackground(colors[0]);
            rl.endTextureMode();
        }

        if (rl.isMouseButtonDown(.left) or rl.isGestureDetected(.drag)) {
            // Paint circle into render texture
            // NOTE: To avoid discontinuous circles, we could store
            // previous-next mouse points and just draw a line using brush size
            rl.beginTextureMode(target);
            if (mouse_pos.y > 50) rl.drawCircle(@intFromFloat(mouse_pos.x), @intFromFloat(mouse_pos.y), brush_size, colors[color_selected]);
            rl.endTextureMode();
        }

        if (rl.isMouseButtonDown(.right)) {
            if (!mouse_was_pressed) {
                color_selected_prev = color_selected;
                color_selected = 0;
            }

            mouse_was_pressed = true;

            // Erase circle from render texture
            rl.beginTextureMode(target);
            if (mouse_pos.y > 50) rl.drawCircle(@intFromFloat(mouse_pos.x), @intFromFloat(mouse_pos.y), brush_size, colors[0]);
            rl.endTextureMode();
        } else if (rl.isMouseButtonReleased(.right) and mouse_was_pressed) {
            color_selected = color_selected_prev;
            mouse_was_pressed = false;
        }

        // Check mouse hover save button
        const btn_save_mouse_hover = rl.checkCollisionPointRec(mouse_pos, btn_save_rec);

        // Image saving logic
        // NOTE: Saving painted texture to a default named image
        if ((btn_save_mouse_hover and rl.isMouseButtonReleased(.left)) or rl.isKeyPressed(.s)) {
            var image = try rl.loadImageFromTexture(target.texture);
            defer rl.unloadImage(image);
            rl.imageFlipVertical(&image);
            _ = rl.exportImage(image, "my_amazing_texture_painting.png");
            show_save_message = true;
        }

        if (show_save_message) {
            // On saving, show a full screen message for 2 seconds
            save_message_counter += 1;
            if (save_message_counter > 240) {
                show_save_message = false;
                save_message_counter = 0;
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // NOTE: Render texture must be y-flipped due to default OpenGL coordinates (left-bottom)
        rl.drawTextureRec(target.texture, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(target.texture.width),
            .height = @floatFromInt(-target.texture.height),
        }, .{ .x = 0, .y = 0 }, .white);

        // Draw drawing circle for reference
        if (mouse_pos.y > 50) {
            if (rl.isMouseButtonDown(.right)) {
                rl.drawCircleLines(@intFromFloat(mouse_pos.x), @intFromFloat(mouse_pos.y), brush_size, .gray);
            } else {
                rl.drawCircle(rl.getMouseX(), rl.getMouseY(), brush_size, colors[color_selected]);
            }
        }

        // Draw top panel
        rl.drawRectangle(0, 0, rl.getScreenWidth(), 50, .ray_white);
        rl.drawLine(0, 50, rl.getScreenWidth(), 50, .light_gray);

        // Draw color selection rectangles
        for (colors_recs, colors) |rec, color| rl.drawRectangleRec(rec, color);
        rl.drawRectangleLines(10, 10, 30, 30, .light_gray);

        if (color_mouse_hover) |hover| rl.drawRectangleRec(colors_recs[hover], rl.fade(.white, 0.6));

        const selected = colors_recs[color_selected];
        rl.drawRectangleLinesEx(.{
            .x = selected.x - 2,
            .y = selected.y - 2,
            .width = selected.width + 4,
            .height = selected.height + 4,
        }, 2, .black);

        // Draw save image button
        rl.drawRectangleLinesEx(btn_save_rec, 2, if (btn_save_mouse_hover) .red else .black);
        rl.drawText("SAVE!", 755, 20, 10, if (btn_save_mouse_hover) .red else .black);

        // Draw save image message
        if (show_save_message) {
            rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), rl.fade(.ray_white, 0.8));
            rl.drawRectangle(0, 150, rl.getScreenWidth(), 80, .black);
            rl.drawText("IMAGE SAVED!", 150, 180, 20, .ray_white);
        }
    }
}
