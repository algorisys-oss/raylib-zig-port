# handoff.md — fresh-session bootstrap (written 2026-10-16 22:30 IST)

> Overwritten at the end of every run (CLAUDE.md). PROGRESS.md holds history.

## 1. State right now

- **Round 2 (idiomatic Zig internals) is complete**, merged on `main` and
  **pushed** (origin/main 36137d1 + this handoff, 2026-10-16 22:45). Worktrees and the
  `idiom/*` branches are removed (all merged).
- idiomaudit: libc externs / calls / `[*c]` = **6 / 9 / 1517** (start of day
  90 / 978 / 2136). Remaining C is documented: vprintf/vsnprintf (C printf
  formats), snprintf for float output, fflush, src/cmem.zig (C heap boundary).
- Gates on main (all measured after the last merge): examples **217/217**
  Debug and ReleaseFast · apiexamples 217/217 · cdiff **12/12** Debug and
  ReleaseFast · pixel 12/12 · audio 43/43 · math 93,000 / cam / gest
  bit-exact · apitest · datacheck · constaudit 0 · idiomaudit OK · browser
  46/46 · raylib-zig-web site e2e 46/46 (public/examples rebuilt locally).

## 2. What this run did

- Review "C with Zig keywords" accepted; reply drafted for the reviewer.
- rcore (+ both platform backends) rewritten by hand: fs.zig, automation.zig,
  cmem.zig, std hashes/base64/CRC; OpenURL without a shell.
- rtext, rtextures, rmodels, raudio, rlgl rewritten by 5 agents in worktrees
  from one brief; merged and re-verified serially. New std-only helpers with
  tests: cscan, rtext_strings, rtext_bmfont, rtextures_encode, rmodels_iqm,
  raudio_wave, rlgl_buffers.
- 8 new cdiff programs; 14 port bugs fixed (list in PROGRESS.md).
- Found: gates could compare two libms (compiler_rt vs glibc) depending on
  optimization level; now pinned (build.zig pinCompilerRtMath, exdiff.sh).
- Found upstream: raylib 6.2 multi-page BMFont use-after-free.
- docs/idioms.md (13 lessons), docs/compatibility.md, CLAUDE.md gotchas.

## 3. Next step on resume

1. Owner: send the reviewer reply (docs/migration-status.md, appendix) and
   decide whether to report the BMFont use-after-free upstream.
2. Phase W (web) resume list: textures, then text in `web_examples`; GLSL
   version constant then shaders; per-example .data; example manifest;
   Asyncify vs frame callback.
3. Optional: idiomaudit `[*c]` count is dominated by export signatures and
   the generated src/api/c*.zig bindings; nothing actionable there.

## 4. Open issues / gotchas

- Allocation-failure paths now log warnings raylib has no wording for
  (rmodels/rtextures); documented in compatibility.md §5.
- New gate executables must go through `linkExe` (or pass -u __multi3).
- Concurrent builds: private `--cache-dir` (webcache/relcache were used).
