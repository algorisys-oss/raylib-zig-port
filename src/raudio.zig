//! raudio - A simple and easy-to-use audio library based on miniaudio
//!
//! Zig port of raylib's `raudio.c`. Every non-static function raudio.c defines is
//! exported with its exact C name, byte-compatible signature, and C calling
//! convention, so the rest of raylib (and user programs) link against it unchanged.
//! Decode paths and frame/sample arithmetic follow the C source operation-for-
//! operation so the decoded PCM byte-diffs clean against pure-C raylib.
//!
//! This build mirrors raylib's default `config.h`: WAV/OGG/MP3/QOA/XM/MOD enabled,
//! FLAC disabled. The third-party libraries (miniaudio, dr_wav, stb_vorbis, dr_mp3,
//! qoa/qoaplay, jar_xm, jar_mod) are instantiated in the C shim
//! `src/c/raudio_impl.c` and only `extern`-declared and called here; their structs
//! stay fully opaque on the Zig side. Where raudio.c embeds miniaudio objects by
//! value in its globals (`ma_context`, `ma_device`, `ma_mutex`, and each buffer's
//! `ma_data_converter`), this port holds opaque heap pointers created through the
//! shim instead; the immutable converter parameters (formatIn/channelsIn/
//! channelsOut/sampleRateIn) are cached in `AudioBuffer`, and the miniaudio device
//! properties raudio.c reads directly are cached in `AUDIO.system` after device
//! creation. Neither cache changes any observable behavior.

const std = @import("std");

//----------------------------------------------------------------------------------
// libc functions, called directly so behavior matches the C source exactly.
//----------------------------------------------------------------------------------
extern fn malloc(usize) ?*anyopaque;
extern fn calloc(usize, usize) ?*anyopaque;
extern fn free(?*anyopaque) void;
extern fn memcpy(noalias ?*anyopaque, noalias ?*const anyopaque, usize) ?*anyopaque;
extern fn memmove(?*anyopaque, ?*const anyopaque, usize) ?*anyopaque;
extern fn memset(?*anyopaque, c_int, usize) ?*anyopaque;
extern fn strcmp([*c]const u8, [*c]const u8) c_int;
extern fn strncpy(noalias [*c]u8, noalias [*c]const u8, usize) [*c]u8;
extern fn sprintf(noalias [*c]u8, noalias [*c]const u8, ...) c_int;

// raylib RL_MALLOC/RL_CALLOC/RL_FREE map to malloc/calloc/free (config.h defaults).
const RL_MALLOC = malloc;
const RL_CALLOC = calloc;
inline fn RL_FREE(p: anytype) void {
    free(@ptrCast(@constCast(p)));
}

//----------------------------------------------------------------------------------
// Cross-module raylib C-ABI symbols (rcore, ported or not, same symbols).
//----------------------------------------------------------------------------------
extern fn TraceLog(logLevel: c_int, text: [*c]const u8, ...) void;
extern fn LoadFileData(fileName: [*c]const u8, dataSize: [*c]c_int) [*c]u8;
extern fn UnloadFileData(data: [*c]u8) void;
extern fn SaveFileData(fileName: [*c]const u8, data: ?*anyopaque, dataSize: c_int) bool;
extern fn SaveFileText(fileName: [*c]const u8, text: [*c]u8) bool;
extern fn IsFileExtension(fileName: [*c]const u8, ext: [*c]const u8) bool;
extern fn GetFileExtension(fileName: [*c]const u8) [*c]const u8;
extern fn GetFileNameWithoutExt(filePath: [*c]const u8) [*c]const u8;

// TraceLog levels (raylib.h TraceLogLevel)
const LOG_INFO: c_int = 3;
const LOG_WARNING: c_int = 4;

//----------------------------------------------------------------------------------
// Build configuration — mirrors config.h:332-351 (the flags raudio.c compiles with)
//----------------------------------------------------------------------------------
const SUPPORT_FILEFORMAT_WAV = true;
const SUPPORT_FILEFORMAT_OGG = true;
const SUPPORT_FILEFORMAT_MP3 = true;
const SUPPORT_FILEFORMAT_QOA = true;
const SUPPORT_FILEFORMAT_FLAC = false; // Disabled by default upstream; dr_flac is not linked
const SUPPORT_FILEFORMAT_XM = true;
const SUPPORT_FILEFORMAT_MOD = true;

//----------------------------------------------------------------------------------
// Defines and Macros (raudio.c:284-303)
//----------------------------------------------------------------------------------
const AUDIO_DEVICE_FORMAT: c_int = ma_format_f32; // Device output format (float-32bit)
const AUDIO_DEVICE_CHANNELS: c_uint = 2; // Device output channels: stereo
const AUDIO_BUFFER_RESIDUAL_CAPACITY: c_uint = 8; // In PCM frames, for resampling and pitch shifting

//----------------------------------------------------------------------------------
// miniaudio constants (verified against vendor/raylib/src/external/miniaudio.h)
//----------------------------------------------------------------------------------
const MA_SUCCESS: c_int = 0; // miniaudio.h:4196
const ma_format_u8: c_int = 1; // miniaudio.h:4312
const ma_format_s16: c_int = 2; // miniaudio.h:4313
const ma_format_f32: c_int = 5; // miniaudio.h:4316

// dr_wav constants (dr_wav.h:224, 281-283)
const DRWAV_SUCCESS: c_int = 0;
const DR_WAVE_FORMAT_PCM: c_uint = 0x1;
const DR_WAVE_FORMAT_IEEE_FLOAT: c_uint = 0x3;

// qoa constants (qoa.h:119-121): QOA_FRAME_LEN = QOA_SLICES_PER_FRAME*QOA_SLICE_LEN
const QOA_FRAME_LEN: c_uint = 256 * 20;

//----------------------------------------------------------------------------------
// Types and Structures Definition (public ABI: extern struct, exact raylib.h layout)
//----------------------------------------------------------------------------------

/// Wave, audio wave data (raylib.h:465-471)
pub const Wave = extern struct {
    frameCount: c_uint,
    sampleRate: c_uint,
    sampleSize: c_uint,
    channels: c_uint,
    data: ?*anyopaque,
};

/// AudioStream, custom audio stream (raylib.h:479-486). `buffer` and `processor`
/// point at raudio-internal types and are opaque to callers.
pub const AudioStream = extern struct {
    buffer: ?*AudioBuffer,
    processor: ?*AudioProcessor,
    sampleRate: c_uint,
    sampleSize: c_uint,
    channels: c_uint,
};

/// Sound (raylib.h:489-492)
pub const Sound = extern struct {
    stream: AudioStream,
    frameCount: c_uint,
};

/// Music, audio stream, anything longer than ~10 seconds should be streamed (raylib.h:495-502)
pub const Music = extern struct {
    stream: AudioStream,
    frameCount: c_uint,
    looping: bool,
    ctxType: c_int,
    ctxData: ?*anyopaque,
};

/// Audio stream callback (raylib.h:1668): void (*)(void *bufferData, unsigned int frames)
pub const AudioCallback = ?*const fn (?*anyopaque, c_uint) callconv(.c) void;

// Music context type (raudio.c:326-335)
const MUSIC_AUDIO_NONE: c_int = 0;
const MUSIC_AUDIO_WAV: c_int = 1;
const MUSIC_AUDIO_OGG: c_int = 2;
const MUSIC_AUDIO_FLAC: c_int = 3; // unused in this build (FLAC disabled)
const MUSIC_AUDIO_MP3: c_int = 4;
const MUSIC_AUDIO_QOA: c_int = 5;
const MUSIC_MODULE_XM: c_int = 6;
const MUSIC_MODULE_MOD: c_int = 7;

// AudioBufferUsage (raudio.c:339-342)
const AUDIO_BUFFER_USAGE_STATIC: c_int = 0;
const AUDIO_BUFFER_USAGE_STREAM: c_int = 1;

/// Audio buffer (raudio.c:345-371). Internal to raudio: crosses the public ABI only
/// as an opaque pointer, so the layout is free to differ from C. The embedded
/// `ma_data_converter converter` becomes an opaque heap pointer plus a cache of its
/// immutable creation parameters (which raudio.c reads back from the converter).
const AudioBuffer = struct {
    converter: *MaDataConverter, // Audio data converter (opaque, heap via shim)
    formatIn: c_int, // converter.formatIn (immutable after creation)
    channelsIn: c_uint, // converter.channelsIn (immutable)
    channelsOut: c_uint, // converter.channelsOut (immutable, always AUDIO_DEVICE_CHANNELS)
    sampleRateIn: c_uint, // converter.sampleRateIn (immutable; set_rate keeps it fixed)

    converterResidual: [*]u8, // Cached residual input frames for use by the converter
    converterResidualCount: c_uint, // The number of valid frames sitting in converterResidual

    callback: AudioCallback, // Audio buffer callback for buffer filling on audio threads
    processor: ?*AudioProcessor, // Audio processor

    volume: f32, // Audio buffer volume
    pitch: f32, // Audio buffer pitch
    pan: f32, // Audio buffer pan (-1.0f to 1.0f)

    playing: bool, // Audio buffer state: AUDIO_PLAYING
    paused: bool, // Audio buffer state: AUDIO_PAUSED
    looping: bool, // Audio buffer looping, default to true for AudioStreams
    usage: c_int, // Audio buffer usage mode: STATIC or STREAM

    isSubBufferProcessed: [2]bool, // SubBuffer processed (virtual double buffer)
    sizeInFrames: c_uint, // Total buffer size in frames
    frameCursorPos: c_uint, // Frame cursor position
    framesProcessed: c_uint, // Total frames processed in this buffer (required for play timing)

    data: ?[*]u8, // Data buffer, on music stream keeps filling

    next: ?*AudioBuffer, // Next audio buffer on the list
    prev: ?*AudioBuffer, // Previous audio buffer on the list
};

/// Audio processor (raudio.c:375-379), useful to apply effects to an AudioBuffer
const AudioProcessor = struct {
    process: AudioCallback, // Processor callback function
    next: ?*AudioProcessor, // Next audio processor on the list
    prev: ?*AudioProcessor, // Previous audio processor on the list
};

/// Audio data context (raudio.c:384-399). The C global embeds the miniaudio
/// context/device/mutex by value; here they are opaque heap objects (created in
/// InitAudioDevice via the shim) plus a cache of the device properties raudio.c
/// reads directly from `AUDIO.System.device`.
const AudioData = struct {
    system: struct {
        context: ?*MaContext = null, // miniaudio context data
        device: ?*MaDevice = null, // miniaudio device
        lock: ?*MaMutex = null, // miniaudio mutex lock
        isReady: bool = false, // Check if audio device is ready
        pcmBufferSize: usize = 0, // Pre-allocated buffer size
        pcmBuffer: ?*anyopaque = null, // Pre-allocated buffer to read audio data from file/memory

        // Cached miniaudio device properties (zero while no device, like C's zeroed global):
        deviceSampleRate: c_uint = 0, // device.sampleRate
        playbackFormat: c_int = 0, // device.playback.format
        playbackChannels: c_uint = 0, // device.playback.channels
        playbackInternalPeriodSizeInFrames: c_uint = 0, // device.playback.internalPeriodSizeInFrames
    } = .{},
    buffer: struct {
        first: ?*AudioBuffer = null, // Pointer to first AudioBuffer in the list
        last: ?*AudioBuffer = null, // Pointer to last AudioBuffer in the list
        defaultSize: c_int = 0, // Default audio buffer size for audio streams
    } = .{},
    mixedProcessor: ?*AudioProcessor = null,
};

//----------------------------------------------------------------------------------
// Global Variables Definition (raudio.c:404-412)
//----------------------------------------------------------------------------------
var AUDIO: AudioData = .{};

//----------------------------------------------------------------------------------
// Third-party opaque types + extern declarations.
// Signatures verified against the vendored headers; struct-by-value and
// static-inside-header functions go through src/c/raudio_impl.c (rl_* wrappers).
//----------------------------------------------------------------------------------
const MaContext = opaque {};
const MaDevice = opaque {};
const MaMutex = opaque {};
const MaDataConverter = opaque {};
const DrWav = opaque {};
const DrMp3 = opaque {};
const StbVorbis = opaque {};
const QoaPlayDesc = opaque {};
const JarXmContext = opaque {};
const JarModContext = opaque {};

// miniaudio callback types (miniaudio.h ma_device_data_proc / ma_log_callback_proc)
const MaDeviceDataProc = *const fn (?*anyopaque, ?*anyopaque, ?*const anyopaque, c_uint) callconv(.c) void;
const MaLogCallbackProc = *const fn (?*anyopaque, c_uint, [*c]const u8) callconv(.c) void;

// Device info snapshot filled by the shim (mirror of rl_ma_device_info in raudio_impl.c)
const RlMaDeviceInfo = extern struct {
    format: c_int,
    internalFormat: c_int,
    channels: c_uint,
    internalChannels: c_uint,
    sampleRate: c_uint,
    internalSampleRate: c_uint,
    internalPeriodSizeInFrames: c_uint,
    internalPeriods: c_uint,
};

// Shim wrappers (src/c/raudio_impl.c)
extern fn rl_ma_context_create(onLog: MaLogCallbackProc) ?*MaContext;
extern fn rl_ma_context_destroy(ctx: ?*MaContext) void;
extern fn rl_ma_context_backend_name(ctx: ?*MaContext) [*c]const u8;
extern fn rl_ma_device_create(ctx: ?*MaContext, dataCallback: MaDeviceDataProc) ?*MaDevice;
extern fn rl_ma_device_destroy(device: ?*MaDevice) void;
extern fn rl_ma_device_get_info(device: ?*MaDevice, info: *RlMaDeviceInfo) void;
extern fn rl_ma_mutex_create() ?*MaMutex;
extern fn rl_ma_mutex_destroy(mutex: ?*MaMutex) void;
extern fn rl_ma_data_converter_create(formatIn: c_int, channelsIn: c_uint, sampleRateIn: c_uint, sampleRateOut: c_uint) ?*MaDataConverter;
extern fn rl_ma_data_converter_destroy(converter: ?*MaDataConverter) void;
extern fn rl_ma_data_converter_resampler_rate_in(converter: ?*MaDataConverter) c_uint;
extern fn rl_ma_data_converter_resampler_rate_out(converter: ?*MaDataConverter) c_uint;

