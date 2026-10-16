//! raylib [core] example - window flags
//!
//! Zig-API translation of examples/core/core_window_flags.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2020-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

/// A window flag and the status line drawn for it.
const FlagStatus = struct {
    flags: rl.ConfigFlags,
    on: [:0]const u8,
    off: [:0]const u8,
};

/// Flags that can be set after window creation
const runtime_flags = [_]FlagStatus{
    .{ .flags = .{ .fullscreen_mode = true }, .on = "[F] FLAG_FULLSCREEN_MODE: on", .off = "[F] FLAG_FULLSCREEN_MODE: off" },
    .{ .flags = .{ .window_resizable = true }, .on = "[R] FLAG_WINDOW_RESIZABLE: on", .off = "[R] FLAG_WINDOW_RESIZABLE: off" },
    .{ .flags = .{ .window_undecorated = true }, .on = "[D] FLAG_WINDOW_UNDECORATED: on", .off = "[D] FLAG_WINDOW_UNDECORATED: off" },
    .{ .flags = .{ .window_hidden = true }, .on = "[H] FLAG_WINDOW_HIDDEN: on", .off = "[H] FLAG_WINDOW_HIDDEN: off (hides for 3 seconds)" },
    .{ .flags = .{ .window_minimized = true }, .on = "[N] FLAG_WINDOW_MINIMIZED: on", .off = "[N] FLAG_WINDOW_MINIMIZED: off (restores after 3 seconds)" },
    .{ .flags = .{ .window_maximized = true }, .on = "[M] FLAG_WINDOW_MAXIMIZED: on", .off = "[M] FLAG_WINDOW_MAXIMIZED: off" },
    .{ .flags = .{ .window_unfocused = true }, .on = "[G] FLAG_WINDOW_UNFOCUSED: on", .off = "[U] FLAG_WINDOW_UNFOCUSED: off" },
    .{ .flags = .{ .window_topmost = true }, .on = "[T] FLAG_WINDOW_TOPMOST: on", .off = "[T] FLAG_WINDOW_TOPMOST: off" },
    .{ .flags = .{ .window_always_run = true }, .on = "[A] FLAG_WINDOW_ALWAYS_RUN: on", .off = "[A] FLAG_WINDOW_ALWAYS_RUN: off" },
    .{ .flags = .{ .vsync_hint = true }, .on = "[V] FLAG_VSYNC_HINT: on", .off = "[V] FLAG_VSYNC_HINT: off" },
    .{ .flags = .{ .borderless_windowed_mode = true }, .on = "[B] FLAG_BORDERLESS_WINDOWED_MODE: on", .off = "[B] FLAG_BORDERLESS_WINDOWED_MODE: off" },
};

