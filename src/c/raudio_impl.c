// raudio_impl.c — third-party single-file-lib instantiation for the raudio port.
//
// raudio.c instantiates miniaudio + the audio-format decoders inside its TU; when
// raudio is ported to Zig (src/raudio.zig) those implementations move here and the
// Zig port calls them via `extern`. The preamble replicates raudio.c's exact
// configuration (raudio.c:159-279), driven by the same config.h flags.
// SUPPORT_FILEFORMAT_FLAC is 0 in config.h, so dr_flac is not instantiated.
//
// All third-party structs are OPAQUE to Zig. This file additionally provides:
//   - create/destroy wrappers for the miniaudio objects raudio.c embeds by value
//     in its globals (ma_context, ma_device, ma_mutex, ma_data_converter)
//   - small getters for every third-party struct field raudio.c reads directly
//   - wrappers for functions that pass/return structs by value or are static
//     inside their header (drwav_seek_to_first_pcm_frame, drmp3_seek_to_start_of_
//     stream, jar_mod_load) and thus have no linkable symbol
//   - sizeof helpers for contexts the Zig port heap-allocates opaquely
//
// Compiled by build.zig only when raudio is ported.

#include "config.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <stdbool.h>

// raylib's default allocators (config.h defaults: RL_MALLOC/RL_CALLOC/RL_FREE).
#define RL_MALLOC(sz)       malloc(sz)
#define RL_CALLOC(n, sz)    calloc(n, sz)
#define RL_REALLOC(p, sz)   realloc(p, sz)
#define RL_FREE(p)          free(p)

//----------------------------------------------------------------------------------
// miniaudio — exact raudio.c instantiation config (raudio.c:159-176)
//----------------------------------------------------------------------------------
#define MA_MALLOC RL_MALLOC
#define MA_FREE RL_FREE

#define MA_NO_JACK
#define MA_NO_WAV
#define MA_NO_FLAC
#define MA_NO_MP3
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#define MA_NO_GENERATION

// Threading model: [2] COINIT_APARTMENTTHREADED (Win32 only; raudio.c:172)
#define MA_COINIT_VALUE  2

#define MINIAUDIO_IMPLEMENTATION
#include "external/miniaudio.h"

//----------------------------------------------------------------------------------
// Audio file-format decoders (raudio.c:203-279, minus FLAC which is disabled)
//----------------------------------------------------------------------------------
#if SUPPORT_FILEFORMAT_WAV
    #define DRWAV_MALLOC RL_MALLOC
    #define DRWAV_REALLOC RL_REALLOC
    #define DRWAV_FREE RL_FREE

    #define DR_WAV_IMPLEMENTATION
    #include "external/dr_wav.h"        // WAV loading functions
#endif

#if SUPPORT_FILEFORMAT_OGG
    // TODO (upstream): stb_vorbis malloc()/free() are not remapped (raudio.c:213)
    #include "external/stb_vorbis.c"    // OGG loading functions
#endif

#if SUPPORT_FILEFORMAT_MP3
    #define DRMP3_MALLOC RL_MALLOC
    #define DRMP3_REALLOC RL_REALLOC
    #define DRMP3_FREE RL_FREE

    #define DR_MP3_IMPLEMENTATION
    #include "external/dr_mp3.h"        // MP3 loading functions
#endif

#if SUPPORT_FILEFORMAT_QOA
    #define QOA_MALLOC RL_MALLOC
    #define QOA_FREE RL_FREE

    #define QOA_IMPLEMENTATION
    #include "external/qoa.h"           // QOA loading and saving functions
    #include "external/qoaplay.c"       // QOA stream playing helper functions
#endif

#if SUPPORT_FILEFORMAT_XM
    #define JARXM_MALLOC RL_MALLOC
    #define JARXM_FREE RL_FREE

    #define JAR_XM_IMPLEMENTATION
    #include "external/jar_xm.h"        // XM loading functions
#endif

#if SUPPORT_FILEFORMAT_MOD
    #define JARMOD_MALLOC RL_MALLOC
    #define JARMOD_FREE RL_FREE

    #define JAR_MOD_IMPLEMENTATION
    #include "external/jar_mod.h"       // MOD loading functions
#endif

//----------------------------------------------------------------------------------
// Device format constants — exactly raudio.c:284-295
//----------------------------------------------------------------------------------
#define AUDIO_DEVICE_FORMAT    ma_format_f32    // Device output format (float-32bit)
#define AUDIO_DEVICE_CHANNELS              2    // Device output channels: stereo
#define AUDIO_DEVICE_SAMPLE_RATE           0    // Device output sample rate (0 = native)
#define AUDIO_DEVICE_PERIOD_SIZE_IN_FRAMES 0    // Device latency (0 = 10ms default)

