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

## Resume point — 7/10 modules; the ENTIRE 2D pipeline is Zig; gate 10/10

**DONE (all green, tagged):** raymath, rcamera, rgestures (bit-exact); rshapes,
rtext, rtextures, **rlgl** (pixel byte-exact). With rlgl ported, the whole 2D
render stack — GL abstraction + batch renderer + shapes + text + image/texture —
is Zig. rlgl swap: rcore.c compiled with `-DRAYLIB_ZIG_NO_RLGL_IMPL` (guarded
patch), GLAD via src/c/glad_impl.c, GL reached through `glad_gl*` fn-pointers
(src/gl33.zig). `rlgl_ported = true` in build.zig.

**Remaining 3 modules:**
1. **rcore.c** (4629) + `platforms/rcore_desktop_glfw.c` (~2700) — 234 fns,
   window/input/timing/data/file. `CoreData CORE` is NOT cross-module (only
   rcore+platform touch it) → model it PRIVATE, no offset tooling. Port rcore.c
   together with the platform it #includes; GLFW via extern (75 glfw* calls).
   Gate: the pixel battery covers the draw-mode fns (BeginDrawing/Mode2D/3D/
   Scissor/Blend/etc.); add numeric/byte harnesses for the data fns (CRC32/MD5/
   SHA/Base64/Compress) and string diffs for the file-path fns. When rcore is
   ported it also stops instantiating raymath/rgestures/rcamera — swap in the
   already-ported Zig versions (or C-shim what's not wanted).
2. **rmodels.c** (7334) — 3D; own third-party shim (cgltf/par_shapes/m3d/tinyobj/
   vox); add 3D scenes (BeginMode3D + DrawCube/Model/Mesh). Depends on rlgl(✅)+
   raymath(✅)+rtextures(✅).
3. **raudio.c** (2964) — audio; miniaudio/dr_*/stb_vorbis/jar shim; validate
   decode via PCM diff (device/mixing = loose).

Then the **Angry Birds capstone** in examples/ (see below).

## Status snapshot (2026-06-28)

| Phase | State |
|---|---|
| 0 — foundation + oracle | **DONE** ✅ (`zig build test` green, 4/4 scenes byte-identical) |
| 1 — raymath | **DONE** ✅ (`zig build mathtest` bit-exact, 146 fns / 79,800 values) |
| 2 — rlgl | not started (header-only; the GL layer) |
| 3 — rshapes/rtextures/rtext | **ALL THREE DONE** ✅ (pixel gate 10/10) |
| 4 — rcamera | **DONE** ✅ (bit-exact); rgestures/rlgl/rcore remain |
| 5 — rmodels/raudio | not started (3D + audio; need shims + 3D/PCM harnesses) |

Modules ported to Zig: **7 / 10** (raymath, rcamera, rgestures, rshapes, rtext, rtextures, rlgl).
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
- `rlgl-ported` — rlgl.zig (163 fns + gl33.zig GL bindings) pixel byte-exact vs C (10/10); the whole 2D pipeline is now Zig.
