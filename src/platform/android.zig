const std = @import("std");
const c = @cImport({
    @cDefine("XR_USE_PLATFORM_ANDROID", "1");
    @cDefine("XR_USE_GRAPHICS_API_OPENGL_ES", "1");
    @cInclude("EGL/egl.h");
    @cInclude("android/native_activity.h");
    @cInclude("openxr/openxr.h");
    @cInclude("openxr/openxr_platform.h");
});

pub const GraphicsBinding = c.XrGraphicsBindingOpenGLESAndroidKHR;

pub fn getCurrentGraphicsBinding() GraphicsBinding {
    return .{
        .type = c.XR_TYPE_GRAPHICS_BINDING_OPENGL_ES_ANDROID_KHR,
        .next = null,
        .display = eglGetCurrentDisplay(),
        .config = null, // TODO: Get proper EGL config
        .context = eglGetCurrentContext(),
    };
}

extern "EGL" fn eglGetCurrentDisplay() callconv(.C) c.EGLDisplay;
extern "EGL" fn eglGetCurrentContext() callconv(.C) c.EGLContext;

pub fn convertPerformanceCounterToTime(
    instance: c.XrInstance,
    convert_fn: ?*const fn (c.XrInstance, *const anyopaque, *c.XrTime) callconv(.C) c.XrResult,
) c.XrTime {
    _ = instance;
    _ = convert_fn;

    // Android uses system time
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);

    return @as(c.XrTime, @intCast(ts.tv_sec)) * 1_000_000_000 + @as(c.XrTime, @intCast(ts.tv_nsec));
}
