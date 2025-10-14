// Frame loop implementation for OpenXR
// Ported from rlOpenXR.cpp (FireFlyForLife)

const std = @import("std");
const main = @import("rlOpenXR.zig");
const c = main.c; // Use main's C imports to avoid type mismatches

pub fn updateOpenXR(state: *main.State) void {
    // Poll OpenXR events
    var runtime_event: c.XrEventDataBuffer = .{
        .type = c.XR_TYPE_EVENT_DATA_BUFFER,
        .next = null,
    };

    var poll_result = c.xrPollEvent(state.data.instance, &runtime_event);
    while (poll_result == c.XR_SUCCESS) {
        switch (runtime_event.type) {
            c.XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING => {
                const event: *c.XrEventDataInstanceLossPending = @ptrCast(&runtime_event);
                std.debug.print("EVENT: instance loss pending at {d}!\n", .{event.lossTime});
            },
            c.XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED => {
                const event: *c.XrEventDataSessionStateChanged = @ptrCast(&runtime_event);
                std.debug.print("EVENT: session state changed from {d} to {d}\n", .{
                    state.data.session_state,
                    event.state,
                });
                state.data.session_state = event.state;
                handleSessionStateChange(state);
            },
            c.XR_TYPE_EVENT_DATA_INTERACTION_PROFILE_CHANGED => {
                std.debug.print("EVENT: interaction profile changed\n", .{});
            },
            else => {
                std.debug.print("Unhandled event type: {d}\n", .{runtime_event.type});
            },
        }

        runtime_event.type = c.XR_TYPE_EVENT_DATA_BUFFER;
        poll_result = c.xrPollEvent(state.data.instance, &runtime_event);
    }

    // Wait for next frame
    if (state.session_running) {
        const frame_wait_info = c.XrFrameWaitInfo{
            .type = c.XR_TYPE_FRAME_WAIT_INFO,
            .next = null,
        };

        const result = c.xrWaitFrame(state.data.session, &frame_wait_info, &state.frame_state);
        if (!main.xrCheck(result, "xrWaitFrame failed", .{})) {
            return;
        }
    }
}

fn handleSessionStateChange(state: *main.State) void {
    switch (state.data.session_state) {
        c.XR_SESSION_STATE_IDLE, c.XR_SESSION_STATE_UNKNOWN => {
            state.run_framecycle = false;
        },
        c.XR_SESSION_STATE_READY => {
            if (!state.session_running) {
                const session_begin_info = c.XrSessionBeginInfo{
                    .type = c.XR_TYPE_SESSION_BEGIN_INFO,
                    .next = null,
                    .primaryViewConfigurationType = state.data.view_type,
                };

                const result = c.xrBeginSession(state.data.session, &session_begin_info);
                if (main.xrCheck(result, "Session started", .{})) {
                    state.session_running = true;
                }
            }
            state.run_framecycle = true;
        },
        c.XR_SESSION_STATE_SYNCHRONIZED, c.XR_SESSION_STATE_VISIBLE, c.XR_SESSION_STATE_FOCUSED => {
            state.run_framecycle = true;
        },
        c.XR_SESSION_STATE_STOPPING => {
            if (state.session_running) {
                const result = c.xrEndSession(state.data.session);
                if (main.xrCheck(result, "Session ended", .{})) {
                    state.session_running = false;
                }
            }
            state.run_framecycle = false;
        },
        c.XR_SESSION_STATE_LOSS_PENDING, c.XR_SESSION_STATE_EXITING => {
            _ = c.xrDestroySession(state.data.session);
            state.run_framecycle = false;
        },
        else => {},
    }
}

