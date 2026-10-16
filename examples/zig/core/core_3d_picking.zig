//! raylib [core] example - 3d picking
//!
//! Zig-API translation of examples/core/core_3d_picking.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - 3d picking");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 10.0, .y = 10.0, .z = 10.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const cube_position: rl.Vector3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 };
    const cube_size: rl.Vector3 = .{ .x = 2.0, .y = 2.0, .z = 2.0 };

    var ray: rl.Ray = .{ .position = .{ .x = 0, .y = 0, .z = 0 }, .direction = .{ .x = 0, .y = 0, .z = 0 } }; // Picking line ray
    var collision: rl.RayCollision = .{ // Ray collision hit info
        .hit = false,
        .distance = 0,
        .point = .{ .x = 0, .y = 0, .z = 0 },
        .normal = .{ .x = 0, .y = 0, .z = 0 },
    };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isCursorHidden()) rl.updateCamera(&camera, .first_person);

        // Toggle camera controls
        if (rl.isMouseButtonPressed(.right)) {
            if (rl.isCursorHidden()) rl.enableCursor() else rl.disableCursor();
        }

        if (rl.isMouseButtonPressed(.left)) {
            if (!collision.hit) {
                ray = rl.getScreenToWorldRay(rl.getMousePosition(), camera);

                // Check collision between ray and box
                collision = rl.getRayCollisionBox(ray, .{
                    .min = .{
                        .x = cube_position.x - cube_size.x / 2,
                        .y = cube_position.y - cube_size.y / 2,
                        .z = cube_position.z - cube_size.z / 2,
                    },
                    .max = .{
                        .x = cube_position.x + cube_size.x / 2,
                        .y = cube_position.y + cube_size.y / 2,
                        .z = cube_position.z + cube_size.z / 2,
                    },
                });
            } else collision.hit = false;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            if (collision.hit) {
                rl.drawCube(cube_position, cube_size.x, cube_size.y, cube_size.z, .red);
                rl.drawCubeWires(cube_position, cube_size.x, cube_size.y, cube_size.z, .maroon);

                rl.drawCubeWires(cube_position, cube_size.x + 0.2, cube_size.y + 0.2, cube_size.z + 0.2, .green);
            } else {
                rl.drawCube(cube_position, cube_size.x, cube_size.y, cube_size.z, .gray);
                rl.drawCubeWires(cube_position, cube_size.x, cube_size.y, cube_size.z, .dark_gray);
            }

            rl.drawRay(ray, .maroon);
            rl.drawGrid(10, 1.0);
        }

        rl.drawText("Try clicking on the box with your mouse!", 240, 10, 20, .dark_gray);

        if (collision.hit) {
            const text_y: i32 = @intFromFloat(@as(f32, screen_height) * 0.1);
            rl.drawText("BOX SELECTED", @divTrunc(screen_width - rl.measureText("BOX SELECTED", 30), 2), text_y, 30, .green);
        }

        rl.drawText("Right click mouse to toggle camera controls", 10, 430, 10, .gray);

        rl.drawFPS(10, 10);
    }
}
