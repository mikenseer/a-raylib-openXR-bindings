const rl = @import("rlOpenXR");
const c = rl.c; // Use the library's C imports to avoid type mismatches
const std = @import("std");

// Constants
const TELEPORT_ARC_SPEED = 7.0;
const TELEPORT_ARC_GRAVITY = 9.81;

const XRInputBindings = struct {
    actionset: c.XrActionSet,
    hand_pose_action: c.XrAction,
    hand_sub_paths: [2]c.XrPath,
    hand_spaces: [2]c.XrSpace,
    hand_teleport_action: c.XrAction,
};

fn calculateParabolaTimeToFloor(hand_position: c.Vector3, hand_orientation: c.Quaternion) f32 {
    // Evaluate t = -(-V0 ± sqrt(2 * g * y0 + V0^2)) / g
    const hand_forward = c.Vector3RotateByQuaternion(c.Vector3{ .x = 0, .y = -1, .z = 0 }, hand_orientation);
    const initial_vel = c.Vector3Scale(hand_forward, TELEPORT_ARC_SPEED);

    const g = TELEPORT_ARC_GRAVITY;

    const discriminant = 2.0 * g * hand_position.y + initial_vel.y * initial_vel.y;
    const sqrt_discriminant = @sqrt(discriminant);

    const t_0 = -(-initial_vel.y - sqrt_discriminant) / g;
    const t_1 = -(-initial_vel.y + sqrt_discriminant) / g;

    return @max(t_0, t_1);
}

