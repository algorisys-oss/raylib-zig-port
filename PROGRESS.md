# PROGRESS.md — raylib-zig live status & resume guide

Authoritative current state. Update at every milestone. See [plan.md](plan.md)
for the roadmap, [CLAUDE.md](CLAUDE.md) for conventions, [tokens.txt](tokens.txt)
for cost.

## Resume point

**rshapes + rtext + rtextures DONE (pixel byte-exact).** Next module: **rcore**
(window/input/timing + the global `CoreData CORE`) with the `platforms/
rcore_desktop_glfw.c` backend. rcore needs CoreData mirrored as an extern struct
with comptime offset asserts vs C ground truth — build tools/offsets.c →
src/c_layout.zig FIRST (copy sqlite-zig's gen_layout pattern). glfw stays linked
C. Then rmodels (cgltf/par_shapes/m3d shim), raudio (miniaudio/dr_* shim; PCM
diff, no pixels). rlgl.h/rcamera.h/rgestures.h are header-only (out-of-line via
rcore's RLGL_IMPLEMENTATION) — port after their callers.

**older rtextures detail** —
needs its own stb shim (stb_image + stb_image_write + stb_image_resize2 +
stb_perlin + qoi, with RL_MALLOC, STBI_NO_* config from rtextures.c lines
~70-280) and procedural-image scenes (GenImage*/Image*/LoadTextureFromImage/
DrawTexture) since the current battery loads no textures. Then rcore+glfw
(needs CoreData offset tooling: tools/offsets.c → src/c_layout.zig), rmodels
(cgltf/par_shapes/m3d shim), raudio (miniaudio/dr_* shim; validate via decoded
PCM diff, no pixels).

## Status snapshot (2026-06-28)

| Phase | State |
|---|---|
| 0 — foundation + oracle | **DONE** ✅ (`zig build test` green, 4/4 scenes byte-identical) |
| 1 — raymath | **DONE** ✅ (`zig build mathtest` bit-exact, 146 fns / 79,800 values) |
| 2 — rlgl | not started |
| 3 — rshapes/rtextures/rtext | **ALL THREE DONE** ✅ (pixel gate 10/10) |
| 4 — rcore + glfw platform | not started |
| 5 — rmodels/raudio | not started |

Modules ported to Zig: **4 / 10** (raymath, rshapes, rtext, rtextures) (+1 platform backend). `ported_modules` in
[build.zig](build.zig) is empty → 100% C baseline; the gate is trivially green.

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
