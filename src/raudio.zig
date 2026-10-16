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
//!
//! Memory: sample data that C callers own or release (Wave.data, the result of
//! LoadWaveSamples, decoder contexts in Music.ctxData, sound data shared by
//! aliases) lives on the C heap through `cmem`. Everything raudio allocates and
//! frees itself (audio buffers, processors, scratch decoders) uses
//! `std.heap.c_allocator`. The Wave logic that needs no C is in raudio_wave.zig.

const std = @import("std");
const cmem = @import("cmem.zig");
const wave_code = @import("raudio_wave.zig");

const c_allocator = std.heap.c_allocator;
const DoublyLinkedList = std.DoublyLinkedList;

// printf, not std.fmt, formats ExportWaveAsCode's floats: `%.4f` rounds binary
// ties to even and spells inf/nan its own way (CLAUDE.md, "std.fmt is not printf")
extern fn snprintf(noalias buf: [*]u8, size: usize, noalias format: [*:0]const u8, ...) c_int;

//----------------------------------------------------------------------------------
// Cross-module raylib C-ABI symbols (rcore, ported or not, same symbols).
// They honour the user's file I/O callbacks, so raudio calls them where C did.
//----------------------------------------------------------------------------------
extern fn TraceLog(logLevel: c_int, text: [*:0]const u8, ...) void;
extern fn LoadFileData(fileName: ?[*:0]const u8, dataSize: *c_int) ?[*]u8;
extern fn UnloadFileData(data: ?[*]u8) void;
extern fn SaveFileData(fileName: ?[*:0]const u8, data: ?*const anyopaque, dataSize: c_int) bool;
extern fn SaveFileText(fileName: ?[*:0]const u8, text: [*:0]const u8) bool;
extern fn IsFileExtension(fileName: ?[*:0]const u8, ext: [*:0]const u8) bool;
extern fn GetFileExtension(fileName: ?[*:0]const u8) ?[*:0]const u8;
extern fn GetFileNameWithoutExt(filePath: ?[*:0]const u8) ?[*:0]const u8;

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

    const empty = std.mem.zeroes(Wave);

    fn info(wave: Wave) wave_code.Info {
        return .{
            .frameCount = wave.frameCount,
            .sampleRate = wave.sampleRate,
            .sampleSize = wave.sampleSize,
            .channels = wave.channels,
        };
    }
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

/// The audio file formats raudio decodes. The values are raudio.c's
/// MusicContextType (raudio.c:326-335), which Music.ctxType stores; 0 is
/// MUSIC_AUDIO_NONE.
const AudioFormat = enum(c_int) {
    wav = 1,
    ogg = 2,
    flac = 3,
    mp3 = 4,
    qoa = 5,
    xm = 6,
    mod = 7,
    _,

    fn enabled(format: AudioFormat) bool {
        return switch (format) {
            .wav => SUPPORT_FILEFORMAT_WAV,
            .ogg => SUPPORT_FILEFORMAT_OGG,
            .flac => SUPPORT_FILEFORMAT_FLAC,
            .mp3 => SUPPORT_FILEFORMAT_MP3,
            .qoa => SUPPORT_FILEFORMAT_QOA,
            .xm => SUPPORT_FILEFORMAT_XM,
            .mod => SUPPORT_FILEFORMAT_MOD,
            _ => false,
        };
    }

    /// The extension, and the only other spelling a memory loader accepts
    fn extensions(comptime format: AudioFormat) [2][:0]const u8 {
        return switch (format) {
            .wav => .{ ".wav", ".WAV" },
            .ogg => .{ ".ogg", ".OGG" },
            .flac => .{ ".flac", ".FLAC" },
            .mp3 => .{ ".mp3", ".MP3" },
            .qoa => .{ ".qoa", ".QOA" },
            .xm => .{ ".xm", ".XM" },
            .mod => .{ ".mod", ".MOD" },
            _ => unreachable,
        };
    }

    /// The name in raudio's "Failed to load <name> data" warnings
    fn name(format: AudioFormat) [*:0]const u8 {
        return switch (format) {
            .wav => "WAV",
            .ogg => "OGG",
            .flac => "FLAC",
            .mp3 => "MP3",
            .qoa => "QOA",
            .xm => "XM",
            .mod => "MOD",
            _ => "",
        };
    }

    fn of(music: Music) AudioFormat {
        return @fromBackingInt(@intCast(music.ctxType));
    }
};

/// Formats LoadWave* decodes, in raudio.c's order
const wave_formats = [_]AudioFormat{ .wav, .ogg, .mp3, .qoa, .flac };
/// Formats LoadMusicStream* streams, in raudio.c's order
const music_formats = [_]AudioFormat{ .wav, .ogg, .mp3, .qoa, .flac, .xm, .mod };

/// A memory loader's file type: exactly the lower- or upper-case extension
/// (raylib: "File extension must be provided in lower-case").
fn formatOfFileType(fileType: ?[*:0]const u8, comptime candidates: []const AudioFormat) ?AudioFormat {
    const ext = cSpan(fileType) orelse return null;
    inline for (candidates) |format| {
        if (comptime !format.enabled()) continue;
        for (format.extensions()) |spelling| {
            if (std.mem.eql(u8, ext, spelling)) return format;
        }
    }
    return null;
}

/// A file loader's format, by raylib's IsFileExtension (case-insensitive)
fn formatOfFileName(fileName: ?[*:0]const u8, comptime candidates: []const AudioFormat) ?AudioFormat {
    inline for (candidates) |format| {
        if (comptime !format.enabled()) continue;
        if (IsFileExtension(fileName, format.extensions()[0])) return format;
    }
    return null;
}

/// AudioBufferUsage (raudio.c:339-342). raudio tests only for STATIC.
const BufferUsage = enum(c_int) {
    static = 0,
    stream = 1,
    _,
};

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

    converterResidual: []u8, // Cached residual input frames, AUDIO_BUFFER_RESIDUAL_CAPACITY of them
    converterResidualCount: c_uint = 0, // The number of valid frames sitting in converterResidual

    callback: AudioCallback = null, // Audio buffer callback for buffer filling on audio threads
    processors: DoublyLinkedList = .{}, // Audio processors (AudioProcessor.node)

    volume: f32 = 1.0, // Audio buffer volume
    pitch: f32 = 1.0, // Audio buffer pitch
    pan: f32 = 0.0, // Audio buffer pan (-1.0f to 1.0f), center by default

    playing: bool = false, // Audio buffer state: AUDIO_PLAYING
    paused: bool = false, // Audio buffer state: AUDIO_PAUSED
    looping: bool = false, // Audio buffer looping, default to true for AudioStreams
    usage: BufferUsage, // Audio buffer usage mode: STATIC or STREAM

    // Buffers are marked as processed by default so that a call to
    // UpdateAudioStream() immediately after initialization works correctly
    isSubBufferProcessed: [2]bool = .{ true, true }, // SubBuffer processed (virtual double buffer)
    sizeInFrames: c_uint, // Total buffer size in frames
    frameCursorPos: c_uint = 0, // Frame cursor position
    framesProcessed: c_uint = 0, // Total frames processed in this buffer (required for play timing)

    // Data buffer, on music stream keeps filling. C heap: sound aliases share
    // it, and its length isn't tracked once an alias points at it
    data: ?[*]u8,

    node: DoublyLinkedList.Node = .{}, // Position in AUDIO.buffers

    fn fromNode(node: *DoublyLinkedList.Node) *AudioBuffer {
        return @fieldParentPtr("node", node);
    }

    fn bytesPerFrame(buffer: *const AudioBuffer) c_uint {
        return maGetBytesPerFrame(buffer.formatIn, buffer.channelsIn);
    }
};

/// Audio processor (raudio.c:375-379), useful to apply effects to an AudioBuffer
const AudioProcessor = struct {
    process: AudioCallback, // Processor callback function
    node: DoublyLinkedList.Node = .{}, // Position in its processor list

    fn fromNode(node: *DoublyLinkedList.Node) *AudioProcessor {
        return @fieldParentPtr("node", node);
    }
};

