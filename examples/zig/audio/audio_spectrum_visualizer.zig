//! raylib [audio] example - spectrum visualizer
//!
//! Zig-API translation of examples/audio/audio_spectrum_visualizer.c (raylib 6.2).
//! Inspired by Inigo Quilez's https://www.shadertoy.com/
//! Resources/specification: https://gist.github.com/soulthreads/2efe50da4be1fb5f7ab60ff14ca434b8
//! Example created by created by IANN (@meisei4) reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 IANN (@meisei4)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

const mono = 1;
const sample_rate = 44100;
const sample_rate_f: f32 = 44100.0;
const fft_window_size = 1024;
const buffer_size = 512;
const per_sample_bit_depth = 16;
const audio_stream_ring_buffer_size = fft_window_size * 2;
const effective_sample_rate: f32 = sample_rate_f * 0.5;
const window_time: f64 = @as(f64, fft_window_size) / @as(f64, effective_sample_rate);
const fft_historical_smoothing_dur: f32 = 2.0;
const min_decibels: f32 = -100.0; // https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/minDecibels
const max_decibels: f32 = -30.0; // https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/maxDecibels
const inverse_decibel_range: f32 = 1.0 / (max_decibels - min_decibels);
const db_to_linear_scale: f32 = 20.0 / @as(f32, 2.302585092994046);
const smoothing_time_constant: f32 = 0.8; // https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/smoothingTimeConstant
const texture_height = 1;
const fft_row = 0;
const unused_channel: f32 = 0.0;

const fft_history_len: comptime_int = @as(i32, @intFromFloat(@ceil(@as(f32, @floatCast(fft_historical_smoothing_dur / window_time))))) + 1;

const FftComplex = struct { real: f32, imaginary: f32 };

const FftData = struct {
    spectrum: [fft_window_size]FftComplex = @splat(.{ .real = 0, .imaginary = 0 }),
    work_buffer: [fft_window_size]FftComplex = @splat(.{ .real = 0, .imaginary = 0 }),
    prev_magnitudes: [buffer_size]f32 = @splat(0),
    fft_history: [fft_history_len][buffer_size]f32 = @splat(@splat(0)),
    history_pos: usize = 0,
    last_fft_time: f64 = 0.0,
    tapback_pos: f32 = 0.01,
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [audio] example - spectrum visualizer");
    defer rl.closeWindow(); // Close window and OpenGL context

    var fft_image = rl.genImageColor(buffer_size, texture_height, .white);
    defer rl.unloadImage(fft_image);
    const fft_texture = try rl.loadTextureFromImage(fft_image);
    defer rl.unloadTexture(fft_texture);
    const buffer_a = try rl.loadRenderTexture(screen_width, screen_height);
    defer rl.unloadRenderTexture(buffer_a);
    const i_resolution: rl.Vector2 = .{ .x = screen_width, .y = screen_height };

    const shader = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/fft.fs", .{glsl_version}));
    defer rl.unloadShader(shader);

    const i_resolution_location = rl.getShaderLocation(shader, "iResolution");
    const i_channel0_location = rl.getShaderLocation(shader, "iChannel0");
    rl.setShaderValue(shader, i_resolution_location, i_resolution);
    rl.setShaderValueTexture(shader, i_channel0_location, fft_texture);

    rl.initAudioDevice();
    defer rl.closeAudioDevice();
    rl.setAudioStreamBufferSizeDefault(audio_stream_ring_buffer_size);

    var wav = try rl.loadWave("resources/country.mp3");
    defer rl.unloadWave(wav);
    rl.waveFormat(&wav, sample_rate, per_sample_bit_depth, mono);

    const audio_stream = try rl.loadAudioStream(sample_rate, per_sample_bit_depth, mono);
    defer rl.unloadAudioStream(audio_stream);
    rl.playAudioStream(audio_stream);

    var fft: FftData = .{};

    const wav_pcm16 = @as([*]const i16, @ptrCast(@alignCast(wav.data.?)))[0 .. wav.frameCount * wav.channels];
    var wav_cursor: usize = 0;

    var chunk_samples: [audio_stream_ring_buffer_size]i16 = @splat(0);
    var audio_samples: [fft_window_size]f32 = @splat(0);

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        while (rl.isAudioStreamProcessed(audio_stream)) {
            for (&chunk_samples) |*sample| {
                const left: i32 = if (wav.channels == 2) wav_pcm16[wav_cursor * 2 + 0] else wav_pcm16[wav_cursor];
                const right: i32 = if (wav.channels == 2) wav_pcm16[wav_cursor * 2 + 1] else left;
                sample.* = @intCast(@divTrunc(left + right, 2));

                wav_cursor += 1;
                if (wav_cursor >= wav.frameCount) wav_cursor = 0;
            }

            rl.updateAudioStream(audio_stream, &chunk_samples, audio_stream_ring_buffer_size);

            for (&audio_samples, 0..) |*sample, i| {
                const sum: f32 = @floatFromInt(@as(i32, chunk_samples[i * 2]) + chunk_samples[i * 2 + 1]);
                sample.* = sum * 0.5 / 32767.0;
            }
        }

        captureFrame(&fft, &audio_samples);
        renderFrame(&fft, &fft_image);
        rl.updateTexture(fft_texture, fft_image.data.?);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginShaderMode(shader);
            defer rl.endShaderMode();

            rl.setShaderValueTexture(shader, i_channel0_location, fft_texture);
            rl.drawTextureRec(
                buffer_a.texture,
                .{ .x = 0, .y = 0, .width = screen_width, .height = -screen_height },
                .{ .x = 0, .y = 0 },
                .white,
            );
        }
    }
}

