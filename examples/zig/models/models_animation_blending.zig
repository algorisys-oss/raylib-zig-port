//! raylib [models] example - animation blending
//!
//! Zig-API translation of examples/models/models_animation_blending.c (raylib 6.2).
//! Example contributed by Kirandeep (@Kirandeep-Singh-Khehra) and reviewed by Ramon Santamaria (@raysan5)
//! WARNING: GPU skinning must be enabled in raylib with a compilation flag,
//! if not enabled, CPU skinning will be used instead
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2024-2026 Kirandeep (@Kirandeep-Singh-Khehra) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");

/// The animation's name, as the NUL-terminated string raygui lists.
fn animName(anim: *const rl.ModelAnimation) [*:0]const u8 {
    return anim.name[0..std.mem.indexOfScalar(u8, &anim.name, 0).? :0];
}

/// Advance `frame` by `speed`, looping over the animation's keyframes.
fn advanceFrame(frame: *f32, speed: f32, anim: rl.ModelAnimation) void {
    frame.* += speed;
    if (frame.* >= @as(f32, @floatFromInt(anim.keyframeCount))) frame.* = 0.0;
}

/// Draw a playing timeline with a tick per keyframe of `anim`.
fn drawTimeline(y: f32, label: [:0]const u8, progress: *f32, anim: rl.ModelAnimation) void {
    const screen_width = rl.getScreenWidth();
    const keyframe_count: f32 = @floatFromInt(anim.keyframeCount);

    _ = gui.progressBar(
        .{ .x = 60, .y = y, .width = @as(f32, @floatFromInt(screen_width)) - 180.0, .height = 20 },
        label,
        rl.textFormat("FRAME: {d:.2} / {d}", .{ progress.*, anim.keyframeCount }),
        progress,
        0.0,
        keyframe_count,
    );
    for (0..@intCast(anim.keyframeCount)) |i| {
        const tick = (@as(f32, @floatFromInt(screen_width - 180)) / keyframe_count) * @as(f32, @floatFromInt(i));
        rl.drawRectangle(60 + @as(i32, @intFromFloat(tick)), @intFromFloat(y), 1, 20, .blue);
    }
}

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - animation blending");
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
    const model = try rl.loadModel("resources/models/gltf/robot.glb"); // Load character model
    defer rl.unloadModel(model); // Unload model and meshes/material
    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model world position

    // NOTE: The C example loads a GPU skinning shader only `#if SUPPORT_GPU_SKINNING`,
    // a raylib config.h flag that is not visible to programs, so it is never loaded.

    // Load model animations
    const anims = try rl.loadModelAnimations("resources/models/gltf/robot.glb");
    defer rl.unloadModelAnimations(anims); // Unload model animation

    // Animation playing variables
    // NOTE: Two animations are played with a smooth transition between them
    var current_anim_playing: u1 = 0; // Current animation playing (0 o 1)
    var next_anim_to_play: u1 = 1; // Next animation to play (to transition)
    var anim_transition = false; // Flag to register anim transition state

    var anim_index0: i32 = 10; // Current animation playing (walking)
    var anim_current_frame0: f32 = 0.0; // Current animation frame (supporting interpolated frames)
    var anim_frame_speed0: f32 = 0.5; // Current animation play speed
    var anim_index1: i32 = 6; // Next animation to play (running)
    var anim_current_frame1: f32 = 0.0; // Next animation frame (supporting interpolated frames)
    var anim_frame_speed1: f32 = 0.5; // Next animation play speed

    var anim_blend_factor: f32 = 0.0; // Blend factor from anim0[frame0] --> anim1[frame1], [0.0f..1.0f]
    // NOTE: 0.0f results in full anim0[] and 1.0f in full anim1[]

    const anim_blend_time: f32 = 2.0; // Time to blend from one playing animation to another (in seconds)
    var anim_blend_time_counter: f32 = 0.0; // Time counter (delta time)

    var anim_pause = false; // Pause animation

    // UI required variables
    var anim_names_buffer: [64][*:0]const u8 = undefined; // Pointers to animation names for dropdown box
    const anim_names = anim_names_buffer[0..anims.len];
    for (anim_names, anims) |*name, *anim| name.* = animName(anim);

    var dropdown_edit_mode0 = false;
    var dropdown_edit_mode1 = false;
    var anim_frame_progress0: f32 = 0.0;
    var anim_frame_progress1: f32 = 0.0;
    var anim_blend_progress: f32 = 0.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        if (rl.isKeyPressed(.p)) anim_pause = !anim_pause;

        if (!anim_pause and anims.len > 0) { // Animations could fail to load
            const anim0 = anims[@intCast(anim_index0)];
            const anim1 = anims[@intCast(anim_index1)];

            // Start transition from anim0[] to anim1[]
            if (rl.isKeyPressed(.space) and !anim_transition) {
                if (current_anim_playing == 0) {
                    // Transition anim0 --> anim1
                    next_anim_to_play = 1;
                    anim_current_frame1 = 0.0;
                } else {
                    // Transition anim1 --> anim0
                    next_anim_to_play = 0;
                    anim_current_frame0 = 0.0;
                }

                // Set animation transition
                anim_transition = true;
                anim_blend_time_counter = 0.0;
                anim_blend_factor = 0.0;
            }

            if (anim_transition) {
                // Playing anim0 and anim1 at the same time
                advanceFrame(&anim_current_frame0, anim_frame_speed0, anim0);
                advanceFrame(&anim_current_frame1, anim_frame_speed1, anim1);

                // Increment blend factor over time to transition from anim0 --> anim1 over time
                // NOTE: Time blending could be other than linear, using some easing
                anim_blend_factor = anim_blend_time_counter / anim_blend_time;
                anim_blend_time_counter += rl.getFrameTime();
                anim_blend_progress = anim_blend_factor;

                // Update model with animations blending
                switch (next_anim_to_play) {
                    // Blend anim0 --> anim1
                    1 => rl.updateModelAnimationEx(model, anim0, anim_current_frame0, anim1, anim_current_frame1, anim_blend_factor),
                    // Blend anim1 --> anim0
                    0 => rl.updateModelAnimationEx(model, anim1, anim_current_frame1, anim0, anim_current_frame0, anim_blend_factor),
                }

                // Check if transition completed
                if (anim_blend_factor > 1.0) {
                    // Reset frame states
                    switch (current_anim_playing) {
                        0 => anim_current_frame0 = 0.0,
                        1 => anim_current_frame1 = 0.0,
                    }
                    current_anim_playing = next_anim_to_play; // Update current animation playing

                    anim_blend_factor = 0.0; // Reset blend factor
                    anim_transition = false; // Exit transition mode
                    anim_blend_time_counter = 0.0;
                }
            } else {
                // Play only one anim, the current one, at its defined speed
                switch (current_anim_playing) {
                    0 => {
                        advanceFrame(&anim_current_frame0, anim_frame_speed0, anim0);
                        rl.updateModelAnimation(model, anim0, anim_current_frame0);
                    },
                    1 => {
                        advanceFrame(&anim_current_frame1, anim_frame_speed1, anim1);
                        rl.updateModelAnimation(model, anim1, anim_current_frame1);
                    },
                }
            }
        }

        // Update progress bars values with current frame for each animation
        anim_frame_progress0 = anim_current_frame0;
        anim_frame_progress1 = anim_current_frame1;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(model, position, 1.0, .white); // Draw animated model

            rl.drawGrid(10, 1.0);
        }

        if (anim_transition) rl.drawText("ANIM TRANSITION BLENDING!", 170, 50, 30, .blue);

        const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_h: f32 = @floatFromInt(rl.getScreenHeight());

        // Draw UI elements
        if (dropdown_edit_mode0) gui.disable();
        _ = gui.slider(.{ .x = 10, .y = 38, .width = 160, .height = 12 }, null, rl.textFormat("x{d:.1}", .{anim_frame_speed0}), &anim_frame_speed0, 0.1, 2.0);
        gui.enable();
        if (dropdown_edit_mode1) gui.disable();
        _ = gui.slider(.{ .x = screen_w - 170.0, .y = 38, .width = 160, .height = 12 }, rl.textFormat("{d:.1}x", .{anim_frame_speed1}), null, &anim_frame_speed1, 0.1, 2.0);
        gui.enable();

        // Draw animation selectors for blending transition
        // NOTE: Transition does not start until requested
        gui.setStyle(.dropdownbox, gui.DropdownBoxProperty.dropdown_items_spacing, 1);
        if (gui.dropdownBox(.{ .x = 10, .y = 10, .width = 160, .height = 24 }, rl.textJoin(anim_names, ";"), &anim_index0, dropdown_edit_mode0) != 0) dropdown_edit_mode0 = !dropdown_edit_mode0;

        // Blending process progress bar
        const side: i32 = switch (next_anim_to_play) {
            1 => 0, // Left-->Right
            0 => 1, // Right-->Left
        };
        gui.setStyle(.progressbar, gui.ProgressBarProperty.side, side);
        _ = gui.progressBar(.{ .x = 180, .y = 14, .width = 440, .height = 16 }, null, null, &anim_blend_progress, 0.0, 1.0);
        gui.setStyle(.progressbar, gui.ProgressBarProperty.side, 0); // Reset to Left-->Right

        if (gui.dropdownBox(.{ .x = screen_w - 170.0, .y = 10, .width = 160, .height = 24 }, rl.textJoin(anim_names, ";"), &anim_index1, dropdown_edit_mode1) != 0) dropdown_edit_mode1 = !dropdown_edit_mode1;

        gui.setStyle(.label, gui.ControlProperty.text_alignment, @backingInt(gui.TextAlignment.center));
        gui.setStyle(.default, gui.DefaultProperty.text_size, gui.getFont().baseSize * 2);
        _ = gui.label(.{ .x = 0, .y = screen_h - 100.0, .width = screen_w, .height = 40 }, "PRESS SPACE to START BLENDING");
        gui.setStyle(.default, gui.DefaultProperty.text_size, gui.getFont().baseSize);
        gui.setStyle(.label, gui.ControlProperty.text_alignment, @backingInt(gui.TextAlignment.left));

        if (anims.len > 0) {
            // Draw playing timeline with keyframes for anim0[]
            drawTimeline(screen_h - 60.0, "ANIM 0", &anim_frame_progress0, anims[@intCast(anim_index0)]);

            // Draw playing timeline with keyframes for anim1[]
            drawTimeline(screen_h - 30.0, "ANIM 1", &anim_frame_progress1, anims[@intCast(anim_index1)]);
        }
    }
}
