const std = @import("std");
const testing = std.testing;
const test_options = @import("test_options");

// ── Filesystem helpers ──

fn fileExistsIn(dir: std.fs.Dir, sub_path: []const u8) bool {
    var f = dir.openFile(sub_path, .{}) catch return false;
    f.close();
    return true;
}

fn dirHasRealFiles(parent: std.fs.Dir, name: []const u8) bool {
    var sub = parent.openDir(name, .{ .iterate = true }) catch return false;
    defer sub.close();
    var iter = sub.iterate();
    while (iter.next() catch null) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".")) continue;
        return true;
    }
    return false;
}

fn dirContainsBoardConfig(parent: std.fs.Dir, sub_path: []const u8) bool {
    var sub = parent.openDir(sub_path, .{ .iterate = true }) catch return false;
    defer sub.close();
    var iter = sub.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .directory) continue;

        var build_buf: [512]u8 = undefined;
        const build_config_path = joinPath(&build_buf, entry.name, "build_config.zig");
        if (!fileExistsIn(sub, build_config_path)) continue;

        var bsp_buf: [512]u8 = undefined;
        const bsp_path = joinPath(&bsp_buf, entry.name, "bsp.zig");
        if (fileExistsIn(sub, bsp_path)) return true;
    }
    return false;
}

fn fileContainsString(dir: std.fs.Dir, sub_path: []const u8, needle: []const u8) bool {
    var f = dir.openFile(sub_path, .{}) catch return false;
    defer f.close();
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = f.read(&buf) catch return false;
        if (n == 0) break;
        if (std.mem.indexOf(u8, buf[0..n], needle) != null) return true;
    }
    return false;
}

fn fileIsNonEmpty(dir: std.fs.Dir, sub_path: []const u8) bool {
    var f = dir.openFile(sub_path, .{}) catch return false;
    defer f.close();
    const stat = f.stat() catch return false;
    return stat.size > 0;
}

fn joinPath(buf: []u8, a: []const u8, b: []const u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}/{s}", .{ a, b }) catch @panic("path buffer overflow");
}

fn isRetainedExample(name: []const u8) bool {
    return std.mem.eql(u8, name, "aec_7210_8311") or
        std.mem.eql(u8, name, "aec_7210_8311_loopback") or
        std.mem.eql(u8, name, "lcd_battery");
}

// ── Example app discovery ──
// Walks examples/ two levels deep, returning paths relative to examples/.
// An "app" is any directory containing build.zig.

fn discoverExampleApps(allocator: std.mem.Allocator) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var examples = std.fs.cwd().openDir("examples", .{ .iterate = true }) catch
        return try list.toOwnedSlice(allocator);
    defer examples.close();

    var iter = examples.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!isRetainedExample(entry.name)) continue;

        var buf: [512]u8 = undefined;
        const build_path = joinPath(&buf, entry.name, "build.zig");
        if (fileExistsIn(examples, build_path)) {
            try list.append(allocator, try allocator.dupe(u8, entry.name));
            continue;
        }

        var sub = examples.openDir(entry.name, .{ .iterate = true }) catch continue;
        defer sub.close();
        var sub_iter = sub.iterate();
        while (try sub_iter.next()) |sub_entry| {
            if (sub_entry.kind != .directory) continue;
            var buf_rel: [512]u8 = undefined;
            const rel = joinPath(&buf_rel, entry.name, sub_entry.name);
            var buf_build: [512]u8 = undefined;
            const bp = joinPath(&buf_build, rel, "build.zig");
            if (fileExistsIn(examples, bp)) {
                try list.append(allocator, try allocator.dupe(u8, rel));
            }
        }
    }
    return try list.toOwnedSlice(allocator);
}

// ── component/<module>/ convention checks ──
// Every subdirectory under src/component/ is a component and must have:
//   1. sdkconfig.zig
//   2. esp_mod.zig
//   3. idf_mod.zig
//   4. README.md
// Component-owned test apps are optional during migration, but if present they
// must follow src/component/<module>/test/ conventions.

test "component modules: required directory structure" {
    var src = try std.fs.cwd().openDir("src/component", .{ .iterate = true });
    defer src.close();

    var fail_count: usize = 0;
    var total: usize = 0;
    var iter = src.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!dirHasRealFiles(src, entry.name)) continue;

        total += 1;

        const required_files = [_][]const u8{ "sdkconfig.zig", "esp_mod.zig", "idf_mod.zig", "README.md" };
        for (required_files) |file| {
            var buf: [512]u8 = undefined;
            const p = joinPath(&buf, entry.name, file);
            if (!fileExistsIn(src, p)) {
                std.debug.print("  MISSING: src/component/{s}/{s}\n", .{ entry.name, file });
                fail_count += 1;
            }
        }

        var test_dir_buf: [512]u8 = undefined;
        const test_dir = joinPath(&test_dir_buf, entry.name, "test");
        var test_build_buf: [512]u8 = undefined;
        const test_build = joinPath(&test_build_buf, test_dir, "build.zig");
        if (fileExistsIn(src, test_build)) {
            const required_test_files = [_][]const u8{
                "build.zig",
                "build.zig.zon",
                "src/main.zig",
                "board/compile/build_config.zig",
                "board/compile/bsp.zig",
            };
            for (required_test_files) |file| {
                var pbuf: [512]u8 = undefined;
                const p = joinPath(&pbuf, test_dir, file);
                if (!fileExistsIn(src, p)) {
                    std.debug.print("  MISSING: src/component/{s}/test/{s}\n", .{ entry.name, file });
                    fail_count += 1;
                }
            }
        }
    }
    if (fail_count > 0) {
        std.debug.print("\n{d} issue(s) found across {d} component(s)\n", .{ fail_count, total });
        return error.TestUnexpectedResult;
    }
}

