# C idioms → Zig idioms

Lessons from rewriting the ported modules so they read as Zig, not as C with
Zig keywords. Each section shows what the first-pass port did, what replaced
it, and why. The examples come from rcore's file system code (round 2.1, see
IMPLEMENT-idiomatic-zig.md): `src/fs.zig` and the wrappers in `src/rcore.zig`.

The rule behind all of them: **C shapes belong only at the ABI edge.** raylib's
public API must stay C (`export fn`, `[*c]u8`, `extern struct`), so the edge
keeps them. Everything behind the edge is ordinary Zig.

## 1. Split the edge from the logic

Before: one 670-line block of `export fn`s, each doing C-string handling,
libc calls, error logging and the actual work.

After: two layers.

```zig
// rcore.zig: the edge. C types in, C types out, nothing else.
export fn FileExists(fileName: [*c]const u8) callconv(.c) bool {
    const path = cSpan(fileName) orelse return false;
    return fs.exists(io(), path);
}

// fs.zig: the logic. Slices, error unions, no C types, unit-tested.
pub fn exists(io: Io, path: []const u8) bool {
    Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}
```

`fs.zig` imports nothing but `std`. That's what makes it testable with
`zig test src/fs.zig`, with no window, no GL and no C library.

## 2. `FILE *` → `std.Io` and `defer`

Before:

```zig
const file = fopen(fileName, "rb");
if (file != null) {
    _ = fseek(file, 0, SEEK_END);
    const size = ftell(file);
    _ = fseek(file, 0, SEEK_SET);
    ...
    _ = fclose(file);
} else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to open file", fileName);
```

After:

```zig
const file = Dir.cwd().openFile(io, path, .{ .allow_directory = false }) catch |err| return switch (err) {
    error.IsDir => error.IsDir,
    else => error.OpenFailed,
};
errdefer file.close(io);
const stat = file.stat(io) catch return error.OpenFailed;
```

`errdefer` closes the file on every error path; on success the caller owns
it and closes it with `defer file.close(io)` right after the call. The size
comes from `stat` instead of seeking to the end and back. Failure is an error
value the caller has to handle, not a null to remember to check.

Zig 0.18's file API takes an `io: std.Io` on every call. Library code should
take that `Io` from its caller, and `fs.zig` does. raylib's C API has no
parameter to carry one, so the edge supplies std's process-wide instance:

```zig
fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}
```

That is the one place the "caller chooses the `Io`" rule bends, and only
because the caller is C.

## 3. Sentinel returns → error unions; logging at the edge

Before, failures were `null`/`-1`/`false` with a `TraceLog` buried in each branch.
After, `fs.loadFile` returns `LoadError!Contents` and the edge maps each error
to raylib's exact message in one exhaustive `switch`:

```zig
const contents = fs.loadFile(io(), c_allocator, path) catch |err| {
    switch (err) {
        error.OpenFailed => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to open file", fileName),
        error.Empty => TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to read file", fileName),
        ...
    }
    return null;
};
```

The `switch` is exhaustive, so adding an error to `LoadError` is a compile
error at every edge that forgot to handle it.

## 4. `RL_CALLOC`/`free` → an `Allocator` parameter

Before: `RL_CALLOC(size, 1)` everywhere, no way to test for leaks.

After: anything in `fs.zig` that allocates takes `gpa: Allocator`.
- Tests pass `std.testing.allocator`, which fails the test on any leak or
  double free.
- The edge passes `std.heap.c_allocator`. For ordinary alignments that is
  `malloc`, so C callers can still release results with `free()`, `MemFree`
  or `UnloadFileData`, as the raylib API promises.

```zig
pub fn loadText(io: Io, gpa: Allocator, path: []const u8) LoadError![:0]u8 {
    ...
    var text = try gpa.alloc(u8, size + 1);
    const read = file.readPositionalAll(io, text[0..size], 0) catch 0;
    if (read < size) text = try gpa.realloc(text, read + 1);
    text[read] = 0;
    return text[0..read :0];
}
```

The return type `[:0]u8` says "NUL-terminated" in the type. C only says it in
a comment.

## 5. `string.h` → `std.mem` on slices

