//! raylib [core] example - 3d camera first person
//!
//! Zig-API translation of examples/core/core_3d_camera_first_person.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const max_columns = 20;

/// A column of the scene: random height, position and color.
const Column = struct {
    height: f32,
    position: rl.Vector3,
    color: rl.Color,
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - 3d camera first person");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world (position, target, up vector)
    var camera: rl.Camera = .{
        .position = .{ .x = 0.0, .y = 2.0, .z = 4.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 2.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 60.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    var camera_mode: rl.CameraMode = .first_person;

    // Generates some random columns
    var columns: [max_columns]Column = undefined;
    for (&columns) |*column| {
        const height: f32 = @floatFromInt(rl.getRandomValue(1, 12));
        const x: f32 = @floatFromInt(rl.getRandomValue(-15, 15));
        const z: f32 = @floatFromInt(rl.getRandomValue(-15, 15));
        const r: u8 = @intCast(rl.getRandomValue(20, 255));
        const g: u8 = @intCast(rl.getRandomValue(10, 55));
        column.* = .{
            .height = height,
            .position = .{ .x = x, .y = height / 2.0, .z = z },
            .color = .{ .r = r, .g = g, .b = 30, .a = 255 },
        };
    }

    rl.disableCursor(); // Limit cursor to relative movement inside the window

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    const up: rl.Vector3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 };

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Switch camera mode (each switch also resets roll)
        const mode_keys = [_]struct { rl.KeyboardKey, rl.CameraMode }{
            .{ .one, .free },
            .{ .two, .first_person },
            .{ .three, .third_person },
            .{ .four, .orbital },
        };
        for (mode_keys) |entry| {
            const key, const mode = entry;
            if (rl.isKeyPressed(key)) {
                camera_mode = mode;
                camera.up = up; // Reset roll
            }
        }

        // Switch camera projection
        if (rl.isKeyPressed(.p)) {
            switch (camera.projection) {
                .perspective => {
                    // Create isometric view
                    camera_mode = .third_person;
                    // Note: The target distance is related to the render distance in the orthographic projection
                    camera.position = .{ .x = 0.0, .y = 2.0, .z = -100.0 };
                    camera.target = .{ .x = 0.0, .y = 2.0, .z = 0.0 };
                    camera.up = up;
                    camera.projection = .orthographic;
                    camera.fovy = 20.0; // near plane width in CAMERA_ORTHOGRAPHIC
                    rl.cameraYaw(&camera, -135 * rl.deg2rad, true);
                    rl.cameraPitch(&camera, -45 * rl.deg2rad, true, true, false);
                },
                .orthographic => {
                    // Reset to default view
                    camera_mode = .third_person;
                    camera.position = .{ .x = 0.0, .y = 2.0, .z = 10.0 };
                    camera.target = .{ .x = 0.0, .y = 2.0, .z = 0.0 };
                    camera.up = up;
                    camera.projection = .perspective;
                    camera.fovy = 60.0;
                },
            }
        }

        // Update camera computes movement internally depending on the camera mode
        // Some default standard keyboard/mouse inputs are hardcoded to simplify use
        // For advanced camera controls, it's recommended to compute camera movement manually
        rl.updateCamera(&camera, camera_mode); // Update camera

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawPlane(.{ .x = 0.0, .y = 0.0, .z = 0.0 }, .{ .x = 32.0, .y = 32.0 }, .light_gray); // Draw ground
            rl.drawCube(.{ .x = -16.0, .y = 2.5, .z = 0.0 }, 1.0, 5.0, 32.0, .blue); // Draw a blue wall
            rl.drawCube(.{ .x = 16.0, .y = 2.5, .z = 0.0 }, 1.0, 5.0, 32.0, .lime); // Draw a green wall
            rl.drawCube(.{ .x = 0.0, .y = 2.5, .z = 16.0 }, 32.0, 5.0, 1.0, .gold); // Draw a yellow wall

            // Draw some cubes around
            for (columns) |column| {
                rl.drawCube(column.position, 2.0, column.height, 2.0, column.color);
                rl.drawCubeWires(column.position, 2.0, column.height, 2.0, .maroon);
            }

            // Draw player cube
            if (camera_mode == .third_person) {
                rl.drawCube(camera.target, 0.5, 0.5, 0.5, .purple);
                rl.drawCubeWires(camera.target, 0.5, 0.5, 0.5, .dark_purple);
            }
        }

        // Draw info boxes
        rl.drawRectangle(5, 5, 330, 100, rl.fade(.sky_blue, 0.5));
        rl.drawRectangleLines(5, 5, 330, 100, .blue);

        rl.drawText("Camera controls:", 15, 15, 10, .black);
        rl.drawText("- Move keys: W, A, S, D, Space, Left-Ctrl", 15, 30, 10, .black);
        rl.drawText("- Look around: arrow keys or mouse", 15, 45, 10, .black);
        rl.drawText("- Camera mode keys: 1, 2, 3, 4", 15, 60, 10, .black);
        rl.drawText("- Zoom keys: num-plus, num-minus or mouse scroll", 15, 75, 10, .black);
        rl.drawText("- Camera projection key: P", 15, 90, 10, .black);

        rl.drawRectangle(600, 5, 195, 100, rl.fade(.sky_blue, 0.5));
        rl.drawRectangleLines(600, 5, 195, 100, .blue);

        rl.drawText("Camera status:", 610, 15, 10, .black);
        rl.drawText(rl.textFormat("- Mode: {s}", .{modeName(camera_mode)}), 610, 30, 10, .black);
        rl.drawText(rl.textFormat("- Projection: {s}", .{projectionName(camera.projection)}), 610, 45, 10, .black);
        rl.drawText(rl.textFormat("- Position: ({d:0>6.3}, {d:0>6.3}, {d:0>6.3})", .{ camera.position.x, camera.position.y, camera.position.z }), 610, 60, 10, .black);
        rl.drawText(rl.textFormat("- Target: ({d:0>6.3}, {d:0>6.3}, {d:0>6.3})", .{ camera.target.x, camera.target.y, camera.target.z }), 610, 75, 10, .black);
        rl.drawText(rl.textFormat("- Up: ({d:0>6.3}, {d:0>6.3}, {d:0>6.3})", .{ camera.up.x, camera.up.y, camera.up.z }), 610, 90, 10, .black);
    }
}

fn modeName(mode: rl.CameraMode) [:0]const u8 {
    return switch (mode) {
        .free => "FREE",
        .first_person => "FIRST_PERSON",
        .third_person => "THIRD_PERSON",
        .orbital => "ORBITAL",
        else => "CUSTOM",
    };
}

fn projectionName(projection: rl.CameraProjection) [:0]const u8 {
    return switch (projection) {
        .perspective => "PERSPECTIVE",
        .orthographic => "ORTHOGRAPHIC",
    };
}
