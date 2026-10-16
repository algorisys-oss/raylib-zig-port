//! raylib [models] example - decals
//!
//! Example contributed by JP Mortiboys (@themushroompirates) and reviewed by Ramon Santamaria (@raysan5)
//! Based on previous work by @mrdoob
//!
//! Zig-API translation of examples/models/models_decals.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 JP Mortiboys (@themushroompirates) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const max_decals = 256;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const gpa = debug_allocator.allocator();

    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [models] example - decals");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Load character model
    const model = try rl.loadModel("resources/models/obj/character.obj");
    defer rl.unloadModel(model);

    // Apply character skin
    const model_texture = try rl.loadTexture("resources/models/obj/character_diffuse.png");
    defer rl.unloadTexture(model_texture);
    rl.setTextureFilter(model_texture, .bilinear);
    model.materials.?[0].map(.diffuse).texture = model_texture;

    const model_bbox = rl.getMeshBoundingBox(model.meshes.?[0]); // Get mesh bounding box

    const model_size = @min(
        @min(@abs(model_bbox.max.x - model_bbox.min.x), @abs(model_bbox.max.y - model_bbox.min.y)),
        @abs(model_bbox.max.z - model_bbox.min.z),
    );

    // Define the camera to look into our 3d world, framing the model
    var camera: rl.Camera = .{
        .position = .{ .x = 0.0, .y = model_bbox.max.y * 1.2, .z = model_size * 3.0 }, // Camera position
        .target = rl.math.vector3Lerp(model_bbox.min, model_bbox.max, 0.5), // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.6, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const decal_size = model_size * 0.25;
    const decal_offset = 0.01;

    var placement_cube = try rl.loadModelFromMesh(rl.genMeshCube(decal_size, decal_size, decal_size));
    defer rl.unloadModel(placement_cube);
    placement_cube.materials.?[0].map(.diffuse).color = .lime;

    const decal_material = rl.loadMaterialDefault();
    defer rl.unloadMaterial(decal_material); // Also unloads its diffuse map texture (decal_texture)
    decal_material.map(.diffuse).color = .yellow;

    var decal_image = try rl.loadImage("resources/raylib_logo.png");
    rl.imageResizeNN(&decal_image, @divTrunc(decal_image.width, 4), @divTrunc(decal_image.height, 4));
    const decal_texture = try rl.loadTextureFromImage(decal_image);
    rl.unloadImage(decal_image);

    rl.setTextureFilter(decal_texture, .bilinear);
    decal_material.map(.diffuse).texture = decal_texture;
    decal_material.map(.diffuse).color = .ray_white;

    var show_model = true;
    var decal_models: [max_decals]rl.Model = undefined;
    var decal_count: usize = 0;
    // Unload decal models
    defer for (decal_models[0..decal_count]) |decal_model| rl.unloadModel(decal_model);

    var decal_builder: DecalBuilder = .{};
    defer decal_builder.deinit(gpa); // Free the data for decal generation

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isMouseButtonDown(.right)) rl.updateCamera(&camera, .third_person);

        // Display information about closest hit
        var collision: rl.RayCollision = .{
            .hit = false,
            .distance = std.math.floatMax(f32),
            .point = .{ .x = 0, .y = 0, .z = 0 },
            .normal = .{ .x = 0, .y = 0, .z = 0 },
        };

        // Get mouse ray
        const ray = rl.getScreenToWorldRay(rl.getMousePosition(), camera);

        // Check ray collision against bounding box first, before trying the full ray-mesh test
        const box_hit_info = rl.getRayCollisionBox(ray, model_bbox);

        if (box_hit_info.hit and decal_count < max_decals) {
            // Check ray collision against model meshes
            var mesh_hit_info = std.mem.zeroes(rl.RayCollision);
            for (model.meshes.?[0..@intCast(model.meshCount)]) |mesh| {
                // NOTE: We consider the model.transform for the collision check but
                // it can be checked against any transform Matrix, used when checking against same
                // model drawn multiple times with multiple transforms
                mesh_hit_info = rl.getRayCollisionMesh(ray, mesh, model.transform);
                // Save the closest hit mesh
                if (mesh_hit_info.hit and (!collision.hit or collision.distance > mesh_hit_info.distance)) {
                    collision = mesh_hit_info;
                }
            }

            if (mesh_hit_info.hit) collision = mesh_hit_info;
        }

        // Add decal to mesh on hit point
        if (collision.hit and rl.isMouseButtonPressed(.left) and decal_count < max_decals) {
            // Create the transformation to project the decal
            const origin = rl.math.vector3Add(collision.point, rl.math.vector3Scale(collision.normal, 1.0));
            var splat = rl.math.matrixLookAt(collision.point, origin, .{ .x = 0.0, .y = 1.0, .z = 0.0 });

            // Spin the placement around a bit
            splat = rl.math.matrixMultiply(splat, rl.math.matrixRotateZ(rl.deg2rad * @as(f32, @floatFromInt(rl.getRandomValue(-180, 180)))));

            if (try decal_builder.genMesh(gpa, model, splat, decal_size, decal_offset)) |decal_mesh| {
                const decal_model = try rl.loadModelFromMesh(decal_mesh);
                decal_model.materials.?[0].map(.diffuse).* = decal_material.map(.diffuse).*;
                decal_models[decal_count] = decal_model;
                decal_count += 1;
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            const zero: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };

            // Draw the model at the origin and default scale
            if (show_model) rl.drawModel(model, zero, 1.0, .white);

            // Draw the decal models
            for (decal_models[0..decal_count]) |decal_model| rl.drawModel(decal_model, zero, 1.0, .white);

            // If we hit the mesh, draw the box for the decal
            if (collision.hit) {
                const origin = rl.math.vector3Add(collision.point, rl.math.vector3Scale(collision.normal, 1.0));
                const splat = rl.math.matrixLookAt(collision.point, origin, .{ .x = 0, .y = 1, .z = 0 });
                placement_cube.transform = rl.math.matrixInvert(splat);
                rl.drawModel(placement_cube, zero, 1.0, rl.fade(.white, 0.5));
            }

            rl.drawGrid(10, 10.0);
        }

        var y_pos: f32 = 10;
        const x0 = @as(f32, @floatFromInt(rl.getScreenWidth())) - 300.0;
        const x1 = x0 + 100;
        const x2 = x1 + 100;

        drawCell("Vertices", x1, y_pos);
        drawCell("Triangles", x2, y_pos);
        y_pos += 15;

        var vertex_count: i32 = 0;
        var triangle_count: i32 = 0;

        for (model.meshes.?[0..@intCast(model.meshCount)]) |mesh| {
            vertex_count += mesh.vertexCount;
            triangle_count += mesh.triangleCount;
        }

        drawCell("Main model", x0, y_pos);
        drawCell(rl.textFormat("{d}", .{vertex_count}), x1, y_pos);
        drawCell(rl.textFormat("{d}", .{triangle_count}), x2, y_pos);
        y_pos += 15;

        for (decal_models[0..decal_count], 0..) |decal_model, i| {
            const mesh = decal_model.meshes.?[0];

            if (i == 20) {
                drawCell("...", x0, y_pos);
                y_pos += 15;
            }

            if (i < 20) {
                drawCell(rl.textFormat("Decal #{d}", .{i + 1}), x0, y_pos);
                drawCell(rl.textFormat("{d}", .{mesh.vertexCount}), x1, y_pos);
                drawCell(rl.textFormat("{d}", .{mesh.triangleCount}), x2, y_pos);
                y_pos += 15;
            }

            vertex_count += mesh.vertexCount;
            triangle_count += mesh.triangleCount;
        }

        drawCell("TOTAL", x0, y_pos);
        drawCell(rl.textFormat("{d}", .{vertex_count}), x1, y_pos);
        drawCell(rl.textFormat("{d}", .{triangle_count}), x2, y_pos);
        y_pos += 15;

        rl.drawText("Hold RMB to move camera", 10, 430, 10, .gray);
        rl.drawText("(c) Character model and texture from kenney.nl", screen_width - 260, screen_height - 20, 10, .gray);

        // UI elements
        if (guiButton(.{ .x = 10, .y = screen_height - 100.0, .width = 100, .height = 60 }, if (show_model) "Hide Model" else "Show Model")) {
            show_model = !show_model;
        }

        if (guiButton(.{ .x = 10 + 110, .y = screen_height - 100.0, .width = 100, .height = 60 }, "Clear Decals")) {
            // Clear decals, unload all decal models
            for (decal_models[0..decal_count]) |decal_model| rl.unloadModel(decal_model);
            decal_count = 0;
        }

        rl.drawFPS(10, 10);
    }
}

