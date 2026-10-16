// image_ops.c — C-vs-Zig differential for rtextures' image functions.
//
// The examples gate draws images, but most image operations, every pixel
// format conversion and the export paths are never reached unattended. This
// program runs each image operation over every uncompressed pixel format (plus
// compressed and mipmapped inputs for the warning paths), generates images,
// exports them to PNG/BMP/QOI/RAW/code and reads the bytes back, and prints a
// hash of every resulting pixel buffer and file. Every TraceLog line goes
// through a log callback, so warnings are compared too. Files land in a fresh
// temp directory and are printed by relative path. The second half opens a
// hidden window for the text and texture paths.
// Run via tools/cdiff.sh <oracle> <zig> <scarfy_run.gif>
#define _XOPEN_SOURCE 700
#include <ftw.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "raylib.h"

static void logCallback(int level, const char *text, va_list args)
{
    printf("  log %d: ", level);
    // ImageMipmaps logs a heap address: compare the format, not the value
    if (strstr(text, "offset: 0x%x")) { printf("%s\n", text); return; }
    vprintf(text, args);
    printf("\n");
}

static unsigned int hashBytes(const void *data, int size)
{
    const unsigned char *p = data;
    unsigned int h = 2166136261u;
    for (int i = 0; (p != NULL) && (i < size); i++) h = (h ^ p[i])*16777619u;
    return h;
}

static int imageBytes(Image img)
{
    int size = 0, w = img.width, h = img.height;
    for (int i = 0; i < img.mipmaps; i++)
    {
        size += GetPixelDataSize(w, h, img.format);
        w /= 2; h /= 2;
        if (w < 1) w = 1;
        if (h < 1) h = 1;
    }
    return size;
}

static void printImage(const char *what, Image img)
{
    printf("%s: %dx%d fmt=%d mips=%d %s h=%08x\n", what, img.width, img.height, img.format, img.mipmaps,
        img.data ? "D" : "-", img.data ? hashBytes(img.data, imageBytes(img)) : 0);
}

// Base level only: some operations keep `mipmaps` while dropping the levels
static void printImageBase(const char *what, Image img)
{
    img.mipmaps = 1;
    printImage(what, img);
}

static void printFile(const char *what, const char *fileName)
{
    int size = 0;
    unsigned char *data = LoadFileData(fileName, &size);
    printf("%s: size=%d h=%08x\n", what, size, hashBytes(data, size));
    UnloadFileData(data);
}

static void printColor(const char *what, Color c) { printf("%s: %d,%d,%d,%d\n", what, c.r, c.g, c.b, c.a); }

static int removeEntry(const char *path, const struct stat *st, int flag, struct FTW *ftw)
{
    (void)st; (void)flag; (void)ftw;
    return remove(path);
}

// A 37x23 RGBA image with gradients, hard edges and varying alpha
static Image baseImage(void)
{
    Image img = GenImageColor(37, 23, BLANK);
    for (int y = 0; y < img.height; y++)
    {
        for (int x = 0; x < img.width; x++)
        {
            Color c = { (unsigned char)(x*7), (unsigned char)(y*11), (unsigned char)((x*y)%256), (unsigned char)((x + y)*6) };
            if ((x > 10) && (x < 20) && (y > 5) && (y < 15)) c.a = 0;
            if ((x > 25) && (y < 8)) c = (Color){ 200, 30, 60, 255 };
            ImageDrawPixel(&img, x, y, c);
        }
    }
    return img;
}

typedef void (*ImageOp)(Image *img);

static Image g_mask;
static Image g_src;

