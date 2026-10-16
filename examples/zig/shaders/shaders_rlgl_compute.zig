//! raylib [shaders] example - rlgl compute
//!
//! Zig-API translation of examples/shaders/shaders_rlgl_compute.c (raylib 6.2).
//! Example contributed by Teddy Astie (@tsnake41) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2021-2025 Teddy Astie (@tsnake41)

const std = @import("std");
const rl = @import("raylib");

// IMPORTANT: This must match gol*.glsl GOL_WIDTH constant
// This must be a multiple of 16 (check golLogic compute dispatch)
const gol_width = 768;

// Maximum amount of queued draw commands (squares draw from mouse down events)
const max_buffered_transferts = 48;

/// Game Of Life Update Command
const GolUpdateCmd = extern struct {
    x: u32, // x coordinate of the gol command
    y: u32, // y coordinate of the gol command
    w: u32, // width of the filled zone
    enabled: u32, // whether to enable or disable zone
};

/// Game Of Life Update Commands SSBO
const GolUpdateSSBO = extern struct {
    count: u32 = 0,
    commands: [max_buffered_transferts]GolUpdateCmd = std.mem.zeroes([max_buffered_transferts]GolUpdateCmd),
};

/// Load a compute shader program from a GLSL file; returns the shader and program ids.
fn loadComputeProgram(file_name: [:0]const u8) !struct { shader: u32, program: u32 } {
    const code = try rl.loadFileText(file_name);
    defer rl.unloadFileText(code);
    const shader = rl.gl.loadShader(code, rl.gl.compute_shader);
    return .{ .shader = shader, .program = rl.gl.loadShaderProgramCompute(shader) };
}

pub fn main() !void {
    // Initialization
    const screen_width = gol_width;
    const screen_height = gol_width;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - rlgl compute");
    defer rl.closeWindow(); // Close window and OpenGL context

    const resolution: rl.Vector2 = .{ .x = screen_width, .y = screen_height };
    var brush_size: u32 = 8;

    // Game of Life logic compute shader
    const gol_logic = try loadComputeProgram("resources/shaders/glsl430/gol.glsl");
    defer rl.gl.unloadShaderProgram(gol_logic.program);
    defer rl.gl.unloadShader(gol_logic.shader);

    // Game of Life logic render shader
    const gol_render_shader = try rl.loadShader(null, "resources/shaders/glsl430/gol_render.glsl");
    defer rl.unloadShader(gol_render_shader); // Unload rendering fragment shader
    const res_uniform_loc = rl.getShaderLocation(gol_render_shader, "resolution");

    // Game of Life transfert shader (CPU<->GPU download and upload)
    const gol_transfert = try loadComputeProgram("resources/shaders/glsl430/gol_transfert.glsl");
    defer rl.gl.unloadShaderProgram(gol_transfert.program);
    defer rl.gl.unloadShader(gol_transfert.shader);

    // Load shader storage buffer object (SSBO), id returned
    var ssbo_a = rl.gl.loadShaderBuffer(gol_width * gol_width * @sizeOf(u32), null, rl.gl.dynamic_copy);
    var ssbo_b = rl.gl.loadShaderBuffer(gol_width * gol_width * @sizeOf(u32), null, rl.gl.dynamic_copy);
    const ssbo_transfert = rl.gl.loadShaderBuffer(@sizeOf(GolUpdateSSBO), null, rl.gl.dynamic_copy);
    // Unload shader buffers objects
    defer rl.gl.unloadShaderBuffer(ssbo_transfert);
    defer rl.gl.unloadShaderBuffer(ssbo_b);
    defer rl.gl.unloadShaderBuffer(ssbo_a);

    var transfert_buffer: GolUpdateSSBO = .{};

    // Create a white texture of the size of the window to update
    // each pixel of the window using the fragment shader: golRenderShader
    const white_image = rl.genImageColor(gol_width, gol_width, .white);
    const white_tex = try rl.loadTextureFromImage(white_image);
    defer rl.unloadTexture(white_tex); // Unload white texture
    rl.unloadImage(white_image);

    rl.setTargetFPS(0); // Set our game to run with an uncapped framerate

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        brush_size +%= @bitCast(@as(i32, @intFromFloat(rl.getMouseWheelMove())));
        const half_brush: i32 = @bitCast(brush_size / 2);

        if ((rl.isMouseButtonDown(.left) or rl.isMouseButtonDown(.right)) and
            transfert_buffer.count < max_buffered_transferts)
        {
            // Buffer a new command
            transfert_buffer.commands[transfert_buffer.count] = .{
                .x = @bitCast(rl.getMouseX() -% half_brush),
                .y = @bitCast(rl.getMouseY() -% half_brush),
                .w = brush_size,
                .enabled = @intFromBool(rl.isMouseButtonDown(.left)),
            };
            transfert_buffer.count += 1;
        } else if (transfert_buffer.count > 0) { // Process transfert buffer
            // Send SSBO buffer to GPU
            rl.gl.updateShaderBuffer(ssbo_transfert, std.mem.asBytes(&transfert_buffer), 0);

            // Process SSBO commands on GPU
            rl.gl.enableShader(gol_transfert.program);
            rl.gl.bindShaderBuffer(ssbo_a, 1);
            rl.gl.bindShaderBuffer(ssbo_transfert, 3);
            rl.gl.computeShaderDispatch(transfert_buffer.count, 1, 1); // Each GPU unit will process a command!
            rl.gl.disableShader();

            transfert_buffer.count = 0;
        } else {
            // Process game of life logic
            rl.gl.enableShader(gol_logic.program);
            rl.gl.bindShaderBuffer(ssbo_a, 1);
            rl.gl.bindShaderBuffer(ssbo_b, 2);
            rl.gl.computeShaderDispatch(gol_width / 16, gol_width / 16, 1);
            rl.gl.disableShader();

            // ssboA <-> ssboB
            std.mem.swap(u32, &ssbo_a, &ssbo_b);
        }

        rl.gl.bindShaderBuffer(ssbo_a, 1);
        rl.setShaderValue(gol_render_shader, res_uniform_loc, resolution);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.blank);

        {
            rl.beginShaderMode(gol_render_shader);
            defer rl.endShaderMode();

            rl.drawTexture(white_tex, 0, 0, .white);
        }

        const brush: i32 = @bitCast(brush_size);
        rl.drawRectangleLines(rl.getMouseX() -% half_brush, rl.getMouseY() -% half_brush, brush, brush, .red);

        rl.drawText("Use Mouse wheel to increase/decrease brush size", 10, 10, 20, .white);
        rl.drawFPS(rl.getScreenWidth() - 100, 10);
    }
}
