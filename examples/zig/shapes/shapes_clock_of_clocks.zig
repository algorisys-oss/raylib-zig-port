//! raylib [shapes] example - clock of clocks
//!
//! Zig-API translation of examples/shapes/shapes_clock_of_clocks.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 JP Mortiboys (@themushroompirates)

const rl = @import("raylib");
const rm = rl.math;

/// Local wall-clock time comes from libc (`time` + `localtime`), as in the C
/// example: Zig's standard library has no time-zone-aware local time.
const libc = struct {
    const Tm = extern struct {
        sec: c_int,
        min: c_int,
        hour: c_int,
        mday: c_int,
        mon: c_int,
        year: c_int,
        wday: c_int,
        yday: c_int,
        isdst: c_int,
        gmtoff: c_long,
        zone: ?[*:0]const u8,
    };
    extern "c" fn time(tloc: ?*c_long) c_long;
    extern "c" fn localtime(timer: *const c_long) *const Tm;
};

fn localTime() libc.Tm {
    const now = libc.time(null);
    return libc.localtime(&now).*;
}

/// Hand angles (big hand, little hand) for each clock face shape.
const tl: rl.Vector2 = .{ .x = 0.0, .y = 90.0 }; // Top-left corner
const tr: rl.Vector2 = .{ .x = 90.0, .y = 180.0 }; // Top-right corner
const br: rl.Vector2 = .{ .x = 180.0, .y = 270.0 }; // Bottom-right corner
const bl: rl.Vector2 = .{ .x = 0.0, .y = 270.0 }; // Bottom-left corner
const hh: rl.Vector2 = .{ .x = 0.0, .y = 180.0 }; // Horizontal line
const vv: rl.Vector2 = .{ .x = 90.0, .y = 270.0 }; // Vertical line
const zz: rl.Vector2 = .{ .x = 135.0, .y = 135.0 }; // Not relevant

