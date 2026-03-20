const std = @import("std");
const embed_build = @import("embed_zig");

pub const RuntimeOptions = struct {
    port: ?[]const u8,
    timeout: ?u32 = null,
};

const ExternalRuntimeOptions = struct {
    esp_idf: ?[]const u8,
    port: ?[]const u8,
    timeout: ?u32 = null,
};

pub const SdkconfigOptions = struct {
    output_file: []const u8 = "sdkconfig.generated",
    partition_file: []const u8 = "partitions.generated.csv",
    partition_file_for_idf: ?[]const u8 = null,
    build_config: []const u8,
};

pub const AutoAppMainOptions = struct {
    output_file: []const u8 = "build/app_main.generated.c",
    delegate_symbol: []const u8,
};

fn externalRuntimeOptionsFromBuild(b: *std.Build) ExternalRuntimeOptions {
    const opt = b.option([]const u8, "esp_idf", "ESP-IDF root directory; defaults to ESP_IDF env var");
    const esp_idf = opt orelse getEnvOrNull(b, "ESP_IDF");
    const port = b.option([]const u8, "port", "Serial port used by flash/monitor");
    const timeout = b.option(u32, "timeout", "Auto-exit monitor after N seconds");

    return .{
        .esp_idf = esp_idf,
        .port = port,
        .timeout = timeout,
    };
}

pub const RegisterOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    app_name: []const u8,
    app_dir: []const u8,
    app_entry: []const u8 = "src/main.zig",

    idf_module: ?*std.Build.Module = null,
    idf_root_source: ?[]const u8 = null,
    app_options_module: ?*std.Build.Module = null,
    esp_dep: ?*std.Build.Dependency = null,
    esp_root: ?std.Build.LazyPath = null,

    sdkconfig: ?SdkconfigOptions = null,
    auto_app_main: ?AutoAppMainOptions = null,
    idf_build_dir: ?[]const u8 = null,
    extra_component_dirs: []const std.Build.LazyPath = &.{},

    link_libc: bool = true,
    install_artifact: bool = true,
    runtime: RuntimeOptions,
    board_profile_name: ?[]const u8 = null,

    /// 如果为 true，则额外暴露 configure/idf-build/flash/monitor/flash-monitor 短别名。
    /// 一个 build.zig 中仅建议对一个默认 app 打开此选项。
    expose_unprefixed_steps: bool = false,
};

pub const ExtraZigModule = struct {
    name: []const u8,
    path: std.Build.LazyPath,
    deps: []const []const u8 = &.{},
};

pub const Registration = struct {
    build_step: *std.Build.Step,
    sdkconfig_step: ?*std.Build.Step,
    app_main_step: ?*std.Build.Step,
    configure_step: *std.Build.Step,
    idf_build_step: *std.Build.Step,
    flash_step: *std.Build.Step,
    monitor_step: *std.Build.Step,
    flash_monitor_step: *std.Build.Step,
};

pub const BuildOption = struct {
    name: []const u8,
    value: Value,

    pub const Value = union(enum) {
        string: []const u8,
        boolean: bool,
        i64: i64,
        u32: u32,
    };
};

const ToolchainSysroot = struct {
    root: []const u8,
    include_dir: std.Build.LazyPath,
};

pub const RegisterAppOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    app_root: []const u8 = ".",
    app_entry: []const u8 = "src/main.zig",
    entry_symbol: []const u8 = "zig_esp_main",

    extra_component_dirs: []const std.Build.LazyPath = &.{},
    extra_zig_modules: []const ExtraZigModule = &.{},
    build_options: []const BuildOption = &.{},
    embed_links: embed_build.LinkOptions = .{},
};

