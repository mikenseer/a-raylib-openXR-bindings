// This file contains the implementation of OpenXR setup and initialization
// Ported from rlOpenXR.cpp (FireFlyForLife)

const std = @import("std");
const main = @import("rlOpenXR.zig");
const c = main.c; // Use main's C imports to avoid type mismatches

// Android logging support
const builtin = @import("builtin");
const android_log = if (builtin.abi == .android) struct {
    extern "log" fn __android_log_write(prio: c_int, tag: [*:0]const u8, text: [*:0]const u8) c_int;
    const ANDROID_LOG_INFO = 4;

    fn log(comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrintZ(&buf, fmt, args) catch "Log formatting failed";
        _ = __android_log_write(ANDROID_LOG_INFO, "rlOpenXR-setup", msg.ptr);
    }
} else struct {
    fn log(comptime fmt: []const u8, args: anytype) void {
        std.debug.print(fmt ++ "\n", args);
    }
};

fn logInfo(comptime fmt: []const u8, args: anytype) void {
    android_log.log(fmt, args);
    std.debug.print(fmt ++ "\n", args); // Also print to stderr for desktop
}

pub fn setupOpenXR(state: *main.State) !void {
    var result: c.XrResult = c.XR_SUCCESS;

    // Android/Quest requires xrInitializeLoaderKHR to be called BEFORE xrEnumerateInstanceExtensionProperties
    if (builtin.abi == .android) {
        const android_ctx = @import("rlOpenXR.zig").android_context;
        if (android_ctx) |ctx| {
            var init_loader_fn: c.PFN_xrVoidFunction = null;
            result = c.xrGetInstanceProcAddr(null, "xrInitializeLoaderKHR", &init_loader_fn);
            if (main.xrCheck(result, "Got xrInitializeLoaderKHR function pointer", .{})) {
                const xrInitializeLoaderKHR: *const fn (*const c.XrLoaderInitInfoAndroidKHR) callconv(.c) c.XrResult = @ptrCast(init_loader_fn);
                const loader_init_info = c.XrLoaderInitInfoAndroidKHR{
                    .type = c.XR_TYPE_LOADER_INIT_INFO_ANDROID_KHR,
                    .next = null,
                    .applicationVM = ctx.vm,
                    .applicationContext = ctx.activity,
                };
                result = xrInitializeLoaderKHR(&loader_init_info);
                if (!main.xrCheck(result, "xrInitializeLoaderKHR", .{})) {
                    return error.InitializationFailed;
                }
            } else {
                return error.InitializationFailed;
            }
        } else {
            std.debug.print("ERROR: Android context is null! Call setAndroidContext() before setup().\n", .{});
            return error.InitializationFailed;
        }
    }

    // Enumerate instance extensions
    var ext_count: u32 = 0;
    result = c.xrEnumerateInstanceExtensionProperties(null, 0, &ext_count, null);
    if (!main.xrCheck(result, "Failed to enumerate extension count", .{})) {
        return error.InitializationFailed;
    }
    const ext_props = try state.allocator.alloc(c.XrExtensionProperties, ext_count);
    defer state.allocator.free(ext_props);

    for (ext_props) |*prop| {
        prop.* = .{ .type = c.XR_TYPE_EXTENSION_PROPERTIES, .next = null };
    }

    result = c.xrEnumerateInstanceExtensionProperties(null, ext_count, &ext_count, ext_props.ptr);
    if (!main.xrCheck(result, "Failed to enumerate extensions", .{})) {
        return error.InitializationFailed;
    }

    // Check for required and optional extensions
    var opengl_supported = false;
    var enabled_exts = std.ArrayList([*:0]const u8).initCapacity(state.allocator, 0) catch unreachable;
    defer enabled_exts.deinit(state.allocator);

    // Required extensions (platform-specific OpenGL)
    const opengl_ext = if (builtin.abi == .android)
        c.XR_KHR_OPENGL_ES_ENABLE_EXTENSION_NAME
    else if (builtin.os.tag == .windows)
        c.XR_KHR_OPENGL_ENABLE_EXTENSION_NAME
    else
        c.XR_KHR_OPENGL_ENABLE_EXTENSION_NAME;

    try enabled_exts.append(state.allocator, opengl_ext);

    // Android requires android_create_instance extension
    if (builtin.abi == .android) {
        try enabled_exts.append(state.allocator, c.XR_KHR_ANDROID_CREATE_INSTANCE_EXTENSION_NAME);
    }

    // Optional but useful extensions
    // NOTE: Debug utils commented out - can cause instance creation failures with some runtimes
    // try enabled_exts.append(state.allocator, c.XR_EXT_DEBUG_UTILS_EXTENSION_NAME);

    std.debug.print("Runtime supports {d} extensions:\n", .{ext_count});
    for (ext_props) |ext| {
        const ext_name = std.mem.sliceTo(&ext.extensionName, 0);
        std.debug.print("  {s} v{d}\n", .{ ext_name, ext.extensionVersion });

        if (std.mem.eql(u8, ext_name, std.mem.sliceTo(opengl_ext, 0))) {
            opengl_supported = true;
        }

        // Depth layer extension
        if (std.mem.eql(u8, ext_name, c.XR_KHR_COMPOSITION_LAYER_DEPTH_EXTENSION_NAME)) {
            state.extensions.depth_enabled = true;
            try enabled_exts.append(state.allocator, c.XR_KHR_COMPOSITION_LAYER_DEPTH_EXTENSION_NAME);
        }

        // Quest/Meta refresh rate extension (72-120Hz support on Quest 3)
        if (std.mem.eql(u8, ext_name, "XR_FB_display_refresh_rate")) {
            try enabled_exts.append(state.allocator, "XR_FB_display_refresh_rate");
            state.extensions.refresh_rate_enabled = true;
        }
    }

    if (!opengl_supported) {
        std.debug.print("Runtime does not support OpenGL extension!\n", .{});
        return error.ExtensionNotSupported;
    }

    std.debug.print("\nRequesting {d} extensions:\n", .{enabled_exts.items.len});
    for (enabled_exts.items) |ext| {
        std.debug.print("  {s}\n", .{std.mem.sliceTo(ext, 0)});
    }
    std.debug.print("\n", .{});

    // Create XrInstance
    var app_info = std.mem.zeroes(c.XrApplicationInfo);
    // Copy strings with proper null termination
    const app_name = "rlOpenXR-Zig";
    const engine_name = "Raylib";
    @memcpy(app_info.applicationName[0..app_name.len], app_name);
    app_info.applicationName[app_name.len] = 0; // Null terminator
    @memcpy(app_info.engineName[0..engine_name.len], engine_name);
    app_info.engineName[engine_name.len] = 0; // Null terminator
    app_info.applicationVersion = 1;
    app_info.engineVersion = 1;
    // Use XR_API_VERSION_1_0 instead of XR_CURRENT_API_VERSION for better compatibility
    app_info.apiVersion = c.XR_MAKE_VERSION(1, 0, 0);

    // Android-specific instance creation info (must be chained)
    var android_create_info: c.XrInstanceCreateInfoAndroidKHR = undefined;
    const instance_next: ?*anyopaque = if (builtin.abi == .android) blk: {
        // Get Android context from rlOpenXR main module
        const android_ctx = @import("rlOpenXR.zig").android_context;
        if (android_ctx) |ctx| {
            android_create_info = c.XrInstanceCreateInfoAndroidKHR{
                .type = c.XR_TYPE_INSTANCE_CREATE_INFO_ANDROID_KHR,
                .next = null,
                .applicationVM = ctx.vm,
                .applicationActivity = ctx.activity,
            };
            std.debug.print("Using Android context: VM={*}, Activity={*}\n", .{ ctx.vm, ctx.activity });
            break :blk @ptrCast(&android_create_info);
        } else {
            std.debug.print("⚠ Warning: Android context not set! Call setAndroidContext() before setup().\n", .{});
            break :blk null;
        }
    } else null;

    const instance_create_info = c.XrInstanceCreateInfo{
        .type = c.XR_TYPE_INSTANCE_CREATE_INFO,
        .next = instance_next,
        .createFlags = 0,
        .applicationInfo = app_info,
        .enabledApiLayerCount = 0,
        .enabledApiLayerNames = null,
        .enabledExtensionCount = @intCast(enabled_exts.items.len),
        .enabledExtensionNames = enabled_exts.items.ptr,
    };

    std.debug.print("Creating instance with:\n", .{});
    std.debug.print("  App: {s} v{d}\n", .{ std.mem.sliceTo(&app_info.applicationName, 0), app_info.applicationVersion });
    std.debug.print("  Engine: {s} v{d}\n", .{ std.mem.sliceTo(&app_info.engineName, 0), app_info.engineVersion });
    std.debug.print("  API Version: 0x{x}\n", .{app_info.apiVersion});
    std.debug.print("  Extensions: {d}\n", .{instance_create_info.enabledExtensionCount});
    if (builtin.abi == .android) {
        std.debug.print("  Platform: Android (Quest)\n", .{});
    }
    std.debug.print("\n", .{});

    result = c.xrCreateInstance(&instance_create_info, &state.data.instance);
    if (!main.xrCheck(result, "Failed to create XR instance", .{})) {
        return error.InitializationFailed;
    }

    // Load extension functions
    try loadExtensionFunctions(state);

    // Get runtime info
    printInstanceProperties(state.data.instance);

    // Get system ID
    const system_get_info = c.XrSystemGetInfo{
        .type = c.XR_TYPE_SYSTEM_GET_INFO,
        .next = null,
        .formFactor = state.data.form_factor,
    };

    result = c.xrGetSystem(state.data.instance, &system_get_info, &state.data.system_id);
    if (!main.xrCheck(result, "Failed to get system for HMD", .{})) {
        return error.InitializationFailed;
    }

    // Get system properties
    var system_props = std.mem.zeroes(c.XrSystemProperties);
    system_props.type = c.XR_TYPE_SYSTEM_PROPERTIES;
    result = c.xrGetSystemProperties(state.data.instance, state.data.system_id, &system_props);
    if (!main.xrCheck(result, "Failed to get system properties", .{})) {
        return error.InitializationFailed;
    }

    printSystemProperties(&system_props);

    // Get view configuration
    var view_count: u32 = 0;
    result = c.xrEnumerateViewConfigurationViews(
        state.data.instance,
        state.data.system_id,
        state.data.view_type,
        0,
        &view_count,
        null,
    );
    if (!main.xrCheck(result, "Failed to get view count", .{})) {
        return error.InitializationFailed;
    }

    try state.viewconfig_views.resize(state.allocator, view_count);
    for (state.viewconfig_views.items) |*view| {
        view.* = .{ .type = c.XR_TYPE_VIEW_CONFIGURATION_VIEW, .next = null };
    }

    result = c.xrEnumerateViewConfigurationViews(
        state.data.instance,
        state.data.system_id,
        state.data.view_type,
        view_count,
        &view_count,
        state.viewconfig_views.items.ptr,
    );
    if (!main.xrCheck(result, "Failed to enumerate view configs", .{})) {
        return error.InitializationFailed;
    }

    printViewConfigInfo(view_count, state.viewconfig_views.items);

    // Check graphics requirements
    try checkGraphicsRequirements(state);

    // Create session
    try createSession(state);

    // Create reference spaces
    try createReferenceSpaces(state);

    // Create swapchains
    try createSwapchains(state);

    // Initialize frame structures
    try initializeFrameStructures(state);

    std.debug.print("OpenXR setup completed successfully\n", .{});
}

