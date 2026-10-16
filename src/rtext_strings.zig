//! rtext_strings - the text logic behind raylib's Text* and codepoint API.
//!
//! rtext.zig exports raylib's C functions over this file. raylib returns most
//! of its strings in fixed static buffers (MAX_TEXT_BUFFER_LENGTH bytes); the
//! functions here write into an `out` buffer the caller has zeroed, and never
//! past `out.len - 1`, so the result stays NUL-terminated. Limits, truncation
//! points and odd corners follow raylib 6.2 exactly: test/cdiff/text_strings.c
//! and test/cdiff/text_fonts.c compare them with the C library byte for byte.

const std = @import("std");

//------------------------------------------------------------------------------
// Case and spacing
//------------------------------------------------------------------------------

/// TextToUpper: ASCII letters only, as raylib.
pub fn toUpper(out: []u8, text: []const u8) void {
    const len = @min(text.len, out.len - 1);
    for (out[0..len], text[0..len]) |*o, c| o.* = std.ascii.toUpper(c);
}

/// TextToLower: ASCII letters only, as raylib.
pub fn toLower(out: []u8, text: []const u8) void {
    const len = @min(text.len, out.len - 1);
    for (out[0..len], text[0..len]) |*o, c| o.* = std.ascii.toLower(c);
}

/// TextRemoveSpaces. Like raylib, it reads at most `out.len - 1` bytes of
/// `text`, not writes: spaces past that point are never reached.
pub fn removeSpaces(out: []u8, text: []const u8) void {
    var len: usize = 0;
    for (text[0..@min(text.len, out.len - 1)]) |c| {
        if (c == ' ') continue;
        out[len] = c;
        len += 1;
    }
}

pub const FirstLetter = enum { upper, lower };

/// TextToPascal (`first` = .upper) and TextToCamel (`first` = .lower): drops
/// '_' separators and upper-cases the byte after each run of them. The first
/// byte is only case-converted, so a leading '_' stays.
pub fn joinWords(out: []u8, text: [:0]const u8, first: FirstLetter) void {
    if (text.len == 0) return;
    out[0] = switch (first) {
        .upper => std.ascii.toUpper(text[0]),
        .lower => std.ascii.toLower(text[0]),
    };

    var i: usize = 1;
    var j: usize = 1;
    while (i < out.len - 1 and text[j] != 0) : ({
        i += 1;
        j += 1;
    }) {
        if (text[j] != '_') {
            out[i] = text[j];
            continue;
        }
        while (text[j] == '_') j += 1; // Skip one or more separators
        if (text[j] == 0) break; // Text ends on a separator, nothing left to copy
        out[i] = std.ascii.toUpper(text[j]); // Non-letters are copied as is
    }
}

/// TextToSnake: a '_' at each space and word boundary, capitals lowered.
/// Consecutive capitals are one word (HTTPRequest -> http_request).
pub fn snake(out: []u8, text: [:0]const u8) void {
    var i: usize = 0;
    var j: usize = 0;
    while (i < out.len - 1 and text[j] != 0) : (j += 1) {
        const c = text[j];
        const can_separate = i > 0 and out[i - 1] != '_';

        if (c == ' ') {
            if (can_separate) {
                out[i] = '_';
                i += 1;
            }
        } else if (std.ascii.isUpper(c)) {
            if (can_separate) {
                // i > 0 here, so j > 0 too
                const prev = text[j - 1];
                const next = text[j + 1];
                const boundary = std.ascii.isLower(prev) or (std.ascii.isUpper(prev) and std.ascii.isLower(next));
                if (boundary and i < out.len - 2) {
                    out[i] = '_';
                    i += 1;
                }
            }
            out[i] = std.ascii.toLower(c);
            i += 1;
        } else {
            out[i] = c;
            i += 1;
        }
    }
}

//------------------------------------------------------------------------------
// Pieces of text
//------------------------------------------------------------------------------

/// Copies as much of `text` as fits before `out`'s last byte.
pub fn copyTruncated(out: []u8, text: []const u8) void {
    const len = @min(text.len, out.len - 1);
    @memcpy(out[0..len], text[0..len]);
}

/// TextSubtext: `length` bytes from `position`, clamped to the text and to
/// `out`. Negative or out-of-range arguments give an empty result.
pub fn subtext(out: []u8, text: []const u8, position: i32, length: i32) void {
    if (position < 0 or length <= 0) return;
    const start: usize = @intCast(position);
    if (start >= text.len) return;
    const len = @min(@as(usize, @intCast(length)), text.len - start, out.len - 1);
    @memcpy(out[0..len], text[start..][0..len]);
}

