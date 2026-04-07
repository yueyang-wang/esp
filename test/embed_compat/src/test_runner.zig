const context_test = @import("context_test");
const embed_test = @import("embed_test");
const lvgl = @import("lvgl");
const ogg = @import("ogg");
const opus = @import("opus");
const stb_truetype = @import("stb_truetype");
const testing = @import("testing");

pub fn run(comptime lib: type, stack_size: usize) !void {
    const withStackSize = struct {
        fn apply(tr: testing.TestRunner, requested_stack_size: usize) testing.TestRunner {
            var r = tr;
            r.spawn_config = .{ .stack_size = requested_stack_size };
            return r;
        }
    }.apply;

    const rtstd = lib.std;
    const app_log = rtstd.log.scoped(.embed_compat);

    try lib.setup();
    defer lib.teardown();

    app_log.info("starting embed-zig test runners", .{});

    var runner = testing.T.new(rtstd, .embed_compat);
    defer runner.deinit();

    runner.parallel();
    runner.timeout(240 * rtstd.time.ns_per_s);

    runner.run("embed/unit", withStackSize(embed_test.make(rtstd), stack_size));
    runner.run("context/unit", withStackSize(context_test.make(rtstd), stack_size));
    runner.run("sync/integration", withStackSize(lib.sync.test_runner.integration.make(rtstd, lib.Channel), stack_size));
    runner.run("net/integration", withStackSize(lib.net.test_runner.integration.make(rtstd), stack_size));
    runner.run("lvgl", withStackSize(lvgl.test_runner.lvgl.make(rtstd), stack_size));
    runner.run("stb_truetype", withStackSize(stb_truetype.test_runner.stb_truetype.make(rtstd), stack_size));
    runner.run("ogg", withStackSize(ogg.test_runner.ogg.make(rtstd), stack_size));
    runner.run("opus", withStackSize(opus.test_runner.opus.make(rtstd), stack_size));

    const passed = runner.wait();
    app_log.info("embed-zig test runners finished", .{});
    if (!passed) return error.TestsFailed;
}

test "embed compat native runner" {
    @import("std").testing.log_level = .info;

    const NativePlatform = struct {
        const embed_std = @import("embed_std");
        const net_mod = @import("net");
        const sync_mod = @import("sync");
        const testing_mod = @import("testing");
        pub const std = embed_std.std;
        pub const Channel = embed_std.sync.Channel;
        pub const net = net_mod;
        pub const sync = sync_mod;
        pub const testing_api = testing_mod;

        pub fn setup() !void {}
        pub fn teardown() void {}
    };

    try run(NativePlatform, 0);
}
