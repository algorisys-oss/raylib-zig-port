//! raylib [shaders] example - basic lighting
//!
//! Zig-API translation of examples/shaders/shaders_basic_lighting.c (raylib 6.2).
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
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - basic lighting");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 2.0, .y = 4.0, .z = 6.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.5, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load basic lighting shader
    const shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/lighting.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/lighting.fs", .{glsl_version}),
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

    // Create lights
    var lights = [rlights.max_lights]rlights.Light{
        rlights.createLight(.point, .{ .x = -2, .y = 1, .z = -2 }, rl.math.vector3Zero(), .yellow, shader),
        rlights.createLight(.point, .{ .x = 2, .y = 1, .z = 2 }, rl.math.vector3Zero(), .red, shader),
        rlights.createLight(.point, .{ .x = -2, .y = 1, .z = 2 }, rl.math.vector3Zero(), .green, shader),
        rlights.createLight(.point, .{ .x = 2, .y = 1, .z = -2 }, rl.math.vector3Zero(), .blue, shader),
    };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        // Update the shader with the camera view vector (points towards { 0.0f, 0.0f, 0.0f })
        rl.setShaderValue(shader, shader.loc(.vector_view).*, camera.position);

        // Check key inputs to enable/disable lights
        for (&lights, [_]rl.KeyboardKey{ .y, .r, .g, .b }) |*light, key| {
            if (rl.isKeyPressed(key)) light.enabled = !light.enabled;
        }

        // Update light values (actually, only enable/disable them)
        for (lights) |light| light.update(shader);

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

                rl.drawPlane(rl.math.vector3Zero(), .{ .x = 10.0, .y = 10.0 }, .white);
                rl.drawCube(rl.math.vector3Zero(), 2.0, 4.0, 2.0, .white);
            }

            // Draw spheres to show where the lights are
            for (lights) |light| {
                if (light.enabled) {
                    rl.drawSphereEx(light.position, 0.2, 8, 8, light.color);
                } else {
                    rl.drawSphereWires(light.position, 0.2, 8, 8, rl.colorAlpha(light.color, 0.3));
                }
            }

            rl.drawGrid(10, 1.0);
        }

        rl.drawFPS(10, 10);

        rl.drawText("Use keys [Y][R][G][B] to toggle lights", 10, 40, 20, .dark_gray);
    }
}
