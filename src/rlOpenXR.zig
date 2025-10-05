const std = @import("std");
const builtin = @import("builtin");

// Import C libraries
pub const c = @cImport({
    // Include OpenXR first (with platform headers)
    @cInclude("openxr/openxr.h");

    if (builtin.os.tag == .windows) {
        @cDefine("WIN32_LEAN_AND_MEAN", "1"); // Minimize Windows.h
        @cDefine("NOMINMAX", "1"); // Prevent min/max macros
        @cDefine("NOGDI", "1"); // Exclude GDI (conflicts with raylib Rectangle)
        @cDefine("NOUSER", "1"); // Exclude USER (conflicts with CloseWindow, ShowCursor)
        @cInclude("windows.h"); // Required for basic types
        @cInclude("gl/gl.h"); // For HDC, HGLRC from OpenGL context
        // Define IUnknown as void* to avoid COM headers (we don't use those extensions)
        @cDefine("IUnknown", "void");
        @cDefine("XR_USE_PLATFORM_WIN32", "1");
        @cDefine("XR_USE_GRAPHICS_API_OPENGL", "1");
        @cInclude("openxr/openxr_platform.h");
    } else if (builtin.os.tag == .linux) {
        @cDefine("XR_USE_PLATFORM_XLIB", "1");
        @cDefine("XR_USE_GRAPHICS_API_OPENGL", "1");
        @cInclude("openxr/openxr_platform.h");
    } else if (builtin.os.tag == .android) {
        @cDefine("XR_USE_PLATFORM_ANDROID", "1");
        @cDefine("XR_USE_GRAPHICS_API_OPENGL_ES", "1");
        @cInclude("openxr/openxr_platform.h");
    }

    // Include raylib AFTER OpenXR to avoid name conflicts
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
});

// Platform-specific imports
const platform = switch (builtin.os.tag) {
    .windows => @import("platform/windows.zig"),
    .linux => @import("platform/linux.zig"),
    // TODO: Android support - .android tag doesn't exist in Zig 0.15.1
    // .android => @import("platform/android.zig"),
    else => @compileError("Unsupported platform for OpenXR"),
};

//==============================================================================
// Public Types
//==============================================================================

pub const Eye = enum(c_int) {
    left = 0,
    right = 1,
    both = 2,
};

pub const Hand = enum(c_int) {
    left = 0,
    right = 1,
};

pub const Data = extern struct {
    instance: c.XrInstance,
    system_id: c.XrSystemId,
    session: c.XrSession,
    session_state: c.XrSessionState,
    play_space: c.XrSpace,
    view_space: c.XrSpace,

    // Constants
    view_type: c.XrViewConfigurationType,
    form_factor: c.XrFormFactor,
    play_space_type: c.XrReferenceSpaceType,
};

pub const HandData = extern struct {
    // OpenXR output data
    valid: bool,
    position: c.Vector3,
    orientation: c.Quaternion,

    // Input config
    handedness: Hand,

    hand_pose_action: c.XrAction,
    hand_pose_subpath: c.XrPath,
    hand_pose_space: c.XrSpace,
};

//==============================================================================
// Private State
//==============================================================================

const ViewCount = 2;

const Extensions = struct {
    xrGetOpenGLGraphicsRequirementsKHR: ?*const fn (c.XrInstance, c.XrSystemId, *c.XrGraphicsRequirementsOpenGLKHR) callconv(.c) c.XrResult = null,
    xrConvertWin32PerformanceCounterToTimeKHR: ?*const fn (c.XrInstance, *const c.LARGE_INTEGER, *c.XrTime) callconv(.c) c.XrResult = null,
    xrCreateDebugUtilsMessengerEXT: ?*const fn (c.XrInstance, *const c.XrDebugUtilsMessengerCreateInfoEXT, *c.XrDebugUtilsMessengerEXT) callconv(.c) c.XrResult = null,
    debug_messenger_handle: c.XrDebugUtilsMessengerEXT = null,
    depth_enabled: bool = false,
};

