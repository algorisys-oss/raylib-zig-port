//! Angry Birds slingshot demo — capstone example for raylib-zig.
//!
//! A Zig port of the C# reference game (csharp-raylib-angrybirds), running
//! against the ported library through the plain raylib C ABI. All art is
//! procedural (circles, rectangles, lines) — same as the C# reference, so
//! the demo has zero asset dependencies.
//!
//! Controls: drag the bird back with the left mouse button and release to
//! fire. R restarts the level; SPACE advances after a clear.
//!
//! Self-test: with ANGRYBIRDS_SELFTEST=1 the game opens a hidden window,
//! auto-plays scripted max-power shots through the same update path the
//! mouse drives, runs 300 fixed-timestep frames, saves a screenshot to
//! $ANGRYBIRDS_SHOT/selftest.png (default: cwd), and exits 0.

const std = @import("std");
const rl = @import("raylib.zig");
const game = @import("game.zig");

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const gpa = debug_allocator.allocator();

    if (getenv("ANGRYBIRDS_SELFTEST")) |v| {
        if (std.mem.eql(u8, v, "1")) return selfTest(gpa);
    }
    return play(gpa);
}

/// Libc getenv (the game links libc for raylib anyway).
fn getenv(name: [*:0]const u8) ?[:0]const u8 {
    return std.mem.span(std.c.getenv(name) orelse return null);
}

fn play(gpa: std.mem.Allocator) !void {
    rl.InitWindow(game.screen_width, game.screen_height, "Slingshot - a tiny Angry Birds");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    var g = try game.Game.init(gpa);
    defer g.deinit();

    while (!rl.WindowShouldClose()) {
        try g.update(.poll(), rl.GetFrameTime());
        g.draw();
    }
}

// --- Self-test -----------------------------------------------------------

const selftest_frames = 300;
const selftest_dt = 1.0 / 60.0;

/// Scripted stand-in for the mouse: whenever a bird is waiting on the sling,
/// press, pull to full stretch over 30 frames, hold, and release — a
/// max-power horizontal shot straight into the level-1 wall. Two such shots
/// break the wall; the input feeds the same Game.update the player drives.
const Script = struct {
    drag_frame: u32 = 0,

    const pull: rl.Vector2 = .{ .x = -game.max_stretch, .y = 0 };
    const release_frame = 40;

    fn next(script: *Script, g: *const game.Game) game.Input {
        if (g.state != .aiming or g.bird == null) {
            script.drag_frame = 0;
            return .{ .mouse = game.anchor };
        }
        script.drag_frame += 1;
        const t = @min(@as(f32, @floatFromInt(script.drag_frame)), 30) / 30;
        return .{
            .mouse = game.anchor.add(pull.scale(t)),
            .pressed = script.drag_frame == 1,
            .released = script.drag_frame == release_frame,
        };
    }
};

fn selfTest(gpa: std.mem.Allocator) !void {
    // TakeScreenshot resolves file names against the working directory as it
    // was at InitWindow (raylib's storage base path), so enter the shot
    // directory first and pass a bare file name later.
    if (getenv("ANGRYBIRDS_SHOT")) |dir| {
        if (std.c.chdir(dir) != 0) return error.BadShotDirectory;
    }

    rl.SetConfigFlags(rl.flag_window_hidden);
    rl.InitWindow(game.screen_width, game.screen_height, "angrybirds selftest");
    defer rl.CloseWindow();

    var g = try game.Game.init(gpa);
    defer g.deinit();

    var script: Script = .{};
    for (0..selftest_frames) |_| {
        try g.update(script.next(&g), selftest_dt);
        g.draw();
    }

    rl.TakeScreenshot("selftest.png");

    std.debug.print("selftest: frames={d} score={d} state={t} shot={s}/selftest.png\n", .{
        selftest_frames, g.score, g.state, getenv("ANGRYBIRDS_SHOT") orelse ".",
    });
}
