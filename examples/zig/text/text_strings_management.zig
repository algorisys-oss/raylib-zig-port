//! raylib [text] example - strings management
//!
//! Zig-API translation of examples/text/text_strings_management.c (raylib 6.2).
//! Example contributed by David Buzatto (@davidbuzatto) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 David Buzatto (@davidbuzatto)

const std = @import("std");
const rl = @import("raylib");

const max_text_length = 100;
const max_text_particles = 100;
const font_size = 30;

const screen_width = 800;
const screen_height = 450;

const TextParticle = struct {
    buffer: [max_text_length]u8,
    len: usize,
    rect: rl.Rectangle, // Boundary
    vel: rl.Vector2, // Velocity
    ppos: rl.Vector2, // Previous position
    padding: f32,
    border_width: f32,
    friction: f32,
    elasticity: f32,
    color: rl.Color,
    grabbed: bool,

    fn init(content: []const u8, x: f32, y: f32, color: rl.Color) TextParticle {
        var tp: TextParticle = .{
            .buffer = undefined,
            .len = @min(content.len, max_text_length - 1),
            .rect = .{ .x = x, .y = y, .width = 30, .height = 30 },
            .vel = .{
                .x = @floatFromInt(rl.getRandomValue(-200, 200)),
                .y = @floatFromInt(rl.getRandomValue(-200, 200)),
            },
            .ppos = .{ .x = 0, .y = 0 },
            .padding = 5.0,
            .border_width = 5.0,
            .friction = 0.99,
            .elasticity = 0.9,
            .color = color,
            .grabbed = false,
        };

        @memcpy(tp.buffer[0..tp.len], content[0..tp.len]);
        tp.buffer[tp.len] = 0;
        tp.rect.width = @as(f32, @floatFromInt(rl.measureText(tp.text(), font_size))) + tp.padding * 2;
        tp.rect.height = font_size + tp.padding * 2;
        return tp;
    }

    fn text(tp: *const TextParticle) [:0]const u8 {
        return tp.buffer[0..tp.len :0];
    }
};

/// A fixed-capacity list of text particles
const Particles = struct {
    buffer: [max_text_particles]TextParticle = undefined,
    len: usize = 0,

    fn items(particles: *Particles) []TextParticle {
        return particles.buffer[0..particles.len];
    }

    fn append(particles: *Particles, tp: TextParticle) void {
        particles.buffer[particles.len] = tp;
        particles.len += 1;
    }

    /// Remove the particle at `index`, shifting the following ones down.
    fn orderedRemove(particles: *Particles, index: usize) void {
        std.mem.copyForwards(TextParticle, particles.buffer[index .. particles.len - 1], particles.buffer[index + 1 .. particles.len]);
        particles.len -= 1;
    }

    fn reset(particles: *Particles, content: []const u8) void {
        const x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0;
        const y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0;
        particles.buffer[0] = .init(content, x, y, .ray_white);
        particles.len = 1;
    }
};

fn randomColor() rl.Color {
    return .{
        .r = @intCast(rl.getRandomValue(0, 255)),
        .g = @intCast(rl.getRandomValue(0, 255)),
        .b = @intCast(rl.getRandomValue(0, 255)),
        .a = 255,
    };
}

