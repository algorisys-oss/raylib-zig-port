//! raylib [shapes] example - easings testbed
//!
//! Zig-API translation of examples/shapes/shapes_easings_testbed.c (raylib 6.2).
//! Example contributed by Juan Miguel López (@flashback-fx) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Juan Miguel López (@flashback-fx) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");
const reasings = @import("reasings"); // Required for: easing functions

const font_size = 20;

const d_step = 20.0;
const d_step_fine = 2.0;
const d_min = 1.0;
const d_max = 10000.0;

const Easing = struct {
    name: [:0]const u8,
    func: *const fn (t: f32, b: f32, c: f32, d: f32) f32,
};

/// Easing functions reference data; the last entry is "no easing"
const easings = [_]Easing{
    .{ .name = "EaseLinearNone", .func = reasings.easeLinearNone },
    .{ .name = "EaseLinearIn", .func = reasings.easeLinearIn },
    .{ .name = "EaseLinearOut", .func = reasings.easeLinearOut },
    .{ .name = "EaseLinearInOut", .func = reasings.easeLinearInOut },
    .{ .name = "EaseSineIn", .func = reasings.easeSineIn },
    .{ .name = "EaseSineOut", .func = reasings.easeSineOut },
    .{ .name = "EaseSineInOut", .func = reasings.easeSineInOut },
    .{ .name = "EaseCircIn", .func = reasings.easeCircIn },
    .{ .name = "EaseCircOut", .func = reasings.easeCircOut },
    .{ .name = "EaseCircInOut", .func = reasings.easeCircInOut },
    .{ .name = "EaseCubicIn", .func = reasings.easeCubicIn },
    .{ .name = "EaseCubicOut", .func = reasings.easeCubicOut },
    .{ .name = "EaseCubicInOut", .func = reasings.easeCubicInOut },
    .{ .name = "EaseQuadIn", .func = reasings.easeQuadIn },
    .{ .name = "EaseQuadOut", .func = reasings.easeQuadOut },
    .{ .name = "EaseQuadInOut", .func = reasings.easeQuadInOut },
    .{ .name = "EaseExpoIn", .func = reasings.easeExpoIn },
    .{ .name = "EaseExpoOut", .func = reasings.easeExpoOut },
    .{ .name = "EaseExpoInOut", .func = reasings.easeExpoInOut },
    .{ .name = "EaseBackIn", .func = reasings.easeBackIn },
    .{ .name = "EaseBackOut", .func = reasings.easeBackOut },
    .{ .name = "EaseBackInOut", .func = reasings.easeBackInOut },
    .{ .name = "EaseBounceOut", .func = reasings.easeBounceOut },
    .{ .name = "EaseBounceIn", .func = reasings.easeBounceIn },
    .{ .name = "EaseBounceInOut", .func = reasings.easeBounceInOut },
    .{ .name = "EaseElasticIn", .func = reasings.easeElasticIn },
    .{ .name = "EaseElasticOut", .func = reasings.easeElasticOut },
    .{ .name = "EaseElasticInOut", .func = reasings.easeElasticInOut },
    .{ .name = "None", .func = noEase },
};
const easing_none = easings.len - 1;

/// Used when "no easing" is selected for any axis: ignores all parameters besides b
fn noEase(t: f32, b: f32, c: f32, d: f32) f32 {
    _ = .{ t, c, d };
    return b;
}

/// Step to the next easing, wrapping around
fn next(index: usize) usize {
    return if (index == easing_none) 0 else index + 1;
}

/// Step to the previous easing, wrapping around
fn prev(index: usize) usize {
    return if (index == 0) easing_none else index - 1;
}

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - easings testbed");
    defer rl.closeWindow();

    var ball_position: rl.Vector2 = .{ .x = 100.0, .y = 100.0 };

    var t: f32 = 0.0; // Current time (in any unit measure, but same unit as duration)
    var d: f32 = 300.0; // Total time it should take to complete (duration)
    var paused = true;
    var bounded_t = true; // If true, t will stop when d >= td, otherwise t will keep adding td to its value every loop

    var easing_x: usize = easing_none; // Easing selected for x axis
    var easing_y: usize = easing_none; // Easing selected for y axis

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.t)) bounded_t = !bounded_t;

        // Choose easing for the X axis
        if (rl.isKeyPressed(.right)) {
            easing_x = next(easing_x);
        } else if (rl.isKeyPressed(.left)) {
            easing_x = prev(easing_x);
        }

        // Choose easing for the Y axis
        if (rl.isKeyPressed(.down)) {
            easing_y = next(easing_y);
        } else if (rl.isKeyPressed(.up)) {
            easing_y = prev(easing_y);
        }

        // Change d (duration) value
        if (rl.isKeyPressed(.w) and d < d_max - d_step) {
            d += d_step;
        } else if (rl.isKeyPressed(.q) and d > d_min + d_step) {
            d -= d_step;
        }

        if (rl.isKeyDown(.s) and d < d_max - d_step_fine) {
            d += d_step_fine;
        } else if (rl.isKeyDown(.a) and d > d_min + d_step_fine) {
            d -= d_step_fine;
        }

        // Play, pause and restart controls
        if (rl.isKeyPressed(.space) or rl.isKeyPressed(.t) or
            rl.isKeyPressed(.right) or rl.isKeyPressed(.left) or
            rl.isKeyPressed(.down) or rl.isKeyPressed(.up) or
            rl.isKeyPressed(.w) or rl.isKeyPressed(.q) or
            rl.isKeyDown(.s) or rl.isKeyDown(.a) or
            (rl.isKeyPressed(.enter) and bounded_t and t >= d))
        {
            t = 0.0;
            ball_position = .{ .x = 100.0, .y = 100.0 };
            paused = true;
        }

        if (rl.isKeyPressed(.enter)) paused = !paused;

        // Movement computation
        if (!paused and (!bounded_t or t < d)) {
            ball_position.x = easings[easing_x].func(t, 100.0, 700.0 - 170.0, d);
            ball_position.y = easings[easing_y].func(t, 100.0, 400.0 - 170.0, d);
            t += 1.0;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw information text
        rl.drawText(rl.textFormat("Easing x: {s}", .{easings[easing_x].name}), 20, font_size, font_size, .light_gray);
        rl.drawText(rl.textFormat("Easing y: {s}", .{easings[easing_y].name}), 20, font_size * 2, font_size, .light_gray);
        rl.drawText(rl.textFormat("t ({c}) = {d:.2} d = {d:.2}", .{ @as(u8, if (bounded_t) 'b' else 'u'), t, d }), 20, font_size * 3, font_size, .light_gray);

        // Draw instructions text
        rl.drawText("Use ENTER to play or pause movement, use SPACE to restart", 20, rl.getScreenHeight() - font_size * 2, font_size, .light_gray);
        rl.drawText("Use Q and W or A and S keys to change duration", 20, rl.getScreenHeight() - font_size * 3, font_size, .light_gray);
        rl.drawText("Use LEFT or RIGHT keys to choose easing for the x axis", 20, rl.getScreenHeight() - font_size * 4, font_size, .light_gray);
        rl.drawText("Use UP or DOWN keys to choose easing for the y axis", 20, rl.getScreenHeight() - font_size * 5, font_size, .light_gray);

        // Draw ball
        rl.drawCircleV(ball_position, 16.0, .maroon);
    }
}
