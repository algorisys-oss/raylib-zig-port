//! raylib [shaders] example - texture tiling
//!
//! Zig-API translation of examples/shaders/shaders_texture_tiling.c (raylib 6.2).
//! Example contributed by Luis Almeida (@luis605) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 Luis Almeida (@luis605)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - texture tiling");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera3D = .{
        .position = .{ .x = 4.0, .y = 4.0, .z = 4.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.5, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load a cube model
    const cube = rl.genMeshCube(1.0, 1.0, 1.0);
    const model = try rl.loadModelFromMesh(cube);
    defer rl.unloadModel(model);

    // Load a texture and assign to cube model
    const texture = try rl.loadTexture("resources/cubicmap_atlas.png");
    defer rl.unloadTexture(texture);
    const material = &model.materials.?[0];
    material.map(.diffuse).texture = texture;

    // Set the texture tiling using a shader
    const tiling = [2]f32{ 3.0, 3.0 };
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/tiling.fs", .{glsl_version}));
    defer rl.unloadShader(shader);
    rl.setTextureWrap(texture, .repeat);
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "tiling"), &tiling, .vec2);
    material.shader = shader;

    rl.disableCursor(); // Limit cursor to relative movement inside the window
    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .free);

        if (rl.isKeyPressed(.z)) camera.target = .{ .x = 0.0, .y = 0.5, .z = 0.0 };

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            {
                rl.beginShaderMode(shader);
                defer rl.endShaderMode();

                rl.drawModel(model, .{ .x = 0.0, .y = 0.0, .z = 0.0 }, 2.0, .white);
            }

            rl.drawGrid(10, 1.0);
        }

        rl.drawText("Use mouse to rotate the camera", 10, 10, 20, .dark_gray);
    }
}
