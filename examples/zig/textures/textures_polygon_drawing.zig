//! raylib [textures] example - polygon drawing
//!
//! Zig-API translation of examples/textures/textures_polygon_drawing.c (raylib 6.2).
//! Example contributed by Chris Camacho (@chriscamacho) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2021-2025 Chris Camacho (@chriscamacho) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const max_points = 11; // 10 points and back to the start

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - polygon drawing");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define texture coordinates to map our texture to poly
    const texcoords = [max_points]rl.Vector2{
        .{ .x = 0.75, .y = 0.0 },
        .{ .x = 0.25, .y = 0.0 },
        .{ .x = 0.0, .y = 0.5 },
        .{ .x = 0.0, .y = 0.75 },
        .{ .x = 0.25, .y = 1.0 },
        .{ .x = 0.375, .y = 0.875 },
        .{ .x = 0.625, .y = 0.875 },
        .{ .x = 0.75, .y = 1.0 },
        .{ .x = 1.0, .y = 0.75 },
        .{ .x = 1.0, .y = 0.5 },
        .{ .x = 0.75, .y = 0.0 }, // Close the poly
    };

    // Define the base poly vertices from the UV's
    // NOTE: They can be specified in any other way
    var points: [max_points]rl.Vector2 = undefined;
    for (&points, texcoords) |*point, uv| {
        point.* = .{ .x = (uv.x - 0.5) * 256.0, .y = (uv.y - 0.5) * 256.0 };
    }

    // Define the vertices drawing position
    // NOTE: Initially same as points but updated every frame
    var positions = points;

    // Load texture to be mapped to poly
    const texture = try rl.loadTexture("resources/cat.png");
    defer rl.unloadTexture(texture); // Unload texture

    var angle: f32 = 0.0; // Rotation angle (in degrees)

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Update points rotation with an angle transform
        // NOTE: Base points position are not modified
        angle += 1;
        for (&positions, points) |*position, point| position.* = rl.math.vector2Rotate(point, angle * rl.deg2rad);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("textured polygon", 20, 20, 20, .dark_gray);

        const center: rl.Vector2 = .{
            .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
            .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
        };
        drawTexturePoly(texture, center, &positions, &texcoords, .white);
    }
}

/// Draw textured polygon, defined by vertex and texture coordinates
/// NOTE: Polygon center must have straight line path to all points
/// without crossing perimeter, points must be in anticlockwise order
fn drawTexturePoly(texture: rl.Texture2D, center: rl.Vector2, points: []const rl.Vector2, texcoords: []const rl.Vector2, tint: rl.Color) void {
    rl.gl.setTexture(texture.id);
    defer rl.gl.setTexture(0);

    rl.gl.begin(rl.gl.triangles);
    defer rl.gl.end();

    rl.gl.color4ub(tint.r, tint.g, tint.b, tint.a);

    for (0..points.len - 1) |i| {
        rl.gl.texCoord2f(0.5, 0.5);
        rl.gl.vertex2f(center.x, center.y);

        rl.gl.texCoord2f(texcoords[i].x, texcoords[i].y);
        rl.gl.vertex2f(points[i].x + center.x, points[i].y + center.y);

        rl.gl.texCoord2f(texcoords[i + 1].x, texcoords[i + 1].y);
        rl.gl.vertex2f(points[i + 1].x + center.x, points[i + 1].y + center.y);
    }
}
