//! api_test.zig — checks for the generated idiomatic Zig API (src/api).
//!
//! 1. Every `extern struct` the API exports is layout-identical to the C
//!    struct of the same name in raylib.h (via translate-c): size, alignment
//!    and the offset of every field, found by comptime reflection — a new or
//!    changed struct in raylib.h is covered without editing this file.
//! 2. Every wrapper compiles (all 619 functions are semantically analyzed).
//!
//! Behavior is not re-tested here: each wrapper forwards to the C-ABI export
//! the port's pixel/numeric/PCM gates already cover.

const std = @import("std");
const rl = @import("raylib");
const c = @import("c_raylib");
const c_rlgl = @import("c_rlgl");
const gui = @import("raygui");

test "API structs are layout-identical to raylib.h" {
    var checked: usize = 0;
    inline for (@typeInfo(rl).@"struct".decl_names) |decl_name| {
        const T = @field(rl, decl_name);
        if (@TypeOf(T) != type) continue;
        const info = @typeInfo(T);
        if (info != .@"struct" or info.@"struct".layout != .@"extern") continue;
        // Aliases (Texture2D = Texture, Camera = Camera3D) check the target twice; harmless.
        const C = @field(c, decl_name);
        try expectLayout(decl_name, T, C);
        checked += 1;
    }
    try std.testing.expect(checked >= 35);
}

fn expectLayout(name: []const u8, comptime T: type, comptime C: type) !void {
    errdefer std.debug.print("layout mismatch in {s}\n", .{name});
    try std.testing.expectEqual(@sizeOf(C), @sizeOf(T));
    try std.testing.expectEqual(@alignOf(C), @alignOf(T));
    const info = @typeInfo(T).@"struct";
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        errdefer std.debug.print("  field {s}.{s}\n", .{ name, field_name });
        try std.testing.expectEqual(@offsetOf(C, field_name), @offsetOf(T, field_name));
        try std.testing.expectEqual(@sizeOf(@FieldType(C, field_name)), @sizeOf(field_type));
    }
}

test "rlgl batch structs are layout-identical to rlgl.h (OPENGL_33)" {
    try expectLayout("VertexBuffer", rl.gl.VertexBuffer, c_rlgl.rlVertexBuffer);
    try expectLayout("DrawCall", rl.gl.DrawCall, c_rlgl.rlDrawCall);
    try expectLayout("RenderBatch", rl.gl.RenderBatch, c_rlgl.rlRenderBatch);
    try expectLayout("float16", rl.math.float16, extern struct { v: [16]f32 });
}

test "all API wrappers compile" {
    std.testing.refAllDecls(rl);
    std.testing.refAllDecls(rl.math);
    std.testing.refAllDecls(rl.gl);
    std.testing.refAllDecls(gui);
}

test "generic wrappers instantiate (refAllDecls skips anytype functions)" {
    try std.testing.expectEqualStrings("7 pts, 3.50", rl.textFormat("{d} pts, {d:.2}", .{ 7, 3.5 }));
    rl.setTraceLogLevel(.none);
    rl.traceLog(.info, "{s}", .{"unused"});
}

test "colors and enums match raylib.h" {
    try std.testing.expectEqual(rl.Color{ .r = 245, .g = 245, .b = 245, .a = 255 }, rl.Color.ray_white);
    try std.testing.expectEqual(c.KEY_LEFT_SHIFT, @backingInt(rl.KeyboardKey.left_shift));
    try std.testing.expectEqual(c.MOUSE_BUTTON_RIGHT, @backingInt(rl.MouseButton.right));
    try std.testing.expectEqual(c.SHADER_LOC_VERTEX_INSTANCETRANSFORM, @backingInt(rl.ShaderLocationIndex.vertex_instancetransform));
    try std.testing.expectEqual(c.MATERIAL_MAP_ALBEDO, @backingInt(rl.MaterialMapIndex.diffuse));
    try std.testing.expectEqual(c_rlgl.RL_QUADS, rl.gl.quads);
    try std.testing.expectEqual(c_rlgl.RL_TEXTURE_WRAP_S, rl.gl.texture_wrap_s);
    try std.testing.expectEqual(c_rlgl.RL_DEFAULT_BATCH_BUFFER_ELEMENTS, rl.gl.default_batch_buffer_elements);
    try std.testing.expectEqual(@as(i32, c_rlgl.RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8A8), rl.gl.pixelformat_uncompressed_r8g8b8a8);
    const flags: rl.ConfigFlags = .{ .vsync_hint = true, .window_hidden = true, .msaa_4x_hint = true };
    try std.testing.expectEqual(@as(u32, c.FLAG_VSYNC_HINT | c.FLAG_WINDOW_HIDDEN | c.FLAG_MSAA_4X_HINT), @as(u32, @bitCast(flags)));
}