//----------------------------------------------------------------------------------
// miniaudio object lifetime wrappers
// raudio.c embeds these BY VALUE in its static AudioData global; the Zig port keeps
// them as opaque heap objects instead, created/destroyed through these wrappers.
//----------------------------------------------------------------------------------

// InitAudioDevice's context setup (raudio.c:468-476)
ma_context *rl_ma_context_create(ma_log_callback_proc onLog)
{
    ma_context *ctx = (ma_context *)RL_MALLOC(sizeof(ma_context));
    if (ctx == NULL) return NULL;

    ma_context_config ctxConfig = ma_context_config_init();
    // NOTE: Return value discarded, exactly as raudio.c:469 — the callback is
    // built but never attached to the context (upstream quirk, kept as-is)
    ma_log_callback_init(onLog, NULL);

    if (ma_context_init(NULL, 0, &ctxConfig, ctx) != MA_SUCCESS)
    {
        RL_FREE(ctx);
        return NULL;
    }

    return ctx;
}

void rl_ma_context_destroy(ma_context *ctx)
{
    if (ctx != NULL)
    {
        ma_context_uninit(ctx);
        RL_FREE(ctx);
    }
}

// Backend name for InitAudioDevice's TRACELOG (raudio.c:522)
const char *rl_ma_context_backend_name(const ma_context *ctx)
{
    return ma_get_backend_name(ctx->backend);
}

// InitAudioDevice's device setup (raudio.c:480-497)
ma_device *rl_ma_device_create(ma_context *ctx, ma_device_data_proc dataCallback)
{
    ma_device *device = (ma_device *)RL_MALLOC(sizeof(ma_device));
    if (device == NULL) return NULL;

    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.pDeviceID = NULL;  // NULL for the default playback device
    config.playback.format = AUDIO_DEVICE_FORMAT;
    config.playback.channels = AUDIO_DEVICE_CHANNELS;
    config.sampleRate = AUDIO_DEVICE_SAMPLE_RATE;
    config.periodSizeInFrames = AUDIO_DEVICE_PERIOD_SIZE_IN_FRAMES;
    config.dataCallback = dataCallback;
    config.pUserData = NULL;
    config.noPreSilencedOutputBuffer = true;    // raylib pre-silences the output buffer manually
    config.noFixedSizedCallback = true;         // raylib does not require fixed sized callback guarantees

    if (ma_device_init(ctx, &config, device) != MA_SUCCESS)
    {
        RL_FREE(device);
        return NULL;
    }

    return device;
}

void rl_ma_device_destroy(ma_device *device)
{
    if (device != NULL)
    {
        ma_device_uninit(device);
        RL_FREE(device);
    }
}

// Device fields read directly by raudio.c (raudio.c:523-526, 2135-2140):
// device.sampleRate, device.playback.{format,internalFormat,channels,
// internalChannels,internalSampleRate,internalPeriodSizeInFrames,internalPeriods}
typedef struct rl_ma_device_info {
    int format;                             // ma_format (ma_format_f32 = 5, miniaudio.h:4316)
    int internalFormat;
    unsigned int channels;
    unsigned int internalChannels;
    unsigned int sampleRate;                // device.sampleRate
    unsigned int internalSampleRate;
    unsigned int internalPeriodSizeInFrames;
    unsigned int internalPeriods;
} rl_ma_device_info;

void rl_ma_device_get_info(const ma_device *device, rl_ma_device_info *info)
{
    info->format = (int)device->playback.format;
    info->internalFormat = (int)device->playback.internalFormat;
    info->channels = device->playback.channels;
    info->internalChannels = device->playback.internalChannels;
    info->sampleRate = device->sampleRate;
    info->internalSampleRate = device->playback.internalSampleRate;
    info->internalPeriodSizeInFrames = device->playback.internalPeriodSizeInFrames;
    info->internalPeriods = device->playback.internalPeriods;
}

// Mixing mutex (raudio.c:502)
ma_mutex *rl_ma_mutex_create(void)
{
    ma_mutex *mutex = (ma_mutex *)RL_MALLOC(sizeof(ma_mutex));
    if (mutex == NULL) return NULL;

    if (ma_mutex_init(mutex) != MA_SUCCESS)
    {
        RL_FREE(mutex);
        return NULL;
    }

    return mutex;
}

