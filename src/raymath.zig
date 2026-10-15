//! raymath v2.0 - Math functions to work with Vector2, Vector3, Vector4, Matrix and Quaternions
//!
//! Zig port of raylib's `raymath.h`. Every `RMAPI` function is exported with its
//! exact C name, byte-compatible signature, and C calling convention, so a C caller
//! can link against it out-of-line. Floating-point operation order matches the C
//! source exactly to keep results bit-identical, and libm functions are called via
//! extern declarations rather than `std.math`.

const std = @import("std");

// libm functions, called directly so results are bit-identical to the C source.
extern fn sqrtf(f32) f32;
extern fn sinf(f32) f32;
extern fn cosf(f32) f32;
extern fn asinf(f32) f32;
extern fn acosf(f32) f32;
extern fn atan2f(f32, f32) f32;
extern fn fabsf(f32) f32;
extern fn floorf(f32) f32;
extern fn fminf(f32, f32) f32;
extern fn fmaxf(f32, f32) f32;
extern fn tan(f64) f64;

//----------------------------------------------------------------------------------
// Defines and Macros
//----------------------------------------------------------------------------------

pub const PI: f32 = 3.14159265358979323846;
pub const EPSILON: f32 = 0.000001;
pub const DEG2RAD: f32 = PI / 180.0;
pub const RAD2DEG: f32 = 180.0 / PI;

//----------------------------------------------------------------------------------
// Types and Structures Definition
//----------------------------------------------------------------------------------

/// Vector2 type
pub const Vector2 = extern struct {
    x: f32,
    y: f32,
};

/// Vector3 type
pub const Vector3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

/// Vector4 type
pub const Vector4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

/// Quaternion type
pub const Quaternion = Vector4;

/// Matrix type (OpenGL style 4x4 - right handed, column major)
pub const Matrix = extern struct {
    m0: f32,
    m4: f32,
    m8: f32,
    m12: f32, // Matrix first row (4 components)
    m1: f32,
    m5: f32,
    m9: f32,
    m13: f32, // Matrix second row (4 components)
    m2: f32,
    m6: f32,
    m10: f32,
    m14: f32, // Matrix third row (4 components)
    m3: f32,
    m7: f32,
    m11: f32,
    m15: f32, // Matrix fourth row (4 components)
};

/// Helper type to be used instead of array return types for *ToFloat functions
pub const float3 = extern struct {
    v: [3]f32,
};

/// Helper type to be used instead of array return types for *ToFloat functions
pub const float16 = extern struct {
    v: [16]f32,
};

//----------------------------------------------------------------------------------
// Module Functions Definition - Utils math
//----------------------------------------------------------------------------------

/// Clamp float value
export fn Clamp(value: f32, min: f32, max: f32) callconv(.c) f32 {
    var result: f32 = if (value < min) min else value;

    if (result > max) result = max;

    return result;
}

/// Calculate linear interpolation between two floats
export fn Lerp(start: f32, end: f32, amount: f32) callconv(.c) f32 {
    const result = start + amount * (end - start);

    return result;
}

/// Normalize input value within input range
export fn Normalize(value: f32, start: f32, end: f32) callconv(.c) f32 {
    const result = (value - start) / (end - start);

    return result;
}

/// Remap input value within input range to output range
export fn Remap(value: f32, inputStart: f32, inputEnd: f32, outputStart: f32, outputEnd: f32) callconv(.c) f32 {
    const result = (value - inputStart) / (inputEnd - inputStart) * (outputEnd - outputStart) + outputStart;

    return result;
}

/// Wrap input value from min to max
export fn Wrap(value: f32, min: f32, max: f32) callconv(.c) f32 {
    const result = value - (max - min) * floorf((value - min) / (max - min));

    return result;
}

/// Check whether two given floats are almost equal
export fn FloatEquals(x: f32, y: f32) callconv(.c) c_int {
    const result: c_int = @intFromBool((fabsf(x - y)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(x), fabsf(y)))));

    return result;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Vector2 math
//----------------------------------------------------------------------------------

/// Vector with components value 0.0f
export fn Vector2Zero() callconv(.c) Vector2 {
    const result = Vector2{ .x = 0.0, .y = 0.0 };

    return result;
}

/// Vector with components value 1.0f
export fn Vector2One() callconv(.c) Vector2 {
    const result = Vector2{ .x = 1.0, .y = 1.0 };

    return result;
}

/// Add two vectors (v1 + v2)
export fn Vector2Add(v1: Vector2, v2: Vector2) callconv(.c) Vector2 {
    const result = Vector2{ .x = v1.x + v2.x, .y = v1.y + v2.y };

    return result;
}

/// Add vector and float value
export fn Vector2AddValue(v: Vector2, add: f32) callconv(.c) Vector2 {
    const result = Vector2{ .x = v.x + add, .y = v.y + add };

    return result;
}

/// Subtract two vectors (v1 - v2)
export fn Vector2Subtract(v1: Vector2, v2: Vector2) callconv(.c) Vector2 {
    const result = Vector2{ .x = v1.x - v2.x, .y = v1.y - v2.y };

    return result;
}

/// Subtract vector by float value
export fn Vector2SubtractValue(v: Vector2, sub: f32) callconv(.c) Vector2 {
    const result = Vector2{ .x = v.x - sub, .y = v.y - sub };

    return result;
}

/// Calculate vector length
export fn Vector2Length(v: Vector2) callconv(.c) f32 {
    const result = sqrtf((v.x * v.x) + (v.y * v.y));

    return result;
}

/// Calculate vector square length
export fn Vector2LengthSqr(v: Vector2) callconv(.c) f32 {
    const result = (v.x * v.x) + (v.y * v.y);

    return result;
}

/// Calculate two vectors dot product
export fn Vector2DotProduct(v1: Vector2, v2: Vector2) callconv(.c) f32 {
    const result = (v1.x * v2.x + v1.y * v2.y);

    return result;
}

/// Calculate two vectors cross product
export fn Vector2CrossProduct(v1: Vector2, v2: Vector2) callconv(.c) f32 {
    const result = (v1.x * v2.y - v1.y * v2.x);

    return result;
}

/// Calculate distance between two vectors
export fn Vector2Distance(v1: Vector2, v2: Vector2) callconv(.c) f32 {
    const result = sqrtf((v1.x - v2.x) * (v1.x - v2.x) + (v1.y - v2.y) * (v1.y - v2.y));

    return result;
}

/// Calculate square distance between two vectors
export fn Vector2DistanceSqr(v1: Vector2, v2: Vector2) callconv(.c) f32 {
    const result = ((v1.x - v2.x) * (v1.x - v2.x) + (v1.y - v2.y) * (v1.y - v2.y));

    return result;
}

/// Calculate the signed angle from v1 to v2, relative to the origin (0, 0)
export fn Vector2Angle(v1: Vector2, v2: Vector2) callconv(.c) f32 {
    var result: f32 = 0.0;

    const dot = v1.x * v2.x + v1.y * v2.y;
    const det = v1.x * v2.y - v1.y * v2.x;

    result = atan2f(det, dot);

    return result;
}

/// Calculate angle defined by a two vectors line
export fn Vector2LineAngle(start: Vector2, end: Vector2) callconv(.c) f32 {
    var result: f32 = 0.0;

    result = -atan2f(end.y - start.y, end.x - start.x);

    return result;
}

/// Scale vector (multiply by value)
export fn Vector2Scale(v: Vector2, scale: f32) callconv(.c) Vector2 {
    const result = Vector2{ .x = v.x * scale, .y = v.y * scale };

    return result;
}

/// Multiply vector by vector
export fn Vector2Multiply(v1: Vector2, v2: Vector2) callconv(.c) Vector2 {
    const result = Vector2{ .x = v1.x * v2.x, .y = v1.y * v2.y };

    return result;
}

/// Negate vector
export fn Vector2Negate(v: Vector2) callconv(.c) Vector2 {
    const result = Vector2{ .x = -v.x, .y = -v.y };

    return result;
}

/// Divide vector by vector
export fn Vector2Divide(v1: Vector2, v2: Vector2) callconv(.c) Vector2 {
    const result = Vector2{ .x = v1.x / v2.x, .y = v1.y / v2.y };

    return result;
}

/// Normalize provided vector
export fn Vector2Normalize(v: Vector2) callconv(.c) Vector2 {
    var result = Vector2{ .x = 0, .y = 0 };
    const length = sqrtf((v.x * v.x) + (v.y * v.y));

    if (length > 0) {
        const ilength = 1.0 / length;
        result.x = v.x * ilength;
        result.y = v.y * ilength;
    }

    return result;
}

/// Transforms a Vector2 by a given Matrix
export fn Vector2Transform(v: Vector2, mat: Matrix) callconv(.c) Vector2 {
    var result = Vector2{ .x = 0, .y = 0 };

    const x = v.x;
    const y = v.y;
    const z: f32 = 0;

    result.x = mat.m0 * x + mat.m4 * y + mat.m8 * z + mat.m12;
    result.y = mat.m1 * x + mat.m5 * y + mat.m9 * z + mat.m13;

    return result;
}

/// Calculate linear interpolation between two vectors
export fn Vector2Lerp(v1: Vector2, v2: Vector2, amount: f32) callconv(.c) Vector2 {
    var result = Vector2{ .x = 0, .y = 0 };

    result.x = v1.x + amount * (v2.x - v1.x);
    result.y = v1.y + amount * (v2.y - v1.y);

    return result;
}

/// Calculate reflected vector to normal
export fn Vector2Reflect(v: Vector2, normal: Vector2) callconv(.c) Vector2 {
    var result = Vector2{ .x = 0, .y = 0 };

    const dotProduct = (v.x * normal.x + v.y * normal.y); // Dot product

    result.x = v.x - (2.0 * normal.x) * dotProduct;
    result.y = v.y - (2.0 * normal.y) * dotProduct;

    return result;
}

/// Get min value for each pair of components
export fn Vector2Min(v1: Vector2, v2: Vector2) callconv(.c) Vector2 {
    var result = Vector2{ .x = 0, .y = 0 };

    result.x = fminf(v1.x, v2.x);
    result.y = fminf(v1.y, v2.y);

    return result;
}

/// Get max value for each pair of components
export fn Vector2Max(v1: Vector2, v2: Vector2) callconv(.c) Vector2 {
    var result = Vector2{ .x = 0, .y = 0 };

    result.x = fmaxf(v1.x, v2.x);
    result.y = fmaxf(v1.y, v2.y);

    return result;
}

/// Rotate vector by angle
export fn Vector2Rotate(v: Vector2, angle: f32) callconv(.c) Vector2 {
    var result = Vector2{ .x = 0, .y = 0 };

    const cosres = cosf(angle);
    const sinres = sinf(angle);

    result.x = v.x * cosres - v.y * sinres;
    result.y = v.x * sinres + v.y * cosres;

    return result;
}

/// Move Vector towards target
export fn Vector2MoveTowards(v: Vector2, target: Vector2, maxDistance: f32) callconv(.c) Vector2 {
    var result = Vector2{ .x = 0, .y = 0 };

    const dx = target.x - v.x;
    const dy = target.y - v.y;
    const value = (dx * dx) + (dy * dy);

    if ((value == 0) or ((maxDistance >= 0) and (value <= maxDistance * maxDistance))) return target;

    const dist = sqrtf(value);

    result.x = v.x + dx / dist * maxDistance;
    result.y = v.y + dy / dist * maxDistance;

    return result;
}

/// Invert the given vector
export fn Vector2Invert(v: Vector2) callconv(.c) Vector2 {
    const result = Vector2{ .x = 1.0 / v.x, .y = 1.0 / v.y };

    return result;
}

/// Clamp the components of the vector between min and max values specified by the given vectors
export fn Vector2Clamp(v: Vector2, min: Vector2, max: Vector2) callconv(.c) Vector2 {
    var result = Vector2{ .x = 0, .y = 0 };

    result.x = fminf(max.x, fmaxf(min.x, v.x));
    result.y = fminf(max.y, fmaxf(min.y, v.y));

    return result;
}

