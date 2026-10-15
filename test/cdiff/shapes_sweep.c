// shapes_sweep.c — C-vs-Zig differential for rshapes' parameter space.
//
// Headless examples only render default slider values, so most of rshapes'
// thickness/angle/segment branches are unreachable from the examples gate.
// Renders 720 frames over negative/zero/small/huge thickness, reversed and
// >360-degree sweeps, segment counts 0/1/3/7/36 and degenerate inner radii,
// printing a CRC32 per framebuffer. Needs a display (tools/cdiff.sh sets
// llvmpipe).
#include "raylib.h"
#include <stdio.h>
#include <stdint.h>
static uint32_t crc32(const unsigned char *p, size_t n) {
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) { c ^= p[i]; for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (uint32_t)(-(int)(c & 1))); }
    return c ^ 0xFFFFFFFFu;
}
int main(void) {
    SetTraceLogLevel(LOG_ERROR);
    SetConfigFlags(FLAG_WINDOW_HIDDEN);
    InitWindow(640, 360, "sweep");
    float thicks[] = { -25, -12, -5, -1, 0, 0.5f, 1, 3, 8, 20, 45, 80 };
    float angs[][2] = { {0,360},{20,270},{-90,90},{10,40},{0,200},{30,389},{0,720},{45,-200},{0,181},{100,350},{0,90},{5,355} };
    int segs[] = { 0, 1, 3, 7, 36 };
    int frame = 0;
    for (int ti = 0; ti < 12; ti++) for (int ai = 0; ai < 12; ai++) for (int si = 0; si < 5; si++) {
        float t = thicks[ti]; float a0 = angs[ai][0], a1 = angs[ai][1]; int sg = segs[si];
        BeginDrawing();
        ClearBackground(RAYWHITE);
        Color c = Fade(MAROON, 0.6f);
        DrawCircleSectorLinesEx((Vector2){80, 80}, 60, a0, a1, sg, t, c);
        DrawCircleSectorLinesEx((Vector2){80, 250}, 12, a0, a1, sg, t*0.3f, BLUE);
        DrawRingLinesEx((Vector2){230, 80}, 20, 65, a0, a1, sg, t, c);
        DrawRingLinesEx((Vector2){230, 250}, 0, 60, a0, a1, sg, t, DARKGREEN);
        DrawRingLinesEx((Vector2){380, 80}, 55, 30, a0, a1, sg, t*0.5f, PURPLE);
        DrawRingLinesEx((Vector2){380, 250}, 45, 50, a0, a1, sg, t*0.2f, ORANGE);
        DrawCircleSector((Vector2){520, 80}, 50, a0, a1, sg, Fade(GOLD, 0.5f));
        DrawCircleSectorLines((Vector2){520, 80}, 55, a0, a1, sg, BLACK);
        DrawRing((Vector2){520, 250}, 20, 50, a0, a1, sg, Fade(SKYBLUE, 0.5f));
        DrawRingLines((Vector2){520, 250}, 20 - ti*3, 55, a0, a1, sg, BLACK);
        if (ai < 4) {
            DrawRectangleLinesEx((Rectangle){ 300 + ai*20, 150, 60 + si*10, 40 }, t, Fade(RED, 0.5f));
            DrawRectangleRoundedLinesEx((Rectangle){ 20 + ai*5, 150, 120, 70 }, (si)*0.3f - 0.1f, sg, t*0.4f, Fade(DARKBLUE, 0.5f));
            DrawRectangleRoundedLines((Rectangle){ 160, 160, 100, 60 }, ai*0.35f, sg, BLACK);
            DrawRectangleRounded((Rectangle){ 160, 230, 100, 60 }, ai*0.35f, sg, Fade(LIME, 0.5f));
            DrawPolyLinesEx((Vector2){ 600, 180 }, 3 + si, 30, ai*10.0f, t*0.4f, Fade(BROWN, 0.6f));
            DrawEllipseLinesEx((Vector2){ 460, 170 }, 40 + si*5, 20 + ai*4, t*0.5f, Fade(VIOLET, 0.6f));
            DrawTriangleLinesEx((Vector2){ 300, 210 }, (Vector2){ 260 + si*5, 330 }, (Vector2){ 380, 300 - ai*20 }, t*0.5f, Fade(DARKGRAY, 0.6f));
            DrawCircleLinesEx((Vector2){ 60, 320 }, 25, t*0.3f, PINK);
        }
        EndDrawing();
        Image img = LoadImageFromScreen();
        ImageFormat(&img, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);
        printf("%04d t=%g a=%g..%g s=%d %08x\n", frame++, t, a0, a1, sg, crc32(img.data, (size_t)img.width*img.height*4));
        UnloadImage(img);
    }
    CloseWindow();
    return 0;
}
