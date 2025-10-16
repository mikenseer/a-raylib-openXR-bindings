# Integration Guide: Adding VR Locomotion to Your 3D Project

This guide shows how to integrate the smooth locomotion system from `hello_smooth_turning.zig` into your existing 3D raylib/Zig projects.

## Quick Overview

The locomotion system uses OpenXR reference spaces correctly - you draw your world at world coordinates, and OpenXR automatically transforms everything for VR. No manual coordinate transforms needed!

## Step 1: Copy the Quaternion Helpers

```zig
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
        const v_quat = c.XrQuaternionf{ .x = v.x, .y = v.y, .z = v.z, .w = 0.0 };
        const q_conj = c.XrQuaternionf{ .x = -q.x, .y = -q.y, .z = -q.z, .w = q.w };
        const temp = multiply(q, v_quat);
        const result = multiply(temp, q_conj);
        return .{ .x = result.x, .y = result.y, .z = result.z };
    }
};
```

## Step 2: Add Locomotion Code to Your Update Loop

### Movement (Head-Relative)

```zig
// Get thumbstick input (use your input system)
const move_input = getThumbstickInput(); // XrVector2f with x/y in range [-1, 1]

if (@abs(move_input.x) > 0.1 or @abs(move_input.y) > 0.1) {
    // Get current offset
    var offset = rl.getPlaySpaceOffset();

    // Calculate HMD's forward direction (flatten to XZ plane)
    const hmd_forward_playspace = c.Vector3Subtract(camera.target, camera.position);
    const hmd_forward_flat = c.Vector3{
        .x = hmd_forward_playspace.x,
        .y = 0,
        .z = hmd_forward_playspace.z
    };
    const hmd_forward_norm = c.Vector3Normalize(hmd_forward_flat);

    // Get right direction (perpendicular to forward)
    const hmd_right_norm = c.Vector3{
        .x = -hmd_forward_norm.z,
        .y = 0,
        .z = hmd_forward_norm.x
    };

    // Transform to world space
    const forward_world = QuatHelpers.rotateVector(hmd_forward_norm, offset.orientation);
    const right_world = QuatHelpers.rotateVector(hmd_right_norm, offset.orientation);

    // Apply movement (adjust move_speed to taste, e.g., 3.0 units/sec)
    const move_speed: f32 = 3.0;
    const move_forward = c.Vector3Scale(forward_world, -move_input.y * move_speed * dt);
    const move_right = c.Vector3Scale(right_world, -move_input.x * move_speed * dt);

    offset.position.x += move_forward.x + move_right.x;
    offset.position.z += move_forward.z + move_right.z;

    // Update OpenXR reference space
    rl.updatePlaySpaceOffset(offset) catch |err| {
        std.debug.print("Failed to update play space offset: {}\n", .{err});
    };
}
```

### Turning (Smooth)

```zig
// Get turn input (use your input system)
const turn_input = getTurnThumbstickInput(); // XrVector2f

if (@abs(turn_input.x) > 0.1) {
    // Get current offset
    var offset = rl.getPlaySpaceOffset();

    // Calculate rotation delta (adjust turn_speed to taste, e.g., 180°/sec)
    const turn_speed: f32 = 180.0;
    const delta_yaw_deg = turn_input.x * turn_speed * dt;
    const delta_yaw_rad = delta_yaw_deg * c.DEG2RAD;

    // Get HMD position in world space (this is our pivot point)
    const hmd_playspace = camera.position;
    const hmd_world = QuatHelpers.rotateVector(hmd_playspace, offset.orientation);
    const pivot_world = c.Vector3{
        .x = offset.position.x + hmd_world.x,
        .y = offset.position.y + hmd_world.y,
        .z = offset.position.z + hmd_world.z,
    };

    // Create and apply rotation
    const delta_quat = QuatHelpers.fromYaw(delta_yaw_rad);
    const new_orientation = QuatHelpers.multiply(delta_quat, offset.orientation);

    // Calculate new position to keep pivot stationary
    const rotated_hmd = QuatHelpers.rotateVector(hmd_playspace, new_orientation);
    const new_position = c.XrVector3f{
        .x = pivot_world.x - rotated_hmd.x,
        .y = pivot_world.y - rotated_hmd.y,
        .z = pivot_world.z - rotated_hmd.z,
    };

    // Update offset and apply
    offset.orientation = new_orientation;
    offset.position = new_position;

    rl.updatePlaySpaceOffset(offset) catch |err| {
        std.debug.print("Failed to update play space offset: {}\n", .{err});
    };
}
```

