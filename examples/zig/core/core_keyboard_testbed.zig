//! raylib [core] example - keyboard testbed
//!
//! Zig-API translation of examples/core/core_keyboard_testbed.c (raylib 6.2).
//! NOTE: raylib defined keys refer to ENG-US Keyboard layout,
//! mapping to other layouts is up to the user
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const key_rec_spacing = 4; // Space in pixels between key rectangles

/// One key of the on-screen keyboard
const Key = struct {
    key: rl.KeyboardKey,
    width: i32 = 45,
};

/// One row of the on-screen keyboard
const Row = struct {
    keys: []const Key,
    y: f32, // Offset from the keyboard top
    height: f32,
};

const rows = [_]Row{
    // Keyboard line 01 - 15 keys
    // ESC, F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12, IMP, CLOSE
    .{ .y = 0, .height = 30.0, .keys = &.{
        .{ .key = .escape }, .{ .key = .f1 },                        .{ .key = .f2 },    .{ .key = .f3 },
        .{ .key = .f4 },     .{ .key = .f5 },                        .{ .key = .f6 },    .{ .key = .f7 },
        .{ .key = .f8 },     .{ .key = .f9 },                        .{ .key = .f10 },   .{ .key = .f11 },
        .{ .key = .f12 },    .{ .key = .print_screen, .width = 62 }, .{ .key = .pause },
    } },
    // Keyboard line 02 - 15 keys
    // `, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, -, =, BACKSPACE, DEL
    .{ .y = 30 + key_rec_spacing, .height = 38.0, .keys = &.{
        .{ .key = .grave, .width = 25 }, .{ .key = .one },                    .{ .key = .two },
        .{ .key = .three },              .{ .key = .four },                   .{ .key = .five },
        .{ .key = .six },                .{ .key = .seven },                  .{ .key = .eight },
        .{ .key = .nine },               .{ .key = .zero },                   .{ .key = .minus },
        .{ .key = .equal },              .{ .key = .backspace, .width = 82 }, .{ .key = .delete },
    } },
    // Keyboard line 03 - 15 keys
    // TAB, Q, W, E, R, T, Y, U, I, O, P, [, ], \, INS
    .{ .y = 30 + 38 + key_rec_spacing * 2, .height = 38.0, .keys = &.{
        .{ .key = .tab, .width = 50 }, .{ .key = .q },                      .{ .key = .w },
        .{ .key = .e },                .{ .key = .r },                      .{ .key = .t },
        .{ .key = .y },                .{ .key = .u },                      .{ .key = .i },
        .{ .key = .o },                .{ .key = .p },                      .{ .key = .left_bracket },
        .{ .key = .right_bracket },    .{ .key = .backslash, .width = 57 }, .{ .key = .insert },
    } },
    // Keyboard line 04 - 14 keys
    // MAYUS, A, S, D, F, G, H, J, K, L, ;, ', ENTER, REPAG
    .{ .y = 30 + 38 * 2 + key_rec_spacing * 3, .height = 38.0, .keys = &.{
        .{ .key = .caps_lock, .width = 68 }, .{ .key = .a },         .{ .key = .s },
        .{ .key = .d },                      .{ .key = .f },         .{ .key = .g },
        .{ .key = .h },                      .{ .key = .j },         .{ .key = .k },
        .{ .key = .l },                      .{ .key = .semicolon }, .{ .key = .apostrophe },
        .{ .key = .enter, .width = 88 },     .{ .key = .page_up },
    } },
    // Keyboard line 05 - 14 keys
    // LSHIFT, Z, X, C, V, B, N, M, ,, ., /, RSHIFT, UP, AVPAG
    .{ .y = 30 + 38 * 3 + key_rec_spacing * 4, .height = 38.0, .keys = &.{
        .{ .key = .left_shift, .width = 80 }, .{ .key = .z },         .{ .key = .x },
        .{ .key = .c },                       .{ .key = .v },         .{ .key = .b },
        .{ .key = .n },                       .{ .key = .m },         .{ .key = .comma },
        .{ .key = .period },                  .{ .key = .slash },     .{ .key = .right_shift, .width = 76 },
        .{ .key = .up },                      .{ .key = .page_down },
    } },
    // Keyboard line 06 - 11 keys
    // LCTRL, WIN, LALT, SPACE, ALTGR, \, FN, RCTRL, LEFT, DOWN, RIGHT
    .{ .y = 30 + 38 * 4 + key_rec_spacing * 5, .height = 38.0, .keys = &.{
        .{ .key = .left_control, .width = 80 }, .{ .key = .left_super },
        .{ .key = .left_alt },                  .{ .key = .space, .width = 208 },
        .{ .key = .right_alt },                 .{ .key = @fromBackingInt(@intCast(162)) },
        .{ .key = .null },                      .{ .key = .right_control, .width = 60 },
        .{ .key = .left },                      .{ .key = .down },
        .{ .key = .right },
    } },
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - keyboard testbed");
    defer rl.closeWindow(); // Close window and OpenGL context
    rl.setExitKey(.null); // Avoid exit on KEY_ESCAPE

    const keyboard_offset: rl.Vector2 = .{ .x = 26, .y = 80 };

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const key = rl.getKeyPressed(); // Get pressed keycode
        if (@backingInt(key) > 0) rl.traceLog(.info, "KEYBOARD TESTBED: KEY PRESSED:    {d}", .{@backingInt(key)});

        const ch = rl.getCharPressed(); // Get pressed char for text input, using OS mapping
        if (ch > 0) rl.traceLog(.info, "KEYBOARD TESTBED: CHAR PRESSED:   {c} ({d})", .{ @as(u8, @truncate(@as(u32, @bitCast(ch)))), ch });

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("KEYBOARD LAYOUT: ENG-US", 26, 38, 20, .light_gray);

        for (rows) |row| {
            var rec_offset_x: i32 = 0;
            for (row.keys) |key_info| {
                guiKeyboardKey(.{
                    .x = keyboard_offset.x + @as(f32, @floatFromInt(rec_offset_x)),
                    .y = keyboard_offset.y + row.y,
                    .width = @floatFromInt(key_info.width),
                    .height = row.height,
                }, key_info.key);
                rec_offset_x += key_info.width + key_rec_spacing;
            }
        }
    }
}

