# raylib-zig

A from-scratch **migration of [raylib](https://www.raylib.com/) from C to Zig** —
a Zig implementation of the raylib game/graphics library that is behaviorally
compatible with upstream raylib: same public C ABI (`raylib.h`), same on-screen
output, so existing raylib programs link and render identically.

This is the sibling of the completed **sqlite-zig** migration and reuses its
proven playbook: per-translation-unit C→Zig swap, C-ABI-preserving boundaries,
ground-truth struct-offset tooling, parallel drafting with serial verification,
and per-prompt token logging.

> **Status (2026-07-04): all 10 raylib modules are ported — 100% of
> raylib-authored C is Zig** for the pinned Linux/GLFW/OpenGL 3.3 target
> (bundled third-party libs in `external/` stay linked C, by design). Gates:
> 12/12 scene pixel-diff, 43/43 audio PCM-diff, bit-exact math/camera/gesture
> grids, and the upstream-examples acceptance suite (first batch, 2D categories).
> Live status: [PROGRESS.md](PROGRESS.md); resume notes: [handoff.md](handoff.md).

## Build & run

```bash
zig build                  # build libraylib.a (Zig-swapped) + demo runners
zig build test             # the migration gate: C-vs-Zig scene pixel diff (llvmpipe)
zig build audiocheck       # the raudio gate: C-vs-Zig decode/PCM diff
zig build datacheck        # rcore data functions vs known vectors
zig build angrybirds       # play the Angry Birds capstone demo (X11 window)
```

The **Angry Birds demo** ([examples/angrybirds/](examples/angrybirds/)) is a
complete slingshot game written in idiomatic Zig against the ported library —
drag with the left mouse button and release to fire, `R` restarts, `SPACE`
advances after a level clear. See its [README](examples/angrybirds/README.md)
for the headless self-test mode.

- **Porting:** raylib **v6.2** (`/home/rajesh/opensource/graphics/raylib-6.2`, tag
  `6.2`, git `02566453`) — rebased from 6.1-dev on 2026-10-16
- **Toolchain:** Zig `0.18.0-dev.246+05671ced9`
- **Status:** 10/10 modules Zig; examples gate **220/220** byte-identical vs
  pure-C raylib 6.2 (7 excluded with reasons — all 227 accounted for)
- **License:** zlib/libpng (same as upstream raylib)

## Using raylib from Zig

Besides the unchanged C ABI (`raylib.h` programs link as-is), the build
exports an idiomatic Zig API as the `raylib` module — raylib's functions and
names, first letter lower-cased, with Zig types where C is weak
([docs/zig-api.md](docs/zig-api.md)):

```zig
const rl = @import("raylib");

pub fn main() !void {
    rl.initWindow(800, 450, "raylib [core] example - basic window");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    const logo = try rl.loadTexture("resources/raylib_logo.png");
    defer rl.unloadTexture(logo);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.ray_white);
        rl.drawTexture(logo, 10, 10, .white);
    }
}
```

raymath is `rl.math`, rlgl is `rl.gl`. 181 upstream examples are translated
in [examples/zig/](examples/zig/), each gated to render byte-identical to the
original C example (`zig build apiexamples`).

## Goal

**100% port** of all raylib-authored C to Zig — all 6 `.c` modules, all 4
header-only modules, and the platform backend. "Done" means no raylib-authored C
remains in the build, the code is clean idiomatic Zig, and **every upstream
example passes** (or is excluded with a logged reason).

Two deliberate, intended **exceptions** (linked as C, not ported — the raylib
analog of sqlite-zig keeping the generated `parse.c` as C):

1. **Bundled third-party libraries in `src/external/`** — stb_*, miniaudio,
   dr_*, cgltf, par_shapes, m3d, qoi/qoa, glad, rlsw, GLFW. These are vendored
   upstream single-file libs, not raylib; we link them.
2. **Platform/GL backends outside the first target** — SDL/RGFW/Win32/DRM/Web/
   Android and the OPENGL 11/21/43/ES2/ES3 paths. Portable in principle, deferred,
   not excluded. The first milestone is 100% for **Linux + GLFW + OpenGL 3.3**.

## The quality bar

- **Code idiom — Zig as if written by Andrew Kelley** (Zig's creator): reads like
  the Zig standard library — minimal, explicit, no hidden control flow or
  allocations, every error handled. Not C transliterated into Zig syntax.
- **Design — API as if by Raysan** (Ramón Santamaría, raylib's creator): the
  public surface keeps raylib's simple, consistent, beginner-friendly shape
  unchanged. C-shaped ABI code is confined to a thin boundary layer so internals
  stay idiomatic.

## How it will work

raylib's hand-written core is small (~38k LOC; ~408k tokens — roughly 1/5 of
sqlite's core). The migration is **incremental, never big-bang**:

1. Stand up a Zig build of **unmodified** upstream raylib C (the official
   `build.zig` already compiles per-TU), producing a working library plus the
   validation harness — the safety net, from day one.
2. Port module-by-module, keeping the **C ABI** at every boundary (`export` the
   same `RLAPI`/`RMAPI` symbols `raylib.h` declares) so ported-Zig and
   not-yet-ported-C modules coexist in one binary.
3. After every port, run the pixel/numeric diff against pure-C raylib.
4. Port bottom-up: `raymath` → `rlgl` → `rshapes`/`rtextures`/`rtext` → `rcore` +
   GLFW platform → `rmodels`/`raudio`.

See [plan.md](plan.md) for the full phased roadmap and the open decisions to
resolve in Phase 0.

## How correctness is established (the manufactured oracle)

**raylib ships no assertion/unit test suite** — upstream CI only *builds* the
examples. Its de facto test cases are its **example programs** (227 in 6.2). Since we
can't eyeball every commit, we manufacture an automatable oracle:

1. **Numeric diff (`raymath`)** — pure functions diffed Zig-vs-C over a large
   input grid to ULP tolerance. No rendering. The first, simplest gate.
2. **Software-renderer pixel diff (primary gate)** — raylib bundles
   `external/rlsw.h`, a software OpenGL 1.1 rasterizer. Built against it, raylib
   renders **headlessly and deterministically** to a CPU framebuffer. Render a
   workload through pure-C and Zig-swapped builds, read back the framebuffer, and
   compare **byte-for-byte**.
3. **Example acceptance suite (all of them)** — drive each `examples/*.c` through the
   software renderer, `TakeScreenshot` to PNG, and diff against a golden captured
   from pure-C raylib. **100% done = every example builds, links, and pixel-matches**
   (audio examples diffed on decoded PCM instead of pixels).
4. **Real-GPU spot check** — periodically run examples on real GLFW + OpenGL 3.3
   to catch anything the software path masks. GPU output isn't bit-deterministic,
   so this is a loose check, not the gate.

**A port is "done" only when the diff against pure-C raylib is clean.** The
software-renderer oracle being faithful and deterministic is the Phase-0 linchpin
— the whole migration's safety rests on it.

## Scope: what we port vs. link

| Bucket | Files | Decision |
|---|---|---|
| raylib modules | `rcore.c`, `rshapes.c`, `rtextures.c`, `rtext.c`, `rmodels.c`, `raudio.c`, `raymath.h`, `rlgl.h`, `rcamera.h`, `rgestures.h` | **PORT** to `src/*.zig` |
| platform backend | `platforms/rcore_desktop_glfw.c` (Linux first) | **PORT** (one backend) |
| third-party `external/` | stb_*, miniaudio, dr_*, cgltf, par_shapes, m3d, qoi/qoa, glad, rlsw, GLFW | **LINK as C** — never hand-port |
| other backends / GL paths | `rcore_{sdl,rgfw,win32,drm,web,android}.c`, ES2/ES3 | **DEFER** |

See [token-count.md](token-count.md) for the per-module size breakdown.

## Token & time tracking

This migration logs its own cost. [tokens.txt](tokens.txt) records **actual**
per-prompt token usage (real API figures — input + cache creation + cache read +
output — not chars/4 estimates), parsed from the Claude Code session transcript:

```bash
python3 tools/token_usage.py          # human-readable table
python3 tools/token_usage.py --tsv    # machine-readable (for tokens.txt)
```

Time and tokens are recorded at **every pause/stop**, not just session end (see
the rule in [CLAUDE.md](CLAUDE.md)). [token-count.md](token-count.md) is the
separate scope-sizing number (LOC/tokens of the raylib C we port).

## Repository layout

```
CLAUDE.md            Working guidance: architecture, port/link boundary,
                     conventions, the quality bar, gotchas, token protocol.
plan.md              Living migration plan — phases, decisions, risks, progress.
token-count.md       Scope sizing: LOC/tokens of the raylib C we port.
tokens.txt           Actual per-prompt LLM token usage (real API figures).
tools/token_usage.py Parser that produces tokens.txt from the session transcript.
README.md            This file.

# created when porting starts:
PROGRESS.md          Authoritative live status + resume guide + example pass count.
docs/                architecture / testing / migration-workflow / not-migrated.
build.zig            Zig build with the per-module C↔Zig swap list.
src/*.zig            The ported modules.
```

## Reference sources (read-only)

| What | Path | Notes |
|---|---|---|
| raylib C source | `/home/rajesh/opensource/graphics/raylib-6.2` | v6.2 (current target). zlib license. |
| raylib C source (previous) | `/home/rajesh/opensource/graphics/raylib` | v6.1-dev (original target). |
| Zig compiler/stdlib | `/home/rajesh/opensource/ziglang/zig` | Toolchain reference. |
| sqlite-zig (sibling) | `/home/rajesh/lab/ai-port/sqlite-zig` | The completed migration whose playbook this copies. |

## License

This project follows upstream raylib's **zlib/libpng** license. Upstream
attribution headers are preserved when porting structure from a file; the port is
not relicensed.
