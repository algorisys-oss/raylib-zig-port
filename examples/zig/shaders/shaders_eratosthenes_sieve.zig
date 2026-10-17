//! raylib [shaders] example - eratosthenes sieve
//!
//! Zig-API translation of examples/shaders/shaders_eratosthenes_sieve.c (raylib 6.2).
//!
//! NOTE: Sieve of Eratosthenes, the earliest known (ancient Greek) prime number sieve
//!
//!     "Sift the twos and sift the threes,
//!      The Sieve of Eratosthenes.
//!      When the multiples sublime,
//!      the numbers that are left are prime."
//!
//! Example contributed by ProfJski (@ProfJski) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 ProfJski (@ProfJski) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - eratosthenes sieve");
    defer rl.closeWindow(); // Close window and OpenGL context

    const target = try rl.loadRenderTexture(screen_width, screen_height);
    defer rl.unloadRenderTexture(target);

    // Load Eratosthenes shader
    // NOTE: Defining null for vertex shader forces usage of internal default vertex shader
    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/eratosthenes.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Nothing to do here, everything is happening in the shader

        // Draw
        {
            rl.beginTextureMode(target); // Enable drawing to texture
            defer rl.endTextureMode(); // End drawing to texture (now we have a blank texture available for the shader)

            rl.clearBackground(.black); // Clear the render texture

            // Draw a rectangle in shader mode to be used as shader canvas
            // NOTE: Rectangle uses font white character texture coordinates,
            // so shader can not be applied here directly because input vertexTexCoord
            // do not represent full screen coordinates (space where want to apply shader)
            rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), .black);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white); // Clear screen background

        rl.beginShaderMode(shader);
        defer rl.endShaderMode();

        // NOTE: Render texture must be y-flipped due to default OpenGL coordinates (left-bottom)
        const source: rl.Rectangle = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(target.texture.width),
            .height = @floatFromInt(-target.texture.height),
        };
        rl.drawTextureRec(target.texture, source, .{ .x = 0.0, .y = 0.0 }, .white);
    }
}
