//! raylib [core] example - 2d camera platformer
//!
//! Zig-API translation of examples/core/core_2d_camera_platformer.c (raylib 6.2).
//! Example contributed by arvyy (@arvyy) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 arvyy (@arvyy)

const std = @import("std");
const rl = @import("raylib");
const rm = rl.math;

const gravity = 400;
const player_jump_spd: f32 = 350.0;
const player_hor_spd: f32 = 200.0;

const Player = struct {
    position: rl.Vector2,
    speed: f32,
    can_jump: bool,
};

const EnvItem = struct {
    rect: rl.Rectangle,
    blocking: bool,
    color: rl.Color,
};

/// Every camera mode updates the camera from the player, the map and the frame delta.
const CameraUpdater = *const fn (camera: *rl.Camera2D, player: *const Player, env_items: []const EnvItem, delta: f32, width: i32, height: i32) void;

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - 2d camera platformer");
    defer rl.closeWindow(); // Close window and OpenGL context

    var player: Player = .{ .position = .{ .x = 400, .y = 280 }, .speed = 0, .can_jump = false };
    const env_items = [_]EnvItem{
        .{ .rect = .{ .x = 0, .y = 0, .width = 1000, .height = 400 }, .blocking = false, .color = .light_gray },
        .{ .rect = .{ .x = 0, .y = 400, .width = 1000, .height = 200 }, .blocking = true, .color = .gray },
        .{ .rect = .{ .x = 300, .y = 200, .width = 400, .height = 10 }, .blocking = true, .color = .gray },
        .{ .rect = .{ .x = 250, .y = 300, .width = 100, .height = 10 }, .blocking = true, .color = .gray },
        .{ .rect = .{ .x = 650, .y = 300, .width = 100, .height = 10 }, .blocking = true, .color = .gray },
    };

    var camera: rl.Camera2D = .{
        .target = player.position,
        .offset = .{
            .x = @as(f32, @floatFromInt(rl.getRenderWidth())) / 2.0,
            .y = @as(f32, @floatFromInt(rl.getRenderHeight())) / 2.0,
        },
        .rotation = 0.0,
        .zoom = 1.0,
    };

    // The multiple update camera functions
    const camera_updaters = [_]CameraUpdater{
        updateCameraCenter,
        updateCameraCenterInsideMap,
        updateCameraCenterSmoothFollow,
        updateCameraEvenOutOnLanding,
        updateCameraPlayerBoundsPush,
    };

    var camera_option: usize = 0;

    const camera_descriptions = [camera_updaters.len][:0]const u8{
        "Follow player center",
        "Follow player center, but clamp to map edges",
        "Follow player center; smoothed",
        "Follow player center horizontally; update player center vertically after landing",
        "Player push camera on getting too close to screen edge",
    };

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        const delta_time = rl.getFrameTime();

        updatePlayer(&player, &env_items, delta_time);

        camera.zoom += rl.getMouseWheelMove() * 0.05;
        camera.zoom = std.math.clamp(camera.zoom, 0.25, 3.0);

        if (rl.isKeyPressed(.r)) {
            camera.zoom = 1.0;
            player.position = .{ .x = 400, .y = 280 };
        }

        if (rl.isKeyPressed(.c)) camera_option = (camera_option + 1) % camera_updaters.len;

        // Call update camera function by its pointer
        camera_updaters[camera_option](&camera, &player, &env_items, delta_time, screen_width, screen_height);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.light_gray);

        {
            rl.beginMode2D(camera);
            defer rl.endMode2D();

            for (env_items) |item| rl.drawRectangleRec(item.rect, item.color);

            const player_rect: rl.Rectangle = .{ .x = player.position.x - 20, .y = player.position.y - 40, .width = 40.0, .height = 40.0 };
            rl.drawRectangleRec(player_rect, .red);

            rl.drawCircleV(player.position, 5.0, .gold);
        }

        rl.drawText("Controls:", 20, 20, 10, .black);
        rl.drawText("- Right/Left to move", 40, 40, 10, .dark_gray);
        rl.drawText("- Space to jump", 40, 60, 10, .dark_gray);
        rl.drawText("- Mouse Wheel to Zoom in-out", 40, 80, 10, .dark_gray);
        rl.drawText("- R to reset position + zoom", 40, 100, 10, .dark_gray);
        rl.drawText("- C to change camera mode", 40, 120, 10, .dark_gray);
        rl.drawText("Current camera mode:", 20, 140, 10, .black);
        rl.drawText(camera_descriptions[camera_option], 40, 160, 10, .dark_gray);
    }
}

fn updatePlayer(player: *Player, env_items: []const EnvItem, delta: f32) void {
    if (rl.isKeyDown(.left)) player.position.x -= player_hor_spd * delta;
    if (rl.isKeyDown(.right)) player.position.x += player_hor_spd * delta;
    if (rl.isKeyDown(.space) and player.can_jump) {
        player.speed = -player_jump_spd;
        player.can_jump = false;
    }

    const p = &player.position;
    for (env_items) |item| {
        if (item.blocking and
            item.rect.x <= p.x and
            item.rect.x + item.rect.width >= p.x and
            item.rect.y >= p.y and
            item.rect.y <= p.y + player.speed * delta)
        {
            player.speed = 0.0;
            p.y = item.rect.y;
            player.can_jump = true;
            break;
        }
    } else {
        player.position.y += player.speed * delta;
        player.speed += gravity * delta;
        player.can_jump = false;
    }
}

