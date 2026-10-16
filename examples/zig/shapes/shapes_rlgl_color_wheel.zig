//! raylib [shapes] example - rlgl color wheel
//!
//! Zig-API translation of examples/shapes/shapes_rlgl_color_wheel.c (raylib 6.2).
//! Example contributed by Robin (@RobinsAviary) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Robin (@RobinsAviary)

const rl = @import("raylib");
const gui = @import("raygui");
const gl = rl.gl;
const math = rl.math;

/// How the color wheel will be rendered
const RenderMode = enum { triangles, lines };

/// Position on a circle of `radius` around `center`, `angle` radians clockwise from the top.
fn pointOnWheel(center: rl.Vector2, angle: f32, radius: f32) rl.Vector2 {
    return math.vector2Add(.{ .x = @sin(angle) * radius, .y = -@cos(angle) * radius }, center);
}

/// Normalized (0..1) clockwise angle of `position` around `center`.
fn wheelAngle(center: rl.Vector2, position: rl.Vector2, radius: f32) f32 {
    return (math.vector2Angle(.{ .x = 0.0, .y = -radius }, math.vector2Subtract(center, position)) / rl.pi + 1.0) / 2.0;
}

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    // The minimum/maximum points the circle can have
    const points_min = 3;
    const points_max = 256;

    // The current number of points and the radius of the circle
    var triangle_count: u32 = 64;
    var point_scale: f32 = 150.0;

    // Slider value, literally maps to value in HSV
    var value: f32 = 1.0;

    // The center of the screen
    const center: rl.Vector2 = .{ .x = screen_width / 2.0, .y = screen_height / 2.0 };
    // The location of the color wheel
    var circle_position = center;

    // The currently selected color
    var color: rl.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };

    // Indicates if the slider is being clicked
    var slider_clicked = false;

    // Indicates if the current color going to be updated, as well as the handle position
    var setting_color = false;

    var render_mode: RenderMode = .triangles;

    // Enable anti-aliasing
    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - rlgl color wheel");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const wheel = @round(rl.getMouseWheelMove());
        triangle_count = @intFromFloat(math.clamp(@as(f32, @floatFromInt(triangle_count)) + wheel, points_min, points_max));

        const slider_rectangle: rl.Rectangle = .{ .x = 42.0, .y = 16.0 + 64.0 + 45.0, .width = 64.0, .height = 16.0 };
        const mouse_position = rl.getMousePosition();

        // Checks if the user is hovering over the value slider
        const slider_hover = mouse_position.x >= slider_rectangle.x and mouse_position.y >= slider_rectangle.y and
            mouse_position.x < slider_rectangle.x + slider_rectangle.width and mouse_position.y < slider_rectangle.y + slider_rectangle.height;

        // Copy color as hex
        if (rl.isKeyDown(.left_control) and rl.isKeyDown(.c)) {
            if (rl.isKeyPressed(.c)) {
                rl.setClipboardText(rl.textFormat("#{X:0>2}{X:0>2}{X:0>2}", .{ color.r, color.g, color.b }));
            }
        }

        // Scale up the color wheel, adjusting the handle visually
        if (rl.isKeyDown(.up)) {
            point_scale *= 1.025;

            if (point_scale > screen_height / 2.0) {
                point_scale = screen_height / 2.0;
            } else {
                circle_position = math.vector2Add(math.vector2Multiply(math.vector2Subtract(circle_position, center), .{ .x = 1.025, .y = 1.025 }), center);
            }
        }

        // Scale down the wheel, adjusting the handle visually
        if (rl.isKeyDown(.down)) {
            point_scale *= 0.975;

            if (point_scale < 32.0) {
                point_scale = 32.0;
            } else {
                circle_position = math.vector2Add(math.vector2Multiply(math.vector2Subtract(circle_position, center), .{ .x = 0.975, .y = 0.975 }), center);
            }

            const distance = math.vector2Distance(center, circle_position) / point_scale;
            const angle = wheelAngle(center, circle_position, point_scale);

            if (distance > 1.0) circle_position = pointOnWheel(center, angle * (rl.pi * 2.0), point_scale);
        }

        // Checks if the user clicked on the color wheel
        if (rl.isMouseButtonPressed(.left) and math.vector2Distance(rl.getMousePosition(), center) <= point_scale + 10.0) {
            setting_color = true;
        }

        // Update flag when mouse button is released
        if (rl.isMouseButtonReleased(.left)) setting_color = false;

        // Check if the user clicked/released the slider for the color's value
        if (slider_hover and rl.isMouseButtonPressed(.left)) slider_clicked = true;

        if (slider_clicked and rl.isMouseButtonReleased(.left)) slider_clicked = false;

        // Update render mode accordingly
        if (rl.isKeyPressed(.space)) render_mode = .lines;

        if (rl.isKeyReleased(.space)) render_mode = .triangles;

        // If the slider or the wheel was clicked, update the current color
        if (setting_color or slider_clicked) {
            if (setting_color) circle_position = rl.getMousePosition();

            const distance = math.vector2Distance(center, circle_position) / point_scale;

            const angle = wheelAngle(center, circle_position, point_scale);
            if (setting_color and distance > 1.0) circle_position = pointOnWheel(center, angle * (rl.pi * 2.0), point_scale);

            const angle360 = angle * 360.0;
            const value_actual = math.clamp(distance, 0.0, 1.0);
            const gray: u8 = @intFromFloat(value * 255.0);
            color = rl.colorLerp(.{ .r = gray, .g = gray, .b = gray, .a = 255 }, rl.colorFromHSV(angle360, math.clamp(distance, 0.0, 1.0), 1.0), value_actual);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Begin rendering color wheel
        gl.begin(switch (render_mode) {
            .triangles => gl.triangles,
            .lines => gl.lines,
        });
        for (0..triangle_count) |i| {
            const angle_offset = (rl.pi * 2.0) / @as(f32, @floatFromInt(triangle_count));
            const angle = angle_offset * @as(f32, @floatFromInt(i));
            const angle_offset_calculated = (@as(f32, @floatFromInt(i)) + 1) * angle_offset;
            const scale: rl.Vector2 = .{ .x = point_scale, .y = point_scale };

            const offset = math.vector2Multiply(.{ .x = @sin(angle), .y = -@cos(angle) }, scale);
            const offset2 = math.vector2Multiply(.{ .x = @sin(angle_offset_calculated), .y = -@cos(angle_offset_calculated) }, scale);

            const position = math.vector2Add(center, offset);
            const position2 = math.vector2Add(center, offset2);

            const angle_non_radian = (angle / (2.0 * rl.pi)) * 360.0;
            const angle_non_radian_offset = (angle_offset / (2.0 * rl.pi)) * 360.0;

            const current_color = rl.colorFromHSV(angle_non_radian, 1.0, 1.0);
            const offset_color = rl.colorFromHSV(angle_non_radian + angle_non_radian_offset, 1.0, 1.0);

            // Input vertices differently depending on mode
            switch (render_mode) {
                .triangles => {
                    // RL_TRIANGLES expects three vertices per triangle
                    gl.color4ub(current_color.r, current_color.g, current_color.b, current_color.a);
                    gl.vertex2f(position.x, position.y);
                    gl.color4f(value, value, value, 1.0);
                    gl.vertex2f(center.x, center.y);
                    gl.color4ub(offset_color.r, offset_color.g, offset_color.b, offset_color.a);
                    gl.vertex2f(position2.x, position2.y);
                },
                .lines => {
                    // RL_LINES expects two vertices per line
                    const white: rl.Color = .white;
                    gl.color4ub(current_color.r, current_color.g, current_color.b, current_color.a);
                    gl.vertex2f(position.x, position.y);
                    gl.color4ub(white.r, white.g, white.b, white.a);
                    gl.vertex2f(center.x, center.y);

                    gl.vertex2f(center.x, center.y);
                    gl.color4ub(offset_color.r, offset_color.g, offset_color.b, offset_color.a);
                    gl.vertex2f(position2.x, position2.y);

                    gl.vertex2f(position2.x, position2.y);
                    gl.color4ub(current_color.r, current_color.g, current_color.b, current_color.a);
                    gl.vertex2f(position.x, position.y);
                },
            }
        }
        gl.end();

        // Make the handle slightly more visible overtop darker colors
        const handle_color: rl.Color = if (math.vector2Distance(center, circle_position) / point_scale <= 0.5 and value <= 0.5) .dark_gray else .black;

        // Draw the color handle
        rl.drawCircleLinesV(circle_position, 4.0, handle_color);

        // Draw the color in a preview, with a darkened outline.
        rl.drawRectangleV(.{ .x = 8.0, .y = 8.0 }, .{ .x = 64.0, .y = 64.0 }, color);
        rl.drawRectangleLinesEx(.{ .x = 8.0, .y = 8.0, .width = 64.0, .height = 64.0 }, 2.0, rl.colorLerp(color, .black, 0.5));

        // Draw current color as hex and decimal
        rl.drawText(rl.textFormat("#{X:0>2}{X:0>2}{X:0>2}\n({d}, {d}, {d})", .{ color.r, color.g, color.b, color.r, color.g, color.b }), 8, 8 + 64 + 8, 20, .dark_gray);

        // Update the visuals for the copying text
        const copying = rl.isKeyDown(.left_control) and rl.isKeyDown(.c);
        const copy_color: rl.Color = if (copying) .dark_green else .dark_gray;
        const offset: i32 = if (copying) 4 else 0;

        // Draw the copying text
        rl.drawText("press ctrl+c to copy!", 8, 425 - offset, 20, copy_color);

        // Display the number of rendered triangles
        rl.drawText(rl.textFormat("triangle count: {d}", .{triangle_count}), 8, 395, 20, .dark_gray);

        // Slider to change color's value
        _ = gui.sliderBar(slider_rectangle, "value: ", "", &value, 0.0, 1.0);

        // Draw FPS next to outlined color preview
        rl.drawFPS(64 + 16, 8);
    }
}
