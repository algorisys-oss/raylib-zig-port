//! reasings - raylib easings library, based on Robert Penner library
//!
//! Zig port of examples/shapes/reasings.h (raylib 6.2), shared by the easing
//! examples (`const reasings = @import("reasings");`).
//!
//! Useful easing functions for values animation. The four inputs t, b, c, d
//! are defined as follows:
//!   t = current time (in any unit measure, but same unit as duration)
//!   b = starting value to interpolate
//!   c = the total change in value of b that needs to occur
//!   d = total time it should take to complete (duration)
//!
//! The math is kept term-for-term with the C header (f32 throughout, same
//! operation order, same libm `sinf`/`cosf`/`powf`), so results are
//! bit-identical to the C functions.
//!
//! A port of Robert Penner's easing equations to C (http://robertpenner.com/easing/)
//!
//! Robert Penner License
//! ---------------------------------------------------------------------------------
//! Open source under the BSD License.
//!
//! Copyright (c) 2001 Robert Penner. All rights reserved.
//!
//! Redistribution and use in source and binary forms, with or without modification,
//! are permitted provided that the following conditions are met:
//!
//!     - Redistributions of source code must retain the above copyright notice,
//!       this list of conditions and the following disclaimer.
//!     - Redistributions in binary form must reproduce the above copyright notice,
//!       this list of conditions and the following disclaimer in the documentation
//!       and/or other materials provided with the distribution.
//!     - Neither the name of the author nor the names of contributors may be used
//!       to endorse or promote products derived from this software without specific
//!       prior written permission.
//!
//! THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//! ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//! WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//! IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//! INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//! BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//! DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
//! LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
//! OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
//! OF THE POSSIBILITY OF SUCH DAMAGE.
//! ---------------------------------------------------------------------------------
//!
//! Copyright (c) 2015-2024 Ramon Santamaria (@raysan5)
//!
//! This software is provided "as-is", without any express or implied warranty. In no event
//! will the authors be held liable for any damages arising from the use of this software.
//!
//! Permission is granted to anyone to use this software for any purpose, including commercial
//! applications, and to alter it and redistribute it freely, subject to the following restrictions:
//!
//!   1. The origin of this software must not be misrepresented; you must not claim that you
//!   wrote the original software. If you use this software in a product, an acknowledgment
//!   in the product documentation would be appreciated but is not required.
//!
//!   2. Altered source versions must be plainly marked as such, and must not be misrepresented
//!   as being the original software.
//!
//!   3. This notice may not be removed or altered from any source distribution.

// The C header calls libm; call the very same functions so results match bit-for-bit.
extern "c" fn sinf(x: f32) f32;
extern "c" fn cosf(x: f32) f32;
extern "c" fn powf(x: f32, y: f32) f32;

const pi: f32 = 3.14159265358979323846;

// Linear Easing functions

/// Ease: Linear
pub fn easeLinearNone(t: f32, b: f32, c: f32, d: f32) f32 {
    return c * t / d + b;
}

/// Ease: Linear In
pub fn easeLinearIn(t: f32, b: f32, c: f32, d: f32) f32 {
    return c * t / d + b;
}

/// Ease: Linear Out
pub fn easeLinearOut(t: f32, b: f32, c: f32, d: f32) f32 {
    return c * t / d + b;
}

/// Ease: Linear In Out
pub fn easeLinearInOut(t: f32, b: f32, c: f32, d: f32) f32 {
    return c * t / d + b;
}

// Sine Easing functions

/// Ease: Sine In
pub fn easeSineIn(t: f32, b: f32, c: f32, d: f32) f32 {
    return -c * cosf(t / d * (pi / 2.0)) + c + b;
}

/// Ease: Sine Out
pub fn easeSineOut(t: f32, b: f32, c: f32, d: f32) f32 {
    return c * sinf(t / d * (pi / 2.0)) + b;
}

