//! raylib [audio] example - module playing
//!
//! Zig-API translation of examples/audio/audio_module_playing.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const max_circles = 64;

const screen_width = 800;
const screen_height = 450;

const colors = [_]rl.Color{
    .orange, .red,   .gold,     .lime,   .blue,  .violet, .brown, .light_gray, .pink,
    .yellow, .green, .sky_blue, .purple, .beige,
};

const CircleWave = struct {
    position: rl.Vector2,
    radius: f32,
    alpha: f32,
    speed: f32,
    color: rl.Color,

    /// A new transparent circle with random radius, position, color and speed
    /// (the order raylib's example respawns faded-out circles in).
    fn random() CircleWave {
        const radius: f32 = @floatFromInt(rl.getRandomValue(10, 40));
        const x: f32 = @floatFromInt(rl.getRandomValue(@intFromFloat(radius), @intFromFloat(screen_width - radius)));
        const y: f32 = @floatFromInt(rl.getRandomValue(@intFromFloat(radius), @intFromFloat(screen_height - radius)));
        const color = colors[@intCast(rl.getRandomValue(0, colors.len - 1))];
        const speed: f32 = @floatFromInt(rl.getRandomValue(1, 100));
        return .{
            .position = .{ .x = x, .y = y },
            .radius = radius,
            .alpha = 0.0,
            .speed = speed / 2000.0,
            .color = color,
        };
    }
};

pub fn main() !void {
    // Initialization
    rl.setConfigFlags(.{ .msaa_4x_hint = true }); // NOTE: Try to enable MSAA 4X

    rl.initWindow(screen_width, screen_height, "raylib [audio] example - module playing");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice(); // Initialize audio device
    defer rl.closeAudioDevice(); // Close audio device (music streaming is automatically stopped)

    // Creates some circles for visual effect
    var circles: [max_circles]CircleWave = undefined;
    // NOTE: The initial circles draw their speed before their color
    for (0..max_circles) |n| {
        const radius: f32 = @floatFromInt(rl.getRandomValue(10, 40));
        const x: f32 = @floatFromInt(rl.getRandomValue(@intFromFloat(radius), @intFromFloat(screen_width - radius)));
        const y: f32 = @floatFromInt(rl.getRandomValue(@intFromFloat(radius), @intFromFloat(screen_height - radius)));
        const speed: f32 = @floatFromInt(rl.getRandomValue(1, 100));
        const color = colors[@intCast(rl.getRandomValue(0, colors.len - 1))];
        circles[max_circles - 1 - n] = .{
            .position = .{ .x = x, .y = y },
            .radius = radius,
            .alpha = 0.0,
            .speed = speed / 2000.0,
            .color = color,
        };
    }

    var music = try rl.loadMusicStream("resources/mini1111.xm");
    defer rl.unloadMusicStream(music); // Unload music stream buffers from RAM
    music.looping = false;
    var pitch: f32 = 1.0;

    rl.playMusicStream(music);

    var time_played: f32 = 0.0;
    var pause = false;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateMusicStream(music); // Update music buffer with new stream data

        // Restart music playing (stop and play)
        if (rl.isKeyPressed(.space)) {
            rl.stopMusicStream(music);
            rl.playMusicStream(music);
            pause = false;
        }

        // Pause/Resume music playing
        if (rl.isKeyPressed(.p)) {
            pause = !pause;

            if (pause) rl.pauseMusicStream(music) else rl.resumeMusicStream(music);
        }

        if (rl.isKeyDown(.down)) {
            pitch -= 0.01;
        } else if (rl.isKeyDown(.up)) {
            pitch += 0.01;
        }

        rl.setMusicPitch(music, pitch);

        // Get timePlayed scaled to bar dimensions
        time_played = rl.getMusicTimePlayed(music) / rl.getMusicTimeLength(music) * (screen_width - 40);

        // Color circles animation
        if (!pause) {
            for (0..max_circles) |n| {
                const circle = &circles[max_circles - 1 - n];
                circle.alpha += circle.speed;
                circle.radius += circle.speed * 10.0;

                if (circle.alpha > 1.0) circle.speed *= -1;

                if (circle.alpha <= 0.0) circle.* = .random();
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        for (0..max_circles) |n| {
            const circle = circles[max_circles - 1 - n];
            rl.drawCircleV(circle.position, circle.radius, rl.fade(circle.color, circle.alpha));
        }

        // Draw time bar
        rl.drawRectangle(20, screen_height - 20 - 12, screen_width - 40, 12, .light_gray);
        rl.drawRectangle(20, screen_height - 20 - 12, @intFromFloat(time_played), 12, .maroon);
        rl.drawRectangleLines(20, screen_height - 20 - 12, screen_width - 40, 12, .gray);

        // Draw help instructions
        rl.drawRectangle(20, 20, 425, 145, .white);
        rl.drawRectangleLines(20, 20, 425, 145, .gray);
        rl.drawText("PRESS SPACE TO RESTART MUSIC", 40, 40, 20, .black);
        rl.drawText("PRESS P TO PAUSE/RESUME", 40, 70, 20, .black);
        rl.drawText("PRESS UP/DOWN TO CHANGE SPEED", 40, 100, 20, .black);
        rl.drawText(rl.textFormat("SPEED: {d:.6}", .{pitch}), 40, 130, 20, .maroon);
    }
}