pub fn main() void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [text] example - strings management");
    defer rl.closeWindow(); // Close window and OpenGL context

    var particles: Particles = .{};
    var grabbed: ?usize = null; // Index of the grabbed text particle
    var press_offset: rl.Vector2 = .{ .x = 0, .y = 0 };

    particles.reset("raylib => fun videogames programming!");

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const delta = rl.getFrameTime();
        const mouse_pos = rl.getMousePosition();

        // Checks if a text particle was grabbed
        if (rl.isMouseButtonPressed(.left)) {
            var i = particles.len;
            while (i > 0) {
                i -= 1;
                const tp = &particles.buffer[i];
                press_offset.x = mouse_pos.x - tp.rect.x;
                press_offset.y = mouse_pos.y - tp.rect.y;
                if (rl.checkCollisionPointRec(mouse_pos, tp.rect)) {
                    tp.grabbed = true;
                    grabbed = i;
                    break;
                }
            }
        }

        // Releases any text particle the was grabbed
        if (rl.isMouseButtonReleased(.left)) {
            if (grabbed) |index| {
                particles.buffer[index].grabbed = false;
                grabbed = null;
            }
        }

        // Slice os shatter a text particle
        if (rl.isMouseButtonPressed(.right)) {
            var i = particles.len;
            while (i > 0) {
                i -= 1;
                const tp = particles.buffer[i];
                if (rl.checkCollisionPointRec(mouse_pos, tp.rect)) {
                    if (rl.isKeyDown(.left_shift)) {
                        shatterTextParticle(&particles, i);
                    } else {
                        sliceTextParticle(&particles, i, tp.len / 2);
                    }
                    break;
                }
            }
        }

        // Shake text particles
        if (rl.isMouseButtonPressed(.middle)) {
            for (particles.items()) |*tp| {
                if (!tp.grabbed) tp.vel = .{
                    .x = @floatFromInt(rl.getRandomValue(-2000, 2000)),
                    .y = @floatFromInt(rl.getRandomValue(-2000, 2000)),
                };
            }
        }

        // Reset using TextTo* functions
        if (rl.isKeyPressed(.one)) particles.reset("raylib => fun videogames programming!");
        if (rl.isKeyPressed(.two)) particles.reset(rl.textToUpper("raylib => fun videogames programming!"));
        if (rl.isKeyPressed(.three)) particles.reset(rl.textToLower("raylib => fun videogames programming!"));
        if (rl.isKeyPressed(.four)) particles.reset(rl.textToPascal("raylib_fun_videogames_programming"));
        if (rl.isKeyPressed(.five)) particles.reset(rl.textToSnake("RaylibFunVideogamesProgramming"));
        if (rl.isKeyPressed(.six)) particles.reset(rl.textToCamel("raylib_fun_videogames_programming"));

        // Slice by char pressed only when we have one text particle
        const char_pressed: u8 = @truncate(@as(u32, @bitCast(rl.getCharPressed())));
        if (char_pressed >= 'A' and char_pressed <= 'z' and particles.len == 1) {
            sliceTextParticleByChar(&particles, char_pressed);
        }

        // Updates each text particle state
        var i: usize = 0;
        while (i < particles.len) : (i += 1) {
            const tp = &particles.buffer[i];

            // The text particle is not grabbed
            if (!tp.grabbed) {
                // text particle repositioning using the velocity
                tp.rect.x += tp.vel.x * delta;
                tp.rect.y += tp.vel.y * delta;

                // Does the text particle hit the screen right boundary?
                if ((tp.rect.x + tp.rect.width) >= screen_width) {
                    tp.rect.x = screen_width - tp.rect.width; // Text particle repositioning
                    tp.vel.x = -tp.vel.x * tp.elasticity; // Elasticity makes the text particle lose 10% of its velocity on hit
                }
                // Does the text particle hit the screen left boundary?
                else if (tp.rect.x <= 0) {
                    tp.rect.x = 0.0;
                    tp.vel.x = -tp.vel.x * tp.elasticity;
                }

                // The same for y axis
                if ((tp.rect.y + tp.rect.height) >= screen_height) {
                    tp.rect.y = screen_height - tp.rect.height;
                    tp.vel.y = -tp.vel.y * tp.elasticity;
                } else if (tp.rect.y <= 0) {
                    tp.rect.y = 0.0;
                    tp.vel.y = -tp.vel.y * tp.elasticity;
                }

                // Friction makes the text particle lose 1% of its velocity each frame
                tp.vel.x = tp.vel.x * tp.friction;
                tp.vel.y = tp.vel.y * tp.friction;
            } else {
                // Text particle repositioning using the mouse position
                tp.rect.x = mouse_pos.x - press_offset.x;
                tp.rect.y = mouse_pos.y - press_offset.y;

                // While the text particle is grabbed, recalculates its velocity
                tp.vel.x = (tp.rect.x - tp.ppos.x) / delta;
                tp.vel.y = (tp.rect.y - tp.ppos.y) / delta;
                tp.ppos.x = tp.rect.x;
                tp.ppos.y = tp.rect.y;

                // Glue text particles when dragging and pressing left ctrl
                if (rl.isKeyDown(.left_control)) {
                    var j: usize = 0;
                    while (j < particles.len) : (j += 1) {
                        const grabbed_index = grabbed.?;
                        const grabbed_tp = particles.buffer[grabbed_index];
                        if (j != grabbed_index and grabbed_tp.grabbed) {
                            if (rl.checkCollisionRecs(grabbed_tp.rect, particles.buffer[j].rect)) {
                                glueTextParticles(&particles, grabbed_index, j);
                                grabbed = particles.len - 1;
                            }
                        }
                    }
                }
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        for (particles.items()) |*tp| {
            rl.drawRectangleRec(.{
                .x = tp.rect.x - tp.border_width,
                .y = tp.rect.y - tp.border_width,
                .width = tp.rect.width + tp.border_width * 2,
                .height = tp.rect.height + tp.border_width * 2,
            }, .black);
            rl.drawRectangleRec(tp.rect, tp.color);
            rl.drawText(tp.text(), @intFromFloat(tp.rect.x + tp.padding), @intFromFloat(tp.rect.y + tp.padding), font_size, .black);
        }

        rl.drawText("grab a text particle by pressing with the mouse and throw it by releasing", 10, 10, 10, .dark_gray);
        rl.drawText("slice a text particle by pressing it with the mouse right button", 10, 30, 10, .dark_gray);
        rl.drawText("shatter a text particle keeping left shift pressed and pressing it with the mouse right button", 10, 50, 10, .dark_gray);
        rl.drawText("glue text particles by grabbing than and keeping left control pressed", 10, 70, 10, .dark_gray);
        rl.drawText("1 to 6 to reset", 10, 90, 10, .dark_gray);
        rl.drawText("when you have only one text particle, you can slice it by pressing a char", 10, 110, 10, .dark_gray);
        rl.drawText(rl.textFormat("TEXT PARTICLE COUNT: {d}", .{particles.len}), 10, rl.getScreenHeight() - 30, 20, .black);
    }
}

