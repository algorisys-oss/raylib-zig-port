//! raylib [core] example - world screen
//!
//! Zig-API translation of examples/core/core_world_screen.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - world screen");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 10.0, .y = 10.0, .z = 10.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const cube_position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };

    rl.disableCursor(); // Limit cursor to relative movement inside the window

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .third_person);

        // Calculate cube screen space position (with a little offset to be in top)
        const cube_screen_position = rl.getWorldToScreen(.{
            .x = cube_position.x,
            .y = cube_position.y + 2.5,
            .z = cube_position.z,
        }, camera);
        const screen_x: i32 = @intFromFloat(cube_screen_position.x);
        const screen_y: i32 = @intFromFloat(cube_screen_position.y);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawCube(cube_position, 2.0, 2.0, 2.0, .red);
            rl.drawCubeWires(cube_position, 2.0, 2.0, 2.0, .maroon);

            rl.drawGrid(10, 1.0);
        }

        const enemy_text = "Enemy: 100/100";
        rl.drawText(enemy_text, screen_x - @divTrunc(rl.measureText(enemy_text, 20), 2), screen_y, 20, .black);

        rl.drawText(rl.textFormat("Cube position in screen space coordinates: [{d}, {d}]", .{ screen_x, screen_y }), 10, 10, 20, .lime);
        rl.drawText("Text 2d should be always on top of the cube", 10, 40, 20, .gray);
    }
}
