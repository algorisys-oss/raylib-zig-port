//! raylib [core] example - viewport scaling
//!
//! Zig-API translation of examples/core/core_viewport_scaling.c (raylib 6.2).
//! Example contributed by Agnis Aldiņš (@nezvers) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Agnis Aldiņš (@nezvers)

const std = @import("std");
const rl = @import("raylib");

const ViewportType = enum {
    // Only upscale, useful for pixel art
    keep_aspect_integer,
    keep_height_integer,
    keep_width_integer,
    // Can also downscale
    keep_aspect,
    keep_height,
    keep_width,

    const count = @typeInfo(ViewportType).@"enum".field_names.len;

    /// For displaying on GUI
    fn name(viewport_type: ViewportType) [:0]const u8 {
        return switch (viewport_type) {
            .keep_aspect_integer => "KEEP_ASPECT_INTEGER",
            .keep_height_integer => "KEEP_HEIGHT_INTEGER",
            .keep_width_integer => "KEEP_WIDTH_INTEGER",
            .keep_aspect => "KEEP_ASPECT",
            .keep_height => "KEEP_HEIGHT",
            .keep_width => "KEEP_WIDTH",
        };
    }

    fn cycle(viewport_type: ViewportType, step: usize) ViewportType {
        return @fromBackingInt(@intCast((@backingInt(viewport_type) + step) % count));
    }
};

/// Source (render texture) and destination (screen) rectangles of the scaled viewport.
const Viewport = struct {
    source: rl.Rectangle,
    dest: rl.Rectangle,
};

/// The scaled game view: the window size it was computed for, the game
/// resolution, the scaling rule and the render texture the game draws to.
const Scaler = struct {
    screen_width: i32,
    screen_height: i32,
    game_width: i32,
    game_height: i32,
    viewport_type: ViewportType,
    viewport: Viewport,
    target: rl.RenderTexture2D,

    /// Recompute the viewport for the current window size and recreate the render texture
    fn resize(scaler: *Scaler) !void {
        scaler.screen_width = rl.getScreenWidth();
        scaler.screen_height = rl.getScreenHeight();

        const rule: *const fn (i32, i32, i32, i32) Viewport = switch (scaler.viewport_type) {
            .keep_aspect_integer => keepAspectCenteredInteger,
            .keep_height_integer => keepHeightCenteredInteger,
            .keep_width_integer => keepWidthCenteredInteger,
            .keep_aspect => keepAspectCentered,
            .keep_height => keepHeightCentered,
            .keep_width => keepWidthCentered,
        };
        scaler.viewport = rule(scaler.screen_width, scaler.screen_height, scaler.game_width, scaler.game_height);

        rl.unloadRenderTexture(scaler.target);
        const source = scaler.viewport.source;
        scaler.target = try rl.loadRenderTexture(@intFromFloat(source.width), -@as(i32, @intFromFloat(source.height)));
    }
};

