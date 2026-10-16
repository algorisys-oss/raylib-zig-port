//! rmodels_iqm - the IQM (Inter-Quake Model) v2 file layout, for rmodels.
//!
//! An IQM file is a header followed by arrays of packed little-endian
//! structs, each found by a byte offset the header gives. `File` reads items
//! out of the file bytes by value, so nothing needs to be aligned and nothing
//! is allocated. Reading never goes past the end of the data: missing bytes
//! read as zero (raylib's C loader reads past the buffer in that case).
//!
//! This file imports nothing but `std`, so `zig test src/rmodels_iqm.zig`
//! runs without raylib.

const std = @import("std");

/// The file magic, with its NUL terminator
pub const magic = "INTERQUAKEMODEL\x00";
/// The only IQM version raylib supports
pub const version = 2;

pub const Header = extern struct {
    magic: [16]u8,
    version: u32,
    dataSize: u32,
    flags: u32,
    num_text: u32,
    ofs_text: u32,
    num_meshes: u32,
    ofs_meshes: u32,
    num_vertexarrays: u32,
    num_vertexes: u32,
    ofs_vertexarrays: u32,
    num_triangles: u32,
    ofs_triangles: u32,
    ofs_adjacency: u32,
    num_joints: u32,
    ofs_joints: u32,
    num_poses: u32,
    ofs_poses: u32,
    num_anims: u32,
    ofs_anims: u32,
    num_frames: u32,
    num_framechannels: u32,
    ofs_frames: u32,
    ofs_bounds: u32,
    num_comment: u32,
    ofs_comment: u32,
    num_extensions: u32,
    ofs_extensions: u32,
};

pub const Mesh = extern struct {
    name: u32,
    material: u32,
    first_vertex: u32,
    num_vertexes: u32,
    first_triangle: u32,
    num_triangles: u32,
};

pub const Triangle = extern struct {
    vertex: [3]u32,
};

pub const Joint = extern struct {
    name: u32,
    parent: i32,
    translate: [3]f32,
    rotate: [4]f32,
    scale: [3]f32,
};

pub const VertexArray = extern struct {
    type: u32,
    flags: u32,
    format: u32,
    size: u32,
    offset: u32,
};

/// Vertex array types raylib reads (others exist and are skipped)
pub const VertexArrayType = enum(u32) {
    position = 0,
    texcoord = 1,
    normal = 2,
    tangent = 3,
    blendindexes = 4,
    blendweights = 5,
    color = 6,
    _,
};

pub const Pose = extern struct {
    parent: i32,
    /// Bit c set: channel c has per-frame data
    mask: u32,
    channeloffset: [10]f32,
    channelscale: [10]f32,
};

pub const Anim = extern struct {
    name: u32,
    first_frame: u32,
    num_frames: u32,
    framerate: f32,
    flags: u32,
};

/// Names are read as fixed 32-byte fields, as raylib stores them
pub const Name = [32]u8;

pub const File = struct {
    data: []const u8,
    header: Header,

    pub fn init(data: []const u8) File {
        return .{ .data = data, .header = readAt(data, Header, 0) };
    }

    /// Whether the data is an IQM file raylib can load
    pub fn check(file: File) error{ NotIqm, UnsupportedVersion }!void {
        if (!std.mem.eql(u8, &file.header.magic, magic)) return error.NotIqm;
        if (file.header.version != version) return error.UnsupportedVersion;
    }

    /// Item `index` of an array of `T` that starts at byte `offset`
    pub fn read(file: File, comptime T: type, offset: usize, index: usize) T {
        return readAt(file.data, T, offset +| index *| @sizeOf(T));
    }

    /// The 32-byte name field at `offset` into the text block. Like raylib, it
    /// copies all 32 bytes, including whatever follows the name's terminator.
    pub fn name(file: File, offset: u32) Name {
        return file.read(Name, @as(usize, file.header.ofs_text) + offset, 0);
    }
};

fn readAt(data: []const u8, comptime T: type, start: usize) T {
    var value = std.mem.zeroes(T);
    if (start < data.len) {
        const available = data[start..][0..@min(@sizeOf(T), data.len - start)];
        @memcpy(std.mem.asBytes(&value)[0..available.len], available);
    }
    return value;
}

fn testFile(gpa: std.mem.Allocator) ![]u8 {
    var header = std.mem.zeroes(Header);
    header.magic = magic.*;
    header.version = version;
    header.num_meshes = 1;
    header.ofs_meshes = @sizeOf(Header);
    header.ofs_text = @sizeOf(Header) + @sizeOf(Mesh);

    const mesh: Mesh = .{ .name = 1, .material = 6, .first_vertex = 0, .num_vertexes = 3, .first_triangle = 0, .num_triangles = 1 };
    const text = "\x00body\x00skin.png\x00";

    const data = try gpa.alloc(u8, @sizeOf(Header) + @sizeOf(Mesh) + text.len);
    @memcpy(data[0..@sizeOf(Header)], std.mem.asBytes(&header));
    @memcpy(data[@sizeOf(Header)..][0..@sizeOf(Mesh)], std.mem.asBytes(&mesh));
    @memcpy(data[@sizeOf(Header) + @sizeOf(Mesh) ..], text);
    return data;
}

test "header and arrays" {
    const data = try testFile(std.testing.allocator);
    defer std.testing.allocator.free(data);

    const file: File = .init(data);
    try file.check();
    try std.testing.expectEqual(1, file.header.num_meshes);

    const mesh = file.read(Mesh, file.header.ofs_meshes, 0);
    try std.testing.expectEqual(3, mesh.num_vertexes);

    // A name copies 32 bytes; here the text block ends first, padding with zeros
    const name = file.name(mesh.name);
    try std.testing.expectEqualStrings("body", std.mem.sliceTo(&name, 0));
    try std.testing.expectEqualStrings("skin.png", std.mem.sliceTo(name[5..], 0));
    try std.testing.expectEqual(0, name[31]);
    try std.testing.expectEqualStrings("skin.png", std.mem.sliceTo(&file.name(mesh.material), 0));
}

test "reads past the end are zero" {
    const data = try testFile(std.testing.allocator);
    defer std.testing.allocator.free(data);

    const file: File = .init(data);
    // Mesh 1 overlaps the 16-byte text block: its first 16 bytes come from it
    const partial = file.read(Mesh, file.header.ofs_meshes, 1);
    try std.testing.expectEqual(0, partial.num_triangles);
    try std.testing.expectEqual(std.mem.zeroes(Mesh), file.read(Mesh, file.header.ofs_meshes, 2));
    try std.testing.expectEqual(0, file.read(u32, std.math.maxInt(usize), 3));
}

test "File.check" {
    const data = try testFile(std.testing.allocator);
    defer std.testing.allocator.free(data);

    data[@offsetOf(Header, "version")] = 3;
    try std.testing.expectError(error.UnsupportedVersion, File.init(data).check());

    data[0] = 'X';
    try std.testing.expectError(error.NotIqm, File.init(data).check());

    // Too short for a header: what is there is compared, the rest reads as zero
    try std.testing.expectError(error.NotIqm, File.init("INTERQUAKE").check());
    try std.testing.expectError(error.UnsupportedVersion, File.init(magic).check());
}