pub fn registerApp(b: *std.Build, app_name: []const u8, opts: RegisterAppOptions) Registration {
    const deprecated_board = b.option([]const u8, "board", "DEPRECATED: use -Dbuild_config instead");
    const build_config_opt = b.option([]const u8, "build_config", "Board build config file path");
    const bsp_file_opt = b.option([]const u8, "bsp", "Board BSP file (optional, enables @import(\"esp\") in board)");
    const build_dir_opt = b.option([]const u8, "build_dir", "Directory for all generated workflow files");
    const build_config = build_config_opt orelse @panic("missing required -Dbuild_config=<path>");
    const bsp_file = bsp_file_opt orelse @panic("missing required -Dbsp=<path>");
    const build_dir = build_dir_opt orelse
        "build";
    const app_root = opts.app_root;
    const app_entry = opts.app_entry;
    const entry_symbol = opts.entry_symbol;
    const external_runtime = externalRuntimeOptionsFromBuild(b);
    const expose_prefixed_steps = false;

    if (deprecated_board != null) {
        @panic("-Dboard is no longer supported; use -Dbuild_config instead");
    }
    if (build_dir_opt == null) {
        std.log.warn("missing -Dbuild_dir, using default {s}", .{build_dir});
    }

    const esp_dep = b.dependency("esp", .{});
    const esp_root = esp_dep.path("");
    const extra_component_dirs = opts.extra_component_dirs;

    const board_profile_name = deriveBoardProfileName(build_config);
    const chip = deriveChipFromBuildConfig(b, app_root, build_config);
    const sdkconfig_output_file = joinPath(b, build_dir, "sdkconfig.generated");
    const partition_file_name = b.fmt(
        "partitions.generated.{x}.csv",
        .{std.hash.Wyhash.hash(0, board_profile_name)},
    );
    const generated_partition_file = joinPath(b, build_dir, partition_file_name);
    const project_rel_dir = joinPath(b, build_dir, "idf_project");
    const project_main_rel_dir = joinPath(b, project_rel_dir, "main");
    const zig_entry_library_rel_file = joinPath(b, project_main_rel_dir, "zig_entry.a");
    const zig_entry_library_name = "zig_entry.a";
    const resolved_target = resolveChipTarget(b, chip);
    const toolchain_sysroot = resolveToolchainSysroot(b, chip);
    const build_options_root = createBuildOptionsRootSource(b, opts.build_options);
    const embed_dep = esp_dep.builder.dependency(
        "embed_zig",
        opts.embed_links.withBuildOptions(resolved_target, opts.optimize),
    );
    const embed_link_artifact = embed_dep.artifact("embed_link");
    if (toolchain_sysroot) |sysroot| {
        embed_dep.builder.sysroot = sysroot.root;
        addSystemIncludePathToCompileDependencies(embed_link_artifact, sysroot.include_dir);
    }
    const extra_archives = collectExtraZigArchives(b, embed_link_artifact);
    const extra_archive_names = archiveNames(b, extra_archives);

    const sdkconfig_step = registerSdkconfigStep(
        b,
        app_name,
        app_root,
        .{
            .output_file = sdkconfig_output_file,
            .partition_file = generated_partition_file,
            .partition_file_for_idf = b.fmt("../{s}", .{partition_file_name}),
            .build_config = build_config,
        },
        esp_dep,
        build_options_root,
        expose_prefixed_steps,
    );

    const project_step = registerExternalProjectScaffoldStep(
        b,
        app_name,
        app_root,
        project_rel_dir,
        zig_entry_library_name,
        extra_archive_names,
        esp_dep,
        expose_prefixed_steps,
    );

    const zig_entry_library_step = registerExternalZigLibraryStep(
        b,
        app_name,
        app_root,
        app_entry,
        zig_entry_library_rel_file,
        opts.optimize,
        chip,
        esp_dep,
        build_config,
        bsp_file,
        build_options_root,
        expose_prefixed_steps,
        opts.extra_zig_modules,
        embed_dep,
        toolchain_sysroot,
    );
    zig_entry_library_step.dependOn(project_step);

    const extra_archive_steps = relayExtraZigArchives(
        b,
        app_root,
        project_main_rel_dir,
        extra_archives,
        project_step,
    );

    const app_main_step = registerAppMainGenerationStep(
        b,
        app_name,
        app_root,
        .{
            .output_file = joinPath(b, project_main_rel_dir, "app_main.generated.c"),
            .delegate_symbol = entry_symbol,
        },
        esp_root,
        expose_prefixed_steps,
    );
    app_main_step.dependOn(project_step);

    const runtime = RuntimeOptions{
        .port = external_runtime.port,
        .timeout = external_runtime.timeout,
    };

    const sdkconfig_arg = "../sdkconfig.generated";
    const idf_build_arg = "../idf";
    const idf_project_dir = joinPath(b, app_root, project_rel_dir);

    const reconfigure_cmd = addIdfPyBaseCommandWithEnv(
        b,
        runtime,
        idf_project_dir,
        sdkconfig_arg,
        board_profile_name,
        idf_build_arg,
        extra_component_dirs,
        external_runtime.esp_idf,
        esp_root,
    );
    reconfigure_cmd.addArg("reconfigure");
    if (external_runtime.esp_idf == null) {
        const required_env_check_run = registerRequiredEnvCheckStepWithRoot(
            b,
            app_name,
            esp_root,
        );
        reconfigure_cmd.step.dependOn(&required_env_check_run.step);
    }
    reconfigure_cmd.step.dependOn(sdkconfig_step);
    reconfigure_cmd.step.dependOn(project_step);
    reconfigure_cmd.step.dependOn(app_main_step);
    for (extra_archive_steps) |step| {
        reconfigure_cmd.step.dependOn(step);
    }

    const configure_step: *std.Build.Step = if (expose_prefixed_steps) blk: {
        const step = b.step(
            b.fmt("{s}-configure", .{app_name}),
            b.fmt("Run idf.py reconfigure for {s}", .{app_name}),
        );
        step.dependOn(&reconfigure_cmd.step);
        break :blk step;
    } else &reconfigure_cmd.step;

    const idf_build_cmd = addIdfPyBaseCommandWithEnv(
        b,
        runtime,
        idf_project_dir,
        sdkconfig_arg,
        board_profile_name,
        idf_build_arg,
        extra_component_dirs,
        external_runtime.esp_idf,
        esp_root,
    );
    idf_build_cmd.addArg("build");
    idf_build_cmd.step.dependOn(&reconfigure_cmd.step);
    idf_build_cmd.step.dependOn(zig_entry_library_step);
    for (extra_archive_steps) |step| {
        idf_build_cmd.step.dependOn(step);
    }

    const idf_build_step: *std.Build.Step = if (expose_prefixed_steps) blk: {
        const step = b.step(
            b.fmt("{s}-idf-build", .{app_name}),
            b.fmt("Run idf.py build for {s}", .{app_name}),
        );
        step.dependOn(&idf_build_cmd.step);
        break :blk step;
    } else &idf_build_cmd.step;

    const build_step: *std.Build.Step = if (expose_prefixed_steps) blk: {
        const step = b.step(
            app_name,
            b.fmt("Build {s} example", .{app_name}),
        );
        step.dependOn(&idf_build_cmd.step);
        break :blk step;
    } else &idf_build_cmd.step;

    const flash_cmd = addIdfPyBaseCommandWithEnv(
        b,
        runtime,
        idf_project_dir,
        sdkconfig_arg,
        board_profile_name,
        idf_build_arg,
        extra_component_dirs,
        external_runtime.esp_idf,
        esp_root,
    );
    addExternalSerialArgs(flash_cmd, external_runtime.port);
    flash_cmd.addArg("flash");
    flash_cmd.step.dependOn(&idf_build_cmd.step);

    const data_partition_flash_step = registerExternalDataPartitionFlashStep(
        b,
        app_name,
        app_root,
        build_dir,
        build_config,
        external_runtime.port,
        external_runtime.esp_idf,
        esp_root,
        build_options_root,
        expose_prefixed_steps,
    );
    data_partition_flash_step.dependOn(&idf_build_cmd.step);
    data_partition_flash_step.dependOn(&flash_cmd.step);

    const flash_step: *std.Build.Step = if (expose_prefixed_steps) blk: {
        const step = b.step(
            b.fmt("{s}-flash", .{app_name}),
            b.fmt("Flash {s} with idf.py", .{app_name}),
        );
        step.dependOn(data_partition_flash_step);
        break :blk step;
    } else data_partition_flash_step;

    const monitor_cmd = addIdfPyMonitorCommandWithEnv(
        b,
        runtime,
        idf_project_dir,
        sdkconfig_arg,
        board_profile_name,
        idf_build_arg,
        extra_component_dirs,
        esp_root,
        false,
        external_runtime.esp_idf,
    );
    monitor_cmd.step.dependOn(&idf_build_cmd.step);

    const monitor_step: *std.Build.Step = if (expose_prefixed_steps) blk: {
        const step = b.step(
            b.fmt("{s}-monitor", .{app_name}),
            b.fmt("Monitor {s} with idf.py", .{app_name}),
        );
        step.dependOn(&monitor_cmd.step);
        break :blk step;
    } else &monitor_cmd.step;

    const flash_monitor_cmd = addIdfPyMonitorCommandWithEnv(
        b,
        runtime,
        idf_project_dir,
        sdkconfig_arg,
        board_profile_name,
        idf_build_arg,
        extra_component_dirs,
        esp_root,
        true,
        external_runtime.esp_idf,
    );
    flash_monitor_cmd.step.dependOn(&idf_build_cmd.step);

    const flash_monitor_step: *std.Build.Step = if (expose_prefixed_steps) blk: {
        const step = b.step(
            b.fmt("{s}-flash-monitor", .{app_name}),
            b.fmt("Flash and monitor {s} with idf.py", .{app_name}),
        );
        step.dependOn(&flash_monitor_cmd.step);
        break :blk step;
    } else &flash_monitor_cmd.step;

    exposeAliasStep(
        b,
        "build",
        "Build firmware (-Dbuild_config=<path>, optional -Dbsp=<path>, -Dbuild_dir=build)",
        build_step,
    );
    exposeAliasStep(
        b,
        "generate-sdkconfig",
        "Generate sdkconfig (-Dbuild_config=<path>, optional -Dbsp=<path>, -Dbuild_dir=build)",
        sdkconfig_step,
    );
    exposeAliasStep(
        b,
        "flash",
        "Flash firmware (-Dbuild_config=<path>, optional -Dbsp=<path>, -Desp_idf=/path/to/esp-idf, -Dport=/dev/cu.xxx)",
        flash_step,
    );
    exposeAliasStep(
        b,
        "monitor",
        "Monitor serial output (-Dbuild_config=<path>, optional -Dbsp=<path>, -Desp_idf=/path/to/esp-idf, -Dport=/dev/cu.xxx, -Dtimeout=15)",
        monitor_step,
    );
    exposeAliasStep(
        b,
        "flash-monitor",
        "Flash and monitor (-Dbuild_config=<path>, optional -Dbsp=<path>, -Desp_idf=/path/to/esp-idf, -Dport=/dev/cu.xxx, -Dtimeout=15)",
        flash_monitor_step,
    );

    return .{
        .build_step = build_step,
        .sdkconfig_step = sdkconfig_step,
        .app_main_step = app_main_step,
        .configure_step = configure_step,
        .idf_build_step = idf_build_step,
        .flash_step = flash_step,
        .monitor_step = monitor_step,
        .flash_monitor_step = flash_monitor_step,
    };
}