/// Audio data context (raudio.c:384-399). The C global embeds the miniaudio
/// context/device/mutex by value; here they are opaque heap objects (created in
/// InitAudioDevice via the shim) plus a cache of the device properties raudio.c
/// reads directly from `AUDIO.System.device`.
const AudioData = struct {
    system: System = .{},
    buffers: DoublyLinkedList = .{}, // Every loaded AudioBuffer (AudioBuffer.node)
    defaultBufferSize: c_int = 0, // Default audio buffer size for audio streams
    mixedProcessors: DoublyLinkedList = .{}, // Processors on the mixed output (AudioProcessor.node)

    const System = struct {
        context: ?*MaContext = null, // miniaudio context data
        device: ?*MaDevice = null, // miniaudio device
        lock: ?*MaMutex = null, // miniaudio mutex lock
        isReady: bool = false, // Check if audio device is ready
        pcmBuffer: []u8 = &.{}, // Pre-allocated buffer to read audio data from file/memory

        // Cached miniaudio device properties (zero while no device, like C's zeroed global):
        deviceSampleRate: c_uint = 0, // device.sampleRate
        playbackFormat: c_int = 0, // device.playback.format
        playbackChannels: c_uint = 0, // device.playback.channels
        playbackInternalPeriodSizeInFrames: c_uint = 0, // device.playback.internalPeriodSizeInFrames

        fn forgetDevice(system: *System) void {
            system.deviceSampleRate = 0;
            system.playbackFormat = 0;
            system.playbackChannels = 0;
            system.playbackInternalPeriodSizeInFrames = 0;
        }
    };
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
const MaLogCallbackProc = *const fn (?*anyopaque, c_uint, [*:0]const u8) callconv(.c) void;

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
extern fn rl_ma_context_backend_name(ctx: *MaContext) [*:0]const u8;
extern fn rl_ma_device_create(ctx: *MaContext, dataCallback: MaDeviceDataProc) ?*MaDevice;
extern fn rl_ma_device_destroy(device: ?*MaDevice) void;
extern fn rl_ma_device_get_info(device: *MaDevice, info: *RlMaDeviceInfo) void;
extern fn rl_ma_mutex_create() ?*MaMutex;
extern fn rl_ma_mutex_destroy(mutex: ?*MaMutex) void;
extern fn rl_ma_data_converter_create(formatIn: c_int, channelsIn: c_uint, sampleRateIn: c_uint, sampleRateOut: c_uint) ?*MaDataConverter;
extern fn rl_ma_data_converter_destroy(converter: *MaDataConverter) void;
extern fn rl_ma_data_converter_resampler_rate_in(converter: *MaDataConverter) c_uint;
extern fn rl_ma_data_converter_resampler_rate_out(converter: *MaDataConverter) c_uint;

// miniaudio direct externs (MA_API, non-static; miniaudio.h lines cited)
extern fn ma_device_start(device: *MaDevice) c_int; // :9185, ma_result
extern fn ma_device_set_master_volume(device: ?*MaDevice, volume: f32) c_int; // :9417
extern fn ma_device_get_master_volume(device: ?*MaDevice, volume: *f32) c_int; // :9460
extern fn ma_mutex_lock(mutex: *MaMutex) void; // :6219
extern fn ma_mutex_unlock(mutex: *MaMutex) void; // :6224
extern fn ma_data_converter_process_pcm_frames(converter: *MaDataConverter, framesIn: ?*const anyopaque, frameCountIn: *u64, framesOut: ?*anyopaque, frameCountOut: *u64) c_int; // :5655
extern fn ma_data_converter_set_rate(converter: *MaDataConverter, sampleRateIn: c_uint, sampleRateOut: c_uint) c_int; // :5656
extern fn ma_get_bytes_per_sample(format: c_int) c_uint; // :6170
extern fn ma_convert_frames(out: ?*anyopaque, frameCountOut: u64, formatOut: c_int, channelsOut: c_uint, sampleRateOut: c_uint, in: ?*const anyopaque, frameCountIn: u64, formatIn: c_int, channelsIn: c_uint, sampleRateIn: c_uint) u64; // :5827
extern fn ma_get_format_name(format: c_int) [*:0]const u8; // :6155

// ma_get_bytes_per_frame is `static MA_INLINE` (miniaudio.h:6171): reimplemented,
// same expression: ma_get_bytes_per_sample(format)*channels
fn maGetBytesPerFrame(format: c_int, channels: c_uint) c_uint {
    return ma_get_bytes_per_sample(format) *% channels;
}

// dr_wav (dr_wav.h:1053-1327; drwav_bool32 is u32, drwav_result is i32, drwav_uint64 is u64)
extern fn rl_sizeof_drwav() usize;
extern fn rl_drwav_get_info(wav: *DrWav, totalPCMFrameCount: *u64, sampleRate: *c_uint, channels: *c_uint, bitsPerSample: *c_uint) void;
extern fn drwav_init_memory(wav: *DrWav, data: ?*const anyopaque, dataSize: usize, allocationCallbacks: ?*const anyopaque) u32; // :1277
extern fn drwav_init_file(wav: *DrWav, filename: [*:0]const u8, allocationCallbacks: ?*const anyopaque) u32; // :1246
extern fn rl_drwav_init_memory_write(wav: *DrWav, ppData: *?*anyopaque, pDataSize: *usize, format: c_uint, channels: c_uint, sampleRate: c_uint, bitsPerSample: c_uint) u32;
extern fn drwav_uninit(wav: *DrWav) i32; // :1053
extern fn drwav_read_pcm_frames_s16(wav: *DrWav, framesToRead: u64, bufferOut: ?[*]i16) u64; // :1138
extern fn drwav_read_pcm_frames_f32(wav: *DrWav, framesToRead: u64, bufferOut: [*]f32) u64; // :1173
extern fn drwav_write_pcm_frames(wav: *DrWav, framesToWrite: u64, data: ?*const anyopaque) u64; // :1122
extern fn rl_drwav_seek_to_first_pcm_frame(wav: *DrWav) u32; // DRWAV_PRIVATE upstream (:6011)
extern fn drwav_seek_to_pcm_frame(wav: *DrWav, targetFrameIndex: u64) u32; // :1094
extern fn drwav_free(p: ?*anyopaque, allocationCallbacks: ?*const anyopaque) void; // :1327

// stb_vorbis (stb_vorbis.c:150-361)
extern fn stb_vorbis_open_memory(data: ?[*]const u8, len: c_int, err: ?*c_int, allocBuffer: ?*const anyopaque) ?*StbVorbis; // :268
extern fn stb_vorbis_open_filename(filename: [*:0]const u8, err: ?*c_int, allocBuffer: ?*const anyopaque) ?*StbVorbis; // :274
extern fn rl_stb_vorbis_get_info(vorbis: *StbVorbis, sampleRate: *c_uint, channels: *c_int) void; // get_info returns by value (:150)
extern fn stb_vorbis_stream_length_in_samples(vorbis: *StbVorbis) c_uint; // :310
extern fn stb_vorbis_get_samples_short_interleaved(vorbis: *StbVorbis, channels: c_int, buffer: ?[*]i16, numShorts: c_int) c_int; // :361
extern fn stb_vorbis_seek_start(vorbis: *StbVorbis) c_int; // :307
extern fn stb_vorbis_seek_frame(vorbis: *StbVorbis, sampleNumber: c_uint) c_int; // :298
extern fn stb_vorbis_close(vorbis: *StbVorbis) void; // :159

// dr_mp3 (dr_mp3.h:463-558; drmp3_bool32 is u32, drmp3_uint64 is u64)
const Drmp3Config = extern struct { channels: c_uint, sampleRate: c_uint }; // dr_mp3.h:393-396
extern fn rl_sizeof_drmp3() usize;
extern fn rl_drmp3_get_info(mp3: *DrMp3, channels: *c_uint, sampleRate: *c_uint) void; // fields at dr_mp3.h:401-402
extern fn drmp3_init_memory(mp3: *DrMp3, data: ?*const anyopaque, dataSize: usize, allocationCallbacks: ?*const anyopaque) u32; // :463
extern fn drmp3_init_file(mp3: *DrMp3, filePath: [*:0]const u8, allocationCallbacks: ?*const anyopaque) u32; // :476
extern fn drmp3_uninit(mp3: *DrMp3) void; // :483
extern fn drmp3_read_pcm_frames_f32(mp3: *DrMp3, framesToRead: u64, bufferOut: [*]f32) u64; // :490
extern fn drmp3_get_pcm_frame_count(mp3: *DrMp3) u64; // :510
extern fn drmp3_seek_to_pcm_frame(mp3: *DrMp3, frameIndex: u64) u32; // :504
extern fn rl_drmp3_seek_to_start_of_stream(mp3: *DrMp3) u32; // static upstream (:4348)
extern fn drmp3_open_memory_and_read_pcm_frames_f32(data: ?*const anyopaque, dataSize: usize, config: *Drmp3Config, totalFrameCount: *u64, allocationCallbacks: ?*const anyopaque) ?[*]f32; // :558

// qoa / qoaplay (qoa.h:143-154, qoaplay.c:64-74)
extern fn rl_qoa_decode(bytes: ?[*]const u8, size: c_int, channels: *c_uint, samplerate: *c_uint, samples: *c_uint) ?[*]i16;
extern fn rl_qoa_write(fileName: [*:0]const u8, sampleData: ?*const anyopaque, channels: c_uint, samplerate: c_uint, samples: c_uint) c_int;
extern fn qoaplay_open(path: [*:0]const u8) ?*QoaPlayDesc; // qoaplay.c:64
extern fn qoaplay_open_memory(data: [*]const u8, dataSize: c_int) ?*QoaPlayDesc; // :65
extern fn qoaplay_close(ctx: *QoaPlayDesc) void; // :66
extern fn qoaplay_rewind(ctx: *QoaPlayDesc) void; // :68
extern fn qoaplay_seek_frame(ctx: *QoaPlayDesc, frame: c_int) void; // :69
extern fn qoaplay_decode(ctx: *QoaPlayDesc, sampleData: [*]f32, numSamples: c_int) c_uint; // :70
extern fn rl_qoaplay_get_info(ctx: *QoaPlayDesc, channels: *c_uint, samplerate: *c_uint, samples: *c_uint) void;
extern fn rl_qoaplay_sample_position(ctx: *QoaPlayDesc) c_uint;

// jar_xm (jar_xm.h:93-220)
extern fn jar_xm_create_context_from_file(ctx: *?*JarXmContext, rate: u32, filename: [*:0]const u8) c_int; // :93
extern fn jar_xm_create_context_safe(ctx: *?*JarXmContext, moddata: ?[*]const u8, moddataLength: usize, rate: u32) c_int; // :112
extern fn jar_xm_free_context(ctx: ?*JarXmContext) void; // :115
extern fn jar_xm_set_max_loop_count(ctx: *JarXmContext, loopcnt: u8) void; // :150
extern fn jar_xm_get_remaining_samples(ctx: *JarXmContext) u64; // :220
extern fn jar_xm_reset(ctx: *JarXmContext) void; // :2259
extern fn jar_xm_generate_samples(ctx: *JarXmContext, output: [*]f32, numsamples: usize) void; // :120
extern fn jar_xm_get_position(ctx: *JarXmContext, patternIndex: ?*u8, pattern: ?*u8, row: ?*u8, samples: ?*u64) void; // :202

// jar_mod (jar_mod.h:245-252; mulong is unsigned long)
extern fn rl_sizeof_jar_mod_context() usize;
extern fn rl_jar_mod_load_memory(data: ?[*]const u8, dataSize: c_int) ?*JarModContext; // jar_mod_load is static upstream (:1117)
extern fn jar_mod_init(ctx: *JarModContext) bool; // :245
extern fn jar_mod_load_file(ctx: *JarModContext, filename: [*:0]const u8) c_ulong; // :249
extern fn jar_mod_unload(ctx: *JarModContext) void; // :248
extern fn jar_mod_max_samples(ctx: *JarModContext) c_ulong; // :251
extern fn jar_mod_seek_start(ctx: *JarModContext) void; // :252
extern fn jar_mod_fillbuffer(ctx: *JarModContext, outBuffer: [*]i16, nbsample: c_ulong, trkbuf: ?*anyopaque) void; // :247

//----------------------------------------------------------------------------------
// Small helpers
//----------------------------------------------------------------------------------

/// A C string parameter, typed for the Zig side
fn cStr(text: [*c]const u8) ?[*:0]const u8 {
    return @ptrCast(text);
}

fn cSpan(text: ?[*:0]const u8) ?[:0]const u8 {
    return if (text) |t| std.mem.span(t) else null;
}

/// `len` bytes at `ptr`. C passes NULL with a zero length freely.
fn bytesAt(ptr: ?*const anyopaque, len: usize) []const u8 {
    if (len == 0) return &.{};
    const bytes: [*]const u8 = @ptrCast(ptr.?);
    return bytes[0..len];
}

/// A sample view of decode-buffer bytes, for a decoder that writes `T`s
fn samplesAt(comptime T: type, bytes: []u8) [*]T {
    return @ptrCast(@alignCast(bytes.ptr));
}

/// C's implicit `int` -> `uint64` conversion (ma_uint64/drwav_uint64): sign-extend
fn cU64(n: c_int) u64 {
    return @bitCast(@as(i64, n));
}

/// The miniaudio sample format raudio uses for a sample size in bits
fn sampleFormat(sampleSize: c_uint) c_int {
    return switch (sampleSize) {
        8 => ma_format_u8,
        16 => ma_format_s16,
        else => ma_format_f32,
    };
}

/// Zeroed C-heap storage for a third-party decoder struct whose size only the
/// shim knows. Music.ctxData holds it and UnloadMusicStream frees it, as C.
fn allocDecoder(comptime T: type, size: usize) ?*T {
    const memory = cmem.alloc(u8, size) catch return null;
    return @ptrCast(memory.ptr);
}

/// Zeroed scratch storage for a dr_wav decoder used within one call (C keeps
/// a stack-local `drwav wav = { 0 }`; its size is only known to the shim).
const ScratchWav = struct {
    memory: []align(16) u8,

    fn init() error{OutOfMemory}!ScratchWav {
        const memory = try c_allocator.alignedAlloc(u8, .@"16", rl_sizeof_drwav());
        @memset(memory, 0);
        return .{ .memory = memory };
    }

    fn deinit(scratch: ScratchWav) void {
        c_allocator.free(scratch.memory);
    }

    fn wav(scratch: ScratchWav) *DrWav {
        return @ptrCast(scratch.memory.ptr);
    }
};

// C locks `AUDIO.System.lock` (an embedded, zero-initialized ma_mutex) even before
// InitAudioDevice() ever ran; our mutex only exists once created there, so locking
// is skipped while there is no mutex (single-threaded at that point: same behavior).
fn lockAudio() void {
    if (AUDIO.system.lock) |lock| ma_mutex_lock(lock);
}

fn unlockAudio() void {
    if (AUDIO.system.lock) |lock| ma_mutex_unlock(lock);
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Audio Device initialization and Closing
//----------------------------------------------------------------------------------

const DeviceError = error{ ContextFailed, DeviceFailed, MutexFailed, StartFailed };

// Initialize audio device
export fn InitAudioDevice() void {
    const info = openAudioDevice() catch |err| {
        TraceLog(LOG_WARNING, switch (err) {
            error.ContextFailed => "AUDIO: Failed to initialize context",
            error.DeviceFailed => "AUDIO: Failed to initialize playback device",
            error.MutexFailed => "AUDIO: Failed to create mutex for mixing",
            error.StartFailed => "AUDIO: Failed to start playback device",
        });
        return;
    };

    TraceLog(LOG_INFO, "AUDIO: Device initialized successfully");
    TraceLog(LOG_INFO, "    > Backend:       miniaudio | %s", rl_ma_context_backend_name(AUDIO.system.context.?));
    TraceLog(LOG_INFO, "    > Format:        %s -> %s", ma_get_format_name(info.format), ma_get_format_name(info.internalFormat));
    TraceLog(LOG_INFO, "    > Channels:      %d -> %d", info.channels, info.internalChannels);
    TraceLog(LOG_INFO, "    > Sample rate:   %d -> %d", info.sampleRate, info.internalSampleRate);
    TraceLog(LOG_INFO, "    > Periods size:  %d", info.internalPeriodSizeInFrames *% info.internalPeriods);

    AUDIO.system.isReady = true;
}

/// Creates and starts the miniaudio context, device and mixing mutex
/// (raudio.c:468-519), leaving AUDIO.system as C leaves it on each failure.
fn openAudioDevice() DeviceError!RlMaDeviceInfo {
    // The log callback is built-and-discarded inside the shim exactly as upstream does
    const context = rl_ma_context_create(&onLog) orelse return error.ContextFailed;
    AUDIO.system.context = context;
    errdefer {
        rl_ma_context_destroy(context);
        AUDIO.system.context = null;
    }

    // Default playback device, f32 stereo (raudio.c:480-497)
    const device = rl_ma_device_create(context, &onSendAudioDataToDevice) orelse return error.DeviceFailed;
    AUDIO.system.device = device;
    errdefer {
        rl_ma_device_destroy(device);
        AUDIO.system.device = null;
        AUDIO.system.forgetDevice(); // ma_device_uninit() zeroes the C global's device
    }

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

    // Mixing happens on a separate thread, synchronized by this mutex. Like
    // raudio.c, the mutex outlives a failed device start below
    AUDIO.system.lock = rl_ma_mutex_create() orelse return error.MutexFailed;

    // Keep the device running the whole time
    if (ma_device_start(device) != MA_SUCCESS) return error.StartFailed;

    return info;
}

// Close the audio device for all contexts
export fn CloseAudioDevice() void {
    if (!AUDIO.system.isReady) {
        TraceLog(LOG_WARNING, "AUDIO: Device could not be closed, not currently initialized");
        return;
    }

    // Stop the device first (joins the callback thread) before destroying the mutex it locks
    rl_ma_device_destroy(AUDIO.system.device);
    AUDIO.system.device = null;
    rl_ma_mutex_destroy(AUDIO.system.lock);
    AUDIO.system.lock = null;
    rl_ma_context_destroy(AUDIO.system.context);
    AUDIO.system.context = null;
    AUDIO.system.forgetDevice(); // ma_device_uninit() zeroes the C global's device

    AUDIO.system.isReady = false;
    c_allocator.free(AUDIO.system.pcmBuffer);
    AUDIO.system.pcmBuffer = &.{};

    TraceLog(LOG_INFO, "AUDIO: Device closed successfully");
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
    return createAudioBuffer(format, channels, sampleRate, sizeInFrames, @fromBackingInt(@intCast(usage))) catch |err| {
        TraceLog(LOG_WARNING, switch (err) {
            error.OutOfMemory => "AUDIO: Failed to allocate memory for buffer",
            error.ConverterFailed => "AUDIO: Failed to create data conversion pipeline",
        });
        return null;
    };
}

fn createAudioBuffer(format: c_int, channels: c_uint, sampleRate: c_uint, sizeInFrames: c_uint, usage: BufferUsage) error{ OutOfMemory, ConverterFailed }!*AudioBuffer {
    const buffer = try c_allocator.create(AudioBuffer);
    errdefer c_allocator.destroy(buffer);

    const data: ?[*]u8 = if (sizeInFrames > 0)
        (try cmem.alloc(u8, sizeInFrames *% channels *% ma_get_bytes_per_sample(format))).ptr
    else
        null;
    errdefer cmem.free(data);

    // Audio data runs through a format converter (raudio.c:588-598); output side is
    // always AUDIO_DEVICE_FORMAT x AUDIO_DEVICE_CHANNELS at the device sample rate
    const converter = rl_ma_data_converter_create(format, channels, sampleRate, AUDIO.system.deviceSampleRate) orelse
        return error.ConverterFailed;
    errdefer rl_ma_data_converter_destroy(converter);

    // Residual input-frame cache for the converter; required because pitch shifting
    // is done through resampling (raudio.c:600-607)
    const residual = try c_allocator.alloc(u8, AUDIO_BUFFER_RESIDUAL_CAPACITY *% maGetBytesPerFrame(format, channels));
    @memset(residual, 0);

    buffer.* = .{
        .converter = converter,
        .formatIn = format,
        .channelsIn = channels,
        .channelsOut = AUDIO_DEVICE_CHANNELS,
        .sampleRateIn = sampleRate,
        .converterResidual = residual,
        .usage = usage,
        .sizeInFrames = sizeInFrames,
        .data = data,
    };

    TrackAudioBuffer(buffer);
    return buffer;
}

/// Releases an audio buffer; `data` stays when a sound alias shares it
fn destroyAudioBuffer(buffer: *AudioBuffer, ownership: enum { owns_data, shares_data }) void {
    UntrackAudioBuffer(buffer);
    rl_ma_data_converter_destroy(buffer.converter);
    c_allocator.free(buffer.converterResidual);
    if (ownership == .owns_data) cmem.free(buffer.data);
    c_allocator.destroy(buffer);
}

// Delete an audio buffer
export fn UnloadAudioBuffer(buffer: ?*AudioBuffer) void {
    if (buffer) |b| destroyAudioBuffer(b, .owns_data);
}

// Check if an audio buffer is playing from a program state without lock
export fn IsAudioBufferPlaying(buffer: ?*AudioBuffer) bool {
    lockAudio();
    defer unlockAudio();
    return isAudioBufferPlayingInLockedState(buffer);
}

// Play an audio buffer
// NOTE: Buffer is restarted to the start
// Use PauseAudioBuffer() and ResumeAudioBuffer() if the playback position should be maintained
export fn PlayAudioBuffer(buffer: ?*AudioBuffer) void {
    const b = buffer orelse return;
    lockAudio();
    defer unlockAudio();
    b.playing = true;
    b.paused = false;
    b.frameCursorPos = 0;
    b.framesProcessed = 0;
    b.isSubBufferProcessed = .{ true, true };
}

// Stop an audio buffer from a program state without lock
export fn StopAudioBuffer(buffer: ?*AudioBuffer) void {
    lockAudio();
    defer unlockAudio();
    stopAudioBufferInLockedState(buffer);
}

// Pause an audio buffer
export fn PauseAudioBuffer(buffer: ?*AudioBuffer) void {
    const b = buffer orelse return;
    lockAudio();
    defer unlockAudio();
    b.paused = true;
}

// Resume an audio buffer
export fn ResumeAudioBuffer(buffer: ?*AudioBuffer) void {
    const b = buffer orelse return;
    lockAudio();
    defer unlockAudio();
    b.paused = false;
}

// Set volume for an audio buffer
export fn SetAudioBufferVolume(buffer: ?*AudioBuffer, volume: f32) void {
    const b = buffer orelse return;
    lockAudio();
    defer unlockAudio();
    b.volume = volume;
}

// Set pitch for an audio buffer
export fn SetAudioBufferPitch(buffer: ?*AudioBuffer, pitch: f32) void {
    const b = buffer orelse return;
    if (!(pitch > 0.0)) return;

    lockAudio();
    defer unlockAudio();
    // Pitching is an adjustment of the sample rate; this changes the duration
    // of the sound: higher pitches are faster, lower pitches slower
    const outputSampleRate: c_uint = @intFromFloat(@as(f32, @floatFromInt(AUDIO.system.deviceSampleRate)) / pitch);
    _ = ma_data_converter_set_rate(b.converter, b.sampleRateIn, outputSampleRate);
    b.pitch = pitch;
}

// Set pan for an audio buffer
export fn SetAudioBufferPan(buffer: ?*AudioBuffer, pan: f32) void {
    // Not std.math.clamp: raylib's two comparisons let a NaN pan through unchanged
    const clampedPan: f32 = if (pan < -1.0) -1.0 else if (pan > 1.0) 1.0 else pan;

    const b = buffer orelse return;
    lockAudio();
    defer unlockAudio();
    b.pan = clampedPan;
}

// Track audio buffer to linked list next position
export fn TrackAudioBuffer(buffer: ?*AudioBuffer) void {
    lockAudio();
    defer unlockAudio();
    AUDIO.buffers.append(&buffer.?.node);
}

// Untrack audio buffer from linked list
export fn UntrackAudioBuffer(buffer: ?*AudioBuffer) void {
    lockAudio();
    defer unlockAudio();
    const node = &buffer.?.node;
    AUDIO.buffers.remove(node);
    node.* = .{};
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Sounds loading and playing (.WAV)
//----------------------------------------------------------------------------------

// Load wave data from file
export fn LoadWave(fileName: [*c]const u8) Wave {
    const path = cStr(fileName);

    // Loading file to memory
    var dataSize: c_int = 0;
    const fileData = LoadFileData(path, &dataSize);
    defer UnloadFileData(fileData);

    // Loading wave from memory data
    if (fileData == null) return .empty;
    return LoadWaveFromMemory(GetFileExtension(path), fileData, dataSize);
}

/// File data handed to a LoadXFromMemory function. Kept as C's pointer and
/// int size: the decoders take them as such, negative sizes included.
const Memory = struct {
    data: ?[*]const u8,
    size: c_int,

    /// `size` as the decoders that take a size_t see it (sign-extended, as C)
    fn byteLen(memory: Memory) usize {
        return @bitCast(@as(isize, memory.size));
    }
};

// Load wave from memory buffer, fileType refers to extension: i.e. ".wav"
// WARNING: File extension must be provided in lower-case
export fn LoadWaveFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: c_int) Wave {
    const memory: Memory = .{ .data = fileData, .size = dataSize };

    const wave: Wave = if (formatOfFileType(cStr(fileType), &wave_formats)) |format|
        decodeWave(format, memory) orelse failed: {
            TraceLog(LOG_WARNING, "WAVE: Failed to load %s data", format.name());
            // Deliberate: raylib sets MP3's and QOA's sample size before it
            // checks the decode, so the line below reports it even on failure
            var failed = Wave.empty;
            failed.sampleSize = switch (format) {
                .mp3 => 32,
                .qoa => 16,
                else => 0,
            };
            break :failed failed;
        }
    else unsupported: {
        TraceLog(LOG_WARNING, "WAVE: Data format not supported");
        break :unsupported .empty;
    };

    TraceLog(LOG_INFO, "WAVE: Data loaded successfully (%i Hz, %i bit, %i channels)", wave.sampleRate, wave.sampleSize, wave.channels);

    return wave;
}

/// Decodes a whole file in memory; null when the decoder rejects it
fn decodeWave(format: AudioFormat, memory: Memory) ?Wave {
    return switch (format) {
        .wav => decodeWav(memory),
        .ogg => decodeOgg(memory),
        .mp3 => decodeMp3(memory),
        .qoa => decodeQoa(memory),
        else => unreachable, // not in wave_formats, or disabled
    };
}

fn decodeWav(memory: Memory) ?Wave {
    const scratch = ScratchWav.init() catch return null;
    defer scratch.deinit();
    const wav = scratch.wav();
    // raylib uninitializes the decoder whether or not it opened
    defer _ = drwav_uninit(wav);

    if (drwav_init_memory(wav, memory.data, memory.byteLen(), null) == 0) return null;

    var totalPCMFrameCount: u64 = 0;
    var wave: Wave = .{ .frameCount = 0, .sampleRate = 0, .sampleSize = 16, .channels = 0, .data = null };
    var bitsPerSample: c_uint = 0;
    rl_drwav_get_info(wav, &totalPCMFrameCount, &wave.sampleRate, &wave.channels, &bitsPerSample);
    wave.frameCount = @truncate(totalPCMFrameCount);

    // NOTE: Forcing conversion to 16bit sample size on reading
    const samples = cmem.alloc(i16, wave.frameCount *% wave.channels) catch return null;
    _ = drwav_read_pcm_frames_s16(wav, wave.frameCount, samples.ptr);
    wave.data = samples.ptr;
    return wave;
}

fn decodeOgg(memory: Memory) ?Wave {
    const ogg = stb_vorbis_open_memory(memory.data, memory.size, null, null) orelse return null;
    defer stb_vorbis_close(ogg);

    var sampleRate: c_uint = 0;
    var channels: c_int = 0;
    rl_stb_vorbis_get_info(ogg, &sampleRate, &channels);

    var wave: Wave = .{
        .frameCount = stb_vorbis_stream_length_in_samples(ogg), // NOTE: It returns frames!
        .sampleRate = sampleRate,
        .sampleSize = 16, // By default, ogg data is 16 bit per sample (short)
        .channels = @bitCast(channels),
        .data = null,
    };
    const sampleCount = wave.frameCount *% wave.channels;
    // Like raylib, a failed allocation leaves the decoder writing nowhere
    const samples: ?[*]i16 = if (cmem.alloc(i16, sampleCount)) |s| s.ptr else |_| null;

    // NOTE: The count is in shorts, not bytes
    _ = stb_vorbis_get_samples_short_interleaved(ogg, channels, samples, @bitCast(sampleCount));
    wave.data = samples;
    return wave;
}

fn decodeMp3(memory: Memory) ?Wave {
    var config: Drmp3Config = .{ .channels = 0, .sampleRate = 0 };
    var totalFrameCount: u64 = 0;

    // NOTE: Forcing conversion to 32bit float sample size on reading
    const samples = drmp3_open_memory_and_read_pcm_frames_f32(memory.data, memory.byteLen(), &config, &totalFrameCount, null) orelse return null;
    return .{
        .frameCount = @truncate(totalFrameCount), // WARNING: Potential loss of data
        .sampleRate = config.sampleRate,
        .sampleSize = 32,
        .channels = config.channels,
        .data = samples,
    };
}

fn decodeQoa(memory: Memory) ?Wave {
    var wave: Wave = .{ .frameCount = 0, .sampleRate = 0, .sampleSize = 16, .channels = 0, .data = null };
    // NOTE: Returned sample data is always 16 bit
    wave.data = rl_qoa_decode(memory.data, memory.size, &wave.channels, &wave.sampleRate, &wave.frameCount) orelse return null;
    return wave;
}

// Check if wave data is valid (data loaded and parameters)
export fn IsWaveValid(wave: Wave) bool {
    return (wave.data != null) and // Validate wave data available
        (wave.frameCount > 0) and // Validate frame count
        (wave.sampleRate > 0) and // Validate sample rate is supported
        (wave.sampleSize > 0) and // Validate sample size is supported
        (wave.channels > 0); // Validate number of channels supported
}

// Load sound from file
// NOTE: The entire file is loaded to memory to be played (no-streaming)
export fn LoadSound(fileName: [*c]const u8) Sound {
    const wave = LoadWave(fileName);
    defer UnloadWave(wave); // Sound is loaded, wave can be unloaded
    return LoadSoundFromWave(wave);
}

// Load sound from wave data
// NOTE: Wave data must be unallocated manually
export fn LoadSoundFromWave(wave: Wave) Sound {
    var sound = std.mem.zeroes(Sound);
    if (wave.data == null) return sound;

    // Format conversion to the device format is done in one go at load time
    // (mixing with miniaudio is manual, so every sound must share one format)
    const formatIn = sampleFormat(wave.sampleSize);
    const rate = AUDIO.system.deviceSampleRate;

    var frameCount: c_uint = @truncate(ma_convert_frames(null, 0, AUDIO_DEVICE_FORMAT, AUDIO_DEVICE_CHANNELS, rate, null, wave.frameCount, formatIn, wave.channels, wave.sampleRate));
    if (frameCount == 0) TraceLog(LOG_WARNING, "SOUND: Failed to get frame count for format conversion");

    const buffer = LoadAudioBuffer(AUDIO_DEVICE_FORMAT, AUDIO_DEVICE_CHANNELS, rate, frameCount, @backingInt(BufferUsage.static)) orelse {
        TraceLog(LOG_WARNING, "SOUND: Failed to create buffer");
        return sound;
    };

    frameCount = @truncate(ma_convert_frames(buffer.data, frameCount, AUDIO_DEVICE_FORMAT, AUDIO_DEVICE_CHANNELS, rate, wave.data, wave.frameCount, formatIn, wave.channels, wave.sampleRate));
    if (frameCount == 0) TraceLog(LOG_WARNING, "SOUND: Failed format conversion");

    sound.frameCount = frameCount;
    sound.stream = deviceStream(buffer);
    return sound;
}

/// A stream in the device's own format over `buffer`
fn deviceStream(buffer: *AudioBuffer) AudioStream {
    return .{
        .buffer = buffer,
        .processor = null,
        .sampleRate = AUDIO.system.deviceSampleRate,
        .sampleSize = 32,
        .channels = AUDIO_DEVICE_CHANNELS,
    };
}

// Load sound alias, clone sound from existing sound data, clone does not own wave data
// NOTE: Wave data must be unallocated manually and will be shared across all clones
export fn LoadSoundAlias(source: Sound) Sound {
    var sound = std.mem.zeroes(Sound);
    const sourceBuffer = source.stream.buffer orelse return sound;
    if (sourceBuffer.data == null) return sound;

    const buffer = LoadAudioBuffer(AUDIO_DEVICE_FORMAT, AUDIO_DEVICE_CHANNELS, AUDIO.system.deviceSampleRate, 0, @backingInt(BufferUsage.static)) orelse {
        TraceLog(LOG_WARNING, "SOUND: Failed to create buffer");
        return sound;
    };

    buffer.sizeInFrames = sourceBuffer.sizeInFrames;
    buffer.data = sourceBuffer.data;

    sound.frameCount = source.frameCount;
    sound.stream = deviceStream(buffer);
    return sound;
}

// Check if sound is valid (data loaded and buffers initialized)
export fn IsSoundValid(sound: Sound) bool {
    return (sound.frameCount > 0) and // Validate frame count
        (sound.stream.buffer != null) and // Validate stream buffer
        (sound.stream.sampleRate > 0) and // Validate sample rate is supported
        (sound.stream.sampleSize > 0) and // Validate sample size is supported
        (sound.stream.channels > 0); // Validate number of channels supported
}

// Unload wave data
export fn UnloadWave(wave: Wave) void {
    cmem.free(wave.data);
}

// Unload sound
export fn UnloadSound(sound: Sound) void {
    UnloadAudioBuffer(sound.stream.buffer);
}

export fn UnloadSoundAlias(alias: Sound) void {
    // Untrack and unload the sound buffer, not the sample data, it is shared with the source for the alias
    if (alias.stream.buffer) |buffer| destroyAudioBuffer(buffer, .shares_data);
}

// Update sound buffer with new data
// PARAMS: [data], format must match sound.stream.sampleSize, default 32 bit float - stereo
// PARAMS: [frameCount] must not exceed sound.frameCount
export fn UpdateSound(sound: Sound, data: ?*const anyopaque, frameCount: c_int) void {
    const buffer = sound.stream.buffer orelse return;
    StopAudioBuffer(buffer);

    const size = @as(c_uint, @bitCast(frameCount)) *% buffer.bytesPerFrame();
    if (size > 0) @memcpy(buffer.data.?[0..size], bytesAt(data, size));
}

// Export wave data to file
export fn ExportWave(wave: Wave, fileName: [*c]const u8) bool {
    const result = exportWave(wave, cStr(fileName));

    if (result) {
        TraceLog(LOG_INFO, "FILEIO: [%s] Wave data exported successfully", fileName);
    } else {
        TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export wave data", fileName);
    }
    return result;
}

fn exportWave(wave: Wave, fileName: ?[*:0]const u8) bool {
    if (SUPPORT_FILEFORMAT_WAV and IsFileExtension(fileName, ".wav")) return exportWav(wave, fileName);

    if (SUPPORT_FILEFORMAT_QOA and IsFileExtension(fileName, ".qoa")) {
        if (wave.sampleSize != 16) {
            TraceLog(LOG_WARNING, "AUDIO: Wave data must be 16 bit per sample for QOA format export");
            return false;
        }
        return rl_qoa_write(fileName.?, wave.data, wave.channels, wave.sampleRate, wave.frameCount) > 0;
    }

    if (IsFileExtension(fileName, ".raw")) {
        // Export raw sample data (without header)
        // NOTE: It's up to the user to track wave parameters
        return SaveFileData(fileName, wave.data, @bitCast(wave.info().byteSize()));
    }

    return false;
}

fn exportWav(wave: Wave, fileName: ?[*:0]const u8) bool {
    const scratch = ScratchWav.init() catch return false;
    defer scratch.deinit();
    const wav = scratch.wav();

    const format = if (wave.sampleSize == 32) DR_WAVE_FORMAT_IEEE_FLOAT else DR_WAVE_FORMAT_PCM;
    var fileData: ?*anyopaque = null;
    var fileDataSize: usize = 0;
    var result = rl_drwav_init_memory_write(wav, &fileData, &fileDataSize, format, wave.channels, wave.sampleRate, wave.sampleSize) != 0;
    // C stores the written frame count through an (int) cast into a bool
    if (result) result = @as(c_int, @bitCast(@as(c_uint, @truncate(drwav_write_pcm_frames(wav, wave.frameCount, wave.data))))) != 0;

    // Deliberate: raudio.c:1091-1094 shadows `result` with the drwav_result here,
    // so SaveFileData's outcome never reaches the returned value
    if (drwav_uninit(wav) == DRWAV_SUCCESS) _ = SaveFileData(fileName, fileData, @bitCast(@as(c_uint, @truncate(fileDataSize))));
    drwav_free(fileData, null);

    return result;
}

// Export wave sample data to code (.h)
export fn ExportWaveAsCode(wave: Wave, fileName: [*c]const u8) bool {
    const result = exportWaveAsCode(wave, cStr(fileName)) catch false;

    if (result) {
        TraceLog(LOG_INFO, "FILEIO: [%s] Wave as code exported successfully", fileName);
    } else {
        TraceLog(LOG_WARNING, "FILEIO: [%s] Failed to export wave as code", fileName);
    }
    return result;
}

fn exportWaveAsCode(wave: Wave, fileName: ?[*:0]const u8) std.Io.Writer.Error!bool {
    // Wave data is exported as byte array for 8/16bit and float array for 32bit float data
    const size: usize = @intCast(@as(c_int, @bitCast(wave.info().byteSize())));
    const samples: wave_code.Samples = if (wave.sampleSize == 32) floats: {
        const floats: [*]const f32 = @ptrCast(@alignCast(wave.data.?));
        break :floats .{ .floats = floats[0 .. size / 4] };
    } else .{ .bytes = bytesAt(wave.data, size) };

    // Get file name from path and convert variable name to uppercase
    var nameBuffer: [255]u8 = undefined;
    const name = wave_code.variableName(&nameBuffer, cSpan(GetFileNameWithoutExt(fileName)) orelse "");

    var text: std.Io.Writer.Allocating = .init(c_allocator);
    defer text.deinit();
    try wave_code.writeCode(&text.writer, name, wave.info(), samples, formatFloat);
    try text.writer.writeByte(0);

    // NOTE: Text data length exported is determined by '\0' (NULL) character
    const written = text.written();
    return SaveFileText(fileName, written[0 .. written.len - 1 :0]);
}

/// raylib's `%.4f` (the trailing `f` suffix is added by the caller)
fn formatFloat(buf: *[64]u8, value: f32) []const u8 {
    const len = snprintf(buf, buf.len, "%.4f", @as(f64, value));
    return buf[0..@intCast(len)];
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
    return IsAudioBufferPlaying(sound.stream.buffer);
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
export fn WaveFormat(w: *Wave, sampleRate: c_int, sampleSize: c_int, channels: c_int) void {
    const formatIn = sampleFormat(w.sampleSize);
    const formatOut = sampleFormat(@bitCast(sampleSize));
    const rateOut: c_uint = @bitCast(sampleRate);
    const channelsOut: c_uint = @bitCast(channels);

    var frameCount: c_uint = @truncate(ma_convert_frames(null, 0, formatOut, channelsOut, rateOut, null, w.frameCount, formatIn, w.channels, w.sampleRate));
    if (frameCount == 0) {
        TraceLog(LOG_WARNING, "WAVE: Failed to get frame count for format conversion");
        return;
    }

    const bytesPerSample: c_uint = @bitCast(@divTrunc(sampleSize, 8));
    const data = cmem.alloc(u8, frameCount *% channelsOut *% bytesPerSample) catch return;

    frameCount = @truncate(ma_convert_frames(data.ptr, frameCount, formatOut, channelsOut, rateOut, w.data, w.frameCount, formatIn, w.channels, w.sampleRate));
    if (frameCount == 0) {
        cmem.free(data.ptr);
        TraceLog(LOG_WARNING, "WAVE: Failed format conversion");
        return;
    }

    cmem.free(w.data);
    w.* = .{
        .frameCount = frameCount,
        .sampleRate = rateOut,
        .sampleSize = @bitCast(sampleSize),
        .channels = channelsOut,
        .data = data.ptr,
    };
}

// Copy a wave to a new wave
export fn WaveCopy(wave: Wave) Wave {
    // NOTE: Size must be provided in bytes
    const size = wave.info().byteSize();
    const data = cmem.alloc(u8, size) catch return .empty;
    @memcpy(data, bytesAt(wave.data, size));

    var copy = wave;
    copy.data = data.ptr;
    return copy;
}

// Crop a wave to defined frames range
// NOTE: Security check in case of out-of-range
export fn WaveCrop(w: *Wave, initFrame: c_int, finalFrame: c_int) void {
    const range = wave_code.cropRange(w.info(), initFrame, finalFrame) orelse {
        TraceLog(LOG_WARNING, "WAVE: Crop range out of bounds");
        return;
    };

    const data = cmem.alloc(u8, range.len) catch return;
    @memcpy(data, bytesAt(w.data, range.start + range.len)[range.start..]);

    cmem.free(w.data);
    w.data = data.ptr;
    w.frameCount = @bitCast(finalFrame - initFrame);
}

// Load samples data from wave as a floats array
// NOTE 1: Returned sample values are normalized to range [-1..1]
// NOTE 2: Sample data allocated should be freed with UnloadWaveSamples()
export fn LoadWaveSamples(wave: Wave) [*c]f32 {
    // NOTE: The count is of interlaced samples (including channels)
    const samples = cmem.alloc(f32, wave.info().sampleCount()) catch return null;
    if (samples.len > 0) wave_code.normalizeSamples(samples, wave.sampleSize, @ptrCast(wave.data.?));
    return samples.ptr;
}

// Unload samples data loaded with LoadWaveSamples()
export fn UnloadWaveSamples(samples: [*c]f32) void {
    cmem.free(samples);
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Music loading and stream playing
//----------------------------------------------------------------------------------

/// Where a music stream's data comes from
const MusicSource = union(enum) {
    file: [*:0]const u8,
    memory: Memory,
};

/// A decoder opened for streaming, before its AudioStream exists
const MusicDecoder = struct {
    format: AudioFormat,
    ctx: *anyopaque,
    sampleRate: c_uint,
    sampleSize: c_uint,
    channels: c_uint,
    frameCount: c_uint,
};

// Load music stream from file
export fn LoadMusicStream(fileName: [*c]const u8) Music {
    const path = cStr(fileName);

    const decoder = if (formatOfFileName(path, &music_formats)) |format|
        openMusic(format, .{ .file = path.? }) // a matched extension means a name
    else unsupported: {
        TraceLog(LOG_WARNING, "STREAM: [%s] File format not supported", fileName);
        break :unsupported null;
    };

    const music = startMusic(decoder orelse {
        TraceLog(LOG_WARNING, "FILEIO: [%s] Music file could not be opened", fileName);
        return std.mem.zeroes(Music);
    });
    TraceLog(LOG_INFO, "FILEIO: [%s] Music file loaded successfully", fileName);
    logMusicInfo(music);
    return music;
}

// Load music stream from memory buffer, fileType refers to extension: i.e. ".wav"
// WARNING: File extension must be provided in lower-case
export fn LoadMusicStreamFromMemory(fileType: [*c]const u8, data: [*c]const u8, dataSize: c_int) Music {
    const memory: Memory = .{ .data = data, .size = dataSize };

    const decoder = if (formatOfFileType(cStr(fileType), &music_formats)) |format|
        openMusic(format, .{ .memory = memory })
    else unsupported: {
        TraceLog(LOG_WARNING, "STREAM: Data format not supported");
        break :unsupported null;
    };

    const music = startMusic(decoder orelse {
        TraceLog(LOG_WARNING, "FILEIO: Music data could not be loaded");
        return std.mem.zeroes(Music);
    });
    TraceLog(LOG_INFO, "FILEIO: Music data loaded successfully");
    logMusicInfo(music);
    return music;
}

fn startMusic(decoder: MusicDecoder) Music {
    return .{
        .stream = LoadAudioStream(decoder.sampleRate, decoder.sampleSize, decoder.channels),
        .frameCount = decoder.frameCount,
        .looping = true, // Looping enabled by default
        .ctxType = @backingInt(decoder.format),
        .ctxData = decoder.ctx,
    };
}

fn logMusicInfo(music: Music) void {
    const channelsText: [*:0]const u8 = switch (music.stream.channels) {
        1 => "Mono",
        2 => "Stereo",
        else => "Multi",
    };
    TraceLog(LOG_INFO, "    > Sample rate:   %i Hz", music.stream.sampleRate);
    TraceLog(LOG_INFO, "    > Sample size:   %i bits", music.stream.sampleSize);
    TraceLog(LOG_INFO, "    > Channels:      %i (%s)", music.stream.channels, channelsText);
    TraceLog(LOG_INFO, "    > Total frames:  %i", music.frameCount);
}

/// Opens a streaming decoder; null when the data can't be decoded
fn openMusic(format: AudioFormat, source: MusicSource) ?MusicDecoder {
    return switch (format) {
        .wav => openWavMusic(source),
        .ogg => openOggMusic(source),
        .mp3 => openMp3Music(source),
        .qoa => openQoaMusic(source),
        .xm => openXmMusic(source),
        .mod => openModMusic(source),
        else => unreachable, // disabled formats never match
    };
}

fn openWavMusic(source: MusicSource) ?MusicDecoder {
    const wav = allocDecoder(DrWav, rl_sizeof_drwav()) orelse return null;
    const opened = switch (source) {
        .file => |path| drwav_init_file(wav, path, null),
        .memory => |memory| drwav_init_memory(wav, memory.data, memory.byteLen(), null),
    } != 0;
    if (!opened) {
        // As raylib: only the memory loader uninitializes the failed decoder
        if (source == .memory) _ = drwav_uninit(wav);
        cmem.free(wav);
        return null;
    }

    var totalPCMFrameCount: u64 = 0;
    var sampleRate: c_uint = 0;
    var channels: c_uint = 0;
    var bitsPerSample: c_uint = 0;
    rl_drwav_get_info(wav, &totalPCMFrameCount, &sampleRate, &channels, &bitsPerSample);

    return .{
        .format = .wav,
        .ctx = wav,
        .sampleRate = sampleRate,
        .sampleSize = if (bitsPerSample == 24) 16 else bitsPerSample, // 24 bit: converted to s16 on UpdateMusicStream()
        .channels = channels,
        .frameCount = @truncate(totalPCMFrameCount),
    };
}

fn openOggMusic(source: MusicSource) ?MusicDecoder {
    // (On failure raylib calls stb_vorbis_close(NULL), which does nothing)
    const ogg = switch (source) {
        .file => |path| stb_vorbis_open_filename(path, null, null),
        .memory => |memory| stb_vorbis_open_memory(memory.data, memory.size, null, null),
    } orelse return null;

    var sampleRate: c_uint = 0;
    var channels: c_int = 0;
    rl_stb_vorbis_get_info(ogg, &sampleRate, &channels);

    return .{
        .format = .ogg,
        .ctx = ogg,
        .sampleRate = sampleRate,
        .sampleSize = 16, // OGG bit rate defaults to 16 bit, it's enough for compressed format
        .channels = @bitCast(channels),
        // WARNING: It seems this function returns length in frames, not samples
        .frameCount = stb_vorbis_stream_length_in_samples(ogg),
    };
}

fn openMp3Music(source: MusicSource) ?MusicDecoder {
    const mp3 = allocDecoder(DrMp3, rl_sizeof_drmp3()) orelse return null;
    const opened = switch (source) {
        .file => |path| drmp3_init_file(mp3, path, null),
        .memory => |memory| drmp3_init_memory(mp3, memory.data, memory.byteLen(), null),
    } != 0;
    if (!opened) {
        // As raylib: only the memory loader uninitializes the failed decoder
        if (source == .memory) drmp3_uninit(mp3);
        cmem.free(mp3);
        return null;
    }

    var channels: c_uint = 0;
    var sampleRate: c_uint = 0;
    rl_drmp3_get_info(mp3, &channels, &sampleRate);

    return .{
        .format = .mp3,
        .ctx = mp3,
        .sampleRate = sampleRate,
        .sampleSize = 32,
        .channels = channels,
        .frameCount = @truncate(drmp3_get_pcm_frame_count(mp3)),
    };
}

fn openQoaMusic(source: MusicSource) ?MusicDecoder {
    const qoa = switch (source) {
        .file => |path| qoaplay_open(path),
        .memory => |memory| if (memory.data != null and memory.size > 0) qoaplay_open_memory(memory.data.?, memory.size) else null,
    } orelse return null; // no uninit required

    var channels: c_uint = 0;
    var samplerate: c_uint = 0;
    var samples: c_uint = 0;
    rl_qoaplay_get_info(qoa, &channels, &samplerate, &samples);

    // NOTE: Samples are decoded as 32bit float normalized data, so the
    // output audio stream also uses float 32bit
    return .{ .format = .qoa, .ctx = qoa, .sampleRate = samplerate, .sampleSize = 32, .channels = channels, .frameCount = samples };
}

fn openXmMusic(source: MusicSource) ?MusicDecoder {
    const rate = AUDIO.system.deviceSampleRate;
    var created: ?*JarXmContext = null;
    const result = switch (source) {
        .file => |path| jar_xm_create_context_from_file(&created, rate, path),
        .memory => |memory| jar_xm_create_context_safe(&created, memory.data, memory.byteLen(), rate),
    };
    if (result != 0) {
        jar_xm_free_context(created);
        return null;
    }

    const xm = created.?;
    jar_xm_set_max_loop_count(xm, 0); // Set infinite number of loops
    const frameCount: c_uint = @truncate(jar_xm_get_remaining_samples(xm)); // NOTE: Always 2 channels (stereo)
    jar_xm_reset(xm); // Make sure to start at the beginning of the song

    // AUDIO_DEVICE_FORMAT is ma_format_f32 in this build -> 32 bit; only stereo is supported
    return .{ .format = .xm, .ctx = xm, .sampleRate = rate, .sampleSize = 32, .channels = 2, .frameCount = frameCount };
}

fn openModMusic(source: MusicSource) ?MusicDecoder {
    const mod = switch (source) {
        .file => |path| openModFile(path),
        // The whole load-from-memory sequence (context alloc, data copy, modfile
        // wiring, jar_mod_load, failure cleanup) is replicated verbatim in the shim:
        // jar_mod_load is static upstream and the sequence writes context fields
        .memory => |memory| rl_jar_mod_load_memory(memory.data, memory.size),
    } orelse return null;

    // NOTE: Only stereo is supported for MOD
    return .{
        .format = .mod,
        .ctx = mod,
        .sampleRate = AUDIO.system.deviceSampleRate,
        .sampleSize = 16,
        .channels = 2,
        .frameCount = @truncate(jar_mod_max_samples(mod)), // NOTE: Always 2 channels (stereo)
    };
}

fn openModFile(path: [*:0]const u8) ?*JarModContext {
    const mod = allocDecoder(JarModContext, rl_sizeof_jar_mod_context()) orelse return null;
    _ = jar_mod_init(mod);
    // C stores the unsigned long result in an int
    const result: c_int = @bitCast(@as(c_uint, @truncate(jar_mod_load_file(mod, path))));
    if (result > 0) return mod;

    jar_mod_unload(mod);
    cmem.free(mod);
    return null;
}

// Check if music stream is valid (context and buffers initialized)
export fn IsMusicValid(music: Music) bool {
    return (music.ctxData != null) and // Validate context loaded
        (music.frameCount > 0) and // Validate audio frame count
        (music.stream.sampleRate > 0) and // Validate sample rate is supported
        (music.stream.sampleSize > 0) and // Validate sample size is supported
        (music.stream.channels > 0); // Validate number of channels supported
}

// Unload music stream
export fn UnloadMusicStream(music: Music) void {
    if (IsMusicStreamPlaying(music)) StopMusicStream(music);

    UnloadAudioStream(music.stream);

    const ctx = music.ctxData orelse return;
    switch (AudioFormat.of(music)) {
        .wav => {
            _ = drwav_uninit(@ptrCast(ctx));
            cmem.free(ctx);
        },
        .ogg => stb_vorbis_close(@ptrCast(ctx)),
        .mp3 => {
            drmp3_uninit(@ptrCast(ctx));
            cmem.free(ctx);
        },
        .qoa => qoaplay_close(@ptrCast(ctx)),
        .xm => jar_xm_free_context(@ptrCast(ctx)),
        .mod => {
            jar_mod_unload(@ptrCast(ctx));
            cmem.free(ctx);
        },
        .flac, _ => {},
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
    rewindMusic(music);
}

/// Seeks a music decoder back to its first frame
fn rewindMusic(music: Music) void {
    const ctx = music.ctxData;
    switch (AudioFormat.of(music)) {
        .wav => _ = rl_drwav_seek_to_first_pcm_frame(@ptrCast(ctx)),
        .ogg => _ = stb_vorbis_seek_start(@ptrCast(ctx)),
        .mp3 => _ = rl_drmp3_seek_to_start_of_stream(@ptrCast(ctx)),
        .qoa => qoaplay_rewind(@ptrCast(ctx)),
        .xm => jar_xm_reset(@ptrCast(ctx)),
        .mod => jar_mod_seek_start(@ptrCast(ctx)),
        .flac, _ => {},
    }
}

// Seek music to a certain position (in seconds)
export fn SeekMusicStream(music: Music, position: f32) void {
    // Seeking is not supported in module formats
    const format = AudioFormat.of(music);
    if (format == .xm or format == .mod) return;

    const ctx = music.ctxData;
    var positionInFrames: c_uint = @intFromFloat(position * @as(f32, @floatFromInt(music.stream.sampleRate)));

    switch (format) {
        .xm, .mod => unreachable,
        .wav => _ = drwav_seek_to_pcm_frame(@ptrCast(ctx), positionInFrames),
        .ogg => _ = stb_vorbis_seek_frame(@ptrCast(ctx), positionInFrames),
        .mp3 => _ = drmp3_seek_to_pcm_frame(@ptrCast(ctx), positionInFrames),
        .qoa => {
            // Seeks to QOA frame, not PCM frame, then reports the position it reached
            qoaplay_seek_frame(@ptrCast(ctx), @bitCast(positionInFrames / QOA_FRAME_LEN));
            positionInFrames = rl_qoaplay_sample_position(@ptrCast(ctx));
        },
        .flac, _ => {},
    }

    const buffer = music.stream.buffer.?;
    lockAudio();
    defer unlockAudio();
    buffer.framesProcessed = positionInFrames;
    buffer.isSubBufferProcessed = .{ true, true };
}

// Update (re-fill) music buffers if data already processed
export fn UpdateMusicStream(music: Music) void {
    const buffer = music.stream.buffer orelse return;
    if (!buffer.playing) return;

    lockAudio();
    const finished = refillMusicBuffers(music, buffer);
    unlockAudio();

    // Outside the lock: StopMusicStream takes it again
    if (finished) StopMusicStream(music);
}

/// Refills the processed halves of a music stream's buffer. Returns true when
/// the music has no frames left and both halves have played.
fn refillMusicBuffers(music: Music, buffer: *AudioBuffer) bool {
    const subBufferSizeInFrames = buffer.sizeInFrames / 2;

    // On first call of this function, lazily pre-allocate a temp buffer to read audio files/memory data in
    const frameSize: c_int = @bitCast(music.stream.channels *% music.stream.sampleSize / 8);
    const pcm = pcmBuffer(subBufferSizeInFrames *% @as(c_uint, @bitCast(frameSize))) catch return false;

    // Check both sub-buffers to check if they require refilling
    for (0..2) |i| {
        const framesLeft = music.frameCount -% buffer.framesProcessed; // Frames left to be processed
        const framesToStream = if (framesLeft >= subBufferSizeInFrames or music.looping) subBufferSizeInFrames else framesLeft;

        if (framesToStream == 0) return buffer.isSubBufferProcessed[0] and buffer.isSubBufferProcessed[1];
        if (!buffer.isSubBufferProcessed[i]) continue; // No refilling required, move to next sub-buffer

        decodeMusic(music, pcm, frameSize, framesToStream);
        updateAudioStreamInLockedState(music.stream, pcm.ptr, @bitCast(framesToStream));
    }
    return false;
}

/// The decode buffer shared by all music streams, grown (never shrunk) to at
/// least `size` zeroed bytes
fn pcmBuffer(size: usize) error{OutOfMemory}![]u8 {
    if (AUDIO.system.pcmBuffer.len < size) {
        c_allocator.free(AUDIO.system.pcmBuffer);
        AUDIO.system.pcmBuffer = &.{};
        const grown = try c_allocator.alloc(u8, size);
        @memset(grown, 0);
        AUDIO.system.pcmBuffer = grown;
    }
    return AUDIO.system.pcmBuffer;
}

/// Decodes `frames` frames of music into `pcm`
fn decodeMusic(music: Music, pcm: []u8, frameSize: c_int, frames: c_uint) void {
    const ctx = music.ctxData;
    switch (AudioFormat.of(music)) {
        .wav => switch (music.stream.sampleSize) {
            16 => decodeLooping(i16, pcm, frameSize, frames, WavStream{ .wav = @ptrCast(ctx) }),
            32 => decodeLooping(f32, pcm, frameSize, frames, WavStream{ .wav = @ptrCast(ctx) }),
            else => {},
        },
        .ogg => decodeLooping(i16, pcm, frameSize, frames, OggStream{ .ogg = @ptrCast(ctx), .channels = music.stream.channels }),
        .mp3 => decodeLooping(f32, pcm, frameSize, frames, Mp3Stream{ .mp3 = @ptrCast(ctx) }),
        .qoa => _ = qoaplay_decode(@ptrCast(ctx), samplesAt(f32, pcm), @bitCast(frames)),
        // NOTE: Internally considering 2 channels generation; AUDIO_DEVICE_FORMAT is f32
        .xm => jar_xm_generate_samples(@ptrCast(ctx), samplesAt(f32, pcm), frames),
        // NOTE: nbsample is the number of stereo 16bits samples desired
        .mod => jar_mod_fillbuffer(@ptrCast(ctx), samplesAt(i16, pcm), frames, null),
        .flac, _ => {},
    }
}

/// Decodes `frames` frames into `pcm`, rewinding the decoder each time its
/// data runs out: streamed music loops at the decoder too
fn decodeLooping(comptime Sample: type, pcm: []u8, frameSize: c_int, frames: c_uint, stream: anytype) void {
    var stillNeeded: c_int = @bitCast(frames);
    var readTotal: c_int = 0;
    while (true) {
        const read = stream.read(samplesAt(Sample, pcm[@intCast(readTotal * frameSize)..]), stillNeeded);
        readTotal += read;
        stillNeeded -= read;
        if (stillNeeded == 0) break;
        stream.rewind();
    }
}

const WavStream = struct {
    wav: *DrWav,

    fn read(s: WavStream, out: anytype, frames: c_int) c_int {
        const n = switch (@TypeOf(out)) {
            [*]i16 => drwav_read_pcm_frames_s16(s.wav, cU64(frames), out),
            [*]f32 => drwav_read_pcm_frames_f32(s.wav, cU64(frames), out),
            else => @compileError("dr_wav streams s16 or f32"),
        };
        return @bitCast(@as(c_uint, @truncate(n)));
    }

    fn rewind(s: WavStream) void {
        _ = rl_drwav_seek_to_first_pcm_frame(s.wav);
    }
};

const OggStream = struct {
    ogg: *StbVorbis,
    channels: c_uint,

    fn read(s: OggStream, out: [*]i16, frames: c_int) c_int {
        // Asks for shorts, returns frames
        const shorts: c_int = @bitCast(@as(c_uint, @bitCast(frames)) *% s.channels);
        return stb_vorbis_get_samples_short_interleaved(s.ogg, @bitCast(s.channels), out, shorts);
    }

    fn rewind(s: OggStream) void {
        _ = stb_vorbis_seek_start(s.ogg);
    }
};

const Mp3Stream = struct {
    mp3: *DrMp3,

    fn read(s: Mp3Stream, out: [*]f32, frames: c_int) c_int {
        return @bitCast(@as(c_uint, @truncate(drmp3_read_pcm_frames_f32(s.mp3, cU64(frames), out))));
    }

    fn rewind(s: Mp3Stream) void {
        _ = rl_drmp3_seek_to_start_of_stream(s.mp3);
    }
};

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
    const buffer = music.stream.buffer orelse return 0.0;
    const sampleRate: f32 = @floatFromInt(music.stream.sampleRate);

    if (SUPPORT_FILEFORMAT_XM and AudioFormat.of(music) == .xm) {
        var framesPlayed: u64 = 0;
        jar_xm_get_position(@ptrCast(music.ctxData), null, null, null, &framesPlayed);
        return @as(f32, @floatFromInt(framesPlayed)) / sampleRate;
    }

    lockAudio();
    defer unlockAudio();
    // C's int arithmetic, conversions included (raudio.c:2107-2115)
    const framesProcessed: c_int = @bitCast(buffer.framesProcessed);
    const subBufferSize: c_int = @divTrunc(@as(c_int, @bitCast(buffer.sizeInFrames)), 2);
    const framesInFirstBuffer: c_int = if (buffer.isSubBufferProcessed[0]) 0 else subBufferSize;
    const framesInSecondBuffer: c_int = if (buffer.isSubBufferProcessed[1]) 0 else subBufferSize;
    var framesInBuffers: c_int = framesInFirstBuffer + framesInSecondBuffer;
    if ((@as(c_uint, @bitCast(framesInBuffers)) > music.frameCount) and !music.looping) framesInBuffers = @bitCast(music.frameCount);
    const framesSentToMix: c_int = @bitCast(buffer.frameCursorPos % @as(c_uint, @bitCast(subBufferSize)));
    var framesPlayed: c_int = @rem(framesProcessed - framesInBuffers + framesSentToMix, @as(c_int, @bitCast(music.frameCount)));
    if (framesPlayed < 0) framesPlayed = @bitCast(@as(c_uint, @bitCast(framesPlayed)) +% music.frameCount);
    return @as(f32, @floatFromInt(framesPlayed)) / sampleRate;
}

// Load audio stream (to stream audio pcm data)
export fn LoadAudioStream(sampleRate: c_uint, sampleSize: c_uint, channels: c_uint) AudioStream {
    // The size of a streaming buffer must be at least double the size of a period
    const periodSize = AUDIO.system.playbackInternalPeriodSizeInFrames;

    // If the buffer is not set, compute one that would give us a buffer good enough for a decent frame rate at the device bit size/rate
    // Deliberate: raylib uses the ma_format value (capped at 4) as the bytes per sample
    const deviceBytesPerFrame = @as(c_uint, @bitCast(@min(AUDIO.system.playbackFormat, 4))) *% AUDIO.system.playbackChannels;
    var subBufferSize: c_uint = if (AUDIO.defaultBufferSize == 0)
        AUDIO.system.deviceSampleRate / 30 *% deviceBytesPerFrame
    else
        @bitCast(AUDIO.defaultBufferSize);
    if (subBufferSize < periodSize) subBufferSize = periodSize;

    // Create a double audio buffer of defined size
    const buffer = LoadAudioBuffer(sampleFormat(sampleSize), channels, sampleRate, subBufferSize *% 2, @backingInt(BufferUsage.stream));

    const stream: AudioStream = .{ .buffer = buffer, .processor = null, .sampleRate = sampleRate, .sampleSize = sampleSize, .channels = channels };
    if (buffer) |b| {
        b.looping = true; // Always loop for streaming buffers
        const channelsText: [*:0]const u8 = if (channels == 1) "Mono" else "Stereo";
        TraceLog(LOG_INFO, "STREAM: Initialized successfully (%i Hz, %i bit, %s)", sampleRate, sampleSize, channelsText);
    } else TraceLog(LOG_WARNING, "STREAM: Failed to load audio buffer, stream could not be created");

    return stream;
}

// Check if an audio stream is valid (buffers initialized)
export fn IsAudioStreamValid(stream: AudioStream) bool {
    return (stream.buffer != null) and // Validate stream buffer
        (stream.sampleRate > 0) and // Validate sample rate is supported
        (stream.sampleSize > 0) and // Validate sample size is supported
        (stream.channels > 0); // Validate number of channels supported
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
    defer unlockAudio();
    updateAudioStreamInLockedState(stream, data, frameCount);
}

// Check if any audio stream buffers requires refill
export fn IsAudioStreamProcessed(stream: AudioStream) bool {
    const buffer = stream.buffer orelse return false;
    lockAudio();
    defer unlockAudio();
    return buffer.isSubBufferProcessed[0] or buffer.isSubBufferProcessed[1];
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
    AUDIO.defaultBufferSize = size;
}

// Audio thread callback to request new data
export fn SetAudioStreamCallback(stream: AudioStream, callback: AudioCallback) void {
    const buffer = stream.buffer orelse return;
    lockAudio();
    defer unlockAudio();
    buffer.callback = callback;
}

// Add processor to audio stream. Contrary to buffers, the order of processors is important
// The new processor must be added at the end, iterating through the list to find it
export fn AttachAudioStreamProcessor(stream: AudioStream, process: AudioCallback) void {
    lockAudio();
    defer unlockAudio();
    attachProcessor(&stream.buffer.?.processors, process);
}

// Remove processor from audio stream
export fn DetachAudioStreamProcessor(stream: AudioStream, process: AudioCallback) void {
    lockAudio();
    defer unlockAudio();
    detachProcessors(&stream.buffer.?.processors, process);
}

// Add processor to audio pipeline. Order of processors is important
// Works the same way as {Attach,Detach}AudioStreamProcessor() functions, except
// these two work on the already mixed output before sending it to the sound hardware
export fn AttachAudioMixedProcessor(process: AudioCallback) void {
    lockAudio();
    defer unlockAudio();
    attachProcessor(&AUDIO.mixedProcessors, process);
}

// Remove processor from audio pipeline
export fn DetachAudioMixedProcessor(process: AudioCallback) void {
    lockAudio();
    defer unlockAudio();
    detachProcessors(&AUDIO.mixedProcessors, process);
}

/// Appends a processor to a list, assuming the audio system mutex is locked.
/// As raylib, an allocation failure is not reported.
fn attachProcessor(list: *DoublyLinkedList, process: AudioCallback) void {
    const processor = c_allocator.create(AudioProcessor) catch return;
    processor.* = .{ .process = process };
    list.append(&processor.node);
}

/// Removes every processor running `process`, assuming the audio system mutex is locked
fn detachProcessors(list: *DoublyLinkedList, process: AudioCallback) void {
    var it = list.first;
    while (it) |node| {
        it = node.next;
        const processor = AudioProcessor.fromNode(node);
        if (processor.process == process) {
            list.remove(node);
            c_allocator.destroy(processor);
        }
    }
}

/// Runs a processor chain over `frames`, assuming the audio system mutex is locked
fn runProcessors(list: DoublyLinkedList, frames: ?*anyopaque, frameCount: c_uint) void {
    var it = list.first;
    while (it) |node| : (it = node.next) {
        AudioProcessor.fromNode(node).process.?(frames, frameCount);
    }
}

//----------------------------------------------------------------------------------
// Module Internal Functions Definition
// The mixing functions below run on miniaudio's audio thread: no allocation,
// no logging that raudio.c doesn't do there.
//----------------------------------------------------------------------------------

// Log callback function (built-and-discarded by the shim, matching raudio.c:469)
fn onLog(userData: ?*anyopaque, level: c_uint, message: [*:0]const u8) callconv(.c) void {
    _ = userData;
    _ = level;
    TraceLog(LOG_WARNING, "miniaudio: %s", message); // All log messages from miniaudio are errors
}

// Reads audio data from an AudioBuffer object in internal format
fn readAudioBufferFramesInInternalFormat(audioBuffer: *AudioBuffer, framesOut: []u8, frameCount: c_uint) c_uint {
    // Don't read anything if the sound is not playing
    if (!audioBuffer.playing) return 0;

    // Using audio buffer callback
    if (audioBuffer.callback) |callback| {
        callback(framesOut.ptr, frameCount);
        audioBuffer.framesProcessed +%= frameCount;
        return frameCount;
    }

    const subBufferSizeInFrames: c_uint = if (audioBuffer.sizeInFrames > 1) audioBuffer.sizeInFrames / 2 else audioBuffer.sizeInFrames;
    var currentSubBufferIndex: c_uint = audioBuffer.frameCursorPos / subBufferSizeInFrames;
    if (currentSubBufferIndex > 1) return 0;

    // Another thread can update the processed state of buffers, so
    // take a copy here to try and avoid potential synchronization problems
    var isSubBufferProcessed = audioBuffer.isSubBufferProcessed;

    const frameSize = audioBuffer.bytesPerFrame();

    // Fill out every frame until a buffer that's marked as processed is found, then fill the remainder with 0
    var framesRead: c_uint = 0;
    while (true) {
        // Break from this loop differently depending on the buffer's usage
        //  - For static buffers, simply fill as much data as possible
        //  - For streaming buffers, only fill half of the buffer that are processed
        //    Unprocessed halves must keep their audio data in-tact
        if (audioBuffer.usage == .static) {
            if (framesRead >= frameCount) break;
        } else {
            if (isSubBufferProcessed[currentSubBufferIndex]) break;
        }

        const totalFramesRemaining = frameCount -% framesRead;
        if (totalFramesRemaining == 0) break;

        const framesRemainingInOutputBuffer: c_uint = if (audioBuffer.usage == .static)
            audioBuffer.sizeInFrames -% audioBuffer.frameCursorPos
        else
            subBufferSizeInFrames -% (audioBuffer.frameCursorPos -% subBufferSizeInFrames *% currentSubBufferIndex);

        const framesToRead = @min(totalFramesRemaining, framesRemainingInOutputBuffer);

        const len = framesToRead *% frameSize;
        const source = audioBuffer.data.?[audioBuffer.frameCursorPos *% frameSize ..][0..len];
        @memcpy(framesOut[framesRead *% frameSize ..][0..len], source);
        audioBuffer.frameCursorPos = (audioBuffer.frameCursorPos +% framesToRead) % audioBuffer.sizeInFrames;
        framesRead +%= framesToRead;

        // If the end of the buffer is read, mark it as processed
        if (framesToRead == framesRemainingInOutputBuffer) {
            audioBuffer.isSubBufferProcessed[currentSubBufferIndex] = true;
            isSubBufferProcessed[currentSubBufferIndex] = true;

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
        @memset(framesOut[framesRead *% frameSize ..][0 .. totalFramesRemaining *% frameSize], 0);

        // For static buffers, fill the remaining frames with silence for safety, but don't report those
        // frames as "read"; the caller uses the return value to know whether a
        // non-looping sound has finished playback
        if (audioBuffer.usage != .static) framesRead +%= totalFramesRemaining;
    }

    return framesRead;
}

// Reads audio data from an AudioBuffer object in device format, returned data will be in a format appropriate for mixing
fn readAudioBufferFramesInMixingFormat(audioBuffer: *AudioBuffer, framesOut: []f32, frameCount: c_uint) c_uint {
    // NOTE: Continuously converting data from the AudioBuffer's internal format to the mixing format,
    // which should be defined by the output format of the data converter,
    // until frameCount frames have been output
    const frameSize = audioBuffer.bytesPerFrame();
    var inputBuffer: [4096]u8 = @splat(0);
    const inputBufferFrameCap: c_uint = @intCast(inputBuffer.len / frameSize);
    const residual = audioBuffer.converterResidual;

    var totalOutputFramesProcessed: c_uint = 0;
    while (totalOutputFramesProcessed < frameCount) {
        const runningFramesOut = framesOut[totalOutputFramesProcessed *% audioBuffer.channelsOut ..];
        const outputFramesToProcessThisIteration: u64 = frameCount - totalOutputFramesProcessed;

        // Process any residual input frames from the previous read first
        if (audioBuffer.converterResidualCount > 0) {
            var inputFramesProcessedThisIteration: u64 = audioBuffer.converterResidualCount;
            var outputFramesProcessedThisIteration: u64 = outputFramesToProcessThisIteration;
            _ = ma_data_converter_process_pcm_frames(audioBuffer.converter, residual.ptr, &inputFramesProcessedThisIteration, runningFramesOut.ptr, &outputFramesProcessedThisIteration);

            // Make sure the data in the cache is consumed
            const consumed: usize = @intCast(inputFramesProcessedThisIteration *% frameSize);
            std.mem.copyForwards(u8, residual, residual[consumed..]);
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
            _ = ma_data_converter_process_pcm_frames(audioBuffer.converter, &inputBuffer, &inputFramesProcessedThisIteration, runningFramesOut.ptr, &outputFramesProcessedThisIteration);

            totalOutputFramesProcessed +%= @truncate(outputFramesProcessedThisIteration);

            if (inputFramesInInternalFormatCount > inputFramesProcessedThisIteration) {
                // The estimated input frame count was overestimated:
                // the residual needs to be stored for later use, within the cache's capacity
                const residualFrameCount = @min(inputFramesInInternalFormatCount - inputFramesProcessedThisIteration, AUDIO_BUFFER_RESIDUAL_CAPACITY);

                const start: usize = @intCast(inputFramesProcessedThisIteration *% frameSize);
                const len: usize = @intCast(residualFrameCount *% frameSize);
                @memcpy(residual[0..len], inputBuffer[start..][0..len]);
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

    const channels = AUDIO.system.playbackChannels;
    const outputBytes: [*]u8 = @ptrCast(framesOutOpaque.?);
    const outputSamples: [*]f32 = @ptrCast(@alignCast(outputBytes));

    // Mixing is basically an accumulation, need to initialize the output buffer to 0
    @memset(outputBytes[0 .. frameCount *% channels *% ma_get_bytes_per_sample(AUDIO.system.playbackFormat)], 0);

    // Using a mutex here for thread-safety which makes things not real-time;
    // this is unlikely to be necessary for this project, but it can be reconsidered
    lockAudio();
    defer unlockAudio();

    var it = AUDIO.buffers.first;
    while (it) |node| : (it = node.next) {
        const audioBuffer = AudioBuffer.fromNode(node);

        // Ignore stopped or paused sounds
        if (!audioBuffer.playing or audioBuffer.paused) continue;

        var framesRead: c_uint = 0;
        while (framesRead < frameCount) {
            // Read as much data as possible from the stream
            var framesToRead = frameCount -% framesRead;

            while (framesToRead > 0) {
                var tempBuffer: [1024]f32 = @splat(0); // Frames for stereo
                const framesToReadRightNow = @min(framesToRead, tempBuffer.len / AUDIO_DEVICE_CHANNELS);

                const framesJustRead = readAudioBufferFramesInMixingFormat(audioBuffer, &tempBuffer, framesToReadRightNow);
                if (framesJustRead > 0) {
                    // Apply processors chain if defined
                    runProcessors(audioBuffer.processors, &tempBuffer, framesJustRead);

                    const samples = framesJustRead *% channels;
                    mixAudioFrames(outputSamples[framesRead *% channels ..][0..samples], tempBuffer[0..samples], audioBuffer);

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
                    }
                    // Should never get here, but for safety,
                    // move the cursor position back to the start and continue the loop
                    audioBuffer.frameCursorPos = 0;
                }
            }

            // If for some reason is not possible to read every frame, the loop needs to be broken
            // Not doing this could theoretically end up into an infinite loop
            if (framesToRead > 0) break;
        }
    }

    runProcessors(AUDIO.mixedProcessors, framesOutOpaque, frameCount);
}

// Main mixing function, pretty simple in this project, only an accumulation
// NOTE: framesOut is both an input and an output, it is initially filled with zeros outside of this function
fn mixAudioFrames(framesOut: []f32, framesIn: []const f32, buffer: *const AudioBuffer) void {
    const localVolume = buffer.volume;

    if (AUDIO.system.playbackChannels == 2) { // Consider panning
        const right = (buffer.pan + 1.0) / 2.0; // Normalize: [-1..1] -> [0..1]
        const left = 1.0 - right;

        // Fast sine approximation in [0..1] for pan law: y = 0.5f*x*(3 - x*x);
        const levels = [2]f32{ localVolume * 0.5 * left * (3.0 - left * left), localVolume * 0.5 * right * (3.0 - right * right) };

        var frame: usize = 0;
        while (frame < framesOut.len) : (frame += 2) {
            framesOut[frame] += framesIn[frame] * levels[0];
            framesOut[frame + 1] += framesIn[frame + 1] * levels[1];
        }
    } else { // Do not consider panning
        // Output accumulates input multiplied by volume to provided output (usually 0)
        for (framesOut, framesIn) |*out, in| out.* += in * localVolume;
    }
}

// Check if an audio buffer is playing, assuming the audio system mutex has been locked
fn isAudioBufferPlayingInLockedState(buffer: ?*AudioBuffer) bool {
    const b = buffer orelse return false;
    return b.playing and !b.paused;
}

// Stop an audio buffer, assuming the audio system mutex has been locked
fn stopAudioBufferInLockedState(buffer: ?*AudioBuffer) void {
    const b = buffer orelse return;
    if (!isAudioBufferPlayingInLockedState(b)) return;

    b.playing = false;
    b.paused = false;
    b.frameCursorPos = 0;
    b.framesProcessed = 0;
    b.isSubBufferProcessed = .{ true, true };
}

// Update audio stream, assuming the audio system mutex has been locked
fn updateAudioStreamInLockedState(stream: AudioStream, data: ?*const anyopaque, frameCount: c_int) void {
    const buffer = stream.buffer orelse return;

    if (!buffer.isSubBufferProcessed[0] and !buffer.isSubBufferProcessed[1]) {
        TraceLog(LOG_WARNING, "STREAM: Buffer not available for updating");
        return;
    }

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

    const subBufferSizeInFrames = buffer.sizeInFrames / 2;
    const frameSize = stream.channels *% (stream.sampleSize / 8);
    const subBufferBytes = subBufferSizeInFrames *% frameSize;
    const framesToWrite: c_uint = @bitCast(frameCount);

    buffer.framesProcessed +%= framesToWrite;

    // Does this API expect a whole buffer to be updated in one go?
    // Assuming so, but if not will need to change this logic
    if (subBufferSizeInFrames < framesToWrite) {
        TraceLog(LOG_WARNING, "STREAM: Attempting to write too many frames to buffer");
        return;
    }

    const subBuffer = buffer.data.?[subBufferBytes *% subBufferToUpdate ..][0..subBufferBytes];
    const bytesToWrite = framesToWrite *% frameSize;
    @memcpy(subBuffer[0..bytesToWrite], bytesAt(data, bytesToWrite));

    // Any leftover frames should be filled with zeros
    @memset(subBuffer[bytesToWrite..], 0);

    buffer.isSubBufferProcessed[subBufferToUpdate] = false;
}
