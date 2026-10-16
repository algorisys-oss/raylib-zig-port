//! raylib [others] example - scissor shapes
//!
//! Zig-API translation of examples/others/gl_scissor_shapes.c (raylib 6.2).
//! Example contributed by David Buzatto (@davidbuzatto) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2026 David Buzatto (@davidbuzatto)

const rl = @import("raylib");

// BeginScissorMode() only clips to an axis-aligned rectangle, since it maps
// directly to glScissor. Clipping to an arbitrary shape (the same idea as
// Graphics2D.setClip(Shape) in Java2D) needs the stencil buffer instead:
// the clip shape is rasterized into the stencil buffer first, then further
// draws are only let through where the stencil was written.
//
// rlgl has no stencil wrapper (see raysan5/raylib discussion #2964), so this
// example calls the handful of OpenGL 1.0 stencil functions directly - they
// don't need glad/extension loading, same as glScissor doesn't.
const gl = struct {
    const stencil_buffer_bit: u32 = 0x00000400;
    const stencil_test: u32 = 0x0B90;
    const always: u32 = 0x0207;
    const equal: u32 = 0x0202;
    const keep: u32 = 0x1E00;
    const replace: u32 = 0x1E01;

    extern "c" fn glClear(mask: u32) void;
    extern "c" fn glEnable(cap: u32) void;
    extern "c" fn glDisable(cap: u32) void;
    extern "c" fn glStencilMask(mask: u32) void;
    extern "c" fn glStencilFunc(func: u32, ref: i32, mask: u32) void;
    extern "c" fn glStencilOp(sfail: u32, dpfail: u32, dppass: u32) void;
};

/// `mask` is any value with a `draw()` method, so the clip region can be any
/// combination of draw* calls (circle, polygon, text, several shapes together).
fn beginScissorModeShape(mask: anytype) void {
    rl.gl.drawRenderBatchActive(); // Flush before touching stencil state
    gl.glClear(gl.stencil_buffer_bit);
    gl.glEnable(gl.stencil_test);
    gl.glStencilMask(0xFF);

    // Pass 1: rasterize the mask into the stencil buffer only, no color write
    rl.gl.colorMask(false, false, false, false);
    gl.glStencilFunc(gl.always, 1, 0xFF);
    gl.glStencilOp(gl.replace, gl.replace, gl.replace);
    mask.draw();
    rl.gl.drawRenderBatchActive(); // Flush the mask draw

    // Pass 2: subsequent draws only survive where the stencil was written
    rl.gl.colorMask(true, true, true, true);
    gl.glStencilFunc(gl.equal, 1, 0xFF);
    gl.glStencilOp(gl.keep, gl.keep, gl.keep);
}

fn endScissorModeShape() void {
    rl.gl.drawRenderBatchActive();
    gl.glDisable(gl.stencil_test);
}

// Two example mask shapes, drawn in WHITE (the color is irrelevant here,
// only the stencil write from pass 1 matters)
const CircleMask = struct {
    center: rl.Vector2,
    radius: f32,

    fn draw(m: CircleMask) void {
        rl.drawCircleV(m.center, m.radius, .white);
    }
};

const PolyMask = struct {
    center: rl.Vector2,
    radius: f32,
    sides: i32,

    fn draw(m: PolyMask) void {
        rl.drawPoly(m.center, m.sides, m.radius, 0.0, .white);
    }
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [others] example - scissor shapes");
    defer rl.closeWindow(); // Close window and OpenGL context

    var circle_center: rl.Vector2 = .{ .x = screen_width / 2.0 - 120, .y = screen_height / 2.0 };
    const hex_center: rl.Vector2 = .{ .x = screen_width / 2.0 + 120, .y = screen_height / 2.0 };
    const mask_radius: f32 = 100.0;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        circle_center.y = screen_height / 2.0 + @sin(@as(f32, @floatCast(rl.getTime()))) * 40.0;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Circle-shaped clip: the full-screen rectangle only shows inside the circle
        beginScissorModeShape(CircleMask{ .center = circle_center, .radius = mask_radius });
        rl.drawRectangle(0, 0, screen_width, screen_height, .blue);
        endScissorModeShape();

        // Hexagon-shaped clip: same mechanism, a different mask shape
        beginScissorModeShape(PolyMask{ .center = hex_center, .radius = mask_radius, .sides = 6 });
        rl.drawRectangle(0, 0, screen_width, screen_height, .orange);
        endScissorModeShape();

        rl.drawText("BeginScissorMode() only clips to a rectangle (glScissor)", 10, 10, 10, .dark_gray);
        rl.drawText("This clips to arbitrary shapes instead, using the stencil buffer", 10, 25, 10, .dark_gray);
    }
}
