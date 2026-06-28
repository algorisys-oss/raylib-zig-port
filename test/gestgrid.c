// gestgrid.c — C oracle for the rgestures bit-exact numeric diff.
// Feeds a deterministic stream of GestureEvents through a HARNESS-CONTROLLED
// clock (GetTime returns g_time, which we set each step), then prints the raw
// bits of every gesture query. test/gestgrid.zig mirrors this against the Zig
// port; tools/gestdiff.sh diffs. Deterministic ⇒ no real time, no RNG.

#include <math.h> // rgestures.h uses atan2f/sqrt (rcore.c includes this before it)
#include "raylib.h" // Vector2, GestureEvent, GESTURE_*, TOUCH_ACTION_* + the API decls

// Controlled clock: rgestures' rgGetCurrentTime() calls GetTime() in
// non-standalone mode. We define it so both builds see identical time.
static double g_time = 0.0;
double GetTime(void) { return g_time; }

#define RGESTURES_IMPLEMENTATION
#include "rgestures.h"

#include <stdio.h>
#include <stdint.h>

static uint32_t S = 0x13572468u;
static uint32_t lcg(void) { S = S * 1103515245u + 12345u; return (S >> 8) & 0xFFFFFFu; }
static float frnd(float lo, float hi) { return lo + (float)lcg() / 16777216.0f * (hi - lo); }

static void pf(float f) { uint32_t u; __builtin_memcpy(&u, &f, 4); printf("%08x ", u); }
static void pi(int i) { printf("%d ", i); }
static void p2(Vector2 v) { pf(v.x); pf(v.y); }

int main(void) {
    SetGesturesEnabled(0xFFFFFFFF); // GESTURE_ALL
    const int N = 400;
    for (int i = 0; i < N; i++) {
        g_time += (double)(lcg() % 100) * 0.005; // advance 0..0.5s per step

        GestureEvent ev = {0};
        uint32_t a = lcg() % 10;
        ev.touchAction = (a < 2) ? 1 /*DOWN*/ : (a < 4) ? 0 /*UP*/ : 2 /*MOVE*/;
        ev.pointCount = (lcg() % 3 == 0) ? 2 : 1; // sometimes two-finger (pinch)
        ev.pointId[0] = 0;
        ev.pointId[1] = 1;
        ev.position[0] = (Vector2){frnd(0, 640), frnd(0, 360)};
        ev.position[1] = (Vector2){frnd(0, 640), frnd(0, 360)};

        ProcessGestureEvent(ev);
        UpdateGestures();

        pi(GetGestureDetected());
        pf(GetGestureHoldDuration());
        p2(GetGestureDragVector());
        pf(GetGestureDragAngle());
        p2(GetGesturePinchVector());
        pf(GetGesturePinchAngle());
        printf("\n");
    }
    return 0;
}
