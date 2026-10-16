//! raylib [core] example - automation events
//!
//! Zig-API translation of examples/core/core_automation_events.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2023-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const gravity = 400;
const player_jump_spd: f32 = 350.0;
const player_hor_spd: f32 = 200.0;

const Player = struct {
    position: rl.Vector2,
    speed: f32,
    can_jump: bool,

    const start: Player = .{ .position = .{ .x = 400, .y = 280 }, .speed = 0, .can_jump = false };
};

const EnvElement = struct {
    rect: rl.Rectangle,
    blocking: bool,
    color: rl.Color,
};

const screen_width = 800;
const screen_height = 450;

pub fn main() void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [core] example - automation events");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Define player
    var player: Player = .start;

    // Define environment elements (platforms)
    const env_elements = [_]EnvElement{
        .{ .rect = .{ .x = 0, .y = 0, .width = 1000, .height = 400 }, .blocking = false, .color = .light_gray },
        .{ .rect = .{ .x = 0, .y = 400, .width = 1000, .height = 200 }, .blocking = true, .color = .gray },
        .{ .rect = .{ .x = 300, .y = 200, .width = 400, .height = 10 }, .blocking = true, .color = .gray },
        .{ .rect = .{ .x = 250, .y = 300, .width = 100, .height = 10 }, .blocking = true, .color = .gray },
        .{ .rect = .{ .x = 650, .y = 300, .width = 100, .height = 10 }, .blocking = true, .color = .gray },
    };

    // Define camera
    var camera = resetCamera(player);

    // Automation events
    var aelist = rl.loadAutomationEventList(null); // Initialize list of automation events to record new events
    defer rl.unloadAutomationEventList(aelist);
    rl.setAutomationEventList(&aelist);
    var event_recording = false;
    var event_playing = false;

    var frame_counter: u32 = 0;
    var play_frame_counter: u32 = 0;
    var current_play_frame: u32 = 0;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        const delta_time: f32 = 0.015; // rl.getFrameTime();

        // Dropped files logic
        if (rl.isFileDropped()) {
            const dropped_files = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(dropped_files); // Unload filepaths from memory

            // Supports loading .rgs style files (text or binary) and .png style palette images
            const path = std.mem.span(dropped_files.slice()[0]);
            if (rl.isFileExtension(path, ".txt;.rae")) {
                rl.unloadAutomationEventList(aelist);
                aelist = rl.loadAutomationEventList(path);

                event_recording = false;

                // Reset scene state to play
                event_playing = true;
                play_frame_counter = 0;
                current_play_frame = 0;

                player = .start;
                camera = resetCamera(player);
            }
        }

        // Update player
        if (rl.isKeyDown(.left)) player.position.x -= player_hor_spd * delta_time;
        if (rl.isKeyDown(.right)) player.position.x += player_hor_spd * delta_time;
        if (rl.isKeyDown(.space) and player.can_jump) {
            player.speed = -player_jump_spd;
            player.can_jump = false;
        }

        var hit_obstacle = false;
        for (env_elements) |element| {
            const p = &player.position;
            if (element.blocking and
                element.rect.x <= p.x and
                element.rect.x + element.rect.width >= p.x and
                element.rect.y >= p.y and
                element.rect.y <= p.y + player.speed * delta_time)
            {
                hit_obstacle = true;
                player.speed = 0.0;
                p.y = element.rect.y;
            }
        }

        if (!hit_obstacle) {
            player.position.y += player.speed * delta_time;
            player.speed += gravity * delta_time;
            player.can_jump = false;
        } else player.can_jump = true;

        if (rl.isKeyPressed(.r)) {
            // Reset game state
            player = .start;
            camera = resetCamera(player);
        }

        // Events playing
        // NOTE: Logic must be before Camera update because it depends on mouse-wheel value,
        // that can be set by the played event... but some other inputs could be affected
        if (event_playing) {
            // NOTE: Multiple events could be executed in a single frame
            const events = aelist.slice();
            while (play_frame_counter == events[current_play_frame].frame) {
                rl.playAutomationEvent(events[current_play_frame]);
                current_play_frame += 1;

                if (current_play_frame == aelist.count) {
                    event_playing = false;
                    current_play_frame = 0;
                    play_frame_counter = 0;

                    rl.traceLog(.info, "FINISH PLAYING!", .{});
                    break;
                }
            }

            play_frame_counter += 1;
        }

        // Update camera
        camera.target = player.position;
        camera.offset = renderCenter();
        var min_x: f32 = 1000;
        var min_y: f32 = 1000;
        var max_x: f32 = -1000;
        var max_y: f32 = -1000;

        // WARNING: On event replay, mouse-wheel internal value is set
        camera.zoom += rl.getMouseWheelMove() * 0.05;
        camera.zoom = std.math.clamp(camera.zoom, 0.25, 3.0);

        for (env_elements) |element| {
            min_x = @min(element.rect.x, min_x);
            max_x = @max(element.rect.x + element.rect.width, max_x);
            min_y = @min(element.rect.y, min_y);
            max_y = @max(element.rect.y + element.rect.height, max_y);
        }

        const max = rl.getWorldToScreen2D(.{ .x = max_x, .y = max_y }, camera);
        const min = rl.getWorldToScreen2D(.{ .x = min_x, .y = min_y }, camera);

        if (max.x < screen_width) camera.offset.x = screen_width - (max.x - screen_width / 2.0);
        if (max.y < screen_height) camera.offset.y = screen_height - (max.y - screen_height / 2.0);
        if (min.x > 0) camera.offset.x = screen_width / 2.0 - min.x;
        if (min.y > 0) camera.offset.y = screen_height / 2.0 - min.y;

        // Events management
        if (rl.isKeyPressed(.s)) { // Toggle events recording
            if (!event_playing) {
                if (event_recording) {
                    rl.stopAutomationEventRecording();
                    event_recording = false;

                    _ = rl.exportAutomationEventList(aelist, "automation.rae");

                    rl.traceLog(.info, "RECORDED FRAMES: {d}", .{aelist.count});
                } else {
                    rl.setAutomationEventBaseFrame(180);
                    rl.startAutomationEventRecording();
                    event_recording = true;
                }
            }
        } else if (rl.isKeyPressed(.a)) { // Toggle events playing (WARNING: Starts next frame)
            if (!event_recording and aelist.count > 0) {
                // Reset scene state to play
                event_playing = true;
                play_frame_counter = 0;
                current_play_frame = 0;

                player = .start;
                camera = resetCamera(player);
            }
        }

        if (event_recording or event_playing) frame_counter += 1 else frame_counter = 0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.light_gray);

        {
            rl.beginMode2D(camera);
            defer rl.endMode2D();

            // Draw environment elements
            for (env_elements) |element| rl.drawRectangleRec(element.rect, element.color);

            // Draw player rectangle
            rl.drawRectangleRec(.{ .x = player.position.x - 20, .y = player.position.y - 40, .width = 40, .height = 40 }, .red);
        }

        // Draw game controls
        rl.drawRectangle(10, 10, 290, 145, rl.fade(.sky_blue, 0.5));
        rl.drawRectangleLines(10, 10, 290, 145, rl.fade(.blue, 0.8));

        rl.drawText("Controls:", 20, 20, 10, .black);
        rl.drawText("- RIGHT | LEFT: Player movement", 30, 40, 10, .dark_gray);
        rl.drawText("- SPACE: Player jump", 30, 60, 10, .dark_gray);
        rl.drawText("- R: Reset game state", 30, 80, 10, .dark_gray);

        rl.drawText("- S: START/STOP RECORDING INPUT EVENTS", 30, 110, 10, .black);
        rl.drawText("- A: REPLAY LAST RECORDED INPUT EVENTS", 30, 130, 10, .black);

        // Draw automation events recording indicator
        const blink_on = (frame_counter / 15) % 2 == 1;
        if (event_recording) {
            rl.drawRectangle(10, 160, 290, 30, rl.fade(.red, 0.3));
            rl.drawRectangleLines(10, 160, 290, 30, rl.fade(.maroon, 0.8));
            rl.drawCircle(30, 175, 10, .maroon);

            if (blink_on) rl.drawText(rl.textFormat("RECORDING EVENTS... [{d}]", .{aelist.count}), 50, 170, 10, .maroon);
        } else if (event_playing) {
            rl.drawRectangle(10, 160, 290, 30, rl.fade(.lime, 0.3));
            rl.drawRectangleLines(10, 160, 290, 30, rl.fade(.dark_green, 0.8));
            rl.drawTriangle(.{ .x = 20, .y = 155 + 10 }, .{ .x = 20, .y = 155 + 30 }, .{ .x = 40, .y = 155 + 20 }, .dark_green);

            if (blink_on) rl.drawText(rl.textFormat("PLAYING RECORDED EVENTS... [{d}]", .{current_play_frame}), 50, 170, 10, .dark_green);
        }
    }
}

fn renderCenter() rl.Vector2 {
    return .{
        .x = @as(f32, @floatFromInt(rl.getRenderWidth())) / 2.0,
        .y = @as(f32, @floatFromInt(rl.getRenderHeight())) / 2.0,
    };
}

fn resetCamera(player: Player) rl.Camera2D {
    return .{ .target = player.position, .offset = renderCenter(), .rotation = 0.0, .zoom = 1.0 };
}
