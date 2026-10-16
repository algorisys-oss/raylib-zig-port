// audio_wave.c — C-vs-Zig differential for raudio's Wave and stream edges.
//
// test/audiocheck.c hashes the happy paths (decode, one crop, three formats,
// one 16-bit export). This program pins what it doesn't: ExportWaveAsCode's
// exact text for 8/16/32-bit data (float formatting ties, signs, inf/nan,
// variable-name upper-casing), ExportWave for every format and its failure
// paths, WaveCrop/WaveFormat/WaveCopy edge cases, LoadWaveSamples per sample
// size, loaders fed bad data or the wrong extension, and the stream update
// warnings. Every TraceLog line goes through a log callback so log text and
// level are compared too. Paths are relative to a fresh temp directory so both
// runs print the same text. Run via tools/cdiff.sh.
#define _XOPEN_SOURCE 700
#include <ftw.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include "raylib.h"

#define RES "/home/rajesh/opensource/graphics/raylib-6.2/examples/audio/resources/"

static void logCallback(int level, const char *text, va_list args)
{
    printf("  log %d: ", level);
    vprintf(text, args);
    printf("\n");
}

static unsigned int hashBytes(const void *data, size_t size)
{
    const unsigned char *p = data;
    unsigned int sum = 0;
    for (size_t i = 0; i < size; i++) sum = sum*31 + p[i];
    return sum;
}

static void printWave(const char *what, Wave w)
{
    size_t size = (size_t)w.frameCount*w.channels*(w.sampleSize/8);
    printf("%s: frames=%u rate=%u bits=%u ch=%u data=%s valid=%d sum=%08x\n", what,
           w.frameCount, w.sampleRate, w.sampleSize, w.channels, w.data ? "yes" : "NULL",
           IsWaveValid(w), w.data ? hashBytes(w.data, size) : 0);
}

static void printFile(const char *what, const char *path, int full)
{
    int size = 0;
    unsigned char *data = LoadFileData(path, &size);
    printf("%s: size=%d sum=%08x\n", what, size, data ? hashBytes(data, (size_t)size) : 0);
    if (full && data) { fwrite(data, 1, (size_t)size, stdout); printf("<EOF>\n"); }
    UnloadFileData(data);
}

static Wave makeWave(unsigned int frames, unsigned int rate, unsigned int bits, unsigned int ch)
{
    Wave w = { frames, rate, bits, ch, NULL };
    size_t size = (size_t)frames*ch*(bits/8);
    unsigned char *data = MemAlloc((unsigned int)(size ? size : 1));
    if (bits == 16)
    {
        // Small, smooth-ish samples: the QOA encoder overflows int on noise
        short *samples = (short *)data;
        for (size_t i = 0; i < size/2; i++) samples[i] = (short)((int)((i*97) % 2000) - 1000);
    }
    else for (size_t i = 0; i < size; i++) data[i] = (unsigned char)(i*37 + 11);
    w.data = data;
    return w;
}

static void processorA(void *buffer, unsigned int frames) { (void)buffer; (void)frames; }
static void processorB(void *buffer, unsigned int frames) { (void)buffer; (void)frames; }

static int removeEntry(const char *path, const struct stat *st, int flag, struct FTW *ftw)
{
    (void)st; (void)flag; (void)ftw;
    return remove(path);
}

