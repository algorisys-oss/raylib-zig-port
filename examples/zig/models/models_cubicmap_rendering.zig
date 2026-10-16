//! raylib [models] example - cubicmap rendering
//!
//! Zig-API translation of examples/models/models_cubicmap_rendering.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - cubicmap rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 16.0, .y = 14.0, .z = 16.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const image = try rl.loadImage("resources/cubicmap.png"); // Load cubicmap image (RAM)
    const cubicmap = try rl.loadTextureFromImage(image); // Convert image to texture to display (VRAM)
    defer rl.unloadTexture(cubicmap);

    const mesh = rl.genMeshCubicmap(image, .{ .x = 1.0, .y = 1.0, .z = 1.0 });
    const model = try rl.loadModelFromMesh(mesh);
    defer rl.unloadModel(model);

    // NOTE: By default each cube is mapped to one part of texture atlas
    const texture = try rl.loadTexture("resources/cubicmap_atlas.png"); // Load map texture
    defer rl.unloadTexture(texture);
    model.materials.?[0].map(.diffuse).texture = texture; // Set map diffuse texture

    const map_position: rl.Vector3 = .{ .x = -16.0, .y = 0.0, .z = -8.0 }; // Set model position

    rl.unloadImage(image); // Unload cubesmap image from RAM, already uploaded to VRAM

    var pause = false; // Pause camera orbital rotation (and zoom)

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.p)) pause = !pause;

        if (!pause) rl.updateCamera(&camera, .orbital);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(model, map_position, 1.0, .white);
        }

        const map_width: f32 = @floatFromInt(cubicmap.width);
        rl.drawTextureEx(cubicmap, .{ .x = screen_width - map_width * 4.0 - 20, .y = 20.0 }, 0.0, 4.0, .white);
        rl.drawRectangleLines(screen_width - cubicmap.width * 4 - 20, 20, cubicmap.width * 4, cubicmap.height * 4, .green);

        rl.drawText("cubicmap image used to", 658, 90, 10, .gray);
        rl.drawText("generate map 3d model", 658, 104, 10, .gray);

        rl.drawFPS(10, 10);
    }
}