pub fn beginOpenXR(state: *main.State) bool {
    if (!state.session_running) {
        return false;
    }

    // Locate views
    const view_locate_info = c.XrViewLocateInfo{
        .type = c.XR_TYPE_VIEW_LOCATE_INFO,
        .next = null,
        .viewConfigurationType = state.data.view_type,
        .displayTime = state.frame_state.predictedDisplayTime,
        .space = state.data.play_space,
    };

    var view_state: c.XrViewState = .{ .type = c.XR_TYPE_VIEW_STATE, .next = null };
    var output_view_count: u32 = 0;

    var result = c.xrLocateViews(
        state.data.session,
        &view_locate_info,
        &view_state,
        @intCast(state.views.items.len),
        &output_view_count,
        state.views.items.ptr,
    );
    if (!main.xrCheck(result, "Could not locate views", .{})) {
        return false;
    }

    // Copy view pose and fov to projection views
    for (state.projection_views.items, 0..) |*proj, i| {
        proj.pose = state.views.items[i].pose;
        proj.fov = state.views.items[i].fov;
    }

    // Get view location for camera
    var view_location: c.XrSpaceLocation = .{ .type = c.XR_TYPE_SPACE_LOCATION, .next = null };
    result = c.xrLocateSpace(
        state.data.view_space,
        state.data.play_space,
        state.frame_state.predictedDisplayTime,
        &view_location,
    );
    if (!main.xrCheck(result, "Could not locate view space", .{})) {
        return false;
    }

    // Begin frame
    const frame_begin_info = c.XrFrameBeginInfo{ .type = c.XR_TYPE_FRAME_BEGIN_INFO, .next = null };
    result = c.xrBeginFrame(state.data.session, &frame_begin_info);
    if (!main.xrCheck(result, "Failed to begin frame", .{})) {
        return false;
    }

    if (!state.run_framecycle) {
        return false;
    }

    // Acquire swapchain image
    var swapchain_image_index: u32 = 0;
    const acquire_info = c.XrSwapchainImageAcquireInfo{ .type = c.XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO, .next = null };
    result = c.xrAcquireSwapchainImage(state.swapchain, &acquire_info, &swapchain_image_index);
    if (!main.xrCheck(result, "Failed to acquire swapchain image", .{})) {
        return false;
    }

    const wait_info = c.XrSwapchainImageWaitInfo{
        .type = c.XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO,
        .next = null,
        .timeout = c.XR_INFINITE_DURATION,
    };
    result = c.xrWaitSwapchainImage(state.swapchain, &wait_info);
    if (!main.xrCheck(result, "Failed to wait for swapchain image", .{})) {
        return false;
    }

    const color_image = state.swapchain_images.items[swapchain_image_index].image;

    // Attach color to framebuffer
    c.rlFramebufferAttach(
        state.fbo,
        color_image,
        c.RL_ATTACHMENT_COLOR_CHANNEL0,
        c.RL_ATTACHMENT_TEXTURE2D,
        0,
    );

    // Attach depth if enabled
    if (state.extensions.depth_enabled) {
        var depth_swapchain_image_index: u32 = 0;
        const depth_acquire_info = c.XrSwapchainImageAcquireInfo{
            .type = c.XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO,
            .next = null,
        };
        result = c.xrAcquireSwapchainImage(state.depth_swapchain, &depth_acquire_info, &depth_swapchain_image_index);
        if (main.xrCheck(result, "Acquired depth swapchain image", .{})) {
            const depth_wait_info = c.XrSwapchainImageWaitInfo{
                .type = c.XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO,
                .next = null,
                .timeout = c.XR_INFINITE_DURATION,
            };
            result = c.xrWaitSwapchainImage(state.depth_swapchain, &depth_wait_info);
            if (main.xrCheck(result, "Waited for depth swapchain image", .{})) {
                const depth_image = state.depth_swapchain_images.items[depth_swapchain_image_index].image;
                c.rlFramebufferAttach(
                    state.fbo,
                    depth_image,
                    c.RL_ATTACHMENT_DEPTH,
                    c.RL_ATTACHMENT_TEXTURE2D,
                    0,
                );
            }
        }
    }

    // Begin texture mode
    const render_width = state.viewconfig_views.items[0].recommendedImageRectWidth * 2;
    const render_height = state.viewconfig_views.items[0].recommendedImageRectHeight;

    const render_texture = c.RenderTexture2D{
        .id = state.fbo,
        .texture = .{
            .id = color_image,
            .width = @intCast(render_width),
            .height = @intCast(render_height),
            .mipmaps = 1,
            .format = -1,
        },
        .depth = .{
            .id = 0,
            .width = @intCast(render_width),
            .height = @intCast(render_height),
            .mipmaps = 1,
            .format = -1,
        },
    };

    c.BeginTextureMode(render_texture);
    state.active_fbo = state.fbo;
    c.rlEnableDepthTest(); // Enable depth testing for correct rendering order
    c.rlClearScreenBuffers(); // Clear color and depth buffers

    // Setup stereo rendering
    c.rlEnableStereoRender();

    const proj_left = xrProjectionMatrix(state.views.items[0].fov);
    const proj_right = xrProjectionMatrix(state.views.items[1].fov);
    c.rlSetMatrixProjectionStereo(proj_left, proj_right);

    const view_matrix = matrixInvert(xrMatrix(view_location.pose));
    const view_offset_left = matrixMultiply(xrMatrix(state.views.items[0].pose), view_matrix);
    const view_offset_right = matrixMultiply(xrMatrix(state.views.items[1].pose), view_matrix);
    c.rlSetMatrixViewOffsetStereo(view_offset_right, view_offset_left);

    return true;
}

