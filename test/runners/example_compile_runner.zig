const std = @import("std");
const common = @import("common.zig");

pub fn main() !void {
    const esp_idf = common.espIdfOrNull() orelse {
        std.debug.print("example-compile: SKIPPED (-Desp_idf not provided)\n", .{});
        return;
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const apps = try common.discoverExampleApps(allocator);
    if (apps.len == 0) {
        std.debug.print("example-compile: WARNING no examples found\n", .{});
        return;
    }

    var pass_count: usize = 0;
    var fail_count: usize = 0;

    for (apps) |app| {
        const esp_idf_arg = try std.fmt.allocPrint(allocator, "-Desp_idf={s}", .{esp_idf});
        const build_config_arg = try std.fmt.allocPrint(allocator, "-Dbuild_config={s}", .{app.inputs.build_config});
        const bsp_arg = try std.fmt.allocPrint(allocator, "-Dbsp={s}", .{app.inputs.bsp});
        const argv = [_][]const u8{
            common.zigExe(),
            "build",
            "build",
            esp_idf_arg,
            build_config_arg,
            bsp_arg,
        };

        std.debug.print("  example: {s} ...", .{app.app_name});
        const result = common.runChild(allocator, app.app_dir, &argv) catch |err| {
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
            common.printResultFailure("example-compile", app.app_name, result);
        }
    }

    std.debug.print(
        "\nexample-compile results: {d} passed, {d} failed out of {d} examples\n",
        .{ pass_count, fail_count, apps.len },
    );
    if (fail_count > 0) return error.TestUnexpectedResult;
}
