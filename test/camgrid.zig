//! camgrid.zig — Zig side of the rcamera bit-exact numeric diff.
//! Mirrors test/camgrid.c exactly: same LCG, same camera-op sequence, prints
//! raw float bits. Calls the Zig rcamera C-ABI exports via extern fn (linked
//! against the rcamera.zig object, which imports the bit-exact Zig raymath).

const Vector3 = extern struct { x: f32, y: f32, z: f32 };
const Matrix = extern struct {
    m0: f32,
    m4: f32,
    m8: f32,
    m12: f32,
    m1: f32,
    m5: f32,
    m9: f32,
    m13: f32,
    m2: f32,
    m6: f32,
    m10: f32,
    m14: f32,
    m3: f32,
    m7: f32,
    m11: f32,
    m15: f32,
};
const Camera3D = extern struct {
    position: Vector3,
    target: Vector3,
    up: Vector3,
    fovy: f32,
    projection: c_int,
};

extern fn GetCameraForward(*Camera3D) Vector3;
extern fn GetCameraUp(*Camera3D) Vector3;
extern fn GetCameraRight(*Camera3D) Vector3;
extern fn CameraMoveForward(*Camera3D, f32, bool) void;
extern fn CameraMoveUp(*Camera3D, f32) void;
extern fn CameraMoveRight(*Camera3D, f32, bool) void;
extern fn CameraMoveToTarget(*Camera3D, f32) void;
extern fn CameraYaw(*Camera3D, f32, bool) void;
extern fn CameraPitch(*Camera3D, f32, bool, bool, bool) void;
extern fn CameraRoll(*Camera3D, f32) void;
extern fn GetCameraViewMatrix(*Camera3D) Matrix;
extern fn GetCameraProjectionMatrix(*Camera3D, f32) Matrix;

extern fn printf(format: [*:0]const u8, ...) c_int;

var S: u32 = 0x2468ace0;
fn nextf() f32 {
    S = S *% 1103515245 +% 12345;
    const m: u32 = (S >> 8) & 0xFFFFFF;
    return @as(f32, @floatFromInt(m)) / 16777216.0 * 2.0 - 1.0;
}
fn pf(f: f32) void {
    _ = printf("%08x ", @as(c_uint, @bitCast(f)));
}
fn p3(v: Vector3) void {
    pf(v.x);
    pf(v.y);
    pf(v.z);
}
fn pm(m: Matrix) void {
    inline for (.{ m.m0, m.m4, m.m8, m.m12, m.m1, m.m5, m.m9, m.m13, m.m2, m.m6, m.m10, m.m14, m.m3, m.m7, m.m11, m.m15 }) |x| pf(x);
}

pub fn main() void {
    var cam: Camera3D = .{
        .position = .{ .x = 0.0, .y = 2.0, .z = -5.0 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = 0,
    };
    const N = 150;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        CameraMoveForward(&cam, nextf(), (i & 1) != 0);
        CameraMoveRight(&cam, nextf(), (i & 2) != 0);
        CameraMoveUp(&cam, nextf());
        CameraYaw(&cam, nextf() * 0.3, (i & 4) != 0);
        CameraPitch(&cam, nextf() * 0.2, (i & 1) != 0, (i & 2) != 0, (i & 4) != 0);
        CameraRoll(&cam, nextf() * 0.1);
        CameraMoveToTarget(&cam, nextf() * 0.5);

        p3(cam.position);
        p3(cam.target);
        p3(cam.up);
        p3(GetCameraForward(&cam));
        p3(GetCameraUp(&cam));
        p3(GetCameraRight(&cam));
        pm(GetCameraViewMatrix(&cam));
        pm(GetCameraProjectionMatrix(&cam, 1.6));
        _ = printf("\n");
    }
}