test "component modules: esp_mod.zig must not contain extern fn" {
    var src = try std.fs.cwd().openDir("src/component", .{ .iterate = true });
    defer src.close();

    var fail_count: usize = 0;
    var iter = src.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!dirHasRealFiles(src, entry.name)) continue;

        var buf: [512]u8 = undefined;
        const p = joinPath(&buf, entry.name, "esp_mod.zig");
        if (fileContainsString(src, p, "extern fn")) {
            std.debug.print("  VIOLATION: src/component/{s}/esp_mod.zig contains 'extern fn' — move to a separate .zig file\n", .{entry.name});
            fail_count += 1;
        }
    }
    if (fail_count > 0) {
        std.debug.print("{d} module(s) have extern fn in esp_mod.zig\n", .{fail_count});
        return error.TestUnexpectedResult;
    }
}

// ── examples/<app>/ convention checks ──
// AGENTS.md §9: every example app needs build.zig, build.zig.zon,
// README.md, src/main.zig, and at least one board/<name>/ with build_config.zig and bsp.zig.
// AGENTS.md §7.6: no hand-written CMakeLists.txt or main/main.c.

test "examples: every app has build.zig.zon" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const apps = try discoverExampleApps(arena.allocator());
    var examples = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    defer examples.close();

    var fail_count: usize = 0;
    for (apps) |app| {
        var buf: [512]u8 = undefined;
        const p = joinPath(&buf, app, "build.zig.zon");
        if (!fileExistsIn(examples, p)) {
            std.debug.print("  MISSING: examples/{s}/build.zig.zon\n", .{app});
            fail_count += 1;
        }
    }
    if (fail_count > 0) {
        std.debug.print("{d}/{d} example(s) missing build.zig.zon\n", .{ fail_count, apps.len });
        return error.TestUnexpectedResult;
    }
}

test "examples: every app has README.md" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const apps = try discoverExampleApps(arena.allocator());
    var examples = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    defer examples.close();

    var fail_count: usize = 0;
    for (apps) |app| {
        var buf: [512]u8 = undefined;
        const p = joinPath(&buf, app, "README.md");
        if (!fileExistsIn(examples, p)) {
            std.debug.print("  MISSING: examples/{s}/README.md\n", .{app});
            fail_count += 1;
        }
    }
    if (fail_count > 0) {
        std.debug.print("{d}/{d} example(s) missing README.md\n", .{ fail_count, apps.len });
        return error.TestUnexpectedResult;
    }
}

test "examples: every app has src/main.zig" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const apps = try discoverExampleApps(arena.allocator());
    var examples = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    defer examples.close();

    var fail_count: usize = 0;
    for (apps) |app| {
        var buf: [512]u8 = undefined;
        const p = joinPath(&buf, app, "src/main.zig");
        if (!fileExistsIn(examples, p)) {
            std.debug.print("  MISSING: examples/{s}/src/main.zig\n", .{app});
            fail_count += 1;
        }
    }
    if (fail_count > 0) {
        std.debug.print("{d}/{d} example(s) missing src/main.zig\n", .{ fail_count, apps.len });
        return error.TestUnexpectedResult;
    }
}

test "examples: every app has board/<name>/build_config.zig and bsp.zig" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const apps = try discoverExampleApps(arena.allocator());
    var examples = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    defer examples.close();

    var fail_count: usize = 0;
    for (apps) |app| {
        var buf: [512]u8 = undefined;
        const board_path = joinPath(&buf, app, "board");
        if (!dirContainsBoardConfig(examples, board_path)) {
            std.debug.print("  MISSING: examples/{s}/board/<name>/{{build_config,bsp}}.zig\n", .{app});
            fail_count += 1;
        }
    }
    if (fail_count > 0) {
        std.debug.print("{d}/{d} example(s) missing board/<name>/{{build_config,bsp}}.zig\n", .{ fail_count, apps.len });
        return error.TestUnexpectedResult;
    }
}

test "examples: no app has hand-written CMakeLists.txt" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const apps = try discoverExampleApps(arena.allocator());
    var examples = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    defer examples.close();

    var fail_count: usize = 0;
    for (apps) |app| {
        var buf: [512]u8 = undefined;
        const p = joinPath(&buf, app, "CMakeLists.txt");
        if (fileExistsIn(examples, p)) {
            std.debug.print("  UNEXPECTED: examples/{s}/CMakeLists.txt should be auto-generated\n", .{app});
            fail_count += 1;
        }
    }
    if (fail_count > 0) {
        std.debug.print("{d} example(s) have hand-written CMakeLists.txt\n", .{fail_count});
        return error.TestUnexpectedResult;
    }
}

test "examples: no app has main/main.c" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const apps = try discoverExampleApps(arena.allocator());
    var examples = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    defer examples.close();

    var fail_count: usize = 0;
    for (apps) |app| {
        var buf: [512]u8 = undefined;
        const p = joinPath(&buf, app, "main/main.c");
        if (fileExistsIn(examples, p)) {
            std.debug.print("  UNEXPECTED: examples/{s}/main/main.c should use auto-generated entry\n", .{app});
            fail_count += 1;
        }
    }
    if (fail_count > 0) {
        std.debug.print("{d} example(s) have hand-written main/main.c\n", .{fail_count});
        return error.TestUnexpectedResult;
    }
}
