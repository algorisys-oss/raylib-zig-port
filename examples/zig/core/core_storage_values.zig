//! raylib [core] example - storage values
//!
//! Zig-API translation of examples/core/core_storage_values.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const storage_data_file = "storage.data"; // Storage file

/// NOTE: Storage positions must start with 0, directly related to file memory layout
const StorageData = enum(u32) {
    score = 0,
    hiscore = 1,
};

pub fn main(init: std.process.Init) void {
    const gpa = init.gpa;

    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - storage values");
    defer rl.closeWindow(); // Close window and OpenGL context

    var score: i32 = 0;
    var hiscore: i32 = 0;
    var frames_counter: i32 = 0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.r)) {
            score = rl.getRandomValue(1000, 2000);
            hiscore = rl.getRandomValue(2000, 4000);
        }

        if (rl.isKeyPressed(.enter)) {
            saveStorageValue(gpa, .score, score) catch |err| logSaveError(err);
            saveStorageValue(gpa, .hiscore, hiscore) catch |err| logSaveError(err);
        } else if (rl.isKeyPressed(.space)) {
            // NOTE: If requested position could not be found, value 0 is returned
            score = loadStorageValue(.score);
            hiscore = loadStorageValue(.hiscore);
        }

        frames_counter += 1;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawText(rl.textFormat("SCORE: {d}", .{score}), 280, 130, 40, .maroon);
        rl.drawText(rl.textFormat("HI-SCORE: {d}", .{hiscore}), 210, 200, 50, .black);

        rl.drawText(rl.textFormat("frames: {d}", .{frames_counter}), 10, 10, 20, .lime);

        rl.drawText("Press R to generate random numbers", 220, 40, 20, .light_gray);
        rl.drawText("Press ENTER to SAVE values", 250, 310, 20, .light_gray);
        rl.drawText("Press SPACE to LOAD values", 252, 350, 20, .light_gray);
    }
}

fn logSaveError(err: anyerror) void {
    rl.traceLog(.warning, "FILEIO: [{s}] Failed to save storage value: {s}", .{ storage_data_file, @errorName(err) });
}

/// Save integer value to storage file (to defined position)
/// NOTE: Storage positions is directly related to file memory layout (4 bytes each integer)
fn saveStorageValue(gpa: std.mem.Allocator, position: StorageData, value: i32) !void {
    const offset = @backingInt(position) * @sizeOf(i32);

    // Start from the current file contents (if any), grown up to the requested position
    const old_data: []const u8 = rl.loadFileData(storage_data_file) catch blk: {
        rl.traceLog(.info, "FILEIO: [{s}] File created successfully", .{storage_data_file});
        break :blk &.{};
    };
    defer if (old_data.len > 0) rl.unloadFileData(@constCast(old_data));

    const data = try gpa.alloc(u8, @max(old_data.len, offset + @sizeOf(i32)));
    defer gpa.free(data);
    @memset(data, 0);
    @memcpy(data[0..old_data.len], old_data);

    // Replace value on selected position
    std.mem.writeInt(i32, data[offset..][0..@sizeOf(i32)], value, .native);

    if (!rl.saveFileData(storage_data_file, data)) return error.SaveFailed;

    rl.traceLog(.info, "FILEIO: [{s}] Saved storage value: {d}", .{ storage_data_file, value });
}

/// Load integer value from storage file (from defined position)
/// NOTE: If requested position could not be found, value 0 is returned
fn loadStorageValue(position: StorageData) i32 {
    const offset = @backingInt(position) * @sizeOf(i32);

    const data = rl.loadFileData(storage_data_file) catch return 0;
    defer rl.unloadFileData(data);

    const value: i32 = if (data.len < offset + @sizeOf(i32)) blk: {
        rl.traceLog(.warning, "FILEIO: [{s}] Failed to find storage position: {d}", .{ storage_data_file, @backingInt(position) });
        break :blk 0;
    } else std.mem.readInt(i32, data[offset..][0..@sizeOf(i32)], .native);

    rl.traceLog(.info, "FILEIO: [{s}] Loaded storage value: {d}", .{ storage_data_file, value });
    return value;
}
