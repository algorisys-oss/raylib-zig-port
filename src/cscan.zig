//! cscan - the part of glibc's `sscanf` raylib's text formats use.
//!
//! raylib parses its automation events file and BMFont descriptors with
//! `sscanf`, so their results follow glibc's rules: `%i` picks its base from
//! the prefix ("0x" hex, "0" octal), values are read as a C `long` and then
//! truncated to 32 bits, a space in the format matches any whitespace run.
//! `Scanner` reproduces those rules on a slice; automation.zig and
//! rtext_bmfont.zig parse through it.

const std = @import("std");

pub const Scanner = struct {
    text: []const u8,
    pos: usize = 0,

    pub const Base = enum {
        /// `%d`
        decimal,
        /// `%i`: "0x" means hex, a leading "0" octal
        auto,
    };

    /// A scanner starting at the first `key` in `line` (C's `strstr`).
    pub fn from(line: []const u8, key: []const u8) ?Scanner {
        const start = std.mem.indexOf(u8, line, key) orelse return null;
        return .{ .text = line, .pos = start };
    }

    /// Matches a format literal: a space matches any run of whitespace,
    /// including none; other bytes match themselves.
    pub fn literal(scanner: *Scanner, format: []const u8) bool {
        for (format) |f| {
            if (f == ' ') {
                scanner.skipWhitespace();
            } else if (scanner.pos < scanner.text.len and scanner.text[scanner.pos] == f) {
                scanner.pos += 1;
            } else return false;
        }
        return true;
    }

    /// `format` followed by `%i`.
    pub fn intAfter(scanner: *Scanner, format: []const u8) ?i32 {
        if (!scanner.literal(format)) return null;
        return scanner.int(.auto);
    }

    pub fn skipWhitespace(scanner: *Scanner) void {
        while (scanner.pos < scanner.text.len and std.ascii.isWhitespace(scanner.text[scanner.pos])) scanner.pos += 1;
    }

    /// `%d` or `%i`: whitespace, a sign, then digits. As in glibc, the value is
    /// read as a C `long`, saturating on overflow, then truncated to 32 bits;
    /// for `%i`, "0x" without hex digits reads as 0 and is consumed. Null,
    /// with nothing consumed, when there is no number.
    pub fn int(scanner: *Scanner, base_kind: Base) ?i32 {
        scanner.skipWhitespace();
        const text = scanner.text;
        var i = scanner.pos;

        const negative = i < text.len and text[i] == '-';
        if (i < text.len and (text[i] == '-' or text[i] == '+')) i += 1;

        var base: u8 = 10;
        var matched = false;
        if (base_kind == .auto and i < text.len and text[i] == '0') {
            i += 1;
            matched = true;
            base = 8;
            if (i < text.len and std.ascii.toLower(text[i]) == 'x') {
                i += 1;
                base = 16;
            }
        }

        const limit: u128 = 1 << 64; // beyond any C long: saturated anyway
        var magnitude: u128 = 0;
        while (i < text.len) : (i += 1) {
            const digit = std.fmt.charToDigit(text[i], base) catch break;
            if (magnitude < limit) magnitude = magnitude * base + digit;
            matched = true;
        }
        if (!matched) return null;

        scanner.pos = i;
        const signed: i128 = if (negative) -@as(i128, @intCast(magnitude)) else @intCast(magnitude);
        const long: i64 = @intCast(std.math.clamp(signed, std.math.minInt(i64), std.math.maxInt(i64)));
        return @truncate(long);
    }

    /// `%N[^end]`: 1 to `max` bytes up to `end`; null when there are none.
    pub fn until(scanner: *Scanner, end: u8, max: usize) ?[]const u8 {
        const rest = scanner.text[scanner.pos..];
        const window = rest[0..@min(rest.len, max)];
        const len = std.mem.indexOfScalar(u8, window, end) orelse window.len;
        if (len == 0) return null;
        scanner.pos += len;
        return rest[0..len];
    }
};

const testing = std.testing;

fn testInt(text: []const u8, base: Scanner.Base) ?i32 {
    var scanner: Scanner = .{ .text = text };
    return scanner.int(base);
}

test "Scanner.int follows glibc %i and %d" {
    try testing.expectEqual(16, testInt(" 0x10", .auto));
    try testing.expectEqual(31, testInt("+0X1F", .auto));
    try testing.expectEqual(8, testInt("010", .auto));
    try testing.expectEqual(0, testInt("09", .auto));
    try testing.expectEqual(0, testInt("0x", .auto));
    try testing.expectEqual(0, testInt("0xg", .auto));
    try testing.expectEqual(-2, testInt("-0x2", .auto));
    try testing.expectEqual(null, testInt("-", .auto));
    try testing.expectEqual(null, testInt("x", .auto));
    try testing.expectEqual(10, testInt("010", .decimal));
    try testing.expectEqual(0, testInt("0x10", .decimal));
    // Wider than 32 bits: truncated; wider than a C long: saturated first.
    try testing.expectEqual(1215752191, testInt("99999999999", .decimal));
    try testing.expectEqual(-1, testInt("0xFFFFFFFF", .auto));
    try testing.expectEqual(-1, testInt("99999999999999999999", .decimal));
    try testing.expectEqual(0, testInt("-99999999999999999999", .decimal));
}

test "Scanner literals" {
    // "0x" is consumed even without digits: the next literal starts after it
    var scanner: Scanner = .{ .text = "id=0x x=5" };
    try testing.expectEqual(0, scanner.intAfter("id="));
    try testing.expectEqual(5, scanner.intAfter(" x="));
    // A space in the format matches no whitespace too, and tabs
    scanner = .{ .text = "a=1b=2\tc=3" };
    try testing.expectEqual(1, scanner.intAfter("a="));
    try testing.expectEqual(2, scanner.intAfter(" b="));
    try testing.expectEqual(3, scanner.intAfter(" c="));
    try testing.expectEqual(null, scanner.intAfter(" d="));
}

test "Scanner.until" {
    var scanner: Scanner = .{ .text = "name.png\" rest" };
    try testing.expectEqualStrings("name.png", scanner.until('"', 128).?);
    try testing.expectEqual(null, scanner.until('"', 128));
}
