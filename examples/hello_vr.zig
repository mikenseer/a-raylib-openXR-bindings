// Desktop entry point - uses shared VR logic
const shared = @import("hello_vr_shared.zig");
const c = @import("rlOpenXR").c;

pub fn main() !void {
    // Initialize shared VR application
    var app = try shared.VRApp.init();
    defer app.deinit();

    // Main game loop
    while (!app.shouldClose()) {
        app.update();
        app.render();
    }
}
