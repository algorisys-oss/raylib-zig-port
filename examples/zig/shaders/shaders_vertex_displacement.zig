//! raylib [shaders] example - vertex displacement
//!
//! Zig-API translation of examples/shaders/shaders_vertex_displacement.c (raylib 6.2).
//! Example contributed by Alex ZH (@ZzzhHe) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 Alex ZH (@ZzzhHe)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - vertex displacement");
    defer rl.closeWindow(); // Close window and OpenGL context

    // set up camera
    var camera: rl.Camera = .{
        .position = .{ .x = 20.0, .y = 5.0, .z = -20.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 60.0,
        .projection = .perspective,
    };

    // Load vertex and fragment shaders
    const shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/vertex_displacement.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/vertex_displacement.fs", .{glsl_version}),
    );
    defer rl.unloadShader(shader);

    // Load perlin noise texture
    const perlin_noise_image = rl.genImagePerlinNoise(512, 512, 0, 0, 1.0);
    const perlin_noise_map = try rl.loadTextureFromImage(perlin_noise_image);
    defer rl.unloadTexture(perlin_noise_map);
    rl.unloadImage(perlin_noise_image);

    // Set shader uniform location
    const perlin_noise_map_loc = rl.getShaderLocation(shader, "perlinNoiseMap");
    rl.gl.enableShader(shader.id);
    rl.gl.activeTextureSlot(1);
    rl.gl.enableTexture(perlin_noise_map.id);
    rl.gl.setUniformSampler(perlin_noise_map_loc, 1);

    // Create a plane mesh and model
    const plane_model = try rl.loadModelFromMesh(rl.genMeshPlane(50, 50, 50, 50));
    defer rl.unloadModel(plane_model);
    // Set plane model material
    plane_model.materials.?[0].shader = shader;

    var time: f32 = 0.0;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .free); // Update camera

        time += rl.getFrameTime(); // Update time variable
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "time"), &time, .float); // Send time value to shader

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.beginShaderMode(shader);
            defer rl.endShaderMode();

            // Draw plane model
            rl.drawModel(plane_model, .{ .x = 0.0, .y = 0.0, .z = 0.0 }, 1.0, .white);
        }

        rl.drawText("Vertex displacement", 10, 10, 20, .dark_gray);
        rl.drawFPS(10, 40);
    }
}
