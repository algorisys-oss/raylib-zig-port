//! raylib [audio] example - sound positioning
//!
//! Zig-API translation of examples/audio/audio_sound_positioning.c (raylib 6.2).
//! Example contributed by Le Juez Victor (@Bigfoot71) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Le Juez Victor (@Bigfoot71)

const rl = @import("raylib");
const rm = rl.math;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [audio] example - sound positioning");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice();
    defer rl.closeAudioDevice(); // Close audio device

    const sound = try rl.loadSound("resources/coin.wav");
    defer rl.unloadSound(sound);

    var camera: rl.Camera = .{
        .position = .{ .x = 0, .y = 5, .z = 5 },
        .target = .{ .x = 0, .y = 0, .z = 0 },
        .up = .{ .x = 0, .y = 1, .z = 0 },
        .fovy = 60,
        .projection = .perspective,
    };

    rl.disableCursor();

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        rl.updateCamera(&camera, .free);

        const th: f32 = @floatCast(rl.getTime());

        const sphere_pos: rl.Vector3 = .{
            .x = 5.0 * @cos(th),
            .y = 0.0,
            .z = 5.0 * @sin(th),
        };

        setSoundPosition(camera, sound, sphere_pos, 1.0);

        if (!rl.isSoundPlaying(sound)) rl.playSound(sound);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.beginMode3D(camera);
        rl.drawGrid(10, 2);
        rl.drawSphere(sphere_pos, 0.5, .red);
        rl.endMode3D();
    }
}

/// Set sound 3d position
fn setSoundPosition(listener: rl.Camera, sound: rl.Sound, position: rl.Vector3, max_dist: f32) void {
    // Calculate direction vector and distance between listener and sound source
    const direction = rm.vector3Subtract(position, listener.position);
    const distance = rm.vector3Length(direction);

    // Apply logarithmic distance attenuation and clamp between 0-1
    var attenuation = 1.0 / (1.0 + (distance / max_dist));
    attenuation = rm.clamp(attenuation, 0.0, 1.0);

    // Calculate normalized vectors for spatial positioning
    const normalized_direction = rm.vector3Normalize(direction);
    const forward = rm.vector3Normalize(rm.vector3Subtract(listener.target, listener.position));
    const right = rm.vector3Normalize(rm.vector3CrossProduct(forward, listener.up));

    // Reduce volume for sounds behind the listener
    const dot_product = rm.vector3DotProduct(forward, normalized_direction);
    if (dot_product < 0.0) attenuation *= (1.0 + dot_product * 0.5);

    // Set stereo panning based on sound position relative to listener
    const pan = rm.vector3DotProduct(normalized_direction, right);

    // Apply final sound properties
    rl.setSoundVolume(sound, attenuation);
    rl.setSoundPan(sound, pan);
}