/// Clamp the magnitude of the vector between two min and max values
export fn Vector2ClampValue(v: Vector2, min: f32, max: f32) callconv(.c) Vector2 {
    var result = v;

    var length = (v.x * v.x) + (v.y * v.y);
    if (length > 0.0) {
        length = sqrtf(length);

        var scale: f32 = 1; // By default, 1 as the neutral element
        if (length < min) {
            scale = min / length;
        } else if (length > max) {
            scale = max / length;
        }

        result.x = v.x * scale;
        result.y = v.y * scale;
    }

    return result;
}

/// Check whether two given vectors are almost equal
export fn Vector2Equals(p: Vector2, q: Vector2) callconv(.c) c_int {
    const result: c_int = @intFromBool(((fabsf(p.x - q.x)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.x), fabsf(q.x))))) and
        ((fabsf(p.y - q.y)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.y), fabsf(q.y))))));

    return result;
}

/// Compute the direction of a refracted ray
export fn Vector2Refract(v_in: Vector2, n: Vector2, r: f32) callconv(.c) Vector2 {
    var v = v_in;
    var result = Vector2{ .x = 0, .y = 0 };

    const dot = v.x * n.x + v.y * n.y;
    var d = 1.0 - r * r * (1.0 - dot * dot);

    if (d >= 0.0) {
        d = sqrtf(d);
        v.x = r * v.x - (r * dot + d) * n.x;
        v.y = r * v.y - (r * dot + d) * n.y;

        result = v;
    }

    return result;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Vector3 math
//----------------------------------------------------------------------------------

/// Vector with components value 0.0f
export fn Vector3Zero() callconv(.c) Vector3 {
    const result = Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };

    return result;
}

/// Vector with components value 1.0f
export fn Vector3One() callconv(.c) Vector3 {
    const result = Vector3{ .x = 1.0, .y = 1.0, .z = 1.0 };

    return result;
}

/// Add two vectors
export fn Vector3Add(v1: Vector3, v2: Vector3) callconv(.c) Vector3 {
    const result = Vector3{ .x = v1.x + v2.x, .y = v1.y + v2.y, .z = v1.z + v2.z };

    return result;
}

/// Add vector and float value
export fn Vector3AddValue(v: Vector3, add: f32) callconv(.c) Vector3 {
    const result = Vector3{ .x = v.x + add, .y = v.y + add, .z = v.z + add };

    return result;
}

/// Subtract two vectors
export fn Vector3Subtract(v1: Vector3, v2: Vector3) callconv(.c) Vector3 {
    const result = Vector3{ .x = v1.x - v2.x, .y = v1.y - v2.y, .z = v1.z - v2.z };

    return result;
}

/// Subtract vector by float value
export fn Vector3SubtractValue(v: Vector3, sub: f32) callconv(.c) Vector3 {
    const result = Vector3{ .x = v.x - sub, .y = v.y - sub, .z = v.z - sub };

    return result;
}

/// Multiply vector by scalar
export fn Vector3Scale(v: Vector3, scalar: f32) callconv(.c) Vector3 {
    const result = Vector3{ .x = v.x * scalar, .y = v.y * scalar, .z = v.z * scalar };

    return result;
}

/// Multiply vector by vector
export fn Vector3Multiply(v1: Vector3, v2: Vector3) callconv(.c) Vector3 {
    const result = Vector3{ .x = v1.x * v2.x, .y = v1.y * v2.y, .z = v1.z * v2.z };

    return result;
}

/// Calculate two vectors cross product
export fn Vector3CrossProduct(v1: Vector3, v2: Vector3) callconv(.c) Vector3 {
    const result = Vector3{ .x = v1.y * v2.z - v1.z * v2.y, .y = v1.z * v2.x - v1.x * v2.z, .z = v1.x * v2.y - v1.y * v2.x };

    return result;
}

/// Calculate one vector perpendicular vector
export fn Vector3Perpendicular(v: Vector3) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    var min = fabsf(v.x);
    var cardinalAxis = Vector3{ .x = 1.0, .y = 0.0, .z = 0.0 };

    if (fabsf(v.y) < min) {
        min = fabsf(v.y);
        const tmp = Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 };
        cardinalAxis = tmp;
    }

    if (fabsf(v.z) < min) {
        const tmp = Vector3{ .x = 0.0, .y = 0.0, .z = 1.0 };
        cardinalAxis = tmp;
    }

    // Cross product between vectors
    result.x = v.y * cardinalAxis.z - v.z * cardinalAxis.y;
    result.y = v.z * cardinalAxis.x - v.x * cardinalAxis.z;
    result.z = v.x * cardinalAxis.y - v.y * cardinalAxis.x;

    return result;
}

/// Calculate vector length
export fn Vector3Length(v: Vector3) callconv(.c) f32 {
    const result = sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);

    return result;
}

/// Calculate vector square length
export fn Vector3LengthSqr(v: Vector3) callconv(.c) f32 {
    const result = v.x * v.x + v.y * v.y + v.z * v.z;

    return result;
}

/// Calculate two vectors dot product
export fn Vector3DotProduct(v1: Vector3, v2: Vector3) callconv(.c) f32 {
    const result = (v1.x * v2.x + v1.y * v2.y + v1.z * v2.z);

    return result;
}

/// Calculate distance between two vectors
export fn Vector3Distance(v1: Vector3, v2: Vector3) callconv(.c) f32 {
    var result: f32 = 0.0;

    const dx = v2.x - v1.x;
    const dy = v2.y - v1.y;
    const dz = v2.z - v1.z;
    result = sqrtf(dx * dx + dy * dy + dz * dz);

    return result;
}

/// Calculate square distance between two vectors
export fn Vector3DistanceSqr(v1: Vector3, v2: Vector3) callconv(.c) f32 {
    var result: f32 = 0.0;

    const dx = v2.x - v1.x;
    const dy = v2.y - v1.y;
    const dz = v2.z - v1.z;
    result = dx * dx + dy * dy + dz * dz;

    return result;
}

/// Calculate angle between two vectors
export fn Vector3Angle(v1: Vector3, v2: Vector3) callconv(.c) f32 {
    var result: f32 = 0.0;

    const cross = Vector3{ .x = v1.y * v2.z - v1.z * v2.y, .y = v1.z * v2.x - v1.x * v2.z, .z = v1.x * v2.y - v1.y * v2.x };
    const len = sqrtf(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z);
    const dot = (v1.x * v2.x + v1.y * v2.y + v1.z * v2.z);
    result = atan2f(len, dot);

    return result;
}

/// Negate provided vector (invert direction)
export fn Vector3Negate(v: Vector3) callconv(.c) Vector3 {
    const result = Vector3{ .x = -v.x, .y = -v.y, .z = -v.z };

    return result;
}

/// Divide vector by vector
export fn Vector3Divide(v1: Vector3, v2: Vector3) callconv(.c) Vector3 {
    const result = Vector3{ .x = v1.x / v2.x, .y = v1.y / v2.y, .z = v1.z / v2.z };

    return result;
}

/// Normalize provided vector
export fn Vector3Normalize(v: Vector3) callconv(.c) Vector3 {
    var result = v;

    const length = sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
    if (length != 0.0) {
        const ilength = 1.0 / length;

        result.x *= ilength;
        result.y *= ilength;
        result.z *= ilength;
    }

    return result;
}

/// Calculate the projection of the vector v1 on to v2
export fn Vector3Project(v1: Vector3, v2: Vector3) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    const v1dv2 = (v1.x * v2.x + v1.y * v2.y + v1.z * v2.z);
    const v2dv2 = (v2.x * v2.x + v2.y * v2.y + v2.z * v2.z);

    const mag = v1dv2 / v2dv2;

    result.x = v2.x * mag;
    result.y = v2.y * mag;
    result.z = v2.z * mag;

    return result;
}

/// Calculate the rejection of the vector v1 on to v2
export fn Vector3Reject(v1: Vector3, v2: Vector3) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    const v1dv2 = (v1.x * v2.x + v1.y * v2.y + v1.z * v2.z);
    const v2dv2 = (v2.x * v2.x + v2.y * v2.y + v2.z * v2.z);

    const mag = v1dv2 / v2dv2;

    result.x = v1.x - (v2.x * mag);
    result.y = v1.y - (v2.y * mag);
    result.z = v1.z - (v2.z * mag);

    return result;
}

/// Orthonormalize provided vectors (Gram-Schmidt)
export fn Vector3OrthoNormalize(v1: *Vector3, v2: *Vector3) callconv(.c) void {
    var length: f32 = 0.0;
    var ilength: f32 = 0.0;

    // Vector3Normalize(*v1);
    var v = v1.*;
    length = sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
    if (length == 0.0) length = 1.0;
    ilength = 1.0 / length;
    v1.x *= ilength;
    v1.y *= ilength;
    v1.z *= ilength;

    // Vector3CrossProduct(*v1, *v2)
    var vn1 = Vector3{ .x = v1.y * v2.z - v1.z * v2.y, .y = v1.z * v2.x - v1.x * v2.z, .z = v1.x * v2.y - v1.y * v2.x };

    // Vector3Normalize(vn1);
    v = vn1;
    length = sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
    if (length == 0.0) length = 1.0;
    ilength = 1.0 / length;
    vn1.x *= ilength;
    vn1.y *= ilength;
    vn1.z *= ilength;

    // Vector3CrossProduct(vn1, *v1)
    const vn2 = Vector3{ .x = vn1.y * v1.z - vn1.z * v1.y, .y = vn1.z * v1.x - vn1.x * v1.z, .z = vn1.x * v1.y - vn1.y * v1.x };

    v2.* = vn2;
}

/// Transforms a Vector3 by a given Matrix
export fn Vector3Transform(v: Vector3, mat: Matrix) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    const x = v.x;
    const y = v.y;
    const z = v.z;

    result.x = mat.m0 * x + mat.m4 * y + mat.m8 * z + mat.m12;
    result.y = mat.m1 * x + mat.m5 * y + mat.m9 * z + mat.m13;
    result.z = mat.m2 * x + mat.m6 * y + mat.m10 * z + mat.m14;

    return result;
}

/// Transform a vector by quaternion rotation
export fn Vector3RotateByQuaternion(v: Vector3, q: Quaternion) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    result.x = v.x * (q.x * q.x + q.w * q.w - q.y * q.y - q.z * q.z) + v.y * (2 * q.x * q.y - 2 * q.w * q.z) + v.z * (2 * q.x * q.z + 2 * q.w * q.y);
    result.y = v.x * (2 * q.w * q.z + 2 * q.x * q.y) + v.y * (q.w * q.w - q.x * q.x + q.y * q.y - q.z * q.z) + v.z * (-2 * q.w * q.x + 2 * q.y * q.z);
    result.z = v.x * (-2 * q.w * q.y + 2 * q.x * q.z) + v.y * (2 * q.w * q.x + 2 * q.y * q.z) + v.z * (q.w * q.w - q.x * q.x - q.y * q.y + q.z * q.z);

    return result;
}

/// Rotates a vector around an axis
export fn Vector3RotateByAxisAngle(v: Vector3, axis_in: Vector3, angle_in: f32) callconv(.c) Vector3 {
    // Using Euler-Rodrigues Formula
    var axis = axis_in;
    var angle = angle_in;

    var result = v;

    // Vector3Normalize(axis);
    var length = sqrtf(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z);
    if (length == 0.0) length = 1.0;
    const ilength = 1.0 / length;
    axis.x *= ilength;
    axis.y *= ilength;
    axis.z *= ilength;

    angle /= 2.0;
    var a = sinf(angle);
    const b = axis.x * a;
    const c = axis.y * a;
    const d = axis.z * a;
    a = cosf(angle);
    const w = Vector3{ .x = b, .y = c, .z = d };

    // Vector3CrossProduct(w, v)
    var wv = Vector3{ .x = w.y * v.z - w.z * v.y, .y = w.z * v.x - w.x * v.z, .z = w.x * v.y - w.y * v.x };

    // Vector3CrossProduct(w, wv)
    var wwv = Vector3{ .x = w.y * wv.z - w.z * wv.y, .y = w.z * wv.x - w.x * wv.z, .z = w.x * wv.y - w.y * wv.x };

    // Vector3Scale(wv, 2*a)
    a *= 2;
    wv.x *= a;
    wv.y *= a;
    wv.z *= a;

    // Vector3Scale(wwv, 2)
    wwv.x *= 2;
    wwv.y *= 2;
    wwv.z *= 2;

    result.x += wv.x;
    result.y += wv.y;
    result.z += wv.z;

    result.x += wwv.x;
    result.y += wwv.y;
    result.z += wwv.z;

    return result;
}

