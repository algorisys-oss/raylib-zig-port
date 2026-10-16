//! raylib [audio] example - raw stream
//!
//! Zig-API translation of examples/audio/audio_raw_stream.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2026 Ramon Santamaria (@raysan5) and James Hofmann (@triplefox)

const rl = @import("raylib");

const buffer_size = 4096;
const sample_rate = 44100;

/// sin(2*PI*t/wavelength), with C's float evaluation order.
fn sineAt(t: i32, wavelength: i32) f32 {
    return @sin(2 * rl.pi * @as(f32, @floatFromInt(t)) / @as(f32, @floatFromInt(wavelength)));
}

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [audio] example - raw stream");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice();
    defer rl.closeAudioDevice(); // Close audio device (music streaming is automatically stopped)

    // Set the number of samples the stream will keep in memory at a time to buffer_size
    rl.setAudioStreamBufferSizeDefault(buffer_size);
    var buffer: [buffer_size]f32 = @splat(0.0);

    // Init raw audio stream (sample rate: 44100, sample size: 32bit-float, channels: 1-mono)
    const stream = try rl.loadAudioStream(sample_rate, 32, 1);
    defer rl.unloadAudioStream(stream); // Close raw audio stream and delete buffers from RAM
    var pan: f32 = 0.0;
    rl.setAudioStreamPan(stream, pan);
    rl.playAudioStream(stream);

    var sine_frequency: i32 = 440;
    var new_sine_frequency: i32 = 440;
    var sine_index: i32 = 0;
    var sine_start_time: f64 = 0.0;

    rl.setTargetFPS(30);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyDown(.up)) new_sine_frequency = @min(new_sine_frequency + 10, 12500);
        if (rl.isKeyDown(.down)) new_sine_frequency = @max(new_sine_frequency - 10, 20);

        if (rl.isKeyDown(.left)) {
            pan -= 0.01;
            if (pan < -1.0) pan = -1.0;
            rl.setAudioStreamPan(stream, pan);
        }

        if (rl.isKeyDown(.right)) {
            pan += 0.01;
            if (pan > 1.0) pan = 1.0;
            rl.setAudioStreamPan(stream, pan);
        }

        if (rl.isAudioStreamProcessed(stream)) {
            for (&buffer) |*sample| {
                const wavelength = @divTrunc(sample_rate, sine_frequency);
                sample.* = sineAt(sine_index, wavelength);
                sine_index += 1;

                if (sine_index >= wavelength) {
                    sine_frequency = new_sine_frequency;
                    sine_index = 0;
                    sine_start_time = rl.getTime();
                }
            }

            rl.updateAudioStream(stream, &buffer, buffer_size);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText(rl.textFormat("sine frequency: {d}", .{sine_frequency}), screen_width - 220, 10, 20, .red);
        rl.drawText(rl.textFormat("pan: {d:.2}", .{pan}), screen_width - 220, 30, 20, .red);
        rl.drawText("Up/down to change frequency", 10, 10, 20, .dark_gray);
        rl.drawText("Left/right to pan", 10, 30, 20, .dark_gray);

        const window_start: i32 = @intFromFloat((rl.getTime() - sine_start_time) * sample_rate);
        const window_size = sample_rate / 10;
        const wavelength = @divTrunc(sample_rate, sine_frequency);

        // Draw a sine wave with the same frequency as the one being sent to the audio stream
        for (0..screen_width) |column| {
            const i: i32 = @intCast(column);
            const t0 = window_start + @divTrunc(i * window_size, screen_width);
            const t1 = window_start + @divTrunc((i + 1) * window_size, screen_width);
            const x: f32 = @floatFromInt(i);
            const start_pos: rl.Vector2 = .{ .x = x, .y = 250 + 50 * sineAt(t0, wavelength) };
            const end_pos: rl.Vector2 = .{ .x = x + 1, .y = 250 + 50 * sineAt(t1, wavelength) };
            rl.drawLineV(start_pos, end_pos, .red);
        }
    }
}
