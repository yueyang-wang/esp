const std = @import("std");
const esp = @import("esp");

const Module = std.Build.Module;
const Compile = std.Build.Step.Compile;
const BuildContext = esp.idf.BuildContext.BuildContext;
const Component = esp.idf.Component;

const default_build_config_path = "board/compile/build_config.zig";
const default_bsp_path = "board/compile/bsp.zig";

const EspZigImports = struct {
    idf: *Module,
    esp_embed: *Module,
    esp_binding: *Module,
};

const EmbedZigImports = struct {
    dep: *std.Build.Dependency,
    embed: *Module,
    context: *Module,
    net: *Module,
    sync: *Module,
    embed_std: *Module,
    integration: *Module,
    testing: *Module,
    ogg: *Module,
    ogg_artifact: *Compile,
    opus: *Module,
    opus_artifact: *Compile,
    lvgl: *Module,
    lvgl_osal: *Module,
    lvgl_artifact: *Compile,
    stb_truetype: *Module,
    stb_truetype_artifact: *Compile,
};

const EspAppContext = struct {
    build_config_module: *Module,
    context: BuildContext,
    esp_imports: EspZigImports,
};

pub fn build(b: *std.Build) void {
    const test_only = isTestOnlyInvocation();
    const host_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (test_only) {
        buildHost(b, host_target, optimize);
    } else {
        buildEsp(b, optimize);
    }
}

fn buildHost(
    b: *std.Build,
    host_target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const embed_native = importEmbedZig(b, host_target, optimize);

    const native_test_module = createNativeTestModule(b, host_target, optimize, embed_native);
    const native_tests = b.addTest(.{
        .root_module = native_test_module,
    });
    const lvgl_osal_artifact = createHostLvglOsalArtifact(
        b,
        host_target,
        optimize,
        embed_native,
    );
    embed_native.lvgl_artifact.root_module.addObject(lvgl_osal_artifact);
    native_tests.linkLibrary(embed_native.lvgl_artifact);
    const run_native_tests = b.addRunArtifact(native_tests);
    const test_step = b.step("test", "Run the host test runner");
    test_step.dependOn(&run_native_tests.step);
}

fn buildEsp(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const esp_app_context = resolveEspAppContext(b);
    const app_options_module = createAppOptionsModule(b);

    const embed_esp = importEmbedZig(b, esp_app_context.context.target, optimize);
    wireEspRuntimeImports(esp_app_context.esp_imports, embed_esp, esp_app_context.build_config_module);

    const app_root_module = createAppRootModule(
        b,
        esp_app_context.context.target,
        optimize,
        esp_app_context.esp_imports.esp_embed,
        embed_esp,
        app_options_module,
    );

    const lvgl_osal_artifact = createEspLvglOsalArtifact(
        b,
        esp_app_context.context.target,
        optimize,
        esp_app_context.esp_imports.esp_embed,
        embed_esp.lvgl_osal,
    );
    embed_esp.lvgl_artifact.root_module.addObject(lvgl_osal_artifact);

    const ogg_component = createArchiveComponent(b, "ogg", embed_esp.ogg_artifact);
    const opus_component = createArchiveComponent(b, "opus", embed_esp.opus_artifact);
    const stb_truetype_component = createArchiveComponent(b, "stb_truetype", embed_esp.stb_truetype_artifact);
    const lvgl_component = createArchiveComponent(b, "lvgl", embed_esp.lvgl_artifact);
    const esp_main_helper = createEspMainHelperComponent(b);

    const app = esp.idf.addApp(b, "embed_compat", .{
        .context = esp_app_context.context,
        .entry = .{
            .symbol = "zig_esp_main",
            .module = app_root_module,
        },
        .components = &.{ ogg_component, opus_component, lvgl_component, stb_truetype_component, esp_main_helper },
    });

    registerAppSteps(b, app);
}

fn resolveEspAppContext(b: *std.Build) EspAppContext {
    const build_config_module = createBuildConfigModule(b, b.dependency("esp", .{}).module("esp_idf"));
    const context = esp.idf.resolveBuildContext(b, .{
        .build_config = build_config_module,
    });
    applyEspSysroot(b, context);
    return .{
        .build_config_module = build_config_module,
        .context = context,
        .esp_imports = importEspZig(b),
    };
}

