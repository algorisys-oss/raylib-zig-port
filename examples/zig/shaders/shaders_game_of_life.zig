//! raylib [shaders] example - game of life
//!
//! Zig-API translation of examples/shaders/shaders_game_of_life.c (raylib 6.2).
//! NOTE: This example requires raylib OpenGL 3.3 or ES2 versions for shaders support,
//!       OpenGL 1.1 does not support shaders, recompile raylib to OpenGL 3.3 version
//! Example contributed by Jordi Santonja (@JordSant) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jordi Santonja (@JordSant)

const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

/// Interaction mode
const InteractionMode = enum(i32) { run = 0, pause, draw };

/// Example preset pattern
const PresetPattern = struct {
    name: [:0]const u8,
    position: rl.Vector2,
    /// Pattern image to load; null fills the world with random cells
    image: ?[:0]const u8,
};

const preset_patterns = [_]PresetPattern{
    .{ .name = "Glider", .position = .{ .x = 0.5, .y = 0.5 }, .image = "resources/game_of_life/glider.png" },
    .{ .name = "R-pentomino", .position = .{ .x = 0.5, .y = 0.5 }, .image = "resources/game_of_life/r_pentomino.png" },
    .{ .name = "Acorn", .position = .{ .x = 0.5, .y = 0.5 }, .image = "resources/game_of_life/acorn.png" },
    .{ .name = "Spaceships", .position = .{ .x = 0.1, .y = 0.5 }, .image = "resources/game_of_life/spaceships.png" },
    .{ .name = "Still lifes", .position = .{ .x = 0.5, .y = 0.5 }, .image = "resources/game_of_life/still_lifes.png" },
    .{ .name = "Oscillators", .position = .{ .x = 0.5, .y = 0.5 }, .image = "resources/game_of_life/oscillators.png" },
    .{ .name = "Puffer train", .position = .{ .x = 0.1, .y = 0.5 }, .image = "resources/game_of_life/puffer_train.png" },
    .{ .name = "Glider Gun", .position = .{ .x = 0.2, .y = 0.2 }, .image = "resources/game_of_life/glider_gun.png" },
    .{ .name = "Breeder", .position = .{ .x = 0.1, .y = 0.5 }, .image = "resources/game_of_life/breeder.png" },
    .{ .name = "Random", .position = .{ .x = 0.5, .y = 0.5 }, .image = null },
};

const screen_width = 800;
const screen_height = 450;

const menu_width = 100;
const window_width = screen_width - menu_width;
const window_height = screen_height;

const world_width = 2048;
const world_height = 2048;

const random_tiles = 8; // Random preset: divide the world to compute random points in each tile

/// Load `preset` into `world`: its pattern image at the preset position, or random cells.
fn loadPreset(world: rl.RenderTexture2D, preset: PresetPattern) !void {
    if (preset.image) |file_name| { // Preset with pattern image to load
        const pattern = try rl.loadImage(file_name);
        defer rl.unloadImage(pattern);

        rl.beginTextureMode(world);
        rl.clearBackground(.ray_white);
        rl.endTextureMode();

        const width: f32 = @floatFromInt(pattern.width);
        const height: f32 = @floatFromInt(pattern.height);
        rl.updateTextureRec(world.texture, .{
            .x = world_width * preset.position.x - width / 2.0,
            .y = world_height * preset.position.y - height / 2.0,
            .width = width,
            .height = height,
        }, pattern.data.?);
    } else { // Last preset: Random values
        var pattern = rl.genImageColor(world_width / random_tiles, world_height / random_tiles, .ray_white);
        defer rl.unloadImage(pattern);

        for (0..random_tiles) |i| {
            for (0..random_tiles) |j| {
                rl.imageClearBackground(&pattern, .ray_white);
                for (0..@intCast(pattern.width)) |x| {
                    for (0..@intCast(pattern.height)) |y| {
                        if (rl.getRandomValue(0, 100) < 15) rl.imageDrawPixel(&pattern, @intCast(x), @intCast(y), .black);
                    }
                }
                const width: f32 = @floatFromInt(pattern.width);
                const height: f32 = @floatFromInt(pattern.height);
                rl.updateTextureRec(world.texture, .{
                    .x = @floatFromInt(pattern.width * @as(i32, @intCast(i))),
                    .y = @floatFromInt(pattern.height * @as(i32, @intCast(j))),
                    .width = width,
                    .height = height,
                }, pattern.data.?);
            }
        }
    }
}

