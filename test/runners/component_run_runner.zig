const std = @import("std");
const common = @import("common.zig");

pub fn main() !void {
    const esp_idf = common.espIdfOrNull() orelse {
        std.debug.print("component-run: SKIPPED (-Desp_idf not provided)\n", .{});
        return;
    };
    const port = common.portOrNull() orelse {
        std.debug.print("component-run: SKIPPED (-Dport not provided)\n", .{});
        return;
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tests = try common.discoverComponentTests(allocator);
    if (tests.len == 0) {
        std.debug.print("component-run: WARNING no component tests found\n", .{});
        return;
    }

    var pass_count: usize = 0;
    var fail_count: usize = 0;

    for (tests) |test_case| {
        const real = test_case.real orelse continue;

        const esp_idf_arg = try std.fmt.allocPrint(allocator, "-Desp_idf={s}", .{esp_idf});
        const build_config_arg = try std.fmt.allocPrint(allocator, "-Dbuild_config={s}", .{real.build_config});
        const bsp_arg = try std.fmt.allocPrint(allocator, "-Dbsp={s}", .{real.bsp});
        const port_arg = try std.fmt.allocPrint(allocator, "-Dport={s}", .{port});
        const timeout_arg = if (common.timeoutOrNull()) |timeout|
            try std.fmt.allocPrint(allocator, "-Dtimeout={d}", .{timeout})
        else
            null;

        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(allocator);
        try argv.appendSlice(allocator, &.{
            common.zigExe(),
            "build",
            "flash-monitor",
            esp_idf_arg,
            build_config_arg,
            bsp_arg,
            port_arg,
        });
        if (timeout_arg) |arg| try argv.append(allocator, arg);

        std.debug.print("  run: {s} ...", .{test_case.module_name});
        const result = common.runChild(allocator, test_case.test_dir, argv.items) catch |err| {
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
            pass_count += 1;
            std.debug.print(" OK\n", .{});
        } else {
            fail_count += 1;
            common.printResultFailure("component-run", test_case.module_name, result);
        }
    }

    std.debug.print(
        "\ncomponent-run results: {d} passed, {d} failed\n",
        .{ pass_count, fail_count },
    );
    if (fail_count > 0) return error.TestUnexpectedResult;
}
