// Example: Smooth locomotion and turning for VR
//
// This demonstrates head-relative movement and smooth turning using OpenXR reference spaces.
// The locomotion system can be easily integrated into existing 3D projects:
// 1. Copy the QuatHelpers struct for quaternion math
// 2. Use rl.getPlaySpaceOffset() / rl.updatePlaySpaceOffset() for movement/turning
// 3. Draw your existing 3D world at world coordinates - OpenXR handles the transform
//
// Controls:
// - Left thumbstick: Move in the direction you're looking
// - Right thumbstick: Smooth turn left/right (180°/sec)
// - Triggers: Change hand color (demonstration of input)

const rl = @import("rlOpenXR");
const c = rl.c; // Use the library's C imports to avoid type mismatches
const std = @import("std");

const XRInputBindings = struct {
    actionset: c.XrActionSet,
    hand_pose_action: c.XrAction,
    hand_sub_paths: [2]c.XrPath,
    hand_spaces: [2]c.XrSpace,
    hand_activate_action: c.XrAction,
    move_action: c.XrAction, // Left thumbstick for locomotion
    turn_action: c.XrAction, // Right thumbstick for turning
};

// Quaternion helper functions for locomotion
const QuatHelpers = struct {
    /// Create a quaternion representing rotation around Y axis by angle (in radians)
    fn fromYaw(yaw_radians: f32) c.XrQuaternionf {
        const half_angle = yaw_radians * 0.5;
        return .{
            .x = 0.0,
            .y = @sin(half_angle),
            .z = 0.0,
            .w = @cos(half_angle),
        };
    }

    /// Multiply two quaternions (returns q1 * q2)
    fn multiply(q1: c.XrQuaternionf, q2: c.XrQuaternionf) c.XrQuaternionf {
        return .{
            .x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
            .y = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
            .z = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w,
            .w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z,
        };
    }

    /// Rotate a Vector3 by a quaternion
    fn rotateVector(v: c.Vector3, q: c.XrQuaternionf) c.Vector3 {
        // Convert Vector3 to quaternion with w=0
        const v_quat = c.XrQuaternionf{ .x = v.x, .y = v.y, .z = v.z, .w = 0.0 };

        // Calculate conjugate of q
        const q_conj = c.XrQuaternionf{ .x = -q.x, .y = -q.y, .z = -q.z, .w = q.w };

        // Rotate: result = q * v * q_conj
        const temp = multiply(q, v_quat);
        const result = multiply(temp, q_conj);

        return .{ .x = result.x, .y = result.y, .z = result.z };
    }
};

