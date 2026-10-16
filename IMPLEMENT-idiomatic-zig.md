# IMPLEMENT — idiomatic Zig internals (round 2)

## Why

External review (2026-10-16): the ported modules are "C written with Zig
keywords" — ~950 direct libc calls (`strcmp`, `memcpy`, `snprintf`, `fopen`…),
no `Allocator`, almost no `defer`. True, and it breaks our own CLAUDE.md rule:
C shapes belong only at the ABI edge. The pixel/numeric gates proved behaviour,
nothing enforced idiom. This round fixes the internals, module by module, with
the existing C-vs-Zig gates as the safety net.

## Decisions

- **Split edge from internals.** Each area gets a std-only Zig file with
  idiomatic APIs (slices, error unions, `std.Io`, `Allocator`, `defer`) and its
  own `test` blocks. The module (`rcore.zig`, …) keeps only thin `export fn`
  shims: C strings → slices, errors → raylib's exact TraceLog messages.
- **`std.Io` at the edge.** std's guidance is that library code takes an `io`
  parameter. The internals do; the C ABI has no caller to supply one, so the
  shims pass `std.Io.Threaded.global_single_threaded.io()`.
- **Allocator at the edge.** Internals take `gpa: Allocator`. The shims pass
  `std.heap.c_allocator`, which for alignment <= max_align_t is plain `malloc`,
  so C callers can still release results with `free()`/`MemFree`/`UnloadFileData`.
- **Behaviour is the spec.** Same return values, same files on disk, same
  directory order, same TraceLog text and level as raylib 6.2.

## Lint

`tools/idiomaudit.py` counts, per `src/**/*.zig`: libc `extern fn`
declarations, libc call sites, and `[*c]` pointer types. A checked-in baseline
(`tools/idiomaudit.baseline.json`) may only go down; `--update` lowers it.

## Round 2.1 — rcore file system (contract)

Scope: rcore.zig "File System management" section (LoadFileData …
ScanDirectoryFiles, ~670 lines). New file `src/fs.zig`.

Done when ALL hold:

1. `test/cdiff/core_fileio.c` exists, exercises every function in scope (incl.
   error paths and every TraceLog line via a log callback), and passes C == Zig
   **before** the rewrite (proves the harness) and **after** it.
2. `src/fs.zig` uses no libc externs, no `[*c]`, no `std.c`; its tests pass
   under `std.testing.allocator` (leak-checked).
3. rcore's file-system section has no `fopen/fread/fwrite/fprintf/fseek/ftell/
   fclose/opendir/readdir/closedir/access/stat/mkdir/getcwd/chdir/readlink/
   rename/remove/strcmp/strstr/strlen/strncpy/strrchr/strpbrk/memcpy/memset/
   snprintf/sprintf` calls; their now-unused extern decls are deleted.
4. Gates green: `zig build cdiff` (5/5), `zig build test` (12/12),
   `zig build apitest`, `python3 tools/constaudit.py`, `tools/exdiff.sh`
   full run, and the web build still links (`zig build web`).
5. idiomaudit baseline lowered and committed.
6. `docs/idioms.md` has the before/after lessons from this round.

## Status

- [x] 2.1 rcore file system (fs.zig) — 2026-10-16
- [x] 2.1b rcore automation events (automation.zig) and the rest of rcore,
      platform backends, cmem.zig — 2026-10-16
- [x] 2.2 rtext · 2.3 rtextures · 2.4 rmodels · 2.5 raudio · 2.6 rlgl —
      2026-10-16, one agent per module in its own worktree (shared brief),
      merged and re-verified serially on main
- Result: idiomaudit 90/978/2136 → 6/9/1517; all gates green (PROGRESS.md)
