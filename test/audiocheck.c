// audiocheck.c — the C-vs-Zig differential gate for raudio.
//
// Exercises raudio's deterministic surface — file/memory decoding (WAV, OGG,
// MP3, QOA), Wave manipulation, wave export, music/stream metadata and seek —
// and prints one labeled line per check (metadata + FNV-1a hash of PCM bytes).
// Built twice (against the all-C oracle raylib and the Zig-swapped raylib) by
// tools/audiodiff.sh, which byte-diffs the two outputs. Identical output ⇒ the
// Zig raudio decodes and transforms audio identically to upstream C.
//
// The playback/mixing path (device thread) is inherently non-deterministic in
// timing, so it gets a loose check only: device init, play/stop state flips.
// Decoded PCM is the hard gate. MOD is loose-checked via examples (no .mod
// asset in the raylib tree); its decode logic is jar_mod (linked C, identical
// in both builds) — the raudio-authored MOD glue is covered by code review.
//
// Usage: audiocheck <scratch-dir>   (for export round-trip files)
// Output goes to stdout with TraceLog silenced (LOG_NONE) so miniaudio's
// async log callbacks can't interleave.

#include "raylib.h"

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define RES "/home/rajesh/opensource/graphics/raylib/examples/audio/resources/"

static uint64_t fnv1a(const void *data, size_t len)
{
    const unsigned char *p = (const unsigned char *)data;
    uint64_t h = 1469598103934665603ULL;
    for (size_t i = 0; i < len; i++) { h ^= p[i]; h *= 1099511628211ULL; }
    return h;
}

static size_t waveBytes(Wave w) { return (size_t)w.frameCount*w.channels*(w.sampleSize/8); }

static void printWave(const char *label, Wave w)
{
    printf("%s: frames=%u rate=%u bits=%u ch=%u hash=%016llx\n", label,
           w.frameCount, w.sampleRate, w.sampleSize, w.channels,
           (unsigned long long)((w.data != NULL) ? fnv1a(w.data, waveBytes(w)) : 0));
}

static uint32_t f32bits(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }

// Decode one asset from memory and print metadata + PCM hash; returns the wave.
static Wave checkDecode(const char *name, const char *ext)
{
    char path[512];
    snprintf(path, sizeof(path), RES "%s", name);
    int size = 0;
    unsigned char *data = LoadFileData(path, &size);
    printf("filedata %s: size=%d\n", name, size);
    Wave w = LoadWaveFromMemory(ext, data, size);
    printWave(name, w);
    UnloadFileData(data);
    return w;
}

