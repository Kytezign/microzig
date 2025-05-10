const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const httpz_dep = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    const mirror = b.addExecutable(.{
        .name = "atpack-mirror",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });
    mirror.root_module.addImport("httpz", httpz_dep.module("httpz"));
    b.installArtifact(mirror);

    const run_mirror = b.addRunArtifact(mirror);
    const run_step = b.step("run", "Run the server");
    run_step.dependOn(&run_mirror.step);
}
