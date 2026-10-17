//! raylib-zig build — Phase 0 foundation.
//!
//! Incremental C→Zig migration of raylib. Each raylib translation unit under
//! vendor/raylib/src is compiled separately; as a module is ported, its `.c` is
//! dropped from the build (see `ported_modules`) and the Zig replacement in
//! src/<name>.zig is compiled in its place, keeping the same C-ABI symbols. A
//! mixed C/Zig binary builds and renders identically at every step.
//!
//! Pinned target (decision 2026-06-28): Linux desktop, vendored GLFW (X11),
//! OpenGL 3.3. The validation oracle is software rendering via mesa llvmpipe,
//! which is byte-exact deterministic for this codepath (see docs/testing.md).
//!
//! Steps:
//!   zig build            build static libraylib.a + the demo            → zig-out/
//!   zig build demo       run the headless demo (needs DISPLAY)
//!   zig build test       C-vs-Zig scene diff under llvmpipe (the gate)
//!   zig build runners    build both scene_runner exes (oracle + zig)

const std = @import("std");

/// raylib's own translation units (rcore.c #includes the platform backend).
const raylib_tus = [_][]const u8{
    "rcore.c",
    "rshapes.c",
    "rtextures.c",
    "rtext.c",
    "rmodels.c",
    "raudio.c",
};

/// Modules ported to Zig. As each lands, add its C basename here AND create
/// src/<name>.zig exporting the same C-ABI symbols. The C file is then excluded
/// and the Zig object linked in its place. (raymath.h / rlgl.h are header-only —
/// not TUs — and are swapped via a different mechanism; see plan.md Phase 1/2.)
const ported_modules = [_][]const u8{
    "rshapes.c", // -> src/rshapes.zig (2D shapes/collision; calls rlgl via extern)
    "rtext.c", // -> src/rtext.zig (fonts/text; stb via src/c/rtext_stb_impl.c shim)
    "rtextures.c", // -> src/rtextures.zig (image/texture; stb via src/c/rtextures_stb_impl.c shim)
    "rmodels.c", // -> src/rmodels.zig (3D models/meshes; third-party via shim, see rmodels swap below)
    "raudio.c", // -> src/raudio.zig (audio; miniaudio/dr_*/stb_vorbis/qoa/jar_* via src/c/raudio_impl.c shim)
};

/// The two targets the port builds for. Desktop is the pinned Linux/GLFW/GL 3.3
/// configuration every gate runs on; web is PLATFORM_WEB + OpenGL ES 3 (WebGL 2)
/// on Emscripten, linked by emcc (see `addWeb`). The Zig modules pick their side
/// at comptime from the target OS (rcore.zig `backend`, rlgl.zig `graphics_api`);
/// these defines do the same for the C that is still compiled.
const Platform = enum { desktop, web };

/// Compile defines pinning the Linux/GLFW/GL3.3 configuration. Proven to build
/// and render headlessly under both the GPU and llvmpipe.
const c_defines = [_][]const u8{
    "-DPLATFORM_DESKTOP_GLFW",
    "-DGRAPHICS_API_OPENGL_33",
    "-D_GLFW_X11",
} ++ c_defines_common;

/// The web configuration: what upstream raylib's Makefile passes for
/// PLATFORM_WEB, with the WebGL 2 graphics API.
const web_c_defines = [_][]const u8{
    "-DPLATFORM_WEB",
    "-DGRAPHICS_API_OPENGL_ES3",
} ++ c_defines_common ++ [_][]const u8{
    // EM_ASM (rcore_web.c) refuses strict C modes; upstream builds the web with
    // gnu99 too. Later -std wins over the common -std=c99.
    "-std=gnu99",
};

const c_defines_common = [_][]const u8{
    "-D_GNU_SOURCE",
    "-DSUPPORT_MODULE_RSHAPES=1",
    "-DSUPPORT_MODULE_RTEXTURES=1",
    "-DSUPPORT_MODULE_RTEXT=1",
    "-DSUPPORT_MODULE_RMODELS=1",
    "-DSUPPORT_MODULE_RAUDIO=1",
    "-std=c99",
    "-w", // vendored third-party C is noisy; we don't own its warnings
    // Strict IEEE: no FMA contraction. Zig never contracts, and clang's default
    // fuses a*b+c in e.g. rlVertex3f's transform multiply — found as sub-pixel
    // glyph shifts in text_3d_drawing (3D text under a rotated matrix stack).
    // The scene battery missed it (its transforms had zero off-diagonals);
    // mathgrid's oracle already used this flag for raymath bit-exactness.
    "-ffp-contract=off",
    // Vendored single-file parsers (m3d.h, vox_loader.h) do misaligned u32
    // reads on packed file data — benign on x86, but zig cc's default UBSan
    // traps them (models_loading_m3d/_vox). Disable ONLY the alignment check;
    // the rest of UBSan stays on for the swapped build's C (it caught the
    // raudio NaN bug). The oracle disables UBSan entirely (see oracle_flags).
    "-fno-sanitize=alignment",
};

/// Translated but only compiled, not pixel-gated: the C original is
/// self-nondeterministic (audio-thread timing, a wall-clock busy-wait) or
/// interactive (see test/examples.list).
const api_examples_build_only = [_][]const u8{
    "audio/audio_mixed_processor",
    "audio/audio_module_playing",
    "audio/audio_raw_stream",
    "audio/audio_spectrum_visualizer",
    "audio/audio_stream_callback",
    "audio/audio_stream_effects",
    "core/core_custom_frame_control",
    "core/core_input_gestures_testbed",
    "core/core_window_should_close",
};

/// Zig-API examples that link a third-party single-file C library the upstream
/// example bundles: each instantiates it in `examples/zig/<entry>_shim.c`.
const api_example_c_shims = [_][]const u8{
    "core/core_screen_recording",
};

