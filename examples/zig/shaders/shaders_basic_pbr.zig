//! raylib [shaders] example - basic pbr
//!
//! Zig-API translation of examples/shaders/shaders_basic_pbr.c (raylib 6.2).
//! Example contributed by Afan OLOVCIC (@_DevDad) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 Afan OLOVCIC (@_DevDad)
//!
//! Model: "Old Rusty Car" (https://skfb.ly/LxRy) by Renafox,
//! licensed under Creative Commons Attribution-NonCommercial
//! (http://creativecommons.org/licenses/by-nc/4.0/)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

const max_lights = 4; // Max dynamic lights supported by shader

/// Light type
const LightType = enum(i32) {
    directional = 0,
    point,
    spot,
};

/// Light data
const Light = struct {
    type: LightType,
    enabled: bool,
    position: rl.Vector3,
    target: rl.Vector3,
    color: rl.Vector4, // Normalized color
    intensity: f32,

    // Shader light parameters locations
    type_loc: i32,
    enabled_loc: i32,
    position_loc: i32,
    target_loc: i32,
    color_loc: i32,
    intensity_loc: i32,

    /// Create light `index` (of the shader's `lights[max_lights]` array) and get its shader locations
    fn init(index: usize, light_type: LightType, position: rl.Vector3, target: rl.Vector3, color: rl.Color, intensity: f32, shader: rl.Shader) Light {
        const light: Light = .{
            .enabled = true,
            .type = light_type,
            .position = position,
            .target = target,
            .color = rl.colorNormalize(color),
            .intensity = intensity,

            // NOTE: Shader parameters names for lights must match the requested ones
            .enabled_loc = rl.getShaderLocation(shader, rl.textFormat("lights[{d}].enabled", .{index})),
            .type_loc = rl.getShaderLocation(shader, rl.textFormat("lights[{d}].type", .{index})),
            .position_loc = rl.getShaderLocation(shader, rl.textFormat("lights[{d}].position", .{index})),
            .target_loc = rl.getShaderLocation(shader, rl.textFormat("lights[{d}].target", .{index})),
            .color_loc = rl.getShaderLocation(shader, rl.textFormat("lights[{d}].color", .{index})),
            .intensity_loc = rl.getShaderLocation(shader, rl.textFormat("lights[{d}].intensity", .{index})),
        };
        light.update(shader);
        return light;
    }

    /// Send light properties to shader
    /// NOTE: Light shader locations should be available
    fn update(light: Light, shader: rl.Shader) void {
        const enabled: i32 = @intFromBool(light.enabled);
        const light_type: i32 = @backingInt(light.type);
        rl.setShaderValue(shader, light.enabled_loc, enabled);
        rl.setShaderValue(shader, light.type_loc, light_type);

        // Send to shader light position and target position values
        rl.setShaderValue(shader, light.position_loc, light.position);
        rl.setShaderValue(shader, light.target_loc, light.target);
        rl.setShaderValue(shader, light.color_loc, light.color);
        rl.setShaderValue(shader, light.intensity_loc, light.intensity);
    }

    /// The light's color, back in 8-bit channels
    fn rgba(light: Light) rl.Color {
        return .{
            .r = @intFromFloat(light.color.x * 255),
            .g = @intFromFloat(light.color.y * 255),
            .b = @intFromFloat(light.color.z * 255),
            .a = @intFromFloat(light.color.w * 255),
        };
    }
};

