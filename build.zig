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
const ported_modules = [_][]const u8{};

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
};

const sys_libs = [_][]const u8{ "X11", "Xrandr", "Xinerama", "Xcursor", "Xi", "GL", "m", "pthread", "dl", "rt" };

fn isPorted(name: []const u8) bool {
    for (ported_modules) |m| if (std.mem.eql(u8, m, name)) return true;
    return false;
}

/// Build a static libraylib. `swap = false` forces an all-C build (the oracle);
/// `swap = true` replaces ported `.c` files with their Zig objects.
fn raylibLib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
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

    // GLFW is always C (vendored third-party windowing — never ported).
    mod.addCSourceFile(.{ .file = b.path("vendor/raylib/src/rglfw.c"), .flags = &c_defines });

    for (raylib_tus) |tu| {
        if (swap and isPorted(tu)) {
            const stem = tu[0 .. tu.len - 2];
            const obj_mod = b.createModule(.{
                .root_source_file = b.path(b.fmt("src/{s}.zig", .{stem})),
                .target = target,
                .optimize = optimize,
            });
            obj_mod.addImport("config", cfg_mod);
            mod.addObject(b.addObject(.{ .name = stem, .root_module = obj_mod }));
        } else {
            mod.addCSourceFile(.{ .file = b.path(b.fmt("vendor/raylib/src/{s}", .{tu})), .flags = &c_defines });
        }
    }

    // NOTE: system libs (X11/GL/…) are linked on the final executable, not here —
    // archiving .so paths into a static lib is wrong and pollutes the archive.
    return b.addLibrary(.{ .name = name, .linkage = .static, .root_module = mod });
}

/// A headless executable linked against the given raylib lib.
fn linkExe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
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
}
