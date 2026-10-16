//! rtext_bmfont - reading AngelCode BMFont text files (.fnt).
//!
//! rtext.zig's LoadBMFont loads the atlas pages and builds the Font; this file
//! reads the text. raylib reads it line by line into a 256-byte buffer and
//! parses each line with `sscanf`, so the results follow glibc's rules: `%i`
//! reads hex ("0x") and octal (leading "0") numbers, a space in the format
//! matches any run of whitespace (or none), and a field that fails to parse
//! ends the line. `Scanner` reproduces exactly the part of `sscanf` raylib's
//! formats use; test/cdiff/text_fonts.c compares the result with the C library
//! over crafted files.
//!
//! A file looks like:
//!
//!     info face="PixAntiqua" size=32 ...
//!     common lineHeight=32 base=27 scaleW=512 scaleH=512 pages=1 ...
//!     page id=0 file="pixantiqua.png"
//!     chars count=184
//!     char id=32   x=9     y=304   width=7     height=36    xoffset=-3    yoffset=-2    xadvance=8     page=0  chnl=15

const std = @import("std");

/// Line reader with raylib's GetLine rules: a line ends at '\n' or after
/// `max_line_length` bytes, and the byte after it is always skipped (so the
/// first byte of the rest of an over-long line is lost).
///
/// raylib scans for '\n' without stopping at the end of the text, reading
/// past it when the last line has no '\n'. Here the end of the text ends the
/// line, and lines past the end are empty.
pub const Lines = struct {
    rest: []const u8,

    /// raylib's buffer is 256 bytes, one kept for the terminator.
    pub const max_line_length = 255;

    pub fn next(lines: *Lines) []const u8 {
        const window = lines.rest[0..@min(lines.rest.len, max_line_length)];
        const len = std.mem.findScalar(u8, window, '\n') orelse window.len;
        const line = lines.rest[0..len];
        lines.rest = lines.rest[@min(len + 1, lines.rest.len)..];
        return line;
    }
};

/// The `common` line. raylib needs the first four fields; `pages` is
/// optional and defaults to 1.
pub const Common = struct {
    line_height: i32,
    base: i32,
    scale_w: i32,
    scale_h: i32,
    pages: i32 = 1,
};

/// `sscanf(strstr(line, "lineHeight"), "lineHeight=%i base=%i scaleW=%i scaleH=%i pages=%i", ...)`
pub fn scanCommon(line: []const u8) ?Common {
    var scanner = Scanner.from(line, "lineHeight") orelse return null;
    var common: Common = .{
        .line_height = scanner.intAfter("lineHeight=") orelse return null,
        .base = scanner.intAfter(" base=") orelse return null,
        .scale_w = scanner.intAfter(" scaleW=") orelse return null,
        .scale_h = scanner.intAfter(" scaleH=") orelse return null,
    };
    if (scanner.intAfter(" pages=")) |pages| common.pages = pages;
    return common;
}

/// raylib's page file name buffer holds 128 bytes and a terminator.
pub const max_page_file_length = 128;

/// `sscanf(strstr(line, "file"), "file=\"%128[^\"]\"", name)`: the quoted
/// file name, cut at 128 bytes; null when it is empty.
pub fn scanPageFile(line: []const u8) ?[]const u8 {
    var scanner = Scanner.from(line, "file") orelse return null;
    if (!scanner.literal("file=\"")) return null;
    return scanner.until('"', max_page_file_length);
}

/// `sscanf(strstr(line, "count"), "count=%i", &count)`
pub fn scanCount(line: []const u8) ?i32 {
    var scanner = Scanner.from(line, "count") orelse return null;
    return scanner.intAfter("count=");
}

/// One `char` line.
pub const Char = struct {
    id: i32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    offset_x: i32,
    offset_y: i32,
    advance_x: i32,
    page: i32,
};

/// `sscanf(line, "char id=%i x=%i y=%i width=%i height=%i xoffset=%i yoffset=%i xadvance=%i page=%i", ...)`:
/// null unless all nine fields read, as raylib requires.
pub fn scanChar(line: []const u8) ?Char {
    var scanner: Scanner = .{ .text = line };
    return .{
        .id = scanner.intAfter("char id=") orelse return null,
        .x = scanner.intAfter(" x=") orelse return null,
        .y = scanner.intAfter(" y=") orelse return null,
        .width = scanner.intAfter(" width=") orelse return null,
        .height = scanner.intAfter(" height=") orelse return null,
        .offset_x = scanner.intAfter(" xoffset=") orelse return null,
        .offset_y = scanner.intAfter(" yoffset=") orelse return null,
        .advance_x = scanner.intAfter(" xadvance=") orelse return null,
        .page = scanner.intAfter(" page=") orelse return null,
    };
}

