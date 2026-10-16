//! raylib [models] example - skybox rendering
//!
//! Zig-API translation of examples/models/models_skybox_rendering.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330; // Desktop GLSL version

// Set this to true to use an HDR Texture
// NOTE: raylib must be built with HDR Support for this to work: SUPPORT_FILEFORMAT_HDR
const use_hdr = false;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - skybox rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 1.0, .y = 1.0, .z = 1.0 }, // Camera position
        .target = .{ .x = 4.0, .y = 1.0, .z = 4.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load skybox model
    const cube = rl.genMeshCube(1.0, 1.0, 1.0);
    const skybox = try rl.loadModelFromMesh(cube);
    defer rl.unloadModel(skybox); // Unload skybox model
    const material = &skybox.materials.?[0];

    // Load skybox shader and set required locations
    // NOTE: Some locations are automatically set at shader loading
    material.shader = try rl.loadShader(
        rl.textFormat("resources/shaders/glsl{d}/skybox.vs", .{glsl_version}),
        rl.textFormat("resources/shaders/glsl{d}/skybox.fs", .{glsl_version}),
    );
    defer rl.unloadShader(material.shader);

    const gamma: i32 = @intFromBool(use_hdr);
    rl.setShaderValue(material.shader, rl.getShaderLocation(material.shader, "environmentMap"), @as(i32, @backingInt(rl.MaterialMapIndex.cubemap)));
    rl.setShaderValue(material.shader, rl.getShaderLocation(material.shader, "doGamma"), gamma);
    rl.setShaderValue(material.shader, rl.getShaderLocation(material.shader, "vflipped"), gamma);

    // Load cubemap shader and setup required shader locations
    const shdr_cubemap = try rl.loadShader(
        rl.textFormat("resources/shaders/glsl{d}/cubemap.vs", .{glsl_version}),
        rl.textFormat("resources/shaders/glsl{d}/cubemap.fs", .{glsl_version}),
    );
    defer rl.unloadShader(shdr_cubemap);

    rl.setShaderValue(shdr_cubemap, rl.getShaderLocation(shdr_cubemap, "equirectangularMap"), 0);

    var skybox_file_name = std.mem.zeroes([256:0]u8);

    const cubemap = &material.map(.cubemap).texture;
    if (use_hdr) {
        _ = rl.textCopy(&skybox_file_name, "resources/dresden_square_2k.hdr");
        cubemap.* = try loadSkyboxCubemap(shdr_cubemap, std.mem.sliceTo(&skybox_file_name, 0));
    } else {
        // TODO: WARNING: On PLATFORM_WEB it requires a big amount of memory to process input image
        // and generate the required cubemap image to be passed to rlLoadTextureCubemap()
        cubemap.* = try loadSkyboxCubemap(shdr_cubemap, "resources/skybox.png");
    }
    defer rl.unloadTexture(cubemap.*);

    rl.disableCursor(); // Limit cursor to relative movement inside the window

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .first_person);

        // Load new cubemap texture on drag&drop
        if (rl.isFileDropped()) {
            const dropped_files = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(dropped_files); // Unload filepaths from memory

            if (dropped_files.count == 1) { // Only support one file dropped
                const path = std.mem.span(dropped_files.paths.?[0]);
                if (rl.isFileExtension(path, ".png;.jpg;.hdr;.bmp;.tga")) {
                    // Unload current cubemap texture to load new one
                    rl.unloadTexture(cubemap.*);
                    cubemap.* = try loadSkyboxCubemap(shdr_cubemap, path);

                    _ = rl.textCopy(&skybox_file_name, path);
                }
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            // We are inside the cube, we need to disable backface culling!
            rl.gl.disableBackfaceCulling();
            rl.gl.disableDepthMask();
            rl.drawModel(skybox, .{ .x = 0, .y = 0, .z = 0 }, 1.0, .white);
            rl.gl.enableBackfaceCulling();
            rl.gl.enableDepthMask();

            rl.drawGrid(10, 1.0);
        }

        const file_name = rl.getFileName(std.mem.sliceTo(&skybox_file_name, 0));
        if (use_hdr) {
            rl.drawText(rl.textFormat("Panorama image from hdrihaven.com: {s}", .{file_name}), 10, rl.getScreenHeight() - 20, 10, .black);
        } else {
            rl.drawText(rl.textFormat(": {s}", .{file_name}), 10, rl.getScreenHeight() - 20, 10, .black);
        }

        rl.drawFPS(10, 10);
    }
}

