# CLAUDE.md — raylib-zig

Guidance for Claude (and other agents) working in this repository.

## What this project is

A from-scratch **migration of raylib from C to Zig**. The goal is a Zig
implementation of the raylib game/graphics library that is behaviorally
compatible with upstream raylib — same public C ABI (`raylib.h`), same on-screen
output — so existing raylib programs link and render identically.

**Goal: 100% port.** Every line of *raylib-authored* C becomes Zig — all 6 `.c`
modules, all 4 header-only modules, and the platform backends. "Done" means no
raylib-authored C remains in the build. The **real, intended exceptions** (things
we deliberately do **not** port — same spirit as sqlite-zig keeping the
Lemon-generated `parse.c` as C):

1. **Bundled third-party libraries in `src/external/`** (stb_*, miniaudio, dr_*,
   cgltf, par_shapes, m3d, qoi/qoa, glad, rlsw, jar_*, GLFW/RGFW). These are not
   raylib — they are vendored upstream single-file libs. We **link** them as C.
   Porting them is a separate, out-of-scope effort.
2. **Platform backends and GL backends we don't target yet** — `_sdl`, `_rgfw`,
   `_win32`, `drm`, `web`, `android`, and the OPENGL_11/21/43/ES2/ES3 paths. These
   are *portable in principle*; they're deferred, not excluded. 100% for the
   pinned Linux/GLFW + OpenGL 3.3 target is the first milestone; other targets
   extend it later.