fn screenCenter(width: i32, height: i32) rl.Vector2 {
    return .{ .x = @as(f32, @floatFromInt(width)) / 2.0, .y = @as(f32, @floatFromInt(height)) / 2.0 };
}

fn updateCameraCenter(camera: *rl.Camera2D, player: *const Player, _: []const EnvItem, _: f32, width: i32, height: i32) void {
    camera.offset = screenCenter(width, height);
    camera.target = player.position;
}

fn updateCameraCenterInsideMap(camera: *rl.Camera2D, player: *const Player, env_items: []const EnvItem, _: f32, width: i32, height: i32) void {
    camera.target = player.position;
    camera.offset = screenCenter(width, height);
    var min_x: f32 = 1000;
    var min_y: f32 = 1000;
    var max_x: f32 = -1000;
    var max_y: f32 = -1000;

    for (env_items) |item| {
        min_x = @min(item.rect.x, min_x);
        max_x = @max(item.rect.x + item.rect.width, max_x);
        min_y = @min(item.rect.y, min_y);
        max_y = @max(item.rect.y + item.rect.height, max_y);
    }

    const max = rl.getWorldToScreen2D(.{ .x = max_x, .y = max_y }, camera.*);
    const min = rl.getWorldToScreen2D(.{ .x = min_x, .y = min_y }, camera.*);

    const w: f32 = @floatFromInt(width);
    const h: f32 = @floatFromInt(height);
    if (max.x < w) camera.offset.x = w - (max.x - w / 2);
    if (max.y < h) camera.offset.y = h - (max.y - h / 2);
    if (min.x > 0) camera.offset.x = w / 2 - min.x;
    if (min.y > 0) camera.offset.y = h / 2 - min.y;
}

fn updateCameraCenterSmoothFollow(camera: *rl.Camera2D, player: *const Player, _: []const EnvItem, delta: f32, width: i32, height: i32) void {
    const min_speed = 30;
    const min_effect_length = 10;
    const fraction_speed = 0.8;

    camera.offset = screenCenter(width, height);
    const diff = rm.vector2Subtract(player.position, camera.target);
    const length = rm.vector2Length(diff);

    if (length > min_effect_length) {
        const speed = @max(fraction_speed * length, min_speed);
        camera.target = rm.vector2Add(camera.target, rm.vector2Scale(diff, speed * delta / length));
    }
}

/// Camera state that persists across frames (C: function-local statics).
const even_out = struct {
    const speed = 700;
    var active = false;
    var target: f32 = 0;
};

fn updateCameraEvenOutOnLanding(camera: *rl.Camera2D, player: *const Player, _: []const EnvItem, delta: f32, width: i32, height: i32) void {
    camera.offset = screenCenter(width, height);
    camera.target.x = player.position.x;

    if (even_out.active) {
        if (even_out.target > camera.target.y) {
            camera.target.y += even_out.speed * delta;

            if (camera.target.y > even_out.target) {
                camera.target.y = even_out.target;
                even_out.active = false;
            }
        } else {
            camera.target.y -= even_out.speed * delta;

            if (camera.target.y < even_out.target) {
                camera.target.y = even_out.target;
                even_out.active = false;
            }
        }
    } else if (player.can_jump and player.speed == 0 and player.position.y != camera.target.y) {
        even_out.active = true;
        even_out.target = player.position.y;
    }
}

fn updateCameraPlayerBoundsPush(camera: *rl.Camera2D, player: *const Player, _: []const EnvItem, _: f32, width: i32, height: i32) void {
    const bbox: rl.Vector2 = .{ .x = 0.2, .y = 0.2 };

    const w: f32 = @floatFromInt(width);
    const h: f32 = @floatFromInt(height);
    const bbox_world_min = rl.getScreenToWorld2D(.{ .x = (1 - bbox.x) * 0.5 * w, .y = (1 - bbox.y) * 0.5 * h }, camera.*);
    const bbox_world_max = rl.getScreenToWorld2D(.{ .x = (1 + bbox.x) * 0.5 * w, .y = (1 + bbox.y) * 0.5 * h }, camera.*);
    camera.offset = .{ .x = (1 - bbox.x) * 0.5 * w, .y = (1 - bbox.y) * 0.5 * h };

    if (player.position.x < bbox_world_min.x) camera.target.x = player.position.x;
    if (player.position.y < bbox_world_min.y) camera.target.y = player.position.y;
    if (player.position.x > bbox_world_max.x) camera.target.x = bbox_world_min.x + (player.position.x - bbox_world_max.x);
    if (player.position.y > bbox_world_max.y) camera.target.y = bbox_world_min.y + (player.position.y - bbox_world_max.y);
}
