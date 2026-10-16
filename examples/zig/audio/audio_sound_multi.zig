//! raylib [audio] example - sound multi
//!
//! Zig-API translation of examples/audio/audio_sound_multi.c (raylib 6.2).
//! Example contributed by Jeffery Myers (@JeffM2501) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 Jeffery Myers (@JeffM2501)

const rl = @import("raylib");

const max_sounds = 10;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [audio] example - sound multi");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice(); // Initialize audio device
    defer rl.closeAudioDevice(); // Close audio device

    var sounds: [max_sounds]rl.Sound = undefined;

    // Load audio file into the first slot as the 'source' sound,
    // this sound owns the sample data
    sounds[0] = try rl.loadSound("resources/sound.wav");
    defer rl.unloadSound(sounds[0]); // Unload source sound data

    // Load an alias of the sound into slots 1-9. These do not own the sound data, but can be played
    for (sounds[1..]) |*alias| alias.* = try rl.loadSoundAlias(sounds[0]);
    defer for (sounds[1..]) |alias| rl.unloadSoundAlias(alias); // Unload sound aliases

    var current_sound: usize = 0; // Set the sound list to the start

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.space)) {
            rl.playSound(sounds[current_sound]); // Play the next open sound slot

            // Advance to the next slot, going back to 0 when out of bounds
            // NOTE: Another approach would be to look at the list for the first sound
            // that is not playing and use that slot
            current_sound = (current_sound + 1) % max_sounds;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("Press SPACE to PLAY a WAV sound!", 200, 180, 20, .light_gray);
    }
}