/// Upstream examples translated to the idiomatic Zig API (examples/zig/),
/// gated by `zig build apiexamples` against the original C example.
const api_examples = [_][]const u8{
    "audio/audio_amp_envelope",
    "audio/audio_music_stream",
    "audio/audio_sound_loading",
    "audio/audio_sound_multi",
    "audio/audio_sound_positioning",
    "core/core_2d_camera",
    "core/core_2d_camera_mouse_zoom",
    "core/core_2d_camera_platformer",
    "core/core_2d_camera_split_screen",
    "core/core_3d_camera_first_person",
    "core/core_3d_camera_fps",
    "core/core_3d_camera_free",
    "core/core_3d_camera_mode",
    "core/core_3d_camera_split_screen",
    "core/core_3d_picking",
    "core/core_automation_events",
    "core/core_basic_screen_manager",
    "core/core_basic_window",
    "core/core_clipboard_text",
    "core/core_compute_hash",
    "core/core_custom_logging",
    "core/core_delta_time",
    "core/core_directory_files",
    "core/core_drop_files",
    "core/core_highdpi_demo",
    "core/core_highdpi_testbed",
    "core/core_input_actions",
    "core/core_input_gamepad",
    "core/core_input_gestures",
    "core/core_input_keys",
    "core/core_input_mouse",
    "core/core_input_mouse_wheel",
    "core/core_input_multitouch",
    "core/core_input_virtual_controls",
    "core/core_keyboard_testbed",
    "core/core_monitor_detector",
    "core/core_random_sequence",
    "core/core_random_values",
    "core/core_render_texture",
    "core/core_scissor_test",
    "core/core_screen_recording",
    "core/core_smooth_pixelperfect",
    "core/core_storage_values",
    "core/core_text_file_loading",
    "core/core_undo_redo",
    "core/core_viewport_scaling",
    "core/core_vr_simulator",
    "core/core_window_flags",
    "core/core_window_letterbox",
    "core/core_window_web",
    "core/core_world_screen",
    "models/models_animation_blend_custom",
    "models/models_animation_blending",
    "models/models_animation_gpu_skinning",
    "models/models_animation_timing",
    "models/models_basic_voxel",
    "models/models_billboard_rendering",
    "models/models_bone_socket",
    "models/models_box_collisions",
    "models/models_cubicmap_rendering",
    "models/models_decals",
    "models/models_directional_billboard",
    "models/models_first_person_maze",
    "models/models_geometric_shapes",
    "models/models_heightmap_rendering",
    "models/models_loading",
    "models/models_loading_gltf",
    "models/models_loading_iqm",
    "models/models_loading_m3d",
    "models/models_loading_vox",
    "models/models_mesh_generation",
    "models/models_mesh_picking",
    "models/models_mesh_uv_painting",
    "models/models_orthographic_projection",
    "models/models_point_rendering",
    "models/models_procedural_decals",
    "models/models_rlgl_solar_system",
    "models/models_rotating_cube",
    "models/models_skybox_rendering",
    "models/models_tesseract_view",
    "models/models_textured_cube",
    "models/models_waving_cubes",
    "models/models_yaw_pitch_roll",
    "others/embedded_files_loading",
    "others/gl_scissor_shapes",
    "others/raylib_opengl_interop",
    "shaders/shaders_ascii_rendering",
    "shaders/shaders_basic_lighting",
    "shaders/shaders_basic_pbr",
    "shaders/shaders_cel_shading",
    "shaders/shaders_color_correction",
    "shaders/shaders_custom_uniform",
    "shaders/shaders_deferred_rendering",
    "shaders/shaders_depth_rendering",
    "shaders/shaders_depth_writing",
    "shaders/shaders_eratosthenes_sieve",
    "shaders/shaders_fog_rendering",
    "shaders/shaders_game_of_life",
    "shaders/shaders_hot_reloading",
    "shaders/shaders_hybrid_rendering",
    "shaders/shaders_julia_set",
    "shaders/shaders_lightmap_rendering",
    "shaders/shaders_lights_bloom",
    "shaders/shaders_mandelbrot_set",
    "shaders/shaders_mesh_instancing",
    "shaders/shaders_model_shader",
    "shaders/shaders_multi_sample2d",
    "shaders/shaders_normalmap_rendering",
    "shaders/shaders_palette_switch",
    "shaders/shaders_postprocessing",
    "shaders/shaders_raymarching_rendering",
    "shaders/shaders_rlgl_compute",
    "shaders/shaders_rounded_rectangle",
    "shaders/shaders_shadowmap_rendering",
    "shaders/shaders_shapes_textures",
    "shaders/shaders_simple_mask",
    "shaders/shaders_spotlight_rendering",
    "shaders/shaders_texture_outline",
    "shaders/shaders_texture_rendering",
    "shaders/shaders_texture_tiling",
    "shaders/shaders_texture_waves",
    "shaders/shaders_vertex_displacement",
    "shapes/shapes_ball_physics",
    "shapes/shapes_basic_shapes",
    "shapes/shapes_bouncing_ball",
    "shapes/shapes_bullet_hell",
    "shapes/shapes_circle_sector_drawing",
    "shapes/shapes_clock_of_clocks",
    "shapes/shapes_collision_area",
    "shapes/shapes_colors_palette",
    "shapes/shapes_dashed_line",
    "shapes/shapes_digital_clock",
    "shapes/shapes_double_pendulum",
    "shapes/shapes_drag_puzzle",
    "shapes/shapes_easings_ball",
    "shapes/shapes_easings_box",
    "shapes/shapes_easings_rectangles",
    "shapes/shapes_easings_testbed",
    "shapes/shapes_ellipse_collision",
    "shapes/shapes_following_eyes",
    "shapes/shapes_hilbert_curve",
    "shapes/shapes_kaleidoscope",
    "shapes/shapes_lines_bezier",
    "shapes/shapes_lines_drawing",
    "shapes/shapes_logo_raylib",
    "shapes/shapes_logo_raylib_anim",
    "shapes/shapes_math_angle_rotation",
    "shapes/shapes_math_sine_cosine",
    "shapes/shapes_mouse_trail",
    "shapes/shapes_outlines_testbed",
    "shapes/shapes_outlines_thickness",
    "shapes/shapes_penrose_tile",
    "shapes/shapes_pie_chart",
    "shapes/shapes_polygon_lines",
    "shapes/shapes_rectangle_advanced",
    "shapes/shapes_rectangle_scaling",
    "shapes/shapes_recursive_tree",
    "shapes/shapes_ring_drawing",
    "shapes/shapes_rlgl_color_wheel",
    "shapes/shapes_rlgl_triangle",
    "shapes/shapes_rounded_rectangle_drawing",
    "shapes/shapes_simple_particles",
    "shapes/shapes_splines_drawing",
    "shapes/shapes_starfield_effect",
    "shapes/shapes_top_down_lights",
    "shapes/shapes_triangle_strip",
    "shapes/shapes_vector_angle",
    "text/text_3d_drawing",
    "text/text_animations",
    "text/text_codepoints_loading",
    "text/text_font_filters",
    "text/text_font_loading",
    "text/text_font_sdf",
    "text/text_font_spritefont",
    "text/text_format_text",
    "text/text_inline_styling",
    "text/text_input_box",
    "text/text_rectangle_bounds",
    "text/text_sprite_fonts",
    "text/text_strings_management",
    "text/text_unicode_emojis",
    "text/text_unicode_ranges",
    "text/text_words_alignment",
    "text/text_writing_anim",
    "textures/textures_background_scrolling",
    "textures/textures_blend_modes",
    "textures/textures_bunnymark",
    "textures/textures_cellular_automata",
    "textures/textures_clipboard_image",
    "textures/textures_fog_of_war",
    "textures/textures_framebuffer_rendering",
    "textures/textures_gif_player",
    "textures/textures_image_channel",
    "textures/textures_image_drawing",
    "textures/textures_image_generation",
    "textures/textures_image_kernel",
    "textures/textures_image_loading",
    "textures/textures_image_processing",
    "textures/textures_image_rotate",
    "textures/textures_image_text",
    "textures/textures_logo_raylib",
    "textures/textures_magnifying_glass",
    "textures/textures_mouse_painting",
    "textures/textures_npatch_drawing",
    "textures/textures_particles_blending",
    "textures/textures_polygon_drawing",
    "textures/textures_portal_window",
    "textures/textures_raw_data",
    "textures/textures_screen_buffer",
    "textures/textures_sprite_animation",
    "textures/textures_sprite_button",
    "textures/textures_sprite_explosion",
    "textures/textures_sprite_stacking",
    "textures/textures_srcrec_dstrec",
    "textures/textures_textured_curve",
    "textures/textures_tiled_drawing",
    "textures/textures_to_image",
};

