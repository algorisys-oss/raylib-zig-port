//! raylib [shaders] example - shadowmap rendering
//!
//! Zig-API translation of examples/shaders/shaders_shadowmap_rendering.c (raylib 6.2).
//! Example contributed by TheManTheMythTheGameDev (@TheManTheMythTheGameDev) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 TheManTheMythTheGameDev (@TheManTheMythTheGameDev)

const rl = @import("raylib");

const glsl_version = 330; // Desktop GLSL version

const shadowmap_resolution = 1024;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    // Shadows are a HUGE topic, and this example shows an extremely simple implementation of the shadowmapping algorithm,
    // which is the industry standard for shadows. This algorithm can be extended in a ridiculous number of ways to improve
    // realism and also adapt it for different scenes. This is pretty much the simplest possible implementation

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - shadowmap rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    var camera: rl.Camera3D = .{
        .position = .{ .x = 10.0, .y = 10.0, .z = 10.0 },
        .target = rl.math.vector3Zero(),
        .projection = .perspective,
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
    };

    const shadow_shader = try rl.loadShader(
        rl.textFormat("resources/shaders/glsl{d}/shadowmap.vs", .{glsl_version}),
        rl.textFormat("resources/shaders/glsl{d}/shadowmap.fs", .{glsl_version}),
    );
    defer rl.unloadShader(shadow_shader);
    shadow_shader.loc(.vector_view).* = rl.getShaderLocation(shadow_shader, "viewPos");

    var light_dir = rl.math.vector3Normalize(.{ .x = 0.35, .y = -1.0, .z = -0.35 });
    const light_color: rl.Color = .white;
    const light_color_normalized = rl.colorNormalize(light_color);
    const light_dir_loc = rl.getShaderLocation(shadow_shader, "lightDir");
    const light_col_loc = rl.getShaderLocation(shadow_shader, "lightColor");
    rl.setShaderValue(shadow_shader, light_dir_loc, light_dir);
    rl.setShaderValue(shadow_shader, light_col_loc, light_color_normalized);
    const ambient_loc = rl.getShaderLocation(shadow_shader, "ambient");
    const ambient = [4]f32{ 0.1, 0.1, 0.1, 1.0 };
    rl.setShaderValue(shadow_shader, ambient_loc, ambient);
    const light_vp_loc = rl.getShaderLocation(shadow_shader, "lightVP");
    const shadow_map_loc = rl.getShaderLocation(shadow_shader, "shadowMap");
    const shadow_map_resolution: i32 = shadowmap_resolution;
    rl.setShaderValue(shadow_shader, rl.getShaderLocation(shadow_shader, "shadowMapResolution"), shadow_map_resolution);

    const cube = try rl.loadModelFromMesh(rl.genMeshCube(1.0, 1.0, 1.0));
    defer rl.unloadModel(cube);
    cube.materials.?[0].shader = shadow_shader;
    const robot = try rl.loadModel("resources/models/robot.glb");
    defer rl.unloadModel(robot);
    for (robot.materials.?[0..@intCast(robot.materialCount)]) |*material| material.shader = shadow_shader;

    const anims = try rl.loadModelAnimations("resources/models/robot.glb");
    defer rl.unloadModelAnimations(anims);

    const shadow_map = try loadShadowmapRenderTexture(shadowmap_resolution, shadowmap_resolution);
    defer unloadShadowmapRenderTexture(shadow_map);

    // For the shadowmapping algorithm, we will be rendering everything from the light's point of view
    var light_camera: rl.Camera3D = .{
        .position = rl.math.vector3Scale(light_dir, -15.0),
        .target = rl.math.vector3Zero(),
        .projection = .orthographic, // Use an orthographic projection for directional lights
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 20.0,
    };

    var frame_counter: i32 = 0;

    const texture_active_slot: i32 = 10; // Can be anything 0 to 15, but 0 will probably be taken up

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const delta_time = rl.getFrameTime();

        rl.updateCamera(&camera, .orbital);

        // send the updated camera position to the shader so that it can calculate the correct lighting for the scene
        const camera_pos = camera.position;
        rl.setShaderValue(shadow_shader, shadow_shader.loc(.vector_view).*, camera_pos);

        frame_counter += 1;
        frame_counter = @rem(frame_counter, anims[0].keyframeCount);
        rl.updateModelAnimation(robot, anims[0], @floatFromInt(frame_counter));

        // Move light with arrow keys
        const camera_speed: f32 = 0.05;
        if (rl.isKeyDown(.left)) {
            if (light_dir.x < 0.6) light_dir.x += camera_speed * 60.0 * delta_time;
        }
        if (rl.isKeyDown(.right)) {
            if (light_dir.x > -0.6) light_dir.x -= camera_speed * 60.0 * delta_time;
        }
        if (rl.isKeyDown(.up)) {
            if (light_dir.z < 0.6) light_dir.z += camera_speed * 60.0 * delta_time;
        }
        if (rl.isKeyDown(.down)) {
            if (light_dir.z > -0.6) light_dir.z -= camera_speed * 60.0 * delta_time;
        }

        light_dir = rl.math.vector3Normalize(light_dir);
        light_camera.position = rl.math.vector3Scale(light_dir, -15.0);
        rl.setShaderValue(shadow_shader, light_dir_loc, light_dir);

        // Draw
        // PASS 01: Render all objects into the shadowmap render texture
        // We record all the objects' depths (as rendered from the light source's point of view) in a buffer
        // Anything that is "visible" to the light is in light, anything that isn't is in shadow
        // We can later use the depth buffer when rendering everything from the player's point of view
        // to determine whether a given point is "visible" to the light
        // Store the light matrices
        const light_view, const light_proj = blk: {
            rl.beginTextureMode(shadow_map);
            defer rl.endTextureMode();

            rl.clearBackground(.white);

            rl.beginMode3D(light_camera);
            defer rl.endMode3D();

            const view = rl.gl.getMatrixModelview();
            const proj = rl.gl.getMatrixProjection();
            drawScene(cube, robot);
            break :blk .{ view, proj };
        };

        const light_view_proj = rl.math.matrixMultiply(light_view, light_proj);

        // PASS 02: Draw the scene into main framebuffer, using the generated shadowmap
        {
            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(.ray_white);

            rl.setShaderValueMatrix(shadow_shader, light_vp_loc, light_view_proj);
            rl.gl.enableShader(shadow_shader.id);

            rl.gl.activeTextureSlot(texture_active_slot);
            rl.gl.enableTexture(shadow_map.depth.id);
            rl.gl.setUniform(shadow_map_loc, &texture_active_slot, rl.gl.shader_uniform_int, 1);

            {
                rl.beginMode3D(camera);
                defer rl.endMode3D();

                drawScene(cube, robot); // Draw the same exact things as we drew in the shadowmap!
            }

            rl.gl.activeTextureSlot(texture_active_slot);
            rl.gl.disableTexture();

            rl.drawText("Use the arrow keys to rotate the light!", 10, 10, 30, .red);
            rl.drawText("Shadows in raylib using the shadowmapping algorithm!", screen_width - 280, screen_height - 20, 10, .gray);
        }

        if (rl.isKeyPressed(.f)) rl.takeScreenshot("shaders_shadowmap.png");
    }
}