/// Load the skybox cubemap from an image file: an HDR panorama is converted
/// with the cubemap shader (use_hdr), any other image is a cubemap layout.
fn loadSkyboxCubemap(shdr_cubemap: rl.Shader, file_name: [:0]const u8) !rl.TextureCubemap {
    if (use_hdr) {
        // Load HDR panorama (sphere) texture
        const panorama = try rl.loadTexture(file_name);
        defer rl.unloadTexture(panorama); // Texture not required anymore, cubemap already generated

        // Generate cubemap (texture with 6 quads-cube-mapping) from panorama HDR texture
        // NOTE 1: New texture is generated rendering to texture, shader calculates the sphere->cube coordinates mapping
        // NOTE 2: It seems on some Android devices WebGL, fbo does not properly support a FLOAT-based attachment,
        // despite texture can be successfully created.. so using PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 instead of PIXELFORMAT_UNCOMPRESSED_R32G32B32A32
        return genTextureCubemap(shdr_cubemap, panorama, 1024, .uncompressed_r8g8b8a8);
    } else {
        const image = try rl.loadImage(file_name);
        defer rl.unloadImage(image);
        return rl.loadTextureCubemap(image, .auto_detect);
    }
}

/// Generate cubemap texture from HDR texture
fn genTextureCubemap(shader: rl.Shader, panorama: rl.Texture2D, size: i32, format: rl.PixelFormat) rl.TextureCubemap {
    rl.gl.disableBackfaceCulling(); // Disable backface culling to render inside the cube

    // STEP 1: Setup framebuffer
    const rbo = rl.gl.loadTextureDepth(size, size, true);
    const cubemap: rl.TextureCubemap = .{
        .id = rl.gl.loadTextureCubemap(null, size, @backingInt(format), 1),
        .width = size,
        .height = size,
        .mipmaps = 1,
        .format = format,
    };

    const fbo = rl.gl.loadFramebuffer();
    rl.gl.framebufferAttach(fbo, rbo, rl.gl.attachment_depth, rl.gl.attachment_renderbuffer, 0);
    rl.gl.framebufferAttach(fbo, cubemap.id, rl.gl.attachment_color_channel0, rl.gl.attachment_cubemap_positive_x, 0);

    // Check if framebuffer is complete with attachments (valid)
    if (rl.gl.framebufferComplete(fbo)) rl.traceLog(.info, "FBO: [ID {d}] Framebuffer object created successfully", .{fbo});

    // STEP 2: Draw to framebuffer
    // NOTE: Shader is used to convert HDR equirectangular environment map to cubemap equivalent (6 faces)
    rl.gl.enableShader(shader.id);

    // Define projection matrix and send it to shader
    const mat_fbo_projection = rl.math.matrixPerspective(90.0 * @as(f64, rl.deg2rad), 1.0, rl.gl.getCullDistanceNear(), rl.gl.getCullDistanceFar());
    rl.gl.setUniformMatrix(shader.loc(.matrix_projection).*, mat_fbo_projection);

    // Define view matrix for every side of the cubemap
    const origin: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const fbo_views = [6]rl.Matrix{
        rl.math.matrixLookAt(origin, .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .{ .x = 0.0, .y = -1.0, .z = 0.0 }),
        rl.math.matrixLookAt(origin, .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .{ .x = 0.0, .y = -1.0, .z = 0.0 }),
        rl.math.matrixLookAt(origin, .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .{ .x = 0.0, .y = 0.0, .z = 1.0 }),
        rl.math.matrixLookAt(origin, .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .{ .x = 0.0, .y = 0.0, .z = -1.0 }),
        rl.math.matrixLookAt(origin, .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .{ .x = 0.0, .y = -1.0, .z = 0.0 }),
        rl.math.matrixLookAt(origin, .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .{ .x = 0.0, .y = -1.0, .z = 0.0 }),
    };

    rl.gl.viewport(0, 0, size, size); // Set viewport to current fbo dimensions

    // Activate and enable texture for drawing to cubemap faces
    rl.gl.activeTextureSlot(0);
    rl.gl.enableTexture(panorama.id);

    for (fbo_views, 0..) |view, face| {
        // Set the view matrix for the current cube face
        rl.gl.setUniformMatrix(shader.loc(.matrix_view).*, view);

        // Select the current cubemap face attachment for the fbo
        // WARNING: This function by default enables->attach->disables fbo!!!
        rl.gl.framebufferAttach(fbo, cubemap.id, rl.gl.attachment_color_channel0, rl.gl.attachment_cubemap_positive_x + @as(i32, @intCast(face)), 0);
        rl.gl.enableFramebuffer(fbo);

        // Load and draw a cube, it uses the current enabled texture
        rl.gl.clearScreenBuffers();
        rl.gl.loadDrawCube();
    }

    // STEP 3: Unload framebuffer and reset state
    rl.gl.disableShader(); // Unbind shader
    rl.gl.disableTexture(); // Unbind texture
    rl.gl.disableFramebuffer(); // Unbind framebuffer
    rl.gl.unloadFramebuffer(fbo); // Unload framebuffer (and automatically attached depth texture/renderbuffer)

    // Reset viewport dimensions to default
    rl.gl.viewport(0, 0, rl.gl.getFramebufferWidth(), rl.gl.getFramebufferHeight());
    rl.gl.enableBackfaceCulling();

    return cubemap;
}