fn importEspZig(b: *std.Build) EspZigImports {
    const esp_idf_dep = b.dependency("esp", .{});
    const esp_dep = b.dependency("esp", .{});
    return .{
        .idf = esp_idf_dep.module("esp_idf"),
        .esp_embed = esp_dep.module("esp_embed"),
        .esp_binding = esp_dep.module("esp_binding"),
    };
}

fn importEmbedZig(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) EmbedZigImports {
    const dep = b.dependency("embed_zig", .{
        .target = target,
        .optimize = optimize,
        .ogg = true,
        .opus = true,
        .opus_config_header = b.path("opus_config.h"),
        .lvgl = true,
        .lvgl_config_header = b.path("lv_conf.h"),
        .stb_truetype = true,
    });

    return .{
        .dep = dep,
        .embed = dep.module("embed"),
        .context = dep.module("context"),
        .net = dep.module("net"),
        .sync = dep.module("sync"),
        .embed_std = dep.module("embed_std"),
        .integration = dep.module("integration"),
        .testing = dep.module("testing"),
        .ogg = dep.module("ogg"),
        .ogg_artifact = dep.artifact("ogg"),
        .opus = dep.module("opus"),
        .opus_artifact = dep.artifact("opus"),
        .lvgl = dep.module("lvgl"),
        .lvgl_osal = dep.module("lvgl_osal"),
        .lvgl_artifact = dep.artifact("lvgl"),
        .stb_truetype = dep.module("stb_truetype"),
        .stb_truetype_artifact = dep.artifact("stb_truetype"),
    };
}

fn createBuildConfigModule(b: *std.Build, idf_module: *Module) *Module {
    const build_config_path = b.option([]const u8, "build_config", "Project build_config file path") orelse
        default_build_config_path;
    _ = b.option([]const u8, "bsp", "Project BSP file path") orelse
        default_bsp_path;

    return b.createModule(.{
        .root_source_file = b.path(build_config_path),
        .imports = &.{
            .{ .name = "esp_idf", .module = idf_module },
        },
    });
}

fn applyEspSysroot(b: *std.Build, build_ctx: BuildContext) void {
    if (build_ctx.toolchain_sysroot) |sysroot| {
        b.sysroot = sysroot.root;
    }
}

fn wireEspRuntimeImports(
    esp_imports: EspZigImports,
    embed_imports: EmbedZigImports,
    build_config_module: *Module,
) void {
    esp_imports.esp_binding.addImport("embed", embed_imports.embed);
    esp_imports.esp_binding.addImport("sync", embed_imports.sync);
    esp_imports.esp_binding.addImport("build_config", build_config_module);
    esp_imports.esp_binding.addImport("esp_idf", esp_imports.idf);

    esp_imports.esp_embed.addImport("embed", embed_imports.embed);
    esp_imports.esp_embed.addImport("context", embed_imports.context);
    esp_imports.esp_embed.addImport("net", embed_imports.net);
    esp_imports.esp_embed.addImport("sync", embed_imports.sync);
    esp_imports.esp_embed.addImport("esp_binding", esp_imports.esp_binding);
}

fn createNativeTestModule(
    b: *std.Build,
    host_target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    embed_native: EmbedZigImports,
) *Module {
    return b.createModule(.{
        .root_source_file = b.path("src/test_runner.zig"),
        .target = host_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "embed", .module = embed_native.embed },
            .{ .name = "embed_std", .module = embed_native.embed_std },
            .{ .name = "integration", .module = embed_native.integration },
            .{ .name = "context", .module = embed_native.context },
            .{ .name = "lvgl", .module = embed_native.lvgl },
            .{ .name = "net", .module = embed_native.net },
            .{ .name = "sync", .module = embed_native.sync },
            .{ .name = "testing", .module = embed_native.testing },
            .{ .name = "ogg", .module = embed_native.ogg },
            .{ .name = "opus", .module = embed_native.opus },
            .{ .name = "stb_truetype", .module = embed_native.stb_truetype },
        },
    });
}

fn createAppRootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    esp_embed_module: *Module,
    embed_esp: EmbedZigImports,
    app_options_module: *Module,
) *Module {
    return b.createModule(.{
        .root_source_file = b.path("src/esp_main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_options", .module = app_options_module },
            .{ .name = "esp_embed", .module = esp_embed_module },
            .{ .name = "integration", .module = embed_esp.integration },
            .{ .name = "ogg", .module = embed_esp.ogg },
            .{ .name = "opus", .module = embed_esp.opus },
            .{ .name = "lvgl", .module = embed_esp.lvgl },
            .{ .name = "stb_truetype", .module = embed_esp.stb_truetype },
            .{ .name = "testing", .module = embed_esp.testing },
        },
    });
}

