//! raylib [models] example - bone socket
//!
//! Zig-API translation of examples/models/models_bone_socket.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2024-2025 iP (@ipzaur)

const std = @import("std");
const rl = @import("raylib");

// Equipment sockets, in index order: hat, right hand, left hand
const bone_sockets = 3;

/// Socket bone names in the character skeleton, by socket index.
const socket_bone_names = [bone_sockets][]const u8{ "socket_hat", "socket_hand_R", "socket_hand_L" };

/// Keys toggling each socket's equipment, by socket index.
const socket_toggle_keys = [bone_sockets]rl.KeyboardKey{ .one, .two, .three };

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - bone socket");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 5.0, .y = 5.0, .z = 5.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 2.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load gltf model
    var character_model = try rl.loadModel("resources/models/gltf/greenman.glb"); // Load character model
    defer rl.unloadModel(character_model);
    const equip_models = [bone_sockets]rl.Model{
        try rl.loadModel("resources/models/gltf/greenman_hat.glb"), // Index for the hat model is the same as the hat socket
        try rl.loadModel("resources/models/gltf/greenman_sword.glb"), // Index for the sword model is the same as the right hand socket
        try rl.loadModel("resources/models/gltf/greenman_shield.glb"), // Index for the shield model is the same as the left hand socket
    };
    // Unload equipment model and meshes/material
    defer for (equip_models) |model| rl.unloadModel(model);

    var show_equip: [bone_sockets]bool = @splat(true); // Toggle on/off equip

    // Load gltf model animations
    var anim_index: usize = 0;
    var anim_current_frame: u32 = 0;
    const model_animations = try rl.loadModelAnimations("resources/models/gltf/greenman.glb");
    defer rl.unloadModelAnimations(model_animations);

    // Search bones for sockets
    var bone_socket_index: [bone_sockets]?usize = @splat(null);
    const skeleton = character_model.skeleton;
    for (skeleton.bones.?[0..skeleton.boneCount], 0..) |bone, i| {
        const name = std.mem.sliceTo(&bone.name, 0);
        for (socket_bone_names, &bone_socket_index) |socket_name, *index| {
            if (std.mem.eql(u8, name, socket_name)) {
                index.* = i;
                break;
            }
        }
    }

    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model position
    var angle: u16 = 0; // Set angle for rotate character

    rl.disableCursor(); // Limit cursor to relative movement inside the window

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .third_person);

        // Rotate character
        if (rl.isKeyDown(.f)) {
            angle = (angle + 1) % 360;
        } else if (rl.isKeyDown(.h)) {
            angle = (360 + angle - 1) % 360;
        }

        // Select current animation
        if (rl.isKeyPressed(.t)) {
            anim_index = (anim_index + 1) % model_animations.len;
        } else if (rl.isKeyPressed(.g)) {
            anim_index = (anim_index + model_animations.len - 1) % model_animations.len;
        }

        // Toggle shown of equip
        for (socket_toggle_keys, &show_equip) |key, *show| {
            if (rl.isKeyPressed(key)) show.* = !show.*;
        }

        // Update model animation
        const anim = model_animations[anim_index];
        anim_current_frame = (anim_current_frame + 1) % @as(u32, @intCast(anim.keyframeCount));
        rl.updateModelAnimation(character_model, anim, @floatFromInt(anim_current_frame));

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            // Draw character
            const character_rotate = rl.math.quaternionFromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, @as(f32, @floatFromInt(angle)) * rl.deg2rad);
            character_model.transform = rl.math.matrixMultiply(rl.math.quaternionToMatrix(character_rotate), rl.math.matrixTranslate(position.x, position.y, position.z));
            rl.updateModelAnimation(character_model, anim, @floatFromInt(anim_current_frame));
            rl.drawMesh(character_model.meshes.?[0], character_model.materials.?[1], character_model.transform);

            // Draw equipments (hat, sword, shield)
            const pose = anim.keyframePoses.?[anim_current_frame].?;
            for (equip_models, show_equip, bone_socket_index) |equip_model, show, socket_index| {
                if (!show) continue;

                const bone = socket_index.?;
                const transform = pose[bone];
                const in_rotation = skeleton.bindPose.?[bone].rotation;
                const out_rotation = transform.rotation;

                // Calculate socket rotation (angle between bone in initial pose and same bone in current animation frame)
                const rotate = rl.math.quaternionMultiply(out_rotation, rl.math.quaternionInvert(in_rotation));
                var matrix_transform = rl.math.quaternionToMatrix(rotate);
                // Translate socket to its position in the current animation
                matrix_transform = rl.math.matrixMultiply(matrix_transform, rl.math.matrixTranslate(transform.translation.x, transform.translation.y, transform.translation.z));
                // Transform the socket using the transform of the character (angle and translate)
                matrix_transform = rl.math.matrixMultiply(matrix_transform, character_model.transform);

                // Draw mesh at socket position with socket angle rotation
                rl.drawMesh(equip_model.meshes.?[0], equip_model.materials.?[1], matrix_transform);
            }

            rl.drawGrid(10, 1.0);
        }

        rl.drawText("Use the T/G to switch animation", 10, 10, 20, .gray);
        rl.drawText("Use the F/H to rotate character left/right", 10, 35, 20, .gray);
        rl.drawText("Use the 1,2,3 to toggle shown of hat, sword and shield", 10, 60, 20, .gray);
    }
}
