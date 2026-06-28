// rcore_impl.c — third-party single-file-lib instantiation for the rcore port.
// rcore.c instantiates sinfl (decompress), sdefl (compress), and rprand (random)
// inside its TU. When rcore is ported to Zig those move here so src/rcore.zig can
// call them via extern. Faithful to rcore.c's config (SINFL_NO_SIMD etc.).
// Compiled by build.zig only when rcore is ported.

#include <stddef.h>
#include <stdbool.h> // rprand.h uses bool

#define SINFL_IMPLEMENTATION
#define SINFL_NO_SIMD
#include "external/sinfl.h" // sinflate / zsinflate (RFC 1951 decompressor)

#define SDEFL_IMPLEMENTATION
#include "external/sdefl.h" // sdeflate / sdefl_bound / zsdeflate (RFC 1951 compressor)

#define RPRAND_IMPLEMENTATION
#include "external/rprand.h" // rprand_* (random sequence generator)

// `struct sdefl` is ~1 MB; the Zig port allocates it opaquely via this sizeof.
size_t rl_sizeof_sdefl(void) { return sizeof(struct sdefl); }
