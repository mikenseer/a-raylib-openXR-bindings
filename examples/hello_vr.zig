const rl = @import("rlOpenXR");
const c = rl.c; // Use the library's C imports to avoid type mismatches

pub fn main() !void {
    // Initialization
    const screenWidth = 1200;
    const screenHeight = 900;

    c.InitWindow(screenWidth, screenHeight, "rlOpenXR-Zig - Hello VR");
    defer c.CloseWindow();

    // Define the camera
    var camera = c.Camera3D{
        .position = .{ .x = 10.0, .y = 10.0, .z = 10.0 },
        .target = .{ .x = 0.0, .y = 3.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = c.CAMERA_PERSPECTIVE,
    };

    // OpenXR is responsible for frame timing, disable raylib VSync
    c.SetTargetFPS(-1);

    // Initialize OpenXR
    const initialized_openxr = rl.setup();
    if (!initialized_openxr) {
        @import("std").debug.print("Failed to initialize rlOpenXR! Will run in non-VR mode.\n", .{});
    }
    defer if (initialized_openxr) rl.shutdown();

    // Try to load refresh rate extension (Quest/Meta specific)
    if (initialized_openxr) {
        if (rl.loadRefreshRateExtension()) {
            @import("std").debug.print("Refresh rate extension available\n", .{});
        }
    }

    // Main game loop
    while (!c.WindowShouldClose()) {
        // Update
        if (initialized_openxr) {
            rl.update(); // Update OpenXR state (must be called first)
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

            // Draw scene
            c.DrawCube(.{ .x = -3, .y = 0, .z = 0 }, 2.0, 2.0, 2.0, c.RED);
            c.DrawCube(.{ .x = 3, .y = 0, .z = 0 }, 2.0, 2.0, 2.0, c.GREEN);
            c.DrawCube(.{ .x = 0, .y = 0, .z = -3 }, 2.0, 2.0, 2.0, c.YELLOW);
            c.DrawGrid(10, 1.0);

            c.EndMode3D();

            // Blit to window for flatscreen preview
            const keep_aspect_ratio = true;
            rl.blitToWindow(.both, keep_aspect_ratio);
        } else {
            // Fallback non-VR rendering
            c.BeginMode3D(camera);

            c.DrawCube(.{ .x = -3, .y = 0, .z = 0 }, 2.0, 2.0, 2.0, c.RED);
            c.DrawCube(.{ .x = 3, .y = 0, .z = 0 }, 2.0, 2.0, 2.0, c.GREEN);
            c.DrawCube(.{ .x = 0, .y = 0, .z = -3 }, 2.0, 2.0, 2.0, c.YELLOW);
            c.DrawGrid(10, 1.0);

            c.EndMode3D();
        }

        if (initialized_openxr) {
            rl.end();
        }

        // Draw UI overlay
        c.BeginDrawing();

        c.DrawFPS(10, 10);

        if (initialized_openxr) {
            c.DrawText("OpenXR Active", 10, 40, 20, c.GREEN);
        } else {
            c.DrawText("OpenXR Not Available - Running in fallback mode", 10, 40, 20, c.ORANGE);
        }

        c.EndDrawing();
    }
}
