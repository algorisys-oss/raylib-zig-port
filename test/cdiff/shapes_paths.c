// shapes_paths.c — C-vs-Zig differential for rshapes' point-list functions.
//
// The examples draw splines, strips and fans with one fixed point list, and
// switch spline types only on key presses. This draws every point-list
// function over point counts from too-few to odd and even (so partial
// trailing Bezier segments and both triangle-strip windings occur), with
// repeated points (zero-length segments), printing a CRC32 per frame, and
// checks CheckCollisionPointPoly over a grid for convex, concave and
// degenerate polygons. Needs a display (tools/cdiff.sh sets llvmpipe).
#include "raylib.h"
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

static uint32_t crc32(const unsigned char *p, size_t n)
{
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) { c ^= p[i]; for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (uint32_t)(-(int)(c & 1))); }
    return c ^ 0xFFFFFFFFu;
}

static void frameCrc(int count)
{
    Image frame = LoadImageFromScreen();
    printf("frame count=%d crc=%08x\n", count, crc32(frame.data, (size_t)frame.width*frame.height*4));
    UnloadImage(frame);
}

int main(void)
{
    SetTraceLogLevel(LOG_ERROR);
    SetConfigFlags(FLAG_WINDOW_HIDDEN);
    InitWindow(480, 320, "shapes paths");

    Vector2 points[12] = {
        { 40, 60 }, { 120, 20 }, { 120, 20 }, { 200, 140 }, { 260, 40 }, { 330, 180 },
        { 300, 260 }, { 220, 300 }, { 150, 230 }, { 90, 290 }, { 30, 200 }, { 60, 120 },
    };

    for (int count = 0; count <= 12; count++) {
        BeginDrawing();
        ClearBackground(RAYWHITE);
        DrawLineStrip(points, count, BLACK);
        DrawTriangleFan(points, count, Fade(GOLD, 0.5f));
        DrawTriangleStrip(points, count, Fade(SKYBLUE, 0.5f));
        DrawSplineLinear(points, count, 3.0f, Fade(RED, 0.6f));
        DrawSplineBasis(points, count, 4.0f, Fade(BLUE, 0.6f));
        DrawSplineCatmullRom(points, count, 2.0f, Fade(DARKGREEN, 0.6f));
        DrawSplineBezierQuadratic(points, count, 5.0f, Fade(PURPLE, 0.5f));
        DrawSplineBezierCubic(points, count, 6.0f, Fade(ORANGE, 0.5f));
        if (count >= 2) DrawLineBezier(points[count - 2], points[count - 1], 2.0f + count, MAROON);
        EndDrawing();
        frameCrc(count);
    }

    Vector2 square[4] = { { 10, 10 }, { 90, 10 }, { 90, 90 }, { 10, 90 } };
    Vector2 concave[6] = { { 10, 10 }, { 90, 10 }, { 50, 50 }, { 90, 90 }, { 10, 90 }, { 30, 50 } };
    Vector2 flat[3] = { { 10, 50 }, { 50, 50 }, { 90, 50 } };
    struct { const char *name; Vector2 *points; int count; } polys[] = {
        { "square", square, 4 }, { "concave", concave, 6 }, { "flat", flat, 3 }, { "two", square, 2 }, { "spline", points, 12 },
    };
    for (int p = 0; p < 5; p++) {
        unsigned int bits = 0, inside = 0;
        for (int y = -5; y <= 330; y += 7) for (int x = -5; x <= 340; x += 7) {
            bool hit = CheckCollisionPointPoly((Vector2){ x + 0.5f, y + 0.25f }, polys[p].points, polys[p].count);
            bits = bits*33 + hit;
            inside += hit;
        }
        printf("poly %s: inside=%u hash=%08x\n", polys[p].name, inside, bits);
    }

    CloseWindow();
    return 0;
}
