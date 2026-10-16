//! raylib [core] example - 2d camera mouse zoom
//!
//! Zig-API translation of examples/core/core_2d_camera_mouse_zoom.c (raylib 6.2).
//! Example contributed by Jeffery Myers (@JeffM2501) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2022-2025 Jeffery Myers (@JeffM2501)

const rl = @import("raylib");

const ZoomMode = enum { mouse_wheel, mouse_move };

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - 2d camera mouse zoom");
    defer rl.closeWindow(); // Close window and OpenGL context

    var camera: rl.Camera2D = .{ .offset = .{ .x = 0, .y = 0 }, .target = .{ .x = 0, .y = 0 }, .rotation = 0, .zoom = 1.0 };

    var zoom_mode: ZoomMode = .mouse_wheel;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.one)) {
            zoom_mode = .mouse_wheel;
        } else if (rl.isKeyPressed(.two)) {
            zoom_mode = .mouse_move;
        }

        // Translate based on mouse right click
        if (rl.isMouseButtonDown(.left)) {
            const delta = rl.math.vector2Scale(rl.getMouseDelta(), -1.0 / camera.zoom);
            camera.target = rl.math.vector2Add(camera.target, delta);
        }

        switch (zoom_mode) {
            .mouse_wheel => {
                // Zoom based on mouse wheel
                const wheel = rl.getMouseWheelMove();
                if (wheel != 0) {
                    focusCameraOnMouse(&camera);

                    // Zoom increment
                    // Uses log scaling to provide consistent zoom speed
                    zoomCamera(&camera, 0.2 * wheel);
                }
            },
            .mouse_move => {
                // Zoom based on mouse right click
                if (rl.isMouseButtonPressed(.right)) focusCameraOnMouse(&camera);

                if (rl.isMouseButtonDown(.right)) {
                    // Zoom increment
                    // Uses log scaling to provide consistent zoom speed
                    zoomCamera(&camera, 0.005 * rl.getMouseDelta().x);
                }
            },
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode2D(camera);
            defer rl.endMode2D();

            // Draw the 3d grid, rotated 90 degrees and centered around 0,0
            // just so we have something in the XY plane
            rl.gl.pushMatrix();
            rl.gl.translatef(0, 25 * 50, 0);
            rl.gl.rotatef(90, 1, 0, 0);
            rl.drawGrid(100, 50);
            rl.gl.popMatrix();

            // Draw a reference circle
            rl.drawCircle(@divTrunc(rl.getScreenWidth(), 2), @divTrunc(rl.getScreenHeight(), 2), 50, .maroon);
        }

        // Draw mouse reference
        rl.drawCircleV(rl.getMousePosition(), 4, .dark_gray);
        rl.drawTextEx(
            rl.getFontDefault(),
            rl.textFormat("[{d}, {d}]", .{ rl.getMouseX(), rl.getMouseY() }),
            rl.math.vector2Add(rl.getMousePosition(), .{ .x = -44, .y = -24 }),
            20,
            2,
            .black,
        );

        rl.drawText("[1][2] Select mouse zoom mode (Wheel or Move)", 20, 20, 20, .dark_gray);
        switch (zoom_mode) {
            .mouse_wheel => rl.drawText("Mouse left button drag to move, mouse wheel to zoom", 20, 50, 20, .dark_gray),
            .mouse_move => rl.drawText("Mouse left button drag to move, mouse press and move to zoom", 20, 50, 20, .dark_gray),
        }
    }
}

/// Re-anchor the camera so the world point under the cursor stays put while zooming.
fn focusCameraOnMouse(camera: *rl.Camera2D) void {
    // Get the world point that is under the mouse
    const mouse_world_pos = rl.getScreenToWorld2D(rl.getMousePosition(), camera.*);

    // Set the offset to where the mouse is, mouse is scaled to viewport space, but offset is in unscaled pixels
    camera.offset = rl.math.vector2Multiply(rl.getMousePosition(), rl.getWindowScaleDPI());

    // Set the target to match, so that the camera maps the world space point
    // under the cursor to the screen space point under the cursor at any zoom
    camera.target = mouse_world_pos;
}

fn zoomCamera(camera: *rl.Camera2D, scale: f32) void {
    camera.zoom = rl.math.clamp(@exp(@log(camera.zoom) + scale), 0.125, 64.0);
}
