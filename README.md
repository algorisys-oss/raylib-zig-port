# raylib-zig

A from-scratch **migration of [raylib](https://www.raylib.com/) from C to Zig** —
a Zig implementation of the raylib game/graphics library that is behaviorally
compatible with upstream raylib: same public C ABI (`raylib.h`), same on-screen
output, so existing raylib programs link and render identically.

This is the sibling of the completed **sqlite-zig** migration and reuses its
proven playbook: per-translation-unit C→Zig swap, C-ABI-preserving boundaries,
ground-truth struct-offset tooling, parallel drafting with serial verification,
and per-prompt token logging.

> **Status: planning only — no code yet.** This repository currently holds the
> migration plan and conventions. Implementation has not started. See
> [plan.md](plan.md) for the staged approach and [CLAUDE.md](CLAUDE.md) for the
> working guidance. This README will grow build/run instructions as Phase 0 lands.

- **Porting:** raylib v6.1-dev (`/home/rajesh/opensource/graphics/raylib`, git
  `6.0-178`)
- **Toolchain:** Zig `0.17.0-dev.644+3de725074`
- **License:** zlib/libpng (same as upstream raylib)

## Goal

**100% port** of all raylib-authored C to Zig — all 6 `.c` modules, all 4
header-only modules, and the platform backend. "Done" means no raylib-authored C
remains in the build, the code is clean idiomatic Zig, and **all 218 upstream
examples pass**.

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
examples. Its de facto test cases are its **218 example programs**. Since we
can't eyeball every commit, we manufacture an automatable oracle:

1. **Numeric diff (`raymath`)** — pure functions diffed Zig-vs-C over a large
   input grid to ULP tolerance. No rendering. The first, simplest gate.
2. **Software-renderer pixel diff (primary gate)** — raylib bundles
   `external/rlsw.h`, a software OpenGL 1.1 rasterizer. Built against it, raylib
   renders **headlessly and deterministically** to a CPU framebuffer. Render a
   workload through pure-C and Zig-swapped builds, read back the framebuffer, and
   compare **byte-for-byte**.
3. **Example acceptance suite (all 218)** — drive each `examples/*.c` through the
   software renderer, `TakeScreenshot` to PNG, and diff against a golden captured
   from pure-C raylib. **100% done = all 218 build, link, and pixel-match**
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
| raylib C source | `/home/rajesh/opensource/graphics/raylib` | v6.1-dev. zlib license. |
| Zig compiler/stdlib | `/home/rajesh/opensource/ziglang/zig` | Toolchain reference. |
| sqlite-zig (sibling) | `/home/rajesh/lab/ai-port/sqlite-zig` | The completed migration whose playbook this copies. |

## License

This project follows upstream raylib's **zlib/libpng** license. Upstream
attribution headers are preserved when porting structure from a file; the port is
not relicensed.
