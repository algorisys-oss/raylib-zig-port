//! raylib [models] example - point rendering
//!
//! Zig-API translation of examples/models/models_point_rendering.c (raylib 6.2).
//! Example contributed by Reese Gallagher (@satchelfrost) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2024-2025 Reese Gallagher (@satchelfrost)

const std = @import("std");
const rl = @import("raylib");

const max_points = 10000000; // 10 million
const min_points = 1000; // 1 thousand

// libc PRNG, as in the C example (rand(), RAND_MAX on glibc)
extern "c" fn rand() c_int;
const rand_max: f32 = 2147483648.0; // (float)RAND_MAX: 2147483647 rounds to 2^31

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - point rendering");
    defer rl.closeWindow();

    var camera: rl.Camera = .{
        .position = .{ .x = 3.0, .y = 3.0, .z = 3.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
    var use_draw_model_points = true;
    var num_points_changed = false;
    var num_points: i32 = 1000;

    var mesh = try genMeshPoints(num_points);
    var model = try rl.loadModelFromMesh(mesh);
    defer rl.unloadModel(model);

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        rl.updateCamera(&camera, .orbital);

        if (rl.isKeyPressed(.space)) use_draw_model_points = !use_draw_model_points;
        if (rl.isKeyPressed(.up)) {
            num_points = @min(num_points * 10, max_points);
            num_points_changed = true;
        }
        if (rl.isKeyPressed(.down)) {
            num_points = @max(@divTrunc(num_points, 10), min_points);
            num_points_changed = true;
        }

        // Upload a different point cloud size
        if (num_points_changed) {
            rl.unloadModel(model);
            mesh = try genMeshPoints(num_points);
            model = try rl.loadModelFromMesh(mesh);
            num_points_changed = false;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            // The new method only uploads the points once to the GPU
            if (use_draw_model_points) {
                drawModelPoints(model, position, 1.0, .white);
            } else {
                // The old method must continually draw the "points" (lines)
                const count: usize = @intCast(num_points);
                const vertices = mesh.vertices.?[0 .. count * 3];
                const colors = mesh.colors.?[0 .. count * 4];
                for (0..count) |i| {
                    const v = vertices[i * 3 ..][0..3];
                    const c = colors[i * 4 ..][0..4];
                    rl.drawPoint3D(.{ .x = v[0], .y = v[1], .z = v[2] }, .{ .r = c[0], .g = c[1], .b = c[2], .a = c[3] });
                }
            }

            // Draw a unit sphere for reference
            rl.drawSphereWires(position, 1.0, 10, 10, .yellow);
        }

        // Draw UI text
        rl.drawText(rl.textFormat("Point Count: {d}", .{num_points}), 10, screen_height - 50, 40, .white);
        rl.drawText("UP - Increase points", 10, 40, 20, .white);
        rl.drawText("DOWN - Decrease points", 10, 70, 20, .white);
        rl.drawText("SPACE - Drawing function", 10, 100, 20, .white);

        if (use_draw_model_points) {
            rl.drawText("Using: DrawModelPoints()", 10, 130, 20, .green);
        } else {
            rl.drawText("Using: DrawPoint3D()", 10, 130, 20, .red);
        }

        rl.drawFPS(10, 10);
    }
}

/// Generate a spherical point cloud
fn genMeshPoints(num_points: i32) !rl.Mesh {
    const count: usize = @intCast(num_points);
    const vertices: [*]f32 = @ptrCast(@alignCast(rl.memAlloc(@intCast(count * 3 * @sizeOf(f32))) orelse return error.OutOfMemory));
    const colors: [*]u8 = @ptrCast(rl.memAlloc(@intCast(count * 4)) orelse return error.OutOfMemory);

    var mesh = std.mem.zeroes(rl.Mesh);
    mesh.triangleCount = 1;
    mesh.vertexCount = num_points;
    mesh.vertices = vertices;
    mesh.colors = colors;

    // REF: https://en.wikipedia.org/wiki/Spherical_coordinate_system
    for (0..count) |i| {
        const theta = (rl.pi * randFloat()) / rand_max;
        const phi = (2.0 * rl.pi * randFloat()) / rand_max;
        const r = (10.0 * randFloat()) / rand_max;

        vertices[i * 3 ..][0..3].* = .{
            r * @sin(theta) * @cos(phi),
            r * @sin(theta) * @sin(phi),
            r * @cos(theta),
        };

        const color = rl.colorFromHSV(r * 360.0, 1.0, 1.0);
        colors[i * 4 ..][0..4].* = .{ color.r, color.g, color.b, color.a };
    }

    // Upload mesh data from CPU (RAM) to GPU (VRAM) memory
    rl.uploadMesh(&mesh, false);

    return mesh;
}

fn randFloat() f32 {
    return @floatFromInt(rand());
}

/// Draw a model as points
/// WARNING: OpenGL ES 2.0 does not support point mode drawing
fn drawModelPoints(model: rl.Model, position: rl.Vector3, scale: f32, tint: rl.Color) void {
    rl.gl.enablePointMode();
    rl.gl.disableBackfaceCulling();

    rl.drawModel(model, position, scale, tint);

    rl.gl.enableBackfaceCulling();
    rl.gl.disablePointMode();
}

/// Draw a model as points with extended parameters
/// WARNING: OpenGL ES 2.0 does not support point mode drawing
fn drawModelPointsEx(model: rl.Model, position: rl.Vector3, rotation_axis: rl.Vector3, rotation_angle: f32, scale: rl.Vector3, tint: rl.Color) void {
    rl.gl.enablePointMode();
    rl.gl.disableBackfaceCulling();

    rl.drawModelEx(model, position, rotation_axis, rotation_angle, scale, tint);

    rl.gl.enableBackfaceCulling();
    rl.gl.disablePointMode();
}
