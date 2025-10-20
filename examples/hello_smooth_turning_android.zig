// Android VR application following Meta's android_native_app_glue pattern
// Main thread runs an event loop to process Android lifecycle events properly

const std = @import("std");
const builtin = @import("builtin");
const rl = @import("rlOpenXR");
const c = rl.c;
const VRApp = @import("hello_smooth_turning_shared.zig").VRApp;

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
const ANativeActivity = extern struct {
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

const ANativeActivityCallbacks = extern struct {
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

// ALooper functions for event loop
extern "c" fn ALooper_prepare(opts: c_int) ?*anyopaque;
extern "c" fn ALooper_pollAll(timeoutMillis: c_int, outFd: ?*c_int, outEvents: ?*c_int, outData: ?*?*anyopaque) c_int;
extern "c" fn ALooper_addFd(looper: *anyopaque, fd: c_int, ident: c_int, events: c_int, callback: ?*anyopaque, data: ?*anyopaque) c_int;
const ALOOPER_PREPARE_ALLOW_NON_CALLBACKS = 1;
const ALOOPER_EVENT_INPUT = 1;

// Pipe functions
extern "c" fn pipe(pipefd: *[2]c_int) c_int;
extern "c" fn write(fd: c_int, buf: *const anyopaque, count: usize) isize;
extern "c" fn read(fd: c_int, buf: *anyopaque, count: usize) isize;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
const F_SETFL = 4;
const O_NONBLOCK = 2048;

// Thread functions
const pthread_t = *anyopaque;
extern "c" fn pthread_create(thread: *pthread_t, attr: ?*anyopaque, start_routine: *const fn (*anyopaque) callconv(.c) ?*anyopaque, arg: *anyopaque) c_int;

// Lifecycle event types
const AppCmd = enum(u8) {
    app_start,
    app_resume,
    app_pause,
    app_stop,
    app_destroy,
    window_created,
    window_destroyed,
    window_focus_changed,
    config_changed,
};

// Input queue functions
extern "c" fn AInputQueue_attachLooper(queue: *anyopaque, looper: *anyopaque, ident: c_int, callback: ?*anyopaque, data: ?*anyopaque) void;
extern "c" fn AInputQueue_detachLooper(queue: *anyopaque) void;
extern "c" fn AInputQueue_hasEvents(queue: *anyopaque) c_int;
extern "c" fn AInputQueue_getEvent(queue: *anyopaque, outEvent: **anyopaque) c_int;
extern "c" fn AInputQueue_preDispatchEvent(queue: *anyopaque, event: *anyopaque) c_int;
extern "c" fn AInputQueue_finishEvent(queue: *anyopaque, event: *anyopaque, handled: c_int) void;

// Application state
const AppState = struct {
    activity: *ANativeActivity,
    looper: ?*anyopaque = null,
    cmd_read_fd: c_int = -1,
    cmd_write_fd: c_int = -1,

    // App state
    window: ?*anyopaque = null,
    input_queue: ?*anyopaque = null,
    resumed: bool = false,
    running: bool = true,
    vr_app: ?VRApp = null,

    mutex: std.Thread.Mutex = .{},

    fn init(activity: *ANativeActivity) !*AppState {
        const allocator = std.heap.c_allocator;
        const state = try allocator.create(AppState);

        state.* = AppState{
            .activity = activity,
        };

        // Create pipe for commands
        var pipefd: [2]c_int = undefined;
        if (pipe(&pipefd) != 0) {
            androidLogError("Failed to create command pipe", .{});
            return error.PipeCreationFailed;
        }

        state.cmd_read_fd = pipefd[0];
        state.cmd_write_fd = pipefd[1];

        return state;
    }

    fn deinit(self: *AppState) void {
        if (self.cmd_read_fd >= 0) _ = close(self.cmd_read_fd);
        if (self.cmd_write_fd >= 0) _ = close(self.cmd_write_fd);

        const allocator = std.heap.c_allocator;
        allocator.destroy(self);
    }

    fn writeCmd(self: *AppState, cmd: AppCmd) void {
        const cmd_byte: u8 = @intFromEnum(cmd);
        _ = write(self.cmd_write_fd, &cmd_byte, 1);
    }

    fn readCmd(self: *AppState) ?AppCmd {
        var cmd_byte: u8 = 0;
        const bytes_read = read(self.cmd_read_fd, &cmd_byte, 1);
        if (bytes_read == 1) {
            return @enumFromInt(cmd_byte);
        }
        return null;
    }

    fn processCmd(self: *AppState, cmd: AppCmd) void {
        switch (cmd) {
            .app_start => {},
            .app_resume => {
                self.mutex.lock();
                self.resumed = true;
                self.mutex.unlock();
            },
            .app_pause => {
                self.mutex.lock();
                self.resumed = false;
                self.mutex.unlock();
            },
            .app_stop => {},
            .app_destroy => {
                self.mutex.lock();
                self.running = false;
                self.mutex.unlock();
            },
            .window_created => {
                androidLog("Window created, initializing VR", .{});
                self.initializeVR() catch |err| {
                    androidLogError("Failed to initialize VR: {}", .{err});
                };
            },
            .window_destroyed => {
                androidLog("Window destroyed, cleaning up VR", .{});
                self.cleanupVR();
            },
            .window_focus_changed => {},
            .config_changed => {},
        }
    }

    fn initializeVR(self: *AppState) !void {
        if (self.vr_app != null) return; // Already initialized

        // Set Android context for OpenXR
        rl.setAndroidContext(.{
            .vm = self.activity.vm,
            .activity = self.activity.clazz,
        });

        // Initialize EGL and OpenGL ES context
        if (!rl.initializeGraphicsContext()) {
            return error.GraphicsInitFailed;
        }

        // Initialize VR application
        self.vr_app = try VRApp.init();
        androidLog("VR initialized successfully", .{});
    }

    fn cleanupVR(self: *AppState) void {
        if (self.vr_app) |*vr_app| {
            vr_app.deinit();
            self.vr_app = null;
        }
    }
};

// Lifecycle callbacks - these run on the Activity thread, not our main thread
// They must NOT block! Just write a command and return immediately.

fn onStart(activity: *ANativeActivity) callconv(.c) void {
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.writeCmd(.app_start);
    }
}

fn onResume(activity: *ANativeActivity) callconv(.c) void {
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.writeCmd(.app_resume);
    }
}

