//! raylib [models] example - directional billboard
//!
//! Zig-API translation of examples/models/models_directional_billboard.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Robin (@RobinsAviary)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - directional billboard");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Set up the camera
    var camera: rl.Camera = .{
        .position = .{ .x = 2.0, .y = 1.0, .z = 2.0 }, // Starting position
        .target = .{ .x = 0.0, .y = 0.5, .z = 0.0 }, // Target position
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Up vector
        .fovy = 45.0, // FOV
        .projection = .perspective, // Projection type (Standard 3D perspective)
    };

    // Load billboard texture
    const skillbot = try rl.loadTexture("resources/skillbot.png");
    defer rl.unloadTexture(skillbot);

    // Timer to update animation
    var anim_timer: f32 = 0.0;
    // Animation frame
    var anim: u32 = 0;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .orbital);

        // Update timer with delta time
        anim_timer += rl.getFrameTime();

        // Update frame index after a certain amount of time (half a second)
        if (anim_timer > 0.5) {
            anim_timer = 0.0;
            anim += 1;
        }

        // Reset frame index to zero on overflow
        if (anim >= 4) anim = 0;

        // Find the current direction frame based on the camera position to the billboard object
        const angle = rl.math.vector2Angle(.{ .x = 2.0, .y = 0.0 }, .{ .x = camera.position.x, .y = camera.position.z });
        var dir = @floor(((angle / rl.pi) * 4.0) + 0.25);

        // Correct frame index if angle is negative (dir is integral, so |dir| needs no truncation)
        if (dir < 0.0) dir = 8.0 - @abs(dir);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawGrid(10, 1.0);

            // Draw billboard pointing straight up to the sky, rotated relative to the camera and offset from the bottom
            const source: rl.Rectangle = .{ .x = 0.0 + (@as(f32, @floatFromInt(anim)) * 24.0), .y = 0.0 + (dir * 24.0), .width = 24.0, .height = 24.0 };
            rl.drawBillboardPro(camera, skillbot, source, rl.math.vector3Zero(), .{ .x = 0.0, .y = 1.0, .z = 0.0 }, rl.math.vector2One(), .{ .x = 0.5, .y = 0.0 }, 0, .white);
        }

        // Render various variables for reference
        rl.drawText(rl.textFormat("animation: {d}", .{anim}), 10, 10, 20, .dark_gray);
        rl.drawText(rl.textFormat("direction frame: {d:.0}", .{dir}), 10, 40, 20, .dark_gray);
    }
}
