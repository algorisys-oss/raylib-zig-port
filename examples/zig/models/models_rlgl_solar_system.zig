//! raylib [models] example - rlgl solar system
//!
//! Zig-API translation of examples/models/models_rlgl_solar_system.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2018-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    const sun_radius: f32 = 4.0;
    const earth_radius: f32 = 0.6;
    const earth_orbit_radius: f32 = 8.0;
    const moon_radius: f32 = 0.16;
    const moon_orbit_radius: f32 = 1.5;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - rlgl solar system");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define the camera to look into our 3d world
    const camera: rl.Camera = .{
        .position = .{ .x = 16.0, .y = 16.0, .z = 16.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const rotation_speed: f32 = 0.2; // General system rotation speed

    var earth_rotation: f32 = 0.0; // Rotation of earth around itself (days) in degrees
    var earth_orbit_rotation: f32 = 0.0; // Rotation of earth around the Sun (years) in degrees
    var moon_rotation: f32 = 0.0; // Rotation of moon around itself
    var moon_orbit_rotation: f32 = 0.0; // Rotation of moon around earth in degrees

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        earth_rotation += 5.0 * rotation_speed;
        earth_orbit_rotation += 365.0 / 360.0 * (5.0 * rotation_speed) * rotation_speed;
        moon_rotation += 2.0 * rotation_speed;
        moon_orbit_rotation += 8.0 * rotation_speed;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.gl.pushMatrix();
            rl.gl.scalef(sun_radius, sun_radius, sun_radius); // Scale Sun
            drawSphereBasic(.gold); // Draw the Sun
            rl.gl.popMatrix();

            rl.gl.pushMatrix();
            rl.gl.rotatef(earth_orbit_rotation, 0.0, 1.0, 0.0); // Rotation for Earth orbit around Sun
            rl.gl.translatef(earth_orbit_radius, 0.0, 0.0); // Translation for Earth orbit

            rl.gl.pushMatrix();
            rl.gl.rotatef(earth_rotation, 0.25, 1.0, 0.0); // Rotation for Earth itself
            rl.gl.scalef(earth_radius, earth_radius, earth_radius); // Scale Earth

            drawSphereBasic(.blue); // Draw the Earth
            rl.gl.popMatrix();

            rl.gl.rotatef(moon_orbit_rotation, 0.0, 1.0, 0.0); // Rotation for Moon orbit around Earth
            rl.gl.translatef(moon_orbit_radius, 0.0, 0.0); // Translation for Moon orbit
            rl.gl.rotatef(moon_rotation, 0.0, 1.0, 0.0); // Rotation for Moon itself
            rl.gl.scalef(moon_radius, moon_radius, moon_radius); // Scale Moon

            drawSphereBasic(.light_gray); // Draw the Moon
            rl.gl.popMatrix();

            // Some reference elements (not affected by previous matrix transformations)
            rl.drawCircle3D(.{ .x = 0.0, .y = 0.0, .z = 0.0 }, earth_orbit_radius, .{ .x = 1, .y = 0, .z = 0 }, 90.0, rl.fade(.red, 0.5));
            rl.drawGrid(20, 1.0);
        }

        rl.drawText("EARTH ORBITING AROUND THE SUN!", 400, 10, 20, .maroon);
        rl.drawFPS(10, 10);
    }
}

/// Draw sphere without any matrix transformation
/// NOTE: Sphere is drawn in world position ( 0, 0, 0 ) with radius 1.0
fn drawSphereBasic(color: rl.Color) void {
    const rings = 16;
    const slices = 16;

    // Make sure there is enough space in the internal render batch
    // buffer to store all required vertex, batch is reseted if required
    _ = rl.gl.checkRenderBatchLimit((rings + 2) * slices * 6);

    rl.gl.begin(rl.gl.triangles);
    defer rl.gl.end();
    rl.gl.color4ub(color.r, color.g, color.b, color.a);

    for (0..rings + 2) |i| {
        for (0..slices) |j| {
            sphereVertex(rings, slices, i, j);
            sphereVertex(rings, slices, i + 1, j + 1);
            sphereVertex(rings, slices, i + 1, j);

            sphereVertex(rings, slices, i, j);
            sphereVertex(rings, slices, i, j + 1);
            sphereVertex(rings, slices, i + 1, j + 1);
        }
    }
}

/// Emit the unit-sphere vertex at latitude step `ring` and longitude step `slice`.
fn sphereVertex(comptime rings: comptime_int, comptime slices: comptime_int, ring: usize, slice: usize) void {
    const lat = rl.deg2rad * (270 + (180.0 / @as(f32, rings + 1)) * @as(f32, @floatFromInt(ring)));
    const lon = rl.deg2rad * (@as(f32, @floatFromInt(slice)) * 360.0 / slices);
    rl.gl.vertex3f(@cos(lat) * @sin(lon), @sin(lat), @cos(lat) * @cos(lon));
}