const RelayedArchive = struct {
    file_name: []const u8,
    compile: *std.Build.Step.Compile,
};

fn collectExtraZigArchives(
    b: *std.Build,
    root: *std.Build.Step.Compile,
) []const RelayedArchive {
    const deps = root.getCompileDependencies(false);
    var count: usize = 0;
    for (deps[1..]) |dep| {
        if (dep.isStaticLibrary()) count += 1;
    }

    const archives = b.allocator.alloc(RelayedArchive, count) catch @panic("OOM");
    var idx: usize = 0;
    for (deps[1..]) |dep| {
        if (!dep.isStaticLibrary()) continue;
        archives[idx] = .{
            .file_name = b.fmt("zig_dep_{s}.a", .{dep.name}),
            .compile = dep,
        };
        idx += 1;
    }
    return archives;
}

fn archiveNames(
    b: *std.Build,
    archives: []const RelayedArchive,
) []const []const u8 {
    const names = b.allocator.alloc([]const u8, archives.len) catch @panic("OOM");
    for (archives, 0..) |archive, idx| {
        names[idx] = archive.file_name;
    }
    return names;
}

fn addSystemIncludePathToCompileDependencies(
    root: *std.Build.Step.Compile,
    include_dir: std.Build.LazyPath,
) void {
    for (root.getCompileDependencies(false)) |compile| {
        addSystemIncludePathToGraph(compile.root_module, include_dir);
    }
}

fn relayExtraZigArchives(
    b: *std.Build,
    app_root: []const u8,
    project_main_rel_dir: []const u8,
    archives: []const RelayedArchive,
    project_step: *std.Build.Step,
) []const *std.Build.Step {
    const steps = b.allocator.alloc(*std.Build.Step, archives.len) catch @panic("OOM");
    for (archives, 0..) |archive, idx| {
        const copy = b.addSystemCommand(&.{ "cp", "-f" });
        copy.addFileArg(archive.compile.getEmittedBin());
        copy.addArg(joinPath(b, app_root, joinPath(b, project_main_rel_dir, archive.file_name)));
        copy.step.dependOn(project_step);
        steps[idx] = &copy.step;
    }
    return steps;
}

