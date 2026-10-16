# PROGRESS.md — raylib-zig live status & resume guide

Authoritative current state. Update at every milestone. See [plan.md](plan.md)
for the roadmap, [CLAUDE.md](CLAUDE.md) for conventions, [tokens.txt](tokens.txt)
for cost.

## Phase 6 — idiomatic Zig API — ✅ (2026-10-16; approved "as per the raylib guidelines")

`const rl = @import("raylib");` — raylib's functions, names and types
(first letter lower-cased) with Zig idiom where C is weak: `[:0]const u8`
strings, slices for ptr+count, real enums, packed `ConfigFlags`, error unions
on loaders, `Color` decl literals (`.ray_white`), std.fmt `textFormat`.
Rules: [docs/zig-api.md](docs/zig-api.md).

- **Generated** by `tools/gen_api.py` from raylib.h + raymath.h + rlgl.h →
  `src/api/raylib.zig` (619 functions + `rl.math` 146 + `rl.gl` 163),
  `src/api/c.zig` (exact-C boundary), `src/api/c_exdiff.zig` (gate variant).
  Anything the rules can't map fails generation by name (~60 overrides).
- **Gates:** `zig build apitest` — every API struct layout-identical to
  translate-c'd raylib.h/rlgl.h (by reflection), all wrappers compile,
  generic wrappers instantiated, enum/flag/color values;
  `zig build apiexamples` — Zig-API translations of upstream examples render
  the final frame byte-identical to the original C example (C example + C
  oracle vs Zig example + Zig lib). **155/155** (+ shapes batch pending). Main C-vs-port gate re-verified after the harness flag change: **219/219**.
- **API bugs the translations found and fixed:** updateSound/updateAudioStream
  frame-count misread as bytes; loadFontEx empty codepoints → NULL handling;
  memRealloc/imageBlurGaussian mis-sliced; textFormat/traceLog didn't compile
  on 0.18 (generic fns escape refAllDecls — now instantiated in apitest).
- **Harness:** C examples now compiled `-ffp-contract=off` (clang fused a*b+c
  in example code; no Zig translation can match FMA).

## raylib 6.2 parity — ✅ DONE 2026-10-16 (tag `raylib-6.2-parity`)

raylib 6.2 was tagged upstream 2026-10-15 (352 commits past our 6.1-dev pin,
a direct descendant). Rebased the whole port onto it in one session:

