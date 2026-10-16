//! raylib [core] example - 3d camera split screen
//!
//! Zig-API translation of examples/core/core_3d_camera_split_screen.c (raylib 6.2).
//! Example contributed by Jeffery Myers (@JeffM2501) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2021-2025 Jeffery Myers (@JeffM2501)

const rl = @import("raylib");

// Grid data
const count = 5;
const spacing: f32 = 4;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - 3d camera split screen");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Setup player 1 camera and screen
    var camera_player1: rl.Camera = .{
        .position = .{ .x = 0, .y = 1.0, .z = -3.0 },
        .target = .{ .x = 0, .y = 1.0, .z = 0 },
        .up = .{ .x = 0, .y = 1.0, .z = 0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    const screen_player1 = try rl.loadRenderTexture(screen_width / 2, screen_height);
    defer rl.unloadRenderTexture(screen_player1); // Unload render texture

    // Setup player two camera and screen
    var camera_player2: rl.Camera = .{
        .position = .{ .x = -3.0, .y = 3.0, .z = 0 },
        .target = .{ .x = 0, .y = 3.0, .z = 0 },
        .up = .{ .x = 0, .y = 1.0, .z = 0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    const screen_player2 = try rl.loadRenderTexture(screen_width / 2, screen_height);
    defer rl.unloadRenderTexture(screen_player2); // Unload render texture

    // Build a flipped rectangle the size of the split view to use for drawing later
    const split_screen_rect: rl.Rectangle = .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(screen_player1.texture.width),
        .height = @floatFromInt(-screen_player1.texture.height),
    };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // If anyone moves this frame, how far will they move based on the time since the last frame
        // this moves things at 10 world units per second, regardless of the actual FPS
        const offset_this_frame = 10.0 * rl.getFrameTime();

        // Move Player1 forward and backwards (no turning)
        if (rl.isKeyDown(.w)) {
            camera_player1.position.z += offset_this_frame;
            camera_player1.target.z += offset_this_frame;
        } else if (rl.isKeyDown(.s)) {
            camera_player1.position.z -= offset_this_frame;
            camera_player1.target.z -= offset_this_frame;
        }

        // Move Player2 forward and backwards (no turning)
        if (rl.isKeyDown(.up)) {
            camera_player2.position.x += offset_this_frame;
            camera_player2.target.x += offset_this_frame;
        } else if (rl.isKeyDown(.down)) {
            camera_player2.position.x -= offset_this_frame;
            camera_player2.target.x -= offset_this_frame;
        }

        // Draw
        // Draw Player1 view to the render texture
        {
            rl.beginTextureMode(screen_player1);
            defer rl.endTextureMode();

            rl.clearBackground(.sky_blue);

            drawScene(camera_player1, camera_player1.position, camera_player2.position);

            rl.drawRectangle(0, 0, @divTrunc(rl.getScreenWidth(), 2), 40, rl.fade(.ray_white, 0.8));
            rl.drawText("PLAYER1: W/S to move", 10, 10, 20, .maroon);
        }

        // Draw Player2 view to the render texture
        {
            rl.beginTextureMode(screen_player2);
            defer rl.endTextureMode();

            rl.clearBackground(.sky_blue);

            drawScene(camera_player2, camera_player1.position, camera_player2.position);

            rl.drawRectangle(0, 0, @divTrunc(rl.getScreenWidth(), 2), 40, rl.fade(.ray_white, 0.8));
            rl.drawText("PLAYER2: UP/DOWN to move", 10, 10, 20, .dark_blue);
        }

        // Draw both views render textures to the screen side by side
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        rl.drawTextureRec(screen_player1.texture, split_screen_rect, .{ .x = 0, .y = 0 }, .white);
        rl.drawTextureRec(screen_player2.texture, split_screen_rect, .{ .x = screen_width / 2.0, .y = 0 }, .white);

        rl.drawRectangle(@divTrunc(rl.getScreenWidth(), 2) - 2, 0, 4, rl.getScreenHeight(), .light_gray);
    }
}

/// Draw scene: grid of cube trees on a plane to make a "world", plus a cube at each player's position
fn drawScene(camera: rl.Camera, player1: rl.Vector3, player2: rl.Vector3) void {
    rl.beginMode3D(camera);
    defer rl.endMode3D();

    rl.drawPlane(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 50, .y = 50 }, .beige); // Simple world plane

    const extent = count * spacing;
    var x: f32 = -extent;
    while (x <= extent) : (x += spacing) {
        var z: f32 = -extent;
        while (z <= extent) : (z += spacing) {
            rl.drawCube(.{ .x = x, .y = 1.5, .z = z }, 1, 1, 1, .lime);
            rl.drawCube(.{ .x = x, .y = 0.5, .z = z }, 0.25, 1, 0.25, .brown);
        }
    }

    // Draw a cube at each player's position
    rl.drawCube(player1, 1, 1, 1, .red);
    rl.drawCube(player2, 1, 1, 1, .blue);
}