So: **100% of raylib's own code → Zig, with `external/` deliberately left as
linked C.** A "pure-Zig raylib" means exactly that, and any module that turns out
*not* to be cleanly portable must be recorded as an explicit, justified exception
in `docs/not-migrated.md` (create it when porting starts, like sqlite-zig's) —
never dropped silently.

This directory (`/home/rajesh/lab/ai-port/raylib-zig`) currently holds only
planning docs. Implementation has not started; see [plan.md](plan.md) for the
staged approach.

This is the sibling of the completed **sqlite-zig** migration
(`/home/rajesh/lab/ai-port/sqlite-zig`). We reuse its proven playbook —
per-translation-unit C→Zig swap, C-ABI-preserving boundaries, ground-truth
struct-offset tooling, agent-parallelized drafting with serial verification, and
per-prompt token logging. **Read the differences section below first: raylib's
correctness oracle is fundamentally different from SQLite's.**

## Reference sources (read-only — never edit)

| What | Path | Notes |
|---|---|---|
| raylib C source | `/home/rajesh/opensource/graphics/raylib` | v6.1-dev (git `6.0-178-g67359073`). zlib/libpng license. Uses **Git**. |
| Zig compiler/stdlib | `/home/rajesh/opensource/ziglang/zig` | Build/run toolchain reference (`src/`). |
| Zig toolchain in PATH | `zig` (`~/.asdf/shims/zig`) | `0.17.0-dev.644+3de725074`. |
| sqlite-zig (sibling) | `/home/rajesh/lab/ai-port/sqlite-zig` | The migration playbook this project copies. |

Treat the source trees as **immutable references**. All new work lands here.

## raylib architecture (the thing we are porting)

raylib is a layered library. The hand-written code we port is small (~38k LOC);
the bulk of `src/external/` is third-party C we **link, not port** (see boundary
below).

```
Public C API ................ src/raylib.h          (1752 lines — the ABI contract)

Modules (the .c we port):
  rcore.c    (4629)  window/input/timing/events; owns global `CoreData CORE`
  rshapes.c  (2514)  2D primitives
  rtextures.c(5627)  image/texture load + pixel ops (wraps stb_image, qoi)
  rtext.c    (3002)  fonts/text (wraps stb_truetype)
  rmodels.c  (7334)  3D meshes/models/materials (wraps cgltf, par_shapes, m3d…)
  raudio.c   (2964)  audio (wraps miniaudio, dr_*, stb_vorbis, jar_*)

Header-only modules (functions live in headers, `static inline` by default):
  raymath.h  (3154)  vector/matrix/quaternion math — PURE, no deps. Easiest port.
  rlgl.h     (5442)  the OpenGL abstraction layer; owns `static rlglData RLGL`.
                     Backend-selectable: OPENGL_11/21/33/43/ES2/ES3 + a software
                     rasterizer (external/rlsw.h).
  rcamera.h  (562)   camera helpers.  rgestures.h (557)  gesture recognizer.

Platform backends ........... src/platforms/rcore_<backend>.c  (~18k LOC total)
  rcore_desktop_glfw.c (the Linux desktop default), _sdl, _rgfw, _win32,
  drm, web/emscripten, android. rcore.c #includes exactly ONE at build time.

Third-party (src/external/, ~13 MB, 138 files — NOT raylib, stays C):
  glfw/ (windowing), glad.h/glad_gles2.h (GL loader), stb_image/_truetype/
  _rect_pack/_vorbis/_image_resize2/_perlin, miniaudio.h, dr_wav/_flac/_mp3,
  cgltf.h, par_shapes.h, m3d.h, qoi.h, qoa.h, vox_loader, jar_mod/jar_xm,
  rlsw.h (software GL), RGFW. Bundled, vendored single-file libs.
```

## The boundary: what we port vs. what stays C

This is the analog of SQLite's "port from the generator, never hand-port a
generated file." raylib bundles ~13 MB of upstream third-party single-file C
libraries in `src/external/`. **They are not raylib and we do not port them.**

| Bucket | Files | Decision |
|---|---|---|
| raylib modules | `rcore.c`, `rshapes.c`, `rtextures.c`, `rtext.c`, `rmodels.c`, `raudio.c`, `raymath.h`, `rlgl.h`, `rcamera.h`, `rgestures.h` | **PORT** to `src/*.zig` |
| platform backend | `platforms/rcore_desktop_glfw.c` (Linux first) | **PORT** (one backend; others deferred) |
| third-party `external/` | stb_*, miniaudio, dr_*, cgltf, par_shapes, m3d, qoi/qoa, glad, rlsw, jar_* | **LINK as C** (`@cImport`/`addCSourceFile`); never hand-port |
| GLFW / RGFW / SDL | `external/glfw/`, `rglfw.c`, … | **LINK as C** (huge windowing libs; out of scope) |
| other platform backends | `platforms/rcore_{sdl,rgfw,win32,drm,web,android}.c` | **DEFER** (not compiled in the Linux/GLFW build) |

A "100% Zig raylib" means every *raylib-authored* module is Zig, with the
bundled third-party libs still linked as C — exactly as sqlite-zig is "pure Zig"
with the Lemon-generated `parse.c` still C.

## ⚠️ The central difference from sqlite-zig: there is no test-suite oracle

SQLite shipped millions of TCL assertions; "the test suite is the spec" made the
port safe. **raylib has no comprehensive automated test suite.** Its validation
surface is **218 visual example programs** (`examples/`) a human eyeballs. We
cannot eyeball every commit. So we manufacture an oracle:

1. **Software-renderer pixel diff (primary gate).** raylib bundles
   `external/rlsw.h`, a software OpenGL 1.1 rasterizer (`GRAPHICS_API_OPENGL_11`
   + `RLSW_IMPLEMENTATION`). Built against it, raylib renders **headlessly and
   deterministically** to a CPU framebuffer — no GPU, no driver nondeterminism.
   For any workload, render once with pure-C raylib and once with Zig-ported
   modules linked in, read back the framebuffer, and compare **byte-for-byte**.
   This is our `make devtest`. Stand it up in Phase 0 before porting anything.
2. **Numeric differential for `raymath`.** Pure math functions: diff Zig vs C
   outputs over a large input grid to ULP tolerance. No rendering needed.
3. **Examples as functional tests.** Drive the `examples/*.c` programs (which
   call the public API) through the software renderer, screenshot to PNG via
   `TakeScreenshot`, and diff against a golden PNG captured from pure-C raylib.
4. **Real-GPU spot check.** Periodically run a few examples on the real GLFW +
   OpenGL 3.3 desktop backend to confirm the software-renderer path didn't mask
   a GPU-state bug. GPU output is not bit-deterministic, so this is a human/loose
   check, not the gate.

**A port is "done" only when the pixel/numeric diff against pure-C raylib is
clean.** Never mark a step complete without it, and report the actual diff
result. If you cannot build the software-renderer oracle, STOP and flag it — the
whole migration's safety rests on it.

## Core strategy (see plan.md for detail)

Same incremental, never-big-bang approach that worked for sqlite-zig:

1. Stand up a Zig build that compiles **unmodified** upstream raylib C (the
   official `build.zig` already compiles per-TU via `addCSourceFile`), producing
   a working library + the software-renderer pixel-diff harness. Safety net from
   day one.
2. Port module-by-module, keeping the **C ABI** at every boundary (`export`
   the same `RLAPI`/`RMAPI` symbols `raylib.h` declares) so ported-Zig and
   not-yet-ported-C modules coexist in one binary.
3. After every port, run the pixel/numeric diff. **The diff vs pure-C is the
   spec.**
4. Port bottom-up: `raymath` (pure, no deps) → `rlgl` (GL state) → `rshapes`/
   `rtextures`/`rtext` → `rcore` (+ glfw platform) → `rmodels`/`raudio` (heaviest
   third-party coupling, last).

## raylib-specific gotchas (seed the checklist — grows as bugs are found)

These are the raylib analogs of sqlite-zig's hard-won gotcha list. Verify each
before claiming a module done.

- **Global state structs must be ABI-exact while half-ported.** `CoreData CORE`
  (rcore.c:399) and `static rlglData RLGL` (rlgl.h:1149) are read across module
  boundaries. Mirror them with `extern struct` and assert every `@offsetOf`/
  `@sizeOf` against C ground truth (`tools/offsets.c` → `src/c_layout.zig`,
  copied from sqlite-zig). `RLGL` is `static` (TU-local) — only `rlgl`'s own Zig
  port touches it, but its layout still must match anything inlined from rlgl.h.
- **Header-only `static inline` functions.** `raymath.h`/`rlgl.h`/`rcamera.h`/
  `rgestures.h` define functions inline (`RMAPI = static inline` by default), so
  C callers **inline** them rather than calling an exported symbol. To swap them,
  build raylib with these as **out-of-line** symbols (raylib supports a
  non-inline build mode) so there is a real symbol to replace; otherwise a Zig
  port has nothing to override. Decide this in Phase 0 — flagged in plan.md.
- **Backend/platform config divergence (multi-axis).** Behavior and struct
  layout vary across `PLATFORM_DESKTOP_GLFW/_SDL/_RGFW/DRM/WEB/ANDROID` ×
  `GRAPHICS_API_OPENGL_11/21/33/43/ES2/ES3` × the `src/config.h` feature flags
  (`SUPPORT_*`). Like sqlite-zig's prod-vs-`--dev` dual build, a single Zig
  object can't satisfy two configs at once. Pin ONE config first
  (PLATFORM_DESKTOP_GLFW + OPENGL_33 on Linux, default `config.h`); mirror the
  chosen flags as a Zig `comptime` `config` module.
- **`Color` is 4×`u8` packed; `Vector*`/`Matrix` are `f32`.** Match field types
  and struct packing exactly; raylib passes these **by value** across the ABI
  (e.g. `DrawRectangle(..., Color)`), which is calling-convention-sensitive for
  small structs — verify aggregate-by-value lowering matches C.
- **Float bit-exactness.** Pixel diffs are byte-exact, so math must match C.
  Watch FMA/contraction, `-ffast-math` assumptions, and `sinf/cosf` libm calls
  (call the same libm, don't reimplement). raymath uses `float`; keep `f32`.
- **Carry the sqlite-zig checklist too** — ABI return-register width (a function
  returning `u8`/`i16`/`bool` declared `c_int` by callers leaks garbage upper
  bits), `@truncate` vs `@intCast` for C truncating casts, `@memmove` for
  overlapping copies, inline-array-vs-pointer, re-probe every enum/flag constant
  against the header. See `docs/migration-workflow.md` in sqlite-zig.

## Conventions

- raylib is **zlib/libpng licensed** (not public domain). Preserve the upstream
  license/attribution header when copying structure from a file; do not relicense.
- **The bar: Zig as if written by Andrew Kelley, design as if by Raysan.**
  Two standards held at once:
  - **Code idiom — Andrew Kelley's Zig** (Zig's creator): the implementation
    should look like it belongs in the Zig standard library — minimal, explicit,
    no hidden control flow, no hidden allocations, communicate intent, handle
    every error, no clever tricks. If a Zig core-team reviewer would frown at it,
    rewrite it. This is the ceiling for *how* the code is written.
  - **Design / API — Raysan's raylib** (Ramón Santamaría, raylib's creator):
    preserve raylib's design ethos — simple, consistent, beginner-friendly,
    self-explanatory function names (`InitWindow`, `BeginDrawing`, `DrawTextureEx`),
    values over handles, sane defaults, no required boilerplate, "no dependencies"
    feel. The public surface stays the raylib people know and love. Do **not**
    redesign the API while porting; a separate idiomatic-Zig API layer (Phase 6)
    may come later, but the C-ABI surface keeps Raysan's shape exactly.