/// Move Vector towards target
export fn Vector3MoveTowards(v: Vector3, target: Vector3, maxDistance: f32) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    const dx = target.x - v.x;
    const dy = target.y - v.y;
    const dz = target.z - v.z;
    const value = (dx * dx) + (dy * dy) + (dz * dz);

    if ((value == 0) or ((maxDistance >= 0) and (value <= maxDistance * maxDistance))) return target;

    const dist = sqrtf(value);

    result.x = v.x + dx / dist * maxDistance;
    result.y = v.y + dy / dist * maxDistance;
    result.z = v.z + dz / dist * maxDistance;

    return result;
}

/// Calculate linear interpolation between two vectors
export fn Vector3Lerp(v1: Vector3, v2: Vector3, amount: f32) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    result.x = v1.x + amount * (v2.x - v1.x);
    result.y = v1.y + amount * (v2.y - v1.y);
    result.z = v1.z + amount * (v2.z - v1.z);

    return result;
}

/// Calculate cubic hermite interpolation between two vectors and their tangents
export fn Vector3CubicHermite(v1: Vector3, tangent1: Vector3, v2: Vector3, tangent2: Vector3, amount: f32) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    const amountPow2 = amount * amount;
    const amountPow3 = amount * amount * amount;

    result.x = (2 * amountPow3 - 3 * amountPow2 + 1) * v1.x + (amountPow3 - 2 * amountPow2 + amount) * tangent1.x + (-2 * amountPow3 + 3 * amountPow2) * v2.x + (amountPow3 - amountPow2) * tangent2.x;
    result.y = (2 * amountPow3 - 3 * amountPow2 + 1) * v1.y + (amountPow3 - 2 * amountPow2 + amount) * tangent1.y + (-2 * amountPow3 + 3 * amountPow2) * v2.y + (amountPow3 - amountPow2) * tangent2.y;
    result.z = (2 * amountPow3 - 3 * amountPow2 + 1) * v1.z + (amountPow3 - 2 * amountPow2 + amount) * tangent1.z + (-2 * amountPow3 + 3 * amountPow2) * v2.z + (amountPow3 - amountPow2) * tangent2.z;

    return result;
}

/// Calculate reflected vector to normal
export fn Vector3Reflect(v: Vector3, normal: Vector3) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    // R = I - (2*N*(DotProduct[I, N]))
    const dotProduct = (v.x * normal.x + v.y * normal.y + v.z * normal.z);

    result.x = v.x - (2.0 * normal.x) * dotProduct;
    result.y = v.y - (2.0 * normal.y) * dotProduct;
    result.z = v.z - (2.0 * normal.z) * dotProduct;

    return result;
}

/// Get min value for each pair of components
export fn Vector3Min(v1: Vector3, v2: Vector3) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    result.x = fminf(v1.x, v2.x);
    result.y = fminf(v1.y, v2.y);
    result.z = fminf(v1.z, v2.z);

    return result;
}

/// Get max value for each pair of components
export fn Vector3Max(v1: Vector3, v2: Vector3) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    result.x = fmaxf(v1.x, v2.x);
    result.y = fmaxf(v1.y, v2.y);
    result.z = fmaxf(v1.z, v2.z);

    return result;
}

/// Compute barycenter coordinates (u, v, w) for point p with respect to triangle (a, b, c)
export fn Vector3Barycenter(p: Vector3, a: Vector3, b: Vector3, c: Vector3) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    const v0 = Vector3{ .x = b.x - a.x, .y = b.y - a.y, .z = b.z - a.z }; // Vector3Subtract(b, a)
    const v1 = Vector3{ .x = c.x - a.x, .y = c.y - a.y, .z = c.z - a.z }; // Vector3Subtract(c, a)
    const v2 = Vector3{ .x = p.x - a.x, .y = p.y - a.y, .z = p.z - a.z }; // Vector3Subtract(p, a)
    const d00 = (v0.x * v0.x + v0.y * v0.y + v0.z * v0.z); // Vector3DotProduct(v0, v0)
    const d01 = (v0.x * v1.x + v0.y * v1.y + v0.z * v1.z); // Vector3DotProduct(v0, v1)
    const d11 = (v1.x * v1.x + v1.y * v1.y + v1.z * v1.z); // Vector3DotProduct(v1, v1)
    const d20 = (v2.x * v0.x + v2.y * v0.y + v2.z * v0.z); // Vector3DotProduct(v2, v0)
    const d21 = (v2.x * v1.x + v2.y * v1.y + v2.z * v1.z); // Vector3DotProduct(v2, v1)

    const denom = d00 * d11 - d01 * d01;

    result.y = (d11 * d20 - d01 * d21) / denom;
    result.z = (d00 * d21 - d01 * d20) / denom;
    result.x = 1.0 - (result.z + result.y);

    return result;
}

/// Projects a Vector3 from screen space into object space
export fn Vector3Unproject(source: Vector3, projection: Matrix, view: Matrix) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    // MatrixMultiply(view, projection);
    const matViewProj = Matrix{
        .m0 = view.m0 * projection.m0 + view.m1 * projection.m4 + view.m2 * projection.m8 + view.m3 * projection.m12,
        .m4 = view.m0 * projection.m1 + view.m1 * projection.m5 + view.m2 * projection.m9 + view.m3 * projection.m13,
        .m8 = view.m0 * projection.m2 + view.m1 * projection.m6 + view.m2 * projection.m10 + view.m3 * projection.m14,
        .m12 = view.m0 * projection.m3 + view.m1 * projection.m7 + view.m2 * projection.m11 + view.m3 * projection.m15,
        .m1 = view.m4 * projection.m0 + view.m5 * projection.m4 + view.m6 * projection.m8 + view.m7 * projection.m12,
        .m5 = view.m4 * projection.m1 + view.m5 * projection.m5 + view.m6 * projection.m9 + view.m7 * projection.m13,
        .m9 = view.m4 * projection.m2 + view.m5 * projection.m6 + view.m6 * projection.m10 + view.m7 * projection.m14,
        .m13 = view.m4 * projection.m3 + view.m5 * projection.m7 + view.m6 * projection.m11 + view.m7 * projection.m15,
        .m2 = view.m8 * projection.m0 + view.m9 * projection.m4 + view.m10 * projection.m8 + view.m11 * projection.m12,
        .m6 = view.m8 * projection.m1 + view.m9 * projection.m5 + view.m10 * projection.m9 + view.m11 * projection.m13,
        .m10 = view.m8 * projection.m2 + view.m9 * projection.m6 + view.m10 * projection.m10 + view.m11 * projection.m14,
        .m14 = view.m8 * projection.m3 + view.m9 * projection.m7 + view.m10 * projection.m11 + view.m11 * projection.m15,
        .m3 = view.m12 * projection.m0 + view.m13 * projection.m4 + view.m14 * projection.m8 + view.m15 * projection.m12,
        .m7 = view.m12 * projection.m1 + view.m13 * projection.m5 + view.m14 * projection.m9 + view.m15 * projection.m13,
        .m11 = view.m12 * projection.m2 + view.m13 * projection.m6 + view.m14 * projection.m10 + view.m15 * projection.m14,
        .m15 = view.m12 * projection.m3 + view.m13 * projection.m7 + view.m14 * projection.m11 + view.m15 * projection.m15,
    };

    // Calculate inverted matrix -> MatrixInvert(matViewProj);
    const a00 = matViewProj.m0;
    const a01 = matViewProj.m1;
    const a02 = matViewProj.m2;
    const a03 = matViewProj.m3;
    const a10 = matViewProj.m4;
    const a11 = matViewProj.m5;
    const a12 = matViewProj.m6;
    const a13 = matViewProj.m7;
    const a20 = matViewProj.m8;
    const a21 = matViewProj.m9;
    const a22 = matViewProj.m10;
    const a23 = matViewProj.m11;
    const a30 = matViewProj.m12;
    const a31 = matViewProj.m13;
    const a32 = matViewProj.m14;
    const a33 = matViewProj.m15;

    const b00 = a00 * a11 - a01 * a10;
    const b01 = a00 * a12 - a02 * a10;
    const b02 = a00 * a13 - a03 * a10;
    const b03 = a01 * a12 - a02 * a11;
    const b04 = a01 * a13 - a03 * a11;
    const b05 = a02 * a13 - a03 * a12;
    const b06 = a20 * a31 - a21 * a30;
    const b07 = a20 * a32 - a22 * a30;
    const b08 = a20 * a33 - a23 * a30;
    const b09 = a21 * a32 - a22 * a31;
    const b10 = a21 * a33 - a23 * a31;
    const b11 = a22 * a33 - a23 * a32;

    const invDet = 1.0 / (b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06);

    const matViewProjInv = Matrix{
        .m0 = (a11 * b11 - a12 * b10 + a13 * b09) * invDet,
        .m4 = (-a01 * b11 + a02 * b10 - a03 * b09) * invDet,
        .m8 = (a31 * b05 - a32 * b04 + a33 * b03) * invDet,
        .m12 = (-a21 * b05 + a22 * b04 - a23 * b03) * invDet,
        .m1 = (-a10 * b11 + a12 * b08 - a13 * b07) * invDet,
        .m5 = (a00 * b11 - a02 * b08 + a03 * b07) * invDet,
        .m9 = (-a30 * b05 + a32 * b02 - a33 * b01) * invDet,
        .m13 = (a20 * b05 - a22 * b02 + a23 * b01) * invDet,
        .m2 = (a10 * b10 - a11 * b08 + a13 * b06) * invDet,
        .m6 = (-a00 * b10 + a01 * b08 - a03 * b06) * invDet,
        .m10 = (a30 * b04 - a31 * b02 + a33 * b00) * invDet,
        .m14 = (-a20 * b04 + a21 * b02 - a23 * b00) * invDet,
        .m3 = (-a10 * b09 + a11 * b07 - a12 * b06) * invDet,
        .m7 = (a00 * b09 - a01 * b07 + a02 * b06) * invDet,
        .m11 = (-a30 * b03 + a31 * b01 - a32 * b00) * invDet,
        .m15 = (a20 * b03 - a21 * b01 + a22 * b00) * invDet,
    };

    // Create quaternion from source point
    const quat = Quaternion{ .x = source.x, .y = source.y, .z = source.z, .w = 1.0 };

    // QuaternionTransform(quat, matViewProjInv)
    const qtransformed = Quaternion{
        .x = matViewProjInv.m0 * quat.x + matViewProjInv.m4 * quat.y + matViewProjInv.m8 * quat.z + matViewProjInv.m12 * quat.w,
        .y = matViewProjInv.m1 * quat.x + matViewProjInv.m5 * quat.y + matViewProjInv.m9 * quat.z + matViewProjInv.m13 * quat.w,
        .z = matViewProjInv.m2 * quat.x + matViewProjInv.m6 * quat.y + matViewProjInv.m10 * quat.z + matViewProjInv.m14 * quat.w,
        .w = matViewProjInv.m3 * quat.x + matViewProjInv.m7 * quat.y + matViewProjInv.m11 * quat.z + matViewProjInv.m15 * quat.w,
    };

    // Normalized world points in vectors
    result.x = qtransformed.x / qtransformed.w;
    result.y = qtransformed.y / qtransformed.w;
    result.z = qtransformed.z / qtransformed.w;

    return result;
}

