//! raylib [shaders] example - lightmap rendering
//!
//! Zig-API translation of examples/shaders/shaders_lightmap_rendering.c (raylib 6.2).
//! Example contributed by Jussi Viitala (@nullstare) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Jussi Viitala (@nullstare) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

const map_size = 16;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true }); // Enable Multi Sampling Anti Aliasing 4x (if available)
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - lightmap rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 4.0, .y = 6.0, .z = 8.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    var mesh = rl.genMeshPlane(map_size, map_size, 1, 1);
    defer rl.unloadMesh(mesh); // Unload the mesh (frees texcoords2 too)

    // GenMeshPlane doesn't generate texcoords2 so we will upload them separately
    // NOTE: Allocated with raylib's allocator: unloadMesh() frees it
    const texcoords2_len: usize = @intCast(mesh.vertexCount * 2);
    const texcoords2_ptr: [*]f32 = @ptrCast(@alignCast(rl.memAlloc(@intCast(texcoords2_len * @sizeOf(f32))) orelse return error.OutOfMemory));
    const texcoords2 = texcoords2_ptr[0..texcoords2_len];
    mesh.texcoords2 = texcoords2.ptr;

    // X     Y
    texcoords2[0..8].* = .{
        0.0, 0.0,
        1.0, 0.0,
        0.0, 1.0,
        1.0, 1.0,
    };

    // Load a new texcoords2 attributes buffer
    mesh.vboId.?[@intCast(@backingInt(rl.ShaderLocationIndex.vertex_texcoord02))] = rl.gl.loadVertexBuffer(std.mem.sliceAsBytes(texcoords2), false);
    _ = rl.gl.enableVertexArray(mesh.vaoId);

    // Index 5 is for texcoords2
    rl.gl.setVertexAttribute(5, 2, rl.gl.float, false, 0, 0);
    rl.gl.enableVertexAttribute(5);
    rl.gl.disableVertexArray();

    // Load lightmap shader
    const shader = try rl.loadShader(
        rl.textFormat("resources/shaders/glsl{d}/lightmap.vs", .{glsl_version}),
        rl.textFormat("resources/shaders/glsl{d}/lightmap.fs", .{glsl_version}),
    );
    defer rl.unloadShader(shader); // Unload shader

    var texture = try rl.loadTexture("resources/cubicmap_atlas.png");
    defer rl.unloadTexture(texture); // Unload texture
    const light = try rl.loadTexture("resources/spark_flame.png");
    defer rl.unloadTexture(light); // Unload texture

    rl.genTextureMipmaps(&texture);
    rl.setTextureFilter(texture, .trilinear);

    var lightmap = try rl.loadRenderTexture(map_size, map_size);
    defer rl.unloadRenderTexture(lightmap); // Unload lightmap render texture

    var material = rl.loadMaterialDefault();
    material.shader = shader;
    material.map(.albedo).texture = texture;
    material.map(.metalness).texture = lightmap.texture;

    // Drawing to lightmap
    {
        rl.beginTextureMode(lightmap);
        defer rl.endTextureMode();

        rl.clearBackground(.black);

        rl.beginBlendMode(.additive);
        const light_rec: rl.Rectangle = .{ .x = 0, .y = 0, .width = @floatFromInt(light.width), .height = @floatFromInt(light.height) };
        rl.drawTexturePro(
            light,
            light_rec,
            .{ .x = 0, .y = 0, .width = 2.0 * map_size, .height = 2.0 * map_size },
            .{ .x = map_size, .y = map_size },
            0.0,
            .red,
        );
        rl.drawTexturePro(
            light,
            light_rec,
            .{ .x = map_size * 0.8, .y = map_size / 2.0, .width = 2.0 * map_size, .height = 2.0 * map_size },
            .{ .x = map_size, .y = map_size },
            0.0,
            .blue,
        );
        rl.drawTexturePro(
            light,
            light_rec,
            .{ .x = map_size * 0.8, .y = map_size * 0.8, .width = map_size, .height = map_size },
            .{ .x = map_size / 2.0, .y = map_size / 2.0 },
            0.0,
            .green,
        );
        rl.beginBlendMode(.alpha);
    }

    // NOTE: To enable trilinear filtering we need mipmaps available for texture
    rl.genTextureMipmaps(&lightmap.texture);
    rl.setTextureFilter(lightmap.texture, .trilinear);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawMesh(mesh, material, rl.math.matrixIdentity());
        }

        const render_width: f32 = @floatFromInt(rl.getRenderWidth());
        rl.drawTexturePro(
            lightmap.texture,
            .{ .x = 0, .y = 0, .width = -map_size, .height = -map_size },
            .{ .x = render_width - map_size * 8 - 10, .y = 10, .width = map_size * 8, .height = map_size * 8 },
            .{ .x = 0.0, .y = 0.0 },
            0.0,
            .white,
        );

        rl.drawText(rl.textFormat("LIGHTMAP: {d}x{d} pixels", .{ map_size, map_size }), rl.getRenderWidth() - 130, 20 + map_size * 8, 10, .green);

        rl.drawFPS(10, 10);
    }
}
