//! raylib [textures] example - portal window
//!
//! Zig-API translation of examples/textures/textures_portal_window.c (raylib 6.2).
//! Example contributed by PanicTitan (@PanicTitan) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 PanicTitan (@PanicTitan)

const rl = @import("raylib");
const rm = rl.math;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - portal window");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Camera to navigate the "real world" (Dimension A)
    var camera: rl.Camera3D = .{
        .position = .{ .x = 0.0, .y = 2.5, .z = 7.0 },
        .target = .{ .x = 0.0, .y = 1.8, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    // The archway opening, in Dimension A world space (used both to draw the frame and
    // as the window rectangle the oblique projection is built from)
    const arch_bottom_left: rl.Vector3 = .{ .x = -1.5, .y = 0.0, .z = 0.0 };
    const arch_bottom_right: rl.Vector3 = .{ .x = 1.5, .y = 0.0, .z = 0.0 };
    const arch_top_left: rl.Vector3 = .{ .x = -1.5, .y = 4.0, .z = 0.0 };

    // The archway sits at portalA and looks out onto portalB, far away in world space.
    // Every frame, Dimension B gets rendered to a texture using the same relative eye
    // and window position, shifted by the offset between the two portals
    const portal_a: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const portal_b: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = -60.0 };
    const portal_view = try rl.loadRenderTexture(480, 640);
    defer rl.unloadRenderTexture(portal_view);

    rl.disableCursor(); // Lock cursor for first-person free camera controls
    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .free);
        const time: f32 = @floatCast(rl.getTime());

        // Eye and window corners, shifted into Dimension B so they match the player's
        // actual position and viewing angle relative to the archway
        const offset = rm.vector3Subtract(portal_b, portal_a);
        const eye_in_b = rm.vector3Add(camera.position, offset);
        const bl_in_b = rm.vector3Add(arch_bottom_left, offset);
        const br_in_b = rm.vector3Add(arch_bottom_right, offset);
        const tl_in_b = rm.vector3Add(arch_top_left, offset);

        // Draw
        // Render Dimension B into an offscreen texture, using an oblique projection so
        // its perspective lines up with the archway exactly as the real camera sees it
        {
            rl.beginTextureMode(portal_view);
            defer rl.endTextureMode();

            rl.clearBackground(.{ .r = 10, .g = 5, .b = 20, .a = 255 });

            beginPortalMode3D(eye_in_b, bl_in_b, br_in_b, tl_in_b, 0.05, 100.0);
            defer endPortalMode3D();

            rl.drawGrid(30, 0.8);

            // Floating pulsing core sphere
            const core_pos = rm.vector3Add(portal_b, .{ .x = 0.0, .y = 2.0 + @sin(time * 2.5) * 0.4, .z = -4.0 });
            rl.drawSphere(core_pos, 1.2, .purple);
            rl.drawSphereWires(core_pos, 1.25, 16, 16, .magenta);

            // Orbiting cubes
            for (0..4) |i| {
                const fi: f32 = @floatFromInt(i);
                const angle = time * 1.5 + fi * (rl.pi / 2.0);
                const pos = rm.vector3Add(portal_b, .{
                    .x = @sin(angle) * 2.5,
                    .y = 2.0 + @cos(time * 3.0 + fi) * 0.5,
                    .z = -4.0 + @cos(angle) * 2.5,
                });

                rl.drawCube(pos, 0.5, 0.5, 0.5, .lime);
                rl.drawCubeWires(pos, 0.52, 0.52, 0.52, .dark_green);
            }
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawGrid(20, 1.0);

            // Side pillars
            rl.drawCube(.{ .x = -3.5, .y = 2.0, .z = 0.0 }, 0.8, 4.0, 0.8, .dark_gray);
            rl.drawCubeWires(.{ .x = -3.5, .y = 2.0, .z = 0.0 }, 0.8, 4.0, 0.8, .orange);
            rl.drawCube(.{ .x = 3.5, .y = 2.0, .z = 0.0 }, 0.8, 4.0, 0.8, .dark_gray);
            rl.drawCubeWires(.{ .x = 3.5, .y = 2.0, .z = 0.0 }, 0.8, 4.0, 0.8, .orange);

            // Golden archway frame and solid base
            rl.drawCubeWires(.{ .x = 0.0, .y = 2.0, .z = 0.0 }, 3.2, 4.2, 0.2, .gold);
            rl.drawCube(.{ .x = 0.0, .y = 0.05, .z = 0.0 }, 3.4, 0.1, 0.6, .maroon);

            // Solid backing wall, only ever seen if looking at the archway from behind
            rl.drawCube(.{ .x = 0.0, .y = 2.0, .z = -0.05 }, 3.1, 4.1, 0.05, .maroon);

            // The portal opening itself: a plain quad textured with the Dimension B
            // render, filling the archway exactly, so nothing "leaks" outside its shape
            rl.gl.setTexture(portal_view.texture.id);
            defer rl.gl.setTexture(0);
            rl.gl.begin(rl.gl.quads);
            defer rl.gl.end();
            rl.gl.color4ub(255, 255, 255, 255);
            rl.gl.normal3f(0.0, 0.0, 1.0);
            rl.gl.texCoord2f(0.0, 0.0);
            rl.gl.vertex3f(arch_bottom_left.x, arch_bottom_left.y, arch_bottom_left.z);
            rl.gl.texCoord2f(1.0, 0.0);
            rl.gl.vertex3f(arch_bottom_right.x, arch_bottom_right.y, arch_bottom_right.z);
            rl.gl.texCoord2f(1.0, 1.0);
            rl.gl.vertex3f(arch_bottom_right.x, 4.0, arch_bottom_right.z);
            rl.gl.texCoord2f(0.0, 1.0);
            rl.gl.vertex3f(arch_top_left.x, arch_top_left.y, arch_top_left.z);
        }

        // HUD overlay
        rl.drawRectangle(15, 15, 520, 100, rl.fade(.black, 0.75));
        rl.drawRectangleLines(15, 15, 520, 100, .gold);
        rl.drawText("PORTAL WINDOW", 28, 25, 20, .gold);
        rl.drawText("Look through the golden arch into Dimension B", 28, 52, 20, .ray_white);
        rl.drawText("Controls: Mouse to look | WASD to move", 28, 80, 20, .gray);
    }
}

