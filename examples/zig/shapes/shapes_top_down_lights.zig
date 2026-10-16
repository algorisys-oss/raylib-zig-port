//! raylib [shapes] example - top down lights
//!
//! Zig-API translation of examples/shapes/shapes_top_down_lights.c (raylib 6.2).
//! Example contributed by Jeffery Myers (@JeffM2501) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2022-2025 Jeffery Myers (@JeffM2501)

const rl = @import("raylib");

// Custom Blend Modes
const rlgl_src_alpha = 0x0302;
const rlgl_min = 0x8007;
const rlgl_max = 0x8008;

const max_boxes = 20;
const max_shadows = max_boxes * 3; // Each box can cast up to two shadow volumes for the edges it is away from, and one for the box itself
const max_lights = 16;

/// Shadow geometry: a quad
const ShadowGeometry = [4]rl.Vector2;

/// Light info type
const Light = struct {
    mask: ?rl.RenderTexture = null, // Alpha mask for the light (null: this light slot is not active)
    dirty: bool = false, // Does this light need to be updated?
    valid: bool = false, // Is this light in a valid position?

    position: rl.Vector2 = .{ .x = 0, .y = 0 }, // Light position
    outer_radius: f32 = 0, // The distance the light touches
    bounds: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 }, // A cached rectangle of the light bounds to help with culling

    shadows: [max_shadows]ShadowGeometry = undefined,
    shadow_count: usize = 0,

    /// Setup a light
    fn setup(light: *Light, x: f32, y: f32, radius: f32) !void {
        light.valid = false; // The light must prove it is valid
        light.mask = try rl.loadRenderTexture(rl.getScreenWidth(), rl.getScreenHeight());
        light.outer_radius = radius;

        light.bounds.width = radius * 2;
        light.bounds.height = radius * 2;

        light.move(x, y);

        // Force the render texture to have something in it
        light.drawMask();
    }

    /// Move a light and mark it as dirty so that we update it's mask next frame
    fn move(light: *Light, x: f32, y: f32) void {
        light.dirty = true;
        light.position = .{ .x = x, .y = y };

        // update the cached bounds
        light.bounds.x = x - light.outer_radius;
        light.bounds.y = y - light.outer_radius;
    }

    /// Compute a shadow volume for the edge
    /// It takes the edge and projects it back by the light radius and turns it into a quad
    fn computeShadowVolumeForEdge(light: *Light, sp: rl.Vector2, ep: rl.Vector2) void {
        if (light.shadow_count >= max_shadows) return;

        const extension = light.outer_radius * 2;

        const sp_vector = rl.math.vector2Normalize(rl.math.vector2Subtract(sp, light.position));
        const sp_projection = rl.math.vector2Add(sp, rl.math.vector2Scale(sp_vector, extension));

        const ep_vector = rl.math.vector2Normalize(rl.math.vector2Subtract(ep, light.position));
        const ep_projection = rl.math.vector2Add(ep, rl.math.vector2Scale(ep_vector, extension));

        light.shadows[light.shadow_count] = .{ sp, ep, ep_projection, sp_projection };
        light.shadow_count += 1;
    }

    /// See if a light needs to update it's mask
    fn update(light: *Light, boxes: []const rl.Rectangle) bool {
        if (light.mask == null or !light.dirty) return false;

        light.dirty = false;
        light.shadow_count = 0;
        light.valid = false;

        for (boxes) |box| {
            // Are we in a box? if so we are not valid
            if (rl.checkCollisionPointRec(light.position, box)) return false;

            // If this box is outside our bounds, we can skip it
            if (!rl.checkCollisionRecs(light.bounds, box)) continue;

            // Check the edges that are on the same side we are, and cast shadow volumes out from them

            // Top
            var sp: rl.Vector2 = .{ .x = box.x, .y = box.y };
            var ep: rl.Vector2 = .{ .x = box.x + box.width, .y = box.y };

            if (light.position.y > ep.y) light.computeShadowVolumeForEdge(sp, ep);

            // Right
            sp = ep;
            ep.y += box.height;
            if (light.position.x < ep.x) light.computeShadowVolumeForEdge(sp, ep);

            // Bottom
            sp = ep;
            ep.x -= box.width;
            if (light.position.y < ep.y) light.computeShadowVolumeForEdge(sp, ep);

            // Left
            sp = ep;
            ep.y -= box.height;
            if (light.position.x > ep.x) light.computeShadowVolumeForEdge(sp, ep);

            // The box itself
            light.shadows[light.shadow_count] = .{
                .{ .x = box.x, .y = box.y },
                .{ .x = box.x, .y = box.y + box.height },
                .{ .x = box.x + box.width, .y = box.y + box.height },
                .{ .x = box.x + box.width, .y = box.y },
            };
            light.shadow_count += 1;
        }

        light.valid = true;

        light.drawMask();

        return true;
    }

    /// Draw the light and shadows to the mask for a light
    fn drawMask(light: *const Light) void {
        // Use the light mask
        rl.beginTextureMode(light.mask.?);
        defer rl.endTextureMode();

        rl.clearBackground(.white);

        // Force the blend mode to only set the alpha of the destination
        rl.gl.setBlendFactors(rlgl_src_alpha, rlgl_src_alpha, rlgl_min);
        rl.gl.setBlendMode(rl.gl.blend_custom);

        // If we are valid, then draw the light radius to the alpha mask
        if (light.valid) rl.drawCircleGradient(light.position, light.outer_radius, rl.colorAlpha(.white, 0), .white);

        rl.gl.drawRenderBatchActive();

        // Cut out the shadows from the light radius by forcing the alpha to maximum
        rl.gl.setBlendMode(rl.gl.blend_alpha);
        rl.gl.setBlendFactors(rlgl_src_alpha, rlgl_src_alpha, rlgl_max);
        rl.gl.setBlendMode(rl.gl.blend_custom);

        // Draw the shadows to the alpha mask
        for (light.shadows[0..light.shadow_count]) |*shadow| rl.drawTriangleFan(shadow, .white);

        rl.gl.drawRenderBatchActive();

        // Go back to normal blend mode
        rl.gl.setBlendMode(rl.gl.blend_alpha);
    }
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - top down lights");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Initialize our 'world' of boxes
    const boxes = setupBoxes();

    // Create a checkerboard ground texture
    const img = rl.genImageChecked(64, 64, 32, 32, .dark_brown, .dark_gray);
    const background_texture = try rl.loadTextureFromImage(img);
    defer rl.unloadTexture(background_texture);
    rl.unloadImage(img);

    // Create a global light mask to hold all the blended lights
    const light_mask = try rl.loadRenderTexture(rl.getScreenWidth(), rl.getScreenHeight());
    defer rl.unloadRenderTexture(light_mask);

    var lights: [max_lights]Light = @splat(.{});
    defer for (lights) |light| {
        if (light.mask) |mask| rl.unloadRenderTexture(mask);
    };

    // Setup initial light
    try lights[0].setup(600, 400, 300);
    var next_light: usize = 1;

    var show_lines = false;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Drag light 0
        if (rl.isMouseButtonDown(.left)) lights[0].move(rl.getMousePosition().x, rl.getMousePosition().y);

        // Make a new light
        if (rl.isMouseButtonPressed(.right) and next_light < max_lights) {
            try lights[next_light].setup(rl.getMousePosition().x, rl.getMousePosition().y, 200);
            next_light += 1;
        }

        // Toggle debug info
        if (rl.isKeyPressed(.f1)) show_lines = !show_lines;

        // Update the lights and keep track if any were dirty so we know if we need to update the master light mask
        var dirty_lights = false;
        for (&lights) |*light| {
            if (light.update(&boxes)) dirty_lights = true;
        }

        const screen_rec: rl.Rectangle = .{ .x = 0, .y = 0, .width = @floatFromInt(rl.getScreenWidth()), .height = @floatFromInt(rl.getScreenHeight()) };
        const flipped_screen_rec: rl.Rectangle = .{ .x = 0, .y = 0, .width = screen_rec.width, .height = -screen_rec.height };

        // Update the light mask
        if (dirty_lights) {
            // Build up the light mask
            rl.beginTextureMode(light_mask);
            defer rl.endTextureMode();

            rl.clearBackground(.black);

            // Force the blend mode to only set the alpha of the destination
            rl.gl.setBlendFactors(rlgl_src_alpha, rlgl_src_alpha, rlgl_min);
            rl.gl.setBlendMode(rl.gl.blend_custom);

            // Merge in all the light masks
            for (lights) |light| {
                if (light.mask) |mask| rl.drawTextureRec(mask.texture, flipped_screen_rec, rl.math.vector2Zero(), .white);
            }

            rl.gl.drawRenderBatchActive();

            // Go back to normal blend
            rl.gl.setBlendMode(rl.gl.blend_alpha);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        // Draw the tile background
        rl.drawTextureRec(background_texture, screen_rec, rl.math.vector2Zero(), .white);

        // Overlay the shadows from all the lights
        rl.drawTextureRec(light_mask.texture, flipped_screen_rec, rl.math.vector2Zero(), rl.colorAlpha(.white, if (show_lines) 0.75 else 1.0));

        // Draw the lights
        for (lights, 0..) |light, i| {
            if (light.mask != null) {
                rl.drawCircle(@intFromFloat(light.position.x), @intFromFloat(light.position.y), 10, if (i == 0) .yellow else .white);
            }
        }

        if (show_lines) {
            for (lights[0].shadows[0..lights[0].shadow_count]) |*shadow| {
                rl.drawTriangleFan(shadow, .dark_purple);
            }

            for (boxes) |box| {
                if (rl.checkCollisionRecs(box, lights[0].bounds)) rl.drawRectangleRec(box, .purple);

                rl.drawRectangleLines(@intFromFloat(box.x), @intFromFloat(box.y), @intFromFloat(box.width), @intFromFloat(box.height), .dark_blue);
            }

            rl.drawText("(F1) Hide Shadow Volumes", 10, 50, 10, .green);
        } else {
            rl.drawText("(F1) Show Shadow Volumes", 10, 50, 10, .green);
        }

        rl.drawFPS(screen_width - 80, 10);
        rl.drawText("Drag to move light #1", 10, 10, 10, .dark_green);
        rl.drawText("Right click to add new light", 10, 30, 10, .dark_green);
    }
}

/// Set up some boxes
fn setupBoxes() [max_boxes]rl.Rectangle {
    var boxes: [max_boxes]rl.Rectangle = undefined;
    boxes[0..5].* = .{
        .{ .x = 150, .y = 80, .width = 40, .height = 40 },
        .{ .x = 1200, .y = 700, .width = 40, .height = 40 },
        .{ .x = 200, .y = 600, .width = 40, .height = 40 },
        .{ .x = 1000, .y = 50, .width = 40, .height = 40 },
        .{ .x = 500, .y = 350, .width = 40, .height = 40 },
    };

    for (boxes[5..]) |*box| {
        box.* = .{
            .x = @floatFromInt(rl.getRandomValue(0, rl.getScreenWidth())),
            .y = @floatFromInt(rl.getRandomValue(0, rl.getScreenHeight())),
            .width = @floatFromInt(rl.getRandomValue(10, 100)),
            .height = @floatFromInt(rl.getRandomValue(10, 100)),
        };
    }

    return boxes;
}