/// Builds decal meshes by clipping a model's triangles against the decal box.
/// Holds two triangle lists (vertices in groups of three), reused across calls:
/// each clipping pass reads from one and writes to the other.
const DecalBuilder = struct {
    lists: [2]std.ArrayList(rl.Vector3) = .{ .empty, .empty },

    fn deinit(builder: *DecalBuilder, gpa: std.mem.Allocator) void {
        for (&builder.lists) |*list| list.deinit(gpa);
    }

    /// Generate mesh decals for provided model; null when the decal covers no triangle.
    fn genMesh(
        builder: *DecalBuilder,
        gpa: std.mem.Allocator,
        target: rl.Model,
        projection: rl.Matrix,
        decal_size: f32,
        decal_offset: f32,
    ) !?rl.Mesh {
        // We're going to need the inverse matrix
        const inv_proj = rl.math.matrixInvert(projection);

        // Reset the triangle lists
        for (&builder.lists) |*list| list.clearRetainingCapacity();

        // We'll be flip-flopping between the two lists
        // Reading from one and writing to the other, then swapping
        var list_index: usize = 0;

        // First pass, just get any triangle inside the bounding box (for each mesh of the model)
        for (target.meshes.?[0..@intCast(target.meshCount)]) |mesh| {
            const vertices = mesh.vertices.?;
            for (0..@intCast(mesh.triangleCount)) |tri| {
                var triangle: [3]rl.Vector3 = undefined;

                // The way we calculate the vertices of the mesh triangle
                // depend on whether the mesh vertices are indexed or not
                if (mesh.indices) |indices| {
                    for (&triangle, 0..) |*vertex, v| {
                        vertex.* = .{
                            .x = vertices[3 * @as(usize, indices[3 * tri + 0]) + v],
                            .y = vertices[3 * @as(usize, indices[3 * tri + 1]) + v],
                            .z = vertices[3 * @as(usize, indices[3 * tri + 2]) + v],
                        };
                    }
                } else {
                    for (&triangle, 0..) |*vertex, v| {
                        vertex.* = .{
                            .x = vertices[3 * 3 * tri + 3 * v + 0],
                            .y = vertices[3 * 3 * tri + 3 * v + 1],
                            .z = vertices[3 * 3 * tri + 3 * v + 2],
                        };
                    }
                }

                // Transform all 3 vertices of the triangle
                // and check if they are inside our decal box
                var inside_count: usize = 0;
                for (&triangle) |*vertex| {
                    // To projection space
                    const v = rl.math.vector3Transform(vertex.*, projection);

                    if (@abs(v.x) < decal_size or @abs(v.y) <= decal_size or @abs(v.z) <= decal_size) inside_count += 1;

                    // We need to keep the transformed vertex
                    vertex.* = v;
                }

                // If any of them are inside, we add the triangle - we'll clip it later
                if (inside_count > 0) try builder.lists[list_index].appendSlice(gpa, &triangle);
            }
        }

        // Clipping time! We need to clip against all 6 directions
        const planes = [6]rl.Vector3{
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = -1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
            .{ .x = 0, .y = -1, .z = 0 },
            .{ .x = 0, .y = 0, .z = 1 },
            .{ .x = 0, .y = 0, .z = -1 },
        };

        const s = 0.5 * decal_size;

        for (planes) |plane| {
            // Swap current list (so we read from the one we just wrote to)
            list_index = 1 - list_index;

            const in = builder.lists[1 - list_index].items;
            const out = &builder.lists[list_index];

            // Reset write list
            out.clearRetainingCapacity();

            for (0..in.len / 3) |t| {
                const v = in[3 * t ..][0..3].*;

                // Calculate, how many vertices of the face lie outside of the clipping plane
                var outside: [3]bool = undefined;
                for (v, &outside) |vertex, *is_out| is_out.* = rl.math.vector3DotProduct(vertex, plane) - s > 0;
                const total = @as(u8, @intFromBool(outside[0])) + @intFromBool(outside[1]) + @intFromBool(outside[2]);

                switch (total) {
                    // The entire face lies inside of the plane, no clipping needed
                    0 => try out.appendSlice(gpa, &v),
                    // One vertex lies outside of the plane, perform clipping
                    1 => if (outside[0]) {
                        const n1 = v[1];
                        const n2 = v[2];
                        const n3 = clipSegment(v[0], n1, plane, s);
                        const n4 = clipSegment(v[0], n2, plane, s);
                        try out.appendSlice(gpa, &.{ n1, n2, n3 });
                        try out.appendSlice(gpa, &.{ n4, n3, n2 });
                    } else if (outside[1]) {
                        const n1 = v[0];
                        const n2 = v[2];
                        const n3 = clipSegment(v[1], n1, plane, s);
                        const n4 = clipSegment(v[1], n2, plane, s);
                        try out.appendSlice(gpa, &.{ n3, n2, n1 });
                        try out.appendSlice(gpa, &.{ n2, n3, n4 });
                    } else {
                        const n1 = v[0];
                        const n2 = v[1];
                        const n3 = clipSegment(v[2], n1, plane, s);
                        const n4 = clipSegment(v[2], n2, plane, s);
                        try out.appendSlice(gpa, &.{ n1, n2, n3 });
                        try out.appendSlice(gpa, &.{ n4, n3, n2 });
                    },
                    // Two vertices lie outside of the plane: keep the inside one,
                    // clipping its edges towards the next two vertices (in winding order)
                    2 => {
                        const k = std.mem.indexOfScalar(bool, &outside, false).?;
                        const n1 = v[k];
                        const n2 = clipSegment(n1, v[(k + 1) % 3], plane, s);
                        const n3 = clipSegment(n1, v[(k + 2) % 3], plane, s);
                        try out.appendSlice(gpa, &.{ n1, n2, n3 });
                    },
                    // The entire face lies outside of the plane, so let's discard the corresponding vertices
                    else => {},
                }
            }
        }

        // Now we just need to re-transform the vertices
        const decal = builder.lists[list_index].items;

        // Return no mesh when there's nothing to add
        if (decal.len == 0) return null;

        // Decal model data ready, create the mesh (its buffers are owned and freed by raylib)
        const vertices = try rl.mem_allocator.alloc(f32, decal.len * 3);
        errdefer rl.mem_allocator.free(vertices);
        const texcoords = try rl.mem_allocator.alloc(f32, decal.len * 2);
        errdefer rl.mem_allocator.free(texcoords);

        for (decal, 0..) |vertex, i| {
            // Calculate the UVs based on the projected coords
            // They are clipped to (-decal_size .. decal_size) and we want them (0..1)
            texcoords[2 * i + 0] = vertex.x / decal_size + 0.5;
            texcoords[2 * i + 1] = vertex.y / decal_size + 0.5;

            // Tiny nudge in the normal direction so it renders properly over the mesh
            var nudged = vertex;
            nudged.z -= decal_offset;

            // From projection space to world space
            const world = rl.math.vector3Transform(nudged, inv_proj);
            vertices[3 * i ..][0..3].* = .{ world.x, world.y, world.z };
        }

        var mesh = std.mem.zeroes(rl.Mesh);
        mesh.vertexCount = @intCast(decal.len);
        mesh.triangleCount = @intCast(decal.len / 3);
        mesh.vertices = vertices.ptr;
        mesh.texcoords = texcoords.ptr;

        rl.uploadMesh(&mesh, false);

        return mesh;
    }
};

