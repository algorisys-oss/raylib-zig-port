//! raylib [models] example - basic voxel
//!
//! Zig-API translation of examples/models/models_basic_voxel.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Tim Little (@timlittle)

const rl = @import("raylib");

const world_size = 8; // Size of our voxel world (8x8x8 cubes)

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - basic voxel");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.disableCursor(); // Lock mouse to window center

    // Define the camera to look into our 3d world (first person)
    var camera: rl.Camera3D = .{
        .position = .{ .x = -2.0, .y = 0.0, .z = -2.0 }, // Camera position at ground level
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Create a cube model
    const cube_mesh = rl.genMeshCube(1.0, 1.0, 1.0); // Create a unit cube mesh
    const cube_model = try rl.loadModelFromMesh(cube_mesh); // Convert mesh to a model
    defer rl.unloadModel(cube_model);
    cube_model.materials.?[0].map(.diffuse).color = .beige;

    // Initialize voxel world - fill with voxels
    var voxels: [world_size][world_size][world_size]bool = @splat(@splat(@splat(true)));

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .first_person);

        // Handle voxel removal with mouse click
        // This method is quite inefficient. Ray marching through the voxel grid using DDA would be faster, but more complex.
        if (rl.isMouseButtonPressed(.left)) {
            // Cast a ray from the screen center (where crosshair would be)
            const screen_center: rl.Vector2 = .{
                .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
                .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
            };
            const ray = rl.getScreenToWorldRay(screen_center, camera);

            // Check ray collision with all voxels
            var closest_distance: f32 = 99999.0;
            var closest_voxel: ?*bool = null;
            for (&voxels, 0..) |*plane, x| {
                for (plane, 0..) |*row, y| {
                    for (row, 0..) |*voxel, z| {
                        if (!voxel.*) continue; // Skip empty voxels

                        // Build a bounding box for this voxel
                        const position = voxelPosition(x, y, z);
                        const box: rl.BoundingBox = .{
                            .min = .{ .x = position.x - 0.5, .y = position.y - 0.5, .z = position.z - 0.5 },
                            .max = .{ .x = position.x + 0.5, .y = position.y + 0.5, .z = position.z + 0.5 },
                        };

                        // Check ray-box collision
                        const collision = rl.getRayCollisionBox(ray, box);
                        if (collision.hit and collision.distance < closest_distance) {
                            closest_distance = collision.distance;
                            closest_voxel = voxel;
                        }
                    }
                }
            }

            // Remove the closest voxel if one was hit
            if (closest_voxel) |voxel| voxel.* = false;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawGrid(10, 1.0);

            // Draw all voxels
            for (voxels, 0..) |plane, x| {
                for (plane, 0..) |row, y| {
                    for (row, 0..) |voxel, z| {
                        if (!voxel) continue;

                        const position = voxelPosition(x, y, z);
                        rl.drawModel(cube_model, position, 1.0, .beige);
                        rl.drawCubeWires(position, 1.0, 1.0, 1.0, .black);
                    }
                }
            }
        }

        // Draw reference point for raycasting to delete blocks
        rl.drawCircle(@divTrunc(rl.getScreenWidth(), 2), @divTrunc(rl.getScreenHeight(), 2), 4, .red);

        rl.drawText("Left-click a voxel to remove it!", 10, 10, 20, .dark_gray);
        rl.drawText("WASD to move, mouse to look around", 10, 35, 10, .gray);
    }
}

fn voxelPosition(x: usize, y: usize, z: usize) rl.Vector3 {
    return .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z) };
}