/// Get keyboard keycode as text (US keyboard)
/// NOTE: Mapping for other keyboard layouts can be done here
fn getKeyText(key: rl.KeyboardKey) [:0]const u8 {
    return switch (key) {
        .apostrophe => "'", // Key: '
        .comma => ",", // Key: ,
        .minus => "-", // Key: -
        .period => ".", // Key: .
        .slash => "/", // Key: /
        .zero => "0", // Key: 0
        .one => "1", // Key: 1
        .two => "2", // Key: 2
        .three => "3", // Key: 3
        .four => "4", // Key: 4
        .five => "5", // Key: 5
        .six => "6", // Key: 6
        .seven => "7", // Key: 7
        .eight => "8", // Key: 8
        .nine => "9", // Key: 9
        .semicolon => ";", // Key: ;
        .equal => "=", // Key: =
        .a => "A", // Key: A | a
        .b => "B", // Key: B | b
        .c => "C", // Key: C | c
        .d => "D", // Key: D | d
        .e => "E", // Key: E | e
        .f => "F", // Key: F | f
        .g => "G", // Key: G | g
        .h => "H", // Key: H | h
        .i => "I", // Key: I | i
        .j => "J", // Key: J | j
        .k => "K", // Key: K | k
        .l => "L", // Key: L | l
        .m => "M", // Key: M | m
        .n => "N", // Key: N | n
        .o => "O", // Key: O | o
        .p => "P", // Key: P | p
        .q => "Q", // Key: Q | q
        .r => "R", // Key: R | r
        .s => "S", // Key: S | s
        .t => "T", // Key: T | t
        .u => "U", // Key: U | u
        .v => "V", // Key: V | v
        .w => "W", // Key: W | w
        .x => "X", // Key: X | x
        .y => "Y", // Key: Y | y
        .z => "Z", // Key: Z | z
        .left_bracket => "[", // Key: [
        .backslash => "\\", // Key: '\'
        .right_bracket => "]", // Key: ]
        .grave => "`", // Key: `
        .space => "SPACE", // Key: Space
        .escape => "ESC", // Key: Esc
        .enter => "ENTER", // Key: Enter
        .tab => "TAB", // Key: Tab
        .backspace => "BACK", // Key: Backspace
        .insert => "INS", // Key: Ins
        .delete => "DEL", // Key: Del
        .right => "RIGHT", // Key: Cursor right
        .left => "LEFT", // Key: Cursor left
        .down => "DOWN", // Key: Cursor down
        .up => "UP", // Key: Cursor up
        .page_up => "PGUP", // Key: Page up
        .page_down => "PGDOWN", // Key: Page down
        .home => "HOME", // Key: Home
        .end => "END", // Key: End
        .caps_lock => "CAPS", // Key: Caps lock
        .scroll_lock => "LOCK", // Key: Scroll down
        .num_lock => "NUMLOCK", // Key: Num lock
        .print_screen => "PRINTSCR", // Key: Print screen
        .pause => "PAUSE", // Key: Pause
        .f1 => "F1", // Key: F1
        .f2 => "F2", // Key: F2
        .f3 => "F3", // Key: F3
        .f4 => "F4", // Key: F4
        .f5 => "F5", // Key: F5
        .f6 => "F6", // Key: F6
        .f7 => "F7", // Key: F7
        .f8 => "F8", // Key: F8
        .f9 => "F9", // Key: F9
        .f10 => "F10", // Key: F10
        .f11 => "F11", // Key: F11
        .f12 => "F12", // Key: F12
        .left_shift => "LSHIFT", // Key: Shift left
        .left_control => "LCTRL", // Key: Control left
        .left_alt => "LALT", // Key: Alt left
        .left_super => "WIN", // Key: Super left
        .right_shift => "RSHIFT", // Key: Shift right
        .right_control => "RCTRL", // Key: Control right
        .right_alt => "ALTGR", // Key: Alt right
        .right_super => "RSUPER", // Key: Super right
        .kb_menu => "KBMENU", // Key: KB menu
        .kp_0 => "KP0", // Key: Keypad 0
        .kp_1 => "KP1", // Key: Keypad 1
        .kp_2 => "KP2", // Key: Keypad 2
        .kp_3 => "KP3", // Key: Keypad 3
        .kp_4 => "KP4", // Key: Keypad 4
        .kp_5 => "KP5", // Key: Keypad 5
        .kp_6 => "KP6", // Key: Keypad 6
        .kp_7 => "KP7", // Key: Keypad 7
        .kp_8 => "KP8", // Key: Keypad 8
        .kp_9 => "KP9", // Key: Keypad 9
        .kp_decimal => "KPDEC", // Key: Keypad .
        .kp_divide => "KPDIV", // Key: Keypad /
        .kp_multiply => "KPMUL", // Key: Keypad *
        .kp_subtract => "KPSUB", // Key: Keypad -
        .kp_add => "KPADD", // Key: Keypad +
        .kp_enter => "KPENTER", // Key: Keypad Enter
        .kp_equal => "KPEQU", // Key: Keypad =
        else => "",
    };
}

/// Draw keyboard key
fn guiKeyboardKey(bounds: rl.Rectangle, key: rl.KeyboardKey) void {
    if (key == .null) {
        rl.drawRectangleLinesEx(bounds, 2.0, .light_gray);
    } else {
        const color: rl.Color = if (rl.isKeyDown(key)) .maroon else .dark_gray;
        rl.drawRectangleLinesEx(bounds, 2.0, color);
        rl.drawText(getKeyText(key), @intFromFloat(bounds.x + 4), @intFromFloat(bounds.y + 4), 10, color);
    }

    if (rl.checkCollisionPointRec(rl.getMousePosition(), bounds)) {
        rl.drawRectangleRec(bounds, rl.fade(.red, 0.2));
        rl.drawRectangleLinesEx(bounds, 3.0, .red);
    }
}
