# Changelog

## [2026-10-16 19:50]
- rcore file system functions rewritten as idiomatic Zig: new `src/fs.zig`
  (std-only: slices, error unions, `std.Io`, `Allocator`, leak-checked tests);
  rcore.zig keeps thin `export fn` wrappers. 20 libc externs, 103 libc calls
  and 35 `[*c]` removed from rcore.zig. Behaviour unchanged (cdiff, pixel,
  examples gates).
- New gate `test/cdiff/core_fileio.c` (C-vs-Zig file I/O differential) and
  ratchet lint `tools/idiomaudit.py` + `tools/idiomaudit.baseline.json`.
- Docs: docs/idioms.md (before/after lessons), docs/compatibility.md (cdiff 5/5,
  file system misuse cases), IMPLEMENT-idiomatic-zig.md (plan and contract).
- Files: src/fs.zig, src/rcore.zig, build.zig, test/cdiff/core_fileio.c,
  tools/idiomaudit.py, tools/idiomaudit.baseline.json, CLAUDE.md.
