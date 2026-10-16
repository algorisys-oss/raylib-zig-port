//! raylib [audio] example - music stream
//!
//! Zig-API translation of examples/audio/audio_music_stream.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [audio] example - music stream");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice(); // Initialize audio device
    defer rl.closeAudioDevice(); // Close audio device (music streaming is automatically stopped)

    const music = try rl.loadMusicStream("resources/country.mp3");
    defer rl.unloadMusicStream(music); // Unload music stream buffers from RAM

    rl.playMusicStream(music);

    var time_played: f32 = 0.0; // Time played normalized [0.0f..1.0f]
    var pause = false; // Music playing paused

    var pan: f32 = 0.0; // Default audio pan center [-1.0f..1.0f]
    rl.setMusicPan(music, pan);

    var volume: f32 = 0.8; // Default audio volume [0.0f..1.0f]
    rl.setMusicVolume(music, volume);

    rl.setTargetFPS(30); // Set our game to run at 30 frames-per-second

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

        // Set audio pan
        if (rl.isKeyDown(.left)) {
            pan = @max(pan - 0.05, -1.0);
            rl.setMusicPan(music, pan);
        } else if (rl.isKeyDown(.right)) {
            pan = @min(pan + 0.05, 1.0);
            rl.setMusicPan(music, pan);
        }

        // Set audio volume
        if (rl.isKeyDown(.down)) {
            volume = @max(volume - 0.05, 0.0);
            rl.setMusicVolume(music, volume);
        } else if (rl.isKeyDown(.up)) {
            volume = @min(volume + 0.05, 1.0);
            rl.setMusicVolume(music, volume);
        }

        // Get normalized time played for current music stream
        time_played = rl.getMusicTimePlayed(music) / rl.getMusicTimeLength(music);

        if (time_played > 1.0) time_played = 1.0; // Make sure time played is no longer than music

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("MUSIC SHOULD BE PLAYING!", 255, 150, 20, .light_gray);

        rl.drawText("LEFT-RIGHT for PAN CONTROL", 320, 74, 10, .dark_blue);
        rl.drawRectangle(300, 100, 200, 12, .light_gray);
        rl.drawRectangleLines(300, 100, 200, 12, .gray);
        rl.drawRectangle(@intFromFloat(300 + (pan + 1.0) / 2.0 * 200 - 5), 92, 10, 28, .dark_gray);

        rl.drawRectangle(200, 200, 400, 12, .light_gray);
        rl.drawRectangle(200, 200, @intFromFloat(time_played * 400.0), 12, .maroon);
        rl.drawRectangleLines(200, 200, 400, 12, .gray);

        rl.drawText("PRESS SPACE TO RESTART MUSIC", 215, 250, 20, .light_gray);
        rl.drawText("PRESS P TO PAUSE/RESUME MUSIC", 208, 280, 20, .light_gray);

        rl.drawText("UP-DOWN for VOLUME CONTROL", 320, 334, 10, .dark_green);
        rl.drawRectangle(300, 360, 200, 12, .light_gray);
        rl.drawRectangleLines(300, 360, 200, 12, .gray);
        rl.drawRectangle(@intFromFloat(300 + volume * 200 - 5), 352, 10, 28, .dark_gray);
    }
}
