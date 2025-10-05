# Windows Setup and Testing Guide

This guide will help you build and test the raylib OpenXR bindings on Windows.

## Prerequisites

### Required Tools
- **Zig 0.15.1** - [Download](https://ziglang.org/download/)
- **Git** - For cloning the repository
- **Visual Studio Build Tools** (optional) - For C/C++ compilation if needed

### Optional (for VR testing)
- **SteamVR** or **Oculus software** - VR runtime
- **VR Headset** - Valve Index, Quest 3, etc.

## Phase 1: Build Without OpenXR (Raylib Only)

This tests that raylib dependency works correctly.

### Step 1: Clone and Build

```bash
git clone https://github.com/mikenseer/a-raylib-openXR-bindings.git
cd a-raylib-openXR-bindings
zig build
```

**Expected Result:**
- ✅ Should compile successfully (raylib downloads automatically)
- ⚠️ May show warnings about missing OpenXR headers (this is normal)

If you get errors about missing OpenXR headers, that's expected - proceed to Phase 2.

## Phase 2: Install OpenXR SDK (Not Committed to Repo)

OpenXR SDK is **not included** in the repository. You need to download it separately.

### Option A: Download Pre-built SDK (Recommended)

1. **Download OpenXR SDK:**
   - Go to https://github.com/KhronosGroup/OpenXR-SDK/releases
   - Download latest Windows release (e.g., `OpenXR-SDK-1.0.33-windows.zip`)
   - Extract to a location like `C:\OpenXR-SDK`

2. **Add Include Path to Build:**

   Create a file `.build-config.zig` in the project root:
   ```zig
   // Local build configuration (NOT committed to repo)
   pub const openxr_include_path = "C:\\OpenXR-SDK\\include";
   pub const openxr_lib_path = "C:\\OpenXR-SDK\\lib";
   ```

3. **Update `.gitignore`:**
   The repo should already ignore `.build-config.zig` so your local paths don't get committed.

### Option B: Use System Environment Variable

Set environment variable:
```cmd
set OPENXR_SDK_PATH=C:\OpenXR-SDK
```

Then the build system can check for this variable.

### Option C: Use Zig's Include Path Flag

```bash
zig build -Dsystem-include-path="C:\OpenXR-SDK\include"
```

## Phase 3: Configure Build for OpenXR

We need to update `build.zig` to support local OpenXR SDK paths.

### Temporary Approach (Quick Test)

Add these lines to `build.zig` after the OpenXR comment block (around line 19):

```zig
// Local OpenXR SDK path (modify this for your system)
const openxr_sdk = "C:\\OpenXR-SDK"; // Change this path!

rlOpenXR.addIncludePath(b.path(openxr_sdk ++ "\\include"));
rlOpenXR.addLibraryPath(b.path(openxr_sdk ++ "\\lib"));
```

**Important:** Don't commit this change! It's just for local testing.

### Better Approach (Use Environment Variable)

We should create a proper build option. Let me know if you want me to implement this.

## Phase 4: Test Non-VR Fallback Mode

**Without VR runtime running:**

```bash
zig build run
```

**Expected Behavior:**
- ✅ Should compile successfully
- ✅ Should print "OpenXR Not Available - Running in fallback mode"
- ✅ Should open a window showing raylib rendering
- ✅ Should NOT require VR headset

**This tests:**
- Raylib integration works
- Graceful fallback when VR not available
- Basic rendering pipeline

## Phase 5: Test with VR Runtime

### Step 1: Install VR Runtime

**Option A: SteamVR**
1. Install Steam
2. Install SteamVR from Steam
3. Launch SteamVR

**Option B: Oculus/Meta**
1. Install Oculus PC software
2. Connect Quest via Link/Air Link
3. Start Oculus runtime

### Step 2: Run with VR

```bash
# Make sure SteamVR or Oculus is running
zig build run
```

**Expected Behavior:**
- ✅ Should detect OpenXR runtime
- ✅ Should print "OpenXR Active"
- ✅ Should render to VR headset
- ✅ You should see the scene in your headset

## Phase 6: Test Refresh Rate (Quest 3 Only)

If using Quest 3 with Link:

```bash
zig build run
```

The example app should:
- ✅ Detect supported refresh rates (72, 90, 120 Hz)
- ✅ Set optimal refresh rate
- ✅ Print current refresh rate to console

## Troubleshooting

### Error: "openxr/openxr.h: No such file or directory"

**Solution:** OpenXR SDK not found. Check:
1. Did you download OpenXR SDK?
2. Is the path in `build.zig` correct?
3. Try absolute paths instead of relative

### Error: "undefined reference to xrEnumerateInstanceExtensionProperties"

**Solution:** OpenXR loader library not linked.

Two options:
1. **Don't link loader** - Use fallback mode (works without VR)
2. **Link loader** - Uncomment in `build.zig` (lines 54-63):
   ```zig
   if (target.result.os.tag == .windows) {
       rlOpenXR.linkSystemLibrary("openxr_loader");
   }
   ```

### Error: "OpenXR runtime not available"

**Solution:** This is normal if:
- No VR runtime installed → Install SteamVR or Oculus
- VR runtime not running → Launch SteamVR or Oculus software
- Want to test without VR → This is expected, app should use fallback

### App crashes in VR mode

**Debug steps:**
1. Check SteamVR/Oculus is running
2. Check headset is connected
3. Run with debug output: `zig build run -Doptimize=Debug`
4. Check console for error messages

## Build Configurations

### Debug Build (Verbose Output)
```bash
zig build -Doptimize=Debug
```

### Release Build (Fast)
```bash
zig build -Doptimize=ReleaseFast
```

### Run Tests
```bash
zig build test
```

## What Gets Committed vs Local

### ✅ Committed to Repo:
- Source code (`src/`)
- Build configuration (`build.zig`, `build.zig.zon`)
- Examples (`examples/`)
- Documentation

### ❌ NOT Committed (Local Only):
- OpenXR SDK files
- `.build-config.zig` (local paths)
- `.zig-cache/` (build artifacts)
- `zig-out/` (compiled binaries)
- Personal VR runtime installations

## Next Steps After Windows Testing

Once Windows testing works:

1. **Test on Linux** - See `LINUX_SETUP.md` (TODO)
2. **Build for Quest 3** - See `ANDROID_SETUP.md` (TODO)
3. **Report Issues** - Open GitHub issues for any problems
4. **Contribute** - Add features, fix bugs, improve docs

## Quick Reference

### Minimal Setup (Fallback Mode Only)
```bash
git clone <repo>
cd a-raylib-openXR-bindings
zig build run
# Should work without VR!
```

### Full VR Setup
```bash
# 1. Download OpenXR SDK
# 2. Update build.zig with SDK path
# 3. Install SteamVR or Oculus
# 4. Run
zig build run
```

### Clean Build
```bash
rm -rf .zig-cache zig-out
zig build
```

## Support

- **GitHub Issues:** https://github.com/mikenseer/a-raylib-openXR-bindings/issues
- **Discord:** (TODO: Add if available)
- **Reference C++ Version:** https://github.com/FireFlyForLife/rlOpenXR
