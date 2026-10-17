//! raylib [shaders] example - deferred rendering
//!
//! Zig-API translation of examples/shaders/shaders_deferred_rendering.c (raylib 6.2).
//! Example contributed by Justin Andreas Lacoste (@27justin) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 Justin Andreas Lacoste (@27justin)
//!
//! NOTE: This example requires raylib OpenGL 3.3 or OpenGL ES 3.0.

const std = @import("std");
const rl = @import("raylib");
const rlights = @import("rlights");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

const max_cubes = 30;

/// libc's `rand()`: the C example draws cube placement from it (not raylib's
/// GetRandomValue), so the same unseeded sequence is used here.
extern "c" fn rand() c_int;

/// GBuffer data
const GBuffer = struct {
    framebuffer_id: u32,

    position_texture_id: u32,
    normal_texture_id: u32,
    albedo_spec_texture_id: u32,

    depth_renderbuffer_id: u32,

    fn unload(g_buffer: GBuffer) void {
        // Unload geometry buffer and all attached textures
        rl.gl.unloadFramebuffer(g_buffer.framebuffer_id);
        rl.gl.unloadTexture(g_buffer.position_texture_id);
        rl.gl.unloadTexture(g_buffer.normal_texture_id);
        rl.gl.unloadTexture(g_buffer.albedo_spec_texture_id);
        rl.gl.unloadTexture(g_buffer.depth_renderbuffer_id);
    }
};

/// Deferred mode passes
const DeferredMode = enum {
    position,
    normal,
    albedo,
    shading,
};

/// A libc `rand() % n` draw, as f32
fn randFloat(n: c_int) f32 {
    return @floatFromInt(@rem(rand(), n));
}