- **Write clean, idiomatic Zig — this is a hard requirement, not a nice-to-have.**
  The output must read like Zig a Zig programmer would write, **not** a C program
  transliterated into Zig syntax. That means: error unions / `error{...}` instead
  of sentinel returns and out-params; `std.mem.Allocator` instead of raw
  malloc/free; slices (`[]T`, `[]const u8`) instead of ptr+len pairs; `comptime`
  and `const` config instead of `#define`/`#ifdef`; tagged `union(enum)` and real
  `enum`s instead of int constants; `defer`/`errdefer` for cleanup instead of
  `goto cleanup`; `for`/`while` with captures instead of index bookkeeping;
  `std.math`/`std.mem`/`std.fmt` instead of hand-rolled C helpers. Run `zig fmt`;
  keep functions small; name things in Zig style (`camelCase` fns, `TitleCase`
  types). **The one allowed concession is at ABI boundaries** that must stay
  C-compatible — the public `raylib.h` surface, `CoreData`/`rlglData` layout, the
  exported `RLAPI`/`RMAPI` symbols, and by-value struct args. There, use
  `extern struct`/`export`/exact C types as needed, and isolate that ugliness to
  a thin boundary layer so the *internals* stay idiomatic. Idiomatic Zig and a
  byte-exact ABI are not in tension when the C-shaped parts are confined to the
  edge. A clean diff vs C does **not** justify ugly code — correctness is gated by
  the pixel/numeric diff, readability by this rule; both must hold.
