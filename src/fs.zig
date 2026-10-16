//! fs - the logic behind raylib's file system functions.
//!
//! rcore.zig exports the C API (`LoadFileData`, `LoadDirectoryFilesEx`, ...) as
//! thin wrappers over this file: they turn C strings into slices, pass the
//! process `Io` and the C allocator, and turn errors into raylib's log
//! messages. Here everything takes slices, allocates only through the
//! `Allocator` it is given and reports failure through error unions.
//!
//! The behaviour is raylib 6.2's, quirks included: test/cdiff/core_fileio.c
//! compares it with the C library byte for byte.

const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const Allocator = std.mem.Allocator;

/// Longest path raylib handles, terminator included (Linux PATH_MAX).
pub const max_path_len = 4096;

/// Longest file name `fileStem` keeps.
pub const max_file_name_len = 255;

//------------------------------------------------------------------------------
// Whole files
//------------------------------------------------------------------------------

pub const LoadError = error{
    OpenFailed,
    IsDir,
    /// The file is empty: raylib treats that as a failed read.
    Empty,
    /// Larger than raylib's `int` sizes can describe.
    TooBig,
    OutOfMemory,
};

/// A file read whole. `data.len` is the size the file had when opened;
/// `read` is shorter when the file shrank while being read.
pub const Contents = struct {
    data: []u8,
    read: usize,
};

/// Reads the file at `path`. The caller owns `data`.
pub fn loadFile(io: Io, gpa: Allocator, path: []const u8) LoadError!Contents {
    const file, const size = try openForReading(io, path);
    defer file.close(io);

    if (size == 0) return error.Empty;
    if (size > std.math.maxInt(c_int)) return error.TooBig;

    const data = try gpa.alloc(u8, @intCast(size));
    // A failed read is a short read, as with C's fread.
    const read = file.readPositionalAll(io, data, 0) catch 0;
    return .{ .data = data, .read = read };
}

/// Reads the file at `path` as text. The caller owns the result, which is
/// allocated to its exact length plus the terminator, so C's `free` works too.
pub fn loadText(io: Io, gpa: Allocator, path: []const u8) LoadError![:0]u8 {
    const file, const size = try openForReading(io, path);
    defer file.close(io);

    if (size == 0) return error.Empty;
    if (size >= std.math.maxInt(c_uint)) return error.TooBig;

    var text = try gpa.alloc(u8, @intCast(size + 1));
    const read = file.readPositionalAll(io, text[0..@intCast(size)], 0) catch 0;
    if (read < size) text = try gpa.realloc(text, read + 1);
    text[read] = 0;
    return text[0..read :0];
}

fn openForReading(io: Io, path: []const u8) LoadError!struct { File, u64 } {
    const file = Dir.cwd().openFile(io, path, .{ .allow_directory = false }) catch |err| return switch (err) {
        error.IsDir => error.IsDir,
        else => error.OpenFailed,
    };
    errdefer file.close(io);
    const stat = file.stat(io) catch return error.OpenFailed;
    return .{ file, stat.size };
}

pub const SaveError = error{ OpenFailed, WriteFailed };

/// Creates or truncates the file at `path` and writes `bytes` to it.
pub fn saveFile(io: Io, path: []const u8, bytes: []const u8) SaveError!void {
    const file = Dir.cwd().createFile(io, path, .{}) catch return error.OpenFailed;
    defer file.close(io);
    file.writeStreamingAll(io, bytes) catch return error.WriteFailed;
}

/// Removes the file or empty directory at `path`, like C's `remove`.
pub fn remove(io: Io, path: []const u8) (Dir.DeleteFileError || Dir.DeleteDirError)!void {
    Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
        error.IsDir => return Dir.cwd().deleteDir(io, path),
        else => |e| return e,
    };
}

/// Size of the file at `path`, read through an open handle like C's
/// `fopen` + `ftell`, so an unreadable file has no length.
pub fn fileLength(io: Io, path: []const u8) error{ OpenFailed, IsDir }!u64 {
    const file, const size = openForReading(io, path) catch |err| return switch (err) {
        error.IsDir => error.IsDir,
        else => error.OpenFailed,
    };
    file.close(io);
    return size;
}

