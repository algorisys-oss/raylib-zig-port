# Compatibility with C raylib — what is verified, and how

Status as of 2026-10-16 (tag `raylib-6.2-parity` and later). This records how
compatible the Zig port is with upstream C raylib, the evidence behind each
claim, and — just as important — what is **not** covered.

**Short answer:** for the pinned configuration (raylib 6.2, Linux x86-64,
desktop GLFW, OpenGL 3.3, default `config.h`), the Zig library is a drop-in
replacement for C raylib: unmodified raylib programs compile against the same
`raylib.h`, link against the Zig library, and render **byte-identical frames**
for every upstream example that can be run deterministically (217 of 217),
with numeric, audio and data functions bit-exact on their test grids. Outside
that configuration, compatibility is not claimed.

## 1. Scope: the configuration the claims apply to

| Axis | Supported / verified | Not supported (yet) |
|---|---|---|
| raylib version | **6.2** (tag `6.2`, git `02566453`) | other versions (re-port per release; 6.1-dev → 6.2 took one session) |
| OS / arch | Linux x86-64 | others untested |
| Platform backend | `PLATFORM_DESKTOP_GLFW` (GLFW 3, X11) | SDL, RGFW, Win32, DRM, Android (see [not-migrated.md](not-migrated.md)) |
| Graphics API | `GRAPHICS_API_OPENGL_33` | OpenGL 1.1 / 2.1 / 4.3, ES2, rlsw |
| Web (in progress) | `PLATFORM_WEB` + `GRAPHICS_API_OPENGL_ES3` (WebGL 2) on `wasm32-emscripten`: ported; the browser gate covers **46** examples so far (core_basic_window and all of shapes) (see [web.md](web.md)) | claims above do not yet extend to the web |
| Feature config | raylib's **default `config.h`** | any non-default `SUPPORT_*` flag (see §5) |
| Library form | static `libraylib.a` | shared `libraylib.so` (not built) |
| Optimization | Debug and ReleaseFast (both gated, §3) | — |

## 2. Interface compatibility (does a C program link?)

| Property | Result | Evidence |
|---|---|---|
| Public API symbols | **619 / 619** `RLAPI` functions in raylib.h exported, each defined exactly once, **all from Zig objects** (none from C) | `nm` sweep of `libraylib.a` vs raylib.h prototypes |
| Header | programs compile against the **unmodified** upstream `raylib.h` (plus `raymath.h`, `rlgl.h`, `rcamera.h`) | 219 upstream examples build unmodified |
| raymath / rlgl / rcamera | out-of-line exported symbols (`RMAPI`/`RLAPI`) | math/camera grids link against the Zig exports |
| Mirrored constants | **514** enum values / `#define`s (numeric, string, bool flags) in the Zig sources equal raylib's | `python3 tools/constaudit.py` (0 mismatches; negative control re-finds the historical SHADER_LOC off-by-one) |
| Struct layout & by-value ABI | `Color`/`Vector*`/`Rectangle`/`Matrix`/`Image`/`Model`… passed by value and by pointer exactly as C does | exercised by every gate below; the separate Zig API's 35 structs are checked field-by-field against translate-c'd raylib.h (`zig build apitest`) |
| Global state | `CoreData`/`rlglData` unchanged between 6.1-dev and 6.2; internal to Zig modules | struct diff of upstream headers |

## 3. Behavioral compatibility (does it do the same thing?)

The oracle is the **same build of upstream C raylib** (all-C library from the
vendored 6.2 sources), compiled side by side; every gate compares C output to
Zig output **byte-for-byte** — no tolerances.

| Gate | What is compared | Result |
|---|---|---|
| `zig build test` | 12 scenes (2D, text, textures, image ops, 3D shapes/meshes) rendered headless under mesa llvmpipe | **12/12** framebuffers identical |
| `tools/exdiff.sh` (examples) | every upstream example (unmodified), final frame after 240 frames, deterministic shim (fixed clock, hidden window, fixed RNG seed) | **217/217** automated identical; 10 excluded (§4) = all 227 accounted for |
| `zig build mathtest` | 146 raymath functions over a pseudo-random grid incl. edge cases (opposite vectors, TRS round-trips) | **90,200** values bit-identical |
| `zig build camtest` / `gesttest` | rcamera functions over an input grid / rgestures over scripted touch events | **7,500** / **3,200** values bit-identical |
| `zig build audiocheck` | decoded PCM (WAV/OGG/MP3/QOA/XM/MOD), Wave ops, export round-trips, stream/music metadata | **43/43** identical |
| `zig build datacheck` | compression, base64, file/data helpers | 0 failures |
| `zig build cdiff` | paths examples can't reach: Text* edge cases, LoadFontData default/bitmap/SDF over 5 TTFs, SHA256/SHA1/MD5 for lengths 0..200, path predicates, 720-frame rshapes thickness/angle/segment sweep | **4/4** programs identical |
| Real GPU spot check (`EXDIFF_GPU=1`) | examples on Intel Iris Xe (Mesa 25.2.8, GL 4.6) instead of llvmpipe | **219/219** identical (run before the last two audio exclusions) |
| ReleaseFast | all non-example gates at `-Doptimize=ReleaseFast` | pixel 12/12, math, cam, gest, data, audio 43/43, cdiff 4/4 identical |
| ReleaseFast examples sweep | full examples gate, optimized Zig library vs optimized C oracle | **217/217** identical |

