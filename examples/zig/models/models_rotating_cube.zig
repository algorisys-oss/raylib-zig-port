//! raylib [models] example - rotating cube
//!
//! Zig-API translation of examples/models/models_rotating_cube.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jopestpe (@jopestpe)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - rotating cube");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    const camera: rl.Camera = .{
        .position = .{ .x = 0.0, .y = 3.0, .z = 3.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    // Load image to create texture for the cube
    const model = try rl.loadModelFromMesh(rl.genMeshCube(1.0, 1.0, 1.0));
    defer rl.unloadModel(model);
    const img = try rl.loadImage("resources/cubicmap_atlas.png");
    const width: f32 = @floatFromInt(img.width);
    const height: f32 = @floatFromInt(img.height);
    const crop = rl.imageFromImage(img, .{ .x = 0, .y = height / 2.0, .width = width / 2.0, .height = height / 2.0 });
    const texture = try rl.loadTextureFromImage(crop);
    defer rl.unloadTexture(texture);
    rl.unloadImage(img);
    rl.unloadImage(crop);

    model.materials.?[0].map(.diffuse).texture = texture;

    var rotation: f32 = 0.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rotation += 1.0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            // Draw model defining: position, size, rotation-axis, rotation (degrees), size, and tint-color
            rl.drawModelEx(model, .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .{ .x = 0.5, .y = 1.0, .z = 0.0 }, rotation, .{ .x = 1.0, .y = 1.0, .z = 1.0 }, .white);

            rl.drawGrid(10, 1.0);
        }

        rl.drawFPS(10, 10);
    }
}
