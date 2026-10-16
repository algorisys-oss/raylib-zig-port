//! raylib [shaders] example - spotlight rendering
//!
//! Zig-API translation of examples/shaders/shaders_spotlight_rendering.c (raylib 6.2).
//! Example contributed by Chris Camacho (@chriscamacho) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Chris Camacho (@chriscamacho) and Ramon Santamaria (@raysan5)
//!
//! The shader makes alpha holes in the forground to give the appearance of a top
//! down look at a spotlight casting a pool of light...
//!
//! The right hand side of the screen there is just enough light to see whats
//! going on without the spot light, great for a stealth type game where you
//! have to avoid the spotlights
//!
//! The left hand side of the screen is in pitch dark except for where the spotlights are
//!
//! Although this example doesn't scale like the letterbox example, you could integrate
//! the two techniques, but by scaling the actual colour of the render texture rather
//! than using alpha as a mask

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

const max_spots = 3; // NOTE: It must be the same as define in shader
const max_stars = 400;

const screen_width = 800;
const screen_height = 450;

/// Spot data
const Spot = struct {
    position: rl.Vector2,
    speed: rl.Vector2,
    inner: f32,
    radius: f32,

    // Shader locations
    position_loc: i32,
    inner_loc: i32,
    radius_loc: i32,
};

/// Stars in the star field have a position and velocity
const Star = struct {
    position: rl.Vector2,
    speed: rl.Vector2,

    fn randomSpeed() f32 {
        return @as(f32, @floatFromInt(rl.getRandomValue(-1000, 1000))) / 100.0;
    }

    fn reset(star: *Star) void {
        star.position = .{
            .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
            .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
        };

        star.speed.x = randomSpeed();
        star.speed.y = randomSpeed();

        // NOTE: upstream tests `!(fabs(x) + (fabs(y) > 1))`, which (by operator
        // precedence) rerolls only a star with no x speed and |y speed| <= 1
        while (star.speed.x == 0 and @abs(star.speed.y) <= 1) {
            star.speed.x = randomSpeed();
            star.speed.y = randomSpeed();
        }

        star.position = rl.math.vector2Add(star.position, rl.math.vector2Multiply(star.speed, .{ .x = 8.0, .y = 8.0 }));
    }

    fn update(star: *Star) void {
        star.position = rl.math.vector2Add(star.position, star.speed);

        const width: f32 = @floatFromInt(rl.getScreenWidth());
        const height: f32 = @floatFromInt(rl.getScreenHeight());
        if (star.position.x < 0 or star.position.x > width or
            star.position.y < 0 or star.position.y > height) star.reset();
    }
};

