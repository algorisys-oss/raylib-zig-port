//! raylib [textures] example - framebuffer rendering
//!
//! Zig-API translation of examples/textures/textures_framebuffer_rendering.c (raylib 6.2).
//! Example contributed by Jack Boakes (@jackboakes) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Jack Boakes (@jackboakes)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;
    const split_width = screen_width / 2;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - framebuffer rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Camera to look at the 3D world
    var subject_camera: rl.Camera3D = .{
        .position = .{ .x = 5.0, .y = 5.0, .z = 5.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    // Camera to observe the subject camera and 3D world
    var observer_camera: rl.Camera3D = .{
        .position = .{ .x = 10.0, .y = 10.0, .z = 10.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    // Set up render textures
    const observer_target = try rl.loadRenderTexture(split_width, screen_height);
    defer rl.unloadRenderTexture(observer_target);
    const observer_source: rl.Rectangle = .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(observer_target.texture.width),
        .height = -@as(f32, @floatFromInt(observer_target.texture.height)),
    };
    const observer_dest: rl.Rectangle = .{ .x = 0.0, .y = 0.0, .width = split_width, .height = screen_height };

    const subject_target = try rl.loadRenderTexture(split_width, screen_height);
    defer rl.unloadRenderTexture(subject_target);
    const subject_width: f32 = @floatFromInt(subject_target.texture.width);
    const subject_height: f32 = @floatFromInt(subject_target.texture.height);
    const subject_source: rl.Rectangle = .{ .x = 0.0, .y = 0.0, .width = subject_width, .height = -subject_height };
    const subject_dest: rl.Rectangle = .{ .x = split_width, .y = 0.0, .width = split_width, .height = screen_height };
    const texture_aspect_ratio = subject_width / subject_height;

    // Rectangles for cropping render texture
    const capture_size: f32 = 128.0;
    const crop_source: rl.Rectangle = .{
        .x = (subject_width - capture_size) / 2.0,
        .y = (subject_height - capture_size) / 2.0,
        .width = capture_size,
        .height = -capture_size,
    };
    const crop_dest: rl.Rectangle = .{ .x = split_width + 20.0, .y = 20.0, .width = capture_size, .height = capture_size };

    rl.setTargetFPS(60);
    rl.disableCursor();

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&observer_camera, .free);
        rl.updateCamera(&subject_camera, .orbital);

        if (rl.isKeyPressed(.r)) observer_camera.target = .{ .x = 0.0, .y = 0.0, .z = 0.0 };

        // Build LHS observer view texture
        {
            rl.beginTextureMode(observer_target);
            defer rl.endTextureMode();

            rl.clearBackground(.ray_white);

            {
                rl.beginMode3D(observer_camera);
                defer rl.endMode3D();

                rl.drawGrid(10, 1.0);
                rl.drawCube(.{ .x = 0.0, .y = 0.0, .z = 0.0 }, 2.0, 2.0, 2.0, .gold);
                rl.drawCubeWires(.{ .x = 0.0, .y = 0.0, .z = 0.0 }, 2.0, 2.0, 2.0, .pink);
                drawCameraPrism(subject_camera, texture_aspect_ratio, .green);
            }

            rl.drawText("Observer View", 10, observer_target.texture.height - 30, 20, .black);
            rl.drawText("WASD + Mouse to Move", 10, 10, 20, .dark_gray);
            rl.drawText("Scroll to Zoom", 10, 30, 20, .dark_gray);
            rl.drawText("R to Reset Observer Target", 10, 50, 20, .dark_gray);
        }

        // Build RHS subject view texture
        {
            rl.beginTextureMode(subject_target);
            defer rl.endTextureMode();

            rl.clearBackground(.ray_white);

            {
                rl.beginMode3D(subject_camera);
                defer rl.endMode3D();

                rl.drawCube(.{ .x = 0.0, .y = 0.0, .z = 0.0 }, 2.0, 2.0, 2.0, .gold);
                rl.drawCubeWires(.{ .x = 0.0, .y = 0.0, .z = 0.0 }, 2.0, 2.0, 2.0, .pink);
                rl.drawGrid(10, 1.0);
            }

            rl.drawRectangleLines(
                @intFromFloat((subject_width - capture_size) / 2.0),
                @intFromFloat((subject_height - capture_size) / 2.0),
                @intFromFloat(capture_size),
                @intFromFloat(capture_size),
                .green,
            );
            rl.drawText("Subject View", 10, subject_target.texture.height - 30, 20, .black);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        // Draw observer texture LHS
        rl.drawTexturePro(observer_target.texture, observer_source, observer_dest, .{ .x = 0.0, .y = 0.0 }, 0.0, .white);

        // Draw subject texture RHS
        rl.drawTexturePro(subject_target.texture, subject_source, subject_dest, .{ .x = 0.0, .y = 0.0 }, 0.0, .white);

        // Draw the small crop overlay on top
        rl.drawTexturePro(subject_target.texture, crop_source, crop_dest, .{ .x = 0.0, .y = 0.0 }, 0.0, .white);
        rl.drawRectangleLinesEx(crop_dest, 2, .black);

        // Draw split screen divider line
        rl.drawLine(split_width, 0, split_width, screen_height, .black);
    }
}

/// Draw the camera's view prism, from its position to the plane sliced at its target.
fn drawCameraPrism(camera: rl.Camera3D, aspect: f32, color: rl.Color) void {
    const length = rl.math.vector3Distance(camera.position, camera.target);
    // Define the 4 corners of the camera's prism plane sliced at the target in Normalized Device Coordinates
    const plane_ndc = [4]rl.Vector3{
        .{ .x = -1.0, .y = -1.0, .z = 1.0 }, // Bottom Left
        .{ .x = 1.0, .y = -1.0, .z = 1.0 }, // Bottom Right
        .{ .x = 1.0, .y = 1.0, .z = 1.0 }, // Top Right
        .{ .x = -1.0, .y = 1.0, .z = 1.0 }, // Top Left
    };

    // Build the matrices
    const view = rl.getCameraMatrix(camera);
    const proj = rl.math.matrixPerspective(camera.fovy * rl.deg2rad, aspect, 0.05, length);
    // Combine view and projection so we can reverse the full camera transform
    const view_proj = rl.math.matrixMultiply(view, proj);
    // Invert the view-projection matrix to unproject points from NDC space back into world space
    const m = rl.math.matrixInvert(view_proj);

    // Transform the 4 plane corners from NDC into world space
    var corners: [4]rl.Vector3 = undefined;
    for (&corners, plane_ndc) |*corner, p| {
        // Multiply NDC position by the inverse view-projection matrix
        // This produces a homogeneous (x, y, z, w) position in world space
        const vx = m.m0 * p.x + m.m4 * p.y + m.m8 * p.z + m.m12;
        const vy = m.m1 * p.x + m.m5 * p.y + m.m9 * p.z + m.m13;
        const vz = m.m2 * p.x + m.m6 * p.y + m.m10 * p.z + m.m14;
        const vw = m.m3 * p.x + m.m7 * p.y + m.m11 * p.z + m.m15;

        corner.* = .{ .x = vx / vw, .y = vy / vw, .z = vz / vw };
    }

    // Draw the far plane sliced at the target
    for (corners, 0..) |corner, i| {
        rl.drawLine3D(corner, corners[(i + 1) % corners.len], color);
    }

    // Draw the prism lines from the far plane to the camera position
    for (corners) |corner| rl.drawLine3D(camera.position, corner, color);
}