static void opCrop(Image *i) { ImageCrop(i, (Rectangle){ 3, 2, 20, 15 }); }
static void opCropNeg(Image *i) { ImageCrop(i, (Rectangle){ -5, -5, 12, 10 }); }
static void opCropOut(Image *i) { ImageCrop(i, (Rectangle){ 100, 100, 5, 5 }); }
static void opResizeUp(Image *i) { ImageResize(i, 50, 31); }
static void opResizeDown(Image *i) { ImageResize(i, 11, 7); }
static void opResizeNNUp(Image *i) { ImageResizeNN(i, 50, 31); }
static void opResizeNNDown(Image *i) { ImageResizeNN(i, 11, 7); }
static void opCanvasGrow(Image *i) { ImageResizeCanvas(i, 45, 30, 3, 4, (Color){ 10, 200, 30, 128 }); }
static void opCanvasShrink(Image *i) { ImageResizeCanvas(i, 20, 10, -5, -3, RED); }
static void opCanvasOver(Image *i) { ImageResizeCanvas(i, 40, 25, 10, 10, BLUE); }
static void opPOT(Image *i) { ImageToPOT(i, GREEN); }
static void opAlphaCrop(Image *i) { ImageAlphaCrop(i, 0.3f); }
static void opAlphaClear(Image *i) { ImageAlphaClear(i, (Color){ 1, 2, 3, 4 }, 0.5f); }
static void opAlphaClearLow(Image *i) { ImageAlphaClear(i, ORANGE, 0.1f); }
static void opAlphaMask(Image *i) { ImageAlphaMask(i, g_mask); }
static void opPremultiply(Image *i) { ImageAlphaPremultiply(i); }
static void opBlur(Image *i) { ImageBlurGaussian(i, 2); }
static void opSharpen(Image *i) { float k[9] = { 0, -1, 0, -1, 5, -1, 0, -1, 0 }; ImageKernelConvolution(i, k, 9); }
static void opKernelEven(Image *i) { float k[16]; for (int n = 0; n < 16; n++) k[n] = 1.0f/16.0f; ImageKernelConvolution(i, k, 16); }
static void opKernelBad(Image *i) { float k[5] = { 1, 1, 1, 1, 1 }; ImageKernelConvolution(i, k, 5); }
static void opMipmaps(Image *i) { ImageMipmaps(i); }
static void opMipmapsTwice(Image *i) { ImageMipmaps(i); ImageMipmaps(i); }
static void opDither565(Image *i) { ImageDither(i, 5, 6, 5, 0); }
static void opDither5551(Image *i) { ImageDither(i, 5, 5, 5, 1); }
static void opDither4444(Image *i) { ImageDither(i, 4, 4, 4, 4); }
static void opDitherOdd(Image *i) { ImageDither(i, 3, 3, 3, 3); }
static void opDitherBig(Image *i) { ImageDither(i, 8, 8, 8, 8); }
static void opFlipV(Image *i) { ImageFlipVertical(i); }
static void opFlipH(Image *i) { ImageFlipHorizontal(i); }
static void opRotate30(Image *i) { ImageRotate(i, 30); }
static void opRotateM45(Image *i) { ImageRotate(i, -45); }
static void opRotate90(Image *i) { ImageRotate(i, 90); }
static void opRotateCW(Image *i) { ImageRotateCW(i); }
static void opRotateCCW(Image *i) { ImageRotateCCW(i); }
static void opTint(Image *i) { ImageColorTint(i, (Color){ 200, 100, 50, 180 }); }
static void opInvert(Image *i) { ImageColorInvert(i); }
static void opGrayscale(Image *i) { ImageColorGrayscale(i); }
static void opContrastUp(Image *i) { ImageColorContrast(i, 40); }
static void opContrastDown(Image *i) { ImageColorContrast(i, -160); }
static void opBrightUp(Image *i) { ImageColorBrightness(i, 50); }
static void opBrightDown(Image *i) { ImageColorBrightness(i, -300); }
static void opReplace(Image *i) { ImageColorReplace(i, (Color){ 200, 30, 60, 255 }, (Color){ 1, 2, 3, 4 }); }
static void opClear(Image *i) { ImageClearBackground(i, (Color){ 12, 34, 56, 78 }); }
static void opPixels(Image *i) { ImageDrawPixel(i, 0, 0, RED); ImageDrawPixel(i, 36, 22, BLUE); ImageDrawPixel(i, -1, 3, RED); ImageDrawPixelV(i, (Vector2){ 5.7f, 6.2f }, GREEN); }
static void opLines(Image *i)
{
    ImageDrawLine(i, 0, 0, 36, 22, RED);
    ImageDrawLine(i, 30, 2, 3, 20, (Color){ 0, 255, 0, 100 });
    ImageDrawLine(i, 5, 20, 5, 1, BLUE);
    ImageDrawLineV(i, (Vector2){ 1.4f, 2.6f }, (Vector2){ 35.5f, 10.4f }, YELLOW);
    ImageDrawLineEx(i, (Vector2){ 2, 3 }, (Vector2){ 33, 12 }, 3, MAROON);
    ImageDrawLineEx(i, (Vector2){ 20, 1 }, (Vector2){ 22, 21 }, 4, LIME);
    Vector2 strip[4] = { { 1, 1 }, { 10, 20 }, { 20, 2 }, { 35, 21 } };
    ImageDrawLineStrip(i, strip, 4, PURPLE);
}
static void opTriangles(Image *i)
{
    ImageDrawTriangle(i, (Vector2){ 2, 2 }, (Vector2){ 5, 20 }, (Vector2){ 30, 15 }, RED);
    ImageDrawTriangle(i, (Vector2){ 2, 2 }, (Vector2){ 30, 15 }, (Vector2){ 5, 20 }, (Color){ 0, 0, 255, 120 });
    ImageDrawTriangleGradient(i, (Vector2){ 10, 1 }, (Vector2){ 1, 21 }, (Vector2){ 35, 18 }, RED, GREEN, BLUE);
    ImageDrawTriangleLines(i, (Vector2){ 3, 3 }, (Vector2){ 33, 4 }, (Vector2){ 18, 21 }, YELLOW);
    Vector2 fan[5] = { { 18, 11 }, { 30, 2 }, { 35, 15 }, { 20, 22 }, { 5, 15 } };
    ImageDrawTriangleFan(i, fan, 5, (Color){ 255, 0, 255, 200 });
    ImageDrawTriangleStrip(i, fan, 5, (Color){ 0, 255, 255, 60 });
}
static void opRects(Image *i)
{
    ImageDrawRectangle(i, 2, 3, 10, 8, RED);
    ImageDrawRectangle(i, -4, -4, 10, 8, (Color){ 0, 255, 0, 128 });
    ImageDrawRectangle(i, 30, 18, 20, 20, BLUE);
    ImageDrawRectangleV(i, (Vector2){ 12.5f, 4.5f }, (Vector2){ 6.7f, 3.2f }, YELLOW);
    ImageDrawRectanglePro(i, (Rectangle){ 18, 11, 14, 6 }, (Vector2){ 7, 3 }, 33.0f, (Color){ 10, 20, 30, 200 });
    ImageDrawRectangleLines(i, 1, 1, 35, 21, WHITE);
    ImageDrawRectangleLinesEx(i, (Rectangle){ 4, 4, 28, 14 }, 2, BLACK);
    ImageDrawRectangleGradientEx(i, (Rectangle){ 3.5f, 2.25f, 25.0f, 17.5f }, RED, GREEN, BLUE, (Color){ 255, 255, 0, 100 });
}
static void opCircles(Image *i)
{
    ImageDrawCircle(i, 18, 11, 8, RED);
    ImageDrawCircleV(i, (Vector2){ 3.7f, 4.2f }, 6, (Color){ 0, 0, 255, 90 });
    ImageDrawCircleLines(i, 30, 15, 9, GREEN);
    ImageDrawCircleLinesV(i, (Vector2){ 10, 10 }, 4, YELLOW);
    ImageDrawCircleGradient(i, (Vector2){ 20.3f, 12.6f }, 9.5f, WHITE, (Color){ 0, 0, 0, 0 });
}
static void opDrawImages(Image *i)
{
    ImageDrawImage(i, g_src, 5, 4, WHITE);
    ImageDrawImage(i, g_src, -6, 15, (Color){ 255, 128, 64, 200 });
    ImageDrawImageEx(i, g_src, (Vector2){ 20, 2 }, 25.0f, 0.8f, (Color){ 200, 255, 255, 255 });
    ImageDrawImageRec(i, g_src, (Rectangle){ 2, 2, 8, 6 }, (Vector2){ 28, 15 }, WHITE);
    ImageDrawImagePro(i, g_src, (Rectangle){ 0, 0, 16, 12 }, (Rectangle){ 1, 10, 30, 9 }, (Vector2){ 0, 0 }, 0.0f, (Color){ 255, 255, 255, 128 });
}
static void opDrawSelfFormat(Image *i)
{
    // Same-format opaque source: the memcpy fast path
    Image src = ImageCopy(*i);
    ImageCrop(&src, (Rectangle){ 0, 0, 10, 8 });
    ImageDrawImage(i, src, 20, 10, WHITE);
    ImageDrawImage(i, src, 30, -2, WHITE);
    UnloadImage(src);
}

