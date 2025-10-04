const std = @import("std");
const c = @cImport({
    @cDefine("XR_USE_PLATFORM_XLIB", "1");
    @cDefine("XR_USE_GRAPHICS_API_OPENGL", "1");
    @cInclude("X11/Xlib.h");
    @cInclude("GL/glx.h");
    @cInclude("openxr/openxr.h");
    @cInclude("openxr/openxr_platform.h");
});

pub const GraphicsBinding = c.XrGraphicsBindingOpenGLXlibKHR;

pub fn getCurrentGraphicsBinding() GraphicsBinding {
    return .{
        .type = c.XR_TYPE_GRAPHICS_BINDING_OPENGL_XLIB_KHR,
        .next = null,
        .xDisplay = glXGetCurrentDisplay(),
        .visualid = 0, // TODO: Get proper visual ID
        .glxFBConfig = null, // TODO: Get proper FB config
        .glxDrawable = glXGetCurrentDrawable(),
        .glxContext = glXGetCurrentContext(),
    };
}

extern "GL" fn glXGetCurrentDisplay() callconv(.C) ?*c.Display;
extern "GL" fn glXGetCurrentDrawable() callconv(.C) c.GLXDrawable;
extern "GL" fn glXGetCurrentContext() callconv(.C) c.GLXContext;

pub fn convertPerformanceCounterToTime(
    instance: c.XrInstance,
    convert_fn: ?*const fn (c.XrInstance, *const anyopaque, *c.XrTime) callconv(.C) c.XrResult,
) c.XrTime {
    _ = instance;
    _ = convert_fn;

    // Linux uses system time directly
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);

    return @as(c.XrTime, @intCast(ts.tv_sec)) * 1_000_000_000 + @as(c.XrTime, @intCast(ts.tv_nsec));
}
