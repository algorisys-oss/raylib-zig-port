# handoff.md — fresh-session bootstrap (written 2026-10-16 19:56 IST)

> Overwritten at the end of every run (CLAUDE.md). PROGRESS.md holds history.

## 1. State right now

- All gates green after round 2.1: pixel 12/12 · exdiff **217/217** · cdiff
  **5/5** (Debug + ReleaseFast) · audio 43/43 · datacheck · math/cam/gest ·
  apitest · constaudit 0 · idiomaudit OK · browser gate **46/46**.
- Committed locally at the end of this run (see git log); **not pushed**
  (pushing needs the owner's go-ahead). origin/main had no new commits at 19:50.
- Two workstreams are live: **Round 2 idiomatic internals** (this run; plan in
  IMPLEMENT-idiomatic-zig.md) and **Phase W web target** (driven from the
  raylib-zig-web session; resume list in §3b).

## 2. What this run did

- Review feedback ("C with Zig keywords") accepted; reply drafted for the reviewer.
- `tools/idiomaudit.py` + baseline: ratchet on libc externs / calls / `[*c]`
  (HEAD e73f1c0: 90 / 978 / 2136 → now 70 / 875 / 2101).
- `test/cdiff/core_fileio.c`: C-vs-Zig file I/O differential (real file tree,
  every TraceLog line); green before and after the rewrite.
- `src/fs.zig` (std-only, 9 leak-checked tests) + rcore.zig file system
  section rewritten as thin `export fn` wrappers.
- docs/idioms.md (lessons), docs/compatibility.md (§3 cdiff 5/5, §5 file
  system misuse cases), CLAUDE.md gotcha, CHANGELOG.md, PROGRESS.md.

## 3. Next step on resume

1. Check the raylib-zig-web pushes the owner mentioned (2026-10-16 ~19:45):
   pull there, run its sync (`npm run sync`) against this repo, confirm nothing
   in `zig build webdemos` / the site broke.
2. Round 2.1b: rcore automation events file (LoadAutomationEventList /
   ExportAutomationEventList) into fs.zig-style code. Write a cdiff driver
   first; C's loop has fgets 255-byte chunking, a last line without '\n' that
   is never processed, an "Issue reading line" warning at EOF, and `%i`
   (accepts 0x hex and leading-0 octal). Then delete FILE/fopen/fgets/feof/sscanf.
3. Round 2.2+: rtext, rtextures, rmodels, raudio, rlgl — same pattern
   (cdiff first, std-only file, thin wrappers, `idiomaudit.py --update`).

### 3b. Phase W (web) resume list, unchanged

1. Grow `web_examples` in build.zig category by category (textures next, then text).
2. GLSL version as one comptime constant for the web, then shaders.
3. Per-example .data with only the files an example loads.
4. Example manifest for the site (phase W step 7).
5. Measure Asyncify vs a frame callback.

## 4. Open issues / gotchas hit

- The browser gate does not yet exercise file I/O on the web (no gated web
  example loads files): fs.zig on emscripten is proven to compile and link,
  not to run. The textures category (step 3b.1) will exercise it.
- `std.Io` in a C-ABI library: wrappers use
  `std.Io.Threaded.global_single_threaded.io()`; fs.zig takes `io` as a parameter.
- Zig 0.18: `**` array repetition is gone (`@splat`); a multiline `\\` literal's
  last line has no trailing newline; cross-file `anytype` visitors need `pub` decls.
- Run concurrent builds with a private `--cache-dir` (used for web + ReleaseFast here).