fn setupInputBindings(bindings: *XRInputBindings) void {
    const xr = rl.getData() orelse return;

    var result = c.xrStringToPath(xr.instance, "/user/hand/left", &bindings.hand_sub_paths[0]);
    if (!rl.xrCheck(result, "Could not convert Left hand string to path", .{})) return;

    result = c.xrStringToPath(xr.instance, "/user/hand/right", &bindings.hand_sub_paths[1]);
    if (!rl.xrCheck(result, "Could not convert Right hand string to path", .{})) return;

    var actionset_info = c.XrActionSetCreateInfo{
        .type = c.XR_TYPE_ACTION_SET_CREATE_INFO,
        .next = null,
        .actionSetName = undefined,
        .localizedActionSetName = undefined,
        .priority = 0,
    };

    const actionset_name = "rlopenxr_smooth_turning_actionset";
    const localized_name = "OpenXR Smooth Turning ActionSet";
    @memcpy(actionset_info.actionSetName[0..actionset_name.len], actionset_name);
    actionset_info.actionSetName[actionset_name.len] = 0;
    @memcpy(actionset_info.localizedActionSetName[0..localized_name.len], localized_name);
    actionset_info.localizedActionSetName[localized_name.len] = 0;

    result = c.xrCreateActionSet(xr.instance, &actionset_info, &bindings.actionset);
    if (!rl.xrCheck(result, "Failed to create actionset", .{})) return;

    // Create hand pose action
    {
        var action_info = c.XrActionCreateInfo{
            .type = c.XR_TYPE_ACTION_CREATE_INFO,
            .next = null,
            .actionName = undefined,
            .actionType = c.XR_ACTION_TYPE_POSE_INPUT,
            .countSubactionPaths = 2,
            .subactionPaths = &bindings.hand_sub_paths,
            .localizedActionName = undefined,
        };

        const action_name = "handpose";
        const localized_action_name = "Hand Pose";
        @memcpy(action_info.actionName[0..action_name.len], action_name);
        action_info.actionName[action_name.len] = 0;
        @memcpy(action_info.localizedActionName[0..localized_action_name.len], localized_action_name);
        action_info.localizedActionName[localized_action_name.len] = 0;

        result = c.xrCreateAction(bindings.actionset, &action_info, &bindings.hand_pose_action);
        _ = rl.xrCheck(result, "Failed to create hand pose action", .{});
    }

    // Create hand activate action (trigger)
    {
        var action_info = c.XrActionCreateInfo{
            .type = c.XR_TYPE_ACTION_CREATE_INFO,
            .next = null,
            .actionName = undefined,
            .actionType = c.XR_ACTION_TYPE_FLOAT_INPUT,
            .countSubactionPaths = 2,
            .subactionPaths = &bindings.hand_sub_paths,
            .localizedActionName = undefined,
        };

        const action_name = "activate";
        const localized_action_name = "Activate";
        @memcpy(action_info.actionName[0..action_name.len], action_name);
        action_info.actionName[action_name.len] = 0;
        @memcpy(action_info.localizedActionName[0..localized_action_name.len], localized_action_name);
        action_info.localizedActionName[localized_action_name.len] = 0;

        result = c.xrCreateAction(bindings.actionset, &action_info, &bindings.hand_activate_action);
        _ = rl.xrCheck(result, "Failed to create hand activate action", .{});
    }

    // Create move action (left thumbstick) - using subaction for left hand only
    {
        var action_info = c.XrActionCreateInfo{
            .type = c.XR_TYPE_ACTION_CREATE_INFO,
            .next = null,
            .actionName = undefined,
            .actionType = c.XR_ACTION_TYPE_VECTOR2F_INPUT,
            .countSubactionPaths = 1,
            .subactionPaths = &bindings.hand_sub_paths[0], // Left hand only
            .localizedActionName = undefined,
        };

        const action_name = "move";
        const localized_action_name = "Move";
        @memcpy(action_info.actionName[0..action_name.len], action_name);
        action_info.actionName[action_name.len] = 0;
        @memcpy(action_info.localizedActionName[0..localized_action_name.len], localized_action_name);
        action_info.localizedActionName[localized_action_name.len] = 0;

        result = c.xrCreateAction(bindings.actionset, &action_info, &bindings.move_action);
        _ = rl.xrCheck(result, "Failed to create move action", .{});
    }

    // Create turn action (right thumbstick) - using subaction for right hand only
    {
        var action_info = c.XrActionCreateInfo{
            .type = c.XR_TYPE_ACTION_CREATE_INFO,
            .next = null,
            .actionName = undefined,
            .actionType = c.XR_ACTION_TYPE_VECTOR2F_INPUT,
            .countSubactionPaths = 1,
            .subactionPaths = &bindings.hand_sub_paths[1], // Right hand only
            .localizedActionName = undefined,
        };

        const action_name = "turn";
        const localized_action_name = "Turn";
        @memcpy(action_info.actionName[0..action_name.len], action_name);
        action_info.actionName[action_name.len] = 0;
        @memcpy(action_info.localizedActionName[0..localized_action_name.len], localized_action_name);
        action_info.localizedActionName[localized_action_name.len] = 0;

        result = c.xrCreateAction(bindings.actionset, &action_info, &bindings.turn_action);
        _ = rl.xrCheck(result, "Failed to create turn action", .{});
    }

    // Create action spaces for poses
    for (0..2) |hand| {
        const identity_pose = c.XrPosef{
            .orientation = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
            .position = .{ .x = 0, .y = 0, .z = 0 },
        };

        var action_space_info = c.XrActionSpaceCreateInfo{
            .type = c.XR_TYPE_ACTION_SPACE_CREATE_INFO,
            .next = null,
            .action = bindings.hand_pose_action,
            .subactionPath = bindings.hand_sub_paths[hand],
            .poseInActionSpace = identity_pose,
        };

        result = c.xrCreateActionSpace(xr.session, &action_space_info, &bindings.hand_spaces[hand]);
        _ = rl.xrCheck(result, "Failed to create hand {d} pose space", .{hand});
    }

    // Setup grip pose paths
    var grip_pose_paths: [2]c.XrPath = undefined;
    _ = c.xrStringToPath(xr.instance, "/user/hand/left/input/grip/pose", &grip_pose_paths[0]);
    _ = c.xrStringToPath(xr.instance, "/user/hand/right/input/grip/pose", &grip_pose_paths[1]);

    var activate_paths: [2]c.XrPath = undefined;
    _ = c.xrStringToPath(xr.instance, "/user/hand/left/input/trigger/value", &activate_paths[0]);
    _ = c.xrStringToPath(xr.instance, "/user/hand/right/input/trigger/value", &activate_paths[1]);

    // Setup thumbstick paths
    var left_thumbstick_path: c.XrPath = undefined;
    var right_thumbstick_path: c.XrPath = undefined;
    _ = c.xrStringToPath(xr.instance, "/user/hand/left/input/thumbstick", &left_thumbstick_path);
    _ = c.xrStringToPath(xr.instance, "/user/hand/right/input/thumbstick", &right_thumbstick_path);

    // Suggest bindings for khr/simple_controller (no thumbsticks)
    {
        var interaction_profile_path: c.XrPath = undefined;
        result = c.xrStringToPath(xr.instance, "/interaction_profiles/khr/simple_controller", &interaction_profile_path);
        _ = rl.xrCheck(result, "Failed to get interaction profile", .{});

        const action_suggested_bindings = [_]c.XrActionSuggestedBinding{
            .{ .action = bindings.hand_pose_action, .binding = grip_pose_paths[0] },
            .{ .action = bindings.hand_pose_action, .binding = grip_pose_paths[1] },
        };

        var suggested_bindings = c.XrInteractionProfileSuggestedBinding{
            .type = c.XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING,
            .next = null,
            .interactionProfile = interaction_profile_path,
            .countSuggestedBindings = action_suggested_bindings.len,
            .suggestedBindings = &action_suggested_bindings,
        };

        result = c.xrSuggestInteractionProfileBindings(xr.instance, &suggested_bindings);
        _ = rl.xrCheck(result, "Failed to suggest bindings for khr/simple_controller", .{});
    }

    // Suggest bindings for oculus/touch_controller (with thumbsticks)
    {
        var interaction_profile_path: c.XrPath = undefined;
        result = c.xrStringToPath(xr.instance, "/interaction_profiles/oculus/touch_controller", &interaction_profile_path);
        _ = rl.xrCheck(result, "Failed to get interaction profile", .{});

        const action_suggested_bindings = [_]c.XrActionSuggestedBinding{
            .{ .action = bindings.hand_pose_action, .binding = grip_pose_paths[0] },
            .{ .action = bindings.hand_pose_action, .binding = grip_pose_paths[1] },
            .{ .action = bindings.hand_activate_action, .binding = activate_paths[0] },
            .{ .action = bindings.hand_activate_action, .binding = activate_paths[1] },
            .{ .action = bindings.move_action, .binding = left_thumbstick_path },
            .{ .action = bindings.turn_action, .binding = right_thumbstick_path },
        };

        var suggested_bindings = c.XrInteractionProfileSuggestedBinding{
            .type = c.XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING,
            .next = null,
            .interactionProfile = interaction_profile_path,
            .countSuggestedBindings = action_suggested_bindings.len,
            .suggestedBindings = &action_suggested_bindings,
        };

        result = c.xrSuggestInteractionProfileBindings(xr.instance, &suggested_bindings);
        _ = rl.xrCheck(result, "Failed to suggest bindings for oculus/touch_controller", .{});
    }

    // Attach action sets
    var actionset_attach_info = c.XrSessionActionSetsAttachInfo{
        .type = c.XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO,
        .next = null,
        .countActionSets = 1,
        .actionSets = &bindings.actionset,
    };

    result = c.xrAttachSessionActionSets(xr.session, &actionset_attach_info);
    _ = rl.xrCheck(result, "Failed to attach action set", .{});
}

