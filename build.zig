const std = @import("std");

pub const idf = @import("src/idf_mod.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const port_opt = b.option([]const u8, "port", "Serial port used by component run runner");
    const timeout_opt = b.option(u32, "timeout", "Monitor timeout used by component run runner");

    const embed_zig_dep = b.dependency("embed_zig", .{});

    _ = b.addModule("esp", .{
        .root_source_file = b.path("src/esp_mod.zig"),
        .imports = &.{
            .{ .name = "embed", .module = embed_zig_dep.module("embed") },
        },
    });
    _ = b.addModule("idf", .{
        .root_source_file = b.path("src/idf_mod.zig"),
    });

    const esp_idf_opt = b.option([]const u8, "esp_idf", "ESP-IDF root directory for module compile tests (enables idf-build verification)");

    const test_options = b.addOptions();
    test_options.addOption([]const u8, "zig_exe_path", b.graph.zig_exe);
    test_options.addOption(?[]const u8, "esp_idf", esp_idf_opt);
    test_options.addOption(?[]const u8, "port", port_opt);
    test_options.addOption(?u32, "timeout", timeout_opt);

    const convention_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/convention_checks.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "test_options", .module = test_options.createModule() },
            },
        }),
    });
    const run_tests = b.addRunArtifact(convention_tests);

    const component_compile_runner = b.addExecutable(.{
        .name = "component_compile_runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/runners/component_compile_runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runner_options", .module = test_options.createModule() },
            },
        }),
    });
    const run_component_compile = b.addRunArtifact(component_compile_runner);

    const component_run_runner = b.addExecutable(.{
        .name = "component_run_runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/runners/component_run_runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runner_options", .module = test_options.createModule() },
            },
        }),
    });
    const run_component_run = b.addRunArtifact(component_run_runner);

    const example_compile_runner = b.addExecutable(.{
        .name = "example_compile_runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/runners/example_compile_runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runner_options", .module = test_options.createModule() },
            },
        }),
    });
    const run_example_compile = b.addRunArtifact(example_compile_runner);

    const test_step = b.step("test", "Run convention checks");
    test_step.dependOn(&run_tests.step);

    const component_compile_step = b.step("component-compile", "Compile component-owned test apps");
    component_compile_step.dependOn(&run_component_compile.step);
    test_step.dependOn(&run_component_compile.step);

    const component_run_step = b.step("component-run", "Flash and monitor component-owned test apps");
    component_run_step.dependOn(&run_component_run.step);

    const example_compile_step = b.step("example-compile", "Compile remaining example apps");
    example_compile_step.dependOn(&run_example_compile.step);
}