fn onPause(activity: *ANativeActivity) callconv(.c) void {
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.writeCmd(.app_pause);
    }
}

fn onStop(activity: *ANativeActivity) callconv(.c) void {
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.writeCmd(.app_stop);
    }
}

fn onDestroy(activity: *ANativeActivity) callconv(.c) void {
    androidLog("onDestroy callback", .{});
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.writeCmd(.app_destroy);
        // Don't wait for the main thread, just signal it
    }
}

fn onWindowCreated(activity: *ANativeActivity, window: *anyopaque) callconv(.c) void {
    androidLog("onWindowCreated callback", .{});
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.mutex.lock();
        state.window = window;
        state.mutex.unlock();
        state.writeCmd(.window_created);
    }
}

fn onWindowDestroyed(activity: *ANativeActivity, window: *anyopaque) callconv(.c) void {
    _ = window;
    androidLog("onWindowDestroyed callback", .{});
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.mutex.lock();
        state.window = null;
        state.mutex.unlock();
        state.writeCmd(.window_destroyed);
    }
}

fn onWindowFocusChanged(activity: *ANativeActivity, hasFocus: c_int) callconv(.c) void {
    _ = hasFocus;
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.writeCmd(.window_focus_changed);
    }
}

fn onConfigurationChanged(activity: *ANativeActivity) callconv(.c) void {
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.writeCmd(.config_changed);
    }
}

fn onInputQueueCreated(activity: *ANativeActivity, queue: *anyopaque) callconv(.c) void {
    androidLog("onInputQueueCreated callback", .{});
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        state.mutex.lock();
        state.input_queue = queue;
        state.mutex.unlock();
        // Attach to looper if it exists
        if (state.looper) |looper| {
            const input_queue_id = 2; // ID for input queue
            AInputQueue_attachLooper(queue, looper, input_queue_id, null, null);
            androidLog("Input queue attached to looper", .{});
        }
    }
}

fn onInputQueueDestroyed(activity: *ANativeActivity, queue: *anyopaque) callconv(.c) void {
    androidLog("onInputQueueDestroyed callback", .{});
    if (activity.instance) |instance| {
        const state: *AppState = @ptrCast(@alignCast(instance));
        // Detach from looper
        AInputQueue_detachLooper(queue);
        state.mutex.lock();
        state.input_queue = null;
        state.mutex.unlock();
        androidLog("Input queue detached from looper", .{});
    }
}

