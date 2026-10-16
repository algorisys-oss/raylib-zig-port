//! raylib [shaders] example - mesh instancing
//!
//! Zig-API translation of examples/shaders/shaders_mesh_instancing.c (raylib 6.2).
//! Example contributed by seanpringle (@seanpringle) and reviewed by Max (@moliad) and Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2020-2025 seanpringle (@seanpringle), Max (@moliad) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");
const rlights = @import("rlights");

const glsl_version = 330;

const max_instances = 10000;

/// A random value in [min, max], as f32
fn randomFloat(min: i32, max: i32) f32 {
    return @floatFromInt(rl.getRandomValue(min, max));
}

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - mesh instancing");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = -125.0, .y = 125.0, .z = -125.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Define mesh to be instanced
    const cube = rl.genMeshCube(1.0, 1.0, 1.0);
    defer rl.unloadMesh(cube); // Unload cube mesh

    // Define transforms to be uploaded to GPU for instances
    const allocator = std.heap.c_allocator;
    const transforms = try allocator.alloc(rl.Matrix, max_instances); // Pre-multiplied transformations passed to rlgl
    defer allocator.free(transforms);

    // Translate and rotate cubes randomly
    for (transforms) |*transform| {
        const tx = randomFloat(-50, 50);
        const ty = randomFloat(-50, 50);
        const tz = randomFloat(-50, 50);
        const translation = rl.math.matrixTranslate(tx, ty, tz);
        const ax = randomFloat(0, 360);
        const ay = randomFloat(0, 360);
        const az = randomFloat(0, 360);
        const axis = rl.math.vector3Normalize(.{ .x = ax, .y = ay, .z = az });
        const angle = randomFloat(0, 180) * rl.deg2rad;
        const rotation = rl.math.matrixRotate(axis, angle);

        transform.* = rl.math.matrixMultiply(rotation, translation);
    }

    // Load lighting shader
    const shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/lighting_instancing.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/lighting.fs", .{glsl_version}),
    );
    // Get shader locations
    shader.loc(.matrix_mvp).* = rl.getShaderLocation(shader, "mvp");
    shader.loc(.vector_view).* = rl.getShaderLocation(shader, "viewPos");

    // Set shader value: ambient light level
    const ambient_loc = rl.getShaderLocation(shader, "ambient");
    rl.setShaderValue(shader, ambient_loc, &[4]f32{ 0.2, 0.2, 0.2, 1.0 }, .vec4);

    // Create one light
    _ = rlights.createLight(.directional, .{ .x = 50.0, .y = 50.0, .z = 0.0 }, rl.math.vector3Zero(), .white, shader);

    // NOTE: We are assigning the intancing shader to material.shader
    // to be used on mesh drawing with drawMeshInstanced()
    var mat_instances = rl.loadMaterialDefault();
    defer rl.unloadMaterial(mat_instances); // Also unloads the instancing shader
    mat_instances.shader = shader;
    mat_instances.map(.diffuse).color = .red;

    // Load default material (using raylib intenral default shader) for non-instanced mesh drawing
    // WARNING: Default shader enables vertex color attribute BUT genMeshCube() does not generate vertex colors, so,
    // when drawing the color attribute is disabled and a default color value is provided as input for thevertex attribute
    const mat_default = rl.loadMaterialDefault();
    defer rl.unloadMaterial(mat_default); // Unload default material
    mat_default.map(.diffuse).color = .blue;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        // Update the light shader with the camera view position
        rl.setShaderValue(shader, shader.loc(.vector_view).*, &camera.position, .vec3);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            // Draw cube mesh with default material (BLUE)
            rl.drawMesh(cube, mat_default, rl.math.matrixTranslate(-10.0, 0.0, 0.0));

            // Draw meshes instanced using material containing instancing shader (RED + lighting),
            // transforms[] for the instances should be provided, they are dynamically
            // updated in GPU every frame, so we can animate the different mesh instances
            rl.drawMeshInstanced(cube, mat_instances, transforms);

            // Draw cube mesh with default material (BLUE)
            rl.drawMesh(cube, mat_default, rl.math.matrixTranslate(10.0, 0.0, 0.0));
        }

        rl.drawFPS(10, 10);
    }
}