int main(void)
{
    char root[] = "/tmp/rlaudiowave_XXXXXX";
    if (!mkdtemp(root) || chdir(root) != 0) return 2;

    SetTraceLogLevel(LOG_ALL);
    SetTraceLogCallback(logCallback);

    // --- Synthetic waves ---
    Wave w8 = makeWave(45, 8000, 8, 1);
    Wave w16 = makeWave(33, 22050, 16, 2);
    Wave w32 = makeWave(0, 44100, 32, 2);
    {
        // Floats chosen to hit printf's %.4f corners: binary ties (round half
        // to even), signs that round to zero, huge, subnormal, inf and nan
        static const float values[] = {
            0.03125f, 0.00005f, -0.00005f, 0.15625f, -0.0f, 0.0f, 1.0f, -1.0f,
            0.12345f, 1234.56789f, -98765.4321f, 1e-40f, 3.4e38f, -3.4e38f,
            0.99999f, -0.99995f, 0.5f, 0.25f, 0.00015f, 2.00025f,
            INFINITY, -INFINITY, NAN, -NAN, 0.33333334f, 0.66666669f,
        };
        int count = (int)(sizeof(values)/sizeof(values[0]));
        w32.frameCount = (unsigned int)count/2;
        w32.data = MemAlloc((unsigned int)sizeof(values));
        memcpy(w32.data, values, sizeof(values));
    }
    printWave("w8", w8);
    printWave("w16", w16);
    printWave("w32", w32);

    // --- ExportWaveAsCode: exact text per sample size and name ---
    printf("code w8=%d\n", ExportWaveAsCode(w8, "my_wave-1.h"));
    printFile("code w8 file", "my_wave-1.h", 1);
    printf("code w16=%d\n", ExportWaveAsCode(w16, "Mixed.Case.Name.h"));
    printFile("code w16 file", "Mixed.Case.Name.h", 1);
    printf("code w32=%d\n", ExportWaveAsCode(w32, "floats.h"));
    printFile("code w32 file", "floats.h", 1);
    printf("code nodir=%d\n", ExportWaveAsCode(w8, "nodir/x.h"));
    {
        char longName[260];
        memset(longName, 'q', 250);
        strcpy(longName + 250, ".h");
        printf("code long=%d\n", ExportWaveAsCode(w8, longName));
        printFile("code long file", longName, 0);
    }

    // --- ExportWave: every format, then the failure paths ---
    printf("export w8 wav=%d\n", ExportWave(w8, "w8.wav"));
    printFile("export w8 wav file", "w8.wav", 0);
    printf("export w16 wav=%d\n", ExportWave(w16, "w16.wav"));
    printFile("export w16 wav file", "w16.wav", 0);
    printf("export w32 wav=%d\n", ExportWave(w32, "w32.wav"));
    printFile("export w32 wav file", "w32.wav", 0);
    printf("export w16 qoa=%d\n", ExportWave(w16, "w16.qoa"));
    printFile("export w16 qoa file", "w16.qoa", 0);
    printf("export w32 qoa=%d\n", ExportWave(w32, "w32.qoa"));
    printf("export w16 raw=%d\n", ExportWave(w16, "w16.raw"));
    printFile("export w16 raw file", "w16.raw", 0);
    printf("export w16 txt=%d\n", ExportWave(w16, "w16.txt"));
    printf("export w16 WAV upper=%d\n", ExportWave(w16, "upper.WAV"));
    printf("export wav nodir=%d\n", ExportWave(w16, "nodir/x.wav"));
    printf("export raw nodir=%d\n", ExportWave(w16, "nodir/x.raw"));

    // --- Loading what was exported, from memory and from file ---
    const char *types[] = { ".wav", ".WAV", ".Wav", ".qoa", ".QOA", ".flac", ".xyz" };
    int size = 0;
    unsigned char *data = LoadFileData("w16.wav", &size);
    for (int i = 0; i < 7; i++)
    {
        Wave w = LoadWaveFromMemory(types[i], data, size);
        char label[64];
        snprintf(label, sizeof(label), "frommem w16.wav as %s", types[i]);
        printWave(label, w);
        UnloadWave(w);
    }
    UnloadFileData(data);
    data = LoadFileData("w16.qoa", &size);
    {
        Wave w = LoadWaveFromMemory(".qoa", data, size);
        printWave("frommem w16.qoa", w);
        UnloadWave(w);
    }
    UnloadFileData(data);

    unsigned char junk[64];
    for (int i = 0; i < 64; i++) junk[i] = (unsigned char)(i*13 + 5);
    const char *junkTypes[] = { ".wav", ".ogg", ".OGG", ".mp3", ".MP3", ".qoa" };
    for (int i = 0; i < 6; i++)
    {
        Wave w = LoadWaveFromMemory(junkTypes[i], junk, 64);
        char label[64];
        snprintf(label, sizeof(label), "frommem junk as %s", junkTypes[i]);
        printWave(label, w);
        UnloadWave(w);
    }

    const char *files[] = { "w8.wav", "w16.wav", "w16.qoa", "missing.wav", RES "target.ogg", RES "country.mp3" };
    for (int i = 0; i < 6; i++)
    {
        Wave w = LoadWave(files[i]);
        char label[300];
        snprintf(label, sizeof(label), "loadwave %s", (i < 4) ? files[i] : files[i] + strlen(RES));
        printWave(label, w);
        UnloadWave(w);
    }

    // --- WaveCopy / WaveCrop ---
    Wave empty = { 0, 44100, 16, 2, NULL };
    Wave emptyCopy = WaveCopy(empty);
    printWave("copy empty", emptyCopy);
    UnloadWave(emptyCopy);

    struct { int init, final; } crops[] = {
        { 5, 20 }, { -1, 10 }, { 10, 10 }, { 12, 11 }, { 0, 34 }, { 0, 33 }, { 32, 33 }, { 0, 1 },
    };
    for (int i = 0; i < 8; i++)
    {
        Wave c = WaveCopy(w16);
        WaveCrop(&c, crops[i].init, crops[i].final);
        char label[64];
        snprintf(label, sizeof(label), "crop w16 %d..%d", crops[i].init, crops[i].final);
        printWave(label, c);
        UnloadWave(c);
    }
    {
        Wave c = WaveCopy(w8);
        WaveCrop(&c, 3, 44);
        printWave("crop w8 3..44", c);
        UnloadWave(c);
        c = WaveCopy(w32);
        WaveCrop(&c, 1, 12);
        printWave("crop w32 1..12", c);
        UnloadWave(c);
    }

    // --- WaveFormat ---
    struct { int rate, bits, ch; } fmts[] = {
        { 8000, 16, 1 }, { 8000, 32, 2 }, { 16000, 8, 2 }, { 4000, 8, 1 }, { 22050, 16, 2 },
        { 0, 16, 1 }, { 8000, 16, 3 },
    };
    for (int i = 0; i < 7; i++)
    {
        // From 16-bit: miniaudio's u8 conversions trip UBSan (negative left shift)
        Wave c = WaveCopy(w16);
        WaveFormat(&c, fmts[i].rate, fmts[i].bits, fmts[i].ch);
        char label[64];
        snprintf(label, sizeof(label), "format w16 %d/%d/%d", fmts[i].rate, fmts[i].bits, fmts[i].ch);
        printWave(label, c);
        UnloadWave(c);
    }
    {
        // Frames 10..12 hold inf/nan, which miniaudio's f32->s16 can't convert
        Wave c = WaveCopy(w32);
        WaveCrop(&c, 0, 10);
        WaveFormat(&c, 44100, 16, 1);
        printWave("format w32 44100/16/1", c);
        UnloadWave(c);
        Wave e = WaveCopy(empty);
        WaveFormat(&e, 44100, 16, 1);
        printWave("format empty", e);
        UnloadWave(e);
    }

    // --- LoadWaveSamples per sample size ---
    Wave sampled[] = { w8, w16, w32 };
    for (int i = 0; i < 3; i++)
    {
        float *s = LoadWaveSamples(sampled[i]);
        unsigned int n = sampled[i].frameCount*sampled[i].channels;
        printf("samples %u-bit: count=%u sum=%08x first=%a last=%a\n", sampled[i].sampleSize, n,
               hashBytes(s, n*sizeof(float)), n ? s[0] : 0.0f, n ? s[n - 1] : 0.0f);
        UnloadWaveSamples(s);
    }

    // --- Music loaders that fail (no device needed) ---
    const char *musicTypes[] = { ".wav", ".ogg", ".mp3", ".qoa", ".xm", ".mod", ".MOD", ".flac", ".xyz" };
    for (int i = 0; i < 9; i++)
    {
        Music m = LoadMusicStreamFromMemory(musicTypes[i], junk, 64);
        printf("music frommem junk %s: valid=%d ctx=%d frames=%u\n", musicTypes[i], IsMusicValid(m), m.ctxType, m.frameCount);
        UnloadMusicStream(m);
    }
    {
        Music m = LoadMusicStreamFromMemory(".qoa", NULL, 0);
        printf("music frommem null qoa: valid=%d\n", IsMusicValid(m));
    }
    const char *musicFiles[] = { "missing.wav", "missing.ogg", "missing.mp3", "missing.qoa", "missing.xm", "missing.mod", "missing.flac", "w16.txt" };
    for (int i = 0; i < 8; i++)
    {
        Music m = LoadMusicStream(musicFiles[i]);
        printf("music %s: valid=%d ctx=%d\n", musicFiles[i], IsMusicValid(m), m.ctxType);
        UnloadMusicStream(m);
    }

    // --- Device section: stream buffer state machine (no playback) ---
    SetTraceLogCallback(NULL);
    SetTraceLogLevel(LOG_NONE);
    InitAudioDevice();
    int ready = IsAudioDeviceReady();
    SetTraceLogLevel(LOG_ALL);
    SetTraceLogCallback(logCallback);
    printf("device: ready=%d\n", ready);
    if (ready)
    {
        SetAudioStreamBufferSizeDefault(64);
        AudioStream st = LoadAudioStream(22050, 16, 2);
        printf("stream: valid=%d processed=%d\n", IsAudioStreamValid(st), IsAudioStreamProcessed(st));
        short pcm[2*200];
        for (int i = 0; i < 2*200; i++) pcm[i] = (short)(i*7919);
        UpdateAudioStream(st, pcm, 1000000);   // too many frames: warns, copies nothing
        UpdateAudioStream(st, pcm, 200);
        UpdateAudioStream(st, pcm, 64);    // first half
        printf("stream after 1: processed=%d\n", IsAudioStreamProcessed(st));
        UpdateAudioStream(st, pcm, 10);    // second half, partly zero-filled
        printf("stream after 2: processed=%d\n", IsAudioStreamProcessed(st));
        UpdateAudioStream(st, pcm, 10);    // nothing available
        AttachAudioStreamProcessor(st, processorA);
        AttachAudioStreamProcessor(st, processorB);
        AttachAudioStreamProcessor(st, processorA);
        DetachAudioStreamProcessor(st, processorA);
        DetachAudioStreamProcessor(st, processorB);
        AttachAudioMixedProcessor(processorA);
        AttachAudioMixedProcessor(processorB);
        DetachAudioMixedProcessor(processorB);
        DetachAudioMixedProcessor(processorA);
        UnloadAudioStream(st);

        Sound snd = LoadSoundFromWave(w16);
        printf("sound: valid=%d frames=%u\n", IsSoundValid(snd), snd.frameCount);
        UpdateSound(snd, pcm, 10);
        UnloadSound(snd);
        Sound none = LoadSoundFromWave(empty);
        printf("sound empty: valid=%d\n", IsSoundValid(none));

        Music m = LoadMusicStream("w16.wav");
        printf("music w16.wav: valid=%d frames=%u len=%a\n", IsMusicValid(m), m.frameCount, GetMusicTimeLength(m));
        UnloadMusicStream(m);

        SetTraceLogCallback(NULL);
        SetTraceLogLevel(LOG_NONE);
        CloseAudioDevice();
        SetTraceLogLevel(LOG_ALL);
        SetTraceLogCallback(logCallback);
    }
    CloseAudioDevice();   // not initialized: warning

    UnloadWave(w8);
    UnloadWave(w16);
    UnloadWave(w32);

    SetTraceLogCallback(NULL);
    if (chdir("/tmp") != 0) return 2;
    nftw(root, removeEntry, 16, FTW_DEPTH | FTW_PHYS);
    return 0;
}
