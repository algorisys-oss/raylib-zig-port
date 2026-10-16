//! raylib [textures] example - tiled drawing
//!
//! Zig-API translation of examples/textures/textures_tiled_drawing.c (raylib 6.2).
//! Example contributed by Vlad Adrian (@demizdor) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2020-2025 Vlad Adrian (@demizdor) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const opt_width = 220; // Max width for the options container
const margin_size = 8; // Size for the margins
const color_size = 16; // Size of the color select buttons

// Coordinates for all patterns inside the texture
const rec_pattern = [_]rl.Rectangle{
    .{ .x = 3, .y = 3, .width = 66, .height = 66 },
    .{ .x = 75, .y = 3, .width = 100, .height = 100 },
    .{ .x = 3, .y = 75, .width = 66, .height = 66 },
    .{ .x = 7, .y = 156, .width = 50, .height = 50 },
    .{ .x = 85, .y = 106, .width = 90, .height = 45 },
    .{ .x = 75, .y = 154, .width = 100, .height = 60 },
};

// Setup colors
const colors = [_]rl.Color{ .black, .maroon, .orange, .blue, .purple, .beige, .lime, .red, .dark_gray, .sky_blue };

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .window_resizable = true }); // Make the window resizable
    rl.initWindow(screen_width, screen_height, "raylib [textures] example - tiled drawing");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)
    const tex_pattern = try rl.loadTexture("resources/patterns.png");
    defer rl.unloadTexture(tex_pattern); // Unload texture
    rl.setTextureFilter(tex_pattern, .bilinear); // Makes the texture smoother when upscaled

    // Calculate rectangle for each color: two rows of buttons
    var color_rec: [colors.len]rl.Rectangle = undefined;
    for (&color_rec, 0..) |*rec, i| {
        const column: i32 = @intCast(i % (colors.len / 2));
        const row: i32 = @intCast(i / (colors.len / 2));
        const x = column * (color_size * 2 + margin_size);
        const y = row * (color_size + margin_size);
        rec.* = .{
            .x = 2.0 + margin_size + @as(f32, @floatFromInt(x)),
            .y = 22.0 + 256.0 + margin_size + @as(f32, @floatFromInt(y)),
            .width = color_size * 2.0,
            .height = color_size,
        };
    }

    var active_pattern: usize = 0;
    var active_col: usize = 0;
    var scale: f32 = 1.0;
    var rotation: f32 = 0.0;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Handle mouse
        if (rl.isMouseButtonPressed(.left)) {
            const mouse = rl.getMousePosition();

            // Check which pattern was clicked and set it as the active pattern
            for (rec_pattern, 0..) |pattern, i| {
                if (rl.checkCollisionPointRec(mouse, .{
                    .x = 2 + margin_size + pattern.x,
                    .y = 40 + margin_size + pattern.y,
                    .width = pattern.width,
                    .height = pattern.height,
                })) {
                    active_pattern = i;
                    break;
                }
            }

            // Check to see which color was clicked and set it as the active color
            for (color_rec, 0..) |rec, i| {
                if (rl.checkCollisionPointRec(mouse, rec)) {
                    active_col = i;
                    break;
                }
            }
        }

        // Handle keys: change scale
        if (rl.isKeyPressed(.up)) scale += 0.25;
        if (rl.isKeyPressed(.down)) scale -= 0.25;
        if (scale > 10.0) {
            scale = 10.0;
        } else if (scale <= 0.0) {
            scale = 0.25;
        }

        // Handle keys: change rotation
        if (rl.isKeyPressed(.left)) rotation -= 25.0;
        if (rl.isKeyPressed(.right)) rotation += 25.0;

        // Handle keys: reset
        if (rl.isKeyPressed(.space)) {
            rotation = 0.0;
            scale = 1.0;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw the tiled area
        drawTextureTiled(tex_pattern, rec_pattern[active_pattern], .{
            .x = opt_width + margin_size,
            .y = margin_size,
            .width = @as(f32, @floatFromInt(rl.getScreenWidth() - opt_width)) - 2.0 * margin_size,
            .height = @as(f32, @floatFromInt(rl.getScreenHeight())) - 2.0 * margin_size,
        }, .{ .x = 0.0, .y = 0.0 }, rotation, scale, colors[active_col]);

        // Draw options
        rl.drawRectangle(margin_size, margin_size, opt_width - margin_size, rl.getScreenHeight() - 2 * margin_size, rl.colorAlpha(.light_gray, 0.5));

        rl.drawText("Select Pattern", 2 + margin_size, 30 + margin_size, 10, .black);
        rl.drawTexture(tex_pattern, 2 + margin_size, 40 + margin_size, .black);
        const pattern = rec_pattern[active_pattern];
        rl.drawRectangle(
            2 + margin_size + @as(i32, @intFromFloat(pattern.x)),
            40 + margin_size + @as(i32, @intFromFloat(pattern.y)),
            @intFromFloat(pattern.width),
            @intFromFloat(pattern.height),
            rl.colorAlpha(.dark_blue, 0.3),
        );

        rl.drawText("Select Color", 2 + margin_size, 10 + 256 + margin_size, 10, .black);
        for (color_rec, colors, 0..) |rec, color, i| {
            rl.drawRectangleRec(rec, color);
            if (active_col == i) rl.drawRectangleLinesEx(rec, 3, rl.colorAlpha(.white, 0.5));
        }

        rl.drawText("Scale (UP/DOWN to change)", 2 + margin_size, 80 + 256 + margin_size, 10, .black);
        rl.drawText(rl.textFormat("{d:.2}x", .{scale}), 2 + margin_size, 92 + 256 + margin_size, 20, .black);

        rl.drawText("Rotation (LEFT/RIGHT to change)", 2 + margin_size, 122 + 256 + margin_size, 10, .black);
        rl.drawText(rl.textFormat("{d:.0} degrees", .{rotation}), 2 + margin_size, 134 + 256 + margin_size, 20, .black);

        rl.drawText("Press [SPACE] to reset", 2 + margin_size, 164 + 256 + margin_size, 10, .dark_blue);

        // Draw FPS
        rl.drawText(rl.textFormat("{d} FPS", .{rl.getFPS()}), 2 + margin_size, 2 + margin_size, 20, .black);
    }
}

