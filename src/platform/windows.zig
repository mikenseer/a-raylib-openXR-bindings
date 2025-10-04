const std = @import("std");
const c = @cImport({
    @cDefine("XR_USE_PLATFORM_WIN32", "1");
    @cDefine("XR_USE_GRAPHICS_API_OPENGL", "1");
    @cInclude("windows.h");
    @cInclude("openxr/openxr.h");
    @cInclude("openxr/openxr_platform.h");
});

pub const GraphicsBinding = c.XrGraphicsBindingOpenGLWin32KHR;

pub fn getCurrentGraphicsBinding() GraphicsBinding {
    return .{
        .type = c.XR_TYPE_GRAPHICS_BINDING_OPENGL_WIN32_KHR,
        .next = null,
        .hDC = wglGetCurrentDC(),
        .hGLRC = wglGetCurrentContext(),
    };
}

extern "opengl32" fn wglGetCurrentDC() callconv(.C) c.HDC;
extern "opengl32" fn wglGetCurrentContext() callconv(.C) c.HGLRC;

pub fn convertPerformanceCounterToTime(
    instance: c.XrInstance,
    convert_fn: ?*const fn (c.XrInstance, *const c.LARGE_INTEGER, *c.XrTime) callconv(.C) c.XrResult,
) c.XrTime {
    var qpc: c.LARGE_INTEGER = undefined;
    _ = c.QueryPerformanceCounter(&qpc);

    var xr_time: c.XrTime = 0;
    if (convert_fn) |func| {
        const result = func(instance, &qpc, &xr_time);
        if (result < 0) {
            std.debug.print("Failed to convert performance counter to XrTime\n", .{});
        }
    }

    return xr_time;
}