/// Last modification time of `path` in whole seconds since the epoch.
pub fn modTime(io: Io, path: []const u8) ?i64 {
    const stat = Dir.cwd().statFile(io, path, .{}) catch return null;
    return @intCast(@divFloor(stat.mtime.nanoseconds, std.time.ns_per_s));
}

/// raylib's "data as code" export: `data` as a C array named after the file.
/// The caller owns the result.
pub fn dataAsCode(gpa: Allocator, data: []const u8, file_path: []const u8) Allocator.Error![:0]u8 {
    std.debug.assert(data.len > 0);
    const bytes_per_line = 20;

    var name_buf: [max_file_name_len]u8 = undefined;
    const stem = fileStem(file_path);
    const name = name_buf[0..stem.len];
    for (name, stem) |*out, ch| out.* = switch (ch) {
        'a'...'z' => std.ascii.toUpper(ch),
        '.', '-', '?', '!', '+' => '_',
        else => ch,
    };

    var text: Io.Writer.Allocating = try .initCapacity(gpa, data.len * 6 + 2000);
    defer text.deinit();
    const w = &text.writer;
    writeDataAsCode(w, name, data, bytes_per_line) catch return error.OutOfMemory;
    return text.toOwnedSliceSentinel(0);
}

fn writeDataAsCode(w: *Io.Writer, name: []const u8, data: []const u8, bytes_per_line: usize) Io.Writer.Error!void {
    try w.writeAll(
        \\////////////////////////////////////////////////////////////////////////////////////////
        \\//                                                                                    //
        \\// DataAsCode exporter v1.0 - Raw data exported as an array of bytes                  //
        \\//                                                                                    //
        \\// more info and bugs-report:  github.com/raysan5/raylib                              //
        \\// feedback and support:       ray[at]raylib.com                                      //
        \\//                                                                                    //
        \\// Copyright (c) 2022-2026 Ramon Santamaria (@raysan5)                                //
        \\//                                                                                    //
        \\////////////////////////////////////////////////////////////////////////////////////////
        \\
        \\
    );
    try w.print("#define {s}_DATA_SIZE     {d}\n\n", .{ name, data.len });
    try w.print("static unsigned char {s}_DATA[{s}_DATA_SIZE] = {{ ", .{ name, name });
    const last = data.len - 1;
    for (data[0..last], 0..) |byte, i| {
        const sep = if (i % bytes_per_line == 0) ",\n" else ", ";
        try w.print("0x{x}{s}", .{ byte, sep });
    }
    try w.print("0x{x} }};\n", .{data[last]});
}

//------------------------------------------------------------------------------
// Path strings
//------------------------------------------------------------------------------

const separators = "\\/";

/// The extension of `path`, dot included: from the last '.' anywhere in the
/// path, unless that '.' is the first character.
pub fn extension(path: []const u8) ?[]const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse return null;
    if (dot == 0) return null;
    return path[dot..];
}

/// The part of `path` after its last '/' or '\'.
pub fn fileName(path: []const u8) []const u8 {
    const sep = std.mem.lastIndexOfAny(u8, path, separators) orelse return path;
    return path[sep + 1 ..];
}

/// The file name of `path`, cut to `max_file_name_len` bytes, without its
/// extension (a leading '.' is part of the name).
pub fn fileStem(path: []const u8) []const u8 {
    const name = fileName(path);
    const kept = name[0..@min(name.len, max_file_name_len)];
    const dot = std.mem.lastIndexOfScalar(u8, kept, '.') orelse return kept;
    return if (dot == 0) kept else kept[0..dot];
}

/// Whether `path` starts at a root: '/', '\' or a drive letter ("C:").
fn hasRoot(path: []const u8) bool {
    if (path.len > 0 and (path[0] == '/' or path[0] == '\\')) return true;
    return path.len > 1 and path[1] == ':';
}

/// The directory part of `path`, written to `buf` (at least 2 bytes) and cut
/// to fit. A path without a root is made explicitly relative ("a/b" -> "./a");
/// a root alone stays ("/usr" -> "/").
pub fn directoryPath(buf: []u8, path: []const u8) []u8 {
    const prefix = if (hasRoot(path)) "" else "./";
    const end = if (std.mem.lastIndexOfAny(u8, path, separators)) |sep| @max(sep, 1) else 0;
    const dir = path[0..@min(end, buf.len - prefix.len)];
    return std.fmt.bufPrint(buf, "{s}{s}", .{ prefix, dir }) catch unreachable;
}