/// Cooley–Tukey FFT https://en.wikipedia.org/wiki/Cooley%E2%80%93Tukey_FFT_algorithm#Data_reordering,_bit_reversal,_and_in-place_algorithms
fn cooleyTukeyFftSlow(spectrum: []FftComplex) void {
    const n = spectrum.len;

    var j: usize = 0;
    for (1..n - 1) |i| {
        var bit = n >> 1;
        while (j >= bit) {
            j -= bit;
            bit >>= 1;
        }
        j += bit;
        if (i < j) std.mem.swap(FftComplex, &spectrum[i], &spectrum[j]);
    }

    var len: usize = 2;
    while (len <= n) : (len <<= 1) {
        const angle = -2.0 * rl.pi / @as(f32, @floatFromInt(len));
        const twiddle_unit: FftComplex = .{ .real = @cos(angle), .imaginary = @sin(angle) };
        const half = len / 2;
        var i: usize = 0;
        while (i < n) : (i += len) {
            var twiddle_current: FftComplex = .{ .real = 1.0, .imaginary = 0.0 };
            for (spectrum[i..][0..half], spectrum[i + half ..][0..half]) |*even_slot, *odd_slot| {
                const even = even_slot.*;
                const odd = odd_slot.*;
                const twiddled_odd: FftComplex = .{
                    .real = odd.real * twiddle_current.real - odd.imaginary * twiddle_current.imaginary,
                    .imaginary = odd.real * twiddle_current.imaginary + odd.imaginary * twiddle_current.real,
                };

                even_slot.* = .{ .real = even.real + twiddled_odd.real, .imaginary = even.imaginary + twiddled_odd.imaginary };
                odd_slot.* = .{ .real = even.real - twiddled_odd.real, .imaginary = even.imaginary - twiddled_odd.imaginary };

                const t = twiddle_current;
                twiddle_current = .{
                    .real = t.real * twiddle_unit.real - t.imaginary * twiddle_unit.imaginary,
                    .imaginary = t.real * twiddle_unit.imaginary + t.imaginary * twiddle_unit.real,
                };
            }
        }
    }
}

fn captureFrame(fft_data: *FftData, audio_samples: *const [fft_window_size]f32) void {
    for (&fft_data.work_buffer, audio_samples, 0..) |*bin, sample, i| {
        const x = (2.0 * rl.pi * @as(f32, @floatFromInt(i))) / (fft_window_size - 1.0);
        const blackman_weight = 0.42 - 0.5 * @cos(x) + 0.08 * @cos(2.0 * x); // https://en.wikipedia.org/wiki/Window_function#Blackman_window
        bin.* = .{ .real = sample * blackman_weight, .imaginary = 0.0 };
    }

    cooleyTukeyFftSlow(&fft_data.work_buffer);
    fft_data.spectrum = fft_data.work_buffer;

    var smoothed_spectrum: [buffer_size]f32 = undefined;

    for (&smoothed_spectrum, &fft_data.prev_magnitudes, fft_data.work_buffer[0..buffer_size]) |*smoothed, *prev_magnitude, bin| {
        const linear_magnitude = @sqrt(bin.real * bin.real + bin.imaginary * bin.imaginary) / fft_window_size;

        const smoothed_magnitude = smoothing_time_constant * prev_magnitude.* + (1.0 - smoothing_time_constant) * linear_magnitude;
        prev_magnitude.* = smoothed_magnitude;

        const db = @log(@max(smoothed_magnitude, 1e-40)) * db_to_linear_scale;
        const normalized = (db - min_decibels) * inverse_decibel_range;
        smoothed.* = rl.math.clamp(normalized, 0.0, 1.0);
    }

    fft_data.last_fft_time = rl.getTime();
    fft_data.fft_history[fft_data.history_pos] = smoothed_spectrum;
    fft_data.history_pos = (fft_data.history_pos + 1) % fft_history_len;
}

fn renderFrame(fft_data: *const FftData, fft_image: *rl.Image) void {
    var frames_since_tapback = @floor(@as(f32, @floatCast(fft_data.tapback_pos / window_time)));
    frames_since_tapback = rl.math.clamp(frames_since_tapback, 0.0, fft_history_len - 1);

    const history_len: i32 = fft_history_len;
    var history_position = @rem(@as(i32, @intCast(fft_data.history_pos)) - 1 - @as(i32, @intFromFloat(frames_since_tapback)), history_len);
    if (history_position < 0) history_position += history_len;

    const amplitude = &fft_data.fft_history[@intCast(history_position)];
    for (amplitude, 0..) |value, bin| {
        const color = rl.colorFromNormalized(.{ .x = value, .y = unused_channel, .z = unused_channel, .w = unused_channel });
        rl.imageDrawPixel(fft_image, @intCast(bin), fft_row, color);
    }
}
