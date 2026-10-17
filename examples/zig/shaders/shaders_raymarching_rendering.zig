//! raylib [shaders] example - raymarching rendering
//!
//! Zig-API translation of examples/shaders/shaders_raymarching_rendering.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2018-2025 Ramon Santamaria (@raysan5)
//!
//! NOTE: This example requires raylib OpenGL 3.3 for shaders support and only #version 330
//! is currently supported. OpenGL ES 2.0 platforms are not supported at the moment.

const std = @import("std");
const rl = @import("raylib");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - raymarching rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    var camera: rl.Camera = .{
        .position = .{ .x = 2.5, .y = 2.5, .z = 3.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.7 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 65.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load raymarching shader
    // NOTE: Defining null for vertex shader forces usage of internal default vertex shader
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/raymarching.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    // Get shader locations for required uniforms
    const view_eye_loc = rl.getShaderLocation(shader, "viewEye");
    const view_center_loc = rl.getShaderLocation(shader, "viewCenter");
    const run_time_loc = rl.getShaderLocation(shader, "runTime");
    const resolution_loc = rl.getShaderLocation(shader, "resolution");

    var resolution = [2]f32{ screen_width, screen_height };
    rl.setShaderValue(shader, resolution_loc, resolution);

    var run_time: f32 = 0.0;

    rl.disableCursor(); // Limit cursor to relative movement inside the window
    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .first_person);

        const delta_time = rl.getFrameTime();
        run_time += delta_time;

        // Set shader required uniform values
        rl.setShaderValue(shader, view_eye_loc, camera.position);
        rl.setShaderValue(shader, view_center_loc, camera.target);
        rl.setShaderValue(shader, run_time_loc, run_time);

        // Check if screen is resized
        if (rl.isWindowResized()) {
            resolution = .{ @floatFromInt(rl.getScreenWidth()), @floatFromInt(rl.getScreenHeight()) };
            rl.setShaderValue(shader, resolution_loc, resolution);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // We only draw a white full-screen rectangle,
        // frame is generated in shader using raymarching
        {
            rl.beginShaderMode(shader);
            defer rl.endShaderMode();

            rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), .white);
        }

        rl.drawText("(c) Raymarching shader by Iñigo Quilez. MIT License.", rl.getScreenWidth() - 280, rl.getScreenHeight() - 20, 10, .black);
    }
}
