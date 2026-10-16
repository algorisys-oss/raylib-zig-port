//! raylib [shapes] example - digital clock
//!
//! Zig-API translation of examples/shapes/shapes_digital_clock.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Hamza RAHAL (@hmz-rhl) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

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

const ClockMode = enum { analog, digital };

/// Clock hand type
const ClockHand = struct {
    value: u32 = 0, // Time value (unsigned: `{d:0>2}` would print a sign for signed ints)

    // Visual elements
    angle: f32, // Hand angle
    length: i32, // Hand length
    thickness: i32, // Hand thickness
    color: rl.Color, // Hand color
};

/// Clock hands
const Clock = struct {
    second: ClockHand, // Clock hand for seconds
    minute: ClockHand, // Clock hand for minutes
    hour: ClockHand, // Clock hand for hours

    /// Update clock time: hand values and angles
    fn update(clock: *Clock) void {
        const now = libc.time(null);
        const time_info = libc.localtime(&now);

        // Updating time data
        clock.second.value = @intCast(time_info.sec);
        clock.minute.value = @intCast(time_info.min);
        clock.hour.value = @intCast(time_info.hour);

        clock.hour.angle = @as(f32, @floatFromInt(@mod(time_info.hour, 12))) * 180.0 / 6.0;
        clock.hour.angle += @as(f32, @floatFromInt(@mod(time_info.min, 60) * 30)) / 60.0;
        clock.hour.angle -= 90;

        clock.minute.angle = @as(f32, @floatFromInt(@mod(time_info.min, 60))) * 6.0;
        clock.minute.angle += @as(f32, @floatFromInt(@mod(time_info.sec, 60) * 6)) / 60.0;
        clock.minute.angle -= 90;

        clock.second.angle = @as(f32, @floatFromInt(@mod(time_info.sec, 60))) * 6.0;
        clock.second.angle -= 90;
    }
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - digital clock");
    defer rl.closeWindow(); // Close window and OpenGL context

    var clock_mode: ClockMode = .digital;

    // Initialize clock
    // NOTE: Includes visual info for analog clock
    var clock: Clock = .{
        .second = .{ .angle = 45, .length = 140, .thickness = 3, .color = .maroon },
        .minute = .{ .angle = 10, .length = 130, .thickness = 7, .color = .dark_gray },
        .hour = .{ .angle = 0, .length = 100, .thickness = 7, .color = .black },
    };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.space)) {
            // Toggle clock mode
            clock_mode = switch (clock_mode) {
                .digital => .analog,
                .analog => .digital,
            };
        }

        clock.update(); // Update clock required data: value and angle

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw clock in selected mode
        switch (clock_mode) {
            .analog => drawClockAnalog(clock, .{ .x = 400, .y = 240 }),
            .digital => {
                drawClockDigital(clock, .{ .x = 30, .y = 60 });

                // Draw clock using default raylib font
                // WARNING: Pointing to an internal static string that is reused between TextFormat() calls
                const clock_time = rl.textFormat("{d:0>2}:{d:0>2}:{d:0>2}", .{ clock.hour.value, clock.minute.value, clock.second.value });
                rl.drawText(clock_time, @divTrunc(rl.getScreenWidth(), 2) - @divTrunc(rl.measureText(clock_time, 150), 2), 300, 150, .black);
            },
        }

        const mode_name = switch (clock_mode) {
            .digital => "DIGITAL CLOCK",
            .analog => "ANALOGUE CLOCK",
        };
        rl.drawText(rl.textFormat("Press [SPACE] to switch clock mode: {s}", .{mode_name}), 10, 10, 20, .dark_gray);
    }
}

/// Draw analog clock
/// Parameter: position, refers to center position
fn drawClockAnalog(clock: Clock, position: rl.Vector2) void {
    // Draw clock base
    rl.drawCircleV(position, @as(f32, @floatFromInt(clock.second.length)) + 40.0, .light_gray);
    rl.drawCircleV(position, 12.0, .gray);

    // Draw clock minutes/seconds lines
    for (0..60) |i| {
        const angle = (6.0 * @as(f32, @floatFromInt(i)) - 90.0) * rl.deg2rad;
        const inner: f32 = @floatFromInt(clock.second.length + @as(i32, if (i % 5 != 0) 10 else 6));
        const outer: f32 = @floatFromInt(clock.second.length + 20);
        rl.drawLineEx(
            .{ .x = position.x + inner * @cos(angle), .y = position.y + inner * @sin(angle) },
            .{ .x = position.x + outer * @cos(angle), .y = position.y + outer * @sin(angle) },
            if (i % 5 != 0) 1.0 else 3.0,
            .dark_gray,
        );
    }

    // Draw hands: seconds, minutes, hours
    for ([_]ClockHand{ clock.second, clock.minute, clock.hour }) |hand| {
        const thickness: f32 = @floatFromInt(hand.thickness);
        rl.drawRectanglePro(
            .{ .x = position.x, .y = position.y, .width = @floatFromInt(hand.length), .height = thickness },
            .{ .x = 0.0, .y = thickness / 2.0 },
            hand.angle,
            hand.color,
        );
    }
}