fn assignHandInputBindings(bindings: *XRInputBindings, left: *rl.HandData, right: *rl.HandData) void {
    const hands = [_]*rl.HandData{ left, right };

    for (hands, 0..) |hand, i| {
        hand.hand_pose_action = bindings.hand_pose_action;
        hand.hand_pose_subpath = bindings.hand_sub_paths[i];
        hand.hand_pose_space = bindings.hand_spaces[i];
    }
}

// Helper to get Vector2 action state
fn getActionVector2(session: c.XrSession, action: c.XrAction, subaction_path: c.XrPath) c.XrVector2f {
    const get_info = c.XrActionStateGetInfo{
        .type = c.XR_TYPE_ACTION_STATE_GET_INFO,
        .next = null,
        .action = action,
        .subactionPath = subaction_path,
    };

    var action_state: c.XrActionStateVector2f = .{
        .type = c.XR_TYPE_ACTION_STATE_VECTOR2F,
        .next = null,
        .currentState = .{ .x = 0, .y = 0 },
        .changedSinceLastSync = 0,
        .lastChangeTime = 0,
        .isActive = 0,
    };

    const result = c.xrGetActionStateVector2f(session, &get_info, &action_state);
    if (result < 0 or action_state.isActive == 0) {
        return .{ .x = 0, .y = 0 };
    }

    return action_state.currentState;
}