/// Ease: Sine In Out
pub fn easeSineInOut(t: f32, b: f32, c: f32, d: f32) f32 {
    return -c / 2.0 * (cosf(pi * t / d) - 1.0) + b;
}

// Circular Easing functions

/// Ease: Circular In
pub fn easeCircIn(t: f32, b: f32, c: f32, d: f32) f32 {
    const x = t / d;
    return -c * (@sqrt(1.0 - x * x) - 1.0) + b;
}

/// Ease: Circular Out
pub fn easeCircOut(t: f32, b: f32, c: f32, d: f32) f32 {
    const x = t / d - 1.0;
    return c * @sqrt(1.0 - x * x) + b;
}

/// Ease: Circular In Out
pub fn easeCircInOut(t: f32, b: f32, c: f32, d: f32) f32 {
    const x = t / (d / 2.0);
    if (x < 1.0) return -c / 2.0 * (@sqrt(1.0 - x * x) - 1.0) + b;
    const y = x - 2.0;
    return c / 2.0 * (@sqrt(1.0 - y * y) + 1.0) + b;
}

// Cubic Easing functions

/// Ease: Cubic In
pub fn easeCubicIn(t: f32, b: f32, c: f32, d: f32) f32 {
    const x = t / d;
    return c * x * x * x + b;
}

/// Ease: Cubic Out
pub fn easeCubicOut(t: f32, b: f32, c: f32, d: f32) f32 {
    const x = t / d - 1.0;
    return c * (x * x * x + 1.0) + b;
}

/// Ease: Cubic In Out
pub fn easeCubicInOut(t: f32, b: f32, c: f32, d: f32) f32 {
    const x = t / (d / 2.0);
    if (x < 1.0) return c / 2.0 * x * x * x + b;
    const y = x - 2.0;
    return c / 2.0 * (y * y * y + 2.0) + b;
}

// Quadratic Easing functions

/// Ease: Quadratic In
pub fn easeQuadIn(t: f32, b: f32, c: f32, d: f32) f32 {
    const x = t / d;
    return c * x * x + b;
}

/// Ease: Quadratic Out
pub fn easeQuadOut(t: f32, b: f32, c: f32, d: f32) f32 {
    const x = t / d;
    return -c * x * (x - 2.0) + b;
}

/// Ease: Quadratic In Out
pub fn easeQuadInOut(t: f32, b: f32, c: f32, d: f32) f32 {
    const x = t / (d / 2.0);
    if (x < 1.0) return c / 2.0 * (x * x) + b;
    return -c / 2.0 * ((x - 1.0) * (x - 3.0) - 1.0) + b;
}

// Exponential Easing functions

/// Ease: Exponential In
pub fn easeExpoIn(t: f32, b: f32, c: f32, d: f32) f32 {
    return if (t == 0.0) b else c * powf(2.0, 10.0 * (t / d - 1.0)) + b;
}

/// Ease: Exponential Out
pub fn easeExpoOut(t: f32, b: f32, c: f32, d: f32) f32 {
    return if (t == d) b + c else c * (-powf(2.0, -10.0 * t / d) + 1.0) + b;
}

/// Ease: Exponential In Out
pub fn easeExpoInOut(t: f32, b: f32, c: f32, d: f32) f32 {
    if (t == 0.0) return b;
    if (t == d) return b + c;
    const x = t / (d / 2.0);
    if (x < 1.0) return c / 2.0 * powf(2.0, 10.0 * (x - 1.0)) + b;
    return c / 2.0 * (-powf(2.0, -10.0 * (x - 1.0)) + 2.0) + b;
}

// Back Easing functions

const back_overshoot: f32 = 1.70158;
/// The In Out variants scale the overshoot (an f32 multiply, as in C).
const back_overshoot_in_out: f32 = back_overshoot * @as(f32, 1.525);

/// Ease: Back In
pub fn easeBackIn(t: f32, b: f32, c: f32, d: f32) f32 {
    const s = back_overshoot;
    const x = t / d;
    return c * x * x * ((s + 1.0) * x - s) + b;
}

