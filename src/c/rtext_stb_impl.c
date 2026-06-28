// rtext_stb_impl.c — third-party single-file-lib instantiation for the rtext port.
//
// When rtext.c is ported to Zig (src/rtext.zig), the stb_rect_pack and
// stb_truetype IMPLEMENTATIONS it used to instantiate must be provided by a
// separate C translation unit (the Zig port calls them via `extern`). This shim
// reproduces rtext.c's exact instantiation config — EXCEPT it does NOT define
// STBTT_STATIC, so the stbtt_* symbols are globally linkable from Zig.
//
// Compiled (by build.zig) only when "rtext.c" is in ported_modules. See
// docs/architecture.md (third-party boundary) and not-migrated.md.

// raylib's default allocators (match config.h: RL_MALLOC/RL_FREE/RL_REALLOC).
#include <stdlib.h>
#define RL_MALLOC(sz)       malloc(sz)
#define RL_FREE(p)          free(p)
#define RL_REALLOC(p, sz)   realloc(p, sz)

// --- stb_rect_pack (font atlas rectangle packing) ---
#define STB_RECT_PACK_IMPLEMENTATION
#include "external/stb_rect_pack.h"

#include <math.h>

// --- stb_truetype (TTF reading + glyph rasterization) ---
// NOTE: rtext.c uses STBTT_STATIC (file-local). We intentionally omit it so the
// symbols are external and callable from src/rtext.zig.
#define STBTT_malloc(x, u)  ((void)(u), RL_MALLOC(x))
#define STBTT_free(x, u)    ((void)(u), RL_FREE(x))
#define STB_TRUETYPE_IMPLEMENTATION
#include "external/stb_truetype.h"

#include <stddef.h>
// sizeof helpers so the Zig port can allocate these structs opaquely (it never
// touches their fields — only passes pointers to stb functions).
size_t rl_sizeof_stbtt_fontinfo(void) { return sizeof(stbtt_fontinfo); }
size_t rl_sizeof_stbrp_context(void) { return sizeof(stbrp_context); }
size_t rl_sizeof_stbrp_node(void) { return sizeof(stbrp_node); }
