//! raylib [models] example - waving cubes
//!
//! Zig-API translation of examples/models/models_waving_cubes.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Codecat (@codecat) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - waving cubes");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Initialize the camera
    var camera: rl.Camera3D = .{
        .position = .{ .x = 30.0, .y = 20.0, .z = 30.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 70.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Specify the amount of blocks in each direction
    const num_blocks = 15;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const time = rl.getTime();

        // Calculate time scale for cube position and size
        const scale = (2.0 + @as(f32, @floatCast(@sin(time)))) * 0.7;

        // Move camera around the scene
        const camera_time = time * 0.3;
        camera.position.x = @as(f32, @floatCast(@cos(camera_time))) * 40.0;
        camera.position.z = @as(f32, @floatCast(@sin(camera_time))) * 40.0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawGrid(10, 5.0);

            for (0..num_blocks) |x| {
                for (0..num_blocks) |y| {
                    for (0..num_blocks) |z| {
                        const xyz = x + y + z;

                        // Scale of the blocks depends on x/y/z positions
                        const block_scale = @as(f32, @floatFromInt(xyz)) / 30.0;

                        // Scatter makes the waving effect by adding block_scale over time
                        const scatter = @sin(block_scale * 20.0 + @as(f32, @floatCast(time * 4.0)));

                        // Calculate the cube position
                        const half = @as(f32, num_blocks) / 2;
                        const cube_pos: rl.Vector3 = .{
                            .x = (@as(f32, @floatFromInt(x)) - half) * (scale * 3.0) + scatter,
                            .y = (@as(f32, @floatFromInt(y)) - half) * (scale * 2.0) + scatter,
                            .z = (@as(f32, @floatFromInt(z)) - half) * (scale * 3.0) + scatter,
                        };

                        // Pick a color with a hue depending on cube position for the rainbow color effect
                        // NOTE: This function is quite costly to be done per cube and frame,
                        // pre-catching the results into a separate array could improve performance
                        const cube_color = rl.colorFromHSV(@floatFromInt((xyz * 18) % 360), 0.75, 0.9);

                        // Calculate cube size
                        const cube_size = (2.4 - scale) * block_scale;

                        // And finally, draw the cube!
                        rl.drawCube(cube_pos, cube_size, cube_size, cube_size, cube_color);
                    }
                }
            }
        }

        rl.drawFPS(10, 10);
    }
}