pub fn main() !void {
    // Initialization
    const screenWidth = 1200;
    const screenHeight = 900;

    c.InitWindow(screenWidth, screenHeight, "rlOpenXR-Zig - Smooth Locomotion & Turning");
    defer c.CloseWindow();

    // Initialize OpenXR
    const initialized_openxr = rl.setup();
    if (!initialized_openxr) {
        std.debug.print("Failed to initialize rlOpenXR! Will run in non-VR mode.\n", .{});
    }
    defer if (initialized_openxr) rl.shutdown();

    // Define the camera
    var camera = c.Camera3D{
        .position = .{ .x = 0.0, .y = 1.6, .z = 5.0 },
        .target = .{ .x = 0.0, .y = 1.6, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = c.CAMERA_PERSPECTIVE,
    };

    // Setup input bindings
    var bindings = std.mem.zeroes(XRInputBindings);
    if (initialized_openxr) {
        setupInputBindings(&bindings);
    }

    // Hand tracking data
    var left_hand = rl.HandData{
        .valid = false,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .orientation = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        .handedness = .left,
        .hand_pose_action = null,
        .hand_pose_subpath = 0,
        .hand_pose_space = null,
    };

    var right_hand = rl.HandData{
        .valid = false,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .orientation = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        .handedness = .right,
        .hand_pose_action = null,
        .hand_pose_subpath = 0,
        .hand_pose_space = null,
    };

    if (initialized_openxr) {
        assignHandInputBindings(&bindings, &left_hand, &right_hand);
    }

    // Hand model
    const hand_mesh = c.GenMeshCube(0.2, 0.2, 0.2);
    const hand_model = c.LoadModelFromMesh(hand_mesh);
    defer c.UnloadModel(hand_model);

    // OpenXR is responsible for frame timing, disable raylib VSync
    c.SetTargetFPS(-1);

    // Resize window to match VR eye aspect ratio
    if (initialized_openxr) {
        if (rl.getEyeResolution()) |res| {
            const aspect_ratio = @as(f32, @floatFromInt(res.width)) / @as(f32, @floatFromInt(res.height));
            const new_width: i32 = @intFromFloat(900.0 * aspect_ratio);
            c.SetWindowSize(new_width, 900);
        }
    }

    // Locomotion constants
    const turn_speed: f32 = 180.0; // Degrees per second for smooth turning
    const move_speed: f32 = 3.0; // Units per second

    // Main game loop
    while (!c.WindowShouldClose()) {
        const dt = c.GetFrameTime();
        const xr_data = rl.getData();

        // Update
        if (initialized_openxr) {
            rl.update(); // Update OpenXR state (must be called first)
            rl.syncSingleActionSet(bindings.actionset); // Sync action set
            rl.updateHands(&left_hand, &right_hand); // Update hand tracking
            rl.updateCamera(&camera); // Update camera from HMD

            // Get thumbstick input for locomotion
            if (xr_data) |xr| {
                // Get current play space offset
                var offset = rl.getPlaySpaceOffset();

                // Left thumbstick for smooth locomotion (relative to HMD facing direction)
                const move_input = getActionVector2(xr.session, bindings.move_action, bindings.hand_sub_paths[0]);

                if (@abs(move_input.x) > 0.1 or @abs(move_input.y) > 0.1) {
                    // Get HMD forward direction in play space (flatten to XZ plane)
                    const hmd_forward_playspace = c.Vector3Subtract(camera.target, camera.position);
                    const hmd_forward_flat = c.Vector3{
                        .x = hmd_forward_playspace.x,
                        .y = 0,
                        .z = hmd_forward_playspace.z
                    };
                    const hmd_forward_norm = c.Vector3Normalize(hmd_forward_flat);

                    // Get HMD right direction (perpendicular to forward on XZ plane)
                    const hmd_right_norm = c.Vector3{
                        .x = -hmd_forward_norm.z,
                        .y = 0,
                        .z = hmd_forward_norm.x
                    };

                    // Transform to world space using play space orientation
                    const forward_world = QuatHelpers.rotateVector(hmd_forward_norm, offset.orientation);
                    const right_world = QuatHelpers.rotateVector(hmd_right_norm, offset.orientation);

                    // Calculate movement delta (negate Y for correct forward/backward)
                    const move_forward = c.Vector3Scale(forward_world, -move_input.y * move_speed * dt);
                    const move_right = c.Vector3Scale(right_world, -move_input.x * move_speed * dt);

                    // Update position offset
                    offset.position.x += move_forward.x + move_right.x;
                    offset.position.z += move_forward.z + move_right.z;

                    // Update OpenXR reference space
                    rl.updatePlaySpaceOffset(offset) catch |err| {
                        std.debug.print("Failed to update play space offset: {}\n", .{err});
                    };
                }

                // Right thumbstick for smooth turning (head-centric rotation)
                const turn_input = getActionVector2(xr.session, bindings.turn_action, bindings.hand_sub_paths[1]);

                if (@abs(turn_input.x) > 0.1) {
                    // Calculate yaw delta
                    const delta_yaw_deg = turn_input.x * turn_speed * dt;
                    const delta_yaw_rad = delta_yaw_deg * c.DEG2RAD;

                    // Get current HMD position in world space (this is our pivot point)
                    const hmd_playspace = camera.position;
                    const hmd_world = QuatHelpers.rotateVector(hmd_playspace, offset.orientation);
                    const pivot_world = c.Vector3{
                        .x = offset.position.x + hmd_world.x,
                        .y = offset.position.y + hmd_world.y,
                        .z = offset.position.z + hmd_world.z,
                    };

                    // Create delta rotation quaternion and compose with current
                    const delta_quat = QuatHelpers.fromYaw(delta_yaw_rad);
                    const new_orientation = QuatHelpers.multiply(delta_quat, offset.orientation);

                    // Calculate new position offset to keep pivot stationary
                    // pivot_world = new_position + rotate(hmd_playspace, new_orientation)
                    // new_position = pivot_world - rotate(hmd_playspace, new_orientation)
                    const rotated_hmd = QuatHelpers.rotateVector(hmd_playspace, new_orientation);
                    const new_position = c.XrVector3f{
                        .x = pivot_world.x - rotated_hmd.x,
                        .y = pivot_world.y - rotated_hmd.y,
                        .z = pivot_world.z - rotated_hmd.z,
                    };

                    // Update offset and apply to OpenXR
                    offset.orientation = new_orientation;
                    offset.position = new_position;

                    rl.updatePlaySpaceOffset(offset) catch |err| {
                        std.debug.print("Failed to update play space offset: {}\n", .{err});
                    };
                }
            }
        }

        c.UpdateCamera(&camera, c.CAMERA_FREE); // Mouse control for debug

        // Draw
        c.ClearBackground(c.RAYWHITE); // Clear window if OpenXR skips frame

        // Try to render to VR, fall back to mock HMD if VR unavailable
        const rendering_vr = if (initialized_openxr)
            rl.begin() or rl.beginMockHMD()
        else
            false;

        if (rendering_vr) {
            c.ClearBackground(c.SKYBLUE);

            c.BeginMode3D(camera);

            // Draw world objects at world coordinates (OpenXR handles the transform)
            // Grid of cubes in world space
            for (0..5) |x| {
                for (0..5) |z| {
                    const fx: f32 = @floatFromInt(x);
                    const fz: f32 = @floatFromInt(z);
                    const world_pos = c.Vector3{
                        .x = (fx - 2.0) * 3.0,
                        .y = 1.0,
                        .z = (fz - 2.0) * 3.0,
                    };

                    const color = if ((x + z) % 2 == 0) c.RED else c.BLUE;
                    c.DrawCube(world_pos, 1.0, 2.0, 1.0, color);
                    c.DrawCubeWires(world_pos, 1.0, 2.0, 1.0, c.BLACK);
                }
            }

            // Ground grid (drawn at world origin)
            c.DrawGrid(20, 1.0);

            // Draw hands (already in play space coordinates from OpenXR)
            if (left_hand.valid) {
                var axis: c.Vector3 = undefined;
                var angle: f32 = undefined;
                c.QuaternionToAxisAngle(left_hand.orientation, &axis, &angle);

                const left_value = rl.getActionFloat(bindings.hand_activate_action, bindings.hand_sub_paths[0]);
                const left_color = if (left_value > 0.75) c.GREEN else c.ORANGE;

                c.DrawModelEx(hand_model, left_hand.position, axis, angle * c.RAD2DEG, c.Vector3One(), left_color);
            }

            if (right_hand.valid) {
                var axis: c.Vector3 = undefined;
                var angle: f32 = undefined;
                c.QuaternionToAxisAngle(right_hand.orientation, &axis, &angle);

                const right_value = rl.getActionFloat(bindings.hand_activate_action, bindings.hand_sub_paths[1]);
                const right_color = if (right_value > 0.75) c.GREEN else c.YELLOW;

                c.DrawModelEx(hand_model, right_hand.position, axis, angle * c.RAD2DEG, c.Vector3One(), right_color);
            }

            c.EndMode3D();
        } else {
            // Fallback non-VR rendering
            c.BeginMode3D(camera);

            // Origin marker (useful for testing without VR)
            c.DrawCube(c.Vector3{ .x = 0.0, .y = 0.5, .z = 0.0 }, 0.5, 1.0, 0.5, c.GOLD);

            // Cube grid
            for (0..5) |x| {
                for (0..5) |z| {
                    const fx: f32 = @floatFromInt(x);
                    const fz: f32 = @floatFromInt(z);
                    const world_pos = c.Vector3{
                        .x = (fx - 2.0) * 3.0,
                        .y = 1.0,
                        .z = (fz - 2.0) * 3.0,
                    };

                    const color = if ((x + z) % 2 == 0) c.RED else c.BLUE;
                    c.DrawCube(world_pos, 1.0, 2.0, 1.0, color);
                }
            }

            c.DrawGrid(20, 1.0);
            c.EndMode3D();
        }

        if (initialized_openxr) {
            rl.end();
        }

        // Draw UI overlay
        c.BeginDrawing();

        // Blit VR view to window INSIDE BeginDrawing
        if (initialized_openxr and rendering_vr) {
            const keep_aspect_ratio = true;
            rl.blitToWindow(.both, keep_aspect_ratio);
        }

        c.DrawFPS(10, 10);
        c.DrawText("Controls:", 10, 35, 20, c.BLACK);
        c.DrawText("  Left Thumbstick = Move (smooth locomotion)", 10, 60, 20, c.BLACK);
        c.DrawText("  Right Thumbstick = Smooth Turn", 10, 85, 20, c.BLACK);
        c.DrawText("  Triggers = Change hand color", 10, 110, 20, c.BLACK);

        if (initialized_openxr) {
            c.DrawText("OpenXR Active", 10, 145, 20, c.GREEN);

            // Get current offset for display
            const offset = rl.getPlaySpaceOffset();

            // Calculate yaw from quaternion for display
            const yaw_rad = 2.0 * std.math.asin(offset.orientation.y);
            const yaw_deg = yaw_rad * c.RAD2DEG;

            const yaw_text = c.TextFormat("Play Space Yaw: %.1f degrees", yaw_deg);
            c.DrawText(yaw_text, 10, 170, 20, c.DARKGREEN);
            const pos_text = c.TextFormat("Play Space Pos: (%.2f, %.2f, %.2f)", offset.position.x, offset.position.y, offset.position.z);
            c.DrawText(pos_text, 10, 195, 20, c.DARKGREEN);
        } else {
            c.DrawText("OpenXR Not Available - Running in fallback mode", 10, 145, 20, c.ORANGE);
        }

        c.EndDrawing();
    }
}
