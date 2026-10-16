//! rtextures_encode - std-only encoders behind rtextures' C API.
//!
//! Half-float conversion for the 16-bit-per-channel pixel formats, and the
//! "image as code" text that ExportImageAsCode writes. No C types, no C
//! library: `zig test src/rtextures_encode.zig` runs without raylib.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// Converts a half float (IEEE 754 binary16, as stored in R16 pixels) to f32.
///
/// raylib computes every case and multiplies each by its condition. The
/// cases not taken can shift by out-of-range amounts (undefined in C, a panic
/// in Zig), so here only the selected case is computed. The bits returned are
/// the same.
pub fn halfToFloat(x: u16) f32 {
    const h: u32 = x;
    const e = (h & 0x7c00) >> 10; // Exponent
    const m = (h & 0x03ff) << 13; // Mantissa
    const v: u32 = @as(u32, @bitCast(@as(f32, @floatFromInt(m)))) >> 23; // log2 bit hack to count leading zeros
    const sign = (h & 0x8000) << 16;
    const norm: u32 = if (e != 0) ((e + 112) << 23) | m else 0;
    const denorm: u32 = if (e == 0 and m != 0) ((v - 37) << 23) | ((m << @intCast(150 - v)) & 0x007fe000) else 0;
    return @bitCast(sign | norm | denorm);
}

/// Converts an f32 to a half float, rounding to nearest even and saturating
/// out-of-range values. Like `halfToFloat`, only the selected case is computed.
pub fn floatToHalf(x: f32) u16 {
    const b = @as(u32, @bitCast(x)) +% 0x00001000; // Round-to-nearest-even
    const e = (b & 0x7f800000) >> 23; // Exponent
    const m = b & 0x007fffff; // Mantissa
    const sign = (b & 0x80000000) >> 16;
    const norm: u32 = if (e > 112) (((e - 112) << 10) & 0x7c00) | (m >> 13) else 0;
    const denorm: u32 = if (e > 101 and e < 113) (((0x007ff000 + m) >> @intCast(125 - e)) + 1) >> 1 else 0;
    const sat: u32 = if (e > 143) 0x7fff else 0;
    return @truncate(sign | norm | denorm | sat);
}

pub const ImageInfo = struct {
    width: i32,
    height: i32,
    format: i32,
};

/// The text ExportImageAsCode saves: a C header defining `pixels` as a byte
/// array, named after `stem` (the file name without extension) upper-cased.
/// `pixels` must not be empty. The caller owns the result.
pub fn imageAsCode(gpa: Allocator, pixels: []const u8, info: ImageInfo, stem: []const u8) Allocator.Error![:0]u8 {
    std.debug.assert(pixels.len > 0);

    // raylib copies the name into a 256-byte buffer: 255 bytes and a NUL
    var name_buf: [255]u8 = undefined;
    const name = name_buf[0..@min(stem.len, name_buf.len)];
    for (name, stem[0..name.len]) |*out, ch| out.* = std.ascii.toUpper(ch);

    // Sized like raylib's buffer: 6 bytes for each "0x00, " plus the header
    var text: Io.Writer.Allocating = try .initCapacity(gpa, pixels.len * 6 + 2000);
    defer text.deinit();
    writeImageAsCode(&text.writer, pixels, info, name) catch return error.OutOfMemory;
    return text.toOwnedSliceSentinel(0);
}

