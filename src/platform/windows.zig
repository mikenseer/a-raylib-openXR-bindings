const std = @import("std");
const main = @import("../rlOpenXR.zig");
const c = main.c; // Use main's C imports to avoid type mismatches

pub const GraphicsBinding = c.XrGraphicsBindingOpenGLWin32KHR;

pub fn getCurrentGraphicsBinding() GraphicsBinding {
    return .{
        .type = c.XR_TYPE_GRAPHICS_BINDING_OPENGL_WIN32_KHR,
        .next = null,
        .hDC = wglGetCurrentDC(),
        .hGLRC = wglGetCurrentContext(),
    };
}

extern "opengl32" fn wglGetCurrentDC() callconv(.c) c.HDC;
extern "opengl32" fn wglGetCurrentContext() callconv(.c) c.HGLRC;

pub fn convertPerformanceCounterToTime(
    instance: c.XrInstance,
    convert_fn: ?*const fn (c.XrInstance, *const c.LARGE_INTEGER, *c.XrTime) callconv(.c) c.XrResult,
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
