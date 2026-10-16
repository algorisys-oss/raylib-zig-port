//! rgestures - Gestures system, gestures processing based on input events (touch/mouse)
//!
//! Zig port of raylib's `rgestures.h` (implementation section, non-standalone mode).
//! Every public gesture function is exported with its exact C name, byte-compatible
//! signature, and C calling convention, so the rest of raylib (still C) links against
//! it unchanged. Floating-point operation order matches the C source exactly to keep
//! results bit-identical, and the few libm functions are called via `extern`.
//!
//! The module owns the `static GesturesData GESTURES` global state. It is internal to
//! this translation unit (not ABI-shared), so it is a plain module-private `var` rather
//! than `extern`, but its initial field values replicate the C initializer exactly.
//!
//! `rgGetCurrentTime()` in non-standalone mode simply forwards to `GetTime()` (provided
//! by rcore at link time), declared here via `extern` so a test harness can control the
//! clock. The internal vector helpers `rgVector2Angle` / `rgVector2Distance` are ported
//! as private functions with the same float/double op-order as the C (they use `atan2f`
//! and the double `sqrt`).

//----------------------------------------------------------------------------------
// libm functions, called directly so results are bit-identical to the C source.
//----------------------------------------------------------------------------------
extern fn atan2f(f32, f32) f32;
extern fn sqrt(f64) f64;

//----------------------------------------------------------------------------------
// rcore functions, provided by another translation unit in the build.
//----------------------------------------------------------------------------------
extern fn GetTime() f64;

//----------------------------------------------------------------------------------
// Defines and Macros
//----------------------------------------------------------------------------------
// PI is FLOAT in non-standalone mode (raylib.h: `#define PI ...f`); the double
// definition only exists under RGESTURES_STANDALONE. rgVector2Angle therefore
// computes entirely in f32 — matching C bit-for-bit.
const PI: f32 = 3.14159265358979323846;

const MAX_TOUCH_POINTS: usize = 8; // Maximum number of touch points supported

const FORCE_TO_SWIPE: f32 = 0.2; // Swipe force, measured in normalized screen units/time
const MINIMUM_DRAG: f32 = 0.015; // Drag minimum force, measured in normalized screen units (0.0f to 1.0f)
const DRAG_TIMEOUT: f32 = 0.3; // Drag minimum time for web, measured in seconds
const MINIMUM_PINCH: f32 = 0.005; // Pinch minimum force, measured in normalized screen units (0.0f to 1.0f)
const TAP_TIMEOUT: f32 = 0.3; // Tap minimum time, measured in seconds
const PINCH_TIMEOUT: f32 = 0.3; // Pinch minimum time, measured in seconds
const DOUBLETAP_RANGE: f32 = 0.03; // DoubleTap range, measured in normalized screen units (0.0f to 1.0f)

// Gesture flags (from raylib.h). Used as flags to enable only some gestures.
const GESTURE_NONE: c_uint = 0;
const GESTURE_TAP: c_uint = 1;
const GESTURE_DOUBLETAP: c_uint = 2;
const GESTURE_HOLD: c_uint = 4;
const GESTURE_DRAG: c_uint = 8;
const GESTURE_SWIPE_RIGHT: c_uint = 16;
const GESTURE_SWIPE_LEFT: c_uint = 32;
const GESTURE_SWIPE_UP: c_uint = 64;
const GESTURE_SWIPE_DOWN: c_uint = 128;
const GESTURE_PINCH_IN: c_uint = 256;
const GESTURE_PINCH_OUT: c_uint = 512;

// Touch actions (from raylib.h)
const TOUCH_ACTION_UP: c_int = 0;
const TOUCH_ACTION_DOWN: c_int = 1;
const TOUCH_ACTION_MOVE: c_int = 2;
const TOUCH_ACTION_CANCEL: c_int = 3;

//----------------------------------------------------------------------------------
// Types and Structures Definition
//----------------------------------------------------------------------------------

/// Vector2 type
const Vector2 = extern struct {
    x: f32,
    y: f32,
};

/// Gesture event
const GestureEvent = extern struct {
    touchAction: c_int,
    pointCount: c_int,
    pointId: [MAX_TOUCH_POINTS]c_int,
    position: [MAX_TOUCH_POINTS]Vector2,
};

