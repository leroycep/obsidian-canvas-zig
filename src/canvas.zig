pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();
    const gpa = general_purpose_allocator.allocator();
    std.debug.print("Hello, world!\n", .{});

    _ = c.glfwSetErrorCallback(&error_callback);

    const glfw_init_res = c.glfwInit();
    if (glfw_init_res != 1) {
        std.debug.print("glfw init error: {}\n", .{glfw_init_res});
        std.process.exit(1);
    }
    defer c.glfwTerminate();

    const window = c.glfwCreateWindow(640, 640, "Canvas", null, null) orelse return error.GlfwCreateWindow;
    defer c.glfwDestroyWindow(window);

    c.glfwMakeContextCurrent(window);
    try gl.loadExtensions({}, glGetProcAddress);

    var canvas = try Canvas.init(gpa, 4096);
    defer canvas.deinit(gpa);

    _ = c.glfwSetKeyCallback(window, &key_callback);
    while (c.glfwWindowShouldClose(window) != 1) {
        var framebuffer_size: [2]c_int = undefined;
        c.glfwGetFramebufferSize(window, &framebuffer_size[0], &framebuffer_size[1]);

        var window_size: [2]c_int = undefined;
        c.glfwGetWindowSize(window, &window_size[0], &window_size[1]);

        gl.viewport(0, 0, @intCast(usize, framebuffer_size[0]), @intCast(usize, framebuffer_size[1]));

        const projection = orthographic(f32, 0, @intToFloat(f32, window_size[0]), @intToFloat(f32, window_size[0]), 0, -1, 1);

        canvas.begin(.{ .projection = projection });
        canvas.writeText("Hello, world!", .{ .pos = .{ 0, 0 }, .scale = 5 });
        canvas.end();

        c.glfwSwapBuffers(window);
        c.glfwWaitEvents();
    }
}

pub fn orthographic(comptime T: type, left: T, right: T, bottom: T, top: T, near: T, far: T) [4][4]T {
    const widthRatio = 1 / (right - left);
    const heightRatio = 1 / (top - bottom);
    const depthRatio = 1 / (far - near);
    const tx = -(right + left) * widthRatio;
    const ty = -(top + bottom) * heightRatio;
    const tz = -(far + near) * depthRatio;
    return .{
        .{ 2 * widthRatio, 0, 0, 0 },
        .{ 0, 2 * heightRatio, 0, 0 },
        .{ 0, 0, -2 * depthRatio, 0 },
        .{ tx, ty, tz, 1 },
    };
}

fn key_callback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    _ = mods;
    _ = scancode;
    if (key == c.GLFW_KEY_ESCAPE and action == c.GLFW_PRESS) {
        c.glfwSetWindowShouldClose(window, c.GLFW_TRUE);
    }
}

fn error_callback(err: c_int, description: ?[*:0]const u8) callconv(.C) void {
    std.debug.print("Error 0x{x}: {?s}\n", .{ err, description });
}

fn glGetProcAddress(_: void, proc: [:0]const u8) ?*const anyopaque {
    return c.glfwGetProcAddress(proc);
}

const Canvas = @import("./Canvas.zig");

const c = @import("./c.zig");
// const gl = @import("./gl.zig");
const gl = @import("zgl");
const std = @import("std");
