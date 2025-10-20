// Android entry point for Hello Clicky Hands example
// Uses Meta's ANR-free event loop pattern

const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("android/native_activity.h");
    @cInclude("android/native_window.h");
    @cInclude("android/looper.h");
    @cInclude("raylib.h");
});

const VRApp = @import("hello_clicky_hands_shared.zig").VRApp;

// Android lifecycle commands
const AndroidCommand = enum(i32) {
    resume = 1,
    pause = 2,
    destroy = 3,
    init_window = 4,
    term_window = 5,
    window_resized = 6,
};

// Application state
const AndroidAppState = struct {
    app: ?*c.ANativeActivity,
    vr_app: ?VRApp,
    window: ?*c.ANativeWindow,
    looper: ?*c.ALooper,
    cmd_pipe_read: c_int,
    cmd_pipe_write: c_int,
    running: bool,
    window_initialized: bool,
};

var g_state: AndroidAppState = undefined;

// Android logging
fn androidLog(comptime fmt: []const u8, args: anytype) void {
    const ANDROID_LOG_INFO = 4;
    const __android_log_write = @extern(*const fn (c_int, [*:0]const u8, [*:0]const u8) callconv(.C) c_int, .{ .name = "__android_log_write", .linkage = .strong });

    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, fmt, args) catch "Log formatting failed";
    _ = __android_log_write(ANDROID_LOG_INFO, "rlOpenXR", msg.ptr);
}

// Write command to pipe
fn writeCmd(cmd: AndroidCommand) void {
    const cmd_value: i32 = @intFromEnum(cmd);
    _ = std.posix.write(g_state.cmd_pipe_write, std.mem.asBytes(&cmd_value)) catch |err| {
        androidLog("Failed to write command: {}", .{err});
    };
}

// Looper callback to process commands from pipe
fn looperCallback(fd: c_int, events: c_int, data: ?*anyopaque) callconv(.C) c_int {
    _ = events;
    _ = data;

    var cmd: i32 = 0;
    const bytes_read = std.posix.read(fd, std.mem.asBytes(&cmd)) catch |err| {
        androidLog("Failed to read command: {}", .{err});
        return 1;
    };

    if (bytes_read != @sizeOf(i32)) {
        return 1;
    }

    const android_cmd: AndroidCommand = @enumFromInt(cmd);

    switch (android_cmd) {
        .resume => {
            androidLog("APP_CMD_RESUME", .{});
        },
        .pause => {
            androidLog("APP_CMD_PAUSE", .{});
        },
        .destroy => {
            androidLog("APP_CMD_DESTROY", .{});
            g_state.running = false;
        },
        .init_window => {
            androidLog("APP_CMD_INIT_WINDOW", .{});
            if (g_state.window) |win| {
                androidLog("Window size: {}x{}", .{ c.ANativeWindow_getWidth(win), c.ANativeWindow_getHeight(win) });

                // Initialize VR app
                g_state.vr_app = VRApp.init() catch |err| {
                    androidLog("Failed to initialize VR app: {}", .{err});
                    return 1;
                };

                g_state.window_initialized = true;
                androidLog("VR app initialized successfully", .{});
            }
        },
        .term_window => {
            androidLog("APP_CMD_TERM_WINDOW", .{});
            if (g_state.vr_app) |*vr_app| {
                androidLog("Cleaning up VR app", .{});
                vr_app.deinit();
                g_state.vr_app = null;
            }
            g_state.window_initialized = false;
        },
        .window_resized => {
            androidLog("APP_CMD_WINDOW_RESIZED", .{});
            if (g_state.window) |win| {
                androidLog("New window size: {}x{}", .{ c.ANativeWindow_getWidth(win), c.ANativeWindow_getHeight(win) });
            }
        },
    }

    return 1; // Continue receiving events
}

// Android lifecycle callbacks
export fn onStart(activity: ?*c.ANativeActivity) callconv(.C) void {
    _ = activity;
    androidLog("onStart callback", .{});
}

export fn onResume(activity: ?*c.ANativeActivity) callconv(.C) void {
    _ = activity;
    androidLog("onResume callback", .{});
    writeCmd(.resume);
}