pub fn main() !void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - game of life");
    defer rl.closeWindow(); // Close window and OpenGL context

    const world_rect_source: rl.Rectangle = .{ .x = 0, .y = 0, .width = world_width, .height = -world_height };
    const world_rect_dest: rl.Rectangle = .{ .x = 0, .y = 0, .width = world_width, .height = world_height };
    const texture_on_screen: rl.Rectangle = .{ .x = 0, .y = 0, .width = window_width, .height = window_height };

    var zoom: i32 = 1;
    var offset_x: f32 = (world_width - window_width) / 2.0; // Centered on window
    var offset_y: f32 = (world_height - window_height) / 2.0; // Centered on window
    var frames_per_step: i32 = 1;
    var frame: i32 = 0;

    var preset: ?PresetPattern = null; // No button pressed for preset
    var mode: InteractionMode = .run; // Starting mode: running
    var button_zoom_in = false; // Button states: false not pressed
    var button_zoom_out = false;
    var button_faster = false;
    var button_slower = false;

    // Load shader
    const shdr_game_of_life = try rl.loadShader(null, rl.textFormat("resources/shaders/glsl{d}/game_of_life.fs", .{glsl_version}));
    defer rl.unloadShader(shdr_game_of_life);

    // Set shader uniform size of the world
    const resolution_loc = rl.getShaderLocation(shdr_game_of_life, "resolution");
    const resolution = [2]f32{ world_width, world_height };
    rl.setShaderValue(shdr_game_of_life, resolution_loc, resolution);

    // Define two textures: the current world and the previous world
    var world1 = try rl.loadRenderTexture(world_width, world_height);
    defer rl.unloadRenderTexture(world1);
    var world2 = try rl.loadRenderTexture(world_width, world_height);
    defer rl.unloadRenderTexture(world2);
    rl.beginTextureMode(world2);
    rl.clearBackground(.ray_white);
    rl.endTextureMode();

    {
        const start_pattern = try rl.loadImage("resources/game_of_life/r_pentomino.png");
        defer rl.unloadImage(start_pattern);
        rl.updateTextureRec(world2.texture, .{
            .x = world_width / 2.0,
            .y = world_height / 2.0,
            .width = @floatFromInt(start_pattern.width),
            .height = @floatFromInt(start_pattern.height),
        }, start_pattern.data.?);
    }

    // Pointers to the two textures, to be swapped
    var current_world = &world2;
    var previous_world = &world1;

    // Image to be used in DRAW mode, to be changed with mouse input
    var image_to_draw: ?rl.Image = null;
    defer if (image_to_draw) |image| rl.unloadImage(image);

    // Mouse state carried between frames
    var previous_mouse_position: rl.Vector2 = .{ .x = 0.0, .y = 0.0 };
    var first_color: ?bool = null; // Color of the first cell painted in the current stroke

    rl.setTargetFPS(60); // Set at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        frame += 1;

        const zoom_f: f32 = @floatFromInt(zoom);

        // Change zoom: both by buttons or by mouse wheel
        const mouse_wheel_move = rl.getMouseWheelMove();
        if (button_zoom_in or (button_zoom_out and zoom > 1) or mouse_wheel_move != 0.0) {
            // Zoom change: free the image to draw to be recreated again
            if (image_to_draw) |image| rl.unloadImage(image);
            image_to_draw = null;

            const center_x = offset_x + (window_width / 2.0) / zoom_f;
            const center_y = offset_y + (window_height / 2.0) / zoom_f;
            if (button_zoom_in or mouse_wheel_move > 0.0) zoom *= 2;
            if ((button_zoom_out or mouse_wheel_move < 0.0) and zoom > 1) zoom = @divTrunc(zoom, 2);
            offset_x = center_x - (window_width / 2.0) / @as(f32, @floatFromInt(zoom));
            offset_y = center_y - (window_height / 2.0) / @as(f32, @floatFromInt(zoom));
        }

        // Change speed: number of frames per step
        if (button_faster and frames_per_step > 1) frames_per_step -= 1;
        if (button_slower) frames_per_step += 1;

        const zoom_now: f32 = @floatFromInt(zoom);

        // Mouse management
        switch (mode) {
            .run, .pause => {
                // Free the image to draw: no longer needed in these modes
                if (image_to_draw) |image| rl.unloadImage(image);
                image_to_draw = null;

                // Pan with mouse left button
                const mouse_position = rl.getMousePosition();
                if (rl.isMouseButtonDown(.left) and mouse_position.x < window_width) {
                    offset_x -= (mouse_position.x - previous_mouse_position.x) / zoom_now;
                    offset_y -= (mouse_position.y - previous_mouse_position.y) / zoom_now;
                }
                previous_mouse_position = mouse_position;
            },
            .draw => {
                const offset_decimal_x = offset_x - @floor(offset_x);
                const offset_decimal_y = offset_y - @floor(offset_y);
                var size_in_world_x: i32 = @intFromFloat(@ceil((window_width + offset_decimal_x * zoom_now) / zoom_now));
                var size_in_world_y: i32 = @intFromFloat(@ceil((window_height + offset_decimal_y * zoom_now) / zoom_now));
                if (offset_x + @as(f32, @floatFromInt(size_in_world_x)) >= world_width) size_in_world_x = world_width - @as(i32, @intFromFloat(@floor(offset_x)));
                if (offset_y + @as(f32, @floatFromInt(size_in_world_y)) >= world_height) size_in_world_y = world_height - @as(i32, @intFromFloat(@floor(offset_y)));
                const size_x: f32 = @floatFromInt(size_in_world_x);
                const size_y: f32 = @floatFromInt(size_in_world_y);

                // Create image to draw if not created yet
                const image = if (image_to_draw) |*image| image else blk: {
                    const world_on_screen = try rl.loadRenderTexture(size_in_world_x, size_in_world_y);
                    defer rl.unloadRenderTexture(world_on_screen);

                    rl.beginTextureMode(world_on_screen);
                    rl.drawTexturePro(current_world.texture, .{ .x = @floor(offset_x), .y = @floor(offset_y), .width = size_x, .height = -size_y }, .{ .x = 0, .y = 0, .width = size_x, .height = size_y }, .{ .x = 0, .y = 0 }, 0.0, .white);
                    rl.endTextureMode();

                    image_to_draw = try rl.loadImageFromTexture(world_on_screen.texture);
                    break :blk &image_to_draw.?;
                };

                const mouse_position = rl.getMousePosition();
                if (rl.isMouseButtonDown(.left) and mouse_position.x < window_width) {
                    var mouse_x = @divTrunc(@as(i32, @intFromFloat(mouse_position.x + offset_decimal_x * zoom_now)), zoom);
                    var mouse_y = @divTrunc(@as(i32, @intFromFloat(mouse_position.y + offset_decimal_y * zoom_now)), zoom);
                    if (mouse_x >= size_in_world_x) mouse_x = size_in_world_x - 1;
                    if (mouse_y >= size_in_world_y) mouse_y = size_in_world_y - 1;
                    const prev_color = rl.getImageColor(image.*, mouse_x, mouse_y).r >= 5;
                    const color = first_color orelse prev_color;
                    first_color = color;

                    rl.imageDrawPixel(image, mouse_x, mouse_y, if (color) .black else .ray_white);

                    if (prev_color != color) rl.updateTextureRec(current_world.texture, .{ .x = @floor(offset_x), .y = @floor(offset_y), .width = size_x, .height = size_y }, image.data.?);
                } else first_color = null;
            },
        }

        // Load selected preset
        if (preset) |selected| {
            try loadPreset(current_world.*, selected);

            mode = .pause;
            offset_x = world_width * selected.position.x - window_width / zoom_now / 2.0;
            offset_y = world_height * selected.position.y - window_height / zoom_now / 2.0;
        }

        // Check window draw inside world limits
        if (offset_x < 0) offset_x = 0;
        if (offset_y < 0) offset_y = 0;
        if (offset_x > world_width - window_width / zoom_now) offset_x = world_width - window_width / zoom_now;
        if (offset_y > world_height - window_height / zoom_now) offset_y = world_height - window_height / zoom_now;

        // Rectangles for drawing texture portion to screen
        const texture_source_to_screen: rl.Rectangle = .{ .x = offset_x, .y = offset_y, .width = window_width / zoom_now, .height = window_height / zoom_now };

        // Draw to texture
        if (mode == .run and @rem(frame, frames_per_step) == 0) {
            // Swap worlds
            std.mem.swap(*rl.RenderTexture2D, &current_world, &previous_world);

            // Draw to texture
            rl.beginTextureMode(current_world.*);
            rl.beginShaderMode(shdr_game_of_life);
            rl.drawTexturePro(previous_world.texture, world_rect_source, world_rect_dest, .{ .x = 0, .y = 0 }, 0.0, .ray_white);
            rl.endShaderMode();
            rl.endTextureMode();
        }

        // Draw to screen
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.drawTexturePro(current_world.texture, texture_source_to_screen, texture_on_screen, .{ .x = 0, .y = 0 }, 0.0, .white);

        rl.drawLine(window_width, 0, window_width, screen_height, .{ .r = 218, .g = 218, .b = 218, .a = 255 });
        rl.drawRectangle(window_width, 0, screen_width - window_width, screen_height, .{ .r = 232, .g = 232, .b = 232, .a = 255 });

        rl.drawText("Conway's", 704, 4, 20, .dark_blue);
        rl.drawText(" game of", 704, 19, 20, .dark_blue);
        rl.drawText("  life", 708, 34, 20, .dark_blue);
        rl.drawText("in raylib", 757, 42, 6, .black);

        rl.drawText("Presets", 710, 58, 8, .gray);
        preset = null;
        for (preset_patterns, 0..) |pattern, i| {
            const y = 70.0 + @as(f32, @floatFromInt(18 * i));
            if (gui.button(.{ .x = 710.0, .y = y, .width = 80.0, .height = 16.0 }, pattern.name) != 0) preset = pattern;
        }

        var mode_index: i32 = @backingInt(mode);
        _ = gui.toggleGroup(.{ .x = 710, .y = 258, .width = 80, .height = 16 }, "Run\nPause\nDraw", &mode_index);
        mode = @fromBackingInt(@intCast(mode_index));

        rl.drawText(rl.textFormat("Zoom: {d}x", .{zoom}), 710, 316, 8, .gray);
        button_zoom_in = gui.button(.{ .x = 710, .y = 328, .width = 80, .height = 16 }, "Zoom in") != 0;
        button_zoom_out = gui.button(.{ .x = 710, .y = 346, .width = 80, .height = 16 }, "Zoom out") != 0;

        rl.drawText(rl.textFormat("Speed: {d} frame{s}", .{ frames_per_step, if (frames_per_step > 1) "s" else "" }), 710, 370, 8, .gray);
        button_faster = gui.button(.{ .x = 710, .y = 382, .width = 80, .height = 16 }, "Faster") != 0;
        button_slower = gui.button(.{ .x = 710, .y = 400, .width = 80, .height = 16 }, "Slower") != 0;

        rl.drawFPS(712, 426);
    }
}
