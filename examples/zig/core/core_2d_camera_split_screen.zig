//! raylib [core] example - 2d camera split screen
//!
//! Zig-API translation of examples/core/core_2d_camera_split_screen.c (raylib 6.2).
//! Example contributed by Gabriel dos Santos Sanches (@gabrielssanches) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 Gabriel dos Santos Sanches (@gabrielssanches)

const rl = @import("raylib");

const player_size = 40;

const screen_width = 800;
const screen_height = 440;

pub fn main() !void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [core] example - 2d camera split screen");
    defer rl.closeWindow(); // Close window and OpenGL context

    var player1: rl.Rectangle = .{ .x = 200, .y = 200, .width = player_size, .height = player_size };
    var player2: rl.Rectangle = .{ .x = 250, .y = 200, .width = player_size, .height = player_size };

    var camera1: rl.Camera2D = .{
        .target = .{ .x = player1.x, .y = player1.y },
        .offset = rl.math.vector2Multiply(.{ .x = 200.0, .y = 200.0 }, rl.getWindowScaleDPI()),
        .rotation = 0.0,
        .zoom = 1.0,
    };

    var camera2: rl.Camera2D = .{
        .target = .{ .x = player2.x, .y = player2.y },
        .offset = rl.math.vector2Multiply(.{ .x = 200.0, .y = 200.0 }, rl.getWindowScaleDPI()),
        .rotation = 0.0,
        .zoom = 1.0,
    };

    const screen_camera1 = try rl.loadRenderTexture(screen_width / 2, screen_height);
    defer rl.unloadRenderTexture(screen_camera1); // Unload render texture
    const screen_camera2 = try rl.loadRenderTexture(screen_width / 2, screen_height);
    defer rl.unloadRenderTexture(screen_camera2); // Unload render texture

    // Build a flipped rectangle the size of the split view to use for drawing later
    const split_screen_rect: rl.Rectangle = .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(screen_camera1.texture.width),
        .height = @floatFromInt(-screen_camera1.texture.height),
    };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyDown(.s)) {
            player1.y += 3.0;
        } else if (rl.isKeyDown(.w)) {
            player1.y -= 3.0;
        }
        if (rl.isKeyDown(.d)) {
            player1.x += 3.0;
        } else if (rl.isKeyDown(.a)) {
            player1.x -= 3.0;
        }

        if (rl.isKeyDown(.up)) {
            player2.y -= 3.0;
        } else if (rl.isKeyDown(.down)) {
            player2.y += 3.0;
        }
        if (rl.isKeyDown(.right)) {
            player2.x += 3.0;
        } else if (rl.isKeyDown(.left)) {
            player2.x -= 3.0;
        }

        camera1.target = .{ .x = player1.x, .y = player1.y };
        camera2.target = .{ .x = player2.x, .y = player2.y };

        // Draw
        {
            rl.beginTextureMode(screen_camera1);
            defer rl.endTextureMode();

            rl.clearBackground(.ray_white);

            // Draw full scene with first camera
            drawScene(camera1, player1, player2);

            rl.drawRectangle(0, 0, @divTrunc(rl.getScreenWidth(), 2), 30, rl.fade(.ray_white, 0.6));
            rl.drawText("PLAYER1: W/S/A/D to move", 10, 10, 10, .maroon);
        }

        {
            rl.beginTextureMode(screen_camera2);
            defer rl.endTextureMode();

            rl.clearBackground(.ray_white);

            // Draw full scene with second camera
            drawScene(camera2, player1, player2);

            rl.drawRectangle(0, 0, @divTrunc(rl.getScreenWidth(), 2), 30, rl.fade(.ray_white, 0.6));
            rl.drawText("PLAYER2: UP/DOWN/LEFT/RIGHT to move", 10, 10, 10, .dark_blue);
        }

        // Draw both views render textures to the screen side by side
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        rl.drawTextureRec(screen_camera1.texture, split_screen_rect, .{ .x = 0, .y = 0 }, .white);
        rl.drawTextureRec(screen_camera2.texture, split_screen_rect, .{ .x = screen_width / 2.0, .y = 0 }, .white);

        rl.drawRectangle(@divTrunc(rl.getScreenWidth(), 2) - 2, 0, 4, rl.getScreenHeight(), .light_gray);
    }
}

/// Draw the grid, its cell coordinates and both players, seen through `camera`.
fn drawScene(camera: rl.Camera2D, player1: rl.Rectangle, player2: rl.Rectangle) void {
    rl.beginMode2D(camera);
    defer rl.endMode2D();

    for (0..screen_width / player_size + 1) |i| {
        const x: f32 = @floatFromInt(player_size * i);
        rl.drawLineV(.{ .x = x, .y = 0 }, .{ .x = x, .y = screen_height }, .light_gray);
    }

    for (0..screen_height / player_size + 1) |i| {
        const y: f32 = @floatFromInt(player_size * i);
        rl.drawLineV(.{ .x = 0, .y = y }, .{ .x = screen_width, .y = y }, .light_gray);
    }

    for (0..screen_width / player_size) |i| {
        for (0..screen_height / player_size) |j| {
            const x: i32 = @intCast(10 + player_size * i);
            const y: i32 = @intCast(15 + player_size * j);
            rl.drawText(rl.textFormat("[{d},{d}]", .{ i, j }), x, y, 10, .light_gray);
        }
    }

    rl.drawRectangleRec(player1, .red);
    rl.drawRectangleRec(player2, .blue);
}