/// Flags that can only be set before window creation
const creation_flags = [_]FlagStatus{
    .{ .flags = .{ .window_highdpi = true }, .on = "FLAG_WINDOW_HIGHDPI: on", .off = "FLAG_WINDOW_HIGHDPI: off" },
    .{ .flags = .{ .window_transparent = true }, .on = "FLAG_WINDOW_TRANSPARENT: on", .off = "FLAG_WINDOW_TRANSPARENT: off" },
    .{ .flags = .{ .msaa_4x_hint = true }, .on = "FLAG_MSAA_4X_HINT: on", .off = "FLAG_MSAA_4X_HINT: off" },
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    // Possible window flags
    //   vsync_hint
    //   fullscreen_mode    -> not working properly -> wrong scaling!
    //   window_resizable
    //   window_undecorated
    //   window_transparent
    //   window_hidden
    //   window_minimized   -> Not supported on window creation
    //   window_maximized   -> Not supported on window creation
    //   window_unfocused
    //   window_topmost
    //   window_highdpi     -> errors after minimize-resize, fb size is recalculated
    //   window_always_run
    //   msaa_4x_hint

    // Set configuration flags for window creation
    //rl.setConfigFlags(.{ .vsync_hint = true, .msaa_4x_hint = true, .window_highdpi = true }); // .window_transparent = true
    rl.initWindow(screen_width, screen_height, "raylib [core] example - window flags");
    defer rl.closeWindow(); // Close window and OpenGL context

    var ball_position: rl.Vector2 = .{
        .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
        .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
    };
    var ball_speed: rl.Vector2 = .{ .x = 5.0, .y = 4.0 };
    const ball_radius: f32 = 20;

    var frames_counter: i32 = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.f)) rl.toggleFullscreen(); // modifies window size when scaling!

        if (rl.isKeyPressed(.r)) toggleWindowState(.{ .window_resizable = true });
        if (rl.isKeyPressed(.d)) toggleWindowState(.{ .window_undecorated = true });

        if (rl.isKeyPressed(.h)) {
            if (!rl.isWindowState(.{ .window_hidden = true })) rl.setWindowState(.{ .window_hidden = true });

            frames_counter = 0;
        }

        if (rl.isWindowState(.{ .window_hidden = true })) {
            frames_counter += 1;
            if (frames_counter >= 240) rl.clearWindowState(.{ .window_hidden = true }); // Show window after 3 seconds
        }

        if (rl.isKeyPressed(.n)) {
            if (!rl.isWindowState(.{ .window_minimized = true })) rl.minimizeWindow();

            frames_counter = 0;
        }

        if (rl.isWindowState(.{ .window_minimized = true })) {
            frames_counter += 1;
            if (frames_counter >= 240) {
                rl.restoreWindow(); // Restore window after 3 seconds
                frames_counter = 0;
            }
        }

        if (rl.isKeyPressed(.m)) {
            // NOTE: Requires window_resizable enabled!
            if (rl.isWindowState(.{ .window_maximized = true })) rl.restoreWindow() else rl.maximizeWindow();
        }

        if (rl.isKeyPressed(.u)) toggleWindowState(.{ .window_unfocused = true });
        if (rl.isKeyPressed(.t)) toggleWindowState(.{ .window_topmost = true });
        if (rl.isKeyPressed(.a)) toggleWindowState(.{ .window_always_run = true });
        if (rl.isKeyPressed(.v)) toggleWindowState(.{ .vsync_hint = true });
        if (rl.isKeyPressed(.b)) rl.toggleBorderlessWindowed();

        // Bouncing ball logic
        const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
        ball_position.x += ball_speed.x;
        ball_position.y += ball_speed.y;
        if (ball_position.x >= screen_w - ball_radius or ball_position.x <= ball_radius) ball_speed.x *= -1.0;
        if (ball_position.y >= screen_h - ball_radius or ball_position.y <= ball_radius) ball_speed.y *= -1.0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(if (rl.isWindowState(.{ .window_transparent = true })) .blank else .ray_white);

        rl.drawCircleV(ball_position, ball_radius, .maroon);
        rl.drawRectangleLinesEx(.{ .x = 0, .y = 0, .width = screen_w, .height = screen_h }, 4, .ray_white);

        rl.drawCircleV(rl.getMousePosition(), 10, .dark_blue);

        rl.drawFPS(10, 10);

        rl.drawText(rl.textFormat("Screen Size: [{d}, {d}]", .{ rl.getScreenWidth(), rl.getScreenHeight() }), 10, 40, 10, .green);

        // Draw window state info
        rl.drawText("Following flags can be set after window creation:", 10, 60, 10, .gray);
        for (runtime_flags, 0..) |status, i| drawFlagStatus(status, 80 + 20 * @as(i32, @intCast(i)));

        rl.drawText("Following flags can only be set before window creation:", 10, 320, 10, .gray);
        for (creation_flags, 0..) |status, i| drawFlagStatus(status, 340 + 20 * @as(i32, @intCast(i)));
    }
}

fn toggleWindowState(flags: rl.ConfigFlags) void {
    if (rl.isWindowState(flags)) rl.clearWindowState(flags) else rl.setWindowState(flags);
}

fn drawFlagStatus(status: FlagStatus, y: i32) void {
    if (rl.isWindowState(status.flags)) {
        rl.drawText(status.on, 10, y, 10, .lime);
    } else {
        rl.drawText(status.off, 10, y, 10, .maroon);
    }
}
