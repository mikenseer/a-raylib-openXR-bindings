const std = @import("std");

//==============================================================================
// OpenXR SDK Configuration
//==============================================================================
// OPTION 1 (Recommended): Set environment variable before building:
//   Windows:  set OPENXR_SDK=C:\OpenXR-SDK
//   Linux:    export OPENXR_SDK=/usr/local/openxr
//
// OPTION 2: Hardcode path here (uncomment ONE line below):
const OPENXR_SDK_PATH: ?[]const u8 = "C:\\OpenXR-SDK";        // Windows example
// const OPENXR_SDK_PATH: ?[]const u8 = "/usr/local/openxr";    // Linux example
// const OPENXR_SDK_PATH: ?[]const u8 = null;  // Leave null to use environment variable
//==============================================================================

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

    // Get OpenXR SDK path (hardcoded path overrides environment variable)
    const openxr_sdk_path: ?[]const u8 = if (OPENXR_SDK_PATH) |path| path else b.graph.env_map.get("OPENXR_SDK");

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

    // Configure OpenXR SDK paths if available
    if (openxr_sdk_path) |sdk_path| {
        const include_path = b.fmt("{s}/include", .{sdk_path});
        rlOpenXR.addIncludePath(.{ .cwd_relative = include_path });

        std.debug.print("✓ Using OpenXR headers from: {s}\n", .{sdk_path});
        std.debug.print("  (OpenXR loader will be provided by VR runtime)\n", .{});
    } else {
        std.debug.print("ℹ OPENXR_SDK not configured\n", .{});
        std.debug.print("  Set path at top of build.zig or use environment variable:\n", .{});
        std.debug.print("    Windows: set OPENXR_SDK=C:\\OpenXR-SDK\n", .{});
        std.debug.print("    Linux:   export OPENXR_SDK=/usr/local/openxr\n", .{});
    }

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
    // Link OpenXR loader library
    // NOTE: The loader DLL is NOT installed system-wide by VR runtimes
    // VR apps typically bundle it with their executable or add its path to PATH
    if (target.result.os.tag == .windows) {
        // Check common VR runtime locations for openxr_loader.dll
        const possible_paths = [_][]const u8{
            // Current directory (if user copied DLL here)
            ".",
            // SteamVR locations (common install paths)
            "C:\\Program Files (x86)\\Steam\\steamapps\\common\\SteamVR\\bin\\win64",
            "D:\\Steam\\steamapps\\common\\SteamVR\\bin\\win64",
            "D:\\SteamLibrary\\steamapps\\common\\SteamVR\\bin\\win64",
            "E:\\SteamLibrary\\steamapps\\common\\SteamVR\\bin\\win64",
        };

        var loader_found = false;
        var found_path: []const u8 = "";

        for (possible_paths) |path| {
            const dll_path = b.fmt("{s}\\openxr_loader.dll", .{path});
            const file = std.fs.cwd().openFile(dll_path, .{}) catch continue;
            file.close();

            // Found it!
            rlOpenXR.addLibraryPath(.{ .cwd_relative = path });
            loader_found = true;
            found_path = path;
            break;
        }

        // Try to link (will fail with clear error if not found)
        rlOpenXR.linkSystemLibrary("openxr_loader");

        if (loader_found) {
            std.debug.print("✓ Found OpenXR loader at: {s}\n", .{found_path});
        } else {
            std.debug.print("\n", .{});
            std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
            std.debug.print("  OpenXR Loader Required\n", .{});
            std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("  The build needs openxr_loader.dll for linking.\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("  OPTION 1 - Use your VR runtime's loader (if installed):\n", .{});
            std.debug.print("    Find openxr_loader.dll in your VR runtime folder and copy it here:\n", .{});
            std.debug.print("      • SteamVR: Steam\\steamapps\\common\\SteamVR\\bin\\win64\\\n", .{});
            std.debug.print("      • Meta: Check your Oculus install directory\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("  OPTION 2 - Download official Khronos loader:\n", .{});
            std.debug.print("    https://github.com/KhronosGroup/OpenXR-SDK/releases\n", .{});
            std.debug.print("    Extract openxr_loader.dll from the Windows zip to this directory\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("  OPTION 3 - Install a VR runtime (if you don't have one):\n", .{});
            std.debug.print("    • SteamVR: https://store.steampowered.com/app/250820\n", .{});
            std.debug.print("    • Meta PC: https://www.meta.com/quest/setup/\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("  (The DLL is NOT committed to git - ~500KB)\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
            std.debug.print("\n", .{});
        }
    } else if (target.result.os.tag == .linux) {
        // Linux: Use system OpenXR package (apt install libopenxr-loader1)
        rlOpenXR.linkSystemLibrary("openxr_loader");
    }

    // TODO: Add Android support when targeting Android
    // Note: Android linking will be added when we properly set up Android target

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
