//! raylib [audio] example - sound loading
//!
//! Zig-API translation of examples/audio/audio_sound_loading.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [audio] example - sound loading");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice(); // Initialize audio device
    defer rl.closeAudioDevice(); // Close audio device

    const fx_wav = try rl.loadSound("resources/sound.wav"); // Load WAV audio file
    defer rl.unloadSound(fx_wav);
    const fx_ogg = try rl.loadSound("resources/target.ogg"); // Load OGG audio file
    defer rl.unloadSound(fx_ogg);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.space)) rl.playSound(fx_wav); // Play WAV sound
        if (rl.isKeyPressed(.enter)) rl.playSound(fx_ogg); // Play OGG sound

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("Press SPACE to PLAY the WAV sound!", 200, 180, 20, .light_gray);
        rl.drawText("Press ENTER to PLAY the OGG sound!", 200, 220, 20, .light_gray);
    }
}