/// Draw one G-buffer texture to the full screen (flipped, as render textures are)
fn drawGBufferTexture(id: u32, format: rl.PixelFormat, label: [:0]const u8, screen_width: i32, screen_height: i32) void {
    const texture: rl.Texture2D = .{ .id = id, .width = screen_width, .height = screen_height, .mipmaps = 1, .format = format };
    const source: rl.Rectangle = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(screen_width),
        .height = @floatFromInt(-screen_height),
    };
    rl.drawTextureRec(texture, source, rl.math.vector2Zero(), .ray_white);

    rl.drawText(label, 10, screen_height - 30, 20, .dark_green);
}

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - deferred rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    var camera: rl.Camera = .{
        .position = .{ .x = 5.0, .y = 4.0, .z = 5.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 60.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load plane model from a generated mesh
    const model = try rl.loadModelFromMesh(rl.genMeshPlane(10.0, 10.0, 3, 3));
    defer rl.unloadModel(model);
    const cube = try rl.loadModelFromMesh(rl.genMeshCube(2.0, 2.0, 2.0));
    defer rl.unloadModel(cube);

    // Load geometry buffer (G-buffer) shader and deferred shader
    const gbuffer_shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/gbuffer.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/gbuffer.fs", .{glsl_version}),
    );
    defer rl.unloadShader(gbuffer_shader);

    const deferred_shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/deferred_shading.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/deferred_shading.fs", .{glsl_version}),
    );
    defer rl.unloadShader(deferred_shader);
    deferred_shader.loc(.vector_view).* = rl.getShaderLocation(deferred_shader, "viewPosition");

    // Initialize the G-buffer
    var g_buffer: GBuffer = undefined;
    g_buffer.framebuffer_id = rl.gl.loadFramebuffer();
    if (g_buffer.framebuffer_id == 0) rl.traceLog(.warning, "Failed to create framebufferId", .{});

    rl.gl.enableFramebuffer(g_buffer.framebuffer_id);

    // NOTE: Vertex positions are stored in a texture for simplicity. A better approach would use a depth texture
    // (instead of a detph renderbuffer) to reconstruct world positions in the final render shader via clip-space position,
    // depth, and the inverse view/projection matrices

    // 16-bit precision ensures OpenGL ES 3 compatibility, though it may lack precision for real scenarios
    // But as mentioned above, the positions could be reconstructed instead of stored. If not targeting OpenGL ES
    // and you wish to maintain this approach, consider using `pixelformat_uncompressed_r32g32b32`
    g_buffer.position_texture_id = rl.gl.loadTexture(null, screen_width, screen_height, rl.gl.pixelformat_uncompressed_r16g16b16, 1);

    // Similarly, 16-bit precision is used for normals ensures OpenGL ES 3 compatibility
    // This is generally sufficient, but a 16-bit fixed-point format offer a better uniform precision in all orientations
    g_buffer.normal_texture_id = rl.gl.loadTexture(null, screen_width, screen_height, rl.gl.pixelformat_uncompressed_r16g16b16, 1);

    // Albedo (diffuse color) and specular strength can be combined into one texture
    // The color in RGB, and the specular strength in the alpha channel
    g_buffer.albedo_spec_texture_id = rl.gl.loadTexture(null, screen_width, screen_height, rl.gl.pixelformat_uncompressed_r8g8b8a8, 1);

    // Activate the draw buffers for our framebufferId
    rl.gl.activeDrawBuffers(3);

    // Now we attach our textures to the framebufferId
    rl.gl.framebufferAttach(g_buffer.framebuffer_id, g_buffer.position_texture_id, rl.gl.attachment_color_channel0, rl.gl.attachment_texture2d, 0);
    rl.gl.framebufferAttach(g_buffer.framebuffer_id, g_buffer.normal_texture_id, rl.gl.attachment_color_channel1, rl.gl.attachment_texture2d, 0);
    rl.gl.framebufferAttach(g_buffer.framebuffer_id, g_buffer.albedo_spec_texture_id, rl.gl.attachment_color_channel2, rl.gl.attachment_texture2d, 0);

    // Finally we attach the depth buffer
    g_buffer.depth_renderbuffer_id = rl.gl.loadTextureDepth(screen_width, screen_height, true);
    rl.gl.framebufferAttach(g_buffer.framebuffer_id, g_buffer.depth_renderbuffer_id, rl.gl.attachment_depth, rl.gl.attachment_renderbuffer, 0);
    defer g_buffer.unload();

    // Make sure our framebufferId is complete
    // NOTE: framebufferComplete() automatically unbinds the framebufferId, so we don't have to disableFramebuffer() here
    if (!rl.gl.framebufferComplete(g_buffer.framebuffer_id)) rl.traceLog(.warning, "Framebuffer is not complete", .{});

    // Now we initialize the sampler2D uniform's in the deferred shader
    // We do this by setting the uniform's values to the texture units that
    // we later bind our g-buffer textures to
    rl.gl.enableShader(deferred_shader.id);
    const tex_unit_position: i32 = 0;
    const tex_unit_normal: i32 = 1;
    const tex_unit_albedo_spec: i32 = 2;
    rl.setShaderValue(deferred_shader, rl.gl.getLocationUniform(deferred_shader.id, "gPosition"), tex_unit_position);
    rl.setShaderValue(deferred_shader, rl.gl.getLocationUniform(deferred_shader.id, "gNormal"), tex_unit_normal);
    rl.setShaderValue(deferred_shader, rl.gl.getLocationUniform(deferred_shader.id, "gAlbedoSpec"), tex_unit_albedo_spec);
    rl.gl.disableShader();

    // Assign out lighting shader to model
    model.materials.?[0].shader = gbuffer_shader;
    cube.materials.?[0].shader = gbuffer_shader;

    // Create lights
    var lights = [rlights.max_lights]rlights.Light{
        rlights.createLight(.point, .{ .x = -2, .y = 1, .z = -2 }, rl.math.vector3Zero(), .yellow, deferred_shader),
        rlights.createLight(.point, .{ .x = 2, .y = 1, .z = 2 }, rl.math.vector3Zero(), .red, deferred_shader),
        rlights.createLight(.point, .{ .x = -2, .y = 1, .z = 2 }, rl.math.vector3Zero(), .green, deferred_shader),
        rlights.createLight(.point, .{ .x = 2, .y = 1, .z = -2 }, rl.math.vector3Zero(), .blue, deferred_shader),
    };

    const cube_scale = 0.25;
    var cube_positions: [max_cubes]rl.Vector3 = undefined;
    var cube_rotations: [max_cubes]f32 = undefined;

    for (&cube_positions, &cube_rotations) |*position, *rotation| {
        const x = randFloat(10) - 5;
        const y = randFloat(5);
        const z = randFloat(10) - 5;
        position.* = .{ .x = x, .y = y, .z = z };

        rotation.* = randFloat(360);
    }

    var mode: DeferredMode = .shading;

    rl.gl.enableDepthTest();

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        rl.updateCamera(&camera, .orbital);

        // Update the shader with the camera view vector (points towards { 0.0f, 0.0f, 0.0f })
        rl.setShaderValue(deferred_shader, deferred_shader.loc(.vector_view).*, camera.position);

        // Check key inputs to enable/disable lights
        for (&lights, [_]rl.KeyboardKey{ .y, .r, .g, .b }) |*light, key| {
            if (rl.isKeyPressed(key)) light.enabled = !light.enabled;
        }

        // Check key inputs to switch between G-buffer textures
        if (rl.isKeyPressed(.one)) mode = .position;
        if (rl.isKeyPressed(.two)) mode = .normal;
        if (rl.isKeyPressed(.three)) mode = .albedo;
        if (rl.isKeyPressed(.four)) mode = .shading;

        // Update light values (actually, only enable/disable them)
        for (lights) |light| light.update(deferred_shader);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        // Draw to the geometry buffer by first activating it
        rl.gl.enableFramebuffer(g_buffer.framebuffer_id);
        rl.gl.clearColor(0, 0, 0, 0);
        rl.gl.clearScreenBuffers(); // Clear color and depth buffer
        rl.gl.disableColorBlend();

        rl.beginMode3D(camera);
        // NOTE: We have to use enableShader here. `beginShaderMode` or thus `setShader`
        // will not work, as they won't immediately load the shader program
        rl.gl.enableShader(gbuffer_shader.id);
        // When drawing a model here, make sure that the material's shaders are set to the gbuffer shader!
        rl.drawModel(model, rl.math.vector3Zero(), 1.0, .white);
        rl.drawModel(cube, .{ .x = 0.0, .y = 1.0, .z = 0.0 }, 1.0, .white);

        for (cube_positions, cube_rotations) |position, rotation| {
            rl.drawModelEx(cube, position, .{ .x = 1, .y = 1, .z = 1 }, rotation, .{ .x = cube_scale, .y = cube_scale, .z = cube_scale }, .white);
        }
        rl.gl.disableShader();
        rl.endMode3D();

        rl.gl.enableColorBlend();

        // Go back to the default framebufferId (0) and draw our deferred shading
        rl.gl.disableFramebuffer();
        rl.gl.clearScreenBuffers(); // Clear color & depth buffer

        switch (mode) {
            .shading => {
                rl.beginMode3D(camera);
                rl.gl.disableColorBlend();
                rl.gl.enableShader(deferred_shader.id);
                // Bind our g-buffer textures
                // We are binding them to locations that we earlier set in sampler2D uniforms `gPosition`, `gNormal`,
                // and `gAlbedoSpec`
                rl.gl.activeTextureSlot(tex_unit_position);
                rl.gl.enableTexture(g_buffer.position_texture_id);
                rl.gl.activeTextureSlot(tex_unit_normal);
                rl.gl.enableTexture(g_buffer.normal_texture_id);
                rl.gl.activeTextureSlot(tex_unit_albedo_spec);
                rl.gl.enableTexture(g_buffer.albedo_spec_texture_id);

                // Finally, we draw a fullscreen quad to our default framebufferId
                // This will now be shaded using our deferred shader
                rl.gl.loadDrawQuad();
                rl.gl.disableShader();
                rl.gl.enableColorBlend();
                rl.endMode3D();

                // As a last step, we now copy over the depth buffer from our g-buffer to the default framebufferId
                rl.gl.bindFramebuffer(rl.gl.read_framebuffer, g_buffer.framebuffer_id);
                rl.gl.bindFramebuffer(rl.gl.draw_framebuffer, 0);
                rl.gl.blitFramebuffer(0, 0, screen_width, screen_height, 0, 0, screen_width, screen_height, 0x00000100); // GL_DEPTH_BUFFER_BIT
                rl.gl.disableFramebuffer();

                // Since our shader is now done and disabled, we can draw spheres
                // that represent light positions in default forward rendering
                rl.beginMode3D(camera);
                rl.gl.enableShader(rl.gl.getShaderIdDefault());
                for (lights) |light| {
                    if (light.enabled) {
                        rl.drawSphereEx(light.position, 0.2, 8, 8, light.color);
                    } else {
                        rl.drawSphereWires(light.position, 0.2, 8, 8, rl.colorAlpha(light.color, 0.3));
                    }
                }
                rl.gl.disableShader();
                rl.endMode3D();

                rl.drawText("FINAL RESULT", 10, screen_height - 30, 20, .dark_green);
            },
            .position => drawGBufferTexture(g_buffer.position_texture_id, .uncompressed_r16g16b16, "POSITION TEXTURE", screen_width, screen_height),
            .normal => drawGBufferTexture(g_buffer.normal_texture_id, .uncompressed_r16g16b16, "NORMAL TEXTURE", screen_width, screen_height),
            .albedo => drawGBufferTexture(g_buffer.albedo_spec_texture_id, .uncompressed_r8g8b8a8, "ALBEDO TEXTURE", screen_width, screen_height),
        }

        rl.drawText("Toggle lights keys: [Y][R][G][B]", 10, 40, 20, .dark_gray);
        rl.drawText("Switch G-buffer textures: [1][2][3][4]", 10, 70, 20, .dark_gray);

        rl.drawFPS(10, 10);
    }
}