fn loadExtensionFunctions(state: *main.State) !void {
    var result: c.XrResult = undefined;

    // Get OpenGL graphics requirements function (platform-specific name)
    const gl_reqs_func_name = if (builtin.abi == .android)
        "xrGetOpenGLESGraphicsRequirementsKHR"
    else
        "xrGetOpenGLGraphicsRequirementsKHR";

    var get_gl_reqs: c.PFN_xrVoidFunction = null;
    result = c.xrGetInstanceProcAddr(
        state.data.instance,
        gl_reqs_func_name,
        &get_gl_reqs,
    );
    if (!main.xrCheck(result, "Failed to get GL requirements function", .{})) {
        return error.ExtensionNotSupported;
    }
    state.extensions.xrGetOpenGLGraphicsRequirementsKHR = @ptrCast(get_gl_reqs);

    // Platform-specific time conversion (Windows only)
    if (@import("builtin").os.tag == .windows) {
        var convert_time: c.PFN_xrVoidFunction = null;
        result = c.xrGetInstanceProcAddr(
            state.data.instance,
            "xrConvertWin32PerformanceCounterToTimeKHR",
            &convert_time,
        );
        if (result >= 0) {
            state.extensions.xrConvertWin32PerformanceCounterToTimeKHR = @ptrCast(convert_time);
        }
    }

    // Debug messenger (optional)
    var create_debug: c.PFN_xrVoidFunction = null;
    result = c.xrGetInstanceProcAddr(
        state.data.instance,
        "xrCreateDebugUtilsMessengerEXT",
        &create_debug,
    );
    if (result >= 0) {
        state.extensions.xrCreateDebugUtilsMessengerEXT = @ptrCast(create_debug);
    }
}