- Keep [plan.md](plan.md) and `PROGRESS.md` (create when porting starts) updated
  as the living source of truth. Check off steps as they land; record deviations.

## Token tracking (required)

[tokens.txt](tokens.txt) records **actual** per-prompt token usage — real API
figures (input + cache creation + cache read + output) with real start/end
times, **not** chars/4 estimates — parsed from the Claude Code session
transcript by [tools/token_usage.py](tools/token_usage.py):

```bash
python3 tools/token_usage.py          # human-readable table
python3 tools/token_usage.py --tsv    # machine-readable (for tokens.txt)
```

The script reads the newest `*.jsonl` in
`/home/rajesh/.claude/projects/-home-rajesh-lab-ai-port-raylib-zig/` — it is
session-specific. A "turn" = one human prompt + all assistant work it triggered;
`cache_read` dominates (context re-read each step). Follow-ups sent mid-turn fold
into that turn; list them under it.

### Record at EVERY pause / stop (required)

Don't wait only for "end of session." **Any time you pause, hand back control, or
are temporarily done and about to stop, take a measurement first:**

1. **Time** — note the wall-clock start→end of the work since the last record
   (and the elapsed duration). For a long autonomous run, also note turns elapsed.
2. **Tokens** — run `python3 tools/token_usage.py` and append/refresh the
   relevant rows in [tokens.txt](tokens.txt) (input + cache_cr + cache_rd + output
   → TOTAL, plus the running cumulative).
3. **What landed** — a one-line note of what was done in that span (which module,
   what gate passed), so the log doubles as a progress trail.

Caveat: the transcript only records a turn's **full** cost once that turn
completes, so the **in-progress** turn (the one you're stopping in) can't be
fully self-counted — record it as `(in progress)` with the figures through the
last recorded step, and capture its tail at the next pause/session. Everything
already-completed since the last record IS countable now — log it before you stop.

[token-count.md](token-count.md) is the separate **scope-sizing** number (how big
the porting job is: LOC/bytes of the raylib C we port), distinct from per-prompt
LLM usage.

## Build (this project)

Not yet scaffolded. Phase 0 stands up: a Zig build of unmodified upstream raylib
C (per-TU, swap-ready) + the software-renderer pixel-diff harness + the
`ported_modules` swap list (empty → 100% C baseline). See [plan.md](plan.md) for
the staged approach and the open decisions to resolve before committing to a
build shape.
