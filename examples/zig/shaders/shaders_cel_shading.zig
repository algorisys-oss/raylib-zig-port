//! raylib [shaders] example - cel shading
//!
//! Zig-API translation of examples/shaders/shaders_cel_shading.c (raylib 6.2).
//! Example contributed by Gleb A (@ggrizzly) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Gleb A (@ggrizzly)

const std = @import("std");
const rl = @import("raylib");
const rlights = @import("rlights");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - cel shading");
    defer rl.closeWindow();

    var camera: rl.Camera = .{
        .position = .{ .x = 9.0, .y = 6.0, .z = 9.0 },
        .target = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    // Load model
    const model = try rl.loadModel("resources/models/old_car_new.glb");
    defer rl.unloadModel(model);

    // Load cel shader
    const cel_shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/cel.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/cel.fs", .{glsl_version}),
    );
    defer rl.unloadShader(cel_shader);
    cel_shader.loc(.vector_view).* = rl.getShaderLocation(cel_shader, "viewPos");

    // Apply cel shader to model, keep copy of default shader
    const material = &model.materials.?[0];
    const default_shader = material.shader;
    material.shader = cel_shader;

    // numBands: controls toon quantization steps (2 = hard binary, 20 = near-smooth)
    var num_bands: f32 = 10.0;
    const num_bands_loc = rl.getShaderLocation(cel_shader, "numBands");
    rl.setShaderValue(cel_shader, num_bands_loc, num_bands);

    // Inverted-hull outline shader: draws back faces extruded along normals
    const outline_shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/outline_hull.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/outline_hull.fs", .{glsl_version}),
    );
    defer rl.unloadShader(outline_shader);
    const outline_thickness_loc = rl.getShaderLocation(outline_shader, "outlineThickness");

    // Single directional white light, angled so toon bands are visible on the model sides.
    // Spins opposite to CAMERA_ORBITAL (0.5 rad/s) so lighting changes as you watch.
    // The unused slots stay zero lights, updated like the C example does.
    var lights: [rlights.max_lights]rlights.Light = .{
        rlights.createLight(.directional, .{ .x = 50.0, .y = 50.0, .z = 50.0 }, rl.math.vector3Zero(), .white, cel_shader),
        .{},
        .{},
        .{},
    };

    var cel_enabled = true;
    var outline_enabled = true;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        rl.updateCamera(&camera, .orbital);

        rl.setShaderValue(cel_shader, cel_shader.loc(.vector_view).*, camera.position);

        // [Z] Toggle cel shading on/off
        if (rl.isKeyPressed(.z)) {
            cel_enabled = !cel_enabled;
            material.shader = if (cel_enabled) cel_shader else default_shader;
        }

        // [C] Toggle outline on/off
        if (rl.isKeyPressed(.c)) outline_enabled = !outline_enabled;

        // [Q/E] Decrease/increase toon band count (press or hold to repeat)
        if (rl.isKeyPressed(.e) or rl.isKeyPressedRepeat(.e)) num_bands = rl.math.clamp(num_bands + 1.0, 2.0, 20.0);
        if (rl.isKeyPressed(.q) or rl.isKeyPressedRepeat(.q)) num_bands = rl.math.clamp(num_bands - 1.0, 2.0, 20.0);
        rl.setShaderValue(cel_shader, num_bands_loc, num_bands);

        // Spin light opposite to CAMERA_ORBITAL (0.5 rad/s), angled 45 degrees off vertical
        const t: f32 = @floatCast(rl.getTime());
        lights[0].position = .{ .x = @sin(-t * 0.3) * 5.0, .y = 5.0, .z = @cos(-t * 0.3) * 5.0 };

        for (lights) |light| light.update(cel_shader);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            if (outline_enabled) {
                // Outline pass: cull front faces, draw extruded back faces as silhouette
                const thickness: f32 = 0.005;
                rl.setShaderValue(outline_shader, outline_thickness_loc, thickness);

                rl.gl.setCullFace(rl.gl.cull_face_front);

                material.shader = outline_shader;

                rl.drawModel(model, rl.math.vector3Zero(), 0.75, .white);

                material.shader = if (cel_enabled) cel_shader else default_shader;

                rl.gl.setCullFace(rl.gl.cull_face_back);
            }

            rl.drawModel(model, rl.math.vector3Zero(), 0.75, .white);
            rl.drawSphereEx(lights[0].position, 0.2, 50, 50, .yellow); // Light position indicator
            rl.drawGrid(10, 10.0);
        }

        rl.drawFPS(10, 10);
        rl.drawText(rl.textFormat("Cel: {s}  [Z]", .{if (cel_enabled) "ON" else "OFF"}), 10, 65, 20, if (cel_enabled) .dark_green else .dark_gray);
        rl.drawText(rl.textFormat("Outline: {s}  [C]", .{if (outline_enabled) "ON" else "OFF"}), 10, 90, 20, if (outline_enabled) .dark_green else .dark_gray);
        rl.drawText(rl.textFormat("Bands: {d:.0}  [Q/E]", .{num_bands}), 10, 115, 20, .dark_gray);
    }
}
