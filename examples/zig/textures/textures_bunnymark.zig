//! raylib [textures] example - bunnymark
//!
//! Zig-API translation of examples/textures/textures_bunnymark.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const max_bunnies = 80000; // 80K bunnies limit

// This is the maximum amount of elements (quads) per batch
// NOTE: This value is defined in [rlgl] module and can be changed there
const max_batch_elements = 8192;

const Bunny = struct {
    position: rl.Vector2,
    speed: rl.Vector2,
    color: rl.Color,
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - bunnymark");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Load bunny texture
    const tex_bunny = try rl.loadTexture("resources/raybunny.png");
    defer rl.unloadTexture(tex_bunny);

    // Bunnies storage, filled up to `bunnies_count`
    const bunnies = try std.heap.page_allocator.alloc(Bunny, max_bunnies);
    defer std.heap.page_allocator.free(bunnies);
    var bunnies_count: usize = 0;

    var paused = false;

    const half_width = @as(f32, @floatFromInt(tex_bunny.width)) / 2;
    const half_height = @as(f32, @floatFromInt(tex_bunny.height)) / 2;

    rl.setTargetFPS(0); // Set our game to run with an uncapped framerate

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isMouseButtonDown(.left)) {
            // Create more bunnies
            for (0..100) |_| {
                if (bunnies_count < max_bunnies) {
                    const position = rl.getMousePosition();
                    const speed_x: f32 = @floatFromInt(rl.getRandomValue(-250, 250));
                    const speed_y: f32 = @floatFromInt(rl.getRandomValue(-250, 250));
                    const r: u8 = @intCast(rl.getRandomValue(50, 240));
                    const g: u8 = @intCast(rl.getRandomValue(80, 240));
                    const b: u8 = @intCast(rl.getRandomValue(100, 240));
                    bunnies[bunnies_count] = .{
                        .position = position,
                        .speed = .{ .x = speed_x, .y = speed_y },
                        .color = .{ .r = r, .g = g, .b = b, .a = 255 },
                    };
                    bunnies_count += 1;
                }
            }
        }

        if (rl.isKeyPressed(.p)) paused = !paused;

        if (!paused) {
            // Update bunnies
            const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
            const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
            for (bunnies[0..bunnies_count]) |*bunny| {
                bunny.position.x += bunny.speed.x * rl.getFrameTime();
                bunny.position.y += bunny.speed.y * rl.getFrameTime();

                if (((bunny.position.x + half_width) > screen_w) or
                    ((bunny.position.x + half_width) < 0)) bunny.speed.x *= -1;
                if (((bunny.position.y + half_height) > screen_h) or
                    ((bunny.position.y + half_height - 40) < 0)) bunny.speed.y *= -1;
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        for (bunnies[0..bunnies_count]) |bunny| {
            // NOTE: When internal batch buffer limit is reached (MAX_BATCH_ELEMENTS),
            // a draw call is launched and buffer starts being filled again;
            // before issuing a draw call, updated vertex data from internal CPU buffer is send to GPU...
            // Process of sending data is costly and it could happen that GPU data has not been completely
            // processed for drawing while new data is tried to be sent (updating current in-use buffers)
            // it could generates a stall and consequently a frame drop, limiting the number of drawn bunnies
            rl.drawTexture(tex_bunny, @intFromFloat(bunny.position.x), @intFromFloat(bunny.position.y), bunny.color);
        }

        rl.drawRectangle(0, 0, screen_width, 40, .black);
        rl.drawText(rl.textFormat("bunnies: {d}", .{bunnies_count}), 120, 10, 20, .green);
        rl.drawText(rl.textFormat("batched draw calls: {d}", .{1 + bunnies_count / max_batch_elements}), 320, 10, 20, .maroon);

        rl.drawFPS(10, 10);
    }
}
