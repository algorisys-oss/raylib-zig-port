//! cmem - memory that crosses raylib's C ABI.
//!
//! raylib returns buffers to its C callers (file data, image pixels, mesh
//! arrays, encoded text, ...) and documents that they are released with
//! `free`: through MemFree, UnloadFileData, UnloadImage and friends. Those
//! buffers must live on the C heap, and this file is the one place that
//! touches it. Memory that never leaves Zig takes an `Allocator` instead.

const std = @import("std");

/// `count` zeroed items on the C heap, as raylib's RL_CALLOC. Even an empty
/// result is a real heap pointer, because a C caller may `free` it.
pub fn alloc(comptime T: type, count: usize) error{OutOfMemory}![]T {
    const ptr = std.c.calloc(@max(count, 1), @sizeOf(T)) orelse return error.OutOfMemory;
    const items: [*]T = @ptrCast(@alignCast(ptr));
    return items[0..count];
}

/// One zeroed `T` on the C heap.
pub fn create(comptime T: type) error{OutOfMemory}!*T {
    return &(try alloc(T, 1))[0];
}

/// Resizes C-heap memory to `count` items, as raylib's RL_REALLOC. Items
/// past the old length are not initialized. `ptr` may be null.
pub fn realloc(comptime T: type, ptr: ?[*]T, count: usize) error{OutOfMemory}![]T {
    const new = std.c.realloc(ptr, @max(count, 1) * @sizeOf(T)) orelse return error.OutOfMemory;
    const items: [*]T = @ptrCast(@alignCast(new));
    return items[0..count];
}

/// Releases C-heap memory, typically handed back by a C caller whose struct
/// may not carry the allocation's true length. Accepts any pointer, null too.
pub fn free(ptr: anytype) void {
    std.c.free(@ptrCast(@constCast(ptr)));
}

test alloc {
    const items = try alloc(u32, 4);
    defer free(items.ptr);
    try std.testing.expectEqualSlices(u32, &.{ 0, 0, 0, 0 }, items);

    const empty = try alloc(u8, 0);
    try std.testing.expectEqual(0, empty.len);
    free(empty.ptr);
}

test realloc {
    var items = try alloc(u8, 2);
    items = try realloc(u8, items.ptr, 3);
    defer free(items.ptr);
    try std.testing.expectEqual(3, items.len);
    try std.testing.expectEqual(0, items[1]);
}
