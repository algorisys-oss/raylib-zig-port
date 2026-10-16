//! raylib [models] example - animation timing
//!
//! Zig-API translation of examples/models/models_animation_timing.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const gui = @import("raygui");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - animation timing");
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
    defer rl.unloadModel(model); // Unload model and meshes/material
    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model world position

    // Load model animations
    const anims = try rl.loadModelAnimations("resources/models/gltf/robot.glb");
    defer rl.unloadModelAnimations(anims); // Unload model animation

    // Animation playing variables
    var anim_index: i32 = 10; // Current animation playing
    var anim_current_frame: f32 = 0.0; // Current animation frame (supporting interpolated frames)
    var anim_frame_speed: f32 = 0.5; // Animation play speed
    var anim_pause = false; // Pause animation

    // UI required variables
    var anim_names_buffer: [64][*:0]const u8 = undefined;
    const anim_names = anim_names_buffer[0..anims.len];
    for (anim_names, anims) |*name, *anim| name.* = @ptrCast(&anim.name);

    var dropdown_edit_mode = false;
    var anim_frame_progress: f32 = 0.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        if (rl.isKeyPressed(.p)) anim_pause = !anim_pause;

        if (!anim_pause and anim_index < anims.len) {
            // Update model animation
            const anim = anims[@intCast(anim_index)];
            anim_current_frame += anim_frame_speed;
            if (anim_current_frame >= @as(f32, @floatFromInt(anim.keyframeCount))) anim_current_frame = 0.0;
            rl.updateModelAnimation(model, anim, anim_current_frame);
        }

        // NOTE: Animation and playing speed selected through UI

        // Update progressbar value with current frame
        anim_frame_progress = anim_current_frame;

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

        // Draw UI, select anim and playing speed
        gui.setStyle(.dropdownbox, gui.DropdownBoxProperty.dropdown_items_spacing, 1);
        if (gui.dropdownBox(.{ .x = 10, .y = 10, .width = 140, .height = 24 }, rl.textJoin(anim_names, ";"), &anim_index, dropdown_edit_mode) != 0) {
            dropdown_edit_mode = !dropdown_edit_mode;
        }

        _ = gui.slider(.{ .x = 260, .y = 10, .width = 500, .height = 24 }, "FRAME SPEED: ", rl.textFormat("x{d:.1}", .{anim_frame_speed}), &anim_frame_speed, 0.1, 2.0);

        // Draw playing timeline with keyframes
        const keyframe_count = anims[@intCast(anim_index)].keyframeCount;
        const screen_w = rl.getScreenWidth();
        const screen_h = rl.getScreenHeight();
        _ = gui.label(
            .{ .x = 10, .y = @as(f32, @floatFromInt(screen_h)) - 64.0, .width = @as(f32, @floatFromInt(screen_w)) - 20.0, .height = 24 },
            rl.textFormat("CURRENT FRAME: {d:.2} / {d}", .{ anim_frame_progress, keyframe_count }),
        );
        _ = gui.progressBar(
            .{ .x = 10, .y = @as(f32, @floatFromInt(screen_h)) - 40.0, .width = @as(f32, @floatFromInt(screen_w)) - 20.0, .height = 24 },
            null,
            null,
            &anim_frame_progress,
            0.0,
            @floatFromInt(keyframe_count),
        );
        const keyframe_spacing = @as(f32, @floatFromInt(screen_w - 20)) / @as(f32, @floatFromInt(keyframe_count));
        for (0..@intCast(keyframe_count)) |i| {
            const x: i32 = @intFromFloat(keyframe_spacing * @as(f32, @floatFromInt(i)));
            rl.drawRectangle(10 + x, screen_h - 40, 1, 24, .blue);
        }
    }
}