void rl_ma_mutex_destroy(ma_mutex *mutex)
{
    if (mutex != NULL)
    {
        ma_mutex_uninit(mutex);
        RL_FREE(mutex);
    }
}

// LoadAudioBuffer's converter setup (raudio.c:588-591). Output side is always the
// device format: AUDIO_DEVICE_FORMAT (f32) x AUDIO_DEVICE_CHANNELS (2).
ma_data_converter *rl_ma_data_converter_create(int formatIn, unsigned int channelsIn,
                                               unsigned int sampleRateIn, unsigned int sampleRateOut)
{
    ma_data_converter *converter = (ma_data_converter *)RL_MALLOC(sizeof(ma_data_converter));
    if (converter == NULL) return NULL;

    ma_data_converter_config converterConfig = ma_data_converter_config_init((ma_format)formatIn,
        AUDIO_DEVICE_FORMAT, channelsIn, AUDIO_DEVICE_CHANNELS, sampleRateIn, sampleRateOut);
    converterConfig.allowDynamicSampleRate = true;  // Required for pitch shifting

    if (ma_data_converter_init(&converterConfig, NULL, converter) != MA_SUCCESS)
    {
        RL_FREE(converter);
        return NULL;
    }

    return converter;
}

void rl_ma_data_converter_destroy(ma_data_converter *converter)
{
    if (converter != NULL)
    {
        ma_data_converter_uninit(converter, NULL);
        RL_FREE(converter);
    }
}

// Resampler rates read by ReadAudioBufferFramesInMixingFormat (raudio.c:2522);
// sampleRateOut changes when SetAudioBufferPitch calls ma_data_converter_set_rate.
unsigned int rl_ma_data_converter_resampler_rate_in(const ma_data_converter *converter)
{
    return converter->resampler.sampleRateIn;
}

unsigned int rl_ma_data_converter_resampler_rate_out(const ma_data_converter *converter)
{
    return converter->resampler.sampleRateOut;
}

//----------------------------------------------------------------------------------
// dr_wav helpers
//----------------------------------------------------------------------------------
#if SUPPORT_FILEFORMAT_WAV
size_t rl_sizeof_drwav(void) { return sizeof(drwav); }

// drwav fields read by raudio.c (dr_wav.h:888-900): totalPCMFrameCount (u64),
// sampleRate (u32), channels (u16), bitsPerSample (u16)
void rl_drwav_get_info(const drwav *wav, unsigned long long *totalPCMFrameCount,
                       unsigned int *sampleRate, unsigned int *channels, unsigned int *bitsPerSample)
{
    *totalPCMFrameCount = wav->totalPCMFrameCount;
    *sampleRate = wav->sampleRate;
    *channels = wav->channels;
    *bitsPerSample = wav->bitsPerSample;
}

// drwav_seek_to_first_pcm_frame is DRWAV_PRIVATE (static, dr_wav.h:6011) — no
// linkable symbol, so it is re-exported here for the Zig port.
drwav_bool32 rl_drwav_seek_to_first_pcm_frame(drwav *wav)
{
    return drwav_seek_to_first_pcm_frame(wav);
}

// ExportWave's drwav_data_format setup (raudio.c:1079-1089); the container is
// always drwav_container_riff there, so it is fixed here.
drwav_bool32 rl_drwav_init_memory_write(drwav *wav, void **ppData, size_t *pDataSize,
                                        unsigned int format, unsigned int channels,
                                        unsigned int sampleRate, unsigned int bitsPerSample)
{
    drwav_data_format dataFormat = { 0 };
    dataFormat.container = drwav_container_riff;
    dataFormat.format = format;             // DR_WAVE_FORMAT_PCM (0x1) or _IEEE_FLOAT (0x3), dr_wav.h:281-283
    dataFormat.channels = channels;
    dataFormat.sampleRate = sampleRate;
    dataFormat.bitsPerSample = bitsPerSample;

    return drwav_init_memory_write(wav, ppData, pDataSize, &dataFormat, NULL);
}
#endif

//----------------------------------------------------------------------------------
// stb_vorbis helpers
//----------------------------------------------------------------------------------
#if SUPPORT_FILEFORMAT_OGG
// stb_vorbis_get_info returns stb_vorbis_info BY VALUE (stb_vorbis.c:150);
// raudio.c reads only sample_rate and channels from it.
void rl_stb_vorbis_get_info(stb_vorbis *vorbis, unsigned int *sampleRate, int *channels)
{
    stb_vorbis_info info = stb_vorbis_get_info(vorbis);
    *sampleRate = info.sample_rate;
    *channels = info.channels;
}
#endif