fn checkGraphicsRequirements(state: *main.State) !void {
    var opengl_reqs = std.mem.zeroes(main.XrGraphicsRequirements);
    opengl_reqs.type = if (@import("builtin").abi == .android)
        c.XR_TYPE_GRAPHICS_REQUIREMENTS_OPENGL_ES_KHR
    else
        c.XR_TYPE_GRAPHICS_REQUIREMENTS_OPENGL_KHR;

    if (state.extensions.xrGetOpenGLGraphicsRequirementsKHR) |get_reqs| {
        const result = get_reqs(state.data.instance, state.data.system_id, &opengl_reqs);
        if (!main.xrCheck(result, "Failed to get OpenGL requirements", .{})) {
            return error.InitializationFailed;
        }

        // Print version requirements
        const min_major = c.XR_VERSION_MAJOR(opengl_reqs.minApiVersionSupported);
        const min_minor = c.XR_VERSION_MINOR(opengl_reqs.minApiVersionSupported);
        std.debug.print("OpenXR requires OpenGL {d}.{d} minimum\n", .{ min_major, min_minor });
    }
}

fn createSession(state: *main.State) !void {
    state.graphics_binding = if (builtin.abi == .android)
        @import("platform/android.zig").getCurrentGraphicsBinding()
    else switch (builtin.os.tag) {
        .windows => @import("platform/windows.zig").getCurrentGraphicsBinding(),
        .linux => @import("platform/linux.zig").getCurrentGraphicsBinding(),
        else => @compileError("Unsupported platform for OpenXR"),
    };

    const session_create_info = c.XrSessionCreateInfo{
        .type = c.XR_TYPE_SESSION_CREATE_INFO,
        .next = @ptrCast(&state.graphics_binding),
        .createFlags = 0,
        .systemId = state.data.system_id,
    };

    const result = c.xrCreateSession(state.data.instance, &session_create_info, &state.data.session);
    if (!main.xrCheck(result, "Failed to create session", .{})) {
        return error.SessionCreationFailed;
    }

    // Load refresh rate extension function pointers (Quest 3 support)
    // Note: Actual refresh rate request happens later in frame.zig when session is SYNCHRONIZED
    if (builtin.abi == .android and state.extensions.refresh_rate_enabled) {
        const refresh = @import("refresh_rate.zig");
        _ = refresh.loadRefreshRateExtension(state.data.instance);
    }
}