static const struct { const char *name; ImageOp op; } ops[] = {
    { "crop", opCrop }, { "cropneg", opCropNeg }, { "cropout", opCropOut },
    { "resizeup", opResizeUp }, { "resizedown", opResizeDown }, { "nnup", opResizeNNUp }, { "nndown", opResizeNNDown },
    { "canvasgrow", opCanvasGrow }, { "canvasshrink", opCanvasShrink }, { "canvasover", opCanvasOver }, { "pot", opPOT },
    { "alphacrop", opAlphaCrop }, { "alphaclear", opAlphaClear }, { "alphaclearlow", opAlphaClearLow },
    { "alphamask", opAlphaMask }, { "premultiply", opPremultiply }, { "blur", opBlur },
    { "sharpen", opSharpen }, { "kerneleven", opKernelEven }, { "kernelbad", opKernelBad },
    { "mipmaps", opMipmaps }, { "mipmaps2", opMipmapsTwice },
    { "dither565", opDither565 }, { "dither5551", opDither5551 }, { "dither4444", opDither4444 },
    { "ditherodd", opDitherOdd }, { "ditherbig", opDitherBig },
    { "flipv", opFlipV }, { "fliph", opFlipH }, { "rot30", opRotate30 }, { "rotm45", opRotateM45 }, { "rot90", opRotate90 },
    { "rotcw", opRotateCW }, { "rotccw", opRotateCCW },
    { "tint", opTint }, { "invert", opInvert }, { "gray", opGrayscale }, { "contrastup", opContrastUp },
    { "contrastdown", opContrastDown }, { "brightup", opBrightUp }, { "brightdown", opBrightDown }, { "replace", opReplace },
    { "clear", opClear }, { "pixels", opPixels }, { "lines", opLines }, { "triangles", opTriangles }, { "rects", opRects },
    { "circles", opCircles }, { "drawimages", opDrawImages }, { "drawself", opDrawSelfFormat },
};
#define OP_COUNT ((int)(sizeof(ops)/sizeof(ops[0])))

