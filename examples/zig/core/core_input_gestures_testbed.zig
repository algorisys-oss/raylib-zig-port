//! raylib [core] example - input gestures testbed
//!
//! Zig-API translation of examples/core/core_input_gestures_testbed.c (raylib 6.2).
//! Example contributed by ubkp (@ubkp) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 ubkp (@ubkp)

const rl = @import("raylib");

const gesture_log_size = 20;
const max_touch_count = 32;

/// Gesture log filter, toggled by the two log buttons
const LogMode = struct {
    hide_repeat: bool = true, // Hide repeated events
    hide_hold: bool = false, // Hide hold events

    /// Whether `gesture` passes the filter, given the last logged gesture.
    fn accepts(mode: LogMode, gesture: rl.Gesture, previous: rl.Gesture) bool {
        if (gesture == .none) return false;
        const repeated = gesture == previous;
        if (mode.hide_repeat and mode.hide_hold) return (gesture != .hold and !repeated) or @backingInt(gesture) < 3;
        if (mode.hide_hold) return gesture != .hold;
        if (mode.hide_repeat) return !repeated;
        return true;
    }
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - input gestures testbed");
    defer rl.closeWindow(); // Close window and OpenGL context

    const message_position: rl.Vector2 = .{ .x = 160, .y = 7 };

    // Last gesture variables definitions
    var last_gesture: rl.Gesture = .none;
    const last_gesture_position: rl.Vector2 = .{ .x = 165, .y = 130 };

    // Gesture log variables definitions
    // NOTE: The gesture log uses an array (as an inverted circular queue) to store the performed gestures
    var gesture_log: [gesture_log_size][:0]const u8 = @splat("");
    // NOTE: The index for the inverted circular queue (moving from last to first direction, then looping around)
    var gesture_log_index: usize = 0;
    var previous_gesture: rl.Gesture = .none;

    var log_mode: LogMode = .{};

    var gesture_color: rl.Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
    const log_button1: rl.Rectangle = .{ .x = 53, .y = 7, .width = 48, .height = 26 };
    const log_button2: rl.Rectangle = .{ .x = 108, .y = 7, .width = 36, .height = 26 };
    const gesture_log_position: rl.Vector2 = .{ .x = 10, .y = 10 };

    // Protractor variables definitions
    const angle_length: f32 = 90.0;
    var current_angle_degrees: f32 = 0.0;
    const protractor_position: rl.Vector2 = .{ .x = 266.0, .y = 315.0 };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Handle common gestures data
        const current_gesture = rl.getGestureDetected();
        const current_drag_degrees = rl.getGestureDragAngle();
        const current_pitch_degrees = rl.getGesturePinchAngle();
        const touch_count: usize = @intCast(rl.getTouchPointCount());

        // Handle last gesture
        if (current_gesture != .none and current_gesture != .hold and current_gesture != previous_gesture)
            last_gesture = current_gesture; // Filter the meaningful gestures (1, 2, 8 to 512) for the display

        // Handle gesture log
        if (rl.isMouseButtonReleased(.left)) {
            if (rl.checkCollisionPointRec(rl.getMousePosition(), log_button1)) {
                log_mode.hide_repeat = !log_mode.hide_repeat;
            } else if (rl.checkCollisionPointRec(rl.getMousePosition(), log_button2)) {
                log_mode.hide_hold = !log_mode.hide_hold;
            }
        }

        // If the gesture passes the log mode filter, fill the gesture log
        if (log_mode.accepts(current_gesture, previous_gesture)) {
            previous_gesture = current_gesture;
            gesture_color = gestureColor(current_gesture);
            if (gesture_log_index == 0) gesture_log_index = gesture_log_size;
            gesture_log_index -= 1;

            gesture_log[gesture_log_index] = gestureName(current_gesture);
        }

        // Handle protractor
        const gesture_value = @backingInt(current_gesture);
        if (gesture_value > 255) {
            current_angle_degrees = current_pitch_degrees; // Pinch In and Pinch Out
        } else if (gesture_value > 15) {
            current_angle_degrees = current_drag_degrees; // Swipe Right, Swipe Left, Swipe Up and Swipe Down
        } else if (gesture_value > 0) {
            current_angle_degrees = 0.0; // Tap, Doubletap, Hold and Grab
        }

        const current_angle_radians = ((current_angle_degrees + 90.0) * rl.pi / 180); // Convert the current angle to Radians
        // Calculate the final vector for display
        const final_vector: rl.Vector2 = .{
            .x = (angle_length * @sin(current_angle_radians)) + protractor_position.x,
            .y = (angle_length * @cos(current_angle_radians)) + protractor_position.y,
        };

        // Handle touch and mouse pointer points
        var touch_position: [max_touch_count]rl.Vector2 = @splat(.{ .x = 0, .y = 0 });
        var mouse_position: rl.Vector2 = .{ .x = 0, .y = 0 };
        if (current_gesture != .none) {
            if (touch_count != 0) {
                for (touch_position[0..touch_count], 0..) |*position, i| position.* = rl.getTouchPosition(@intCast(i)); // Fill the touch positions
            } else mouse_position = rl.getMousePosition();
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw common elements
        const mx: i32 = @intFromFloat(message_position.x);
        const my: i32 = @intFromFloat(message_position.y);
        rl.drawText("*", mx + 5, my + 5, 10, .black);
        rl.drawText("Example optimized for Web/HTML5\non Smartphones with Touch Screen.", mx + 15, my + 5, 10, .black);
        rl.drawText("*", mx + 5, my + 35, 10, .black);
        rl.drawText("While running on Desktop Web Browsers,\ninspect and turn on Touch Emulation.", mx + 15, my + 35, 10, .black);

        // Draw last gesture
        const lg = last_gesture_position;
        const lx: i32 = @intFromFloat(lg.x);
        const ly: i32 = @intFromFloat(lg.y);
        rl.drawText("Last gesture", lx + 33, ly - 47, 20, .black);
        rl.drawText("Swipe         Tap       Pinch  Touch", lx + 17, ly - 18, 10, .black);
        rl.drawRectangle(lx + 20, ly, 20, 20, if (last_gesture == .swipe_up) .red else .light_gray);
        rl.drawRectangle(lx, ly + 20, 20, 20, if (last_gesture == .swipe_left) .red else .light_gray);
        rl.drawRectangle(lx + 40, ly + 20, 20, 20, if (last_gesture == .swipe_right) .red else .light_gray);
        rl.drawRectangle(lx + 20, ly + 40, 20, 20, if (last_gesture == .swipe_down) .red else .light_gray);
        rl.drawCircle(lx + 80, ly + 16, 10, if (last_gesture == .tap) .blue else .light_gray);
        rl.drawRing(.{ .x = lg.x + 103, .y = lg.y + 16 }, 6.0, 11.0, 0.0, 360.0, 0, if (last_gesture == .drag) .lime else .light_gray);
        rl.drawCircle(lx + 80, ly + 43, 10, if (last_gesture == .doubletap) .sky_blue else .light_gray);
        rl.drawCircle(lx + 103, ly + 43, 10, if (last_gesture == .doubletap) .sky_blue else .light_gray);
        const pinch_out_color: rl.Color = if (last_gesture == .pinch_out) .orange else .light_gray;
        rl.drawTriangle(.{ .x = lg.x + 122, .y = lg.y + 16 }, .{ .x = lg.x + 137, .y = lg.y + 26 }, .{ .x = lg.x + 137, .y = lg.y + 6 }, pinch_out_color);
        rl.drawTriangle(.{ .x = lg.x + 147, .y = lg.y + 6 }, .{ .x = lg.x + 147, .y = lg.y + 26 }, .{ .x = lg.x + 162, .y = lg.y + 16 }, pinch_out_color);
        const pinch_in_color: rl.Color = if (last_gesture == .pinch_in) .violet else .light_gray;
        rl.drawTriangle(.{ .x = lg.x + 125, .y = lg.y + 33 }, .{ .x = lg.x + 125, .y = lg.y + 53 }, .{ .x = lg.x + 140, .y = lg.y + 43 }, pinch_in_color);
        rl.drawTriangle(.{ .x = lg.x + 144, .y = lg.y + 43 }, .{ .x = lg.x + 159, .y = lg.y + 53 }, .{ .x = lg.x + 159, .y = lg.y + 33 }, pinch_in_color);
        for (0..4) |i| {
            const touch_y = ly + 7 + @as(i32, @intCast(i)) * 15;
            rl.drawCircle(lx + 180, touch_y, 5, if (touch_count <= i) .light_gray else gesture_color);
        }

        // Draw gesture log
        const gx: i32 = @intFromFloat(gesture_log_position.x);
        const gy: i32 = @intFromFloat(gesture_log_position.y);
        rl.drawText("Log", gx, gy, 20, .black);

        // Print the gesture log array in the inverted order (looping around if the index started somewhere in the middle)
        for (0..gesture_log_size) |i| {
            const entry = gesture_log[(gesture_log_index + i) % gesture_log_size];
            rl.drawText(entry, gx, gy + 410 - @as(i32, @intCast(i)) * 20, 20, if (i == 0) gesture_color else .light_gray);
        }
        const log_button1_color: rl.Color = if (log_mode.hide_repeat) .maroon else .gray;
        const log_button2_color: rl.Color = if (log_mode.hide_hold) .maroon else .gray;
        const bx: i32 = @intFromFloat(log_button1.x);
        const by: i32 = @intFromFloat(log_button1.y);
        rl.drawRectangleRec(log_button1, log_button1_color);
        rl.drawText("Hide", bx + 7, by + 3, 10, .white);
        rl.drawText("Repeat", bx + 7, by + 13, 10, .white);
        rl.drawRectangleRec(log_button2, log_button2_color);
        rl.drawText("Hide", bx + 62, by + 3, 10, .white);
        rl.drawText("Hold", bx + 62, by + 13, 10, .white);

        // Draw protractor
        const p = protractor_position;
        const px: i32 = @intFromFloat(p.x);
        const py: i32 = @intFromFloat(p.y);
        rl.drawText("Angle", px + 55, py + 76, 10, .black);
        const angle_string = rl.textFormat("{d:.6}", .{current_angle_degrees});
        const angle_string_dot = rl.textFindIndex(angle_string, ".");
        const angle_string_trim = rl.textSubtext(angle_string, 0, angle_string_dot + 3);
        rl.drawText(angle_string_trim, px + 55, py + 92, 20, gesture_color);
        rl.drawCircleV(p, 80.0, .white);
        rl.drawLineEx(.{ .x = p.x - 90, .y = p.y }, .{ .x = p.x + 90, .y = p.y }, 3.0, .light_gray);
        rl.drawLineEx(.{ .x = p.x, .y = p.y - 90 }, .{ .x = p.x, .y = p.y + 90 }, 3.0, .light_gray);
        rl.drawLineEx(.{ .x = p.x - 80, .y = p.y - 45 }, .{ .x = p.x + 80, .y = p.y + 45 }, 3.0, .green);
        rl.drawLineEx(.{ .x = p.x - 80, .y = p.y + 45 }, .{ .x = p.x + 80, .y = p.y - 45 }, 3.0, .green);
        rl.drawText("0", px + 96, py - 9, 20, .black);
        rl.drawText("30", px + 74, py - 68, 20, .black);
        rl.drawText("90", px - 11, py - 110, 20, .black);
        rl.drawText("150", px - 100, py - 68, 20, .black);
        rl.drawText("180", px - 124, py - 9, 20, .black);
        rl.drawText("210", px - 100, py + 50, 20, .black);
        rl.drawText("270", px - 18, py + 92, 20, .black);
        rl.drawText("330", px + 72, py + 50, 20, .black);
        if (current_angle_degrees != 0.0) rl.drawLineEx(p, final_vector, 3.0, gesture_color);

        // Draw touch and mouse pointer points
        if (current_gesture != .none) {
            if (touch_count != 0) {
                for (touch_position[0..touch_count]) |position| {
                    rl.drawCircleV(position, 50.0, rl.fade(gesture_color, 0.5));
                    rl.drawCircleV(position, 5.0, gesture_color);
                }

                if (touch_count == 2) rl.drawLineEx(touch_position[0], touch_position[1], if (current_gesture == .pinch_out) 8.0 else 12.0, gesture_color);
            } else {
                rl.drawCircleV(mouse_position, 35.0, rl.fade(gesture_color, 0.5));
                rl.drawCircleV(mouse_position, 5.0, gesture_color);
            }
        }
    }
}

/// Get text string for gesture value
fn gestureName(gesture: rl.Gesture) [:0]const u8 {
    return switch (gesture) {
        .none => "None",
        .tap => "Tap",
        .doubletap => "Double Tap",
        .hold => "Hold",
        .drag => "Drag",
        .swipe_right => "Swipe Right",
        .swipe_left => "Swipe Left",
        .swipe_up => "Swipe Up",
        .swipe_down => "Swipe Down",
        .pinch_in => "Pinch In",
        .pinch_out => "Pinch Out",
        _ => "Unknown",
    };
}

/// Get color for gesture value
fn gestureColor(gesture: rl.Gesture) rl.Color {
    return switch (gesture) {
        .tap => .blue,
        .doubletap => .sky_blue,
        .drag => .lime,
        .swipe_right, .swipe_left, .swipe_up, .swipe_down => .red,
        .pinch_in => .violet,
        .pinch_out => .orange,
        .none, .hold, _ => .black,
    };
}
