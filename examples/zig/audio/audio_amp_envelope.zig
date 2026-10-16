//! raylib [audio] example - amp envelope
//!
//! Zig-API translation of examples/audio/audio_amp_envelope.c (raylib 6.2).
//! Example contributed by Arbinda Rizki Muhammad (@arbipink) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Arbinda Rizki Muhammad (@arbipink)

const rl = @import("raylib");
const gui = @import("raygui");

const buffer_size = 4096;
const sample_rate = 44100;

/// Calculate the time delta for ONE sample (1/44100)
const sample_time: f32 = 1.0 / @as(f32, sample_rate);

/// Grouping all ADSR parameters and state into a struct
const Envelope = struct {
    attack_time: f32,
    decay_time: f32,
    sustain_level: f32,
    release_time: f32,
    current_value: f32 = 0.0,
    state: State = .idle,

    /// Wave state
    const State = enum { idle, attack, decay, sustain, release };

    /// Advance the envelope by one sample.
    fn update(env: *Envelope) void {
        switch (env.state) {
            .attack => {
                env.current_value += (1.0 / env.attack_time) * sample_time;
                if (env.current_value >= 1.0) {
                    env.current_value = 1.0;
                    env.state = .decay;
                }
            },
            .decay => {
                env.current_value -= ((1.0 - env.sustain_level) / env.decay_time) * sample_time;
                if (env.current_value <= env.sustain_level) {
                    env.current_value = env.sustain_level;
                    env.state = .sustain;
                }
            },
            .sustain => env.current_value = env.sustain_level,
            .release => {
                env.current_value -= (env.sustain_level / env.release_time) * sample_time;
                if (env.current_value <= 0.001) { // Use a small threshold to avoid infinite tail
                    env.current_value = 0.0;
                    env.state = .idle;
                }
            },
            .idle => {},
        }
    }

    /// Draw the envelope shape inside `bounds`.
    fn drawGraph(env: Envelope, bounds: rl.Rectangle) void {
        rl.drawRectangleRec(bounds, rl.fade(.light_gray, 0.3));
        rl.drawRectangleLinesEx(bounds, 1, .gray);

        // Fixed visual width for sustain stage since it's an amplitude not a time value
        const sustain_width: f32 = 1.0;

        // Total time to visualize (sum of A, D, R + a padding for Sustain)
        const total_time = env.attack_time + env.decay_time + sustain_width + env.release_time;

        const scale_x = bounds.width / total_time;
        const scale_y = bounds.height;

        const start: rl.Vector2 = .{ .x = bounds.x, .y = bounds.y + bounds.height };
        const peak: rl.Vector2 = .{ .x = start.x + (env.attack_time * scale_x), .y = bounds.y };
        const sustain: rl.Vector2 = .{ .x = peak.x + (env.decay_time * scale_x), .y = bounds.y + (1.0 - env.sustain_level) * scale_y };
        const rel: rl.Vector2 = .{ .x = sustain.x + (sustain_width * scale_x), .y = sustain.y };
        const end: rl.Vector2 = .{ .x = rel.x + (env.release_time * scale_x), .y = bounds.y + bounds.height };

        rl.drawLineV(start, peak, .sky_blue);
        rl.drawLineV(peak, sustain, .blue);
        rl.drawLineV(sustain, rel, .dark_blue);
        rl.drawLineV(rel, end, .orange);

        rl.drawText("ADSR Visualizer", @intFromFloat(bounds.x), @intFromFloat(bounds.y - 20), 10, .dark_gray);
    }
};

/// Sine wave sample at `audio_time`, scaled by the envelope; advances the phase.
fn sineSample(envelope_value: f32, audio_time: *f32) f32 {
    const frequency = 440;
    const sample = envelope_value * @sin(2.0 * rl.pi * @as(f32, frequency) * audio_time.*);
    audio_time.* += 1.0 / @as(f32, sample_rate);
    return sample;
}

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [audio] example - amp envelope");
    defer rl.closeWindow();

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    // Set the number of samples the stream will keep in memory at a time to buffer_size
    rl.setAudioStreamBufferSizeDefault(buffer_size);
    var buffer: [buffer_size]f32 = @splat(0);

    // Init raw audio stream (sample rate: 44100, sample size: 32bit-float, channels: 1-mono)
    const stream = try rl.loadAudioStream(sample_rate, 32, 1);
    defer rl.unloadAudioStream(stream);

    // Init Phase
    var audio_time: f32 = 0.0;

    var env: Envelope = .{
        .attack_time = 1.0,
        .decay_time = 1.0,
        .sustain_level = 0.5,
        .release_time = 1.0,
    };

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        if (rl.isKeyPressed(.space)) env.state = .attack;

        if (rl.isKeyReleased(.space) and env.state != .idle) env.state = .release;

        if (rl.isAudioStreamProcessed(stream)) {
            if (env.state != .idle or env.current_value > 0.0) {
                for (&buffer) |*sample| {
                    env.update();
                    sample.* = sineSample(env.current_value, &audio_time);
                }
            } else {
                // Clear buffer if silent to avoid looping noise
                @memset(&buffer, 0);
                audio_time = 0.0;
            }

            rl.updateAudioStream(stream, &buffer, buffer_size);
        }

        if (!rl.isAudioStreamPlaying(stream)) rl.playAudioStream(stream);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        _ = gui.sliderBar(.{ .x = 100, .y = 60, .width = 400, .height = 30 }, "Attack (s)", rl.textFormat("{d:.2}s", .{env.attack_time}), &env.attack_time, 0.1, 3.0);
        _ = gui.sliderBar(.{ .x = 100, .y = 100, .width = 400, .height = 30 }, "Decay (s)", rl.textFormat("{d:.2}s", .{env.decay_time}), &env.decay_time, 0.1, 3.0);
        _ = gui.sliderBar(.{ .x = 100, .y = 140, .width = 400, .height = 30 }, "Sustain", rl.textFormat("{d:.2}", .{env.sustain_level}), &env.sustain_level, 0.0, 1.0);
        _ = gui.sliderBar(.{ .x = 100, .y = 180, .width = 400, .height = 30 }, "Release (s)", rl.textFormat("{d:.2}s", .{env.release_time}), &env.release_time, 0.1, 3.0);

        env.drawGraph(.{ .x = 100, .y = 250, .width = 400, .height = 100 });

        rl.drawCircleV(.{ .x = 520, .y = 350 - (env.current_value * 100) }, 5, .maroon);
        rl.drawText(rl.textFormat("Current Gain: {d:.2}", .{env.current_value}), 535, @intFromFloat(345 - (env.current_value * 100)), 10, .maroon);

        rl.drawText("Press SPACE to PLAY the sound!", 200, 400, 20, .light_gray);
    }
}