/// Gestures module state context [136 bytes]
const GesturesData = extern struct {
    current: c_uint, // Current detected gesture
    enabledFlags: c_uint, // Enabled gestures flags
    Touch: extern struct {
        firstId: c_int, // Touch id for first touch point
        pointCount: c_int, // Touch points counter
        eventTime: f64, // Time stamp when an event happened
        upPosition: Vector2, // Touch up position
        downPositionA: Vector2, // First touch down position
        downPositionB: Vector2, // Second touch down position
        downDragPosition: Vector2, // Touch drag position
        moveDownPositionA: Vector2, // First touch down position on move
        moveDownPositionB: Vector2, // Second touch down position on move
        previousPositionA: Vector2, // Previous position A to compare for pinch gestures
        previousPositionB: Vector2, // Previous position B to compare for pinch gestures
        tapCounter: c_int, // TAP counter (one tap implies TOUCH_ACTION_DOWN and TOUCH_ACTION_UP actions)
    },
    Hold: extern struct {
        resetRequired: bool, // HOLD reset to get first touch point again
        timeDuration: f64, // HOLD duration in seconds
    },
    Drag: extern struct {
        vector: Vector2, // DRAG vector (between initial and current position)
        angle: f32, // DRAG angle (relative to x-axis)
        distance: f32, // DRAG distance (from initial touch point to final) (normalized [0..1])
        intensity: f32, // DRAG intensity, how far why did the DRAG (pixels per frame)
    },
    Swipe: extern struct {
        startTime: f64, // SWIPE start time to calculate drag intensity
    },
    Pinch: extern struct {
        vector: Vector2, // PINCH vector (between first and second touch points)
        angle: f32, // PINCH angle (relative to x-axis)
        distance: f32, // PINCH displacement distance (normalized [0..1])
    },
};

//----------------------------------------------------------------------------------
// Global Variables Definition
//----------------------------------------------------------------------------------
// Mirrors the C `static GesturesData GESTURES = { .current = GESTURE_NONE,
// .Touch.firstId = -1, .enabledFlags = 0b0000001111111111 };`. Every other field is
// zero-initialized by the C designated initializer, replicated with std.mem.zeroes.
var GESTURES: GesturesData = blk: {
    var g = std.mem.zeroes(GesturesData);
    g.current = GESTURE_NONE; // No current gesture detected
    g.Touch.firstId = -1;
    g.enabledFlags = 0b0000001111111111; // All gestures supported by default
    break :blk g;
};

const std = @import("std");

//----------------------------------------------------------------------------------
// Module Functions Definition
//----------------------------------------------------------------------------------

/// Enable only desired gestures to be detected
export fn SetGesturesEnabled(flags: c_uint) callconv(.c) void {
    GESTURES.enabledFlags = flags;
}

/// Check if gesture have been detected
export fn IsGestureDetected(gesture: c_uint) callconv(.c) bool {
    return (GESTURES.enabledFlags & GESTURES.current) == gesture;
}

