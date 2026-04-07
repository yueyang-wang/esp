const context_test = @import("context_test");
const embed_test = @import("embed_test");
const lvgl = @import("lvgl");
const ogg = @import("ogg");
const opus = @import("opus");
const stb_truetype = @import("stb_truetype");
const testing = @import("testing");

pub fn run(comptime lib: type) !void {
    const rtstd = lib.std;
    const app_log = rtstd.log.scoped(.embed_compat);

    try lib.setup();
    defer lib.teardown();

    app_log.info("starting embed-zig test runners", .{});

    var runner = testing.T.new(rtstd, .embed_compat);
    defer runner.deinit();

    runner.parallel();
    runner.timeout(240 * rtstd.time.ns_per_s);

    runner.run("embed/unit", embed_test.make(rtstd));
    runner.run("context/unit", context_test.make(rtstd));
    runner.run("sync/integration", lib.sync.test_runner.integration.make(rtstd, lib.Channel));
    runner.run("net/integration", lib.net.test_runner.integration.make(rtstd));
    runner.run("lvgl", lvgl.test_runner.lvgl.make(rtstd));
    runner.run("stb_truetype", stb_truetype.test_runner.stb_truetype.make(rtstd));
    runner.run("ogg", ogg.test_runner.ogg.make(rtstd));
    runner.run("opus", opus.test_runner.opus.make(rtstd));

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
