<div align="center">

<img src="assets/logo.png" alt="rlOpenXR-Zig Logo" width="200"/>

# rlOpenXR-Zig

Zig bindings for raylib with OpenXR VR support, providing cross-platform VR development for PC and mobile.

https://github.com/user-attachments/assets/fb1750bb-739d-49eb-b949-487037ddee57




</div>

## Features

- **Cross-Platform VR**: Windows and Android/Quest (confirmed), Linux (should work, needs testing)
- **Automatic Fallback**: Gracefully handles systems without VR runtimes
- **High Refresh Rate Support**: 72-300Hz display refresh rates for future-proofing
- **Mock HMD Mode**: Test and develop without a VR headset
- **Hand Tracking**: Full OpenXR action system for controllers and hand input
- **Platform Detection**: Runtime detection of PC vs Android, VR vs non-VR
- **Clean API**: Zig-idiomatic wrapper around OpenXR with error unions

## Credits

This project is a Zig port of [rlOpenXR](https://github.com/FireFlyForLife/rlOpenXR) by FireFlyForLife. The original C++ implementation provided the foundation for these bindings.

## Requirements

- **Zig 0.15.1** or later
- **raylib** (automatically fetched by build system)
- **OpenXR SDK** (automatically fetched by build system for PC)
- **Meta OpenXR Mobile SDK** (required for Android VR - see Android setup below)
- **VR Runtime** (for VR mode):
  - Windows: SteamVR or Oculus/Meta runtime
  - Linux: Monado or SteamVR
  - Android: Built-in Quest runtime

## Quick Start

```bash
# Clone the repository
git clone https://github.com/mikenseer/a-raylib-openXR-bindings.git
cd a-raylib-openXR-bindings

# Build and run the example
zig build run
```

The example will automatically detect if a VR runtime is available and fall back to mock HMD mode if not.

## Examples

The library includes five progressive examples demonstrating different features:

```bash
# Basic VR rendering with automatic fallback
zig build run                    # or: zig build run-vr

# Hand tracking with controller visualization
zig build run-hands

# Interactive cubes using trigger input
zig build run-clicky-hands

# Teleportation locomotion system
zig build run-teleport

# Smooth turning and locomotion with joystick input
zig build run-smooth-turning
```

Each example builds on the previous one, teaching VR fundamentals step-by-step.

## Usage Example

```zig
const rl = @import("rlOpenXR");
const c = @cImport({
    @cInclude("raylib.h");
});

pub fn main() !void {
    c.InitWindow(1200, 900, "My VR App");
    defer c.CloseWindow();

    // Initialize OpenXR (gracefully fails if no VR)
    const has_vr = rl.setup();
    defer if (has_vr) rl.shutdown();

    var camera = c.Camera3D{
        .position = .{ .x = 0, .y = 1.6, .z = 3 },
        .target = .{ .x = 0, .y = 1.6, .z = 0 },
        .up = .{ .x = 0, .y = 1, .z = 0 },
        .fovy = 45.0,
        .projection = c.CAMERA_PERSPECTIVE,
    };

    while (!c.WindowShouldClose()) {
        // Update VR state
        if (has_vr) {
            rl.update();
            rl.updateCamera(&camera);
        }

        // Render to VR or fallback to mock HMD
        const rendering = if (has_vr)
            rl.begin() or rl.beginMockHMD()
        else
            false;

        if (rendering) {
            c.BeginMode3D(camera);
            // Draw your scene here
            c.EndMode3D();

            // Preview on flatscreen
            rl.blitToWindow(.both, true);
        }

        if (has_vr) rl.end();

        c.BeginDrawing();
        c.DrawFPS(10, 10);
        c.EndDrawing();
    }
}
```

## Refresh Rate Configuration

**Android/Quest automatically defaults to the highest available refresh rate (120Hz on Quest 3).**

The library handles this automatically on the first frame. No code changes needed for 120Hz!

### Customizing Refresh Rate

To implement a settings menu or override the default:

```zig
const rl = @import("rlOpenXR");
const std = @import("std");

// Modify src/frame.zig beginOpenXR() to customize refresh rate behavior:

// Example 1: Always use 90Hz (battery saving mode)
if (builtin.abi == .android and state.extensions.refresh_rate_enabled and !state.extensions.refresh_rate_requested) {
    state.extensions.refresh_rate_requested = true;
    const refresh = @import("refresh_rate.zig");
    refresh.setRefreshRate(state.data.session, 90.0) catch {};
}

// Example 2: Build a settings menu
if (builtin.abi == .android and state.extensions.refresh_rate_enabled and !state.extensions.refresh_rate_requested) {
    state.extensions.refresh_rate_requested = true;
    const refresh = @import("refresh_rate.zig");

    // Query available rates
    if (refresh.getSupportedRefreshRates(state.data.session, state.allocator)) |rates| {
        defer state.allocator.free(rates);

        // Show rates in UI: rates[0], rates[1], etc.
        // Let user pick, then:
        const user_choice: f32 = 90.0; // From settings
        refresh.setRefreshRate(state.data.session, user_choice) catch {};
    } else |_| {}
}

// Example 3: Get current refresh rate
const current_rate = refresh.getCurrentRefreshRate(state.data.session) catch 72.0;
std.debug.print("Running at {d}Hz\n", .{current_rate});
```

**Supported rates** (device-dependent):
- Quest 3: 72Hz, 90Hz, 120Hz
- Quest 2: 72Hz, 90Hz
- Quest Pro: 72Hz, 90Hz
- Valve Index: 80Hz, 90Hz, 120Hz, 144Hz
- Future devices: Up to 300Hz

## Platform Detection

```zig
const std = @import("std");
const builtin = @import("builtin");

if (builtin.os.tag == .android) {
    // Android-specific code (Quest 3 APK)
} else if (builtin.os.tag == .windows) {
    // Windows PCVR (SteamVR/Oculus)
}

// Runtime VR detection
const has_vr = rl.setup();
if (has_vr) {
    // VR runtime is available
} else {
    // Fallback to non-VR mode
}
```

## Building

### Windows PCVR

```bash
zig build -Dtarget=x86_64-windows
zig build run  # Run locally
```

### Linux PCVR

```bash
zig build -Dtarget=x86_64-linux
```

### Android Quest 3 APK

**Prerequisites:**
- Android NDK 25.1.8937393
- Meta OpenXR Mobile SDK (for VR functionality)
- See `android/README.md` for complete setup instructions

```bash
# Configure Meta SDK (first time only)
# Windows:
set META_OPENXR_SDK=C:\Meta-OpenXR-SDK

# Linux/Mac:
export META_OPENXR_SDK=/path/to/Meta-OpenXR-SDK

# Generate debug keystore (first time only)
zig build android-keystore

# Build APK for Quest
zig build android

# Install to connected Quest via USB
zig build android-install

# Build, install, and run
zig build android-run
```

**Note:** Download Meta OpenXR Mobile SDK from [Meta Developer Downloads](https://developer.oculus.com/downloads/package/oculus-openxr-mobile-sdk/)

See `android/README.md` for detailed Android setup and troubleshooting.

## Testing Without VR

The library includes a mock HMD mode for testing without a headset:

1. Run the example without a VR runtime installed
2. The code detects absence of VR and uses `rl.beginMockHMD()`
3. Renders a simulated VR view to the window

This allows fast iteration without putting on a headset.

## Architecture

```
src/
  rlOpenXR.zig       - Main public API
  setup.zig          - OpenXR initialization
  frame.zig          - Frame loop and rendering
  input.zig          - Hand tracking and action input
  refresh_rate.zig   - Refresh rate configuration
  platform/
    windows.zig      - Windows-specific OpenGL context
    linux.zig        - Linux-specific OpenGL context
    android.zig      - Android EGL context

examples/
  hello_vr.zig             - Basic VR example with fallback
  hello_hands.zig          - Hand tracking with controller visualization
  hello_clicky_hands.zig   - Interactive cubes with trigger input
  hello_teleport.zig       - Teleportation locomotion system
  hello_smooth_turning.zig - Joystick based smooth turning and locomotion
```

## API Reference

### Setup/Shutdown
- `setup() bool` - Initialize OpenXR with default allocator
- `setupWithAllocator(allocator) bool` - Initialize with custom allocator
- `shutdown()` - Clean up OpenXR resources

### Frame Loop
- `update()` - Poll OpenXR events and wait for frame
- `updateCamera(*Camera3D)` - Update camera from HMD pose
- `updateCameraTransform(*Transform)` - Update transform from HMD pose
- `begin() bool` - Begin VR rendering
- `beginMockHMD() bool` - Begin mock HMD rendering (fallback)
- `end()` - End VR frame and submit to compositor
- `blitToWindow(eye, keep_aspect) void` - Copy VR view to window

### Hand Tracking & Input
- `updateHands(?*HandData, ?*HandData)` - Update left/right hand tracking
- `syncSingleActionSet(XrActionSet)` - Sync OpenXR action set
- `getActionFloat(XrAction, XrPath) f32` - Get analog input (trigger, grip)
- `getActionBooleanClicked(XrAction, XrPath) bool` - Get button click event

### Refresh Rate
- `loadRefreshRateExtension() bool` - Load Meta Quest refresh rate extension
- `getSupportedRefreshRates(allocator) ![]f32` - Query supported rates
- `getCurrentRefreshRate() !f32` - Get current refresh rate
- `setRefreshRate(f32) !void` - Set target refresh rate (72-300Hz)

### State
- `getData() ?*const Data` - Get OpenXR instance data
- `getTime() XrTime` - Get current XR time
- `getEyeResolution() ?struct{ width: u32, height: u32 }` - Get recommended eye resolution

## Supported Headsets

- **PC VR**: Valve Index, Meta Quest (via Link/Air Link), HTC Vive, Windows Mixed Reality
- **Standalone**: Meta Quest 2, Meta Quest 3, Meta Quest Pro
- **Refresh Rates**:
  - Quest 3: 72Hz, 90Hz, 120Hz
  - Valve Index: 80Hz, 90Hz, 120Hz, 144Hz
  - Future devices: Up to 300Hz

## Troubleshooting

**OpenXR fails to initialize on Windows:**
- Install SteamVR or Oculus software
- Ensure VR headset is connected
- Check OpenXR runtime is set in Windows settings

**Linux OpenXR not working:**
- Install Monado or SteamVR for Linux
- Set `XR_RUNTIME_JSON` environment variable if needed

**Quest APK not working:**
- Ensure Meta OpenXR Mobile SDK is installed and `META_OPENXR_SDK` environment variable is set
- Enable developer mode on Quest (Settings → System → Developer)
- Connect Quest via USB and allow USB debugging
- Check `adb logcat | grep rlOpenXR` for detailed error logs
- See `android/README.md` for full troubleshooting guide

## Development

### Git Workflow

This repository uses a rebase-based workflow:

```bash
git pull  # Automatically rebases (configured in .git/config)
git rebase master  # Keep history clean
```

### Running Tests

```bash
zig build test
```

## Contributing

Contributions are welcome! Please ensure:
- Code follows Zig style guidelines
- Prefer standard library functions over low-level builtins when practical (e.g., `std.math.cast` instead of `@intCast`)
  - This guideline encourages error unions over panics, improving robustness
  - Use your judgment - performance-critical paths may warrant direct builtins
- Test on both VR and non-VR systems
- Verify examples still work after API changes

## Acknowledgments

- **FireFlyForLife** - Original [rlOpenXR](https://github.com/FireFlyForLife/rlOpenXR) C++ implementation
- **s-ol** - [openxr-zig](https://github.com/s-ol/openxr-zig) OpenXR binding generator for Zig
- **raysan5** - [raylib](https://www.raylib.com/) game framework
- **Khronos Group** - OpenXR standard and SDK
- **Meta** - Quest platform and OpenXR runtime

## Links

- [rlOpenXR Original (C++)](https://github.com/FireFlyForLife/rlOpenXR)
- [openxr-zig](https://github.com/s-ol/openxr-zig)
- [raylib](https://www.raylib.com/)
- [OpenXR Specification](https://www.khronos.org/openxr/)
- [Zig Programming Language](https://ziglang.org/)