/// Replace the particle at `index` by slices of `slice_length` chars of its text
fn sliceTextParticle(particles: *Particles, index: usize, slice_length: usize) void {
    const tp = particles.buffer[index];
    const length = tp.len;

    if (length > 1 and (particles.len + length) < max_text_particles) {
        var i: usize = 0;
        while (i < length) : (i += slice_length) {
            const content = if (slice_length == 1)
                rl.textFormat("{c}", .{tp.buffer[i]})
            else
                rl.textSubtext(tp.text(), @intCast(i), @intCast(slice_length));
            const color = randomColor();
            const x = tp.rect.x + @as(f32, @floatFromInt(i)) * tp.rect.width / @as(f32, @floatFromInt(length));
            particles.append(.init(content, x, tp.rect.y, color));
        }
        particles.orderedRemove(index);
    }
}

/// Replace the single particle by the pieces of its text split by `char_to_slice`
fn sliceTextParticleByChar(particles: *Particles, char_to_slice: u8) void {
    const tp = particles.buffer[0];
    const tokens = rl.textSplit(tp.text(), char_to_slice);

    if (tokens.len > 1) {
        for (tp.buffer[0..tp.len]) |char| {
            if (char == char_to_slice) {
                const color = randomColor();
                particles.append(.init(rl.textFormat("{c}", .{char_to_slice}), tp.rect.x, tp.rect.y, color));
            }
        }
        for (tokens, 0..) |token_ptr, i| {
            const token = std.mem.span(token_ptr);
            const color = randomColor();
            const x = tp.rect.x + @as(f32, @floatFromInt(i)) * tp.rect.width / @as(f32, @floatFromInt(token.len));
            particles.append(.init(token, x, tp.rect.y, color));
        }
        particles.orderedRemove(0);
    }
}

/// Slice the particle at `index` into single chars
fn shatterTextParticle(particles: *Particles, index: usize) void {
    sliceTextParticle(particles, index, 1);
}

/// Replace the grabbed and target particles by one joining their texts
fn glueTextParticles(particles: *Particles, grabbed: usize, target: usize) void {
    const grabbed_tp = &particles.buffer[grabbed];
    const content = rl.textFormat("{s}{s}", .{ grabbed_tp.text(), particles.buffer[target].text() });

    var tp: TextParticle = .init(content, grabbed_tp.rect.x, grabbed_tp.rect.y, .ray_white);
    tp.grabbed = true;
    particles.append(tp);
    grabbed_tp.grabbed = false;

    // Remove the higher index first so the lower one stays valid
    particles.orderedRemove(@max(grabbed, target));
    particles.orderedRemove(@min(grabbed, target));
}
