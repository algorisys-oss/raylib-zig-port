# handoff.md — fresh-session bootstrap (written 2026-10-16 18:50 IST)

> Overwritten at the end of every run (CLAUDE.md). PROGRESS.md holds history.

## 1. State right now

- Desktop port unchanged in behaviour: pixel 12/12 · exdiff **217/217** ·
  apiexamples **217/217** · cdiff 4/4 · audio 43/43 · datacheck · math/cam/gest
  · apitest · constaudit 0. (exdiff/apiexamples ran before the last change,
  src/c_va.zig; that change is identical machine code on x86-64, and the cheap
  gates plus cdiff text_strings re-ran green after it.)
- **Phase W (web target) started** — see PROGRESS.md "Phase W" and docs/web.md.
  `zig build webexamples -Demsdk=$HOME/emsdk`: browser gate **46/46**
  (core_basic_window), Debug and ReleaseFast. `zig build webdemos` feeds the
  site (raylib-zig-web, `npm run sync`).
- Committed at the end of this run (see git log); not pushed (pushing needs the
  owner's go-ahead).

## 2. What this run did

- rcore split: desktop GLFW backend -> src/platforms/rcore_desktop_glfw.zig;
  new src/platforms/rcore_web.zig + rcore_web.js (PLATFORM_WEB); backend picked
  at comptime from the target OS.
- rlgl.zig: GRAPHICS_API_OPENGL_ES3 path (diffed from preprocessed rlgl.h);
  src/gles3.zig binds the same glad_gl* names to WebGL 2.
- build.zig: `Platform`/`LibTarget`; `web`, `webexamples`, `webdemos` steps;
  tools/webdiff.sh + tools/webdiff/{run.mjs,page.html} (Playwright).
- Fixed two port bugs x86-64 hid: libc types (time_t etc. from std.c) and
  va_list forwarding (src/c_va.zig).
- gen_api.py: rl.gl.VertexBuffer.indices / default batch size follow the target.

## 3. Next step on resume

1. Grow `web_examples` in build.zig category by category (core_basic_window
   and all 45 shapes are in, 0dba149; next textures, then text), recording each browser exclusion with its reason.
2. GLSL version as one comptime constant for the web (examples load
   resources/shaders/glsl100 or glsl300es there), then the shaders category.
3. Per-example .data with only the files the example loads (now: whole
   category resources/).
4. Example manifest for the site (phase W step 7) to replace raylib-zig-web's
   parsing of build.zig lists.
5. Measure Asyncify vs a frame callback (size and speed).

## 4. Open issues / gotchas hit

- `npm install` once in tools/webdiff (Playwright 1.61.1). emsdk at ~/emsdk
  needed `npm ci` inside upstream/emscripten (acorn) — done.
- run.mjs now fails a crashed tab instead of hanging (a crashed page never
  satisfies waitForFunction).
- Two `libraylib_oracle.a` in the cache now (desktop and wasm): CLAUDE.md says
  how to pick the desktop one.
- tools/gen_api.py output must be run through `zig fmt` to match the committed
  src/api/*.zig.
- Disk: ~/.cache/zig-local reached 74 GB and was cleared this run.
