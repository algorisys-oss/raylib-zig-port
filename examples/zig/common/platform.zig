//! What the upstream examples choose with `#if defined(PLATFORM_DESKTOP)`,
//! shared by the Zig-API translations (`@import("platform")`) and decided by
//! the build target, so one example source serves the desktop and the web.

const builtin = @import("builtin");

/// The shader directory an example loads from: `resources/shaders/glsl330/`
/// on the desktop (OpenGL 3.3), `glsl100/` on the web (WebGL 2 runs GLSL ES
/// 1.00 shaders), as in every upstream example.
pub const glsl_version = if (builtin.os.tag == .emscripten) 100 else 330;
