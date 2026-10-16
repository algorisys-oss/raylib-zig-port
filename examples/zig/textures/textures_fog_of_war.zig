//! raylib [textures] example - fog of war
//!
//! Zig-API translation of examples/textures/textures_fog_of_war.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2018-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const map_tile_size = 32; // Tiles size 32x32 pixels
const player_size = 16; // Player size
const player_tile_visibility = 2; // Player can see 2 tiles around its position

const tiles_x = 25; // Number of tiles in X axis
const tiles_y = 15; // Number of tiles in Y axis

/// Tile fog state
const Fog = enum(u8) { full, visible, partial };

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - fog of war");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Tile ids define the type of tile to draw; tile fog defines if a tile has fog or half-fog
    var tile_ids: [tiles_y][tiles_x]u8 = undefined;
    var tile_fog: [tiles_y][tiles_x]Fog = @splat(@splat(.full));

    // Load map tiles (generating 2 random tile ids for testing)
    // NOTE: Map tile ids should be probably loaded from an external map file
    for (&tile_ids) |*row| {
        for (row) |*id| id.* = @intCast(rl.getRandomValue(0, 1));
    }

    // Player position on the screen (pixel coordinates, not tile coordinates)
    var player_position: rl.Vector2 = .{ .x = 180, .y = 130 };
    var player_tile_x: i32 = 0;
    var player_tile_y: i32 = 0;

    // Render texture to render fog of war
    // NOTE: To get an automatic smooth-fog effect we use a render texture to render fog
    // at a smaller size (one pixel per tile) and scale it on drawing with bilinear filtering
    const fog_of_war = try rl.loadRenderTexture(tiles_x, tiles_y);
    defer rl.unloadRenderTexture(fog_of_war);
    rl.setTextureFilter(fog_of_war.texture, .bilinear);
    rl.setTextureWrap(fog_of_war.texture, .clamp);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Move player around
        if (rl.isKeyDown(.right)) player_position.x += 5;
        if (rl.isKeyDown(.left)) player_position.x -= 5;
        if (rl.isKeyDown(.down)) player_position.y += 5;
        if (rl.isKeyDown(.up)) player_position.y -= 5;

        // Check player position to avoid moving outside tilemap limits
        if (player_position.x < 0) {
            player_position.x = 0;
        } else if ((player_position.x + player_size) > (tiles_x * map_tile_size)) {
            player_position.x = tiles_x * map_tile_size - player_size;
        }
        if (player_position.y < 0) {
            player_position.y = 0;
        } else if ((player_position.y + player_size) > (tiles_y * map_tile_size)) {
            player_position.y = tiles_y * map_tile_size - player_size;
        }

        // Previous visited tiles are set to partial fog
        for (&tile_fog) |*row| {
            for (row) |*fog| {
                if (fog.* == .visible) fog.* = .partial;
            }
        }

        // Get current tile position from player pixel position
        player_tile_x = @intFromFloat((player_position.x + @as(f32, map_tile_size) / 2) / map_tile_size);
        player_tile_y = @intFromFloat((player_position.y + @as(f32, map_tile_size) / 2) / map_tile_size);

        // Check visibility and update fog
        // NOTE: We check tilemap limits to avoid processing tiles out-of-array-bounds (it could crash program)
        var y = player_tile_y - player_tile_visibility;
        while (y < player_tile_y + player_tile_visibility) : (y += 1) {
            var x = player_tile_x - player_tile_visibility;
            while (x < player_tile_x + player_tile_visibility) : (x += 1) {
                if ((x >= 0) and (x < tiles_x) and (y >= 0) and (y < tiles_y)) {
                    tile_fog[@intCast(y)][@intCast(x)] = .visible;
                }
            }
        }

        // Draw
        // Draw fog of war to a small render texture for automatic smoothing on scaling
        rl.beginTextureMode(fog_of_war);
        rl.clearBackground(.blank);
        for (tile_fog, 0..) |row, ty| {
            for (row, 0..) |fog, tx| {
                const px: i32 = @intCast(tx);
                const py: i32 = @intCast(ty);
                switch (fog) {
                    .full => rl.drawRectangle(px, py, 1, 1, .black),
                    .partial => rl.drawRectangle(px, py, 1, 1, rl.fade(.black, 0.8)),
                    .visible => {},
                }
            }
        }
        rl.endTextureMode();

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        for (tile_ids, 0..) |row, ty| {
            for (row, 0..) |id, tx| {
                const px: i32 = @intCast(tx * map_tile_size);
                const py: i32 = @intCast(ty * map_tile_size);
                // Draw tiles from id (and tile borders)
                rl.drawRectangle(px, py, map_tile_size, map_tile_size, if (id == 0) .blue else rl.fade(.blue, 0.9));
                rl.drawRectangleLines(px, py, map_tile_size, map_tile_size, rl.fade(.dark_blue, 0.5));
            }
        }

        // Draw player
        rl.drawRectangleV(player_position, .{ .x = player_size, .y = player_size }, .red);

        // Draw fog of war (scaled to full map, bilinear filtering)
        rl.drawTexturePro(
            fog_of_war.texture,
            .{ .x = 0, .y = 0, .width = @floatFromInt(fog_of_war.texture.width), .height = @floatFromInt(-fog_of_war.texture.height) },
            .{ .x = 0, .y = 0, .width = tiles_x * map_tile_size, .height = tiles_y * map_tile_size },
            .{ .x = 0, .y = 0 },
            0.0,
            .white,
        );

        // Draw player current tile
        rl.drawText(rl.textFormat("Current tile: [{d},{d}]", .{ player_tile_x, player_tile_y }), 10, 10, 20, .ray_white);
        rl.drawText("ARROW KEYS to move", 10, screen_height - 25, 20, .ray_white);
    }
}
