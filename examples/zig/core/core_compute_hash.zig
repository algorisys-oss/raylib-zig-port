//! raylib [core] example - compute hash
//!
//! Zig-API translation of examples/core/core_compute_hash.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");

/// Hex text of a hash (8 digits per word) in `buffer`, as an edit buffer of
/// the size the read-only text boxes take; "00000000" when there is no hash.
fn dataAsHexText(buffer: *[128]u8, data: ?[]const u32) []u8 {
    @memset(buffer, 0);

    var writer: std.Io.Writer = .fixed(buffer);
    if (data) |words| {
        for (words) |word| writer.print("{X:0>8}", .{word}) catch unreachable;
    } else {
        writer.writeAll("00000000") catch unreachable;
    }

    return buffer[0..120];
}

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [core] example - compute hash");
    defer rl.closeWindow(); // Close window and OpenGL context

    // UI controls variables
    var text_input: [96]u8 = @splat(0);
    @memcpy(text_input[0..44], "The quick brown fox jumps over the lazy dog.");
    var text_box_edit_mode = false;
    var btn_compute_hashes = false;

    // Data hash values
    var hash_crc32: u32 = 0;
    var hash_md5: ?[]const u32 = null;
    var hash_sha1: ?[]const u32 = null;
    var hash_sha256: ?[]const u32 = null;

    // Base64 encoded data
    var base64_text: ?[:0]u8 = null;
    defer if (base64_text) |text| rl.memFree(text.ptr); // Free Base64 text data

    var hex_buffer: [128]u8 = undefined;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (btn_compute_hashes) {
            const data = std.mem.sliceTo(&text_input, 0);

            // Encode data to Base64 string (includes NULL terminator), memory must be freed
            if (base64_text) |text| rl.memFree(text.ptr);
            base64_text = try rl.encodeDataBase64(data);

            hash_crc32 = rl.computeCRC32(data); // Compute CRC32 hash code (4 bytes)
            hash_md5 = rl.computeMD5(data); // Compute MD5 hash code, returns static int[4] (16 bytes)
            hash_sha1 = rl.computeSHA1(data); // Compute SHA1 hash code, returns static int[5] (20 bytes)
            hash_sha256 = rl.computeSHA256(data); // Compute SHA256 hash code, returns static int[8] (32 bytes)
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        gui.setStyle(.default, gui.DefaultProperty.text_size, 20);
        gui.setStyle(.default, gui.DefaultProperty.text_spacing, 2);
        _ = gui.label(.{ .x = 40, .y = 26, .width = 720, .height = 32 }, "INPUT DATA (TEXT):");
        gui.setStyle(.default, gui.DefaultProperty.text_spacing, 1);
        gui.setStyle(.default, gui.DefaultProperty.text_size, 10);

        if (gui.textBox(.{ .x = 40, .y = 64, .width = 720, .height = 32 }, text_input[0..95], text_box_edit_mode) != 0) text_box_edit_mode = !text_box_edit_mode;

        btn_compute_hashes = gui.button(.{ .x = 40, .y = 64 + 40, .width = 720, .height = 32 }, "COMPUTE INPUT DATA HASHES") != 0;

        gui.setStyle(.default, gui.DefaultProperty.text_size, 20);
        gui.setStyle(.default, gui.DefaultProperty.text_spacing, 2);
        _ = gui.label(.{ .x = 40, .y = 160, .width = 720, .height = 32 }, "INPUT DATA HASH VALUES:");
        gui.setStyle(.default, gui.DefaultProperty.text_spacing, 1);
        gui.setStyle(.default, gui.DefaultProperty.text_size, 10);

        gui.setStyle(.textbox, gui.TextBoxProperty.text_readonly, 1);
        _ = gui.label(.{ .x = 40, .y = 200, .width = 120, .height = 32 }, "CRC32 [32 bit]:");
        _ = gui.textBox(.{ .x = 40 + 120, .y = 200, .width = 720 - 120, .height = 32 }, dataAsHexText(&hex_buffer, &.{hash_crc32}), false);
        _ = gui.label(.{ .x = 40, .y = 200 + 36, .width = 120, .height = 32 }, "MD5 [128 bit]:");
        _ = gui.textBox(.{ .x = 40 + 120, .y = 200 + 36, .width = 720 - 120, .height = 32 }, dataAsHexText(&hex_buffer, hash_md5), false);
        _ = gui.label(.{ .x = 40, .y = 200 + 36 * 2, .width = 120, .height = 32 }, "SHA1 [160 bit]:");
        _ = gui.textBox(.{ .x = 40 + 120, .y = 200 + 36 * 2, .width = 720 - 120, .height = 32 }, dataAsHexText(&hex_buffer, hash_sha1), false);
        _ = gui.label(.{ .x = 40, .y = 200 + 36 * 3, .width = 120, .height = 32 }, "SHA256 [256 bit]:");
        _ = gui.textBox(.{ .x = 40 + 120, .y = 200 + 36 * 3, .width = 720 - 120, .height = 32 }, dataAsHexText(&hex_buffer, hash_sha256), false);

        gui.setState(.focused);
        _ = gui.label(.{ .x = 40, .y = 200 + 36 * 5 - 30, .width = 320, .height = 32 }, "BONUS - BAS64 ENCODED STRING:");
        gui.setState(.normal);
        _ = gui.label(.{ .x = 40, .y = 200 + 36 * 5, .width = 120, .height = 32 }, "BASE64 ENCODING:");
        _ = gui.textBox(.{ .x = 40 + 120, .y = 200 + 36 * 5, .width = 720 - 120, .height = 32 }, base64_text, false);
        gui.setStyle(.textbox, gui.TextBoxProperty.text_readonly, 0);
    }
}
