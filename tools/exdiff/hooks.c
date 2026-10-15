// exdiff/hooks.c — the determinism hooks behind tools/exdiff/shim.h.
//
// Shared by both kinds of gated program:
//   - upstream C examples, whose calls shim.h redirects here by macro
//     (process entry: driver.c);
//   - Zig-API example translations, whose `raylib_c` boundary module
//     (src/api/c_exdiff.zig, generated) routes the same functions here.
//
// Env contract (set by exdiff.sh):
//   EXDIFF_FRAMES  frames to run before closing (default 240)
//   EXDIFF_SHOT    absolute path for the final-frame screenshot (PNG)

#include "raylib.h"

#include <stdbool.h>
#include <stdlib.h>

static int framesTotal = 240;
static int frame = 0;
static const char *shotPath = NULL;

void ExdiffInitWindow(int width, int height, const char *title)
{
    shotPath = getenv("EXDIFF_SHOT");
    const char *frames = getenv("EXDIFF_FRAMES");
    if (frames != NULL) framesTotal = atoi(frames);

    SetConfigFlags(FLAG_WINDOW_HIDDEN);
    InitWindow(width, height, title);
    SetRandomSeed(42); // InitWindow seeds from wall time; re-seed for determinism
}

bool ExdiffWindowShouldClose(void)
{
    if (frame >= framesTotal)
    {
        if (shotPath != NULL) TakeScreenshot(shotPath);
        return true;
    }
    frame++;
    return false;
}

float ExdiffGetFrameTime(void) { return 1.0f/60.0f; }
double ExdiffGetTime(void) { return frame/60.0; }
int ExdiffGetFPS(void) { return 60; }
void ExdiffDrawFPS(int posX, int posY) { DrawText("60 FPS", posX, posY, 20, LIME); }
void ExdiffSetTargetFPS(int fps) { (void)fps; }
