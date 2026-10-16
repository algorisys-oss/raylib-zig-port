//! raylib [models] example - procedural decals
//!
//! Example demonstrates projecting decals onto a 3D mesh surface by transforming the
//! mesh's own triangles into the decal's local space and clipping them against a box,
//! using only procedurally generated geometry and textures (no external resource files)
//!
//! NOTE: This is the same clip-space decal projection idea used by models_decals.c
//! (in turn based on three.js' DecalGeometry), applied here to a generated mesh and
//! generated textures instead of a loaded model, so the example is fully self-contained
//!
//! Zig-API translation of examples/models/models_procedural_decals.c (raylib 6.2).
//! Example contributed by PanicTitan (@PanicTitan) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 PanicTitan (@PanicTitan)

const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");
const math = rl.math;

const max_decals = 256;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const gpa = debug_allocator.allocator();

    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [models] example - procedural decals");
    defer rl.closeWindow(); // Close window and OpenGL context

    var camera: rl.Camera3D = .{
        .position = .{ .x = 0.0, .y = 2.5, .z = 5.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    // Target model: a procedurally generated knot with a checkerboard skin
    const model = try rl.loadModelFromMesh(rl.genMeshTorus(0.8, 1.8, 32, 64));
    defer rl.unloadModel(model);

    const checker_image = rl.genImageChecked(512, 512, 32, 32, .light_gray, .gray);
    const model_texture = try rl.loadTextureFromImage(checker_image);
    defer rl.unloadTexture(model_texture);
    rl.unloadImage(checker_image);
    rl.setTextureFilter(model_texture, .bilinear);
    model.materials.?[0].map(.diffuse).texture = model_texture;

    const model_bbox = rl.getMeshBoundingBox(model.meshes.?[0]);
    camera.target = math.vector3Lerp(model_bbox.min, model_bbox.max, 0.5);

    const model_size = @min(
        @min(@abs(model_bbox.max.x - model_bbox.min.x), @abs(model_bbox.max.y - model_bbox.min.y)),
        @abs(model_bbox.max.z - model_bbox.min.z),
    );

    const decal_size = model_size * 0.35;
    const decal_offset = 0.01;

    // Translucent cube previewing where the next decal will land
    var placement_cube = try rl.loadModelFromMesh(rl.genMeshCube(decal_size, decal_size, decal_size));
    defer rl.unloadModel(placement_cube);
    placement_cube.materials.?[0].map(.diffuse).color = .lime;

    // Decal texture: a procedurally drawn target/bullseye, no image file needed
    var decal_image = rl.genImageColor(128, 128, .blank);
    rl.imageDrawCircle(&decal_image, 64, 64, 60, .red);
    rl.imageDrawCircle(&decal_image, 64, 64, 45, .white);
    rl.imageDrawCircle(&decal_image, 64, 64, 30, .red);
    rl.imageDrawCircle(&decal_image, 64, 64, 15, .yellow);

    const decal_texture = try rl.loadTextureFromImage(decal_image);
    rl.unloadImage(decal_image);
    rl.setTextureFilter(decal_texture, .bilinear);

    const decal_material = rl.loadMaterialDefault();
    defer rl.unloadMaterial(decal_material); // Also unloads its diffuse map texture (decal_texture)
    decal_material.map(.diffuse).texture = decal_texture;
    decal_material.map(.diffuse).color = .ray_white;

    var show_model = true;
    var decals: [max_decals]rl.Model = undefined;
    var decal_count: usize = 0;
    defer for (decals[0..decal_count]) |decal| rl.unloadModel(decal);

    const zero = math.vector3Zero();

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isMouseButtonDown(.right)) rl.updateCamera(&camera, .third_person);

        // Cast a ray from the mouse and keep the closest point it hits on the model
        const ray = rl.getScreenToWorldRay(rl.getMousePosition(), camera);
        var collision = std.mem.zeroes(rl.RayCollision);

        if (rl.getRayCollisionBox(ray, model_bbox).hit and decal_count < max_decals) {
            for (model.meshes.?[0..@intCast(model.meshCount)]) |mesh| {
                const mesh_hit = rl.getRayCollisionMesh(ray, mesh, model.transform);
                if (mesh_hit.hit and (!collision.hit or mesh_hit.distance < collision.distance)) collision = mesh_hit;
            }
        }

        // Project a new decal at the hit point, facing along the surface normal
        if (collision.hit and rl.isMouseButtonPressed(.left) and decal_count < max_decals) {
            const look_target = math.vector3Add(collision.point, collision.normal);
            var splat = math.matrixLookAt(collision.point, look_target, .{ .x = 0.0, .y = 1.0, .z = 0.0 });
            splat = math.matrixMultiply(splat, math.matrixRotateZ(rl.deg2rad * @as(f32, @floatFromInt(rl.getRandomValue(-180, 180)))));

            if (try genMeshDecal(gpa, model, splat, decal_size, decal_offset)) |decal_mesh| {
                const decal = try rl.loadModelFromMesh(decal_mesh);
                decal.materials.?[0].map(.diffuse).* = decal_material.map(.diffuse).*;
                decals[decal_count] = decal;
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

            if (show_model) rl.drawModel(model, zero, 1.0, .white);

            for (decals[0..decal_count]) |decal| rl.drawModel(decal, zero, 1.0, .white);

            // Preview cube at the surface point currently under the mouse
            if (collision.hit) {
                const look_target = math.vector3Add(collision.point, collision.normal);
                const splat = math.matrixLookAt(collision.point, look_target, .{ .x = 0.0, .y = 1.0, .z = 0.0 });
                placement_cube.transform = math.matrixInvert(splat);
                rl.drawModel(placement_cube, zero, 1.0, rl.fade(.white, 0.5));
            }

            rl.drawGrid(10, 1.0);
        }

        // Vertex/triangle counts: base model vs total once decal geometry is added
        var base_vertices: i32 = 0;
        var base_triangles: i32 = 0;
        for (model.meshes.?[0..@intCast(model.meshCount)]) |mesh| {
            base_vertices += mesh.vertexCount;
            base_triangles += mesh.triangleCount;
        }

        var total_vertices = base_vertices;
        var total_triangles = base_triangles;
        for (decals[0..decal_count]) |decal| {
            total_vertices += decal.meshes.?[0].vertexCount;
            total_triangles += decal.meshes.?[0].triangleCount;
        }

        const stat_x = screen_width - 280;
        rl.drawText("Vertices", stat_x + 90, 10, 10, .lime);
        rl.drawText("Triangles", stat_x + 180, 10, 10, .lime);
        rl.drawText("Base Model", stat_x, 25, 10, .lime);
        rl.drawText(rl.textFormat("{d}", .{base_vertices}), stat_x + 90, 25, 10, .lime);
        rl.drawText(rl.textFormat("{d}", .{base_triangles}), stat_x + 180, 25, 10, .lime);
        rl.drawText("TOTAL", stat_x, 40, 10, .lime);
        rl.drawText(rl.textFormat("{d}", .{total_vertices}), stat_x + 90, 40, 10, .lime);
        rl.drawText(rl.textFormat("{d}", .{total_triangles}), stat_x + 180, 40, 10, .lime);

        if (gui.button(.{ .x = 10, .y = screen_height - 80.0, .width = 100, .height = 40 }, if (show_model) "Hide Model" else "Show Model") != 0) {
            show_model = !show_model;
        }

        if (gui.button(.{ .x = 120, .y = screen_height - 80.0, .width = 100, .height = 40 }, "Clear Decals") != 0) {
            for (decals[0..decal_count]) |decal| rl.unloadModel(decal);
            decal_count = 0;
        }

        rl.drawText("Left click: place decal   |   Right drag: orbit camera", 10, screen_height - 25, 10, .dark_gray);
        rl.drawFPS(10, 10);
    }
}

