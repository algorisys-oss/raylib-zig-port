//! raylib [shaders] example - custom uniform
//!
//! Zig-API translation of examples/shaders/shaders_custom_uniform.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)
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

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - custom uniform");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 8.0, .y = 8.0, .z = 8.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 1.5, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const model = try rl.loadModel("resources/models/barracks.obj"); // Load OBJ model
    defer rl.unloadModel(model);
    const texture = try rl.loadTexture("resources/models/barracks_diffuse.png"); // Load model texture (diffuse map)
    defer rl.unloadTexture(texture);
    model.materials.?[0].map(.diffuse).texture = texture; // Set model diffuse texture

    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model position

    // Load postprocessing shader
    // NOTE: Defining null for vertex shader forces usage of internal default vertex shader
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/swirl.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    // Get variable (uniform) location on the shader to connect with the program
    // NOTE: If uniform variable could not be found in the shader, function returns -1
    const swirl_center_loc = rl.getShaderLocation(shader, "center");

    var swirl_center = [2]f32{ @as(f32, screen_width) / 2, @as(f32, screen_height) / 2 };

    // Create a RenderTexture2D to be used for render to texture
    const target = try rl.loadRenderTexture(screen_width, screen_height);
    defer rl.unloadRenderTexture(target);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        const mouse_position = rl.getMousePosition();

        swirl_center[0] = mouse_position.x;
        swirl_center[1] = screen_height - mouse_position.y;

        // Send new value to the shader to be used on drawing
        rl.setShaderValue(shader, swirl_center_loc, swirl_center);

        // Draw
        {
            rl.beginTextureMode(target); // Enable drawing to texture
            defer rl.endTextureMode(); // End drawing to texture (now we have a texture available for next passes)

            rl.clearBackground(.ray_white); // Clear texture background

            {
                rl.beginMode3D(camera); // Begin 3d mode drawing
                defer rl.endMode3D(); // End 3d mode drawing, returns to orthographic 2d mode

                rl.drawModel(model, position, 0.5, .white); // Draw 3d model with texture
                rl.drawGrid(10, 1.0); // Draw a grid
            }

            rl.drawText("TEXT DRAWN IN RENDER TEXTURE", 200, 10, 30, .red);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white); // Clear screen background

        {
            // Enable shader using the custom uniform
            rl.beginShaderMode(shader);
            defer rl.endShaderMode();

            // NOTE: Render texture must be y-flipped due to default OpenGL coordinates (left-bottom)
            const source: rl.Rectangle = .{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(target.texture.width),
                .height = @floatFromInt(-target.texture.height),
            };
            rl.drawTextureRec(target.texture, source, .{ .x = 0, .y = 0 }, .white);
        }

        // Draw some 2d text over drawn texture
        rl.drawText("(c) Barracks 3D model by Alberto Cano", screen_width - 220, screen_height - 20, 10, .gray);
        rl.drawFPS(10, 10);
    }
}