// miniaudio direct externs (MA_API, non-static; miniaudio.h lines cited)
extern fn ma_device_start(device: ?*MaDevice) c_int; // :9185, ma_result
extern fn ma_device_set_master_volume(device: ?*MaDevice, volume: f32) c_int; // :9417
extern fn ma_device_get_master_volume(device: ?*MaDevice, volume: [*c]f32) c_int; // :9460
extern fn ma_mutex_lock(mutex: ?*MaMutex) void; // :6219
extern fn ma_mutex_unlock(mutex: ?*MaMutex) void; // :6224
extern fn ma_data_converter_process_pcm_frames(converter: ?*MaDataConverter, framesIn: ?*const anyopaque, frameCountIn: [*c]u64, framesOut: ?*anyopaque, frameCountOut: [*c]u64) c_int; // :5655
extern fn ma_data_converter_set_rate(converter: ?*MaDataConverter, sampleRateIn: c_uint, sampleRateOut: c_uint) c_int; // :5656
extern fn ma_get_bytes_per_sample(format: c_int) c_uint; // :6170
extern fn ma_convert_frames(out: ?*anyopaque, frameCountOut: u64, formatOut: c_int, channelsOut: c_uint, sampleRateOut: c_uint, in: ?*const anyopaque, frameCountIn: u64, formatIn: c_int, channelsIn: c_uint, sampleRateIn: c_uint) u64; // :5827
extern fn ma_get_format_name(format: c_int) [*c]const u8; // :6155

// ma_get_bytes_per_frame is `static MA_INLINE` (miniaudio.h:6171): reimplemented,
// same expression: ma_get_bytes_per_sample(format)*channels
inline fn maGetBytesPerFrame(format: c_int, channels: c_uint) c_uint {
    return ma_get_bytes_per_sample(format) *% channels;
}

// dr_wav (dr_wav.h:1053-1327; drwav_bool32 is u32, drwav_result is i32, drwav_uint64 is u64)
extern fn rl_sizeof_drwav() usize;
extern fn rl_drwav_get_info(wav: ?*DrWav, totalPCMFrameCount: [*c]u64, sampleRate: [*c]c_uint, channels: [*c]c_uint, bitsPerSample: [*c]c_uint) void;
extern fn drwav_init_memory(wav: ?*DrWav, data: ?*const anyopaque, dataSize: usize, allocationCallbacks: ?*const anyopaque) u32; // :1277
extern fn drwav_init_file(wav: ?*DrWav, filename: [*c]const u8, allocationCallbacks: ?*const anyopaque) u32; // :1246
extern fn rl_drwav_init_memory_write(wav: ?*DrWav, ppData: [*c]?*anyopaque, pDataSize: [*c]usize, format: c_uint, channels: c_uint, sampleRate: c_uint, bitsPerSample: c_uint) u32;
extern fn drwav_uninit(wav: ?*DrWav) i32; // :1053
extern fn drwav_read_pcm_frames_s16(wav: ?*DrWav, framesToRead: u64, bufferOut: [*c]i16) u64; // :1138
extern fn drwav_read_pcm_frames_f32(wav: ?*DrWav, framesToRead: u64, bufferOut: [*c]f32) u64; // :1173
extern fn drwav_write_pcm_frames(wav: ?*DrWav, framesToWrite: u64, data: ?*const anyopaque) u64; // :1122
extern fn rl_drwav_seek_to_first_pcm_frame(wav: ?*DrWav) u32; // DRWAV_PRIVATE upstream (:6011)
extern fn drwav_seek_to_pcm_frame(wav: ?*DrWav, targetFrameIndex: u64) u32; // :1094
extern fn drwav_free(p: ?*anyopaque, allocationCallbacks: ?*const anyopaque) void; // :1327

// stb_vorbis (stb_vorbis.c:150-361)
extern fn stb_vorbis_open_memory(data: [*c]const u8, len: c_int, err: [*c]c_int, allocBuffer: ?*const anyopaque) ?*StbVorbis; // :268
extern fn stb_vorbis_open_filename(filename: [*c]const u8, err: [*c]c_int, allocBuffer: ?*const anyopaque) ?*StbVorbis; // :274
extern fn rl_stb_vorbis_get_info(vorbis: ?*StbVorbis, sampleRate: [*c]c_uint, channels: [*c]c_int) void; // get_info returns by value (:150)
extern fn stb_vorbis_stream_length_in_samples(vorbis: ?*StbVorbis) c_uint; // :310
extern fn stb_vorbis_get_samples_short_interleaved(vorbis: ?*StbVorbis, channels: c_int, buffer: [*c]i16, numShorts: c_int) c_int; // :361
extern fn stb_vorbis_seek_start(vorbis: ?*StbVorbis) c_int; // :307
extern fn stb_vorbis_seek_frame(vorbis: ?*StbVorbis, sampleNumber: c_uint) c_int; // :298
extern fn stb_vorbis_close(vorbis: ?*StbVorbis) void; // :159

// dr_mp3 (dr_mp3.h:463-558; drmp3_bool32 is u32, drmp3_uint64 is u64)
const Drmp3Config = extern struct { channels: c_uint, sampleRate: c_uint }; // dr_mp3.h:393-396
extern fn rl_sizeof_drmp3() usize;
extern fn rl_drmp3_get_info(mp3: ?*DrMp3, channels: [*c]c_uint, sampleRate: [*c]c_uint) void; // fields at dr_mp3.h:401-402
extern fn drmp3_init_memory(mp3: ?*DrMp3, data: ?*const anyopaque, dataSize: usize, allocationCallbacks: ?*const anyopaque) u32; // :463
extern fn drmp3_init_file(mp3: ?*DrMp3, filePath: [*c]const u8, allocationCallbacks: ?*const anyopaque) u32; // :476
extern fn drmp3_uninit(mp3: ?*DrMp3) void; // :483
extern fn drmp3_read_pcm_frames_f32(mp3: ?*DrMp3, framesToRead: u64, bufferOut: [*c]f32) u64; // :490
extern fn drmp3_get_pcm_frame_count(mp3: ?*DrMp3) u64; // :510
extern fn drmp3_seek_to_pcm_frame(mp3: ?*DrMp3, frameIndex: u64) u32; // :504
extern fn rl_drmp3_seek_to_start_of_stream(mp3: ?*DrMp3) u32; // static upstream (:4348)
extern fn drmp3_open_memory_and_read_pcm_frames_f32(data: ?*const anyopaque, dataSize: usize, config: [*c]Drmp3Config, totalFrameCount: [*c]u64, allocationCallbacks: ?*const anyopaque) [*c]f32; // :558

// qoa / qoaplay (qoa.h:143-154, qoaplay.c:64-74)
extern fn rl_qoa_decode(bytes: [*c]const u8, size: c_int, channels: [*c]c_uint, samplerate: [*c]c_uint, samples: [*c]c_uint) [*c]i16;
extern fn rl_qoa_write(fileName: [*c]const u8, sampleData: [*c]const i16, channels: c_uint, samplerate: c_uint, samples: c_uint) c_int;
extern fn qoaplay_open(path: [*c]const u8) ?*QoaPlayDesc; // qoaplay.c:64
extern fn qoaplay_open_memory(data: [*c]const u8, dataSize: c_int) ?*QoaPlayDesc; // :65
extern fn qoaplay_close(ctx: ?*QoaPlayDesc) void; // :66
extern fn qoaplay_rewind(ctx: ?*QoaPlayDesc) void; // :68
extern fn qoaplay_seek_frame(ctx: ?*QoaPlayDesc, frame: c_int) void; // :69
extern fn qoaplay_decode(ctx: ?*QoaPlayDesc, sampleData: [*c]f32, numSamples: c_int) c_uint; // :70
extern fn rl_qoaplay_get_info(ctx: ?*QoaPlayDesc, channels: [*c]c_uint, samplerate: [*c]c_uint, samples: [*c]c_uint) void;
extern fn rl_qoaplay_sample_position(ctx: ?*QoaPlayDesc) c_uint;

// jar_xm (jar_xm.h:93-220)
extern fn jar_xm_create_context_from_file(ctx: [*c]?*JarXmContext, rate: u32, filename: [*c]const u8) c_int; // :93
extern fn jar_xm_create_context_safe(ctx: [*c]?*JarXmContext, moddata: [*c]const u8, moddataLength: usize, rate: u32) c_int; // :112
extern fn jar_xm_free_context(ctx: ?*JarXmContext) void; // :115
extern fn jar_xm_set_max_loop_count(ctx: ?*JarXmContext, loopcnt: u8) void; // :150
extern fn jar_xm_get_remaining_samples(ctx: ?*JarXmContext) u64; // :220
extern fn jar_xm_reset(ctx: ?*JarXmContext) void; // :2259
extern fn jar_xm_generate_samples(ctx: ?*JarXmContext, output: [*c]f32, numsamples: usize) void; // :120
extern fn jar_xm_get_position(ctx: ?*JarXmContext, patternIndex: [*c]u8, pattern: [*c]u8, row: [*c]u8, samples: [*c]u64) void; // :202

// jar_mod (jar_mod.h:245-252; mulong is unsigned long)
extern fn rl_sizeof_jar_mod_context() usize;
extern fn rl_jar_mod_load_memory(data: [*c]const u8, dataSize: c_int) ?*JarModContext; // jar_mod_load is static upstream (:1117)
extern fn jar_mod_init(ctx: ?*JarModContext) bool; // :245
extern fn jar_mod_load_file(ctx: ?*JarModContext, filename: [*c]const u8) c_ulong; // :249
extern fn jar_mod_unload(ctx: ?*JarModContext) void; // :248
extern fn jar_mod_max_samples(ctx: ?*JarModContext) c_ulong; // :251
extern fn jar_mod_seek_start(ctx: ?*JarModContext) void; // :252
extern fn jar_mod_fillbuffer(ctx: ?*JarModContext, outBuffer: [*c]i16, nbsample: c_ulong, trkbuf: ?*anyopaque) void; // :247

//----------------------------------------------------------------------------------
// Small helpers for C implicit-conversion semantics
//----------------------------------------------------------------------------------

// C implicit `int` -> `size_t` conversion: sign-extend, then reinterpret.
inline fn cSizeT(n: c_int) usize {
    return @bitCast(@as(isize, n));
}

// C implicit `int` -> `uint64` (ma_uint64/drwav_uint64) conversion: sign-extend.
inline fn cU64(n: c_int) u64 {
    return @bitCast(@as(i64, n));
}

// C locks `AUDIO.System.lock` (an embedded, zero-initialized ma_mutex) even before
// InitAudioDevice() ever ran; our mutex only exists once created there, so locking
// is skipped while there is no mutex (single-threaded at that point: same behavior).
inline fn lockAudio() void {
    if (AUDIO.system.lock) |lock| ma_mutex_lock(lock);
}

