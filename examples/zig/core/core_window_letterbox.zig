//! raylib [core] example - window letterbox
//!
//! Zig-API translation of examples/core/core_window_letterbox.c (raylib 6.2).
//! Example contributed by Anata (@anatagawa) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Anata (@anatagawa) and Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const game_screen_width = 640;
const game_screen_height = 480;

pub fn main() !void {
    const screen_width = 800;
    const screen_height = 450;

    // Enable config flags for resizable window and vertical synchro
    rl.setConfigFlags(.{ .window_resizable = true, .vsync_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [core] example - window letterbox");
    defer rl.closeWindow(); // Close window and OpenGL context
    rl.setWindowMinSize(320, 240);

    // Render texture initialization, used to hold the rendering result so we can easily resize it
    const target = try rl.loadRenderTexture(game_screen_width, game_screen_height);
    defer rl.unloadRenderTexture(target); // Unload render texture
    rl.setTextureFilter(target.texture, .bilinear); // Texture scale filter to use

    var colors: [10]rl.Color = undefined;
    randomizeColors(&colors);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Compute required framebuffer scaling
        const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
        const scale = @min(screen_w / game_screen_width, screen_h / game_screen_height);

        if (rl.isKeyPressed(.space)) {
            // Recalculate random colors for the bars
            randomizeColors(&colors);
        }

        // Update virtual mouse (clamped mouse value behind game screen)
        const mouse = rl.getMousePosition();
        var virtual_mouse: rl.Vector2 = .{
            .x = (mouse.x - (screen_w - game_screen_width * scale) * 0.5) / scale,
            .y = (mouse.y - (screen_h - game_screen_height * scale) * 0.5) / scale,
        };
        virtual_mouse = rl.math.vector2Clamp(virtual_mouse, .{ .x = 0, .y = 0 }, .{ .x = game_screen_width, .y = game_screen_height });

        // Apply the same transformation as the virtual mouse to the real mouse (i.e. to work with raygui)
        //rl.setMouseOffset(-(screen_w - (game_screen_width*scale))*0.5, -(screen_h - (game_screen_height*scale))*0.5);
        //rl.setMouseScale(1/scale, 1/scale);

        // Draw
        // Draw everything in the render texture, note this will not be rendered on screen, yet
        {
            rl.beginTextureMode(target);
            defer rl.endTextureMode();

            rl.clearBackground(.ray_white); // Clear render texture background color

            for (colors, 0..) |color, i| {
                const bar_height = game_screen_height / 10;
                rl.drawRectangle(0, bar_height * @as(i32, @intCast(i)), game_screen_width, bar_height, color);
            }

            rl.drawText("If executed inside a window,\nyou can resize the window,\nand see the screen scaling!", 10, 25, 20, .white);
            rl.drawText(rl.textFormat("Default Mouse: [{d} , {d}]", .{
                @as(i32, @intFromFloat(mouse.x)),
                @as(i32, @intFromFloat(mouse.y)),
            }), 350, 25, 20, .green);
            rl.drawText(rl.textFormat("Virtual Mouse: [{d} , {d}]", .{
                @as(i32, @intFromFloat(virtual_mouse.x)),
                @as(i32, @intFromFloat(virtual_mouse.y)),
            }), 350, 55, 20, .yellow);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black); // Clear screen background

        // Draw render texture to screen, properly scaled
        const texture_width: f32 = @floatFromInt(target.texture.width);
        const texture_height: f32 = @floatFromInt(target.texture.height);
        rl.drawTexturePro(
            target.texture,
            .{ .x = 0.0, .y = 0.0, .width = texture_width, .height = -texture_height },
            .{
                .x = (screen_w - game_screen_width * scale) * 0.5,
                .y = (screen_h - game_screen_height * scale) * 0.5,
                .width = game_screen_width * scale,
                .height = game_screen_height * scale,
            },
            .{ .x = 0, .y = 0 },
            0.0,
            .white,
        );
    }
}

fn randomizeColors(colors: []rl.Color) void {
    for (colors) |*color| color.* = .{
        .r = @intCast(rl.getRandomValue(100, 250)),
        .g = @intCast(rl.getRandomValue(50, 150)),
        .b = @intCast(rl.getRandomValue(10, 100)),
        .a = 255,
    };
}
