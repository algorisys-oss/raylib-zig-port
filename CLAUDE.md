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

Validate agains: LOOP.md for essential checklist/processes

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

Status: all 10 modules are ported (100% of raylib-authored code is Zig) and
tracking **raylib 6.2**; see [PROGRESS.md](PROGRESS.md) for gate results and
[handoff.md](handoff.md) for the current resume point.

This is the sibling of the completed **sqlite-zig** migration
(`/home/rajesh/lab/ai-port/sqlite-zig`). We reuse its proven playbook —
per-translation-unit C→Zig swap, C-ABI-preserving boundaries, ground-truth
struct-offset tooling, agent-parallelized drafting with serial verification, and
per-prompt token logging. **Read the differences section below first: raylib's
correctness oracle is fundamentally different from SQLite's.**

## Reference sources (read-only — never edit)

| What | Path | Notes |
|---|---|---|
| raylib C source | `/home/rajesh/opensource/graphics/raylib-6.2` | **v6.2** (tag `6.2`, git `02566453`) — the current port target since 2026-10-16. zlib/libpng license. Uses **Git**. |
| raylib C source (previous) | `/home/rajesh/opensource/graphics/raylib` | v6.1-dev (git `6.0-178-g67359073`) — the original port target; kept for diffing old→new. |
| Zig compiler/stdlib | `/home/rajesh/opensource/ziglang/zig` | Build/run toolchain reference (`src/`). |
| Zig toolchain in PATH | `zig` (`~/.asdf/shims/zig`) | `0.18.0-dev.246+05671ced9` (moved from 0.17.0-dev.644 on 2026-10-16; build.zig ported — Optimize is now optional, Zig objects must set link_libc). |
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
port safe. **raylib has no comprehensive automated test suite** — no unit tests,
no assertion harness; upstream CI merely *builds* the examples. Its de facto test
suite *is* its **example programs** (`examples/`; 217 in 6.1-dev, 227 in 6.2), normally eyeballed by a
human. We cannot eyeball every commit, and the user's bar is explicit: **the port
must pass all the original raylib test cases — i.e. all the examples.** So we
manufacture an automatable oracle that turns "the examples" into a hard gate:

1. **Software-renderer pixel diff (primary gate).** raylib bundles
   `external/rlsw.h`, a software OpenGL 1.1 rasterizer (`GRAPHICS_API_OPENGL_11`
   + `RLSW_IMPLEMENTATION`). Built against it, raylib renders **headlessly and
   deterministically** to a CPU framebuffer — no GPU, no driver nondeterminism.
   For any workload, render once with pure-C raylib and once with Zig-ported
   modules linked in, read back the framebuffer, and compare **byte-for-byte**.
   This is our `make devtest`. Stand it up in Phase 0 before porting anything.
2. **Numeric differential for `raymath`.** Pure math functions: diff Zig vs C
   outputs over a large input grid to ULP tolerance. No rendering needed.