pub fn main() !void {
    // Initialization
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(800, 450, "raylib [core] example - viewport scaling");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Preset resolutions that could be created by subdividing screen resolution
    const resolution_list = [_]rl.Vector2{
        .{ .x = 64, .y = 64 },
        .{ .x = 256, .y = 240 },
        .{ .x = 320, .y = 180 },
        // 4K doesn't work with integer scaling but included for example purposes with non-integer scaling
        .{ .x = 3840, .y = 2160 },
    };

    var resolution_index: usize = 0;

    var scaler: Scaler = .{
        .screen_width = 800,
        .screen_height = 450,
        .game_width = 64,
        .game_height = 64,
        .viewport_type = .keep_aspect_integer,
        .viewport = undefined,
        .target = std.mem.zeroes(rl.RenderTexture2D),
    };
    try scaler.resize();
    defer rl.unloadRenderTexture(scaler.target);

    // Button rectangles
    const decrease_resolution_button: rl.Rectangle = .{ .x = 200, .y = 30, .width = 10, .height = 10 };
    const increase_resolution_button: rl.Rectangle = .{ .x = 215, .y = 30, .width = 10, .height = 10 };
    const decrease_type_button: rl.Rectangle = .{ .x = 200, .y = 45, .width = 10, .height = 10 };
    const increase_type_button: rl.Rectangle = .{ .x = 215, .y = 45, .width = 10, .height = 10 };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isWindowResized()) try scaler.resize();

        const mouse_position = rl.getMousePosition();
        const mouse_pressed = rl.isMouseButtonPressed(.left);

        // Check buttons and rescale
        if (rl.checkCollisionPointRec(mouse_position, decrease_resolution_button) and mouse_pressed) {
            resolution_index = (resolution_index + resolution_list.len - 1) % resolution_list.len;
            scaler.game_width = @intFromFloat(resolution_list[resolution_index].x);
            scaler.game_height = @intFromFloat(resolution_list[resolution_index].y);
            try scaler.resize();
        }

        if (rl.checkCollisionPointRec(mouse_position, increase_resolution_button) and mouse_pressed) {
            resolution_index = (resolution_index + 1) % resolution_list.len;
            scaler.game_width = @intFromFloat(resolution_list[resolution_index].x);
            scaler.game_height = @intFromFloat(resolution_list[resolution_index].y);
            try scaler.resize();
        }

        if (rl.checkCollisionPointRec(mouse_position, decrease_type_button) and mouse_pressed) {
            scaler.viewport_type = scaler.viewport_type.cycle(ViewportType.count - 1);
            try scaler.resize();
        }

        if (rl.checkCollisionPointRec(mouse_position, increase_type_button) and mouse_pressed) {
            scaler.viewport_type = scaler.viewport_type.cycle(1);
            try scaler.resize();
        }

        const source_rect = scaler.viewport.source;
        const dest_rect = scaler.viewport.dest;
        const texture_mouse_position = screenToRenderTexturePosition(mouse_position, source_rect, dest_rect);

        // Draw
        // Draw our scene to the render texture
        {
            rl.beginTextureMode(scaler.target);
            defer rl.endTextureMode();

            rl.clearBackground(.white);
            rl.drawCircleV(texture_mouse_position, 20.0, .lime);
        }

        // Draw render texture to main framebuffer
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        // Draw our render texture with rotation applied
        rl.drawTexturePro(scaler.target.texture, source_rect, dest_rect, .{ .x = 0.0, .y = 0.0 }, 0.0, .white);

        // Draw Native resolution (GUI or anything)
        // Draw info box
        const info_rect: rl.Rectangle = .{ .x = 5, .y = 5, .width = 330, .height = 105 };
        rl.drawRectangleRec(info_rect, rl.fade(.light_gray, 0.7));
        rl.drawRectangleLinesEx(info_rect, 1, .blue);

        rl.drawText(rl.textFormat("Window Resolution: {d} x {d}", .{ scaler.screen_width, scaler.screen_height }), 15, 15, 10, .black);
        rl.drawText(rl.textFormat("Game Resolution: {d} x {d}", .{ scaler.game_width, scaler.game_height }), 15, 30, 10, .black);

        rl.drawText(rl.textFormat("Type: {s}", .{scaler.viewport_type.name()}), 15, 45, 10, .black);
        const scale_ratio: rl.Vector2 = .{ .x = dest_rect.width / source_rect.width, .y = -dest_rect.height / source_rect.height };
        if (scale_ratio.x < 0.001 or scale_ratio.y < 0.001) {
            rl.drawText("Scale ratio: INVALID", 15, 60, 10, .black);
        } else {
            rl.drawText(rl.textFormat("Scale ratio: {d:.2} x {d:.2}", .{ scale_ratio.x, scale_ratio.y }), 15, 60, 10, .black);
        }

        rl.drawText(rl.textFormat("Source size: {d:.2} x {d:.2}", .{ source_rect.width, -source_rect.height }), 15, 75, 10, .black);
        rl.drawText(rl.textFormat("Destination size: {d:.2} x {d:.2}", .{ dest_rect.width, dest_rect.height }), 15, 90, 10, .black);

        // Draw buttons
        rl.drawRectangleRec(decrease_type_button, .sky_blue);
        rl.drawRectangleRec(increase_type_button, .sky_blue);
        rl.drawRectangleRec(decrease_resolution_button, .sky_blue);
        rl.drawRectangleRec(increase_resolution_button, .sky_blue);
        drawButtonLabel("<", decrease_type_button);
        drawButtonLabel(">", increase_type_button);
        drawButtonLabel("<", decrease_resolution_button);
        drawButtonLabel(">", increase_resolution_button);
    }
}

fn drawButtonLabel(label: [:0]const u8, button: rl.Rectangle) void {
    rl.drawText(label, @as(i32, @intFromFloat(button.x)) + 3, @as(i32, @intFromFloat(button.y)) + 1, 10, .black);
}

/// C's `(float)(int)x`: truncate toward zero through an integer (so -0.5 gives +0.0).
fn truncate(x: f32) f32 {
    return @floatFromInt(@as(i32, @intFromFloat(x)));
}

fn float(x: i32) f32 {
    return @floatFromInt(x);
}