pub const State = struct {
    data: Data = .{
        .instance = null,
        .system_id = 0,
        .session = null,
        .session_state = c.XR_SESSION_STATE_UNKNOWN,
        .play_space = null,
        .view_space = null,
        .view_type = c.XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,
        .form_factor = c.XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY,
        .play_space_type = c.XR_REFERENCE_SPACE_TYPE_STAGE,
    },

    extensions: Extensions = .{},
    graphics_binding: platform.GraphicsBinding = undefined,
    frame_state: c.XrFrameState = .{ .type = c.XR_TYPE_FRAME_STATE },

    session_running: bool = false,
    run_framecycle: bool = false,

    viewconfig_views: std.ArrayList(c.XrViewConfigurationView) = undefined,
    projection_views: std.ArrayList(c.XrCompositionLayerProjectionView) = undefined,
    depth_infos: std.ArrayList(c.XrCompositionLayerDepthInfoKHR) = undefined,

    layer_projection: c.XrCompositionLayerProjection = .{ .type = c.XR_TYPE_COMPOSITION_LAYER_PROJECTION },
    layers_pointers: std.ArrayList(*c.XrCompositionLayerBaseHeader) = undefined,
    views: std.ArrayList(c.XrView) = undefined,

    swapchain: c.XrSwapchain = null,
    swapchain_images: std.ArrayList(c.XrSwapchainImageOpenGLKHR) = undefined,
    current_swapchain_index: u32 = 0, // Track current image for blitting
    depth_swapchain: c.XrSwapchain = null,
    depth_swapchain_images: std.ArrayList(c.XrSwapchainImageOpenGLKHR) = undefined,

    fbo: c_uint = 0,
    mock_hmd_rt: c.RenderTexture = .{ .id = 0, .texture = undefined, .depth = undefined },
    active_fbo: c_uint = 0,

    allocator: std.mem.Allocator = undefined,
};

var state: ?State = null;

//==============================================================================
// Error Handling
//==============================================================================

pub const OpenXRError = error{
    InitializationFailed,
    ExtensionNotSupported,
    SessionCreationFailed,
    SwapchainCreationFailed,
    FrameError,
    NotInitialized,
    OutOfMemory,
};

pub fn xrCheck(result: c.XrResult, comptime fmt: []const u8, args: anytype) bool {
    if (result >= 0) return true; // XR_SUCCEEDED

    var result_string: [c.XR_MAX_RESULT_STRING_SIZE]u8 = undefined;
    if (state) |s| {
        if (s.data.instance != null) {
            _ = c.xrResultToString(s.data.instance, result, &result_string);
        } else {
            _ = std.fmt.bufPrint(&result_string, "Error XrResult({d})", .{result}) catch unreachable;
        }
    }

    std.debug.print(fmt ++ " [{s}] ({d})\n", args ++ .{result_string, result});
    return false;
}

//==============================================================================
// Public API - Setup/Shutdown
//==============================================================================

/// Initialize OpenXR. Returns true on success, false on failure.
/// This will gracefully fail if no VR runtime is available.
pub fn setup() bool {
    return setupWithAllocator(std.heap.c_allocator);
}

pub fn setupWithAllocator(allocator: std.mem.Allocator) bool {
    if (state != null) {
        std.debug.print("rlOpenXR already initialized\n", .{});
        return false;
    }

    state = State{
        .allocator = allocator,
        .viewconfig_views = std.ArrayList(c.XrViewConfigurationView).initCapacity(allocator, 0) catch unreachable,
        .projection_views = std.ArrayList(c.XrCompositionLayerProjectionView).initCapacity(allocator, 0) catch unreachable,
        .depth_infos = std.ArrayList(c.XrCompositionLayerDepthInfoKHR).initCapacity(allocator, 0) catch unreachable,
        .layers_pointers = std.ArrayList(*c.XrCompositionLayerBaseHeader).initCapacity(allocator, 0) catch unreachable,
        .views = std.ArrayList(c.XrView).initCapacity(allocator, 0) catch unreachable,
        .swapchain_images = std.ArrayList(c.XrSwapchainImageOpenGLKHR).initCapacity(allocator, 0) catch unreachable,
        .depth_swapchain_images = std.ArrayList(c.XrSwapchainImageOpenGLKHR).initCapacity(allocator, 0) catch unreachable,
    };

    const setup_impl = @import("setup.zig");
    setup_impl.setupOpenXR(&state.?) catch |err| {
        std.debug.print("OpenXR setup failed: {}\n", .{err});
        shutdown();
        return false;
    };

    return true;
}

pub fn shutdown() void {
    if (state) |*s| {
        if (s.fbo != 0) {
            c.rlUnloadFramebuffer(s.fbo);
        }
        if (s.mock_hmd_rt.id != 0) {
            c.UnloadRenderTexture(s.mock_hmd_rt);
        }

        if (s.data.instance != null) {
            const result = c.xrDestroyInstance(s.data.instance);
            if (result >= 0) {
                std.debug.print("Successfully shutdown OpenXR\n", .{});
            } else {
                std.debug.print("Failed to shutdown OpenXR: {d}\n", .{result});
            }
        }

        // Free array lists
        s.viewconfig_views.deinit(s.allocator);
        s.projection_views.deinit(s.allocator);
        s.depth_infos.deinit(s.allocator);
        s.layers_pointers.deinit(s.allocator);
        s.views.deinit(s.allocator);
        s.swapchain_images.deinit(s.allocator);
        s.depth_swapchain_images.deinit(s.allocator);

        state = null;
    }
}

