# Migration architecture & decisions

Living record of the architectural decisions behind the raylib C→Zig migration.
Read alongside [../plan.md](../plan.md) (roadmap), [../PROGRESS.md](../PROGRESS.md)
(status), and [testing.md](testing.md) (validation). New decisions get appended
with a date.

## How a module is ported (the swap mechanism)

Each raylib translation unit under [`../vendor/raylib/src`](../vendor/raylib/src)
is compiled separately by [../build.zig](../build.zig). To port a module we write
`src/<name>.zig` that **exports the same C-ABI symbols** as `vendor/raylib/src/
<name>.c`, then add `"<name>.c"` to `ported_modules` in build.zig. The C file is
dropped and the Zig object linked in its place; every still-C caller links
against the Zig symbols unchanged.

`build.zig` builds the library **twice from the same `ported_modules`-aware
source list**:

- `raylib` — ported Zig swapped in (the build under test).
- `raylib_oracle` — `ported_modules` ignored, always all-C (the differential
  oracle).

A scene runner links against each; [testing.md](testing.md) explains the
framebuffer diff that gates every change.

## What is C, what is Zig (the boundary)

| Layer | Files | Treatment |
|---|---|---|
| raylib modules | `rcore.c`, `rshapes.c`, `rtextures.c`, `rtext.c`, `rmodels.c`, `raudio.c` (+ header-only `raymath.h`, `rlgl.h`, `rcamera.h`, `rgestures.h`) | **ported** to `src/*.zig` |
| platform backend | `platforms/rcore_desktop_glfw.c` (`#include`d by rcore.c) | ported (Linux/GLFW first) |
| GLFW | `rglfw.c` (bundles `external/glfw/`) | **always C** (vendored windowing lib) |
| third-party | `external/` stb_*, miniaudio, dr_*, cgltf, par_shapes, m3d, qoi/qoa, glad, rlsw, jar_* | **always C** (linked, never ported) |

This is the raylib analog of sqlite-zig keeping the Lemon-generated `parse.c` as
C: a "pure-Zig raylib" means every *raylib-authored* module is Zig with the
bundled third-party libs still linked as C.

## Struct-coupling patterns

Two patterns, same as sqlite-zig:

- **ABI-shared struct** (read across module boundaries — e.g. the globals
  `CoreData CORE` in rcore.c, `rlglData RLGL` in rlgl.h, and the public types in
  `raylib.h`): mirror field-for-field as a Zig `extern struct`. Layout must match
  exactly. Verify with comptime `@offsetOf`/`@sizeOf` asserts against C ground
  truth (the `tools/offsets.c` → `src/c_layout.zig` tooling, to be added before
  rcore/rlgl land — Phase 2/4).
- **By-value structs** (`Color`, `Vector2/3/4`, `Rectangle`, `Matrix` passed by
  value across the ABI): keep them `extern struct` so the C calling convention
  for small aggregates matches. This is pervasive in raylib and
  calling-convention-sensitive — lock it down first in raymath (Phase 1).

## Decision 2026-06-28: pinned config (Linux / GLFW / OpenGL 3.3)

raylib's behavior and struct layout vary across three axes —
`PLATFORM_DESKTOP_*` × `GRAPHICS_API_OPENGL_*` × `src/config.h` `SUPPORT_*` flags.
A single Zig object can't satisfy two configs at once (the same constraint
sqlite-zig hit with prod vs `--dev`). We pin **one** production config:

```
PLATFORM_DESKTOP_GLFW  GRAPHICS_API_OPENGL_33  _GLFW_X11  + the SUPPORT_MODULE_* set
```

mirrored as a comptime `config` options module in build.zig (`opengl_version`,
extended as needed). Other backends (SDL/RGFW/DRM/Web/Android) and GL versions
(11/21/43/ES2/ES3) are deferred, not excluded — see
[not-migrated.md](not-migrated.md).

## Decision 2026-06-28: the oracle is llvmpipe, byte-exact

The validation oracle is mesa **llvmpipe** software rendering of the *real GL3.3
codepath*, which Phase 0 proved byte-exact deterministic — stronger than the
originally-planned rlsw (GL1.1, a different codepath) or a tolerance diff. See
[testing.md](testing.md) for the full rationale and the determinism discipline.

## Decision 2026-06-28: install-free build

The build uses only what's present on the host — system X11/GL/EGL dev headers
(`/usr/include`) and `.so`s, plus the **vendored** GLFW compiled from source. **No
`sudo`/apt.** System paths (`/usr/include`, `/usr/lib/x86_64-linux-gnu`) are
currently hardcoded in build.zig; parameterize if the build moves hosts.

## Known issue: ReleaseFast static archive

`zig build -Doptimize=ReleaseFast` fails to write the static archive
(`LLD: UnableToWriteArchive`) with the full TU set; **Debug is the working
default** and is fine for the correctness gate (determinism holds regardless of
opt level, with FP contraction disabled). An isolated 2-file `build-lib` archives
fine, so it's an LLD archive-writer quirk at `-OReleaseFast` + many large C
objects. Revisit for an optimized production lib (candidate workarounds: a
`zig ar` post-archive step, `-fno-lto`, or per-object archiving). Tracked in
[../PROGRESS.md](../PROGRESS.md); not blocking the migration.
