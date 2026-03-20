const std = @import("std");
const runner_options = @import("runner_options");

pub const BuildInputs = struct {
    build_config: []const u8,
    bsp: []const u8,
};

pub const ComponentTest = struct {
    module_name: []const u8,
    test_dir: []const u8,
    compile: BuildInputs,
    real: ?BuildInputs,
    golden_dir: []const u8,
};

pub const ExampleApp = struct {
    app_name: []const u8,
    app_dir: []const u8,
    inputs: BuildInputs,
};

pub const GoldenCheckResult = union(enum) {
    missing: struct {
        expected_path: []const u8,
    },
    matched,
    mismatch: struct {
        expected_path: []const u8,
        actual_path: []const u8,
    },
};

pub fn espIdfOrNull() ?[]const u8 {
    return runner_options.esp_idf;
}

pub fn portOrNull() ?[]const u8 {
    return runner_options.port;
}

pub fn timeoutOrNull() ?u32 {
    return runner_options.timeout;
}

pub fn zigExe() []const u8 {
    return runner_options.zig_exe_path;
}

pub fn fileExists(sub_path: []const u8) bool {
    var file = std.fs.cwd().openFile(sub_path, .{}) catch return false;
    defer file.close();
    return true;
}

pub fn dirExists(sub_path: []const u8) bool {
    var dir = std.fs.cwd().openDir(sub_path, .{}) catch return false;
    defer dir.close();
    return true;
}

pub fn join2(allocator: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ a, b });
}

pub fn join3(allocator: std.mem.Allocator, a: []const u8, b: []const u8, c: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ a, b, c });
}

fn isRetainedExample(name: []const u8) bool {
    return std.mem.eql(u8, name, "aec_7210_8311") or
        std.mem.eql(u8, name, "aec_7210_8311_loopback") or
        std.mem.eql(u8, name, "lcd_battery");
}

fn discoverBoardInputs(
    allocator: std.mem.Allocator,
    board_dir: []const u8,
    comptime include_compile: bool,
) !?BuildInputs {
    var dir = std.fs.cwd().openDir(board_dir, .{ .iterate = true }) catch return null;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!include_compile and std.mem.eql(u8, entry.name, "compile")) continue;
        if (include_compile and !std.mem.eql(u8, entry.name, "compile")) continue;

        const profile_dir = try join2(allocator, board_dir, entry.name);
        const build_config_abs = try join2(allocator, profile_dir, "build_config.zig");
        const bsp_abs = try join2(allocator, profile_dir, "bsp.zig");
        if (fileExists(build_config_abs) and fileExists(bsp_abs)) {
            const profile_dir_rel = try join2(allocator, "board", entry.name);
            const build_config_rel = try join2(allocator, profile_dir_rel, "build_config.zig");
            const bsp_rel = try join2(allocator, profile_dir_rel, "bsp.zig");
            return .{
                .build_config = build_config_rel,
                .bsp = bsp_rel,
            };
        }
    }
    return null;
}

pub fn discoverComponentTests(allocator: std.mem.Allocator) ![]ComponentTest {
    var list: std.ArrayList(ComponentTest) = .empty;

    var src = try std.fs.cwd().openDir("src/component", .{ .iterate = true });
    defer src.close();

    var iter = src.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;

        const module_name = try allocator.dupe(u8, entry.name);
        const module_dir = try join2(allocator, "src/component", entry.name);
        const test_dir = try join2(allocator, module_dir, "test");
        const build_file = try join2(allocator, test_dir, "build.zig");
        if (!fileExists(build_file)) continue;

        const board_dir = try join2(allocator, test_dir, "board");
        const compile_inputs = (try discoverBoardInputs(allocator, board_dir, true)) orelse continue;
        const real_inputs = try discoverBoardInputs(allocator, board_dir, false);
        const golden_dir = try join3(allocator, board_dir, "compile", "golden");

        try list.append(allocator, .{
            .module_name = module_name,
            .test_dir = test_dir,
            .compile = compile_inputs,
            .real = real_inputs,
            .golden_dir = golden_dir,
        });
    }

    return try list.toOwnedSlice(allocator);
}

pub fn discoverExampleApps(allocator: std.mem.Allocator) ![]ExampleApp {
    var list: std.ArrayList(ExampleApp) = .empty;

    var examples = std.fs.cwd().openDir("examples", .{ .iterate = true }) catch {
        return try list.toOwnedSlice(allocator);
    };
    defer examples.close();

    var iter = examples.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!isRetainedExample(entry.name)) continue;

        const app_dir = try join2(allocator, "examples", entry.name);
        const build_file = try join2(allocator, app_dir, "build.zig");
        if (!fileExists(build_file)) continue;

        const board_dir = try join2(allocator, app_dir, "board");
        const inputs = (try discoverBoardInputs(allocator, board_dir, false)) orelse continue;
        try list.append(allocator, .{
            .app_name = try allocator.dupe(u8, entry.name),
            .app_dir = app_dir,
            .inputs = inputs,
        });
    }

    return try list.toOwnedSlice(allocator);
}

pub fn runChild(allocator: std.mem.Allocator, cwd: []const u8, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd,
        .max_output_bytes = 16 * 1024 * 1024,
    });
}

pub fn printResultFailure(label: []const u8, name: []const u8, result: std.process.Child.RunResult) void {
    std.debug.print("  {s}: {s} FAILED\n", .{ label, name });
    if (result.stderr.len > 0) {
        const max_len = @min(result.stderr.len, 2048);
        std.debug.print("--- stderr ({s}/{s}) ---\n{s}\n---\n", .{ label, name, result.stderr[0..max_len] });
    }
}

pub fn verifyElfLayoutGolden(
    allocator: std.mem.Allocator,
    test_dir: []const u8,
    build_dir: []const u8,
    build_config: []const u8,
    bsp: []const u8,
    golden_dir: []const u8,
) !GoldenCheckResult {
    const expected_path = try join2(allocator, golden_dir, "elf_layout.readelf.txt");
    if (!fileExists(expected_path)) {
        return .{
            .missing = .{
                .expected_path = expected_path,
            },
        };
    }

    const argv = [_][]const u8{
        "python3",
        "test/runners/elf_layout_golden.py",
        test_dir,
        build_dir,
        build_config,
        bsp,
    };
    const result = try runChild(allocator, ".", &argv);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const ok = switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
    if (!ok) {
        if (result.stderr.len > 0) {
            const max_len = @min(result.stderr.len, 2048);
            std.debug.print("--- stderr (golden) ---\n{s}\n---\n", .{result.stderr[0..max_len]});
        }
        return error.GoldenToolFailed;
    }

    const expected = try std.fs.cwd().readFileAlloc(allocator, expected_path, std.math.maxInt(usize));
    defer allocator.free(expected);

    const expected_trimmed = std.mem.trimRight(u8, expected, "\r\n");
    const actual_trimmed = std.mem.trimRight(u8, result.stdout, "\r\n");
    if (std.mem.eql(u8, expected_trimmed, actual_trimmed)) return .matched;

    const build_root = try join2(allocator, test_dir, build_dir);
    const actual_path = try join2(allocator, build_root, "elf_layout.readelf.actual.txt");
    var file = try std.fs.cwd().createFile(actual_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(result.stdout);

    return .{
        .mismatch = .{
            .expected_path = expected_path,
            .actual_path = actual_path,
        },
    };
}
