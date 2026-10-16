//! raylib [core] example - 3d camera mode
//!
//! Zig-API translation of examples/core/core_3d_camera_mode.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - 3d camera mode");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    const camera: rl.Camera3D = .{
        .position = .{ .x = 0.0, .y = 10.0, .z = 10.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera mode type
    };

    const cube_position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
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

        rl.drawText("Welcome to the third dimension!", 10, 40, 20, .dark_gray);

        rl.drawFPS(10, 10);
    }
}