## Step 3: Draw Your World at World Coordinates

**Important**: Do NOT transform your world objects! OpenXR handles the coordinate transform automatically.

```zig
// VR rendering
if (rl.begin()) {
    c.BeginMode3D(camera);

    // Draw your game world at world coordinates
    drawYourGameWorld(); // Trees, buildings, enemies, etc.

    // Draw ground grid
    c.DrawGrid(20, 1.0);

    // Draw hands (if you have hand tracking)
    if (left_hand.valid) {
        drawHand(left_hand);
    }

    c.EndMode3D();
}
rl.end();
```

## Customization

### Adjust Movement Speed
```zig
const move_speed: f32 = 5.0; // Faster movement
const move_speed: f32 = 1.5; // Slower movement
```

### Adjust Turn Speed
```zig
const turn_speed: f32 = 90.0;  // Slower turning (90°/sec)
const turn_speed: f32 = 180.0; // Default (180°/sec)
const turn_speed: f32 = 360.0; // Faster turning (360°/sec)
```

### Snap Turning Instead of Smooth
Replace the smooth turning code with:

```zig
if (@abs(turn_input.x) > 0.5) { // Higher threshold for snap
    if (!is_turning) { // Prevent repeated snaps
        is_turning = true;

        // Snap by fixed angle (e.g., 45 degrees)
        const snap_angle = if (turn_input.x > 0) 45.0 else -45.0;
        const delta_yaw_rad = snap_angle * c.DEG2RAD;

        // [Same pivot calculation and quaternion math as smooth turning]
    }
} else {
    is_turning = false; // Reset when thumbstick returns to center
}
```

## Complete Example

See `examples/hello_smooth_turning.zig` for a complete, working example with:
- Input setup (left/right thumbsticks)
- Hand tracking
- Trigger input (color change demo)
- Fallback mode for testing without VR

## Key Points

1. **No coordinate transforms needed**: Draw at world coordinates, OpenXR handles it
2. **Head-relative movement**: Forward goes where you're looking, not where play space faces
3. **Head-centric rotation**: Rotates around your head position, not room center
4. **Performance**: Reference space updates are the correct OpenXR approach (not a perf issue)

## API Reference

### Locomotion Functions

```zig
// Get current play space offset (position + rotation)
const offset = rl.getPlaySpaceOffset(); // Returns XrPosef

// Update play space offset (recreates OpenXR reference space)
rl.updatePlaySpaceOffset(new_offset) catch |err| { /* handle error */ };
```

### XrPosef Structure

```zig
pub const XrPosef = extern struct {
    orientation: XrQuaternionf, // Rotation (quaternion)
    position: XrVector3f,        // Position in world space
};
```

## Troubleshooting

**Issue**: Movement feels backwards
- **Fix**: Negate `move_input.y` when calculating `move_forward`

**Issue**: Turning direction is reversed
- **Fix**: Remove negation from `turn_input.x` (or add if missing)

**Issue**: Rotation around wrong point
- **Fix**: Ensure you're using `camera.position` (HMD position in play space) as the pivot

**Issue**: World objects rotate with player
- **Fix**: Don't apply any transforms to world objects - draw at world coordinates directly

## Migration from Other Systems

### From Manual Transform System
If you were previously transforming objects CPU-side:
1. Remove all `worldToPlaySpace()` transforms
2. Delete custom rotation/position tracking
3. Draw objects at world coordinates
4. Use `rl.updatePlaySpaceOffset()` for locomotion

### From Unity XR Interaction Toolkit
The concepts map directly:
- Unity's XR Origin = OpenXR play_space_offset
- Unity's LocomotionProvider = This locomotion code
- Unity's XR Rig = OpenXR reference space with offset

## Performance Notes

- ✅ Reference space updates are lightweight (intended OpenXR design)
- ✅ Quaternion math is ~16 multiplications per frame (negligible)
- ✅ No object transforms = better performance than manual systems
- ✅ Only updates when moving/turning (idle = zero cost)

## Further Reading

- OpenXR Specification: [Reference Spaces](https://registry.khronos.org/OpenXR/specs/1.0/html/xrspec.html#spaces)
- Unity XR Interaction Toolkit: [Locomotion System](https://docs.unity3d.com/Packages/com.unity.xr.interaction.toolkit@2.0/manual/locomotion.html)
- Example Implementation: `examples/hello_smooth_turning.zig`
