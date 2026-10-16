//! raylib [models] example - yaw pitch roll
//!
//! Zig-API translation of examples/models/models_yaw_pitch_roll.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2017-2025 Berni (@Berni8k) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    //rl.setConfigFlags(.{ .msaa_4x_hint = true, .window_highdpi = true });
    rl.initWindow(screen_width, screen_height, "raylib [models] example - yaw pitch roll");
    defer rl.closeWindow(); // Close window and OpenGL context

    const camera: rl.Camera = .{
        .position = .{ .x = 0.0, .y = 50.0, .z = -120.0 }, // Camera position perspective
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 30.0, // Camera field-of-view Y
        .projection = .perspective, // Camera type
    };

    var model = try rl.loadModel("resources/models/obj/plane.obj"); // Load model
    defer rl.unloadModel(model);
    const texture = try rl.loadTexture("resources/models/obj/plane_diffuse.png"); // Load model texture
    defer rl.unloadTexture(texture);

    rl.setTextureWrap(texture, .repeat); // Force Repeat to avoid issue on Web version

    model.materials.?[0].map(.diffuse).texture = texture; // Set map diffuse texture

    var pitch: f32 = 0.0;
    var roll: f32 = 0.0;
    var yaw: f32 = 0.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Plane pitch (x-axis) controls
        if (rl.isKeyDown(.down)) {
            pitch += 0.6;
        } else if (rl.isKeyDown(.up)) {
            pitch -= 0.6;
        } else {
            if (pitch > 0.3) {
                pitch -= 0.3;
            } else if (pitch < -0.3) {
                pitch += 0.3;
            }
        }

        // Plane yaw (y-axis) controls
        if (rl.isKeyDown(.s)) {
            yaw -= 1.0;
        } else if (rl.isKeyDown(.a)) {
            yaw += 1.0;
        } else {
            if (yaw > 0.0) {
                yaw -= 0.5;
            } else if (yaw < 0.0) {
                yaw += 0.5;
            }
        }

        // Plane roll (z-axis) controls
        if (rl.isKeyDown(.left)) {
            roll -= 1.0;
        } else if (rl.isKeyDown(.right)) {
            roll += 1.0;
        } else {
            if (roll > 0.0) {
                roll -= 0.5;
            } else if (roll < 0.0) {
                roll += 0.5;
            }
        }

        // Tranformation matrix for rotations
        model.transform = rl.math.matrixRotateXYZ(.{ .x = rl.deg2rad * pitch, .y = rl.deg2rad * yaw, .z = rl.deg2rad * roll });

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw 3D model (recomended to draw 3D always before 2D)
        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(model, .{ .x = 0.0, .y = -8.0, .z = 0.0 }, 1.0, .white); // Draw 3d model with texture
            rl.drawGrid(10, 10.0);
        }

        // Draw controls info
        rl.drawRectangle(30, 370, 260, 70, rl.fade(.green, 0.5));
        rl.drawRectangleLines(30, 370, 260, 70, rl.fade(.dark_green, 0.5));
        rl.drawText("Pitch controlled with: KEY_UP / KEY_DOWN", 40, 380, 10, .dark_gray);
        rl.drawText("Roll controlled with: KEY_LEFT / KEY_RIGHT", 40, 400, 10, .dark_gray);
        rl.drawText("Yaw controlled with: KEY_A / KEY_S", 40, 420, 10, .dark_gray);

        rl.drawText("(c) WWI Plane Model created by GiaHanLam", screen_width - 240, screen_height - 20, 10, .dark_gray);
    }
}
