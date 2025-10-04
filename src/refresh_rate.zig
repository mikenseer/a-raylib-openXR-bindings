// Refresh rate configuration for OpenXR (72-300Hz support)
// Primarily for Quest and other variable refresh rate HMDs

const std = @import("std");
const main = @import("rlOpenXR.zig");
const c = @cImport({
    @cInclude("openxr/openxr.h");
});

const RefreshRateError = error{
    ExtensionNotSupported,
    QueryFailed,
    SetFailed,
};

// Function pointers for refresh rate extension (XR_FB_display_refresh_rate)
var xrEnumerateDisplayRefreshRatesFB: ?*const fn (
    c.XrSession,
    u32,
    *u32,
    [*]f32,
) callconv(.C) c.XrResult = null;

var xrGetDisplayRefreshRateFB: ?*const fn (
    c.XrSession,
    *f32,
) callconv(.C) c.XrResult = null;

var xrRequestDisplayRefreshRateFB: ?*const fn (
    c.XrSession,
    f32,
) callconv(.C) c.XrResult = null;

pub fn loadRefreshRateExtension(instance: c.XrInstance) bool {
    var enum_func: ?*anyopaque = null;
    var get_func: ?*anyopaque = null;
    var set_func: ?*anyopaque = null;

    var result = c.xrGetInstanceProcAddr(
        instance,
        "xrEnumerateDisplayRefreshRatesFB",
        &enum_func,
    );
    if (result < 0) return false;

    result = c.xrGetInstanceProcAddr(
        instance,
        "xrGetDisplayRefreshRateFB",
        &get_func,
    );
    if (result < 0) return false;

    result = c.xrGetInstanceProcAddr(
        instance,
        "xrRequestDisplayRefreshRateFB",
        &set_func,
    );
    if (result < 0) return false;

    xrEnumerateDisplayRefreshRatesFB = @ptrCast(enum_func);
    xrGetDisplayRefreshRateFB = @ptrCast(get_func);
    xrRequestDisplayRefreshRateFB = @ptrCast(set_func);

    std.debug.print("Display refresh rate extension loaded successfully\n", .{});
    return true;
}

pub fn getSupportedRefreshRates(
    session: c.XrSession,
    allocator: std.mem.Allocator,
) ![]f32 {
    const enum_fn = xrEnumerateDisplayRefreshRatesFB orelse return error.ExtensionNotSupported;

    var count: u32 = 0;
    var result = enum_fn(session, 0, &count, undefined);
    if (!main.xrCheck(result, "Failed to get refresh rate count", .{})) {
        return error.QueryFailed;
    }

    const rates = try allocator.alloc(f32, count);
    errdefer allocator.free(rates);

    result = enum_fn(session, count, &count, rates.ptr);
    if (!main.xrCheck(result, "Failed to enumerate refresh rates", .{})) {
        return error.QueryFailed;
    }

    std.debug.print("Supported refresh rates: ", .{});
    for (rates) |rate| {
        std.debug.print("{d}Hz ", .{rate});
    }
    std.debug.print("\n", .{});

    return rates;
}

pub fn getCurrentRefreshRate(session: c.XrSession) !f32 {
    const get_fn = xrGetDisplayRefreshRateFB orelse return error.ExtensionNotSupported;

    var rate: f32 = 0;
    const result = get_fn(session, &rate);
    if (!main.xrCheck(result, "Failed to get current refresh rate", .{})) {
        return error.QueryFailed;
    }

    return rate;
}

pub fn setRefreshRate(session: c.XrSession, target_rate: f32) !void {
    const set_fn = xrRequestDisplayRefreshRateFB orelse return error.ExtensionNotSupported;

    const result = set_fn(session, target_rate);
    if (!main.xrCheck(result, "Failed to set refresh rate to {d}Hz", .{target_rate})) {
        return error.SetFailed;
    }

    std.debug.print("Requested refresh rate: {d}Hz\n", .{target_rate});
}

/// Helper function to select the best refresh rate from supported rates
/// Prefers rates in this order: 120Hz, 90Hz, 144Hz, highest available
pub fn selectBestRefreshRate(rates: []const f32) f32 {
    if (rates.len == 0) return 0;

    // Preferred rates
    const preferred = [_]f32{ 120.0, 90.0, 144.0, 72.0 };

    for (preferred) |pref| {
        for (rates) |rate| {
            if (@abs(rate - pref) < 0.1) {
                return rate;
            }
        }
    }

    // Return highest available
    var highest: f32 = rates[0];
    for (rates) |rate| {
        if (rate > highest) {
            highest = rate;
        }
    }
    return highest;
}

/// Helper to select a refresh rate, clamped to 72-300Hz range
pub fn selectRefreshRateInRange(rates: []const f32, min: f32, max: f32) ?f32 {
    var best: ?f32 = null;

    for (rates) |rate| {
        if (rate >= min and rate <= max) {
            if (best == null or rate > best.?) {
                best = rate;
            }
        }
    }

    return best;
}
