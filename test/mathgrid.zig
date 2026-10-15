//! mathgrid.zig — Zig side of the raymath bit-exact numeric diff.
//!
//! Mirrors test/mathgrid.c EXACTLY: the same LCG input stream and the same
//! sequence of raymath calls, printing the raw IEEE-754 bits of every result.
//! It calls the Zig port's C-ABI exports via `extern fn` (so it tests the real
//! exported symbols), linked against the raymath.zig object by the build.
//! tools/mathdiff.sh diffs this output against the C oracle's — identical bytes
//! ⇒ the Zig port is bit-exact with C raymath.

// Mirror raymath's ABI structs (must match src/raymath.zig field order).
const Vector2 = extern struct { x: f32, y: f32 };
const Vector3 = extern struct { x: f32, y: f32, z: f32 };
const Vector4 = extern struct { x: f32, y: f32, z: f32, w: f32 };
const Quaternion = Vector4;
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

// --- raymath C-ABI exports under test ---
extern fn Clamp(f32, f32, f32) f32;
extern fn Lerp(f32, f32, f32) f32;
extern fn Normalize(f32, f32, f32) f32;
extern fn Remap(f32, f32, f32, f32, f32) f32;
extern fn Wrap(f32, f32, f32) f32;
extern fn FloatEquals(f32, f32) c_int;
extern fn Vector2Add(Vector2, Vector2) Vector2;
extern fn Vector2Subtract(Vector2, Vector2) Vector2;
extern fn Vector2Scale(Vector2, f32) Vector2;
extern fn Vector2DotProduct(Vector2, Vector2) f32;
extern fn Vector2Length(Vector2) f32;
extern fn Vector2LengthSqr(Vector2) f32;
extern fn Vector2Distance(Vector2, Vector2) f32;
extern fn Vector2Normalize(Vector2) Vector2;
extern fn Vector2Lerp(Vector2, Vector2, f32) Vector2;
extern fn Vector2Rotate(Vector2, f32) Vector2;
extern fn Vector2Angle(Vector2, Vector2) f32;
extern fn Vector2Reflect(Vector2, Vector2) Vector2;
extern fn Vector2MoveTowards(Vector2, Vector2, f32) Vector2;
extern fn Vector2Clamp(Vector2, Vector2, Vector2) Vector2;
extern fn Vector3Add(Vector3, Vector3) Vector3;
extern fn Vector3Subtract(Vector3, Vector3) Vector3;
extern fn Vector3Scale(Vector3, f32) Vector3;
extern fn Vector3Multiply(Vector3, Vector3) Vector3;
extern fn Vector3CrossProduct(Vector3, Vector3) Vector3;
extern fn Vector3DotProduct(Vector3, Vector3) f32;
extern fn Vector3Length(Vector3) f32;
extern fn Vector3LengthSqr(Vector3) f32;
extern fn Vector3Distance(Vector3, Vector3) f32;
extern fn Vector3Normalize(Vector3) Vector3;
extern fn Vector3Lerp(Vector3, Vector3, f32) Vector3;
extern fn Vector3Reflect(Vector3, Vector3) Vector3;
extern fn Vector3Min(Vector3, Vector3) Vector3;
extern fn Vector3Max(Vector3, Vector3) Vector3;
extern fn Vector3Negate(Vector3) Vector3;
extern fn Vector3Perpendicular(Vector3) Vector3;
extern fn Vector3Barycenter(Vector3, Vector3, Vector3, Vector3) Vector3;
extern fn Vector3ClampValue(Vector3, f32, f32) Vector3;
extern fn Vector3Angle(Vector3, Vector3) f32;
extern fn Vector3Transform(Vector3, Matrix) Vector3;
extern fn Vector3RotateByQuaternion(Vector3, Quaternion) Vector3;
extern fn MatrixIdentity() Matrix;
extern fn MatrixAdd(Matrix, Matrix) Matrix;
extern fn MatrixSubtract(Matrix, Matrix) Matrix;
extern fn MatrixMultiply(Matrix, Matrix) Matrix;
extern fn MatrixTranslate(f32, f32, f32) Matrix;
extern fn MatrixRotateXYZ(Vector3) Matrix;
extern fn MatrixScale(f32, f32, f32) Matrix;
extern fn MatrixRotateX(f32) Matrix;
extern fn MatrixRotateY(f32) Matrix;
extern fn MatrixRotateZ(f32) Matrix;
extern fn MatrixRotate(Vector3, f32) Matrix;
extern fn MatrixDeterminant(Matrix) f32;
extern fn MatrixInvert(Matrix) Matrix;
extern fn MatrixTranspose(Matrix) Matrix;
extern fn MatrixPerspective(f64, f64, f64, f64) Matrix;
extern fn MatrixOrtho(f64, f64, f64, f64, f64, f64) Matrix;
extern fn MatrixLookAt(Vector3, Vector3, Vector3) Matrix;
extern fn QuaternionFromAxisAngle(Vector3, f32) Quaternion;
extern fn QuaternionFromEuler(f32, f32, f32) Quaternion;
extern fn QuaternionIdentity() Quaternion;
extern fn QuaternionAdd(Quaternion, Quaternion) Quaternion;
extern fn QuaternionMultiply(Quaternion, Quaternion) Quaternion;
extern fn QuaternionLength(Quaternion) f32;
extern fn QuaternionNormalize(Quaternion) Quaternion;
extern fn QuaternionInvert(Quaternion) Quaternion;
extern fn QuaternionSlerp(Quaternion, Quaternion, f32) Quaternion;
extern fn QuaternionNlerp(Quaternion, Quaternion, f32) Quaternion;
extern fn QuaternionToMatrix(Quaternion) Matrix;
extern fn QuaternionFromMatrix(Matrix) Quaternion;
extern fn QuaternionToEuler(Quaternion) Vector3;
extern fn QuaternionFromVector3ToVector3(Vector3, Vector3) Quaternion;
extern fn MatrixCompose(Vector3, Quaternion, Vector3) Matrix;
extern fn MatrixDecompose(Matrix, *Vector3, *Quaternion, *Vector3) void;

