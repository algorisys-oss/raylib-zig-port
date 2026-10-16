//! raylib [models] example - loading gltf
//!
//! Zig-API translation of examples/models/models_loading_gltf.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2020-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - loading gltf");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 6.0, .y = 6.0, .z = 6.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 2.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load model
    const model = try rl.loadModel("resources/models/gltf/robot.glb");
    defer rl.unloadModel(model);
    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model world position

    // Load model animations
    const anims = try rl.loadModelAnimations("resources/models/gltf/robot.glb");
    defer rl.unloadModelAnimations(anims);

    // Animation playing variables
    var anim_index: usize = 0; // Current animation playing
    var anim_current_frame: u32 = 0; // Current animation frame

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        // Select current animation
        if (rl.isKeyPressed(.right)) {
            anim_index = (anim_index + 1) % anims.len;
        } else if (rl.isKeyPressed(.left)) {
            anim_index = (anim_index + anims.len - 1) % anims.len;
        }

        // Update model animation
        const anim = anims[anim_index];
        anim_current_frame = (anim_current_frame + 1) % @as(u32, @intCast(anim.keyframeCount));
        rl.updateModelAnimation(model, anim, @floatFromInt(anim_current_frame));

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(model, position, 1.0, .white);

            rl.drawGrid(10, 1.0);
        }

        rl.drawText(rl.textFormat("Current animation: {s}", .{std.mem.sliceTo(&anim.name, 0)}), 10, 40, 20, .maroon);
        rl.drawText("Use the LEFT/RIGHT keys to switch animation", 10, 10, 20, .gray);
    }
}