/// Draw digital clock
/// Parameter: position, refers to top-left corner
fn drawClockDigital(clock: Clock, position: rl.Vector2) void {
    const off = rl.fade(.light_gray, 0.3);
    const blink: rl.Color = if (clock.second.value % 2 != 0) .red else off;

    // Draw clock using custom 7-segments display (made of shapes)
    drawDisplayValue(.{ .x = position.x, .y = position.y }, clock.hour.value / 10, .red, off);
    drawDisplayValue(.{ .x = position.x + 120, .y = position.y }, clock.hour.value % 10, .red, off);

    const x: i32 = @intFromFloat(position.x);
    const y: i32 = @intFromFloat(position.y);
    rl.drawCircle(x + 240, y + 70, 12, blink);
    rl.drawCircle(x + 240, y + 150, 12, blink);

    drawDisplayValue(.{ .x = position.x + 260, .y = position.y }, clock.minute.value / 10, .red, off);
    drawDisplayValue(.{ .x = position.x + 380, .y = position.y }, clock.minute.value % 10, .red, off);

    rl.drawCircle(x + 500, y + 70, 12, blink);
    rl.drawCircle(x + 500, y + 150, 12, blink);

    drawDisplayValue(.{ .x = position.x + 520, .y = position.y }, clock.second.value / 10, .red, off);
    drawDisplayValue(.{ .x = position.x + 640, .y = position.y }, clock.second.value % 10, .red, off);
}

/// Active segments (bit 0 = A ... bit 6 = G) for each decimal digit
const digit_segments = [10]u7{
    0b0111111, 0b0000110, 0b1011011, 0b1001111, 0b1100110,
    0b1101101, 0b1111101, 0b0000111, 0b1111111, 0b1101111,
};

/// Draw 7-segment display with value
fn drawDisplayValue(position: rl.Vector2, value: u32, color_on: rl.Color, color_off: rl.Color) void {
    if (value > 9) return;
    draw7SDisplay(position, digit_segments[value], color_on, color_off);
}

/// Draw seven segments display
/// Parameter: position, refers to top-left corner of display
/// Parameter: segments, defines in binary the segments to be activated
fn draw7SDisplay(position: rl.Vector2, segments: u7, color_on: rl.Color, color_off: rl.Color) void {
    const segment_len = 60;
    const segment_thick = 20;
    const offset_y_adjust: f32 = segment_thick * 0.3; // HACK: Adjust gap space between segment limits

    const Segment = struct { center: rl.Vector2, vertical: bool };
    const segments_layout = [7]Segment{
        // Segment A
        .{ .center = .{ .x = position.x + segment_thick + segment_len / 2.0, .y = position.y + segment_thick }, .vertical = false },
        // Segment B
        .{ .center = .{ .x = position.x + segment_thick + segment_len + segment_thick / 2.0, .y = position.y + 2 * segment_thick + segment_len / 2.0 - offset_y_adjust }, .vertical = true },
        // Segment C
        .{ .center = .{ .x = position.x + segment_thick + segment_len + segment_thick / 2.0, .y = position.y + 4 * segment_thick + segment_len + segment_len / 2.0 - 3 * offset_y_adjust }, .vertical = true },
        // Segment D
        .{ .center = .{ .x = position.x + segment_thick + segment_len / 2.0, .y = position.y + 5 * segment_thick + 2 * segment_len - 4 * offset_y_adjust }, .vertical = false },
        // Segment E
        .{ .center = .{ .x = position.x + segment_thick / 2.0, .y = position.y + 4 * segment_thick + segment_len + segment_len / 2.0 - 3 * offset_y_adjust }, .vertical = true },
        // Segment F
        .{ .center = .{ .x = position.x + segment_thick / 2.0, .y = position.y + 2 * segment_thick + segment_len / 2.0 - offset_y_adjust }, .vertical = true },
        // Segment G
        .{ .center = .{ .x = position.x + segment_thick + segment_len / 2.0, .y = position.y + 3 * segment_thick + segment_len - 2 * offset_y_adjust }, .vertical = false },
    };

    for (segments_layout, 0..) |segment, bit| {
        const on = (segments >> @intCast(bit)) & 1 != 0;
        drawDisplaySegment(segment.center, segment_len, segment_thick, segment.vertical, if (on) color_on else color_off);
    }
}

/// Draw one 7-segment display segment, horizontal or vertical
fn drawDisplaySegment(center: rl.Vector2, length: i32, thick: i32, vertical: bool, color: rl.Color) void {
    const half_len = @as(f32, @floatFromInt(length)) / 2.0;
    const half_thick = @as(f32, @floatFromInt(thick)) / 2.0;

    if (!vertical) {
        // Horizontal segment points
        //
        //      3___________________________5
        //     /                             \
        //    /1             x               6\
        //    \                               /
        //     \2___________________________4/
        //
        const segment_points_h = [6]rl.Vector2{
            .{ .x = center.x - half_len - half_thick, .y = center.y }, // Point 1
            .{ .x = center.x - half_len, .y = center.y + half_thick }, // Point 2
            .{ .x = center.x - half_len, .y = center.y - half_thick }, // Point 3
            .{ .x = center.x + half_len, .y = center.y + half_thick }, // Point 4
            .{ .x = center.x + half_len, .y = center.y - half_thick }, // Point 5
            .{ .x = center.x + half_len + half_thick, .y = center.y }, // Point 6
        };
        rl.drawTriangleStrip(&segment_points_h, color);
    } else {
        // Vertical segment points
        const segment_points_v = [6]rl.Vector2{
            .{ .x = center.x, .y = center.y - half_len - half_thick }, // Point 1
            .{ .x = center.x - half_thick, .y = center.y - half_len }, // Point 2
            .{ .x = center.x + half_thick, .y = center.y - half_len }, // Point 3
            .{ .x = center.x - half_thick, .y = center.y + half_len }, // Point 4
            .{ .x = center.x + half_thick, .y = center.y + half_len }, // Point 5
            .{ .x = center.x, .y = center.y + half_len + half_thick }, // Point 6
        };
        rl.drawTriangleStrip(&segment_points_v, color);
    }
}
