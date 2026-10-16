//! raylib.lights - Some useful functions to deal with lights data
//!
//! Zig-API port of examples/shaders/rlights.h (raylib 6.2), shared by the
//! lighting examples (`const rlights = @import("rlights");`).
//!
//! LICENSE: zlib/libpng
//!
//! Copyright (c) 2017-2024 Victor Fisac (@victorfisac) and Ramon Santamaria (@raysan5)
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

const rl = @import("raylib");

/// Max dynamic lights supported by shader
pub const max_lights = 4;

/// Light type
pub const LightType = enum(i32) {
    directional = 0,
    point = 1,
};

/// Light data. The zero value (`.{}`) is a disabled light whose shader
/// locations are all 0, exactly like C's `Light light = { 0 }`.
pub const Light = struct {
    type: LightType = .directional,
    enabled: bool = false,
    position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    target: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    color: rl.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    attenuation: f32 = 0,

    // Shader locations
    enabled_loc: i32 = 0,
    type_loc: i32 = 0,
    position_loc: i32 = 0,
    target_loc: i32 = 0,
    color_loc: i32 = 0,
    attenuation_loc: i32 = 0,

    /// Send light properties to shader
    /// NOTE: Light shader locations should be available
    pub fn update(light: Light, shader: rl.Shader) void {
        // Send to shader light enabled state and type
        const enabled: i32 = @intFromBool(light.enabled);
        const light_type: i32 = @backingInt(light.type);
        rl.setShaderValue(shader, light.enabled_loc, enabled);
        rl.setShaderValue(shader, light.type_loc, light_type);

        // Send to shader light position and target position values
        rl.setShaderValue(shader, light.position_loc, light.position);
        rl.setShaderValue(shader, light.target_loc, light.target);

        // Send to shader light color values
        const color = [4]f32{
            @as(f32, @floatFromInt(light.color.r)) / 255,
            @as(f32, @floatFromInt(light.color.g)) / 255,
            @as(f32, @floatFromInt(light.color.b)) / 255,
            @as(f32, @floatFromInt(light.color.a)) / 255,
        };
        rl.setShaderValue(shader, light.color_loc, color);
    }
};

/// Current amount of created lights
var lights_count: u32 = 0;

/// Create a light and get shader locations. Once `max_lights` lights exist,
/// further calls return the zero `Light` (as in C).
pub fn createLight(light_type: LightType, position: rl.Vector3, target: rl.Vector3, color: rl.Color, shader: rl.Shader) Light {
    if (lights_count >= max_lights) return .{};

    // NOTE: Lighting shader naming must be the provided ones
    const light: Light = .{
        .enabled = true,
        .type = light_type,
        .position = position,
        .target = target,
        .color = color,
        .enabled_loc = rl.getShaderLocation(shader, rl.textFormat("lights[{d}].enabled", .{lights_count})),
        .type_loc = rl.getShaderLocation(shader, rl.textFormat("lights[{d}].type", .{lights_count})),
        .position_loc = rl.getShaderLocation(shader, rl.textFormat("lights[{d}].position", .{lights_count})),
        .target_loc = rl.getShaderLocation(shader, rl.textFormat("lights[{d}].target", .{lights_count})),
        .color_loc = rl.getShaderLocation(shader, rl.textFormat("lights[{d}].color", .{lights_count})),
    };
    light.update(shader);

    lights_count += 1;
    return light;
}
