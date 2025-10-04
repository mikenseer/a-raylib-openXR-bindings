// Hand tracking and input implementation
// Ported from rlOpenXR.cpp (FireFlyForLife)

const std = @import("std");
const main = @import("rlOpenXR.zig");
const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("openxr/openxr.h");
});

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

fn quaternionEquals(a: c.Quaternion, b: c.Quaternion) bool {
    const epsilon = 0.0001;
    return @abs(a.x - b.x) < epsilon and
           @abs(a.y - b.y) < epsilon and
           @abs(a.z - b.z) < epsilon and
           @abs(a.w - b.w) < epsilon;
}
