//! raylib [core] example - input actions
//!
//! Zig-API translation of examples/core/core_input_actions.c (raylib 6.2).
//! Example contributed by Jett (@JettMonstersGoBoom) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jett (@JettMonstersGoBoom)

const std = @import("std");
const rl = @import("raylib");

const Action = enum { up, down, left, right, fire };

/// Key and button inputs
const ActionInput = struct {
    key: rl.KeyboardKey,
    button: rl.GamepadButton,
};

const ActionSet = std.EnumArray(Action, ActionInput);

/// The "default" keyset
/// NOTE: Here WASD and gamepad buttons on the left side for movement
const actions_default: ActionSet = .init(.{
    .up = .{ .key = .w, .button = .left_face_up },
    .down = .{ .key = .s, .button = .left_face_down },
    .left = .{ .key = .a, .button = .left_face_left },
    .right = .{ .key = .d, .button = .left_face_right },
    .fire = .{ .key = .space, .button = .right_face_down },
});

/// The "alternate" keyset
/// NOTE: Here cursor keys and gamepad buttons on the right side for movement
const actions_cursor: ActionSet = .init(.{
    .up = .{ .key = .up, .button = .right_face_up },
    .down = .{ .key = .down, .button = .right_face_down },
    .left = .{ .key = .left, .button = .right_face_left },
    .right = .{ .key = .right, .button = .right_face_right },
    .fire = .{ .key = .space, .button = .left_face_down },
});

var gamepad_index: i32 = 0; // Gamepad default index
var action_inputs: *const ActionSet = &actions_default;

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - input actions");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Set default actions
    var cursor_set = false;
    action_inputs = &actions_default;
    var release_action = false;

    var position: rl.Vector2 = .{ .x = 400.0, .y = 200.0 };
    const size: rl.Vector2 = .{ .x = 40.0, .y = 40.0 };

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        gamepad_index = 0; // Set gamepad being checked

        if (isActionDown(.up)) position.y -= 2;
        if (isActionDown(.down)) position.y += 2;
        if (isActionDown(.left)) position.x -= 2;
        if (isActionDown(.right)) position.x += 2;
        if (isActionPressed(.fire)) {
            position.x = (screen_width - size.x) / 2;
            position.y = (screen_height - size.y) / 2;
        }

        // Register release action for one frame
        release_action = isActionReleased(.fire);

        // Switch control scheme by pressing TAB
        if (rl.isKeyPressed(.tab)) {
            cursor_set = !cursor_set;
            action_inputs = if (cursor_set) &actions_cursor else &actions_default;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.gray);

        rl.drawRectangleV(position, size, if (release_action) .blue else .red);

        rl.drawText(if (cursor_set) "Current input set: Arrow keys" else "Current input set: WASD (default)", 10, 10, 20, .white);
        rl.drawText("Use TAB key to toggles Actions keyset", 10, 50, 20, .green);
    }
}

/// Check action key/button pressed
/// NOTE: Combines key pressed and gamepad button pressed in one action
fn isActionPressed(action: Action) bool {
    const input = action_inputs.get(action);
    return rl.isKeyPressed(input.key) or rl.isGamepadButtonPressed(gamepad_index, input.button);
}

/// Check action key/button released
/// NOTE: Combines key released and gamepad button released in one action
fn isActionReleased(action: Action) bool {
    const input = action_inputs.get(action);
    return rl.isKeyReleased(input.key) or rl.isGamepadButtonReleased(gamepad_index, input.button);
}

/// Check action key/button down
/// NOTE: Combines key down and gamepad button down in one action
fn isActionDown(action: Action) bool {
    const input = action_inputs.get(action);
    return rl.isKeyDown(input.key) or rl.isGamepadButtonDown(gamepad_index, input.button);
}