3. **Examples as the acceptance suite (all of them — these ARE raylib's test cases).**
   Drive every `examples/*.c` program (which calls the public API) through the
   software renderer, screenshot to PNG via `TakeScreenshot`, and diff against a
   golden PNG captured from pure-C raylib. An example "passes" when it builds,
   links against the Zig library, and pixel-matches. **100% done = every example passes or is excluded with a logged reason**
   (build + diff); audio examples diff on decoded PCM instead of pixels. Track the
   pass count in PROGRESS.md. No example skipped silently — log any that can't
   pass, with the reason, in `docs/not-migrated.md`.
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
- **Result-location aliasing when translating C compound-literal assignment.**
  (Found the hard way: rmodels' `DrawSphereEx` — sphere rendered as nothing.)
  C's `v[2] = (Vector3){ f(v[2].x), v[2].y, g(v[2].x) }` evaluates the literal
  into a temporary, then stores. Zig's `v[2] = .{ .x = ..., .z = ... }` uses
  `v[2]` itself as the result location — later field initializers read fields
  the earlier ones already overwrote. Any C assignment whose RHS literal reads
  the LHS must snapshot first (`const old = v[2];`) in Zig. Sweep every drafted
  module for `X = .{ ... X.field ... }` (single- AND multi-line) before gating.
- **Callback-before-cache when wrapping C globals behind opaque pointers.**
  (Found the hard way: raudio's device callback — NaN audio, UBSan abort.) When
  a port caches C-struct properties (instead of reading them live through the
  pointer like C does), any callback that can fire DURING setup reads the
  not-yet-cached values. `ma_device_start` invokes the data callback
  synchronously (pulse primes its stream); the callback sized its memset from
  fields cached only after start → zero-byte memset → uninitialized output.
  Rule: cache every property a callback reads BEFORE the call that can first
  trigger the callback, and audit each cached-instead-of-live field for "who
  reads this, and can they run before it's set?"
- **Casts C performs freely must stay lazy in Zig.** (Three finds from the
  examples gate, 2026-07-04.) (a) C casts NULL to `unsigned char *` and never
  dereferences it (zero-trip loops guard it) — a Zig `@ptrCast` to non-optional
  `[*]u8` panics at the cast; use `?[*]u8` and unwrap inside the loop. (b) C
  declares `u16*`/`f32*` views inside the switch arm that uses them — hoisting
  them above the switch as eager `@alignCast` traps when the pointer is a
  byte-offset into 1-byte-per-pixel data. (c) C's `(float)((count-1)*spacing)`
  with float `spacing` is an int*float FLOAT multiply (the cast is a no-op) —
  translating it as an int truncation of `spacing` silently zeroes the term for
  fractional spacings. Rule: replicate WHERE C casts, not just what it casts to.
- **Hand-mirrored enum constants drift — audit them mechanically.** (Found by
  the examples gate: rcore.zig's ShaderLocationIndex mirror had the last four
  entries shifted +1 vs raylib.h; LoadShader wrote auto-bound attrib locations
  at the wrong indices while rmodels read the right ones — ALL GPU instancing
  silently rendered nothing.) Every module keeps private copies of raylib.h
  enums; two modules can each look plausible and still disagree. After any
  module lands, run `python3 tools/constaudit.py` (enums, numeric AND string
  #defines, bool-mirrored config flags vs every `const NAME = …` in
  src/*.zig). Limitation: a name C defines per-#if branch (e.g.
  MAX_MESH_VERTEX_BUFFERS 7/9 by SUPPORT_GPU_SKINNING) passes if it matches
  ANY branch — check config-dependent values by hand when a flag flips.
- **The examples gate only sees what an example renders unattended.** (6.2
  rebase: rtext's FONT_SDF glyph generation was never ported — text_font_sdf
  draws SDF text only while SPACE is held; rshapes' new thickness/angle paths
  are reached only through UI sliders.) Any branch an example reaches only via
  input needs its own direct C-vs-Zig differential (small C driver linked
  against both libs, byte-compare output). Likewise the math grid had never
  covered QuaternionFromVector3ToVector3/MatrixCompose/MatrixDecompose — when a
  function changes upstream, first confirm a gate actually exercises it
  (negative control: the OLD port must fail the gate).
- **`@intFromFloat` is not C's `(int)`.** On x86-64 C's cast yields INT_MIN for
  NaN/out-of-range and raylib's `if (segments <= 0)` fallbacks rely on it (tiny
  radii push `acosf` out of domain → NaN); Zig traps. Use a checked helper
  (rshapes `cInt`) wherever the float can be NaN or huge.
- **Signedness changes in C struct fields ripple into every implicit
  conversion.** (6.2: Model/ModelAnimation `boneCount` int → unsigned int.) C
  silently converts back to int at each use; Zig needs an explicit `@bitCast`
  there, and `size_t` → field narrowing needs `@truncate`, not `@intCast`.
- **Example compile flags must mirror upstream's Makefile.** The gate omitted
  `-DPLATFORM_DESKTOP`, so shader examples loaded their GLSL 100 (ES) shaders —
  passing, but on a configuration desktop raylib never runs. Upstream passes
  `-DPLATFORM_DESKTOP -I src/external`; so does tools/exdiff.sh now.
- **`std.testing.refAllDecls` never analyzes generic (`anytype`/`comptime`)
  functions.** The Zig API's `textFormat`/`traceLog` didn't compile on 0.18
  (`std.fmt.bufPrintZ` removed) while apitest stayed green. Instantiate every
  generic wrapper explicitly in a test.
- **`std.fmt` is not printf.** `{d:0>2}` on a *signed* int prints `+6` (printf
  `%02i` → `06`); float ties round differently (`{d:.2}` of 0.125 → `0.13`,
  printf → `0.12`). Zig-API example translations format unsigned/abs values or
  avoid exact ties when output must match C byte-for-byte.
- **Generator edits merged from parallel branches can duplicate silently.** Two
  branches adding the same Python table/constant merge "cleanly" into two
  definitions (the later wins) or two emitted decls. After every merge of
  tools/gen_api.py: grep for duplicate top-level names and regenerate.
- **Audio-driven examples are timing-sensitive under load.** Before calling an
  audio example a port failure, run it C-vs-C (`exdiff.sh <oracle> <oracle>`)
  several times; exclude it only if C disagrees with itself.
- **FMA contraction is real, and the scene battery can miss it.** Confirmed:
  clang fuses `a*b + c` (rlVertex3f's transform multiply) while Zig never
  contracts — visible only when the transform has non-zero off-diagonals
  (rotation), which the original scene battery never exercised. All C in this
  repo now compiles `-ffp-contract=off` (build.zig c_defines); keep it.
- **Hand-declared libc types are Linux x86-64 types.** (Found by the web
  target, 2026-10-16.) rcore.zig declared `time()` as returning `c_long`; on
  x86-64 that equals `time_t`, on wasm32 `c_long` is 32-bit and `time_t`
  64-bit, and wasm-ld produced invalid wasm (Binaryen: "local.set's value type
  must be correct" in InitWindow). Use `std.c` types (`time_t`, `timespec`,
  `dirent`, `Stat` where it exists) for anything libc defines per OS; when a
  wasm link fails validation, relink with `--profiling-funcs` to get names.
- **No `std.heap.page_allocator` in code that runs on the web.** On wasm it
  grows memory behind Emscripten's back (stale JS heap views, WebGL errors,
  "detached ArrayBuffer"). Zig-API examples use `std.heap.c_allocator`. The
  same `time_t` rule applies to examples' own libc declarations (docs/web.md).
- **Zig `extern` decls must match the C prototype (float is `f32`).** x86-64
  tolerates a mismatch silently; wasm-ld turns the call into a trap. The web
  link runs with `-Wl,--fatal-warnings` to catch it (docs/web.md).
- **Forwarding `...` to vprintf: `&ap` is x86-64 only.** C's `va_list` is an
  array on x86-64 (decays to a pointer) and a plain pointer on wasm32. Passing
  `&ap` everywhere made TraceLog/TextFormat format stack garbage on the web,
  and crashed the tab in ReleaseFast. Use `c_va.arg(&ap)` (src/c_va.zig).
- **The gates prove behaviour, not idiom.** (External review, 2026-10-16: the
  first-pass modules were "C with Zig keywords" — ~980 libc/raw-alloc calls,
  no `Allocator`, almost no `defer` — while every gate was green.) Idiom is now
  enforced by `tools/idiomaudit.py` (a ratchet: counts per file may only go
  down). Pattern for every cleanup: a std-only file (`src/fs.zig`) with
  slices/error unions/`Io`/`Allocator` and its own leak-checked tests, plus
  thin `export fn` wrappers in the module; write the cdiff driver FIRST and
  see it pass against the old code. Lessons: docs/idioms.md. Zig 0.18 notes
  from that work: `**` array repetition is gone (use `@splat`); a multiline
  `\\` literal's last line has no trailing newline; an `anytype` visitor from
  another file needs `pub` decls; `zig fmt` strips trailing spaces inside
  `\\` lines (use a plain string when they matter).
- **Never `Allocator.free` memory a C caller hands back.** Its length comes
  from a caller-mutable struct field, and safe builds write over that many
  bytes. Memory crossing the C ABI goes through `src/cmem.zig` (alloc/realloc/
  free on the C heap); scratch memory uses an `Allocator` with `defer`.
- **"Same libm" is a link-time accident unless pinned.** (Found 2026-10-16:
  models_data diverged only in ReleaseFast.) compiler_rt is ONE archive member
  that also defines weak sinf/cosf/expf/...; once anything pulls it in (Zig
  code always does) its math replaces glibc's. A pure-C oracle pulled it in at
  Debug but not at ReleaseFast, so the gate compared two libms. Every gate exe
  forces `__multi3` (build.zig `pinCompilerRtMath`, exdiff.sh `-Wl,-u,__multi3`).
  New gate executables must go through `linkExe` or do the same.
- **Keep the process clock on libc.** tools/exdiff/fakeclock.c freezes time by
  preloading libc `clock_gettime`/`time`; a std.Io clock that skips libc would
  make the examples gate nondeterministic.
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

## handoff.md (required after every run)

At the end of **every run** — any pause, stop, or hand-back of control — write
(overwrite, don't append) `handoff.md` at the repo root. It is the fresh-session
bootstrap: a new agent should be able to read handoff.md alone and resume
correctly. Keep it short and current; PROGRESS.md stays the long-lived history.
Contents:

1. **State right now** — last green commit/tag, gate result (e.g. `12/12`),
   modules ported vs remaining, anything uncommitted.
2. **What this run did** — the few bullets of what landed since the previous
   handoff.
3. **Next step** — the single first action to take on resume, then the ordered
   short list after it.
4. **Open issues / gotchas hit** — anything in-flight, half-debugged, or
   surprising (also fold durable ones into the CLAUDE.md gotcha list).

Do this **in addition to** the token/time record above — same trigger, both
required.

## Build (this project)

```bash
zig build                      # libraylib.a (Zig-swapped) + all-C oracle lib
zig build test                 # 12 pixel scenes, C vs Zig (llvmpipe)
zig build mathtest camtest gesttest datacheck audiocheck   # numeric/data/PCM gates
python3 tools/constaudit.py    # mirrored-constant audit
python3 tools/idiomaudit.py    # C-idiom ratchet (libc calls, [*c]); counts only go down
tools/exdiff.sh <oracle.a> zig-out/lib/libraylib.a [filter]  # examples gate
```

Web target (docs/web.md; needs emsdk, and `npm install` in tools/webdiff once):

```bash
zig build web -Demsdk=$HOME/emsdk           # wasm32-emscripten libraylib.a + rcore_web.js
zig build webexamples -Demsdk=$HOME/emsdk   # browser gate: C vs Zig in headless Chrome
```

The oracle archive lives in the zig cache:
`find .zig-cache ~/.cache/zig-local -name libraylib_oracle.a` (newest). The web
build makes a wasm archive of the same name: the desktop one is the archive
whose `ar t` lists `rglfw.o`. When
several builds run concurrently (e.g. agent worktrees), pass a private
`--cache-dir` to avoid shared-cache link races. Vendored C (vendor/raylib/src)
is raylib 6.2 + one local patch (see vendor/README.md).
