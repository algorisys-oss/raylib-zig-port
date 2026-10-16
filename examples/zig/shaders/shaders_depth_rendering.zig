//! raylib [shaders] example - depth rendering
//!
//! Zig-API translation of examples/shaders/shaders_depth_rendering.c (raylib 6.2).
//! Example contributed by Luís Almeida (@luis605) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Luís Almeida (@luis605)

const rl = @import("raylib");

const glsl_version = 330; // Desktop GLSL version

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - depth rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 4.0, .y = 1.0, .z = 5.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    // Load render texture with a depth texture attached
    const target = try loadRenderTextureDepthTex(screen_width, screen_height);
    defer unloadRenderTextureDepthTex(target);

    // Load depth shader and get depth texture shader location
    const depth_shader = try rl.loadShader(null, rl.textFormat("resources/shaders/glsl{d}/depth_render.fs", .{glsl_version}));
    defer rl.unloadShader(depth_shader); // Unload shader
    const depth_loc = rl.getShaderLocation(depth_shader, "depthTexture");
    const flip_texture_loc = rl.getShaderLocation(depth_shader, "flipY");
    rl.setShaderValue(depth_shader, flip_texture_loc, 1); // Flip Y texture

    // Load scene models
    const cube = try rl.loadModelFromMesh(rl.genMeshCube(1.0, 1.0, 1.0));
    defer rl.unloadModel(cube); // Unload model
    const floor = try rl.loadModelFromMesh(rl.genMeshPlane(20.0, 20.0, 1, 1));
    defer rl.unloadModel(floor); // Unload model

    rl.disableCursor(); // Limit cursor to relative movement inside the window

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .free);

        // Draw
        {
            rl.beginTextureMode(target);
            defer rl.endTextureMode();

            rl.clearBackground(.white);

            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(cube, .{ .x = 0.0, .y = 0.0, .z = 0.0 }, 3.0, .yellow);
            rl.drawModel(floor, .{ .x = 10.0, .y = 0.0, .z = 2.0 }, 2.0, .red);
        }

        // Draw into screen (main framebuffer)
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginShaderMode(depth_shader);
            defer rl.endShaderMode();

            rl.setShaderValueTexture(depth_shader, depth_loc, target.depth);
            rl.drawTexture(target.depth, 0, 0, .white);
        }

        rl.drawRectangle(10, 10, 320, 93, rl.fade(.sky_blue, 0.5));
        rl.drawRectangleLines(10, 10, 320, 93, .blue);

        rl.drawText("Camera Controls:", 20, 20, 10, .black);
        rl.drawText("- WASD to move", 40, 40, 10, .dark_gray);
        rl.drawText("- Mouse Wheel Pressed to Pan", 40, 60, 10, .dark_gray);
        rl.drawText("- Z to zoom to (0, 0, 0)", 40, 80, 10, .dark_gray);
    }
}

/// Load custom render texture, create a writable depth texture buffer
fn loadRenderTextureDepthTex(width: i32, height: i32) error{LoadFailed}!rl.RenderTexture2D {
    const id = rl.gl.loadFramebuffer(); // Load an empty framebuffer
    if (id == 0) {
        rl.traceLog(.warning, "FBO: Framebuffer object can not be created", .{});
        return error.LoadFailed;
    }

    rl.gl.enableFramebuffer(id);
    defer rl.gl.disableFramebuffer();

    const target: rl.RenderTexture2D = .{
        .id = id,
        // Create color texture (default to RGBA)
        .texture = .{
            .id = rl.gl.loadTexture(null, width, height, rl.gl.pixelformat_uncompressed_r8g8b8a8, 1),
            .width = width,
            .height = height,
            .mipmaps = 1,
            .format = .uncompressed_r8g8b8a8,
        },
        // Create depth texture buffer (instead of raylib default renderbuffer)
        .depth = .{
            .id = rl.gl.loadTextureDepth(width, height, false),
            .width = width,
            .height = height,
            .mipmaps = 1,
            .format = @fromBackingInt(@intCast(19)), // DEPTH_COMPONENT_24BIT: Not defined in raylib
        },
    };

    // Attach color texture and depth texture to FBO
    rl.gl.framebufferAttach(target.id, target.texture.id, rl.gl.attachment_color_channel0, rl.gl.attachment_texture2d, 0);
    rl.gl.framebufferAttach(target.id, target.depth.id, rl.gl.attachment_depth, rl.gl.attachment_texture2d, 0);

    // Check if fbo is complete with attachments (valid)
    if (rl.gl.framebufferComplete(target.id)) rl.traceLog(.info, "FBO: [ID {d}] Framebuffer object created successfully", .{target.id});

    return target;
}

/// Unload render texture from GPU memory (VRAM)
fn unloadRenderTextureDepthTex(target: rl.RenderTexture2D) void {
    // Color texture attached to FBO is deleted
    rl.gl.unloadTexture(target.texture.id);
    rl.gl.unloadTexture(target.depth.id);

    // NOTE: Depth texture is automatically
    // queried and deleted before deleting framebuffer
    rl.gl.unloadFramebuffer(target.id);
}