// Operations that check for compressed data before touching the pixels
static const struct { const char *name; ImageOp op; } compressedOps[] = {
    { "crop", opCrop }, { "canvasgrow", opCanvasGrow }, { "alphaclear", opAlphaClear }, { "alphamask", opAlphaMask },
    { "dither565", opDither565 }, { "flipv", opFlipV }, { "fliph", opFlipH }, { "rot30", opRotate30 },
    { "rotcw", opRotateCW }, { "rotccw", opRotateCCW }, { "drawimages", opDrawImages },
};

static void runFormat(Image base, int format)
{
    Image img = ImageCopy(base);
    ImageFormat(&img, format);
    char label[64];
    snprintf(label, sizeof(label), "fmt %d", format);
    printImage(label, img);

    for (int k = 0; k < OP_COUNT; k++)
    {
        Image work = ImageCopy(img);
        ops[k].op(&work);
        snprintf(label, sizeof(label), " %d %s", format, ops[k].name);
        printImage(label, work);
        UnloadImage(work);
    }

    // Conversions to every other format
    for (int to = 1; to <= 13; to++)
    {
        Image work = ImageCopy(img);
        ImageFormat(&work, to);
        snprintf(label, sizeof(label), " %d to %d", format, to);
        printImage(label, work);
        UnloadImage(work);
    }

    // Queries
    Color *colors = LoadImageColors(img);
    printf(" %d colors h=%08x\n", format, hashBytes(colors, img.width*img.height*4));
    UnloadImageColors(colors);
    int count = 0;
    Color *palette = LoadImagePalette(img, 16, &count);
    printf(" %d palette16 count=%d h=%08x\n", format, count, hashBytes(palette, count*4));
    UnloadImagePalette(palette);
    palette = LoadImagePalette(img, 1000, &count);
    printf(" %d palette1000 count=%d h=%08x\n", format, count, hashBytes(palette, count*4));
    UnloadImagePalette(palette);
    Rectangle border = GetImageAlphaBorder(img, 0.2f);
    printf(" %d border %g %g %g %g\n", format, border.x, border.y, border.width, border.height);
    const int points[][2] = { { 0, 0 }, { 13, 9 }, { 36, 22 }, { 30, 3 }, { 37, 0 }, { -1, 5 } };
    for (int p = 0; p < 6; p++)
    {
        snprintf(label, sizeof(label), " %d pixel %d,%d", format, points[p][0], points[p][1]);
        printColor(label, GetImageColor(img, points[p][0], points[p][1]));
    }
    for (int channel = -1; channel <= 4; channel++)
    {
        Image ch = ImageFromChannel(img, channel);
        snprintf(label, sizeof(label), " %d channel %d", format, channel);
        printImage(label, ch);
        UnloadImage(ch);
    }
    Image piece = ImageFromImage(img, (Rectangle){ 4, 3, 17, 11 });
    snprintf(label, sizeof(label), " %d fromimage", format);
    printImage(label, piece);
    UnloadImage(piece);
    piece = ImageFromImage(img, (Rectangle){ 30, 3, 17, 11 });
    printImage(" fromimage bad", piece);

    // Pixel accessors on the first pixel
    if (format <= 13)
    {
        unsigned char buffer[16] = { 0 };
        SetPixelColor(buffer, (Color){ 100, 150, 200, 30 }, format);
        printf(" %d setpixel h=%08x\n", format, hashBytes(buffer, 16));
        snprintf(label, sizeof(label), " %d getpixel", format);
        printColor(label, GetPixelColor(img.data, format));
    }

    UnloadImage(img);
}

static void runGenerators(void)
{
    printImage("gen color", GenImageColor(9, 7, (Color){ 1, 2, 3, 4 }));
    int directions[] = { 0, 45, 90, 135, 200, 310 };
    for (int d = 0; d < 6; d++)
    {
        char label[64];
        snprintf(label, sizeof(label), "gen linear %d", directions[d]);
        printImage(label, GenImageGradientLinear(31, 17, directions[d], RED, (Color){ 0, 0, 255, 100 }));
    }
    printImage("gen radial 0", GenImageGradientRadial(31, 17, 0.0f, WHITE, BLACK));
    printImage("gen radial .5", GenImageGradientRadial(17, 31, 0.5f, YELLOW, (Color){ 0, 0, 0, 0 }));
    printImage("gen square .3", GenImageGradientSquare(31, 17, 0.3f, RED, BLUE));
    printImage("gen square 0", GenImageGradientSquare(16, 16, 0.0f, GREEN, BLACK));
    printImage("gen checked", GenImageChecked(31, 17, 4, 3, RED, BLUE));
    SetRandomSeed(1234);
    printImage("gen white", GenImageWhiteNoise(31, 17, 0.3f));
    printImage("gen perlin", GenImagePerlinNoise(31, 17, 5, -3, 2.5f));
    printImage("gen perlin tall", GenImagePerlinNoise(13, 29, 0, 0, 1.0f));
    SetRandomSeed(99);
    printImage("gen cellular", GenImageCellular(31, 17, 6));
    printImage("gen text", GenImageText(8, 3, "hello raylib, this is longer than the image"));
    printImage("gen text short", GenImageText(8, 3, "hi"));
    printImage("gen text null", GenImageText(4, 2, NULL));
}