/// Where the text between two markers starts and ends.
pub const Between = struct {
    /// Index just past `begin`
    start: usize,
    /// Index of `end`
    end: usize,
};

/// The first `begin`, then the first `end` after it (raylib's TextFindIndex
/// twice: an empty marker matches at once).
pub fn findBetween(text: []const u8, begin: []const u8, end: []const u8) ?Between {
    const start = (std.mem.find(u8, text, begin) orelse return null) + begin.len;
    const len = std.mem.find(u8, text[start..], end) orelse return null;
    return .{ .start = start, .end = start + len };
}

/// GetTextBetween.
pub fn between(out: []u8, text: []const u8, begin: []const u8, end: []const u8) void {
    const found = findBetween(text, begin, end) orelse return;
    // Deliberate raylib quirk: when the piece is too long for the buffer, the
    // whole rest of the text, end marker included, is copied (truncated).
    if (found.end - found.start < out.len - 1) {
        @memcpy(out[0 .. found.end - found.start], text[found.start..found.end]);
    } else {
        copyTruncated(out, text[found.start..]);
    }
}

/// Length of `text` with the piece `found` replaced by `replacement`.
pub fn replaceBetweenSize(text: []const u8, found: Between, replacement: []const u8) usize {
    return found.start + replacement.len + (text.len - found.end);
}

/// TextReplaceBetween(Alloc): writes `text` with the piece `found` (markers
/// kept) replaced by `replacement`. `out.len` must be `replaceBetweenSize`.
pub fn replaceBetween(out: []u8, text: []const u8, found: Between, replacement: []const u8) void {
    @memcpy(out[0..found.start], text[0..found.start]);
    @memcpy(out[found.start..][0..replacement.len], replacement);
    @memcpy(out[found.start + replacement.len ..], text[found.end..]);
}

/// TextInsert(Alloc): writes `text` with `insert` spliced in at `position`
/// (<= text.len). `out.len` must be `text.len + insert.len`.
pub fn insert(out: []u8, text: []const u8, piece: []const u8, position: usize) void {
    @memcpy(out[0..position], text[0..position]);
    @memcpy(out[position..][0..piece.len], piece);
    @memcpy(out[position + piece.len ..], text[position..]);
}

//------------------------------------------------------------------------------
// Numbers
//------------------------------------------------------------------------------

/// TextToInteger: an optional sign, then decimal digits up to the first
/// non-digit. Overflow wraps, as the C code does on every raylib target.
pub fn parseInt(text: []const u8) i32 {
    const negative, const digits = splitSign(text);
    var value: i32 = 0;
    for (digits) |c| {
        if (!std.ascii.isDigit(c)) break;
        value = value *% 10 +% (c - '0');
    }
    return if (negative) 0 -% value else value;
}

/// TextToFloat: an optional sign, digits, and a fraction after '.'. No
/// exponent. The arithmetic (and so the rounding) is raylib's, step by step.
pub fn parseFloat(text: []const u8) f32 {
    const negative, const digits = splitSign(text);
    var value: f32 = 0.0;
    var i: usize = 0;
    while (i < digits.len and std.ascii.isDigit(digits[i])) : (i += 1) {
        value = value * 10.0 + @as(f32, @floatFromInt(digits[i] - '0'));
    }
    if (i < digits.len and digits[i] == '.') {
        var divisor: f32 = 10.0;
        for (digits[i + 1 ..]) |c| {
            if (!std.ascii.isDigit(c)) break;
            value += @as(f32, @floatFromInt(c - '0')) / divisor;
            divisor = divisor * 10.0;
        }
    }
    return value * @as(f32, if (negative) -1.0 else 1.0);
}

fn splitSign(text: []const u8) struct { bool, []const u8 } {
    if (text.len > 0 and (text[0] == '+' or text[0] == '-')) return .{ text[0] == '-', text[1..] };
    return .{ false, text };
}

//------------------------------------------------------------------------------
// UTF-8
//------------------------------------------------------------------------------

/// A codepoint and the bytes it took. Malformed input decodes as '?'.
pub const Decoded = struct {
    codepoint: i32,
    size: u3,

    const invalid: Decoded = .{ .codepoint = '?', .size = 1 };

    fn fail(size: u3) Decoded {
        return .{ .codepoint = '?', .size = size };
    }
};

/// Byte `i` of a C string viewed through `bytes`: past the end reads as the
/// NUL terminator, which no continuation check accepts.
fn at(bytes: []const u8, i: usize) u8 {
    return if (i < bytes.len) bytes[i] else 0;
}

fn isContinuation(byte: u8) bool {
    return byte & 0xc0 == 0x80;
}