var S: u32 = 0x12345678;
fn nextf() f32 {
    S = S *% 1103515245 +% 12345;
    const m: u32 = (S >> 8) & 0xFFFFFF;
    return @as(f32, @floatFromInt(m)) / 16777216.0 * 20.0 - 10.0;
}
fn v2() Vector2 {
    const x = nextf();
    const y = nextf();
    return .{ .x = x, .y = y };
}
fn v3() Vector3 {
    const x = nextf();
    const y = nextf();
    const z = nextf();
    return .{ .x = x, .y = y, .z = z };
}
fn v4() Vector4 {
    const x = nextf();
    const y = nextf();
    const z = nextf();
    const w = nextf();
    return .{ .x = x, .y = y, .z = z, .w = w };
}

// Output via C stdio (the harness links libc): identical formatting to the C
// oracle (test/mathgrid.c uses the same printf), and avoids the churning Zig
// std.Io writer API. Raw float bits are printed, so formatting can't hide a diff.
extern fn printf(format: [*:0]const u8, ...) c_int;

fn pf(f: f32) void {
    _ = printf("%08x ", @as(c_uint, @bitCast(f)));
}
fn p2(v: Vector2) void {
    pf(v.x);
    pf(v.y);
}
fn p3(v: Vector3) void {
    pf(v.x);
    pf(v.y);
    pf(v.z);
}
fn p4(v: Vector4) void {
    pf(v.x);
    pf(v.y);
    pf(v.z);
    pf(v.w);
}
fn pm(m: Matrix) void {
    inline for (.{ m.m0, m.m4, m.m8, m.m12, m.m1, m.m5, m.m9, m.m13, m.m2, m.m6, m.m10, m.m14, m.m3, m.m7, m.m11, m.m15 }) |x| pf(x);
}
fn pi(i: c_int) void {
    _ = printf("%d ", i);
}