static void runExports(Image base)
{
    const int formats[] = { 1, 2, 4, 7, 3, 8 };
    for (int f = 0; f < 6; f++)
    {
        Image img = ImageCopy(base);
        ImageFormat(&img, formats[f]);
        const char *names[] = { "e.png", "e.bmp", "e.qoi", "e.raw", "e.jpg", "e.PNG" };
        for (int n = 0; n < 6; n++)
        {
            char path[64];
            snprintf(path, sizeof(path), "%d_%s", formats[f], names[n]);
            printf("export %s=%d\n", path, ExportImage(img, path));
            printFile(path, path);
        }
        UnloadImage(img);
    }
    // ExportImageToMemory trusts the format's channel count: 8-bit formats only
    const int memFormats[] = { 1, 2, 4, 7 };
    for (int f = 0; f < 4; f++)
    {
        Image img = ImageCopy(base);
        ImageFormat(&img, memFormats[f]);
        int size = -1;
        unsigned char *mem = ExportImageToMemory(img, ".png", &size);
        printf("tomemory %d png size=%d h=%08x\n", memFormats[f], size, hashBytes(mem, size));
        MemFree(mem);
        mem = ExportImageToMemory(img, ".PNG", &size);
        printf("tomemory %d PNG size=%d h=%08x\n", memFormats[f], size, hashBytes(mem, size));
        MemFree(mem);
        mem = ExportImageToMemory(img, ".bmp", &size);
        printf("tomemory %d bmp size=%d %s\n", memFormats[f], size, mem ? "D" : "-");
        UnloadImage(img);
    }
    Image empty = { 0 };
    printf("export empty=%d\n", ExportImage(empty, "empty.png"));
    int size = -1;
    printf("tomemory empty %s size=%d\n", ExportImageToMemory(empty, ".png", &size) ? "D" : "-", size);

    // Image as code: the whole text for a tiny image, a hash for larger ones
    Image tiny = GenImageColor(3, 2, (Color){ 0, 9, 10, 255 });
    ImageDrawPixel(&tiny, 1, 1, (Color){ 171, 205, 239, 1 });
    printf("code tiny=%d\n", ExportImageAsCode(tiny, "my-tiny_img.v2.h"));
    char *text = LoadFileText("my-tiny_img.v2.h");
    printf("[%s]\n", text);
    UnloadFileText(text);
    UnloadImage(tiny);
    Image img = ImageCopy(base);
    printf("code base=%d\n", ExportImageAsCode(img, "Base Image.h"));
    printFile("code base", "Base Image.h");
    ImageFormat(&img, 2);
    printf("code ga=%d\n", ExportImageAsCode(img, "ga.h"));
    printFile("code ga", "ga.h");
    printf("code nodir=%d\n", ExportImageAsCode(img, "nodir/x.h"));
    UnloadImage(img);
}

