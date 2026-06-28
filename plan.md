# plan.md — Migrating raylib (C → Zig)

Living migration plan. Source of truth for scope, strategy, and progress.
Update checkboxes and notes as work lands.

- **Target to port:** raylib v6.1-dev (`/home/rajesh/opensource/graphics/raylib`,
  git `6.0-178-g67359073`)
- **Toolchain:** Zig `0.17.0-dev.644+3de725074`
- **Scope:** ~38k LOC of hand-written raylib C/H (6 `.c` modules + 4 header-only
  modules + 1 platform backend), ~408k source tokens. The ~13 MB of bundled
  third-party `src/external/` libs are **linked, not ported**. See
  [token-count.md](token-count.md).
- **Goal: 100% port** of all raylib-authored code to Zig (no raylib `.c` left in
  the build). **Real exceptions** (deliberately kept as linked C, not failures):
  (1) the bundled third-party libs in `src/external/` — not raylib; (2) platform/
  GL backends outside the pinned Linux/GLFW + OpenGL 3.3 target — deferred, not
  excluded. Any raylib module that proves un-portable must be logged as an
  explicit, justified exception in `docs/not-migrated.md`, never dropped silently.
- **Definition of done for any step:** the software-renderer **pixel/numeric
  diff against pure-C raylib is clean** (see Validation below). raylib has no
  test suite — this is the whole safety net.
- **Playbook:** copied from the completed sibling migration
  `/home/rajesh/lab/ai-port/sqlite-zig` (per-TU swap, C-ABI boundaries,
  ground-truth offset asserts, parallel drafting + serial verification).

---

## Guiding principles

1. **The pixel diff is the spec.** No test suite exists; we manufacture the
   oracle (software renderer + numeric diff + golden-PNG examples) and gate every
   port on it. See Validation.
2. **Incremental, never big-bang.** A mixed C/Zig binary must build and pass the
   diff at every commit. Zig links C trivially (`addCSourceFile`, `@cImport`), so
   we replace one `.c` / header-module at a time.
3. **Preserve the C ABI at boundaries.** Each module keeps its `raylib.h`/
   `rlgl.h` signatures (`export` matching `RLAPI`/`RMAPI`) and the `CoreData`/
   `rlglData` global-state layout until all callers are ported.
4. **Bottom-up.** Port leaf dependencies before dependents:
   `raymath` → `rlgl` → `rshapes`/`rtextures`/`rtext` → `rcore`+platform →
   `rmodels`/`raudio`.
5. **Don't port `src/external/`.** stb, miniaudio, dr_*, cgltf, glfw, glad, etc.
   are third-party single-file libs — link them as C. Porting them is out of
   scope (the raylib analog of not hand-porting SQLite's generated `parse.c`).
6. **Idiomatic Zig inside, C-compatible outside.** Rewrite internals with Zig
   idioms; expose C-ABI shims where C still calls in.
7. **The quality bar: Zig as if written by Andrew Kelley, design as if by
   Raysan.** Code idiom held to Zig-stdlib standards (minimal, explicit, no hidden
   control flow/allocations, every error handled); the public API keeps raylib's
   simple, consistent, beginner-friendly design unchanged. Confine C-shaped ABI
   code to a thin boundary layer so internals stay clean. `zig fmt` is mandatory.
   See [CLAUDE.md](CLAUDE.md) Conventions for the full statement.

---

## CURRENT STATUS (2026-06-28) — planning only, no code yet

Scaffolding docs created: `CLAUDE.md`, `plan.md`, `token-count.md`, `tokens.txt`,
`tools/token_usage.py`. Phase 0 not started. **PROGRESS.md** (authoritative live
status + resume guide) will be created when porting begins, as in sqlite-zig.

---

## Decisions to resolve BEFORE committing to a build shape (flag to user)

These shape everything; resolve in Phase 0. Recommendations given.

1. **Validation oracle — confirm the software-renderer approach.** Plan assumes
   `external/rlsw.h` (software OpenGL 1.1, `GRAPHICS_API_OPENGL_11` +
   `RLSW_IMPLEMENTATION`) gives a deterministic, headless, byte-exact framebuffer
   for pixel diffing. **Must be proven in Phase 0.** If rlsw is too lossy/
   incomplete to be an oracle, fallback is real-GPU rendering to an FBO +
   loose/perceptual diff (non-deterministic, weaker gate) — a materially worse
   position. *Recommend: prove rlsw first; it is the linchpin.*

2. **Header-only inline modules (`raymath`/`rlgl`/`rcamera`/`rgestures`).** Their
   functions are `static inline` by default (`RMAPI`/inline), so C callers inline
   them and there is no exported symbol to swap. Options: (a) build raylib with
   these forced **out-of-line** (real symbols) so a Zig port can override them;
   (b) port them as Zig and have *all* C callers go through the Zig symbols;
   (c) port them last, as a pure Zig rewrite once their callers are already Zig.
   *Recommend (a) for raymath early (prove the pixel/numeric harness on the
   easiest module), (c) for rlgl.*

3. **Platform/backend config to pin first.** raylib varies by
   `PLATFORM_DESKTOP_*` × `GRAPHICS_API_OPENGL_*` × `config.h` `SUPPORT_*` flags.
   A single Zig object can't match two configs (same constraint sqlite-zig hit
   with prod vs `--dev`). *Recommend: pin **PLATFORM_DESKTOP_GLFW + OPENGL_33 +
   default config.h** as the production target, and **OPENGL_11/rlsw** as the
   headless test config — mirror both as a comptime `config` module, exactly like
   sqlite-zig's `-Dtestfixture`.*

