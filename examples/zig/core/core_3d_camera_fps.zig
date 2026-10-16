//! raylib [core] example - 3d camera fps
//!
//! Zig-API translation of examples/core/core_3d_camera_fps.c (raylib 6.2).
//! Example contributed by Agnis Aldiņš (@nezvers) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Agnis Aldiņš (@nezvers)

const std = @import("std");
const rl = @import("raylib");
const rm = rl.math;

const pi: f32 = std.math.pi;

// Movement constants
const gravity: f32 = 32.0;
const max_speed: f32 = 20.0;
const crouch_speed: f32 = 5.0;
const jump_force: f32 = 12.0;
const max_accel: f32 = 150.0;
// Grounded drag
const friction: f32 = 0.86;
// Increasing air drag, increases strafing speed
const air_drag: f32 = 0.98;
// Responsiveness for turning movement direction to looked direction
const control: f32 = 15.0;
const crouch_height: f32 = 0.0;
const stand_height: f32 = 1.0;
const bottom_height: f32 = 0.5;

// Slow down diagonal movement
const normalize_input = true;

/// Body structure
const Body = struct {
    position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    velocity: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    dir: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    is_grounded: bool = false,
};

const sensitivity: rl.Vector2 = .{ .x = 0.001, .y = 0.001 };

var player: Body = .{};
var look_rotation: rl.Vector2 = .{ .x = 0, .y = 0 };
var head_timer: f32 = 0.0;
var walk_lerp: f32 = 0.0;
var head_lerp: f32 = stand_height;
var lean: rl.Vector2 = .{ .x = 0, .y = 0 };

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - 3d camera fps");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Initialize camera variables
    // NOTE: updateCameraFps() takes care of the rest
    var camera: rl.Camera = .{
        .position = .{
            .x = player.position.x,
            .y = player.position.y + (bottom_height + head_lerp),
            .z = player.position.z,
        },
        .target = .{ .x = 0, .y = 0, .z = 0 },
        .up = .{ .x = 0, .y = 0, .z = 0 },
        .fovy = 60.0,
        .projection = .perspective,
    };

    updateCameraFps(&camera); // Update camera parameters

    rl.disableCursor(); // Limit cursor to relative movement inside the window

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_delta = rl.getMouseDelta();
        look_rotation.x -= mouse_delta.x * sensitivity.x;
        look_rotation.y += mouse_delta.y * sensitivity.y;

        const sideway = axis(.d, .a);
        const forward = axis(.w, .s);
        const crouching = rl.isKeyDown(.left_control);
        updateBody(&player, look_rotation.x, sideway, forward, rl.isKeyPressed(.space), crouching);

        const delta = rl.getFrameTime();
        head_lerp = rm.lerp(head_lerp, if (crouching) crouch_height else stand_height, 20.0 * delta);
        camera.position = .{
            .x = player.position.x,
            .y = player.position.y + (bottom_height + head_lerp),
            .z = player.position.z,
        };

        if (player.is_grounded and (forward != 0 or sideway != 0)) {
            head_timer += delta * 3.0;
            walk_lerp = rm.lerp(walk_lerp, 1.0, 10.0 * delta);
            camera.fovy = rm.lerp(camera.fovy, 55.0, 5.0 * delta);
        } else {
            walk_lerp = rm.lerp(walk_lerp, 0.0, 10.0 * delta);
            camera.fovy = rm.lerp(camera.fovy, 60.0, 5.0 * delta);
        }

        lean.x = rm.lerp(lean.x, @as(f32, @floatFromInt(sideway)) * 0.02, 10.0 * delta);
        lean.y = rm.lerp(lean.y, @as(f32, @floatFromInt(forward)) * 0.015, 10.0 * delta);

        updateCameraFps(&camera);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            drawLevel();
        }

        // Draw info box
        rl.drawRectangle(5, 5, 330, 75, rl.fade(.sky_blue, 0.5));
        rl.drawRectangleLines(5, 5, 330, 75, .blue);

        rl.drawText("Camera controls:", 15, 15, 10, .black);
        rl.drawText("- Move keys: W, A, S, D, Space, Left-Ctrl", 15, 30, 10, .black);
        rl.drawText("- Look around: arrow keys or mouse", 15, 45, 10, .black);
        const velocity_length = rm.vector2Length(.{ .x = player.velocity.x, .y = player.velocity.z });
        rl.drawText(rl.textFormat("- Velocity Len: ({d:0>6.3})", .{velocity_length}), 15, 60, 10, .black);
    }
}

/// -1, 0 or 1 from a pair of opposing keys
fn axis(positive: rl.KeyboardKey, negative: rl.KeyboardKey) i8 {
    return @as(i8, @intFromBool(rl.isKeyDown(positive))) - @intFromBool(rl.isKeyDown(negative));
}