/// Draw part of a texture (defined by a rectangle) with rotation and scale tiled into dest
fn drawTextureTiled(texture: rl.Texture2D, source: rl.Rectangle, dest: rl.Rectangle, origin: rl.Vector2, rotation: f32, scale: f32, tint: rl.Color) void {
    if ((texture.id == 0) or (scale <= 0.0)) return; // Wanna see a infinite loop?!...just delete this line!
    if ((source.width == 0) or (source.height == 0)) return;

    const tile_width: i32 = @intFromFloat(source.width * scale);
    const tile_height: i32 = @intFromFloat(source.height * scale);
    const tile_w: f32 = @floatFromInt(tile_width);
    const tile_h: f32 = @floatFromInt(tile_height);

    const Tile = struct {
        texture: rl.Texture2D,
        source: rl.Rectangle,
        origin: rl.Vector2,
        rotation: f32,
        tint: rl.Color,

        /// Draw the source part scaled by (sx, sy) into `rec`
        fn draw(t: @This(), sx: f32, sy: f32, rec: rl.Rectangle) void {
            rl.drawTexturePro(t.texture, .{
                .x = t.source.x,
                .y = t.source.y,
                .width = sx * t.source.width,
                .height = sy * t.source.height,
            }, rec, t.origin, t.rotation, t.tint);
        }
    };
    const tile: Tile = .{ .texture = texture, .source = source, .origin = origin, .rotation = rotation, .tint = tint };

    if ((dest.width < tile_w) and (dest.height < tile_h)) {
        // Can fit only one tile
        tile.draw(dest.width / tile_w, dest.height / tile_h, .{ .x = dest.x, .y = dest.y, .width = dest.width, .height = dest.height });
    } else if (dest.width <= tile_w) {
        // Tiled vertically (one column)
        var dy: i32 = 0;
        while (@as(f32, @floatFromInt(dy + tile_height)) < dest.height) : (dy += tile_height) {
            const fdy: f32 = @floatFromInt(dy);
            tile.draw(dest.width / tile_w, 1, .{ .x = dest.x, .y = dest.y + fdy, .width = dest.width, .height = tile_h });
        }

        // Fit last tile
        const fdy: f32 = @floatFromInt(dy);
        if (fdy < dest.height) {
            tile.draw(dest.width / tile_w, (dest.height - fdy) / tile_h, .{ .x = dest.x, .y = dest.y + fdy, .width = dest.width, .height = dest.height - fdy });
        }
    } else if (dest.height <= tile_h) {
        // Tiled horizontally (one row)
        var dx: i32 = 0;
        while (@as(f32, @floatFromInt(dx + tile_width)) < dest.width) : (dx += tile_width) {
            const fdx: f32 = @floatFromInt(dx);
            tile.draw(1, dest.height / tile_h, .{ .x = dest.x + fdx, .y = dest.y, .width = tile_w, .height = dest.height });
        }

        // Fit last tile
        const fdx: f32 = @floatFromInt(dx);
        if (fdx < dest.width) {
            tile.draw((dest.width - fdx) / tile_w, dest.height / tile_h, .{ .x = dest.x + fdx, .y = dest.y, .width = dest.width - fdx, .height = dest.height });
        }
    } else {
        // Tiled both horizontally and vertically (rows and columns)
        var dx: i32 = 0;
        while (@as(f32, @floatFromInt(dx + tile_width)) < dest.width) : (dx += tile_width) {
            const fdx: f32 = @floatFromInt(dx);
            var dy: i32 = 0;
            while (@as(f32, @floatFromInt(dy + tile_height)) < dest.height) : (dy += tile_height) {
                const fdy: f32 = @floatFromInt(dy);
                rl.drawTexturePro(texture, source, .{ .x = dest.x + fdx, .y = dest.y + fdy, .width = tile_w, .height = tile_h }, origin, rotation, tint);
            }

            const fdy: f32 = @floatFromInt(dy);
            if (fdy < dest.height) {
                tile.draw(1, (dest.height - fdy) / tile_h, .{ .x = dest.x + fdx, .y = dest.y + fdy, .width = tile_w, .height = dest.height - fdy });
            }
        }

        // Fit last column of tiles
        const fdx: f32 = @floatFromInt(dx);
        if (fdx < dest.width) {
            var dy: i32 = 0;
            while (@as(f32, @floatFromInt(dy + tile_height)) < dest.height) : (dy += tile_height) {
                const fdy: f32 = @floatFromInt(dy);
                tile.draw((dest.width - fdx) / tile_w, 1, .{ .x = dest.x + fdx, .y = dest.y + fdy, .width = dest.width - fdx, .height = tile_h });
            }

            // Draw final tile in the bottom right corner
            const fdy: f32 = @floatFromInt(dy);
            if (fdy < dest.height) {
                tile.draw((dest.width - fdx) / tile_w, (dest.height - fdy) / tile_h, .{ .x = dest.x + fdx, .y = dest.y + fdy, .width = dest.width - fdx, .height = dest.height - fdy });
            }
        }
    }
}
