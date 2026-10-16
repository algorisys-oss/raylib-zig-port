//! raylib [models] example - mesh picking
//!
//! Zig-API translation of examples/models/models_mesh_picking.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2017-2025 Joel Davis (@joeld42) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - mesh picking");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 20.0, .y = 20.0, .z = 20.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 8.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.6, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const tower = try rl.loadModel("resources/models/obj/turret.obj"); // Load OBJ model
    defer rl.unloadModel(tower);
    const texture = try rl.loadTexture("resources/models/obj/turret_diffuse.png"); // Load model texture
    defer rl.unloadTexture(texture);
    tower.materials.?[0].map(.diffuse).texture = texture; // Set model diffuse texture

    const tower_pos: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model position
    const tower_bbox = rl.getMeshBoundingBox(tower.meshes.?[0]); // Get mesh bounding box

    // Ground quad
    const g0: rl.Vector3 = .{ .x = -50.0, .y = 0.0, .z = -50.0 };
    const g1: rl.Vector3 = .{ .x = -50.0, .y = 0.0, .z = 50.0 };
    const g2: rl.Vector3 = .{ .x = 50.0, .y = 0.0, .z = 50.0 };
    const g3: rl.Vector3 = .{ .x = 50.0, .y = 0.0, .z = -50.0 };

    // Test triangle
    const ta: rl.Vector3 = .{ .x = -25.0, .y = 0.5, .z = 0.0 };
    const tb: rl.Vector3 = .{ .x = -4.0, .y = 2.5, .z = 1.0 };
    const tc: rl.Vector3 = .{ .x = -8.0, .y = 6.5, .z = 0.0 };

    var bary: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };

    // Test sphere
    const sp: rl.Vector3 = .{ .x = -30.0, .y = 5.0, .z = 5.0 };
    const sr: f32 = 4.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isCursorHidden()) rl.updateCamera(&camera, .first_person); // Update camera

        // Toggle camera controls
        if (rl.isMouseButtonPressed(.right)) {
            if (rl.isCursorHidden()) rl.enableCursor() else rl.disableCursor();
        }

        // Display information about closest hit
        var collision: rl.RayCollision = .{
            .hit = false,
            .distance = std.math.floatMax(f32),
            .point = .{ .x = 0, .y = 0, .z = 0 },
            .normal = .{ .x = 0, .y = 0, .z = 0 },
        };
        var hit_object_name: [:0]const u8 = "None";
        var cursor_color: rl.Color = .white;

        // Get ray and test against objects
        const ray = rl.getScreenToWorldRay(rl.getMousePosition(), camera);

        // Check ray collision against ground quad
        const ground_hit_info = rl.getRayCollisionQuad(ray, g0, g1, g2, g3);

        if (ground_hit_info.hit and ground_hit_info.distance < collision.distance) {
            collision = ground_hit_info;
            cursor_color = .green;
            hit_object_name = "Ground";
        }

        // Check ray collision against test triangle
        const tri_hit_info = rl.getRayCollisionTriangle(ray, ta, tb, tc);

        if (tri_hit_info.hit and tri_hit_info.distance < collision.distance) {
            collision = tri_hit_info;
            cursor_color = .purple;
            hit_object_name = "Triangle";

            bary = rl.math.vector3Barycenter(collision.point, ta, tb, tc);
        }

        // Check ray collision against test sphere
        const sphere_hit_info = rl.getRayCollisionSphere(ray, sp, sr);

        if (sphere_hit_info.hit and sphere_hit_info.distance < collision.distance) {
            collision = sphere_hit_info;
            cursor_color = .orange;
            hit_object_name = "Sphere";
        }

        // Check ray collision against bounding box first, before trying the full ray-mesh test
        const box_hit_info = rl.getRayCollisionBox(ray, tower_bbox);

        if (box_hit_info.hit and box_hit_info.distance < collision.distance) {
            collision = box_hit_info;
            cursor_color = .orange;
            hit_object_name = "Box";

            // Check ray collision against model meshes, stopping at the first mesh hit
            for (tower.meshSlice()) |mesh| {
                // NOTE: We consider the model.transform for the collision check but
                // it can be checked against any transform Matrix, used when checking against same
                // model drawn multiple times with multiple transforms
                const mesh_hit_info = rl.getRayCollisionMesh(ray, mesh, tower.transform);
                if (mesh_hit_info.hit) {
                    collision = mesh_hit_info;
                    cursor_color = .orange;
                    hit_object_name = "Mesh";
                    break;
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

            // Draw the tower
            // WARNING: If scale is different than 1.0,
            // not considered by getRayCollisionMesh()
            rl.drawModel(tower, tower_pos, 1.0, .white);

            // Draw the test triangle
            rl.drawLine3D(ta, tb, .purple);
            rl.drawLine3D(tb, tc, .purple);
            rl.drawLine3D(tc, ta, .purple);

            // Draw the test sphere
            rl.drawSphereWires(sp, sr, 8, 8, .purple);

            // Draw the mesh bbox if we hit it
            if (box_hit_info.hit) rl.drawBoundingBox(tower_bbox, .lime);

            // If we hit something, draw the cursor at the hit point
            if (collision.hit) {
                rl.drawCube(collision.point, 0.3, 0.3, 0.3, cursor_color);
                rl.drawCubeWires(collision.point, 0.3, 0.3, 0.3, .red);

                const normal_end: rl.Vector3 = .{
                    .x = collision.point.x + collision.normal.x,
                    .y = collision.point.y + collision.normal.y,
                    .z = collision.point.z + collision.normal.z,
                };

                rl.drawLine3D(collision.point, normal_end, .red);
            }

            rl.drawRay(ray, .maroon);

            rl.drawGrid(10, 10.0);
        }

        // Draw some debug GUI text
        rl.drawText(rl.textFormat("Hit Object: {s}", .{hit_object_name}), 10, 50, 10, .black);

        if (collision.hit) {
            const ypos = 70;

            rl.drawText(rl.textFormat("Distance: {d:3.2}", .{collision.distance}), 10, ypos, 10, .black);

            const point = collision.point;
            rl.drawText(rl.textFormat("Hit Pos: {d:3.2} {d:3.2} {d:3.2}", .{ point.x, point.y, point.z }), 10, ypos + 15, 10, .black);

            const normal = collision.normal;
            rl.drawText(rl.textFormat("Hit Norm: {d:3.2} {d:3.2} {d:3.2}", .{ normal.x, normal.y, normal.z }), 10, ypos + 30, 10, .black);

            if (tri_hit_info.hit and std.mem.eql(u8, hit_object_name, "Triangle")) {
                rl.drawText(rl.textFormat("Barycenter: {d:3.2} {d:3.2} {d:3.2}", .{ bary.x, bary.y, bary.z }), 10, ypos + 45, 10, .black);
            }
        }

        rl.drawText("Right click mouse to toggle camera controls", 10, 430, 10, .gray);

        rl.drawText("(c) Turret 3D model by Alberto Cano", screen_width - 200, screen_height - 20, 10, .gray);

        rl.drawFPS(10, 10);
    }
}
