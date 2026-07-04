# PROGRESS.md — raylib-zig live status & resume guide

Authoritative current state. Update at every milestone. See [plan.md](plan.md)
for the roadmap, [CLAUDE.md](CLAUDE.md) for conventions, [tokens.txt](tokens.txt)
for cost.

## Capstone (user request 2026-06-28) — ✅ DONE 2026-07-04

`examples/angrybirds/` — the C# reference game
(`/home/rajesh/lab/csharp/csharp-raylib-angrybirds`) recreated as idiomatic Zig
over the ported library's C ABI. `zig build angrybirds` to play; headless
scripted selftest (`ANGRYBIRDS_SELFTEST=1`) verifies it runs (screenshot
checked). Proves the library is usable, not just gate-passing.

## Resume point — 🏁 100%: all 10 modules Zig (2026-07-04, tag `raudio-ported`)

**Every raylib-authored module is now Zig.** raymath, rcamera, rgestures
(bit-exact); rshapes, rtext, rtextures, rlgl, rcore, rmodels (pixel byte-exact);
**raudio** (PCM byte-exact). The swapped build compiles NO raylib-authored C —
remaining C is bundled third-party only (rglfw.c + the src/c/ instantiation
shims), per the charter's allowed exceptions. Gates all green: pixel **12/12**,
**audiocheck 43/43** (full coverage incl. device section), datacheck OK, and the
**Angry Birds capstone** (examples/angrybirds/, `zig build angrybirds`) runs on
the full-Zig library with a headless selftest.

**Module-draft post-mortems (2026-07-04)** — both gate-caught, both now CLAUDE.md
gotchas to check in any future Zig work here:
- rmodels: **result-location aliasing** in DrawSphereEx (`v = .{ .z =
  f(v.x) }` reads the freshly-written `.x`; C's compound literal is a temporary).
- raudio: **callback-before-cache** — `ma_device_start` can invoke the data
  callback synchronously (pulse primes its stream), but the draft cached the
  device format/channels only after start → first callback memset 0 bytes,
  shipped uninitialized memory (NaN → UBSan abort). Cache device properties
  before `ma_device_start`.

**Environment note:** if `audiocheck` reports the device section skipped
(`device: ready=0` + loud WARNING), the desktop default sink is an HDMI output
whose sample spec miniaudio can't map. Run with
`PULSE_SINK=alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__hw_sofhdadsp__sink`
(the analog sink) for full 43-check coverage. Decode/wave/export checks (27) are
device-independent.

### NEXT — the examples acceptance suite (the remaining "done" criterion)
CLAUDE.md's bar: **all 218 upstream examples pass** (build + link against the
Zig library + pixel/PCM-match vs the C oracle). The scene battery + audiocheck
prove the modules; the examples suite proves the whole surface. Plan: a runner
that builds each `examples/**/*.c` against both libs, drives N deterministic
frames headless under llvmpipe (inject input where examples need it — many are
static render loops), screenshots both, byte-diffs. Start with the ~40
core/shapes/text/textures examples (no input, no assets beyond resources/),
expand category by category; log unautomatable ones (interactive-only,
GPU-timing-dependent) in docs/not-migrated.md with reasons. Track pass count
here.

### THEN — cleanups (non-blocking)
- ReleaseFast static-archive LLD failure (workaround candidates noted in
  "Known issues").
- Idiomatic-Zig API layer (Phase 6, separate surface; C ABI stays frozen).

## Status snapshot (2026-07-04)

| Phase | State |
|---|---|
| 0 — foundation + oracle | **DONE** ✅ (`zig build test` green) |
| 1 — raymath | **DONE** ✅ (`zig build mathtest` bit-exact, 146 fns / 79,800 values) |
| 2 — rlgl | **DONE** ✅ (163 fns; pixel byte-exact) |
| 3 — rshapes/rtextures/rtext | **ALL THREE DONE** ✅ |
| 4 — rcamera/rgestures/rcore | **ALL DONE** ✅ (bit-exact / pixel byte-exact) |
| 5 — rmodels/raudio | **BOTH DONE** ✅ (tags `rmodels-ported`, `raudio-ported`) |
| capstone | **DONE** ✅ examples/angrybirds (`zig build angrybirds`, headless selftest) |

Modules ported to Zig: **10 / 10** — 🏁 **100% of raylib-authored code**.
`ported_modules` in [build.zig](build.zig) = {rshapes.c, rtext.c, rtextures.c,
rmodels.c, raudio.c}; rlgl + rcore swap via their own flags
(`rlgl_ported`/`rcore_ported`, both true); raymath/rcamera/rgestures link in via
the rcore swap. Gates: 12/12 pixel + 43/43 audio + bit-exact math/cam/gestures +
datacheck.

Examples passing (the 218-example acceptance suite): **not yet wired — this is
the next milestone** (see Resume point). Scene battery: 12 scenes; audiocheck
battery: 43 checks.

## What Phase 0 established (proven, not assumed)

The hard de-risking is done — every claim below was verified by running it:

