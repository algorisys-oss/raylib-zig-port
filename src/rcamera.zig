//! rcamera - Basic camera system with support for multiple camera modes
//!
//! Zig port of raylib's `rcamera.h` (implementation section). Every `RLAPI`
//! function declared in the header is exported with its exact C name,
//! byte-compatible signature, and C calling convention, so a C caller can link
//! against it out-of-line. Floating-point operation order matches the C source
//! exactly to keep results bit-identical; all vector and matrix maths are
//! delegated to the already-ported `raymath` module. Its `export fn`s are not
//! `pub`, so they are pulled in here via `extern` declarations matching their C
//! ABI symbols; the linker resolves them against raymath's object at link time.
//!
//! NOTE: `UpdateCamera` / `UpdateCameraPro` are intentionally not ported here.
//! Although their bodies live in rcamera.h's implementation block, they are not
//! among the `RLAPI` declarations of this module and they depend on rcore.c
//! input functions (GetMouseDelta, IsKeyDown, GetFrameTime, ...), which belong
//! to a different translation unit.

const rm = @import("raymath.zig");

//----------------------------------------------------------------------------------
// Types and Structures Definition
//----------------------------------------------------------------------------------

/// Vector3 type (reused from raymath, identical layout)
const Vector3 = rm.Vector3;

/// Matrix type (reused from raymath, identical layout)
const Matrix = rm.Matrix;

/// Camera type, defines a camera position/orientation in 3d space
const Camera3D = extern struct {
    position: Vector3, // Camera position
    target: Vector3, // Camera target it looks-at
    up: Vector3, // Camera up vector (rotation over its axis)
    fovy: f32, // Camera field-of-view aperture in Y (degrees) in perspective, used as near plane width in orthographic
    projection: c_int, // Camera projection type: CAMERA_PERSPECTIVE or CAMERA_ORTHOGRAPHIC
};

/// Camera type fallback, defaults to Camera3D
const Camera = Camera3D;

//----------------------------------------------------------------------------------
// Defines and Macros
//----------------------------------------------------------------------------------

const DEG2RAD: f32 = rm.DEG2RAD;

// Default projection matrix cull distances (RL_CULL_DISTANCE_NEAR / _FAR from rlgl.h).
// These are `double` macros in C, so they are kept as f64 here.
const CAMERA_CULL_DISTANCE_NEAR: f64 = 0.05;
const CAMERA_CULL_DISTANCE_FAR: f64 = 4000.0;

// Camera projection types (from raylib.h)
const CAMERA_PERSPECTIVE: c_int = 0;
const CAMERA_ORTHOGRAPHIC: c_int = 1;

//----------------------------------------------------------------------------------
// libm functions, called directly so results are bit-identical to the C source.
//----------------------------------------------------------------------------------
extern fn fabsf(f32) f32;

