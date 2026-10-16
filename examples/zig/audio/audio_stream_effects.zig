//! raylib [audio] example - stream effects
//!
//! Zig-API translation of examples/audio/audio_stream_effects.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2022-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

// Delay effect state, shared with the audio thread
var delay_buffer: []f32 = &.{};
var delay_read_index: usize = 2;
var delay_write_index: usize = 0;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [audio] example - stream effects");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Allocate buffer for the delay effect: 1 second delay (device sampleRate*channels)
    // NOTE: Allocated before the audio device so it outlives the processors using it
    const allocator = std.heap.c_allocator;
    delay_buffer = try allocator.alloc(f32, 48000 * 2);
    @memset(delay_buffer, 0.0);
    defer allocator.free(delay_buffer); // Free delay buffer

    rl.initAudioDevice(); // Initialize audio device
    defer rl.closeAudioDevice(); // Close audio device (music streaming is automatically stopped)

    const music = try rl.loadMusicStream("resources/country.mp3");
    defer rl.unloadMusicStream(music); // Unload music stream buffers from RAM

    rl.playMusicStream(music);

    var time_played: f32 = 0.0; // Time played normalized [0.0f..1.0f]
    var pause = false; // Music playing paused

    var enable_effect_lpf = false; // Enable effect low-pass-filter
    var enable_effect_delay = false; // Enable effect delay (1 second)

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateMusicStream(music); // Update music buffer with new stream data

        // Restart music playing (stop and play)
        if (rl.isKeyPressed(.space)) {
            rl.stopMusicStream(music);
            rl.playMusicStream(music);
        }

        // Pause/Resume music playing
        if (rl.isKeyPressed(.p)) {
            pause = !pause;

            if (pause) rl.pauseMusicStream(music) else rl.resumeMusicStream(music);
        }

        // Add/Remove effect: lowpass filter
        if (rl.isKeyPressed(.f)) {
            enable_effect_lpf = !enable_effect_lpf;
            if (enable_effect_lpf) {
                rl.attachAudioStreamProcessor(music.stream, audioProcessEffectLpf);
            } else {
                rl.detachAudioStreamProcessor(music.stream, audioProcessEffectLpf);
            }
        }

        // Add/Remove effect: delay
        if (rl.isKeyPressed(.d)) {
            enable_effect_delay = !enable_effect_delay;
            if (enable_effect_delay) {
                rl.attachAudioStreamProcessor(music.stream, audioProcessEffectDelay);
            } else {
                rl.detachAudioStreamProcessor(music.stream, audioProcessEffectDelay);
            }
        }

        // Get normalized time played for current music stream
        time_played = rl.getMusicTimePlayed(music) / rl.getMusicTimeLength(music);

        if (time_played > 1.0) time_played = 1.0; // Make sure time played is no longer than music

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("MUSIC SHOULD BE PLAYING!", 245, 150, 20, .light_gray);

        rl.drawRectangle(200, 180, 400, 12, .light_gray);
        rl.drawRectangle(200, 180, @intFromFloat(time_played * 400.0), 12, .maroon);
        rl.drawRectangleLines(200, 180, 400, 12, .gray);

        rl.drawText("PRESS SPACE TO RESTART MUSIC", 215, 230, 20, .light_gray);
        rl.drawText("PRESS P TO PAUSE/RESUME MUSIC", 208, 260, 20, .light_gray);

        rl.drawText(rl.textFormat("PRESS F TO TOGGLE LPF EFFECT: {s}", .{onOff(enable_effect_lpf)}), 200, 320, 20, .gray);
        rl.drawText(rl.textFormat("PRESS D TO TOGGLE DELAY EFFECT: {s}", .{onOff(enable_effect_delay)}), 180, 350, 20, .gray);
    }
}

fn onOff(enabled: bool) []const u8 {
    return if (enabled) "ON" else "OFF";
}

/// View an audio processor buffer as its interleaved stereo float samples.
fn stereoSamples(buffer: ?*anyopaque, frames: c_uint) [][2]f32 {
    const samples: [*][2]f32 = @ptrCast(@alignCast(buffer.?));
    return samples[0..frames];
}

/// Audio effect: lowpass filter
fn audioProcessEffectLpf(buffer: ?*anyopaque, frames: c_uint) callconv(.c) void {
    const S = struct {
        var low: [2]f32 = .{ 0.0, 0.0 };
    };
    const cutoff: f32 = 70.0 / 44100.0; // 70 Hz lowpass filter
    const k = cutoff / (cutoff + 0.1591549431); // RC filter formula

    for (stereoSamples(buffer, frames)) |*frame| {
        for (frame, &S.low) |*sample, *low| {
            low.* += k * (sample.* - low.*);
            sample.* = low.*;
        }
    }
}

/// Audio effect: delay
fn audioProcessEffectDelay(buffer: ?*anyopaque, frames: c_uint) callconv(.c) void {
    for (stereoSamples(buffer, frames)) |*frame| {
        const left_delay = delay_buffer[delay_read_index];
        const right_delay = delay_buffer[delay_read_index + 1];
        delay_read_index += 2;
        if (delay_read_index == delay_buffer.len) delay_read_index = 0;

        frame[0] = 0.5 * frame[0] + 0.5 * left_delay;
        frame[1] = 0.5 * frame[1] + 0.5 * right_delay;

        delay_buffer[delay_write_index] = frame[0];
        delay_buffer[delay_write_index + 1] = frame[1];
        delay_write_index += 2;
        if (delay_write_index == delay_buffer.len) delay_write_index = 0;
    }
}
