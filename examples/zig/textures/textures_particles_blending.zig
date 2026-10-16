//! raylib [textures] example - particles blending
//!
//! Zig-API translation of examples/textures/textures_particles_blending.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const max_particles = 200;

const Particle = struct {
    position: rl.Vector2,
    color: rl.Color,
    alpha: f32,
    size: f32,
    rotation: f32,
    active: bool, // NOTE: Use it to activate/deactive particle
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - particles blending");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Particles pool, reuse them!
    var mouse_tail: [max_particles]Particle = undefined;

    // Initialize particles
    for (&mouse_tail) |*particle| {
        const r: u8 = @intCast(rl.getRandomValue(0, 255));
        const g: u8 = @intCast(rl.getRandomValue(0, 255));
        const b: u8 = @intCast(rl.getRandomValue(0, 255));
        const size = @as(f32, @floatFromInt(rl.getRandomValue(1, 30))) / 20.0;
        const rotation: f32 = @floatFromInt(rl.getRandomValue(0, 360));
        particle.* = .{
            .position = .{ .x = 0, .y = 0 },
            .color = .{ .r = r, .g = g, .b = b, .a = 255 },
            .alpha = 1.0,
            .size = size,
            .rotation = rotation,
            .active = false,
        };
    }

    const gravity: f32 = 3.0;

    const smoke = try rl.loadTexture("resources/spark_flame.png");
    defer rl.unloadTexture(smoke);
    const smoke_width: f32 = @floatFromInt(smoke.width);
    const smoke_height: f32 = @floatFromInt(smoke.height);

    var blending: rl.BlendMode = .alpha;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update

        // Activate one particle every frame and Update active particles
        // NOTE: Particles initial position should be mouse position when activated
        // NOTE: Particles fall down with gravity and rotation... and disappear after 2 seconds (alpha = 0)
        // NOTE: When a particle disappears, active = false and it can be reused
        for (&mouse_tail) |*particle| {
            if (!particle.active) {
                particle.active = true;
                particle.alpha = 1.0;
                particle.position = rl.getMousePosition();
                break;
            }
        }

        for (&mouse_tail) |*particle| {
            if (particle.active) {
                particle.position.y += gravity / 2;
                particle.alpha -= 0.005;

                if (particle.alpha <= 0.0) particle.active = false;

                particle.rotation += 2.0;
            }
        }

        if (rl.isKeyPressed(.space)) {
            blending = if (blending == .alpha) .additive else .alpha;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.dark_gray);

        rl.beginBlendMode(blending);

        // Draw active particles
        for (mouse_tail) |particle| {
            if (!particle.active) continue;
            const width = smoke_width * particle.size;
            const height = smoke_height * particle.size;
            rl.drawTexturePro(
                smoke,
                .{ .x = 0.0, .y = 0.0, .width = smoke_width, .height = smoke_height },
                .{ .x = particle.position.x, .y = particle.position.y, .width = width, .height = height },
                .{ .x = width / 2.0, .y = height / 2.0 },
                particle.rotation,
                rl.fade(particle.color, particle.alpha),
            );
        }

        rl.endBlendMode();

        rl.drawText("PRESS SPACE to CHANGE BLENDING MODE", 180, 20, 20, .black);

        if (blending == .alpha) {
            rl.drawText("ALPHA BLENDING", 290, screen_height - 40, 20, .black);
        } else {
            rl.drawText("ADDITIVE BLENDING", 280, screen_height - 40, 20, .ray_white);
        }
    }
}
