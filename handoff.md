# handoff.md — fresh-session bootstrap (written 2026-07-04, end of session)

> Per CLAUDE.md this file is overwritten at the end of every run. PROGRESS.md
> holds the long-lived history; this is only "what a new session needs".

## 1. State right now

- 🏁 **100% of raylib-authored code is Zig — all 10 modules ported and gated.**
  Last commit: `raudio ported: 10/10 modules` (tag `raudio-ported`); repo clean
  except this docs pass. Remaining C in the swapped build = bundled third-party
  only (rglfw.c, src/c/ shims), per charter.
- Gates, all green and re-runnable: `zig build test` (pixel, 12/12),
  `zig build audiocheck` (43/43), `zig build datacheck`, `zig build mathtest`/
  camera/gestures grids. Capstone: `zig build angrybirds` (headless selftest via
  `ANGRYBIRDS_SELFTEST=1`).
- Tags: phase0-oracle-ready, phase1-raymath, r{camera,gestures,shapes,text,
  textures,lgl,core,models,audio}-ported.

## 2. What this run did (2026-07-04, ~55 min + 2 background agents)

- Fixed rmodels' DrawSphereEx (result-location aliasing), integrated → 12/12 →
  tag `rmodels-ported`.
- Built the raudio differential gate (test/audiocheck.c + tools/audiodiff.sh,
  43 checks: PCM hashes for WAV/OGG/MP3/QOA, wave ops, exports, music
  metadata+seek, stream state).
- Agent-drafted src/raudio.zig (2287 lines, 78 exports) + src/c/raudio_impl.c
  (miniaudio/decoder shim); fixed the gate-caught callback-before-cache bug
  (device data callback fires during ma_device_start, before the draft cached
  format/channels → memset(0 bytes) → NaN audio). All gates green → tag
  `raudio-ported`.
- Agent-built the Angry Birds capstone (examples/angrybirds/, 759 lines,
  selftest + screenshot verified).
- CLAUDE.md: added this handoff.md convention (user request) + 2 new gotchas
  (result-location aliasing; callback-before-cache). tokens.txt updated.

## 3. Next step on resume

**Wire the 218-example acceptance suite** — the last "done" criterion in
CLAUDE.md. First action: build a runner that compiles upstream
`examples/core/*.c` against BOTH libs and pixel-diffs N deterministic frames
under llvmpipe (pattern: tools/scenediff.sh). Start with the static no-input
examples (~40), expand per category; log unautomatable ones in
docs/not-migrated.md. Details in PROGRESS.md "Resume point".

Then (non-blocking): ReleaseFast archive failure workaround; Phase-6 idiomatic
Zig API layer.

## 4. Open issues / gotchas hit this run

- **Audio device flake on this machine:** when the desktop's default sink is an
  HDMI output, miniaudio can't map its sample spec and `InitAudioDevice` fails
  in BOTH builds → audiocheck's device section (16/43 checks) is skipped with a
  loud WARNING. Fix: prefix with
  `PULSE_SINK=alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__hw_sofhdadsp__sink`.
  Decode checks are device-independent.
- raudio.zig keeps upstream C quirks verbatim (discarded log callback, ExportWave
  result shadowing, ≥32MB jar_mod leak) — intentional, byte-exactness first;
  documented in src comments.
- `[_]u8{0} ** N` is rejected by zig 0.17.0-dev.644 in some positions; use
  `: [N]T = @splat(0)`.
- Zig object files MUST use `use_llvm = true` (self-hosted x86 backend
  miscompiles by-value float code) — already applied everywhere in build.zig.
