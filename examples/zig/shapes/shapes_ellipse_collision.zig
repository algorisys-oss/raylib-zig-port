//! raylib [shapes] example - ellipse collision
//!
//! Zig-API translation of examples/shapes/shapes_ellipse_collision.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Ziya (@Monjaris)

const std = @import("std");
const rl = @import("raylib");

const Ellipse = struct {
    center: rl.Vector2,
    rx: f32,
    ry: f32,

    /// Check if point is inside ellipse
    fn containsPoint(e: Ellipse, point: rl.Vector2) bool {
        const dx = (point.x - e.center.x) / e.rx;
        const dy = (point.y - e.center.y) / e.ry;
        return dx * dx + dy * dy <= 1.0;
    }

    /// Radial distance from center to ellipse boundary in direction theta:
    /// r(theta) = (rx * ry) / sqrt((ry*cos)^2 + (rx*sin)^2)
    fn radius(e: Ellipse, cos_t: f32, sin_t: f32) f32 {
        return (e.rx * e.ry) / @sqrt((e.ry * cos_t) * (e.ry * cos_t) + (e.rx * sin_t) * (e.rx * sin_t));
    }

    /// Check if two ellipses collide
    /// Uses radial boundary distance in the direction between centers — scales correctly with radii
    fn collides(e1: Ellipse, e2: Ellipse) bool {
        const dx = e2.center.x - e1.center.x;
        const dy = e2.center.y - e1.center.y;
        const dist = @sqrt(dx * dx + dy * dy);

        // Ellipses are on top of each other
        if (dist == 0.0) return true;

        const theta = std.math.atan2(dy, dx);
        const cos_t = @cos(theta);
        const sin_t = @sin(theta);

        return dist <= e1.radius(cos_t, sin_t) + e2.radius(cos_t, sin_t);
    }

    fn draw(e: Ellipse, color: rl.Color) void {
        rl.drawEllipse(@intFromFloat(e.center.x), @intFromFloat(e.center.y), e.rx, e.ry, color);
    }

    fn drawLines(e: Ellipse, color: rl.Color) void {
        rl.drawEllipseLines(@intFromFloat(e.center.x), @intFromFloat(e.center.y), e.rx, e.ry, color);
    }
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - ellipse collision");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var ellipse_a: Ellipse = .{ .center = .{ .x = screen_width / 4.0, .y = screen_height / 2.0 }, .rx = 120.0, .ry = 70.0 };
    var ellipse_b: Ellipse = .{ .center = .{ .x = screen_width * 3 / 4.0, .y = screen_height / 2.0 }, .rx = 90.0, .ry = 140.0 };

    var controlled: enum { a, b } = .a;

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyPressed(.a)) controlled = .a;
        if (rl.isKeyPressed(.b)) controlled = .b;

        switch (controlled) {
            .a => ellipse_a.center = rl.getMousePosition(),
            .b => ellipse_b.center = rl.getMousePosition(),
        }

        const ellipses_collide = ellipse_a.collides(ellipse_b);

        const mouse_in_a = ellipse_a.containsPoint(rl.getMousePosition());
        const mouse_in_b = ellipse_b.containsPoint(rl.getMousePosition());

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        ellipse_a.draw(if (ellipses_collide) .red else .blue);
        ellipse_b.draw(if (ellipses_collide) .red else .green);

        ellipse_a.drawLines(.white);
        ellipse_b.drawLines(.white);

        rl.drawCircleV(ellipse_a.center, 4, .white);
        rl.drawCircleV(ellipse_b.center, 4, .white);

        if (ellipses_collide) {
            rl.drawText("ELLIPSES COLLIDE", screen_width / 2 - 120, 40, 28, .red);
        } else {
            rl.drawText("NO COLLISION", screen_width / 2 - 80, 40, 28, .dark_gray);
        }

        rl.drawText(if (controlled == .a) "Controlling: A" else "Controlling: B", 20, screen_height - 40, 20, .yellow);

        if (mouse_in_a and controlled != .a) rl.drawText("Mouse inside ellipse A", 20, screen_height - 70, 20, .blue);
        if (mouse_in_b and controlled != .b) rl.drawText("Mouse inside ellipse B", 20, screen_height - 70, 20, .green);

        rl.drawText("Press [A] or [B] to switch control", 20, 20, 20, .gray);
    }
}
