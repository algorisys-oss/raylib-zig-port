// glad_impl.c — GLAD (OpenGL loader) instantiation for the rlgl port.
//
// rlgl.h normally instantiates GLAD inside its RLGL_IMPLEMENTATION block (which
// rcore.c triggers). When rlgl is ported to Zig, that block is disabled (rcore.c
// is compiled with RAYLIB_ZIG_NO_RLGL_IMPL), so GLAD must be instantiated here
// as its own C TU. It provides the `glad_gl*` function pointers + gladLoadGL,
// which src/rlgl.zig calls via extern. Compiled by build.zig only when rlgl is
// ported. GLAD is third-party generated code — linked, never ported.

#include <stdlib.h> // malloc/free for GLAD_MALLOC/GLAD_FREE
#define GLAD_MALLOC(sz) malloc(sz)
#define GLAD_FREE(p) free(p)
#define GLAD_GL_IMPLEMENTATION
#include "external/glad.h"
