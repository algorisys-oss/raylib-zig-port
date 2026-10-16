//! raylib [models] example - loading iqm
//!
//! Zig-API translation of examples/models/models_loading_iqm.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Culacant (@culacant) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - loading iqm");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 10.0, .y = 10.0, .z = 10.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 4.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera mode type
    };

    const model = try rl.loadModel("resources/models/iqm/guy.iqm"); // Load the animated model mesh and basic data
    defer rl.unloadModel(model);
    const texture = try rl.loadTexture("resources/models/iqm/guytex.png"); // Load model texture and set material
    defer rl.unloadTexture(texture);
    rl.setMaterialTexture(&model.materials.?[0], .diffuse, texture); // Set model material map texture
    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model position

    // Load animation data
    const anims = try rl.loadModelAnimations("resources/models/iqm/guyanim.iqm");
    defer rl.unloadModelAnimations(anims);

    // Animation playing variables
    var anim_index: usize = 0; // Current animation playing
    var anim_current_frame: f32 = 0.0; // Current animation frame (supporting interpolated frames)
    var anim_speed: f32 = 1.0; // How fast the animation plays

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        if (rl.isKeyPressed(.right)) {
            anim_index = if (anim_index == anims.len - 1) 0 else anim_index + 1;
            anim_current_frame = 0.0;
        }
        if (rl.isKeyPressed(.left)) {
            anim_index = if (anim_index == 0) anims.len - 1 else anim_index - 1;
            anim_current_frame = 0.0;
        }

        if (rl.isKeyPressed(.up)) anim_speed = @min(5.0, anim_speed + 0.1);
        if (rl.isKeyPressed(.down)) anim_speed = @max(0.0, anim_speed - 0.1);

        const anim = anims[anim_index];
        anim_current_frame += anim_speed;
        rl.updateModelAnimation(model, anim, anim_current_frame);
        if (anim_current_frame >= @as(f32, @floatFromInt(anim.keyframeCount))) anim_current_frame = 0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModelEx(model, position, .{ .x = 1.0, .y = 0.0, .z = 0.0 }, -90.0, .{ .x = 1.0, .y = 1.0, .z = 1.0 }, .white);

            rl.drawGrid(10, 1.0);
        }

        rl.drawText(rl.textFormat("Current animation: {s}", .{anim.nameSlice()}), 10, 10, 20, .maroon);
        rl.drawText(rl.textFormat("Animation speed: {d:.2}", .{anim_speed}), 10, 40, 20, .maroon);
        rl.drawText("Use left and right arrow keys to change current animation", 10, screen_height - 34, 10, .black);
        rl.drawText("Use up and down arrow keys to change animation speed", 10, screen_height - 20, 10, .black);
        rl.drawText("(c) Guy IQM 3D model by @culacant", screen_width - 200, screen_height - 20, 10, .gray);
    }
}
