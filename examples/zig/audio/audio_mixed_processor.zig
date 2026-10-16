//! raylib [audio] example - mixed processor
//!
//! Zig-API translation of examples/audio/audio_mixed_processor.c (raylib 6.2).
//! Example contributed by hkc (@hatkidchan) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 hkc (@hatkidchan)

const std = @import("std");
const rl = @import("raylib");

var exponent: f32 = 1.0; // Audio exponentiation value
var average_volume: [400]f32 = @splat(0.0); // Average volume history

/// Audio processing function: runs on the audio thread for the whole mix.
fn processAudio(buffer: ?*anyopaque, frames: c_uint) callconv(.c) void {
    // Samples internally stored as <float>s, interleaved stereo
    const samples: [*]f32 = @ptrCast(@alignCast(buffer.?));
    const frame_count: f32 = @floatFromInt(frames);
    var average: f32 = 0.0; // Temporary average volume

    for (samples[0 .. frames * 2]) |*sample| {
        const sign: f32 = if (sample.* < 0.0) -1.0 else 1.0;
        sample.* = std.math.pow(f32, @abs(sample.*), exponent) * sign;

        average += @abs(sample.*) / frame_count; // accumulating average volume
    }

    // Moving history to the left
    std.mem.copyForwards(f32, average_volume[0..399], average_volume[1..]);

    average_volume[399] = average; // Adding last average value
}

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [audio] example - mixed processor");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice(); // Initialize audio device
    defer rl.closeAudioDevice(); // Close audio device (music streaming is automatically stopped)

    rl.attachAudioMixedProcessor(processAudio);
    defer rl.detachAudioMixedProcessor(processAudio); // Disconnect audio processor

    const music = try rl.loadMusicStream("resources/country.mp3");
    defer rl.unloadMusicStream(music); // Unload music stream buffers from RAM
    const sound = try rl.loadSound("resources/coin.wav");
    defer rl.unloadSound(sound);

    rl.playMusicStream(music);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateMusicStream(music); // Update music buffer with new stream data

        // Modify processing variables
        if (rl.isKeyPressed(.left)) exponent -= 0.05;
        if (rl.isKeyPressed(.right)) exponent += 0.05;

        if (exponent <= 0.5) exponent = 0.5;
        if (exponent >= 3.0) exponent = 3.0;

        if (rl.isKeyPressed(.space)) rl.playSound(sound);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("MUSIC SHOULD BE PLAYING!", 255, 150, 20, .light_gray);

        rl.drawText(rl.textFormat("EXPONENT = {d:.2}", .{exponent}), 215, 180, 20, .light_gray);

        rl.drawRectangle(199, 199, 402, 34, .light_gray);
        for (average_volume, 0..) |volume, i| {
            const x = 201 + @as(i32, @intCast(i));
            rl.drawLine(x, 232 - @as(i32, @intFromFloat(volume * 32)), x, 232, .maroon);
        }
        rl.drawRectangleLines(199, 199, 402, 34, .gray);

        rl.drawText("PRESS SPACE TO PLAY OTHER SOUND", 200, 250, 20, .light_gray);
        rl.drawText("USE LEFT AND RIGHT ARROWS TO ALTER DISTORTION", 140, 280, 20, .light_gray);
    }
}
