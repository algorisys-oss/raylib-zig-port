//! raylib [shaders] example - rounded rectangle
//!
//! Zig-API translation of examples/shaders/shaders_rounded_rectangle.c (raylib 6.2).
//! Example contributed by Anstro Pleuton (@anstropleuton) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Anstro Pleuton (@anstropleuton)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

const screen_width = 800;
const screen_height = 450;

/// Rounded rectangle data
const RoundedRectangle = struct {
    corner_radius: rl.Vector4, // Individual corner radius (top-left, top-right, bottom-left, bottom-right)

    // Shadow variables
    shadow_radius: f32,
    shadow_offset: rl.Vector2,
    shadow_scale: f32,

    // Border variables
    border_thickness: f32, // Inner-border thickness

    // Shader locations
    rectangle_loc: i32,
    radius_loc: i32,
    color_loc: i32,
    shadow_radius_loc: i32,
    shadow_offset_loc: i32,
    shadow_scale_loc: i32,
    shadow_color_loc: i32,
    border_thickness_loc: i32,
    border_color_loc: i32,

    /// Create a rounded rectangle and set uniform locations
    fn init(
        corner_radius: rl.Vector4,
        shadow_radius: f32,
        shadow_offset: rl.Vector2,
        shadow_scale: f32,
        border_thickness: f32,
        shader: rl.Shader,
    ) RoundedRectangle {
        const rec: RoundedRectangle = .{
            .corner_radius = corner_radius,
            .shadow_radius = shadow_radius,
            .shadow_offset = shadow_offset,
            .shadow_scale = shadow_scale,
            .border_thickness = border_thickness,

            // Get shader uniform locations
            .rectangle_loc = rl.getShaderLocation(shader, "rectangle"),
            .radius_loc = rl.getShaderLocation(shader, "radius"),
            .color_loc = rl.getShaderLocation(shader, "color"),
            .shadow_radius_loc = rl.getShaderLocation(shader, "shadowRadius"),
            .shadow_offset_loc = rl.getShaderLocation(shader, "shadowOffset"),
            .shadow_scale_loc = rl.getShaderLocation(shader, "shadowScale"),
            .shadow_color_loc = rl.getShaderLocation(shader, "shadowColor"),
            .border_thickness_loc = rl.getShaderLocation(shader, "borderThickness"),
            .border_color_loc = rl.getShaderLocation(shader, "borderColor"),
        };
        rec.update(shader);
        return rec;
    }

    /// Update rounded rectangle uniforms
    fn update(rec: RoundedRectangle, shader: rl.Shader) void {
        rl.setShaderValue(shader, rec.radius_loc, rec.corner_radius);
        rl.setShaderValue(shader, rec.shadow_radius_loc, rec.shadow_radius);
        rl.setShaderValue(shader, rec.shadow_offset_loc, rec.shadow_offset);
        rl.setShaderValue(shader, rec.shadow_scale_loc, rec.shadow_scale);
        rl.setShaderValue(shader, rec.border_thickness_loc, rec.border_thickness);
    }

    /// Draw `rec` (framed and labelled, `margin` pixels around it) with the
    /// shader; pass `.blank` to leave a color layer (fill, shadow, border) out.
    fn draw(
        self: RoundedRectangle,
        shader: rl.Shader,
        rec: rl.Rectangle,
        margin: i32,
        label: [:0]const u8,
        color: rl.Color,
        shadow_color: rl.Color,
        border_color: rl.Color,
    ) void {
        const x: i32 = @intFromFloat(rec.x);
        const y: i32 = @intFromFloat(rec.y);
        const width: i32 = @intFromFloat(rec.width);
        const height: i32 = @intFromFloat(rec.height);
        rl.drawRectangleLines(x - margin, y - margin, width + 2 * margin, height + 2 * margin, .dark_gray);
        rl.drawText(label, x - margin, y - margin - 15, 10, .dark_gray);

        // Flip Y axis to match shader coordinate system
        const flipped: rl.Vector4 = .{ .x = rec.x, .y = screen_height - rec.y - rec.height, .z = rec.width, .w = rec.height };
        rl.setShaderValue(shader, self.rectangle_loc, flipped);

        rl.setShaderValue(shader, self.color_loc, rl.colorNormalize(color));
        rl.setShaderValue(shader, self.shadow_color_loc, rl.colorNormalize(shadow_color));
        rl.setShaderValue(shader, self.border_color_loc, rl.colorNormalize(border_color));

        rl.beginShaderMode(shader);
        defer rl.endShaderMode();

        rl.drawRectangle(0, 0, screen_width, screen_height, .white);
    }
};

pub fn main() !void {
    // Initialization
    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - rounded rectangle");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Load the shader
    const shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/base.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/rounded_rectangle.fs", .{glsl_version}),
    );
    defer rl.unloadShader(shader);

    // Create a rounded rectangle
    const rounded_rectangle: RoundedRectangle = .init(
        .{ .x = 5.0, .y = 10.0, .z = 15.0, .w = 20.0 }, // Corner radius
        20.0, // Shadow radius
        .{ .x = 0.0, .y = -5.0 }, // Shadow offset
        0.95, // Shadow scale
        5.0, // Border thickness
        shader, // Shader
    );

    // Update shader uniforms
    rounded_rectangle.update(shader);

    const rectangle_color: rl.Color = .blue;
    const shadow_color: rl.Color = .dark_blue;
    const border_color: rl.Color = .sky_blue;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw rectangle box with rounded corners using shader (only rectangle color)
        rounded_rectangle.draw(shader, .{ .x = 50, .y = 70, .width = 110, .height = 60 }, 20, "Rounded rectangle", rectangle_color, .blank, .blank);

        // Draw rectangle shadow using shader (only shadow color)
        rounded_rectangle.draw(shader, .{ .x = 50, .y = 200, .width = 110, .height = 60 }, 20, "Rounded rectangle shadow", .blank, shadow_color, .blank);

        // Draw rectangle's border using shader (only border color)
        rounded_rectangle.draw(shader, .{ .x = 50, .y = 330, .width = 110, .height = 60 }, 20, "Rounded rectangle border", .blank, .blank, border_color);

        // Draw one more rectangle with all three colors
        rounded_rectangle.draw(shader, .{ .x = 240, .y = 80, .width = 500, .height = 300 }, 30, "Rectangle with all three combined", rectangle_color, shadow_color, border_color);

        rl.drawText("(c) Rounded rectangle SDF by Iñigo Quilez. MIT License.", screen_width - 300, screen_height - 20, 10, .black);
    }
}
