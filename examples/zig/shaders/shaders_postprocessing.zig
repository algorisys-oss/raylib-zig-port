//! raylib [shaders] example - postprocessing
//!
//! Zig-API translation of examples/shaders/shaders_postprocessing.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)
//!
//! NOTE: Shaders used in this example are #version 330 (OpenGL 3.3).

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

/// A postprocessing effect: its display name and fragment shader file.
const Postpro = struct {
    name: [:0]const u8,
    file: [:0]const u8,
};

fn postpro(comptime name: [:0]const u8, comptime file: []const u8) Postpro {
    return .{ .name = name, .file = std.fmt.comptimePrint("resources/shaders/glsl{d}/{s}.fs", .{ glsl_version, file }) };
}

// NOTE: All postpro shader use the base vertex shader (DEFAULT_VERTEX_SHADER)
const postpro_shaders = [_]Postpro{
    postpro("GRAYSCALE", "grayscale"),
    postpro("POSTERIZATION", "posterization"),
    postpro("DREAM_VISION", "dream_vision"),
    postpro("PIXELIZER", "pixelizer"),
    postpro("CROSS_HATCHING", "cross_hatching"),
    postpro("CROSS_STITCHING", "cross_stitching"),
    postpro("PREDATOR_VIEW", "predator"),
    postpro("SCANLINES", "scanlines"),
    postpro("FISHEYE", "fisheye"),
    postpro("SOBEL", "sobel"),
    postpro("BLOOM", "bloom"),
    postpro("BLUR", "blur"),
    //postpro("FXAA", "fxaa"),
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true }); // Enable Multi Sampling Anti Aliasing 4x (if available)

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - postprocessing");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 2.0, .y = 3.0, .z = 2.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const model = try rl.loadModel("resources/models/church.obj"); // Load OBJ model
    defer rl.unloadModel(model);
    const texture = try rl.loadTexture("resources/models/church_diffuse.png"); // Load model texture (diffuse map)
    defer rl.unloadTexture(texture);
    model.materials.?[0].map(.diffuse).texture = texture; // Set model diffuse texture

    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model position

    // Load all postpro shaders
    // NOTE: Defining null for vertex shader forces usage of internal default vertex shader
    var shaders: [postpro_shaders.len]rl.Shader = undefined;
    for (&shaders, postpro_shaders) |*shader, fx| shader.* = try rl.loadShader(null, fx.file);
    defer for (shaders) |shader| rl.unloadShader(shader);

    var current_shader: usize = 0;

    // Create a RenderTexture2D to be used for render to texture
    const target = try rl.loadRenderTexture(screen_width, screen_height);
    defer rl.unloadRenderTexture(target);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        if (rl.isKeyPressed(.right)) {
            current_shader = (current_shader + 1) % shaders.len;
        } else if (rl.isKeyPressed(.left)) {
            current_shader = (current_shader + shaders.len - 1) % shaders.len;
        }

        // Draw
        {
            rl.beginTextureMode(target); // Enable drawing to texture
            defer rl.endTextureMode(); // End drawing to texture (now we have a texture available for next passes)

            rl.clearBackground(.ray_white); // Clear texture background

            rl.beginMode3D(camera); // Begin 3d mode drawing
            defer rl.endMode3D(); // End 3d mode drawing, returns to orthographic 2d mode

            rl.drawModel(model, position, 0.1, .white); // Draw 3d model with texture
            rl.drawGrid(10, 1.0); // Draw a grid
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white); // Clear screen background

        // Render generated texture using selected postprocessing shader
        {
            rl.beginShaderMode(shaders[current_shader]);
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

        // Draw 2d shapes and text over drawn texture
        rl.drawRectangle(0, 9, 580, 30, rl.fade(.light_gray, 0.7));

        rl.drawText("(c) Church 3D model by Alberto Cano", screen_width - 200, screen_height - 20, 10, .gray);
        rl.drawText("CURRENT POSTPRO SHADER:", 10, 15, 20, .black);
        rl.drawText(postpro_shaders[current_shader].name, 330, 15, 20, .red);
        rl.drawText("< >", 540, 10, 30, .dark_blue);
        rl.drawFPS(700, 15);
    }
}
