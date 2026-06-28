// camgrid.c — C oracle for the rcamera bit-exact numeric diff.
// Applies a deterministic sequence of camera operations and prints the raw
// IEEE-754 bits of the mutated camera state + the queried vectors/matrices.
// test/camgrid.zig mirrors this against the Zig port; tools/camdiff.sh diffs.
//
// RCAMERA_STANDALONE makes rcamera.h self-define Camera3D/Vector3/Matrix; it
// pulls in raymath.h for the math. Compiled strict-IEEE (-ffp-contract=off,
// RAYMATH_STATIC_INLINE) so it matches the Zig port (which uses the bit-exact
// Zig raymath).

// Use raylib.h for the types (Camera3D/Vector3/Matrix/bool); its RL_*_TYPE
// guards let the raymath.h that rcamera.h pulls in coexist without redefinition.
#include "raylib.h"
// rcamera.h's projection-matrix path uses these (normally from rlgl.h).
#define RL_CULL_DISTANCE_NEAR 0.05
#define RL_CULL_DISTANCE_FAR 4000.0
#define RCAMERA_IMPLEMENTATION
#include "rcamera.h"

#include <stdio.h>
#include <stdint.h>

// Link stubs for the rcore input functions UpdateCamera/UpdateCameraPro
// reference (emitted by RCAMERA_IMPLEMENTATION). The harness never calls
// UpdateCamera, so these are never executed — they only satisfy the linker.
Vector2 GetMouseDelta(void) { return (Vector2){0, 0}; }
float GetMouseWheelMove(void) { return 0.0f; }
float GetFrameTime(void) { return 0.0f; }
bool IsKeyDown(int k) { (void)k; return false; }
bool IsKeyPressed(int k) { (void)k; return false; }
bool IsMouseButtonDown(int b) { (void)b; return false; }
bool IsGamepadAvailable(int g) { (void)g; return false; }
float GetGamepadAxisMovement(int g, int a) { (void)g; (void)a; return 0.0f; }

static uint32_t S = 0x2468ace0u;
static float nextf(void) { // LCG → f32 in [-1, 1); must match Zig
    S = S * 1103515245u + 12345u;
    uint32_t m = (S >> 8) & 0xFFFFFFu;
    return (float)m / 16777216.0f * 2.0f - 1.0f;
}
static void pf(float f) { uint32_t u; __builtin_memcpy(&u, &f, 4); printf("%08x ", u); }
static void p3(Vector3 v) { pf(v.x); pf(v.y); pf(v.z); }
static void pm(Matrix m) {
    pf(m.m0); pf(m.m4); pf(m.m8); pf(m.m12); pf(m.m1); pf(m.m5); pf(m.m9); pf(m.m13);
    pf(m.m2); pf(m.m6); pf(m.m10); pf(m.m14); pf(m.m3); pf(m.m7); pf(m.m11); pf(m.m15);
}

int main(void) {
    Camera3D cam = {0};
    cam.position = (Vector3){0.0f, 2.0f, -5.0f};
    cam.target = (Vector3){0.0f, 0.0f, 0.0f};
    cam.up = (Vector3){0.0f, 1.0f, 0.0f};
    cam.fovy = 45.0f;
    cam.projection = 0; // CAMERA_PERSPECTIVE

    const int N = 150;
    for (int i = 0; i < N; i++) {
        CameraMoveForward(&cam, nextf(), (i & 1));
        CameraMoveRight(&cam, nextf(), (i & 2) != 0);
        CameraMoveUp(&cam, nextf());
        CameraYaw(&cam, nextf() * 0.3f, (i & 4) != 0);
        CameraPitch(&cam, nextf() * 0.2f, (i & 1), (i & 2) != 0, (i & 4) != 0);
        CameraRoll(&cam, nextf() * 0.1f);
        CameraMoveToTarget(&cam, nextf() * 0.5f);

        p3(cam.position); p3(cam.target); p3(cam.up);
        p3(GetCameraForward(&cam)); p3(GetCameraUp(&cam)); p3(GetCameraRight(&cam));
        pm(GetCameraViewMatrix(&cam));
        pm(GetCameraProjectionMatrix(&cam, 1.6f));
        printf("\n");
    }
    return 0;
}