inline fn unlockAudio() void {
    if (AUDIO.system.lock) |lock| ma_mutex_unlock(lock);
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Audio Device initialization and Closing
//----------------------------------------------------------------------------------

// Initialize audio device
export fn InitAudioDevice() void {
    // Init audio context (raudio.c:468-476); the log callback is built-and-discarded
    // inside the shim exactly as upstream does
    const context = rl_ma_context_create(&onLog) orelse {
        TraceLog(LOG_WARNING, "AUDIO: Failed to initialize context");
        return;
    };
    AUDIO.system.context = context;

    // Init audio device: default playback device, f32 stereo (raudio.c:480-497)
    const device = rl_ma_device_create(context, &onSendAudioDataToDevice) orelse {
        TraceLog(LOG_WARNING, "AUDIO: Failed to initialize playback device");
        rl_ma_context_destroy(context);
        AUDIO.system.context = null;
        return;
    };
    AUDIO.system.device = device;

    // Cache the device properties NOW: ma_device_start below can invoke the data
    // callback synchronously (e.g. the pulse backend primes its stream during
    // start), and the callback sizes its output memset from these fields. C reads
    // them live from pDevice->playback.*, which ma_device_init already filled.
    var info: RlMaDeviceInfo = undefined;
    rl_ma_device_get_info(device, &info);
    AUDIO.system.deviceSampleRate = info.sampleRate;
    AUDIO.system.playbackFormat = info.format;
    AUDIO.system.playbackChannels = info.channels;
    AUDIO.system.playbackInternalPeriodSizeInFrames = info.internalPeriodSizeInFrames;

    // Mixing happens on a separate thread, synchronized by this mutex (raudio.c:502-508)
    const lock = rl_ma_mutex_create() orelse {
        TraceLog(LOG_WARNING, "AUDIO: Failed to create mutex for mixing");
        rl_ma_device_destroy(device);
        rl_ma_context_destroy(context);
        AUDIO.system.device = null;
        AUDIO.system.context = null;
        return;
    };
    AUDIO.system.lock = lock;

    // Keep the device running the whole time (raudio.c:512-519)
    if (ma_device_start(device) != MA_SUCCESS) {
        TraceLog(LOG_WARNING, "AUDIO: Failed to start playback device");
        rl_ma_device_destroy(device);
        rl_ma_context_destroy(context);
        AUDIO.system.device = null;
        AUDIO.system.context = null;
        // NOTE: like raudio.c, the mutex stays initialized on this path
        return;
    }

    TraceLog(LOG_INFO, "AUDIO: Device initialized successfully");
    TraceLog(LOG_INFO, "    > Backend:       miniaudio | %s", rl_ma_context_backend_name(context));
    TraceLog(LOG_INFO, "    > Format:        %s -> %s", ma_get_format_name(info.format), ma_get_format_name(info.internalFormat));
    TraceLog(LOG_INFO, "    > Channels:      %d -> %d", info.channels, info.internalChannels);
    TraceLog(LOG_INFO, "    > Sample rate:   %d -> %d", info.sampleRate, info.internalSampleRate);
    TraceLog(LOG_INFO, "    > Periods size:  %d", info.internalPeriodSizeInFrames *% info.internalPeriods);

    AUDIO.system.isReady = true;
}

// Close the audio device for all contexts
export fn CloseAudioDevice() void {
    if (AUDIO.system.isReady) {
        // Stop the device first (joins the callback thread) before destroying the mutex it locks
        rl_ma_device_destroy(AUDIO.system.device);
        AUDIO.system.device = null;
        rl_ma_mutex_destroy(AUDIO.system.lock);
        AUDIO.system.lock = null;
        rl_ma_context_destroy(AUDIO.system.context);
        AUDIO.system.context = null;

        // ma_device_uninit() zeroes the C global's device struct; reset the cache to match
        AUDIO.system.deviceSampleRate = 0;
        AUDIO.system.playbackFormat = 0;
        AUDIO.system.playbackChannels = 0;
        AUDIO.system.playbackInternalPeriodSizeInFrames = 0;

        AUDIO.system.isReady = false;
        RL_FREE(AUDIO.system.pcmBuffer);
        AUDIO.system.pcmBuffer = null;
        AUDIO.system.pcmBufferSize = 0;

        TraceLog(LOG_INFO, "AUDIO: Device closed successfully");
    } else TraceLog(LOG_WARNING, "AUDIO: Device could not be closed, not currently initialized");
}

// Check if device has been initialized successfully
export fn IsAudioDeviceReady() bool {
    return AUDIO.system.isReady;
}

// Set master volume (listener)
export fn SetMasterVolume(volume: f32) void {
    _ = ma_device_set_master_volume(AUDIO.system.device, volume);
}

// Get master volume (listener)
export fn GetMasterVolume() f32 {
    var volume: f32 = 0.0;
    _ = ma_device_get_master_volume(AUDIO.system.device, &volume);
    return volume;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Audio Buffer management
//----------------------------------------------------------------------------------

// Initialize a new audio buffer (filled with silence)
export fn LoadAudioBuffer(format: c_int, channels: c_uint, sampleRate: c_uint, sizeInFrames: c_uint, usage: c_int) ?*AudioBuffer {
    const bufferMem = RL_CALLOC(1, @sizeOf(AudioBuffer)) orelse {
        TraceLog(LOG_WARNING, "AUDIO: Failed to allocate memory for buffer");
        return null;
    };
    const audioBuffer: *AudioBuffer = @ptrCast(@alignCast(bufferMem));

    var data: ?[*]u8 = null;
    if (sizeInFrames > 0) data = @ptrCast(RL_CALLOC(@as(usize, sizeInFrames *% channels *% ma_get_bytes_per_sample(format)), 1));

    // Audio data runs through a format converter (raudio.c:588-598); output side is
    // always AUDIO_DEVICE_FORMAT x AUDIO_DEVICE_CHANNELS at the device sample rate
    const converter = rl_ma_data_converter_create(format, channels, sampleRate, AUDIO.system.deviceSampleRate) orelse {
        TraceLog(LOG_WARNING, "AUDIO: Failed to create data conversion pipeline");
        RL_FREE(bufferMem); // NOTE: like raudio.c:596, `data` is not freed on this path
        return null;
    };

    // Residual input-frame cache for the converter; required because pitch shifting
    // is done through resampling (raudio.c:600-607)
    const converterResidual: [*]u8 = @ptrCast(RL_CALLOC(@as(usize, AUDIO_BUFFER_RESIDUAL_CAPACITY *% maGetBytesPerFrame(format, channels)), 1).?);

    audioBuffer.* = .{
        .converter = converter,
        .formatIn = format,
        .channelsIn = channels,
        .channelsOut = AUDIO_DEVICE_CHANNELS,
        .sampleRateIn = sampleRate,
        .converterResidual = converterResidual,
        .converterResidualCount = 0,
        .callback = null,
        .processor = null,
        .volume = 1.0,
        .pitch = 1.0,
        .pan = 0.0, // Center
        .playing = false,
        .paused = false,
        .looping = false,
        .usage = usage,
        // Buffers should be marked as processed by default so that a call to
        // UpdateAudioStream() immediately after initialization works correctly
        .isSubBufferProcessed = .{ true, true },
        .sizeInFrames = sizeInFrames,
        .frameCursorPos = 0,
        .framesProcessed = 0,
        .data = data,
        .next = null,
        .prev = null,
    };

    // Track audio buffer to linked list next position
    TrackAudioBuffer(audioBuffer);

    return audioBuffer;
}

// Delete an audio buffer
export fn UnloadAudioBuffer(buffer: ?*AudioBuffer) void {
    if (buffer) |b| {
        UntrackAudioBuffer(b);
        rl_ma_data_converter_destroy(b.converter);
        RL_FREE(b.converterResidual);
        RL_FREE(b.data);
        RL_FREE(b);
    }
}

// Check if an audio buffer is playing from a program state without lock
export fn IsAudioBufferPlaying(buffer: ?*AudioBuffer) bool {
    lockAudio();
    const result = isAudioBufferPlayingInLockedState(buffer);
    unlockAudio();
    return result;
}

// Play an audio buffer
// NOTE: Buffer is restarted to the start
// Use PauseAudioBuffer() and ResumeAudioBuffer() if the playback position should be maintained
export fn PlayAudioBuffer(buffer: ?*AudioBuffer) void {
    if (buffer) |b| {
        lockAudio();
        b.playing = true;
        b.paused = false;
        b.frameCursorPos = 0;
        b.framesProcessed = 0;
        b.isSubBufferProcessed[0] = true;
        b.isSubBufferProcessed[1] = true;
        unlockAudio();
    }
}

// Stop an audio buffer from a program state without lock
export fn StopAudioBuffer(buffer: ?*AudioBuffer) void {
    lockAudio();
    stopAudioBufferInLockedState(buffer);
    unlockAudio();
}

// Pause an audio buffer
export fn PauseAudioBuffer(buffer: ?*AudioBuffer) void {
    if (buffer) |b| {
        lockAudio();
        b.paused = true;
        unlockAudio();
    }
}

// Resume an audio buffer
export fn ResumeAudioBuffer(buffer: ?*AudioBuffer) void {
    if (buffer) |b| {
        lockAudio();
        b.paused = false;
        unlockAudio();
    }
}

// Set volume for an audio buffer
export fn SetAudioBufferVolume(buffer: ?*AudioBuffer, volume: f32) void {
    if (buffer) |b| {
        lockAudio();
        b.volume = volume;
        unlockAudio();
    }
}

// Set pitch for an audio buffer
export fn SetAudioBufferPitch(buffer: ?*AudioBuffer, pitch: f32) void {
    if (buffer != null and pitch > 0.0) {
        const b = buffer.?;
        lockAudio();
        // Pitching is an adjustment of the sample rate; this changes the duration
        // of the sound: higher pitches are faster, lower pitches slower
        const outputSampleRate: c_uint = @intFromFloat(@as(f32, @floatFromInt(AUDIO.system.deviceSampleRate)) / pitch);
        _ = ma_data_converter_set_rate(b.converter, b.sampleRateIn, outputSampleRate);

        b.pitch = pitch;
        unlockAudio();
    }
}

// Set pan for an audio buffer
export fn SetAudioBufferPan(buffer: ?*AudioBuffer, pan: f32) void {
    var clampedPan = pan;
    if (clampedPan < -1.0) {
        clampedPan = -1.0;
    } else if (clampedPan > 1.0) {
        clampedPan = 1.0;
    }

    if (buffer) |b| {
        lockAudio();
        b.pan = clampedPan;
        unlockAudio();
    }
}

// Track audio buffer to linked list next position
export fn TrackAudioBuffer(buffer: ?*AudioBuffer) void {
    lockAudio();
    {
        if (AUDIO.buffer.first == null) {
            AUDIO.buffer.first = buffer;
        } else {
            AUDIO.buffer.last.?.next = buffer;
            buffer.?.prev = AUDIO.buffer.last;
        }

        AUDIO.buffer.last = buffer;
    }
    unlockAudio();
}

// Untrack audio buffer from linked list
export fn UntrackAudioBuffer(buffer: ?*AudioBuffer) void {
    lockAudio();
    {
        const b = buffer.?;
        if (b.prev == null) AUDIO.buffer.first = b.next else b.prev.?.next = b.next;

        if (b.next == null) AUDIO.buffer.last = b.prev else b.next.?.prev = b.prev;

        b.prev = null;
        b.next = null;
    }
    unlockAudio();
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Sounds loading and playing (.WAV)
//----------------------------------------------------------------------------------

// Load wave data from file
export fn LoadWave(fileName: [*c]const u8) Wave {
    var wave = std.mem.zeroes(Wave);

    // Loading file to memory
    var dataSize: c_int = 0;
    const fileData = LoadFileData(fileName, &dataSize);

    // Loading wave from memory data
    if (fileData != null) wave = LoadWaveFromMemory(GetFileExtension(fileName), fileData, dataSize);

    UnloadFileData(fileData);

    return wave;
}

// Load wave from memory buffer, fileType refers to extension: i.e. ".wav"
// WARNING: File extension must be provided in lower-case
export fn LoadWaveFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: c_int) Wave {
    var wave = std.mem.zeroes(Wave);

    if (SUPPORT_FILEFORMAT_WAV and ((strcmp(fileType, ".wav") == 0) or (strcmp(fileType, ".WAV") == 0))) {
        // C keeps a stack-local `drwav wav = { 0 }` (raudio.c:816); the struct is
        // opaque here, so it lives on the heap for the duration of the call
        const wav: ?*DrWav = @ptrCast(RL_CALLOC(1, rl_sizeof_drwav()));
        const success = drwav_init_memory(wav, fileData, cSizeT(dataSize), null) != 0;

        if (success) {
            var totalPCMFrameCount: u64 = 0;
            var sampleRate: c_uint = 0;
            var channels: c_uint = 0;
            var bitsPerSample: c_uint = 0;
            rl_drwav_get_info(wav, &totalPCMFrameCount, &sampleRate, &channels, &bitsPerSample);

            wave.frameCount = @truncate(totalPCMFrameCount);
            wave.sampleRate = sampleRate;
            wave.sampleSize = 16;
            wave.channels = channels;
            wave.data = RL_CALLOC(@as(usize, wave.frameCount) * wave.channels, @sizeOf(c_short));

            // NOTE: Forcing conversion to 16bit sample size on reading
            _ = drwav_read_pcm_frames_s16(wav, wave.frameCount, @ptrCast(@alignCast(wave.data)));
        } else TraceLog(LOG_WARNING, "WAVE: Failed to load WAV data");

        _ = drwav_uninit(wav);
        RL_FREE(wav);
    } else if (SUPPORT_FILEFORMAT_OGG and ((strcmp(fileType, ".ogg") == 0) or (strcmp(fileType, ".OGG") == 0))) {
        const oggData = stb_vorbis_open_memory(fileData, dataSize, null, null);

        if (oggData != null) {
            var sampleRate: c_uint = 0;
            var channels: c_int = 0;
            rl_stb_vorbis_get_info(oggData, &sampleRate, &channels);

            wave.sampleRate = sampleRate;
            wave.sampleSize = 16; // By default, ogg data is 16 bit per sample (short)
            wave.channels = @bitCast(channels);
            wave.frameCount = stb_vorbis_stream_length_in_samples(oggData); // NOTE: It returns frames!
            wave.data = RL_CALLOC(wave.frameCount *% wave.channels, @sizeOf(c_short));

            // NOTE: Get the number of samples to process (be careful! asking for number of shorts, not bytes!)
            _ = stb_vorbis_get_samples_short_interleaved(oggData, channels, @ptrCast(@alignCast(wave.data)), @bitCast(wave.frameCount *% wave.channels));
            stb_vorbis_close(oggData);
        } else TraceLog(LOG_WARNING, "WAVE: Failed to load OGG data");
    } else if (SUPPORT_FILEFORMAT_MP3 and ((strcmp(fileType, ".mp3") == 0) or (strcmp(fileType, ".MP3") == 0))) {
        var config = std.mem.zeroes(Drmp3Config);
        var totalFrameCount: u64 = 0;

        // NOTE: Forcing conversion to 32bit float sample size on reading
        wave.data = drmp3_open_memory_and_read_pcm_frames_f32(fileData, cSizeT(dataSize), &config, &totalFrameCount, null);
        wave.sampleSize = 32;

        if (wave.data != null) {
            wave.channels = config.channels;
            wave.sampleRate = config.sampleRate;
            wave.frameCount = @truncate(totalFrameCount); // WARNING: Potential loss of data
        } else TraceLog(LOG_WARNING, "WAVE: Failed to load MP3 data");
    } else if (SUPPORT_FILEFORMAT_QOA and ((strcmp(fileType, ".qoa") == 0) or (strcmp(fileType, ".QOA") == 0))) {
        var channels: c_uint = 0;
        var samplerate: c_uint = 0;
        var samples: c_uint = 0;

        // NOTE: Returned sample data is always 16 bit
        wave.data = rl_qoa_decode(fileData, dataSize, &channels, &samplerate, &samples);
        wave.sampleSize = 16;

        if (wave.data != null) {
            wave.channels = channels;
            wave.sampleRate = samplerate;
            wave.frameCount = samples;
        } else TraceLog(LOG_WARNING, "WAVE: Failed to load QOA data");
    } else {
        // SUPPORT_FILEFORMAT_FLAC is 0 in this build (raudio.c:896-908 not compiled)
        TraceLog(LOG_WARNING, "WAVE: Data format not supported");
    }

    TraceLog(LOG_INFO, "WAVE: Data loaded successfully (%i Hz, %i bit, %i channels)", wave.sampleRate, wave.sampleSize, wave.channels);

    return wave;
}

// Check if wave data is valid (data loaded and parameters)
export fn IsWaveValid(wave: Wave) bool {
    var result = false;

    if ((wave.data != null) and // Validate wave data available
        (wave.frameCount > 0) and // Validate frame count
        (wave.sampleRate > 0) and // Validate sample rate is supported
        (wave.sampleSize > 0) and // Validate sample size is supported
        (wave.channels > 0)) result = true; // Validate number of channels supported

    return result;
}

// Load sound from file
// NOTE: The entire file is loaded to memory to be played (no-streaming)
export fn LoadSound(fileName: [*c]const u8) Sound {
    const wave = LoadWave(fileName);

    const sound = LoadSoundFromWave(wave);

    UnloadWave(wave); // Sound is loaded, wave can be unloaded

    return sound;
}

// Load sound from wave data
// NOTE: Wave data must be unallocated manually
export fn LoadSoundFromWave(wave: Wave) Sound {
    var sound = std.mem.zeroes(Sound);

    if (wave.data != null) {
        // Format conversion to the device format is done in one go at load time
        // (mixing with miniaudio is manual, so every sound must share one format)
        const formatIn: c_int = if (wave.sampleSize == 8) ma_format_u8 else if (wave.sampleSize == 16) ma_format_s16 else ma_format_f32;
        const frameCountIn: c_uint = wave.frameCount;

        var frameCount: c_uint = @truncate(ma_convert_frames(null, 0, AUDIO_DEVICE_FORMAT, AUDIO_DEVICE_CHANNELS, AUDIO.system.deviceSampleRate, null, frameCountIn, formatIn, wave.channels, wave.sampleRate));
        if (frameCount == 0) TraceLog(LOG_WARNING, "SOUND: Failed to get frame count for format conversion");

        const audioBuffer = LoadAudioBuffer(AUDIO_DEVICE_FORMAT, AUDIO_DEVICE_CHANNELS, AUDIO.system.deviceSampleRate, frameCount, AUDIO_BUFFER_USAGE_STATIC);
        if (audioBuffer) |buffer| {
            frameCount = @truncate(ma_convert_frames(buffer.data, frameCount, AUDIO_DEVICE_FORMAT, AUDIO_DEVICE_CHANNELS, AUDIO.system.deviceSampleRate, wave.data, frameCountIn, formatIn, wave.channels, wave.sampleRate));
            if (frameCount == 0) TraceLog(LOG_WARNING, "SOUND: Failed format conversion");

            sound.frameCount = frameCount;
            sound.stream.sampleRate = AUDIO.system.deviceSampleRate;
            sound.stream.sampleSize = 32;
            sound.stream.channels = AUDIO_DEVICE_CHANNELS;
            sound.stream.buffer = buffer;
        } else TraceLog(LOG_WARNING, "SOUND: Failed to create buffer");
    }

    return sound;
}

// Load sound alias, clone sound from existing sound data, clone does not own wave data
// NOTE: Wave data must be unallocated manually and will be shared across all clones
export fn LoadSoundAlias(source: Sound) Sound {
    var sound = std.mem.zeroes(Sound);

    if (source.stream.buffer != null and source.stream.buffer.?.data != null) {
        const audioBuffer = LoadAudioBuffer(AUDIO_DEVICE_FORMAT, AUDIO_DEVICE_CHANNELS, AUDIO.system.deviceSampleRate, 0, AUDIO_BUFFER_USAGE_STATIC);

        if (audioBuffer) |buffer| {
            buffer.sizeInFrames = source.stream.buffer.?.sizeInFrames;
            buffer.data = source.stream.buffer.?.data;

            // Initialize the buffer as if it was new
            buffer.volume = 1.0;
            buffer.pitch = 1.0;
            buffer.pan = 0.0; // Center

            sound.frameCount = source.frameCount;
            sound.stream.sampleRate = AUDIO.system.deviceSampleRate;
            sound.stream.sampleSize = 32;
            sound.stream.channels = AUDIO_DEVICE_CHANNELS;
            sound.stream.buffer = buffer;
        } else TraceLog(LOG_WARNING, "SOUND: Failed to create buffer");
    }

    return sound;
}

// Check if sound is valid (data loaded and buffers initialized)
export fn IsSoundValid(sound: Sound) bool {
    var result = false;

    if ((sound.frameCount > 0) and // Validate frame count
        (sound.stream.buffer != null) and // Validate stream buffer
        (sound.stream.sampleRate > 0) and // Validate sample rate is supported
        (sound.stream.sampleSize > 0) and // Validate sample size is supported
        (sound.stream.channels > 0)) result = true; // Validate number of channels supported

    return result;
}

// Unload wave data
export fn UnloadWave(wave: Wave) void {
    RL_FREE(wave.data);
}

// Unload sound
export fn UnloadSound(sound: Sound) void {
    UnloadAudioBuffer(sound.stream.buffer);
}

export fn UnloadSoundAlias(alias: Sound) void {
    // Untrack and unload the sound buffer, not the sample data, it is shared with the source for the alias
    if (alias.stream.buffer) |buffer| {
        UntrackAudioBuffer(buffer);
        rl_ma_data_converter_destroy(buffer.converter);
        RL_FREE(buffer.converterResidual);
        RL_FREE(buffer);
    }
}

// Update sound buffer with new data
// PARAMS: [data], format must match sound.stream.sampleSize, default 32 bit float - stereo
// PARAMS: [frameCount] must not exceed sound.frameCount
export fn UpdateSound(sound: Sound, data: ?*const anyopaque, frameCount: c_int) void {
    if (sound.stream.buffer) |buffer| {
        StopAudioBuffer(buffer);

        _ = memcpy(buffer.data, data, @as(usize, @as(c_uint, @bitCast(frameCount)) *% maGetBytesPerFrame(buffer.formatIn, buffer.channelsIn)));
    }
}

// Export wave data to file
export fn ExportWave(wave: Wave, fileName: [*c]const u8) bool {
    var result = false;

    if (SUPPORT_FILEFORMAT_WAV and IsFileExtension(fileName, ".wav")) {
        // C keeps a stack-local `drwav wav = { 0 }` (raudio.c:1078); opaque here, so heap
        const wav: ?*DrWav = @ptrCast(RL_CALLOC(1, rl_sizeof_drwav()));
        const format: c_uint = if (wave.sampleSize == 32) DR_WAVE_FORMAT_IEEE_FLOAT else DR_WAVE_FORMAT_PCM;

        var fileData: ?*anyopaque = null;
        var fileDataSize: usize = 0;
        result = rl_drwav_init_memory_write(wav, &fileData, &fileDataSize, format, wave.channels, wave.sampleRate, wave.sampleSize) != 0;
        if (result) result = @as(c_int, @bitCast(@as(c_uint, @truncate(drwav_write_pcm_frames(wav, wave.frameCount, wave.data))))) != 0;
        const uninitResult: c_int = drwav_uninit(wav);

        // NOTE: raudio.c:1091-1093 shadows `result` with the drwav_result here, so
        // SaveFileData's outcome never reaches the returned value (kept as-is)
        if (uninitResult == DRWAV_SUCCESS) _ = SaveFileData(fileName, fileData, @bitCast(@as(c_uint, @truncate(fileDataSize))));

        drwav_free(fileData, null);
        RL_FREE(wav);
    } else if (SUPPORT_FILEFORMAT_QOA and IsFileExtension(fileName, ".qoa")) {
        if (wave.sampleSize == 16) {
            const bytesWritten = rl_qoa_write(fileName, @ptrCast(@alignCast(wave.data)), wave.channels, wave.sampleRate, wave.frameCount);
            if (bytesWritten > 0) result = true;
        } else TraceLog(LOG_WARNING, "AUDIO: Wave data must be 16 bit per sample for QOA format export");
    } else if (IsFileExtension(fileName, ".raw")) {
        // Export raw sample data (without header)
        // NOTE: It's up to the user to track wave parameters
        result = SaveFileData(fileName, wave.data, @bitCast(wave.frameCount *% wave.channels *% wave.sampleSize / 8));
    }

    if (result) TraceLog(LOG_INFO, "FILEIO: [%s] Wave data exported successfully", fileName) else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export wave data", fileName);

    return result;
}

// Export wave sample data to code (.h)
export fn ExportWaveAsCode(wave: Wave, fileName: [*c]const u8) bool {
    const TEXT_BYTES_PER_LINE: c_int = 20;

    const waveDataSize: c_int = @bitCast(wave.frameCount *% wave.channels *% wave.sampleSize / 8);

    // NOTE: Text data buffer size is estimated considering wave data size in bytes
    // and requiring 12 char bytes for every byte
    const txtData: [*c]u8 = @ptrCast(RL_CALLOC(cSizeT(waveDataSize *% 12 +% 2000), @sizeOf(u8)));

    var byteCount: c_int = 0;
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "\n//////////////////////////////////////////////////////////////////////////////////\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                              //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// WaveAsCode exporter v1.1 - Wave data exported as an array of bytes           //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                              //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// more info and bugs-report:  github.com/raysan5/raylib                        //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// feedback and support:       ray[at]raylib.com                                //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                              //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// Copyright (c) 2018-2026 Ramon Santamaria (@raysan5)                          //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//                                                                              //\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "//////////////////////////////////////////////////////////////////////////////////\n\n");

    // Get file name from path and convert variable name to uppercase
    var varFileName: [256]u8 = @splat(0);
    _ = strncpy(&varFileName, GetFileNameWithoutExt(fileName), 256 - 1);
    var n: usize = 0;
    while (varFileName[n] != 0) : (n += 1) {
        if (varFileName[n] >= 'a' and varFileName[n] <= 'z') varFileName[n] = varFileName[n] - 32;
    }

    // Add wave information
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "// Wave data information\n");
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#define %s_FRAME_COUNT      %u\n", &varFileName, wave.frameCount);
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#define %s_SAMPLE_RATE      %u\n", &varFileName, wave.sampleRate);
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#define %s_SAMPLE_SIZE      %u\n", &varFileName, wave.sampleSize);
    byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "#define %s_CHANNELS         %u\n\n", &varFileName, wave.channels);

    // Write wave data as an array of values
    // Wave data is exported as byte array for 8/16bit and float array for 32bit float data
    // NOTE: Frame data exported is channel-interlaced: frame01[sampleChannel1, sampleChannel2, ...], frame02[], frame03[]
    if (wave.sampleSize == 32) {
        const floatData: [*]const f32 = @ptrCast(@alignCast(wave.data.?));
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "static float %s_DATA[%i] = {\n", &varFileName, @divTrunc(waveDataSize, 4));
        var i: c_int = 1;
        while (i < @divTrunc(waveDataSize, 4)) : (i += 1) {
            const fmt: [*c]const u8 = if (@rem(i, TEXT_BYTES_PER_LINE) == 0) "%.4ff,\n    " else "%.4ff, ";
            byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), fmt, @as(f64, floatData[@intCast(i - 1)]));
        }
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "%.4ff };\n", @as(f64, floatData[@intCast(@divTrunc(waveDataSize, 4) - 1)]));
    } else {
        const byteData: [*]const u8 = @ptrCast(wave.data.?);
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "static unsigned char %s_DATA[%i] = { ", &varFileName, waveDataSize);
        var i: c_int = 1;
        while (i < waveDataSize) : (i += 1) {
            const fmt: [*c]const u8 = if (@rem(i, TEXT_BYTES_PER_LINE) == 0) "0x%x,\n    " else "0x%x, ";
            byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), fmt, @as(c_uint, byteData[@intCast(i - 1)]));
        }
        byteCount += sprintf(txtData + @as(usize, @intCast(byteCount)), "0x%x };\n", @as(c_uint, byteData[@intCast(waveDataSize - 1)]));
    }

    // NOTE: Text data length exported is determined by '\0' (NULL) character
    const result = SaveFileText(fileName, txtData);

    RL_FREE(txtData);

    if (result) TraceLog(LOG_INFO, "FILEIO: [%s] Wave as code exported successfully", fileName) else TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export wave as code", fileName);

    return result;
}