/// Process gesture event and translate it into gestures
export fn ProcessGestureEvent(event: GestureEvent) callconv(.c) void {
    // Reset required variables
    GESTURES.Touch.pointCount = event.pointCount; // Required on UpdateGestures()

    if (GESTURES.Touch.pointCount == 1) { // One touch point
        if (event.touchAction == TOUCH_ACTION_DOWN) {
            GESTURES.Touch.tapCounter += 1; // Tap counter

            // Detect GESTURE_DOUBLE_TAP
            if ((GESTURES.current == GESTURE_NONE) and (GESTURES.Touch.tapCounter >= 2) and ((rgGetCurrentTime() - GESTURES.Touch.eventTime) < TAP_TIMEOUT) and (rgVector2Distance(GESTURES.Touch.downPositionA, event.position[0]) < DOUBLETAP_RANGE)) {
                GESTURES.current = GESTURE_DOUBLETAP;
                GESTURES.Touch.tapCounter = 0;
            } else { // Detect GESTURE_TAP
                GESTURES.Touch.tapCounter = 1;
                GESTURES.current = GESTURE_TAP;
            }

            GESTURES.Touch.downPositionA = event.position[0];
            GESTURES.Touch.downDragPosition = event.position[0];

            GESTURES.Touch.upPosition = GESTURES.Touch.downPositionA;
            GESTURES.Touch.eventTime = rgGetCurrentTime();

            GESTURES.Swipe.startTime = rgGetCurrentTime();

            GESTURES.Drag.vector = Vector2{ .x = 0.0, .y = 0.0 };
        } else if (event.touchAction == TOUCH_ACTION_UP) {
            // A swipe can happen while the current gesture is drag, but (especially for web) also hold, so set upPosition for both cases
            if (GESTURES.current == GESTURE_DRAG or GESTURES.current == GESTURE_HOLD) GESTURES.Touch.upPosition = event.position[0];

            // NOTE: GESTURES.Drag.intensity is dependent on the resolution of the screen
            GESTURES.Drag.distance = rgVector2Distance(GESTURES.Touch.downPositionA, GESTURES.Touch.upPosition);
            GESTURES.Drag.intensity = GESTURES.Drag.distance / @as(f32, @floatCast(rgGetCurrentTime() - GESTURES.Swipe.startTime));

            // Detect GESTURE_SWIPE
            if ((GESTURES.Drag.intensity > FORCE_TO_SWIPE) and (GESTURES.current != GESTURE_DRAG)) {
                // NOTE: Angle should be inverted in Y
                GESTURES.Drag.angle = 360.0 - rgVector2Angle(GESTURES.Touch.downPositionA, GESTURES.Touch.upPosition);

                if ((GESTURES.Drag.angle < 30) or (GESTURES.Drag.angle > 330)) {
                    GESTURES.current = GESTURE_SWIPE_RIGHT; // Right
                } else if ((GESTURES.Drag.angle >= 30) and (GESTURES.Drag.angle <= 150)) {
                    GESTURES.current = GESTURE_SWIPE_UP; // Up
                } else if ((GESTURES.Drag.angle > 150) and (GESTURES.Drag.angle < 210)) {
                    GESTURES.current = GESTURE_SWIPE_LEFT; // Left
                } else if ((GESTURES.Drag.angle >= 210) and (GESTURES.Drag.angle <= 330)) {
                    GESTURES.current = GESTURE_SWIPE_DOWN; // Down
                } else {
                    GESTURES.current = GESTURE_NONE;
                }
            } else {
                GESTURES.Drag.distance = 0.0;
                GESTURES.Drag.intensity = 0.0;
                GESTURES.Drag.angle = 0.0;

                GESTURES.current = GESTURE_NONE;
            }

            GESTURES.Touch.downDragPosition = Vector2{ .x = 0.0, .y = 0.0 };
            GESTURES.Touch.pointCount = 0;
        } else if (event.touchAction == TOUCH_ACTION_MOVE) {
            GESTURES.Touch.moveDownPositionA = event.position[0];

            if (GESTURES.current == GESTURE_HOLD) {
                if (GESTURES.Hold.resetRequired) GESTURES.Touch.downPositionA = event.position[0];

                GESTURES.Hold.resetRequired = false;

                // Detect GESTURE_DRAG
                if ((rgGetCurrentTime() - GESTURES.Touch.eventTime) > DRAG_TIMEOUT) {
                    GESTURES.Touch.eventTime = rgGetCurrentTime();
                    GESTURES.current = GESTURE_DRAG;
                }
            }

            GESTURES.Drag.vector.x = GESTURES.Touch.moveDownPositionA.x - GESTURES.Touch.downDragPosition.x;
            GESTURES.Drag.vector.y = GESTURES.Touch.moveDownPositionA.y - GESTURES.Touch.downDragPosition.y;
        }
    } else if (GESTURES.Touch.pointCount == 2) { // Two touch points
        if (event.touchAction == TOUCH_ACTION_DOWN) {
            GESTURES.Touch.downPositionA = event.position[0];
            GESTURES.Touch.downPositionB = event.position[1];

            GESTURES.Touch.previousPositionA = GESTURES.Touch.downPositionA;
            GESTURES.Touch.previousPositionB = GESTURES.Touch.downPositionB;

            //GESTURES.Pinch.distance = rgVector2Distance(GESTURES.Touch.downPositionA, GESTURES.Touch.downPositionB);

            GESTURES.Pinch.vector.x = GESTURES.Touch.downPositionB.x - GESTURES.Touch.downPositionA.x;
            GESTURES.Pinch.vector.y = GESTURES.Touch.downPositionB.y - GESTURES.Touch.downPositionA.y;

            GESTURES.current = GESTURE_HOLD;
            GESTURES.Hold.timeDuration = rgGetCurrentTime();
        } else if (event.touchAction == TOUCH_ACTION_MOVE) {
            GESTURES.Pinch.distance = rgVector2Distance(GESTURES.Touch.moveDownPositionA, GESTURES.Touch.moveDownPositionB);

            GESTURES.Touch.moveDownPositionA = event.position[0];
            GESTURES.Touch.moveDownPositionB = event.position[1];

            GESTURES.Pinch.vector.x = GESTURES.Touch.moveDownPositionB.x - GESTURES.Touch.moveDownPositionA.x;
            GESTURES.Pinch.vector.y = GESTURES.Touch.moveDownPositionB.y - GESTURES.Touch.moveDownPositionA.y;

            if ((rgVector2Distance(GESTURES.Touch.previousPositionA, GESTURES.Touch.moveDownPositionA) >= MINIMUM_PINCH) or (rgVector2Distance(GESTURES.Touch.previousPositionB, GESTURES.Touch.moveDownPositionB) >= MINIMUM_PINCH)) {
                if (rgVector2Distance(GESTURES.Touch.previousPositionA, GESTURES.Touch.previousPositionB) > rgVector2Distance(GESTURES.Touch.moveDownPositionA, GESTURES.Touch.moveDownPositionB)) {
                    GESTURES.current = GESTURE_PINCH_IN;
                } else {
                    GESTURES.current = GESTURE_PINCH_OUT;
                }
            } else {
                GESTURES.current = GESTURE_HOLD;
                GESTURES.Hold.timeDuration = rgGetCurrentTime();
            }

            // NOTE: Angle should be inverted in Y
            GESTURES.Pinch.angle = 360.0 - rgVector2Angle(GESTURES.Touch.moveDownPositionA, GESTURES.Touch.moveDownPositionB);
        } else if (event.touchAction == TOUCH_ACTION_UP) {
            GESTURES.Pinch.distance = 0.0;
            GESTURES.Pinch.angle = 0.0;
            GESTURES.Pinch.vector = Vector2{ .x = 0.0, .y = 0.0 };
            GESTURES.Touch.pointCount = 0;

            GESTURES.current = GESTURE_NONE;
        }
    } else if (GESTURES.Touch.pointCount > 2) { // More than two touch points
        // TODO: Process gesture events for more than two points
    }
}