/// Get Vector3 as float array
export fn Vector3ToFloatV(v: Vector3) callconv(.c) float3 {
    var buffer = float3{ .v = .{ 0, 0, 0 } };

    buffer.v[0] = v.x;
    buffer.v[1] = v.y;
    buffer.v[2] = v.z;

    return buffer;
}

/// Invert the given vector
export fn Vector3Invert(v: Vector3) callconv(.c) Vector3 {
    const result = Vector3{ .x = 1.0 / v.x, .y = 1.0 / v.y, .z = 1.0 / v.z };

    return result;
}

/// Clamp the components of the vector between min and max values specified by the given vectors
export fn Vector3Clamp(v: Vector3, min: Vector3, max: Vector3) callconv(.c) Vector3 {
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    result.x = fminf(max.x, fmaxf(min.x, v.x));
    result.y = fminf(max.y, fmaxf(min.y, v.y));
    result.z = fminf(max.z, fmaxf(min.z, v.z));

    return result;
}

/// Clamp the magnitude of the vector between two values
export fn Vector3ClampValue(v: Vector3, min: f32, max: f32) callconv(.c) Vector3 {
    var result = v;

    var length = (v.x * v.x) + (v.y * v.y) + (v.z * v.z);
    if (length > 0.0) {
        length = sqrtf(length);

        var scale: f32 = 1; // By default, 1 as the neutral element
        if (length < min) {
            scale = min / length;
        } else if (length > max) {
            scale = max / length;
        }

        result.x = v.x * scale;
        result.y = v.y * scale;
        result.z = v.z * scale;
    }

    return result;
}

/// Check whether two given vectors are almost equal
export fn Vector3Equals(p: Vector3, q: Vector3) callconv(.c) c_int {
    const result: c_int = @intFromBool(((fabsf(p.x - q.x)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.x), fabsf(q.x))))) and
        ((fabsf(p.y - q.y)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.y), fabsf(q.y))))) and
        ((fabsf(p.z - q.z)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.z), fabsf(q.z))))));

    return result;
}

/// Compute the direction of a refracted ray
export fn Vector3Refract(v_in: Vector3, n: Vector3, r: f32) callconv(.c) Vector3 {
    var v = v_in;
    var result = Vector3{ .x = 0, .y = 0, .z = 0 };

    const dot = v.x * n.x + v.y * n.y + v.z * n.z;
    var d = 1.0 - r * r * (1.0 - dot * dot);

    if (d >= 0.0) {
        d = sqrtf(d);
        v.x = r * v.x - (r * dot + d) * n.x;
        v.y = r * v.y - (r * dot + d) * n.y;
        v.z = r * v.z - (r * dot + d) * n.z;

        result = v;
    }

    return result;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Vector4 math
//----------------------------------------------------------------------------------

/// Get vector zero
export fn Vector4Zero() callconv(.c) Vector4 {
    const result = Vector4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 };
    return result;
}

/// Get vector one
export fn Vector4One() callconv(.c) Vector4 {
    const result = Vector4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
    return result;
}

/// Add two vectors
export fn Vector4Add(v1: Vector4, v2: Vector4) callconv(.c) Vector4 {
    const result = Vector4{
        .x = v1.x + v2.x,
        .y = v1.y + v2.y,
        .z = v1.z + v2.z,
        .w = v1.w + v2.w,
    };
    return result;
}

/// Add value to vector components
export fn Vector4AddValue(v: Vector4, add: f32) callconv(.c) Vector4 {
    const result = Vector4{
        .x = v.x + add,
        .y = v.y + add,
        .z = v.z + add,
        .w = v.w + add,
    };
    return result;
}

/// Subtract vectors
export fn Vector4Subtract(v1: Vector4, v2: Vector4) callconv(.c) Vector4 {
    const result = Vector4{
        .x = v1.x - v2.x,
        .y = v1.y - v2.y,
        .z = v1.z - v2.z,
        .w = v1.w - v2.w,
    };
    return result;
}

/// Subtract value from vector components
export fn Vector4SubtractValue(v: Vector4, add: f32) callconv(.c) Vector4 {
    const result = Vector4{
        .x = v.x - add,
        .y = v.y - add,
        .z = v.z - add,
        .w = v.w - add,
    };
    return result;
}

/// Vector length
export fn Vector4Length(v: Vector4) callconv(.c) f32 {
    const result = sqrtf((v.x * v.x) + (v.y * v.y) + (v.z * v.z) + (v.w * v.w));
    return result;
}

/// Vector square length
export fn Vector4LengthSqr(v: Vector4) callconv(.c) f32 {
    const result = (v.x * v.x) + (v.y * v.y) + (v.z * v.z) + (v.w * v.w);
    return result;
}

/// Vectors dot product
export fn Vector4DotProduct(v1: Vector4, v2: Vector4) callconv(.c) f32 {
    const result = (v1.x * v2.x + v1.y * v2.y + v1.z * v2.z + v1.w * v2.w);
    return result;
}

/// Calculate distance between two vectors
export fn Vector4Distance(v1: Vector4, v2: Vector4) callconv(.c) f32 {
    const result = sqrtf((v1.x - v2.x) * (v1.x - v2.x) + (v1.y - v2.y) * (v1.y - v2.y) +
        (v1.z - v2.z) * (v1.z - v2.z) + (v1.w - v2.w) * (v1.w - v2.w));
    return result;
}

/// Calculate square distance between two vectors
export fn Vector4DistanceSqr(v1: Vector4, v2: Vector4) callconv(.c) f32 {
    const result = (v1.x - v2.x) * (v1.x - v2.x) + (v1.y - v2.y) * (v1.y - v2.y) +
        (v1.z - v2.z) * (v1.z - v2.z) + (v1.w - v2.w) * (v1.w - v2.w);

    return result;
}

/// Scale vector components by value (multiply)
export fn Vector4Scale(v: Vector4, scale: f32) callconv(.c) Vector4 {
    const result = Vector4{ .x = v.x * scale, .y = v.y * scale, .z = v.z * scale, .w = v.w * scale };
    return result;
}

/// Multiply vector by vector
export fn Vector4Multiply(v1: Vector4, v2: Vector4) callconv(.c) Vector4 {
    const result = Vector4{ .x = v1.x * v2.x, .y = v1.y * v2.y, .z = v1.z * v2.z, .w = v1.w * v2.w };
    return result;
}

/// Negate vector
export fn Vector4Negate(v: Vector4) callconv(.c) Vector4 {
    const result = Vector4{ .x = -v.x, .y = -v.y, .z = -v.z, .w = -v.w };
    return result;
}

/// Divide vector by vector
export fn Vector4Divide(v1: Vector4, v2: Vector4) callconv(.c) Vector4 {
    const result = Vector4{ .x = v1.x / v2.x, .y = v1.y / v2.y, .z = v1.z / v2.z, .w = v1.w / v2.w };
    return result;
}

/// Normalize provided vector
export fn Vector4Normalize(v: Vector4) callconv(.c) Vector4 {
    var result = Vector4{ .x = 0, .y = 0, .z = 0, .w = 0 };
    const length = sqrtf((v.x * v.x) + (v.y * v.y) + (v.z * v.z) + (v.w * v.w));

    if (length > 0) {
        const ilength = 1.0 / length;
        result.x = v.x * ilength;
        result.y = v.y * ilength;
        result.z = v.z * ilength;
        result.w = v.w * ilength;
    }

    return result;
}

/// Get min value for each pair of components
export fn Vector4Min(v1: Vector4, v2: Vector4) callconv(.c) Vector4 {
    var result = Vector4{ .x = 0, .y = 0, .z = 0, .w = 0 };

    result.x = fminf(v1.x, v2.x);
    result.y = fminf(v1.y, v2.y);
    result.z = fminf(v1.z, v2.z);
    result.w = fminf(v1.w, v2.w);

    return result;
}

/// Get max value for each pair of components
export fn Vector4Max(v1: Vector4, v2: Vector4) callconv(.c) Vector4 {
    var result = Vector4{ .x = 0, .y = 0, .z = 0, .w = 0 };

    result.x = fmaxf(v1.x, v2.x);
    result.y = fmaxf(v1.y, v2.y);
    result.z = fmaxf(v1.z, v2.z);
    result.w = fmaxf(v1.w, v2.w);

    return result;
}

/// Calculate linear interpolation between two vectors
export fn Vector4Lerp(v1: Vector4, v2: Vector4, amount: f32) callconv(.c) Vector4 {
    var result = Vector4{ .x = 0, .y = 0, .z = 0, .w = 0 };

    result.x = v1.x + amount * (v2.x - v1.x);
    result.y = v1.y + amount * (v2.y - v1.y);
    result.z = v1.z + amount * (v2.z - v1.z);
    result.w = v1.w + amount * (v2.w - v1.w);

    return result;
}

/// Move Vector towards target
export fn Vector4MoveTowards(v: Vector4, target: Vector4, maxDistance: f32) callconv(.c) Vector4 {
    var result = Vector4{ .x = 0, .y = 0, .z = 0, .w = 0 };

    const dx = target.x - v.x;
    const dy = target.y - v.y;
    const dz = target.z - v.z;
    const dw = target.w - v.w;
    const value = (dx * dx) + (dy * dy) + (dz * dz) + (dw * dw);

    if ((value == 0) or ((maxDistance >= 0) and (value <= maxDistance * maxDistance))) return target;

    const dist = sqrtf(value);

    result.x = v.x + dx / dist * maxDistance;
    result.y = v.y + dy / dist * maxDistance;
    result.z = v.z + dz / dist * maxDistance;
    result.w = v.w + dw / dist * maxDistance;

    return result;
}

/// Invert the given vector
export fn Vector4Invert(v: Vector4) callconv(.c) Vector4 {
    const result = Vector4{ .x = 1.0 / v.x, .y = 1.0 / v.y, .z = 1.0 / v.z, .w = 1.0 / v.w };
    return result;
}

/// Check whether two given vectors are almost equal
export fn Vector4Equals(p: Vector4, q: Vector4) callconv(.c) c_int {
    const result: c_int = @intFromBool(((fabsf(p.x - q.x)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.x), fabsf(q.x))))) and
        ((fabsf(p.y - q.y)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.y), fabsf(q.y))))) and
        ((fabsf(p.z - q.z)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.z), fabsf(q.z))))) and
        ((fabsf(p.w - q.w)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.w), fabsf(q.w))))));
    return result;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Matrix math
//----------------------------------------------------------------------------------

/// Compute matrix determinant
export fn MatrixDeterminant(mat: Matrix) callconv(.c) f32 {
    var result: f32 = 0.0;

    // Cache the matrix values (speed optimization)
    const m0 = mat.m0;
    const m1 = mat.m1;
    const m2 = mat.m2;
    const m3 = mat.m3;
    const m4 = mat.m4;
    const m5 = mat.m5;
    const m6 = mat.m6;
    const m7 = mat.m7;
    const m8 = mat.m8;
    const m9 = mat.m9;
    const m10 = mat.m10;
    const m11 = mat.m11;
    const m12 = mat.m12;
    const m13 = mat.m13;
    const m14 = mat.m14;
    const m15 = mat.m15;

    result = (m0 * ((m5 * (m10 * m15 - m11 * m14) - m9 * (m6 * m15 - m7 * m14) + m13 * (m6 * m11 - m7 * m10))) -
        m4 * ((m1 * (m10 * m15 - m11 * m14) - m9 * (m2 * m15 - m3 * m14) + m13 * (m2 * m11 - m3 * m10))) +
        m8 * ((m1 * (m6 * m15 - m7 * m14) - m5 * (m2 * m15 - m3 * m14) + m13 * (m2 * m7 - m3 * m6))) -
        m12 * ((m1 * (m6 * m11 - m7 * m10) - m5 * (m2 * m11 - m3 * m10) + m9 * (m2 * m7 - m3 * m6))));

    return result;
}

