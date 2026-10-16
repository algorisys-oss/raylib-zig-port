//! raylib [core] example - input gestures
//!
//! Zig-API translation of examples/core/core_input_gestures.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const max_gesture_strings = 20;

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - input gestures");
    defer rl.closeWindow(); // Close window and OpenGL context

    var touch_position: rl.Vector2 = .{ .x = 0, .y = 0 };
    const touch_area: rl.Rectangle = .{ .x = 220, .y = 10, .width = screen_width - 230.0, .height = screen_height - 20.0 };

    var gestures_count: usize = 0;
    var gesture_strings: [max_gesture_strings][:0]const u8 = @splat("");

    var current_gesture: rl.Gesture = .none;
    var last_gesture: rl.Gesture = .none;

    //rl.setGesturesEnabled(0b0000000000001001); // Enable only some gestures to be detected

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        last_gesture = current_gesture;
        current_gesture = rl.getGestureDetected();
        touch_position = rl.getTouchPosition(0);

        if (rl.checkCollisionPointRec(touch_position, touch_area) and current_gesture != .none) {
            if (current_gesture != last_gesture) {
                // Store gesture string
                if (gestureName(current_gesture)) |name| gesture_strings[gestures_count] = name;

                gestures_count += 1;

                // Reset gestures strings
                if (gestures_count >= max_gesture_strings) {
                    gesture_strings = @splat("");
                    gestures_count = 0;
                }
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawRectangleRec(touch_area, .gray);
        rl.drawRectangle(225, 15, screen_width - 240, screen_height - 30, .ray_white);

        rl.drawText("GESTURES TEST AREA", screen_width - 270, screen_height - 40, 20, rl.fade(.gray, 0.5));

        for (gesture_strings[0..gestures_count], 0..) |gesture_string, i| {
            const y: i32 = @intCast(20 * i);
            const alpha: f32 = if (i % 2 == 0) 0.5 else 0.3;
            rl.drawRectangle(10, 30 + y, 200, 20, rl.fade(.light_gray, alpha));

            const color: rl.Color = if (i < gestures_count - 1) .dark_gray else .maroon;
            rl.drawText(gesture_string, 35, 36 + y, 10, color);
        }

        rl.drawRectangleLines(10, 29, 200, screen_height - 50, .gray);
        rl.drawText("DETECTED GESTURES", 50, 15, 10, .gray);

        if (current_gesture != .none) rl.drawCircleV(touch_position, 30, .maroon);
    }
}

fn gestureName(gesture: rl.Gesture) ?[:0]const u8 {
    return switch (gesture) {
        .tap => "GESTURE TAP",
        .doubletap => "GESTURE DOUBLETAP",
        .hold => "GESTURE HOLD",
        .drag => "GESTURE DRAG",
        .swipe_right => "GESTURE SWIPE RIGHT",
        .swipe_left => "GESTURE SWIPE LEFT",
        .swipe_up => "GESTURE SWIPE UP",
        .swipe_down => "GESTURE SWIPE DOWN",
        .pinch_in => "GESTURE PINCH IN",
        .pinch_out => "GESTURE PINCH OUT",
        else => null,
    };
}
