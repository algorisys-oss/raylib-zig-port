//! raylib [models] example - orthographic projection
//!
//! Zig-API translation of examples/models/models_orthographic_projection.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2018-2025 Max Danielsson (@autious) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const fovy_perspective = 45.0;
const width_orthographic = 10.0;

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - orthographic projection");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 0.0, .y = 10.0, .z = 10.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = fovy_perspective,
        .projection = .perspective,
    };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.space)) {
            switch (camera.projection) {
                .perspective => {
                    camera.fovy = width_orthographic;
                    camera.projection = .orthographic;
                },
                .orthographic => {
                    camera.fovy = fovy_perspective;
                    camera.projection = .perspective;
                },
            }
        }

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

            rl.drawGrid(10, 1.0); // Draw a grid
        }

        rl.drawText("Press Spacebar to switch camera type", 10, rl.getScreenHeight() - 30, 20, .dark_gray);

        switch (camera.projection) {
            .orthographic => rl.drawText("ORTHOGRAPHIC", 10, 40, 20, .black),
            .perspective => rl.drawText("PERSPECTIVE", 10, 40, 20, .black),
        }

        rl.drawFPS(10, 10);
    }
}