/// Get the trace of the matrix (sum of the values along the diagonal)
export fn MatrixTrace(mat: Matrix) callconv(.c) f32 {
    const result = (mat.m0 + mat.m5 + mat.m10 + mat.m15);

    return result;
}

/// Transposes provided matrix
export fn MatrixTranspose(mat: Matrix) callconv(.c) Matrix {
    var result = std.mem.zeroes(Matrix);

    result.m0 = mat.m0;
    result.m1 = mat.m4;
    result.m2 = mat.m8;
    result.m3 = mat.m12;
    result.m4 = mat.m1;
    result.m5 = mat.m5;
    result.m6 = mat.m9;
    result.m7 = mat.m13;
    result.m8 = mat.m2;
    result.m9 = mat.m6;
    result.m10 = mat.m10;
    result.m11 = mat.m14;
    result.m12 = mat.m3;
    result.m13 = mat.m7;
    result.m14 = mat.m11;
    result.m15 = mat.m15;

    return result;
}

/// Invert provided matrix
export fn MatrixInvert(mat: Matrix) callconv(.c) Matrix {
    var result = std.mem.zeroes(Matrix);

    // Cache the matrix values (speed optimization)
    const a00 = mat.m0;
    const a01 = mat.m1;
    const a02 = mat.m2;
    const a03 = mat.m3;
    const a10 = mat.m4;
    const a11 = mat.m5;
    const a12 = mat.m6;
    const a13 = mat.m7;
    const a20 = mat.m8;
    const a21 = mat.m9;
    const a22 = mat.m10;
    const a23 = mat.m11;
    const a30 = mat.m12;
    const a31 = mat.m13;
    const a32 = mat.m14;
    const a33 = mat.m15;

    const b00 = a00 * a11 - a01 * a10;
    const b01 = a00 * a12 - a02 * a10;
    const b02 = a00 * a13 - a03 * a10;
    const b03 = a01 * a12 - a02 * a11;
    const b04 = a01 * a13 - a03 * a11;
    const b05 = a02 * a13 - a03 * a12;
    const b06 = a20 * a31 - a21 * a30;
    const b07 = a20 * a32 - a22 * a30;
    const b08 = a20 * a33 - a23 * a30;
    const b09 = a21 * a32 - a22 * a31;
    const b10 = a21 * a33 - a23 * a31;
    const b11 = a22 * a33 - a23 * a32;

    // Calculate the invert determinant (inlined to avoid double-caching)
    const invDet = 1.0 / (b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06);

    result.m0 = (a11 * b11 - a12 * b10 + a13 * b09) * invDet;
    result.m1 = (-a01 * b11 + a02 * b10 - a03 * b09) * invDet;
    result.m2 = (a31 * b05 - a32 * b04 + a33 * b03) * invDet;
    result.m3 = (-a21 * b05 + a22 * b04 - a23 * b03) * invDet;
    result.m4 = (-a10 * b11 + a12 * b08 - a13 * b07) * invDet;
    result.m5 = (a00 * b11 - a02 * b08 + a03 * b07) * invDet;
    result.m6 = (-a30 * b05 + a32 * b02 - a33 * b01) * invDet;
    result.m7 = (a20 * b05 - a22 * b02 + a23 * b01) * invDet;
    result.m8 = (a10 * b10 - a11 * b08 + a13 * b06) * invDet;
    result.m9 = (-a00 * b10 + a01 * b08 - a03 * b06) * invDet;
    result.m10 = (a30 * b04 - a31 * b02 + a33 * b00) * invDet;
    result.m11 = (-a20 * b04 + a21 * b02 - a23 * b00) * invDet;
    result.m12 = (-a10 * b09 + a11 * b07 - a12 * b06) * invDet;
    result.m13 = (a00 * b09 - a01 * b07 + a02 * b06) * invDet;
    result.m14 = (-a30 * b03 + a31 * b01 - a32 * b00) * invDet;
    result.m15 = (a20 * b03 - a21 * b01 + a22 * b00) * invDet;

    return result;
}

/// Get identity matrix
export fn MatrixIdentity() callconv(.c) Matrix {
    const result = Matrix{
        .m0 = 1.0,
        .m4 = 0.0,
        .m8 = 0.0,
        .m12 = 0.0,
        .m1 = 0.0,
        .m5 = 1.0,
        .m9 = 0.0,
        .m13 = 0.0,
        .m2 = 0.0,
        .m6 = 0.0,
        .m10 = 1.0,
        .m14 = 0.0,
        .m3 = 0.0,
        .m7 = 0.0,
        .m11 = 0.0,
        .m15 = 1.0,
    };

    return result;
}

/// Add two matrices
export fn MatrixAdd(left: Matrix, right: Matrix) callconv(.c) Matrix {
    var result = std.mem.zeroes(Matrix);

    result.m0 = left.m0 + right.m0;
    result.m1 = left.m1 + right.m1;
    result.m2 = left.m2 + right.m2;
    result.m3 = left.m3 + right.m3;
    result.m4 = left.m4 + right.m4;
    result.m5 = left.m5 + right.m5;
    result.m6 = left.m6 + right.m6;
    result.m7 = left.m7 + right.m7;
    result.m8 = left.m8 + right.m8;
    result.m9 = left.m9 + right.m9;
    result.m10 = left.m10 + right.m10;
    result.m11 = left.m11 + right.m11;
    result.m12 = left.m12 + right.m12;
    result.m13 = left.m13 + right.m13;
    result.m14 = left.m14 + right.m14;
    result.m15 = left.m15 + right.m15;

    return result;
}

/// Subtract two matrices (left - right)
export fn MatrixSubtract(left: Matrix, right: Matrix) callconv(.c) Matrix {
    var result = std.mem.zeroes(Matrix);

    result.m0 = left.m0 - right.m0;
    result.m1 = left.m1 - right.m1;
    result.m2 = left.m2 - right.m2;
    result.m3 = left.m3 - right.m3;
    result.m4 = left.m4 - right.m4;
    result.m5 = left.m5 - right.m5;
    result.m6 = left.m6 - right.m6;
    result.m7 = left.m7 - right.m7;
    result.m8 = left.m8 - right.m8;
    result.m9 = left.m9 - right.m9;
    result.m10 = left.m10 - right.m10;
    result.m11 = left.m11 - right.m11;
    result.m12 = left.m12 - right.m12;
    result.m13 = left.m13 - right.m13;
    result.m14 = left.m14 - right.m14;
    result.m15 = left.m15 - right.m15;

    return result;
}

/// Get two matrix multiplication (order matters!)
export fn MatrixMultiply(left: Matrix, right: Matrix) callconv(.c) Matrix {
    var result = std.mem.zeroes(Matrix);

    result.m0 = left.m0 * right.m0 + left.m1 * right.m4 + left.m2 * right.m8 + left.m3 * right.m12;
    result.m1 = left.m0 * right.m1 + left.m1 * right.m5 + left.m2 * right.m9 + left.m3 * right.m13;
    result.m2 = left.m0 * right.m2 + left.m1 * right.m6 + left.m2 * right.m10 + left.m3 * right.m14;
    result.m3 = left.m0 * right.m3 + left.m1 * right.m7 + left.m2 * right.m11 + left.m3 * right.m15;
    result.m4 = left.m4 * right.m0 + left.m5 * right.m4 + left.m6 * right.m8 + left.m7 * right.m12;
    result.m5 = left.m4 * right.m1 + left.m5 * right.m5 + left.m6 * right.m9 + left.m7 * right.m13;
    result.m6 = left.m4 * right.m2 + left.m5 * right.m6 + left.m6 * right.m10 + left.m7 * right.m14;
    result.m7 = left.m4 * right.m3 + left.m5 * right.m7 + left.m6 * right.m11 + left.m7 * right.m15;
    result.m8 = left.m8 * right.m0 + left.m9 * right.m4 + left.m10 * right.m8 + left.m11 * right.m12;
    result.m9 = left.m8 * right.m1 + left.m9 * right.m5 + left.m10 * right.m9 + left.m11 * right.m13;
    result.m10 = left.m8 * right.m2 + left.m9 * right.m6 + left.m10 * right.m10 + left.m11 * right.m14;
    result.m11 = left.m8 * right.m3 + left.m9 * right.m7 + left.m10 * right.m11 + left.m11 * right.m15;
    result.m12 = left.m12 * right.m0 + left.m13 * right.m4 + left.m14 * right.m8 + left.m15 * right.m12;
    result.m13 = left.m12 * right.m1 + left.m13 * right.m5 + left.m14 * right.m9 + left.m15 * right.m13;
    result.m14 = left.m12 * right.m2 + left.m13 * right.m6 + left.m14 * right.m10 + left.m15 * right.m14;
    result.m15 = left.m12 * right.m3 + left.m13 * right.m7 + left.m14 * right.m11 + left.m15 * right.m15;

    return result;
}

/// Multiply matrix components by value
export fn MatrixMultiplyValue(left: Matrix, value: f32) callconv(.c) Matrix {
    const result = Matrix{
        .m0 = left.m0 * value,
        .m4 = left.m4 * value,
        .m8 = left.m8 * value,
        .m12 = left.m12 * value,
        .m1 = left.m1 * value,
        .m5 = left.m5 * value,
        .m9 = left.m9 * value,
        .m13 = left.m13 * value,
        .m2 = left.m2 * value,
        .m6 = left.m6 * value,
        .m10 = left.m10 * value,
        .m14 = left.m14 * value,
        .m3 = left.m3 * value,
        .m7 = left.m7 * value,
        .m11 = left.m11 * value,
        .m15 = left.m15 * value,
    };

    return result;
}

/// Get translation matrix
export fn MatrixTranslate(x: f32, y: f32, z: f32) callconv(.c) Matrix {
    const result = Matrix{
        .m0 = 1.0,
        .m4 = 0.0,
        .m8 = 0.0,
        .m12 = x,
        .m1 = 0.0,
        .m5 = 1.0,
        .m9 = 0.0,
        .m13 = y,
        .m2 = 0.0,
        .m6 = 0.0,
        .m10 = 1.0,
        .m14 = z,
        .m3 = 0.0,
        .m7 = 0.0,
        .m11 = 0.0,
        .m15 = 1.0,
    };

    return result;
}

/// Create rotation matrix from axis and angle (radians)
export fn MatrixRotate(axis: Vector3, angle: f32) callconv(.c) Matrix {
    var result = std.mem.zeroes(Matrix);

    var x = axis.x;
    var y = axis.y;
    var z = axis.z;

    const lengthSquared = x * x + y * y + z * z;

    if ((lengthSquared != 1.0) and (lengthSquared != 0.0)) {
        const ilength = 1.0 / sqrtf(lengthSquared);
        x *= ilength;
        y *= ilength;
        z *= ilength;
    }

    const sinres = sinf(angle);
    const cosres = cosf(angle);
    const t = 1.0 - cosres;

    result.m0 = x * x * t + cosres;
    result.m1 = y * x * t + z * sinres;
    result.m2 = z * x * t - y * sinres;
    result.m3 = 0.0;

    result.m4 = x * y * t - z * sinres;
    result.m5 = y * y * t + cosres;
    result.m6 = z * y * t + x * sinres;
    result.m7 = 0.0;

    result.m8 = x * z * t + y * sinres;
    result.m9 = y * z * t - x * sinres;
    result.m10 = z * z * t + cosres;
    result.m11 = 0.0;

    result.m12 = 0.0;
    result.m13 = 0.0;
    result.m14 = 0.0;
    result.m15 = 1.0;

    return result;
}

/// Get x-rotation matrix (angle in radians)
export fn MatrixRotateX(angle: f32) callconv(.c) Matrix {
    var result = MatrixIdentity();

    const cosres = cosf(angle);
    const sinres = sinf(angle);

    result.m5 = cosres;
    result.m6 = sinres;
    result.m9 = -sinres;
    result.m10 = cosres;

    return result;
}