// Main event loop thread - This is the real "main" of our app
fn mainEventLoop(app_state_ptr: *anyopaque) callconv(.c) ?*anyopaque {
    const state: *AppState = @ptrCast(@alignCast(app_state_ptr));
    androidLog("Event loop thread starting", .{});

    // Prepare looper for THIS thread (the event loop thread)
    state.looper = ALooper_prepare(ALOOPER_PREPARE_ALLOW_NON_CALLBACKS);
    if (state.looper == null) {
        androidLogError("Failed to prepare ALooper in event loop thread", .{});
        return null;
    }

    // Make the read end of the pipe non-blocking so we can drain it without blocking
    _ = fcntl(state.cmd_read_fd, F_SETFL, @as(c_int, O_NONBLOCK));

    // Register command pipe with looper
    const looper_cmd_id = 1;
    const add_result = ALooper_addFd(
        state.looper.?,
        state.cmd_read_fd,
        looper_cmd_id,
        ALOOPER_EVENT_INPUT,
        null,
        null,
    );
    if (add_result != 1) {
        androidLogError("Failed to register pipe with ALooper in event loop thread", .{});
        return null;
    }

    androidLog("Event loop initialized, entering main loop", .{});

    // Main event loop - process Android events
    while (true) {
        // Check if we should exit
        state.mutex.lock();
        const should_run = state.running;
        state.mutex.unlock();

        if (!should_run) {
            androidLog("Event loop exiting", .{});
            break;
        }

        // Poll for events with 0 timeout (non-blocking when VR is active)
        // Use blocking timeout when paused to save battery
        const timeout: c_int = if (state.resumed and state.vr_app != null) 0 else -1;
        _ = ALooper_pollAll(timeout, null, null, null);

        // Process ALL pending commands from the pipe (drain it completely)
        // This ensures we stay responsive to lifecycle events even when rendering
        while (state.readCmd()) |cmd| {
            state.processCmd(cmd);
        }

        // Process input events (this prevents ANR from input timeout)
        state.mutex.lock();
        const input_queue = state.input_queue;
        state.mutex.unlock();

        if (input_queue) |queue| {
            // Drain all pending input events
            var event: *anyopaque = undefined;
            while (AInputQueue_getEvent(queue, &event) >= 0) {
                // Pre-dispatch for IME handling
                if (AInputQueue_preDispatchEvent(queue, event) == 0) {
                    // Event not handled by pre-dispatch, we can process it
                    // For now, just mark it as handled to prevent ANR
                    // In a real app, you'd process the input here
                    AInputQueue_finishEvent(queue, event, 1); // 1 = handled
                }
            }
        }

        // Render VR frame if active
        if (state.resumed and state.vr_app != null) {
            if (state.vr_app) |*vr_app| {
                vr_app.update();
                vr_app.render();
            }
        }
    }

    // Cleanup
    state.cleanupVR();
    androidLog("Event loop ended", .{});
    return null;
}

// Dummy main to satisfy linker
export fn main() callconv(.c) c_int {
    return 0;
}

// Android entry point - spawns the main thread
export fn ANativeActivity_onCreate(
    activity: *ANativeActivity,
    savedState: ?*anyopaque,
    savedStateSize: usize,
) callconv(.c) void {
    _ = savedState;
    _ = savedStateSize;

    androidLog("ANativeActivity_onCreate", .{});

    // Create app state
    const state = AppState.init(activity) catch {
        androidLogError("Failed to create app state", .{});
        return;
    };

    // Store state in activity
    activity.instance = state;

    // Set up all callbacks
    activity.callbacks.onStart = onStart;
    activity.callbacks.onResume = onResume;
    activity.callbacks.onPause = onPause;
    activity.callbacks.onStop = onStop;
    activity.callbacks.onDestroy = onDestroy;
    activity.callbacks.onNativeWindowCreated = onWindowCreated;
    activity.callbacks.onNativeWindowDestroyed = onWindowDestroyed;
    activity.callbacks.onWindowFocusChanged = onWindowFocusChanged;
    activity.callbacks.onConfigurationChanged = onConfigurationChanged;
    activity.callbacks.onInputQueueCreated = onInputQueueCreated;
    activity.callbacks.onInputQueueDestroyed = onInputQueueDestroyed;

    androidLog("Creating event loop thread", .{});

    // Spawn event loop thread - this allows onCreate to return so the system
    // can deliver input events and lifecycle callbacks
    var thread: pthread_t = undefined;
    const result = pthread_create(&thread, null, &mainEventLoop, state);
    if (result != 0) {
        androidLogError("Failed to create event loop thread: {}", .{result});
        state.deinit();
        activity.instance = null;
        return;
    }

    androidLog("ANativeActivity_onCreate complete - event loop thread running", .{});
}