/// Ease: Back Out
pub fn easeBackOut(t: f32, b: f32, c: f32, d: f32) f32 {
    const s = back_overshoot;
    const x = t / d - 1.0;
    return c * (x * x * ((s + 1.0) * x + s) + 1.0) + b;
}

/// Ease: Back In Out
pub fn easeBackInOut(t: f32, b: f32, c: f32, d: f32) f32 {
    const s = back_overshoot_in_out;
    const x = t / (d / 2.0);
    if (x < 1.0) return c / 2.0 * (x * x * ((s + 1.0) * x - s)) + b;
    const y = x - 2.0;
    return c / 2.0 * (y * y * ((s + 1.0) * y + s) + 2.0) + b;
}

// Bounce Easing functions

/// Ease: Bounce Out
pub fn easeBounceOut(t: f32, b: f32, c: f32, d: f32) f32 {
    // Breakpoints are f32 divisions, as C's `1.0f/2.75f`; the third
    // comparison is done in double in C (`t < (2.5/2.75)`).
    const x = t / d;
    if (x < @as(f32, 1.0) / 2.75) {
        return c * (7.5625 * x * x) + b;
    } else if (x < @as(f32, 2.0) / 2.75) {
        const y = x - @as(f32, 1.5) / 2.75;
        return c * (7.5625 * y * y + 0.75) + b;
    } else if (@as(f64, x) < @as(f64, 2.5) / 2.75) {
        const y = x - @as(f32, 2.25) / 2.75;
        return c * (7.5625 * y * y + 0.9375) + b;
    } else {
        const y = x - @as(f32, 2.625) / 2.75;
        return c * (7.5625 * y * y + 0.984375) + b;
    }
}

/// Ease: Bounce In
pub fn easeBounceIn(t: f32, b: f32, c: f32, d: f32) f32 {
    return c - easeBounceOut(d - t, 0.0, c, d) + b;
}

/// Ease: Bounce In Out
pub fn easeBounceInOut(t: f32, b: f32, c: f32, d: f32) f32 {
    if (t < d / 2.0) return easeBounceIn(t * 2.0, 0.0, c, d) * 0.5 + b;
    return easeBounceOut(t * 2.0 - d, 0.0, c, d) * 0.5 + c * 0.5 + b;
}

// Elastic Easing functions

/// Ease: Elastic In
pub fn easeElasticIn(t: f32, b: f32, c: f32, d: f32) f32 {
    if (t == 0.0) return b;
    const x = t / d;
    if (x == 1.0) return b + c;

    const p = d * 0.3;
    const a = c;
    const s = p / 4.0;
    const y = x - 1.0;
    const post_fix = a * powf(2.0, 10.0 * y);

    return -(post_fix * sinf((y * d - s) * (2.0 * pi) / p)) + b;
}

/// Ease: Elastic Out
pub fn easeElasticOut(t: f32, b: f32, c: f32, d: f32) f32 {
    if (t == 0.0) return b;
    const x = t / d;
    if (x == 1.0) return b + c;

    const p = d * 0.3;
    const a = c;
    const s = p / 4.0;

    return a * powf(2.0, -10.0 * x) * sinf((x * d - s) * (2.0 * pi) / p) + c + b;
}

/// Ease: Elastic In Out
pub fn easeElasticInOut(t: f32, b: f32, c: f32, d: f32) f32 {
    if (t == 0.0) return b;
    const x = t / (d / 2.0);
    if (x == 2.0) return b + c;

    const p = d * (@as(f32, 0.3) * 1.5);
    const a = c;
    const s = p / 4.0;
    const y = x - 1.0;

    if (x < 1.0) {
        const post_fix = a * powf(2.0, 10.0 * y);
        return -0.5 * (post_fix * sinf((y * d - s) * (2.0 * pi) / p)) + b;
    }

    const post_fix = a * powf(2.0, -10.0 * y);
    return post_fix * sinf((y * d - s) * (2.0 * pi) / p) * 0.5 + c + b;
}