/// Examples in the browser gate (`zig build webexamples`): each runs in headless
/// Chrome twice, as upstream C on the all-C library and as the Zig-API translation
/// on the Zig library, and the final frames must be byte-identical.
const web_examples = [_][]const u8{
    "core/core_2d_camera",
    "core/core_2d_camera_mouse_zoom",
    "core/core_2d_camera_platformer",
    "core/core_2d_camera_split_screen",
    "core/core_3d_camera_first_person",
    "core/core_3d_camera_fps",
    "core/core_3d_camera_free",
    "core/core_3d_camera_mode",
    "core/core_3d_camera_split_screen",
    "core/core_3d_picking",
    "core/core_automation_events",
    "core/core_basic_screen_manager",
    "core/core_basic_window",
    "core/core_clipboard_text",
    "core/core_compute_hash",
    "core/core_custom_logging",
    "core/core_delta_time",
    "core/core_drop_files",
    "core/core_highdpi_demo",
    "core/core_highdpi_testbed",
    "core/core_input_actions",
    "core/core_input_gamepad",
    "core/core_input_gestures",
    "core/core_input_keys",
    "core/core_input_mouse",
    "core/core_input_mouse_wheel",
    "core/core_input_multitouch",
    "core/core_input_virtual_controls",
    "core/core_keyboard_testbed",
    "core/core_monitor_detector",
    "core/core_random_sequence",
    "core/core_random_values",
    "core/core_render_texture",
    "core/core_scissor_test",
    "core/core_screen_recording",
    "core/core_smooth_pixelperfect",
    "core/core_storage_values",
    "core/core_text_file_loading",
    "core/core_undo_redo",
    "core/core_viewport_scaling",
    "core/core_vr_simulator",
    "core/core_window_flags",
    "core/core_window_letterbox",
    "core/core_world_screen",
    "shapes/shapes_ball_physics",
    "shapes/shapes_basic_shapes",
    "shapes/shapes_bouncing_ball",
    "shapes/shapes_bullet_hell",
    "shapes/shapes_circle_sector_drawing",
    "shapes/shapes_clock_of_clocks",
    "shapes/shapes_collision_area",
    "shapes/shapes_colors_palette",
    "shapes/shapes_dashed_line",
    "shapes/shapes_digital_clock",
    "shapes/shapes_double_pendulum",
    "shapes/shapes_drag_puzzle",
    "shapes/shapes_easings_ball",
    "shapes/shapes_easings_box",
    "shapes/shapes_easings_rectangles",
    "shapes/shapes_easings_testbed",
    "shapes/shapes_ellipse_collision",
    "shapes/shapes_following_eyes",
    "shapes/shapes_hilbert_curve",
    "shapes/shapes_kaleidoscope",
    "shapes/shapes_lines_bezier",
    "shapes/shapes_lines_drawing",
    "shapes/shapes_logo_raylib",
    "shapes/shapes_logo_raylib_anim",
    "shapes/shapes_math_angle_rotation",
    "shapes/shapes_math_sine_cosine",
    "shapes/shapes_mouse_trail",
    "shapes/shapes_outlines_testbed",
    "shapes/shapes_outlines_thickness",
    "shapes/shapes_penrose_tile",
    "shapes/shapes_pie_chart",
    "shapes/shapes_polygon_lines",
    "shapes/shapes_rectangle_advanced",
    "shapes/shapes_rectangle_scaling",
    "shapes/shapes_recursive_tree",
    "shapes/shapes_ring_drawing",
    "shapes/shapes_rlgl_color_wheel",
    "shapes/shapes_rlgl_triangle",
    "shapes/shapes_rounded_rectangle_drawing",
    "shapes/shapes_simple_particles",
    "shapes/shapes_splines_drawing",
    "shapes/shapes_starfield_effect",
    "shapes/shapes_top_down_lights",
    "shapes/shapes_triangle_strip",
    "shapes/shapes_vector_angle",
    "textures/textures_background_scrolling",
    "textures/textures_blend_modes",
    "textures/textures_bunnymark",
    "textures/textures_cellular_automata",
    "textures/textures_clipboard_image",
    "textures/textures_fog_of_war",
    "textures/textures_framebuffer_rendering",
    "textures/textures_gif_player",
    "textures/textures_image_channel",
    "textures/textures_image_drawing",
    "textures/textures_image_generation",
    "textures/textures_image_kernel",
    "textures/textures_image_loading",
    "textures/textures_image_processing",
    "textures/textures_image_rotate",
    "textures/textures_image_text",
    "textures/textures_logo_raylib",
    "textures/textures_magnifying_glass",
    "textures/textures_mouse_painting",
    "textures/textures_npatch_drawing",
    "textures/textures_particles_blending",
    "textures/textures_polygon_drawing",
    "textures/textures_portal_window",
    "textures/textures_raw_data",
    "textures/textures_screen_buffer",
    "textures/textures_sprite_animation",
    "textures/textures_sprite_button",
    "textures/textures_sprite_explosion",
    "textures/textures_sprite_stacking",
    "textures/textures_srcrec_dstrec",
    "textures/textures_textured_curve",
    "textures/textures_tiled_drawing",
    "text/text_3d_drawing",
    "text/text_animations",
    "text/text_codepoints_loading",
    "text/text_font_filters",
    "text/text_font_loading",
    "text/text_font_sdf",
    "text/text_font_spritefont",
    "text/text_format_text",
    "text/text_inline_styling",
    "text/text_input_box",
    "text/text_rectangle_bounds",
    "text/text_sprite_fonts",
    "text/text_strings_management",
    "text/text_unicode_emojis",
    "text/text_unicode_ranges",
    "text/text_words_alignment",
    "text/text_writing_anim",
    "shaders/shaders_ascii_rendering",
    "shaders/shaders_basic_lighting",
    "shaders/shaders_basic_pbr",
    "shaders/shaders_cel_shading",
    "shaders/shaders_color_correction",
    "shaders/shaders_custom_uniform",
    "shaders/shaders_deferred_rendering",
    "shaders/shaders_depth_rendering",
    "shaders/shaders_eratosthenes_sieve",
    "shaders/shaders_fog_rendering",
    "shaders/shaders_game_of_life",
    "shaders/shaders_hot_reloading",
    "shaders/shaders_julia_set",
    "shaders/shaders_lightmap_rendering",
    "shaders/shaders_lights_bloom",
    "shaders/shaders_mandelbrot_set",
    "shaders/shaders_mesh_instancing",
    "shaders/shaders_model_shader",
    "shaders/shaders_multi_sample2d",
    "shaders/shaders_normalmap_rendering",
    "shaders/shaders_palette_switch",
    "shaders/shaders_postprocessing",
    "shaders/shaders_rounded_rectangle",
    "shaders/shaders_shadowmap_rendering",
    "shaders/shaders_shapes_textures",
    "shaders/shaders_simple_mask",
    "shaders/shaders_spotlight_rendering",
    "shaders/shaders_texture_outline",
    "shaders/shaders_texture_rendering",
    "shaders/shaders_texture_tiling",
    "shaders/shaders_texture_waves",
    "shaders/shaders_vertex_displacement",
    "models/models_animation_blend_custom",
    "models/models_animation_blending",
    "models/models_animation_gpu_skinning",
    "models/models_animation_timing",
    "models/models_basic_voxel",
    "models/models_billboard_rendering",
    "models/models_bone_socket",
    "models/models_box_collisions",
    "models/models_cubicmap_rendering",
    "models/models_decals",
    "models/models_directional_billboard",
    "models/models_first_person_maze",
    "models/models_geometric_shapes",
    "models/models_heightmap_rendering",
    "models/models_loading",
    "models/models_loading_gltf",
    "models/models_loading_iqm",
    "models/models_loading_m3d",
    "models/models_loading_vox",
    "models/models_mesh_generation",
    "models/models_mesh_picking",
    "models/models_mesh_uv_painting",
    "models/models_orthographic_projection",
    "models/models_point_rendering",
    "models/models_procedural_decals",
    "models/models_rlgl_solar_system",
    "models/models_rotating_cube",
    "models/models_skybox_rendering",
    "models/models_tesseract_view",
    "models/models_textured_cube",
    "models/models_waving_cubes",
    "models/models_yaw_pitch_roll",
    // Browser exclusions, one per line as `// <entry>: <reason>` (docs/web.md):
    // textures/textures_to_image: WebGL 2 cannot glReadPixels an RGB texture (GL_INVALID_OPERATION); C and Zig both draw an unwritten buffer
    // shaders/shaders_rlgl_compute: compute shaders need desktop OpenGL 4.3; WebGL 2 has none
    // shaders/shaders_depth_writing: its GLSL 100 shader needs GL_EXT_frag_depth, which WebGL 2 does not offer to GLSL ES 1.00 shaders
    // shaders/shaders_hybrid_rendering: its GLSL 100 shader needs GL_EXT_frag_depth and GL_OES_standard_derivatives, which WebGL 2 does not offer to GLSL ES 1.00 shaders
    // shaders/shaders_raymarching_rendering: its GLSL 100 shader needs GL_OES_standard_derivatives (fwidth), which WebGL 2 does not offer to GLSL ES 1.00 shaders
    // core/core_window_web: its C version runs its frames through emscripten_set_main_loop, which the gate's frame counter (driven by WindowShouldClose) never sees; the Zig translation uses the normal loop
    // core/core_directory_files: port gap on the web: Zig std has no directory reading for emscripten (dirReadUnimplemented), so LoadDirectoryFiles returns nothing where C lists /tmp, /home, /dev, /proc and /resources
};

const sys_libs = [_][]const u8{ "X11", "Xrandr", "Xinerama", "Xcursor", "Xi", "GL", "m", "pthread", "dl", "rt" };

/// rlgl.h (header-only GL abstraction) is ported to src/rlgl.zig. When true, the
/// swapped build compiles C with -DRAYLIB_ZIG_NO_RLGL_IMPL (so rcore.c stops
/// instantiating rlgl + glad), links src/c/glad_impl.c (the GLAD loader) and the
/// rlgl.zig object instead. The oracle build stays all-C. Flip on once rlgl.zig
/// passes the pixel gate.
const rlgl_ported = true;

/// rcore.c (+ the GLFW platform it #includes) is ported to src/rcore.zig. When
/// true, the swapped build excludes rcore.c, compiles src/rcore.zig, links the
/// sinfl/sdefl/rprand shim (src/c/rcore_impl.c), and links src/rcamera.zig +
/// src/rgestures.zig (rcore.c was the out-of-line instantiation point for
/// raymath/rcamera/rgestures; rcamera.zig also bundles raymath's exports via its
/// import, so no separate raymath object — that would duplicate). GLFW stays C.
const rcore_ported = true;

fn isPorted(name: []const u8) bool {
    for (ported_modules) |m| if (std.mem.eql(u8, m, name)) return true;
    return false;
}

/// Where a library is built for: the platform, and for the web the emsdk whose
/// sysroot headers and translated HTML5 API the build uses.
const LibTarget = struct {
    target: std.Build.ResolvedTarget,
    platform: Platform = .desktop,
    /// The `emscripten` module rcore_web.zig imports (web only).
    emscripten: ?*std.Build.Module = null,
    /// emsdk's sysroot include directory (web only).
    sysroot_include: ?[]const u8 = null,
};

