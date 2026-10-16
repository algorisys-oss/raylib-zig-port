//! raylib [others] example - OpenGL interoperatibility
//!
//! Zig-API translation of examples/others/raylib_opengl_interop.c (raylib 6.2).
//! Example contributed by Stephan Soller (@arkanis) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2021-2025 Stephan Soller (@arkanis) and Ramon Santamaria (@raysan5)
//!
//! Mixes raylib and plain OpenGL code to draw a GL_POINTS based particle system. The
//! primary point is to demonstrate raylib and OpenGL interop
//!
//! rlgl batched draw operations internally so we have to flush the current batch before
//! doing our own OpenGL work (rl.gl.drawRenderBatchActive())
//!
//! The example also demonstrates how to get the current model view projection matrix of
//! raylib. That way raylib cameras and so on work as expected

const std = @import("std");
const rl = @import("raylib");

const glsl_version = 330;

const max_particles = 1000;

/// Particle type
const Particle = extern struct {
    x: f32,
    y: f32,
    period: f32,
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [others] example - OpenGL interoperatibility");
    defer rl.closeWindow(); // Close window and OpenGL context

    const shader = try rl.loadShader(
        std.fmt.comptimePrint("resources/shaders/glsl{d}/point_particle.vs", .{glsl_version}),
        std.fmt.comptimePrint("resources/shaders/glsl{d}/point_particle.fs", .{glsl_version}),
    );
    defer rl.unloadShader(shader);

    const current_time_loc = rl.getShaderLocation(shader, "currentTime");
    const color_loc = rl.getShaderLocation(shader, "color");

    // Initialize the vertex buffer for the particles and assign each particle random values
    var particles: [max_particles]Particle = undefined;
    for (&particles) |*particle| {
        const x: f32 = @floatFromInt(rl.getRandomValue(20, screen_width - 20));
        const y: f32 = @floatFromInt(rl.getRandomValue(50, screen_height - 20));
        // Give each particle a slightly different period. But don't spread it to much
        // This way the particles line up every so often and you get a glimps of what is going on
        const period: f32 = @floatFromInt(rl.getRandomValue(10, 30));
        particle.* = .{ .x = x, .y = y, .period = period / 10.0 };
    }

    // Create a plain OpenGL vertex buffer with the data and an vertex array object
    // that feeds the data from the buffer into the vertexPosition shader attribute
    var vao: gl.Uint = 0;
    var vbo: gl.Uint = 0;
    gl.genVertexArrays(1, &vao);
    gl.bindVertexArray(vao);
    gl.genBuffers(1, &vbo);
    gl.bindBuffer(gl.array_buffer, vbo);
    gl.bufferData(gl.array_buffer, @sizeOf(@TypeOf(particles)), &particles, gl.static_draw);
    // Note: loadShader() automatically fetches the attribute index of "vertexPosition" and saves it in shader.loc(.vertex_position)
    gl.vertexAttribPointer(@intCast(shader.loc(.vertex_position).*), 3, gl.float, gl.false_, 0, null);
    gl.enableVertexAttribArray(0);
    gl.bindBuffer(gl.array_buffer, 0);
    gl.bindVertexArray(0);
    defer gl.deleteVertexArrays(1, &vao);
    defer gl.deleteBuffers(1, &vbo);

    // Allows the vertex shader to set the point size of each particle individually
    gl.enable(gl.program_point_size);

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);

        rl.drawRectangle(10, 10, 210, 30, .maroon);
        rl.drawText(std.fmt.comptimePrint("{d} particles in one vertex buffer", .{max_particles}), 20, 20, 10, .ray_white);

        rl.gl.drawRenderBatchActive(); // Draw iternal buffers data (previous draw calls)

        // Switch to plain OpenGL
        gl.useProgram(shader.id);

        gl.uniform1f(current_time_loc, @floatCast(rl.getTime()));

        const color = rl.colorNormalize(.{ .r = 255, .g = 0, .b = 0, .a = 128 });
        gl.uniform4fv(color_loc, 1, &color.x);

        // Get the current modelview and projection matrix so the particle system is displayed and transformed
        const model_view_projection = rl.math.matrixMultiply(rl.gl.getMatrixModelview(), rl.gl.getMatrixProjection());

        gl.uniformMatrix4fv(shader.loc(.matrix_mvp).*, 1, gl.false_, &rl.math.matrixToFloatV(model_view_projection).v);

        gl.bindVertexArray(vao);
        gl.drawArrays(gl.points, 0, max_particles);
        gl.bindVertexArray(0);

        gl.useProgram(0);

        rl.drawFPS(screen_width - 100, 10);
    }
}

