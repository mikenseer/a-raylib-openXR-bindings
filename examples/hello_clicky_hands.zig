const rl = @import("rlOpenXR");
const c = rl.c; // Use the library's C imports to avoid type mismatches
const std = @import("std");

const XRInputBindings = struct {
    actionset: c.XrActionSet,
    hand_pose_action: c.XrAction,
    hand_sub_paths: [2]c.XrPath,
    hand_spaces: [2]c.XrSpace,
    hand_activate_action: c.XrAction,
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
            .{ .action = bindings.hand_activate_action, .binding = activate_paths[0] },
            .{ .action = bindings.hand_activate_action, .binding = activate_paths[1] },
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

pub fn main() !void {
    // Initialization
    const screenWidth = 1200;
    const screenHeight = 900;

    c.InitWindow(screenWidth, screenHeight, "rlOpenXR-Zig - Hello Clicky Hands");
    defer c.CloseWindow();

    // Initialize OpenXR
    const initialized_openxr = rl.setup();
    if (!initialized_openxr) {
        std.debug.print("Failed to initialize rlOpenXR! Will run in non-VR mode.\n", .{});
    }
    defer if (initialized_openxr) rl.shutdown();

    // Define the camera
    var camera = c.Camera3D{
        .position = .{ .x = 10.0, .y = 10.0, .z = 10.0 },
        .target = .{ .x = 0.0, .y = 3.0, .z = 0.0 },
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

    // Main game loop
    while (!c.WindowShouldClose()) {
        // Update
        if (initialized_openxr) {
            rl.update(); // Update OpenXR state (must be called first)
            rl.syncSingleActionSet(bindings.actionset); // Sync action set
            rl.updateHands(&left_hand, &right_hand); // Update hand tracking
            rl.updateCamera(&camera); // Update camera from HMD if available
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
            c.ClearBackground(c.BLUE);

            c.BeginMode3D(camera);

            // Draw hands with color based on trigger value
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

            // Draw scene - cube at y=0 matching C++ example
            c.DrawCube(.{ .x = -3, .y = 0, .z = 0 }, 2.0, 2.0, 2.0, c.RED);
            c.DrawGrid(10, 1.0);

            c.EndMode3D();
        } else {
            // Fallback non-VR rendering
            c.BeginMode3D(camera);

            c.DrawCube(.{ .x = -3, .y = 0, .z = 0 }, 2.0, 2.0, 2.0, c.RED);
            c.DrawGrid(10, 1.0);

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
        c.DrawText("Controls: \n    Activate = Left / Right Hand trigger", 10, 35, 20, c.BLACK);

        if (initialized_openxr) {
            c.DrawText("OpenXR Active", 10, 100, 20, c.GREEN);
        } else {
            c.DrawText("OpenXR Not Available - Running in fallback mode", 10, 100, 20, c.ORANGE);
        }

        c.EndDrawing();
    }
}
