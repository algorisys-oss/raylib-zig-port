//! raylib [models] example - billboard rendering
//!
//! Zig-API translation of examples/models/models_billboard_rendering.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - billboard rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 5.0, .y = 4.0, .z = 5.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 2.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const bill = try rl.loadTexture("resources/billboard.png"); // Our billboard texture
    defer rl.unloadTexture(bill);
    const bill_position_static: rl.Vector3 = .{ .x = 0.0, .y = 2.0, .z = 0.0 }; // Position of static billboard
    const bill_position_rotating: rl.Vector3 = .{ .x = 1.0, .y = 2.0, .z = 1.0 }; // Position of rotating billboard

    // Entire billboard texture, source is used to take a segment from a larger texture
    const source: rl.Rectangle = .{ .x = 0.0, .y = 0.0, .width = @floatFromInt(bill.width), .height = @floatFromInt(bill.height) };

    // NOTE: Billboard locked on axis-Y
    const bill_up: rl.Vector3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 };

    // Set the height of the rotating billboard to 1.0 with the aspect ratio fixed
    const size: rl.Vector2 = .{ .x = source.width / source.height, .y = 1.0 };

    // Rotate around origin
    // Here we choose to rotate around the image center
    const origin = rl.math.vector2Scale(size, 0.5);

    var rotation: f32 = 0.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        rotation += 0.4;
        // Distance is needed for the correct billboard draw order
        // Larger distance (further away from the camera) should be drawn prior to smaller distance
        const distance_static = rl.math.vector3Distance(camera.position, bill_position_static);
        const distance_rotating = rl.math.vector3Distance(camera.position, bill_position_rotating);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawGrid(10, 1.0); // Draw a grid

            // Draw order matters!
            if (distance_static > distance_rotating) {
                rl.drawBillboard(camera, bill, bill_position_static, 2.0, .white);
                rl.drawBillboardPro(camera, bill, source, bill_position_rotating, bill_up, size, origin, rotation, .white);
            } else {
                rl.drawBillboardPro(camera, bill, source, bill_position_rotating, bill_up, size, origin, rotation, .white);
                rl.drawBillboard(camera, bill, bill_position_static, 2.0, .white);
            }
        }

        rl.drawFPS(10, 10);
    }
}
