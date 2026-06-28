# vendor/ — immutable upstream raylib sources

Copied verbatim from `/home/rajesh/opensource/graphics/raylib/src` (raylib 6.1-dev, git 67359073ca26).
We compile these per-translation-unit; a ported module `src/<name>.zig` replaces
`vendor/raylib/src/<name>.c` via the `ported_modules` list in build.zig.

Third-party libs under `vendor/raylib/src/external/` are linked as C, never ported.

Re-vendor: `rm -rf vendor/raylib/src && cp -r /home/rajesh/opensource/graphics/raylib/src vendor/raylib/src`