/// Get y-rotation matrix (angle in radians)
export fn MatrixRotateY(angle: f32) callconv(.c) Matrix {
    var result = MatrixIdentity();

    const cosres = cosf(angle);
    const sinres = sinf(angle);

    result.m0 = cosres;
    result.m2 = -sinres;
    result.m8 = sinres;
    result.m10 = cosres;

    return result;
}

/// Get z-rotation matrix (angle in radians)
export fn MatrixRotateZ(angle: f32) callconv(.c) Matrix {
    var result = MatrixIdentity();

    const cosres = cosf(angle);
    const sinres = sinf(angle);

    result.m0 = cosres;
    result.m1 = sinres;
    result.m4 = -sinres;
    result.m5 = cosres;

    return result;
}

/// Get xyz-rotation matrix (angle in radians)
export fn MatrixRotateXYZ(angle: Vector3) callconv(.c) Matrix {
    var result = MatrixIdentity();

    const cosz = cosf(-angle.z);
    const sinz = sinf(-angle.z);
    const cosy = cosf(-angle.y);
    const siny = sinf(-angle.y);
    const cosx = cosf(-angle.x);
    const sinx = sinf(-angle.x);

    result.m0 = cosz * cosy;
    result.m1 = (cosz * siny * sinx) - (sinz * cosx);
    result.m2 = (cosz * siny * cosx) + (sinz * sinx);

    result.m4 = sinz * cosy;
    result.m5 = (sinz * siny * sinx) + (cosz * cosx);
    result.m6 = (sinz * siny * cosx) - (cosz * sinx);

    result.m8 = -siny;
    result.m9 = cosy * sinx;
    result.m10 = cosy * cosx;

    return result;
}

/// Get zyx-rotation matrix (angle in radians)
export fn MatrixRotateZYX(angle: Vector3) callconv(.c) Matrix {
    var result = std.mem.zeroes(Matrix);

    const cz = cosf(angle.z);
    const sz = sinf(angle.z);
    const cy = cosf(angle.y);
    const sy = sinf(angle.y);
    const cx = cosf(angle.x);
    const sx = sinf(angle.x);

    result.m0 = cz * cy;
    result.m4 = cz * sy * sx - cx * sz;
    result.m8 = sz * sx + cz * cx * sy;
    result.m12 = 0;

    result.m1 = cy * sz;
    result.m5 = cz * cx + sz * sy * sx;
    result.m9 = cx * sz * sy - cz * sx;
    result.m13 = 0;

    result.m2 = -sy;
    result.m6 = cy * sx;
    result.m10 = cy * cx;
    result.m14 = 0;

    result.m3 = 0;
    result.m7 = 0;
    result.m11 = 0;
    result.m15 = 1;

    return result;
}

/// Get scaling matrix
export fn MatrixScale(x: f32, y: f32, z: f32) callconv(.c) Matrix {
    const result = Matrix{
        .m0 = x,
        .m4 = 0.0,
        .m8 = 0.0,
        .m12 = 0.0,
        .m1 = 0.0,
        .m5 = y,
        .m9 = 0.0,
        .m13 = 0.0,
        .m2 = 0.0,
        .m6 = 0.0,
        .m10 = z,
        .m14 = 0.0,
        .m3 = 0.0,
        .m7 = 0.0,
        .m11 = 0.0,
        .m15 = 1.0,
    };

    return result;
}

/// Get perspective projection matrix
export fn MatrixFrustum(left: f64, right: f64, bottom: f64, top: f64, nearPlane: f64, farPlane: f64) callconv(.c) Matrix {
    var result = std.mem.zeroes(Matrix);

    const rl: f32 = @floatCast(right - left);
    const tb: f32 = @floatCast(top - bottom);
    const fn_: f32 = @floatCast(farPlane - nearPlane);

    result.m0 = (@as(f32, @floatCast(nearPlane)) * 2.0) / rl;
    result.m1 = 0.0;
    result.m2 = 0.0;
    result.m3 = 0.0;

    result.m4 = 0.0;
    result.m5 = (@as(f32, @floatCast(nearPlane)) * 2.0) / tb;
    result.m6 = 0.0;
    result.m7 = 0.0;

    result.m8 = (@as(f32, @floatCast(right)) + @as(f32, @floatCast(left))) / rl;
    result.m9 = (@as(f32, @floatCast(top)) + @as(f32, @floatCast(bottom))) / tb;
    result.m10 = -(@as(f32, @floatCast(farPlane)) + @as(f32, @floatCast(nearPlane))) / fn_;
    result.m11 = -1.0;

    result.m12 = 0.0;
    result.m13 = 0.0;
    result.m14 = -(@as(f32, @floatCast(farPlane)) * @as(f32, @floatCast(nearPlane)) * 2.0) / fn_;
    result.m15 = 0.0;

    return result;
}

/// Get perspective projection matrix (fovY in radians)
export fn MatrixPerspective(fovY: f64, aspect: f64, nearPlane: f64, farPlane: f64) callconv(.c) Matrix {
    var result = std.mem.zeroes(Matrix);

    const top = nearPlane * tan(fovY * 0.5);
    const bottom = -top;
    const right = top * aspect;
    const left = -right;

    // MatrixFrustum(-right, right, -top, top, near, far);
    const rl: f32 = @floatCast(right - left);
    const tb: f32 = @floatCast(top - bottom);
    const fn_: f32 = @floatCast(farPlane - nearPlane);

    result.m0 = (@as(f32, @floatCast(nearPlane)) * 2.0) / rl;
    result.m5 = (@as(f32, @floatCast(nearPlane)) * 2.0) / tb;
    result.m8 = (@as(f32, @floatCast(right)) + @as(f32, @floatCast(left))) / rl;
    result.m9 = (@as(f32, @floatCast(top)) + @as(f32, @floatCast(bottom))) / tb;
    result.m10 = -(@as(f32, @floatCast(farPlane)) + @as(f32, @floatCast(nearPlane))) / fn_;
    result.m11 = -1.0;
    result.m14 = -(@as(f32, @floatCast(farPlane)) * @as(f32, @floatCast(nearPlane)) * 2.0) / fn_;

    return result;
}

/// Get orthographic projection matrix
export fn MatrixOrtho(left: f64, right: f64, bottom: f64, top: f64, nearPlane: f64, farPlane: f64) callconv(.c) Matrix {
    var result = std.mem.zeroes(Matrix);

    const rl: f32 = @floatCast(right - left);
    const tb: f32 = @floatCast(top - bottom);
    const fn_: f32 = @floatCast(farPlane - nearPlane);

    result.m0 = 2.0 / rl;
    result.m1 = 0.0;
    result.m2 = 0.0;
    result.m3 = 0.0;
    result.m4 = 0.0;
    result.m5 = 2.0 / tb;
    result.m6 = 0.0;
    result.m7 = 0.0;
    result.m8 = 0.0;
    result.m9 = 0.0;
    result.m10 = -2.0 / fn_;
    result.m11 = 0.0;
    result.m12 = -(@as(f32, @floatCast(left)) + @as(f32, @floatCast(right))) / rl;
    result.m13 = -(@as(f32, @floatCast(top)) + @as(f32, @floatCast(bottom))) / tb;
    result.m14 = -(@as(f32, @floatCast(farPlane)) + @as(f32, @floatCast(nearPlane))) / fn_;
    result.m15 = 1.0;

    return result;
}

/// Get camera look-at matrix (view matrix)
export fn MatrixLookAt(eye: Vector3, target: Vector3, up: Vector3) callconv(.c) Matrix {
    var result = std.mem.zeroes(Matrix);

    var length: f32 = 0.0;
    var ilength: f32 = 0.0;

    // Vector3Subtract(eye, target)
    var vz = Vector3{ .x = eye.x - target.x, .y = eye.y - target.y, .z = eye.z - target.z };

    // Vector3Normalize(vz)
    var v = vz;
    length = sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
    if (length == 0.0) length = 1.0;
    ilength = 1.0 / length;
    vz.x *= ilength;
    vz.y *= ilength;
    vz.z *= ilength;

    // Vector3CrossProduct(up, vz)
    var vx = Vector3{ .x = up.y * vz.z - up.z * vz.y, .y = up.z * vz.x - up.x * vz.z, .z = up.x * vz.y - up.y * vz.x };

    // Vector3Normalize(x)
    v = vx;
    length = sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
    if (length == 0.0) length = 1.0;
    ilength = 1.0 / length;
    vx.x *= ilength;
    vx.y *= ilength;
    vx.z *= ilength;

    // Vector3CrossProduct(vz, vx)
    const vy = Vector3{ .x = vz.y * vx.z - vz.z * vx.y, .y = vz.z * vx.x - vz.x * vx.z, .z = vz.x * vx.y - vz.y * vx.x };

    result.m0 = vx.x;
    result.m1 = vy.x;
    result.m2 = vz.x;
    result.m3 = 0.0;
    result.m4 = vx.y;
    result.m5 = vy.y;
    result.m6 = vz.y;
    result.m7 = 0.0;
    result.m8 = vx.z;
    result.m9 = vy.z;
    result.m10 = vz.z;
    result.m11 = 0.0;
    result.m12 = -(vx.x * eye.x + vx.y * eye.y + vx.z * eye.z); // Vector3DotProduct(vx, eye)
    result.m13 = -(vy.x * eye.x + vy.y * eye.y + vy.z * eye.z); // Vector3DotProduct(vy, eye)
    result.m14 = -(vz.x * eye.x + vz.y * eye.y + vz.z * eye.z); // Vector3DotProduct(vz, eye)
    result.m15 = 1.0;

    return result;
}

