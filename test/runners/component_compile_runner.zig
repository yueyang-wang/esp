const std = @import("std");
const common = @import("common.zig");

pub fn main() !void {
    const esp_idf = common.espIdfOrNull() orelse {
        std.debug.print("component-compile: SKIPPED (-Desp_idf not provided)\n", .{});
        return;
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tests = try common.discoverComponentTests(allocator);
    if (tests.len == 0) {
        std.debug.print("component-compile: WARNING no component tests found\n", .{});
        return;
    }

    var pass_count: usize = 0;
    var fail_count: usize = 0;

    for (tests) |test_case| {
        const esp_idf_arg = try std.fmt.allocPrint(allocator, "-Desp_idf={s}", .{esp_idf});
        const build_config_arg = try std.fmt.allocPrint(allocator, "-Dbuild_config={s}", .{test_case.compile.build_config});
        const bsp_arg = try std.fmt.allocPrint(allocator, "-Dbsp={s}", .{test_case.compile.bsp});
        const argv = [_][]const u8{
            common.zigExe(),
            "build",
            "build",
            esp_idf_arg,
            build_config_arg,
            bsp_arg,
        };

        std.debug.print("  compile: {s} ...", .{test_case.module_name});
        const result = common.runChild(allocator, test_case.test_dir, &argv) catch |err| {
            std.debug.print(" EXEC ERROR: {}\n", .{err});
            fail_count += 1;
            continue;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        const ok = switch (result.term) {
            .Exited => |code| code == 0,
            else => false,
        };
        if (ok) {
            const golden_result = common.verifyElfLayoutGolden(
                allocator,
                test_case.test_dir,
                "build",
                test_case.compile.build_config,
                test_case.compile.bsp,
                test_case.golden_dir,
            ) catch |err| {
                std.debug.print(" GOLDEN ERROR: {}\n", .{err});
                fail_count += 1;
                continue;
            };
            switch (golden_result) {
                .missing => |paths| {
                    fail_count += 1;
                    std.debug.print(" GOLDEN MISSING\n", .{});
                    std.debug.print("    expected: {s}\n", .{paths.expected_path});
                },
                .matched => {
                    pass_count += 1;
                    std.debug.print(" OK (golden)\n", .{});
                },
                .mismatch => |paths| {
                    fail_count += 1;
                    std.debug.print(" GOLDEN MISMATCH\n", .{});
                    std.debug.print("    expected: {s}\n", .{paths.expected_path});
                    std.debug.print("    actual:   {s}\n", .{paths.actual_path});
                },
            }
        } else {
            fail_count += 1;
            common.printResultFailure("component-compile", test_case.module_name, result);
        }
    }

    std.debug.print(
        "\ncomponent-compile results: {d} passed, {d} failed out of {d} tests\n",
        .{ pass_count, fail_count, tests.len },
    );
    if (fail_count > 0) return error.TestUnexpectedResult;
}