/// Whether the extension of `path` is in `extensions`, a ';'-separated list
/// such as ".png;.jpg". Case-insensitive; a listed extension may omit its dot.
/// Like raylib, only the first 15 bytes of the extension and the first 32
/// list entries take part.
pub fn hasExtension(path: []const u8, extensions: []const u8) bool {
    const max_extensions = 32;
    const max_extension_len = 15;

    const ext_full = extension(path) orelse return false;
    const ext = ext_full[0..@min(ext_full.len, max_extension_len)];

    var entries = std.mem.splitScalar(u8, extensions, ';');
    var count: usize = 0;
    while (entries.next()) |entry| : (count += 1) {
        if (count == max_extensions) break;
        const candidate = if (std.mem.startsWith(u8, entry, ".")) ext else ext[1..];
        if (std.ascii.eqlIgnoreCase(candidate, entry)) return true;
    }
    return false;
}

/// Whether `name` is usable as a file name on every platform raylib supports.
/// An empty name counts as valid, as in raylib.
pub fn isValidFileName(name: []const u8) bool {
    const reserved = "<>:\"/\\|?*";
    var all_periods = true;
    for (name) |ch| {
        if (ch < 32 or std.mem.indexOfScalar(u8, reserved, ch) != null) return false;
        if (ch != '.') all_periods = false;
    }
    return name.len == 0 or !all_periods;
}

//------------------------------------------------------------------------------
// File system queries
//------------------------------------------------------------------------------