fn sampleParabolaPosition(hand_position: c.Vector3, hand_orientation: c.Quaternion, t: f32) c.Vector3 {
    // Evaluate y = y0 + V0*t - 0.5*g*t^2
    const hand_forward = c.Vector3RotateByQuaternion(c.Vector3{ .x = 0, .y = -1, .z = 0 }, hand_orientation);
    const initial_vel = c.Vector3Scale(hand_forward, TELEPORT_ARC_SPEED);

    const g = TELEPORT_ARC_GRAVITY;

    const y_at_t = hand_position.y + initial_vel.y * t - 0.5 * g * t * t;

    var sampled_position = c.Vector3Add(hand_position, c.Vector3Scale(initial_vel, t));
    sampled_position.y = y_at_t;
    return sampled_position;
}

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

    // Create teleport action (boolean)
    {
        var action_info = c.XrActionCreateInfo{
            .type = c.XR_TYPE_ACTION_CREATE_INFO,
            .next = null,
            .actionName = undefined,
            .actionType = c.XR_ACTION_TYPE_BOOLEAN_INPUT,
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

        result = c.xrCreateAction(bindings.actionset, &action_info, &bindings.hand_teleport_action);
        _ = rl.xrCheck(result, "Failed to create hand teleport action", .{});
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

    var teleport_paths: [2]c.XrPath = undefined;
    _ = c.xrStringToPath(xr.instance, "/user/hand/left/input/x/click", &teleport_paths[0]);
    _ = c.xrStringToPath(xr.instance, "/user/hand/right/input/a/click", &teleport_paths[1]);

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
            .{ .action = bindings.hand_teleport_action, .binding = teleport_paths[0] },
            .{ .action = bindings.hand_teleport_action, .binding = teleport_paths[1] },
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

    c.InitWindow(screenWidth, screenHeight, "rlOpenXR-Zig - Hello Teleport");
    defer c.CloseWindow();

    // Initialize OpenXR
    const initialized_openxr = rl.setup();
    if (!initialized_openxr) {
        std.debug.print("Failed to initialize rlOpenXR! Will run in non-VR mode.\n", .{});
    }
    defer if (initialized_openxr) rl.shutdown();

    var stage_position = c.Vector3Zero();

    // Define the local camera (relative to stage)
    var local_camera = c.Camera3D{
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

    // Hand tracking data (local to stage)
    var left_local_hand = rl.HandData{
        .valid = false,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .orientation = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        .handedness = .left,
        .hand_pose_action = null,
        .hand_pose_subpath = 0,
        .hand_pose_space = null,
    };

    var right_local_hand = rl.HandData{
        .valid = false,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .orientation = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        .handedness = .right,
        .hand_pose_action = null,
        .hand_pose_subpath = 0,
        .hand_pose_space = null,
    };

    if (initialized_openxr) {
        assignHandInputBindings(&bindings, &left_local_hand, &right_local_hand);
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
            rl.updateHands(&left_local_hand, &right_local_hand); // Update hand tracking
            rl.updateCamera(&local_camera); // Update camera from HMD if available
        }

        c.UpdateCamera(&local_camera, c.CAMERA_FREE); // Mouse control for debug

        // Calculate world space positions
        var world_camera = local_camera;
        world_camera.position = c.Vector3Add(local_camera.position, stage_position);
        world_camera.target = c.Vector3Add(local_camera.target, stage_position);

        var left_hand = left_local_hand;
        left_hand.position = c.Vector3Add(left_local_hand.position, stage_position);

        var right_hand = right_local_hand;
        right_hand.position = c.Vector3Add(right_local_hand.position, stage_position);

        // Teleportation
        if (initialized_openxr and rl.getActionBooleanClicked(bindings.hand_teleport_action, bindings.hand_sub_paths[0])) {
            // Next frame, this will be the new stage position
            stage_position = sampleParabolaPosition(
                left_hand.position,
                left_hand.orientation,
                calculateParabolaTimeToFloor(left_hand.position, left_hand.orientation),
            );
        }

        // Draw
        c.ClearBackground(c.RAYWHITE); // Clear window if OpenXR skips frame

        // Try to render to VR, fall back to mock HMD if VR unavailable
        const rendering_vr = if (initialized_openxr)
            rl.begin() or rl.beginMockHMD()
        else
            false;

        if (rendering_vr) {
            c.ClearBackground(c.SKYBLUE);

            c.BeginMode3D(world_camera);

            // Draw hands
            if (left_hand.valid) {
                var axis: c.Vector3 = undefined;
                var angle: f32 = undefined;
                c.QuaternionToAxisAngle(left_hand.orientation, &axis, &angle);
                c.DrawModelEx(hand_model, left_hand.position, axis, angle * c.RAD2DEG, c.Vector3One(), c.ORANGE);
            }

            if (right_hand.valid) {
                var axis: c.Vector3 = undefined;
                var angle: f32 = undefined;
                c.QuaternionToAxisAngle(right_hand.orientation, &axis, &angle);
                c.DrawModelEx(hand_model, right_hand.position, axis, angle * c.RAD2DEG, c.Vector3One(), c.PINK);
            }

            // Draw teleportation arc
            if (left_hand.valid) {
                const t = calculateParabolaTimeToFloor(left_hand.position, left_hand.orientation);

                const ARC_SEGMENTS = 50;
                var i: usize = 1;
                while (i <= ARC_SEGMENTS) : (i += 1) {
                    const interpolation_t_0 = t / @as(f32, @floatFromInt(ARC_SEGMENTS)) * @as(f32, @floatFromInt(i - 1));
                    const interpolation_t_1 = t / @as(f32, @floatFromInt(ARC_SEGMENTS)) * @as(f32, @floatFromInt(i));
                    const arc_position_0 = sampleParabolaPosition(left_hand.position, left_hand.orientation, interpolation_t_0);
                    const arc_position_1 = sampleParabolaPosition(left_hand.position, left_hand.orientation, interpolation_t_1);
                    c.DrawCylinderEx(arc_position_0, arc_position_1, 0.05, 0.05, 12, c.DARKBLUE);
                }
            }

            // Draw scene - cube at y=0 matching C++ example
            c.DrawCube(.{ .x = -3, .y = 0, .z = 0 }, 2.0, 2.0, 2.0, c.RED);
            c.DrawGrid(10, 1.0);

            c.EndMode3D();
        } else {
            // Fallback non-VR rendering
            c.BeginMode3D(world_camera);

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
        c.DrawText("Controls: \n    Teleport = Left hand 'X' button", 10, 35, 20, c.BLACK);

        if (initialized_openxr) {
            c.DrawText("OpenXR Active", 10, 100, 20, c.GREEN);
        } else {
            c.DrawText("OpenXR Not Available - Running in fallback mode", 10, 100, 20, c.ORANGE);
        }

        c.EndDrawing();
    }
}