// Play a sound
export fn PlaySound(sound: Sound) void {
    PlayAudioBuffer(sound.stream.buffer);
}

// Pause a sound
export fn PauseSound(sound: Sound) void {
    PauseAudioBuffer(sound.stream.buffer);
}

// Resume a paused sound
export fn ResumeSound(sound: Sound) void {
    ResumeAudioBuffer(sound.stream.buffer);
}

// Stop reproducing a sound
export fn StopSound(sound: Sound) void {
    StopAudioBuffer(sound.stream.buffer);
}

// Check if sound is playing
export fn IsSoundPlaying(sound: Sound) bool {
    var result = false;

    if (IsAudioBufferPlaying(sound.stream.buffer)) result = true;

    return result;
}

// Set volume for a sound
export fn SetSoundVolume(sound: Sound, volume: f32) void {
    SetAudioBufferVolume(sound.stream.buffer, volume);
}

// Set pitch for a sound
export fn SetSoundPitch(sound: Sound, pitch: f32) void {
    SetAudioBufferPitch(sound.stream.buffer, pitch);
}

// Set pan for a sound
export fn SetSoundPan(sound: Sound, pan: f32) void {
    SetAudioBufferPan(sound.stream.buffer, pan);
}

// Convert wave data to desired format
export fn WaveFormat(wave: [*c]Wave, sampleRate: c_int, sampleSize: c_int, channels: c_int) void {
    const formatIn: c_int = if (wave.*.sampleSize == 8) ma_format_u8 else if (wave.*.sampleSize == 16) ma_format_s16 else ma_format_f32;
    const formatOut: c_int = if (sampleSize == 8) ma_format_u8 else if (sampleSize == 16) ma_format_s16 else ma_format_f32;

    const frameCountIn: c_uint = wave.*.frameCount;
    var frameCount: c_uint = @truncate(ma_convert_frames(null, 0, formatOut, @bitCast(channels), @bitCast(sampleRate), null, frameCountIn, formatIn, wave.*.channels, wave.*.sampleRate));

    if (frameCount == 0) {
        TraceLog(LOG_WARNING, "WAVE: Failed to get frame count for format conversion");
        return;
    }

    const data = RL_CALLOC(frameCount *% @as(c_uint, @bitCast(channels)) *% @as(c_uint, @bitCast(@divTrunc(sampleSize, 8))), 1);

    frameCount = @truncate(ma_convert_frames(data, frameCount, formatOut, @bitCast(channels), @bitCast(sampleRate), wave.*.data, frameCountIn, formatIn, wave.*.channels, wave.*.sampleRate));
    if (frameCount == 0) {
        RL_FREE(data);
        TraceLog(LOG_WARNING, "WAVE: Failed format conversion");
        return;
    }

    wave.*.frameCount = frameCount;
    wave.*.sampleSize = @bitCast(sampleSize);
    wave.*.sampleRate = @bitCast(sampleRate);
    wave.*.channels = @bitCast(channels);

    RL_FREE(wave.*.data);
    wave.*.data = data;
}