fn writeImageAsCode(w: *Io.Writer, pixels: []const u8, info: ImageInfo, name: []const u8) Io.Writer.Error!void {
    const bytes_per_line = 20;

    try w.writeAll(
        \\////////////////////////////////////////////////////////////////////////////////////////
        \\//                                                                                    //
        \\// ImageAsCode exporter v1.0 - Image pixel data exported as an array of bytes         //
        \\//                                                                                    //
        \\// more info and bugs-report:  github.com/raysan5/raylib                              //
        \\// feedback and support:       ray[at]raylib.com                                      //
        \\//                                                                                    //
        \\// Copyright (c) 2018-2026 Ramon Santamaria (@raysan5)                                //
        \\//                                                                                    //
        \\////////////////////////////////////////////////////////////////////////////////////////
        \\
        \\// Image data information
        \\
    );
    try w.print("#define {s}_WIDTH    {d}\n", .{ name, info.width });
    try w.print("#define {s}_HEIGHT   {d}\n", .{ name, info.height });
    try w.print("#define {s}_FORMAT   {d}          // raylib internal pixel format\n\n", .{ name, info.format });

    try w.print("static unsigned char {s}_DATA[{d}] = {{ ", .{ name, pixels.len });
    const last = pixels.len - 1;
    for (pixels[0..last], 0..) |byte, i| {
        const sep = if (i % bytes_per_line == 0) ",\n" else ", ";
        try w.print("0x{x}{s}", .{ byte, sep });
    }
    try w.print("0x{x} }};\n", .{pixels[last]});
}

test halfToFloat {
    try std.testing.expectEqual(@as(f32, 0.0), halfToFloat(0x0000));
    try std.testing.expectEqual(@as(f32, 1.0), halfToFloat(0x3c00));
    try std.testing.expectEqual(@as(f32, -2.0), halfToFloat(0xc000));
    try std.testing.expectEqual(@as(f32, 65504.0), halfToFloat(0x7bff));
    try std.testing.expectEqual(std.math.pow(f32, 2, -24), halfToFloat(0x0001)); // smallest subnormal
    try std.testing.expectEqual(std.math.pow(f32, 2, -14) * (1023.0 / 1024.0), halfToFloat(0x03ff)); // largest subnormal
}

test floatToHalf {
    try std.testing.expectEqual(@as(u16, 0x0000), floatToHalf(0.0));
    try std.testing.expectEqual(@as(u16, 0x3c00), floatToHalf(1.0));
    try std.testing.expectEqual(@as(u16, 0xc000), floatToHalf(-2.0));
    try std.testing.expectEqual(@as(u16, 0x3800), floatToHalf(0.5));
    try std.testing.expectEqual(@as(u16, 0x7fff), floatToHalf(1.0e6)); // saturates
    try std.testing.expectEqual(@as(u16, 0x0001), floatToHalf(std.math.pow(f32, 2, -24)));
    try std.testing.expectEqual(@as(u16, 0x0000), floatToHalf(1.0e-30)); // underflows
}

test "half round trip" {
    var h: u16 = 0;
    while (h < 0x7c00) : (h += 1) try std.testing.expectEqual(h, floatToHalf(halfToFloat(h)));
}

test imageAsCode {
    const gpa = std.testing.allocator;
    const text = try imageAsCode(gpa, &.{ 0, 9, 10, 255 }, .{ .width = 2, .height = 1, .format = 2 }, "my-img.v2");
    defer gpa.free(text);
    try std.testing.expect(std.mem.endsWith(u8, text,
        \\
        \\// Image data information
        \\#define MY-IMG.V2_WIDTH    2
        \\#define MY-IMG.V2_HEIGHT   1
        \\#define MY-IMG.V2_FORMAT   2          // raylib internal pixel format
        \\
        \\static unsigned char MY-IMG.V2_DATA[4] = { 0x0,
        \\0x9, 0xa, 0xff };
        \\
    ));
}

test "imageAsCode wraps every 20 bytes and cuts the name" {
    const gpa = std.testing.allocator;
    const pixels: [42]u8 = @splat(7);
    const long_name: [300]u8 = @splat('n');
    const text = try imageAsCode(gpa, &pixels, .{ .width = 42, .height = 1, .format = 1 }, &long_name);
    defer gpa.free(text);
    try std.testing.expectEqual(3, std.mem.count(u8, text, "0x7,\n"));
    const kept: [255]u8 = @splat('N');
    try std.testing.expect(std.mem.indexOf(u8, text, &kept ++ "_WIDTH") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, &kept ++ "N") == null);
}