/// Update gestures detected (must be called every frame)
export fn UpdateGestures() callconv(.c) void {
    // NOTE: Gestures are processed through system callbacks on touch events

    // Detect GESTURE_HOLD
    if (((GESTURES.current == GESTURE_TAP) or (GESTURES.current == GESTURE_DOUBLETAP)) and (GESTURES.Touch.pointCount < 2)) {
        GESTURES.current = GESTURE_HOLD;
        GESTURES.Hold.timeDuration = rgGetCurrentTime();
    }

    // Detect GESTURE_NONE
    if ((GESTURES.current == GESTURE_SWIPE_RIGHT) or (GESTURES.current == GESTURE_SWIPE_UP) or (GESTURES.current == GESTURE_SWIPE_LEFT) or (GESTURES.current == GESTURE_SWIPE_DOWN)) {
        GESTURES.current = GESTURE_NONE;
    }
}

/// Get latest detected gesture
export fn GetGestureDetected() callconv(.c) c_int {
    // Get current gesture only if enabled
    return @bitCast(GESTURES.enabledFlags & GESTURES.current);
}

/// Hold time measured in seconds
export fn GetGestureHoldDuration() callconv(.c) f32 {
    // NOTE: time is calculated on current gesture HOLD

    var time: f64 = 0.0;

    if (GESTURES.current == GESTURE_HOLD) time = rgGetCurrentTime() - GESTURES.Hold.timeDuration;

    return @floatCast(time);
}

/// Get drag vector (between initial touch point to current)
export fn GetGestureDragVector() callconv(.c) Vector2 {
    // NOTE: drag vector is calculated on one touch points TOUCH_ACTION_MOVE

    return GESTURES.Drag.vector;
}

/// Get drag angle
/// NOTE: Angle in degrees, horizontal-right is 0, counterclockwise
export fn GetGestureDragAngle() callconv(.c) f32 {
    // NOTE: drag angle is calculated on one touch points TOUCH_ACTION_UP

    return GESTURES.Drag.angle;
}

/// Get distance between two pinch points
export fn GetGesturePinchVector() callconv(.c) Vector2 {
    // NOTE: Pinch distance is calculated on two touch points TOUCH_ACTION_MOVE

    return GESTURES.Pinch.vector;
}

/// Get angle between two pinch points
/// NOTE: Angle in degrees, horizontal-right is 0, counterclockwise
export fn GetGesturePinchAngle() callconv(.c) f32 {
    // NOTE: pinch angle is calculated on two touch points TOUCH_ACTION_MOVE

    return GESTURES.Pinch.angle;
}

//----------------------------------------------------------------------------------
// Module Internal Functions Definition
//----------------------------------------------------------------------------------

/// Get angle from two-points vector with X-axis
fn rgVector2Angle(v1: Vector2, v2: Vector2) f32 {
    // C: float angle = atan2f(v2.y - v1.y, v2.x - v1.x)*(180.0f/PI);
    // PI is FLOAT, so this is entirely f32 (no double promotion).
    var angle: f32 = atan2f(v2.y - v1.y, v2.x - v1.x) * (180.0 / PI);

    if (angle < 0) angle += 360.0;

    return angle;
}

/// Calculate distance between two Vector2
fn rgVector2Distance(v1: Vector2, v2: Vector2) f32 {
    var result: f32 = undefined;

    const dx: f32 = v2.x - v1.x;
    const dy: f32 = v2.y - v1.y;

    // C: result = (float)sqrt(dx*dx + dy*dy);
    // dx*dy products are float, then promoted to double for the double sqrt(),
    // and the double result is narrowed back to float.
    result = @floatCast(sqrt(@as(f64, dx * dx + dy * dy)));

    return result;
}

/// Time measure returned are seconds (non-standalone: forwards to GetTime())
fn rgGetCurrentTime() f64 {
    var time: f64 = 0;

    time = GetTime();

    return time;
}