fn registerAppMainGenerationStep(
    b: *std.Build,
    app_name: []const u8,
    app_dir: []const u8,
    options: AutoAppMainOptions,
    esp_root: ?std.Build.LazyPath,
    expose_named_step: bool,
) *std.Build.Step {
    const generator_root_module = b.createModule(.{
        .root_source_file = espPath(b, esp_root, "src/idf/build/generate_app_main.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });

    const generator = b.addExecutable(.{
        .name = b.fmt("{s}_app_main_generator", .{app_name}),
        .root_module = generator_root_module,
    });

    const run_generator = b.addRunArtifact(generator);
    run_generator.setCwd(b.path(app_dir));
    run_generator.addArg(options.output_file);
    run_generator.addArg(options.delegate_symbol);

    if (expose_named_step) {
        const app_main_step = b.step(
            b.fmt("{s}-gen-main-c", .{app_name}),
            b.fmt("Generate app_main C shim for {s}", .{app_name}),
        );
        app_main_step.dependOn(&run_generator.step);
        return app_main_step;
    }
    return &run_generator.step;
}

fn registerSdkconfigStep(
    b: *std.Build,
    app_name: []const u8,
    app_dir: []const u8,
    options: SdkconfigOptions,
    esp_dep: *std.Build.Dependency,
    build_options_root: ?std.Build.LazyPath,
    expose_named_step: bool,
) *std.Build.Step {
    const idf_mod = esp_dep.module("idf");
    const build_options_mod = if (build_options_root) |root| b.createModule(.{
        .root_source_file = root,
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    }) else null;

    const board_root = joinPath(b, app_dir, options.build_config);
    const app_board_import_count: usize = if (build_options_mod != null) 2 else 1;
    const app_board_imports = b.allocator.alloc(std.Build.Module.Import, app_board_import_count) catch @panic("OOM");
    app_board_imports[0] = .{ .name = "idf", .module = idf_mod };
    if (build_options_mod) |mod| {
        app_board_imports[1] = .{ .name = "build_options", .module = mod };
    }
    const app_board_module = b.createModule(.{
        .root_source_file = b.path(board_root),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = app_board_imports,
    });

    const generator_root_module = b.createModule(.{
        .root_source_file = esp_dep.path("src/idf/sdkconfig/generator.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = &.{
            .{ .name = "app_sdkconfig_profile", .module = app_board_module },
            .{ .name = "idf", .module = idf_mod },
        },
    });

    const generator = b.addExecutable(.{
        .name = b.fmt("{s}_sdkconfig_generator", .{app_name}),
        .root_module = generator_root_module,
    });

    const run_generator = b.addRunArtifact(generator);
    run_generator.setCwd(b.path(app_dir));
    run_generator.addArg(options.output_file);
    run_generator.addArg(options.partition_file);
    run_generator.addArg(options.partition_file_for_idf orelse options.partition_file);

    if (expose_named_step) {
        const sdkconfig_step = b.step(
            b.fmt("{s}-sdkconfig", .{app_name}),
            b.fmt("Generate final sdkconfig for {s}", .{app_name}),
        );
        sdkconfig_step.dependOn(&run_generator.step);
        return sdkconfig_step;
    }
    return &run_generator.step;
}

fn registerExternalProjectScaffoldStep(
    b: *std.Build,
    app_name: []const u8,
    app_root: []const u8,
    project_dir: []const u8,
    zig_entry_library_name: []const u8,
    extra_library_names: []const []const u8,
    esp_dep: *std.Build.Dependency,
    expose_named_step: bool,
) *std.Build.Step {
    const idf_mod = esp_dep.module("idf");

    const generator_root_module = b.createModule(.{
        .root_source_file = esp_dep.path("src/idf/build/generate_external_project.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = &.{
            .{ .name = "idf", .module = idf_mod },
        },
    });

    const generator = b.addExecutable(.{
        .name = b.fmt("{s}_idf_project_generator", .{app_name}),
        .root_module = generator_root_module,
    });

    const run_generator = b.addRunArtifact(generator);
    run_generator.setCwd(b.path(app_root));
    run_generator.addArg(project_dir);
    run_generator.addArg(app_name);
    run_generator.addArg(zig_entry_library_name);
    for (extra_library_names) |name| {
        run_generator.addArg(name);
    }

    if (expose_named_step) {
        const project_step = b.step(
            b.fmt("{s}-gen-idf-project", .{app_name}),
            b.fmt("Generate temporary IDF project for {s}", .{app_name}),
        );
        project_step.dependOn(&run_generator.step);
        return project_step;
    }
    return &run_generator.step;
}

const ChipTarget = struct {
    name: []const u8,
    cpu_arch: std.Target.Cpu.Arch,
    cpu_model: std.Target.Query.CpuModel,
    supported: bool,
};

const chip_targets = [_]ChipTarget{
    .{ .name = "esp32", .cpu_arch = .xtensa, .cpu_model = .{ .explicit = &std.Target.xtensa.cpu.esp32 }, .supported = false },
    .{ .name = "esp32s2", .cpu_arch = .xtensa, .cpu_model = .{ .explicit = &std.Target.xtensa.cpu.esp32s2 }, .supported = false },
    .{ .name = "esp32s3", .cpu_arch = .xtensa, .cpu_model = .{ .explicit = &std.Target.xtensa.cpu.esp32s3 }, .supported = true },
    .{ .name = "esp32c3", .cpu_arch = .riscv32, .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 }, .supported = false },
    .{ .name = "esp32c6", .cpu_arch = .riscv32, .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 }, .supported = false },
    .{ .name = "esp32h2", .cpu_arch = .riscv32, .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 }, .supported = false },
    .{ .name = "esp32p4", .cpu_arch = .riscv32, .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 }, .supported = false },
};

fn resolveChipTarget(b: *std.Build, chip: []const u8) std.Build.ResolvedTarget {
    for (chip_targets) |entry| {
        if (std.mem.eql(u8, chip, entry.name)) {
            if (!entry.supported) {
                std.debug.panic("chip '{s}' is known but not yet supported", .{chip});
            }
            return b.resolveTargetQuery(.{
                .cpu_arch = entry.cpu_arch,
                .os_tag = .freestanding,
                .abi = .none,
                .cpu_model = entry.cpu_model,
            });
        }
    }
    std.debug.panic("unknown chip: '{s}'", .{chip});
}