// Copy a wave to a new wave
export fn WaveCopy(wave: Wave) Wave {
    var newWave = std.mem.zeroes(Wave);

    newWave.data = RL_MALLOC(@as(usize, wave.frameCount *% wave.channels *% wave.sampleSize / 8));

    if (newWave.data != null) {
        // NOTE: Size must be provided in bytes
        _ = memcpy(newWave.data, wave.data, @as(usize, wave.frameCount *% wave.channels *% wave.sampleSize / 8));

        newWave.frameCount = wave.frameCount;
        newWave.sampleRate = wave.sampleRate;
        newWave.sampleSize = wave.sampleSize;
        newWave.channels = wave.channels;
    }

    return newWave;
}

// Crop a wave to defined frames range
// NOTE: Security check in case of out-of-range
export fn WaveCrop(wave: [*c]Wave, initFrame: c_int, finalFrame: c_int) void {
    if ((initFrame >= 0) and (initFrame < finalFrame) and (@as(c_uint, @bitCast(finalFrame)) <= wave.*.frameCount)) {
        const frameCount: c_int = finalFrame - initFrame;

        const cropSize: c_uint = @as(c_uint, @bitCast(frameCount)) *% wave.*.channels *% wave.*.sampleSize / 8;
        const data = RL_MALLOC(@as(usize, cropSize));

        const offset: c_uint = @as(c_uint, @bitCast(initFrame)) *% wave.*.channels *% wave.*.sampleSize / 8;
        _ = memcpy(data, @as([*]const u8, @ptrCast(wave.*.data.?)) + @as(usize, offset), @as(usize, cropSize));

        RL_FREE(wave.*.data);
        wave.*.data = data;
        wave.*.frameCount = @bitCast(frameCount);
    } else TraceLog(LOG_WARNING, "WAVE: Crop range out of bounds");
}

// Load samples data from wave as a floats array
// NOTE 1: Returned sample values are normalized to range [-1..1]
// NOTE 2: Sample data allocated should be freed with UnloadWaveSamples()
export fn LoadWaveSamples(wave: Wave) [*c]f32 {
    const samples: [*c]f32 = @ptrCast(@alignCast(RL_MALLOC(@as(usize, wave.frameCount *% wave.channels) * @sizeOf(f32))));

    // NOTE: sampleCount is the total number of interlaced samples (including channels)
    var i: c_uint = 0;
    while (i < wave.frameCount *% wave.channels) : (i += 1) {
        if (wave.sampleSize == 8) {
            const bytes: [*]const u8 = @ptrCast(wave.data.?);
            samples[@as(usize, i)] = @as(f32, @floatFromInt(@as(c_int, bytes[@as(usize, i)]) - 128)) / 128.0;
        } else if (wave.sampleSize == 16) {
            const shorts: [*]const i16 = @ptrCast(@alignCast(wave.data.?));
            samples[@as(usize, i)] = @as(f32, @floatFromInt(shorts[@as(usize, i)])) / 32768.0;
        } else if (wave.sampleSize == 32) {
            const floats: [*]const f32 = @ptrCast(@alignCast(wave.data.?));
            samples[@as(usize, i)] = floats[@as(usize, i)];
        }
    }

    return samples;
}

