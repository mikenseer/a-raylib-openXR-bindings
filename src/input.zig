// Hand tracking and input implementation
// Ported from rlOpenXR.cpp (FireFlyForLife)

const std = @import("std");
const builtin = @import("builtin");
const main = @import("rlOpenXR.zig");
const c = main.c; // Use main's C imports to avoid type mismatches

// Android logging helper
fn androidLog(comptime fmt: []const u8, args: anytype) void {
    if (builtin.abi == .android) {
        const ANDROID_LOG_INFO = 4;
        const __android_log_write = @extern(*const fn (c_int, [*:0]const u8, [*:0]const u8) callconv(.c) c_int, .{ .name = "__android_log_write", .linkage = .strong });

        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrintZ(&buf, fmt, args) catch "Log formatting failed";
        _ = __android_log_write(ANDROID_LOG_INFO, "rlOpenXR", msg.ptr);
    } else {
        std.debug.print(fmt ++ "\n", args);
    }
}

pub fn updateHandsOpenXR(state: *main.State, left: ?*main.HandData, right: ?*main.HandData) void {
    const time = @import("frame.zig").getTimeOpenXR(state);

    const hands = [_]?*main.HandData{ left, right };

    for (hands, 0..) |hand_opt, hand_index| {
        const hand = hand_opt orelse continue;

        // Validate handedness
        if (@intFromEnum(hand.handedness) != hand_index) {
            std.debug.print("Warning: handedness mismatch for hand {d}\n", .{hand_index});
            continue;
        }

        // Fixup invalid identity quaternion
        if (quaternionEquals(hand.orientation, .{ .x = 0, .y = 0, .z = 0, .w = 0 })) {
            hand.orientation = c.QuaternionIdentity();
        }

        hand.valid = false;

        // Get action state
        const get_info = c.XrActionStateGetInfo{
            .type = c.XR_TYPE_ACTION_STATE_GET_INFO,
            .next = null,
            .action = hand.hand_pose_action,
            .subactionPath = hand.hand_pose_subpath,
        };

        var hand_pose_state: c.XrActionStatePose = .{
            .type = c.XR_TYPE_ACTION_STATE_POSE,
            .next = null,
        };

        var result = c.xrGetActionStatePose(state.data.session, &get_info, &hand_pose_state);
        if (!main.xrCheck(result, "Failed to get hand {d} action state", .{hand_index})) {
            continue;
        }

        hand.valid = hand_pose_state.isActive != 0;

        if (hand_pose_state.isActive != 0) {
            var hand_location: c.XrSpaceLocation = .{
                .type = c.XR_TYPE_SPACE_LOCATION,
                .next = null,
            };

            result = c.xrLocateSpace(hand.hand_pose_space, state.data.play_space, time, &hand_location);
            if (!main.xrCheck(result, "Could not retrieve hand {d} location", .{hand_index})) {
                continue;
            }

            const pose = hand_location.pose;

            if ((hand_location.locationFlags & c.XR_SPACE_LOCATION_POSITION_VALID_BIT) != 0) {
                hand.position = .{
                    .x = pose.position.x,
                    .y = pose.position.y,
                    .z = pose.position.z,
                };
            }

            if ((hand_location.locationFlags & c.XR_SPACE_LOCATION_ORIENTATION_VALID_BIT) != 0) {
                hand.orientation = .{
                    .x = pose.orientation.x,
                    .y = pose.orientation.y,
                    .z = pose.orientation.z,
                    .w = pose.orientation.w,
                };
            }
        }
    }
}

pub fn syncSingleActionSetOpenXR(state: *main.State, action_set: c.XrActionSet) void {
    const active_actionsets = [_]c.XrActiveActionSet{.{
        .actionSet = action_set,
        .subactionPath = c.XR_NULL_PATH,
    }};

    const actions_sync_info = c.XrActionsSyncInfo{
        .type = c.XR_TYPE_ACTIONS_SYNC_INFO,
        .next = null,
        .countActiveActionSets = active_actionsets.len,
        .activeActionSets = &active_actionsets,
    };

    const result = c.xrSyncActions(state.data.session, &actions_sync_info);
    _ = main.xrCheck(result, "Failed to sync actions", .{});
}

pub fn getActionFloatOpenXR(state: *main.State, action: c.XrAction, subaction_path: c.XrPath) f32 {
    const get_info = c.XrActionStateGetInfo{
        .type = c.XR_TYPE_ACTION_STATE_GET_INFO,
        .next = null,
        .action = action,
        .subactionPath = subaction_path,
    };

    var action_state: c.XrActionStateFloat = .{
        .type = c.XR_TYPE_ACTION_STATE_FLOAT,
        .next = null,
        .currentState = 0.0,
        .changedSinceLastSync = 0,
        .lastChangeTime = 0,
        .isActive = 0,
    };

    const result = c.xrGetActionStateFloat(state.data.session, &get_info, &action_state);
    if (!main.xrCheck(result, "Failed to get action float state", .{})) {
        return 0.0;
    }

    if (action_state.isActive == 0) {
        return 0.0;
    }

    return action_state.currentState;
}

pub fn getActionVector2OpenXR(state: *main.State, action: c.XrAction, subaction_path: c.XrPath) c.XrVector2f {
    const get_info = c.XrActionStateGetInfo{
        .type = c.XR_TYPE_ACTION_STATE_GET_INFO,
        .next = null,
        .action = action,
        .subactionPath = subaction_path,
    };

    var action_state: c.XrActionStateVector2f = .{
        .type = c.XR_TYPE_ACTION_STATE_VECTOR2F,
        .next = null,
        .currentState = .{ .x = 0.0, .y = 0.0 },
        .changedSinceLastSync = 0,
        .lastChangeTime = 0,
        .isActive = 0,
    };

    const result = c.xrGetActionStateVector2f(state.data.session, &get_info, &action_state);
    if (!main.xrCheck(result, "Failed to get action vector2 state", .{})) {
        return .{ .x = 0.0, .y = 0.0 };
    }

    if (action_state.isActive == 0) {
        return .{ .x = 0.0, .y = 0.0 };
    }

    return action_state.currentState;
}

pub fn getActionBooleanClickedOpenXR(state: *main.State, action: c.XrAction, subaction_path: c.XrPath) bool {
    const get_info = c.XrActionStateGetInfo{
        .type = c.XR_TYPE_ACTION_STATE_GET_INFO,
        .next = null,
        .action = action,
        .subactionPath = subaction_path,
    };

    var action_state: c.XrActionStateBoolean = .{
        .type = c.XR_TYPE_ACTION_STATE_BOOLEAN,
        .next = null,
        .currentState = 0,
        .changedSinceLastSync = 0,
        .lastChangeTime = 0,
        .isActive = 0,
    };

    const result = c.xrGetActionStateBoolean(state.data.session, &get_info, &action_state);
    if (!main.xrCheck(result, "Failed to get action boolean state", .{})) {
        return false;
    }

    if (action_state.isActive == 0) {
        return false;
    }

    // "Clicked" means the button is pressed AND has changed since last sync
    return action_state.currentState != 0 and action_state.changedSinceLastSync != 0;
}

fn quaternionEquals(a: c.Quaternion, b: c.Quaternion) bool {
    const epsilon = 0.0001;
    return @abs(a.x - b.x) < epsilon and
           @abs(a.y - b.y) < epsilon and
           @abs(a.z - b.z) < epsilon and
           @abs(a.w - b.w) < epsilon;
}
