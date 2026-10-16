//! rlgl_buffers - CPU-side buffer layouts rlgl hands to and reads from OpenGL.
//!
//! Pure data shuffling with no GL and no C: the index pattern every render
//! batch buffer keeps for its quads, and the row order fix-up for pixels read
//! back from the framebuffer. Kept apart from rlgl.zig so it can be tested
//! with `zig test src/rlgl_buffers.zig`.

const std = @import("std");

/// Fills `indices` with two triangles per quad (0-1-2, 0-2-3), as many quads
/// as fit. rlgl.h computes each index as an int and narrows it to the index
/// type, so a batch with more vertices than a u16 can address wraps around on
/// OpenGL ES rather than failing.
pub fn fillQuadIndices(comptime Index: type, indices: []Index) void {
    for (0..indices.len / 6) |quad| {
        const first = 4 * quad;
        indices[quad * 6 ..][0..6].* = .{
            @truncate(first),
            @truncate(first + 1),
            @truncate(first + 2),
            @truncate(first),
            @truncate(first + 2),
            @truncate(first + 3),
        };
    }
}

/// Turns RGBA pixels read by glReadPixels (bottom row first) into image order
/// (top row first) and makes every pixel opaque, as rlReadScreenPixels does.
pub fn flipRowsOpaque(pixels: []u8, width: usize, height: usize) void {
    const texels = std.mem.bytesAsSlice([4]u8, pixels[0 .. width * height * 4]);
    // With an odd height the middle row pairs with itself: it only turns opaque
    for (0..(height + 1) / 2) |top| {
        const bottom = height - 1 - top;
        for (texels[top * width ..][0..width], texels[bottom * width ..][0..width]) |*upper, *lower| {
            std.mem.swap([4]u8, upper, lower);
            upper[3] = 255;
            lower[3] = 255;
        }
    }
}

test fillQuadIndices {
    var indices: [13]u32 = @splat(7);
    fillQuadIndices(u32, &indices);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7, 7 }, &indices);
}

test "fillQuadIndices wraps 16-bit indices" {
    const gpa = std.testing.allocator;
    const indices = try gpa.alloc(u16, 6 * 16385);
    defer gpa.free(indices);
    fillQuadIndices(u16, indices);
    try std.testing.expectEqualSlices(u16, &.{ 65532, 65533, 65534, 65532, 65534, 65535 }, indices[6 * 16383 ..][0..6]);
    try std.testing.expectEqualSlices(u16, &.{ 0, 1, 2, 0, 2, 3 }, indices[6 * 16384 ..][0..6]);
}

test "flipRowsOpaque with an odd height" {
    var pixels = [_]u8{
        1, 1, 1, 0, 2, 2, 2, 9,
        3, 3, 3, 0, 4, 4, 4, 0,
        5, 5, 5, 0, 6, 6, 6, 0,
    };
    flipRowsOpaque(&pixels, 2, 3);
    try std.testing.expectEqualSlices(u8, &.{
        5, 5, 5, 255, 6, 6, 6, 255,
        3, 3, 3, 255, 4, 4, 4, 255,
        1, 1, 1, 255, 2, 2, 2, 255,
    }, &pixels);
}

test "flipRowsOpaque with an even height and empty input" {
    var pixels = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    flipRowsOpaque(&pixels, 1, 2);
    try std.testing.expectEqualSlices(u8, &.{ 5, 6, 7, 255, 1, 2, 3, 255 }, &pixels);

    var none: [0]u8 = .{};
    flipRowsOpaque(&none, 0, 0);
    flipRowsOpaque(&none, 5, 0);
}
