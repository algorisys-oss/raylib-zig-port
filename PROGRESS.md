# PROGRESS.md — raylib-zig live status & resume guide

Authoritative current state. Update at every milestone. See [plan.md](plan.md)
for the roadmap, [CLAUDE.md](CLAUDE.md) for conventions, [tokens.txt](tokens.txt)
for cost.

## Future capstone (user request 2026-06-28)

Once rcore (window+input) + rlgl are ported (so a real interactive game can run),
create `examples/` and **recreate the Angry Birds game in Zig/raylib-zig** —
reference: `/home/rajesh/lab/csharp/csharp-raylib-angrybirds` (C# + raylib, ~6
.cs files, physics slingshot game). Proves the ported library is usable, not just
gate-passing. See memory `angrybirds-demo-task`.

## Resume point — 8/10 modules; engine Zig except rmodels+raudio (paused 2026-06-28)

**DONE (all green, tagged, committed):** raymath, rcamera, rgestures (bit-exact);
rshapes, rtext, rtextures, rlgl, rcore (pixel byte-exact). The whole raylib engine
— window/input/timing (rcore + GLFW platform), GL abstraction (rlgl), 2D drawing
(rshapes), text (rtext), image/texture (rtextures), math/camera/gestures — is Zig.
Main gate **12/12** (incl. two 3D scenes); rcore data fns validated (`zig build
datacheck`). Last green commit: `Pre-wire rmodels shim`. Only **rmodels.c** (3D)
and **raudio.c** (audio) remain.

### IN PROGRESS — rmodels (resume here first) — DRAFT DONE, 1 bug

`src/rmodels.zig` is COMPLETE (6791 lines, 73 exports, fmt-clean, builds
`-fllvm`) and COMMITTED, but NOT in `ported_modules` (so the build stays green
with C rmodels — 12/12). When swapped in, the gate is **11/12**: all 2D scenes +
the **3d_mesh** scene (GenMeshCube/Sphere/Torus + DrawModel/DrawModelEx + DrawGrid)
are **byte-identical**; only **3d_shapes fails (1.3% of pixels)**.

**The one bug: `DrawSphere`/`DrawSphereEx` solid fill does not render.** Evidence:
the diff is exactly the sphere's bounding box (x[283..356] y[132..204]); C shows
the solid blue sphere (0,121,241), Zig shows the plane behind it (50,55,65) — so
the solid triangles aren't drawn (the wireframe `DrawSphereWires` IS fine, and
`DrawCube` solid IS fine). Verified NOT the cause: RL_TRIANGLES=0x0004 constant,
DEG2RAD=PI/180 (f32), the vertex math/order (line-for-line identical to C), Color
ABI (DrawCube works). Suspect: a subtle issue specific to DrawSphereEx's
immediate-mode triangle stream (winding/culling, batch, or the in-place `vertices`
array update). TO DEBUG: make a throwaway scene with ONLY `DrawSphere` (isolate),
compare to C; check rlEnableBackfaceCulling state + triangle winding; verify the
self-referential `vertices[2] = .{ .x = cosslice*vertices[2].x - ... }` array
update isn't mis-evaluating. Then re-add `"rmodels.c"` to `ported_modules`,
`zig build test` → 12/12, commit + tag `rmodels-ported`.

### THEN — raudio (the last module)
Audio. Build `src/c/raudio_impl.c` shim replicating raudio.c's preamble
(config.h-driven; formats enabled: WAV/OGG/MP3/QOA/XM/MOD; FLAC OFF):
- miniaudio: `MA_MALLOC/MA_FREE`, `MA_NO_JACK`, `MA_NO_WAV/FLAC/MP3`,
  `MA_NO_RESOURCE_MANAGER/NODE_GRAPH/ENGINE/GENERATION`, `MA_COINIT_VALUE 2`,
  `MINIAUDIO_IMPLEMENTATION` + `#include "external/miniaudio.h"` (HUGE).
- `DR_WAV_IMPLEMENTATION`+dr_wav.h; `#include "external/stb_vorbis.c"`;
  `DR_MP3_IMPLEMENTATION`+dr_mp3.h; `QOA_MALLOC/FREE`+`QOA_IMPLEMENTATION`+qoa.h +
  `#include "external/qoaplay.c"`; `JAR_XM_IMPLEMENTATION`+jar_xm.h;
  `JAR_MOD_IMPLEMENTATION`+jar_mod.h. (dr_flac OFF.)
- raudio.c owns the AudioBuffer/device callback/mixing — needs an audio device
  for playback (may be absent headless → InitAudioDevice handles gracefully).
  Validate the DECODE path with a **PCM-diff harness**: build a known WAV/QOA in
  memory, `LoadWaveFromMemory` C-vs-Zig (or vs known samples), compare PCM bytes.
  Device/mixing = loose check. Then integrate (add `"raudio.c"` to
  ported_modules + shim) + tag `raudio-ported` = **100%**.

### THEN — the Angry Birds capstone (examples/)
See the "Future capstone" note below + memory `angrybirds-demo-task`.

## Status snapshot (2026-06-28)

| Phase | State |
|---|---|
| 0 — foundation + oracle | **DONE** ✅ (`zig build test` green, 4/4 scenes byte-identical) |
| 1 — raymath | **DONE** ✅ (`zig build mathtest` bit-exact, 146 fns / 79,800 values) |
| 2 — rlgl | not started (header-only; the GL layer) |
| 3 — rshapes/rtextures/rtext | **ALL THREE DONE** ✅ (pixel gate 10/10) |
| 4 — rcamera | **DONE** ✅ (bit-exact); rgestures/rlgl/rcore remain |
| 5 — rmodels/raudio | not started (3D + audio; need shims + 3D/PCM harnesses) |

Modules ported to Zig: **8 / 10** (raymath, rcamera, rgestures, rshapes, rtext, rtextures, rlgl, rcore). Only **rmodels** (3D, draft in progress) + **raudio** (audio) remain.
`ported_modules` in [build.zig](build.zig) = {rshapes.c, rtext.c, rtextures.c}
(the rendering modules swapped into the lib + their stb shims); raymath & rcamera
are header-only, validated bit-exact standalone but not yet swapped into the
render path (they swap in when their callers — rshapes already uses none; rcore —
are ported / via out-of-line instantiation). Gate: 10/10 pixel + bit-exact
math/cam.

Examples passing (the 218-example acceptance suite): not yet wired (needs the
modules a given example uses to be ported first). Scene battery: 10 scenes (+ image_gen, image_ops, color_ops for rtextures).

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