4. **Build foundation.** raylib already ships an official `build.zig` that
   compiles each module per-TU via `addCSourceFile`. *Recommend: fork it, add a
   `ported_modules` swap list + the two-config (`prod`/`rlsw-test`) split, rather
   than writing a build from scratch.*

5. **Allocator / error model.** raylib uses `RL_MALLOC`/`RL_CALLOC` macros and
   returns sentinel structs (e.g. zeroed `Image`) rather than error codes.
   Decide: thread `std.mem.Allocator` internally vs. keep the macro hooks; keep
   the C return-by-value-sentinel contract at the ABI. *Recommend: keep the C
   contract at the boundary; use Zig idioms only in private helpers.*

---

## Validation (the manufactured oracle — replaces a test suite)

Stand this up in Phase 0; it is the entire safety net. Cheapest first:

1. **Numeric diff — `raymath`.** Pure functions. Generate a large input grid,
   run through C and Zig, compare to ULP tolerance. No rendering. First gate;
   proves the harness on the simplest module.
2. **Software-renderer pixel diff (the core gate).** Build with `rlsw` (software
   GL). For a fixed set of drawing workloads, render with pure-C raylib and with
   Zig modules swapped in; read back the framebuffer; diff **byte-for-byte**.
   This is `make devtest` for this project. Every port must keep it clean.
3. **Example golden PNGs.** Drive `examples/*.c` (they exercise the public API)
   through the software renderer, `TakeScreenshot` to PNG, diff against goldens
   captured from pure-C raylib. Broadens coverage to real programs.
4. **Real-GPU spot check.** Periodically run a few examples on GLFW + OpenGL 3.3.
   GPU output isn't bit-deterministic → human/loose check, not the gate; catches
   bugs the software path masks.

**Never commit anything whose diff isn't clean.** The last committed state must
always build and render identically to pure-C raylib.

---

## Phase 0 — Foundation & oracle (no porting yet)

Goal: a Zig-driven build of *unmodified* upstream raylib C that produces a
working library AND the pixel/numeric diff harness. Safety net for everything
after. **This phase is more important here than in sqlite-zig** — there is no
upstream test suite to fall back on.

- [ ] Fork raylib's official `build.zig`; build `libraylib.a` + a sample program
      with the Zig toolchain, unmodified C, PLATFORM_DESKTOP_GLFW + OPENGL_33.
- [ ] Add a second build config: `rlsw` software renderer (OPENGL_11 +
      `RLSW_IMPLEMENTATION`) producing a headless framebuffer. Prove it renders a
      known scene deterministically (same bytes twice).
