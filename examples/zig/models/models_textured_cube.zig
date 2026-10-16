//! raylib [models] example - textured cube
//!
//! Zig-API translation of examples/models/models_textured_cube.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2022-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - textured cube");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    const camera: rl.Camera = .{
        .position = .{ .x = 0.0, .y = 10.0, .z = 10.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    // Load texture to be applied to the cubes sides
    const texture = try rl.loadTexture("resources/cubicmap_atlas.png");
    defer rl.unloadTexture(texture); // Unload texture

    const tex_width: f32 = @floatFromInt(texture.width);
    const tex_height: f32 = @floatFromInt(texture.height);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            // Draw cube with an applied texture
            drawCubeTexture(texture, .{ .x = -2.0, .y = 2.0, .z = 0.0 }, 2.0, 4.0, 2.0, .white);

            // Draw cube with an applied texture, but only a defined rectangle piece of the texture
            drawCubeTextureRec(
                texture,
                .{ .x = 0.0, .y = tex_height / 2.0, .width = tex_width / 2.0, .height = tex_height / 2.0 },
                .{ .x = 2.0, .y = 1.0, .z = 0.0 },
                2.0,
                2.0,
                2.0,
                .white,
            );

            rl.drawGrid(10, 1.0); // Draw a grid
        }

        rl.drawFPS(10, 10);
    }
}

/// Draw cube textured
/// NOTE: Cube position is the center position
fn drawCubeTexture(texture: rl.Texture2D, position: rl.Vector3, width: f32, height: f32, length: f32, color: rl.Color) void {
    // The whole texture: same as drawCubeTextureRec() with uv rect (0, 0)-(1, 1)
    drawCubeUv(texture, .{ .u0 = 0.0, .v0 = 0.0, .u1 = 1.0, .v1 = 1.0 }, position, width, height, length, color, .flipped);
}

/// Draw cube with texture piece applied to all faces
fn drawCubeTextureRec(texture: rl.Texture2D, source: rl.Rectangle, position: rl.Vector3, width: f32, height: f32, length: f32, color: rl.Color) void {
    const tex_width: f32 = @floatFromInt(texture.width);
    const tex_height: f32 = @floatFromInt(texture.height);

    // We calculate the normalized texture coordinates for the desired texture-source-rectangle
    // It means converting from (tex.width, tex.height) coordinates to [0.0, 1.0] equivalent
    const uv: Uv = .{
        .u0 = source.x / tex_width,
        .v0 = source.y / tex_height,
        .u1 = (source.x + source.width) / tex_width,
        .v1 = (source.y + source.height) / tex_height,
    };
    drawCubeUv(texture, uv, position, width, height, length, color, .upright);
}

/// Normalized texture rectangle: (u0, v0) top-left, (u1, v1) bottom-right.
const Uv = struct { u0: f32, v0: f32, u1: f32, v1: f32 };

/// drawCubeTexture() maps the texture bottom-up (v0 at the bottom edge of each
/// face), drawCubeTextureRec() top-down.
const VOrientation = enum { flipped, upright };

fn drawCubeUv(texture: rl.Texture2D, uv: Uv, position: rl.Vector3, width: f32, height: f32, length: f32, color: rl.Color, orientation: VOrientation) void {
    const x = position.x;
    const y = position.y;
    const z = position.z;

    // Bottom/top texture rows of every face
    const vb, const vt = switch (orientation) {
        .flipped => .{ uv.v0, uv.v1 },
        .upright => .{ uv.v1, uv.v0 },
    };
    const l = uv.u0;
    const r = uv.u1;

    // Set desired texture to be enabled while drawing following vertex data
    rl.gl.setTexture(texture.id);
    defer rl.gl.setTexture(0);

    rl.gl.begin(rl.gl.quads);
    defer rl.gl.end();
    rl.gl.color4ub(color.r, color.g, color.b, color.a);

    // Front Face
    rl.gl.normal3f(0.0, 0.0, 1.0); // Normal Pointing Towards Viewer
    vertex(l, vb, x - width / 2, y - height / 2, z + length / 2); // Bottom Left Of The Texture and Quad
    vertex(r, vb, x + width / 2, y - height / 2, z + length / 2); // Bottom Right Of The Texture and Quad
    vertex(r, vt, x + width / 2, y + height / 2, z + length / 2); // Top Right Of The Texture and Quad
    vertex(l, vt, x - width / 2, y + height / 2, z + length / 2); // Top Left Of The Texture and Quad
    // Back Face
    rl.gl.normal3f(0.0, 0.0, -1.0); // Normal Pointing Away From Viewer
    vertex(r, vb, x - width / 2, y - height / 2, z - length / 2); // Bottom Right Of The Texture and Quad
    vertex(r, vt, x - width / 2, y + height / 2, z - length / 2); // Top Right Of The Texture and Quad
    vertex(l, vt, x + width / 2, y + height / 2, z - length / 2); // Top Left Of The Texture and Quad
    vertex(l, vb, x + width / 2, y - height / 2, z - length / 2); // Bottom Left Of The Texture and Quad
    // Top Face
    rl.gl.normal3f(0.0, 1.0, 0.0); // Normal Pointing Up
    vertex(l, vt, x - width / 2, y + height / 2, z - length / 2); // Top Left Of The Texture and Quad
    vertex(l, vb, x - width / 2, y + height / 2, z + length / 2); // Bottom Left Of The Texture and Quad
    vertex(r, vb, x + width / 2, y + height / 2, z + length / 2); // Bottom Right Of The Texture and Quad
    vertex(r, vt, x + width / 2, y + height / 2, z - length / 2); // Top Right Of The Texture and Quad
    // Bottom Face
    rl.gl.normal3f(0.0, -1.0, 0.0); // Normal Pointing Down
    vertex(r, vt, x - width / 2, y - height / 2, z - length / 2); // Top Right Of The Texture and Quad
    vertex(l, vt, x + width / 2, y - height / 2, z - length / 2); // Top Left Of The Texture and Quad
    vertex(l, vb, x + width / 2, y - height / 2, z + length / 2); // Bottom Left Of The Texture and Quad
    vertex(r, vb, x - width / 2, y - height / 2, z + length / 2); // Bottom Right Of The Texture and Quad
    // Right face
    rl.gl.normal3f(1.0, 0.0, 0.0); // Normal Pointing Right
    vertex(r, vb, x + width / 2, y - height / 2, z - length / 2); // Bottom Right Of The Texture and Quad
    vertex(r, vt, x + width / 2, y + height / 2, z - length / 2); // Top Right Of The Texture and Quad
    vertex(l, vt, x + width / 2, y + height / 2, z + length / 2); // Top Left Of The Texture and Quad
    vertex(l, vb, x + width / 2, y - height / 2, z + length / 2); // Bottom Left Of The Texture and Quad
    // Left Face
    rl.gl.normal3f(-1.0, 0.0, 0.0); // Normal Pointing Left
    vertex(l, vb, x - width / 2, y - height / 2, z - length / 2); // Bottom Left Of The Texture and Quad
    vertex(r, vb, x - width / 2, y - height / 2, z + length / 2); // Bottom Right Of The Texture and Quad
    vertex(r, vt, x - width / 2, y + height / 2, z + length / 2); // Top Right Of The Texture and Quad
    vertex(l, vt, x - width / 2, y + height / 2, z - length / 2); // Top Left Of The Texture and Quad
}

fn vertex(u: f32, v: f32, x: f32, y: f32, z: f32) void {
    rl.gl.texCoord2f(u, v);
    rl.gl.vertex3f(x, y, z);
}