//==============================================================================
// Public API - Update/Frame Loop
//==============================================================================

pub fn update() void {
    if (state) |*s| {
        const frame_impl = @import("frame.zig");
        frame_impl.updateOpenXR(s);
    }
}

pub fn updateCamera(camera: *c.Camera3D) void {
    if (state) |*s| {
        const frame_impl = @import("frame.zig");
        frame_impl.updateCameraOpenXR(s, camera);
    }
}

pub fn updateCameraTransform(transform: *c.Transform) void {
    if (state) |*s| {
        const time = @import("frame.zig").getTimeOpenXR(s);

        var view_location: c.XrSpaceLocation = .{
            .type = c.XR_TYPE_SPACE_LOCATION,
            .next = null,
        };

        const result = c.xrLocateSpace(s.data.view_space, s.data.play_space, time, &view_location);
        if (!xrCheck(result, "Could not locate view for transform", .{})) {
            return;
        }

        if ((view_location.locationFlags & c.XR_SPACE_LOCATION_POSITION_VALID_BIT) != 0) {
            const pos = view_location.pose.position;
            transform.translation = .{ .x = pos.x, .y = pos.y, .z = pos.z };
        }

        if ((view_location.locationFlags & c.XR_SPACE_LOCATION_ORIENTATION_VALID_BIT) != 0) {
            const rot = view_location.pose.orientation;
            transform.rotation = .{ .x = rot.x, .y = rot.y, .z = rot.z, .w = rot.w };
        }
    }
}

//==============================================================================
// Public API - Drawing
//==============================================================================

pub fn begin() bool {
    if (state) |*s| {
        const frame_impl = @import("frame.zig");
        return frame_impl.beginOpenXR(s);
    }
    return false;
}

pub fn beginMockHMD() bool {
    if (state) |*s| {
        const frame_impl = @import("frame.zig");
        return frame_impl.beginMockHMD(s);
    }
    return false;
}

pub fn end() void {
    if (state) |*s| {
        const frame_impl = @import("frame.zig");
        frame_impl.endOpenXR(s);
    }
}

