# Next Steps for rlOpenXR-Zig

## Current Status

✅ **Completed:**
- Git repository with rebase workflow initialized
- Project structure created
- Core Zig bindings implemented (setup, frame loop, platform abstraction)
- Refresh rate support (72-300Hz)
- Mock HMD fallback for non-VR testing
- Example application with VR detection
- Documentation and README

## Required Before Building

### 1. Add raylib Dependency

The build currently has TODO comments for linking raylib. You need to either:

**Option A: Use system raylib**
```zig
// In build.zig, uncomment and modify:
rlOpenXR.linkSystemLibrary("raylib");
```

**Option B: Fetch raylib via Zig package manager**
Add to `build.zig.zon`:
```zig
.dependencies = .{
    .raylib = .{
        .url = "https://github.com/raysan5/raylib/archive/refs/tags/5.0.tar.gz",
        .hash = "<hash>", // Run zig build to get hash
    },
},
```

### 2. Add OpenXR SDK Dependency

**Option A: Use system OpenXR**
```bash
# Windows: Download from https://github.com/KhronosGroup/OpenXR-SDK/releases
# Add to system PATH or use --search-prefix
```

**Option B: Fetch via build system**
Add OpenXR SDK fetch logic to `build.zig`

### 3. Platform-Specific Setup

**Windows:**
- Install Visual Studio Build Tools (for C/C++ compiler)
- Install OpenXR runtime (SteamVR or Oculus)
- Set environment variables for OpenXR SDK if needed

**Linux:**
- `sudo apt install libgl1-mesa-dev libx11-dev`
- Install Monado or SteamVR for Linux
- OpenXR SDK headers

**Android:**
- Android NDK
- Quest development setup
- Meta OpenXR SDK

## Testing Strategy

### Phase 1: Non-VR Compilation Test
```bash
# First, just try to compile without VR runtime
zig build
# Expected: Should compile but may have linker warnings about missing OpenXR runtime
```

### Phase 2: Non-VR Runtime Test
```bash
# Run without VR headset or runtime
zig build run
# Expected: Should show "OpenXR Not Available - Running in fallback mode"
```

### Phase 3: VR Runtime Test
```bash
# With SteamVR or Oculus running
zig build run
# Expected: Should show "OpenXR Active" and render to headset
```

### Phase 4: VR Hardware Test
- Test on Valve Index (144Hz)
- Test on Quest 3 via Link (120Hz)
- Test refresh rate switching

### Phase 5: Android APK Build
```bash
zig build -Dtarget=aarch64-android
# Package as APK and sideload to Quest 3
```

## Known Issues to Fix

1. **Build System:** raylib and OpenXR not yet linked
2. **Platform Code:** Windows-specific functions may need adjustment for different GL versions
3. **Mock HMD:** VrStereoConfig is a static variable, may need lifetime management
4. **Error Handling:** Some C functions may return errors we're not catching
5. **Memory:** Some allocations may need explicit cleanup

## Code Quality TODOs

- [ ] Replace remaining `@intCast` with `std.math.cast`
- [ ] Add comprehensive error handling in platform layers
- [ ] Implement `updateCameraTransform` function
- [ ] Add hand tracking support (updateHands, syncSingleActionSet)
- [ ] Add depth swapchain support
- [ ] Test on all three platforms
- [ ] Add more examples (hand tracking, teleportation)
- [ ] Profile and optimize performance

## Documentation TODOs

- [ ] Add API documentation comments
- [ ] Create tutorial for Android APK building
- [ ] Add troubleshooting section for common errors
- [ ] Document refresh rate capabilities per device
- [ ] Add architecture diagram

## Quick Start for Development

1. **Install Dependencies:**
   ```bash
   # Install raylib (system)
   # Install OpenXR SDK
   # Install VR runtime (optional for testing)
   ```

2. **Update build.zig:**
   - Add raylib linking
   - Add OpenXR SDK path
   - Configure include directories

3. **Test Build:**
   ```bash
   zig build
   ```

4. **Test Non-VR Fallback:**
   ```bash
   # Without VR runtime running
   zig build run
   ```

5. **Test VR Mode:**
   ```bash
   # Start SteamVR or Oculus
   zig build run
   # Put on headset
   ```

## Contributing

When adding features:
1. Update tests in `src/rlOpenXR.zig`
2. Add examples to `examples/`
3. Update README.md
4. Test on multiple platforms if possible
5. Use clean git commits with rebase

## Resources

- [Zig Build System Docs](https://ziglang.org/learn/build-system/)
- [OpenXR Specification](https://registry.khronos.org/OpenXR/specs/1.0/html/xrspec.html)
- [raylib Cheatsheet](https://www.raylib.com/cheatsheet/cheatsheet.html)
- [Original rlOpenXR](https://github.com/FireFlyForLife/rlOpenXR)
