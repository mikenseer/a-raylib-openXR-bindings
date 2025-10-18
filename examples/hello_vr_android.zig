const std = @import("std");
const builtin = @import("builtin");
const rl = @import("rlOpenXR");
const c = rl.c;
const VRApp = @import("hello_vr_shared.zig").VRApp;

// Android logging
extern "log" fn __android_log_write(prio: c_int, tag: [*:0]const u8, text: [*:0]const u8) c_int;
const ANDROID_LOG_INFO = 4;
const ANDROID_LOG_ERROR = 6;

fn androidLog(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, fmt, args) catch "Log formatting failed";
    _ = __android_log_write(ANDROID_LOG_INFO, "rlOpenXR", msg.ptr);
}

fn androidLogError(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, fmt, args) catch "Log formatting failed";
    _ = __android_log_write(ANDROID_LOG_ERROR, "rlOpenXR", msg.ptr);
}

// Android NDK types
pub const ANativeActivity = extern struct {
    callbacks: *ANativeActivityCallbacks,
    vm: *anyopaque,
    env: *anyopaque,
    clazz: *anyopaque,
    internalDataPath: [*:0]const u8,
    externalDataPath: [*:0]const u8,
    sdkVersion: i32,
    instance: ?*anyopaque,
    assetManager: *anyopaque,
    obbPath: [*:0]const u8,
};

pub const ANativeActivityCallbacks = extern struct {
    onStart: ?*const fn (activity: *ANativeActivity) callconv(.c) void = null,
    onResume: ?*const fn (activity: *ANativeActivity) callconv(.c) void = null,
    onSaveInstanceState: ?*const fn (activity: *ANativeActivity, outSize: *usize) callconv(.c) ?*anyopaque = null,
    onPause: ?*const fn (activity: *ANativeActivity) callconv(.c) void = null,
    onStop: ?*const fn (activity: *ANativeActivity) callconv(.c) void = null,
    onDestroy: ?*const fn (activity: *ANativeActivity) callconv(.c) void = null,
    onWindowFocusChanged: ?*const fn (activity: *ANativeActivity, hasFocus: i32) callconv(.c) void = null,
    onNativeWindowCreated: ?*const fn (activity: *ANativeActivity, window: *anyopaque) callconv(.c) void = null,
    onNativeWindowResized: ?*const fn (activity: *ANativeActivity, window: *anyopaque) callconv(.c) void = null,
    onNativeWindowRedrawNeeded: ?*const fn (activity: *ANativeActivity, window: *anyopaque) callconv(.c) void = null,
    onNativeWindowDestroyed: ?*const fn (activity: *ANativeActivity, window: *anyopaque) callconv(.c) void = null,
    onInputQueueCreated: ?*const fn (activity: *ANativeActivity, queue: *anyopaque) callconv(.c) void = null,
    onInputQueueDestroyed: ?*const fn (activity: *ANativeActivity, queue: *anyopaque) callconv(.c) void = null,
    onContentRectChanged: ?*const fn (activity: *ANativeActivity, rect: *const anyopaque) callconv(.c) void = null,
    onConfigurationChanged: ?*const fn (activity: *ANativeActivity) callconv(.c) void = null,
    onLowMemory: ?*const fn (activity: *ANativeActivity) callconv(.c) void = null,
};

// Application state
const AppState = struct {
    activity: *ANativeActivity,
    window: ?*anyopaque = null,
    running: std.atomic.Value(bool),
    render_thread: ?std.Thread = null,
    vr_app: ?VRApp = null,
};

// Render thread function
fn renderThread(state: *AppState) void {
    // Wait for window to be available
    while (state.window == null and state.running.load(.acquire)) {
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    if (!state.running.load(.acquire)) {
        return;
    }

    // Set Android context for OpenXR
    rl.setAndroidContext(.{
        .vm = state.activity.vm,
        .activity = state.activity.clazz,
    });

    // Initialize EGL and OpenGL ES context
    if (!rl.initializeGraphicsContext()) {
        androidLogError("Failed to initialize graphics context", .{});
        state.running.store(false, .release);
        return;
    }

    // Initialize VR application
    var vr_app = VRApp.init() catch |err| {
        androidLogError("Failed to initialize VR app: {}", .{err});
        state.running.store(false, .release);
        return;
    };
    state.vr_app = vr_app;

    // Main render loop
    while (state.running.load(.acquire) and !vr_app.shouldClose()) {
        vr_app.update();
        vr_app.render();
    }

    vr_app.deinit();
    state.vr_app = null;
}

// Lifecycle callbacks
fn onStart(activity: *ANativeActivity) callconv(.c) void {
    _ = activity;
}

fn onResume(activity: *ANativeActivity) callconv(.c) void {
    _ = activity;
}

fn onPause(activity: *ANativeActivity) callconv(.c) void {
    _ = activity;
}

fn onStop(activity: *ANativeActivity) callconv(.c) void {
    _ = activity;
}

fn onDestroy(activity: *ANativeActivity) callconv(.c) void {
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));

        // Signal render thread to stop
        state.running.store(false, .release);

        // Wait for render thread to finish
        if (state.render_thread) |thread| {
            thread.join();
        }

        const allocator = std.heap.c_allocator;
        allocator.destroy(state);
        activity.instance = null;
    }
}

fn onWindowCreated(activity: *ANativeActivity, window: *anyopaque) callconv(.c) void {
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.window = window;

        // Start render thread if not already running
        if (state.render_thread == null) {
            state.running.store(true, .release);
            state.render_thread = std.Thread.spawn(.{}, renderThread, .{state}) catch |err| {
                androidLogError("Failed to spawn render thread: {}", .{err});
                return;
            };
        }
    }
}

fn onWindowDestroyed(activity: *ANativeActivity, window: *anyopaque) callconv(.c) void {
    _ = window;
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.window = null;

        // Signal render thread to stop
        state.running.store(false, .release);

        // Wait for thread to finish
        if (state.render_thread) |thread| {
            thread.join();
            state.render_thread = null;
        }
    }
}

// Dummy main function to satisfy linker (never called on Android)
// Android uses ANativeActivity_onCreate as the entry point
export fn main() callconv(.c) c_int {
    return 0;
}

// Main Android entry point
export fn ANativeActivity_onCreate(
    activity: *ANativeActivity,
    savedState: ?*anyopaque,
    savedStateSize: usize,
) callconv(.c) void {
    _ = savedState;
    _ = savedStateSize;

    // Allocate app state
    const allocator = std.heap.c_allocator;
    const state = allocator.create(AppState) catch {
        androidLogError("Failed to allocate app state", .{});
        return;
    };

    state.* = AppState{
        .activity = activity,
        .running = std.atomic.Value(bool).init(false),
    };

    // Set up callbacks
    activity.callbacks.onStart = onStart;
    activity.callbacks.onResume = onResume;
    activity.callbacks.onPause = onPause;
    activity.callbacks.onStop = onStop;
    activity.callbacks.onDestroy = onDestroy;
    activity.callbacks.onNativeWindowCreated = onWindowCreated;
    activity.callbacks.onNativeWindowDestroyed = onWindowDestroyed;

    // Store state in activity
    activity.instance = state;
}
