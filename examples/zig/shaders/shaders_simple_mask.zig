//! raylib [shaders] example - simple mask
//!
//! Zig-API translation of examples/shaders/shaders_simple_mask.c (raylib 6.2).
//! Example contributed by Chris Camacho (@chriscamacho) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Chris Camacho (@chriscamacho) and Ramon Santamaria (@raysan5)
//!
//! After a model is loaded it has a default material, this material can be
//! modified in place rather than creating one from scratch...
//! While all of the maps have particular names, they can be used for any purpose
//! except for three maps that are applied as cubic maps (see below)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - simple mask");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 0.0, .y = 1.0, .z = 2.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Define our three models to show the shader on
    const torus = rl.genMeshTorus(0.3, 1, 16, 32);
    var model1 = try rl.loadModelFromMesh(torus);
    defer rl.unloadModel(model1);

    const cube = rl.genMeshCube(0.8, 0.8, 0.8);
    const model2 = try rl.loadModelFromMesh(cube);
    defer rl.unloadModel(model2);

    // Generate model to be shaded just to see the gaps in the other two
    const sphere = rl.genMeshSphere(1, 16, 16);
    const model3 = try rl.loadModelFromMesh(sphere);
    defer rl.unloadModel(model3);

    // Load the shader
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/mask.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    // Load and apply the diffuse texture (colour map)
    const tex_diffuse = try rl.loadTexture("resources/plasma.png");
    defer rl.unloadTexture(tex_diffuse); // Unload default diffuse texture
    model1.materials.?[0].map(.diffuse).texture = tex_diffuse;
    model2.materials.?[0].map(.diffuse).texture = tex_diffuse;

    // Using MATERIAL_MAP_EMISSION as a spare slot to use for 2nd texture
    // NOTE: Don't use MATERIAL_MAP_IRRADIANCE, MATERIAL_MAP_PREFILTER or  MATERIAL_MAP_CUBEMAP as they are bound as cube maps
    const tex_mask = try rl.loadTexture("resources/mask.png");
    defer rl.unloadTexture(tex_mask); // Unload texture mask
    model1.materials.?[0].map(.emission).texture = tex_mask;
    model2.materials.?[0].map(.emission).texture = tex_mask;
    shader.loc(.map_emission).* = rl.getShaderLocation(shader, "mask");

    // Frame is incremented each frame to animate the shader
    const shader_frame = rl.getShaderLocation(shader, "frame");

    // Apply the shader to the two models
    model1.materials.?[0].shader = shader;
    model2.materials.?[0].shader = shader;

    var frames_counter: i32 = 0;
    var rotation: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 }; // Model rotation angles

    rl.disableCursor(); // Limit cursor to relative movement inside the window
    rl.setTargetFPS(60); // Set  to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .first_person);

        frames_counter += 1;
        rotation.x += 0.01;
        rotation.y += 0.005;
        rotation.z -= 0.0025;

        // Send frames counter to shader for animation
        rl.setShaderValue(shader, shader_frame, &frames_counter, .int);

        // Rotate one of the models
        model1.transform = rl.math.matrixRotateXYZ(rotation);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.dark_blue);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(model1, .{ .x = 0.5, .y = 0.0, .z = 0.0 }, 1, .white);
            rl.drawModelEx(model2, .{ .x = -0.5, .y = 0.0, .z = 0.0 }, .{ .x = 1.0, .y = 1.0, .z = 0.0 }, 50, .{ .x = 1.0, .y = 1.0, .z = 1.0 }, .white);
            rl.drawModel(model3, .{ .x = 0.0, .y = 0.0, .z = -1.5 }, 1, .white);
            rl.drawGrid(10, 1.0); // Draw a grid
        }

        rl.drawRectangle(16, 698, rl.measureText(rl.textFormat("Frame: {d}", .{frames_counter}), 20) + 8, 42, .blue);
        rl.drawText(rl.textFormat("Frame: {d}", .{frames_counter}), 20, 700, 20, .white);

        rl.drawFPS(10, 10);
    }
}
