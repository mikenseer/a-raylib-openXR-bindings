const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the rlOpenXR library module
    const rlOpenXR = b.addStaticLibrary(.{
        .name = "rlOpenXR",
        .root_source_file = b.path("src/rlOpenXR.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link C library (required for OpenXR and raylib)
    rlOpenXR.linkLibC();

    // Link system libraries based on target platform
    if (target.result.os.tag == .windows) {
        rlOpenXR.linkSystemLibrary("opengl32");
        rlOpenXR.linkSystemLibrary("gdi32");
        rlOpenXR.linkSystemLibrary("user32");
    } else if (target.result.os.tag == .linux) {
        rlOpenXR.linkSystemLibrary("GL");
        rlOpenXR.linkSystemLibrary("X11");
    } else if (target.result.os.tag == .android) {
        rlOpenXR.linkSystemLibrary("EGL");
        rlOpenXR.linkSystemLibrary("GLESv3");
        rlOpenXR.linkSystemLibrary("android");
        rlOpenXR.linkSystemLibrary("log");
    }

    // TODO: Link raylib (will need to fetch or provide as dependency)
    // TODO: Link OpenXR SDK (will need to fetch or provide as dependency)

    // Install the library
    b.installArtifact(rlOpenXR);

    // Create a module for users to import
    const rlOpenXR_module = b.addModule("rlOpenXR", .{
        .root_source_file = b.path("src/rlOpenXR.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build examples
    const hello_vr_exe = b.addExecutable(.{
        .name = "hello_vr",
        .root_source_file = b.path("examples/hello_vr.zig"),
        .target = target,
        .optimize = optimize,
    });
    hello_vr_exe.root_module.addImport("rlOpenXR", rlOpenXR_module);
    hello_vr_exe.linkLibrary(rlOpenXR);

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
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/rlOpenXR.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_tests.linkLibC();

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);
}