fn createAppOptionsModule(b: *std.Build) *Module {
    const wifi_ssid = b.option([]const u8, "wifi_ssid", "WiFi SSID for embed_compat ESP build") orelse
        @panic("missing -Dwifi_ssid=<ssid> for ESP build");
    const wifi_password = b.option([]const u8, "wifi_password", "WiFi password for embed_compat ESP build") orelse
        @panic("missing -Dwifi_password=<password> for ESP build");

    const write_files = b.addWriteFiles();
    const source = write_files.add("embed_compat_app_options.zig", b.fmt(
        \\pub const wifi_ssid: [*:0]const u8 = "{f}";
        \\pub const wifi_password: [*:0]const u8 = "{f}";
        \\
    , .{
        std.zig.fmtString(wifi_ssid),
        std.zig.fmtString(wifi_password),
    }));

    return b.createModule(.{
        .root_source_file = source,
    });
}

fn createHostLvglOsalArtifact(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    embed_imports: EmbedZigImports,
) *Compile {
    const impl_module = b.createModule(.{
        .root_source_file = embed_imports.dep.path("lib/embed_std/embed.zig"),
        .target = target,
        .optimize = optimize,
    });
    impl_module.addImport("embed", embed_imports.embed);

    const module = b.createModule(.{
        .root_source_file = b.path("src/lvgl_osal_host.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "embed", .module = embed_imports.embed },
            .{ .name = "lvgl_osal_impl", .module = impl_module },
            .{ .name = "lvgl_osal", .module = embed_imports.lvgl_osal },
        },
    });
    return b.addObject(.{
        .name = "lvgl_osal_host",
        .root_module = module,
    });
}

fn createEspLvglOsalArtifact(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    esp_embed_module: *Module,
    lvgl_osal_module: *Module,
) *Compile {
    const module = b.createModule(.{
        .root_source_file = b.path("src/lvgl_osal_esp.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "esp_embed", .module = esp_embed_module },
            .{ .name = "lvgl_osal", .module = lvgl_osal_module },
        },
    });
    return b.addObject(.{
        .name = "lvgl_osal_esp",
        .root_module = module,
    });
}

fn createArchiveComponent(b: *std.Build, name: []const u8, artifact: *Compile) *Component {
    const component = esp.idf.Component.create(b, .{
        .name = name,
    });
    component.addArtifact(artifact);
    return component;
}

fn createEspMainHelperComponent(b: *std.Build) *Component {
    const component = esp.idf.Component.create(b, .{
        .name = "esp_main_helper",
    });
    component.addCSourceFiles(.{
        .root = b.path("esp_main_helper"),
        .files = &.{"wifi.c"},
    });
    component.addRequire("esp_event");
    component.addRequire("esp_netif");
    component.addRequire("esp_wifi");
    component.addRequire("freertos");
    component.addRequire("nvs_flash");
    return component;
}

fn registerAppSteps(b: *std.Build, app: esp.idf.App) void {
    const build_step = b.step("build", "Build the ESP firmware");
    build_step.dependOn(app.combine_binaries);
    build_step.dependOn(app.elf_layout);
    b.default_step = build_step;

    const flash_step = b.step("flash", "Flash the ESP firmware");
    flash_step.dependOn(app.flash);

    const monitor_step = b.step("monitor", "Monitor the ESP serial output without flashing");
    monitor_step.dependOn(app.monitor);

    const flash_monitor_step = b.step("flash_monitor", "Flash the ESP firmware, then monitor serial output");
    flash_monitor_step.dependOn(app.flash_monitor);
}

fn isTestOnlyInvocation() bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const args = std.process.argsAlloc(arena.allocator()) catch return false;
    if (args.len <= 6) return false;

    var has_test = false;
    var has_esp_step = false;
    for (args[6..]) |arg| {
        if (std.mem.eql(u8, arg, "test")) {
            has_test = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "build") or
            std.mem.eql(u8, arg, "flash") or
            std.mem.eql(u8, arg, "monitor") or
            std.mem.eql(u8, arg, "flash_monitor"))
        {
            has_esp_step = true;
        }
    }
    return has_test and !has_esp_step;
}
