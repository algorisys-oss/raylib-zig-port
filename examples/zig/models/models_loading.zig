//! raylib [models] example - loading
//!
//! NOTE: raylib supports multiple models file formats:
//!
//!   - OBJ  > Text file format. Must include vertex position-texcoords-normals information,
//!            if .obj references some .mtl materials file, it will be tried to be loaded
//!   - GLTF/GLB > Text/binary file formats. Includes lot of information and it could
//!            also reference external files, mesh and materials data will be tried to be loaded
//!   - IQM  > Binary file format. Includes mesh vertex data but also animation data,
//!            meshes and animation data can be loaded
//!   - VOX  > Binary file format. MagikaVoxel mesh format:
//!            https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt
//!   - M3D  > Binary file format. Model 3D format:
//!            https://bztsrc.gitlab.io/model3d
//!
//! Zig-API translation of examples/models/models_loading.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - loading");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 50.0, .y = 50.0, .z = 50.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 12.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera mode type
    };

    var model = try rl.loadModel("resources/models/obj/castle.obj"); // Load model
    defer rl.unloadModel(model);
    var texture = try rl.loadTexture("resources/models/obj/castle_diffuse.png"); // Load model texture
    defer rl.unloadTexture(texture);
    model.materials.?[0].map(.diffuse).texture = texture; // Set map diffuse texture

    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model position

    var bounds = rl.getMeshBoundingBox(model.meshes.?[0]); // Set model bounds

    // NOTE: bounds are calculated from the original size of the model,
    // if model is scaled on drawing, bounds must be also scaled

    var selected = false; // Selected object flag

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        // Load new models/textures on drag&drop
        if (rl.isFileDropped()) {
            const dropped_files = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(dropped_files); // Unload filepaths from memory

            if (dropped_files.count == 1) { // Only support one file dropped
                const path = std.mem.span(dropped_files.paths.?[0]);

                if (isModelFile(path)) { // Model file formats supported
                    // Unload previous model only once the new one loaded
                    if (rl.loadModel(path)) |new_model| {
                        rl.unloadModel(model);
                        model = new_model;
                        model.materials.?[0].map(.diffuse).texture = texture; // Set current map diffuse texture

                        bounds = rl.getMeshBoundingBox(model.meshes.?[0]);

                        // Move camera position from target enough distance to visualize model properly
                        camera.position.x = bounds.max.x + 10.0;
                        camera.position.y = bounds.max.y + 10.0;
                        camera.position.z = bounds.max.z + 10.0;
                    } else |_| {}
                } else if (rl.isFileExtension(path, ".png")) { // Texture file formats supported
                    // Unload current model texture and load new one
                    if (rl.loadTexture(path)) |new_texture| {
                        rl.unloadTexture(texture);
                        texture = new_texture;
                        model.materials.?[0].map(.diffuse).texture = texture;
                    } else |_| {}
                }
            }
        }

        // Select model on mouse click
        if (rl.isMouseButtonPressed(.left)) {
            // Check collision between ray and box
            selected = if (rl.getRayCollisionBox(rl.getScreenToWorldRay(rl.getMousePosition(), camera), bounds).hit) !selected else false;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(model, position, 1.0, .white); // Draw 3d model with texture

            rl.drawGrid(20, 10.0); // Draw a grid

            if (selected) rl.drawBoundingBox(bounds, .green); // Draw selection box
        }

        rl.drawText("Drag & drop model to load mesh/texture.", 10, rl.getScreenHeight() - 20, 10, .dark_gray);
        if (selected) rl.drawText("MODEL SELECTED", rl.getScreenWidth() - 110, 10, 10, .green);

        rl.drawText("(c) Castle 3D model by Alberto Cano", screen_width - 200, screen_height - 20, 10, .gray);

        rl.drawFPS(10, 10);
    }
}

fn isModelFile(path: [:0]const u8) bool {
    for ([_][:0]const u8{ ".obj", ".gltf", ".glb", ".vox", ".iqm", ".m3d" }) |ext| {
        if (rl.isFileExtension(path, ext)) return true;
    }
    return false;
}