fn createReferenceSpaces(state: *main.State) !void {
    const identity_pose = c.XrPosef{
        .orientation = .{ .x = 0, .y = 0, .z = 0, .w = 1.0 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
    };

    // Create play space
    const play_space_create_info = c.XrReferenceSpaceCreateInfo{
        .type = c.XR_TYPE_REFERENCE_SPACE_CREATE_INFO,
        .next = null,
        .referenceSpaceType = state.data.play_space_type,
        .poseInReferenceSpace = identity_pose,
    };

    var result = c.xrCreateReferenceSpace(state.data.session, &play_space_create_info, &state.data.play_space);
    if (!main.xrCheck(result, "Failed to create play space", .{})) {
        return error.InitializationFailed;
    }

    // Create view space
    const view_space_create_info = c.XrReferenceSpaceCreateInfo{
        .type = c.XR_TYPE_REFERENCE_SPACE_CREATE_INFO,
        .next = null,
        .referenceSpaceType = c.XR_REFERENCE_SPACE_TYPE_VIEW,
        .poseInReferenceSpace = identity_pose,
    };

    result = c.xrCreateReferenceSpace(state.data.session, &view_space_create_info, &state.data.view_space);
    if (!main.xrCheck(result, "Failed to create view space", .{})) {
        return error.InitializationFailed;
    }
}

/// Update the play space offset for locomotion (smooth turning, teleportation, etc.)
/// This recreates the play_space reference with a new pose offset
pub fn updatePlaySpaceOffset(state: *main.State, new_offset: c.XrPosef) !void {
    // Destroy old play_space
    const destroy_result = c.xrDestroySpace(state.data.play_space);
    if (!main.xrCheck(destroy_result, "Failed to destroy old play space", .{})) {
        return error.SpaceUpdateFailed;
    }

    // Create new play_space with updated offset
    const play_space_create_info = c.XrReferenceSpaceCreateInfo{
        .type = c.XR_TYPE_REFERENCE_SPACE_CREATE_INFO,
        .next = null,
        .referenceSpaceType = state.data.play_space_type,
        .poseInReferenceSpace = new_offset,
    };

    const create_result = c.xrCreateReferenceSpace(
        state.data.session,
        &play_space_create_info,
        &state.data.play_space
    );
    if (!main.xrCheck(create_result, "Failed to create play space with new offset", .{})) {
        return error.SpaceUpdateFailed;
    }

    // Store the offset for future updates
    state.play_space_offset = new_offset;

    // Update the layer projection space reference
    state.layer_projection.space = state.data.play_space;
}

fn createSwapchains(state: *main.State) !void {
    // Get supported formats
    var format_count: u32 = 0;
    var result = c.xrEnumerateSwapchainFormats(state.data.session, 0, &format_count, null);
    if (!main.xrCheck(result, "Failed to get swapchain format count", .{})) {
        return error.SwapchainCreationFailed;
    }

    const formats = try state.allocator.alloc(i64, format_count);
    defer state.allocator.free(formats);

    result = c.xrEnumerateSwapchainFormats(state.data.session, format_count, &format_count, formats.ptr);
    if (!main.xrCheck(result, "Failed to enumerate swapchain formats", .{})) {
        return error.SwapchainCreationFailed;
    }

    std.debug.print("Runtime supports {d} swapchain formats\n", .{format_count});

    // Calculate swapchain dimensions
    var swapchain_width: u32 = 0;
    for (state.viewconfig_views.items) |view| {
        swapchain_width += view.recommendedImageRectWidth;
    }
    const swapchain_height = state.viewconfig_views.items[0].recommendedImageRectHeight;

    // Create color swapchain
    const color_format: i64 = 0x8C43; // GL_SRGB8_ALPHA8 (not in gl.h, but in glext.h)
    const swapchain_create_info = c.XrSwapchainCreateInfo{
        .type = c.XR_TYPE_SWAPCHAIN_CREATE_INFO,
        .next = null,
        .createFlags = 0,
        .usageFlags = c.XR_SWAPCHAIN_USAGE_SAMPLED_BIT | c.XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT,
        .format = color_format,
        .sampleCount = state.viewconfig_views.items[0].recommendedSwapchainSampleCount,
        .width = swapchain_width,
        .height = swapchain_height,
        .faceCount = 1,
        .arraySize = 1,
        .mipCount = 1,
    };

    result = c.xrCreateSwapchain(state.data.session, &swapchain_create_info, &state.swapchain);
    if (!main.xrCheck(result, "Failed to create swapchain", .{})) {
        return error.SwapchainCreationFailed;
    }

    // Get swapchain images
    var image_count: u32 = 0;
    result = c.xrEnumerateSwapchainImages(state.swapchain, 0, &image_count, null);
    if (!main.xrCheck(result, "Failed to get swapchain image count", .{})) {
        return error.SwapchainCreationFailed;
    }

    const swapchain_image_type = if (builtin.abi == .android)
        c.XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_ES_KHR
    else
        c.XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_KHR;

    try state.swapchain_images.resize(state.allocator, image_count);
    for (state.swapchain_images.items) |*img| {
        img.* = .{ .type = swapchain_image_type, .next = null, .image = 0 };
    }

    result = c.xrEnumerateSwapchainImages(
        state.swapchain,
        image_count,
        &image_count,
        @ptrCast(state.swapchain_images.items.ptr),
    );
    if (!main.xrCheck(result, "Failed to enumerate swapchain images", .{})) {
        return error.SwapchainCreationFailed;
    }

    std.debug.print("Created swapchain: {d}x{d} with {d} images\n", .{ swapchain_width, swapchain_height, image_count });

    // Create framebuffer
    state.fbo = c.rlLoadFramebuffer(); // raylib 5.x - size is set when attaching textures

    // Create depth swapchain if supported
    if (state.extensions.depth_enabled) {
        const depth_format: i64 = 0x81A5; // GL_DEPTH_COMPONENT16

        // Check if depth format is supported
        var depth_supported = false;
        for (formats) |fmt| {
            if (fmt == depth_format) {
                depth_supported = true;
                break;
            }
        }

        if (depth_supported) {
            const depth_swapchain_create_info = c.XrSwapchainCreateInfo{
                .type = c.XR_TYPE_SWAPCHAIN_CREATE_INFO,
                .next = null,
                .createFlags = 0,
                .usageFlags = c.XR_SWAPCHAIN_USAGE_SAMPLED_BIT | c.XR_SWAPCHAIN_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                .format = depth_format,
                .sampleCount = state.viewconfig_views.items[0].recommendedSwapchainSampleCount,
                .width = swapchain_width,
                .height = swapchain_height,
                .faceCount = 1,
                .arraySize = 1,
                .mipCount = 1,
            };

            result = c.xrCreateSwapchain(state.data.session, &depth_swapchain_create_info, &state.depth_swapchain);
            if (!main.xrCheck(result, "Failed to create depth swapchain", .{})) {
                std.debug.print("Disabling depth support\n", .{});
                state.extensions.depth_enabled = false;
            } else {
                var depth_image_count: u32 = 0;
                result = c.xrEnumerateSwapchainImages(state.depth_swapchain, 0, &depth_image_count, null);
                if (main.xrCheck(result, "Got depth swapchain image count", .{})) {
                    try state.depth_swapchain_images.resize(state.allocator, depth_image_count);
                    for (state.depth_swapchain_images.items) |*img| {
                        img.* = .{ .type = swapchain_image_type, .next = null, .image = 0 };
                    }

                    result = c.xrEnumerateSwapchainImages(
                        state.depth_swapchain,
                        depth_image_count,
                        &depth_image_count,
                        @ptrCast(state.depth_swapchain_images.items.ptr),
                    );

                    if (main.xrCheck(result, "Created depth swapchain", .{})) {
                        std.debug.print("Depth swapchain: {d}x{d} with {d} images\n", .{
                            swapchain_width,
                            swapchain_height,
                            depth_image_count,
                        });
                    }
                }
            }
        } else {
            std.debug.print("Depth format not supported, disabling depth\n", .{});
            state.extensions.depth_enabled = false;
        }
    }
}

fn initializeFrameStructures(state: *main.State) !void {
    const view_count = state.viewconfig_views.items.len;

    // Initialize views
    try state.views.resize(state.allocator, view_count);
    for (state.views.items) |*view| {
        view.* = .{ .type = c.XR_TYPE_VIEW, .next = null };
    }

    // Initialize projection views
    try state.projection_views.resize(state.allocator, view_count);
    for (state.projection_views.items, 0..) |*proj_view, i| {
        proj_view.* = .{
            .type = c.XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW,
            .next = null,
            .pose = undefined,
            .fov = undefined,
            .subImage = .{
                .swapchain = state.swapchain,
                .imageArrayIndex = 0,
                .imageRect = .{
                    .offset = .{
                        .x = @intCast(i * state.viewconfig_views.items[i].recommendedImageRectWidth),
                        .y = 0,
                    },
                    .extent = .{
                        .width = @intCast(state.viewconfig_views.items[i].recommendedImageRectWidth),
                        .height = @intCast(state.viewconfig_views.items[i].recommendedImageRectHeight),
                    },
                },
            },
        };
    }

    // Setup layer projection
    state.layer_projection = .{
        .type = c.XR_TYPE_COMPOSITION_LAYER_PROJECTION,
        .next = null,
        .layerFlags = 0,
        .space = state.data.play_space,
        .viewCount = @intCast(view_count),
        .views = state.projection_views.items.ptr,
    };

    try state.layers_pointers.append(state.allocator, @ptrCast(&state.layer_projection));
}

// Helper print functions
fn printInstanceProperties(instance: c.XrInstance) void {
    var props = std.mem.zeroes(c.XrInstanceProperties);
    props.type = c.XR_TYPE_INSTANCE_PROPERTIES;

    const result = c.xrGetInstanceProperties(instance, &props);
    if (result >= 0) {
        const runtime_name = std.mem.sliceTo(&props.runtimeName, 0);
        const major = c.XR_VERSION_MAJOR(props.runtimeVersion);
        const minor = c.XR_VERSION_MINOR(props.runtimeVersion);
        const patch = c.XR_VERSION_PATCH(props.runtimeVersion);
        std.debug.print("Runtime: {s} v{d}.{d}.{d}\n", .{ runtime_name, major, minor, patch });
    }
}

fn printSystemProperties(props: *const c.XrSystemProperties) void {
    const system_name = std.mem.sliceTo(&props.systemName, 0);
    std.debug.print("System: {s} (vendor {d})\n", .{ system_name, props.vendorId });
    std.debug.print("  Max layers: {d}\n", .{props.graphicsProperties.maxLayerCount});
    std.debug.print("  Max swapchain: {d}x{d}\n", .{
        props.graphicsProperties.maxSwapchainImageWidth,
        props.graphicsProperties.maxSwapchainImageHeight,
    });
}

fn printViewConfigInfo(_: u32, views: []const c.XrViewConfigurationView) void {
    for (views, 0..) |view, i| {
        std.debug.print("View {d}: {d}x{d} (max: {d}x{d})\n", .{
            i,
            view.recommendedImageRectWidth,
            view.recommendedImageRectHeight,
            view.maxImageRectWidth,
            view.maxImageRectHeight,
        });
    }
}
