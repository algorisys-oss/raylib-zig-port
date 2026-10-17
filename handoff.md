# handoff.md — fresh-session bootstrap (written 2026-10-16 22:30 IST; state updated 2026-10-17 08:00 from the raylib-zig-web session)

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
- Later (5cd8ae2, from the raylib-zig-web session): browser gate **78/78**
  Debug and ReleaseFast (+32 textures; textures_to_image excluded, docs/web.md);
  rmodels par_shapes extern fixed to f32; web links use -Wl,--fatal-warnings.
- Later (a3623f9, raylib-zig-web session): browser gate **159/159** Debug and
  ReleaseFast (+text 17, shaders 32/36, models 32; 5 exclusions in docs/web.md).
  New: examples/zig/common/platform.zig (glsl_version), test/web_resources.list
  + `zig build webresources` (per-example .data, proven by the gate),
  gate frames in zig-out/web/frames, `tools/gen_api.py --json` ->
  src/api/api.json, builds as a dependency (rlgl_impl_defs.h include fix).
  Desktop re-run after it: pixel 12/12, apiexamples 217/217, exdiff 217/217.
- Later still (raylib-zig-web session, 2026-10-17 08:50): core in the browser
  gate, **202** examples (core 44/46; core_window_web excluded; Debug and
  ReleaseFast run on the core subset, the other 158 unchanged since their
  159/159 run). Web example C shims are linked (core_screen_recording).
- Open, owner's call: **LoadDirectoryFiles lists nothing on the web.** Zig
  std's dirRead for emscripten is `dirReadUnimplemented`; src/fs.zig uses
  std.Io.Dir. Fix = libc readdir on the web (a libc extern, idiomaudit counts
  it) or wait for std. core_directory_files is excluded until then.
- Open: `python3 tools/gen_api.py` (full regen) no longer reproduces the
  checked-in src/api/raylib.zig (zig fmt quoting, @fromBackingInt vs
  @enumFromInt in a few wrappers). Do not regenerate until the generator is
  brought in line; `--json` reads the checked-in file and is safe.
- Open: core_basic_window web wasm is 258,589 bytes at ReleaseFast (docs/web.md
  measured 107,469 before round 2); not investigated.

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
2. Phase W (web) resume list: rest of core, audio, others in `web_examples`
   (text, shaders, models done; after adding, run `zig build webresources`);
   example manifest; Asyncify vs frame callback; the wasm size growth.
3. Optional: idiomaudit `[*c]` count is dominated by export signatures and
   the generated src/api/c*.zig bindings; nothing actionable there.

## 4. Open issues / gotchas

- Allocation-failure paths now log warnings raylib has no wording for
  (rmodels/rtextures); documented in compatibility.md §5.
- New gate executables must go through `linkExe` (or pass -u __multi3).
- Concurrent builds: private `--cache-dir` (webcache/relcache were used).