/// Starts a 3D mode using an off-axis ("oblique frustum") projection, built directly from
/// an eye point and 3 corners of a rectangular window, instead of a fovy centered straight
/// ahead of the camera. This is the standard technique for rendering a scene as seen through
/// a window that isn't necessarily faced head-on (also used for multi-monitor and VR
/// rendering) - the key difference from a normal Camera3D is that the frustum is allowed
/// to be asymmetric, so perspective lines through the window line up correctly from any
/// eye position, instead of behaving like a flat image pasted onto the window
fn beginPortalMode3D(eye: rl.Vector3, bottom_left: rl.Vector3, bottom_right: rl.Vector3, top_left: rl.Vector3, near_plane: f32, far_plane: f32) void {
    const right = rm.vector3Normalize(rm.vector3Subtract(bottom_right, bottom_left));
    const up = rm.vector3Normalize(rm.vector3Subtract(top_left, bottom_left));
    const normal = rm.vector3Normalize(rm.vector3CrossProduct(right, up));

    // Vectors from the eye to 3 corners of the window, used to project the window onto
    // the near plane and read off how far it extends left/right/bottom/top of the eye
    const to_bl = rm.vector3Subtract(bottom_left, eye);
    const to_br = rm.vector3Subtract(bottom_right, eye);
    const to_tl = rm.vector3Subtract(top_left, eye);

    // Keep the eye from crossing the window plane
    const dist = @max(-rm.vector3DotProduct(to_bl, normal), 0.01);

    const scale = near_plane / dist;

    rl.gl.drawRenderBatchActive();

    rl.gl.matrixMode(rl.gl.projection);
    rl.gl.pushMatrix();
    rl.gl.setMatrixProjection(rm.matrixFrustum(
        rm.vector3DotProduct(right, to_bl) * scale,
        rm.vector3DotProduct(right, to_br) * scale,
        rm.vector3DotProduct(up, to_bl) * scale,
        rm.vector3DotProduct(up, to_tl) * scale,
        near_plane,
        far_plane,
    ));

    // View orientation is fixed to the window's own plane (looking straight through it
    // along its normal), NOT aimed at any target - that's what the asymmetric frustum
    // above is for, and is what lets the eye move off to one side without distorting
    rl.gl.matrixMode(rl.gl.modelview);
    rl.gl.loadIdentity();
    rl.gl.multMatrixf(&rm.matrixToFloatV(rm.matrixLookAt(eye, rm.vector3Subtract(eye, normal), up)).v);

    rl.gl.enableDepthTest();
}

/// End portal 3D mode and returns to default 2D orthographic mode
/// NOTE: Similar implementation to endMode3D()
fn endPortalMode3D() void {
    rl.gl.drawRenderBatchActive(); // Update and draw internal render batch

    rl.gl.matrixMode(rl.gl.projection); // Switch to projection matrix
    rl.gl.popMatrix(); // Restore previous matrix (projection) from matrix stack

    rl.gl.matrixMode(rl.gl.modelview); // Switch back to modelview matrix
    rl.gl.loadIdentity(); // Reset current matrix (modelview)

    rl.gl.disableDepthTest(); // Disable DEPTH_TEST for 2D
}
