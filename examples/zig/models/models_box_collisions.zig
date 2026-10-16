//! raylib [models] example - box collisions
//!
//! Zig-API translation of examples/models/models_box_collisions.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - box collisions");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    const camera: rl.Camera = .{
        .position = .{ .x = 0.0, .y = 10.0, .z = 10.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    var player_position: rl.Vector3 = .{ .x = 0.0, .y = 1.0, .z = 2.0 };
    const player_size: rl.Vector3 = .{ .x = 1.0, .y = 2.0, .z = 1.0 };

    const enemy_box_pos: rl.Vector3 = .{ .x = -4.0, .y = 1.0, .z = 0.0 };
    const enemy_box_size: rl.Vector3 = .{ .x = 2.0, .y = 2.0, .z = 2.0 };

    const enemy_sphere_pos: rl.Vector3 = .{ .x = 4.0, .y = 0.0, .z = 0.0 };
    const enemy_sphere_size: f32 = 1.5;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update

        // Move player
        if (rl.isKeyDown(.right)) {
            player_position.x += 0.2;
        } else if (rl.isKeyDown(.left)) {
            player_position.x -= 0.2;
        } else if (rl.isKeyDown(.down)) {
            player_position.z += 0.2;
        } else if (rl.isKeyDown(.up)) {
            player_position.z -= 0.2;
        }

        const player_box = boundingBox(player_position, player_size);

        // Check collisions player vs enemy-box and player vs enemy-sphere
        const collision = rl.checkCollisionBoxes(player_box, boundingBox(enemy_box_pos, enemy_box_size)) or
            rl.checkCollisionBoxSphere(player_box, enemy_sphere_pos, enemy_sphere_size);

        const player_color: rl.Color = if (collision) .red else .green;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            // Draw enemy-box
            rl.drawCube(enemy_box_pos, enemy_box_size.x, enemy_box_size.y, enemy_box_size.z, .gray);
            rl.drawCubeWires(enemy_box_pos, enemy_box_size.x, enemy_box_size.y, enemy_box_size.z, .dark_gray);

            // Draw enemy-sphere
            rl.drawSphere(enemy_sphere_pos, enemy_sphere_size, .gray);
            rl.drawSphereWires(enemy_sphere_pos, enemy_sphere_size, 16, 16, .dark_gray);

            // Draw player
            rl.drawCubeV(player_position, player_size, player_color);

            rl.drawGrid(10, 1.0); // Draw a grid
        }

        rl.drawText("Move player with arrow keys to collide", 220, 40, 20, .gray);

        rl.drawFPS(10, 10);
    }
}

/// Axis-aligned box of `size` centered at `center`.
fn boundingBox(center: rl.Vector3, size: rl.Vector3) rl.BoundingBox {
    return .{
        .min = .{ .x = center.x - size.x / 2, .y = center.y - size.y / 2, .z = center.z - size.z / 2 },
        .max = .{ .x = center.x + size.x / 2, .y = center.y + size.y / 2, .z = center.z + size.z / 2 },
    };
}
