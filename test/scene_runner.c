// scene_runner.c — renders a fixed battery of deterministic scenes headlessly
// and dumps each framebuffer as raw RGBA to <outdir>/<NN>_<name>.raw, plus a
// manifest line "NN name WxH crc32" to stdout.
//
// Run twice — once linked against the all-C raylib (the oracle) and once against
// the Zig-swapped raylib — under the same software rasterizer (llvmpipe), then
// byte-diff the .raw files. Identical bytes ⇒ the ported modules are correct for
// these scenes. This is the migration's pixel-diff gate (see docs/testing.md).
//
// Scenes are intentionally pinned: fixed sizes, fixed colors, no time/RNG, so a
// frame is a pure function of the code under test.

#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static uint32_t crc32(const unsigned char *p, size_t n) {
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) {
        c ^= p[i];
        for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (uint32_t)(-(int)(c & 1)));
    }
    return c ^ 0xFFFFFFFFu;
}

typedef void (*SceneFn)(void);

// ---- scenes -------------------------------------------------------------------
static void scene_shapes_basic(void) {
    ClearBackground(RAYWHITE);
    DrawRectangle(40, 40, 160, 100, RED);
    DrawRectangleLines(40, 40, 160, 100, MAROON);
    DrawCircle(300, 90, 50, BLUE);
    DrawCircleLines(300, 90, 50, DARKBLUE);
    DrawTriangle((Vector2){500, 40}, (Vector2){450, 150}, (Vector2){560, 150}, GREEN);
    DrawLine(20, 200, 600, 200, BLACK);
    DrawLineEx((Vector2){20, 220}, (Vector2){600, 260}, 4.0f, PURPLE);
}
static void scene_shapes_gradient(void) {
    ClearBackground(DARKGRAY);
    DrawRectangleGradientV(40, 40, 200, 160, RED, BLUE);
    DrawRectangleGradientH(280, 40, 200, 160, GREEN, GOLD);
    DrawCircleGradient((Vector2){500, 300}, 80, ORANGE, (Color){0, 0, 0, 0});
    DrawRectangleRounded((Rectangle){40, 240, 200, 120}, 0.4f, 16, MAROON);
}
static void scene_blend_rotation(void) {
    ClearBackground(RAYWHITE);
    for (int i = 0; i < 24; i++) {
        DrawRectanglePro((Rectangle){320, 240, 160, 12}, (Vector2){80, 6},
                         i * 15.0f, Fade(MAROON, 0.5f));
    }
    DrawCircleSector((Vector2){160, 160}, 100, 0, 270, 32, Fade(BLUE, 0.6f));
}
static void scene_text(void) {
    ClearBackground((Color){10, 20, 40, 255});
    DrawText("raylib-zig", 40, 40, 60, RAYWHITE);
    DrawText("C -> Zig migration", 40, 120, 30, GOLD);
    DrawText("the quick brown fox 0123456789", 40, 180, 20, LIGHTGRAY);
    // NOTE: no DrawFPS here — it reads real frame timing and is nondeterministic.
    // Every scene must be a pure function of the code under test (no time/RNG).
    DrawTextEx(GetFontDefault(), "scaled spacing", (Vector2){40, 240}, 28, 4.0f, SKYBLUE);
}

static struct { const char *name; SceneFn fn; } SCENES[] = {
    {"shapes_basic", scene_shapes_basic},
    {"shapes_gradient", scene_shapes_gradient},
    {"blend_rotation", scene_blend_rotation},
    {"text", scene_text},
};
static const int N_SCENES = (int)(sizeof(SCENES) / sizeof(SCENES[0]));

int main(int argc, char **argv) {
    const char *outdir = (argc > 1) ? argv[1] : ".";
    const int W = 640, H = 360;

    SetTraceLogLevel(LOG_ERROR);
    SetConfigFlags(FLAG_WINDOW_HIDDEN);
    InitWindow(W, H, "scene_runner");
    if (!IsWindowReady()) { fprintf(stderr, "window not ready\n"); return 2; }

    for (int i = 0; i < N_SCENES; i++) {
        BeginDrawing();
        SCENES[i].fn();
        EndDrawing();

        Image img = LoadImageFromScreen();
        ImageFormat(&img, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8); // pin format
        size_t n = (size_t)img.width * img.height * 4;

        char path[512];
        snprintf(path, sizeof path, "%s/%02d_%s.raw", outdir, i, SCENES[i].name);
        FILE *f = fopen(path, "wb");
        if (f) { fwrite(img.data, 1, n, f); fclose(f); }

        printf("%02d %-16s %dx%d %08x\n", i, SCENES[i].name, img.width, img.height,
               crc32((unsigned char *)img.data, n));
        UnloadImage(img);
    }

    CloseWindow();
    return 0;
}