/// Get float array of matrix data
export fn MatrixToFloatV(mat: Matrix) callconv(.c) float16 {
    var result = std.mem.zeroes(float16);

    result.v[0] = mat.m0;
    result.v[1] = mat.m1;
    result.v[2] = mat.m2;
    result.v[3] = mat.m3;
    result.v[4] = mat.m4;
    result.v[5] = mat.m5;
    result.v[6] = mat.m6;
    result.v[7] = mat.m7;
    result.v[8] = mat.m8;
    result.v[9] = mat.m9;
    result.v[10] = mat.m10;
    result.v[11] = mat.m11;
    result.v[12] = mat.m12;
    result.v[13] = mat.m13;
    result.v[14] = mat.m14;
    result.v[15] = mat.m15;

    return result;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Quaternion math
//----------------------------------------------------------------------------------

/// Add two quaternions
export fn QuaternionAdd(q1: Quaternion, q2: Quaternion) callconv(.c) Quaternion {
    const result = Quaternion{ .x = q1.x + q2.x, .y = q1.y + q2.y, .z = q1.z + q2.z, .w = q1.w + q2.w };

    return result;
}

/// Add quaternion and float value
export fn QuaternionAddValue(q: Quaternion, add: f32) callconv(.c) Quaternion {
    const result = Quaternion{ .x = q.x + add, .y = q.y + add, .z = q.z + add, .w = q.w + add };

    return result;
}

/// Subtract two quaternions
export fn QuaternionSubtract(q1: Quaternion, q2: Quaternion) callconv(.c) Quaternion {
    const result = Quaternion{ .x = q1.x - q2.x, .y = q1.y - q2.y, .z = q1.z - q2.z, .w = q1.w - q2.w };

    return result;
}

/// Subtract quaternion and float value
export fn QuaternionSubtractValue(q: Quaternion, sub: f32) callconv(.c) Quaternion {
    const result = Quaternion{ .x = q.x - sub, .y = q.y - sub, .z = q.z - sub, .w = q.w - sub };

    return result;
}

/// Get identity quaternion
export fn QuaternionIdentity() callconv(.c) Quaternion {
    const result = Quaternion{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 };

    return result;
}

/// Computes the length of a quaternion
export fn QuaternionLength(q: Quaternion) callconv(.c) f32 {
    const result = sqrtf(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);

    return result;
}

/// Normalize provided quaternion
export fn QuaternionNormalize(q: Quaternion) callconv(.c) Quaternion {
    var result = std.mem.zeroes(Quaternion);

    var length = sqrtf(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
    if (length == 0.0) length = 1.0;
    const ilength = 1.0 / length;

    result.x = q.x * ilength;
    result.y = q.y * ilength;
    result.z = q.z * ilength;
    result.w = q.w * ilength;

    return result;
}

/// Invert provided quaternion
export fn QuaternionInvert(q: Quaternion) callconv(.c) Quaternion {
    var result = q;

    const lengthSq = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w;

    if (lengthSq != 0.0) {
        const invLength = 1.0 / lengthSq;

        result.x *= -invLength;
        result.y *= -invLength;
        result.z *= -invLength;
        result.w *= invLength;
    }

    return result;
}

/// Calculate two quaternion multiplication
export fn QuaternionMultiply(q1: Quaternion, q2: Quaternion) callconv(.c) Quaternion {
    var result = std.mem.zeroes(Quaternion);

    const qax = q1.x;
    const qay = q1.y;
    const qaz = q1.z;
    const qaw = q1.w;
    const qbx = q2.x;
    const qby = q2.y;
    const qbz = q2.z;
    const qbw = q2.w;

    result.x = qax * qbw + qaw * qbx + qay * qbz - qaz * qby;
    result.y = qay * qbw + qaw * qby + qaz * qbx - qax * qbz;
    result.z = qaz * qbw + qaw * qbz + qax * qby - qay * qbx;
    result.w = qaw * qbw - qax * qbx - qay * qby - qaz * qbz;

    return result;
}

/// Scale quaternion by float value
export fn QuaternionScale(q: Quaternion, mul: f32) callconv(.c) Quaternion {
    var result = std.mem.zeroes(Quaternion);

    result.x = q.x * mul;
    result.y = q.y * mul;
    result.z = q.z * mul;
    result.w = q.w * mul;

    return result;
}

/// Divide two quaternions
export fn QuaternionDivide(q1: Quaternion, q2: Quaternion) callconv(.c) Quaternion {
    const result = Quaternion{ .x = q1.x / q2.x, .y = q1.y / q2.y, .z = q1.z / q2.z, .w = q1.w / q2.w };

    return result;
}

/// Calculate linear interpolation between two quaternions
export fn QuaternionLerp(q1: Quaternion, q2: Quaternion, amount: f32) callconv(.c) Quaternion {
    var result = std.mem.zeroes(Quaternion);

    result.x = q1.x + amount * (q2.x - q1.x);
    result.y = q1.y + amount * (q2.y - q1.y);
    result.z = q1.z + amount * (q2.z - q1.z);
    result.w = q1.w + amount * (q2.w - q1.w);

    return result;
}

/// Calculate slerp-optimized interpolation between two quaternions
export fn QuaternionNlerp(q1: Quaternion, q2: Quaternion, amount: f32) callconv(.c) Quaternion {
    var result = std.mem.zeroes(Quaternion);

    // QuaternionLerp(q1, q2, amount)
    result.x = q1.x + amount * (q2.x - q1.x);
    result.y = q1.y + amount * (q2.y - q1.y);
    result.z = q1.z + amount * (q2.z - q1.z);
    result.w = q1.w + amount * (q2.w - q1.w);

    // QuaternionNormalize(q);
    const q = result;
    var length = sqrtf(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
    if (length == 0.0) length = 1.0;
    const ilength = 1.0 / length;

    result.x = q.x * ilength;
    result.y = q.y * ilength;
    result.z = q.z * ilength;
    result.w = q.w * ilength;

    return result;
}

/// Calculates spherical linear interpolation between two quaternions
export fn QuaternionSlerp(q1: Quaternion, q2_in: Quaternion, amount: f32) callconv(.c) Quaternion {
    var q2 = q2_in;
    var result = std.mem.zeroes(Quaternion);

    var cosHalfTheta = q1.x * q2.x + q1.y * q2.y + q1.z * q2.z + q1.w * q2.w;

    if (cosHalfTheta < 0) {
        q2.x = -q2.x;
        q2.y = -q2.y;
        q2.z = -q2.z;
        q2.w = -q2.w;
        cosHalfTheta = -cosHalfTheta;
    }

    if (fabsf(cosHalfTheta) >= 1.0) {
        result = q1;
    } else if (cosHalfTheta > 0.95) {
        result = QuaternionNlerp(q1, q2, amount);
    } else {
        const halfTheta = acosf(cosHalfTheta);
        const sinHalfTheta = sqrtf(1.0 - cosHalfTheta * cosHalfTheta);

        if (fabsf(sinHalfTheta) < EPSILON) {
            result.x = (q1.x * 0.5 + q2.x * 0.5);
            result.y = (q1.y * 0.5 + q2.y * 0.5);
            result.z = (q1.z * 0.5 + q2.z * 0.5);
            result.w = (q1.w * 0.5 + q2.w * 0.5);
        } else {
            const ratioA = sinf((1 - amount) * halfTheta) / sinHalfTheta;
            const ratioB = sinf(amount * halfTheta) / sinHalfTheta;

            result.x = (q1.x * ratioA + q2.x * ratioB);
            result.y = (q1.y * ratioA + q2.y * ratioB);
            result.z = (q1.z * ratioA + q2.z * ratioB);
            result.w = (q1.w * ratioA + q2.w * ratioB);
        }
    }

    return result;
}

/// Calculate quaternion cubic spline interpolation using Cubic Hermite Spline algorithm
export fn QuaternionCubicHermiteSpline(q1: Quaternion, outTangent1: Quaternion, q2: Quaternion, inTangent2: Quaternion, t: f32) callconv(.c) Quaternion {
    const t2 = t * t;
    const t3 = t2 * t;
    const h00 = 2 * t3 - 3 * t2 + 1;
    const h10 = t3 - 2 * t2 + t;
    const h01 = -2 * t3 + 3 * t2;
    const h11 = t3 - t2;

    const p0 = QuaternionScale(q1, h00);
    const m0 = QuaternionScale(outTangent1, h10);
    const p1 = QuaternionScale(q2, h01);
    const m1 = QuaternionScale(inTangent2, h11);

    var result = std.mem.zeroes(Quaternion);

    result = QuaternionAdd(p0, m0);
    result = QuaternionAdd(result, p1);
    result = QuaternionAdd(result, m1);
    result = QuaternionNormalize(result);

    return result;
}

/// Calculate quaternion based on the rotation from one vector to another
export fn QuaternionFromVector3ToVector3(from: Vector3, to: Vector3) callconv(.c) Quaternion {
    var result = std.mem.zeroes(Quaternion);

    const cos2Theta = (from.x * to.x + from.y * to.y + from.z * to.z); // Vector3DotProduct(from, to)
    const cross = Vector3{ .x = from.y * to.z - from.z * to.y, .y = from.z * to.x - from.x * to.z, .z = from.x * to.y - from.y * to.x }; // Vector3CrossProduct(from, to)

    const lengths = sqrtf(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z + cos2Theta * cos2Theta); // |from|*|to|

    result.x = cross.x;
    result.y = cross.y;
    result.z = cross.z;
    result.w = lengths + cos2Theta;

    // Opposite vectors: cross product is zero, rotate 180 degrees around any axis perpendicular to 'from'
    if (lengths > 0.0 and result.w <= lengths * EPSILON) {
        if (fabsf(from.x) > fabsf(from.z)) {
            result.x = -from.y;
            result.y = from.x;
            result.z = 0.0;
        } else {
            result.x = 0.0;
            result.y = -from.z;
            result.z = from.y;
        }

        result.w = 0.0;
    }

    // QuaternionNormalize(q);
    const q = result;
    var length = sqrtf(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
    if (length == 0.0) length = 1.0;
    const ilength = 1.0 / length;

    result.x = q.x * ilength;
    result.y = q.y * ilength;
    result.z = q.z * ilength;
    result.w = q.w * ilength;

    return result;
}

/// Get a quaternion for a given rotation matrix
export fn QuaternionFromMatrix(mat: Matrix) callconv(.c) Quaternion {
    var result = std.mem.zeroes(Quaternion);

    const fourWSquaredMinus1 = mat.m0 + mat.m5 + mat.m10;
    const fourXSquaredMinus1 = mat.m0 - mat.m5 - mat.m10;
    const fourYSquaredMinus1 = mat.m5 - mat.m0 - mat.m10;
    const fourZSquaredMinus1 = mat.m10 - mat.m0 - mat.m5;

    var biggestIndex: c_int = 0;
    var fourBiggestSquaredMinus1 = fourWSquaredMinus1;
    if (fourXSquaredMinus1 > fourBiggestSquaredMinus1) {
        fourBiggestSquaredMinus1 = fourXSquaredMinus1;
        biggestIndex = 1;
    }

    if (fourYSquaredMinus1 > fourBiggestSquaredMinus1) {
        fourBiggestSquaredMinus1 = fourYSquaredMinus1;
        biggestIndex = 2;
    }

    if (fourZSquaredMinus1 > fourBiggestSquaredMinus1) {
        fourBiggestSquaredMinus1 = fourZSquaredMinus1;
        biggestIndex = 3;
    }

    const biggestVal = sqrtf(fourBiggestSquaredMinus1 + 1.0) * 0.5;
    const mult = 0.25 / biggestVal;

    switch (biggestIndex) {
        0 => {
            result.w = biggestVal;
            result.x = (mat.m6 - mat.m9) * mult;
            result.y = (mat.m8 - mat.m2) * mult;
            result.z = (mat.m1 - mat.m4) * mult;
        },
        1 => {
            result.x = biggestVal;
            result.w = (mat.m6 - mat.m9) * mult;
            result.y = (mat.m1 + mat.m4) * mult;
            result.z = (mat.m8 + mat.m2) * mult;
        },
        2 => {
            result.y = biggestVal;
            result.w = (mat.m8 - mat.m2) * mult;
            result.x = (mat.m1 + mat.m4) * mult;
            result.z = (mat.m6 + mat.m9) * mult;
        },
        3 => {
            result.z = biggestVal;
            result.w = (mat.m1 - mat.m4) * mult;
            result.x = (mat.m8 + mat.m2) * mult;
            result.y = (mat.m6 + mat.m9) * mult;
        },
        else => {},
    }

    return result;
}

/// Get a matrix for a given quaternion
export fn QuaternionToMatrix(q: Quaternion) callconv(.c) Matrix {
    var result = MatrixIdentity();

    const a2 = q.x * q.x;
    const b2 = q.y * q.y;
    const c2 = q.z * q.z;
    const ac = q.x * q.z;
    const ab = q.x * q.y;
    const bc = q.y * q.z;
    const ad = q.w * q.x;
    const bd = q.w * q.y;
    const cd = q.w * q.z;

    result.m0 = 1 - 2 * (b2 + c2);
    result.m1 = 2 * (ab + cd);
    result.m2 = 2 * (ac - bd);

    result.m4 = 2 * (ab - cd);
    result.m5 = 1 - 2 * (a2 + c2);
    result.m6 = 2 * (bc + ad);

    result.m8 = 2 * (ac + bd);
    result.m9 = 2 * (bc - ad);
    result.m10 = 1 - 2 * (a2 + b2);

    return result;
}

/// Get rotation quaternion for an angle and axis (angle in radians)
export fn QuaternionFromAxisAngle(axis_in: Vector3, angle_in: f32) callconv(.c) Quaternion {
    var axis = axis_in;
    var angle = angle_in;
    var result = Quaternion{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 };

    var length = sqrtf(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z);

    if (length != 0.0) {
        angle *= 0.5;

        // Vector3Normalize(axis)
        var ilength = 1.0 / length;
        axis.x *= ilength;
        axis.y *= ilength;
        axis.z *= ilength;

        const sinres = sinf(angle);
        const cosres = cosf(angle);

        result.x = axis.x * sinres;
        result.y = axis.y * sinres;
        result.z = axis.z * sinres;
        result.w = cosres;

        // QuaternionNormalize(q);
        const q = result;
        length = sqrtf(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
        if (length == 0.0) length = 1.0;
        ilength = 1.0 / length;
        result.x = q.x * ilength;
        result.y = q.y * ilength;
        result.z = q.z * ilength;
        result.w = q.w * ilength;
    }

    return result;
}

/// Get the rotation angle and axis for a given quaternion
export fn QuaternionToAxisAngle(q_in: Quaternion, outAxis: *Vector3, outAngle: *f32) callconv(.c) void {
    var q = q_in;

    if (fabsf(q.w) > 1.0) {
        // QuaternionNormalize(q);
        var length = sqrtf(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
        if (length == 0.0) length = 1.0;
        const ilength = 1.0 / length;

        q.x = q.x * ilength;
        q.y = q.y * ilength;
        q.z = q.z * ilength;
        q.w = q.w * ilength;
    }

    var resAxis = Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const resAngle = 2.0 * acosf(q.w);
    const den = sqrtf(1.0 - q.w * q.w);

    if (den > EPSILON) {
        resAxis.x = q.x / den;
        resAxis.y = q.y / den;
        resAxis.z = q.z / den;
    } else {
        // This occurs when the angle is zero
        // Not a problem, set an arbitrary normalized axis
        resAxis.x = 1.0;
    }

    outAxis.* = resAxis;
    outAngle.* = resAngle;
}

/// Get the quaternion equivalent to Euler angles (rotation order ZYX)
export fn QuaternionFromEuler(pitch: f32, yaw: f32, roll: f32) callconv(.c) Quaternion {
    var result = std.mem.zeroes(Quaternion);

    const x0 = cosf(pitch * 0.5);
    const x1 = sinf(pitch * 0.5);
    const y0 = cosf(yaw * 0.5);
    const y1 = sinf(yaw * 0.5);
    const z0 = cosf(roll * 0.5);
    const z1 = sinf(roll * 0.5);

    result.x = x1 * y0 * z0 - x0 * y1 * z1;
    result.y = x0 * y1 * z0 + x1 * y0 * z1;
    result.z = x0 * y0 * z1 - x1 * y1 * z0;
    result.w = x0 * y0 * z0 + x1 * y1 * z1;

    return result;
}

/// Get the Euler angles equivalent to quaternion (roll, pitch, yaw) in radians
export fn QuaternionToEuler(q: Quaternion) callconv(.c) Vector3 {
    var result = std.mem.zeroes(Vector3);

    // Roll (x-axis rotation)
    const x0 = 2.0 * (q.w * q.x + q.y * q.z);
    const x1 = 1.0 - 2.0 * (q.x * q.x + q.y * q.y);
    result.x = atan2f(x0, x1);

    // Pitch (y-axis rotation)
    var y0 = 2.0 * (q.w * q.y - q.z * q.x);
    y0 = if (y0 > 1.0) 1.0 else y0;
    y0 = if (y0 < -1.0) -1.0 else y0;
    result.y = asinf(y0);

    // Yaw (z-axis rotation)
    const z0 = 2.0 * (q.w * q.z + q.x * q.y);
    const z1 = 1.0 - 2.0 * (q.y * q.y + q.z * q.z);
    result.z = atan2f(z0, z1);

    return result;
}

/// Transform a quaternion given a transformation matrix
export fn QuaternionTransform(q: Quaternion, mat: Matrix) callconv(.c) Quaternion {
    var result = std.mem.zeroes(Quaternion);

    result.x = mat.m0 * q.x + mat.m4 * q.y + mat.m8 * q.z + mat.m12 * q.w;
    result.y = mat.m1 * q.x + mat.m5 * q.y + mat.m9 * q.z + mat.m13 * q.w;
    result.z = mat.m2 * q.x + mat.m6 * q.y + mat.m10 * q.z + mat.m14 * q.w;
    result.w = mat.m3 * q.x + mat.m7 * q.y + mat.m11 * q.z + mat.m15 * q.w;

    return result;
}

/// Check whether two given quaternions are almost equal
export fn QuaternionEquals(p: Quaternion, q: Quaternion) callconv(.c) c_int {
    const result: c_int = @intFromBool((((fabsf(p.x - q.x)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.x), fabsf(q.x))))) and
        ((fabsf(p.y - q.y)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.y), fabsf(q.y))))) and
        ((fabsf(p.z - q.z)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.z), fabsf(q.z))))) and
        ((fabsf(p.w - q.w)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.w), fabsf(q.w)))))) or
        (((fabsf(p.x + q.x)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.x), fabsf(q.x))))) and
            ((fabsf(p.y + q.y)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.y), fabsf(q.y))))) and
            ((fabsf(p.z + q.z)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.z), fabsf(q.z))))) and
            ((fabsf(p.w + q.w)) <= (EPSILON * fmaxf(1.0, fmaxf(fabsf(p.w), fabsf(q.w)))))));

    return result;
}

