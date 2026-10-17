//! raylib [models] example - animation blend custom
//!
//! Zig-API translation of examples/models/models_animation_blend_custom.c (raylib 6.2).
//! Example contributed by dmitrii-brand (@dmitrii-brand) and reviewed by Ramon Santamaria (@raysan5)
//! WARNING: GPU skinning must be enabled in raylib with a compilation flag,
//! if not enabled, CPU skinning will be used instead
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 dmitrii-brand (@dmitrii-brand)

const std = @import("std");
const rl = @import("raylib");
const rm = rl.math;

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - animation blend custom");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 4.0, .y = 4.0, .z = 4.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    // Load gltf model
    var model = try rl.loadModel("resources/models/gltf/greenman.glb");
    defer rl.unloadModel(model); // Unload model and meshes/material
    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 }; // Set model position

    // Load skinning shader
    // WARNING: GPU skinning must be enabled in raylib with a compilation flag,
    // if not enabled, CPU skinning will be used instead
    const skinning_shader = try rl.loadShader(
        rl.textFormat("resources/shaders/glsl{d}/skinning.vs", .{glsl_version}),
        rl.textFormat("resources/shaders/glsl{d}/skinning.fs", .{glsl_version}),
    );
    defer rl.unloadShader(skinning_shader); // Unload GPU skinning shader
    model.materials.?[1].shader = skinning_shader;

    // Load gltf model animations
    const anims = try rl.loadModelAnimations("resources/models/gltf/greenman.glb");
    defer rl.unloadModelAnimations(anims); // Unload model animation

    // Use specific animation indices: 2-walk/move, 3-attack
    // Validate indices
    const anim_index0: usize = if (2 < anims.len) 2 else 0; // Walk/Move animation (index 2)
    const anim_index1: usize = if (3 < anims.len) 3 else if (anims.len > 1) 1 else 0; // Attack animation (index 3)
    var anim_current_frame0: i32 = 0;
    var anim_current_frame1: i32 = 0;

    var upper_body_blend = true; // Toggle: true = upper/lower body blending, false = uniform blending (50/50)

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        // Toggle upper/lower body blending mode (SPACE key)
        if (rl.isKeyPressed(.space)) upper_body_blend = !upper_body_blend;

        // Update animation frames
        const anim0 = anims[anim_index0];
        const anim1 = anims[anim_index1];

        anim_current_frame0 = @rem(anim_current_frame0 + 1, anim0.keyframeCount);
        anim_current_frame1 = @rem(anim_current_frame1 + 1, anim1.keyframeCount);

        // Blend the two animations
        // When upperBodyBlend is ON: upper body = attack (1.0), lower body = walk (0.0)
        // When upperBodyBlend is OFF: uniform blend at 0.5 (50% walk, 50% attack)
        const blend_factor: f32 = if (upper_body_blend) 1.0 else 0.5;
        updateModelAnimationBoneCustom(&model, anim0, anim_current_frame0, anim1, anim_current_frame1, blend_factor, upper_body_blend);

        // raylib provided animation blending function
        //rl.updateModelAnimationEx(model, anim0, @floatFromInt(anim_current_frame0),
        //    anim1, @floatFromInt(anim_current_frame1), blend_factor);

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

        // Draw UI
        rl.drawText(rl.textFormat("ANIM 0: {s}", .{anim0.nameSlice()}), 10, 10, 20, .gray);
        rl.drawText(rl.textFormat("ANIM 1: {s}", .{anim1.nameSlice()}), 10, 40, 20, .gray);
        rl.drawText(
            rl.textFormat("[SPACE] Toggle blending mode: {s}", .{if (upper_body_blend) "Upper/Lower Body Blending" else "Uniform Blending"}),
            10,
            rl.getScreenHeight() - 30,
            20,
            .dark_gray,
        );
    }
}

/// Check if a bone is part of upper body (for selective blending)
fn isUpperBodyBone(bone_name: []const u8) bool {
    // Common upper body bone names (adjust based on your model)
    const names = [_][]const u8{
        "spine",      "spine1",     "spine2",
        "chest",      "upperChest", "neck",
        "head",       "shoulder",   "shoulder_L",
        "shoulder_R", "upperArm",   "upperArm_L",
        "upperArm_R", "lowerArm",   "lowerArm_L",
        "lowerArm_R", "hand",       "hand_L",
        "hand_R",     "clavicle",   "clavicle_L",
        "clavicle_R",
    };
    for (names) |name| {
        if (std.mem.eql(u8, bone_name, name)) return true;
    }

    // Check if bone name contains upper body keywords
    const keywords = [_][]const u8{ "spine", "chest", "neck", "head", "shoulder", "arm", "hand", "clavicle" };
    for (keywords) |keyword| {
        if (std.mem.indexOf(u8, bone_name, keyword) != null) return true;
    }

    return false;
}

