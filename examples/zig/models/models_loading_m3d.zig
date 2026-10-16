//! raylib [models] example - loading m3d
//!
//! Zig-API translation of examples/models/models_loading_m3d.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2022-2025 bzt (@bztsrc)

const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - loading m3d");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 1.5, .y = 1.5, .z = 1.5 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.4, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load model
    const model = try rl.loadModel("resources/models/m3d/cesium_man.m3d"); // Load the animated model mesh and basic data
    defer rl.unloadModel(model);
    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model position

    // Load animation data
    const anims = try rl.loadModelAnimations("resources/models/m3d/cesium_man.m3d");
    defer rl.unloadModelAnimations(anims);

    // Animation playing variables
    var anim_index: usize = 0; // Current animation playing
    var anim_current_frame: f32 = 0.0; // Current animation frame (supporting interpolated frames)

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
        anim_current_frame += 1.0;
        if (anim_current_frame >= @as(f32, @floatFromInt(anim.keyframeCount))) anim_current_frame = 0.0;
        rl.updateModelAnimation(model, anim, anim_current_frame);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            // Draw 3d model with texture
            if (!rl.isKeyDown(.space)) {
                rl.drawModel(model, position, 1.0, .white);
            } else {
                // Draw the animated skeleton
                const frame: usize = @intFromFloat(anim_current_frame);
                drawModelSkeleton(model.skeleton, anim.keyframePoses.?[frame], 1.0, .red);
            }

            rl.drawGrid(10, 1.0);
        }

        rl.drawText(rl.textFormat("Current animation: {s}", .{anim.nameSlice()}), 10, 10, 20, .light_gray);
        rl.drawText("Press SPACE to draw skeleton", 10, 40, 20, .maroon);
        rl.drawText("(c) CesiumMan model by KhronosGroup", rl.getScreenWidth() - 210, rl.getScreenHeight() - 20, 10, .gray);
    }
}

/// Draw model skeleton
fn drawModelSkeleton(skeleton: rl.ModelSkeleton, pose: rl.ModelAnimPose, scale: f32, color: rl.Color) void {
    const bone_count = skeleton.boneCount - 1;
    const transforms = pose.?[0..skeleton.boneCount];

    // Skip the last bone because it is a special "no bone" bone,
    // needed to workaround buggy models without a -1, a cube is always drawn at the origin
    for (skeleton.bones.?[0..bone_count], transforms[0..bone_count]) |bone, transform| {
        // Display the frame-pose skeleton
        rl.drawCube(transform.translation, scale * 0.05, scale * 0.05, scale * 0.05, color);

        if (bone.parent >= 0) {
            rl.drawLine3D(transform.translation, transforms[@intCast(bone.parent)].translation, color);
        }
    }
}
