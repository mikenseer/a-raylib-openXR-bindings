// Shared VR application logic for smooth locomotion and turning
// Platform-specific entry points call into this code

const rl = @import("rlOpenXR");
const c = rl.c;
const std = @import("std");

pub const XRInputBindings = struct {
    actionset: c.XrActionSet,
    hand_pose_action: c.XrAction,
    hand_sub_paths: [2]c.XrPath,
    hand_spaces: [2]c.XrSpace,
    hand_activate_action: c.XrAction,
    move_action: c.XrAction, // Left thumbstick for locomotion
    turn_action: c.XrAction, // Right thumbstick for turning
};

// Quaternion helper functions for locomotion
pub const QuatHelpers = struct {
    /// Create a quaternion representing rotation around Y axis by angle (in radians)
    pub fn fromYaw(yaw_radians: f32) c.XrQuaternionf {
        const half_angle = yaw_radians * 0.5;
        return .{
            .x = 0.0,
            .y = @sin(half_angle),
            .z = 0.0,
            .w = @cos(half_angle),
        };
    }

    /// Multiply two quaternions (returns q1 * q2)
    pub fn multiply(q1: c.XrQuaternionf, q2: c.XrQuaternionf) c.XrQuaternionf {
        return .{
            .x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
            .y = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
            .z = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w,
            .w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z,
        };
    }

    /// Rotate a Vector3 by a quaternion
    pub fn rotateVector(v: c.Vector3, q: c.XrQuaternionf) c.Vector3 {
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

pub fn setupInputBindings(bindings: *XRInputBindings) void {
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

    // Create move action (left thumbstick)
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

    // Create turn action (right thumbstick)
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

pub fn assignHandInputBindings(bindings: *XRInputBindings, left: *rl.HandData, right: *rl.HandData) void {
    const hands = [_]*rl.HandData{ left, right };

    for (hands, 0..) |hand, i| {
        hand.hand_pose_action = bindings.hand_pose_action;
        hand.hand_pose_subpath = bindings.hand_sub_paths[i];
        hand.hand_pose_space = bindings.hand_spaces[i];
    }
}

// Helper functions removed - now using rl.getActionVector2() from library

pub const VRApp = struct {
    has_vr: bool,
    camera: c.Camera3D,
    bindings: XRInputBindings,
    left_hand: rl.HandData,
    right_hand: rl.HandData,
    hand_model: c.Model,
    last_time: f64, // For calculating delta time on Android
    total_yaw: f32, // Accumulated yaw rotation in radians (for smooth turning)

    // Locomotion constants
    const turn_speed: f32 = 180.0; // Degrees per second
    const move_speed: f32 = 3.0; // Units per second

    pub fn init() !VRApp {
        const builtin = @import("builtin");
        const is_android = builtin.os.tag == .linux and builtin.abi == .android;

        // On desktop, create a debug window
        if (!is_android) {
            const screenWidth = 1200;
            const screenHeight = 900;
            c.InitWindow(screenWidth, screenHeight, "rlOpenXR-Zig - Smooth Locomotion");
            c.SetTargetFPS(-1);
        }

        // Define the camera
        const camera = c.Camera3D{
            .position = .{ .x = 0.0, .y = 1.6, .z = 5.0 },
            .target = .{ .x = 0.0, .y = 1.6, .z = 0.0 },
            .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
            .fovy = 45.0,
            .projection = c.CAMERA_PERSPECTIVE,
        };

        // Initialize OpenXR
        const initialized_openxr = rl.setup();

        // Resize window to match VR eye aspect ratio (desktop only)
        if (!is_android and initialized_openxr) {
            if (rl.getEyeResolution()) |res| {
                const aspect_ratio = @as(f32, @floatFromInt(res.width)) / @as(f32, @floatFromInt(res.height));
                const new_width: i32 = @intFromFloat(900.0 * aspect_ratio);
                c.SetWindowSize(new_width, 900);
            }
        }

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

        return VRApp{
            .has_vr = initialized_openxr,
            .camera = camera,
            .bindings = bindings,
            .left_hand = left_hand,
            .right_hand = right_hand,
            .hand_model = hand_model,
            .last_time = c.GetTime(),
            .total_yaw = 0.0,
        };
    }

    pub fn update(self: *VRApp) void {
        if (self.has_vr) {
            rl.update(); // Update OpenXR state
            rl.syncSingleActionSet(self.bindings.actionset); // Sync action set
            rl.updateHands(&self.left_hand, &self.right_hand); // Update hand tracking

            // Update camera from HMD FIRST to get fresh pose in original play space
            rl.updateCamera(&self.camera);

            // Process locomotion using fresh HMD pose
            self.processLocomotion();

            // Apply locomotion offset manually to camera
            self.applyLocomotionToCamera();
        }

        c.UpdateCamera(&self.camera, c.CAMERA_FREE); // Mouse control for debug
    }

    fn applyLocomotionToCamera(self: *VRApp) void {
        const offset = rl.getPlaySpaceOffset();

        // Transform camera position by offset
        const rotated_pos = QuatHelpers.rotateVector(self.camera.position, offset.orientation);
        self.camera.position = .{
            .x = rotated_pos.x + offset.position.x,
            .y = rotated_pos.y + offset.position.y,
            .z = rotated_pos.z + offset.position.z,
        };

        // Transform camera target by offset
        const rotated_target = QuatHelpers.rotateVector(self.camera.target, offset.orientation);
        self.camera.target = .{
            .x = rotated_target.x + offset.position.x,
            .y = rotated_target.y + offset.position.y,
            .z = rotated_target.z + offset.position.z,
        };

        // Transform camera up vector by offset (prevents tilting!)
        self.camera.up = QuatHelpers.rotateVector(self.camera.up, offset.orientation);
    }

    fn processLocomotion(self: *VRApp) void {
        const builtin_import = @import("builtin");

        // Calculate delta time - GetFrameTime() returns 0 on Android, so calculate manually
        var dt = c.GetFrameTime();
        if (dt == 0.0 or builtin_import.abi == .android) {
            const current_time = c.GetTime();
            dt = @floatCast(current_time - self.last_time);
            self.last_time = current_time;
        }

        // Get current play space offset
        var offset = rl.getPlaySpaceOffset();

        // Left thumbstick for smooth locomotion
        const move_input = rl.getActionVector2(self.bindings.move_action, self.bindings.hand_sub_paths[0]);

        if (@abs(move_input.x) > 0.1 or @abs(move_input.y) > 0.1) {
            // Get HMD forward direction in play space (flatten to XZ plane)
            const hmd_forward_playspace = c.Vector3Subtract(self.camera.target, self.camera.position);
            const hmd_forward_flat = c.Vector3{
                .x = hmd_forward_playspace.x,
                .y = 0,
                .z = hmd_forward_playspace.z,
            };
            const hmd_forward_norm = c.Vector3Normalize(hmd_forward_flat);

            // Get HMD right direction
            const hmd_right_norm = c.Vector3{
                .x = -hmd_forward_norm.z,
                .y = 0,
                .z = hmd_forward_norm.x,
            };

            // Transform to world space using play space orientation
            const forward_world = QuatHelpers.rotateVector(hmd_forward_norm, offset.orientation);
            const right_world = QuatHelpers.rotateVector(hmd_right_norm, offset.orientation);

            // Calculate movement delta
            // Note: Positive Y = forward, Positive X = right
            const move_forward = c.Vector3Scale(forward_world, move_input.y * move_speed * dt);
            const move_right = c.Vector3Scale(right_world, move_input.x * move_speed * dt);

            // Update position offset
            offset.position.x += move_forward.x + move_right.x;
            offset.position.z += move_forward.z + move_right.z;

            // Update OpenXR reference space
            rl.updatePlaySpaceOffset(offset) catch {};
        }

        // Right thumbstick for smooth turning
        const turn_input = rl.getActionVector2(self.bindings.turn_action, self.bindings.hand_sub_paths[1]);

        if (@abs(turn_input.x) > 0.1) {
            // Calculate yaw delta and accumulate total yaw (negate for correct direction)
            const delta_yaw_deg = -turn_input.x * turn_speed * dt;
            const delta_yaw_rad = delta_yaw_deg * c.DEG2RAD;
            self.total_yaw += delta_yaw_rad;

            // Create quaternion from total yaw (always around world Y axis)
            offset.orientation = QuatHelpers.fromYaw(self.total_yaw);

            rl.updatePlaySpaceOffset(offset) catch {};
        }
    }

    pub fn render(self: *VRApp) void {
        const builtin = @import("builtin");
        const is_android = builtin.os.tag == .linux and builtin.abi == .android;

        // Try to render to VR
        const rendering_vr = if (self.has_vr)
            rl.begin() or rl.beginMockHMD()
        else
            false;

        if (rendering_vr) {
            c.ClearBackground(c.SKYBLUE);

            c.BeginMode3D(self.camera);

            // Draw world - grid of cubes
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

            c.DrawGrid(20, 1.0);

            // Draw hands (transform by locomotion offset so they move with player)
            const offset = rl.getPlaySpaceOffset();

            if (self.left_hand.valid) {
                // Transform hand position by offset
                const rotated_pos = QuatHelpers.rotateVector(self.left_hand.position, offset.orientation);
                const transformed_pos = c.Vector3{
                    .x = rotated_pos.x + offset.position.x,
                    .y = rotated_pos.y + offset.position.y,
                    .z = rotated_pos.z + offset.position.z,
                };

                // Transform hand orientation by offset
                const offset_quat_raylib = c.Quaternion{
                    .x = offset.orientation.x,
                    .y = offset.orientation.y,
                    .z = offset.orientation.z,
                    .w = offset.orientation.w,
                };
                const transformed_orientation = c.QuaternionMultiply(offset_quat_raylib, self.left_hand.orientation);

                var axis: c.Vector3 = undefined;
                var angle: f32 = undefined;
                c.QuaternionToAxisAngle(transformed_orientation, &axis, &angle);

                const left_value = rl.getActionFloat(self.bindings.hand_activate_action, self.bindings.hand_sub_paths[0]);
                const left_color = if (left_value > 0.75) c.GREEN else c.ORANGE;

                c.DrawModelEx(self.hand_model, transformed_pos, axis, angle * c.RAD2DEG, c.Vector3One(), left_color);
            }

            if (self.right_hand.valid) {
                // Transform hand position by offset
                const rotated_pos = QuatHelpers.rotateVector(self.right_hand.position, offset.orientation);
                const transformed_pos = c.Vector3{
                    .x = rotated_pos.x + offset.position.x,
                    .y = rotated_pos.y + offset.position.y,
                    .z = rotated_pos.z + offset.position.z,
                };

                // Transform hand orientation by offset
                const offset_quat_raylib = c.Quaternion{
                    .x = offset.orientation.x,
                    .y = offset.orientation.y,
                    .z = offset.orientation.z,
                    .w = offset.orientation.w,
                };
                const transformed_orientation = c.QuaternionMultiply(offset_quat_raylib, self.right_hand.orientation);

                var axis: c.Vector3 = undefined;
                var angle: f32 = undefined;
                c.QuaternionToAxisAngle(transformed_orientation, &axis, &angle);

                const right_value = rl.getActionFloat(self.bindings.hand_activate_action, self.bindings.hand_sub_paths[1]);
                const right_color = if (right_value > 0.75) c.GREEN else c.YELLOW;

                c.DrawModelEx(self.hand_model, transformed_pos, axis, angle * c.RAD2DEG, c.Vector3One(), right_color);
            }

            c.EndMode3D();
        } else if (!is_android) {
            // Fallback non-VR rendering (desktop only)
            c.BeginMode3D(self.camera);

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

        if (self.has_vr) {
            rl.end();
        }

        // Draw UI overlay to desktop window only
        if (!is_android) {
            c.BeginDrawing();
            c.ClearBackground(c.RAYWHITE);

            if (self.has_vr and rendering_vr) {
                rl.blitToWindow(.both, true);
            }

            c.DrawFPS(10, 10);
            c.DrawText("Controls:", 10, 35, 20, c.BLACK);
            c.DrawText("  Left Thumbstick = Move", 10, 60, 20, c.BLACK);
            c.DrawText("  Right Thumbstick = Smooth Turn", 10, 85, 20, c.BLACK);

            if (self.has_vr) {
                c.DrawText("OpenXR Active", 10, 120, 20, c.GREEN);
            } else {
                c.DrawText("OpenXR Not Available", 10, 120, 20, c.ORANGE);
            }

            c.EndDrawing();
        }
    }

    pub fn shouldClose(self: *const VRApp) bool {
        const builtin = @import("builtin");
        const is_android = builtin.os.tag == .linux and builtin.abi == .android;

        _ = self;

        if (is_android) {
            return false;
        }

        return c.WindowShouldClose();
    }

    pub fn deinit(self: *VRApp) void {
        const builtin = @import("builtin");
        const is_android = builtin.os.tag == .linux and builtin.abi == .android;

        c.UnloadModel(self.hand_model);

        if (self.has_vr) {
            rl.shutdown();
        }

        if (!is_android) {
            c.CloseWindow();
        }
    }
};