- [ ] Build the **pixel-diff harness**: render workload → read framebuffer →
      byte-compare two builds. Build the **numeric-diff harness** for raymath.
- [ ] Capture golden framebuffers/PNGs from pure-C raylib for a starter workload
      set (a few shapes/text/texture scenes + a raymath input grid).
- [ ] Set up the per-module swap: a `ported_modules` list in build.zig that
      selects `src/<name>.zig` over its C counterpart (default empty → 100% C).
- [ ] Copy + adapt sqlite-zig's ground-truth offset tooling
      (`tools/offsets.c` → `src/c_layout.zig`) for `CoreData`/`rlglData` and the
      public structs, with comptime `@offsetOf`/`@sizeOf` asserts.
- [ ] Resolve the inline-symbol question (decision #2) so raymath is swappable.

**Exit criteria:** software-renderer pixel diff + raymath numeric diff are wired
and green against an all-C build (baseline diffs to itself = clean), and one
module can be swapped C↔Zig via `ported_modules`.

## Phase 1 — `raymath.h` (pure, no deps — the pattern-setter)

Self-contained vector/matrix/quaternion math; no globals, no GL, no I/O. Ideal
first port to establish the playbook (ABI shims, by-value struct args, float
exactness, the numeric-diff gate).

- [ ] `raymath.h` → `src/raymath.zig`. Export the `RMAPI` functions out-of-line.
      Validate with the numeric diff (ULP-exact vs C over a large grid). Nail the
      by-value `Vector2/3/4`/`Matrix`/`Quaternion` ABI lowering here.

**Exit criteria:** raymath is Zig; numeric diff clean; by-value-struct + float
patterns documented for later modules.

## Phase 2 — `rlgl.h` (the GL abstraction + render state)

The OpenGL state machine every drawing call funnels through; owns `RLGL`. High
risk — first module where the *pixel* diff (not numbers) is the gate. Port
against the software renderer so the gate is deterministic.

- [ ] `rlgl.h` → `src/rlgl.zig`. Mirror `rlglData RLGL` with offset asserts.
      Keep the OPENGL_* backend selection as comptime config. Validate every
      immediate-mode + batched draw path through the rlsw pixel diff.

**Exit criteria:** all rendering flows through Zig rlgl; pixel diff clean on the
shapes/text/texture workloads.

## Phase 3 — Drawing & asset modules

Rest on rlgl. Port in increasing third-party-coupling order.

- [ ] `rshapes.c` → `src/rshapes.zig` — 2D primitives. Pure-ish (uses rlgl +
      a default texture). Pixel-diff every primitive + line/anti-alias path.
- [ ] `rtextures.c` → `src/rtextures.zig` — image/texture. Wraps `stb_image`,
      `qoi`, `stb_image_resize2`, `stb_perlin` (kept as linked C). Diff CPU pixel
      ops (`Image*`) directly; diff GPU upload paths via render.
- [ ] `rtext.c` → `src/rtext.zig` — fonts/text. Wraps `stb_truetype`,
      `stb_rect_pack` (linked C). Pixel-diff glyph atlas build + text rendering.

**Exit criteria:** 2D drawing, textures, and text are Zig; pixel diff clean
across the shapes/textures/text examples.

## Phase 4 — `rcore.c` + the GLFW platform backend

The window/input/timing core and its global `CoreData CORE`. Couples to GLFW
(linked C) via `platforms/rcore_desktop_glfw.c`.

- [ ] `rcore.c` → `src/rcore.zig`. Mirror `CoreData CORE` with offset asserts
      (read across modules). Keep GLFW as linked C.
- [ ] `platforms/rcore_desktop_glfw.c` → `src/rcore_desktop_glfw.zig` (or keep C
      until rcore is Zig). Window/context/input event plumbing over GLFW's C ABI.
- [ ] Defer other backends (`_sdl`, `_rgfw`, `_win32`, `drm`, `web`, `android`).

**Exit criteria:** window lifecycle, input, and timing run on Zig; interactive
examples behave identically; pixel diff clean.

## Phase 5 — `rmodels.c` and `raudio.c` (heaviest third-party coupling — last)

- [ ] `rmodels.c` → `src/rmodels.zig` — 3D meshes/models/materials/animation.
      Wraps `cgltf`, `par_shapes`, `m3d`, `tinyobj`, `vox_loader` (linked C).
      3D pixel-diff via the software renderer; mesh-data diff for loaders.
- [ ] `raudio.c` → `src/raudio.zig` — audio. Wraps `miniaudio`, `dr_wav/_flac/
      _mp3`, `stb_vorbis`, `jar_xm/jar_mod`, `qoa` (linked C). No pixel oracle —
      validate by diffing decoded PCM buffers and the mixing path numerically;
      device output is a loose human check.

**Exit criteria:** 3D + audio are Zig; model/audio examples render/play
correctly; PCM + 3D diffs clean.

## Phase 6 — Helpers, breadth, native API (optional / later)

- [ ] `rcamera.h` → `src/rcamera.zig`, `rgestures.h` → `src/rgestures.zig`
      (header-only helpers; numeric/behavioral diff).
- [ ] Additional platform backends (SDL/RGFW/DRM/Web/Android) and GL backends
      (ES2/ES3 for web/mobile) as needed.
- [ ] A native idiomatic Zig API surface (not just the C ABI), if desired.

---

## What is NOT ported (and why) — the boundary

| Bucket | Examples | Reason |
|---|---|---|
| Third-party `src/external/` | stb_*, miniaudio, dr_*, cgltf, par_shapes, m3d, qoi/qoa, glad, **rlsw**, jar_*, RGFW | Bundled upstream single-file libs — not raylib. Linked as C. |
| Windowing libs | `external/glfw/`, `rglfw.c`, SDL | Large host libraries; out of scope. Linked as C. |
| Non-Linux/non-GLFW backends | `platforms/rcore_{sdl,rgfw,win32,drm,web,android,template}.c` | Not compiled in the pinned Linux/GLFW build. Deferred. |
| Other GL backends | OPENGL_21/43/ES2/ES3 paths | Only OPENGL_33 (+ rlsw for tests) pinned first. Deferred. |

Mirrors sqlite-zig's "not-migrated" buckets (generated/other-platform/
flag-inactive). A "pure-Zig raylib" = every raylib-authored module is Zig, with
`external/` still linked C.

