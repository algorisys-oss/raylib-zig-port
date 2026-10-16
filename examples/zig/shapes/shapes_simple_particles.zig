//! raylib [shapes] example - simple particles
//!
//! Zig-API translation of examples/shapes/shapes_simple_particles.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Jordi Santonja (@JordSant)

const std = @import("std");
const rl = @import("raylib");

/// libc's `rand()`: the C example draws from it (not raylib's GetRandomValue),
/// so the same unseeded sequence is used here.
extern "c" fn rand() c_int;

const max_particles = 3000; // Max number of particles

const ParticleType = enum {
    water,
    smoke,
    fire,

    fn name(particle_type: ParticleType) [:0]const u8 {
        return switch (particle_type) {
            .water => "WATER",
            .smoke => "SMOKE",
            .fire => "FIRE",
        };
    }
};

const Particle = struct {
    type: ParticleType, // Particle type (WATER, SMOKE, FIRE)
    position: rl.Vector2, // Particle position on screen
    velocity: rl.Vector2, // Particle current speed and direction
    radius: f32, // Particle radius
    color: rl.Color, // Particle color

    life_time: f32, // Particle life time
    alive: bool, // Particle alive: inside screen and life time

    /// Update particle life and position; out-of-screen particles die
    fn update(particle: *Particle, screen_width: f32, screen_height: f32) void {
        particle.life_time += 1.0 / 60.0; // 60 FPS -> 1/60 seconds per frame

        switch (particle.type) {
            .water => {
                particle.position.x += particle.velocity.x;
                particle.velocity.y += 0.2; // Gravity
                particle.position.y += particle.velocity.y;
            },
            .smoke => {
                particle.position.x += particle.velocity.x;
                particle.velocity.y -= 0.05; // Upwards
                particle.position.y += particle.velocity.y;
                particle.radius += 0.5; // Increment radius: smoke expands
                particle.color.a -%= 4; // Decrement alpha: smoke fades

                // If alpha transparent, particle dies
                if (particle.color.a < 4) particle.alive = false;
            },
            .fire => {
                // Add a little horizontal oscillation to fire particles
                particle.position.x += particle.velocity.x + @cos(particle.life_time * 215.0);
                particle.velocity.y -= 0.05; // Upwards
                particle.position.y += particle.velocity.y;
                particle.radius -= 0.15; // Decrement radius: fire shrinks
                particle.color.g -%= 3; // Decrement green: fire turns reddish starting from yellow

                // If radius too small, particle dies
                if (particle.radius <= 0.02) particle.alive = false;
            },
        }

        // Disable particle when out of screen
        const center = particle.position;
        const radius = particle.radius;

        if (center.x < -radius or center.x > screen_width + radius or
            center.y < -radius or center.y > screen_height + radius)
        {
            particle.alive = false;
        }
    }
};

/// Fixed-capacity ring of particles: `head` is the next write, `tail` the next read
const CircularBuffer = struct {
    head: usize = 0,
    tail: usize = 0,
    buffer: []Particle,

    /// Next slot to fill, or null when the buffer is full
    fn add(cb: *CircularBuffer) ?*Particle {
        const next = (cb.head + 1) % max_particles;
        if (next == cb.tail) return null;

        const particle = &cb.buffer[cb.head];
        cb.head = next;
        return particle;
    }

    fn emit(cb: *CircularBuffer, emitter_position: rl.Vector2, particle_type: ParticleType) void {
        // If buffer is full, there is no new particle
        const particle = cb.add() orelse return;

        var speed = @as(f32, @floatFromInt(@rem(rand(), 10))) / 5.0;
        const radius: f32, const color: rl.Color = switch (particle_type) {
            .water => .{ 5.0, .blue },
            .smoke => .{ 7.0, .gray },
            .fire => blk: {
                speed /= 10.0;
                break :blk .{ 10.0, .yellow };
            },
        };
        const direction: f32 = @floatFromInt(@rem(rand(), 360));

        particle.* = .{
            .type = particle_type,
            .position = emitter_position,
            .velocity = .{ .x = speed * @cos(direction * rl.deg2rad), .y = speed * @sin(direction * rl.deg2rad) },
            .radius = radius,
            .color = color,
            .life_time = 0.0,
            .alive = true,
        };
    }

    fn update(cb: *CircularBuffer, screen_width: f32, screen_height: f32) void {
        var i = cb.tail;
        while (i != cb.head) : (i = (i + 1) % max_particles) cb.buffer[i].update(screen_width, screen_height);

        // Remove dead particles: advance tail over them
        while (cb.tail != cb.head and !cb.buffer[cb.tail].alive) cb.tail = (cb.tail + 1) % max_particles;
    }

    fn draw(cb: *const CircularBuffer) void {
        var i = cb.tail;
        while (i != cb.head) : (i = (i + 1) % max_particles) {
            const particle = cb.buffer[i];
            if (particle.alive) rl.drawCircleV(particle.position, particle.radius, particle.color);
        }
    }
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - simple particles");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Definition of particles
    const particles = try std.heap.page_allocator.alloc(Particle, max_particles); // Particle array
    defer std.heap.page_allocator.free(particles);
    var circular_buffer: CircularBuffer = .{ .buffer = particles };

    // Particle emitter parameters
    var emission_rate: i32 = -2; // Negative: on average every -X frames. Positive: particles per frame
    var current_type: ParticleType = .water;
    var emitter_position: rl.Vector2 = .{ .x = screen_width / 2.0, .y = screen_height / 2.0 };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Emit new particles: when emission_rate is 1, emit every frame
        if (emission_rate < 0) {
            if (@rem(rand(), -emission_rate) == 0) circular_buffer.emit(emitter_position, current_type);
        } else {
            for (0..@intCast(emission_rate + 1)) |_| circular_buffer.emit(emitter_position, current_type);
        }

        // Update the parameters of each particle, then remove dead ones
        circular_buffer.update(screen_width, screen_height);

        // Change Particle Emission Rate (UP/DOWN arrows)
        if (rl.isKeyPressed(.up)) emission_rate += 1;
        if (rl.isKeyPressed(.down)) emission_rate -= 1;

        // Change Particle Type (LEFT/RIGHT arrows)
        if (rl.isKeyPressed(.right)) current_type = switch (current_type) {
            .water => .smoke,
            .smoke => .fire,
            .fire => .water,
        };
        if (rl.isKeyPressed(.left)) current_type = switch (current_type) {
            .water => .fire,
            .smoke => .water,
            .fire => .smoke,
        };

        if (rl.isMouseButtonDown(.left)) emitter_position = rl.getMousePosition();

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Call the function with a loop to draw all particles
        circular_buffer.draw();

        // Draw UI and Instructions
        rl.drawRectangle(5, 5, 315, 75, rl.fade(.sky_blue, 0.5));
        rl.drawRectangleLines(5, 5, 315, 75, .blue);

        rl.drawText("CONTROLS:", 15, 15, 10, .black);
        rl.drawText("UP/DOWN: Change Particle Emission Rate", 15, 35, 10, .black);
        rl.drawText("LEFT/RIGHT: Change Particle Type (Water, Smoke, Fire)", 15, 55, 10, .black);

        if (emission_rate < 0) {
            rl.drawText(rl.textFormat("Particles every {d} frames | Type: {s}", .{ -emission_rate, current_type.name() }), 15, 95, 10, .dark_gray);
        } else {
            rl.drawText(rl.textFormat("{d} Particles per frame | Type: {s}", .{ emission_rate + 1, current_type.name() }), 15, 95, 10, .dark_gray);
        }

        rl.drawFPS(screen_width - 80, 10);
    }
}