static void runLoaders(Image base, const char *gifPath)
{
    Image img = LoadImage("7_e.png");
    printImage("load png", img);
    UnloadImage(img);
    printImage("load gray png", img = LoadImage("1_e.png"));
    UnloadImage(img);
    printImage("load ga png", img = LoadImage("2_e.png"));
    UnloadImage(img);
    printImage("load rgb png", img = LoadImage("4_e.png"));
    UnloadImage(img);
    printImage("load bmp", img = LoadImage("7_e.bmp"));
    UnloadImage(img);
    printImage("load qoi", img = LoadImage("7_e.qoi"));
    UnloadImage(img);
    printImage("load qoi rgb", img = LoadImage("4_e.qoi"));
    UnloadImage(img);
    printImage("load missing", LoadImage("missing.png"));
    printImage("load unsupported", LoadImage("7_e.raw"));

    // Raw, with and without a header
    unsigned char header[16] = { 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9 };
    int rawSize = 0;
    unsigned char *raw = LoadFileData("7_e.raw", &rawSize);
    unsigned char *withHeader = MemAlloc(rawSize + 16);
    memcpy(withHeader, header, 16);
    memcpy(withHeader + 16, raw, rawSize);
    SaveFileData("h.raw", withHeader, rawSize + 16);
    MemFree(withHeader);
    UnloadFileData(raw);
    printImage("raw", img = LoadImageRaw("7_e.raw", 37, 23, 7, 0));
    UnloadImage(img);
    printImage("raw header", img = LoadImageRaw("h.raw", 37, 23, 7, 16));
    UnloadImage(img);
    printImage("raw header too big", img = LoadImageRaw("h.raw", 37, 23, 7, 64));
    UnloadImage(img);
    printImage("raw too small", LoadImageRaw("7_e.raw", 100, 100, 7, 0));
    printImage("raw missing", LoadImageRaw("missing.raw", 4, 4, 7, 0));

    // Animations
    int frames = -1;
    img = LoadImageAnim(gifPath, &frames);
    printf("anim frames=%d\n", frames);
    printImage("anim gif", img);
    UnloadImage(img);
    img = LoadImageAnim("7_e.png", &frames);
    printf("anim png frames=%d\n", frames);
    printImage("anim png", img);
    UnloadImage(img);
    int gifSize = 0;
    unsigned char *gif = LoadFileData(gifPath, &gifSize);
    img = LoadImageAnimFromMemory(".gif", gif, gifSize, &frames);
    printf("animmem frames=%d\n", frames);
    printImage("animmem gif", img);
    UnloadImage(img);
    img = LoadImageAnimFromMemory(".GIF", gif, gifSize, &frames);
    printf("animmem GIF frames=%d\n", frames);
    UnloadImage(img);
    frames = -1;
    img = LoadImageAnimFromMemory(NULL, gif, gifSize, &frames);
    printf("animmem null frames=%d %s\n", frames, img.data ? "D" : "-");
    img = LoadImageAnimFromMemory(".gif", gif, 0, &frames);
    printf("animmem empty frames=%d %s\n", frames, img.data ? "D" : "-");

    // From memory
    printImage("mem gif", img = LoadImageFromMemory(".gif", gif, gifSize));
    UnloadImage(img);
    printImage("mem GIF", img = LoadImageFromMemory(".GIF", gif, gifSize));
    UnloadImage(img);
    UnloadFileData(gif);
    int pngSize = 0;
    unsigned char *png = LoadFileData("7_e.png", &pngSize);
    printImage("mem png", img = LoadImageFromMemory(".png", png, pngSize));
    UnloadImage(img);
    printImage("mem PNG", img = LoadImageFromMemory(".PNG", png, pngSize));
    UnloadImage(img);
    printImage("mem null type", LoadImageFromMemory(NULL, png, pngSize));
    printImage("mem null data", LoadImageFromMemory(".png", NULL, pngSize));
    printImage("mem zero", LoadImageFromMemory(".png", png, 0));
    printImage("mem jpg", LoadImageFromMemory(".jpg", png, pngSize));
    printImage("mem png as bmp", LoadImageFromMemory(".bmp", png, pngSize));
    img = LoadImageAnimFromMemory(".png", png, pngSize, &frames);
    printf("animmem png frames=%d\n", frames);
    printImage("animmem png", img);
    UnloadImage(img);
    UnloadFileData(png);
    int qoiSize = 0;
    unsigned char *qoi = LoadFileData("7_e.qoi", &qoiSize);
    printImage("mem qoi", img = LoadImageFromMemory(".QOI", qoi, qoiSize));
    UnloadImage(img);
    UnloadFileData(qoi);

    printf("valid base=%d empty=%d\n", IsImageValid(base), IsImageValid((Image){ 0 }));
}

static void runColors(void)
{
    Color c = { 200, 100, 50, 180 };
    printColor("fade", Fade(c, 0.37f));
    printColor("fade hi", Fade(c, 3.0f));
    printColor("fade lo", Fade(c, -1.0f));
    printf("toint %d\n", ColorToInt(c));
    Vector4 n = ColorNormalize(c);
    printf("normalize %.9g %.9g %.9g %.9g\n", n.x, n.y, n.z, n.w);
    printColor("fromnormalized", ColorFromNormalized((Vector4){ 0.1f, 0.5f, 0.999f, 0.3f }));
    Color hsvCases[] = { { 200, 100, 50, 255 }, { 0, 0, 0, 255 }, { 10, 200, 30, 255 }, { 10, 20, 230, 255 }, { 77, 77, 77, 255 }, { 255, 0, 255, 255 } };
    for (int i = 0; i < 6; i++)
    {
        Vector3 hsv = ColorToHSV(hsvCases[i]);
        printf("tohsv %.9g %.9g %.9g\n", hsv.x, hsv.y, hsv.z);
    }
    for (float h = -30.0f; h < 420.0f; h += 37.5f) printColor("fromhsv", ColorFromHSV(h, 0.7f, 0.9f));
    printColor("tint", ColorTint(c, (Color){ 128, 255, 3, 200 }));
    for (float f = -1.5f; f <= 1.5f; f += 0.5f)
    {
        printColor("brightness", ColorBrightness(c, f));
        printColor("contrast", ColorContrast(c, f));
        printColor("alpha", ColorAlpha(c, f));
        printColor("lerp", ColorLerp(c, (Color){ 0, 255, 128, 0 }, f));
    }
    Color dsts[] = { { 10, 20, 30, 255 }, { 10, 20, 30, 0 }, { 10, 20, 30, 128 } };
    Color srcs[] = { { 200, 100, 50, 0 }, { 200, 100, 50, 255 }, { 200, 100, 50, 77 } };
    for (int d = 0; d < 3; d++) for (int s = 0; s < 3; s++) printColor("blend", ColorAlphaBlend(dsts[d], srcs[s], (Color){ 255, 200, 100, 220 }));
    printf("equal %d %d\n", ColorIsEqual(c, c), ColorIsEqual(c, (Color){ 200, 100, 50, 181 }));
    printColor("getcolor", GetColor(0x12345678));
    for (int format = 0; format <= 25; format++)
    {
        printf("datasize %d: %d %d %d %d\n", format, GetPixelDataSize(37, 23, format), GetPixelDataSize(2, 3, format),
            GetPixelDataSize(0, 3, format), GetPixelDataSize(5, 2, format));
    }
    printf("datasize huge: %d\n", GetPixelDataSize(40000, 40000, 7));
}

