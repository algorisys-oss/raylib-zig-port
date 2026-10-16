//! rtext_bmfont - reading AngelCode BMFont text files (.fnt).
//!
//! rtext.zig's LoadBMFont loads the atlas pages and builds the Font; this file
//! reads the text. raylib reads it line by line into a 256-byte buffer and
//! parses each line with `sscanf`, so the results follow glibc's rules: `%i`
//! reads hex ("0x") and octal (leading "0") numbers, a space in the format
//! matches any run of whitespace (or none), and a field that fails to parse
//! ends the line. `cscan.Scanner` (shared with automation.zig) reproduces those rules; the
//! format strings here are raylib's. test/cdiff/text_fonts.c compares the result with the C library
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
const Scanner = @import("cscan.zig").Scanner;

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

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const testing = std.testing;

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
