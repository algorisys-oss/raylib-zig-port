//! automation - raylib's automation events text format.
//!
//! rcore.zig exports `LoadAutomationEventList` and `ExportAutomationEventList`
//! over this file. A file looks like:
//!
//!     # comment
//!     c 2
//!     e 0 2 65 0 0 0 // Event: INPUT_KEY_DOWN
//!     e 10 3 65 0 0 0
//!
//! raylib reads it with `fgets` into a 256-byte buffer and `sscanf`, and the
//! results depend on both: lines are taken in chunks of at most 255 bytes, a
//! last line without '\n' is never processed, and numbers follow glibc's
//! `%i`/`%d` rules. `parse` reproduces all of that; test/cdiff/core_automation.c
//! checks it against the C library byte for byte.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Scanner = @import("cscan.zig").Scanner;

/// One recorded input event, laid out as raylib.h's `AutomationEvent`.
pub const Event = extern struct {
    frame: u32,
    type: u32,
    params: [4]i32,
};

/// Names of raylib's AutomationEventType values, written as comments on export.
pub const type_names = [_][]const u8{
    "EVENT_NONE",                "INPUT_KEY_UP",
    "INPUT_KEY_DOWN",            "INPUT_KEY_PRESSED",
    "INPUT_KEY_RELEASED",        "INPUT_MOUSE_BUTTON_UP",
    "INPUT_MOUSE_BUTTON_DOWN",   "INPUT_MOUSE_POSITION",
    "INPUT_MOUSE_WHEEL_MOTION",  "INPUT_GAMEPAD_CONNECT",
    "INPUT_GAMEPAD_DISCONNECT",  "INPUT_GAMEPAD_BUTTON_UP",
    "INPUT_GAMEPAD_BUTTON_DOWN", "INPUT_GAMEPAD_AXIS_MOTION",
    "INPUT_TOUCH_UP",            "INPUT_TOUCH_DOWN",
    "INPUT_TOUCH_POSITION",      "INPUT_GESTURE",
    "WINDOW_CLOSE",              "WINDOW_MAXIMIZE",
    "WINDOW_MINIMIZE",           "WINDOW_RESIZE",
    "ACTION_TAKE_SCREENSHOT",    "ACTION_SETTARGETFPS",
};

//------------------------------------------------------------------------------
// Reading
//------------------------------------------------------------------------------

/// What `parse` found.
pub const Parsed = struct {
    /// Events stored, at most `events.len`.
    read: u32,
    /// The count the last `c` line declares; 0 without one.
    declared: u32,
};

/// Parses an automation events file into `events`. Reports to `log`, which
/// needs `readIssue()` (a read found nothing, which raylib logs at the end of
/// every file that ends in '\n') and `beyondCapacity(line)` (an event line
/// that did not fit; `line` includes its '\n').
pub fn parse(text: []const u8, events: []Event, log: anytype) Parsed {
    var parsed: Parsed = .{ .read = 0, .declared = 0 };
    var buf: [line_capacity + 1]u8 = @splat(0);
    var lines: Lines = .{ .rest = text };

    if (!lines.next(&buf)) log.readIssue();
    // Like the C loop, a line is processed only once the read after it
    // started: the one that hit the end of the file is dropped.
    while (!lines.at_end) {
        const line = std.mem.sliceTo(&buf, 0);
        switch (buf[0]) {
            'c' => if (scanCount(line)) |count| {
                parsed.declared = count;
            },
            'e' => if (parsed.read < events.len) {
                scanEvent(line, &events[parsed.read]);
                parsed.read += 1;
            } else {
                log.beyondCapacity(buf[0..line.len :0]);
            },
            else => {},
        }
        if (!lines.next(&buf)) log.readIssue();
    }
    return parsed;
}

/// Longest line chunk: `fgets` into raylib's 256-byte buffer.
const line_capacity = 255;

/// C's `fgets` over the file's bytes.
const Lines = struct {
    rest: []const u8,
    /// Set once a read reached the end of the file, as `feof` would be.
    at_end: bool = false,

    /// Copies the next line, '\n' included, or its next `line_capacity`
    /// bytes, into `buf` with a terminator. Returns false, leaving `buf` as it
    /// was, when there was nothing left to read.
    fn next(lines: *Lines, buf: *[line_capacity + 1]u8) bool {
        var len: usize = 0;
        while (len < line_capacity) {
            if (lines.rest.len == 0) {
                lines.at_end = true;
                break;
            }
            const ch = lines.rest[0];
            lines.rest = lines.rest[1..];
            buf[len] = ch;
            len += 1;
            if (ch == '\n') break;
        }
        if (len == 0) return false;
        buf[len] = 0;
        return true;
    }
};

/// `sscanf(line, "c %i", &count)`.
fn scanCount(line: []const u8) ?u32 {
    var scanner: Scanner = .{ .text = line, .pos = 1 };
    return @bitCast(scanner.int(.auto) orelse return null);
}

/// `sscanf(line, "e %d %d %d %d %d %d ...", ...)`: fields are stored in order
/// until the first that does not parse.
fn scanEvent(line: []const u8, event: *Event) void {
    var scanner: Scanner = .{ .text = line, .pos = 1 };
    event.frame = @bitCast(scanner.int(.decimal) orelse return);
    event.type = @bitCast(scanner.int(.decimal) orelse return);
    for (&event.params) |*param| param.* = scanner.int(.decimal) orelse return;
}

