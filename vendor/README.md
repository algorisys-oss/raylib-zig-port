# vendor/ — immutable upstream raylib sources

Copied verbatim from `/home/rajesh/opensource/graphics/raylib-6.2/src` (raylib 6.2, git 02566453880e).
We compile these per-translation-unit; a ported module `src/<name>.zig` replaces
`vendor/raylib/src/<name>.c` via the `ported_modules` list in build.zig.

Third-party libs under `vendor/raylib/src/external/` are linked as C, never ported.

Re-vendor: `rm -rf vendor/raylib/src && cp -r /home/rajesh/opensource/graphics/raylib-6.2/src vendor/raylib/src`

## raylib-zig patches to vendored sources

Minimal, documented edits to `vendor/raylib/src` to enable header-only-module swaps:

- **rcore.c**: `#define RLGL_IMPLEMENTATION` is wrapped in
  `#if !defined(RAYLIB_ZIG_NO_RLGL_IMPL)`. rcore.c instantiates rlgl (and its
  bundled glad) by default; when rlgl is ported to Zig we compile rcore.c with
  `-DRAYLIB_ZIG_NO_RLGL_IMPL` so the rl*/glad symbols come from src/rlgl.zig +
  src/c/glad_impl.c instead. Re-apply after re-vendoring.
