//! raylib [models] example - geometric shapes
//!
//! Zig-API translation of examples/models/models_geometric_shapes.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - geometric shapes");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    const camera: rl.Camera = .{
        .position = .{ .x = 0.0, .y = 10.0, .z = 10.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

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

            rl.drawCube(.{ .x = -4.0, .y = 0.0, .z = 2.0 }, 2.0, 5.0, 2.0, .red);
            rl.drawCubeWires(.{ .x = -4.0, .y = 0.0, .z = 2.0 }, 2.0, 5.0, 2.0, .gold);
            rl.drawCubeWires(.{ .x = -4.0, .y = 0.0, .z = -2.0 }, 3.0, 6.0, 2.0, .maroon);

            rl.drawSphere(.{ .x = -1.0, .y = 0.0, .z = -2.0 }, 1.0, .green);
            rl.drawSphereWires(.{ .x = 1.0, .y = 0.0, .z = 2.0 }, 2.0, 16, 16, .lime);

            rl.drawCylinder(.{ .x = 4.0, .y = 0.0, .z = -2.0 }, 1.0, 2.0, 3.0, 4, .sky_blue);
            rl.drawCylinderWires(.{ .x = 4.0, .y = 0.0, .z = -2.0 }, 1.0, 2.0, 3.0, 4, .dark_blue);
            rl.drawCylinderWires(.{ .x = 4.5, .y = -1.0, .z = 2.0 }, 1.0, 1.0, 2.0, 6, .brown);

            rl.drawCylinder(.{ .x = 1.0, .y = 0.0, .z = -4.0 }, 0.0, 1.5, 3.0, 8, .gold);
            rl.drawCylinderWires(.{ .x = 1.0, .y = 0.0, .z = -4.0 }, 0.0, 1.5, 3.0, 8, .pink);

            rl.drawCapsule(.{ .x = -3.0, .y = 1.5, .z = -4.0 }, .{ .x = -4.0, .y = -1.0, .z = -4.0 }, 1.2, 8, 8, .violet);
            rl.drawCapsuleWires(.{ .x = -3.0, .y = 1.5, .z = -4.0 }, .{ .x = -4.0, .y = -1.0, .z = -4.0 }, 1.2, 8, 8, .purple);

            rl.drawGrid(10, 1.0); // Draw a grid
        }

        rl.drawFPS(10, 10);
    }
}
