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

## [2026-10-16 22:20]
- Round 2 complete: every module idiomatic Zig behind the unchanged C ABI
  (rcore + backends, rlgl, raudio, rtextures, rtext, rmodels). libc externs
  90 -> 6, libc calls 978 -> 9 (all documented). New std-only helper files
  with tests; cdiff programs 4 -> 12; 14 port bugs fixed.
- Gates now pin compiler_rt's libm on both sides (build.zig
  pinCompilerRtMath, exdiff.sh -u __multi3); math grid covers cubic Hermite.
- Files: src/*.zig, src/platforms/*.zig, test/cdiff/*.c, test/mathgrid.*,
  build.zig, tools/exdiff.sh, tools/idiomaudit.*, docs/*, CLAUDE.md.
