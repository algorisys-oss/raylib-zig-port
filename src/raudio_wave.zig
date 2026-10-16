//! raudio_wave - the Wave logic of raudio that needs no C: sample
//! normalization, crop ranges and the ExportWaveAsCode text.
//!
//! Imports nothing but `std`, so `zig test src/raudio_wave.zig` checks it
//! without an audio device or the C library. raudio.zig keeps the C-ABI edge:
//! `Wave`, the C heap and printf-style float formatting.

const std = @import("std");
const Writer = std.Io.Writer;

/// The shape of a wave's sample data, as raylib's `Wave` describes it.
pub const Info = struct {
    frameCount: u32,
    sampleRate: u32,
    sampleSize: u32,
    channels: u32,

    /// Size of the sample data in bytes. Wraps like raylib's unsigned int
    /// arithmetic, so a huge wave reports the same size C does.
    pub fn byteSize(info: Info) u32 {
        return info.frameCount *% info.channels *% info.sampleSize / 8;
    }

    /// Number of interleaved samples (frames times channels), wrapping as C.
    pub fn sampleCount(info: Info) u32 {
        return info.frameCount *% info.channels;
    }
};

/// Converts interleaved samples to floats in [-1..1], as LoadWaveSamples.
/// `data` holds `out.len` samples of `sampleSize` bits. Sizes other than 8,
/// 16 and 32 bits leave `out` untouched, as raylib does.
pub fn normalizeSamples(out: []f32, sampleSize: u32, data: [*]const u8) void {
    switch (sampleSize) {
        8 => for (out, data[0..out.len]) |*sample, byte| {
            sample.* = @as(f32, @floatFromInt(@as(i32, byte) - 128)) / 128.0;
        },
        16 => {
            // The 16/32-bit views are made only here: 8-bit data has no alignment
            const shorts: [*]const i16 = @ptrCast(@alignCast(data));
            for (out, shorts[0..out.len]) |*sample, short| sample.* = @as(f32, @floatFromInt(short)) / 32768.0;
        },
        32 => {
            const floats: [*]const f32 = @ptrCast(@alignCast(data));
            @memcpy(out, floats[0..out.len]);
        },
        else => {},
    }
}

/// Byte range of the frames `[initFrame, finalFrame)`, or null when the range
/// is out of bounds (WaveCrop's check: `initFrame >= 0`, a non-empty range,
/// `finalFrame <= frameCount`).
pub fn cropRange(info: Info, initFrame: i32, finalFrame: i32) ?struct { start: usize, len: usize } {
    if (initFrame < 0 or initFrame >= finalFrame) return null;
    if (@as(u32, @intCast(finalFrame)) > info.frameCount) return null;

    const frameBytes = struct {
        fn of(i: Info, frames: u32) u32 {
            return frames *% i.channels *% i.sampleSize / 8;
        }
    }.of;
    return .{
        .start = frameBytes(info, @intCast(initFrame)),
        .len = frameBytes(info, @intCast(finalFrame - initFrame)),
    };
}

/// The array name ExportWaveAsCode derives from a file name: at most 255
/// bytes, ASCII letters upper-cased, everything else kept as is.
pub fn variableName(buf: *[255]u8, fileName: []const u8) []u8 {
    const name = buf[0..@min(fileName.len, buf.len)];
    _ = std.ascii.upperString(name, fileName[0..name.len]);
    return name;
}

/// Sample data to write as code: bytes for 8/16-bit (and any other) waves,
/// floats for 32-bit waves.
pub const Samples = union(enum) {
    bytes: []const u8,
    floats: []const f32,
};

/// Formats one float the way raylib's `%.4f` does, into `buf`.
pub const FloatFormatter = *const fn (buf: *[64]u8, value: f32) []const u8;

const values_per_line = 20;