- **Toolchain:** Zig moved to 0.18.0-dev.246 (asdf master). build.zig ported:
  `standardOptimizeOption` now returns `?Optimize`; ported Zig objects must set
  `link_libc` (else std's no-libc Thread/getauxval paths need `__zig_elf_*`
  symbols only Zig's start code defines). All gates byte-identical after.
- **6.1-dev examples gate closed first:** 209/209 automated pass; 8 excluded
  with reasons (see test/examples.list) = all 217. The sweep exposed that the
  gate compiled examples without upstream's `-DPLATFORM_DESKTOP -I src/external`
  (shader examples ran their GLSL 100 variants) — fixed, re-swept green.
- **Re-vendor:** vendor/raylib/src = 6.2 (02566453) + the one local patch.
  Reference tree: /home/rajesh/opensource/graphics/raylib-6.2.
- **Module deltas** (5 drafting agents in worktrees + lead; serial merge/verify):
  rshapes (new outline-thickness API: DrawTriangleLinesEx, DrawCircleSectorLinesEx,
  DrawEllipseLinesEx, DrawRingLinesEx; rounded/poly/ring rewrites), rtextures
  (ImageDrawRectanglePro, ImageDrawRectangleGradientEx, ImageDrawImageEx,
  ImageDrawTextPro [upstream stub], LoadRenderTextureEx; kernel convolution,
  circle gradient, R5G5B5A1 fix), rtext (Unicode space glyphs, Text* edge
  cases; + pre-existing FONT_SDF gap fixed), rmodels (SUPPORT_GPU_SKINNING now
  1 → 9 VBOs + bone binding; unsigned boneCount; sphere/animation/glTF/OBJ
  changes), rcore+glfw (IsFileHidden, IsPathDirectory, IsPathAbsolute; GetFPS,
  SHA256 padding, GetPrevDirectoryPath, OpenURL, RAYLIB_VERSION was stale),
  raymath (from→to opposite vectors, MatrixDecompose transpose), rlgl
  (rlGetPixelDataSize overflow guards), raudio (close order, CALLOC, leak fix).
- **Gates vs 6.2 oracle:** pixel 12/12; audio 43/43; datacheck; mathtest
  90,200 values (grid extended — 3 changed fns were never covered; old port
  fails it); camtest; gesttest; **examples 220/220** (7 excluded with reasons
  = all 227); `tools/constaudit.py` 514 constants, 0 mismatches; RLAPI parity
  619/619 symbols, each defined once, all from Zig objects; angrybirds selftest OK.

### Excluded examples (6.2) — reasons in test/examples.list
core_custom_frame_control, core_input_gestures_testbed, core_window_should_close
(as before); rlgl_standalone (embeds its own C rlgl + raw GLFW, never touches the
library); audio_module_playing, audio_raw_stream, audio_spectrum_visualizer (fail
C-vs-C: pixels driven by real-time audio thread). audio_mixed_processor and
audio_stream_effects are load-sensitive (flaked once under heavy concurrent CPU
load; 3/3 green idle).

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

### The examples acceptance suite — first batch DONE (2026-07-04): 135/135

The exdiff gate exists (tools/exdiff.sh + tools/exdiff/{shim.h,driver.c,
fakeclock.c} + test/examples.list): compiles UNMODIFIED upstream examples with
a determinism shim (frame-counter clock, fixed seed, hidden window,
frame-bounded loop + final-frame screenshot) and an LD_PRELOAD clock freezer
(library-internal real-time paths), links each against both libraries, runs
headless under llvmpipe, byte-diffs the PNGs. **All 135 core/shapes/text/
textures examples pass byte-identical** (2 excluded with reasons in the list).

The gate caught and we fixed: 3 real port bugs (rtext null-glyph atlas panic;
rtextures GetPixelColor eager @alignCast; MeasureTextEx fractional-spacing
truncation) and 2 oracle-build issues (-ffp-contract=off needed everywhere;
UBSan off for the oracle only). Post-mortems → CLAUDE.md gotchas.

### Batch 2 DONE (2026-07-04 afternoon): models 30/30, shaders 35/35

Two more port bugs found and fixed (commit `a5e0ee6`):
- **rcore.zig ShaderLocationIndex off-by-one** (BONEIDS/BONEWEIGHTS/
  BONETRANSFORMS/INSTANCETRANSFORM at 27/28/29/30, raylib.h says 26/27/28/29):
  LoadShader wrote auto-bound attrib locs at wrong indices → GPU instancing
  rendered nothing, skinned-bone attribs misfiled. A full mechanical audit of
  every mirrored constant in src/*.zig vs the C headers is now clean.
- **rmodels.zig LoadM3D casts**: bone ids need @truncate (M3D_UNDEF→255 as C
  truncates); materialid comparisons need @bitCast (C compares in unsigned
  domain). Plus `-fno-sanitize=alignment` for vendored parsers' misaligned
  reads (m3d.h, vox_loader.h — benign x86 UB the oracle build ignores).

### DONE (2026-10-16) — final full 6.1-dev sweep: 209/209 (see 6.2 section above)
Audio (11) and others (3) categories are getting first coverage. Expected:
auto-playing music UIs may need exclusion (playback progress is device-thread
real time); rlgl_standalone bypasses InitWindow/WindowShouldClose so the shim
can't frame-bound it. Record the final passed/excluded tally here.

**Ledger (verified against the tree):** this raylib version ships **217**
example programs (the "218 examples" figure counted examples_template.c;
core_loading_thread.c no longer exists upstream). test/examples.list =
**214 automated + 3 excluded with reasons** = all 217 accounted for, none
skipped silently.

### THEN — cleanups (non-blocking)
- ~~ReleaseFast static-archive LLD failure~~ — resolved (Zig 0.18; see Known issues).
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

Examples passing (the 218-example acceptance suite): **135/135 of the first
batch** (all core/shapes/text/textures examples; 2 excluded with reasons in
test/examples.list, 3 upstream categories remain — models/shaders/audio/others,
~81 examples). Run: `tools/exdiff.sh <oracle.a> <zig.a>`. Scene battery: 12
scenes; audiocheck battery: 43 checks.

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

- ~~ReleaseFast fails to archive the static lib~~ — **resolved by the Zig
  0.18-dev toolchain (2026-10-16)**: `zig build -Doptimize=ReleaseFast` archives
  (11 MB vs 59 MB Debug) and every non-example gate is byte-identical at
  ReleaseFast (pixel 12/12, math 90,200, cam, gest, data, audio 43/43, cdiff
  4/4). (Was `LLD: UnableToWriteArchive` under 0.17-dev.)
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
