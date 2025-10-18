const std = @import("std");
const c = @cImport({
    @cDefine("XR_USE_PLATFORM_ANDROID", "1");
    @cDefine("XR_USE_GRAPHICS_API_OPENGL_ES", "1");
    @cInclude("EGL/egl.h");
    @cInclude("android/native_activity.h");
    @cInclude("openxr/openxr.h");
    @cInclude("openxr/openxr_platform.h");
    @cInclude("rlgl.h"); // For rlglInit
});

pub const GraphicsBinding = c.XrGraphicsBindingOpenGLESAndroidKHR;

pub fn getCurrentGraphicsBinding() GraphicsBinding {
    return .{
        .type = c.XR_TYPE_GRAPHICS_BINDING_OPENGL_ES_ANDROID_KHR,
        .next = null,
        .display = eglGetCurrentDisplay(),
        .config = @ptrFromInt(0), // OpenXR spec allows 0 for config on some platforms
        .context = eglGetCurrentContext(),
    };
}

extern "EGL" fn eglGetCurrentDisplay() callconv(.c) c.EGLDisplay;
extern "EGL" fn eglGetCurrentContext() callconv(.c) c.EGLContext;
extern "EGL" fn eglGetDisplay(display_id: c.EGLNativeDisplayType) callconv(.c) c.EGLDisplay;
extern "EGL" fn eglInitialize(dpy: c.EGLDisplay, major: ?*c_int, minor: ?*c_int) callconv(.c) c_int;
extern "EGL" fn eglChooseConfig(dpy: c.EGLDisplay, attrib_list: [*c]const c_int, configs: [*c]c.EGLConfig, config_size: c_int, num_config: *c_int) callconv(.c) c_int;
extern "EGL" fn eglCreateContext(dpy: c.EGLDisplay, config: c.EGLConfig, share_context: c.EGLContext, attrib_list: [*c]const c_int) callconv(.c) c.EGLContext;
extern "EGL" fn eglMakeCurrent(dpy: c.EGLDisplay, draw: c.EGLSurface, read: c.EGLSurface, ctx: c.EGLContext) callconv(.c) c_int;
extern "EGL" fn eglCreatePbufferSurface(dpy: c.EGLDisplay, config: c.EGLConfig, attrib_list: [*c]const c_int) callconv(.c) c.EGLSurface;

const EGL_DEFAULT_DISPLAY = @as(c.EGLNativeDisplayType, @ptrFromInt(0));
const EGL_NO_CONTEXT = @as(c.EGLContext, @ptrFromInt(0));
const EGL_NO_SURFACE = @as(c.EGLSurface, @ptrFromInt(0));
const EGL_OPENGL_ES3_BIT = 0x00000040;
const EGL_PBUFFER_BIT = 0x0001;

/// Initialize EGL and create an OpenGL ES context for OpenXR
/// This must be called before initializing OpenXR on Android
pub fn initializeEGL() !void {
    // Get the default display
    const display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == null) {
        return error.EGLInitFailed;
    }

    // Initialize EGL
    if (eglInitialize(display, null, null) == 0) {
        return error.EGLInitFailed;
    }

    // Choose a config that supports OpenGL ES 3
    const config_attribs = [_]c_int{
        c.EGL_RED_SIZE, 8,
        c.EGL_GREEN_SIZE, 8,
        c.EGL_BLUE_SIZE, 8,
        c.EGL_ALPHA_SIZE, 8,
        c.EGL_DEPTH_SIZE, 24,
        c.EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        c.EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        c.EGL_NONE,
    };

    var config: c.EGLConfig = undefined;
    var num_config: c_int = 0;
    if (eglChooseConfig(display, &config_attribs, &config, 1, &num_config) == 0 or num_config == 0) {
        return error.EGLConfigFailed;
    }

    // Create an OpenGL ES 3 context
    const context_attribs = [_]c_int{
        c.EGL_CONTEXT_CLIENT_VERSION, 3,
        c.EGL_NONE,
    };

    const context = eglCreateContext(display, config, EGL_NO_CONTEXT, &context_attribs);
    if (context == null) {
        return error.EGLContextFailed;
    }

    // Create a 1x1 pbuffer surface (required for makeCurrent, but not used for rendering)
    const pbuffer_attribs = [_]c_int{
        c.EGL_WIDTH, 1,
        c.EGL_HEIGHT, 1,
        c.EGL_NONE,
    };

    const surface = eglCreatePbufferSurface(display, config, &pbuffer_attribs);
    if (surface == null) {
        return error.EGLSurfaceFailed;
    }

    // Make the context current
    if (eglMakeCurrent(display, surface, surface, context) == 0) {
        return error.EGLMakeCurrentFailed;
    }

    // Initialize rlgl (raylib's OpenGL abstraction layer)
    // This must be done after the OpenGL ES context is current
    c.rlglInit(1, 1); // Initialize with minimal size - will be resized by swapchain
}

pub fn convertPerformanceCounterToTime(
    instance: c.XrInstance,
    convert_fn: ?*const fn (c.XrInstance, *const anyopaque, *c.XrTime) callconv(.c) c.XrResult,
) c.XrTime {
    _ = instance;
    _ = convert_fn;

    // Android uses system time
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);

    return @as(c.XrTime, @intCast(ts.tv_sec)) * 1_000_000_000 + @as(c.XrTime, @intCast(ts.tv_nsec));
}