fn registerExternalZigLibraryStep(
    b: *std.Build,
    app_name: []const u8,
    app_root: []const u8,
    source_file: []const u8,
    output_file: []const u8,
    optimize: std.builtin.OptimizeMode,
    chip: []const u8,
    esp_dep: ?*std.Build.Dependency,
    build_config_file: []const u8,
    bsp_file: ?[]const u8,
    build_options_root: ?std.Build.LazyPath,
    expose_named_step: bool,
    extra_zig_modules: []const ExtraZigModule,
    embed_dep: ?*std.Build.Dependency,
    toolchain_sysroot: ?ToolchainSysroot,
) *std.Build.Step {
    const resolved_target = resolveChipTarget(b, chip);

    const esp_mod = if (esp_dep) |dep| dep.module("esp") else @panic("registerExternalZigLibraryStep requires esp dependency");
    const idf_mod = if (esp_dep) |dep| dep.module("idf") else @panic("registerExternalZigLibraryStep requires esp dependency");
    const build_options_mod = if (build_options_root) |root| b.createModule(.{
        .root_source_file = root,
        .target = resolved_target,
        .optimize = optimize,
    }) else null;
    if (embed_dep) |dep| {
        esp_mod.addImport("embed", dep.module("embed"));
    }

    const build_config_path = joinPath(b, app_root, build_config_file);
    const build_config_import_count: usize = if (build_options_mod != null) 2 else 1;
    const build_config_imports = b.allocator.alloc(std.Build.Module.Import, build_config_import_count) catch @panic("OOM");
    build_config_imports[0] = .{ .name = "idf", .module = idf_mod };
    if (build_options_mod) |mod| {
        build_config_imports[1] = .{ .name = "build_options", .module = mod };
    }
    const build_config_mod = b.createModule(.{
        .root_source_file = b.path(build_config_path),
        .target = resolved_target,
        .optimize = optimize,
        .imports = build_config_imports,
    });

    const board_mod = if (bsp_file) |bf| blk: {
        const board_import_count: usize = 3 + (if (build_options_mod != null) @as(usize, 1) else 0);
        const board_imports = b.allocator.alloc(std.Build.Module.Import, board_import_count) catch @panic("OOM");
        board_imports[0] = .{ .name = "esp", .module = esp_mod };
        board_imports[1] = .{ .name = "idf", .module = idf_mod };
        board_imports[2] = .{ .name = "build_config", .module = build_config_mod };
        if (build_options_mod) |mod| {
            board_imports[3] = .{ .name = "build_options", .module = mod };
        }
        break :blk b.createModule(.{
            .root_source_file = b.path(joinPath(b, app_root, bf)),
            .target = resolved_target,
            .optimize = optimize,
            .imports = board_imports,
        });
    } else build_config_mod;

    const base_count: usize = 4 + (if (build_options_mod != null) @as(usize, 1) else 0);
    const total_imports = base_count + extra_zig_modules.len;

    const imports = b.allocator.alloc(std.Build.Module.Import, total_imports) catch @panic("OOM");
    var idx: usize = 0;

    imports[idx] = .{ .name = "esp", .module = esp_mod };
    idx += 1;
    imports[idx] = .{ .name = "idf", .module = idf_mod };
    idx += 1;
    imports[idx] = .{ .name = "build_config", .module = build_config_mod };
    idx += 1;
    imports[idx] = .{ .name = "board", .module = board_mod };
    idx += 1;
    if (build_options_mod) |mod| {
        imports[idx] = .{ .name = "build_options", .module = mod };
        idx += 1;
    }

    const resolved_extra = resolveAllExtraModules(b, esp_mod, idf_mod, extra_zig_modules, resolved_target, optimize);
    for (extra_zig_modules, 0..) |_, ei| {
        imports[idx] = .{ .name = extra_zig_modules[ei].name, .module = resolved_extra[ei] };
        idx += 1;
    }

    const entry_path = joinPath(b, app_root, source_file);
    const app_root_module = b.createModule(.{
        .root_source_file = b.path(entry_path),
        .target = resolved_target,
        .optimize = optimize,
        .imports = imports[0..idx],
    });
    if (toolchain_sysroot) |sysroot| {
        addSystemIncludePathToGraph(app_root_module, sysroot.include_dir);
    }

    const obj = b.addObject(.{
        .name = app_name,
        .root_module = app_root_module,
    });

    const output_path = joinPath(b, app_root, output_file);

    const ar = b.addSystemCommand(&.{"zig"});
    ar.addArg("ar");
    ar.addArg("rcs");
    ar.addArg(output_path);
    ar.addFileArg(obj.getEmittedBin());
    ar.setCwd(b.path("."));

    if (expose_named_step) {
        const step = b.step(
            b.fmt("{s}-zig-lib", .{app_name}),
            b.fmt("Build target Zig static library for {s}", .{app_name}),
        );
        step.dependOn(&ar.step);
        return step;
    }
    return &ar.step;
}

fn resolveAllExtraModules(
    b: *std.Build,
    esp_mod: *std.Build.Module,
    idf_mod: *std.Build.Module,
    all_extra: []const ExtraZigModule,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) []*std.Build.Module {
    const resolved = b.allocator.alloc(*std.Build.Module, all_extra.len) catch @panic("OOM");

    for (all_extra, 0..) |mod, i| {
        resolved[i] = b.createModule(.{
            .root_source_file = mod.path,
            .target = target,
            .optimize = optimize,
        });
    }

    for (0..all_extra.len) |i| {
        resolved[i].addImport("esp", esp_mod);
        resolved[i].addImport("idf", idf_mod);
        for (all_extra, 0..) |other, j| {
            resolved[i].addImport(other.name, resolved[j]);
        }
    }

    return resolved;
}

fn createBuildOptionsRootSource(
    b: *std.Build,
    build_options: []const BuildOption,
) ?std.Build.LazyPath {
    if (build_options.len == 0) return null;

    const opts = b.addOptions();
    for (build_options) |entry| {
        switch (entry.value) {
            .string => |value| opts.addOption([]const u8, entry.name, value),
            .boolean => |value| opts.addOption(bool, entry.name, value),
            .i64 => |value| opts.addOption(i64, entry.name, value),
            .u32 => |value| opts.addOption(u32, entry.name, value),
        }
    }
    return opts.createModule().root_source_file.?;
}

fn addSystemIncludePathToGraph(root: *std.Build.Module, include_dir: std.Build.LazyPath) void {
    for (root.getGraph().modules) |mod| {
        mod.addSystemIncludePath(include_dir);
    }
}

