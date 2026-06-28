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

## Resume point — 8/10 modules; whole engine Zig except rmodels+raudio; gate 10/10

**DONE (all green, tagged):** raymath, rcamera, rgestures (bit-exact); rshapes,
rtext, rtextures, rlgl, **rcore** (pixel byte-exact). With rcore + the GLFW
platform ported, the entire raylib engine — window/input/timing, GL abstraction,
2D drawing, text, image/texture, math/camera/gestures — is **Zig**. Only the C
TUs **rmodels.c** (3D) and **raudio.c** (audio) remain. rcore brought
raymath/rcamera/rgestures into the real build (rcamera.zig bundles raymath's
exports; rgestures.zig standalone; sinfl/sdefl/rprand via src/c/rcore_impl.c).
`rcore_ported = true` in build.zig.

**Remaining 2 modules:**
1. **rmodels.c** (7334) — 3D meshes/models. Needs a third-party shim (tinyobj/
   cgltf/cgltf_write/vox/m3d/par_shapes, config-driven like rtextures) AND the
   loaders traverse cgltf/m3d/tinyobj STRUCTS (must mirror those — bigger ABI
   surface than stb). Add 3D scenes (BeginMode3D + a Camera3D + GenMeshCube/
   Sphere + DrawMesh/DrawModel/DrawCube/DrawGrid) to gate the rendering path;
   the file loaders are ported-but-lightly-validated (no model files in scenes).
   Depends on rlgl(✅)+raymath(✅)+rtextures(✅).
2. **raudio.c** (2964) — audio. miniaudio + dr_wav/flac/mp3 + stb_vorbis + jar
   shim. No pixel oracle — validate decode via a PCM-diff harness; device/mixing
   is a loose check.

Then the **Angry Birds capstone** in examples/.

Pending extra validation for rcore: a data-function check (CRC32/MD5/SHA/Base64/
Compress) against known vectors — the pixel gate covers window/context/draw only.

## Status snapshot (2026-06-28)

| Phase | State |
|---|---|
| 0 — foundation + oracle | **DONE** ✅ (`zig build test` green, 4/4 scenes byte-identical) |
| 1 — raymath | **DONE** ✅ (`zig build mathtest` bit-exact, 146 fns / 79,800 values) |
| 2 — rlgl | not started (header-only; the GL layer) |
| 3 — rshapes/rtextures/rtext | **ALL THREE DONE** ✅ (pixel gate 10/10) |
| 4 — rcamera | **DONE** ✅ (bit-exact); rgestures/rlgl/rcore remain |
| 5 — rmodels/raudio | not started (3D + audio; need shims + 3D/PCM harnesses) |

Modules ported to Zig: **8 / 10** (raymath, rcamera, rgestures, rshapes, rtext, rtextures, rlgl, rcore). Only rmodels + raudio remain.
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