/// A triangle soup: vertices in groups of three.
const TriangleList = std.ArrayList(rl.Vector3);

/// Clips the segment [v0, v1] against the plane p.x = s, returning the intersection point
fn clipSegment(v0: rl.Vector3, v1: rl.Vector3, p: rl.Vector3, s: f32) rl.Vector3 {
    const d0 = math.vector3DotProduct(v0, p) - s;
    const d1 = math.vector3DotProduct(v1, p) - s;
    const t = d0 / (d0 - d1);

    return math.vector3Lerp(v0, v1, t);
}

/// Builds a decal mesh: the model's triangles are transformed into the decal's local space
/// (so the decal sits at the origin, facing +Z) and clipped against a decal_size-sided box,
/// following the same clip-space projection idea used by engines' decal systems (and by
/// three.js' DecalGeometry, which the technique is commonly traced back to). What's left
/// after clipping becomes the decal's own small mesh, UV-mapped from its local coordinates.
/// Returns null when nothing of the model lies inside the decal box.
fn genMeshDecal(gpa: std.mem.Allocator, model: rl.Model, projection: rl.Matrix, decal_size: f32, decal_offset: f32) !?rl.Mesh {
    const inv_proj = math.matrixInvert(projection);

    // Two triangle lists: each clipping pass reads from one and writes to the other
    var lists: [2]TriangleList = .{ .empty, .empty };
    defer for (&lists) |*list| list.deinit(gpa);
    var list_index: usize = 0;

    // Gather triangles that land anywhere near the decal box; this is a loose, cheap
    // pre-filter meant to skip most of the model, the precise clip happens below
    for (model.meshes.?[0..@intCast(model.meshCount)]) |mesh| {
        const vertices = mesh.vertices.?;

        for (0..@intCast(mesh.triangleCount)) |tri| {
            var triangle: [3]rl.Vector3 = undefined;

            for (&triangle, 0..) |*vertex, v| {
                const index: usize = if (mesh.indices) |indices| indices[3 * tri + v] else 3 * tri + v;
                vertex.* = .{ .x = vertices[3 * index + 0], .y = vertices[3 * index + 1], .z = vertices[3 * index + 2] };
            }

            var inside_count: usize = 0;
            for (&triangle) |*vertex| {
                const v = math.vector3Transform(vertex.*, projection);
                if (@abs(v.x) < decal_size or @abs(v.y) <= decal_size or @abs(v.z) <= decal_size) inside_count += 1;
                vertex.* = v;
            }

            if (inside_count > 0) try lists[list_index].appendSlice(gpa, &triangle);
        }
    }

    // Clip the surviving triangles against each of the decal box's 6 faces in turn
    const planes = [6]rl.Vector3{
        .{ .x = 1, .y = 0, .z = 0 }, .{ .x = -1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 }, .{ .x = 0, .y = -1, .z = 0 },
        .{ .x = 0, .y = 0, .z = 1 }, .{ .x = 0, .y = 0, .z = -1 },
    };

    const s = 0.5 * decal_size;

    for (planes) |plane| {
        list_index = 1 - list_index;

        const in = lists[1 - list_index].items;
        const out = &lists[list_index];
        out.clearRetainingCapacity();

        for (0..in.len / 3) |t| {
            const v = in[3 * t ..][0..3].*;

            var outside: [3]bool = undefined;
            for (v, &outside) |vertex, *is_out| is_out.* = math.vector3DotProduct(vertex, plane) - s > 0;
            const total = @as(u8, @intFromBool(outside[0])) + @intFromBool(outside[1]) + @intFromBool(outside[2]);

            switch (total) {
                // Whole triangle is inside this face, keep it as-is
                0 => try out.appendSlice(gpa, &v),
                // One corner is outside; clip it off, turning the triangle into a quad
                1 => if (outside[0]) {
                    const n1 = v[1];
                    const n2 = v[2];
                    const n3 = clipSegment(v[0], n1, plane, s);
                    const n4 = clipSegment(v[0], n2, plane, s);
                    try out.appendSlice(gpa, &.{ n1, n2, n3, n4, n3, n2 });
                } else if (outside[1]) {
                    const n1 = v[0];
                    const n2 = v[2];
                    const n3 = clipSegment(v[1], n1, plane, s);
                    const n4 = clipSegment(v[1], n2, plane, s);
                    try out.appendSlice(gpa, &.{ n3, n2, n1, n2, n3, n4 });
                } else {
                    const n1 = v[0];
                    const n2 = v[1];
                    const n3 = clipSegment(v[2], n1, plane, s);
                    const n4 = clipSegment(v[2], n2, plane, s);
                    try out.appendSlice(gpa, &.{ n1, n2, n3, n4, n3, n2 });
                },
                // Two corners are outside; only the small corner near the surviving vertex remains
                2 => {
                    const k = std.mem.indexOfScalar(bool, &outside, false).?;
                    const n1 = v[k];
                    const n2 = clipSegment(n1, v[(k + 1) % 3], plane, s);
                    const n3 = clipSegment(n1, v[(k + 2) % 3], plane, s);
                    try out.appendSlice(gpa, &.{ n1, n2, n3 });
                },
                // All 3 corners are outside this face, the triangle is fully clipped away
                else => {},
            }
        }
    }

    const decal = lists[list_index].items;
    if (decal.len == 0) return null;

    // Converts the triangle soup into a standard uploaded raylib Mesh (its buffers are owned and freed by raylib)
    const vertices = try rl.mem_allocator.alloc(f32, decal.len * 3);
    errdefer rl.mem_allocator.free(vertices);
    const texcoords = try rl.mem_allocator.alloc(f32, decal.len * 2);
    errdefer rl.mem_allocator.free(texcoords);

    for (decal, 0..) |vertex, i| {
        // Clipped coordinates run roughly (-decal_size/2 .. decal_size/2); remap to (0..1)
        texcoords[2 * i + 0] = vertex.x / decal_size + 0.5;
        texcoords[2 * i + 1] = vertex.y / decal_size + 0.5;

        // Nudge slightly along the normal so the decal doesn't z-fight with the surface
        var nudged = vertex;
        nudged.z -= decal_offset;
        const world = math.vector3Transform(nudged, inv_proj);
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