/// The part of glibc's `sscanf` raylib's BMFont formats use.
const Scanner = struct {
    text: []const u8,
    pos: usize = 0,

    /// A scanner starting at the first `key` in `line` (raylib's `strstr`;
    /// raylib itself crashes when the key is missing).
    fn from(line: []const u8, key: []const u8) ?Scanner {
        const start = std.mem.find(u8, line, key) orelse return null;
        return .{ .text = line, .pos = start };
    }

    /// Matches a format literal: a space matches any run of whitespace,
    /// including none; other bytes match themselves.
    fn literal(scanner: *Scanner, format: []const u8) bool {
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
    fn intAfter(scanner: *Scanner, format: []const u8) ?i32 {
        if (!scanner.literal(format)) return null;
        return scanner.int();
    }

    fn skipWhitespace(scanner: *Scanner) void {
        while (scanner.pos < scanner.text.len and std.ascii.isWhitespace(scanner.text[scanner.pos])) scanner.pos += 1;
    }

    /// `%i`: whitespace, a sign, then a number whose base follows its prefix
    /// ("0x" hex, "0" octal). As in glibc, the value is read as a C `long`,
    /// saturating on overflow, then truncated to 32 bits, and "0x" without hex
    /// digits reads as 0 and is consumed. Null, nothing consumed, without
    /// digits.
    fn int(scanner: *Scanner) ?i32 {
        scanner.skipWhitespace();
        const text = scanner.text;
        var i = scanner.pos;

        const negative = i < text.len and text[i] == '-';
        if (i < text.len and (text[i] == '-' or text[i] == '+')) i += 1;

        var base: u8 = 10;
        var matched = false;
        if (i < text.len and text[i] == '0') {
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
    fn until(scanner: *Scanner, end: u8, max: usize) ?[]const u8 {
        const rest = scanner.text[scanner.pos..];
        const window = rest[0..@min(rest.len, max)];
        const len = std.mem.findScalar(u8, window, end) orelse window.len;
        if (len == 0) return null;
        scanner.pos += len;
        return rest[0..len];
    }
};

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const testing = std.testing;

fn testInt(text: []const u8) ?i32 {
    var scanner: Scanner = .{ .text = text };
    return scanner.int();
}

test "Scanner.int follows glibc %i" {
    try testing.expectEqual(16, testInt(" 0x10"));
    try testing.expectEqual(31, testInt("+0X1F"));
    try testing.expectEqual(8, testInt("010"));
    try testing.expectEqual(0, testInt("08"));
    try testing.expectEqual(0, testInt("0x"));
    try testing.expectEqual(-2, testInt("-0x2"));
    try testing.expectEqual(null, testInt("-"));
    try testing.expectEqual(null, testInt("x"));
    try testing.expectEqual(-1, testInt("0xFFFFFFFF"));
    try testing.expectEqual(-1, testInt("99999999999999999999"));
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

test Lines {
    var lines: Lines = .{ .rest = "ab\n\ncd" };
    try testing.expectEqualStrings("ab", lines.next());
    try testing.expectEqualStrings("", lines.next());
    try testing.expectEqualStrings("cd", lines.next());
    try testing.expectEqualStrings("", lines.next());

    const long = @as([300]u8, @splat('x')) ++ "\nnext";
    lines = .{ .rest = long };
    try testing.expectEqual(Lines.max_line_length, lines.next().len);
    // The byte after a cut line is skipped
    try testing.expectEqual(299 - Lines.max_line_length, lines.next().len);
    try testing.expectEqualStrings("next", lines.next());
}

test scanCommon {
    try testing.expectEqual(Common{ .line_height = 32, .base = 27, .scale_w = 512, .scale_h = 256, .pages = 2 }, scanCommon("common lineHeight=32 base=27 scaleW=512 scaleH=256 pages=2 packed=0"));
    try testing.expectEqual(Common{ .line_height = 16, .base = 12, .scale_w = 64, .scale_h = 64 }, scanCommon("common lineHeight=16 base=12 scaleW=64 scaleH=64"));
    try testing.expectEqual(null, scanCommon("common lineHeight=16 base=12 scaleW=64"));
    try testing.expectEqual(null, scanCommon("common"));
}

test scanPageFile {
    try testing.expectEqualStrings("font.png", scanPageFile("page id=0 file=\"font.png\"").?);
    try testing.expectEqual(null, scanPageFile("page id=0 file=\"\""));
    try testing.expectEqual(null, scanPageFile("page id=0 file="));
    try testing.expectEqual(max_page_file_length, scanPageFile("file=\"" ++ @as([200]u8, @splat('a')) ++ "\"").?.len);
}

test scanChar {
    try testing.expectEqual(Char{ .id = 66, .x = 16, .y = 8, .width = 9, .height = 12, .offset_x = -1, .offset_y = 0, .advance_x = 10, .page = 0 }, scanChar("char id=0x42 x=0x10 y=010 width=+9 height=12 xoffset=-0x1 yoffset=0 xadvance=10 page=0  chnl=15"));
    try testing.expectEqual(null, scanChar("char id=1 x=2 y=3 width=4 height=5 xoffset=6 yoffset=7 xadvance=8"));
    try testing.expectEqual(10, scanCount("chars count=10").?);
    try testing.expectEqual(null, scanCount("chars count=x"));
}
