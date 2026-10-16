//! raylib [textures] example - magnifying glass
//!
//! Zig-API translation of examples/textures/textures_magnifying_glass.c (raylib 6.2).
//! Example contributed by Luke Vaughan (@badram) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 Luke Vaughan (@badram)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - magnifying glass");
    defer rl.closeWindow(); // Close window and OpenGL context

    const bunny = try rl.loadTexture("resources/raybunny.png");
    defer rl.unloadTexture(bunny);
    const parrots = try rl.loadTexture("resources/parrots.png");
    defer rl.unloadTexture(parrots);

    // Use image draw to generate a mask texture instead of loading it from a file.
    var circle = rl.genImageColor(256, 256, .blank);
    rl.imageDrawCircle(&circle, 128, 128, 128, .white);
    const mask = try rl.loadTextureFromImage(circle); // Copy the mask image from RAM to VRAM
    defer rl.unloadTexture(mask);
    rl.unloadImage(circle); // Unload the image from RAM

    const magnified_world = try rl.loadRenderTexture(256, 256);
    defer rl.unloadRenderTexture(magnified_world);

    var camera: rl.Camera2D = .{
        // Offset by half the size of the magnifying glass to counteract drawing the texture centered on the mouse position
        .offset = rl.math.vector2Multiply(.{ .x = 128, .y = 128 }, rl.getWindowScaleDPI()),
        .target = .{ .x = 0, .y = 0 },
        .rotation = 0,
        // Set magnifying glass zoom
        .zoom = 2,
    };

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        const m_pos = rl.getMousePosition();
        camera.target = m_pos;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw the normal version of the world
        rl.drawTexture(parrots, 144, 33, .white);
        rl.drawText("Use the magnifying glass to find hidden bunnies!", 154, 6, 20, .black);

        // Render to a the magnifying glass
        {
            rl.beginTextureMode(magnified_world);
            defer rl.endTextureMode();

            rl.clearBackground(.ray_white);

            {
                rl.beginMode2D(camera);
                defer rl.endMode2D();

                // Draw the same things in the magnified world as were in the normal version
                rl.drawTexture(parrots, 144, 33, .white);
                rl.drawText("Use the magnifying glass to find hidden bunnies!", 154, 6, 20, .black);

                // Draw bunnies only in the magnified world.
                // BLEND_MULTIPLIED lets them take on the color of the image below them.
                rl.beginBlendMode(.multiplied);
                defer rl.endBlendMode();

                rl.drawTexture(bunny, 250, 350, .white);
                rl.drawTexture(bunny, 500, 100, .white);
                rl.drawTexture(bunny, 420, 300, .white);
                rl.drawTexture(bunny, 650, 10, .white);
            }

            // Mask the magnifying glass view texture to a circle
            // To make the mask affect only alpha, a CUSTOM blend mode is used with SEPARATE color/alpha functions
            rl.beginBlendMode(.custom_separate);
            defer rl.endBlendMode();

            // C: Color, A: Alpha, s: source (texture to draw), d: destination (texture drawn to)
            //   glSrcRGB: RL_ZERO      - Cs * 0 = 0  - discard source rgb because we don't want to draw our texture's colors at all
            //   glDstRGB: RL_ONE       - Cd * 1 = Cd - use destination colors unmodified
            //   glSrcAlpha: RL_ONE     - As * 1 = As - use source alpha unmodified
            //   glDstAlpha: RL_ZERO    - Ad * 0 = 0  - discard destination alpha
            //   glEqRGB: RL_FUNC_ADD   - Cs(0) + Cd = Cd - destination color is unmodified
            //   glEqAlpha: RL_FUNC_ADD - As + Ad(0) = As - destination alpha is set to source alpha
            rl.gl.setBlendFactorsSeparate(rl.gl.zero, rl.gl.one, rl.gl.one, rl.gl.zero, rl.gl.func_add, rl.gl.func_add);
            rl.drawTexture(mask, 0, 0, .white);
        }

        // Draw magnifiedWorld to screen, centered on cursor
        rl.drawTextureRec(magnified_world.texture, .{ .x = 0, .y = 0, .width = 256, .height = -256 }, .{ .x = m_pos.x - 128, .y = m_pos.y - 128 }, .white);

        // Draw the outer ring of the magnifying glass
        rl.drawRing(m_pos, 126, 130, 0, 360, 64, .black);

        // Draw floating specular highlight on the glass
        const rx = m_pos.x / 800;
        const ry = m_pos.y / 800;
        const highlight_x: i32 = @intFromFloat(m_pos.x - 64 * rx);
        const highlight_y: i32 = @intFromFloat(m_pos.y - 64 * ry);
        rl.drawCircle(highlight_x - 32, highlight_y - 32, 4, rl.colorAlpha(.white, 0.5));
    }
}
