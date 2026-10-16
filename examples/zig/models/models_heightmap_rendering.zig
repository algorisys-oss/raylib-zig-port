//! raylib [models] example - heightmap rendering
//!
//! Zig-API translation of examples/models/models_heightmap_rendering.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - heightmap rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define our custom camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 18.0, .y = 21.0, .z = 18.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const image = try rl.loadImage("resources/heightmap.png"); // Load heightmap image (RAM)
    const texture = try rl.loadTextureFromImage(image); // Convert image to texture (VRAM)
    defer rl.unloadTexture(texture);

    const mesh = rl.genMeshHeightmap(image, .{ .x = 16, .y = 8, .z = 16 }); // Generate heightmap mesh (RAM and VRAM)
    const model = try rl.loadModelFromMesh(mesh); // Load model from generated mesh
    defer rl.unloadModel(model);

    model.materials.?[0].map(.diffuse).texture = texture; // Set map diffuse texture
    const map_position: rl.Vector3 = .{ .x = -8.0, .y = 0.0, .z = -8.0 }; // Define model position

    rl.unloadImage(image); // Unload heightmap image from RAM, already uploaded to VRAM

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(model, map_position, 1.0, .red);

            rl.drawGrid(20, 1.0);
        }

        rl.drawTexture(texture, screen_width - texture.width - 20, 20, .white);
        rl.drawRectangleLines(screen_width - texture.width - 20, 20, texture.width, texture.height, .green);

        rl.drawFPS(10, 10);
    }
}
