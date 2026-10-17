//! raylib [shaders] example - model shader
//!
//! Zig-API translation of examples/shaders/shaders_model_shader.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)
//!
//! NOTE: Shaders used in this example are #version 330 (OpenGL 3.3).

const std = @import("std");
const rl = @import("raylib");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true }); // Enable Multi Sampling Anti Aliasing 4x (if available)

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - model shader");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 4.0, .y = 4.0, .z = 4.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 1.0, .z = -1.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const model = try rl.loadModel("resources/models/watermill.obj"); // Load OBJ model
    defer rl.unloadModel(model);
    const texture = try rl.loadTexture("resources/models/watermill_diffuse.png"); // Load model texture
    defer rl.unloadTexture(texture);

    // Load shader for model
    // NOTE: Defining null for vertex shader forces usage of internal default vertex shader
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/grayscale.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    const material = &model.materials.?[0];
    material.shader = shader; // Set shader effect to 3d model
    material.map(.diffuse).texture = texture; // Bind texture to model

    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model position

    rl.disableCursor(); // Limit cursor to relative movement inside the window
    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .free);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(model, position, 0.2, .white); // Draw 3d model with texture
            rl.drawGrid(10, 1.0); // Draw a grid
        }

        rl.drawText("(c) Watermill 3D model by Alberto Cano", screen_width - 210, screen_height - 20, 10, .gray);
        rl.drawFPS(10, 10);
    }
}