static void runSpecialInputs(Image base)
{
    // Compressed data: every operation should refuse with a warning
    Image comp = { MemAlloc(GetPixelDataSize(16, 16, PIXELFORMAT_COMPRESSED_DXT1_RGB)), 16, 16, 1, PIXELFORMAT_COMPRESSED_DXT1_RGB };
    for (int k = 0; k < (int)(sizeof(compressedOps)/sizeof(compressedOps[0])); k++)
    {
        Image work = ImageCopy(comp);
        compressedOps[k].op(&work);
        char label[64];
        snprintf(label, sizeof(label), "comp %s", compressedOps[k].name);
        printImage(label, work);
        UnloadImage(work);
    }
    Image work = ImageCopy(comp);
    ImageFormat(&work, 7);
    printImage("comp format", work);
    UnloadImage(work);
    printImage("comp fromimage", ImageFromImage(comp, (Rectangle){ 0, 0, 4, 4 }));
    printColor("comp getcolor", GetImageColor(comp, 1, 1));
    UnloadImage(comp);

    // Mipmapped input: operations warn they only touch the base level
    Image mip = ImageCopy(base);
    ImageMipmaps(&mip);
    printImage("mip", mip);
    for (int k = 0; k < OP_COUNT; k++)
    {
        if (ops[k].op == opDrawSelfFormat) continue; // would recurse into mip levels the crop dropped
        Image w = ImageCopy(mip);
        ops[k].op(&w);
        char label[64];
        snprintf(label, sizeof(label), "mip %s", ops[k].name);
        printImageBase(label, w);
        UnloadImage(w);
    }
    Image mip2 = ImageCopy(mip);
    ImageFormat(&mip2, 4);
    printImage("mip format", mip2);
    ImageDrawImage(&mip2, mip, 3, 3, WHITE);
    printImage("mip draw mip", mip2);
    UnloadImage(mip2);
    UnloadImage(mip);

    // Mask size mismatch, empty images
    Image img = ImageCopy(base);
    Image small = GenImageColor(4, 4, WHITE);
    ImageAlphaMask(&img, small);
    printImage("mask mismatch", img);
    ImageFormat(&img, 1);
    Image mask = ImageCopy(g_mask);
    ImageAlphaMask(&img, mask);
    printImage("mask gray", img);
    UnloadImage(mask);
    UnloadImage(small);
    UnloadImage(img);
    Image empty = { 0 };
    ImageCrop(&empty, (Rectangle){ 0, 0, 1, 1 });
    ImageResize(&empty, 4, 4);
    ImageFormat(&empty, 1);
    ImageDrawPixel(&empty, 0, 0, RED);
    printImage("empty", empty);
    printImage("empty copy", ImageCopy(empty));
    printf("empty colors %s\n", LoadImageColors(empty) ? "D" : "-");
    int count = -1;
    printf("empty palette %s count=%d\n", LoadImagePalette(empty, 8, &count) ? "D" : "-", count);
}