// Unload samples data loaded with LoadWaveSamples()
export fn UnloadWaveSamples(samples: [*c]f32) void {
    RL_FREE(samples);
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Music loading and stream playing
//----------------------------------------------------------------------------------

// Load music stream from file
export fn LoadMusicStream(fileName: [*c]const u8) Music {
    var music = std.mem.zeroes(Music);
    var musicLoaded = false;

    if (SUPPORT_FILEFORMAT_WAV and IsFileExtension(fileName, ".wav")) {
        const ctxWav: ?*DrWav = @ptrCast(RL_CALLOC(1, rl_sizeof_drwav()));
        const success = drwav_init_file(ctxWav, fileName, null) != 0;

        if (success) {
            music.ctxType = MUSIC_AUDIO_WAV;
            music.ctxData = ctxWav;

            var totalPCMFrameCount: u64 = 0;
            var sampleRate: c_uint = 0;
            var channels: c_uint = 0;
            var bitsPerSample: c_uint = 0;
            rl_drwav_get_info(ctxWav, &totalPCMFrameCount, &sampleRate, &channels, &bitsPerSample);

            var sampleSize: c_int = @bitCast(bitsPerSample);
            if (bitsPerSample == 24) sampleSize = 16; // Forcing conversion to s16 on UpdateMusicStream()

            music.stream = LoadAudioStream(sampleRate, @bitCast(sampleSize), channels);
            music.frameCount = @truncate(totalPCMFrameCount);
            music.looping = true; // Looping enabled by default
            musicLoaded = true;
        } else {
            RL_FREE(ctxWav);
        }
    } else if (SUPPORT_FILEFORMAT_OGG and IsFileExtension(fileName, ".ogg")) {
        // Open ogg audio stream
        const ctxOgg = stb_vorbis_open_filename(fileName, null, null);

        if (ctxOgg != null) {
            music.ctxType = MUSIC_AUDIO_OGG;
            music.ctxData = ctxOgg;

            var sampleRate: c_uint = 0;
            var channels: c_int = 0;
            rl_stb_vorbis_get_info(ctxOgg, &sampleRate, &channels); // Get Ogg file info

            // OGG bit rate defaults to 16 bit, it's enough for compressed format
            music.stream = LoadAudioStream(sampleRate, 16, @bitCast(channels));

            // WARNING: It seems this function returns length in frames, not samples, so multiply by channels
            music.frameCount = stb_vorbis_stream_length_in_samples(ctxOgg);
            music.looping = true; // Looping enabled by default
            musicLoaded = true;
        } else {
            stb_vorbis_close(ctxOgg);
        }
    } else if (SUPPORT_FILEFORMAT_MP3 and IsFileExtension(fileName, ".mp3")) {
        const ctxMp3: ?*DrMp3 = @ptrCast(RL_CALLOC(1, rl_sizeof_drmp3()));
        const result: c_int = @bitCast(drmp3_init_file(ctxMp3, fileName, null));

        if (result > 0) {
            music.ctxType = MUSIC_AUDIO_MP3;
            music.ctxData = ctxMp3;

            var channels: c_uint = 0;
            var sampleRate: c_uint = 0;
            rl_drmp3_get_info(ctxMp3, &channels, &sampleRate);

            music.stream = LoadAudioStream(sampleRate, 32, channels);
            music.frameCount = @truncate(drmp3_get_pcm_frame_count(ctxMp3));
            music.looping = true; // Looping enabled by default
            musicLoaded = true;
        } else {
            RL_FREE(ctxMp3);
        }
    } else if (SUPPORT_FILEFORMAT_QOA and IsFileExtension(fileName, ".qoa")) {
        const ctxQoa = qoaplay_open(fileName);

        if (ctxQoa != null) {
            music.ctxType = MUSIC_AUDIO_QOA;
            music.ctxData = ctxQoa;

            var channels: c_uint = 0;
            var samplerate: c_uint = 0;
            var samples: c_uint = 0;
            rl_qoaplay_get_info(ctxQoa, &channels, &samplerate, &samples);

            // NOTE: Loading samples as 32bit float normalized data, so,
            // configure the output audio stream to also use float 32bit
            music.stream = LoadAudioStream(samplerate, 32, channels);
            music.frameCount = samples;
            music.looping = true; // Looping enabled by default
            musicLoaded = true;
        }
        // else: no uninit required
    } else if (SUPPORT_FILEFORMAT_XM and IsFileExtension(fileName, ".xm")) {
        var ctxXm: ?*JarXmContext = null;
        const result = jar_xm_create_context_from_file(&ctxXm, AUDIO.system.deviceSampleRate, fileName);

        if (result == 0) { // XM context created successfully
            music.ctxType = MUSIC_MODULE_XM;
            music.ctxData = ctxXm;
            jar_xm_set_max_loop_count(ctxXm, 0); // Set infinite number of loops

            // AUDIO_DEVICE_FORMAT is ma_format_f32 in this build -> 32 bit (raudio.c:1480-1482)
            const bits: c_uint = 32;

            // NOTE: Only stereo is supported for XM
            music.stream = LoadAudioStream(AUDIO.system.deviceSampleRate, bits, AUDIO_DEVICE_CHANNELS);
            music.frameCount = @truncate(jar_xm_get_remaining_samples(ctxXm)); // NOTE: Always 2 channels (stereo)
            music.looping = true; // Looping enabled by default
            jar_xm_reset(ctxXm); // Make sure to start at the beginning of the song
            musicLoaded = true;
        } else {
            jar_xm_free_context(ctxXm);
        }
    } else if (SUPPORT_FILEFORMAT_MOD and IsFileExtension(fileName, ".mod")) {
        const ctxMod: ?*JarModContext = @ptrCast(RL_CALLOC(1, rl_sizeof_jar_mod_context()));
        _ = jar_mod_init(ctxMod);
        const result: c_int = @bitCast(@as(c_uint, @truncate(jar_mod_load_file(ctxMod, fileName))));

        if (result > 0) {
            music.ctxType = MUSIC_MODULE_MOD;
            music.ctxData = ctxMod;

            // NOTE: Only stereo is supported for MOD
            music.stream = LoadAudioStream(AUDIO.system.deviceSampleRate, 16, AUDIO_DEVICE_CHANNELS);
            music.frameCount = @truncate(jar_mod_max_samples(ctxMod)); // NOTE: Always 2 channels (stereo)
            music.looping = true; // Looping enabled by default
            musicLoaded = true;
        } else {
            jar_mod_unload(ctxMod);
            RL_FREE(ctxMod);
        }
    } else TraceLog(LOG_WARNING, "STREAM: [%s] File format not supported", fileName);

    if (!musicLoaded) {
        TraceLog(LOG_WARNING, "FILEIO: [%s] Music file could not be opened", fileName);
    } else {
        // Show some music stream info
        const channelsText: [*c]const u8 = if (music.stream.channels == 1) "Mono" else if (music.stream.channels == 2) "Stereo" else "Multi";
        TraceLog(LOG_INFO, "FILEIO: [%s] Music file loaded successfully", fileName);
        TraceLog(LOG_INFO, "    > Sample rate:   %i Hz", music.stream.sampleRate);
        TraceLog(LOG_INFO, "    > Sample size:   %i bits", music.stream.sampleSize);
        TraceLog(LOG_INFO, "    > Channels:      %i (%s)", music.stream.channels, channelsText);
        TraceLog(LOG_INFO, "    > Total frames:  %i", music.frameCount);
    }

    return music;
}

// Load music stream from memory buffer, fileType refers to extension: i.e. ".wav"
// WARNING: File extension must be provided in lower-case
export fn LoadMusicStreamFromMemory(fileType: [*c]const u8, data: [*c]const u8, dataSize: c_int) Music {
    var music = std.mem.zeroes(Music);
    var musicLoaded = false;

    if (SUPPORT_FILEFORMAT_WAV and ((strcmp(fileType, ".wav") == 0) or (strcmp(fileType, ".WAV") == 0))) {
        const ctxWav: ?*DrWav = @ptrCast(RL_CALLOC(1, rl_sizeof_drwav()));

        const success = drwav_init_memory(ctxWav, data, cSizeT(dataSize), null) != 0;

        if (success) {
            music.ctxType = MUSIC_AUDIO_WAV;
            music.ctxData = ctxWav;

            var totalPCMFrameCount: u64 = 0;
            var sampleRate: c_uint = 0;
            var channels: c_uint = 0;
            var bitsPerSample: c_uint = 0;
            rl_drwav_get_info(ctxWav, &totalPCMFrameCount, &sampleRate, &channels, &bitsPerSample);

            var sampleSize: c_int = @bitCast(bitsPerSample);
            if (bitsPerSample == 24) sampleSize = 16; // Forcing conversion to s16 on UpdateMusicStream()

            music.stream = LoadAudioStream(sampleRate, @bitCast(sampleSize), channels);
            music.frameCount = @truncate(totalPCMFrameCount);
            music.looping = true; // Looping enabled by default
            musicLoaded = true;
        } else {
            _ = drwav_uninit(ctxWav);
            RL_FREE(ctxWav);
        }
    } else if (SUPPORT_FILEFORMAT_OGG and ((strcmp(fileType, ".ogg") == 0) or (strcmp(fileType, ".OGG") == 0))) {
        // Open ogg audio stream
        const ctxOgg = stb_vorbis_open_memory(data, dataSize, null, null);

        if (ctxOgg != null) {
            music.ctxType = MUSIC_AUDIO_OGG;
            music.ctxData = ctxOgg;

            var sampleRate: c_uint = 0;
            var channels: c_int = 0;
            rl_stb_vorbis_get_info(ctxOgg, &sampleRate, &channels); // Get Ogg file info

            // OGG bit rate defaults to 16 bit, it's enough for compressed format
            music.stream = LoadAudioStream(sampleRate, 16, @bitCast(channels));

            // WARNING: It seems this function returns length in frames, not samples, so multiply by channels
            music.frameCount = stb_vorbis_stream_length_in_samples(ctxOgg);
            music.looping = true; // Looping enabled by default
            musicLoaded = true;
        } else {
            stb_vorbis_close(ctxOgg);
        }
    } else if (SUPPORT_FILEFORMAT_MP3 and ((strcmp(fileType, ".mp3") == 0) or (strcmp(fileType, ".MP3") == 0))) {
        const ctxMp3: ?*DrMp3 = @ptrCast(RL_CALLOC(1, rl_sizeof_drmp3()));
        const success: c_int = @bitCast(drmp3_init_memory(ctxMp3, data, cSizeT(dataSize), null));

        if (success != 0) {
            music.ctxType = MUSIC_AUDIO_MP3;
            music.ctxData = ctxMp3;

            var channels: c_uint = 0;
            var sampleRate: c_uint = 0;
            rl_drmp3_get_info(ctxMp3, &channels, &sampleRate);

            music.stream = LoadAudioStream(sampleRate, 32, channels);
            music.frameCount = @truncate(drmp3_get_pcm_frame_count(ctxMp3));
            music.looping = true; // Looping enabled by default
            musicLoaded = true;
        } else {
            drmp3_uninit(ctxMp3);
            RL_FREE(ctxMp3);
        }
    } else if (SUPPORT_FILEFORMAT_QOA and ((strcmp(fileType, ".qoa") == 0) or (strcmp(fileType, ".QOA") == 0))) {
        var ctxQoa: ?*QoaPlayDesc = null;
        if ((data != null) and (dataSize > 0)) {
            ctxQoa = qoaplay_open_memory(data, dataSize);
        }

        if (ctxQoa != null) {
            music.ctxType = MUSIC_AUDIO_QOA;
            music.ctxData = ctxQoa;

            var channels: c_uint = 0;
            var samplerate: c_uint = 0;
            var samples: c_uint = 0;
            rl_qoaplay_get_info(ctxQoa, &channels, &samplerate, &samples);

            // NOTE: Loading samples are 32bit float normalized data, so,
            // configure the output audio stream to also use float 32bit
            music.stream = LoadAudioStream(samplerate, 32, channels);
            music.frameCount = samples;
            music.looping = true; // Looping enabled by default
            musicLoaded = true;
        }
        // else: no uninit required
    } else if (SUPPORT_FILEFORMAT_XM and ((strcmp(fileType, ".xm") == 0) or (strcmp(fileType, ".XM") == 0))) {
        var ctxXm: ?*JarXmContext = null;
        const result = jar_xm_create_context_safe(&ctxXm, @ptrCast(data), cSizeT(dataSize), AUDIO.system.deviceSampleRate);
        if (result == 0) { // XM context created successfully
            music.ctxType = MUSIC_MODULE_XM;
            music.ctxData = ctxXm;
            jar_xm_set_max_loop_count(ctxXm, 0); // Set infinite number of loops

            // AUDIO_DEVICE_FORMAT is ma_format_f32 in this build -> 32 bit (raudio.c:1679-1681)
            const bits: c_uint = 32;

            // NOTE: Only stereo is supported for XM
            music.stream = LoadAudioStream(AUDIO.system.deviceSampleRate, bits, 2);
            music.frameCount = @truncate(jar_xm_get_remaining_samples(ctxXm)); // NOTE: Always 2 channels (stereo)
            music.looping = true; // Looping enabled by default
            jar_xm_reset(ctxXm); // Make sure to start at the beginning of the song

            musicLoaded = true;
        } else {
            jar_xm_free_context(ctxXm);
        }
    } else if (SUPPORT_FILEFORMAT_MOD and ((strcmp(fileType, ".mod") == 0) or (strcmp(fileType, ".MOD") == 0))) {
        // The whole load-from-memory sequence (context alloc, data copy, modfile
        // wiring, jar_mod_load, failure cleanup) is replicated verbatim in the shim:
        // jar_mod_load is static upstream and the sequence writes context fields
        if (rl_jar_mod_load_memory(data, dataSize)) |ctxMod| {
            music.ctxType = MUSIC_MODULE_MOD;
            music.ctxData = ctxMod;

            // NOTE: Only stereo is supported for MOD
            music.stream = LoadAudioStream(AUDIO.system.deviceSampleRate, 16, 2);
            music.frameCount = @truncate(jar_mod_max_samples(ctxMod)); // NOTE: Always 2 channels (stereo)
            music.looping = true; // Looping enabled by default
            musicLoaded = true;
        }
    } else TraceLog(LOG_WARNING, "STREAM: Data format not supported");

    if (!musicLoaded) {
        TraceLog(LOG_WARNING, "FILEIO: Music data could not be loaded");
    } else {
        // Show some music stream info
        const channelsText: [*c]const u8 = if (music.stream.channels == 1) "Mono" else if (music.stream.channels == 2) "Stereo" else "Multi";
        TraceLog(LOG_INFO, "FILEIO: Music data loaded successfully");
        TraceLog(LOG_INFO, "    > Sample rate:   %i Hz", music.stream.sampleRate);
        TraceLog(LOG_INFO, "    > Sample size:   %i bits", music.stream.sampleSize);
        TraceLog(LOG_INFO, "    > Channels:      %i (%s)", music.stream.channels, channelsText);
        TraceLog(LOG_INFO, "    > Total frames:  %i", music.frameCount);
    }

    return music;
}

// Check if music stream is valid (context and buffers initialized)
export fn IsMusicValid(music: Music) bool {
    return ((music.ctxData != null) and // Validate context loaded
        (music.frameCount > 0) and // Validate audio frame count
        (music.stream.sampleRate > 0) and // Validate sample rate is supported
        (music.stream.sampleSize > 0) and // Validate sample size is supported
        (music.stream.channels > 0)); // Validate number of channels supported
}

// Unload music stream
export fn UnloadMusicStream(music: Music) void {
    if (IsMusicStreamPlaying(music)) StopMusicStream(music);

    UnloadAudioStream(music.stream);

    if (music.ctxData != null) {
        switch (music.ctxType) {
            MUSIC_AUDIO_WAV => {
                _ = drwav_uninit(@ptrCast(music.ctxData));
                RL_FREE(music.ctxData);
            },
            MUSIC_AUDIO_OGG => stb_vorbis_close(@ptrCast(music.ctxData)),
            MUSIC_AUDIO_MP3 => {
                drmp3_uninit(@ptrCast(music.ctxData));
                RL_FREE(music.ctxData);
            },
            MUSIC_AUDIO_QOA => qoaplay_close(@ptrCast(music.ctxData)),
            MUSIC_MODULE_XM => jar_xm_free_context(@ptrCast(music.ctxData)),
            MUSIC_MODULE_MOD => {
                jar_mod_unload(@ptrCast(music.ctxData));
                RL_FREE(music.ctxData);
            },
            else => {},
        }
    }
}

// Start music playing (open stream) from beginning
export fn PlayMusicStream(music: Music) void {
    PlayAudioStream(music.stream);
}

// Pause music playing
export fn PauseMusicStream(music: Music) void {
    PauseAudioStream(music.stream);
}

// Resume music playing
export fn ResumeMusicStream(music: Music) void {
    ResumeAudioStream(music.stream);
}

// Stop music playing (close stream)
export fn StopMusicStream(music: Music) void {
    StopAudioStream(music.stream);

    switch (music.ctxType) {
        MUSIC_AUDIO_WAV => _ = rl_drwav_seek_to_first_pcm_frame(@ptrCast(music.ctxData)),
        MUSIC_AUDIO_OGG => _ = stb_vorbis_seek_start(@ptrCast(music.ctxData)),
        MUSIC_AUDIO_MP3 => _ = rl_drmp3_seek_to_start_of_stream(@ptrCast(music.ctxData)),
        MUSIC_AUDIO_QOA => qoaplay_rewind(@ptrCast(music.ctxData)),
        MUSIC_MODULE_XM => jar_xm_reset(@ptrCast(music.ctxData)),
        MUSIC_MODULE_MOD => jar_mod_seek_start(@ptrCast(music.ctxData)),
        else => {},
    }
}

// Seek music to a certain position (in seconds)
export fn SeekMusicStream(music: Music, position: f32) void {
    // Seeking is not supported in module formats
    if ((music.ctxType == MUSIC_MODULE_XM) or (music.ctxType == MUSIC_MODULE_MOD)) return;

    var positionInFrames: c_uint = @intFromFloat(position * @as(f32, @floatFromInt(music.stream.sampleRate)));

    switch (music.ctxType) {
        MUSIC_AUDIO_WAV => _ = drwav_seek_to_pcm_frame(@ptrCast(music.ctxData), positionInFrames),
        MUSIC_AUDIO_OGG => _ = stb_vorbis_seek_frame(@ptrCast(music.ctxData), positionInFrames),
        MUSIC_AUDIO_MP3 => _ = drmp3_seek_to_pcm_frame(@ptrCast(music.ctxData), positionInFrames),
        MUSIC_AUDIO_QOA => {
            const qoaFrame: c_int = @bitCast(positionInFrames / QOA_FRAME_LEN);
            qoaplay_seek_frame(@ptrCast(music.ctxData), qoaFrame); // Seeks to QOA frame, not PCM frame

            // Compute QOA frame number and update positionInFrames
            positionInFrames = rl_qoaplay_sample_position(@ptrCast(music.ctxData));
        },
        else => {},
    }

    lockAudio();
    music.stream.buffer.?.framesProcessed = positionInFrames;
    music.stream.buffer.?.isSubBufferProcessed[0] = true;
    music.stream.buffer.?.isSubBufferProcessed[1] = true;
    unlockAudio();
}

// Update (re-fill) music buffers if data already processed
export fn UpdateMusicStream(music: Music) void {
    const buffer = music.stream.buffer orelse return;
    if (!buffer.playing) return;

    lockAudio();

    const subBufferSizeInFrames: c_uint = buffer.sizeInFrames / 2;

    // On first call of this function, lazily pre-allocate a temp buffer to read audio files/memory data in
    const frameSize: c_int = @bitCast(music.stream.channels *% music.stream.sampleSize / 8);
    const pcmSize: c_uint = subBufferSizeInFrames *% @as(c_uint, @bitCast(frameSize));

    if (AUDIO.system.pcmBufferSize < pcmSize) {
        RL_FREE(AUDIO.system.pcmBuffer);
        AUDIO.system.pcmBuffer = RL_CALLOC(1, pcmSize);
        AUDIO.system.pcmBufferSize = pcmSize;
    }

    // Check both sub-buffers to check if they require refilling
    var i: usize = 0;
    while (i < 2) : (i += 1) {
        const framesLeft = music.frameCount -% buffer.framesProcessed; // Frames left to be processed
        var framesToStream: c_uint = 0; // Total frames to be streamed

        if ((framesLeft >= subBufferSizeInFrames) or music.looping) framesToStream = subBufferSizeInFrames else framesToStream = framesLeft;

        if (framesToStream == 0) {
            // Check if both buffers have been processed
            if (buffer.isSubBufferProcessed[0] and buffer.isSubBufferProcessed[1]) {
                unlockAudio();
                StopMusicStream(music);
                return;
            }

            unlockAudio();
            return;
        }

        if (!buffer.isSubBufferProcessed[i]) continue; // No refilling required, move to next sub-buffer

        var frameCountStillNeeded: c_int = @bitCast(framesToStream);
        var frameCountReadTotal: c_int = 0;

        const pcm: [*]u8 = @ptrCast(AUDIO.system.pcmBuffer.?);

        switch (music.ctxType) {
            MUSIC_AUDIO_WAV => {
                if (music.stream.sampleSize == 16) {
                    while (true) {
                        const dst: [*c]i16 = @ptrCast(@alignCast(pcm + @as(usize, @intCast(frameCountReadTotal * frameSize))));
                        const frameCountRead: c_int = @bitCast(@as(c_uint, @truncate(drwav_read_pcm_frames_s16(@ptrCast(music.ctxData), cU64(frameCountStillNeeded), dst))));
                        frameCountReadTotal += frameCountRead;
                        frameCountStillNeeded -= frameCountRead;
                        if (frameCountStillNeeded == 0) break else _ = rl_drwav_seek_to_first_pcm_frame(@ptrCast(music.ctxData));
                    }
                } else if (music.stream.sampleSize == 32) {
                    while (true) {
                        const dst: [*c]f32 = @ptrCast(@alignCast(pcm + @as(usize, @intCast(frameCountReadTotal * frameSize))));
                        const frameCountRead: c_int = @bitCast(@as(c_uint, @truncate(drwav_read_pcm_frames_f32(@ptrCast(music.ctxData), cU64(frameCountStillNeeded), dst))));
                        frameCountReadTotal += frameCountRead;
                        frameCountStillNeeded -= frameCountRead;
                        if (frameCountStillNeeded == 0) break else _ = rl_drwav_seek_to_first_pcm_frame(@ptrCast(music.ctxData));
                    }
                }
            },
            MUSIC_AUDIO_OGG => {
                while (true) {
                    const dst: [*c]i16 = @ptrCast(@alignCast(pcm + @as(usize, @intCast(frameCountReadTotal * frameSize))));
                    const numShorts: c_int = @bitCast(@as(c_uint, @bitCast(frameCountStillNeeded)) *% music.stream.channels);
                    const frameCountRead = stb_vorbis_get_samples_short_interleaved(@ptrCast(music.ctxData), @bitCast(music.stream.channels), dst, numShorts);
                    frameCountReadTotal += frameCountRead;
                    frameCountStillNeeded -= frameCountRead;
                    if (frameCountStillNeeded == 0) break else _ = stb_vorbis_seek_start(@ptrCast(music.ctxData));
                }
            },
            MUSIC_AUDIO_MP3 => {
                while (true) {
                    const dst: [*c]f32 = @ptrCast(@alignCast(pcm + @as(usize, @intCast(frameCountReadTotal * frameSize))));
                    const frameCountRead: c_int = @bitCast(@as(c_uint, @truncate(drmp3_read_pcm_frames_f32(@ptrCast(music.ctxData), cU64(frameCountStillNeeded), dst))));
                    frameCountReadTotal += frameCountRead;
                    frameCountStillNeeded -= frameCountRead;
                    if (frameCountStillNeeded == 0) break else _ = rl_drmp3_seek_to_start_of_stream(@ptrCast(music.ctxData));
                }
            },
            MUSIC_AUDIO_QOA => {
                const frameCountRead = qoaplay_decode(@ptrCast(music.ctxData), @ptrCast(@alignCast(pcm)), @bitCast(framesToStream));
                frameCountReadTotal = @bitCast(@as(c_uint, @bitCast(frameCountReadTotal)) +% frameCountRead);
            },
            MUSIC_MODULE_XM => {
                // NOTE: Internally considering 2 channels generation, so sampleCount/2
                // AUDIO_DEVICE_FORMAT is ma_format_f32 in this build (raudio.c:2028)
                jar_xm_generate_samples(@ptrCast(music.ctxData), @ptrCast(@alignCast(pcm)), @as(usize, framesToStream));
            },
            MUSIC_MODULE_MOD => {
                // NOTE: 3rd parameter (nbsample) specify the number of stereo 16bits samples desired
                jar_mod_fillbuffer(@ptrCast(music.ctxData), @ptrCast(@alignCast(pcm)), @as(c_ulong, framesToStream), null);
            },
            else => {},
        }

        updateAudioStreamInLockedState(music.stream, AUDIO.system.pcmBuffer, @bitCast(framesToStream));
    }

    unlockAudio();
}

// Check if any music is playing
export fn IsMusicStreamPlaying(music: Music) bool {
    return IsAudioStreamPlaying(music.stream);
}

// Set volume for music
export fn SetMusicVolume(music: Music, volume: f32) void {
    SetAudioStreamVolume(music.stream, volume);
}

// Set pitch for music
export fn SetMusicPitch(music: Music, pitch: f32) void {
    SetAudioBufferPitch(music.stream.buffer, pitch);
}

// Set pan for music
export fn SetMusicPan(music: Music, pan: f32) void {
    SetAudioBufferPan(music.stream.buffer, pan);
}

// Get music time length (in seconds)
export fn GetMusicTimeLength(music: Music) f32 {
    return @as(f32, @floatFromInt(music.frameCount)) / @as(f32, @floatFromInt(music.stream.sampleRate));
}

// Get current music time played (in seconds)
export fn GetMusicTimePlayed(music: Music) f32 {
    var secondsPlayed: f32 = 0.0;
    if (music.stream.buffer) |buffer| {
        if (SUPPORT_FILEFORMAT_XM and (music.ctxType == MUSIC_MODULE_XM)) {
            var framesPlayed: u64 = 0;

            jar_xm_get_position(@ptrCast(music.ctxData), null, null, null, &framesPlayed);
            secondsPlayed = @as(f32, @floatFromInt(framesPlayed)) / @as(f32, @floatFromInt(music.stream.sampleRate));
        } else {
            lockAudio();
            const framesProcessed: c_int = @bitCast(buffer.framesProcessed);
            const subBufferSize: c_int = @divTrunc(@as(c_int, @bitCast(buffer.sizeInFrames)), 2);
            const framesInFirstBuffer: c_int = if (buffer.isSubBufferProcessed[0]) 0 else subBufferSize;
            const framesInSecondBuffer: c_int = if (buffer.isSubBufferProcessed[1]) 0 else subBufferSize;
            var framesInBuffers: c_int = framesInFirstBuffer + framesInSecondBuffer;
            if ((@as(c_uint, @bitCast(framesInBuffers)) > music.frameCount) and !music.looping) framesInBuffers = @bitCast(music.frameCount);
            const framesSentToMix: c_int = @bitCast(buffer.frameCursorPos % @as(c_uint, @bitCast(subBufferSize)));
            var framesPlayed: c_int = @rem(framesProcessed - framesInBuffers + framesSentToMix, @as(c_int, @bitCast(music.frameCount)));
            if (framesPlayed < 0) framesPlayed = @bitCast(@as(c_uint, @bitCast(framesPlayed)) +% music.frameCount);
            secondsPlayed = @as(f32, @floatFromInt(framesPlayed)) / @as(f32, @floatFromInt(music.stream.sampleRate));
            unlockAudio();
        }
    }

    return secondsPlayed;
}

// Load audio stream (to stream audio pcm data)
export fn LoadAudioStream(sampleRate: c_uint, sampleSize: c_uint, channels: c_uint) AudioStream {
    var stream = std.mem.zeroes(AudioStream);

    stream.sampleRate = sampleRate;
    stream.sampleSize = sampleSize;
    stream.channels = channels;

    const formatIn: c_int = if (stream.sampleSize == 8) ma_format_u8 else if (stream.sampleSize == 16) ma_format_s16 else ma_format_f32;

    // The size of a streaming buffer must be at least double the size of a period
    const periodSize: c_uint = AUDIO.system.playbackInternalPeriodSizeInFrames;

    // If the buffer is not set, compute one that would give us a buffer good enough for a decent frame rate at the device bit size/rate
    var deviceBitsPerSample: c_int = AUDIO.system.playbackFormat;
    if (deviceBitsPerSample > 4) deviceBitsPerSample = 4;
    deviceBitsPerSample = @bitCast(@as(c_uint, @bitCast(deviceBitsPerSample)) *% AUDIO.system.playbackChannels);

    var subBufferSize: c_uint = if (AUDIO.buffer.defaultSize == 0)
        AUDIO.system.deviceSampleRate / 30 *% @as(c_uint, @bitCast(deviceBitsPerSample))
    else
        @bitCast(AUDIO.buffer.defaultSize);

    if (subBufferSize < periodSize) subBufferSize = periodSize;

    // Create a double audio buffer of defined size
    stream.buffer = LoadAudioBuffer(formatIn, stream.channels, stream.sampleRate, subBufferSize *% 2, AUDIO_BUFFER_USAGE_STREAM);

    if (stream.buffer) |buffer| {
        buffer.looping = true; // Always loop for streaming buffers
        const channelsText: [*c]const u8 = if (stream.channels == 1) "Mono" else "Stereo";
        TraceLog(LOG_INFO, "STREAM: Initialized successfully (%i Hz, %i bit, %s)", stream.sampleRate, stream.sampleSize, channelsText);
    } else TraceLog(LOG_WARNING, "STREAM: Failed to load audio buffer, stream could not be created");

    return stream;
}

// Check if an audio stream is valid (buffers initialized)
export fn IsAudioStreamValid(stream: AudioStream) bool {
    return ((stream.buffer != null) and // Validate stream buffer
        (stream.sampleRate > 0) and // Validate sample rate is supported
        (stream.sampleSize > 0) and // Validate sample size is supported
        (stream.channels > 0)); // Validate number of channels supported
}

// Unload audio stream and free memory
export fn UnloadAudioStream(stream: AudioStream) void {
    UnloadAudioBuffer(stream.buffer);

    TraceLog(LOG_INFO, "STREAM: Unloaded audio stream data from RAM");
}

// Update audio stream buffers with data
// NOTE 1: Only updates one buffer of the stream source: dequeue -> update -> queue
// NOTE 2: To dequeue a buffer it needs to be processed: IsAudioStreamProcessed()
export fn UpdateAudioStream(stream: AudioStream, data: ?*const anyopaque, frameCount: c_int) void {
    lockAudio();
    updateAudioStreamInLockedState(stream, data, frameCount);
    unlockAudio();
}

// Check if any audio stream buffers requires refill
export fn IsAudioStreamProcessed(stream: AudioStream) bool {
    var result = false;

    if (stream.buffer) |buffer| {
        lockAudio();
        result = buffer.isSubBufferProcessed[0] or buffer.isSubBufferProcessed[1];
        unlockAudio();
    }

    return result;
}

// Play audio stream
export fn PlayAudioStream(stream: AudioStream) void {
    PlayAudioBuffer(stream.buffer);
}

// Pause audio stream
export fn PauseAudioStream(stream: AudioStream) void {
    PauseAudioBuffer(stream.buffer);
}

// Resume audio stream playing
export fn ResumeAudioStream(stream: AudioStream) void {
    ResumeAudioBuffer(stream.buffer);
}

// Check if audio stream is playing
export fn IsAudioStreamPlaying(stream: AudioStream) bool {
    return IsAudioBufferPlaying(stream.buffer);
}

// Stop audio stream
export fn StopAudioStream(stream: AudioStream) void {
    StopAudioBuffer(stream.buffer);
}

// Set volume for audio stream (1.0 is max level)
export fn SetAudioStreamVolume(stream: AudioStream, volume: f32) void {
    SetAudioBufferVolume(stream.buffer, volume);
}

// Set pitch for audio stream (1.0 is base level)
export fn SetAudioStreamPitch(stream: AudioStream, pitch: f32) void {
    SetAudioBufferPitch(stream.buffer, pitch);
}

// Set pan for audio stream
export fn SetAudioStreamPan(stream: AudioStream, pan: f32) void {
    SetAudioBufferPan(stream.buffer, pan);
}

// Default size for new audio streams
export fn SetAudioStreamBufferSizeDefault(size: c_int) void {
    AUDIO.buffer.defaultSize = size;
}

// Audio thread callback to request new data
export fn SetAudioStreamCallback(stream: AudioStream, callback: AudioCallback) void {
    if (stream.buffer) |buffer| {
        lockAudio();
        buffer.callback = callback;
        unlockAudio();
    }
}

// Add processor to audio stream. Contrary to buffers, the order of processors is important
// The new processor must be added at the end, iterating through the list to find it
export fn AttachAudioStreamProcessor(stream: AudioStream, process: AudioCallback) void {
    lockAudio();

    const processor: *AudioProcessor = @ptrCast(@alignCast(RL_CALLOC(1, @sizeOf(AudioProcessor)).?));
    processor.* = .{ .process = process, .next = null, .prev = null };

    var last = stream.buffer.?.processor;

    while (last != null and last.?.next != null) {
        last = last.?.next;
    }
    if (last) |l| {
        processor.prev = l;
        l.next = processor;
    } else stream.buffer.?.processor = processor;

    unlockAudio();
}

// Remove processor from audio stream
export fn DetachAudioStreamProcessor(stream: AudioStream, process: AudioCallback) void {
    lockAudio();

    var processor = stream.buffer.?.processor;

    while (processor) |p| {
        const next = p.next;
        const prev = p.prev;

        if (p.process == process) {
            if (stream.buffer.?.processor == p) stream.buffer.?.processor = next;
            if (prev) |pv| pv.next = next;
            if (next) |nx| nx.prev = prev;

            RL_FREE(p);
        }

        processor = next;
    }

    unlockAudio();
}

// Add processor to audio pipeline. Order of processors is important
// Works the same way as {Attach,Detach}AudioStreamProcessor() functions, except
// these two work on the already mixed output before sending it to the sound hardware
export fn AttachAudioMixedProcessor(process: AudioCallback) void {
    lockAudio();

    const processor: *AudioProcessor = @ptrCast(@alignCast(RL_CALLOC(1, @sizeOf(AudioProcessor)).?));
    processor.* = .{ .process = process, .next = null, .prev = null };

    var last = AUDIO.mixedProcessor;

    while (last != null and last.?.next != null) {
        last = last.?.next;
    }
    if (last) |l| {
        processor.prev = l;
        l.next = processor;
    } else AUDIO.mixedProcessor = processor;

    unlockAudio();
}

// Remove processor from audio pipeline
export fn DetachAudioMixedProcessor(process: AudioCallback) void {
    lockAudio();

    var processor = AUDIO.mixedProcessor;

    while (processor) |p| {
        const next = p.next;
        const prev = p.prev;

        if (p.process == process) {
            if (AUDIO.mixedProcessor == p) AUDIO.mixedProcessor = next;
            if (prev) |pv| pv.next = next;
            if (next) |nx| nx.prev = prev;

            RL_FREE(p);
        }

        processor = next;
    }

    unlockAudio();
}

//----------------------------------------------------------------------------------
// Module Internal Functions Definition
//----------------------------------------------------------------------------------

// Log callback function (built-and-discarded by the shim, matching raudio.c:469)
fn onLog(userData: ?*anyopaque, level: c_uint, message: [*c]const u8) callconv(.c) void {
    _ = userData;
    _ = level;
    TraceLog(LOG_WARNING, "miniaudio: %s", message); // All log messages from miniaudio are errors
}

// Reads audio data from an AudioBuffer object in internal format
fn readAudioBufferFramesInInternalFormat(audioBuffer: *AudioBuffer, framesOut: [*]u8, frameCount: c_uint) c_uint {
    // Don't read anything if the sound is not playing
    if (!audioBuffer.playing) return 0;

    // Using audio buffer callback
    if (audioBuffer.callback) |callback| {
        callback(framesOut, frameCount);
        audioBuffer.framesProcessed +%= frameCount;

        return frameCount;
    }

    const subBufferSizeInFrames: c_uint = if (audioBuffer.sizeInFrames > 1) audioBuffer.sizeInFrames / 2 else audioBuffer.sizeInFrames;
    var currentSubBufferIndex: c_uint = audioBuffer.frameCursorPos / subBufferSizeInFrames;

    if (currentSubBufferIndex > 1) return 0;

    // Another thread can update the processed state of buffers, so
    // take a copy here to try and avoid potential synchronization problems
    var isSubBufferProcessed = [2]bool{ audioBuffer.isSubBufferProcessed[0], audioBuffer.isSubBufferProcessed[1] };

    const frameSizeInBytes = maGetBytesPerFrame(audioBuffer.formatIn, audioBuffer.channelsIn);

    // Fill out every frame until a buffer that's marked as processed is found, then fill the remainder with 0
    var framesRead: c_uint = 0;
    while (true) {
        // Break from this loop differently depending on the buffer's usage
        //  - For static buffers, simply fill as much data as possible
        //  - For streaming buffers, only fill half of the buffer that are processed
        //    Unprocessed halves must keep their audio data in-tact
        if (audioBuffer.usage == AUDIO_BUFFER_USAGE_STATIC) {
            if (framesRead >= frameCount) break;
        } else {
            if (isSubBufferProcessed[@intCast(currentSubBufferIndex)]) break;
        }

        const totalFramesRemaining = frameCount -% framesRead;
        if (totalFramesRemaining == 0) break;

        var framesRemainingInOutputBuffer: c_uint = undefined;
        if (audioBuffer.usage == AUDIO_BUFFER_USAGE_STATIC) {
            framesRemainingInOutputBuffer = audioBuffer.sizeInFrames -% audioBuffer.frameCursorPos;
        } else {
            const firstFrameIndexOfThisSubBuffer = subBufferSizeInFrames *% currentSubBufferIndex;
            framesRemainingInOutputBuffer = subBufferSizeInFrames -% (audioBuffer.frameCursorPos -% firstFrameIndexOfThisSubBuffer);
        }

        var framesToRead = totalFramesRemaining;
        if (framesToRead > framesRemainingInOutputBuffer) framesToRead = framesRemainingInOutputBuffer;

        _ = memcpy(framesOut + @as(usize, framesRead *% frameSizeInBytes), audioBuffer.data.? + @as(usize, audioBuffer.frameCursorPos *% frameSizeInBytes), @as(usize, framesToRead *% frameSizeInBytes));
        audioBuffer.frameCursorPos = (audioBuffer.frameCursorPos +% framesToRead) % audioBuffer.sizeInFrames;
        framesRead +%= framesToRead;

        // If the end of the buffer is read, mark it as processed
        if (framesToRead == framesRemainingInOutputBuffer) {
            audioBuffer.isSubBufferProcessed[@intCast(currentSubBufferIndex)] = true;
            isSubBufferProcessed[@intCast(currentSubBufferIndex)] = true;

            currentSubBufferIndex = (currentSubBufferIndex + 1) % 2;

            // Break from this loop if looping not enabled
            if (!audioBuffer.looping) {
                stopAudioBufferInLockedState(audioBuffer);
                break;
            }
        }
    }

    // Zero-fill excess
    const totalFramesRemaining = frameCount -% framesRead;
    if (totalFramesRemaining > 0) {
        _ = memset(framesOut + @as(usize, framesRead *% frameSizeInBytes), 0, @as(usize, totalFramesRemaining *% frameSizeInBytes));

        // For static buffers, fill the remaining frames with silence for safety, but don't report those
        // frames as "read"; the caller uses the return value to know whether a
        // non-looping sound has finished playback
        if (audioBuffer.usage != AUDIO_BUFFER_USAGE_STATIC) framesRead +%= totalFramesRemaining;
    }

    return framesRead;
}

// Reads audio data from an AudioBuffer object in device format, returned data will be in a format appropriate for mixing
fn readAudioBufferFramesInMixingFormat(audioBuffer: *AudioBuffer, framesOut: [*]f32, frameCount: c_uint) c_uint {
    // NOTE: Continuously converting data from the AudioBuffer's internal format to the mixing format,
    // which should be defined by the output format of the data converter,
    // until frameCount frames have been output
    const bpf = maGetBytesPerFrame(audioBuffer.formatIn, audioBuffer.channelsIn);
    var inputBuffer: [4096]u8 = @splat(0);
    const inputBufferFrameCap: c_uint = @intCast(inputBuffer.len / bpf);

    var totalOutputFramesProcessed: c_uint = 0;
    while (totalOutputFramesProcessed < frameCount) {
        const runningFramesOut = framesOut + @as(usize, totalOutputFramesProcessed *% audioBuffer.channelsOut);
        const outputFramesToProcessThisIteration: u64 = frameCount - totalOutputFramesProcessed;

        // Process any residual input frames from the previous read first
        if (audioBuffer.converterResidualCount > 0) {
            var inputFramesProcessedThisIteration: u64 = audioBuffer.converterResidualCount;
            var outputFramesProcessedThisIteration: u64 = outputFramesToProcessThisIteration;
            _ = ma_data_converter_process_pcm_frames(audioBuffer.converter, audioBuffer.converterResidual, &inputFramesProcessedThisIteration, runningFramesOut, &outputFramesProcessedThisIteration);

            // Make sure the data in the cache is consumed
            _ = memmove(audioBuffer.converterResidual, audioBuffer.converterResidual + @as(usize, @intCast(inputFramesProcessedThisIteration *% bpf)), @as(usize, @intCast((@as(u64, AUDIO_BUFFER_RESIDUAL_CAPACITY) -% inputFramesProcessedThisIteration) *% bpf)));
            audioBuffer.converterResidualCount -%= @truncate(inputFramesProcessedThisIteration); // Safe cast

            totalOutputFramesProcessed +%= @truncate(outputFramesProcessedThisIteration); // Safe cast
        } else {
            // No residual frames: fresh data is pulled from the AudioBuffer using a
            // best-guess input frame count. An exact or underestimated guess is handled
            // naturally by the loop; an overestimated guess stores the overflow in the
            // residual cache for the next read.
            const rateIn: f32 = @floatFromInt(rl_ma_data_converter_resampler_rate_in(audioBuffer.converter));
            const rateOut: f32 = @floatFromInt(rl_ma_data_converter_resampler_rate_out(audioBuffer.converter));
            var estimatedInputFrameCount: c_uint = @intFromFloat((rateIn / rateOut) * @as(f32, @floatFromInt(outputFramesToProcessThisIteration)));
            if (estimatedInputFrameCount == 0) estimatedInputFrameCount = 1; // Make sure at least one input frame is read
            if (estimatedInputFrameCount > inputBufferFrameCap) estimatedInputFrameCount = inputBufferFrameCap;

            const inputFramesInInternalFormatCount = readAudioBufferFramesInInternalFormat(audioBuffer, &inputBuffer, estimatedInputFrameCount);

            var inputFramesProcessedThisIteration: u64 = inputFramesInInternalFormatCount;
            var outputFramesProcessedThisIteration: u64 = outputFramesToProcessThisIteration;
            _ = ma_data_converter_process_pcm_frames(audioBuffer.converter, &inputBuffer, &inputFramesProcessedThisIteration, runningFramesOut, &outputFramesProcessedThisIteration);

            totalOutputFramesProcessed +%= @truncate(outputFramesProcessedThisIteration);

            if (inputFramesInInternalFormatCount > inputFramesProcessedThisIteration) {
                // The estimated input frame count was overestimated:
                // the residual needs to be stored for later use
                var residualFrameCount: u64 = inputFramesInInternalFormatCount - inputFramesProcessedThisIteration;

                // A safety check to make sure the capacity of the residual cache is not exceeded
                if (residualFrameCount > AUDIO_BUFFER_RESIDUAL_CAPACITY) {
                    residualFrameCount = AUDIO_BUFFER_RESIDUAL_CAPACITY;
                }

                _ = memcpy(audioBuffer.converterResidual, @as([*]const u8, &inputBuffer) + @as(usize, @intCast(inputFramesProcessedThisIteration *% bpf)), @as(usize, @intCast(residualFrameCount *% bpf)));
                audioBuffer.converterResidualCount = @truncate(residualFrameCount);
            }

            if (inputFramesInInternalFormatCount < estimatedInputFrameCount) break; // Reached the end of the sound
        }
    }

    return totalOutputFramesProcessed;
}

// Sending audio data to device callback function
// This function will be called when miniaudio needs more data
// NOTE: All the mixing takes place here
fn onSendAudioDataToDevice(device: ?*anyopaque, framesOutOpaque: ?*anyopaque, framesInput: ?*const anyopaque, frameCount: c_uint) callconv(.c) void {
    _ = device;
    _ = framesInput;

    const pFramesOut: [*]u8 = @ptrCast(framesOutOpaque.?);

    // Mixing is basically an accumulation, need to initialize the output buffer to 0
    _ = memset(pFramesOut, 0, @as(usize, frameCount *% AUDIO.system.playbackChannels *% ma_get_bytes_per_sample(AUDIO.system.playbackFormat)));

    // Using a mutex here for thread-safety which makes things not real-time;
    // this is unlikely to be necessary for this project, but it can be reconsidered
    lockAudio();
    {
        var maybeBuffer = AUDIO.buffer.first;
        while (maybeBuffer) |audioBuffer| : (maybeBuffer = audioBuffer.next) {
            // Ignore stopped or paused sounds
            if (!audioBuffer.playing or audioBuffer.paused) continue;

            var framesRead: c_uint = 0;

            while (true) {
                if (framesRead >= frameCount) break;

                // Read as much data as possible from the stream
                var framesToRead = frameCount -% framesRead;

                while (framesToRead > 0) {
                    var tempBuffer: [1024]f32 = @splat(0); // Frames for stereo

                    var framesToReadRightNow = framesToRead;
                    if (framesToReadRightNow > tempBuffer.len / AUDIO_DEVICE_CHANNELS) {
                        framesToReadRightNow = tempBuffer.len / AUDIO_DEVICE_CHANNELS;
                    }

                    const framesJustRead = readAudioBufferFramesInMixingFormat(audioBuffer, &tempBuffer, framesToReadRightNow);
                    if (framesJustRead > 0) {
                        const framesOut = @as([*]f32, @ptrCast(@alignCast(pFramesOut))) + @as(usize, framesRead *% AUDIO.system.playbackChannels);
                        const framesIn: [*]f32 = &tempBuffer;

                        // Apply processors chain if defined
                        var processor = audioBuffer.processor;
                        while (processor) |p| : (processor = p.next) {
                            p.process.?(framesIn, framesJustRead);
                        }

                        mixAudioFrames(framesOut, framesIn, framesJustRead, audioBuffer);

                        framesToRead -%= framesJustRead;
                        framesRead +%= framesJustRead;
                    }

                    if (!audioBuffer.playing) {
                        framesRead = frameCount;
                        break;
                    }

                    // If all the frames requested can't be read, break
                    if (framesJustRead < framesToReadRightNow) {
                        if (!audioBuffer.looping) {
                            stopAudioBufferInLockedState(audioBuffer);
                            break;
                        } else {
                            // Should never get here, but for safety,
                            // move the cursor position back to the start and continue the loop
                            audioBuffer.frameCursorPos = 0;
                            continue;
                        }
                    }
                }

                // If for some reason is not possible to read every frame, the loop needs to be broken
                // Not doing this could theoretically end up into an infinite loop
                if (framesToRead > 0) break;
            }
        }
    }

    var processor = AUDIO.mixedProcessor;
    while (processor) |p| : (processor = p.next) {
        p.process.?(framesOutOpaque, frameCount);
    }

    unlockAudio();
}

// Main mixing function, pretty simple in this project, only an accumulation
// NOTE: framesOut is both an input and an output, it is initially filled with zeros outside of this function
fn mixAudioFrames(framesOut: [*]f32, framesIn: [*]const f32, frameCount: c_uint, buffer: *AudioBuffer) void {
    const localVolume = buffer.volume;
    const channels = AUDIO.system.playbackChannels;

    if (channels == 2) { // Consider panning
        const right = (buffer.pan + 1.0) / 2.0; // Normalize: [-1..1] -> [0..1]
        const left = 1.0 - right;

        // Fast sine approximation in [0..1] for pan law: y = 0.5f*x*(3 - x*x);
        const levels = [2]f32{ localVolume * 0.5 * left * (3.0 - left * left), localVolume * 0.5 * right * (3.0 - right * right) };

        var frameOut = framesOut;
        var frameIn = framesIn;

        var frame: c_uint = 0;
        while (frame < frameCount) : (frame += 1) {
            frameOut[0] += frameIn[0] * levels[0];
            frameOut[1] += frameIn[1] * levels[1];

            frameOut += 2;
            frameIn += 2;
        }
    } else { // Do not consider panning
        var frame: c_uint = 0;
        while (frame < frameCount) : (frame += 1) {
            var c: c_uint = 0;
            while (c < channels) : (c += 1) {
                const frameOut = framesOut + @as(usize, frame *% channels);
                const frameIn = framesIn + @as(usize, frame *% channels);

                // Output accumulates input multiplied by volume to provided output (usually 0)
                frameOut[@as(usize, c)] += frameIn[@as(usize, c)] * localVolume;
            }
        }
    }
}

// Check if an audio buffer is playing, assuming the audio system mutex has been locked
fn isAudioBufferPlayingInLockedState(buffer: ?*AudioBuffer) bool {
    var result = false;

    if (buffer) |b| result = (b.playing and !b.paused);

    return result;
}

// Stop an audio buffer, assuming the audio system mutex has been locked
fn stopAudioBufferInLockedState(buffer: ?*AudioBuffer) void {
    if (buffer) |b| {
        if (isAudioBufferPlayingInLockedState(b)) {
            b.playing = false;
            b.paused = false;
            b.frameCursorPos = 0;
            b.framesProcessed = 0;
            b.isSubBufferProcessed[0] = true;
            b.isSubBufferProcessed[1] = true;
        }
    }
}

// Update audio stream, assuming the audio system mutex has been locked
fn updateAudioStreamInLockedState(stream: AudioStream, data: ?*const anyopaque, frameCount: c_int) void {
    const buffer = stream.buffer orelse return;

    if (buffer.isSubBufferProcessed[0] or buffer.isSubBufferProcessed[1]) {
        var subBufferToUpdate: c_uint = undefined;

        if (buffer.isSubBufferProcessed[0] and buffer.isSubBufferProcessed[1]) {
            // Both buffers are available for updating:
            // update the first one and make sure the cursor is moved back to the front
            subBufferToUpdate = 0;
            buffer.frameCursorPos = 0;
        } else {
            // Update whichever sub-buffer is processed
            subBufferToUpdate = if (buffer.isSubBufferProcessed[0]) 0 else 1;
        }

        const subBufferSizeInFrames: c_uint = buffer.sizeInFrames / 2;
        const subBuffer = buffer.data.? + @as(usize, subBufferSizeInFrames *% stream.channels *% (stream.sampleSize / 8) *% subBufferToUpdate);

        buffer.framesProcessed +%= @as(c_uint, @bitCast(frameCount));

        // Does this API expect a whole buffer to be updated in one go?
        // Assuming so, but if not will need to change this logic
        if (subBufferSizeInFrames >= @as(c_uint, @bitCast(frameCount))) {
            const framesToWrite: c_uint = @bitCast(frameCount);

            const bytesToWrite = framesToWrite *% stream.channels *% (stream.sampleSize / 8);
            _ = memcpy(subBuffer, data, @as(usize, bytesToWrite));

            // Any leftover frames should be filled with zeros
            const leftoverFrameCount = subBufferSizeInFrames -% framesToWrite;

            if (leftoverFrameCount > 0) _ = memset(subBuffer + @as(usize, bytesToWrite), 0, @as(usize, leftoverFrameCount *% stream.channels *% (stream.sampleSize / 8)));

            buffer.isSubBufferProcessed[@intCast(subBufferToUpdate)] = false;
        } else TraceLog(LOG_WARNING, "STREAM: Attempting to write too many frames to buffer");
    } else TraceLog(LOG_WARNING, "STREAM: Buffer not available for updating");
}
