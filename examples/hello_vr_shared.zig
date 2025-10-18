// Shared VR application logic - works on all platforms (Windows, Linux, Android)
// Platform-specific entry points call into this code

const rl = @import("rlOpenXR");
const c = rl.c; // Use the library's C imports to avoid type mismatches

pub const VRApp = struct {
    has_vr: bool,
    camera: c.Camera3D,

    /// Initialize the VR application (platform-agnostic)
    pub fn init() !VRApp {
        const builtin = @import("builtin");
        const is_android = builtin.os.tag == .linux and builtin.abi == .android;

        // On desktop, create a debug window which also initializes OpenGL
        if (!is_android) {
            const screenWidth = 1200;
            const screenHeight = 900;
            c.InitWindow(screenWidth, screenHeight, "rlOpenXR-Zig - Hello VR");

            // OpenXR is responsible for frame timing, disable raylib VSync
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

                // Keep height at 900, adjust width to match aspect ratio
                const new_width: i32 = @intFromFloat(900.0 * aspect_ratio);
                c.SetWindowSize(new_width, 900);
            }
        }

        // Load refresh rate extension if available (Quest/Meta specific)
        if (initialized_openxr) {
            _ = rl.loadRefreshRateExtension();
        }

        return VRApp{
            .has_vr = initialized_openxr,
            .camera = camera,
        };
    }

    /// Update VR state (call once per frame)
    pub fn update(self: *VRApp) void {
        if (self.has_vr) {
            rl.update(); // Update OpenXR state (must be called first)
            rl.updateCamera(&self.camera); // Update camera from HMD if available
        }

        c.UpdateCamera(&self.camera, c.CAMERA_FREE); // Mouse control for debug
    }

    /// Render the VR scene (call once per frame)
    pub fn render(self: *VRApp) void {
        const builtin = @import("builtin");
        const is_android = builtin.os.tag == .linux and builtin.abi == .android;

        // Try to render to VR, fall back to mock HMD if VR unavailable
        const rendering_vr = if (self.has_vr)
            rl.begin() or rl.beginMockHMD()
        else
            false;

        if (rendering_vr) {
            c.ClearBackground(c.BLUE);

            c.BeginMode3D(self.camera);

            // Draw scene - cubes at y=1 so they're above the grid
            c.DrawCube(.{ .x = -3, .y = 1, .z = 0 }, 2.0, 2.0, 2.0, c.RED);
            c.DrawCube(.{ .x = 3, .y = 1, .z = 0 }, 2.0, 2.0, 2.0, c.GREEN);
            c.DrawCube(.{ .x = 0, .y = 1, .z = -3 }, 2.0, 2.0, 2.0, c.YELLOW);
            c.DrawGrid(10, 1.0);

            c.EndMode3D();
        } else if (!is_android) {
            // Fallback non-VR rendering (desktop only - Quest doesn't have a window)
            c.BeginMode3D(self.camera);

            c.DrawCube(.{ .x = -3, .y = 1, .z = 0 }, 2.0, 2.0, 2.0, c.RED);
            c.DrawCube(.{ .x = 3, .y = 1, .z = 0 }, 2.0, 2.0, 2.0, c.GREEN);
            c.DrawCube(.{ .x = 0, .y = 1, .z = -3 }, 2.0, 2.0, 2.0, c.YELLOW);
            c.DrawGrid(10, 1.0);

            c.EndMode3D();
        }

        if (self.has_vr) {
            rl.end();
        }

        // Draw UI overlay to desktop window only
        if (!is_android) {
            c.BeginDrawing();

            c.ClearBackground(c.RAYWHITE); // Clear window if OpenXR skips frame

            // Blit VR view to window INSIDE BeginDrawing
            if (self.has_vr and rendering_vr) {
                const keep_aspect_ratio = false; // Window is already correct aspect ratio
                rl.blitToWindow(.left, keep_aspect_ratio);
            }

            c.DrawFPS(10, 10);

            if (self.has_vr) {
                c.DrawText("OpenXR Active", 10, 40, 20, c.GREEN);
            } else {
                c.DrawText("OpenXR Not Available - Running in fallback mode", 10, 40, 20, c.ORANGE);
            }

            c.EndDrawing();
        }
    }

    /// Check if the application should close
    pub fn shouldClose(self: *const VRApp) bool {
        const builtin = @import("builtin");
        const is_android = builtin.os.tag == .linux and builtin.abi == .android;

        _ = self;

        // On Android, the activity lifecycle manages closing
        if (is_android) {
            return false;
        }

        return c.WindowShouldClose();
    }

    /// Clean up resources
    pub fn deinit(self: *VRApp) void {
        const builtin = @import("builtin");
        const is_android = builtin.os.tag == .linux and builtin.abi == .android;

        if (self.has_vr) {
            rl.shutdown();
        }

        if (!is_android) {
            c.CloseWindow();
        }
    }
};