/// Writes ExportWaveAsCode's C header text. `samples` must not be empty:
/// raylib always writes the last value, even of an empty array (it reads
/// before the buffer then); here that is a bounds-check failure instead.
pub fn writeCode(w: *Writer, name: []const u8, info: Info, samples: Samples, formatFloat: FloatFormatter) Writer.Error!void {
    try w.writeAll(
        \\
        \\//////////////////////////////////////////////////////////////////////////////////
        \\//                                                                              //
        \\// WaveAsCode exporter v1.1 - Wave data exported as an array of bytes           //
        \\//                                                                              //
        \\// more info and bugs-report:  github.com/raysan5/raylib                        //
        \\// feedback and support:       ray[at]raylib.com                                //
        \\//                                                                              //
        \\// Copyright (c) 2018-2026 Ramon Santamaria (@raysan5)                          //
        \\//                                                                              //
        \\//////////////////////////////////////////////////////////////////////////////////
        \\
        \\// Wave data information
        \\
    );
    try w.print("#define {s}_FRAME_COUNT      {d}\n", .{ name, info.frameCount });
    try w.print("#define {s}_SAMPLE_RATE      {d}\n", .{ name, info.sampleRate });
    try w.print("#define {s}_SAMPLE_SIZE      {d}\n", .{ name, info.sampleSize });
    try w.print("#define {s}_CHANNELS         {d}\n\n", .{ name, info.channels });

    // Frame data is channel-interlaced: frame01[sampleChannel1, sampleChannel2, ...], frame02[], ...
    switch (samples) {
        .floats => |floats| {
            try w.print("static float {s}_DATA[{d}] = {{\n", .{ name, floats.len });
            var buf: [64]u8 = undefined;
            for (floats[0 .. floats.len - 1], 1..) |value, i| {
                try w.print("{s}f,{s}", .{ formatFloat(&buf, value), separator(i) });
            }
            try w.print("{s}f }};\n", .{formatFloat(&buf, floats[floats.len - 1])});
        },
        .bytes => |bytes| {
            try w.print("static unsigned char {s}_DATA[{d}] = {{ ", .{ name, bytes.len });
            for (bytes[0 .. bytes.len - 1], 1..) |byte, i| {
                try w.print("0x{x},{s}", .{ byte, separator(i) });
            }
            try w.print("0x{x} }};\n", .{bytes[bytes.len - 1]});
        },
    }
}

/// What follows the i-th value (1-based): a line break every 20 values.
fn separator(i: usize) []const u8 {
    return if (i % values_per_line == 0) "\n    " else " ";
}

test normalizeSamples {
    var out: [3]f32 = undefined;
    normalizeSamples(&out, 8, &[_]u8{ 0, 128, 255 });
    try std.testing.expectEqualSlices(f32, &.{ -1.0, 0.0, 127.0 / 128.0 }, &out);

    const shorts = [_]i16{ -32768, 0, 16384 };
    normalizeSamples(&out, 16, @ptrCast(&shorts));
    try std.testing.expectEqualSlices(f32, &.{ -1.0, 0.0, 0.5 }, &out);

    const floats = [_]f32{ 0.25, -2.0, 7.0 };
    normalizeSamples(&out, 32, @ptrCast(&floats));
    try std.testing.expectEqualSlices(f32, &floats, &out);

    out = .{ 9, 9, 9 };
    normalizeSamples(&out, 24, @ptrCast(&floats));
    try std.testing.expectEqualSlices(f32, &.{ 9, 9, 9 }, &out);
}

test cropRange {
    const info: Info = .{ .frameCount = 10, .sampleRate = 8000, .sampleSize = 16, .channels = 2 };
    const r = cropRange(info, 2, 5).?;
    try std.testing.expectEqual(8, r.start);
    try std.testing.expectEqual(12, r.len);
    try std.testing.expectEqual(40, cropRange(info, 0, 10).?.len);
    try std.testing.expect(cropRange(info, -1, 5) == null);
    try std.testing.expect(cropRange(info, 5, 5) == null);
    try std.testing.expect(cropRange(info, 6, 5) == null);
    try std.testing.expect(cropRange(info, 0, 11) == null);
}

test variableName {
    var buf: [255]u8 = undefined;
    try std.testing.expectEqualStrings("MY_WAVE-1", variableName(&buf, "my_wave-1"));
    const long: [300]u8 = @splat('a');
    const upper: [255]u8 = @splat('A');
    try std.testing.expectEqualStrings(&upper, variableName(&buf, &long));
}

fn testFormat(buf: *[64]u8, value: f32) []const u8 {
    return std.fmt.bufPrint(buf, "{d}", .{value}) catch unreachable;
}

test writeCode {
    const gpa = std.testing.allocator;
    var out: Writer.Allocating = .init(gpa);
    defer out.deinit();

    const info: Info = .{ .frameCount = 21, .sampleRate = 8000, .sampleSize = 8, .channels = 1 };
    var bytes: [21]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i * 12);
    try writeCode(&out.writer, "W", info, .{ .bytes = &bytes }, testFormat);
    const text = out.written();
    try std.testing.expect(std.mem.startsWith(u8, text, "\n////"));
    try std.testing.expect(std.mem.indexOf(u8, text, "#define W_FRAME_COUNT      21\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "#define W_CHANNELS         1\n\nstatic unsigned char W_DATA[21] = { 0x0, 0xc, ") != null);
    try std.testing.expect(std.mem.endsWith(u8, text, "0xe4,\n    0xf0 };\n"));

    out.clearRetainingCapacity();
    try writeCode(&out.writer, "F", info, .{ .floats = &.{ 0.5, -1 } }, testFormat);
    try std.testing.expect(std.mem.endsWith(u8, out.written(), "static float F_DATA[2] = {\n0.5f, -1f };\n"));
}
