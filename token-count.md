# token-count.md — migration scope sizing

Size of the **raylib-authored** C source we are porting (the "how big is this
job" number). Distinct from [tokens.txt](tokens.txt), which logs per-prompt LLM
token usage for this project.

- Source: raylib v6.1-dev, `/home/rajesh/opensource/graphics/raylib/src`
  (git `6.0-178-g67359073`)
- **Excludes `src/external/`** (~13 MB of bundled third-party single-file libs —
  stb, miniaudio, dr_*, cgltf, glfw, glad, rlsw, …) which we **link, not port**.
  See the boundary in [CLAUDE.md](CLAUDE.md) / [plan.md](plan.md).

## Modules we port (top-level `src/*.c` + header-only `*.h`)

- Lines of code: **~38,060** across the 10 modules below + 1 platform backend
- Estimated tokens (~4 chars/token over source bytes): **~408k tokens**
  (order-of-magnitude scope). For comparison, sqlite-zig's core was ~1.9M tokens
  — raylib's hand-written core is roughly **1/5** the size.

| LOC | File | Notes |
|---|---|---|
| 7334 | src/rmodels.c | 3D meshes/models/materials (wraps cgltf/par_shapes/m3d) |
| 5627 | src/rtextures.c | image/texture (wraps stb_image/qoi) |
| 5442 | src/rlgl.h | OpenGL abstraction (header-only; owns `RLGL`) |
| 4629 | src/rcore.c | window/input/timing (owns `CoreData CORE`) |
| 3154 | src/raymath.h | vector/matrix math (header-only, pure) |
| 3002 | src/rtext.c | fonts/text (wraps stb_truetype) |
| 2964 | src/raudio.c | audio (wraps miniaudio/dr_*/stb_vorbis) |
| 2514 | src/rshapes.c | 2D primitives |
| 1752 | src/raylib.h | public C API — the ABI contract |
| 562  | src/rcamera.h | camera helpers (header-only) |
| 557  | src/rgestures.h | gesture recognizer (header-only) |
| 375  | src/config.h | feature flags (`SUPPORT_*`) |

Plus **one** platform backend (Linux/desktop first):

| LOC | File |
|---|---|
| ~2700 | src/platforms/rcore_desktop_glfw.c |

(The other ~9 backends in `src/platforms/`, ~18k LOC total, are deferred — not
compiled in the pinned Linux/GLFW build.)

## Regenerate counts

```bash
# raylib-authored modules only (exclude external/):
find /home/rajesh/opensource/graphics/raylib/src -maxdepth 1 \
  \( -name '*.c' -o -name '*.h' \) | xargs wc -l | tail -1

# byte size → rough token estimate:
find /home/rajesh/opensource/graphics/raylib/src -maxdepth 1 \
  \( -name '*.c' -o -name '*.h' \) -printf '%s\n' \
  | awk '{s+=$1} END{print s" bytes, ~"int(s/4)" tokens"}'
```
