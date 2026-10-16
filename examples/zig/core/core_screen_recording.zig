//! raylib [core] example - screen recording
//!
//! Zig-API translation of examples/core/core_screen_recording.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const gif_record_framerate = 5; // Record framerate, we get a frame every N frames

const max_sinewave_points = 256;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - screen recording");
    defer rl.closeWindow(); // Close window and OpenGL context

    var gif_recording = false; // GIF recording state
    var gif_frame_counter: u32 = 0; // GIF frames counter
    var gif_state: msf_gif.State = .{}; // MSGIF context state

    // If still recording a GIF on close window, just finish
    defer if (gif_recording) msf_gif.free(msf_gif.end(&gif_state));

    var circle_position: rl.Vector2 = .{ .x = 0.0, .y = screen_height / 2.0 };
    var time_counter: f32 = 0.0;

    // Get sine wave points for line drawing
    var sine_points: [max_sinewave_points]rl.Vector2 = undefined;
    for (&sine_points, 0..) |*point, i| {
        const index: i32 = @intCast(i);
        point.* = .{
            .x = @as(f32, @floatFromInt(index * rl.getScreenWidth())) / 180.0,
            .y = screen_height / 2.0 + 150 * @sin((2 * rl.pi / 1.5) * (@as(f32, 1.0) / 60.0) * @as(f32, @floatFromInt(index))), // Calculate for 60 fps
        };
    }

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Update circle sinusoidal movement
        time_counter += rl.getFrameTime();
        circle_position.x += @as(f32, @floatFromInt(rl.getScreenWidth())) / 180.0;
        circle_position.y = screen_height / 2.0 + 150 * @sin((2 * rl.pi / 1.5) * time_counter);
        if (circle_position.x > screen_width) {
            circle_position.x = 0.0;
            circle_position.y = screen_height / 2.0;
            time_counter = 0.0;
        }

        // Start-Stop GIF recording on CTRL+R
        if (rl.isKeyDown(.left_control) and rl.isKeyPressed(.r)) {
            if (gif_recording) {
                // Stop current recording and save file
                gif_recording = false;
                const result = msf_gif.end(&gif_state);
                defer msf_gif.free(result);
                _ = rl.saveFileData(rl.textFormat("{s}/screenrecording.gif", .{rl.getApplicationDirectory()}), result.bytes());

                rl.traceLog(.info, "Finish animated GIF recording", .{});
            } else {
                // Start a new recording
                gif_recording = true;
                gif_frame_counter = 0;
                _ = msf_gif.begin(&gif_state, rl.getRenderWidth(), rl.getRenderHeight());

                rl.traceLog(.info, "Start animated GIF recording", .{});
            }
        }

        if (gif_recording) {
            gif_frame_counter += 1;

            // NOTE: We record one gif frame depending on the desired gif framerate
            if (gif_frame_counter > gif_record_framerate) {
                // Get image data for the current frame (from backbuffer)
                // WARNING: This process is quite slow, it can generate stuttering
                const im_screen = try rl.loadImageFromScreen();
                defer rl.unloadImage(im_screen); // Free image data

                // Add the frame to the gif recording, providing and "estimated" time for display in centiseconds
                const centiseconds_per_frame = @divTrunc(@as(i32, @intFromFloat((@as(f32, 1.0) / 60.0) * gif_record_framerate)), 10);
                _ = msf_gif.frame(&gif_state, @ptrCast(im_screen.data), centiseconds_per_frame, 16, im_screen.width * 4);
                gif_frame_counter = 0;
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        for (sine_points[0 .. sine_points.len - 1], sine_points[1..]) |point, next| {
            rl.drawLineV(point, next, .maroon);
            rl.drawCircleV(point, 3, .maroon);
        }

        rl.drawCircleV(circle_position, 30, .red);

        rl.drawFPS(10, 10);

        // NOTE: A record indicator drawn here would appear in the recorded image;
        // use a render texture for the recording and loadImageFromTexture(rt.texture) instead
    }
}

/// msf_gif (third-party GIF encoder, vendor/msf_gif, linked as C via
/// core_screen_recording_shim.c): the subset of its API this example uses.
const msf_gif = struct {
    /// MsfGifResult: the encoded GIF, owned by msf_gif until `free`.
    const Result = extern struct {
        data: ?[*]u8,
        data_size: usize,
        alloc_size: usize, // internal use
        context_pointer: ?*anyopaque, // internal use

        fn bytes(result: Result) []const u8 {
            const data = result.data orelse return &.{};
            return data[0..result.data_size];
        }
    };

    /// MsfCookedFrame (internal use)
    const CookedFrame = extern struct {
        pixels: ?[*]u32 = null,
        depth: c_int = 0,
        count: c_int = 0,
        rbits: c_int = 0,
        gbits: c_int = 0,
        bbits: c_int = 0,
    };

    /// MsfGifState (internal use, zero-initialized before `begin`)
    const State = extern struct {
        file_write_func: ?*const anyopaque = null,
        file_write_data: ?*anyopaque = null,
        previous_frame: CookedFrame = .{},
        current_frame: CookedFrame = .{},
        lzw_mem: ?[*]i16 = null,
        list_head: ?*anyopaque = null,
        list_tail: ?*anyopaque = null,
        width: c_int = 0,
        height: c_int = 0,
        custom_allocator_context: ?*anyopaque = null,
        frames_submitted: c_int = 0, // needed for transparency to work correctly
    };

    extern "c" fn msf_gif_begin(handle: *State, width: c_int, height: c_int) c_int;
    extern "c" fn msf_gif_frame(handle: *State, pixel_data: [*]u8, centi_seconds_per_frame: c_int, max_bit_depth: c_int, pitch_in_bytes: c_int) c_int;
    extern "c" fn msf_gif_end(handle: *State) Result;
    extern "c" fn msf_gif_free(result: Result) void;

    const begin = msf_gif_begin;
    const frame = msf_gif_frame;
    const end = msf_gif_end;
    const free = msf_gif_free;
};