pub fn endOpenXR(state: *main.State) void {
    if (!state.session_running) {
        return;
    }

    if (state.run_framecycle) {
        c.EndTextureMode();
        state.active_fbo = 0;

        c.rlDisableStereoRender();

        // Release swapchain images
        const release_info = c.XrSwapchainImageReleaseInfo{
            .type = c.XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO,
            .next = null,
        };
        _ = c.xrReleaseSwapchainImage(state.swapchain, &release_info);

        if (state.extensions.depth_enabled) {
            const depth_release_info = c.XrSwapchainImageReleaseInfo{
                .type = c.XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO,
                .next = null,
            };
            _ = c.xrReleaseSwapchainImage(state.depth_swapchain, &depth_release_info);
        }
    }

    // End frame
    const frame_end_info = c.XrFrameEndInfo{
        .type = c.XR_TYPE_FRAME_END_INFO,
        .next = null,
        .displayTime = state.frame_state.predictedDisplayTime,
        .environmentBlendMode = c.XR_ENVIRONMENT_BLEND_MODE_OPAQUE,
        .layerCount = @intCast(state.layers_pointers.items.len),
        .layers = @ptrCast(state.layers_pointers.items.ptr),
    };

    const result = c.xrEndFrame(state.data.session, &frame_end_info);
    _ = main.xrCheck(result, "Failed to end frame", .{});
}

pub fn updateCameraOpenXR(state: *main.State, camera: *c.Camera3D) void {
    const time = getTimeOpenXR(state);

    var view_location: c.XrSpaceLocation = .{ .type = c.XR_TYPE_SPACE_LOCATION, .next = null };
    const result = c.xrLocateSpace(state.data.view_space, state.data.play_space, time, &view_location);
    if (!main.xrCheck(result, "Could not locate view for camera", .{})) {
        return;
    }

    if ((view_location.locationFlags & c.XR_SPACE_LOCATION_POSITION_VALID_BIT) != 0) {
        const pos = view_location.pose.position;
        camera.position = .{ .x = pos.x, .y = pos.y, .z = pos.z };
    }

    if ((view_location.locationFlags & c.XR_SPACE_LOCATION_ORIENTATION_VALID_BIT) != 0) {
        const rot = view_location.pose.orientation;
        const quat = c.Quaternion{ .x = rot.x, .y = rot.y, .z = rot.z, .w = rot.w };
        const forward = c.Vector3RotateByQuaternion(.{ .x = 0, .y = 0, .z = -1 }, quat);
        const up = c.Vector3RotateByQuaternion(.{ .x = 0, .y = 1, .z = 0 }, quat);
        camera.target = c.Vector3Add(camera.position, forward);
        camera.up = up;
    }
}