/// Update body considering current world state
fn updateBody(body: *Body, rot: f32, side: i8, forward: i8, jump_pressed: bool, crouch_hold: bool) void {
    var input: rl.Vector2 = .{ .x = @floatFromInt(side), .y = @floatFromInt(-forward) };

    if (normalize_input and side != 0 and forward != 0) input = rm.vector2Normalize(input);

    const delta = rl.getFrameTime();

    if (!body.is_grounded) body.velocity.y -= gravity * delta;

    if (body.is_grounded and jump_pressed) {
        body.velocity.y = jump_force;
        body.is_grounded = false;

        // Sound can be played at this moment
        //rl.setSoundPitch(fx_jump, 1.0 + (rl.getRandomValue(-100, 100)*0.001));
        //rl.playSound(fx_jump);
    }

    const front: rl.Vector3 = .{ .x = @sin(rot), .y = 0.0, .z = @cos(rot) };
    const right: rl.Vector3 = .{ .x = @cos(-rot), .y = 0.0, .z = @sin(-rot) };

    const desired_dir: rl.Vector3 = .{
        .x = input.x * right.x + input.y * front.x,
        .y = 0.0,
        .z = input.x * right.z + input.y * front.z,
    };
    body.dir = rm.vector3Lerp(body.dir, desired_dir, control * delta);

    const decel = if (body.is_grounded) friction else air_drag;
    var hvel: rl.Vector3 = .{ .x = body.velocity.x * decel, .y = 0.0, .z = body.velocity.z * decel };

    const hvel_length = rm.vector3Length(hvel); // Magnitude
    if (hvel_length < max_speed * 0.01) hvel = .{ .x = 0, .y = 0, .z = 0 };

    // This is what creates strafing
    const speed = rm.vector3DotProduct(hvel, body.dir);

    // Whenever the amount of acceleration to add is clamped by the maximum acceleration constant,
    // a Player can make the speed faster by bringing the direction closer to horizontal velocity angle
    // More info here: https://youtu.be/v3zT3Z5apaM?t=165
    const top_speed = if (crouch_hold) crouch_speed else max_speed;
    const accel = rm.clamp(top_speed - speed, 0.0, max_accel * delta);
    hvel.x += body.dir.x * accel;
    hvel.z += body.dir.z * accel;

    body.velocity.x = hvel.x;
    body.velocity.z = hvel.z;

    body.position.x += body.velocity.x * delta;
    body.position.y += body.velocity.y * delta;
    body.position.z += body.velocity.z * delta;

    // Fancy collision system against the floor
    if (body.position.y <= 0.0) {
        body.position.y = 0.0;
        body.velocity.y = 0.0;
        body.is_grounded = true; // Enable jumping
    }
}

/// Update camera for FPS behaviour
fn updateCameraFps(camera: *rl.Camera) void {
    const up: rl.Vector3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 };
    const target_offset: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = -1.0 };

    // Left and right
    const yaw = rm.vector3RotateByAxisAngle(target_offset, up, look_rotation.x);

    // Clamp view up
    var max_angle_up = rm.vector3Angle(up, yaw);
    max_angle_up -= 0.001; // Avoid numerical errors
    if (-look_rotation.y > max_angle_up) look_rotation.y = -max_angle_up;

    // Clamp view down
    var max_angle_down = rm.vector3Angle(rm.vector3Negate(up), yaw);
    max_angle_down *= -1.0; // Downwards angle is negative
    max_angle_down += 0.001; // Avoid numerical errors
    if (-look_rotation.y < max_angle_down) look_rotation.y = -max_angle_down;

    // Up and down
    const right = rm.vector3Normalize(rm.vector3CrossProduct(yaw, up));

    // Rotate view vector around right axis
    var pitch_angle = -look_rotation.y - lean.y;
    pitch_angle = rm.clamp(pitch_angle, -pi / 2 + 0.0001, pi / 2 - 0.0001); // Clamp angle so it doesn't go past straight up or straight down
    const pitch = rm.vector3RotateByAxisAngle(yaw, right, pitch_angle);

    // Head animation
    // Rotate up direction around forward axis
    const head_sin = @sin(head_timer * pi);
    const head_cos = @cos(head_timer * pi);
    const step_rotation = 0.01;
    camera.up = rm.vector3RotateByAxisAngle(up, pitch, head_sin * step_rotation + lean.x);

    // Camera BOB
    const bob_side = 0.1;
    const bob_up = 0.15;
    var bobbing = rm.vector3Scale(right, head_sin * bob_side);
    bobbing.y = @abs(head_cos * bob_up);

    camera.position = rm.vector3Add(camera.position, rm.vector3Scale(bobbing, walk_lerp));
    camera.target = rm.vector3Add(camera.position, pitch);
}

/// Draw game level
fn drawLevel() void {
    const floor_extent = 25;
    const tile_size: f32 = 5.0;
    const tile_color1: rl.Color = .{ .r = 150, .g = 200, .b = 200, .a = 255 };

    // Floor tiles
    var y: i32 = -floor_extent;
    while (y < floor_extent) : (y += 1) {
        var x: i32 = -floor_extent;
        while (x < floor_extent) : (x += 1) {
            const position: rl.Vector3 = .{ .x = @as(f32, @floatFromInt(x)) * tile_size, .y = 0.0, .z = @as(f32, @floatFromInt(y)) * tile_size };
            if (y & 1 != 0 and x & 1 != 0) {
                rl.drawPlane(position, .{ .x = tile_size, .y = tile_size }, tile_color1);
            } else if (y & 1 == 0 and x & 1 == 0) {
                rl.drawPlane(position, .{ .x = tile_size, .y = tile_size }, .light_gray);
            }
        }
    }

    const tower_size: rl.Vector3 = .{ .x = 16.0, .y = 32.0, .z = 16.0 };
    const tower_color: rl.Color = .{ .r = 150, .g = 200, .b = 200, .a = 255 };

    // One tower in each quadrant
    var tower_pos: rl.Vector3 = .{ .x = 16.0, .y = 16.0, .z = 16.0 };
    for ([_]enum { none, x, z }{ .none, .x, .z, .x }) |flip| {
        switch (flip) {
            .none => {},
            .x => tower_pos.x *= -1,
            .z => tower_pos.z *= -1,
        }
        rl.drawCubeV(tower_pos, tower_size, tower_color);
        rl.drawCubeWiresV(tower_pos, tower_size, .dark_blue);
    }

    // Red sun
    rl.drawSphere(.{ .x = 300.0, .y = 300.0, .z = 0.0 }, 100.0, .{ .r = 255, .g = 0, .b = 0, .a = 255 });
}