/// The few plain OpenGL entry points this example calls. raylib loads OpenGL
/// through GLAD, which exports every entry point as a `glad_gl*` function
/// pointer (valid once the window, and so the GL context, exists).
const gl = struct {
    const Uint = c_uint;
    const Enum = c_uint;

    const false_: u8 = 0;
    const points: Enum = 0x0000;
    const float: Enum = 0x1406;
    const array_buffer: Enum = 0x8892;
    const static_draw: Enum = 0x88E4;
    const program_point_size: Enum = 0x8642;

    fn Proc(comptime Fn: type) type {
        return ?*const Fn;
    }

    extern var glad_glGenVertexArrays: Proc(fn (c_int, *Uint) callconv(.c) void);
    extern var glad_glDeleteVertexArrays: Proc(fn (c_int, *const Uint) callconv(.c) void);
    extern var glad_glBindVertexArray: Proc(fn (Uint) callconv(.c) void);
    extern var glad_glGenBuffers: Proc(fn (c_int, *Uint) callconv(.c) void);
    extern var glad_glDeleteBuffers: Proc(fn (c_int, *const Uint) callconv(.c) void);
    extern var glad_glBindBuffer: Proc(fn (Enum, Uint) callconv(.c) void);
    extern var glad_glBufferData: Proc(fn (Enum, isize, ?*const anyopaque, Enum) callconv(.c) void);
    extern var glad_glVertexAttribPointer: Proc(fn (Uint, c_int, Enum, u8, c_int, ?*const anyopaque) callconv(.c) void);
    extern var glad_glEnableVertexAttribArray: Proc(fn (Uint) callconv(.c) void);
    extern var glad_glEnable: Proc(fn (Enum) callconv(.c) void);
    extern var glad_glUseProgram: Proc(fn (Uint) callconv(.c) void);
    extern var glad_glUniform1f: Proc(fn (c_int, f32) callconv(.c) void);
    extern var glad_glUniform4fv: Proc(fn (c_int, c_int, *const f32) callconv(.c) void);
    extern var glad_glUniformMatrix4fv: Proc(fn (c_int, c_int, u8, *const f32) callconv(.c) void);
    extern var glad_glDrawArrays: Proc(fn (Enum, c_int, c_int) callconv(.c) void);

    fn genVertexArrays(n: c_int, arrays: *Uint) void {
        glad_glGenVertexArrays.?(n, arrays);
    }
    fn deleteVertexArrays(n: c_int, arrays: *const Uint) void {
        glad_glDeleteVertexArrays.?(n, arrays);
    }
    fn bindVertexArray(array: Uint) void {
        glad_glBindVertexArray.?(array);
    }
    fn genBuffers(n: c_int, buffers: *Uint) void {
        glad_glGenBuffers.?(n, buffers);
    }
    fn deleteBuffers(n: c_int, buffers: *const Uint) void {
        glad_glDeleteBuffers.?(n, buffers);
    }
    fn bindBuffer(target: Enum, buffer: Uint) void {
        glad_glBindBuffer.?(target, buffer);
    }
    fn bufferData(target: Enum, size: isize, data: ?*const anyopaque, usage: Enum) void {
        glad_glBufferData.?(target, size, data, usage);
    }
    fn vertexAttribPointer(index: Uint, size: c_int, @"type": Enum, normalized: u8, stride: c_int, pointer: ?*const anyopaque) void {
        glad_glVertexAttribPointer.?(index, size, @"type", normalized, stride, pointer);
    }
    fn enableVertexAttribArray(index: Uint) void {
        glad_glEnableVertexAttribArray.?(index);
    }
    fn enable(cap: Enum) void {
        glad_glEnable.?(cap);
    }
    fn useProgram(program: Uint) void {
        glad_glUseProgram.?(program);
    }
    fn uniform1f(location: c_int, v0: f32) void {
        glad_glUniform1f.?(location, v0);
    }
    fn uniform4fv(location: c_int, count: c_int, value: *const f32) void {
        glad_glUniform4fv.?(location, count, value);
    }
    fn uniformMatrix4fv(location: c_int, count: c_int, transpose: u8, value: *const [16]f32) void {
        glad_glUniformMatrix4fv.?(location, count, transpose, &value[0]);
    }
    fn drawArrays(mode: Enum, first: c_int, count: c_int) void {
        glad_glDrawArrays.?(mode, first, count);
    }
};
