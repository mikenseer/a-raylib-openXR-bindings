// Shared VR application logic for hand tracking visualization
// Platform-specific entry points call into this code

const rl = @import("rlOpenXR");
const c = rl.c;
const std = @import("std");

pub const XRInputBindings = struct {
    actionset: c.XrActionSet,
    hand_pose_action: c.XrAction,
    hand_sub_paths: [2]c.XrPath,
    hand_spaces: [2]c.XrSpace,
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

    const actionset_name = "rlopenxr_hello_hands_actionset";
    const localized_name = "OpenXR Hello Hands ActionSet";
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

    // Suggest bindings for khr/simple_controller
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

    // Suggest bindings for oculus/touch_controller
    {
        var interaction_profile_path: c.XrPath = undefined;
        result = c.xrStringToPath(xr.instance, "/interaction_profiles/oculus/touch_controller", &interaction_profile_path);
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

pub const VRApp = struct {
    has_vr: bool,
    camera: c.Camera3D,
    bindings: XRInputBindings,
    left_hand: rl.HandData,
    right_hand: rl.HandData,
    hand_model: c.Model,

    pub fn init() !VRApp {
        const builtin = @import("builtin");
        const is_android = builtin.os.tag == .linux and builtin.abi == .android;

        // On desktop, create a debug window
        if (!is_android) {
            const screenWidth = 1200;
            const screenHeight = 900;
            c.InitWindow(screenWidth, screenHeight, "rlOpenXR-Zig - Hello Hands");
            c.SetTargetFPS(-1);
        }

        // Define the camera
        const camera = c.Camera3D{
            .position = .{ .x = 10.0, .y = 10.0, .z = 10.0 },
            .target = .{ .x = 0.0, .y = 3.0, .z = 0.0 },
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
        };
    }

    pub fn update(self: *VRApp) void {
        if (self.has_vr) {
            rl.update(); // Update OpenXR state
            rl.syncSingleActionSet(self.bindings.actionset); // Sync action set
            rl.updateHands(&self.left_hand, &self.right_hand); // Update hand tracking
            rl.updateCamera(&self.camera); // Update camera from HMD
        }

        c.UpdateCamera(&self.camera, c.CAMERA_FREE); // Mouse control for debug
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
            c.ClearBackground(c.BLUE);

            c.BeginMode3D(self.camera);

            // Draw hands
            if (self.left_hand.valid) {
                var axis: c.Vector3 = undefined;
                var angle: f32 = undefined;
                c.QuaternionToAxisAngle(self.left_hand.orientation, &axis, &angle);
                c.DrawModelEx(self.hand_model, self.left_hand.position, axis, angle * c.RAD2DEG, c.Vector3One(), c.ORANGE);
            }

            if (self.right_hand.valid) {
                var axis: c.Vector3 = undefined;
                var angle: f32 = undefined;
                c.QuaternionToAxisAngle(self.right_hand.orientation, &axis, &angle);
                c.DrawModelEx(self.hand_model, self.right_hand.position, axis, angle * c.RAD2DEG, c.Vector3One(), c.PINK);
            }

            // Draw scene - cube at y=1 so it's above the grid
            c.DrawCube(.{ .x = -3, .y = 1, .z = 0 }, 2.0, 2.0, 2.0, c.RED);
            c.DrawGrid(10, 1.0);

            c.EndMode3D();
        } else if (!is_android) {
            // Fallback non-VR rendering (desktop only)
            c.BeginMode3D(self.camera);

            c.DrawCube(.{ .x = -3, .y = 1, .z = 0 }, 2.0, 2.0, 2.0, c.RED);
            c.DrawGrid(10, 1.0);

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
                rl.blitToWindow(.left, false);
            }

            c.DrawFPS(10, 10);

            if (self.has_vr) {
                c.DrawText("OpenXR Active", 10, 40, 20, c.GREEN);

                // Show hand tracking status
                if (self.left_hand.valid) {
                    c.DrawText("Left Hand: Tracked", 10, 70, 20, c.ORANGE);
                } else {
                    c.DrawText("Left Hand: Not tracked", 10, 70, 20, c.GRAY);
                }

                if (self.right_hand.valid) {
                    c.DrawText("Right Hand: Tracked", 10, 100, 20, c.PINK);
                } else {
                    c.DrawText("Right Hand: Not tracked", 10, 100, 20, c.GRAY);
                }
            } else {
                c.DrawText("OpenXR Not Available - Running in fallback mode", 10, 40, 20, c.ORANGE);
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
