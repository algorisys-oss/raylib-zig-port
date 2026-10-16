//! raylib [models] example - loading vox
//!
//! Zig-API translation of examples/models/models_loading_vox.c (raylib 6.2).
//! Example contributed by Johann Nadalutti (@procfxgen) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2021-2025 Johann Nadalutti (@procfxgen) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");
const rlights = @import("rlights");

const glsl_version = 330;

const vox_file_names = [_][:0]const u8{
    "resources/models/vox/chr_knight.vox",
    "resources/models/vox/chr_sword.vox",
    "resources/models/vox/monu9.vox",
    "resources/models/vox/fez.vox",
};

/// One axis of keyboard movement: 0.1 towards `pos`, minus 0.1 towards `neg`
fn moveAxis(pos: bool, neg: bool) f32 {
    return @as(f32, @floatFromInt(@intFromBool(pos))) * 0.1 - @as(f32, @floatFromInt(@intFromBool(neg))) * 0.1;
}

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - loading vox");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 10.0, .y = 10.0, .z = 10.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load MagicaVoxel files
    var models: [vox_file_names.len]rl.Model = undefined;
    var loaded: usize = 0;
    defer for (models[0..loaded]) |model| rl.unloadModel(model); // Unload models data (GPU VRAM)

    for (&models, vox_file_names) |*model, file_name| {
        // Load VOX file and measure time
        const t0 = rl.getTime() * 1000.0;
        model.* = try rl.loadModel(file_name);
        loaded += 1;
        const t1 = rl.getTime() * 1000.0;

        rl.traceLog(.info, "[{s}] Model file loaded in {d:.3} ms", .{ file_name, t1 - t0 });

        // Compute model translation matrix to center model on draw position (0, 0 , 0)
        const bb = rl.getModelBoundingBox(model.*);
        const center_x = bb.min.x + ((bb.max.x - bb.min.x) / 2);
        const center_z = bb.min.z + ((bb.max.z - bb.min.z) / 2);

        model.transform = rl.math.matrixTranslate(-center_x, 0, -center_z);
    }

    var current_model: usize = 0;
    const model_position = rl.math.vector3Zero();
    var camera_rotation = rl.math.vector3Zero();

    // Load voxel shader
    const shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/voxel_lighting.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/voxel_lighting.fs", .{glsl_version}),
    );
    defer rl.unloadShader(shader);

    // Get some required shader locations
    shader.loc(.vector_view).* = rl.getShaderLocation(shader, "viewPos");
    // NOTE: "matModel" location name is automatically assigned on shader loading,
    // no need to get the location again if using that uniform name
    //shader.loc(.matrix_model).* = rl.getShaderLocation(shader, "matModel");

    // Ambient light level (some basic lighting)
    const ambient_loc = rl.getShaderLocation(shader, "ambient");
    rl.setShaderValue(shader, ambient_loc, [4]f32{ 0.1, 0.1, 0.1, 1.0 });

    // Assign out lighting shader to model
    for (models) |model| {
        for (model.materials.?[0..@intCast(model.materialCount)]) |*material| material.shader = shader;
    }

    // Create lights
    const lights = [rlights.max_lights]rlights.Light{
        rlights.createLight(.point, .{ .x = -20, .y = 20, .z = -20 }, rl.math.vector3Zero(), .gray, shader),
        rlights.createLight(.point, .{ .x = 20, .y = -20, .z = 20 }, rl.math.vector3Zero(), .gray, shader),
        rlights.createLight(.point, .{ .x = -20, .y = 20, .z = 20 }, rl.math.vector3Zero(), .gray, shader),
        rlights.createLight(.point, .{ .x = 20, .y = -20, .z = -20 }, rl.math.vector3Zero(), .gray, shader),
    };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isMouseButtonDown(.middle)) {
            const mouse_delta = rl.getMouseDelta();
            camera_rotation.x = mouse_delta.x * 0.05;
            camera_rotation.y = mouse_delta.y * 0.05;
        } else {
            camera_rotation.x = 0;
            camera_rotation.y = 0;
        }

        // Update camera movement, custom controls
        rl.updateCameraPro(&camera, .{
            .x = moveAxis(rl.isKeyDown(.w) or rl.isKeyDown(.up), rl.isKeyDown(.s) or rl.isKeyDown(.down)), // Move forward-backward
            .y = moveAxis(rl.isKeyDown(.d) or rl.isKeyDown(.right), rl.isKeyDown(.a) or rl.isKeyDown(.left)), // Move right-left
            .z = 0.0, // Move up-down
        }, camera_rotation, // Camera rotation
            rl.getMouseWheelMove() * -2.0); // Move to target (zoom)

        // Cycle between models on mouse click
        if (rl.isMouseButtonPressed(.left)) current_model = (current_model + 1) % models.len;

        // Update the shader with the camera view vector (points towards { 0.0f, 0.0f, 0.0f })
        rl.setShaderValue(shader, shader.loc(.vector_view).*, camera.position);

        // Update light values (actually, only enable/disable them)
        for (lights) |light| light.update(shader);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw 3D model
        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(models[current_model], model_position, 1.0, .white);
            rl.drawGrid(10, 1.0);

            // Draw spheres to show where the lights are
            for (lights) |light| {
                if (light.enabled) {
                    rl.drawSphereEx(light.position, 0.2, 8, 8, light.color);
                } else {
                    rl.drawSphereWires(light.position, 0.2, 8, 8, rl.colorAlpha(light.color, 0.3));
                }
            }
        }

        // Display info
        rl.drawRectangle(10, 40, 340, 70, rl.fade(.sky_blue, 0.5));
        rl.drawRectangleLines(10, 40, 340, 70, rl.fade(.dark_blue, 0.5));
        rl.drawText("- MOUSE LEFT BUTTON: CYCLE VOX MODELS", 20, 50, 10, .blue);
        rl.drawText("- MOUSE MIDDLE BUTTON: ZOOM OR ROTATE CAMERA", 20, 70, 10, .blue);
        rl.drawText("- UP-DOWN-LEFT-RIGHT KEYS: MOVE CAMERA", 20, 90, 10, .blue);
        rl.drawText(rl.textFormat("VOX model file: {s}", .{rl.getFileName(vox_file_names[current_model])}), 10, 10, 20, .gray);
    }
}
