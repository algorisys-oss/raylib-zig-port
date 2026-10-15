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

/// Compile defines pinning the Linux/GLFW/GL3.3 configuration. Proven to build
/// and render headlessly under both the GPU and llvmpipe.
const c_defines = [_][]const u8{
    "-DPLATFORM_DESKTOP_GLFW",
    "-DGRAPHICS_API_OPENGL_33",
    "-D_GNU_SOURCE",
    "-D_GLFW_X11",
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

/// Build a static libraylib. `swap = false` forces an all-C build (the oracle);
/// `swap = true` replaces ported `.c` files with their Zig objects.
fn raylibLib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: ?std.builtin.Optimize,
    cfg_mod: *std.Build.Module,
    swap: bool,
    name: []const u8,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    mod.addIncludePath(b.path("vendor/raylib/src"));
    mod.addIncludePath(b.path("vendor/raylib/src/external/glfw/include"));
    mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    // (no addLibraryPath here — this is a static archive; system libs are linked
    //  on the final executable in linkExe.)

    // C compile flags: when rlgl is ported, the swapped build adds
    // -DRAYLIB_ZIG_NO_RLGL_IMPL so rcore.c stops instantiating rlgl + glad
    // (provided by src/rlgl.zig + src/c/glad_impl.c instead). Oracle stays all-C.
    const rlgl_flags = c_defines ++ [_][]const u8{
        "-DRAYLIB_ZIG_NO_RLGL_IMPL",
        // RL_DEFAULT_SHADER_* name constants live in rlgl.h's (now-disabled)
        // IMPLEMENTATION block; rcore.c/rmodels.c still use them.
        "-includesrc/c/rlgl_impl_defs.h",
    };
    // The oracle compiles WITHOUT UBSan: its job is producing upstream C's
    // practical reference output, and zig cc's default trap aborts on upstream's
    // own benign-in-practice UB (e.g. rtextures.c ImageKernelConvolution's
    // out-of-range float->uchar, hit by textures_image_kernel). The swapped
    // build keeps UBSan on its remaining C — it has caught real port bugs.
    const oracle_flags = c_defines ++ [_][]const u8{"-fno-sanitize=undefined"};
    const c_flags: []const []const u8 = if (swap and rlgl_ported) &rlgl_flags else &oracle_flags;

    // GLFW is always C (vendored third-party windowing — never ported).
    mod.addCSourceFile(.{ .file = b.path("vendor/raylib/src/rglfw.c"), .flags = c_flags });

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
    if (swap and rlgl_ported) {
        mod.addCSourceFile(.{ .file = b.path("src/c/glad_impl.c"), .flags = c_flags });
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
    return b.addExecutable(.{ .name = name, .root_module = mod });
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
    const lib = raylibLib(b, target, optimize, cfg_mod, true, "raylib");
    b.installArtifact(lib);

    // All-C oracle library (never swapped) — for the differential gate.
    const oracle = raylibLib(b, target, optimize, cfg_mod, false, "raylib_oracle");

    // Headless demo against the production lib.
    const demo = linkExe(b, target, optimize, lib, "demo", "test/scene_runner.c");
    b.installArtifact(demo);
    const demo_run = b.addRunArtifact(demo);
    demo_run.addArg("zig-out/frames");
    b.step("demo", "Run the headless scene_runner demo (dumps to zig-out/frames)").dependOn(&demo_run.step);

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
