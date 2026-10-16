# The web target

raylib-zig also builds for the browser. The library is the same Zig code as on
the desktop, compiled for `wasm32-emscripten` and linked by Emscripten's `emcc`.
This page explains how it is put together, how it is checked against C raylib,
and what is not done yet.

Status (2026-10-16): the platform backend and the OpenGL ES 3 path are ported.
The browser gate covers 46 examples: `core_basic_window` and all 45 of the
shapes category. All 46 pass in Debug and in ReleaseFast.

## What runs in the browser

Upstream raylib has a web platform, `PLATFORM_WEB`. It is
`platforms/rcore_web.c`, which runs on Emscripten's own GLFW (`-sUSE_GLFW=3`),
and rlgl on OpenGL ES. We port the same pair:

| Upstream C | Zig port | Chosen when |
|---|---|---|
| `platforms/rcore_desktop_glfw.c` | `src/platforms/rcore_desktop_glfw.zig` | any other target |
| `platforms/rcore_web.c` | `src/platforms/rcore_web.zig` + `rcore_web.js` | target OS is Emscripten |
| rlgl.h `GRAPHICS_API_OPENGL_33` | `src/rlgl.zig` with `src/gl33.zig` | any other target |
| rlgl.h `GRAPHICS_API_OPENGL_ES3` | `src/rlgl.zig` with `src/gles3.zig` | target OS is Emscripten |

The choice is made at comptime from the target, so there is no build flag to
get wrong. `rcore.zig` imports one backend (its `backend` constant), the same
way `rcore.c` `#include`s one platform file. `rlgl.zig` picks its
`graphics_api` the same way.

We use WebGL 2 (OpenGL ES 3.0), not WebGL 1. Every current browser has it, and
it is what `GRAPHICS_API_OPENGL_ES3` targets.

### rcore_web.js

`rcore_web.c` talks to the browser with inline JavaScript (`EM_ASM`, `EM_JS`).
Zig can't emit those. So each snippet is a function in
`src/platforms/rcore_web.js`, an Emscripten JS library, and the Zig backend
declares it as an `extern fn`. The JavaScript bodies are rcore_web.c's,
unchanged. Every link must pass the file to emcc:

```
emcc ... --js-library src/platforms/rcore_web.js
```

### gles3.zig

On the desktop rlgl calls OpenGL through GLAD's loaded function pointers:
`gl.glad_glClear.?(mask)`. `src/gles3.zig` declares the same `glad_gl*` names,
bound at comptime to the functions Emscripten's WebGL library defines. So the
376 call sites in rlgl.zig are the same on both targets. Entry points that
OpenGL ES doesn't have (`glPolygonMode`, `glClearDepth`, `glGetTexImage`) are
left out on purpose: using one on the web is a compile error.

### The ES3 differences in rlgl

We found them by preprocessing `rlgl.h` twice, once for OpenGL 3.3 and once for
ES3 on `PLATFORM_WEB`, and diffing the output. That gave the complete list,
about 20 places:

- 16-bit batch indices (`unsigned short`) and a smaller default batch (2048).
- Wire mode, point mode and smooth lines are no-ops.
- No `GL_TEXTURE_LOD_BIAS`, no cubemap seamless, no `GL_TEXTURE_WRAP_R` on cubemaps.
- Grayscale textures upload as `GL_LUMINANCE`, and 8-bit formats as unsized
  `GL_RGB`/`GL_RGBA`. There is no swizzle.
- NPOT textures use `GL_CLAMP_TO_EDGE` when the device lacks NPOT support, and
  mipmap filtering is not set.
- Sized depth formats (`GL_DEPTH_COMPONENT24` or `16`).
- `rlReadTexturePixels` reads through a temporary framebuffer, since there is
  no `glGetTexImage`.
- Unsigned-int uniforms are not set (rlgl.h only sets them on GL 3.3).
- `rlSetUniformMatrices` doesn't transpose, because WebGL rejects it.
- The default shaders use `#version 300 es` with precision qualifiers.

## The main loop

The translated examples keep raylib's normal loop:

```zig
while (!rl.windowShouldClose()) {
    rl.beginDrawing();
    defer rl.endDrawing();
    // ...
}
```

A browser can't run a loop like that, because the page freezes until it
returns. So we link with `-sASYNCIFY`, as raylib.com does. On the web,
`WindowShouldClose` calls `emscripten_sleep(12)`, and Asyncify unwinds the
stack to the browser and resumes it later. The examples need no changes.

The other way is a frame callback (`emscripten_set_main_loop`), which is what
lane-dodger on ziglang.in uses. It is smaller and faster, but every example
would have to be restructured. That doesn't scale to 226 examples.

## How it is checked

`zig build webexamples` is the browser gate. For each example in `build.zig`'s
`web_examples` it builds two programs for `wasm32-emscripten`:

1. The unmodified upstream C example on the all-C library (the oracle).
2. The Zig-API translation (`examples/zig/<category>/<name>.zig`) on the Zig
   library.