/// Clip segment
fn clipSegment(v0: rl.Vector3, v1: rl.Vector3, p: rl.Vector3, s: f32) rl.Vector3 {
    const d0 = rl.math.vector3DotProduct(v0, p) - s;
    const d1 = rl.math.vector3DotProduct(v1, p) - s;
    const s0 = d0 / (d0 - d1);

    return rl.math.vector3Lerp(v0, v1, s0);
}

/// Draw one cell of the vertex/triangle count table
fn drawCell(text: [:0]const u8, x: f32, y: f32) void {
    rl.drawText(text, @intFromFloat(x), @intFromFloat(y), 10, .lime);
}

/// Button UI element
fn guiButton(rec: rl.Rectangle, label: [:0]const u8) bool {
    var bg_color: rl.Color = .gray;
    var pressed = false;

    if (rl.checkCollisionPointRec(rl.getMousePosition(), rec)) {
        bg_color = .light_gray;
        pressed = rl.isMouseButtonPressed(.left);
    }

    rl.drawRectangleRec(rec, bg_color);
    rl.drawRectangleLinesEx(rec, 2.0, .dark_gray);

    const font_size = 10;
    const text_width: f32 = @floatFromInt(rl.measureText(label, font_size));

    rl.drawText(label, @intFromFloat(rec.x + rec.width * 0.5 - text_width * 0.5), @intFromFloat(rec.y + rec.height * 0.5 - font_size * 0.5), font_size, .dark_gray);

    return pressed;
}
