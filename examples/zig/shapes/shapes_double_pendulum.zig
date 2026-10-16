//! raylib [shapes] example - double pendulum
//!
//! Zig-API translation of examples/shapes/shapes_double_pendulum.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 JoeCheong (@Joecheong2006)

const rl = @import("raylib");

// Constant for Simulation
const simulation_steps = 30;
const g: f32 = 9.81;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .window_highdpi = true });
    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - double pendulum");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Simulation Parameters
    const l1: f32 = 15.0;
    const m1: f32 = 0.2;
    var theta1: f32 = rl.deg2rad * 170;
    var w1: f32 = 0;
    const l2: f32 = 15.0;
    const m2: f32 = 0.1;
    var theta2: f32 = rl.deg2rad * 0;
    var w2: f32 = 0;
    const length_scaler: f32 = 0.1;
    const total_m = m1 + m2;

    var previous_position = calculateDoublePendulumEndPoint(l1, theta1, l2, theta2);
    previous_position.x += screen_width / 2.0;
    previous_position.y += screen_height / 2.0 - 100;

    // Scale length
    const scaled_l1 = l1 * length_scaler;
    const scaled_l2 = l2 * length_scaler;

    // Draw parameters
    const line_thick: f32 = 20;
    const trail_thick: f32 = 2;
    const fade_alpha: f32 = 0.01;

    // Create framebuffer
    const target = try rl.loadRenderTexture(screen_width, screen_height);
    defer rl.unloadRenderTexture(target);
    rl.setTextureFilter(target.texture, .bilinear);

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const dt = rl.getFrameTime();
        const step = dt / simulation_steps;
        const step2 = step * step;

        // Update Physics - larger steps = better approximation
        for (0..simulation_steps) |_| {
            const delta = theta1 - theta2;
            const sin_d = @sin(delta);
            const cos_d = @cos(delta);
            const cos_2d = @cos(2 * delta);
            const ww1 = w1 * w1;
            const ww2 = w2 * w2;

            // Calculate a1
            const a1 = (-g * (2 * m1 + m2) * @sin(theta1) -
                m2 * g * @sin(theta1 - 2 * theta2) -
                2 * sin_d * m2 * (ww2 * scaled_l2 + ww1 * scaled_l1 * cos_d)) /
                (scaled_l1 * (2 * m1 + m2 - m2 * cos_2d));

            // Calculate a2
            const a2 = (2 * sin_d * (ww1 * scaled_l1 * total_m +
                g * total_m * @cos(theta1) +
                ww2 * scaled_l2 * m2 * cos_d)) /
                (scaled_l2 * (2 * m1 + m2 - m2 * cos_2d));

            // Update thetas
            theta1 += w1 * step + 0.5 * a1 * step2;
            theta2 += w2 * step + 0.5 * a2 * step2;

            // Update omegas
            w1 += a1 * step;
            w2 += a2 * step;
        }

        // Calculate position
        var current_position = calculateDoublePendulumEndPoint(l1, theta1, l2, theta2);
        current_position.x += screen_width / 2.0;
        current_position.y += screen_height / 2.0 - 100;

        // Draw to render texture
        {
            rl.beginTextureMode(target);
            defer rl.endTextureMode();

            // Draw a transparent rectangle - smaller alpha = longer trails
            rl.drawRectangle(0, 0, screen_width, screen_height, rl.fade(.black, fade_alpha));

            // Draw trail
            rl.drawCircleV(previous_position, trail_thick, .red);
            rl.drawLineEx(previous_position, current_position, trail_thick * 2, .red);
        }

        // Update previous position
        previous_position = current_position;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        // Draw trails texture (flipped: render textures are stored bottom-up)
        const texture = target.texture;
        rl.drawTextureRec(texture, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(texture.width),
            .height = @floatFromInt(-texture.height),
        }, .{ .x = 0, .y = 0 }, .white);

        // Draw double pendulum
        rl.drawRectanglePro(
            .{ .x = screen_width / 2.0, .y = screen_height / 2.0 - 100, .width = 10 * l1, .height = line_thick },
            .{ .x = 0, .y = line_thick * 0.5 },
            90 - rl.rad2deg * theta1,
            .ray_white,
        );

        const endpoint1 = calculatePendulumEndPoint(l1, theta1);
        rl.drawRectanglePro(
            .{ .x = screen_width / 2.0 + endpoint1.x, .y = screen_height / 2.0 - 100 + endpoint1.y, .width = 10 * l2, .height = line_thick },
            .{ .x = 0, .y = line_thick * 0.5 },
            90 - rl.rad2deg * theta2,
            .ray_white,
        );
    }
}

/// Calculate pendulum end point
fn calculatePendulumEndPoint(l: f32, theta: f32) rl.Vector2 {
    return .{ .x = 10 * l * @sin(theta), .y = 10 * l * @cos(theta) };
}

/// Calculate double pendulum end point
fn calculateDoublePendulumEndPoint(l1: f32, theta1: f32, l2: f32, theta2: f32) rl.Vector2 {
    const endpoint1 = calculatePendulumEndPoint(l1, theta1);
    const endpoint2 = calculatePendulumEndPoint(l2, theta2);
    return .{ .x = endpoint1.x + endpoint2.x, .y = endpoint1.y + endpoint2.y };
}