static void checkMusic(const char *name, const char *ext)
{
    char path[512];
    snprintf(path, sizeof(path), RES "%s", name);
    int size = 0;
    unsigned char *data = LoadFileData(path, &size);
    Music m = LoadMusicStreamFromMemory(ext, data, size);
    printf("music %s: valid=%d ctx=%d frames=%u looping=%d rate=%u bits=%u ch=%u len=%08x\n",
           name, IsMusicValid(m), m.ctxType, m.frameCount, m.looping,
           m.stream.sampleRate, m.stream.sampleSize, m.stream.channels,
           f32bits(GetMusicTimeLength(m)));
    if (IsMusicValid(m))
    {
        SeekMusicStream(m, 0.5f);
        printf("music %s seek: played=%08x\n", name, f32bits(GetMusicTimePlayed(m)));
    }
    UnloadMusicStream(m);
    UnloadFileData(data);
}

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: audiocheck <scratch-dir>\n"); return 2; }
    const char *scratch = argv[1];
    SetTraceLogLevel(LOG_NONE);

    // --- Wave decode from memory: every enabled format with an asset ---
    Wave sound = checkDecode("sound.wav", ".wav");
    Wave spring = checkDecode("spring.wav", ".wav");
    Wave coin = checkDecode("coin.wav", ".wav");
    Wave weird = checkDecode("weird.wav", ".wav");
    Wave ogg = checkDecode("target.ogg", ".ogg");
    Wave mp3 = checkDecode("country.mp3", ".mp3");
    Wave qoa = checkDecode("target.qoa", ".qoa");

    // --- Wave decode straight from file (extension routing + LoadFileData) ---
    Wave fromFile = LoadWave(RES "sound.wav");
    printWave("loadwave sound.wav", fromFile);
    UnloadWave(fromFile);

    // --- Wave ops ---
    Wave copy = WaveCopy(sound);
    printWave("copy", copy);
    WaveCrop(&copy, 100, 4000);
    printWave("crop 100..4000", copy);

    struct { int rate, bits, ch; } fmts[] = { {22050, 16, 1}, {48000, 32, 2}, {11025, 8, 1} };
    for (int i = 0; i < 3; i++)
    {
        Wave conv = WaveCopy(sound);
        WaveFormat(&conv, fmts[i].rate, fmts[i].bits, fmts[i].ch);
        char label[64];
        snprintf(label, sizeof(label), "format %d/%d/%d", fmts[i].rate, fmts[i].bits, fmts[i].ch);
        printWave(label, conv);
        UnloadWave(conv);
    }

    float *samples = LoadWaveSamples(sound);
    printf("samples: hash=%016llx\n", (unsigned long long)
           fnv1a(samples, (size_t)sound.frameCount*sound.channels*sizeof(float)));
    UnloadWaveSamples(samples);

    // --- Export round-trip (dr_wav encode via raudio logic) ---
    char out[512];
    snprintf(out, sizeof(out), "%s/out.wav", scratch);
    printf("exportwave: ok=%d\n", ExportWave(copy, out));
    int exSize = 0;
    unsigned char *exData = LoadFileData(out, &exSize);
    printf("exportwave file: size=%d hash=%016llx\n", exSize,
           (unsigned long long)fnv1a(exData, (size_t)exSize));
    UnloadFileData(exData);

    snprintf(out, sizeof(out), "%s/out.h", scratch);
    printf("exportcode: ok=%d\n", ExportWaveAsCode(copy, out));
    exData = LoadFileData(out, &exSize);
    printf("exportcode file: size=%d hash=%016llx\n", exSize,
           (unsigned long long)fnv1a(exData, (size_t)exSize));
    UnloadFileData(exData);
    UnloadWave(copy);

    // --- Device-dependent section (same machine for both builds ⇒ same device) ---
    InitAudioDevice();
    int ready = IsAudioDeviceReady();
    printf("device: ready=%d\n", ready);
    if (ready)
    {
        printf("mastervolume: %08x\n", f32bits(GetMasterVolume()));

        Sound snd = LoadSoundFromWave(sound);
        printf("sound: valid=%d frames=%u rate=%u bits=%u ch=%u\n", IsSoundValid(snd),
               snd.frameCount, snd.stream.sampleRate, snd.stream.sampleSize, snd.stream.channels);
        Sound alias = LoadSoundAlias(snd);
        printf("alias: valid=%d frames=%u\n", IsSoundValid(alias), alias.frameCount);

        // Loose playback-state check (timing-independent booleans only).
        PlaySound(snd);
        printf("play: playing=%d\n", IsSoundPlaying(snd));
        StopSound(snd);
        printf("stop: playing=%d\n", IsSoundPlaying(snd));
        UnloadSoundAlias(alias);
        UnloadSound(snd);

        // Music metadata + seek per streamable format.
        checkMusic("target.ogg", ".ogg");
        checkMusic("country.mp3", ".mp3");
        checkMusic("target.qoa", ".qoa");
        checkMusic("mini1111.xm", ".xm");

        // AudioStream state machine (no playback).
        SetAudioStreamBufferSizeDefault(4096);
        AudioStream st = LoadAudioStream(44100, 16, 2);
        printf("stream: valid=%d processed=%d\n", IsAudioStreamValid(st), IsAudioStreamProcessed(st));
        short *pcm = (short *)calloc(1024*2, sizeof(short));
        for (int i = 0; i < 1024*2; i++) pcm[i] = (short)((i*7919) & 0xFFFF);
        UpdateAudioStream(st, pcm, 1024);
        printf("stream updated: processed=%d playing=%d\n", IsAudioStreamProcessed(st), IsAudioStreamPlaying(st));
        free(pcm);
        UnloadAudioStream(st);

        CloseAudioDevice();
        printf("device closed: ready=%d\n", IsAudioDeviceReady());
    }

    UnloadWave(sound);
    UnloadWave(spring);
    UnloadWave(coin);
    UnloadWave(weird);
    UnloadWave(ogg);
    UnloadWave(mp3);
    UnloadWave(qoa);

    printf("audiocheck done\n");
    return 0;
}