//----------------------------------------------------------------------------------
// dr_mp3 helpers
//----------------------------------------------------------------------------------
#if SUPPORT_FILEFORMAT_MP3
size_t rl_sizeof_drmp3(void) { return sizeof(drmp3); }

// drmp3 fields read by raudio.c (dr_mp3.h:401-402): channels, sampleRate
void rl_drmp3_get_info(const drmp3 *mp3, unsigned int *channels, unsigned int *sampleRate)
{
    *channels = mp3->channels;
    *sampleRate = mp3->sampleRate;
}

// drmp3_seek_to_start_of_stream is static inside dr_mp3.h (dr_mp3.h:4348) — no
// linkable symbol, so it is re-exported here for the Zig port.
drmp3_bool32 rl_drmp3_seek_to_start_of_stream(drmp3 *mp3)
{
    return drmp3_seek_to_start_of_stream(mp3);
}
#endif

//----------------------------------------------------------------------------------
// qoa / qoaplay helpers
//----------------------------------------------------------------------------------
#if SUPPORT_FILEFORMAT_QOA
// LoadWaveFromMemory's QOA branch (raudio.c:880-891): qoa_desc is stack-local and
// only channels/samplerate/samples are read back.
short *rl_qoa_decode(const unsigned char *bytes, int size, unsigned int *channels,
                     unsigned int *samplerate, unsigned int *samples)
{
    qoa_desc qoa = { 0 };
    short *data = qoa_decode(bytes, size, &qoa);
    *channels = qoa.channels;
    *samplerate = qoa.samplerate;
    *samples = qoa.samples;
    return data;
}

// ExportWave's QOA branch (raudio.c:1101-1110)
int rl_qoa_write(const char *fileName, const short *sampleData, unsigned int channels,
                 unsigned int samplerate, unsigned int samples)
{
    qoa_desc qoa = { 0 };
    qoa.channels = channels;
    qoa.samplerate = samplerate;
    qoa.samples = samples;
    return qoa_write(fileName, sampleData, &qoa);
}

// qoaplay_desc fields read by raudio.c (qoaplay.c:40-54): info.{channels,
// samplerate,samples} and sample_position
void rl_qoaplay_get_info(const qoaplay_desc *ctx, unsigned int *channels,
                         unsigned int *samplerate, unsigned int *samples)
{
    *channels = ctx->info.channels;
    *samplerate = ctx->info.samplerate;
    *samples = ctx->info.samples;
}

unsigned int rl_qoaplay_sample_position(const qoaplay_desc *ctx)
{
    return ctx->sample_position;
}
#endif

//----------------------------------------------------------------------------------
// jar_mod helpers
//----------------------------------------------------------------------------------
#if SUPPORT_FILEFORMAT_MOD
size_t rl_sizeof_jar_mod_context(void) { return sizeof(jar_mod_context_t); }

// Replicates LoadMusicStreamFromMemory's MOD branch (raudio.c:1700-1715) verbatim:
// jar_mod_load is static inside jar_mod.h (jar_mod.h:1117) and the branch writes
// ctxMod->modfile/modfilesize directly, so the whole memory-load sequence lives
// here. Returns the context on success; on failure performs raudio.c's exact
// cleanup (jar_mod_unload + RL_FREE(ctx)) and returns NULL. NOTE: like upstream,
// the copied data buffer is intentionally leaked when dataSize >= 32MB.
jar_mod_context_t *rl_jar_mod_load_memory(const unsigned char *data, int dataSize)
{
    jar_mod_context_t *ctxMod = (jar_mod_context_t *)RL_MALLOC(sizeof(jar_mod_context_t));
    int result = 0;

    jar_mod_init(ctxMod);

    // Copy data to allocated memory for default UnloadMusicStream
    unsigned char *newData = (unsigned char *)RL_MALLOC(dataSize);
    for (int i = 0; i < dataSize; i++) newData[i] = data[i];

    // Memory loaded version for jar_mod_load_file()
    if (dataSize && (dataSize < 32*1024*1024))
    {
        ctxMod->modfilesize = dataSize;
        ctxMod->modfile = newData;
        if (jar_mod_load(ctxMod, (void *)ctxMod->modfile, dataSize)) result = dataSize;
    }

    if (result > 0) return ctxMod;

    jar_mod_unload(ctxMod);
    RL_FREE(ctxMod);
    return NULL;
}
#endif
