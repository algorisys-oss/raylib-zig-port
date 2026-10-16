//! raylib [models] example - first person maze
//!
//! Zig-API translation of examples/models/models_first_person_maze.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - first person maze");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 0.2, .y = 0.4, .z = 0.2 }, // Camera position
        .target = .{ .x = 0.185, .y = 0.4, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const im_map = try rl.loadImage("resources/cubicmap.png"); // Load cubicmap image (RAM)
    const cubicmap = try rl.loadTextureFromImage(im_map); // Convert image to texture to display (VRAM)
    defer rl.unloadTexture(cubicmap);
    const mesh = rl.genMeshCubicmap(im_map, .{ .x = 1.0, .y = 1.0, .z = 1.0 });
    const model = try rl.loadModelFromMesh(mesh);
    defer rl.unloadModel(model);

    // NOTE: By default each cube is mapped to one part of texture atlas
    const texture = try rl.loadTexture("resources/cubicmap_atlas.png"); // Load map texture
    defer rl.unloadTexture(texture);
    model.materials.?[0].map(.diffuse).texture = texture; // Set map diffuse texture

    // Get map image data to be used for collision detection
    const map_pixels = try rl.loadImageColors(im_map);
    defer rl.unloadImageColors(map_pixels);
    rl.unloadImage(im_map); // Unload image from RAM

    const map_position: rl.Vector3 = .{ .x = -16.0, .y = 0.0, .z = -8.0 }; // Set model position

    rl.disableCursor(); // Limit cursor to relative movement inside the window

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const old_cam_pos = camera.position; // Store old camera position

        rl.updateCamera(&camera, .first_person);

        // Check player collision (we simplify to 2D collision detection)
        const player_pos: rl.Vector2 = .{ .x = camera.position.x, .y = camera.position.z };
        const player_radius = 0.1; // Collision radius (player is modelled as a cilinder for collision)

        // Out-of-limits security check
        const player_cell_x = std.math.clamp(@as(i32, @intFromFloat(player_pos.x - map_position.x + 0.5)), 0, cubicmap.width - 1);
        const player_cell_y = std.math.clamp(@as(i32, @intFromFloat(player_pos.y - map_position.z + 0.5)), 0, cubicmap.height - 1);

        // Check map collisions using image data and player position against surrounding cells only
        var y = player_cell_y - 1;
        while (y <= player_cell_y + 1) : (y += 1) {
            // Avoid map accessing out of bounds
            if (y < 0 or y >= cubicmap.height) continue;

            var x = player_cell_x - 1;
            while (x <= player_cell_x + 1) : (x += 1) {
                if (x < 0 or x >= cubicmap.width) continue;

                // NOTE: Collision: Only checking R channel for white pixel
                const cell: rl.Rectangle = .{
                    .x = map_position.x - 0.5 + @as(f32, @floatFromInt(x)) * 1.0,
                    .y = map_position.z - 0.5 + @as(f32, @floatFromInt(y)) * 1.0,
                    .width = 1.0,
                    .height = 1.0,
                };
                if (map_pixels[@intCast(y * cubicmap.width + x)].r == 255 and
                    rl.checkCollisionCircleRec(player_pos, player_radius, cell))
                {
                    // Collision detected, reset camera position
                    camera.position = old_cam_pos;
                }
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(model, map_position, 1.0, .white); // Draw maze map
        }

        const map_width: f32 = @floatFromInt(cubicmap.width);
        const screen_w = rl.getScreenWidth();
        rl.drawTextureEx(cubicmap, .{ .x = @as(f32, @floatFromInt(screen_w)) - map_width * 4.0 - 20, .y = 20.0 }, 0.0, 4.0, .white);
        rl.drawRectangleLines(screen_w - cubicmap.width * 4 - 20, 20, cubicmap.width * 4, cubicmap.height * 4, .green);

        // Draw player position radar
        rl.drawRectangle(screen_w - cubicmap.width * 4 - 20 + player_cell_x * 4, 20 + player_cell_y * 4, 4, 4, .red);

        rl.drawFPS(10, 10);
    }
}
