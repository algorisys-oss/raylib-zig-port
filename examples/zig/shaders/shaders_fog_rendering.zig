//! raylib [shaders] example - fog rendering
//!
//! Zig-API translation of examples/shaders/shaders_fog_rendering.c (raylib 6.2).
//! Example contributed by Chris Camacho (@chriscamacho) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Chris Camacho (@chriscamacho) and Ramon Santamaria (@raysan5)
//!
//! NOTE: Shaders used in this example are #version 330 (OpenGL 3.3).

const std = @import("std");
const rl = @import("raylib");
const rlights = @import("rlights");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true }); // Enable Multi Sampling Anti Aliasing 4x (if available)
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - fog rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 2.0, .y = 2.0, .z = 6.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.5, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load models and texture
    var model_a = try rl.loadModelFromMesh(rl.genMeshTorus(0.4, 1.0, 16, 32));
    defer rl.unloadModel(model_a);
    const model_b = try rl.loadModelFromMesh(rl.genMeshCube(1.0, 1.0, 1.0));
    defer rl.unloadModel(model_b);
    const model_c = try rl.loadModelFromMesh(rl.genMeshSphere(0.5, 32, 32));
    defer rl.unloadModel(model_c);
    const texture = try rl.loadTexture("resources/texel_checker.png");
    defer rl.unloadTexture(texture);

    // Load shader and set up some uniforms
    const shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/lighting.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/fog.fs", .{glsl_version}),
    );
    defer rl.unloadShader(shader);
    shader.loc(.matrix_model).* = rl.getShaderLocation(shader, "matModel");
    shader.loc(.vector_view).* = rl.getShaderLocation(shader, "viewPos");

    // Ambient light level
    const ambient: rl.Vector4 = .{ .x = 0.2, .y = 0.2, .z = 0.2, .w = 1.0 };
    const ambient_loc = rl.getShaderLocation(shader, "ambient");
    rl.setShaderValue(shader, ambient_loc, ambient);

    const fog_color = rl.colorNormalize(.gray);
    const fog_color_loc = rl.getShaderLocation(shader, "fogColor");
    rl.setShaderValue(shader, fog_color_loc, fog_color);

    var fog_density: f32 = 0.15;
    const fog_density_loc = rl.getShaderLocation(shader, "fogDensity");
    rl.setShaderValue(shader, fog_density_loc, fog_density);

    // Assign texture to default model material
    // NOTE: All models share the same shader
    for ([_]rl.Model{ model_a, model_b, model_c }) |model| {
        const material = &model.materials.?[0];
        material.map(.diffuse).texture = texture;
        material.shader = shader;
    }

    // Using just 1 point lights
    _ = rlights.createLight(.point, .{ .x = 0, .y = 2, .z = 6 }, rl.math.vector3Zero(), .white, shader);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        if (rl.isKeyDown(.up)) {
            fog_density += 0.001;
            if (fog_density > 1.0) fog_density = 1.0;
        }

        if (rl.isKeyDown(.down)) {
            fog_density -= 0.001;
            if (fog_density < 0.0) fog_density = 0.0;
        }

        rl.setShaderValue(shader, fog_density_loc, fog_density);

        // Rotate the torus
        model_a.transform = rl.math.matrixMultiply(model_a.transform, rl.math.matrixRotateX(-0.025));
        model_a.transform = rl.math.matrixMultiply(model_a.transform, rl.math.matrixRotateZ(0.012));

        // Update the light shader with the camera view position
        rl.setShaderValue(shader, shader.loc(.vector_view).*, camera.position);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.gray);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            // Draw the three models
            rl.drawModel(model_a, rl.math.vector3Zero(), 1.0, .white);
            rl.drawModel(model_b, .{ .x = -2.6, .y = 0, .z = 0 }, 1.0, .white);
            rl.drawModel(model_c, .{ .x = 2.6, .y = 0, .z = 0 }, 1.0, .white);

            var i: i32 = -20;
            while (i < 20) : (i += 2) rl.drawModel(model_a, .{ .x = @floatFromInt(i), .y = 0, .z = 2 }, 1.0, .white);
        }

        rl.drawText(rl.textFormat("Use KEY_UP/KEY_DOWN to change fog density [{d:.2}]", .{fog_density}), 10, 10, 20, .ray_white);
    }
}