/// Unbind (disconnect) the shared shader from the model's material, so
/// unloadMaterial() does not unload it, then unload the model
fn unloadPbrModel(model: rl.Model) void {
    const material = &model.materials.?[0];
    material.shader = .{ .id = 0, .locs = null };
    rl.unloadMaterial(material.*);
    material.maps = null;
    rl.unloadModel(model);
}

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - basic pbr");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 2.0, .y = 2.0, .z = 6.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.5, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load PBR shader and setup all required locations
    const shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/pbr.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/pbr.fs", .{glsl_version}),
    );
    defer rl.unloadShader(shader);

    shader.loc(.map_albedo).* = rl.getShaderLocation(shader, "albedoMap");
    // WARNING: Metalness, roughness, and ambient occlusion are all packed into a MRA texture
    // They are passed as to the SHADER_LOC_MAP_METALNESS location for convenience,
    // shader already takes care of it accordingly
    shader.loc(.map_metalness).* = rl.getShaderLocation(shader, "mraMap");
    shader.loc(.map_normal).* = rl.getShaderLocation(shader, "normalMap");
    // WARNING: Similar to the MRA map, the emissive map packs different information
    // into a single texture: it stores height and emission data
    // It is binded to SHADER_LOC_MAP_EMISSION location an properly processed on shader
    shader.loc(.map_emission).* = rl.getShaderLocation(shader, "emissiveMap");
    shader.loc(.color_diffuse).* = rl.getShaderLocation(shader, "albedoColor");

    // Setup additional required shader locations, including lights data
    shader.loc(.vector_view).* = rl.getShaderLocation(shader, "viewPos");
    const light_count_loc = rl.getShaderLocation(shader, "numOfLights");
    const max_light_count: i32 = max_lights;
    rl.setShaderValue(shader, light_count_loc, max_light_count);

    // Setup ambient color and intensity parameters
    const ambient_intensity: f32 = 0.02;
    const ambient_color: rl.Color = .{ .r = 26, .g = 32, .b = 135, .a = 255 };
    const ambient_color_normalized: rl.Vector3 = .{
        .x = @as(f32, @floatFromInt(ambient_color.r)) / 255.0,
        .y = @as(f32, @floatFromInt(ambient_color.g)) / 255.0,
        .z = @as(f32, @floatFromInt(ambient_color.b)) / 255.0,
    };
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "ambientColor"), ambient_color_normalized);
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "ambient"), ambient_intensity);

    // Get location for shader parameters that can be modified in real time
    const metallic_value_loc = rl.getShaderLocation(shader, "metallicValue");
    const roughness_value_loc = rl.getShaderLocation(shader, "roughnessValue");
    const emissive_intensity_loc = rl.getShaderLocation(shader, "emissivePower");
    const emissive_color_loc = rl.getShaderLocation(shader, "emissiveColor");
    const texture_tiling_loc = rl.getShaderLocation(shader, "tiling");

    // Load old car model using PBR maps and shader
    // WARNING: We know this model consists of a single model.meshes[0] and
    // that model.materials[0] is by default assigned to that mesh
    // There could be more complex models consisting of multiple meshes and
    // multiple materials defined for those meshes... but always 1 mesh = 1 material
    const car = try rl.loadModel("resources/models/old_car_new.glb");
    defer unloadPbrModel(car);
    const car_material = &car.materials.?[0];

    // Assign already setup PBR shader to model.materials[0], used by models.meshes[0]
    car_material.shader = shader;

    // Setup materials[0].maps default parameters
    car_material.map(.albedo).color = .white;
    car_material.map(.metalness).value = 1.0;
    car_material.map(.roughness).value = 0.0;
    car_material.map(.occlusion).value = 1.0;
    car_material.map(.emission).color = .{ .r = 255, .g = 162, .b = 0, .a = 255 };

    // Setup materials[0].maps default textures
    car_material.map(.albedo).texture = try rl.loadTexture("resources/old_car_d.png");
    car_material.map(.metalness).texture = try rl.loadTexture("resources/old_car_mra.png");
    car_material.map(.normal).texture = try rl.loadTexture("resources/old_car_n.png");
    car_material.map(.emission).texture = try rl.loadTexture("resources/old_car_e.png");

    // Load floor model mesh and assign material parameters
    // NOTE: A basic plane shape can be generated instead of being loaded from a model file
    const floor = try rl.loadModel("resources/models/plane.glb");
    defer unloadPbrModel(floor);
    const floor_material = &floor.materials.?[0];
    //const floor_mesh = rl.genMeshPlane(10, 10, 10, 10);
    //rl.genMeshTangents(&floor_mesh); // TODO: Review tangents generation
    //const floor = try rl.loadModelFromMesh(floor_mesh);

    // Assign material shader for our floor model, same PBR shader
    floor_material.shader = shader;

    floor_material.map(.albedo).color = .white;
    floor_material.map(.metalness).value = 0.8;
    floor_material.map(.roughness).value = 0.1;
    floor_material.map(.occlusion).value = 1.0;
    floor_material.map(.emission).color = .black;

    floor_material.map(.albedo).texture = try rl.loadTexture("resources/road_a.png");
    floor_material.map(.metalness).texture = try rl.loadTexture("resources/road_mra.png");
    floor_material.map(.normal).texture = try rl.loadTexture("resources/road_n.png");

    // Models texture tiling parameter can be stored in the Material struct if required (CURRENTLY NOT USED)
    // NOTE: Material.params[4] are available for generic parameters storage (float)
    const car_texture_tiling: rl.Vector2 = .{ .x = 0.5, .y = 0.5 };
    const floor_texture_tiling: rl.Vector2 = .{ .x = 0.5, .y = 0.5 };

    // Create some lights
    const origin: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
    var lights = [max_lights]Light{
        .init(0, .point, .{ .x = -1.0, .y = 1.0, .z = -2.0 }, origin, .yellow, 4.0, shader),
        .init(1, .point, .{ .x = 2.0, .y = 1.0, .z = 1.0 }, origin, .green, 3.3, shader),
        .init(2, .point, .{ .x = -2.0, .y = 1.0, .z = 1.0 }, origin, .red, 8.3, shader),
        .init(3, .point, .{ .x = 1.0, .y = 1.0, .z = -2.0 }, origin, .blue, 2.0, shader),
    };

    // Setup material texture maps usage in shader
    // NOTE: By default, the texture maps are always used
    const usage: i32 = 1;
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "useTexAlbedo"), usage);
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "useTexNormal"), usage);
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "useTexMRA"), usage);
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "useTexEmissive"), usage);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        // Update the shader with the camera view vector (points towards { 0.0f, 0.0f, 0.0f })
        rl.setShaderValue(shader, shader.loc(.vector_view).*, camera.position);

        // Check key inputs to enable/disable lights
        if (rl.isKeyPressed(.one)) lights[2].enabled = !lights[2].enabled;
        if (rl.isKeyPressed(.two)) lights[1].enabled = !lights[1].enabled;
        if (rl.isKeyPressed(.three)) lights[3].enabled = !lights[3].enabled;
        if (rl.isKeyPressed(.four)) lights[0].enabled = !lights[0].enabled;

        // Update light values on shader (actually, only enable/disable them)
        for (lights) |light| light.update(shader);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            // Set floor model texture tiling and emissive color parameters on shader
            rl.setShaderValue(shader, texture_tiling_loc, floor_texture_tiling);
            const floor_emissive_color = rl.colorNormalize(floor_material.map(.emission).color);
            rl.setShaderValue(shader, emissive_color_loc, floor_emissive_color);

            // Set floor metallic and roughness values
            rl.setShaderValue(shader, metallic_value_loc, floor_material.map(.metalness).value);
            rl.setShaderValue(shader, roughness_value_loc, floor_material.map(.roughness).value);

            rl.drawModel(floor, .{ .x = 0.0, .y = 0.0, .z = 0.0 }, 5.0, .white); // Draw floor model

            // Set old car model texture tiling, emissive color and emissive intensity parameters on shader
            rl.setShaderValue(shader, texture_tiling_loc, car_texture_tiling);
            const car_emissive_color = rl.colorNormalize(car_material.map(.emission).color);
            rl.setShaderValue(shader, emissive_color_loc, car_emissive_color);
            const emissive_intensity: f32 = 0.01;
            rl.setShaderValue(shader, emissive_intensity_loc, emissive_intensity);

            // Set old car metallic and roughness values
            rl.setShaderValue(shader, metallic_value_loc, car_material.map(.metalness).value);
            rl.setShaderValue(shader, roughness_value_loc, car_material.map(.roughness).value);

            rl.drawModel(car, .{ .x = 0.0, .y = 0.0, .z = 0.0 }, 0.25, .white); // Draw car model

            // Draw spheres to show the lights positions
            for (lights) |light| {
                const light_color = light.rgba();

                if (light.enabled) {
                    rl.drawSphereEx(light.position, 0.2, 8, 8, light_color);
                } else {
                    rl.drawSphereWires(light.position, 0.2, 8, 8, rl.colorAlpha(light_color, 0.3));
                }
            }
        }

        rl.drawText("Toggle lights: [1][2][3][4]", 10, 40, 20, .light_gray);

        rl.drawText("(c) Old Rusty Car model by Renafox (https://skfb.ly/LxRy)", screen_width - 320, screen_height - 20, 10, .light_gray);

        rl.drawFPS(10, 10);
    }
}