//------------------------------------------------------------------------------
// Writing
//------------------------------------------------------------------------------

/// The automation events file for `events`. The caller owns the result.
pub fn format(gpa: Allocator, events: []const Event) Allocator.Error![:0]u8 {
    var text: std.Io.Writer.Allocating = try .initCapacity(gpa, 256 * events.len + 2048);
    defer text.deinit();
    write(&text.writer, events) catch return error.OutOfMemory;
    return text.toOwnedSliceSentinel(0);
}

fn write(w: *std.Io.Writer, events: []const Event) std.Io.Writer.Error!void {
    try w.writeAll(
        \\#
        \\# Automation events exporter v1.0 - raylib automation events list
        \\#
        \\#    c <events_count>
        \\#    e <frame> <event_type> <param0> <param1> <param2> <param3> // <event_type_name>
        \\#
        \\# more info and bugs-report:  github.com/raysan5/raylib
        \\# feedback and support:       ray[at]raylib.com
        \\#
        \\# Copyright (c) 2023-2026 Ramon Santamaria (@raysan5)
        \\#
        \\
        \\
    );
    // raylib prints the unsigned fields with %i
    const count: u32 = @intCast(events.len);
    try w.print("c {d}\n", .{@as(i32, @bitCast(count))});
    for (events) |event| {
        const p = event.params;
        try w.print("e {d} {d} {d} {d} {d} {d} // Event: {s}\n", .{
            @as(i32, @bitCast(event.frame)), @as(i32, @bitCast(event.type)),
            p[0],                            p[1],
            p[2],                            p[3],
            typeName(event.type),
        });
    }
}

/// The name of an event type; empty for a value raylib does not define
/// (C indexes past its name table there).
fn typeName(event_type: u32) []const u8 {
    return if (event_type < type_names.len) type_names[event_type] else "";
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const testing = std.testing;

test "Lines reads like fgets" {
    var buf: [line_capacity + 1]u8 = @splat(0);
    var lines: Lines = .{ .rest = "ab\ncd" };
    try testing.expect(lines.next(&buf));
    try testing.expectEqualStrings("ab\n", std.mem.sliceTo(&buf, 0));
    try testing.expect(!lines.at_end);
    try testing.expect(lines.next(&buf));
    try testing.expectEqualStrings("cd", std.mem.sliceTo(&buf, 0));
    try testing.expect(lines.at_end);
    try testing.expect(!lines.next(&buf));
    try testing.expectEqualStrings("cd", std.mem.sliceTo(&buf, 0));

    const long: [300]u8 = @splat('x');
    lines = .{ .rest = &long };
    try testing.expect(lines.next(&buf));
    try testing.expectEqual(line_capacity, std.mem.sliceTo(&buf, 0).len);
    try testing.expect(!lines.at_end);
}

const TestLog = struct {
    read_issues: usize = 0,
    overflow: usize = 0,
    fn readIssue(log: *TestLog) void {
        log.read_issues += 1;
    }
    fn beyondCapacity(log: *TestLog, line: [:0]const u8) void {
        std.debug.assert(line[0] == 'e');
        log.overflow += 1;
    }
};

test parse {
    var events: [2]Event = @splat(std.mem.zeroes(Event));
    var log: TestLog = .{};
    const parsed = parse("# x\nc 3\ne 1 2 3 4 5 6\ne 7 8\ne 9 9 9 9 9 9\n", &events, &log);
    try testing.expectEqual(Parsed{ .read = 2, .declared = 3 }, parsed);
    try testing.expectEqual(Event{ .frame = 1, .type = 2, .params = .{ 3, 4, 5, 6 } }, events[0]);
    try testing.expectEqual(Event{ .frame = 7, .type = 8, .params = .{ 0, 0, 0, 0 } }, events[1]);
    try testing.expectEqual(1, log.read_issues);
    try testing.expectEqual(1, log.overflow);

    // Without a final newline the last line is never processed.
    log = .{};
    events = @splat(std.mem.zeroes(Event));
    try testing.expectEqual(Parsed{ .read = 1, .declared = 0 }, parse("e 1 1 1 1 1 1\ne 2 2 2 2 2 2", &events, &log));
    try testing.expectEqual(0, log.read_issues);
}

test format {
    const text = try format(testing.allocator, &.{
        .{ .frame = 0, .type = 2, .params = .{ 65, 0, 0, 0 } },
        .{ .frame = 4000000000, .type = 99, .params = .{ -1, 0, 0, 0 } },
    });
    defer testing.allocator.free(text);
    // A plain string, not a `\\` literal: zig fmt strips the trailing space after "Event:".
    try testing.expect(std.mem.endsWith(u8, text, "#\n\nc 2\n" ++
        "e 0 2 65 0 0 0 // Event: INPUT_KEY_DOWN\n" ++
        "e -294967296 99 -1 0 0 0 // Event: \n"));

    // What format writes, parse reads back.
    var events: [2]Event = undefined;
    var log: TestLog = .{};
    try testing.expectEqual(Parsed{ .read = 2, .declared = 2 }, parse(text, &events, &log));
    try testing.expectEqual(4000000000, events[1].frame);
}
