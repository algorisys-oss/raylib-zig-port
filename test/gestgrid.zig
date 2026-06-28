//! gestgrid.zig — Zig side of the rgestures bit-exact numeric diff.
//! Mirrors test/gestgrid.c exactly: same LCG, same event stream, same
//! harness-controlled clock. Defines GetTime() (exported) so the Zig rgestures'
//! `extern fn GetTime` resolves to our controlled clock. Prints raw bits.

const std = @import("std");

const Vector2 = extern struct { x: f32, y: f32 };
const GestureEvent = extern struct {
    touchAction: c_int,
    pointCount: c_int,
    pointId: [8]c_int,
    position: [8]Vector2,
};

// Controlled clock — rgestures.zig calls `extern fn GetTime() f64`.
var g_time: f64 = 0.0;
export fn GetTime() callconv(.c) f64 {
    return g_time;
}

extern fn SetGesturesEnabled(flags: c_uint) void;
extern fn ProcessGestureEvent(event: GestureEvent) void;
extern fn UpdateGestures() void;
extern fn GetGestureDetected() c_int;
extern fn GetGestureHoldDuration() f32;
extern fn GetGestureDragVector() Vector2;
extern fn GetGestureDragAngle() f32;
extern fn GetGesturePinchVector() Vector2;
extern fn GetGesturePinchAngle() f32;

extern fn printf(format: [*:0]const u8, ...) c_int;

var S: u32 = 0x13572468;
fn lcg() u32 {
    S = S *% 1103515245 +% 12345;
    return (S >> 8) & 0xFFFFFF;
}
fn frnd(lo: f32, hi: f32) f32 {
    return lo + @as(f32, @floatFromInt(lcg())) / 16777216.0 * (hi - lo);
}
fn pf(f: f32) void {
    _ = printf("%08x ", @as(c_uint, @bitCast(f)));
}
fn pi(i: c_int) void {
    _ = printf("%d ", i);
}
fn p2(v: Vector2) void {
    pf(v.x);
    pf(v.y);
}

pub fn main() void {
    SetGesturesEnabled(0xFFFFFFFF);
    const N = 400;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        g_time += @as(f64, @floatFromInt(lcg() % 100)) * 0.005;

        var ev: GestureEvent = std.mem.zeroes(GestureEvent);
        const a = lcg() % 10;
        ev.touchAction = if (a < 2) 1 else if (a < 4) 0 else 2;
        ev.pointCount = if (lcg() % 3 == 0) 2 else 1;
        ev.pointId[0] = 0;
        ev.pointId[1] = 1;
        ev.position[0] = .{ .x = frnd(0, 640), .y = frnd(0, 360) };
        ev.position[1] = .{ .x = frnd(0, 640), .y = frnd(0, 360) };

        ProcessGestureEvent(ev);
        UpdateGestures();

        pi(GetGestureDetected());
        pf(GetGestureHoldDuration());
        p2(GetGestureDragVector());
        pf(GetGestureDragAngle());
        p2(GetGesturePinchVector());
        pf(GetGesturePinchAngle());
        _ = printf("\n");
    }
}
