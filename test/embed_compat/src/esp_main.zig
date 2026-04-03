const app_options = @import("app_options");
const esp_embed = @import("esp_embed");
const integration_mod = @import("integration");
const test_runner = @import("test_runner.zig");
const testing_mod = @import("testing");

const std = esp_embed.std;
const Thread = std.Thread;
const Time = std.time;
const app_log = std.log.scoped(.embed_compat);

extern fn esp_vfs_spiffs_register(conf: *const SpiffsConf) callconv(.c) i32;
extern fn esp_vfs_spiffs_unregister(partition_label: ?[*:0]const u8) callconv(.c) i32;
extern fn espz_test_wifi_connect(ssid: [*:0]const u8, password: [*:0]const u8, timeout_ms: i32) callconv(.c) i32;

const SpiffsConf = extern struct {
    base_path: ?[*:0]const u8,
    partition_label: ?[*:0]const u8,
    max_files: usize,
    format_if_mount_failed: bool,
};

const tmp_mount_path = "/tmp";
const tmp_partition_label = "tmp";
const esp_ok: i32 = 0;
const wifi_connect_timeout_ms: i32 = 30_000;
const wifi_ssid = app_options.wifi_ssid;
const wifi_password = app_options.wifi_password;

const EspPlatform = struct {
    pub const std = esp_embed.std;
    pub const Channel = esp_embed.sync.Channel;
    pub const integration = integration_mod;
    pub const net = esp_embed.net;
    pub const sync = esp_embed.sync;
    pub const testing_api = testing_mod;

    pub fn setup() !void {
        const wifi_rc = espz_test_wifi_connect(wifi_ssid, wifi_password, wifi_connect_timeout_ms);
        if (wifi_rc != esp_ok) {
            app_log.err("failed to connect wifi: {d}", .{wifi_rc});
            return error.WifiConnectFailed;
        }

        const tmp_conf: SpiffsConf = .{
            .base_path = tmp_mount_path,
            .partition_label = tmp_partition_label,
            .max_files = 8,
            .format_if_mount_failed = false,
        };

        if (esp_vfs_spiffs_register(&tmp_conf) != 0) {
            app_log.err("failed to mount spiffs at {s}", .{tmp_mount_path});
            return error.SpiffsMountFailed;
        }

        app_log.info("mounted spiffs at {s}", .{tmp_mount_path});
    }

    pub fn teardown() void {
        _ = esp_vfs_spiffs_unregister(tmp_partition_label);
    }
};

export fn zig_esp_main() callconv(.c) void {
    test_runner.run(EspPlatform) catch |err| {
        app_log.err("embed-zig test runners failed: {}", .{err});
        @panic("embed-zig test runners failed");
    };

    while (true) {
        Thread.sleep(10000 * Time.ns_per_ms);
        app_log.info("sleeping", .{});
    }
}