int main(int argc, char **argv)
{
    if (argc < 2) return 2;
    char gifPath[4096];
    if (!realpath(argv[1], gifPath)) return 2;

    char root[] = "/tmp/rlimageops_XXXXXX";
    if (!mkdtemp(root) || chdir(root) != 0) return 2;

    SetTraceLogLevel(LOG_ALL);
    SetTraceLogCallback(logCallback);

    Image base = baseImage();
    printImage("base", base);
    g_mask = GenImageGradientLinear(37, 23, 30, WHITE, BLACK);
    g_src = baseImage();
    ImageResize(&g_src, 15, 11);

    runGenerators();
    for (int format = 1; format <= 13; format++) runFormat(base, format);
    runSpecialInputs(base);
    runExports(base);
    runLoaders(base, gifPath);
    runColors();

    // Text and textures need a GL context
    SetTraceLogCallback(NULL);
    SetTraceLogLevel(LOG_NONE);
    SetConfigFlags(FLAG_WINDOW_HIDDEN);
    InitWindow(64, 64, "image_ops");
    SetTraceLogLevel(LOG_ALL);
    SetTraceLogCallback(logCallback);

    Image text = ImageText("Hello, raylib!\nline 2", 10, RED);
    printImage("text 10", text);
    UnloadImage(text);
    printImage("text 23", text = ImageText("Scaled text", 23, (Color){ 0, 128, 255, 200 }));
    UnloadImage(text);
    printImage("text tiny", text = ImageText("tiny", 4, WHITE));
    UnloadImage(text);
    printImage("textex", text = ImageTextEx(GetFontDefault(), "Ex text\twith tab", 15.0f, 2.5f, GREEN));
    UnloadImage(text);
    printImage("textex null", ImageTextEx(GetFontDefault(), NULL, 15.0f, 2.5f, GREEN));
    for (int format = 1; format <= 13; format++)
    {
        Image img = ImageCopy(base);
        ImageFormat(&img, format);
        ImageDrawText(&img, "Hi!", 2, 3, 10, YELLOW);
        ImageDrawTextEx(&img, GetFontDefault(), "ok", (Vector2){ 15.5f, 9.0f }, 20.0f, 1.0f, (Color){ 255, 0, 0, 128 });
        char label[64];
        snprintf(label, sizeof(label), "drawtext %d", format);
        printImage(label, img);
        UnloadImage(img);
    }

    // GPU round trip
    const int texFormats[] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    for (int f = 0; f < 10; f++)
    {
        Image img = ImageCopy(base);
        ImageFormat(&img, texFormats[f]);
        Texture2D tex = LoadTextureFromImage(img);
        printf("tex %d valid=%d %dx%d fmt=%d mips=%d\n", texFormats[f], IsTextureValid(tex), tex.width, tex.height, tex.format, tex.mipmaps);
        Image back = LoadImageFromTexture(tex);
        char label[64];
        snprintf(label, sizeof(label), "texback %d", texFormats[f]);
        printImage(label, back);
        UnloadImage(back);
        UnloadTexture(tex);
        UnloadImage(img);
    }
    Image mip = ImageCopy(base);
    ImageMipmaps(&mip);
    Texture2D tex = LoadTextureFromImage(mip);
    printf("tex mip mips=%d\n", tex.mipmaps);
    SetTextureFilter(tex, TEXTURE_FILTER_TRILINEAR);
    SetTextureWrap(tex, TEXTURE_WRAP_MIRROR_REPEAT);
    UnloadTexture(tex);
    UnloadImage(mip);
    tex = LoadTextureFromImage(base);
    SetTextureFilter(tex, TEXTURE_FILTER_TRILINEAR);
    GenTextureMipmaps(&tex);
    printf("gen mipmaps mips=%d\n", tex.mipmaps);
    UnloadTexture(tex);
    tex = LoadTextureFromImage((Image){ 0 });
    printf("tex empty id=%d\n", tex.id);
    Image comp = { MemAlloc(128), 16, 16, 1, PIXELFORMAT_COMPRESSED_DXT1_RGB };
    tex = (Texture2D){ 0, 16, 16, 1, PIXELFORMAT_COMPRESSED_DXT1_RGB };
    printImage("texback compressed", LoadImageFromTexture(tex));
    UnloadImage(comp);

    // Cubemaps in every layout
    struct { int w, h, layout; } cubes[] = {
        { 16, 96, CUBEMAP_LAYOUT_AUTO_DETECT }, { 96, 16, CUBEMAP_LAYOUT_AUTO_DETECT }, { 48, 64, CUBEMAP_LAYOUT_AUTO_DETECT },
        { 64, 48, CUBEMAP_LAYOUT_AUTO_DETECT }, { 30, 30, CUBEMAP_LAYOUT_AUTO_DETECT }, { 16, 96, CUBEMAP_LAYOUT_LINE_VERTICAL },
        { 96, 16, CUBEMAP_LAYOUT_LINE_HORIZONTAL }, { 48, 64, CUBEMAP_LAYOUT_CROSS_THREE_BY_FOUR },
        { 64, 48, CUBEMAP_LAYOUT_CROSS_FOUR_BY_THREE },
    };
    for (int i = 0; i < 9; i++)
    {
        Image img = GenImageGradientLinear(cubes[i].w, cubes[i].h, 45, RED, BLUE);
        TextureCubemap cube = LoadTextureCubemap(img, cubes[i].layout);
        printf("cube %dx%d layout=%d: %s %dx%d fmt=%d mips=%d\n", cubes[i].w, cubes[i].h, cubes[i].layout,
            cube.id ? "id" : "0", cube.width, cube.height, cube.format, cube.mipmaps);
        UnloadTexture(cube);
        UnloadImage(img);
    }
    Image cubeImg = GenImageChecked(64, 48, 4, 4, RED, GREEN);
    ImageMipmaps(&cubeImg);
    TextureCubemap cube = LoadTextureCubemap(cubeImg, CUBEMAP_LAYOUT_CROSS_FOUR_BY_THREE);
    printf("cube mip: %s mips=%d\n", cube.id ? "id" : "0", cube.mipmaps);
    UnloadTexture(cube);
    UnloadImage(cubeImg);

    RenderTexture2D target = LoadRenderTexture(32, 16);
    printf("render valid=%d %dx%d\n", IsRenderTextureValid(target), target.texture.width, target.texture.height);
    UnloadRenderTexture(target);
    target = LoadRenderTextureEx(8, 8, PIXELFORMAT_COMPRESSED_DXT1_RGB);
    printf("render compressed id=%d\n", target.id);

    SetTraceLogCallback(NULL);
    SetTraceLogLevel(LOG_NONE);
    CloseWindow();

    UnloadImage(base);
    UnloadImage(g_mask);
    UnloadImage(g_src);
    if (chdir("/tmp") != 0) return 2;
    nftw(root, removeEntry, 16, FTW_DEPTH | FTW_PHYS);
    return 0;
}