/// Blend two animations per-bone with selective upper/lower body blending
fn updateModelAnimationBoneCustom(model: *rl.Model, anim0: rl.ModelAnimation, frame0_in: i32, anim1: rl.ModelAnimation, frame1_in: i32, blend_in: f32, upper_body_blend: bool) void {
    // Validate inputs
    const poses0 = anim0.keyframePoses orelse return;
    const poses1 = anim1.keyframePoses orelse return;
    const bind_pose = model.skeleton.bindPose orelse return;
    if (anim0.boneCount == 0 or anim1.boneCount == 0 or model.skeleton.boneCount == 0) return;

    // Clamp blend factor to [0, 1]
    const blend = @min(1.0, @max(0.0, blend_in));

    // Ensure frame indices are valid
    const frame0: usize = @intCast(std.math.clamp(frame0_in, 0, anim0.keyframeCount - 1));
    const frame1: usize = @intCast(std.math.clamp(frame1_in, 0, anim1.keyframeCount - 1));

    // Get bone count (use minimum of all to be safe)
    const bone_count = @min(model.skeleton.boneCount, anim0.boneCount, anim1.boneCount);

    const bones = model.skeleton.bones.?;
    const bone_matrices = model.boneMatrices.?;

    // Blend each bone
    for (0..bone_count) |bone_index| {
        // Determine blend factor for this bone
        var bone_blend_factor = blend;

        // If upper body blending is enabled, use different blend factors for upper vs lower body
        if (upper_body_blend) {
            const bone_name = bones[bone_index].nameSlice();

            // Upper body: use anim1 (attack), Lower body: use anim0 (walk)
            // blend = 0.0 means full anim0 (walk), 1.0 means full anim1 (attack)
            bone_blend_factor = if (isUpperBodyBone(bone_name))
                blend // Upper body: blend towards anim1 (attack)
            else
                1.0 - blend; // Lower body: blend towards anim0 (walk) - invert the blend
        }

        // Get transforms from both animations
        const bind_transform = bind_pose[bone_index];
        const anim_transform0 = poses0[frame0].?[bone_index];
        const anim_transform1 = poses1[frame1].?[bone_index];

        // Blend the transforms
        const blended: rl.Transform = .{
            .translation = rm.vector3Lerp(anim_transform0.translation, anim_transform1.translation, bone_blend_factor),
            .rotation = rm.quaternionSlerp(anim_transform0.rotation, anim_transform1.rotation, bone_blend_factor),
            .scale = rm.vector3Lerp(anim_transform0.scale, anim_transform1.scale, bone_blend_factor),
        };

        // Convert bind pose and blended transform to matrices
        const bind_matrix = transformToMatrix(bind_transform);
        const blended_matrix = transformToMatrix(blended);

        // Calculate final bone matrix (similar to UpdateModelAnimationBones)
        bone_matrices[bone_index] = rm.matrixMultiply(rm.matrixInvert(bind_matrix), blended_matrix);
    }

    // CPU skinning, updates CPU buffers and uploads them to GPU (if available)
    // NOTE: Fallback in case GPU skinning is not supported or enabled
    for (model.meshSlice()) |mesh| {
        // Skip if missing bone data or missing anim buffers initialization
        const bone_weights = mesh.boneWeights orelse continue;
        const bone_indices = mesh.boneIndices orelse continue;
        const anim_vertices_ptr = mesh.animVertices orelse continue;
        const anim_normals_ptr = mesh.animNormals orelse continue;

        const vertex_values_count: usize = @intCast(mesh.vertexCount * 3);
        const vertices = mesh.vertices.?[0..vertex_values_count];
        const normals: ?[]const f32 = if (mesh.normals) |n| n[0..vertex_values_count] else null;
        const anim_vertices = anim_vertices_ptr[0..vertex_values_count];
        const anim_normals = anim_normals_ptr[0..vertex_values_count];

        var bone_counter: usize = 0;
        var buffer_update_required = false; // Flag to check when anim vertex information is updated

        var v_counter: usize = 0;
        while (v_counter < vertex_values_count) : (v_counter += 3) {
            const anim_vertex = anim_vertices[v_counter..][0..3];
            const anim_normal = anim_normals[v_counter..][0..3];
            anim_vertex.* = .{ 0, 0, 0 };
            anim_normal.* = .{ 0, 0, 0 };

            // Iterates over 4 bones per vertex
            for (0..4) |_| {
                defer bone_counter += 1;
                const bone_weight = bone_weights[bone_counter];
                const bone_matrix = bone_matrices[bone_indices[bone_counter]];

                // Early stop when no transformation will be applied
                if (bone_weight == 0.0) continue;
                const v = rm.vector3Transform(.{ .x = vertices[v_counter], .y = vertices[v_counter + 1], .z = vertices[v_counter + 2] }, bone_matrix);
                anim_vertex[0] += v.x * bone_weight;
                anim_vertex[1] += v.y * bone_weight;
                anim_vertex[2] += v.z * bone_weight;
                buffer_update_required = true;

                // Normals processing
                // NOTE: We use meshes.baseNormals (default normal) to calculate meshes.normals (animated normals)
                if (normals) |base_normals| {
                    const n = rm.vector3Transform(
                        .{ .x = base_normals[v_counter], .y = base_normals[v_counter + 1], .z = base_normals[v_counter + 2] },
                        rm.matrixTranspose(rm.matrixInvert(bone_matrix)),
                    );
                    anim_normal[0] += n.x * bone_weight;
                    anim_normal[1] += n.y * bone_weight;
                    anim_normal[2] += n.z * bone_weight;
                }
            }
        }

        if (buffer_update_required) {
            // Update GPU vertex buffers with updated data (position + normals)
            const vbo_id = mesh.vboId.?;
            rl.gl.updateVertexBuffer(vbo_id[@intCast(@backingInt(rl.ShaderLocationIndex.vertex_position))], std.mem.sliceAsBytes(anim_vertices), 0);
            if (normals != null) rl.gl.updateVertexBuffer(vbo_id[@intCast(@backingInt(rl.ShaderLocationIndex.vertex_normal))], std.mem.sliceAsBytes(anim_normals), 0);
        }
    }
}

/// Transform to matrix: scale, then rotate, then translate
fn transformToMatrix(t: rl.Transform) rl.Matrix {
    return rm.matrixMultiply(
        rm.matrixMultiply(rm.matrixScale(t.scale.x, t.scale.y, t.scale.z), rm.quaternionToMatrix(t.rotation)),
        rm.matrixTranslate(t.translation.x, t.translation.y, t.translation.z),
    );
}