/// Each digit is drawn by 6 rows of 4 clocks.
const digit_angles = [10][24]rl.Vector2{
    .{ tl, hh, hh, tr, vv, tl, tr, vv, vv, vv, vv, vv, vv, vv, vv, vv, vv, bl, br, vv, bl, hh, hh, br }, // 0
    .{ tl, hh, tr, zz, bl, tr, vv, zz, zz, vv, vv, zz, zz, vv, vv, zz, tl, br, bl, tr, bl, hh, hh, br }, // 1
    .{ tl, hh, hh, tr, bl, hh, tr, vv, tl, hh, br, vv, vv, tl, hh, br, vv, bl, hh, tr, bl, hh, hh, br }, // 2
    .{ tl, hh, hh, tr, bl, hh, tr, vv, tl, hh, br, vv, bl, hh, tr, vv, tl, hh, br, vv, bl, hh, hh, br }, // 3
    .{ tl, tr, tl, tr, vv, vv, vv, vv, vv, bl, br, vv, bl, hh, tr, vv, zz, zz, vv, vv, zz, zz, bl, br }, // 4
    .{ tl, hh, hh, tr, vv, tl, hh, br, vv, bl, hh, tr, bl, hh, tr, vv, tl, hh, br, vv, bl, hh, hh, br }, // 5
    .{ tl, hh, hh, tr, vv, tl, hh, br, vv, bl, hh, tr, vv, tl, tr, vv, vv, bl, br, vv, bl, hh, hh, br }, // 6
    .{ tl, hh, hh, tr, bl, hh, tr, vv, zz, zz, vv, vv, zz, zz, vv, vv, zz, zz, vv, vv, zz, zz, bl, br }, // 7
    .{ tl, hh, hh, tr, vv, tl, tr, vv, vv, bl, br, vv, vv, tl, tr, vv, vv, bl, br, vv, bl, hh, hh, br }, // 8
    .{ tl, hh, hh, tr, vv, tl, tr, vv, vv, bl, br, vv, bl, hh, tr, vv, tl, hh, br, vv, bl, hh, hh, br }, // 9
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - clock of clocks");
    defer rl.closeWindow(); // Close window and OpenGL context

    const bg_color = rl.colorLerp(.dark_blue, .black, 0.75);
    const hands_color = rl.colorLerp(.yellow, .ray_white, 0.25);

    const clock_face_size: f32 = 24;
    const clock_face_spacing: f32 = 8.0;
    const section_spacing: f32 = 16.0;

    // Time for the hands to move to the new position (in seconds); this must be <1s
    const hands_move_duration: f32 = 0.5;

    const zero: [6][24]rl.Vector2 = @splat(@splat(.{ .x = 0, .y = 0 }));
    var prev_seconds: c_int = -1;
    var current_angles = zero;
    var src_angles = zero;
    var dst_angles = zero;

    var hands_move_timer: f32 = 0.0;
    var hour_mode: c_int = 24;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Get the current time
        const time_info = localTime();

        if (time_info.sec != prev_seconds) {
            // The time has changed, so we need to move the hands to the new positions
            prev_seconds = time_info.sec;

            // The individual digits of the current time (HHMMSS)
            const hour = @mod(time_info.hour, hour_mode);
            const clock_digits = [6]c_int{
                @divTrunc(hour, 10),          @mod(hour, 10),
                @divTrunc(time_info.min, 10), @mod(time_info.min, 10),
                @divTrunc(time_info.sec, 10), @mod(time_info.sec, 10),
            };

            // Fetch where we want all the hands to be
            for (&src_angles, &dst_angles, current_angles, clock_digits, 0..) |*src_row, *dst_row, current_row, value, digit| {
                for (src_row, dst_row, current_row, digit_angles[@intCast(value)]) |*src, *dst, current, target| {
                    src.* = current;
                    dst.* = target;

                    // Quick exception for 12h mode
                    if (digit == 0 and hour_mode == 12 and clock_digits[0] == 0) dst.* = zz;
                    if (src.x > dst.x) src.x -= 360.0;
                    if (src.y > dst.y) src.y -= 360.0;
                }
            }

            // Reset the timer
            hands_move_timer = -rl.getFrameTime();
        }

        // Now let's animate all the hands if we need to
        if (hands_move_timer < hands_move_duration) {
            // Increase the timer but don't go above the maximum
            hands_move_timer = rm.clamp(hands_move_timer + rl.getFrameTime(), 0, hands_move_duration);

            // Calculate the%completion of the animation
            var t = hands_move_timer / hands_move_duration;

            // A little cheeky smoothstep
            t = t * t * (3.0 - 2.0 * t);

            for (&current_angles, src_angles, dst_angles) |*current_row, src_row, dst_row| {
                for (current_row, src_row, dst_row) |*current, src, dst| {
                    current.x = rm.lerp(src.x, dst.x, t);
                    current.y = rm.lerp(src.y, dst.y, t);
                }
            }
        }

        // Handle input
        if (rl.isKeyPressed(.space)) hour_mode = 36 - hour_mode; // Toggle between 12 and 24 hour mode with space

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(bg_color);

        rl.drawText(rl.textFormat("{d}-h mode, space to change", .{hour_mode}), 10, 30, 20, .ray_white);

        var x_offset: f32 = 4.0;

        for (current_angles, 0..) |angles, digit| {
            for (0..6) |row| {
                for (0..4) |col| {
                    const centre: rl.Vector2 = .{
                        .x = x_offset + @as(f32, @floatFromInt(col)) * (clock_face_size + clock_face_spacing) + clock_face_size * 0.5,
                        .y = 100 + @as(f32, @floatFromInt(row)) * (clock_face_size + clock_face_spacing) + clock_face_size * 0.5,
                    };
                    const hands = angles[row * 4 + col];

                    rl.drawRing(centre, clock_face_size * 0.5 - 2.0, clock_face_size * 0.5, 0, 360, 24, .dark_gray);

                    // Big hand
                    rl.drawRectanglePro(
                        .{ .x = centre.x, .y = centre.y, .width = clock_face_size * 0.5 + 4.0, .height = 4.0 },
                        .{ .x = 2.0, .y = 2.0 },
                        hands.x,
                        hands_color,
                    );

                    // Little hand
                    rl.drawRectanglePro(
                        .{ .x = centre.x, .y = centre.y, .width = clock_face_size * 0.5 + 2.0, .height = 4.0 },
                        .{ .x = 2.0, .y = 2.0 },
                        hands.y,
                        hands_color,
                    );
                }
            }

            x_offset += (clock_face_size + clock_face_spacing) * 4;
            if (digit % 2 == 1) {
                rl.drawRing(.{ .x = x_offset + 4.0, .y = 160.0 }, 6.0, 8.0, 0.0, 360.0, 24, hands_color);
                rl.drawRing(.{ .x = x_offset + 4.0, .y = 225.0 }, 6.0, 8.0, 0.0, 360.0, 24, hands_color);
                x_offset += section_spacing;
            }
        }

        rl.drawFPS(10, 10);
    }
}
