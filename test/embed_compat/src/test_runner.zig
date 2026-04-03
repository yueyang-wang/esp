const lvgl = @import("lvgl");
const ogg = @import("ogg");
const opus = @import("opus");
const stb_truetype = @import("stb_truetype");
const integration = @import("integration");
const testing = @import("testing");

pub fn run(comptime lib: type, stack_size: usize) !void {
    const withEspStack = struct {
        fn apply(tr: testing.TestRunner, stack_size: usize) testing.TestRunner {
            var r = tr;
            r.spawn_config = .{ .stack_size = stack_size };
            return r;
        }
    }.apply;

    const rtstd = lib.std;
    const Net = lib.net.make(rtstd);
    const app_log = rtstd.log.scoped(.embed_compat);

    try lib.setup();
    defer lib.teardown();

    app_log.info("starting embed-zig test runners", .{});

    var runner = testing.T.new(rtstd, .embed_compat);
    defer runner.deinit();

    runner.parallel();
    runner.timeout(240 * rtstd.time.ns_per_s);

    runner.run("sync/channel", withEspStack(lib.sync.test_runner.channel.make(rtstd, lib.Channel), stack_size));
    runner.run("sync/racer", withEspStack(lib.sync.test_runner.racer.make(rtstd), stack_size));
    runner.run("integration", withEspStack(integration.make(rtstd), stack_size));
    runner.run("net/fd_stream", withEspStack(lib.net.test_runner.fd_stream.make(rtstd), stack_size));
    runner.run("net/fd_packet", withEspStack(lib.net.test_runner.fd_packet.make(rtstd), stack_size));
    runner.run("net/tcp", withEspStack(lib.net.test_runner.tcp.make(rtstd), stack_size));
    runner.run("net/udp", withEspStack(lib.net.test_runner.udp.make(rtstd), stack_size));
    runner.run("net/resolver", withEspStack(lib.net.test_runner.resolver.make(rtstd), stack_size));
    runner.run("net/resolver_dns", withEspStack(lib.net.test_runner.resolver_dns.make(rtstd, &.{
        Net.Resolver.dns.ali.v4_1,
        Net.Resolver.dns.ali.v4_2,
    }, Net.Resolver.dns.ali.server_name), stack_size));
    runner.run("net/tls", withEspStack(lib.net.test_runner.tls.make(rtstd), stack_size));
    runner.run("net/tls_dial", withEspStack(lib.net.test_runner.tls_dial.make(rtstd, Net.Resolver.dns.ali.server_name), stack_size));
    runner.run("net/ntp", withEspStack(lib.net.test_runner.ntp.make(rtstd), stack_size));
    runner.run("net/http_transport", withEspStack(lib.net.test_runner.http_transport.make(rtstd), stack_size));
    runner.run("net/https_transport", withEspStack(lib.net.test_runner.https_transport.make(rtstd), stack_size));
    runner.run("lvgl", withEspStack(lvgl.test_runner.lvgl.make(rtstd), stack_size));
    runner.run("stb_truetype", withEspStack(stb_truetype.test_runner.stb_truetype.make(rtstd), stack_size));
    runner.run("ogg", withEspStack(ogg.test_runner.ogg.make(rtstd), stack_size));
    runner.run("opus", withEspStack(opus.test_runner.opus.make(rtstd), stack_size));

    const passed = runner.wait();
    app_log.info("embed-zig test runners finished", .{});
    if (!passed) return error.TestsFailed;
}

test "embed compat native runner" {
    @import("std").testing.log_level = .info;

    const NativePlatform = struct {
        const embed_std = @import("embed_std");
        const integration_mod = @import("integration");
        const net_mod = @import("net");
        const sync_mod = @import("sync");
        const testing_mod = @import("testing");
        pub const std = embed_std.std;
        pub const Channel = embed_std.sync.Channel;
        pub const integration = integration_mod;
        pub const net = net_mod;
        pub const sync = sync_mod;
        pub const testing_api = testing_mod;

        pub fn setup() !void {}
        pub fn teardown() void {}
    };

    try run(NativePlatform, 0);
}
