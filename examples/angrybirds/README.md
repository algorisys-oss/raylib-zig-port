# Angry Birds (slingshot) — raylib-zig capstone demo

A small physics slingshot game written in idiomatic Zig against the ported
raylib library's plain C ABI (no `@cImport`; see [raylib.zig](raylib.zig) for
the 22-function binding). Port of the C# reference at
`~/lab/csharp/csharp-raylib-angrybirds`. All art is procedural — no assets.

## Run

```bash
zig build angrybirds        # builds the library + the game, then runs it
# or run the installed binary directly:
./zig-out/bin/angrybirds
```

Needs a display (X11). The game window is 1280×720.

## Controls

| Input | Action |
|---|---|
| Left mouse (drag + release) | Pull the bird back on the sling and fire |
| R | Restart the current level |
| SPACE | Next level after a clear |

Scoring: pig 1000, block 200. Three levels; clearing all pigs advances.

## Headless self-test

```bash
ANGRYBIRDS_SELFTEST=1 ANGRYBIRDS_SHOT=/tmp zig-out/bin/angrybirds
```

Opens a hidden window, auto-plays scripted max-power shots through the same
`Game.update` path the mouse drives, runs 300 fixed-timestep frames, writes
`$ANGRYBIRDS_SHOT/selftest.png`, and exits 0. Add
`LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe` to run without a GPU.