/// Load render texture for shadowmap projection
/// NOTE: Load framebuffer with only a texture depth attachment,
/// no color attachment required for shadowmap
fn loadShadowmapRenderTexture(width: i32, height: i32) error{LoadFailed}!rl.RenderTexture2D {
    const id = rl.gl.loadFramebuffer(); // Load an empty framebuffer
    if (id == 0) {
        rl.traceLog(.warning, "FBO: Framebuffer object can not be created", .{});
        return error.LoadFailed;
    }

    rl.gl.enableFramebuffer(id);
    defer rl.gl.disableFramebuffer();

    const target: rl.RenderTexture2D = .{
        .id = id,
        // No color texture attachment: only its size is used (viewport of beginTextureMode)
        .texture = .{ .id = 0, .width = width, .height = height, .mipmaps = 0, .format = .uncompressed_r8g8b8a8 },
        // Create depth texture
        // NOTE: No need a color texture attachment for the shadowmap
        .depth = .{
            .id = rl.gl.loadTextureDepth(width, height, false),
            .width = width,
            .height = height,
            .mipmaps = 1,
            .format = @fromBackingInt(@intCast(19)), // DEPTH_COMPONENT_24BIT?
        },
    };

    // Attach depth texture to FBO
    rl.gl.framebufferAttach(target.id, target.depth.id, rl.gl.attachment_depth, rl.gl.attachment_texture2d, 0);

    // Check if fbo is complete with attachments (valid)
    if (rl.gl.framebufferComplete(target.id)) rl.traceLog(.info, "FBO: [ID {d}] Framebuffer object created successfully", .{target.id});

    return target;
}

/// Unload shadowmap render texture from GPU memory (VRAM)
fn unloadShadowmapRenderTexture(target: rl.RenderTexture2D) void {
    // NOTE: Depth texture/renderbuffer is automatically
    // queried and deleted before deleting framebuffer
    rl.gl.unloadFramebuffer(target.id);
}

/// Draw full scene projecting shadows
/// NOTE: Required  to be called several time to generate shadowmap
fn drawScene(cube: rl.Model, robot: rl.Model) void {
    rl.drawModelEx(cube, rl.math.vector3Zero(), .{ .x = 0.0, .y = 1.0, .z = 0.0 }, 0.0, .{ .x = 10.0, .y = 1.0, .z = 10.0 }, .blue);
    rl.drawModelEx(cube, .{ .x = 1.5, .y = 1.0, .z = -1.5 }, .{ .x = 0.0, .y = 1.0, .z = 0.0 }, 0.0, rl.math.vector3One(), .white);
    rl.drawModelEx(robot, .{ .x = 0.0, .y = 0.5, .z = 0.0 }, .{ .x = 0.0, .y = 1.0, .z = 0.0 }, 0.0, .{ .x = 1.0, .y = 1.0, .z = 1.0 }, .red);
}