Upstream behavior is reproduced **including its quirks**: e.g. `ImageDrawTextPro`
is an empty stub in 6.2 and is a no-op here too; upstream example bugs are kept
where they affect output.

## 4. What the oracle cannot see

These are limits of the evidence, not known incompatibilities:

- **Self-nondeterministic examples (10 excluded).** Their *C* build disagrees
  with itself run-to-run, so no comparison is meaningful: 6 audio examples
  whose pixels follow the real-time audio thread (`audio_mixed_processor`,
  `audio_module_playing`, `audio_raw_stream`, `audio_spectrum_visualizer`,
  `audio_stream_callback`, `audio_stream_effects`), `core_custom_frame_control`
  (busy-waits on wall time), `core_input_gestures_testbed`,
  `core_window_should_close` (needs a key press), and `rlgl_standalone` (never
  calls the library). Reasons per example: `test/examples.list`.
- **One frame per example.** The gate compares the final frame after 240
  frames, not every frame (intermediate state that is later overdrawn is not
  compared).
- **No live input.** Examples run without mouse/keyboard/gamepad input, so
  input-driven branches are covered only where `cdiff`, `camtest` and
  `gesttest` script them. Two real gaps were found this way (rtext's SDF glyph
  generation; rshapes parameter ranges) — both fixed and now gated.
- **Audio playback.** Decoding is byte-checked; what reaches the speaker in
  real time (mixing, device callbacks) is not.
- **GPU output in general.** The gate runs on llvmpipe; one real GPU was
  spot-checked (identical). Other drivers are not verified, and GPU output is
  not guaranteed bit-deterministic.
- **Floating point.** Byte-exactness is against C raylib compiled with
  `-ffp-contract=off`. C raylib built by clang with its default FMA
  contraction differs (in the last bit, sometimes in pixels) from this port —
  and from GCC builds of C raylib — on rotated/scaled geometry.
- **Undefined behavior in C.** Where upstream C has UB (e.g. out-of-range
  float→int casts, misaligned reads in bundled parsers), the Zig port picks
  the result C gives on x86-64 and is gated against it; it does not trap.

## 5. Known incompatibilities

| Area | Detail |
|---|---|
| Non-default `config.h` | The Zig modules implement raylib's **default** feature set. Code behind default-off flags is not ported: image formats TGA, JPG, PSD, HDR, PIC, PNM, KTX, ASTC, PKM, PVR, PEP; font format BDF; audio format FLAC; rshapes' triangles fallback (`SUPPORT_QUADS_DRAW_MODE=0`). Rebuilding with different `SUPPORT_*` values changes the C oracle but not the Zig port. |
| Other platforms / GL versions | Not compiled (see §1, not-migrated.md). |
| Shared library | Only a static archive is built. |

There are **no known behavioral differences** within the configuration of §1.

## 6. The idiomatic Zig API (a separate surface)

`@import("raylib")` is **not** ABI-compatible by design — it is a Zig API over
the C ABI above, with raylib's names and design (docs/zig-api.md). Its
compatibility is checked differently:

- **Same behavior:** every wrapper forwards to the gated C-ABI export, and
  **217 / 217** Zig-API translations of upstream examples render byte-identical
  to the original C examples (`zig build apiexamples`); 226 of 227 examples are
  translated (9 build-only for the §4 reasons; `rlgl_standalone` n/a).
- **Same layout:** all API structs match translate-c'd raylib.h / rlgl.h
  (`zig build apitest`).
- **Deliberate differences from C raylib's surface:** loaders return error
  unions (a failed `try rl.loadTexture` returns an error where C returns an
  invalid texture); `textFormat`/`traceLog` use `std.fmt` syntax and rounding
  (signed zero-padding prints `+6` where printf prints `06`; exact ties round
  differently); `setShaderValue` infers the uniform type; enums/flags/slices
  replace ints and pointer+count pairs; raygui control results stay `i32`.

## Re-verifying

```bash
zig build && zig build test mathtest camtest gesttest datacheck audiocheck cdiff apitest
python3 tools/constaudit.py
tools/exdiff.sh "$(find ~/.cache/zig-local -name libraylib_oracle.a | head -1)" zig-out/lib/libraylib.a
zig build apiexamples
```

Run the examples sweeps on a quiet machine: the audio-driven examples are
timing-sensitive under heavy CPU load.