/// GetCodepointNext: decodes by the lead byte alone, without rejecting
/// overlong forms or surrogates. A broken sequence takes one byte.
pub fn decodeNext(bytes: []const u8) Decoded {
    const b0: i32 = at(bytes, 0);
    if (b0 & 0xf8 == 0xf0) {
        if (!isContinuation(at(bytes, 1)) or !isContinuation(at(bytes, 2)) or !isContinuation(at(bytes, 3))) return .invalid;
        return .{ .codepoint = (b0 & 0x07) << 18 | trail(bytes, 1) << 12 | trail(bytes, 2) << 6 | trail(bytes, 3), .size = 4 };
    }
    if (b0 & 0xf0 == 0xe0) {
        if (!isContinuation(at(bytes, 1)) or !isContinuation(at(bytes, 2))) return .invalid;
        return .{ .codepoint = (b0 & 0x0f) << 12 | trail(bytes, 1) << 6 | trail(bytes, 2), .size = 3 };
    }
    if (b0 & 0xe0 == 0xc0) {
        if (!isContinuation(at(bytes, 1))) return .invalid;
        return .{ .codepoint = (b0 & 0x1f) << 6 | trail(bytes, 1), .size = 2 };
    }
    if (b0 & 0x80 == 0) return .{ .codepoint = b0, .size = 1 };
    return .invalid;
}

fn trail(bytes: []const u8, i: usize) i32 {
    return at(bytes, i) & 0x3f;
}

/// GetCodepoint: the strict decoder (rejects overlong forms, surrogates and
/// values past U+10FFFF). The sizes it reports on errors are raylib's: how far
/// it read before giving up, even when that byte was the terminator.
pub fn decode(bytes: []const u8) Decoded {
    const octet = at(bytes, 0);
    const o1 = at(bytes, 1);
    const o2 = at(bytes, 2);
    const o3 = at(bytes, 3);

    if (octet <= 0x7f) return .{ .codepoint = octet, .size = 1 };

    if (octet & 0xe0 == 0xc0) {
        if (!isContinuation(o1)) return .fail(2);
        if (octet < 0xc2) return .invalid; // Overlong two-octet form
        return .{ .codepoint = @as(i32, octet & 0x1f) << 6 | (o1 & 0x3f), .size = 2 };
    }

    if (octet & 0xf0 == 0xe0) {
        if (!isContinuation(o1)) return .fail(2);
        if (!isContinuation(o2)) return .fail(3);
        // Overlong forms and UTF-16 surrogates
        if ((octet == 0xe0 and o1 < 0xa0) or (octet == 0xed and o1 > 0x9f)) return .fail(2);
        return .{ .codepoint = @as(i32, octet & 0x0f) << 12 | @as(i32, o1 & 0x3f) << 6 | (o2 & 0x3f), .size = 3 };
    }

    if (octet & 0xf8 == 0xf0) {
        if (octet > 0xf4) return .invalid;
        if (!isContinuation(o1)) return .fail(2);
        if (!isContinuation(o2)) return .fail(3);
        if (!isContinuation(o3)) return .fail(4);
        // Overlong forms and values past U+10FFFF
        if ((octet == 0xf0 and o1 < 0x90) or (octet == 0xf4 and o1 > 0x8f)) return .fail(2);
        return .{
            .codepoint = @as(i32, octet & 0x07) << 18 | @as(i32, o1 & 0x3f) << 12 | @as(i32, o2 & 0x3f) << 6 | (o3 & 0x3f),
            .size = 4,
        };
    }

    return .invalid;
}

