//! raylib [models] example - mesh generation
//!
//! Zig-API translation of examples/models/models_mesh_generation.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

/// Parametric 3d shape names, and where to draw them, by model index.
const labels = [_]struct { text: [:0]const u8, x: i32 }{
    .{ .text = "PLANE", .x = 680 },
    .{ .text = "CUBE", .x = 680 },
    .{ .text = "SPHERE", .x = 680 },
    .{ .text = "HEMISPHERE", .x = 640 },
    .{ .text = "CYLINDER", .x = 680 },
    .{ .text = "TORUS", .x = 680 },
    .{ .text = "KNOT", .x = 680 },
    .{ .text = "POLY", .x = 680 },
    .{ .text = "Custom (triangle)", .x = 580 },
};
const num_models = labels.len; // Parametric 3d shapes to generate

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - mesh generation");
    defer rl.closeWindow(); // Close window and OpenGL context

    // We generate a checked image for texturing
    const checked = rl.genImageChecked(2, 2, 1, 1, .red, .green);
    const texture = try rl.loadTextureFromImage(checked);
    defer rl.unloadTexture(texture);
    rl.unloadImage(checked);

    const models = [num_models]rl.Model{
        try rl.loadModelFromMesh(rl.genMeshPlane(2, 2, 4, 3)),
        try rl.loadModelFromMesh(rl.genMeshCube(2.0, 1.0, 2.0)),
        try rl.loadModelFromMesh(rl.genMeshSphere(2, 32, 32)),
        try rl.loadModelFromMesh(rl.genMeshHemiSphere(2, 16, 16)),
        try rl.loadModelFromMesh(rl.genMeshCylinder(1, 2, 16)),
        try rl.loadModelFromMesh(rl.genMeshTorus(0.25, 4.0, 16, 32)),
        try rl.loadModelFromMesh(rl.genMeshKnot(1.0, 2.0, 16, 128)),
        try rl.loadModelFromMesh(rl.genMeshPoly(5, 2.0)),
        try rl.loadModelFromMesh(try genMeshCustom()),
    };
    // Unload models data (GPU VRAM)
    defer for (models) |model| rl.unloadModel(model);

    // NOTE: Generated meshes could be exported using exportMesh()

    // Set checked texture as default diffuse component for all models material
    for (models) |model| model.materials.?[0].map(.diffuse).texture = texture;

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 5.0, .y = 5.0, .z = 5.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    // Model drawing position
    const position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };

    var current_model: usize = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        if (rl.isMouseButtonPressed(.left)) {
            current_model = (current_model + 1) % num_models; // Cycle between the textures
        }

        if (rl.isKeyPressed(.right)) {
            current_model = (current_model + 1) % num_models;
        } else if (rl.isKeyPressed(.left)) {
            current_model = if (current_model == 0) num_models - 1 else current_model - 1;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(models[current_model], position, 1.0, .white);
            rl.drawGrid(10, 1.0);
        }

        rl.drawRectangle(30, 400, 310, 30, rl.fade(.sky_blue, 0.5));
        rl.drawRectangleLines(30, 400, 310, 30, rl.fade(.dark_blue, 0.5));
        rl.drawText("MOUSE LEFT BUTTON to CYCLE PROCEDURAL MODELS", 40, 410, 10, .blue);

        const label = labels[current_model];
        rl.drawText(label.text, label.x, 10, 20, .dark_blue);
    }
}

/// Generate a simple triangle mesh from code
fn genMeshCustom() !rl.Mesh {
    // Vertex data is owned by the mesh (freed by unloadModel), so it comes from raylib's allocator
    const allocator = rl.mem_allocator;

    const vertices = try allocator.alloc(f32, 3 * 3); // 3 vertices, 3 coordinates each (x, y, z)
    const texcoords = try allocator.alloc(f32, 3 * 2); // 3 vertices, 2 coordinates each (x, y)
    const normals = try allocator.alloc(f32, 3 * 3); // 3 vertices, 3 coordinates each (x, y, z)

    vertices[0..9].* = .{
        0, 0, 0, // Vertex at (0, 0, 0)
        1, 0, 2, // Vertex at (1, 0, 2)
        2, 0, 0, // Vertex at (2, 0, 0)
    };
    normals[0..9].* = .{
        0, 1, 0,
        0, 1, 0,
        0, 1, 0,
    };
    texcoords[0..6].* = .{
        0,   0,
        0.5, 1.0,
        1,   0,
    };

    var mesh = std.mem.zeroes(rl.Mesh);
    mesh.triangleCount = 1;
    mesh.vertexCount = mesh.triangleCount * 3;
    mesh.vertices = vertices.ptr;
    mesh.texcoords = texcoords.ptr;
    mesh.normals = normals.ptr;

    // Upload mesh data from CPU (RAM) to GPU (VRAM) memory
    rl.uploadMesh(&mesh, false);

    return mesh;
}
