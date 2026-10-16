//! raylib [core] example - custom logging
//!
//! Zig-API translation of examples/core/core_custom_logging.c (raylib 6.2).
//! Example contributed by Pablo Marcos Oltra (@pamarcos) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2018-2025 Pablo Marcos Oltra (@pamarcos) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

/// raylib invokes the logger from inside its own calls, so the clock it reads
/// is reached through a global set up in main.
var io: std.Io = undefined;

/// Custom logging function: prefixes every message with a timestamp (UTC)
/// and its log level.
fn customTraceLog(log_level: rl.TraceLogLevel, text: [:0]const u8) void {
    const now = std.Io.Clock.real.now(io);
    const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(@divFloor(now.nanoseconds, std.time.ns_per_s)) };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    const level: []const u8 = switch (log_level) {
        .info => "[INFO] : ",
        .@"error" => "[ERROR]: ",
        .warning => "[WARN] : ",
        .debug => "[DEBUG]: ",
        else => "",
    };

    std.debug.print("[{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] {s}{s}\n", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
        level,
        text,
    });
}

pub fn main(init: std.process.Init) void {
    io = init.io;

    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    // Set custom logger
    rl.setTraceLogCallback(customTraceLog);

    rl.initWindow(screen_width, screen_height, "raylib [core] example - custom logging");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText("Check out the console output to see the custom logger in action!", 60, 200, 20, .light_gray);
    }
}