pub fn blitToWindow(eye: Eye, keep_aspect_ratio: bool) void {
    if (state) |*s| {
        // Check if we have a valid swapchain
        if (s.swapchain_images.items.len == 0) {
            return;
        }

        var src: c.XrRect2Di = undefined;
        switch (eye) {
            .left => {
                src.offset = .{ .x = 0, .y = 0 };
                src.extent.width = @intCast(s.viewconfig_views.items[0].recommendedImageRectWidth);
                src.extent.height = @intCast(s.viewconfig_views.items[0].recommendedImageRectHeight);
            },
            .right => {
                src.offset.x = @intCast(s.viewconfig_views.items[0].recommendedImageRectWidth);
                src.offset.y = 0;
                src.extent.width = @intCast(s.viewconfig_views.items[1].recommendedImageRectWidth);
                src.extent.height = @intCast(s.viewconfig_views.items[1].recommendedImageRectHeight);
            },
            .both => {
                src.offset = .{ .x = 0, .y = 0 };
                src.extent.width = @intCast(s.viewconfig_views.items[0].recommendedImageRectWidth + s.viewconfig_views.items[1].recommendedImageRectWidth);
                src.extent.height = @intCast(s.viewconfig_views.items[0].recommendedImageRectHeight);
            },
        }

        var dest = c.XrRect2Di{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{
                .width = c.GetScreenWidth(),
                .height = c.GetScreenHeight(),
            },
        };

        if (keep_aspect_ratio) {
            const src_aspect: f32 = @as(f32, @floatFromInt(src.extent.width)) / @as(f32, @floatFromInt(src.extent.height));
            const dest_aspect: f32 = @as(f32, @floatFromInt(dest.extent.width)) / @as(f32, @floatFromInt(dest.extent.height));

            const screen_width = dest.extent.width;
            const screen_height = dest.extent.height;

            if (src_aspect > dest_aspect) {
                const new_height = @as(f32, @floatFromInt(dest.extent.width)) / src_aspect;
                dest.extent.height = @intFromFloat(new_height);
                // Center vertically
                dest.offset.y = @intCast(@divTrunc(screen_height - dest.extent.height, 2));
            } else {
                const new_width = @as(f32, @floatFromInt(dest.extent.height)) * src_aspect;
                dest.extent.width = @intFromFloat(new_width);
                // Center horizontally
                dest.offset.x = @intCast(@divTrunc(screen_width - dest.extent.width, 2));
            }
        }

        // Disable VR framebuffer to draw to window
        c.rlDisableFramebuffer();

        // Create a texture struct for raylib to draw
        const texture_id = if (s.swapchain_images.items.len > s.current_swapchain_index)
            s.swapchain_images.items[s.current_swapchain_index].image
        else
            0;

        // Total swapchain texture dimensions (both eyes side-by-side)
        const total_width = s.viewconfig_views.items[0].recommendedImageRectWidth * 2;
        const total_height = s.viewconfig_views.items[0].recommendedImageRectHeight;

        const vr_texture = c.Texture2D{
            .id = texture_id,
            .width = @intCast(total_width),
            .height = @intCast(total_height),
            .mipmaps = 1,
            .format = c.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
        };

        // Source rectangle within the VR texture
        const src_rect = c.Rectangle{
            .x = @floatFromInt(src.offset.x),
            .y = @floatFromInt(src.offset.y),
            .width = @floatFromInt(src.extent.width),
            .height = -@as(f32, @floatFromInt(src.extent.height)), // Negative to flip Y (OpenGL texture is upside down)
        };

        const dest_rect = c.Rectangle{
            .x = @floatFromInt(dest.offset.x),
            .y = @floatFromInt(dest.offset.y),
            .width = @floatFromInt(dest.extent.width),
            .height = @floatFromInt(dest.extent.height),
        };

        c.DrawTexturePro(vr_texture, src_rect, dest_rect, .{ .x = 0, .y = 0 }, 0, c.WHITE);

        c.rlEnableFramebuffer(s.active_fbo);
    }
}

//==============================================================================
// Public API - State Access
//==============================================================================

pub fn getData() ?*const Data {
    if (state) |*s| {
        return &s.data;
    }
    return null;
}

pub fn getTime() c.XrTime {
    if (state) |*s| {
        const frame_impl = @import("frame.zig");
        return frame_impl.getTimeOpenXR(s);
    }
    return 0;
}

pub fn getEyeResolution() ?struct { width: u32, height: u32 } {
    if (state) |*s| {
        if (s.viewconfig_views.items.len > 0) {
            return .{
                .width = s.viewconfig_views.items[0].recommendedImageRectWidth,
                .height = s.viewconfig_views.items[0].recommendedImageRectHeight,
            };
        }
    }
    return null;
}

//==============================================================================
// Public API - Input/Hands
//==============================================================================

pub fn updateHands(left: ?*HandData, right: ?*HandData) void {
    if (state) |*s| {
        const input_impl = @import("input.zig");
        input_impl.updateHandsOpenXR(s, left, right);
    }
}

pub fn syncSingleActionSet(action_set: c.XrActionSet) void {
    if (state) |*s| {
        const input_impl = @import("input.zig");
        input_impl.syncSingleActionSetOpenXR(s, action_set);
    }
}

//==============================================================================
// Public API - Refresh Rate (72-300Hz support)
//==============================================================================

pub fn loadRefreshRateExtension() bool {
    if (state) |s| {
        const refresh = @import("refresh_rate.zig");
        return refresh.loadRefreshRateExtension(s.data.instance);
    }
    return false;
}

pub fn getSupportedRefreshRates(allocator: std.mem.Allocator) ![]f32 {
    if (state) |s| {
        const refresh = @import("refresh_rate.zig");
        return refresh.getSupportedRefreshRates(s.data.session, allocator);
    }
    return error.NotInitialized;
}

pub fn getCurrentRefreshRate() !f32 {
    if (state) |s| {
        const refresh = @import("refresh_rate.zig");
        return refresh.getCurrentRefreshRate(s.data.session);
    }
    return error.NotInitialized;
}

pub fn setRefreshRate(target_rate: f32) !void {
    if (state) |s| {
        const refresh = @import("refresh_rate.zig");
        try refresh.setRefreshRate(s.data.session, target_rate);
    } else {
        return error.NotInitialized;
    }
}

//==============================================================================
// Tests
//==============================================================================

test "basic initialization" {
    const expect = std.testing.expect;

    // Test that state starts as null
    try expect(state == null);
}
