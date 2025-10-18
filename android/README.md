# Android/Quest Build Setup

This directory contains the build infrastructure for creating Android APKs targeting Meta Quest devices (Quest 2, Quest 3, Quest Pro).

## Prerequisites

### 1. Android SDK

You already have the Android SDK installed at:
```
C:\Users\miken\AppData\Local\Android\Sdk
```

### 2. Android NDK

**Required:** NDK version 25.1.8937393

**Installation Options:**

#### Option A: Using Android Studio (Recommended)
1. Open Android Studio
2. Go to: Tools → SDK Manager
3. Select the "SDK Tools" tab
4. Check "Show Package Details" (bottom right)
5. Find "NDK (Side by side)" and expand it
6. Check version **25.1.8937393**
7. Click "Apply" to install

#### Option B: Using Command-Line Tools
1. Download Android command-line tools from: https://developer.android.com/studio#command-tools
2. Extract to: `%LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest\`
3. Run:
   ```cmd
   cd %LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest\bin
   sdkmanager "ndk;25.1.8937393"
   ```

#### Option C: Manual Download
1. Download NDK 25.1.8937393 from: https://github.com/android/ndk/wiki/Unsupported-Downloads
2. Extract to: `%LOCALAPPDATA%\Android\Sdk\ndk\25.1.8937393\`

### 3. Meta OpenXR Mobile SDK (Required for VR)

**Required for OpenXR VR functionality on Quest**

#### Download and Extract:
1. Download from: https://developer.oculus.com/downloads/package/oculus-openxr-mobile-sdk/
2. Extract to a known location, e.g.:
   - Windows: `C:\Meta-OpenXR-SDK`
   - Linux: `~/Meta-OpenXR-SDK`

#### Configuration Options:

**Option A: Environment Variable (Recommended)**
```cmd
setx META_OPENXR_SDK "C:\Meta-OpenXR-SDK"
```

**Option B: Edit build.zig**
Edit `build.zig` line 24:
```zig
const META_OPENXR_SDK_PATH: ?[]const u8 = "C:\\Meta-OpenXR-SDK";
```

**What it provides:**
- OpenXR headers (`OpenXR/Include/`)
- Loader library (`OpenXR/Libs/Android/arm64-v8a/Release/libopenxr_loader.so`)
- Quest-specific OpenXR extensions

### 4. Environment Variables

After installing the NDK and Meta SDK, set:
```cmd
setx ANDROID_HOME "%LOCALAPPDATA%\Android\Sdk"
setx ANDROID_NDK_HOME "%LOCALAPPDATA%\Android\Sdk\ndk\25.1.8937393"
setx META_OPENXR_SDK "C:\Meta-OpenXR-SDK"
```

**Restart your terminal** after setting environment variables.

### 5. Verify Installation

```cmd
echo %ANDROID_HOME%
echo %ANDROID_NDK_HOME%
echo %META_OPENXR_SDK%
dir "%ANDROID_NDK_HOME%\toolchains"
dir "%META_OPENXR_SDK%\OpenXR\Include"
```

You should see the NDK toolchains and OpenXR headers listed.

## Building for Quest

### First-Time Setup

1. Generate a debug keystore:
   ```cmd
   zig build android-keystore
   ```
   This creates `android/debug.keystore` for signing APKs.

### Build Commands

```cmd
# Build APK for Quest (aarch64-android)
zig build android

# Build and install to connected Quest
zig build android-install

# Build, install, and run
zig build android-run
```

### Sideloading to Quest 3

1. **Enable Developer Mode on Quest:**
   - Open Meta Quest app on phone
   - Go to: Menu → Devices → Headset Settings → Developer Mode
   - Toggle Developer Mode ON

2. **Connect Quest via USB-C:**
   - Use the charging cable to connect Quest to PC
   - Put on the headset and allow USB debugging when prompted

3. **Verify Connection:**
   ```cmd
   "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb" devices
   ```
   You should see your Quest listed.

4. **Install APK:**
   ```cmd
   zig build android-install
   ```

5. **Launch App:**
   - In Quest, go to: App Library → Unknown Sources
   - Find "rlOpenXR Hello VR" and launch

## Troubleshooting

### Meta OpenXR SDK Not Found
**Warning:** `⚠ META_OPENXR_SDK not configured`

**Fix:** Download and configure Meta OpenXR Mobile SDK:
1. Download from: https://developer.oculus.com/downloads/package/oculus-openxr-mobile-sdk/
2. Extract to `C:\Meta-OpenXR-SDK`
3. Set environment variable: `setx META_OPENXR_SDK "C:\Meta-OpenXR-SDK"`
4. Restart terminal

**Note:** Without Meta SDK, the APK will build but VR will not work.

### NDK Not Found
**Error:** `Android NDK not found`

**Fix:** Verify NDK installation:
```cmd
dir "%LOCALAPPDATA%\Android\Sdk\ndk"
```
Should show `25.1.8937393` directory.

### adb not found
**Error:** `adb: command not found`

**Fix:** Add platform-tools to PATH or use full path:
```cmd
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb" devices
```

### Quest not detected
**Fixes:**
- Enable Developer Mode in Meta Quest app (phone)
- Allow USB debugging in headset when prompted
- Try a different USB cable
- Run: `adb kill-server && adb start-server`

### APK won't install
**Fixes:**
- Uninstall previous version from Quest
- Check Quest storage (needs free space)
- Verify APK is signed: `jarsigner -verify zig-out/android/app.apk`

## Quest-Specific Notes

- **Minimum API Level:** 23 (Android 6.0)
- **Target API Level:** 34 (Android 14)
- **Graphics API:** OpenGL ES 3.0+ with OpenXR
- **Architecture:** aarch64 (ARM64) only
- **Install Location:** Auto (required by Meta)

## File Structure

```
android/
  ├── README.md              # This file
  ├── Sdk.zig                # Android APK build system
  ├── AndroidManifest.xml    # Quest OpenXR manifest template
  └── debug.keystore         # Debug signing key (auto-generated)
```

## References

- [Meta Quest OpenXR Documentation](https://developers.meta.com/horizon/documentation/native/android/mobile-intro)
- [ZigAndroidTemplate](https://github.com/ikskuh/ZigAndroidTemplate) - Build system basis
- [Android NDK Guide](https://developer.android.com/ndk/guides)
