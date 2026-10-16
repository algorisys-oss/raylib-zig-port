//! raylib [audio] example - stream callback
//!
//! Zig-API translation of examples/audio/audio_stream_callback.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Dan Hoang (@dan-hoang)
//!
//! The user gets the choice of four waves: sine, square, triangle, and sawtooth.
//! A stream is set up to play to the audio device; the stream is hooked to a
//! callback that generates a wave, determined by the user's choice.

const rl = @import("raylib");

const buffer_size = 4096;
const sample_rate = 44100;

const screen_width = 800;
const screen_height = 450;

/// Wave type
const WaveType = enum {
    sine,
    square,
    triangle,
    sawtooth,

    fn previous(wave_type: WaveType) WaveType {
        return switch (wave_type) {
            .sine => .sawtooth,
            .square => .sine,
            .triangle => .square,
            .sawtooth => .triangle,
        };
    }

    fn next(wave_type: WaveType) WaveType {
        return switch (wave_type) {
            .sine => .square,
            .square => .triangle,
            .triangle => .sawtooth,
            .sawtooth => .sine,
        };
    }

    /// Sample `index` of one period of `wavelength` samples, in [-1..1].
    fn sample(wave_type: WaveType, index: i32, wavelength: i32) f32 {
        const t: f32 = @floatFromInt(index);
        const half = @divTrunc(wavelength, 2);
        return switch (wave_type) {
            .sine => @sin(2 * rl.pi * t / @as(f32, @floatFromInt(wavelength))),
            .square => if (index < half) 1.0 else -1.0,
            .triangle => if (index < half)
                -1 + 2.0 * t / @as(f32, @floatFromInt(half))
            else
                1 - 2.0 * @as(f32, @floatFromInt(index - half)) / @as(f32, @floatFromInt(half)),
            .sawtooth => -1 + 2.0 * t / @as(f32, @floatFromInt(wavelength)),
        };
    }

    /// The stream callback synthesizing this wave type.
    fn callback(wave_type: WaveType) rl.AudioCallback {
        return switch (wave_type) {
            inline else => |comptime_type| Synth(comptime_type).callback,
        };
    }
};

// NOTE: Shared with the audio thread, unsynchronized, as in the C example
var wave_frequency: i32 = 440;
var new_wave_frequency: i32 = 440;
var wave_index: i32 = 0;

// Buffer to keep the last second of uploaded audio,
// part of which will be drawn on the screen
var buffer: [sample_rate]f32 = @splat(0);

fn Synth(comptime wave_type: WaveType) type {
    return struct {
        fn callback(frames_out: ?*anyopaque, frame_count: c_uint) callconv(.c) void {
            const frames = @as([*]f32, @ptrCast(@alignCast(frames_out.?)))[0..frame_count];
            const wavelength = @divTrunc(sample_rate, wave_frequency);

            // Synthesize the wave
            for (frames) |*frame| {
                frame.* = wave_type.sample(wave_index, wavelength);
                wave_index += 1;

                if (wave_index >= wavelength) {
                    wave_frequency = new_wave_frequency;
                    wave_index = 0;
                }
            }

            // Save the synthesized samples for later drawing
            const kept = buffer.len - frames.len;
            @memmove(buffer[0..kept], buffer[frames.len..]);
            @memcpy(buffer[kept..], frames);
        }
    };
}

pub fn main() !void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [audio] example - stream callback");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice();
    defer rl.closeAudioDevice(); // Close audio device (music streaming is automatically stopped)

    // Set the number of samples the stream will keep in memory at a time to buffer_size
    rl.setAudioStreamBufferSizeDefault(buffer_size);

    // Init raw audio stream (sample rate: 44100, sample size: 32bit-float, channels: 1-mono)
    const stream = try rl.loadAudioStream(sample_rate, 32, 1);
    defer rl.unloadAudioStream(stream); // Close raw audio stream and delete buffers from RAM
    rl.playAudioStream(stream);

    // Configure it so that the wave type's callback is called whenever stream is out of samples
    var wave_type: WaveType = .sine;
    rl.setAudioStreamCallback(stream, wave_type.callback());

    rl.setTargetFPS(30);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyDown(.up)) new_wave_frequency = @min(new_wave_frequency + 10, 12500);
        if (rl.isKeyDown(.down)) new_wave_frequency = @max(new_wave_frequency - 10, 20);

        if (rl.isKeyPressed(.left)) {
            wave_type = wave_type.previous();
            rl.setAudioStreamCallback(stream, wave_type.callback());
        }

        if (rl.isKeyPressed(.right)) {
            wave_type = wave_type.next();
            rl.setAudioStreamCallback(stream, wave_type.callback());
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);
        rl.drawText(rl.textFormat("frequency: {d}", .{new_wave_frequency}), screen_width - 220, 10, 20, .red);
        rl.drawText(rl.textFormat("wave type: {t}", .{wave_type}), screen_width - 220, 30, 20, .red);
        rl.drawText("Up/down to change frequency", 10, 10, 20, .dark_gray);
        rl.drawText("Left/right to change wave type", 10, 30, 20, .dark_gray);

        // Draw the last 10 ms of uploaded audio
        for (0..screen_width - 1) |column| {
            const i: i32 = @intCast(column);
            const start_pos: rl.Vector2 = .{ .x = @floatFromInt(i), .y = 250 - 50 * buffer[recentSample(i)] };
            const end_pos: rl.Vector2 = .{ .x = @floatFromInt(i + 1), .y = 250 - 50 * buffer[recentSample(i + 1)] };
            rl.drawLineV(start_pos, end_pos, .red);
        }
    }
}

/// Index into `buffer` of the sample drawn at screen column `i` (the last 10 ms span the screen).
fn recentSample(i: i32) usize {
    return @intCast(sample_rate - sample_rate / 100 + @divTrunc(@divTrunc(i * sample_rate, 100), screen_width));
}
