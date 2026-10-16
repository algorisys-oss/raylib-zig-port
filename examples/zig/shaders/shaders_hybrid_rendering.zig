//! raylib [shaders] example - hybrid rendering
//!
//! Zig-API translation of examples/shaders/shaders_hybrid_rendering.c (raylib 6.2).
//! Example contributed by Buğra Alptekin Sarı (@BugraAlptekinSari) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2022-2025 Buğra Alptekin Sarı (@BugraAlptekinSari)

const rl = @import("raylib");

const glsl_version = 330; // Desktop GLSL version

/// Ray march shader uniform locations
const RayLocs = struct {
    cam_pos: i32,
    cam_dir: i32,
    screen_center: i32,
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - hybrid rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    // This Shader calculates pixel depth and color using raymarch
    const shdr_raymarch = try rl.loadShader(null, rl.textFormat("resources/shaders/glsl{d}/hybrid_raymarch.fs", .{glsl_version}));
    defer rl.unloadShader(shdr_raymarch);

    // This Shader is a standard rasterization fragment shader with the addition of depth writing
    // You are required to write depth for all shaders if one shader does it
    const shdr_raster = try rl.loadShader(null, rl.textFormat("resources/shaders/glsl{d}/hybrid_raster.fs", .{glsl_version}));
    defer rl.unloadShader(shdr_raster);

    // Fill the struct with shader locs
    const march_locs: RayLocs = .{
        .cam_pos = rl.getShaderLocation(shdr_raymarch, "camPos"),
        .cam_dir = rl.getShaderLocation(shdr_raymarch, "camDir"),
        .screen_center = rl.getShaderLocation(shdr_raymarch, "screenCenter"),
    };

    // Transfer screenCenter position to shader. Which is used to calculate ray direction
    const screen_center: rl.Vector2 = .{ .x = screen_width / 2.0, .y = screen_height / 2.0 };
    rl.setShaderValue(shdr_raymarch, march_locs.screen_center, &screen_center, .vec2);

    // Use Customized function to create writable depth texture buffer
    const target = try loadRenderTextureDepthTex(screen_width, screen_height);
    defer unloadRenderTextureDepthTex(target);

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 0.5, .y = 1.0, .z = 1.5 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.5, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Camera FOV is pre-calculated in the camera distance
    const cam_dist = 1.0 / @tan(camera.fovy * 0.5 * rl.deg2rad);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        // Update Camera Postion in the ray march shader
        rl.setShaderValue(shdr_raymarch, march_locs.cam_pos, &camera.position, .vec3);

        // Update Camera Looking Vector. Vector length determines FOV
        const cam_dir = rl.math.vector3Scale(rl.math.vector3Normalize(rl.math.vector3Subtract(camera.target, camera.position)), cam_dist);
        rl.setShaderValue(shdr_raymarch, march_locs.cam_dir, &cam_dir, .vec3);

        // Draw
        // Draw into our custom render texture (framebuffer)
        {
            rl.beginTextureMode(target);
            defer rl.endTextureMode();

            rl.clearBackground(.white);

            // Raymarch Scene
            rl.gl.enableDepthTest(); // Manually enable Depth Test to handle multiple rendering methods
            {
                rl.beginShaderMode(shdr_raymarch);
                defer rl.endShaderMode();

                rl.drawRectangleRec(.{ .x = 0, .y = 0, .width = screen_width, .height = screen_height }, .white);
            }

            // Rasterize Scene
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.beginShaderMode(shdr_raster);
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
            .format = @fromBackingInt(@intCast(19)), // DEPTH_COMPONENT_24BIT?
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
