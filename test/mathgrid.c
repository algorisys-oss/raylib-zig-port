// mathgrid.c — C oracle for the raymath bit-exact numeric diff.
//
// Drives a deterministic stream of inputs (a fixed LCG, identical to
// test/mathgrid.zig) through a representative battery of raymath functions and
// prints the raw IEEE-754 bits of every result. test/mathgrid.zig does the exact
// same sequence against the Zig port; tools/mathdiff.sh diffs the two outputs.
// Identical bytes ⇒ the Zig port is bit-exact with C raymath.
//
// Printing raw bits (not %f) means formatting/rounding can never hide a diff.

#include "raymath.h"
#include <stdio.h>
#include <stdint.h>

static uint32_t S = 0x12345678u;
static float nextf(void) {            // LCG → f32 in [-10, 10); must match Zig
    S = S * 1103515245u + 12345u;
    uint32_t m = (S >> 8) & 0xFFFFFFu; // 24 bits
    return (float)m / 16777216.0f * 20.0f - 10.0f;
}
static Vector2 v2(void) { Vector2 v = { nextf(), nextf() }; return v; }
static Vector3 v3(void) { Vector3 v = { nextf(), nextf(), nextf() }; return v; }
static Vector4 v4(void) { Vector4 v = { nextf(), nextf(), nextf(), nextf() }; return v; }

static void pf(float f) { uint32_t u; __builtin_memcpy(&u, &f, 4); printf("%08x ", u); }
static void p2(Vector2 v) { pf(v.x); pf(v.y); }
static void p3(Vector3 v) { pf(v.x); pf(v.y); pf(v.z); }
static void p4(Vector4 v) { pf(v.x); pf(v.y); pf(v.z); pf(v.w); }
static void pm(Matrix m) { pf(m.m0); pf(m.m4); pf(m.m8); pf(m.m12); pf(m.m1); pf(m.m5); pf(m.m9); pf(m.m13);
                           pf(m.m2); pf(m.m6); pf(m.m10); pf(m.m14); pf(m.m3); pf(m.m7); pf(m.m11); pf(m.m15); }
static void pi(int i) { printf("%d ", i); }

int main(void) {
    const int N = 200;
    for (int i = 0; i < N; i++) {
        float a = nextf(), b = nextf(), c = nextf();
        Vector2 A2 = v2(), B2 = v2();
        Vector3 A3 = v3(), B3 = v3(), C3 = v3();
        Vector4 A4 = v4(), B4 = v4();

        // --- scalar ---
        pf(Clamp(a, -5.0f, 5.0f)); pf(Lerp(a, b, 0.3f)); pf(Normalize(a, -10.0f, 10.0f));
        pf(Remap(a, -10.0f, 10.0f, 0.0f, 1.0f)); pf(Wrap(a, -3.0f, 3.0f)); pi(FloatEquals(a, b));

        // --- Vector2 ---
        p2(Vector2Add(A2, B2)); p2(Vector2Subtract(A2, B2)); p2(Vector2Scale(A2, c));
        pf(Vector2DotProduct(A2, B2)); pf(Vector2Length(A2)); pf(Vector2LengthSqr(A2));
        pf(Vector2Distance(A2, B2)); p2(Vector2Normalize(A2)); p2(Vector2Lerp(A2, B2, 0.4f));
        p2(Vector2Rotate(A2, a)); pf(Vector2Angle(A2, B2)); p2(Vector2Reflect(A2, Vector2Normalize(B2)));
        p2(Vector2MoveTowards(A2, B2, c)); p2(Vector2Clamp(A2, (Vector2){-2,-2}, (Vector2){2,2}));

        // --- Vector3 ---
        p3(Vector3Add(A3, B3)); p3(Vector3Subtract(A3, B3)); p3(Vector3Scale(A3, c));
        p3(Vector3Multiply(A3, B3)); p3(Vector3CrossProduct(A3, B3)); pf(Vector3DotProduct(A3, B3));
        pf(Vector3Length(A3)); pf(Vector3LengthSqr(A3)); pf(Vector3Distance(A3, B3));
        p3(Vector3Normalize(A3)); p3(Vector3Lerp(A3, B3, 0.4f)); p3(Vector3Reflect(A3, Vector3Normalize(B3)));
        p3(Vector3Min(A3, B3)); p3(Vector3Max(A3, B3)); p3(Vector3Negate(A3));
        p3(Vector3Perpendicular(A3)); p3(Vector3Barycenter(A3, B3, C3, A3));
        p3(Vector3ClampValue(A3, 0.5f, 3.0f)); pf(Vector3Angle(A3, B3));

        // --- Matrix ---
        Matrix MA = MatrixTranslate(a, b, c);
        Matrix MB = MatrixRotateXYZ((Vector3){a*0.1f, b*0.1f, c*0.1f});
        Matrix MS = MatrixScale(a, b, c);
        pm(MatrixIdentity()); pm(MatrixAdd(MA, MB)); pm(MatrixSubtract(MA, MB));
        pm(MatrixMultiply(MA, MB)); pm(MA); pm(MB); pm(MS);
        pm(MatrixRotateX(a)); pm(MatrixRotateY(b)); pm(MatrixRotateZ(c));
        pm(MatrixRotate(Vector3Normalize(A3), a)); pf(MatrixDeterminant(MatrixMultiply(MA, MS)));
        pm(MatrixInvert(MatrixMultiply(MA, MS))); pm(MatrixTranspose(MB));
        pm(MatrixPerspective(1.2, 1.6, 0.1, 100.0)); pm(MatrixOrtho(-1, 1, -1, 1, 0.1, 100.0));
        pm(MatrixLookAt(A3, B3, (Vector3){0, 1, 0})); p3(Vector3Transform(A3, MatrixMultiply(MA, MB)));

        // --- Quaternion ---
        Quaternion Q1 = QuaternionFromAxisAngle(Vector3Normalize(A3), a);
        Quaternion Q2 = QuaternionFromEuler(a*0.2f, b*0.2f, c*0.2f);
        p4(QuaternionIdentity()); p4(QuaternionAdd(Q1, Q2)); p4(QuaternionMultiply(Q1, Q2));
        pf(QuaternionLength(Q1)); p4(QuaternionNormalize(Q1)); p4(QuaternionInvert(Q1));
        p4(QuaternionSlerp(Q1, Q2, 0.35f)); p4(QuaternionNlerp(Q1, Q2, 0.35f)); p4(Q1); p4(Q2);
        pm(QuaternionToMatrix(Q1)); p4(QuaternionFromMatrix(MB)); p3(Vector3RotateByQuaternion(A3, Q1));
        p3(QuaternionToEuler(Q2));

        (void)A4; (void)B4;
        printf("\n");
    }
    return 0;
}