| C (first pass)                                      | Zig                                          |
|-----------------------------------------------------|----------------------------------------------|
| `strcmp(&dp.name, ".") != 0`                        | (std's directory iterator skips `.` and `..`) |
| `strstr(filter, "*.*") != null`                     | `std.mem.indexOf(u8, text, "*.*") != null`   |
| `strrchr(fileName, '.')`                            | `std.mem.lastIndexOfScalar(u8, path, '.')`   |
| `strprbrk(path, "\\/")` (a hand-written helper)     | `std.mem.lastIndexOfAny(u8, path, "\\/")`    |
| `strcmp` after lower-casing into a 16-byte buffer   | `std.ascii.eqlIgnoreCase(a, b)`              |
| a `';'`-splitting loop that writes NULs into a copy | `std.mem.splitScalar(u8, list, ';')`         |
| `memcpy(dst, src, n)`                               | `@memcpy(dst[0..n], src)` (length-checked)   |

Slices carry their length, so there's no `strlen` and no buffer walk.
`IsFileExtension` dropped its heap copy entirely: splitting a slice doesn't
need to write NULs into it.

## 6. `snprintf` + length check → `std.fmt.bufPrint`

Before:

```zig
const pathLength = snprintf(&path, MAX_FILEPATH_LENGTH, "%s/%s", basePath, &dp.name);
if ((pathLength < 0) or (pathLength >= MAX_FILEPATH_LENGTH)) { ...too long... }
```

After:

```zig
const printed = std.fmt.bufPrint(&buf, "{s}/{s}\x00", .{ base, entry.name }) catch {
    scan.on_skip(.{ .path_too_long = base });
    continue;
};
const path = printed[0 .. printed.len - 1 :0];
```

Overflow is `error.NoSpaceLeft`, not a return value to compare. Formatting the
`\x00` into the buffer gives a `[:0]const u8` that can go straight to C.

## 7. Two copy-pasted walkers → one walk and a visitor

Before: `GetDirectoryFileCountEx` and `ScanDirectoryFiles` were the same
30-line recursive `opendir`/`readdir` loop twice. One counted, the other
copied paths.

After: one `Scan.walk` that takes any visitor with `full()` and `visit(path)`
(duck typing through `anytype`, checked at compile time):

```zig
pub fn count(scan: Scan, base: [:0]const u8) u32 {
    var counter: Counter = .{};
    scan.walk(base, &counter) catch |err| switch (err) {};
    return counter.n;
}
```

The `Counter`'s error set is empty, so `catch |err| switch (err) {}` proves at
compile time that counting can't fail. rcore passes a different visitor
(`PathListFiller`) that copies paths into raylib's `FilePathList`. One gotcha:
a visitor declared in another file needs its `Error`, `full` and `visit` to
be `pub`.

## 8. `sprintf` into a hand-sized buffer → `Io.Writer.Allocating`

Before: `RL_CALLOC(dataSize*6 + 2000, 1)` (a size guess), then
`byteCount += sprintf(txtData + byteCount, ...)` 14 times.

After: an allocating writer, a multiline string literal for the fixed
header, and `print`:

```zig
var text: Io.Writer.Allocating = try .initCapacity(gpa, data.len * 6 + 2000);
defer text.deinit();
try w.writeAll(
    \\////////////////////
    \\
    \\
);
try w.print("#define {s}_DATA_SIZE     {d}\n\n", .{ name, data.len });
```

The buffer grows if the guess is wrong. Watch the multiline literal: its
**last line has no trailing newline**. Each `\\` line ends in `\n` except the
final one. The first draft had one `\\` line too many, and the C-vs-Zig
differential caught the extra blank line.

## 9. Keep the quirks, but name them

The port must behave like raylib 6.2, including its odd corners. A
transliteration hides those inside C-shaped code. Idiomatic code puts them in
one place at the edge, with a comment saying they're deliberate:

```zig
// raylib's result says only whether the destination directory exists or
// could be made: a missing source or a failed write still returns 0
const result = if (DirectoryExists(dstDir)) 0 else MakeDirectory(dstDir);
```

```zig
// Unlike GetDirectoryFileCountEx, an empty filter here means no filter
const effectiveFilter: [*c]const u8 = if (filter != null and filter[0] == 0) null else filter;
```

`test/cdiff/core_fileio.c` pins every one of these against the C library.

## How this stays true

- `python3 tools/idiomaudit.py` counts libc externs, libc calls and `[*c]`
  per file against `tools/idiomaudit.baseline.json`. Counts may only go down.
- The C-vs-Zig gates (`zig build cdiff`, `zig build test`, `tools/exdiff.sh`)
  prove each rewrite left behaviour byte-identical.