fn keepAspectCenteredInteger(screen_width: i32, screen_height: i32, game_width: i32, game_height: i32) Viewport {
    const ratio_x = @divTrunc(screen_width, game_width);
    const ratio_y = @divTrunc(screen_height, game_height);
    const resize_ratio = float(@min(ratio_x, ratio_y));

    return .{
        .source = .{ .x = 0.0, .y = float(game_height), .width = float(game_width), .height = float(-game_height) },
        .dest = .{
            .x = truncate((float(screen_width) - float(game_width) * resize_ratio) * 0.5),
            .y = truncate((float(screen_height) - float(game_height) * resize_ratio) * 0.5),
            .width = truncate(float(game_width) * resize_ratio),
            .height = truncate(float(game_height) * resize_ratio),
        },
    };
}

fn keepHeightCenteredInteger(screen_width: i32, screen_height: i32, _: i32, game_height: i32) Viewport {
    const resize_ratio = float(screen_height) / float(game_height);
    const source_width = truncate(float(screen_width) / resize_ratio);

    return .{
        .source = .{ .x = 0.0, .y = 0.0, .width = source_width, .height = float(-game_height) },
        .dest = .{
            .x = truncate((float(screen_width) - source_width * resize_ratio) * 0.5),
            .y = truncate((float(screen_height) - float(game_height) * resize_ratio) * 0.5),
            .width = truncate(source_width * resize_ratio),
            .height = truncate(float(game_height) * resize_ratio),
        },
    };
}

fn keepWidthCenteredInteger(screen_width: i32, screen_height: i32, game_width: i32, _: i32) Viewport {
    const resize_ratio = float(screen_width) / float(game_width);
    const source_height = truncate(float(screen_height) / resize_ratio);

    return .{
        .source = .{ .x = 0.0, .y = 0.0, .width = float(game_width), .height = source_height * -1.0 },
        .dest = .{
            .x = truncate((float(screen_width) - float(game_width) * resize_ratio) * 0.5),
            .y = truncate((float(screen_height) - source_height * resize_ratio) * 0.5),
            .width = truncate(float(game_width) * resize_ratio),
            .height = truncate(source_height * resize_ratio),
        },
    };
}

fn keepAspectCentered(screen_width: i32, screen_height: i32, game_width: i32, game_height: i32) Viewport {
    const ratio_x = float(screen_width) / float(game_width);
    const ratio_y = float(screen_height) / float(game_height);
    const resize_ratio = @min(ratio_x, ratio_y);

    return .{
        .source = .{ .x = 0.0, .y = float(game_height), .width = float(game_width), .height = float(-game_height) },
        .dest = .{
            .x = truncate((float(screen_width) - float(game_width) * resize_ratio) * 0.5),
            .y = truncate((float(screen_height) - float(game_height) * resize_ratio) * 0.5),
            .width = truncate(float(game_width) * resize_ratio),
            .height = truncate(float(game_height) * resize_ratio),
        },
    };
}

fn keepHeightCentered(screen_width: i32, screen_height: i32, _: i32, game_height: i32) Viewport {
    const resize_ratio = float(screen_height) / float(game_height);
    const source_width = truncate(float(screen_width) / resize_ratio);

    return .{
        .source = .{ .x = 0.0, .y = 0.0, .width = source_width, .height = float(-game_height) },
        .dest = .{
            .x = truncate((float(screen_width) - source_width * resize_ratio) * 0.5),
            .y = truncate((float(screen_height) - float(game_height) * resize_ratio) * 0.5),
            .width = truncate(source_width * resize_ratio),
            .height = truncate(float(game_height) * resize_ratio),
        },
    };
}

fn keepWidthCentered(screen_width: i32, screen_height: i32, game_width: i32, _: i32) Viewport {
    const resize_ratio = float(screen_width) / float(game_width);
    const source_height = truncate(float(screen_height) / resize_ratio);

    return .{
        .source = .{ .x = 0.0, .y = 0.0, .width = float(game_width), .height = source_height * -1.0 },
        .dest = .{
            .x = truncate((float(screen_width) - float(game_width) * resize_ratio) * 0.5),
            .y = truncate((float(screen_height) - source_height * resize_ratio) * 0.5),
            .width = truncate(float(game_width) * resize_ratio),
            .height = truncate(source_height * resize_ratio),
        },
    };
}

/// Example how to calculate position on RenderTexture
fn screenToRenderTexturePosition(point: rl.Vector2, texture_rect: rl.Rectangle, scaled_rect: rl.Rectangle) rl.Vector2 {
    const relative_position: rl.Vector2 = .{ .x = point.x - scaled_rect.x, .y = point.y - scaled_rect.y };
    const ratio: rl.Vector2 = .{ .x = texture_rect.width / scaled_rect.width, .y = -texture_rect.height / scaled_rect.height };

    return .{ .x = relative_position.x * ratio.x, .y = relative_position.y * ratio.x };
}