//----------------------------------------------------------------------------------
// raymath functions, provided by the raymath translation unit in the build.
// (raymath's `export fn`s are not `pub`, so they are linked via their C symbols.)
//----------------------------------------------------------------------------------
extern fn Vector3Add(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3Subtract(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3Scale(v: Vector3, scalar: f32) Vector3;
extern fn Vector3CrossProduct(v1: Vector3, v2: Vector3) Vector3;
extern fn Vector3Normalize(v: Vector3) Vector3;
extern fn Vector3Negate(v: Vector3) Vector3;
extern fn Vector3Distance(v1: Vector3, v2: Vector3) f32;
extern fn Vector3Angle(v1: Vector3, v2: Vector3) f32;
extern fn Vector3RotateByAxisAngle(v: Vector3, axis: Vector3, angle: f32) Vector3;
extern fn MatrixLookAt(eye: Vector3, target: Vector3, up: Vector3) Matrix;
extern fn MatrixPerspective(fovY: f64, aspect: f64, nearPlane: f64, farPlane: f64) Matrix;
extern fn MatrixOrtho(left: f64, right: f64, bottom: f64, top: f64, nearPlane: f64, farPlane: f64) Matrix;
extern fn MatrixIdentity() Matrix;

//----------------------------------------------------------------------------------
// Module Functions Definition
//----------------------------------------------------------------------------------

/// Returns the cameras forward vector (normalized)
export fn GetCameraForward(camera: [*c]Camera) callconv(.c) Vector3 {
    return Vector3Normalize(Vector3Subtract(camera.*.target, camera.*.position));
}

/// Returns the cameras up vector (normalized)
/// Note: The up vector might not be perpendicular to the forward vector
export fn GetCameraUp(camera: [*c]Camera) callconv(.c) Vector3 {
    return Vector3Normalize(camera.*.up);
}

/// Returns the cameras right vector (normalized)
export fn GetCameraRight(camera: [*c]Camera) callconv(.c) Vector3 {
    const forward = GetCameraForward(camera);
    const up = GetCameraUp(camera);

    return Vector3Normalize(Vector3CrossProduct(forward, up));
}

/// Moves the camera in its forward direction
export fn CameraMoveForward(camera: [*c]Camera, distance: f32, moveInWorldPlane: bool) callconv(.c) void {
    var forward = GetCameraForward(camera);

    if (moveInWorldPlane) {
        // Project vector onto world plane (the plane defined by the up vector)
        if (fabsf(camera.*.up.z) > 0.7071) {
            forward.z = 0;
        } else if (fabsf(camera.*.up.x) > 0.7071) {
            forward.x = 0;
        } else {
            forward.y = 0;
        }

        forward = Vector3Normalize(forward);
    }

    // Scale by distance
    forward = Vector3Scale(forward, distance);

    // Move position and target
    camera.*.position = Vector3Add(camera.*.position, forward);
    camera.*.target = Vector3Add(camera.*.target, forward);
}

/// Moves the camera in its up direction
export fn CameraMoveUp(camera: [*c]Camera, distance: f32) callconv(.c) void {
    var up = GetCameraUp(camera);

    // Scale by distance
    up = Vector3Scale(up, distance);

    // Move position and target
    camera.*.position = Vector3Add(camera.*.position, up);
    camera.*.target = Vector3Add(camera.*.target, up);
}

/// Moves the camera target in its current right direction
export fn CameraMoveRight(camera: [*c]Camera, distance: f32, moveInWorldPlane: bool) callconv(.c) void {
    var right = GetCameraRight(camera);

    if (moveInWorldPlane) {
        // Project vector onto world plane (the plane defined by the up vector)
        if (fabsf(camera.*.up.z) > 0.7071) {
            right.z = 0;
        } else if (fabsf(camera.*.up.x) > 0.7071) {
            right.x = 0;
        } else {
            right.y = 0;
        }

        right = Vector3Normalize(right);
    }

    // Scale by distance
    right = Vector3Scale(right, distance);

    // Move position and target
    camera.*.position = Vector3Add(camera.*.position, right);
    camera.*.target = Vector3Add(camera.*.target, right);
}

/// Moves the camera position closer/farther to/from the camera target
export fn CameraMoveToTarget(camera: [*c]Camera, delta: f32) callconv(.c) void {
    var distance = Vector3Distance(camera.*.position, camera.*.target);

    // Apply delta
    distance += delta;

    // Distance must be greater than 0
    if (distance <= 0) distance = 0.001;

    // Set new distance by moving the position along the forward vector
    const forward = GetCameraForward(camera);
    camera.*.position = Vector3Add(camera.*.target, Vector3Scale(forward, -distance));
}

/// Rotates the camera around its up vector
/// Yaw is "looking left and right"
/// If rotateAroundTarget is false, the camera rotates around its position
/// Note: angle must be provided in radians
export fn CameraYaw(camera: [*c]Camera, angle: f32, rotateAroundTarget: bool) callconv(.c) void {
    // Rotation axis
    const up = GetCameraUp(camera);

    // View vector
    var targetPosition = Vector3Subtract(camera.*.target, camera.*.position);

    // Rotate view vector around up axis
    targetPosition = Vector3RotateByAxisAngle(targetPosition, up, angle);

    if (rotateAroundTarget) {
        // Move position relative to target
        camera.*.position = Vector3Subtract(camera.*.target, targetPosition);
    } else { // rotate around camera.position
        // Move target relative to position
        camera.*.target = Vector3Add(camera.*.position, targetPosition);
    }
}

/// Rotates the camera around its right vector, pitch is "looking up and down"
///  - lockView prevents camera overrotation (aka "somersaults")
///  - rotateAroundTarget defines if rotation is around target or around its position
///  - rotateUp rotates the up direction as well (typically only useful in CAMERA_FREE)
/// NOTE: angle must be provided in radians
export fn CameraPitch(camera: [*c]Camera, angle_in: f32, lockView: bool, rotateAroundTarget: bool, rotateUp: bool) callconv(.c) void {
    var angle = angle_in;

    // Up direction
    const up = GetCameraUp(camera);

    // View vector
    var targetPosition = Vector3Subtract(camera.*.target, camera.*.position);

    if (lockView) {
        // In these camera modes, clamp the Pitch angle
        // to allow only viewing straight up or down

        // Clamp view up
        var maxAngleUp = Vector3Angle(up, targetPosition);
        maxAngleUp -= 0.001; // avoid numerical errors
        if (angle > maxAngleUp) angle = maxAngleUp;

        // Clamp view down
        var maxAngleDown = Vector3Angle(Vector3Negate(up), targetPosition);
        maxAngleDown *= -1.0; // downwards angle is negative
        maxAngleDown += 0.001; // avoid numerical errors
        if (angle < maxAngleDown) angle = maxAngleDown;
    }

    // Rotation axis
    const right = GetCameraRight(camera);

    // Rotate view vector around right axis
    targetPosition = Vector3RotateByAxisAngle(targetPosition, right, angle);

    if (rotateAroundTarget) {
        // Move position relative to target
        camera.*.position = Vector3Subtract(camera.*.target, targetPosition);
    } else { // Rotate around camera.position
        // Move target relative to position
        camera.*.target = Vector3Add(camera.*.position, targetPosition);
    }

    if (rotateUp) {
        // Rotate up direction around right axis
        camera.*.up = Vector3RotateByAxisAngle(camera.*.up, right, angle);
    }
}

/// Rotates the camera around its forward vector
/// Roll is "turning your head sideways to the left or right"
/// Note: angle must be provided in radians
export fn CameraRoll(camera: [*c]Camera, angle: f32) callconv(.c) void {
    // Rotation axis
    const forward = GetCameraForward(camera);

    // Rotate up direction around forward axis
    camera.*.up = Vector3RotateByAxisAngle(camera.*.up, forward, angle);
}

/// Returns the camera view matrix
export fn GetCameraViewMatrix(camera: [*c]Camera) callconv(.c) Matrix {
    return MatrixLookAt(camera.*.position, camera.*.target, camera.*.up);
}

/// Returns the camera projection matrix
export fn GetCameraProjectionMatrix(camera: [*c]Camera, aspect: f32) callconv(.c) Matrix {
    if (camera.*.projection == CAMERA_PERSPECTIVE) {
        return MatrixPerspective(camera.*.fovy * DEG2RAD, aspect, CAMERA_CULL_DISTANCE_NEAR, CAMERA_CULL_DISTANCE_FAR);
    } else if (camera.*.projection == CAMERA_ORTHOGRAPHIC) {
        const top = @as(f64, camera.*.fovy) / 2.0;
        const right = top * aspect;

        return MatrixOrtho(-right, right, -top, top, CAMERA_CULL_DISTANCE_NEAR, CAMERA_CULL_DISTANCE_FAR);
    }

    return MatrixIdentity();
}
