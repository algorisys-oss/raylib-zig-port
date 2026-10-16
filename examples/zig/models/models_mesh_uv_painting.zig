//! raylib [models] example - mesh uv painting
//!
//! Example demonstrates painting directly onto a mesh's texture: a ray is cast from the
//! mouse into the scene, the hit triangle is found, and the hit point is converted into
//! UV space using barycentric interpolation so a brush stroke can be drawn on the texture
//!
//! Zig-API translation of examples/models/models_mesh_uv_painting.c (raylib 6.2).
//! Example contributed by PanicTitan (@PanicTitan) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 PanicTitan (@PanicTitan)

const rl = @import("raylib");
const gui = @import("raygui");

const canvas_size = 512;

const Tool = enum { paint, picker };
const Shape = enum { sphere, cube, cylinder, torus };

/// Shape selection toggles, in drawing order
const shape_toggles = [_]struct { shape: Shape, text: [:0]const u8, bounds: rl.Rectangle }{
    .{ .shape = .sphere, .text = "SPHERE", .bounds = .{ .x = 25, .y = 120, .width = 95, .height = 28 } },
    .{ .shape = .cube, .text = "CUBE", .bounds = .{ .x = 125, .y = 120, .width = 95, .height = 28 } },
    .{ .shape = .cylinder, .text = "CYLINDER", .bounds = .{ .x = 25, .y = 153, .width = 95, .height = 28 } },
    .{ .shape = .torus, .text = "TORUS", .bounds = .{ .x = 125, .y = 153, .width = 95, .height = 28 } },
};

const palette = [_]rl.Color{ .red, .orange, .gold, .lime, .sky_blue, .purple, .dark_gray, .white };

/// A primitive shape textured with the canvas, plus its transformed bounding box
/// used for ray testing
const PaintModel = struct {
    model: rl.Model,
    bbox: rl.BoundingBox,
    shape: Shape,

    fn load(shape: Shape, canvas_texture: rl.Texture2D) !PaintModel {
        const mesh = switch (shape) {
            .sphere => rl.genMeshSphere(1.5, 32, 32),
            .cube => rl.genMeshCube(2.2, 2.2, 2.2),
            .cylinder => rl.genMeshCylinder(1.2, 2.5, 24),
            .torus => rl.genMeshTorus(0.6, 1.6, 24, 36),
        };

        var model = try rl.loadModelFromMesh(mesh);

        // genMeshCylinder builds upward from y = 0; shift it down to center on the origin
        if (shape == .cylinder) model.transform = rl.math.matrixTranslate(0.0, -1.25, 0.0);

        model.materials.?[0].map(.diffuse).texture = canvas_texture;

        var box = rl.getMeshBoundingBox(model.meshes.?[0]);
        box.min = rl.math.vector3Transform(box.min, model.transform);
        box.max = rl.math.vector3Transform(box.max, model.transform);

        return .{ .model = model, .bbox = box, .shape = shape };
    }

    fn unload(self: PaintModel) void {
        rl.unloadModel(self.model);
    }

    /// Raycasts against the model's mesh triangles and returns the UV coordinate of the
    /// closest hit, interpolated from the hit triangle's vertices with barycentric weights
    fn hitUV(self: PaintModel, ray: rl.Ray) ?rl.Vector2 {
        if (!rl.getRayCollisionBox(ray, self.bbox).hit) return null; // Fast reject

        const mesh = self.model.meshes.?[0];
        const vertices = mesh.vertices.?;
        const texcoords = mesh.texcoords.?;
        var closest_distance: f32 = 1e9;
        var hit_uv: ?rl.Vector2 = null;

        for (0..@intCast(mesh.triangleCount)) |tri| {
            const index: [3]usize = if (mesh.indices) |indices|
                .{ indices[3 * tri + 0], indices[3 * tri + 1], indices[3 * tri + 2] }
            else
                .{ 3 * tri, 3 * tri + 1, 3 * tri + 2 };

            var corners: [3]rl.Vector3 = undefined;
            for (&corners, index) |*corner, i| {
                const v: rl.Vector3 = .{ .x = vertices[3 * i], .y = vertices[3 * i + 1], .z = vertices[3 * i + 2] };
                corner.* = rl.math.vector3Transform(v, self.model.transform);
            }
            const a, const b, const c = corners;

            const hit = rl.getRayCollisionTriangle(ray, a, b, c);

            if (hit.hit and hit.distance < closest_distance) {
                closest_distance = hit.distance;

                const uv_a: rl.Vector2 = .{ .x = texcoords[2 * index[0]], .y = texcoords[2 * index[0] + 1] };
                const uv_b: rl.Vector2 = .{ .x = texcoords[2 * index[1]], .y = texcoords[2 * index[1] + 1] };
                const uv_c: rl.Vector2 = .{ .x = texcoords[2 * index[2]], .y = texcoords[2 * index[2] + 1] };

                const w = rl.math.vector3Barycenter(hit.point, a, b, c);

                const u = w.x * uv_a.x + w.y * uv_b.x + w.z * uv_c.x;
                const v = w.x * uv_a.y + w.y * uv_b.y + w.z * uv_c.y;

                // Wrap into [0, 1] in case of minor floating point drift at UV seams
                hit_uv = .{ .x = u - @floor(u), .y = v - @floor(v) };
            }
        }

        return hit_uv;
    }
};

