# The idiomatic Zig API (Phase 6)

Status: approved 2026-10-16 ("API design is approved — should be as per the
raylib guidelines"). This document is the rule set; `tools/gen_api.py` applies
it mechanically to `vendor/raylib/src/raylib.h`.

## Goals, in priority order

1. **raylib's design, unchanged.** Same functions, same names, same types,
   same Load/Unload pairing, same "values over handles" and sane defaults. A
   raylib cheatsheet maps 1:1 onto this API by lower-casing the first letter.
   No new concepts, no builder objects, no required boilerplate.
2. **Zig idiom where C is weak.** Strings are `[:0]const u8`; pointer+count
   pairs are slices; int "enums" are real `enum`s; bit flags are packed
   structs; loaders report failure as an error union; out-parameter counts
   become returned slices. Nothing else changes.
3. **One implementation.** Every function is a thin `inline` wrapper over the
   C-ABI export the port already gates (pixel/numeric/PCM diffs). The API
   adds no behavior of its own, so it cannot drift from upstream raylib.
4. **Regenerable.** A new raylib release is absorbed by re-running the
   generator; hand-written exceptions live in one override table.

## Usage

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
        rl.drawText("Congrats! You created your first window!", 190, 200, 20, .light_gray);
        if (rl.isKeyDown(.space)) rl.drawTexture(logo, 10, 10, .white);
    }
}
```

## Mapping rules

| raylib.h | Zig API | Example |
|---|---|---|
| `PascalCase` function | `camelCase` function | `DrawText` → `drawText` |
| struct typedef | same name, `extern struct` (ABI-identical) | `Vector2`, `Texture2D` |
| `int` / `unsigned int` / `float` / `double` | `i32` / `u32` / `f32` / `f64` | |
| `const char *` param | `[:0]const u8` (`?[:0]const u8` where raylib accepts NULL) | `loadShader(null, "fx.fs")` |
| `const char *` return | `[:0]const u8` | `getFileName(path)` |
| `T *p, int count` param pair | `[]const T` / `[]T` | `drawLineStrip(points, color)` |
| `T *dst` param | `*T` | `imageFlipVertical(&img)` |
| int enum param (`int key`, `int button`, …) | typed `enum` | `isKeyPressed(.enter)` |
| `unsigned int flags` (ConfigFlags) | `ConfigFlags` packed struct | `setConfigFlags(.{ .vsync_hint = true })` |
| `LoadX` returning a struct with an `IsXValid` | `error{LoadFailed}!X` | `try rl.loadTexture(path)` |
| returned buffer + `int *count` out-param | returned slice; freed by the matching `unload` | `loadFileData(path)` → `[]u8` |
| color `#define` (`RAYWHITE`) | `Color` decl (`.ray_white`) | `clearBackground(.ray_white)` |
| enum constant (`KEY_LEFT_SHIFT`) | enum tag without prefix | `.left_shift` |
| printf-style varargs (`TextFormat`, `TraceLog`) | `std.fmt` comptime format | `rl.textFormat("{d} pts", .{score})` |
| `PI` / `DEG2RAD` / `RAD2DEG` | `f32` constants | `rl.deg2rad * angle` |
| `char *` struct field | `[*:0]u8` (NUL-terminated) | `std.mem.span(files.paths.?[0])` |
| `material.maps[MATERIAL_MAP_X]` | `material.map(.x)` → `*MaterialMap` | `model.materials.?[0].map(.diffuse).texture = tex` |

Enums that represent open sets (key codes, gamepad buttons, gestures,
shader locations) are non-exhaustive (`_`), so any value raylib can return
round-trips.

## raymath

`raymath.h` is exposed as the `math` namespace with the same rules:
`Vector2Add(a, b)` → `rl.math.vector2Add(a, b)`, `MatrixRotateY(angle)` →
`rl.math.matrixRotateY(angle)`. (`rlgl.h` is not wrapped yet — it is raylib's
low-level GL layer; examples that need it stay C-only for now.)

## Memory

raylib allocates with its own `MemAlloc`/`MemFree` (libc malloc); the API
does not take a `std.mem.Allocator`, because the memory is owned by raylib and
must be returned to raylib (`unloadFileData`, `unloadImageColors`, …) exactly
as in C. The reverse direction — buffers you build and hand to raylib, which
frees them itself (e.g. `Mesh.vertices` passed to `uploadMesh`, released by
`unloadModel`) — goes through `rl.mem_allocator`, a `std.mem.Allocator` over
`MemAlloc`/`MemRealloc`/`MemFree`. Slices returned by the API point at raylib-owned memory; the matching
`unload*` takes the slice back. Functions documented upstream as returning a
"static string" (e.g. `textFormat`, `getFileName`) return slices into raylib's
internal buffers — valid until the next call, as in C.

## Boundary layout

- `src/api/c.zig` — generated `extern fn` declarations with the exact C
  signatures (the only C-shaped code; `[*c]` lives here and nowhere else).
- `src/api/raylib.zig` — generated idiomatic layer: types, enums, colors,
  wrappers. Exposed as the `raylib` module in build.zig.
- `tools/gen_api.py` — the generator; its `OVERRIDES` table holds the few
  hand-written wrappers (varargs, callbacks, multi-out-param functions).

## Gate

The API is checked the same way as the port: Zig-API translations of upstream
examples (`examples/zig/*.zig`) must render frames byte-identical to the
upstream C examples under the same determinism shim (`zig build apitest`).
