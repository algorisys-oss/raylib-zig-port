// exdiff/shim.h — determinism shim for upstream raylib examples.
//
// Force-included (zig cc -include) when compiling an unmodified example from
// the raylib tree, so the example runs headless, frame-bounded, and
// deterministically — every source of run-to-run variance is replaced by a
// frame-counter clock so the C-oracle and Zig builds render identical frames:
//
//   InitWindow          -> hidden window + fixed random seed
//   WindowShouldClose   -> counts EXDIFF_FRAMES frames, screenshots, then true
//   GetFrameTime/GetTime/GetFPS -> fixed 60 Hz frame-counter clock
//   SetTargetFPS        -> no-op (no real-time waits; throughput only)
//   DrawFPS             -> fixed text (real DrawFPS reads live timing)
//
// The example's main() is renamed so tools/exdiff/driver.c owns the process.

#include "raylib.h"

void ExdiffInitWindow(int width, int height, const char *title);
bool ExdiffWindowShouldClose(void);
float ExdiffGetFrameTime(void);
double ExdiffGetTime(void);
int ExdiffGetFPS(void);
void ExdiffDrawFPS(int posX, int posY);

#define InitWindow ExdiffInitWindow
#define WindowShouldClose ExdiffWindowShouldClose
#define GetFrameTime ExdiffGetFrameTime
#define GetTime ExdiffGetTime
#define GetFPS ExdiffGetFPS
#define DrawFPS ExdiffDrawFPS
#define SetTargetFPS(fps) ((void)(fps))

#define main exdiff_example_main
