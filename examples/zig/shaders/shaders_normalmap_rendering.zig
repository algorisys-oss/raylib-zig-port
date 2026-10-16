//! raylib [shaders] example - normalmap rendering
//!
//! Zig-API translation of examples/shaders/shaders_normalmap_rendering.c (raylib 6.2).
//! Example contributed by Jeremy Montgomery (@Sir_Irk) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jeremy Montgomery (@Sir_Irk) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - normalmap rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    const camera: rl.Camera = .{
        .position = .{ .x = 0.0, .y = 2.0, .z = -4.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    // Load basic normal map lighting shader
    const shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/normalmap.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/normalmap.fs", .{glsl_version}),
    );
    defer rl.unloadShader(shader);

    // Get some required shader locations
    shader.loc(.map_normal).* = rl.getShaderLocation(shader, "normalMap");
    shader.loc(.vector_view).* = rl.getShaderLocation(shader, "viewPos");

    // NOTE: "matModel" location name is automatically assigned on shader loading,
    // no need to get the location again if using that uniform name
    //shader.loc(.matrix_model).* = rl.getShaderLocation(shader, "matModel");

    // This example uses just 1 point light
    var light_position: rl.Vector3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 };
    const light_pos_loc = rl.getShaderLocation(shader, "lightPos");

    // Load a plane model that has proper normals and tangents
    var plane = try rl.loadModel("resources/models/plane.glb");
    defer rl.unloadModel(plane);

    // Set the plane model's shader and texture maps
    const material = &plane.materials.?[0];
    material.shader = shader;
    const diffuse_map = material.map(.diffuse);
    const normal_map = material.map(.normal);
    diffuse_map.texture = try rl.loadTexture("resources/tiles_diffuse.png");
    normal_map.texture = try rl.loadTexture("resources/tiles_normal.png");

    // Generate Mipmaps and use TRILINEAR filtering to help with texture aliasing
    rl.genTextureMipmaps(&diffuse_map.texture);
    rl.genTextureMipmaps(&normal_map.texture);

    rl.setTextureFilter(diffuse_map.texture, .trilinear);
    rl.setTextureFilter(normal_map.texture, .trilinear);

    // Specular exponent AKA shininess of the material
    var specular_exponent: f32 = 8.0;
    const specular_exponent_loc = rl.getShaderLocation(shader, "specularExponent");

    // Allow toggling the normal map on and off for comparison purposes
    var use_normal_map = true;
    const use_normal_map_loc = rl.getShaderLocation(shader, "useNormalMap");

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Move the light around on the X and Z axis using WASD keys
        var direction: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 };
        if (rl.isKeyDown(.w)) direction = rl.math.vector3Add(direction, .{ .x = 0.0, .y = 0.0, .z = 1.0 });
        if (rl.isKeyDown(.s)) direction = rl.math.vector3Add(direction, .{ .x = 0.0, .y = 0.0, .z = -1.0 });
        if (rl.isKeyDown(.d)) direction = rl.math.vector3Add(direction, .{ .x = -1.0, .y = 0.0, .z = 0.0 });
        if (rl.isKeyDown(.a)) direction = rl.math.vector3Add(direction, .{ .x = 1.0, .y = 0.0, .z = 0.0 });

        direction = rl.math.vector3Normalize(direction);
        light_position = rl.math.vector3Add(light_position, rl.math.vector3Scale(direction, rl.getFrameTime() * 3.0));

        // Increase/Decrease the specular exponent(shininess)
        if (rl.isKeyDown(.up)) specular_exponent = rl.math.clamp(specular_exponent + 40.0 * rl.getFrameTime(), 2.0, 128.0);
        if (rl.isKeyDown(.down)) specular_exponent = rl.math.clamp(specular_exponent - 40.0 * rl.getFrameTime(), 2.0, 128.0);

        // Toggle normal map on and off
        if (rl.isKeyPressed(.n)) use_normal_map = !use_normal_map;

        // Spin plane model at a constant rate
        plane.transform = rl.math.matrixRotateY(@as(f32, @floatCast(rl.getTime())) * 0.5);

        // Update shader values
        rl.setShaderValue(shader, light_pos_loc, &light_position, .vec3);
        rl.setShaderValue(shader, shader.loc(.vector_view).*, &camera.position, .vec3);
        rl.setShaderValue(shader, specular_exponent_loc, &specular_exponent, .float);
        const use_normal_map_value: i32 = @intFromBool(use_normal_map);
        rl.setShaderValue(shader, use_normal_map_loc, &use_normal_map_value, .int);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            {
                rl.beginShaderMode(shader);
                defer rl.endShaderMode();

                rl.drawModel(plane, rl.math.vector3Zero(), 2.0, .white);
            }

            // Draw sphere to show light position
            rl.drawSphereWires(light_position, 0.2, 8, 8, .orange);
        }

        const text_color: rl.Color = if (use_normal_map) .dark_green else .red;
        const toggle_str = if (use_normal_map) "On" else "Off";
        rl.drawText(rl.textFormat("Use key [N] to toggle normal map: {s}", .{toggle_str}), 10, 10, 10, text_color);

        const y_offset = 24;
        rl.drawText("Use keys [W][A][S][D] to move the light", 10, 10 + y_offset * 1, 10, .black);
        rl.drawText("Use keys [Up][Down] to change specular exponent", 10, 10 + y_offset * 2, 10, .black);
        rl.drawText(rl.textFormat("Specular Exponent: {d:.2}", .{specular_exponent}), 10, 10 + y_offset * 3, 10, .blue);

        rl.drawFPS(screen_width - 90, 10);
    }
}