1. **Zig builds unmodified raylib C, install-free.** All 7 vendored TUs (rcore +
   rshapes/rtextures/rtext/rmodels/raudio + rglfw, which bundles GLFW) compile
   with `zig cc`/`zig build` against the system X11/GL headers
   (`/usr/include`) and dev `.so`s — **no `sudo`/apt needed** (the dev packages
   are already present; vendored GLFW compiles from source). Pinned config:
   `PLATFORM_DESKTOP_GLFW` + `GRAPHICS_API_OPENGL_33` + `_GLFW_X11`.
2. **Headless render + framebuffer readback works** on `DISPLAY=:0` with a hidden
   window (`FLAG_WINDOW_HIDDEN`) via `LoadImageFromScreen`.
3. **The oracle is byte-exact deterministic.** Rendering the GL3.3 codepath under
   **mesa llvmpipe** (`LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe`) gives
   identical bytes across runs — verified 4× on a scene with gradients, alpha
   blending, rotation, and text. The **GPU** path is self-consistent but differs
   slightly from llvmpipe (different rasterizer), so it's a loose spot-check only.
   **Decision refinement:** llvmpipe is the *primary byte-exact* gate (same
   codepath we ship), which is stronger than the originally-planned rlsw/GL11
   path or a tolerance diff. rlsw kept as a documented fallback only.
4. **The C↔Zig swap + diff mechanism works end-to-end.** `build.zig` builds two
   libs from the same sources — `raylib` (ported Zig swapped in via
   `ported_modules`) and `raylib_oracle` (forced all-C) — links a scene runner
   against each, and `tools/scenediff.sh` renders both under llvmpipe and
   byte-diffs the framebuffers. With `ported_modules` empty the gate is green;
   as modules land, any rendering divergence fails the gate.
5. **The harness catches nondeterminism.** A first draft accidentally called
   `DrawFPS()` (reads real timing) → the gate flagged the `text` scene as
   differing. Removed it; the rule "every scene is a pure function of the code
   under test (no time/RNG)" is now enforced by example.

## Commands

```bash
zig build              # build libraylib.a + demo + both scene runners (Debug)
zig build test         # the gate: C-vs-Zig framebuffer diff under llvmpipe
zig build demo         # render the scene battery to zig-out/frames/ (needs DISPLAY)
zig build runners      # build scene_runner_oracle + scene_runner_zig
```

## Known issues / notes

- **ReleaseFast fails to archive the static lib** (`LLD: UnableToWriteArchive`)
  with the full TU set; **Debug builds fine** and is the default. Disk/space ruled
  out (181 G free); an isolated 2-file `build-lib` archives OK, so it's an
  LLD-archive-writer quirk at `-OReleaseFast` + many large C objects. Debug is
  fine for the correctness gate (determinism holds). Revisit for an optimized
  production lib later (possible workarounds: `zig ar` post-step, or `-fno-lto`/
  per-object archive). Tracked; not blocking.
- **Goldens are not committed** — the gate compares the two live builds against
  each other (no machine-specific golden PNGs to maintain). llvmpipe output is
  machine/driver-specific, so committed pixel goldens would not be portable; the
  C-vs-Zig live diff sidesteps that entirely.
- **Zig self-hosted x86 backend miscompiles by-value-struct float code**
  (`InvalidInstruction: no encoding for mov xmm0 xmm` on raymath's `*MoveTowards`).
  Workaround: build Zig objects with the **LLVM backend** (`use_llvm = true` in
  build.zig / `-fllvm`). Applied to the raymath object + math harness; apply to
  every future Zig module object.
- **System paths are hardcoded** to `/usr/include` + `/usr/lib/x86_64-linux-gnu`
  in build.zig (this machine's layout). Parameterize if the build moves hosts.

## Milestone tags

- `phase0-oracle-ready` — foundation + differential oracle green.
- `phase1-raymath` — raymath.zig bit-exact with C (146 fns / 79,800 values).
- `rshapes-ported` — first rendering module; Zig rshapes pixel-identical to C.
- `rtext-ported` — rtext.zig (61 fns, va_list TextFormat, stb shim) pixel-identical to C.
- `rtextures-ported` — rtextures.zig (120 fns, pixel-format/color/raster + stb shim) pixel-identical to C (10/10).
- `rcamera-ported` — rcamera.zig (12 fns, imports Zig raymath) bit-exact vs C (7,500 values).
- `rgestures-ported` — rgestures.zig (10 fns, controlled-clock harness) bit-exact vs C (3,200 values).
- `rlgl-ported` — rlgl.zig (163 fns + gl33.zig) pixel byte-exact vs C (10/10); 2D pipeline Zig.
- `rcore-ported` — rcore.zig (212 fns, rcore.c + GLFW platform, CoreData private) pixel byte-exact (10/10); whole engine Zig except rmodels+raudio.
- `rmodels-ported` — rmodels.zig (73 fns, 6791 lines) pixel byte-exact (12/12 incl. 3d_shapes + 3d_mesh); fixed draft's DrawSphereEx result-location aliasing bug.
- `raudio-ported` — raudio.zig (78 fns, 2287 lines + miniaudio/decoder shim) PCM byte-exact (audiocheck 43/43); fixed draft's callback-before-cache device-start bug. **100% — no raylib-authored C remains in the build.**