/// Canvas pixel coordinate of a UV coordinate.
fn canvasPixel(uv: f32) i32 {
    return @intFromFloat(uv * canvas_size);
}

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - mesh uv painting");
    defer rl.closeWindow(); // Close window and OpenGL context

    var camera: rl.Camera3D = .{
        .position = .{ .x = 0.0, .y = 3.5, .z = 6.5 },
        .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    // CPU-side canvas plus the GPU texture it gets pushed to after every stroke
    var canvas_image = rl.genImageColor(canvas_size, canvas_size, .ray_white);
    defer rl.unloadImage(canvas_image);
    const canvas_texture = try rl.loadTextureFromImage(canvas_image);
    defer rl.unloadTexture(canvas_texture);
    rl.setTextureFilter(canvas_texture, .bilinear);

    var paint_model = try PaintModel.load(.sphere, canvas_texture);
    defer paint_model.unload();

    var current_tool: Tool = .paint;
    var active_color: rl.Color = .red;
    var brush_radius: i32 = 12;
    var last_hit_uv: ?rl.Vector2 = null;

    const ui_panel_rec: rl.Rectangle = .{ .x = 10.0, .y = 10.0, .width = 230.0, .height = 490.0 };

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const mouse_pos = rl.getMousePosition();
        const is_mouse_over_ui = rl.checkCollisionPointRec(mouse_pos, ui_panel_rec);

        if (rl.isMouseButtonDown(.right)) rl.updateCamera(&camera, .third_person);

        const hit_uv: ?rl.Vector2 = if (!is_mouse_over_ui and rl.isMouseButtonDown(.left))
            paint_model.hitUV(rl.getScreenToWorldRay(mouse_pos, camera))
        else
            null;

        if (hit_uv) |uv| {
            const px = canvasPixel(uv.x);
            const py = canvasPixel(uv.y);

            switch (current_tool) {
                .paint => {
                    // Stroke from the last hit to this one, guarding against jumps across a UV seam
                    const stroke_start: ?rl.Vector2 = if (last_hit_uv) |last|
                        if (@abs(uv.x - last.x) < 0.25 and @abs(uv.y - last.y) < 0.25) last else null
                    else
                        null;
                    if (stroke_start) |last| {
                        const last_px: f32 = @floatFromInt(canvasPixel(last.x));
                        const last_py: f32 = @floatFromInt(canvasPixel(last.y));
                        const fpx: f32 = @floatFromInt(px);
                        const fpy: f32 = @floatFromInt(py);
                        const dist = rl.math.vector2Distance(.{ .x = last_px, .y = last_py }, .{ .x = fpx, .y = fpy });
                        const steps: i32 = @as(i32, @intFromFloat(dist / 2.0)) + 1;

                        for (0..@intCast(steps + 1)) |i| {
                            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
                            const x: i32 = @intFromFloat(rl.math.lerp(last_px, fpx, t));
                            const y: i32 = @intFromFloat(rl.math.lerp(last_py, fpy, t));
                            rl.imageDrawCircle(&canvas_image, x, y, brush_radius, active_color);
                        }
                    } else {
                        rl.imageDrawCircle(&canvas_image, px, py, brush_radius, active_color);
                    }

                    rl.updateTexture(canvas_texture, canvas_image.data.?);
                    last_hit_uv = uv;
                },
                .picker => {
                    active_color = rl.getImageColor(canvas_image, px, py);
                    current_tool = .paint;
                    last_hit_uv = null;
                },
            }
        } else {
            last_hit_uv = null;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.{ .r = 30, .g = 32, .b = 40, .a = 255 });

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawModel(paint_model.model, rl.math.vector3Zero(), 1.0, .white);
            rl.drawGrid(10, 1.0);
        }

        // Side panel
        rl.drawRectangleRec(ui_panel_rec, rl.fade(.black, 0.8));
        rl.drawRectangleLinesEx(ui_panel_rec, 2.0, .dark_gray);
        rl.drawText("MESH UV PAINTER", 25, 22, 20, .gold);

        // Tool selection toggles
        var paint_active = current_tool == .paint;
        var picker_active = current_tool == .picker;
        if (gui.toggle(.{ .x = 25, .y = 55, .width = 95, .height = 32 }, "PAINT", &paint_active) != 0) current_tool = .paint;
        if (gui.toggle(.{ .x = 125, .y = 55, .width = 95, .height = 32 }, "PICKER", &picker_active) != 0) current_tool = .picker;

        // Shape selection toggles
        rl.drawText("Mesh Shape:", 25, 100, 10, .light_gray);
        const shape_before = paint_model.shape;
        for (shape_toggles) |toggle| {
            var active = shape_before == toggle.shape;
            if (gui.toggle(toggle.bounds, toggle.text, &active) != 0) {
                const new_model = try PaintModel.load(toggle.shape, canvas_texture);
                paint_model.unload();
                paint_model = new_model;
            }
        }

        // Color display
        rl.drawText("Active Color:", 25, 195, 10, .light_gray);
        rl.drawRectangle(125, 193, 95, 20, active_color);
        rl.drawRectangleLines(125, 193, 95, 20, .white);

        // Color swatches
        rl.drawText("Palette Swatches:", 25, 225, 10, .light_gray);
        for (palette, 0..) |color, i| {
            const column: f32 = @floatFromInt((i % 4) * 48);
            const row: f32 = @floatFromInt((i / 4) * 45);
            const swatch_rec: rl.Rectangle = .{ .x = 25.0 + column, .y = 245.0 + row, .width = 40.0, .height = 38.0 };
            rl.drawRectangleRec(swatch_rec, color);
            rl.drawRectangleLinesEx(swatch_rec, 1.0, .white);
            if (rl.checkCollisionPointRec(mouse_pos, swatch_rec) and rl.isMouseButtonPressed(.left)) active_color = color;
        }

        // Brush size buttons
        rl.drawText(rl.textFormat("Brush Size: {d}px", .{brush_radius}), 25, 345, 10, .light_gray);
        if (gui.button(.{ .x = 25, .y = 365, .width = 95, .height = 30 }, "SIZE -") != 0 and brush_radius > 2) brush_radius -= 2;
        if (gui.button(.{ .x = 125, .y = 365, .width = 95, .height = 30 }, "SIZE +") != 0 and brush_radius < 64) brush_radius += 2;

        // Canvas action buttons
        if (gui.button(.{ .x = 25, .y = 410, .width = 95, .height = 30 }, "CLEAR") != 0) {
            rl.imageClearBackground(&canvas_image, .ray_white);
            rl.updateTexture(canvas_texture, canvas_image.data.?);
        }
        if (gui.button(.{ .x = 125, .y = 410, .width = 95, .height = 30 }, "FILL") != 0) {
            rl.imageClearBackground(&canvas_image, active_color);
            rl.updateTexture(canvas_texture, canvas_image.data.?);
        }

        rl.drawText("Left click: paint / pick color   |   Right drag: orbit camera", 260, screen_height - 25, 10, .ray_white);
        rl.drawFPS(screen_width - 90, 15);
    }
}
