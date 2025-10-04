const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get raylib dependency
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    // Create the rlOpenXR library module
    const rlOpenXR_mod = b.addModule("rlOpenXR", .{
        .root_source_file = b.path("src/rlOpenXR.zig"),
        .target = target,
        .optimize = optimize,
    });

    const rlOpenXR = b.addLibrary(.{
        .linkage = .static,
        .name = "rlOpenXR",
        .root_module = rlOpenXR_mod,
    });

    // Link C library (required for OpenXR and raylib)
    rlOpenXR.linkLibC();

    // Link raylib
    rlOpenXR.linkLibrary(raylib_artifact);
    rlOpenXR_mod.addImport("raylib", raylib);

    // Link system libraries based on target platform
    if (target.result.os.tag == .windows) {
        rlOpenXR.linkSystemLibrary("opengl32");
        rlOpenXR.linkSystemLibrary("gdi32");
        rlOpenXR.linkSystemLibrary("user32");
    } else if (target.result.os.tag == .linux) {
        rlOpenXR.linkSystemLibrary("GL");
        rlOpenXR.linkSystemLibrary("X11");
    }
    // TODO: Add Android support when targeting Android
    // Note: Android linking will be added when we properly set up Android target

    // TODO: Link OpenXR SDK (will need to fetch or provide as dependency)

    // Install the library
    b.installArtifact(rlOpenXR);

    // Build examples
    const hello_vr_mod = b.createModule(.{
        .root_source_file = b.path("examples/hello_vr.zig"),
        .target = target,
        .optimize = optimize,
    });
    hello_vr_mod.addImport("rlOpenXR", rlOpenXR_mod);

    const hello_vr_exe = b.addExecutable(.{
        .name = "hello_vr",
        .root_module = hello_vr_mod,
    });
    hello_vr_exe.linkLibrary(rlOpenXR);
    hello_vr_exe.linkLibrary(raylib_artifact);

    const install_hello_vr = b.addInstallArtifact(hello_vr_exe, .{});

    // Run step
    const run_cmd = b.addRunArtifact(hello_vr_exe);
    run_cmd.step.dependOn(&install_hello_vr.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the hello_vr example");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/rlOpenXR.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_tests = b.addTest(.{
        .root_module = test_mod,
    });
    lib_tests.linkLibC();

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);
}