/// CodepointToUTF8: the encoding of `codepoint` in `out`, empty past
/// U+10FFFF. Like raylib, it does not reject surrogates, and a negative
/// value encodes as its low byte.
pub fn encode(codepoint: i32, out: *[4]u8) []const u8 {
    const cp: u32 = @bitCast(codepoint);
    if (codepoint <= 0x7f) {
        out[0] = @truncate(cp);
        return out[0..1];
    }
    if (codepoint <= 0x7ff) {
        out[0..2].* = .{ @truncate(0xc0 | (cp >> 6 & 0x1f)), @truncate(0x80 | (cp & 0x3f)) };
        return out[0..2];
    }
    if (codepoint <= 0xffff) {
        out[0..3].* = .{ @truncate(0xe0 | (cp >> 12 & 0x0f)), @truncate(0x80 | (cp >> 6 & 0x3f)), @truncate(0x80 | (cp & 0x3f)) };
        return out[0..3];
    }
    if (codepoint <= 0x10ffff) {
        out.* = .{
            @truncate(0xf0 | (cp >> 18 & 0x07)), @truncate(0x80 | (cp >> 12 & 0x3f)),
            @truncate(0x80 | (cp >> 6 & 0x3f)),  @truncate(0x80 | (cp & 0x3f)),
        };
        return out;
    }
    return out[0..0];
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const testing = std.testing;

fn expectOut(expected: []const u8, comptime f: anytype, args: anytype) !void {
    var out: [16]u8 = @splat(0);
    @call(.auto, f, .{@as([]u8, &out)} ++ args);
    try testing.expectEqualStrings(expected, std.mem.sliceTo(&out, 0));
}

test "case conversion" {
    try expectOut("HELLO_1", toUpper, .{"hello_1"});
    try expectOut("abc d", toLower, .{"ABC d"});
    try expectOut("ABCDEFGHIJKLMNO", toUpper, .{"abcdefghijklmnopqrs"}); // truncated to the buffer
    try expectOut("abc", removeSpaces, .{" a b  c "});
    try expectOut("HelloWorld", joinWords, .{ "hello__world_", FirstLetter.upper });
    try expectOut("_lead", joinWords, .{ "_lead", FirstLetter.lower });
    try expectOut("helloWorld", joinWords, .{ "Hello_world", FirstLetter.lower });
    try expectOut("http_request", snake, .{"HTTPRequest"});
    try expectOut("hello_world", snake, .{"Hello World"});
}

test "pieces" {
    try expectOut("ell", subtext, .{ "hello", 1, 3 });
    try expectOut("", subtext, .{ "hello", -1, 3 });
    try expectOut("lo", subtext, .{ "hello", 3, 99 });
    try expectOut("mid", between, .{ "a[mid]b", "[", "]" });
    try expectOut("", between, .{ "a[mid", "[", "]" });
    // Too long for the buffer: everything after `begin`
    try expectOut("0123456789abcde", between, .{ "[0123456789abcdefgh]tail", "[", "]" });

    const text = "x<<y>>z";
    const found = findBetween(text, "<<", ">>").?;
    try testing.expectEqual(Between{ .start = 3, .end = 4 }, found);
    var out: [8]u8 = undefined;
    const size = replaceBetweenSize(text, found, "AB");
    replaceBetween(out[0..size], text, found, "AB");
    try testing.expectEqualStrings("x<<AB>>z", out[0..size]);

    insert(out[0..5], "abc", "XY", 1);
    try testing.expectEqualStrings("aXYbc", out[0..5]);
}

test parseInt {
    try testing.expectEqual(42, parseInt("42abc"));
    try testing.expectEqual(-7, parseInt("-7"));
    try testing.expectEqual(0, parseInt("--3"));
    try testing.expectEqual(0, parseInt(""));
    try testing.expectEqual(-2147483648, parseInt("2147483648"));
}

test parseFloat {
    try testing.expectEqual(@as(f32, 3.25), parseFloat("3.25"));
    try testing.expectEqual(@as(f32, -0.5), parseFloat("-0.5"));
    try testing.expectEqual(@as(f32, 1.0), parseFloat("1e5"));
    try testing.expectEqual(@as(f32, 0.5), parseFloat(".5"));
}

test "utf8 round trip" {
    var buf: [4]u8 = undefined;
    for ([_]i32{ 0x41, 0xe9, 0x4f60, 0x1f600, 0x10ffff }) |cp| {
        const bytes = encode(cp, &buf);
        try testing.expectEqual(Decoded{ .codepoint = cp, .size = @intCast(bytes.len) }, decodeNext(bytes));
        try testing.expectEqual(Decoded{ .codepoint = cp, .size = @intCast(bytes.len) }, decode(bytes));
    }
    try testing.expectEqual(0, encode(0x110000, &buf).len);
    try testing.expectEqualSlices(u8, &.{0xff}, encode(-1, &buf));
}

test "utf8 errors" {
    try testing.expectEqual(Decoded.invalid, decodeNext("\xc3"));
    try testing.expectEqual(Decoded.fail(2), decode("\xc3"));
    try testing.expectEqual(Decoded.invalid, decode("\xc0\x80"));
    try testing.expectEqual(Decoded.fail(3), decode("\xe4\xbd"));
    try testing.expectEqual(Decoded.fail(2), decode("\xed\xa0\x80"));
    try testing.expectEqual(Decoded{ .codepoint = 0xd800, .size = 3 }, decodeNext("\xed\xa0\x80"));
    try testing.expectEqual(Decoded.invalid, decode("\xf5\x80\x80\x80"));
    try testing.expectEqual(Decoded.invalid, decodeNext("\x80"));
}