pub fn main() void {
    const N = 200;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        const a = nextf();
        const b = nextf();
        const c = nextf();
        const A2 = v2();
        const B2 = v2();
        const A3 = v3();
        const B3 = v3();
        const C3 = v3();
        const A4 = v4();
        const B4 = v4();

        // scalar
        pf(Clamp(a, -5.0, 5.0));
        pf(Lerp(a, b, 0.3));
        pf(Normalize(a, -10.0, 10.0));
        pf(Remap(a, -10.0, 10.0, 0.0, 1.0));
        pf(Wrap(a, -3.0, 3.0));
        pi(FloatEquals(a, b));

        // Vector2
        p2(Vector2Add(A2, B2));
        p2(Vector2Subtract(A2, B2));
        p2(Vector2Scale(A2, c));
        pf(Vector2DotProduct(A2, B2));
        pf(Vector2Length(A2));
        pf(Vector2LengthSqr(A2));
        pf(Vector2Distance(A2, B2));
        p2(Vector2Normalize(A2));
        p2(Vector2Lerp(A2, B2, 0.4));
        p2(Vector2Rotate(A2, a));
        pf(Vector2Angle(A2, B2));
        p2(Vector2Reflect(A2, Vector2Normalize(B2)));
        p2(Vector2MoveTowards(A2, B2, c));
        p2(Vector2Clamp(A2, .{ .x = -2, .y = -2 }, .{ .x = 2, .y = 2 }));

        // Vector3
        p3(Vector3Add(A3, B3));
        p3(Vector3Subtract(A3, B3));
        p3(Vector3Scale(A3, c));
        p3(Vector3Multiply(A3, B3));
        p3(Vector3CrossProduct(A3, B3));
        pf(Vector3DotProduct(A3, B3));
        pf(Vector3Length(A3));
        pf(Vector3LengthSqr(A3));
        pf(Vector3Distance(A3, B3));
        p3(Vector3Normalize(A3));
        p3(Vector3Lerp(A3, B3, 0.4));
        p3(Vector3Reflect(A3, Vector3Normalize(B3)));
        p3(Vector3Min(A3, B3));
        p3(Vector3Max(A3, B3));
        p3(Vector3Negate(A3));
        p3(Vector3Perpendicular(A3));
        p3(Vector3Barycenter(A3, B3, C3, A3));
        p3(Vector3ClampValue(A3, 0.5, 3.0));
        pf(Vector3Angle(A3, B3));

        // Matrix
        const MA = MatrixTranslate(a, b, c);
        const MB = MatrixRotateXYZ(.{ .x = a * 0.1, .y = b * 0.1, .z = c * 0.1 });
        const MS = MatrixScale(a, b, c);
        pm(MatrixIdentity());
        pm(MatrixAdd(MA, MB));
        pm(MatrixSubtract(MA, MB));
        pm(MatrixMultiply(MA, MB));
        pm(MA);
        pm(MB);
        pm(MS);
        pm(MatrixRotateX(a));
        pm(MatrixRotateY(b));
        pm(MatrixRotateZ(c));
        pm(MatrixRotate(Vector3Normalize(A3), a));
        pf(MatrixDeterminant(MatrixMultiply(MA, MS)));
        pm(MatrixInvert(MatrixMultiply(MA, MS)));
        pm(MatrixTranspose(MB));
        pm(MatrixPerspective(1.2, 1.6, 0.1, 100.0));
        pm(MatrixOrtho(-1, 1, -1, 1, 0.1, 100.0));
        pm(MatrixLookAt(A3, B3, .{ .x = 0, .y = 1, .z = 0 }));
        p3(Vector3Transform(A3, MatrixMultiply(MA, MB)));

        // Quaternion
        const Q1 = QuaternionFromAxisAngle(Vector3Normalize(A3), a);
        const Q2 = QuaternionFromEuler(a * 0.2, b * 0.2, c * 0.2);
        p4(QuaternionIdentity());
        p4(QuaternionAdd(Q1, Q2));
        p4(QuaternionMultiply(Q1, Q2));
        pf(QuaternionLength(Q1));
        p4(QuaternionNormalize(Q1));
        p4(QuaternionInvert(Q1));
        p4(QuaternionSlerp(Q1, Q2, 0.35));
        p4(QuaternionNlerp(Q1, Q2, 0.35));
        p4(Q1);
        p4(Q2);
        pm(QuaternionToMatrix(Q1));
        p4(QuaternionFromMatrix(MB));
        p3(Vector3RotateByQuaternion(A3, Q1));
        p3(QuaternionToEuler(Q2));

        // 6.2 additions: from->to rotation (incl. both opposite-vector
        // branches), TRS compose/decompose round-trip
        p4(QuaternionFromVector3ToVector3(A3, B3));
        p4(QuaternionFromVector3ToVector3(A3, Vector3Negate(A3)));
        p4(QuaternionFromVector3ToVector3(.{ .x = a, .y = 0, .z = 0 }, .{ .x = -a, .y = 0, .z = 0 }));
        p4(QuaternionFromVector3ToVector3(.{ .x = 0, .y = b, .z = c }, .{ .x = 0, .y = -b, .z = -c }));
        pm(MatrixCompose(A3, Q1, B3));
        var T: Vector3 = undefined;
        var R: Quaternion = undefined;
        var S3: Vector3 = undefined;
        MatrixDecompose(MatrixMultiply(MatrixMultiply(MS, MB), MA), &T, &R, &S3);
        p3(T);
        p4(R);
        p3(S3);
        MatrixDecompose(MatrixCompose(A3, Q2, C3), &T, &R, &S3);
        p3(T);
        p4(R);
        p3(S3);

        _ = A4;
        _ = B4;
        _ = printf("\n");
    }
}