pub fn getTimeOpenXR(state: *main.State) c.XrTime {
    const builtin = @import("builtin");
    const current_time = switch (builtin.os.tag) {
        .windows => @import("platform/windows.zig").convertPerformanceCounterToTime(
            state.data.instance,
            state.extensions.xrConvertWin32PerformanceCounterToTimeKHR,
        ),
        .linux => @import("platform/linux.zig").convertPerformanceCounterToTime(
            state.data.instance,
            null,
        ),
        else => state.frame_state.predictedDisplayTime,
    };
    const predicted_time = state.frame_state.predictedDisplayTime;

    return @max(current_time, predicted_time);
}

// Helper functions for matrix math
fn xrProjectionMatrix(fov: c.XrFovf) c.Matrix {
    const near: f32 = @floatCast(c.RL_CULL_DISTANCE_NEAR);
    const far: f32 = @floatCast(c.RL_CULL_DISTANCE_FAR);

    const tan_left = std.math.tan(fov.angleLeft);
    const tan_right = std.math.tan(fov.angleRight);
    const tan_down = std.math.tan(fov.angleDown);
    const tan_up = std.math.tan(fov.angleUp);

    const tan_width = tan_right - tan_left;
    const tan_height = tan_up - tan_down;

    return c.Matrix{
        .m0 = 2.0 / tan_width,
        .m1 = 0,
        .m2 = 0,
        .m3 = 0,
        .m4 = 0,
        .m5 = 2.0 / tan_height,
        .m6 = 0,
        .m7 = 0,
        .m8 = (tan_right + tan_left) / tan_width,
        .m9 = (tan_up + tan_down) / tan_height,
        .m10 = -(far + near) / (far - near),
        .m11 = -1,
        .m12 = 0,
        .m13 = 0,
        .m14 = -(far * (near + near)) / (far - near),
        .m15 = 0,
    };
}

fn xrMatrix(pose: c.XrPosef) c.Matrix {
    const translation = c.MatrixTranslate(pose.position.x, pose.position.y, pose.position.z);
    const rotation = c.QuaternionToMatrix(.{
        .x = pose.orientation.x,
        .y = pose.orientation.y,
        .z = pose.orientation.z,
        .w = pose.orientation.w,
    });
    return c.MatrixMultiply(rotation, translation);
}

fn matrixInvert(mat: c.Matrix) c.Matrix {
    return c.MatrixInvert(mat);
}

fn matrixMultiply(left: c.Matrix, right: c.Matrix) c.Matrix {
    return c.MatrixMultiply(left, right);
}

pub fn beginMockHMD(state: *main.State) bool {
    const mock_device = c.VrDeviceInfo{
        .hResolution = 2160,
        .vResolution = 1200,
        .hScreenSize = 0.133793,
        .vScreenSize = 0.0669,
        .eyeToScreenDistance = 0.041,
        .lensSeparationDistance = 0.07,
        .interpupillaryDistance = 0.07,
        .lensDistortionValues = .{ 1.0, 0.22, 0.24, 0.0 },
        .chromaAbCorrection = .{ 0.996, -0.004, 1.014, 0.0 },
    };

    const config = c.LoadVrStereoConfig(mock_device);

    if (state.mock_hmd_rt.id == 0) {
        state.mock_hmd_rt = c.LoadRenderTexture(
            @intCast(mock_device.hResolution),
            @intCast(mock_device.vResolution),
        );
    }

    c.BeginTextureMode(state.mock_hmd_rt);
    state.active_fbo = state.mock_hmd_rt.id;

    c.BeginVrStereoMode(config);

    return true;
}
