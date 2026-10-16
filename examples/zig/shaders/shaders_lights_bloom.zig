//! raylib [shaders] example - lights bloom
//!
//! Zig-API translation of examples/shaders/shaders_lights_bloom.c (raylib 6.2).
//! Example contributed by PanicTitan (@PanicTitan) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 PanicTitan (@PanicTitan)

const rl = @import("raylib");

const glsl_version = 330; // Desktop GLSL version

const max_lights = 8;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true, .vsync_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - lights bloom");
    defer rl.closeWindow(); // Close window and OpenGL context

    var camera: rl.Camera3D = .{
        .position = .{ .x = 0.0, .y = 5.0, .z = 9.0 },
        .target = .{ .x = 0.0, .y = 0.5, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    const target = try rl.loadRenderTexture(screen_width, screen_height);
    defer rl.unloadRenderTexture(target);

    // Forward multi-light shader and bloom post-process shader, both loaded from the
    // resources folder shared with the rest of the shaders examples
    const light_shader = try rl.loadShader(
        rl.textFormat("resources/shaders/glsl{d}/lights_bloom.vs", .{glsl_version}),
        rl.textFormat("resources/shaders/glsl{d}/lights_bloom.fs", .{glsl_version}),
    );
    defer rl.unloadShader(light_shader);
    const bloom_shader = try rl.loadShader(null, rl.textFormat("resources/shaders/glsl{d}/lights_bloom_post.fs", .{glsl_version}));
    defer rl.unloadShader(bloom_shader);

    // Load models from generated cube mesh and plane
    // NOTE: Meshes are automatically unloaded on unloadModel()
    const cube = try rl.loadModelFromMesh(rl.genMeshCube(2.0, 2.0, 2.0));
    defer rl.unloadModel(cube);
    const floor = try rl.loadModelFromMesh(rl.genMeshPlane(14.0, 14.0, 1, 1));
    defer rl.unloadModel(floor);
    cube.materials.?[0].shader = light_shader;
    floor.materials.?[0].shader = light_shader;

    const light_pos_loc = rl.getShaderLocation(light_shader, "lightPositions");
    const light_col_loc = rl.getShaderLocation(light_shader, "lightColors");
    const view_pos_loc = rl.getShaderLocation(light_shader, "viewPos");

    var light_positions: [max_lights]rl.Vector3 = undefined;
    const light_colors = [max_lights]rl.Vector3{
        .{ .x = 1.0, .y = 0.2, .z = 0.2 }, // Red
        .{ .x = 0.2, .y = 1.0, .z = 0.3 }, // Green
        .{ .x = 0.2, .y = 0.5, .z = 1.0 }, // Blue
        .{ .x = 1.0, .y = 0.8, .z = 0.1 }, // Yellow
        .{ .x = 1.0, .y = 0.1, .z = 0.8 }, // Magenta
        .{ .x = 0.1, .y = 1.0, .z = 1.0 }, // Cyan
        .{ .x = 1.0, .y = 0.4, .z = 0.1 }, // Orange
        .{ .x = 0.7, .y = 0.2, .z = 1.0 }, // Purple
    };

    rl.setShaderValueV(light_shader, light_col_loc, &light_colors);

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        const time: f32 = @floatCast(rl.getTime());

        // Orbital path for each point light, its own radius/height offset by index
        for (&light_positions, 0..) |*position, i| {
            const fi: f32 = @floatFromInt(i);
            const angle = (fi / max_lights) * 2.0 * rl.pi + time * 0.6;
            const radius = 4.2 + @sin(time * 1.2 + fi) * 0.4;
            const height = 1.0 + @sin(time * 1.8 + fi) * 0.6;

            position.* = .{ .x = @sin(angle) * radius, .y = height, .z = @cos(angle) * radius };
        }

        rl.setShaderValueV(light_shader, light_pos_loc, &light_positions);
        rl.setShaderValue(light_shader, view_pos_loc, camera.position);

        // Draw
        // Render the lit scene to an offscreen texture
        {
            rl.beginTextureMode(target);
            defer rl.endTextureMode();

            rl.clearBackground(.{ .r = 12, .g = 12, .b = 18, .a = 255 });

            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(cube, .{ .x = 0.0, .y = 1.0, .z = 0.0 }, 1.0, .gray);
            rl.drawModel(floor, .{ .x = 0.0, .y = 0.0, .z = 0.0 }, 1.0, .dark_gray);
            rl.drawGrid(10, 1.0);

            // Glowing bulbs mark each light's position
            for (light_positions, light_colors) |position, color| {
                const bulb_color: rl.Color = .{
                    .r = @intFromFloat(color.x * 255),
                    .g = @intFromFloat(color.y * 255),
                    .b = @intFromFloat(color.z * 255),
                    .a = 255,
                };

                rl.drawSphere(position, 0.15, bulb_color);
            }
        }

        // Present the offscreen texture through the bloom + tone mapping shader
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        const src_rec: rl.Rectangle = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(target.texture.width),
            .height = @floatFromInt(-target.texture.height),
        };

        {
            rl.beginShaderMode(bloom_shader);
            defer rl.endShaderMode();

            // NOTE: Render texture must be y-flipped due to default OpenGL coordinates (left-bottom)
            rl.drawTextureRec(target.texture, src_rec, .{ .x = 0, .y = 0 }, .white);
        }

        rl.drawText("BALANCED MULTI-LIGHT + REINHARD TONE MAPPED BLOOM", 20, 20, 20, .green);
    }
}
