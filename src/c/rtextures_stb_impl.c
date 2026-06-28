// rtextures_stb_impl.c — third-party single-file-lib instantiation for the
// rtextures port. When rtextures.c is ported to Zig, the stb/qoi/rltexgpu
// IMPLEMENTATIONS it used to instantiate move here (the Zig port calls them via
// `extern`). This replicates rtextures.c's exact preamble (lines ~73-224),
// driven by the SAME config.h, so the enabled formats and allocators match
// byte-for-byte. Compiled by build.zig only when "rtextures.c" is ported.
//
// Enabled here (from config.h): stb_image (PNG/BMP/GIF), qoi, rltexgpu (DDS),
// stb_image_write (export), stb_perlin (generation), stb_image_resize2 (always).

#include "config.h" // SUPPORT_FILEFORMAT_* / SUPPORT_IMAGE_* values
#include <stdlib.h>
#include <math.h>

#define RL_MALLOC(sz)       malloc(sz)
#define RL_FREE(p)          free(p)
#define RL_REALLOC(p, sz)   realloc(p, sz)

// rltexgpu logs via raylib's TraceLog; declare it (defined in the rcore/utils C).
extern void TraceLog(int logLevel, const char *text, ...);

// ---- stb_image (decode) ----
#if !SUPPORT_FILEFORMAT_BMP
#define STBI_NO_BMP
#endif
#if !SUPPORT_FILEFORMAT_PNG
#define STBI_NO_PNG
#endif
#if !SUPPORT_FILEFORMAT_TGA
#define STBI_NO_TGA
#endif
#if !SUPPORT_FILEFORMAT_JPG
#define STBI_NO_JPEG
#endif
#if !SUPPORT_FILEFORMAT_PSD
#define STBI_NO_PSD
#endif
#if !SUPPORT_FILEFORMAT_GIF
#define STBI_NO_GIF
#endif
#if !SUPPORT_FILEFORMAT_PIC
#define STBI_NO_PIC
#endif
#if !SUPPORT_FILEFORMAT_HDR
#define STBI_NO_HDR
#endif
#if !SUPPORT_FILEFORMAT_PNM
#define STBI_NO_PNM
#endif

#if SUPPORT_FILEFORMAT_DDS
#define RLTEXGPU_SUPPORT_DDS
#endif
#if SUPPORT_FILEFORMAT_PKM
#define RLTEXGPU_SUPPORT_PKM
#endif
#if SUPPORT_FILEFORMAT_KTX
#define RLTEXGPU_SUPPORT_KTX
#endif
#if SUPPORT_FILEFORMAT_PVR
#define RLTEXGPU_SUPPORT_PVR
#endif
#if SUPPORT_FILEFORMAT_ASTC
#define RLTEXGPU_SUPPORT_ASTC
#endif

#if (SUPPORT_FILEFORMAT_BMP || SUPPORT_FILEFORMAT_PNG || SUPPORT_FILEFORMAT_TGA || \
     SUPPORT_FILEFORMAT_JPG || SUPPORT_FILEFORMAT_PSD || SUPPORT_FILEFORMAT_GIF || \
     SUPPORT_FILEFORMAT_HDR || SUPPORT_FILEFORMAT_PIC || SUPPORT_FILEFORMAT_PNM)
#define STBI_MALLOC RL_MALLOC
#define STBI_FREE RL_FREE
#define STBI_REALLOC RL_REALLOC
#define STBI_NO_THREAD_LOCALS
#define STB_IMAGE_IMPLEMENTATION
#include "external/stb_image.h"
#endif

// ---- rltexgpu (compressed GPU texture formats: DDS/...) ----
#if (SUPPORT_FILEFORMAT_DDS || SUPPORT_FILEFORMAT_PKM || SUPPORT_FILEFORMAT_KTX || \
     SUPPORT_FILEFORMAT_PVR || SUPPORT_FILEFORMAT_ASTC)
#define RLTEXGPU_MALLOC RL_MALLOC
#define RLTEXGPU_FREE RL_FREE
#define RLTEXGPU_LOG(...) TraceLog(4 /* LOG_WARNING */, "IMAGE: " __VA_ARGS__)
#define RLTEXGPU_SHOW_LOG_INFO
#define RLTEXGPU_IMPLEMENTATION
#include "external/rltexgpu.h"
#endif

// ---- qoi (decode/encode) ----
#if SUPPORT_FILEFORMAT_QOI
#define QOI_MALLOC RL_MALLOC
#define QOI_FREE RL_FREE
#define QOI_IMPLEMENTATION
#include "external/qoi.h"
#endif

// ---- stb_image_write (export) ----
#if SUPPORT_IMAGE_EXPORT
#define STBIW_MALLOC RL_MALLOC
#define STBIW_FREE RL_FREE
#define STBIW_REALLOC RL_REALLOC
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "external/stb_image_write.h"
#endif

// ---- stb_perlin (procedural image generation) ----
#if SUPPORT_IMAGE_GENERATION
#define STB_PERLIN_IMPLEMENTATION
#include "external/stb_perlin.h"
#endif

// ---- stb_image_resize2 (always; ImageResize) ----
#define STBIR_MALLOC(size, c) ((void)(c), RL_MALLOC(size))
#define STBIR_FREE(ptr, c) ((void)(c), RL_FREE(ptr))
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "external/stb_image_resize2.h"
