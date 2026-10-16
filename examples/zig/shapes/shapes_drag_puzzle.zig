//! raylib [shapes] example - drag puzzle
//!
//! Zig-API translation of examples/shapes/shapes_drag_puzzle.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Gabriel Piangers (@gabriel-piangers)

const rl = @import("raylib");
const rm = rl.math;

const Circle = struct {
    center: rl.Vector2,
    radius: f32,
};

const Triangle = struct {
    v1: rl.Vector2,
    v2: rl.Vector2,
    v3: rl.Vector2,

    fn contains(tri: Triangle, point: rl.Vector2) bool {
        return rl.checkCollisionPointTriangle(point, tri.v1, tri.v2, tri.v3);
    }
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - drag puzzle");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Rectangle
    var rec: rl.Rectangle = .{ .x = screen_width / 2 - 250, .y = screen_height / 2 + 50, .width = 100.0, .height = 100.0 };
    const rec_area: rl.Rectangle = .{ .x = screen_width / 2 - 60, .y = screen_height / 2 - 110, .width = 110.0, .height = 110.0 };
    var rec_picked_up = false;

    // Circle
    var circ: Circle = .{ .center = .{ .x = screen_width / 2, .y = screen_height / 2 + 100 }, .radius = 50.0 };
    const circ_area: Circle = .{ .center = .{ .x = screen_width / 2 - 195, .y = screen_height / 2 - 55 }, .radius = 55.0 };
    var circ_picked_up = false;

    // Triangle
    var tri: Triangle = .{ .v1 = .{ .x = 600, .y = 282 }, .v2 = .{ .x = 550, .y = 369 }, .v3 = .{ .x = 650, .y = 369 } };
    const tri_area: Triangle = .{ .v1 = .{ .x = 600, .y = 115 }, .v2 = .{ .x = 540, .y = 222 }, .v3 = .{ .x = 660, .y = 222 } };
    var tri_picked_up = false;

    var mouse_offset: rl.Vector2 = .{ .x = 0.0, .y = 0.0 }; // Offset of the mouse relative to the object's pivot point

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_position = rl.getMousePosition();

        // Detect object pickup input
        if (rl.isMouseButtonPressed(.left)) {
            if (rl.checkCollisionPointRec(mouse_position, rec)) {
                rec_picked_up = true;
                mouse_offset = .{ .x = rec.x - mouse_position.x, .y = rec.y - mouse_position.y };
            } else if (rl.checkCollisionPointCircle(mouse_position, circ.center, circ.radius)) {
                circ_picked_up = true;
                mouse_offset = .{ .x = circ.center.x - mouse_position.x, .y = circ.center.y - mouse_position.y };
            } else if (tri.contains(mouse_position)) {
                tri_picked_up = true;
                mouse_offset = .{ .x = tri.v1.x - mouse_position.x, .y = tri.v1.y - mouse_position.y }; // Uses v1 as the pivot point
            }
        }

        // Detect object drop input
        if (rl.isMouseButtonReleased(.left)) {
            if (rec_picked_up) {
                rec_picked_up = false;
            } else if (circ_picked_up) {
                circ_picked_up = false;
            } else if (tri_picked_up) {
                tri_picked_up = false;
            }
        }

        // Rectangle update
        if (rec_picked_up) {
            rec.x = mouse_position.x + mouse_offset.x;
            rec.y = mouse_position.y + mouse_offset.y;
        }
        const rec_col = rl.getCollisionRec(rec_area, rec);
        const rec_placed = rec_col.width == rec.width and rec_col.height == rec.height;

        // Circle update
        if (circ_picked_up) {
            circ.center.x = mouse_position.x + mouse_offset.x;
            circ.center.y = mouse_position.y + mouse_offset.y;
        }
        const circ_placed = rm.vector2Distance(circ.center, circ_area.center) < circ_area.radius - circ.radius;

        // Triangle update
        if (tri_picked_up) {
            const v2_offset: rl.Vector2 = .{ .x = tri.v2.x - tri.v1.x, .y = tri.v2.y - tri.v1.y };
            const v3_offset: rl.Vector2 = .{ .x = tri.v3.x - tri.v1.x, .y = tri.v3.y - tri.v1.y };

            tri.v1 = .{ .x = mouse_position.x + mouse_offset.x, .y = mouse_position.y + mouse_offset.y };
            tri.v2 = .{ .x = tri.v1.x + v2_offset.x, .y = tri.v1.y + v2_offset.y };
            tri.v3 = .{ .x = tri.v1.x + v3_offset.x, .y = tri.v1.y + v3_offset.y };
        }
        // NOTE: upstream checks v2 twice (and never v3); kept for identical behavior
        const tri_placed = tri_area.contains(tri.v1) and tri_area.contains(tri.v2) and tri_area.contains(tri.v2);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        rl.drawRectangleLinesEx(rec_area, 2.0, if (rec_placed) .green else .red);
        rl.drawCircleLinesEx(circ_area.center, circ_area.radius, 2.0, if (circ_placed) .green else .red);
        rl.drawTriangleLinesEx(tri_area.v1, tri_area.v2, tri_area.v3, 2.0, if (tri_placed) .green else .red);

        // Draws objects that are not picked up first
        if (!tri_picked_up) rl.drawTriangle(tri.v1, tri.v2, tri.v3, .violet);
        if (!circ_picked_up) rl.drawCircleV(circ.center, circ.radius, .blue);
        if (!rec_picked_up) rl.drawRectangleRec(rec, .orange);

        // Draws the object that is being dragged on top of others
        if (tri_picked_up) rl.drawTriangle(tri.v1, tri.v2, tri.v3, .violet);
        if (circ_picked_up) rl.drawCircleV(circ.center, circ.radius, .blue);
        if (rec_picked_up) rl.drawRectangleRec(rec, .orange);

        rl.drawText("Use mouse to drag and drop the objects into the right spot!", 10, 10, 20, .gray);
    }
}