pub fn exists(io: Io, path: []const u8) bool {
    Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

/// Whether `path` is a directory this process can list.
pub fn isDirectory(io: Io, path: []const u8) bool {
    var dir = Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return false;
    dir.close(io);
    return true;
}

/// Whether `path` is a regular file, following symbolic links.
pub fn isFile(io: Io, path: []const u8) bool {
    const stat = Dir.cwd().statFile(io, path, .{}) catch return false;
    return stat.kind == .file;
}

/// Creates `path` and any missing parent directories. Errors are ignored,
/// as in raylib: the caller checks whether the directory exists afterwards.
/// Separators become '/', except one right after a drive letter's ':'.
pub fn makeDirectories(io: Io, path: []const u8) error{NameTooLong}!void {
    if (path.len >= max_path_len) return error.NameTooLong;
    var buf: [max_path_len]u8 = undefined;
    const dir_path = buf[0..path.len];
    @memcpy(dir_path, path);

    var i: usize = 0;
    while (i < dir_path.len) : (i += 1) {
        switch (dir_path[i]) {
            ':' => i += 1,
            '/', '\\' => {
                makeDirectory(io, dir_path[0..i]);
                dir_path[i] = '/';
            },
            else => {},
        }
    }
    makeDirectory(io, dir_path);
}

fn makeDirectory(io: Io, path: []const u8) void {
    if (path.len == 0 or isDirectory(io, path)) return;
    Dir.cwd().createDir(io, path, .default_dir) catch {};
}

//------------------------------------------------------------------------------
// Directory scans
//------------------------------------------------------------------------------

/// Which entries a directory scan reports, parsed from raylib's filter string.
pub const Filter = struct {
    /// Every regular file.
    all_files: bool,
    /// Every entry that is not a regular file (directories, mostly).
    dirs: bool,
    /// ';'-separated extensions; matching regular files are reported.
    extensions: []const u8,

    /// The tags are raylib's FILE_FILTER_TAG_ALL, _FILE_ONLY and _DIR_ONLY.
    /// No filter at all means every regular file.
    pub fn parse(filter: ?[]const u8) Filter {
        const text = filter orelse return .{ .all_files = true, .dirs = false, .extensions = "" };
        const all = std.mem.indexOf(u8, text, "*.*") != null;
        return .{
            .all_files = all or std.mem.indexOf(u8, text, "FILES*") != null,
            .dirs = all or std.mem.indexOf(u8, text, "DIRS*") != null,
            .extensions = text,
        };
    }

    fn matchesFile(filter: Filter, path: []const u8) bool {
        return filter.all_files or hasExtension(path, filter.extensions);
    }
};

/// A path a scan skipped, and why. The scan goes on after reporting it.
pub const Skipped = union(enum) {
    /// The directory could not be opened.
    cannot_open: [:0]const u8,
    /// An entry of this directory has a path of `max_path_len` bytes or more.
    path_too_long: [:0]const u8,
};

/// A depth-first scan of a directory tree, in the order the OS lists entries.
pub const Scan = struct {
    io: Io,
    filter: Filter,
    recursive: bool,
    on_skip: *const fn (Skipped) void,

    /// Calls `visitor.visit(path)` for every entry the filter accepts, while
    /// `visitor.full()` is false. `path` is "base/name" and valid only during
    /// the call.
    pub fn walk(scan: Scan, base: [:0]const u8, visitor: anytype) @TypeOf(visitor.*).Error!void {
        var dir = Dir.cwd().openDir(scan.io, base, .{ .iterate = true }) catch {
            scan.on_skip(.{ .cannot_open = base });
            return;
        };
        defer dir.close(scan.io);

        var buf: [max_path_len]u8 = undefined;
        var entries = dir.iterateAssumeFirstIteration();
        while (!visitor.full()) {
            // A failed read ends the listing, as readdir() returning NULL does.
            const entry = (entries.next(scan.io) catch null) orelse break;
            const printed = std.fmt.bufPrint(&buf, "{s}/{s}\x00", .{ base, entry.name }) catch {
                scan.on_skip(.{ .path_too_long = base });
                continue;
            };
            const path = printed[0 .. printed.len - 1 :0];
            if (isFile(scan.io, path)) {
                if (scan.filter.matchesFile(path)) try visitor.visit(path);
            } else {
                if (scan.filter.dirs) try visitor.visit(path);
                if (scan.recursive) try scan.walk(path, visitor);
            }
        }
    }

    /// Number of entries `walk` would visit.
    pub fn count(scan: Scan, base: [:0]const u8) u32 {
        var counter: Counter = .{};
        scan.walk(base, &counter) catch |err| switch (err) {};
        return counter.n;
    }

    const Counter = struct {
        n: u32 = 0,
        const Error = error{};
        fn full(_: *const Counter) bool {
            return false;
        }
        fn visit(c: *Counter, _: [:0]const u8) Error!void {
            c.n += 1;
        }
    };
};

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const testing = std.testing;

test extension {
    try testing.expectEqualStrings(".c", extension("a.b.c").?);
    try testing.expectEqualStrings(".d/file", extension("dir.d/file").?);
    try testing.expectEqual(null, extension(".hidden"));
    try testing.expectEqual(null, extension("noext"));
}

test fileName {
    try testing.expectEqualStrings("c.txt", fileName("a/b/c.txt"));
    try testing.expectEqualStrings("b.txt", fileName("a\\b.txt"));
    try testing.expectEqualStrings("", fileName("a/"));
    try testing.expectEqualStrings("plain", fileName("plain"));
}

test fileStem {
    try testing.expectEqualStrings("a.b", fileStem("x/a.b.c"));
    try testing.expectEqualStrings(".hidden", fileStem(".hidden"));
    try testing.expectEqualStrings("file", fileStem("dir.d/file"));
    const long: [300]u8 = @splat('n');
    try testing.expectEqual(max_file_name_len, fileStem(&long ++ ".txt").len);
}

test directoryPath {
    var buf: [max_path_len]u8 = undefined;
    const cases = [_][2][]const u8{
        .{ "", "./" },        .{ "/", "/" },                        .{ "/usr", "/" },
        .{ "/usr/", "/usr" }, .{ "a", "./" },                       .{ "a/b/c", "./a/b" },
        .{ "C:\\", "C:" },    .{ "C:\\raylib\\src", "C:\\raylib" }, .{ "\\\\server\\share", "\\\\server" },
    };
    for (cases) |case| try testing.expectEqualStrings(case[1], directoryPath(&buf, case[0]));
}

test hasExtension {
    try testing.expect(hasExtension("a.PNG", ".png"));
    try testing.expect(hasExtension("a.png", "png"));
    try testing.expect(hasExtension("a.jpg", ".png;jpg;.bmp"));
    try testing.expect(hasExtension("a.png", ".png;"));
    try testing.expect(!hasExtension("a.png", ""));
    try testing.expect(!hasExtension("a.png", ";"));
    try testing.expect(!hasExtension("a.tar.gz", ".tar.gz"));
    try testing.expect(!hasExtension(".bashrc", ".bashrc"));
    // Extensions are compared on their first 15 bytes only.
    try testing.expect(hasExtension("a.verylongexten", ".verylongexten"));
    try testing.expect(!hasExtension("a.verylongextension_x", ".verylongextension_x"));
}

test isValidFileName {
    try testing.expect(isValidFileName("ok.txt"));
    try testing.expect(isValidFileName(""));
    try testing.expect(isValidFileName(".a"));
    try testing.expect(!isValidFileName("a:b"));
    try testing.expect(!isValidFileName("\x01x"));
    try testing.expect(!isValidFileName(".."));
}

test Filter {
    const none: Filter = .parse(null);
    try testing.expect(none.all_files and !none.dirs);
    const dirs: Filter = .parse("DIRS*");
    try testing.expect(!dirs.all_files and dirs.dirs);
    const ext: Filter = .parse(".png;.txt");
    try testing.expect(ext.matchesFile("x/a.TXT") and !ext.matchesFile("x/a.h"));
}

test dataAsCode {
    const text = try dataAsCode(testing.allocator, &.{ 0x0b, 0x30, 0xff }, "dir/my-data.v1.h");
    defer testing.allocator.free(text);
    // From the header's last line on: the blank line count matters, raylib's output is byte-exact.
    try testing.expect(std.mem.endsWith(u8, text,
        \\////////////////////////////////////////////////////////////////////////////////////////
        \\
        \\#define MY_DATA_V1_DATA_SIZE     3
        \\
        \\static unsigned char MY_DATA_V1_DATA[MY_DATA_V1_DATA_SIZE] = { 0xb,
        \\0x30, 0xff };
        \\
    ));
}

test "files and directories" {
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // The functions take paths relative to the working directory, like raylib's.
    var cwd_buf: [max_path_len]u8 = undefined;
    const old_cwd = cwd_buf[0..try std.process.currentPath(io, &cwd_buf)];
    try std.process.setCurrentDir(io, tmp.dir);
    defer std.process.setCurrentPath(io, old_cwd) catch {};

    try saveFile(io, "a.bin", "hello");
    try testing.expectEqual(5, try fileLength(io, "a.bin"));
    try testing.expectError(error.IsDir, fileLength(io, "."));
    try testing.expectError(error.OpenFailed, saveFile(io, "missing/a.bin", "x"));
    try saveFile(io, "gone", "x");
    try remove(io, "gone");
    try testing.expect(!exists(io, "gone"));

    const contents = try loadFile(io, testing.allocator, "a.bin");
    defer testing.allocator.free(contents.data);
    try testing.expectEqualStrings("hello", contents.data[0..contents.read]);

    const text = try loadText(io, testing.allocator, "a.bin");
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("hello", text);

    try saveFile(io, "empty", "");
    try testing.expectError(error.Empty, loadFile(io, testing.allocator, "empty"));
    try testing.expectError(error.OpenFailed, loadText(io, testing.allocator, "missing"));

    try makeDirectories(io, "x\\y/z");
    try testing.expect(isDirectory(io, "x/y/z"));
    try testing.expect(!isFile(io, "x/y"));
    try saveFile(io, "x/y/z/b.png", "");
    try saveFile(io, "x/c.txt", "");

    const scan: Scan = .{ .io = io, .filter = .parse(".png;.txt"), .recursive = true, .on_skip = ignoreSkip };
    try testing.expectEqual(2, scan.count("x"));
    const flat: Scan = .{ .io = io, .filter = .parse("DIRS*"), .recursive = false, .on_skip = ignoreSkip };
    try testing.expectEqual(1, flat.count("x"));
    try testing.expectEqual(0, flat.count("missing"));
}

fn ignoreSkip(_: Skipped) void {}
