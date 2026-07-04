# handoff.md — fresh-session bootstrap (written 2026-07-04, end of session)

> Per CLAUDE.md this file is overwritten at the end of every run. PROGRESS.md
> holds the long-lived history; this is only "what a new session needs".

## 1. State right now

- 🏁 **100% of raylib-authored code is Zig — all 10 modules ported, gated,
  tagged** (`rmodels-ported`, `raudio-ported`). Remaining C in the swapped
  build = bundled third-party only (rglfw.c + src/c/ shims), per charter.
- **Examples acceptance suite: first batch 135/135 byte-identical** — every
  core/shapes/text/textures upstream example, unmodified, C-vs-Zig pixel diff
  (2 excluded with reasons in test/examples.list). Run:
  `zig build && tools/exdiff.sh <oracle.a> zig-out/lib/libraylib.a [filter]`
  (oracle .a path: `find .zig-cache -name libraylib_oracle.a -newer build.zig`).
- Other gates all green: `zig build test` 12/12, `zig build audiocheck` 43/43,
  datacheck, mathtest/camgrid/gestgrid. Capstone: `zig build angrybirds`
  (docs: examples/angrybirds/README.md).
- Repo clean, pushed to origin (github.com/algorisys-oss/raylib-zig-port).

## 2. What this run did (2026-07-04, ~2.5 h + 3 background agents/sweeps)

- rmodels: fixed DrawSphereEx result-location aliasing → 12/12 → tagged.
- raudio: agent-drafted (2287 lines, 78 exports + shim), fixed the
  callback-before-cache device-start bug the audiocheck gate caught → 43/43 →
  tagged. audiocheck harness built this session (43 checks, PCM hashes).
- Angry Birds capstone shipped (examples/angrybirds/, selftest verified).
- Examples gate (exdiff) built and first batch landed 135/135 after fixing
  3 real port bugs (rtext null-glyph atlas panic, rtextures GetPixelColor
  eager @alignCast, rtext MeasureTextEx fractional-spacing truncation) and
  2 oracle-build issues (-ffp-contract=off everywhere; UBSan off for the
  oracle lib only). All post-mortems recorded as CLAUDE.md gotchas.
- README refreshed (was "planning only"); angrybirds run docs added.

## 3. Next step on resume

**Extend exdiff to the remaining upstream example categories** (~81 examples):
add `models/`, `shaders/`, `audio/`, `others/` to test/examples.list, sweep,
triage failures by root cause (process proven — see PROGRESS.md "NEXT"
section for per-category expectations). 218-example bar = suite complete.

Then (non-blocking): ReleaseFast archive workaround; Phase-6 idiomatic API.

## 4. Open issues / gotchas hit this run

- **Audio device flake:** if audiocheck warns the device section was skipped,
  the desktop default sink is HDMI (spec miniaudio can't map). Prefix with
  `PULSE_SINK=alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__hw_sofhdadsp__sink`.
- exdiff examples run with an LD_PRELOAD clock freezer (tools/exdiff/
  fakeclock.c) — library-internal time is frozen; example-side time comes from
  the shim's fixed 60 Hz clock. Don't "fix" one by removing the other.
- The C oracle now builds WITHOUT UBSan and with -ffp-contract=off — both
  deliberate (see build.zig comments); don't revert while diffing.
- `zig build test/audiocheck` rebuild both libs; after build.zig changes the
  oracle .a path in .zig-cache changes — locate with `-newer build.zig`.
