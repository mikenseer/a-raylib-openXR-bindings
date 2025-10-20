// Desktop entry point for Hello Hands example
// Uses shared VR application logic

const VRApp = @import("hello_hands_shared.zig").VRApp;

pub fn main() !void {
    var app = try VRApp.init();
    defer app.deinit();

    while (!app.shouldClose()) {
        app.update();
        app.render();
    }
}