export fn onPause(activity: ?*c.ANativeActivity) callconv(.C) void {
    _ = activity;
    androidLog("onPause callback", .{});
    writeCmd(.pause);
}

export fn onStop(activity: ?*c.ANativeActivity) callconv(.C) void {
    _ = activity;
    androidLog("onStop callback", .{});
}

export fn onDestroy(activity: ?*c.ANativeActivity) callconv(.C) void {
    _ = activity;
    androidLog("onDestroy callback", .{});
    writeCmd(.destroy);
}

export fn onNativeWindowCreated(activity: ?*c.ANativeActivity, window: ?*c.ANativeWindow) callconv(.C) void {
    _ = activity;
    androidLog("onNativeWindowCreated callback", .{});
    g_state.window = window;
    writeCmd(.init_window);
}

export fn onNativeWindowDestroyed(activity: ?*c.ANativeActivity, window: ?*c.ANativeWindow) callconv(.C) void {
    _ = activity;
    _ = window;
    androidLog("onWindowDestroyed callback", .{});
    writeCmd(.term_window);
}

export fn onNativeWindowResized(activity: ?*c.ANativeActivity, window: ?*c.ANativeWindow) callconv(.C) void {
    _ = activity;
    _ = window;
    androidLog("onWindowResized callback", .{});
    writeCmd(.window_resized);
}

export fn ANativeActivity_onCreate(
    activity: ?*c.ANativeActivity,
    saved_state: ?*anyopaque,
    saved_state_size: usize,
) callconv(.C) void {
    _ = saved_state;
    _ = saved_state_size;

    androidLog("ANativeActivity_onCreate", .{});

    // Initialize global state
    g_state = AndroidAppState{
        .app = activity,
        .vr_app = null,
        .window = null,
        .looper = null,
        .cmd_pipe_read = -1,
        .cmd_pipe_write = -1,
        .running = true,
        .window_initialized = false,
    };

    // Create pipe for commands
    var pipe_fds: [2]c_int = undefined;
    const pipe_result = std.posix.pipe(&pipe_fds) catch |err| {
        androidLog("Failed to create pipe: {}", .{err});
        return;
    };
    g_state.cmd_pipe_read = pipe_fds[0];
    g_state.cmd_pipe_write = pipe_fds[1];

    // Setup looper
    g_state.looper = c.ALooper_prepare(c.ALOOPER_PREPARE_ALLOW_NON_CALLBACKS);
    _ = c.ALooper_addFd(g_state.looper, g_state.cmd_pipe_read, 0, c.ALOOPER_EVENT_INPUT, looperCallback, null);

    // Register callbacks
    if (activity) |act| {
        act.callbacks.*.onStart = onStart;
        act.callbacks.*.onResume = onResume;
        act.callbacks.*.onPause = onPause;
        act.callbacks.*.onStop = onStop;
        act.callbacks.*.onDestroy = onDestroy;
        act.callbacks.*.onNativeWindowCreated = onNativeWindowCreated;
        act.callbacks.*.onNativeWindowDestroyed = onNativeWindowDestroyed;
        act.callbacks.*.onNativeWindowResized = onNativeWindowResized;
    }

    // Main loop
    androidLog("Entering main loop", .{});
    while (g_state.running) {
        // Process events with timeout
        const timeout_ms = if (g_state.window_initialized) 0 else -1;
        const result = c.ALooper_pollAll(timeout_ms, null, null, null);

        if (result == c.ALOOPER_POLL_ERROR) {
            androidLog("ALooper_pollAll error", .{});
            break;
        }

        // Update and render if window is ready
        if (g_state.window_initialized) {
            if (g_state.vr_app) |*vr_app| {
                vr_app.update();
                vr_app.render();
            }
        }
    }

    // Cleanup
    androidLog("Exiting main loop", .{});
    if (g_state.vr_app) |*vr_app| {
        androidLog("Final cleanup of VR app", .{});
        vr_app.deinit();
    }

    if (g_state.cmd_pipe_read != -1) std.posix.close(g_state.cmd_pipe_read);
    if (g_state.cmd_pipe_write != -1) std.posix.close(g_state.cmd_pipe_write);

    androidLog("ANativeActivity_onCreate complete", .{});
}
