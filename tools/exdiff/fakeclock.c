// exdiff/fakeclock.c — LD_PRELOAD clock freezer for the examples gate.
//
// Examples call time-dependent LIBRARY paths the source shim can't reach
// (UpdateCamera CAMERA_ORBITAL reads rcore's GetFrameTime; rgestures hold
// timing; shapes_*_clock read time()/localtime()). Two sequential runs see
// different wall clocks, so C-vs-Zig output can never match. Freezing the
// process clock makes internal frame time exactly 0 in BOTH builds: animated-
// by-example state still advances (the shim's fixed 60 Hz clock), library-
// internal time-driven motion becomes static, and wall-clock faces render one
// fixed instant. Deterministic ⇒ diffable.
//
// Build: zig cc -shared -fPIC -o libfakeclock.so fakeclock.c

#define _GNU_SOURCE
#include <time.h>
#include <sys/time.h>
#include <stddef.h>

// 2026-01-01 00:00:00 UTC — arbitrary fixed instant.
#define FROZEN_EPOCH 1767225600

int clock_gettime(clockid_t clockid, struct timespec *tp)
{
    (void)clockid;
    if (tp != NULL) { tp->tv_sec = FROZEN_EPOCH; tp->tv_nsec = 0; }
    return 0;
}

int gettimeofday(struct timeval *tv, void *tz)
{
    (void)tz;
    if (tv != NULL) { tv->tv_sec = FROZEN_EPOCH; tv->tv_usec = 0; }
    return 0;
}

time_t time(time_t *tloc)
{
    if (tloc != NULL) *tloc = FROZEN_EPOCH;
    return FROZEN_EPOCH;
}
