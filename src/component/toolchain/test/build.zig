const std = @import("std");
const esp = @import("esp");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = esp.idf.build.registerApp(b, "toolchain_test", .{
        .target = target,
        .optimize = optimize,
        .embed_links = .{},
    });
}
