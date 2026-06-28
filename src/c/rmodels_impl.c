// rmodels_impl.c — third-party single-file-lib instantiation for the rmodels
// port. rmodels.c instantiates the model-format loaders + the parametric mesh
// generator inside its TU; when rmodels is ported to Zig these move here so
// src/rmodels.zig can call them via extern. Faithful to rmodels.c's config
// (driven by the same config.h). Compiled by build.zig only when rmodels is
// ported. (SUPPORT_FILEFORMAT_GLTF_WRITE is 0 by default → cgltf_write skipped.)

#include "config.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <stdbool.h> // par_shapes / loaders use bool

#define RL_MALLOC(sz)       malloc(sz)
#define RL_CALLOC(n, sz)    calloc(n, sz)
#define RL_REALLOC(p, sz)   realloc(p, sz)
#define RL_FREE(p)          free(p)

// ---- tinyobj (OBJ/MTL) ----
#if SUPPORT_FILEFORMAT_OBJ || SUPPORT_FILEFORMAT_MTL
#define TINYOBJ_MALLOC RL_MALLOC
#define TINYOBJ_CALLOC RL_CALLOC
#define TINYOBJ_REALLOC RL_REALLOC
#define TINYOBJ_FREE RL_FREE
#define TINYOBJ_LOADER_C_IMPLEMENTATION
#include "external/tinyobj_loader_c.h"
#endif

// ---- cgltf (glTF) ----
#if SUPPORT_FILEFORMAT_GLTF
#define CGLTF_MALLOC RL_MALLOC
#define CGLTF_FREE RL_FREE
#define CGLTF_IMPLEMENTATION
#include "external/cgltf.h"
#endif

// ---- vox_loader (MagicaVoxel) ----
#if SUPPORT_FILEFORMAT_VOX
#define VOX_MALLOC RL_MALLOC
#define VOX_CALLOC RL_CALLOC
#define VOX_REALLOC RL_REALLOC
#define VOX_FREE RL_FREE
#define VOX_LOADER_IMPLEMENTATION
#include "external/vox_loader.h"
#endif

// ---- m3d (Model3D) ----
#if SUPPORT_FILEFORMAT_M3D
#define M3D_MALLOC RL_MALLOC
#define M3D_REALLOC RL_REALLOC
#define M3D_FREE RL_FREE
#define M3D_IMPLEMENTATION
#include "external/m3d.h"
#endif

// ---- par_shapes (parametric mesh generation) ----
#if SUPPORT_MESH_GENERATION
#define PAR_MALLOC(T, N) ((T *)RL_MALLOC(N * sizeof(T)))
#define PAR_CALLOC(T, N) ((T *)RL_CALLOC(N * sizeof(T), 1))
#define PAR_REALLOC(T, BUF, N) ((T *)RL_REALLOC(BUF, sizeof(T) * (N)))
#define PAR_FREE RL_FREE
#define PAR_SHAPES_IMPLEMENTATION
#include "external/par_shapes.h"
#endif
