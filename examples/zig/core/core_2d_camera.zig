//! raylib [core] example - 2d camera
//!
//! Zig-API translation of examples/core/core_2d_camera.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const max_buildings = 100;

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - 2d camera");
    defer rl.closeWindow(); // Close window and OpenGL context

    var player: rl.Rectangle = .{ .x = 400, .y = 280, .width = 40, .height = 40 };
    var buildings: [max_buildings]rl.Rectangle = undefined;
    var build_colors: [max_buildings]rl.Color = undefined;

    var spacing: i32 = 0;

    for (&buildings, &build_colors) |*building, *color| {
        building.width = @floatFromInt(rl.getRandomValue(50, 200));
        building.height = @floatFromInt(rl.getRandomValue(100, 800));
        building.y = screen_height - 130.0 - building.height;
        building.x = -6000.0 + @as(f32, @floatFromInt(spacing));

        spacing += @intFromFloat(building.width);

        color.* = .{
            .r = @intCast(rl.getRandomValue(200, 240)),
            .g = @intCast(rl.getRandomValue(200, 240)),
            .b = @intCast(rl.getRandomValue(200, 250)),
            .a = 255,
        };
    }

    var camera: rl.Camera2D = .{
        .target = .{ .x = player.x + 20.0, .y = player.y + 20.0 },
        .offset = .{
            .x = @as(f32, @floatFromInt(rl.getRenderWidth())) / 2.0,
            .y = @as(f32, @floatFromInt(rl.getRenderHeight())) / 2.0,
        },
        .rotation = 0.0,
        .zoom = 1.0,
    };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Player movement
        if (rl.isKeyDown(.right)) {
            player.x += 2;
        } else if (rl.isKeyDown(.left)) {
            player.x -= 2;
        }

        // Camera target follows player
        camera.target = .{ .x = player.x + 20, .y = player.y + 20 };

        // Camera rotation controls
        if (rl.isKeyDown(.a)) {
            camera.rotation -= 1;
        } else if (rl.isKeyDown(.s)) {
            camera.rotation += 1;
        }

        // Limit camera rotation to 80 degrees (-40 to 40)
        camera.rotation = std.math.clamp(camera.rotation, -40, 40);

        // Camera zoom controls
        // Uses log scaling to provide consistent zoom speed
        camera.zoom = @exp(@log(camera.zoom) + rl.getMouseWheelMove() * 0.1);
        camera.zoom = std.math.clamp(camera.zoom, 0.1, 3.0);

        // Camera reset (zoom and rotation)
        if (rl.isKeyPressed(.r)) {
            camera.zoom = 1.0;
            camera.rotation = 0.0;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode2D(camera);
            defer rl.endMode2D();

            rl.drawRectangle(-6000, 320, 13000, 8000, .dark_gray);

            for (buildings, build_colors) |building, color| rl.drawRectangleRec(building, color);

            rl.drawRectangleRec(player, .red);

            const target_x: i32 = @intFromFloat(camera.target.x);
            const target_y: i32 = @intFromFloat(camera.target.y);
            rl.drawLine(target_x, -screen_height * 10, target_x, screen_height * 10, .green);
            rl.drawLine(-screen_width * 10, target_y, screen_width * 10, target_y, .green);
        }

        rl.drawText("SCREEN AREA", 640, 10, 20, .red);

        rl.drawRectangle(0, 0, screen_width, 5, .red);
        rl.drawRectangle(0, 5, 5, screen_height - 10, .red);
        rl.drawRectangle(screen_width - 5, 5, 5, screen_height - 10, .red);
        rl.drawRectangle(0, screen_height - 5, screen_width, 5, .red);

        rl.drawRectangle(10, 10, 250, 113, rl.fade(.sky_blue, 0.5));
        rl.drawRectangleLines(10, 10, 250, 113, .blue);

        rl.drawText("Free 2D camera controls:", 20, 20, 10, .black);
        rl.drawText("- Right/Left to move player", 40, 40, 10, .dark_gray);
        rl.drawText("- Mouse Wheel to Zoom in-out", 40, 60, 10, .dark_gray);
        rl.drawText("- A / S to Rotate", 40, 80, 10, .dark_gray);
        rl.drawText("- R to reset Zoom and Rotation", 40, 100, 10, .dark_gray);
    }
}