Both go through the same determinism shim as the desktop gate
(`tools/exdiff/shim.h`, `hooks.c`, and `c_exdiff.zig` for Zig): N frames on a
fixed 60 Hz frame clock, a fixed random seed, then a screenshot. The
screenshot is written to Emscripten's in-memory file system.

`tools/webdiff.sh` runs each program in headless Chrome through Playwright
(`tools/webdiff/run.mjs`). The page (`tools/webdiff/page.html`) freezes
`performance.now` and `Date.now`, which does what `fakeclock.c` does on the
desktop. WebGL runs on SwiftShader, Chrome's CPU renderer, so the result
doesn't depend on the GPU. The two final frames must be byte-identical.

Both libraries and all C are compiled by the same `zig cc`, with
`-ffp-contract=off`, as on the desktop. Only the link is emcc's.

Before trusting the gate we checked:

- C against C: two runs of the C oracle give byte-identical frames, so
  SwiftShader is deterministic here.
- A negative control: moving the Zig example's text down by one pixel makes
  the gate fail.

To run it you need the Emscripten SDK and Playwright:

```
(cd tools/webdiff && npm install)
zig build webexamples -Demsdk=/path/to/emsdk     # or set EMSDK
zig build webexamples -Demsdk=... -Dweb-filter=core_basic
```

`zig build web` builds and installs the Zig library for the web
(`zig-out/web/libraylib.a` and `rcore_web.js`).

`zig build webdemos` builds the same examples for the documentation site:
the Zig-API translation on the Zig library, with the real API instead of the
gate's shim, so the example runs until the reader leaves the page. Output:
`zig-out/web/examples/<name>/<name>.{js,wasm,data}`. The site copies that
directory (`npm run sync` in raylib-zig-web). Build it with
`-Doptimize=ReleaseFast` for the site.

## Bugs the web found

Both were real port bugs that x86-64 happened to hide. Neither changes the
desktop's machine code.

`rcore.zig` declared libc's `time()` as returning `c_long`. On x86-64 Linux
that is 64 bits, the same as `time_t`, so the desktop never noticed. On
wasm32 `c_long` is 32 bits but `time_t` is 64, and the link produced invalid
wasm. `time_t`, `timespec` and `dirent` now come from `std.c`, which has the
right layout per OS. `struct stat` keeps glibc's x86-64 layout on the desktop
(std.c has none for Linux) and uses `std.c.Stat` on Emscripten.

`TraceLog` and `TextFormat` forward their C variadic arguments to `vprintf`
and `vsnprintf`, and they passed `&ap`. On x86-64 that is right: C's
`va_list` is a one-element array there, so C receives a pointer to the list.
On wasm32 `va_list` is the pointer itself, so C received the address of the
list and formatted stack garbage. In Debug that went unnoticed; in ReleaseFast
the browser tab crashed before the first log line. `src/c_va.zig` now gives
the right argument for the target (`c_va.arg(&ap)`).

## Writing Zig for the web build

Two rules, both learned from examples that passed on the desktop and failed in
the browser:

- **Allocate with `std.heap.c_allocator`, not `std.heap.page_allocator`.** On
  wasm, `page_allocator` is Zig's `WasmAllocator`, which grows wasm memory with
  the `memory.grow` instruction directly. Emscripten's `malloc` and its
  JavaScript views of memory assume they do all the growing, so the views go
  stale: WebGL calls fail with "srcOffset + length too large" and JavaScript
  throws "detached ArrayBuffer". A raylib program links libc anyway, and
  `c_allocator` is `malloc`, which is also what the C original used.
- **Declare libc's time functions with `std.c.time_t`.** `time_t` is 64-bit on
  wasm32 but `c_long` is 32-bit. A `time(?*c_long) c_long` declaration links,
  and wasm-ld replaces the call with a trap (`RuntimeError: unreachable`).

raygui is compiled as C on both sides of the gate, and with the same
defines: `-DPLATFORM_WEB` on the web (raygui reads the scroll wheel
differently there), and without UBSan, which emcc has no runtime for. The Zig
side once used the desktop flags, and every raygui example failed to link.

## Not done yet

- The gate covers core_basic_window and the shapes category. The other
  categories come next, with each browser exclusion recorded and explained.
- Shaders: the examples hard-code GLSL 330. On the web they must load the
  `glsl100` (or `glsl300es`) variants, from one comptime constant.
- Speed: not measured yet. Size, for `core_basic_window` at ReleaseFast with
  `-sASYNCIFY` and emcc `-O2`: the Zig build is 107,469 bytes of wasm and
  159,896 of JS; the C build is 103,858 and 163,614. A frame-callback build
  for comparison is still to do.
- Each example's `.data` bundle is the whole category's `resources/`
  directory (48 KB for core, much more for models). It should hold only the
  files the example loads.
- `PLATFORM_WEB_EMSCRIPTEN` and `PLATFORM_WEB_RGFW` (raylib's other two web
  backends) are not ported. Only `PLATFORM_WEB` is.