---

## Risks

- **No test-suite oracle (the defining risk).** Everything rests on the
  software-renderer pixel diff being a faithful, deterministic oracle. If `rlsw`
  diverges from the GPU path or is nondeterministic, the gate weakens to loose
  perceptual diffs and the whole port gets risky. *Mitigate: prove rlsw in
  Phase 0; back it with periodic real-GPU spot checks and example goldens.*
- **Float / pixel bit-exactness.** Byte-exact pixel diffs demand C-identical
  float math (FMA/contraction, libm calls, rounding). Subtle drift fails the gate
  on unrelated changes. *Mitigate: pin libm calls; match `f32`; treat tolerance
  carefully.*
- **By-value struct ABI.** raylib passes `Color`/`Vector*`/`Rectangle` by value
  pervasively; small-struct calling-convention mismatches corrupt args silently.
  *Mitigate: lock this down in Phase 1 (raymath) before it spreads.*
- **Multi-axis config divergence.** platform × GL backend × `config.h` flags is a
  bigger matrix than sqlite-zig's two builds. *Mitigate: pin one config; comptime
  `config` module; expand only when needed.*
- **Heavy third-party coupling in rmodels/raudio.** The C↔Zig boundary with stb/
  miniaudio/cgltf must stay ABI-exact. *Mitigate: port these last; lean on the
  offset tooling; keep the libs as linked C.*

## Progress log

- 2026-06-28: Repo scaffolding — `CLAUDE.md`, `plan.md`, `token-count.md`,
  `tokens.txt`, `tools/token_usage.py` created. No code yet. Phase 0 not started.
  Playbook adapted from the completed sqlite-zig migration; key adaptation is the
  validation oracle (software-renderer pixel diff) since raylib has no test suite.