fn zigOptimizeFlag(optimize: std.builtin.OptimizeMode) []const u8 {
    return switch (optimize) {
        .Debug => "-ODebug",
        .ReleaseSafe => "-OReleaseSafe",
        .ReleaseFast => "-OReleaseFast",
        .ReleaseSmall => "-OReleaseSmall",
    };
}

fn resolveIdfModule(b: *std.Build, options: RegisterOptions) *std.Build.Module {
    if (options.idf_module) |module| {
        return module;
    }

    const root_source: ?[]const u8 = if (options.idf_root_source) |source|
        source
    else if (options.esp_root != null)
        @as([]const u8, "src/esp_mod.zig")
    else
        null;

    if (root_source) |source| {
        const idf_mod = b.createModule(.{
            .root_source_file = espPath(b, options.esp_root, "src/idf_mod.zig"),
            .target = options.target,
            .optimize = options.optimize,
        });

        return b.createModule(.{
            .root_source_file = espPath(b, options.esp_root, source),
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = options.link_libc,
            .imports = &.{
                .{ .name = "idf", .module = idf_mod },
            },
        });
    }

    @panic("registerAppWorkflow requires idf_module, idf_root_source, or esp_root");
}

fn buildAppImports(
    b: *std.Build,
    idf_module: *std.Build.Module,
    app_options_module: ?*std.Build.Module,
) []const std.Build.Module.Import {
    if (app_options_module) |module| {
        const imports = b.allocator.alloc(std.Build.Module.Import, 2) catch @panic("OOM allocating app imports");
        imports[0] = .{ .name = "idf", .module = idf_module };
        imports[1] = .{ .name = "app_options", .module = module };
        return imports;
    }

    const imports = b.allocator.alloc(std.Build.Module.Import, 1) catch @panic("OOM allocating app imports");
    imports[0] = .{ .name = "idf", .module = idf_module };
    return imports;
}

fn addIdfPyBaseCommand(
    b: *std.Build,
    runtime: RuntimeOptions,
    app_dir: []const u8,
    sdkconfig_file: ?[]const u8,
    board_profile_name: ?[]const u8,
    idf_build_dir: ?[]const u8,
    extra_component_dirs: []const std.Build.LazyPath,
) *std.Build.Step.Run {
    return addIdfPyBaseCommandWithEnv(b, runtime, app_dir, sdkconfig_file, board_profile_name, idf_build_dir, extra_component_dirs, null, null);
}

fn addIdfPyBaseCommandWithEnv(
    b: *std.Build,
    runtime: RuntimeOptions,
    app_dir: []const u8,
    sdkconfig_file: ?[]const u8,
    board_profile_name: ?[]const u8,
    idf_build_dir: ?[]const u8,
    extra_component_dirs: []const std.Build.LazyPath,
    esp_idf: ?[]const u8,
    esp_root: ?std.Build.LazyPath,
) *std.Build.Step.Run {
    _ = runtime;
    const cmd = if (esp_idf) |idf_root| blk: {
        const c = b.addSystemCommand(&.{"bash"});
        c.addFileArg(espPath(b, esp_root, "src/idf/build/idf_env_wrapper.sh"));
        c.addArg(idf_root);
        c.addArg("python3");
        break :blk c;
    } else b.addSystemCommand(&.{"python3"});
    cmd.setCwd(b.path(app_dir));
    cmd.addArg(idfPyExecutable(b, esp_idf));
    if (idf_build_dir) |build_dir| {
        cmd.addArgs(&.{ "-B", build_dir });
    }
    if (sdkconfig_file) |file_name| {
        cmd.addArg(b.fmt("-DSDKCONFIG={s}", .{file_name}));
        cmd.setEnvironmentVariable("SDKCONFIG", file_name);
    }
    if (board_profile_name) |board_name| {
        cmd.setEnvironmentVariable("ESPZ_BOARD_PROFILE", board_name);
    }
    addExtraComponentDirsArg(cmd, extra_component_dirs);
    return cmd;
}

fn addIdfPyMonitorCommand(
    b: *std.Build,
    runtime: RuntimeOptions,
    app_dir: []const u8,
    sdkconfig_file: ?[]const u8,
    board_profile_name: ?[]const u8,
    idf_build_dir: ?[]const u8,
    extra_component_dirs: []const std.Build.LazyPath,
    esp_root: ?std.Build.LazyPath,
    include_flash: bool,
) *std.Build.Step.Run {
    return addIdfPyMonitorCommandWithEnv(b, runtime, app_dir, sdkconfig_file, board_profile_name, idf_build_dir, extra_component_dirs, esp_root, include_flash, null);
}

fn addIdfPyMonitorCommandWithEnv(
    b: *std.Build,
    runtime: RuntimeOptions,
    app_dir: []const u8,
    sdkconfig_file: ?[]const u8,
    board_profile_name: ?[]const u8,
    idf_build_dir: ?[]const u8,
    extra_component_dirs: []const std.Build.LazyPath,
    esp_root: ?std.Build.LazyPath,
    include_flash: bool,
    esp_idf: ?[]const u8,
) *std.Build.Step.Run {
    const cmd = if (esp_idf) |idf_root| blk: {
        const c = b.addSystemCommand(&.{"bash"});
        c.addFileArg(espPath(b, esp_root, "src/idf/build/idf_env_wrapper.sh"));
        c.addArg(idf_root);
        c.addArg("python3");
        break :blk c;
    } else b.addSystemCommand(&.{"python3"});
    cmd.setCwd(b.path(app_dir));
    cmd.addFileArg(espPath(b, esp_root, "src/idf/build/pty_monitor.py"));
    if (runtime.timeout) |t| {
        cmd.addArg(b.fmt("--timeout={d}", .{t}));
    }
    cmd.addArg("python3");
    cmd.addArg(idfPyExecutable(b, esp_idf));

    if (idf_build_dir) |build_dir| {
        cmd.addArgs(&.{ "-B", build_dir });
    }
    if (sdkconfig_file) |file_name| {
        cmd.addArg(b.fmt("-DSDKCONFIG={s}", .{file_name}));
        cmd.setEnvironmentVariable("SDKCONFIG", file_name);
    }
    if (board_profile_name) |board_name| {
        cmd.setEnvironmentVariable("ESPZ_BOARD_PROFILE", board_name);
    }
    addExtraComponentDirsArg(cmd, extra_component_dirs);

    addSerialArgs(cmd, runtime);
    if (include_flash) {
        cmd.addArg("flash");
    }
    cmd.addArg("monitor");
    return cmd;
}

