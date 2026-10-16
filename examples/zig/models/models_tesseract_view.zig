//! raylib [models] example - tesseract view
//!
//! Zig-API translation of examples/models/models_tesseract_view.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2024-2025 Timothy van der Valk (@arceryz) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - tesseract view");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    const camera: rl.Camera = .{
        .position = .{ .x = 4.0, .y = 4.0, .z = 4.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, // Camera up vector (rotation towards target)
        .fovy = 50.0, // Camera field-of-view Y
        .projection = .perspective, // Camera mode type
    };

    // Find the coordinates by setting XYZW to +-1
    const tesseract = [16]rl.Vector4{
        .{ .x = 1, .y = 1, .z = 1, .w = 1 },    .{ .x = 1, .y = 1, .z = 1, .w = -1 },
        .{ .x = 1, .y = 1, .z = -1, .w = 1 },   .{ .x = 1, .y = 1, .z = -1, .w = -1 },
        .{ .x = 1, .y = -1, .z = 1, .w = 1 },   .{ .x = 1, .y = -1, .z = 1, .w = -1 },
        .{ .x = 1, .y = -1, .z = -1, .w = 1 },  .{ .x = 1, .y = -1, .z = -1, .w = -1 },
        .{ .x = -1, .y = 1, .z = 1, .w = 1 },   .{ .x = -1, .y = 1, .z = 1, .w = -1 },
        .{ .x = -1, .y = 1, .z = -1, .w = 1 },  .{ .x = -1, .y = 1, .z = -1, .w = -1 },
        .{ .x = -1, .y = -1, .z = 1, .w = 1 },  .{ .x = -1, .y = -1, .z = 1, .w = -1 },
        .{ .x = -1, .y = -1, .z = -1, .w = 1 }, .{ .x = -1, .y = -1, .z = -1, .w = -1 },
    };

    var transformed: [16]rl.Vector3 = undefined;
    var w_values: [16]f32 = undefined;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const rotation = rl.deg2rad * 45.0 * @as(f32, @floatCast(rl.getTime()));

        for (tesseract, &transformed, &w_values) |vertex, *out, *w| {
            var p = vertex;

            // Rotate the XW part of the vector
            const rot_xw = rl.math.vector2Rotate(.{ .x = p.x, .y = p.w }, rotation);
            p.x = rot_xw.x;
            p.w = rot_xw.y;

            // Projection from XYZW to XYZ from perspective point (0, 0, 0, 3)
            // NOTE: Trace a ray from (0, 0, 0, 3) > p and continue until W = 0
            const c = 3.0 / (3.0 - p.w);
            p.x = c * p.x;
            p.y = c * p.y;
            p.z = c * p.z;

            // Split XYZ coordinate and W values later for drawing
            out.* = .{ .x = p.x, .y = p.y, .z = p.z };
            w.* = p.w;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.beginMode3D(camera);
        defer rl.endMode3D();

        for (tesseract, transformed, w_values, 0..) |v1, point, w, i| {
            // Draw spheres to indicate the W value
            rl.drawSphere(point, @abs(w * 0.1), .red);

            for (tesseract, transformed, 0..) |v2, other, j| {
                // Two lines are connected if they differ by 1 coordinate
                // This way we dont have to keep an edge list
                const diff = @as(u8, @intFromBool(v1.x == v2.x)) + @intFromBool(v1.y == v2.y) +
                    @intFromBool(v1.z == v2.z) + @intFromBool(v1.w == v2.w);

                // Draw only differing by 1 coordinate and the lower index only (duplicate lines)
                if (diff == 3 and i < j) rl.drawLine3D(point, other, .maroon);
            }
        }
    }
}
