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

static void scene_shapes_poly(void) {
    ClearBackground(RAYWHITE);
    DrawPoly((Vector2){120, 110}, 6, 70, 18.0f, ORANGE);
    DrawPolyLines((Vector2){120, 110}, 6, 80, 18.0f, MAROON);
    DrawEllipse(330, 110, 90, 50, Fade(GREEN, 0.7f));
    DrawEllipseLines(330, 110, 90, 50, DARKGREEN);
    DrawCircleSector((Vector2){520, 110}, 70, 30, 250, 24, Fade(BLUE, 0.6f));
    DrawRing((Vector2){160, 270}, 40, 75, 0, 300, 28, Fade(PURPLE, 0.7f));
    DrawRingLines((Vector2){160, 270}, 40, 75, 0, 300, 28, DARKPURPLE);
    DrawTriangleFan((Vector2[]){{360, 230}, {420, 240}, {440, 300}, {380, 330}, {340, 290}}, 5, Fade(RED, 0.5f));
}
static void scene_splines(void) {
    ClearBackground((Color){245, 245, 245, 255});
    Vector2 pts[] = {{40, 60}, {160, 200}, {300, 60}, {440, 200}, {580, 80}};
    DrawSplineLinear(pts, 5, 6.0f, Fade(MAROON, 0.6f));
    DrawSplineBasis(pts, 5, 4.0f, BLUE);
    DrawSplineCatmullRom(pts, 5, 4.0f, GREEN);
    DrawSplineBezierCubic((Vector2[]){{40, 300}, {120, 200}, {240, 360}, {360, 300}}, 4, 5.0f, DARKBLUE);
    DrawLineBezier((Vector2){40, 340}, (Vector2){600, 320}, 3.0f, ORANGE);
    DrawLineDashed((Vector2){40, 350}, (Vector2){600, 350}, 12, 8, GRAY);
}

static void scene_text_format(void) {
    // Exercises rtext's riskiest paths: TextFormat (va_list ABI), DrawTextPro
    // (rotation), MeasureText-based layout, and string utilities — all with the
    // embedded default font (deterministic, no font file needed).
    ClearBackground((Color){30, 30, 46, 255});
    Font fnt = GetFontDefault();
    DrawText(TextFormat("score: %d  x=%4.2f", 1234, 3.14159f), 30, 30, 24, GOLD);
    DrawText(TextFormat("hex %08X  str=%s", 0xBEEF, "raylib"), 30, 70, 20, LIME);
    const char *msg = "MEASURED+CENTERED";
    int w = MeasureText(msg, 28);
    DrawText(msg, (640 - w) / 2, 120, 28, SKYBLUE);
    DrawTextPro(fnt, "rotated text", (Vector2){320, 240}, (Vector2){0, 0}, 35.0f, 30, 2.0f, PINK);
    DrawTextEx(fnt, TextFormat("upper:%s", "abc"), (Vector2){30, 300}, 26, 3.0f, ORANGE);
}

// rtextures coverage. Deterministic: SetRandomSeed pins the noise generators.
static void scene_image_gen(void) {
    ClearBackground(BLACK);
    SetRandomSeed(20260628);
    struct { Image img; int x, y; } cells[6];
    cells[0].img = GenImageColor(120, 100, (Color){200, 60, 60, 255});
    cells[1].img = GenImageChecked(120, 100, 8, 8, RAYWHITE, DARKGRAY);
    cells[2].img = GenImageGradientLinear(120, 100, 45, RED, BLUE);
    cells[3].img = GenImageGradientRadial(120, 100, 0.5f, GOLD, MAROON);
    cells[4].img = GenImagePerlinNoise(120, 100, 0, 0, 4.0f);
    cells[5].img = GenImageWhiteNoise(120, 100, 0.45f);
    int xs[6] = {20, 160, 300, 20, 160, 300};
    int ys[6] = {20, 20, 20, 140, 140, 140};
    // NOTE: raylib BATCHES draws and flushes at EndDrawing. A texture must stay
    // alive until then, so we do NOT UnloadTexture mid-frame (it would delete the
    // GPU texture before the queued DrawTexture runs → blank). The short-lived
    // runner process reclaims everything on exit; a small leak is fine here.
    for (int i = 0; i < 6; i++) {
        Texture2D t = LoadTextureFromImage(cells[i].img);
        DrawTexture(t, xs[i], ys[i], WHITE);
        UnloadImage(cells[i].img);
    }
}
static void scene_image_ops(void) {
    ClearBackground((Color){20, 20, 30, 255});
    Image img = GenImageColor(160, 160, (Color){40, 40, 60, 255});
    ImageDrawRectangle(&img, 10, 10, 80, 60, RED);
    ImageDrawCircle(&img, 110, 50, 35, GREEN);
    ImageColorTint(&img, (Color){180, 220, 255, 255});
    ImageColorInvert(&img);
    Texture2D t1 = LoadTextureFromImage(img);
    DrawTexture(t1, 30, 40, WHITE);
    DrawTexturePro(t1, (Rectangle){0, 0, 160, 160}, (Rectangle){360, 60, 200, 200},
                   (Vector2){0, 0}, 15.0f, WHITE);
    // (texture kept alive until EndDrawing flushes the batch — see scene_image_gen)
    UnloadImage(img);
}
static void scene_color_ops(void) {
    ClearBackground(RAYWHITE);
    Color base = (Color){200, 80, 40, 255};
    for (int i = 0; i < 10; i++) {
        DrawRectangle(20 + i * 60, 30, 56, 60, ColorBrightness(base, -0.5f + i * 0.1f));
        DrawRectangle(20 + i * 60, 100, 56, 60, ColorContrast(base, -0.9f + i * 0.2f));
        DrawRectangle(20 + i * 60, 170, 56, 60, ColorTint(WHITE, ColorFromHSV(i * 36.0f, 0.8f, 0.9f)));
        DrawRectangle(20 + i * 60, 240, 56, 60, Fade(DARKBLUE, i / 9.0f));
        DrawRectangle(20 + i * 60, 310, 56, 40, ColorAlphaBlend((Color){240, 240, 240, 255}, Fade(RED, i / 9.0f), WHITE));
    }
}

static struct { const char *name; SceneFn fn; } SCENES[] = {
    {"shapes_basic", scene_shapes_basic},
    {"shapes_gradient", scene_shapes_gradient},
    {"blend_rotation", scene_blend_rotation},
    {"text", scene_text},
    {"shapes_poly", scene_shapes_poly},
    {"splines", scene_splines},
    {"text_format", scene_text_format},
    {"image_gen", scene_image_gen},
    {"image_ops", scene_image_ops},
    {"color_ops", scene_color_ops},
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
