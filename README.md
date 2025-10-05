<div align="center">

<img src="assets/logo.png" alt="rlOpenXR-Zig Logo" width="200"/>

# rlOpenXR-Zig

Zig bindings for raylib with OpenXR VR support, providing cross-platform VR development for PC (Windows, Linux) and Android (Quest 3).



https://github.com/user-attachments/assets/59cde9de-44c6-4fa1-a52a-a58aeb419cf1



</div>

## Features

- **Cross-Platform VR**: Supports Windows, Linux, and Android (Quest 3)
- **Automatic Fallback**: Gracefully handles systems without VR runtimes
- **High Refresh Rate Support**: 72-300Hz display refresh rates for future-proofing
- **Mock HMD Mode**: Test and develop without a VR headset
- **Platform Detection**: Runtime detection of PC vs Android, VR vs non-VR
- **Clean API**: Zig-idiomatic wrapper around OpenXR with error unions

## Credits

This project is a Zig port of [rlOpenXR](https://github.com/FireFlyForLife/rlOpenXR) by FireFlyForLife. The original C++ implementation provided the foundation for these bindings.

## Requirements

- **Zig 0.15.1** or later
- **raylib** (automatically fetched by build system)
- **OpenXR SDK** (automatically fetched by build system)
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

For Quest 3 and other devices with variable refresh rates:

```zig
// Load the refresh rate extension (Meta Quest specific)
if (rl.loadRefreshRateExtension()) {
    // Get supported refresh rates
    const rates = try rl.getSupportedRefreshRates(allocator);
    defer allocator.free(rates);

    // Set to 120Hz for Quest 3
    try rl.setRefreshRate(120.0);
}
```

Supported range: **72-300Hz** (device-dependent)

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

```bash
zig build -Dtarget=aarch64-android
# TODO: APK packaging steps
```

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
  refresh_rate.zig   - Refresh rate configuration
  platform/
    windows.zig      - Windows-specific OpenGL context
    linux.zig        - Linux-specific OpenGL context
    android.zig      - Android EGL context

examples/
  hello_vr.zig       - Basic VR example with fallback
```

## API Reference

### Setup/Shutdown
- `setup() bool` - Initialize OpenXR with default allocator
- `setupWithAllocator(allocator) bool` - Initialize with custom allocator
- `shutdown()` - Clean up OpenXR resources

### Frame Loop
- `update()` - Poll OpenXR events and wait for frame
- `updateCamera(*Camera3D)` - Update camera from HMD pose
- `begin() bool` - Begin VR rendering
- `beginMockHMD() bool` - Begin mock HMD rendering (fallback)
- `end()` - End VR frame and submit to compositor
- `blitToWindow(eye, keep_aspect) void` - Copy VR view to window

### Refresh Rate
- `loadRefreshRateExtension() bool` - Load Meta Quest refresh rate extension
- `getSupportedRefreshRates(allocator) ![]f32` - Query supported rates
- `getCurrentRefreshRate() !f32` - Get current refresh rate
- `setRefreshRate(f32) !void` - Set target refresh rate (72-300Hz)

### State
- `getData() ?*const Data` - Get OpenXR instance data
- `getTime() XrTime` - Get current XR time

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
- Enable developer mode on Quest
- Use `adb install` to sideload
- Check Logcat for OpenXR errors

## Development

### Git Workflow

This repository uses a rebase-based workflow:

```bash
git pull  # Automatically rebases (configured in .git/config)
git rebase main  # Keep history clean
```

### Running Tests

```bash
zig build test
```

## Contributing

Contributions are welcome! Please ensure:
- Code follows Zig style guidelines
- Use `std.math.cast` instead of `@intCast` where possible
- Prefer error unions over panics
- Test on both VR and non-VR systems

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