pub fn main() !void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - spotlight rendering");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.hideCursor();

    const tex_ray = try rl.loadTexture("resources/raysan.png");
    defer rl.unloadTexture(tex_ray);

    var stars: [max_stars]Star = undefined;
    for (&stars) |*star| star.reset();

    // Progress all the stars on, so they don't all start in the centre
    for (0..screen_width / 2) |_| {
        for (&stars) |*star| star.update();
    }

    var frame_counter: i32 = 0;

    // Use default vert shader
    const shdr_spot = try rl.loadShader(null, std.fmt.comptimePrint("resources/shaders/glsl{d}/spotlight.fs", .{glsl_version}));
    defer rl.unloadShader(shdr_spot);

    // Get the locations of spots in the shader
    var spots: [max_spots]Spot = undefined;
    for (&spots, 0..) |*spot, i| {
        spot.position_loc = rl.getShaderLocation(shdr_spot, rl.textFormat("spots[{d}].pos", .{i}));
        spot.inner_loc = rl.getShaderLocation(shdr_spot, rl.textFormat("spots[{d}].inner", .{i}));
        spot.radius_loc = rl.getShaderLocation(shdr_spot, rl.textFormat("spots[{d}].radius", .{i}));
    }

    // Tell the shader how wide the screen is so we can have
    // a pitch black half and a dimly lit half
    const w_loc = rl.getShaderLocation(shdr_spot, "screenWidth");
    const sw: f32 = @floatFromInt(rl.getScreenWidth());
    rl.setShaderValue(shdr_spot, w_loc, &sw, .float);

    // Randomize the locations and velocities of the spotlights
    // and initialize the shader locations
    for (&spots, 0..) |*spot, i| {
        spot.position.x = @floatFromInt(rl.getRandomValue(64, screen_width - 64));
        spot.position.y = @floatFromInt(rl.getRandomValue(64, screen_height - 64));
        spot.speed = .{ .x = 0, .y = 0 };

        // NOTE: upstream sums the speeds in double precision (fabs)
        while (@abs(@as(f64, spot.speed.x)) + @abs(@as(f64, spot.speed.y)) < 2) {
            spot.speed.x = @as(f32, @floatFromInt(rl.getRandomValue(-400, 40))) / 25.0;
            spot.speed.y = @as(f32, @floatFromInt(rl.getRandomValue(-400, 40))) / 25.0;
        }

        const n: f32 = @floatFromInt(i + 1);
        spot.inner = 28.0 * n;
        spot.radius = 48.0 * n;

        rl.setShaderValue(shdr_spot, spot.position_loc, &spot.position, .vec2);
        rl.setShaderValue(shdr_spot, spot.inner_loc, &spot.inner, .float);
        rl.setShaderValue(shdr_spot, spot.radius_loc, &spot.radius, .float);
    }

    rl.setTargetFPS(60); // Set  to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        frame_counter += 1;

        // Move the stars, resetting them if the go offscreen
        for (&stars) |*star| star.update();

        // Update the spots, send them to the shader
        for (&spots, 0..) |*spot, i| {
            if (i == 0) {
                const mp = rl.getMousePosition();
                spot.position.x = mp.x;
                spot.position.y = screen_height - mp.y;
            } else {
                spot.position.x += spot.speed.x;
                spot.position.y += spot.speed.y;

                if (spot.position.x < 64) spot.speed.x = -spot.speed.x;
                if (spot.position.x > screen_width - 64) spot.speed.x = -spot.speed.x;
                if (spot.position.y < 64) spot.speed.y = -spot.speed.y;
                if (spot.position.y > screen_height - 64) spot.speed.y = -spot.speed.y;
            }

            rl.setShaderValue(shdr_spot, spot.position_loc, &spot.position, .vec2);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.dark_blue);

        // Draw stars and bobs
        for (stars) |star| {
            // Single pixel is just too small these days!
            rl.drawRectangle(@intFromFloat(star.position.x), @intFromFloat(star.position.y), 2, 2, .white);
        }

        // NOTE: upstream computes the bob positions in double precision (cos/sin)
        const half_width: f64 = @as(f32, screen_width) / @as(f32, 2.0);
        const half_height: f64 = @as(f32, screen_height) / @as(f32, 2.0);
        const x_radius: f64 = @as(f32, screen_width) / @as(f32, 2.2);
        const y_radius: f64 = @as(f32, screen_height) / @as(f32, 4.2);
        for (0..16) |i| {
            const t: f32 = @floatFromInt(frame_counter + @as(i32, @intCast(i)) * 8);
            rl.drawTexture(
                tex_ray,
                @intFromFloat(half_width + @cos(@as(f64, t / 51.45)) * x_radius - 32),
                @intFromFloat(half_height + @sin(@as(f64, t / 17.87)) * y_radius),
                .white,
            );
        }

        // Draw spot lights
        {
            rl.beginShaderMode(shdr_spot);
            defer rl.endShaderMode();

            // Instead of a blank rectangle you could render here
            // a render texture of the full screen used to do screen
            // scaling (slight adjustment to shader would be required
            // to actually pay attention to the colour!)
            rl.drawRectangle(0, 0, screen_width, screen_height, .white);
        }

        rl.drawFPS(10, 10);

        rl.drawText("Move the mouse!", 10, 30, 20, .green);
        rl.drawText("Pitch Black", @intFromFloat(@as(f32, screen_width) * 0.2), screen_height / 2, 20, .green);
        rl.drawText("Dark", @intFromFloat(@as(f32, screen_width) * 0.66), screen_height / 2, 20, .green);
    }
}
