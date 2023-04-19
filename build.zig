const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const glfw_dep = b.dependency("glfw", .{
        .target = target,
        .optimize = optimize,
        .opengl = true,
    });
    const zgl_dep = b.dependency("zgl", .{});
    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    const canvas_exe = b.addExecutable(.{
        .name = "canvas",
        .root_source_file = .{ .path = "src/canvas.zig" },
        .target = target,
        .optimize = optimize,
    });
    canvas_exe.addModule("zgl", zgl_dep.module("zgl"));
    canvas_exe.linkLibrary(glfw_dep.artifact("glfw"));
    canvas_exe.addModule("zigimg", zigimg_dep.module("zigimg"));

    _ = b.installArtifact(canvas_exe);
}