/// Build a static libraylib. `swap = false` forces an all-C build (the oracle);
/// `swap = true` replaces ported `.c` files with their Zig objects.
fn raylibLib(
    b: *std.Build,
    lt: LibTarget,
    optimize: ?std.builtin.Optimize,
    cfg_mod: *std.Build.Module,
    swap: bool,
    name: []const u8,
) *std.Build.Step.Compile {
    const target = lt.target;
    const web = lt.platform == .web;
    const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    mod.addIncludePath(b.path("vendor/raylib/src"));
    mod.addIncludePath(b.path("vendor/raylib/src/external/glfw/include"));
    mod.addIncludePath(b.path("src/c")); // rlgl_impl_defs.h
    if (lt.sysroot_include) |dir| {
        mod.addSystemIncludePath(.{ .cwd_relative = dir });
    } else mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    // (no addLibraryPath here — this is a static archive; system libs are linked
    //  on the final executable in linkExe.)

    // C compile flags: when rlgl is ported, the swapped build adds
    // -DRAYLIB_ZIG_NO_RLGL_IMPL so rcore.c stops instantiating rlgl + glad
    // (provided by src/rlgl.zig + src/c/glad_impl.c instead). Oracle stays all-C.
    const no_rlgl_impl = [_][]const u8{
        "-DRAYLIB_ZIG_NO_RLGL_IMPL",
        // RL_DEFAULT_SHADER_* name constants live in rlgl.h's (now-disabled)
        // IMPLEMENTATION block; rcore.c/rmodels.c still use them. Found through
        // the src/c include path (below), not a path relative to the working
        // directory, so the library also builds as another project's dependency.
        "-includerlgl_impl_defs.h",
    };
    const rlgl_flags = c_defines ++ no_rlgl_impl;
    // The oracle compiles WITHOUT UBSan: its job is producing upstream C's
    // practical reference output, and zig cc's default trap aborts on upstream's
    // own benign-in-practice UB (e.g. rtextures.c ImageKernelConvolution's
    // out-of-range float->uchar, hit by textures_image_kernel). The swapped
    // build keeps UBSan on its remaining C — it has caught real port bugs.
    const oracle_flags = c_defines ++ [_][]const u8{"-fno-sanitize=undefined"};
    // On the web emcc does the final link, and Zig's UBSan runtime comes with a
    // Zig link only: both libraries' C is built without it there.
    const web_rlgl_flags = web_c_defines ++ no_rlgl_impl ++ [_][]const u8{"-fno-sanitize=undefined"};
    const web_oracle_flags = web_c_defines ++ [_][]const u8{"-fno-sanitize=undefined"};
    const c_flags: []const []const u8 = switch (lt.platform) {
        .desktop => if (swap and rlgl_ported) &rlgl_flags else &oracle_flags,
        .web => if (swap and rlgl_ported) &web_rlgl_flags else &web_oracle_flags,
    };

    // GLFW is always C (vendored third-party windowing — never ported). On the
    // web Emscripten supplies GLFW (-sUSE_GLFW=3) against the canvas instead.
    if (!web) mod.addCSourceFile(.{ .file = b.path("vendor/raylib/src/rglfw.c"), .flags = c_flags });

    for (raylib_tus) |tu| {
        const tu_ported = isPorted(tu) or (rcore_ported and std.mem.eql(u8, tu, "rcore.c"));
        if (swap and tu_ported) {
            const stem = tu[0 .. tu.len - 2];
            const obj_mod = b.createModule(.{
                .root_source_file = b.path(b.fmt("src/{s}.zig", .{stem})),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            obj_mod.addImport("config", cfg_mod);
            if (std.mem.eql(u8, stem, "rcore")) {
                if (lt.emscripten) |em| obj_mod.addImport("emscripten", em);
            }
            const obj = b.addObject(.{ .name = stem, .root_module = obj_mod });
            obj.use_llvm = true; // self-hosted x86 backend miscompiles by-value float code
            mod.addObject(obj);
        } else {
            mod.addCSourceFile(.{ .file = b.path(b.fmt("vendor/raylib/src/{s}", .{tu})), .flags = c_flags });
        }
    }

    // rcore swap: rcore.zig (compiled above) replaces rcore.c + the GLFW platform.
    // rcore.c was the out-of-line instantiation point for raymath/rgestures/
    // rcamera and the sinfl/sdefl/rprand libs — provide those now. rcamera.zig
    // bundles raymath's exports via its import (so it covers both); rgestures.zig
    // is standalone. GLFW (rglfw.c) is already compiled above.
    if (swap and rcore_ported) {
        mod.addCSourceFile(.{ .file = b.path("src/c/rcore_impl.c"), .flags = c_flags });
        for ([_][]const u8{ "rcamera", "rgestures" }) |stem| {
            const m = b.createModule(.{
                .root_source_file = b.path(b.fmt("src/{s}.zig", .{stem})),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            const o = b.addObject(.{ .name = stem, .root_module = m });
            o.use_llvm = true;
            mod.addObject(o);
        }
    }

    // rlgl swap: GLAD loader (C shim) + the rlgl.zig object, in the swapped build.
    // On the web rlgl.zig calls WebGL 2 directly (src/gles3.zig): no loader.
    if (swap and rlgl_ported) {
        if (!web) mod.addCSourceFile(.{ .file = b.path("src/c/glad_impl.c"), .flags = c_flags });
        const rlgl_obj = b.addObject(.{ .name = "rlgl", .root_module = b.createModule(.{
            .root_source_file = b.path("src/rlgl.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }) });
        rlgl_obj.use_llvm = true;
        mod.addObject(rlgl_obj);
    }

    // Third-party single-file-lib instantiation shims. A ported module's `.c`
    // used to instantiate stb/qoi/etc. IMPLEMENTATIONS; when ported, those move
    // to a C shim (src/c/<m>_*_impl.c) compiled here so the Zig port can call
    // them via `extern`. Only added in the swapped build, and only for ported
    // modules. (See docs/architecture.md, not-migrated.md.)
    if (swap and isPorted("rtext.c")) {
        mod.addCSourceFile(.{ .file = b.path("src/c/rtext_stb_impl.c"), .flags = c_flags });
    }
    if (swap and isPorted("rtextures.c")) {
        mod.addCSourceFile(.{ .file = b.path("src/c/rtextures_stb_impl.c"), .flags = c_flags });
    }
    if (swap and isPorted("rmodels.c")) {
        mod.addCSourceFile(.{ .file = b.path("src/c/rmodels_impl.c"), .flags = c_flags });
    }
    if (swap and isPorted("raudio.c")) {
        mod.addCSourceFile(.{ .file = b.path("src/c/raudio_impl.c"), .flags = c_flags });
    }

    // NOTE: system libs (X11/GL/…) are linked on the final executable, not here —
    // archiving .so paths into a static lib is wrong and pollutes the archive.
    return b.addLibrary(.{ .name = name, .linkage = .static, .root_module = mod });
}

/// A headless executable linked against the given raylib lib.
fn linkExe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: ?std.builtin.Optimize,
    lib: *std.Build.Step.Compile,
    name: []const u8,
    csrc: []const u8,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    mod.addIncludePath(b.path("vendor/raylib/src"));
    mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    mod.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
    mod.addCSourceFile(.{ .file = b.path(csrc), .flags = &.{"-std=c99"} });
    mod.linkLibrary(lib);
    // Direct -l linking (we know the .so dir via addLibraryPath); skip pkg-config,
    // which isn't configured for GL/mesa in this environment.
    for (sys_libs) |l| mod.linkSystemLibrary(l, .{ .use_pkg_config = .no });
    const exe = b.addExecutable(.{ .name = name, .root_module = mod });
    pinCompilerRtMath(exe);
    return exe;
}

/// Makes `exe` take sinf/cosf/... from compiler_rt, whatever else it links.
/// compiler_rt is one archive member that also carries weak libm functions:
/// once anything pulls it in (Zig code nearly always does), its sinf replaces
/// glibc's. A pure-C oracle pulls it in only by accident of optimization level,
/// so without this the C and Zig sides of a gate could use different libms
/// (found by models_data in ReleaseFast: glTF poses off by a few ULPs).
fn pinCompilerRtMath(exe: *std.Build.Step.Compile) void {
    exe.forceUndefinedSymbol("__multi3"); // defined only by compiler_rt
}

/// The `raygui` binding module over `api` (raygui is linked as C: compiled
/// here with the same flags the gate uses for upstream C examples, so a Zig
/// program and its C counterpart run identical raygui code). On the web that
/// means PLATFORM_WEB (raygui reads scrolling differently there) and no UBSan,
/// which emcc has no runtime for.
fn rayguiModule(b: *std.Build, api: *std.Build.Module, platform: Platform) *std.Build.Module {
    const mod = b.createModule(.{ .root_source_file = b.path("src/raygui/raygui.zig") });
    const c_mod = b.createModule(.{ .root_source_file = b.path("src/raygui/c.zig") });
    c_mod.addImport("raygui", mod);
    mod.addImport("raygui_c", c_mod);
    mod.addImport("raylib", api);
    mod.addIncludePath(b.path("vendor/raygui"));
    mod.addIncludePath(b.path("vendor/raylib/src"));
    mod.addCSourceFile(.{
        .file = b.path("src/c/raygui_impl.c"),
        .flags = switch (platform) {
            .desktop => &.{ "-std=gnu99", "-DPLATFORM_DESKTOP", "-ffp-contract=off" },
            .web => &.{ "-std=gnu99", "-DPLATFORM_WEB", "-ffp-contract=off", "-fno-sanitize=undefined" },
        },
    });
    return mod;
}

/// Shared modules the Zig-API examples import, from examples/zig/common/
/// (rlights and reasings are ported from upstream's example headers; platform
/// holds what upstream picks per platform, such as the GLSL version).
const example_helpers = [_][]const u8{ "rlights", "reasings", "platform" };

/// What every gated Zig-API example links against.
const ApiGate = struct {
    api: *std.Build.Module,
    raygui: *std.Build.Module,
    /// Example-local helpers ported from upstream (rlights, reasings).
    helpers: []const std.Build.Module.Import,
    lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: ?std.builtin.Optimize,
};

/// One Zig-API example executable (examples/zig/<entry>.zig) on the gate
/// API instance plus the exdiff determinism hooks.
fn apiExample(b: *std.Build, gate: ApiGate, entry: []const u8, name: []const u8) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("examples/zig/{s}.zig", .{entry})),
        .target = gate.target,
        .optimize = gate.optimize,
        .link_libc = true,
    });
    mod.addImport("raylib", gate.api);
    mod.addImport("raygui", gate.raygui);
    for (gate.helpers) |helper| mod.addImport(helper.name, helper.module);
    mod.addIncludePath(b.path("vendor/raylib/src"));
    mod.addCSourceFile(.{ .file = b.path("tools/exdiff/hooks.c"), .flags = &.{"-std=c99"} });
    for (api_example_c_shims) |shim| {
        if (!std.mem.eql(u8, shim, entry)) continue;
        mod.addCSourceFile(.{ .file = b.path(b.fmt("examples/zig/{s}_shim.c", .{entry})), .flags = &.{ "-std=c99", "-ffp-contract=off" } });
    }
    mod.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
    mod.linkLibrary(gate.lib);
    for (sys_libs) |l| mod.linkSystemLibrary(l, .{ .use_pkg_config = .no });
    const exe = b.addExecutable(.{ .name = name, .root_module = mod });
    exe.use_llvm = true;
    return exe;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Comptime config for ported Zig modules (mirrors the C -D flags that affect
    // struct layout / behavior). Expand as deeply-coupled modules land.
    const cfg = b.addOptions();
    cfg.addOption(u32, "opengl_version", 33);
    const cfg_mod = cfg.createModule();

    // Production library (ported Zig swapped in) — installed.
    const lib = raylibLib(b, .{ .target = target }, optimize, cfg_mod, true, "raylib");
    b.installArtifact(lib);

    // All-C oracle library (never swapped) — for the differential gate.
    const oracle = raylibLib(b, .{ .target = target }, optimize, cfg_mod, false, "raylib_oracle");

    // Headless demo against the production lib.
    const demo = linkExe(b, target, optimize, lib, "demo", "test/scene_runner.c");
    b.installArtifact(demo);
    const demo_run = b.addRunArtifact(demo);
    demo_run.addArg("zig-out/frames");
    b.step("demo", "Run the headless scene_runner demo (dumps to zig-out/frames)").dependOn(&demo_run.step);

    // `raylib` module — the idiomatic Zig API (docs/zig-api.md), generated by
    // tools/gen_api.py. Package consumers: `const rl = @import("raylib");`.
    const api_mod = b.addModule("raylib", .{
        .root_source_file = b.path("src/api/raylib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const api_c_mod = b.createModule(.{ .root_source_file = b.path("src/api/c.zig") });
    api_c_mod.addImport("raylib", api_mod);
    api_mod.addImport("raylib_c", api_c_mod);
    api_mod.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
    api_mod.linkLibrary(lib);
    for (sys_libs) |l| api_mod.linkSystemLibrary(l, .{ .use_pkg_config = .no });
    // `raygui` module — Zig binding for raygui (vendor/raygui, linked as C).
    b.modules.put(b.graph.arena, b.dupe("raygui"), rayguiModule(b, api_mod, .desktop)) catch @panic("OOM");

    // `zig build apitest` — API structs layout-identical to raylib.h (via
    // translate-c), every wrapper compiles, enum/flag/color values match.
    {
        const raylib_h = b.addTranslateC(.{
            .root_source_file = b.path("vendor/raylib/src/raylib.h"),
            .target = target,
            .optimize = optimize orelse .Debug,
        });
        const test_mod = b.createModule(.{
            .root_source_file = b.path("test/api_test.zig"),
            .target = target,
            .optimize = optimize,
        });
        test_mod.addImport("raylib", api_mod);
        test_mod.addImport("raygui", b.modules.get("raygui").?);
        test_mod.addImport("c_raylib", raylib_h.createModule());
        const rlgl_h = b.addTranslateC(.{
            .root_source_file = b.path("vendor/raylib/src/rlgl.h"),
            .target = target,
            .optimize = optimize orelse .Debug,
        });
        rlgl_h.defineCMacro("GRAPHICS_API_OPENGL_33", null);
        test_mod.addImport("c_rlgl", rlgl_h.createModule());
        const api_tests = b.addTest(.{ .root_module = test_mod });
        api_tests.use_llvm = true;
        b.step("apitest", "Check the idiomatic Zig API against raylib.h").dependOn(&b.addRunArtifact(api_tests).step);
    }

    // `zig build apiexamples` — the API's behavioral gate: Zig-API translations
    // of upstream examples (examples/zig/<category>/<name>.zig) must render the
    // final frame byte-identical to the upstream C example on the C oracle.
    // They build against a second instance of the API whose `raylib_c`
    // boundary is the generated c_exdiff.zig (determinism hooks, as shim.h
    // does for C), linked to the Zig-swapped library.
    {
        const gate_api = b.createModule(.{
            .root_source_file = b.path("src/api/raylib.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const gate_c = b.createModule(.{ .root_source_file = b.path("src/api/c_exdiff.zig") });
        gate_c.addImport("raylib", gate_api);
        gate_api.addImport("raylib_c", gate_c);
        // Shared helper modules ported from the raylib-authored headers that
        // sit next to the upstream examples (rlights.h, reasings.h).
        var helpers: [example_helpers.len]std.Build.Module.Import = undefined;
        for (&helpers, example_helpers) |*helper, helper_name| {
            const helper_mod = b.createModule(.{ .root_source_file = b.path(b.fmt("examples/zig/common/{s}.zig", .{helper_name})) });
            helper_mod.addImport("raylib", gate_api);
            helper.* = .{ .name = helper_name, .module = helper_mod };
        }
        const gate: ApiGate = .{
            .api = gate_api,
            .raygui = rayguiModule(b, gate_api, .desktop),
            .helpers = &helpers,
            .lib = lib,
            .target = target,
            .optimize = optimize,
        };

        const step = b.step("apiexamples", "Zig-API example translations vs upstream C examples (pixel diff)");
        const list = b.addWriteFiles();
        var list_text: std.ArrayList(u8) = .empty;
        const bin_dir = b.addWriteFiles();
        for (api_examples) |entry| {
            const category = entry[0..std.mem.indexOfScalar(u8, entry, '/').?];
            const name = entry[category.len + 1 ..];
            list_text.appendSlice(b.allocator, b.fmt("{s}/{s}.c\n", .{ category, name })) catch @panic("OOM");

            const exe = apiExample(b, gate, entry, name);
            _ = bin_dir.addCopyFile(exe.getEmittedBin(), name);
        }
        for (api_examples_build_only) |entry| {
            const name = entry[std.mem.indexOfScalar(u8, entry, '/').? + 1 ..];
            step.dependOn(&apiExample(b, gate, entry, name).step);
        }
        const list_file = list.add("apiexamples.list", list_text.items);

        const diff = b.addSystemCommand(&.{"tools/exdiff.sh"});
        diff.addArtifactArg(oracle);
        diff.addArtifactArg(lib);
        // -Dapi-filter=<substring>: only diff matching examples (all are still built).
        diff.addArg(b.option([]const u8, "api-filter", "apiexamples: only diff examples whose path contains this") orelse "");
        diff.addFileArg(list_file);
        diff.addDirectoryArg(bin_dir.getDirectory()); // Zig-API binaries, one per example
        diff.has_side_effects = true;
        step.dependOn(&diff.step);
    }

    addWeb(b, optimize, cfg_mod);

    // `zig build angrybirds` — Angry Birds capstone demo (Zig game over the C ABI).
    {
        const ab_mod = b.createModule(.{
            .root_source_file = b.path("examples/angrybirds/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        ab_mod.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
        ab_mod.linkLibrary(lib);
        for (sys_libs) |l| ab_mod.linkSystemLibrary(l, .{ .use_pkg_config = .no });
        const ab = b.addExecutable(.{ .name = "angrybirds", .root_module = ab_mod });
        ab.use_llvm = true; // self-hosted x86 backend miscompiles by-value float code
        b.installArtifact(ab);
        const ab_run = b.addRunArtifact(ab);
        b.step("angrybirds", "Run the Angry Birds slingshot demo").dependOn(&ab_run.step);
    }

    // Two scene runners — identical source, one per library.
    const runner_zig = linkExe(b, target, optimize, lib, "scene_runner_zig", "test/scene_runner.c");
    const runner_c = linkExe(b, target, optimize, oracle, "scene_runner_oracle", "test/scene_runner.c");
    b.installArtifact(runner_zig);
    b.installArtifact(runner_c);
    const runners = b.step("runners", "Build both scene_runner executables");
    runners.dependOn(&b.addInstallArtifact(runner_zig, .{}).step);
    runners.dependOn(&b.addInstallArtifact(runner_c, .{}).step);

    // `zig build test` — the differential gate. Renders the scene battery through
    // both libraries under llvmpipe and byte-diffs the framebuffers.
    const diff = b.addSystemCommand(&.{"tools/scenediff.sh"});
    diff.addArtifactArg(runner_c);
    diff.addArtifactArg(runner_zig);
    const test_step = b.step("test", "C-vs-Zig framebuffer diff under llvmpipe (the migration gate)");
    test_step.dependOn(&diff.step);

    // `zig build datacheck` — validate the Zig rcore data functions (CRC32/SHA/
    // Base64/Compress) against published vectors (the pixel gate misses these).
    const datacheck = linkExe(b, target, optimize, lib, "datacheck", "test/datacheck.c");
    const datacheck_run = b.addRunArtifact(datacheck);
    b.step("datacheck", "Validate rcore data functions vs known vectors").dependOn(&datacheck_run.step);

    // `zig build audiocheck` — the raudio differential gate. Decodes the audio
    // asset battery (WAV/OGG/MP3/QOA + wave ops + export + music metadata)
    // through both libraries and byte-diffs the reports (PCM hashes included).
    const audiocheck_zig = linkExe(b, target, optimize, lib, "audiocheck_zig", "test/audiocheck.c");
    const audiocheck_c = linkExe(b, target, optimize, oracle, "audiocheck_oracle", "test/audiocheck.c");
    const audiodiff = b.addSystemCommand(&.{"tools/audiodiff.sh"});
    audiodiff.addArtifactArg(audiocheck_c);
    audiodiff.addArtifactArg(audiocheck_zig);
    b.step("audiocheck", "C-vs-Zig audio decode diff (the raudio gate)").dependOn(&audiodiff.step);

    // `zig build cdiff` — direct C-vs-Zig differentials for paths the examples
    // gate can't reach (input-gated branches, edge-case parameters). Each
    // test/cdiff program is linked against both libraries; tools/cdiff.sh runs
    // the pair with identical args and byte-diffs stdout.
    {
        const cdiff_step = b.step("cdiff", "C-vs-Zig differentials for paths the examples can't reach");
        const fonts_dir = "/home/rajesh/opensource/graphics/raylib-6.2/examples/text/resources";
        const programs = [_]struct { name: []const u8, args: []const []const u8 }{
            .{ .name = "text_strings", .args = &.{} },
            .{ .name = "core_files", .args = &.{} },
            .{ .name = "core_fileio", .args = &.{} },
            .{ .name = "core_automation", .args = &.{} },
            .{ .name = "shapes_sweep", .args = &.{} },
            .{ .name = "rlgl_paths", .args = &.{} },
            .{ .name = "shapes_paths", .args = &.{} },
            .{ .name = "audio_wave", .args = &.{} },
            .{ .name = "image_ops", .args = &.{"/home/rajesh/opensource/graphics/raylib-6.2/examples/textures/resources/scarfy_run.gif"} },
            .{ .name = "text_fonts", .args = &.{fonts_dir} },
            .{ .name = "models_data", .args = &.{"/home/rajesh/opensource/graphics/raylib-6.2/examples"} },
            .{ .name = "font_data", .args = &.{
                fonts_dir ++ "/anonymous_pro_bold.ttf",
                fonts_dir ++ "/pixantiqua.ttf",
                fonts_dir ++ "/NotoSansTC-Regular.ttf",
                fonts_dir ++ "/DotGothic16-Regular.ttf",
            } },
        };
        for (programs) |p| {
            const src = b.fmt("test/cdiff/{s}.c", .{p.name});
            const exe_c = linkExe(b, target, optimize, oracle, b.fmt("{s}_oracle", .{p.name}), src);
            const exe_zig = linkExe(b, target, optimize, lib, b.fmt("{s}_zig", .{p.name}), src);
            const run = b.addSystemCommand(&.{"tools/cdiff.sh"});
            run.addArtifactArg(exe_c);
            run.addArtifactArg(exe_zig);
            run.addArgs(p.args);
            run.has_side_effects = true;
            cdiff_step.dependOn(&run.step);
        }
    }

    // `zig build mathtest` — raymath bit-exact numeric gate. Builds the C oracle
    // (raymath.h inline, strict IEEE) and the Zig harness (linked against the
    // raymath.zig exports), runs both over the same input stream, diffs raw float
    // bits. Only meaningful once src/raymath.zig exists (Phase 1); the default
    // `zig build` never touches this step.
    {
        const raymath_obj = b.addObject(.{
            .name = "raymath",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/raymath.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true, // raymath calls libm (sinf/cosf/...) for bit-exactness
            }),
        });
        // Zig 0.17-dev's self-hosted x86 backend miscompiles some by-value-struct
        // float code (InvalidInstruction on *MoveTowards); use the LLVM backend.
        raymath_obj.use_llvm = true;

        const zig_harness_mod = b.createModule(.{
            .root_source_file = b.path("test/mathgrid.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        zig_harness_mod.addObject(raymath_obj);
        const zig_harness = b.addExecutable(.{ .name = "mathgrid_zig", .root_module = zig_harness_mod });
        zig_harness.use_llvm = true;

        const c_oracle_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
        c_oracle_mod.addIncludePath(b.path("vendor/raylib/src"));
        c_oracle_mod.addCSourceFile(.{
            .file = b.path("test/mathgrid.c"),
            .flags = &.{ "-DRAYMATH_STATIC_INLINE", "-ffp-contract=off", "-std=c99" },
        });
        c_oracle_mod.linkSystemLibrary("m", .{ .use_pkg_config = .no });
        const c_oracle = b.addExecutable(.{ .name = "mathgrid_c", .root_module = c_oracle_mod });

        const mathdiff = b.addSystemCommand(&.{"tools/mathdiff.sh"});
        mathdiff.addArtifactArg(c_oracle);
        mathdiff.addArtifactArg(zig_harness);
        b.step("mathtest", "raymath bit-exact numeric diff (C vs Zig)").dependOn(&mathdiff.step);
    }

    // `zig build camtest` — rcamera bit-exact numeric diff. The Zig rcamera
    // object imports the (bit-exact) Zig raymath; the C oracle uses rcamera.h in
    // RCAMERA_STANDALONE mode with strict-IEEE raymath.h.
    {
        const rcam_obj = b.addObject(.{ .name = "rcamera", .root_module = b.createModule(.{
            .root_source_file = b.path("src/rcamera.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }) });
        rcam_obj.use_llvm = true;

        const zmod = b.createModule(.{
            .root_source_file = b.path("test/camgrid.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        zmod.addObject(rcam_obj);
        const zexe = b.addExecutable(.{ .name = "camgrid_zig", .root_module = zmod });
        zexe.use_llvm = true;

        const cmod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
        cmod.addIncludePath(b.path("vendor/raylib/src"));
        cmod.addCSourceFile(.{
            .file = b.path("test/camgrid.c"),
            .flags = &.{ "-DRAYMATH_STATIC_INLINE", "-ffp-contract=off", "-std=c99" },
        });
        cmod.linkSystemLibrary("m", .{ .use_pkg_config = .no });
        const cexe = b.addExecutable(.{ .name = "camgrid_c", .root_module = cmod });

        const camdiff = b.addSystemCommand(&.{"tools/camdiff.sh"});
        camdiff.addArtifactArg(cexe);
        camdiff.addArtifactArg(zexe);
        b.step("camtest", "rcamera bit-exact numeric diff (C vs Zig)").dependOn(&camdiff.step);
    }

    // `zig build gesttest` — rgestures bit-exact numeric diff. Both builds use a
    // harness-controlled GetTime() clock so the time-dependent gesture logic is
    // deterministic.
    {
        const rg_obj = b.addObject(.{ .name = "rgestures", .root_module = b.createModule(.{
            .root_source_file = b.path("src/rgestures.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }) });
        rg_obj.use_llvm = true;

        const zmod = b.createModule(.{
            .root_source_file = b.path("test/gestgrid.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        zmod.addObject(rg_obj);
        const zexe = b.addExecutable(.{ .name = "gestgrid_zig", .root_module = zmod });
        zexe.use_llvm = true;

        const cmod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
        cmod.addIncludePath(b.path("vendor/raylib/src"));
        cmod.addCSourceFile(.{
            .file = b.path("test/gestgrid.c"),
            .flags = &.{ "-DPLATFORM_DESKTOP_GLFW", "-DGRAPHICS_API_OPENGL_33", "-ffp-contract=off", "-std=c99", "-w" },
        });
        cmod.linkSystemLibrary("m", .{ .use_pkg_config = .no });
        const cexe = b.addExecutable(.{ .name = "gestgrid_c", .root_module = cmod });

        const gestdiff = b.addSystemCommand(&.{"tools/gestdiff.sh"});
        gestdiff.addArtifactArg(cexe);
        gestdiff.addArtifactArg(zexe);
        b.step("gesttest", "rgestures bit-exact numeric diff (C vs Zig)").dependOn(&gestdiff.step);
    }
}

/// emcc settings shared by every web example, C oracle and Zig alike.
const emcc_flags = [_][]const u8{
    // Emscripten supplies GLFW 3 against the canvas (PLATFORM_WEB runs on it).
    "-sUSE_GLFW=3",
    // The examples keep raylib's `while (!WindowShouldClose())` loop; Asyncify lets
    // WindowShouldClose yield to the browser (emscripten_sleep) mid-loop.
    "-sASYNCIFY",
    // rlgl is built for OpenGL ES 3, which needs a WebGL 2 context.
    "-sMIN_WEBGL_VERSION=2",
    "-sMAX_WEBGL_VERSION=2",
    "-sALLOW_MEMORY_GROWTH=1",
    "-sSTACK_SIZE=1048576",
    "-sFORCE_FILESYSTEM=1",
    // A factory function (`createExample(config)`) instead of a global `Module`,
    // so a page decides when an example starts and which canvas it gets.
    "-sMODULARIZE=1",
    "-sEXPORT_NAME=createExample",
    // FS and ENV: the gate passes EXDIFF_* through ENV and reads the final
    // frame back from MEMFS.
    "-sEXPORTED_RUNTIME_METHODS=FS,ENV",
    "-O2",
    // A Zig extern whose signature differs from the C definition links on wasm
    // with only a warning, and the call becomes a trap (RuntimeError:
    // unreachable). x86-64 hides such bugs: par_shapes_set_epsilon_degenerate_sphere
    // was declared f64 for a C float and passed 0.0 correctly by luck.
    "-Wl,--fatal-warnings",
};

/// One example linked by emcc into <name>.js + .wasm (+ .data). The .data
/// bundle holds `files` (paths under the category's resources/), or the whole
/// resources/ directory when `files` is null. Returns the directory holding them.
fn emccLink(
    b: *std.Build,
    emcc_path: []const u8,
    name: []const u8,
    category: []const u8,
    inputs: []const *std.Build.Step.Compile,
    js_library: ?std.Build.LazyPath,
    files: ?[]const []const u8,
) std.Build.LazyPath {
    const emcc = b.addSystemCommand(&.{emcc_path});
    for (inputs) |input| emcc.addArtifactArg(input);
    emcc.addArgs(&emcc_flags);
    if (js_library) |js| {
        emcc.addArg("--js-library");
        emcc.addFileArg(js);
    }
    // Examples load "resources/..." relative to the working directory, which is
    // MEMFS's root on the web.
    const resources = b.fmt("{s}/{s}/resources", .{ raylib_examples, category });
    // `*` (an example that lists a directory) means the whole resources/.
    const whole = if (files) |list| list.len == 1 and std.mem.eql(u8, list[0], "*") else true;
    if (!whole) {
        for (files.?) |file| emcc.addArgs(&.{ "--preload-file", b.fmt("{s}/{s}@resources/{s}", .{ resources, file, file }) });
    } else if (std.Io.Dir.cwd().access(b.graph.io, resources, .{})) |_| {
        emcc.addArgs(&.{ "--preload-file", b.fmt("{s}@resources", .{resources}) });
    } else |_| {}
    emcc.addArg("-o");
    return emcc.addOutputFileArg(b.fmt("{s}.js", .{name})).dirname();
}

const raylib_examples = "/home/rajesh/opensource/graphics/raylib-6.2/examples";

/// test/web_resources.list (written by `zig build webresources`): for each web
/// example, the resource files it loads. Lines are `<category>/<name>: <file>...`.
fn webResources(b: *std.Build) std.StringHashMapUnmanaged([]const []const u8) {
    var map: std.StringHashMapUnmanaged([]const []const u8) = .empty;
    const text = std.Io.Dir.cwd().readFileAlloc(b.graph.io, "test/web_resources.list", b.allocator, .limited(1 << 20)) catch return map;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        var files: std.ArrayList([]const u8) = .empty;
        var it = std.mem.tokenizeScalar(u8, line[colon + 1 ..], ' ');
        while (it.next()) |file| files.append(b.allocator, file) catch @panic("OOM");
        map.put(b.allocator, line[0..colon], files.items) catch @panic("OOM");
    }
    return map;
}

/// `zig build web` and `zig build webexamples`: the port's web target.
///
/// Zig compiles the library (Zig modules + the bundled C) for wasm32-emscripten,
/// and emcc links each program, because the JavaScript glue and the WebGL
/// context are things only Emscripten emits. `web` installs the Zig library;
/// `webexamples` is the browser gate over `web_examples`: the upstream C example
/// on the all-C library (the oracle) and the Zig-API translation on the Zig
/// library, each run in headless Chrome by tools/webdiff.sh, final frames
/// byte-compared.
fn addWeb(b: *std.Build, optimize: ?std.builtin.Optimize, cfg_mod: *std.Build.Module) void {
    const web_step = b.step("web", "Build the Zig raylib for the browser (wasm32-emscripten)");
    const demos_step = b.step("webdemos", "Browser builds of the web examples for the site (zig-out/web/examples)");
    const gate_step = b.step("webexamples", "Browser gate: web examples, C vs Zig, in headless Chrome");
    const resources_step = b.step("webresources", "Record the resource files each web example loads (test/web_resources.list)");

    const emsdk = b.option([]const u8, "emsdk", "Path to the Emscripten SDK (default: $EMSDK)") orelse
        b.graph.environ_map.get("EMSDK") orelse {
        const fail = b.addFail("no Emscripten SDK: pass -Demsdk=/path/to/emsdk, or source emsdk_env.sh");
        web_step.dependOn(&fail.step);
        gate_step.dependOn(&fail.step);
        demos_step.dependOn(&fail.step);
        resources_step.dependOn(&fail.step);
        return;
    };
    const emcc_path = b.pathJoin(&.{ emsdk, "upstream", "emscripten", "emcc" });
    const sysroot_include = b.pathJoin(&.{ emsdk, "upstream", "emscripten", "cache", "sysroot", "include" });

    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .emscripten });

    // Emscripten's HTML5 API for rcore_web.zig, from emsdk's own headers.
    const em_h = b.addTranslateC(.{
        .root_source_file = b.path("src/platforms/emscripten.h"),
        .target = target,
        .optimize = optimize orelse .Debug,
        .link_libc = true,
    });
    em_h.addSystemIncludePath(.{ .cwd_relative = sysroot_include });

    const lt: LibTarget = .{
        .target = target,
        .platform = .web,
        .emscripten = em_h.createModule(),
        .sysroot_include = sysroot_include,
    };
    const lib = raylibLib(b, lt, optimize, cfg_mod, true, "raylib");
    const oracle = raylibLib(b, lt, optimize, cfg_mod, false, "raylib_oracle");
    web_step.dependOn(&b.addInstallArtifact(lib, .{ .dest_dir = .{ .override = .{ .custom = "web" } } }).step);
    const js_library = b.path("src/platforms/rcore_web.js");
    web_step.dependOn(&b.addInstallFile(js_library, "web/rcore_web.js").step);

    // The Zig-API boundary with the exdiff hooks (as `apiexamples` uses).
    const gate_api = b.createModule(.{
        .root_source_file = b.path("src/api/raylib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const gate_c = b.createModule(.{ .root_source_file = b.path("src/api/c_exdiff.zig") });
    gate_c.addImport("raylib", gate_api);
    gate_api.addImport("raylib_c", gate_c);
    const raygui = rayguiModule(b, gate_api, .web);
    raygui.addSystemIncludePath(.{ .cwd_relative = sysroot_include });
    var helpers: [example_helpers.len]std.Build.Module.Import = undefined;
    for (&helpers, example_helpers) |*helper, helper_name| {
        const helper_mod = b.createModule(.{ .root_source_file = b.path(b.fmt("examples/zig/common/{s}.zig", .{helper_name})) });
        helper_mod.addImport("raylib", gate_api);
        helper.* = .{ .name = helper_name, .module = helper_mod };
    }

    // The API as programs use it (no determinism hooks), for the site's demos.
    const demo_api = b.createModule(.{
        .root_source_file = b.path("src/api/raylib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const demo_c = b.createModule(.{ .root_source_file = b.path("src/api/c.zig") });
    demo_c.addImport("raylib", demo_api);
    demo_api.addImport("raylib_c", demo_c);
    const demo_raygui = rayguiModule(b, demo_api, .web);
    demo_raygui.addSystemIncludePath(.{ .cwd_relative = sysroot_include });
    var demo_helpers: [example_helpers.len]std.Build.Module.Import = undefined;
    for (&demo_helpers, example_helpers) |*helper, helper_name| {
        const helper_mod = b.createModule(.{ .root_source_file = b.path(b.fmt("examples/zig/common/{s}.zig", .{helper_name})) });
        helper_mod.addImport("raylib", demo_api);
        helper.* = .{ .name = helper_name, .module = helper_mod };
    }

    const c_flags = [_][]const u8{ "-std=gnu99", "-DPLATFORM_WEB", "-ffp-contract=off", "-fno-sanitize=undefined", "-w" };

    const c_dirs = b.addWriteFiles();
    const zig_dirs = b.addWriteFiles();
    var list_text: std.ArrayList(u8) = .empty;
    var entries_text: std.ArrayList(u8) = .empty;
    // The C oracle always gets its category's whole resources/; the Zig builds
    // get only the files listed, so the gate proves the list is enough.
    const resources = webResources(b);
    for (web_examples) |entry| {
        const category = entry[0..std.mem.indexOfScalar(u8, entry, '/').?];
        const name = entry[category.len + 1 ..];
        list_text.appendSlice(b.allocator, b.fmt("{s}\n", .{name})) catch @panic("OOM");
        entries_text.appendSlice(b.allocator, b.fmt("{s}\n", .{entry})) catch @panic("OOM");
        const files = resources.get(entry) orelse files: {
            const fail = b.addFail(b.fmt("{s} is not in test/web_resources.list: run zig build webresources -Demsdk=...", .{entry}));
            gate_step.dependOn(&fail.step);
            demos_step.dependOn(&fail.step);
            break :files null;
        };

        // C oracle: the unmodified upstream example, shimmed for determinism.
        const c_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
        c_mod.addIncludePath(b.path("vendor/raylib/src"));
        c_mod.addIncludePath(.{ .cwd_relative = b.fmt("{s}/{s}", .{ raylib_examples, category }) });
        c_mod.addSystemIncludePath(.{ .cwd_relative = sysroot_include });
        c_mod.addCSourceFile(.{
            .file = .{ .cwd_relative = b.fmt("{s}/{s}.c", .{ raylib_examples, entry }) },
            .flags = &(c_flags ++ [_][]const u8{"-includetools/exdiff/shim.h"}),
        });
        c_mod.addCSourceFiles(.{ .files = &.{ "tools/exdiff/driver.c", "tools/exdiff/hooks.c" }, .flags = &c_flags });
        const c_lib = b.addLibrary(.{ .name = b.fmt("{s}_c", .{name}), .linkage = .static, .root_module = c_mod });
        const c_out = emccLink(b, emcc_path, name, category, &.{ c_lib, oracle }, null, null);
        _ = c_dirs.addCopyDirectory(c_out, name, .{});

        // Zig: the Zig-API translation on the Zig library.
        const z_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/zig/{s}.zig", .{entry})),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        z_mod.addImport("raylib", gate_api);
        z_mod.addImport("raygui", raygui);
        for (helpers) |helper| z_mod.addImport(helper.name, helper.module);
        z_mod.addIncludePath(b.path("vendor/raylib/src"));
        z_mod.addSystemIncludePath(.{ .cwd_relative = sysroot_include });
        z_mod.addCSourceFile(.{ .file = b.path("tools/exdiff/hooks.c"), .flags = &c_flags });
        for (api_example_c_shims) |shim| {
            if (std.mem.eql(u8, shim, entry)) z_mod.addCSourceFile(.{ .file = b.path(b.fmt("examples/zig/{s}_shim.c", .{entry})), .flags = &c_flags });
        }
        const z_lib = b.addLibrary(.{ .name = name, .linkage = .static, .root_module = z_mod });
        z_lib.use_llvm = true;
        const z_out = emccLink(b, emcc_path, name, category, &.{ z_lib, lib }, js_library, files);
        _ = zig_dirs.addCopyDirectory(z_out, name, .{});

        // The same translation for the site: the real API, the real main loop.
        const d_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/zig/{s}.zig", .{entry})),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        d_mod.addImport("raylib", demo_api);
        d_mod.addImport("raygui", demo_raygui);
        for (demo_helpers) |helper| d_mod.addImport(helper.name, helper.module);
        // The example's own C (e.g. a single-header library), as on the desktop.
        for (api_example_c_shims) |shim| {
            if (!std.mem.eql(u8, shim, entry)) continue;
            d_mod.addIncludePath(b.path("vendor/raylib/src"));
            d_mod.addSystemIncludePath(.{ .cwd_relative = sysroot_include });
            d_mod.addCSourceFile(.{ .file = b.path(b.fmt("examples/zig/{s}_shim.c", .{entry})), .flags = &c_flags });
        }
        const d_lib = b.addLibrary(.{ .name = b.fmt("{s}_demo", .{name}), .linkage = .static, .root_module = d_mod });
        d_lib.use_llvm = true;
        const d_out = emccLink(b, emcc_path, name, category, &.{ d_lib, lib }, js_library, files);
        demos_step.dependOn(&b.addInstallDirectory(.{
            .source_dir = d_out,
            .install_dir = .{ .custom = "web/examples" },
            .install_subdir = name,
        }).step);
    }
    const list = b.addWriteFiles().add("webexamples.list", list_text.items);

    const diff = b.addSystemCommand(&.{"tools/webdiff.sh"});
    diff.addDirectoryArg(c_dirs.getDirectory());
    diff.addDirectoryArg(zig_dirs.getDirectory());
    diff.addFileArg(list);
    diff.addArg(b.option([]const u8, "web-filter", "webexamples: only diff examples whose name contains this") orelse "");
    // Each passing example's final frame, for the site's gallery thumbnails.
    diff.addArg("zig-out/web/frames"); // from the project root, as the script itself
    diff.has_side_effects = true;
    gate_step.dependOn(&diff.step);

    const record = b.addSystemCommand(&.{ "node", "tools/webdiff/resources.mjs" });
    record.addDirectoryArg(c_dirs.getDirectory());
    record.addFileArg(b.addWriteFiles().add("webentries.list", entries_text.items));
    record.addArg(raylib_examples);
    record.addArg("test/web_resources.list"); // run from the project root, as webdiff.sh
    record.has_side_effects = true;
    resources_step.dependOn(&record.step);
}