/// Compose a transformation matrix from rotational, translational and scaling components
export fn MatrixCompose(translation: Vector3, rotation: Quaternion, scale: Vector3) callconv(.c) Matrix {
    // Initialize vectors
    var right = Vector3{ .x = 1.0, .y = 0.0, .z = 0.0 };
    var up = Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    var forward = Vector3{ .x = 0.0, .y = 0.0, .z = 1.0 };

    // Scale vectors
    right = Vector3Scale(right, scale.x);
    up = Vector3Scale(up, scale.y);
    forward = Vector3Scale(forward, scale.z);

    // Rotate vectors
    right = Vector3RotateByQuaternion(right, rotation);
    up = Vector3RotateByQuaternion(up, rotation);
    forward = Vector3RotateByQuaternion(forward, rotation);

    // Set result matrix output
    const result = Matrix{
        .m0 = right.x,
        .m4 = up.x,
        .m8 = forward.x,
        .m12 = translation.x,
        .m1 = right.y,
        .m5 = up.y,
        .m9 = forward.y,
        .m13 = translation.y,
        .m2 = right.z,
        .m6 = up.z,
        .m10 = forward.z,
        .m14 = translation.z,
        .m3 = 0.0,
        .m7 = 0.0,
        .m11 = 0.0,
        .m15 = 1.0,
    };

    return result;
}

/// Decompose a transformation matrix into its rotational, translational and scaling components and remove shear
export fn MatrixDecompose(mat: Matrix, translation: *Vector3, rotation: *Quaternion, scale: *Vector3) callconv(.c) void {
    const eps: f32 = @floatCast(1e-9);

    // Extract Translation
    translation.x = mat.m12;
    translation.y = mat.m13;
    translation.z = mat.m14;

    // Matrix Columns - Rotation will be extracted into here
    var matColumns = [3]Vector3{
        .{ .x = mat.m0, .y = mat.m1, .z = mat.m2 },
        .{ .x = mat.m4, .y = mat.m5, .z = mat.m6 },
        .{ .x = mat.m8, .y = mat.m9, .z = mat.m10 },
    };

    // Shear Parameters XY, XZ, and YZ (extract and ignored)
    var shear = [_]f32{ 0, 0, 0 };

    // Normalized Scale Parameters
    var scl = Vector3{ .x = 0, .y = 0, .z = 0 };

    // Max-Normalizing helps numerical stability
    var stabilizer = eps;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        stabilizer = fmaxf(stabilizer, fabsf(matColumns[i].x));
        stabilizer = fmaxf(stabilizer, fabsf(matColumns[i].y));
        stabilizer = fmaxf(stabilizer, fabsf(matColumns[i].z));
    }
    matColumns[0] = Vector3Scale(matColumns[0], 1.0 / stabilizer);
    matColumns[1] = Vector3Scale(matColumns[1], 1.0 / stabilizer);
    matColumns[2] = Vector3Scale(matColumns[2], 1.0 / stabilizer);

    // X Scale
    scl.x = Vector3Length(matColumns[0]);
    if (scl.x > eps) matColumns[0] = Vector3Scale(matColumns[0], 1.0 / scl.x);

    // Compute XY shear and make col2 orthogonal
    shear[0] = Vector3DotProduct(matColumns[0], matColumns[1]);
    matColumns[1] = Vector3Subtract(matColumns[1], Vector3Scale(matColumns[0], shear[0]));

    // Y Scale
    scl.y = Vector3Length(matColumns[1]);
    if (scl.y > eps) {
        matColumns[1] = Vector3Scale(matColumns[1], 1.0 / scl.y);
        shear[0] /= scl.y; // Correct XY shear
    }

    // Compute XZ and YZ shears and make col3 orthogonal
    shear[1] = Vector3DotProduct(matColumns[0], matColumns[2]);
    matColumns[2] = Vector3Subtract(matColumns[2], Vector3Scale(matColumns[0], shear[1]));
    shear[2] = Vector3DotProduct(matColumns[1], matColumns[2]);
    matColumns[2] = Vector3Subtract(matColumns[2], Vector3Scale(matColumns[1], shear[2]));

    // Z Scale
    scl.z = Vector3Length(matColumns[2]);
    if (scl.z > eps) {
        matColumns[2] = Vector3Scale(matColumns[2], 1.0 / scl.z);
        shear[1] /= scl.z; // Correct XZ shear
        shear[2] /= scl.z; // Correct YZ shear
    }

    // matColumns are now orthonormal in O(3). Now ensure its in SO(3) by enforcing det = 1
    if (Vector3DotProduct(matColumns[0], Vector3CrossProduct(matColumns[1], matColumns[2])) < 0) {
        scl = Vector3Negate(scl);
        matColumns[0] = Vector3Negate(matColumns[0]);
        matColumns[1] = Vector3Negate(matColumns[1]);
        matColumns[2] = Vector3Negate(matColumns[2]);
    }

    // Set Scale
    scale.* = Vector3Scale(scl, stabilizer);

    // Extract Rotation
    const rotationMatrix = Matrix{
        .m0 = matColumns[0].x,
        .m4 = matColumns[1].x,
        .m8 = matColumns[2].x,
        .m12 = 0,
        .m1 = matColumns[0].y,
        .m5 = matColumns[1].y,
        .m9 = matColumns[2].y,
        .m13 = 0,
        .m2 = matColumns[0].z,
        .m6 = matColumns[1].z,
        .m10 = matColumns[2].z,
        .m14 = 0,
        .m3 = 0,
        .m7 = 0,
        .m11 = 0,
        .m15 = 1,
    };
    rotation.* = QuaternionFromMatrix(rotationMatrix);
}

test "raymath sanity" {
    const expectEqual = std.testing.expectEqual;

    // Vector3Add of {1,2,3}+{4,5,6} == {5,7,9}
    const a = Vector3{ .x = 1, .y = 2, .z = 3 };
    const b = Vector3{ .x = 4, .y = 5, .z = 6 };
    const sum = Vector3Add(a, b);
    try expectEqual(@as(f32, 5), sum.x);
    try expectEqual(@as(f32, 7), sum.y);
    try expectEqual(@as(f32, 9), sum.z);

    // Vector2Length of {3,4} == 5
    try expectEqual(@as(f32, 5), Vector2Length(.{ .x = 3, .y = 4 }));

    // MatrixIdentity diagonal == 1
    const id = MatrixIdentity();
    try expectEqual(@as(f32, 1), id.m0);
    try expectEqual(@as(f32, 1), id.m5);
    try expectEqual(@as(f32, 1), id.m10);
    try expectEqual(@as(f32, 1), id.m15);
    try expectEqual(@as(f32, 0), id.m1);

    // FloatEquals returns c_int 0/1
    try expectEqual(@as(c_int, 1), FloatEquals(1.0, 1.0));
    try expectEqual(@as(c_int, 0), FloatEquals(1.0, 2.0));

    // QuaternionIdentity
    const qi = QuaternionIdentity();
    try expectEqual(@as(f32, 0), qi.x);
    try expectEqual(@as(f32, 1), qi.w);

    // MatrixMultiply identity * identity == identity
    const mm = MatrixMultiply(id, id);
    try expectEqual(@as(f32, 1), mm.m0);
    try expectEqual(@as(f32, 0), mm.m4);

    // Clamp
    try expectEqual(@as(f32, 5), Clamp(10, 0, 5));
    try expectEqual(@as(f32, 0), Clamp(-3, 0, 5));
}