fn registerRequiredEnvCheckStep(b: *std.Build, app_name: []const u8) *std.Build.Step.Run {
    const checker_root_module = b.createModule(.{
        .root_source_file = b.path("src/idf/build/check_required_env.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });

    const checker = b.addExecutable(.{
        .name = b.fmt("{s}_check_required_env", .{app_name}),
        .root_module = checker_root_module,
    });

    return b.addRunArtifact(checker);
}

fn registerRequiredEnvCheckStepWithRoot(
    b: *std.Build,
    app_name: []const u8,
    esp_root: ?std.Build.LazyPath,
) *std.Build.Step.Run {
    const checker_root_module = b.createModule(.{
        .root_source_file = espPath(b, esp_root, "src/idf/build/check_required_env.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });

    const checker = b.addExecutable(.{
        .name = b.fmt("{s}_check_required_env", .{app_name}),
        .root_module = checker_root_module,
    });

    return b.addRunArtifact(checker);
}

fn addSerialArgs(cmd: *std.Build.Step.Run, runtime: RuntimeOptions) void {
    if (runtime.port) |port| {
        cmd.addArgs(&.{ "-p", port });
    }
}

fn addExternalSerialArgs(cmd: *std.Build.Step.Run, port: ?[]const u8) void {
    if (port) |value| {
        cmd.addArgs(&.{ "-p", value });
    }
}

fn idfPyExecutable(b: *std.Build, esp_idf: ?[]const u8) []const u8 {
    return if (esp_idf) |root| idfPyPath(b, root) else "idf.py";
}

fn registerExternalDataPartitionFlashStep(
    b: *std.Build,
    app_name: []const u8,
    app_root: []const u8,
    build_dir: []const u8,
    build_config_file: []const u8,
    port: ?[]const u8,
    esp_idf: ?[]const u8,
    esp_root: ?std.Build.LazyPath,
    build_options_root: ?std.Build.LazyPath,
    expose_named_step: bool,
) *std.Build.Step {
    const esp_dep = b.dependency("esp", .{});
    const idf_mod = esp_dep.module("idf");
    const build_config_path = joinPath(b, app_root, build_config_file);
    const build_options_mod = if (build_options_root) |root| b.createModule(.{
        .root_source_file = root,
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    }) else null;

    const build_config_import_count: usize = if (build_options_mod != null) 2 else 1;
    const build_config_imports = b.allocator.alloc(std.Build.Module.Import, build_config_import_count) catch @panic("OOM");
    build_config_imports[0] = .{ .name = "idf", .module = idf_mod };
    if (build_options_mod) |mod| {
        build_config_imports[1] = .{ .name = "build_options", .module = mod };
    }
    const build_config_mod = b.createModule(.{
        .root_source_file = b.path(build_config_path),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = build_config_imports,
    });

    const tool_root = b.createModule(.{
        .root_source_file = esp_dep.path("src/idf/build/data_partitions.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = &.{
            .{ .name = "idf", .module = idf_mod },
            .{ .name = "build_config", .module = build_config_mod },
        },
    });
    const tool = b.addExecutable(.{
        .name = b.fmt("{s}_data_partitions", .{app_name}),
        .root_module = tool_root,
    });

    const run_tool = b.addRunArtifact(tool);
    run_tool.setCwd(b.path(app_root));
    run_tool.addArg("flash");
    run_tool.addArg(app_root);
    run_tool.addArg(build_dir);
    run_tool.addArg(esp_idf orelse "");
    run_tool.addFileArg(espPath(b, esp_root, "src/idf/build/idf_env_wrapper.sh"));
    run_tool.addArg(port orelse "");

    if (expose_named_step) {
        const step = b.step(
            b.fmt("{s}-data-flash", .{app_name}),
            b.fmt("Generate and flash data partitions for {s}", .{app_name}),
        );
        step.dependOn(&run_tool.step);
        return step;
    }

    return &run_tool.step;
}

fn addSpiffsgenCommand(
    b: *std.Build,
    app_root: []const u8,
    esp_idf: ?[]const u8,
    esp_root: ?std.Build.LazyPath,
    size: u32,
    source_dir: []const u8,
    output_bin: []const u8,
) *std.Build.Step.Run {
    const spiffsgen_path = if (esp_idf) |idf_root|
        b.pathJoin(&.{ idf_root, "components", "spiffs", "spiffsgen.py" })
    else
        @panic("addSpiffsgenCommand requires esp_idf");

    const cmd = if (esp_idf) |idf_root| blk: {
        const c = b.addSystemCommand(&.{"bash"});
        c.addFileArg(espPath(b, esp_root, "src/idf/build/idf_env_wrapper.sh"));
        c.addArg(idf_root);
        c.addArg("python3");
        break :blk c;
    } else blk: {
        const c = b.addSystemCommand(&.{"python3"});
        break :blk c;
    };
    cmd.setCwd(b.path(app_root));
    cmd.addArg(spiffsgen_path);
    cmd.addArg(b.fmt("0x{x}", .{size}));
    cmd.addArg(source_dir);
    cmd.addArg(output_bin);
    cmd.addArgs(&.{ "--page-size", "256", "--block-size", "4096" });
    return cmd;
}

fn addEsptoolWriteFlash(
    b: *std.Build,
    app_root: []const u8,
    esp_idf: ?[]const u8,
    esp_root: ?std.Build.LazyPath,
    port: ?[]const u8,
    offset: u32,
    bin_path: []const u8,
) *std.Build.Step.Run {
    const cmd = if (esp_idf) |idf_root| blk: {
        const c = b.addSystemCommand(&.{"bash"});
        c.addFileArg(espPath(b, esp_root, "src/idf/build/idf_env_wrapper.sh"));
        c.addArg(idf_root);
        c.addArg("python3");
        c.addArg("-m");
        c.addArg("esptool");
        break :blk c;
    } else blk: {
        const c = b.addSystemCommand(&.{ "python3", "-m", "esptool" });
        break :blk c;
    };
    cmd.setCwd(b.path(app_root));
    if (port) |p| {
        cmd.addArgs(&.{ "--port", p });
    }
    cmd.addArg("write_flash");
    cmd.addArg(b.fmt("0x{x}", .{offset}));
    cmd.addArg(bin_path);
    return cmd;
}

fn exposeAliasStep(
    b: *std.Build,
    alias_name: []const u8,
    description: []const u8,
    dependency: *std.Build.Step,
) void {
    const alias_step = b.step(alias_name, description);
    alias_step.dependOn(dependency);
}

fn addExtraComponentDirsArg(cmd: *std.Build.Step.Run, extra_component_dirs: []const std.Build.LazyPath) void {
    if (extra_component_dirs.len == 0) {
        return;
    }

    const resolved = cmd.step.owner.allocator.alloc([]const u8, extra_component_dirs.len) catch @panic("OOM");
    for (extra_component_dirs, 0..) |lazy, idx| {
        resolved[idx] = lazy.getPath2(cmd.step.owner, &cmd.step);
    }
    const joined = std.mem.join(cmd.step.owner.allocator, ";", resolved) catch @panic("OOM");
    cmd.addArg(cmd.step.owner.fmt("-DEXTRA_COMPONENT_DIRS={s}", .{joined}));
}

fn idfPyPath(b: *std.Build, esp_idf: []const u8) []const u8 {
    return b.pathJoin(&.{ esp_idf, "tools", "idf.py" });
}

fn joinSemicolonList(b: *std.Build, values: []const []const u8) []const u8 {
    if (values.len == 0) {
        return "";
    }
    return std.mem.join(b.allocator, ";", values) catch @panic("OOM");
}

fn deriveBoardProfileName(board_file: []const u8) []const u8 {
    const base = std.fs.path.basename(board_file);
    if (std.mem.endsWith(u8, base, ".zig")) {
        return base[0 .. base.len - 4];
    }
    return base;
}

fn deriveChipFromBuildConfig(b: *std.Build, app_root: []const u8, build_config_file: []const u8) []const u8 {
    const rel_path = joinPath(b, app_root, build_config_file);
    const path = b.pathFromRoot(rel_path);
    const source = std.fs.cwd().readFileAlloc(b.allocator, path, 1024 * 1024) catch |err| {
        std.debug.panic("failed to read build_config '{s}': {}", .{ path, err });
    };

    const board_anchor = std.mem.indexOf(u8, source, ".board = .{") orelse
        std.mem.indexOf(u8, source, "board = .{") orelse
        std.debug.panic("missing config.board in build_config '{s}'", .{path});
    const board_body = source[board_anchor..];
    const chip_anchor_rel = std.mem.indexOf(u8, board_body, ".chip") orelse
        std.mem.indexOf(u8, board_body, "chip") orelse
        std.debug.panic("missing config.board.chip in build_config '{s}'", .{path});
    const chip_body = board_body[chip_anchor_rel..];
    const quote_start = std.mem.indexOfScalar(u8, chip_body, '"') orelse
        std.debug.panic("missing quoted chip value in build_config '{s}'", .{path});
    const chip_value = chip_body[quote_start + 1 ..];
    const quote_end = std.mem.indexOfScalar(u8, chip_value, '"') orelse
        std.debug.panic("unterminated chip value in build_config '{s}'", .{path});

    return chip_value[0..quote_end];
}

fn getEnvOrNull(b: *std.Build, name: []const u8) ?[]const u8 {
    const value = std.process.getEnvVarOwned(b.allocator, name) catch return null;
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0) {
        return null;
    }
    return trimmed;
}

fn resolveToolchainSysroot(b: *std.Build, chip: []const u8) ?ToolchainSysroot {
    const arch_prefix: []const u8 = blk: {
        for (chip_targets) |entry| {
            if (std.mem.eql(u8, chip, entry.name)) {
                break :blk switch (entry.cpu_arch) {
                    .xtensa => "xtensa-esp-elf",
                    .riscv32 => "riscv32-esp-elf",
                    else => return null,
                };
            }
        }
        return null;
    };

    const idf_tools_path = getEnvOrNull(b, "IDF_TOOLS_PATH") orelse blk: {
        const home = getEnvOrNull(b, "HOME") orelse return null;
        break :blk b.pathJoin(&.{ home, ".espressif" });
    };

    const tools_dir = b.pathJoin(&.{ idf_tools_path, "tools", arch_prefix });

    var dir = std.fs.openDirAbsolute(tools_dir, .{ .iterate = true }) catch return null;
    defer dir.close();

    var iter = dir.iterate();
    const version_dir = blk: {
        while (iter.next() catch return null) |entry| {
            if (entry.kind == .directory and !std.mem.startsWith(u8, entry.name, ".")) {
                break :blk b.allocator.dupe(u8, entry.name) catch return null;
            }
        }
        return null;
    };

    const root = b.pathJoin(&.{ tools_dir, version_dir, arch_prefix, arch_prefix });
    return .{
        .root = root,
        .include_dir = .{ .cwd_relative = b.pathJoin(&.{ root, "include" }) },
    };
}

fn espPath(b: *std.Build, root: ?std.Build.LazyPath, relative: []const u8) std.Build.LazyPath {
    if (root) |lazy| {
        return lazy.path(b, relative);
    }
    return b.path(relative);
}

fn joinPath(b: *std.Build, dir_path: []const u8, child_path: []const u8) []const u8 {
    if (dir_path.len == 0 or std.mem.eql(u8, dir_path, ".")) {
        return child_path;
    }
    return b.pathJoin(&.{ dir_path, child_path });
}
