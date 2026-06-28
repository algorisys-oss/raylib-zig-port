# What is *not* migrated (and why)

The goal is **100% of raylib-authored code → Zig**. This file is the ledger of
everything deliberately left as C, plus any raylib module that proves un-portable
(none yet). Nothing is dropped silently; every entry has a reason.

Three buckets, same spirit as sqlite-zig's not-migrated list
(generated / other-platform / flag-inactive).

## 1. Bundled third-party libraries — linked as C, never ported

`vendor/raylib/src/external/` (~13 MB, 138 files) is upstream third-party
single-file C, **not raylib**. It is the raylib analog of SQLite's
Lemon-generated `parse.c`: we link it, we do not hand-port it.

| Lib | Used by | What it is |
|---|---|---|
| `glfw/` (+ `rglfw.c`) | rcore platform | windowing/input/GL context |
| `glad.h` / `glad_gles2.h` | rlgl | OpenGL function loader |
| `stb_image.h`, `qoi.h`, `stb_image_resize2.h`, `stb_perlin.h` | rtextures | image load/resize/noise |
| `stb_truetype.h`, `stb_rect_pack.h` | rtext | font rasterization / atlas packing |
| `cgltf.h`, `par_shapes.h`, `m3d.h`, `tinyobj_loader_c.h`, `vox_loader.h` | rmodels | model/mesh loaders |
| `miniaudio.h`, `dr_wav.h`, `dr_flac.h`, `dr_mp3.h`, `stb_vorbis.c`, `jar_xm.h`, `jar_mod.h`, `qoa.h` | raudio | audio backend / decoders |
| `rlsw.h` | (fallback only) | software GL1.1 rasterizer — see testing.md |

➡️ Porting these is out of scope. A "pure-Zig raylib" = raylib's own modules in
Zig with `external/` still linked C.

## 2. Platform & GL backends outside the pinned target — deferred

Portable in principle, but not compiled in the pinned **Linux / GLFW / OpenGL
3.3** build, so not ported yet.

| File / path | What it is |
|---|---|
| `platforms/rcore_desktop_sdl.c` | SDL2/3 backend |
| `platforms/rcore_desktop_rgfw.c` | RGFW backend |
| `platforms/rcore_desktop_win32.c` | raw Win32 backend |
| `platforms/rcore_drm.c` | Linux DRM/KMS (no desktop) |
| `platforms/rcore_web*.c` | Emscripten/WebAssembly |
| `platforms/rcore_android.c` | Android NDK |
| `platforms/rcore_template.c` | backend skeleton |
| `GRAPHICS_API_OPENGL_{11,21,43,ES2,ES3}` paths in rlgl | other GL versions |

The pinned backend, `platforms/rcore_desktop_glfw.c`, **is** in scope (it's
`#include`d by rcore.c and ports with it).

## 3. raylib modules that proved un-portable

**None.** Every raylib-authored module is expected to port. If one turns out not
to be cleanly portable, it gets logged here with the specific reason and what
would unblock it — not quietly skipped.

## Bottom line

| Bucket | In the pinned Linux/GLFW/GL33 build? | Blocks "pure Zig"? |
|---|---|---|
| Bundled third-party `external/` | Yes (linked C) | No — not raylib (like SQLite's generated parse.c) |
| Other platform/GL backends | No (not compiled) | No — deferred, not excluded |
| Un-portable raylib modules | — | none so far |

See [../PROGRESS.md](../PROGRESS.md) for the ported-module list and
[testing.md](testing.md) for how each port is verified.
