//! raylib [textures] example - srcrec dstrec
//!
//! Zig-API translation of examples/textures/textures_srcrec_dstrec.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [textures] example - srcrec dstrec");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)
    const scarfy = try rl.loadTexture("resources/scarfy.png"); // Texture loading
    defer rl.unloadTexture(scarfy); // Texture unloading

    const frame_width: f32 = @floatFromInt(@divTrunc(scarfy.width, 6));
    const frame_height: f32 = @floatFromInt(scarfy.height);

    // Source rectangle (part of the texture to use for drawing)
    const source_rec: rl.Rectangle = .{ .x = 0.0, .y = 0.0, .width = frame_width, .height = frame_height };

    // Destination rectangle (screen rectangle where drawing part of texture)
    const dest_rec: rl.Rectangle = .{ .x = screen_width / 2.0, .y = screen_height / 2.0, .width = frame_width * 2.0, .height = frame_height * 2.0 };

    // Origin of the texture (rotation/scale point), it's relative to destination rectangle size
    const origin: rl.Vector2 = .{ .x = frame_width, .y = frame_height };

    var rotation: i32 = 0;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rotation += 1;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // NOTE: Using DrawTexturePro() we can easily rotate and scale the part of the texture we draw
        // sourceRec defines the part of the texture we use for drawing
        // destRec defines the rectangle where our texture part will fit (scaling it to fit)
        // origin defines the point of the texture used as reference for rotation and scaling
        // rotation defines the texture rotation (using origin as rotation point)
        rl.drawTexturePro(scarfy, source_rec, dest_rec, origin, @floatFromInt(rotation), .white);

        rl.drawLine(@intFromFloat(dest_rec.x), 0, @intFromFloat(dest_rec.x), screen_height, .gray);
        rl.drawLine(0, @intFromFloat(dest_rec.y), screen_width, @intFromFloat(dest_rec.y), .gray);

        rl.drawText("(c) Scarfy sprite by Eiden Marsal", screen_width - 200, screen_height - 20, 10, .gray);
    }
}
