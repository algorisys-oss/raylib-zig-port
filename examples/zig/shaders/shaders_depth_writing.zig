//! raylib [shaders] example - depth writing
//!
//! Zig-API translation of examples/shaders/shaders_depth_writing.c (raylib 6.2).
//! Example contributed by Buğra Alptekin Sarı (@BugraAlptekinSari) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2022-2025 Buğra Alptekin Sarı (@BugraAlptekinSari)

const rl = @import("raylib");

const glsl_version = 330; // Desktop GLSL version

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - depth writing");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 2.0, .y = 2.0, .z = 3.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.5, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load custom render texture with writable depth texture buffer
    const target = try loadRenderTextureDepthTex(screen_width, screen_height);
    defer unloadRenderTextureDepthTex(target);

    // Load depth writing shader
    // NOTE: The shader inverts the depth buffer by writing into it by `gl_FragDepth = 1 - gl_FragCoord.z;`
    const shader = try rl.loadShader(null, rl.textFormat("resources/shaders/glsl{d}/depth_write.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        // Draw
        // Draw into our custom render texture
        {
            rl.beginTextureMode(target);
            defer rl.endTextureMode();

            rl.clearBackground(.white);

            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.beginShaderMode(shader);
            defer rl.endShaderMode();

            rl.drawCubeWiresV(.{ .x = 0.0, .y = 0.5, .z = 1.0 }, .{ .x = 1.0, .y = 1.0, .z = 1.0 }, .red);
            rl.drawCubeV(.{ .x = 0.0, .y = 0.5, .z = 1.0 }, .{ .x = 1.0, .y = 1.0, .z = 1.0 }, .purple);
            rl.drawCubeWiresV(.{ .x = 0.0, .y = 0.5, .z = -1.0 }, .{ .x = 1.0, .y = 1.0, .z = 1.0 }, .dark_green);
            rl.drawCubeV(.{ .x = 0.0, .y = 0.5, .z = -1.0 }, .{ .x = 1.0, .y = 1.0, .z = 1.0 }, .yellow);
            rl.drawGrid(10, 1.0);
        }

        // Draw into screen our custom render texture
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawTextureRec(target.texture, .{ .x = 0, .y = 0, .width = screen_width, .height = -screen_height }, .{ .x = 0, .y = 0 }, .white);

        rl.drawFPS(10, 10);
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
