//! raylib [shaders] example - hot reloading
//!
//! Zig-API translation of examples/shaders/shaders_hot_reloading.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2020-2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const glsl_version = @import("platform").glsl_version; // GLSL 330 on desktop, 100 on the web

const frag_shader_file_name = std.fmt.comptimePrint("resources/shaders/glsl{d}/reload.fs", .{glsl_version});

// libc time formatting (C example: localtime(), asctime()), for the on-screen timestamp
const time_t = std.c.time_t;
const tm = opaque {};
extern "c" fn localtime(timer: *const time_t) ?*const tm;
extern "c" fn asctime(timeptr: *const tm) [*:0]const u8;

const ShaderLocs = struct {
    resolution: i32,
    mouse: i32,
    time: i32,

    // Get shader locations for required uniforms
    fn init(shader: rl.Shader) ShaderLocs {
        return .{
            .resolution = rl.getShaderLocation(shader, "resolution"),
            .mouse = rl.getShaderLocation(shader, "mouse"),
            .time = rl.getShaderLocation(shader, "time"),
        };
    }
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [shaders] example - hot reloading");
    defer rl.closeWindow(); // Close window and OpenGL context

    var frag_shader_file_mod_time: time_t = rl.getFileModTime(frag_shader_file_name);

    // Load raymarching shader
    // NOTE: Defining null for vertex shader forces usage of internal default vertex shader
    var shader = try rl.loadShader(null, frag_shader_file_name);
    defer rl.unloadShader(shader); // Unload shader

    // Get shader locations for required uniforms
    var locs: ShaderLocs = .init(shader);

    const resolution = [2]f32{ screen_width, screen_height };
    rl.setShaderValue(shader, locs.resolution, resolution);

    var total_time: f32 = 0.0;
    var shader_auto_reloading = false;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        total_time += rl.getFrameTime();
        const mouse = rl.getMousePosition();
        const mouse_pos = [2]f32{ mouse.x, mouse.y };

        // Set shader required uniform values
        rl.setShaderValue(shader, locs.time, total_time);
        rl.setShaderValue(shader, locs.mouse, mouse_pos);

        // Hot shader reloading
        if (shader_auto_reloading or rl.isMouseButtonPressed(.left)) {
            const current_frag_shader_mod_time = rl.getFileModTime(frag_shader_file_name);

            // Check if shader file has been modified
            if (current_frag_shader_mod_time != frag_shader_file_mod_time) {
                // Try reloading updated shader (on failure, keep the current one)
                const updated_shader = rl.loadShader(null, frag_shader_file_name) catch shader;

                if (updated_shader.id != shader.id and updated_shader.id != rl.gl.getShaderIdDefault()) { // It was correctly loaded
                    rl.unloadShader(shader);
                    shader = updated_shader;

                    // Get shader locations for required uniforms
                    locs = .init(shader);

                    // Reset required uniforms
                    rl.setShaderValue(shader, locs.resolution, resolution);
                }

                frag_shader_file_mod_time = current_frag_shader_mod_time;
            }
        }

        if (rl.isKeyPressed(.a)) shader_auto_reloading = !shader_auto_reloading;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // We only draw a white full-screen rectangle, frame is generated in shader
        {
            rl.beginShaderMode(shader);
            defer rl.endShaderMode();

            rl.drawRectangle(0, 0, screen_width, screen_height, .white);
        }

        rl.drawText(
            rl.textFormat("PRESS [A] to TOGGLE SHADER AUTOLOADING: {s}", .{if (shader_auto_reloading) "AUTO" else "MANUAL"}),
            10,
            10,
            10,
            if (shader_auto_reloading) .red else .black,
        );
        if (!shader_auto_reloading) rl.drawText("MOUSE CLICK to SHADER RE-LOADING", 10, 30, 10, .black);

        const mod_time_text = std.mem.span(asctime(localtime(&frag_shader_file_mod_time).?));
        rl.drawText(rl.textFormat("Shader last modification: {s}", .{mod_time_text}), 10, 430, 10, .black);
    }
}
