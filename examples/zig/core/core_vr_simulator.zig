//! raylib [core] example - vr simulator
//!
//! Zig-API translation of examples/core/core_vr_simulator.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)

const rl = @import("raylib");

const glsl_version = 330; // Desktop GLSL (PLATFORM_ANDROID, PLATFORM_WEB use 100)

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    // NOTE: screen_width/screen_height should match VR device aspect ratio
    rl.initWindow(screen_width, screen_height, "raylib [core] example - vr simulator");
    defer rl.closeWindow(); // Close window and OpenGL context

    // VR device parameters definition
    const device: rl.VrDeviceInfo = .{
        // Oculus Rift CV1 parameters for simulator
        .hResolution = 2160, // Horizontal resolution in pixels
        .vResolution = 1200, // Vertical resolution in pixels
        .hScreenSize = 0.133793, // Horizontal size in meters
        .vScreenSize = 0.0669, // Vertical size in meters
        .eyeToScreenDistance = 0.041, // Distance between eye and display in meters
        .lensSeparationDistance = 0.07, // Lens separation distance in meters
        .interpupillaryDistance = 0.07, // IPD (distance between pupils) in meters

        // NOTE: CV1 uses fresnel-hybrid-asymmetric lenses with specific compute shaders
        // Following parameters are just an approximation to CV1 distortion stereo rendering
        .lensDistortionValues = .{ 1.0, 0.22, 0.24, 0.0 }, // Lens distortion constant parameters
        .chromaAbCorrection = .{ 0.996, -0.004, 1.014, 0.0 }, // Chromatic aberration correction parameters
    };

    // Load VR stereo config for VR device parameteres (Oculus Rift CV1 parameters)
    const config = rl.loadVrStereoConfig(device);
    defer rl.unloadVrStereoConfig(config); // Unload stereo config

    // Distortion shader (uses device lens distortion and chroma)
    const distortion = try rl.loadShader(null, rl.textFormat("resources/shaders/glsl{d}/distortion.fs", .{glsl_version}));
    defer rl.unloadShader(distortion); // Unload distortion shader

    // Update distortion shader with lens and distortion-scale parameters
    rl.setShaderValue(distortion, rl.getShaderLocation(distortion, "leftLensCenter"), &config.leftLensCenter, .vec2);
    rl.setShaderValue(distortion, rl.getShaderLocation(distortion, "rightLensCenter"), &config.rightLensCenter, .vec2);
    rl.setShaderValue(distortion, rl.getShaderLocation(distortion, "leftScreenCenter"), &config.leftScreenCenter, .vec2);
    rl.setShaderValue(distortion, rl.getShaderLocation(distortion, "rightScreenCenter"), &config.rightScreenCenter, .vec2);

    rl.setShaderValue(distortion, rl.getShaderLocation(distortion, "scale"), &config.scale, .vec2);
    rl.setShaderValue(distortion, rl.getShaderLocation(distortion, "scaleIn"), &config.scaleIn, .vec2);
    rl.setShaderValue(distortion, rl.getShaderLocation(distortion, "deviceWarpParam"), &device.lensDistortionValues, .vec4);
    rl.setShaderValue(distortion, rl.getShaderLocation(distortion, "chromaAbParam"), &device.chromaAbCorrection, .vec4);

    // Initialize framebuffer for stereo rendering
    // NOTE: Screen size should match HMD aspect ratio
    const target = try rl.loadRenderTexture(device.hResolution, device.vResolution);
    defer rl.unloadRenderTexture(target); // Unload stereo render fbo

    // The target's height is flipped (in the source Rectangle), due to OpenGL reasons
    const source_rec: rl.Rectangle = .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(target.texture.width),
        .height = -@as(f32, @floatFromInt(target.texture.height)),
    };
    const dest_rec: rl.Rectangle = .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(rl.getScreenWidth()),
        .height = @floatFromInt(rl.getScreenHeight()),
    };

    // Define the camera to look into our 3d world
    var camera: rl.Camera = .{
        .position = .{ .x = 5.0, .y = 2.0, .z = 5.0 }, // Camera position
        .target = .{ .x = 0.0, .y = 2.0, .z = 0.0 }, // Camera looking at point
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, // Camera up vector
        .fovy = 60.0, // Camera field-of-view Y
        .projection = .perspective, // Camera projection type
    };

    const cube_position: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };

    rl.disableCursor(); // Limit cursor to relative movement inside the window

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        rl.updateCamera(&camera, .first_person);

        // Draw
        {
            rl.beginTextureMode(target);
            defer rl.endTextureMode();

            rl.clearBackground(.ray_white);

            rl.beginVrStereoMode(config);
            defer rl.endVrStereoMode();

            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawCube(cube_position, 2.0, 2.0, 2.0, .red);
            rl.drawCubeWires(cube_position, 2.0, 2.0, 2.0, .maroon);
            rl.drawGrid(40, 1.0);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);
        {
            rl.beginShaderMode(distortion);
            defer rl.endShaderMode();

            rl.drawTexturePro(target.texture, source_rec, dest_rec, .{ .x = 0.0, .y = 0.0 }, 0.0, .white);
        }
        rl.drawFPS(10, 10);
    }
}
