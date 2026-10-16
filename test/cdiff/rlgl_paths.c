// rlgl_paths.c — C-vs-Zig differential for rlgl paths the examples don't reach.
//
// The examples only see rlgl through what they render. This drives rlgl
// directly: a render batch loaded before the GPU is ready, a user render
// batch (its CPU arrays, index pattern and draw-call table, then drawing
// through it past its limit), the default shader locations, texture format
// tables and names for every format id (invalid ones too), shader compile and
// link failures (their info logs), screen and texture readback for odd and
// even sizes and an unsupported format, automatic mipmaps for POT and NPOT
// textures, sampler slots, and indexed draws with an offset into the bound
// element buffer. Every TraceLog line is printed. Needs a display
// (tools/cdiff.sh sets llvmpipe).
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "raylib.h"
#include "rlgl.h"
#include "raymath.h"

static void logCallback(int level, const char *text, va_list args)
{
    // InitWindow's "> rshapes:... loaded (optional)" module list is rcore's,
    // and rcore.zig does not print it: not an rlgl matter, skipped here
    if (strstr(text, "(optional)") != NULL) return;
    printf("  log %d: ", level);
    vprintf(text, args);
    printf("\n");
}

static uint32_t crc32(const unsigned char *p, size_t n)
{
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) { c ^= p[i]; for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (uint32_t)(-(int)(c & 1))); }
    return c ^ 0xFFFFFFFFu;
}

static void printBatch(const char *what, rlRenderBatch b)
{
    printf("== %s: bufferCount=%d currentBuffer=%d drawCounter=%d depth=%a vertexBuffer=%s draws=%s\n", what,
        b.bufferCount, b.currentBuffer, b.drawCounter, b.currentDepth, b.vertexBuffer ? "set" : "NULL", b.draws ? "set" : "NULL");
    for (int i = 0; i < b.bufferCount; i++) {
        rlVertexBuffer vb = b.vertexBuffer[i];
        int e = vb.elementCount;
        printf("  vb[%d] elements=%d vao=%s crc v=%08x t=%08x n=%08x c=%08x i=%08x\n", i, e, vb.vaoId ? "set" : "0",
            crc32((unsigned char *)vb.vertices, e*12*sizeof(float)), crc32((unsigned char *)vb.texcoords, e*8*sizeof(float)),
            crc32((unsigned char *)vb.normals, e*12*sizeof(float)), crc32(vb.colors, e*16),
            crc32((unsigned char *)vb.indices, e*6*sizeof(vb.indices[0])));
        printf("  indices:");
        for (int k = 0; k < 12; k++) printf(" %u", (unsigned int)vb.indices[k]);
        printf("\n");
    }
    if (b.draws) {
        unsigned int sum = 0;
        for (int i = 0; i < 256; i++) sum = sum*31 + (unsigned int)b.draws[i].mode*7 + (unsigned int)b.draws[i].vertexCount*3 + (unsigned int)b.draws[i].vertexAlignment + b.draws[i].textureId;
        printf("  draws sum=%08x first: mode=%d count=%d align=%d tex=%u\n", sum, b.draws[0].mode, b.draws[0].vertexCount, b.draws[0].vertexAlignment, b.draws[0].textureId);
    }
}

static void readScreen(int w, int h)
{
    unsigned char *pixels = rlReadScreenPixels(w, h);
    printf("== rlReadScreenPixels %dx%d: %s crc=%08x\n", w, h, pixels ? "set" : "NULL", pixels ? crc32(pixels, (size_t)w*h*4) : 0);
    free(pixels);
}

static void readTexture(const char *what, Image image)
{
    Texture2D tex = LoadTextureFromImage(image);
    int size = GetPixelDataSize(image.width, image.height, image.format);
    void *pixels = rlReadTexturePixels(tex.id, tex.width, tex.height, tex.format);
    printf("== rlReadTexturePixels %s %dx%d fmt=%d: %s crc=%08x\n", what, tex.width, tex.height, tex.format,
        pixels ? "set" : "NULL", pixels ? crc32(pixels, size) : 0);
    free(pixels);

    int mipmaps = 1;
    rlGenTextureMipmaps(tex.id, tex.width, tex.height, tex.format, &mipmaps);
    printf("  mipmaps=%d\n", mipmaps);
    UnloadTexture(tex);
}

static void frameCrc(const char *what)
{
    unsigned char *pixels = rlReadScreenPixels(GetRenderWidth(), GetRenderHeight());
    printf("== frame %s crc=%08x\n", what, crc32(pixels, (size_t)GetRenderWidth()*GetRenderHeight()*4));
    free(pixels);
}

static const char *badVs = "#version 330\nvoid main() { gl_Position = undefinedThing; }\n";
static const char *goodVs =
    "#version 330\nin vec3 vertexPosition;\nuniform mat4 mvp;\nuniform vec4 shared;\n"
    "void main() { gl_Position = mvp*vec4(vertexPosition, 1.0) + shared; }\n";
static const char *linkFs =
    "#version 330\nuniform vec3 shared;\nout vec4 finalColor;\n"
    "void main() { finalColor = vec4(shared, 1.0); }\n";

int main(void)
{
    SetTraceLogCallback(logCallback);
    SetTraceLogLevel(LOG_ALL);

    printBatch("before InitWindow", rlLoadRenderBatch(1, 16));

    SetConfigFlags(FLAG_WINDOW_HIDDEN);
    InitWindow(320, 180, "rlgl paths");

    int *locs = rlGetShaderLocsDefault();
    printf("== default shader locs:");
    for (int i = 0; i < 32; i++) printf(" %d", locs[i]);
    printf("\n");

    printf("== texture formats\n");
    for (int format = -1; format <= 26; format++) {
        unsigned int internal = 1, glFormat = 2, glType = 3;
        rlGetGlTextureFormats(format, &internal, &glFormat, &glType);
        printf("  %d %s: %#x %#x %#x\n", format, rlGetPixelFormatName((unsigned int)format), internal, glFormat, glType);
    }

    printf("== shaders\n");
    printf("  bad vs id=%u\n", rlLoadShader(badVs, RL_VERTEX_SHADER));
    printf("  bad program id=%s\n", rlLoadShaderProgram(badVs, NULL) == rlGetShaderIdDefault() ? "default" : "other");
    unsigned int linked = rlLoadShaderProgram(goodVs, linkFs);
    printf("  link program id=%s\n", linked == rlGetShaderIdDefault() ? "default" : "other");

    // A user render batch, small enough to overflow
    rlRenderBatch batch = rlLoadRenderBatch(2, 64);
    printBatch("user batch", batch);
    BeginDrawing();
    ClearBackground(RAYWHITE);
    rlSetRenderBatchActive(&batch);
    for (int i = 0; i < 300; i++) DrawRectangle((i*7)%300, (i*13)%160, 9, 7, (Color){ (unsigned char)i, (unsigned char)(i*3), (unsigned char)(i*5), 200 });
    for (int i = 0; i < 40; i++) DrawLine(i*8, 0, 320 - i*8, 180, DARKBLUE);
    for (int i = 0; i < 40; i++) DrawTriangle((Vector2){ i*8.0f, 10 }, (Vector2){ i*8.0f + 4, 30 }, (Vector2){ i*8.0f + 8, 10 }, MAROON);
    rlSetRenderBatchActive(NULL);
    EndDrawing();
    printBatch("user batch after drawing", batch);
    frameCrc("user batch");
    rlUnloadRenderBatch(batch);

    // rlColor4f/rlColor3f with components outside 0..1 and NaN: C's
    // (unsigned char)(x*255) on x86-64 truncates through int
    rlRenderBatch colors = rlLoadRenderBatch(1, 16);
    rlSetRenderBatchActive(&colors);
    const float odd[] = { 0.0f, 1.0f, 0.5f, 1.5f, -0.5f, 2.0f, -2.0f, 300.0f, -1e9f, 1e9f, 0.0f/0.0f, 1.0f/0.0f };
    rlBegin(RL_QUADS);
    for (int i = 0; i < 12; i += 4) {
        rlColor4f(odd[i], odd[i + 1], odd[i + 2], odd[i + 3]); rlVertex2f(0, 0);
        rlColor3f(odd[i + 1], odd[i + 2], odd[i + 3]); rlVertex2f(1, 0);
        rlColor4f(odd[i + 3], odd[i], odd[i + 1], odd[i + 2]); rlVertex2f(1, 1);
        rlColor3f(odd[i + 2], odd[i + 3], odd[i]); rlVertex2f(0, 1);
    }
    rlEnd();
    printf("odd colors:");
    for (int i = 0; i < 48; i++) printf(" %u", colors.vertexBuffer[0].colors[i]);
    printf("\n");
    rlSetRenderBatchActive(NULL);
    rlUnloadRenderBatch(colors);

    // Indexed draws with an offset into the bound element buffer, and sampler slots
    Mesh cube = GenMeshCube(1.0f, 1.0f, 1.0f);
    Texture2D tex = LoadTextureFromImage(GenImageChecked(8, 8, 2, 2, RED, BLUE));
    Camera3D camera = { { 2.0f, 2.0f, 2.0f }, { 0.0f, 0.0f, 0.0f }, { 0.0f, 1.0f, 0.0f }, 60.0f, CAMERA_PERSPECTIVE };
    BeginDrawing();
    ClearBackground(RAYWHITE);
    BeginMode3D(camera);
    rlDrawRenderBatchActive();
    rlEnableShader(rlGetShaderIdDefault());
    rlSetUniformMatrix(locs[SHADER_LOC_MATRIX_MVP], MatrixMultiply(rlGetMatrixModelview(), rlGetMatrixProjection()));
    float white[4] = { 1, 1, 1, 1 };
    rlSetUniform(locs[SHADER_LOC_COLOR_DIFFUSE], white, SHADER_UNIFORM_VEC4, 1);
    rlSetUniformSampler(5, tex.id);
    rlSetUniformSampler(6, tex.id);
    rlSetUniformSampler(7, tex.id + 100);
    rlActiveTextureSlot(0);
    rlEnableTexture(tex.id);
    rlEnableVertexArray(cube.vaoId);
    rlDrawVertexArrayElements(6, 12, 0);
    rlDrawVertexArrayElementsInstanced(24, 6, 0, 1);
    rlDisableVertexArray();
    rlDisableTexture();
    rlDisableShader();
    EndMode3D();
    EndDrawing();
    frameCrc("indexed offset");
    UnloadTexture(tex);
    UnloadMesh(cube);

    // Screen readback: odd and even heights, a single row, an empty read
    BeginDrawing();
    ClearBackground(RAYWHITE);
    for (int y = 0; y < 180; y += 3) DrawRectangle(0, y, 320, 2, (Color){ (unsigned char)y, 0, (unsigned char)(255 - y), 255 });
    DrawRectangle(10, 10, 50, 50, Fade(GREEN, 0.5f));
    EndDrawing();
    readScreen(320, 180);
    readScreen(320, 7);
    readScreen(17, 8);
    readScreen(5, 1);
    readScreen(0, 0);

    // Texture readback and mipmaps
    readTexture("rgba8 pot", GenImageGradientLinear(64, 32, 30, RED, BLUE));
    Image gray = GenImageGradientRadial(30, 20, 0.2f, WHITE, BLACK);
    ImageFormat(&gray, PIXELFORMAT_UNCOMPRESSED_GRAYSCALE);
    readTexture("gray npot", gray);
    Image r32 = GenImageChecked(16, 16, 4, 4, WHITE, BLACK);
    ImageFormat(&r32, PIXELFORMAT_UNCOMPRESSED_R32);
    readTexture("r32", r32);
    Image rgb = GenImageChecked(7, 5, 2, 2, YELLOW, PURPLE);
    ImageFormat(&rgb, PIXELFORMAT_UNCOMPRESSED_R8G8B8);
    readTexture("rgb odd", rgb);
    printf("== rlReadTexturePixels dxt1: %s\n", rlReadTexturePixels(1, 4, 4, RL_PIXELFORMAT_COMPRESSED_DXT1_RGB) ? "set" : "NULL");

    CloseWindow();
    return 0;
}
