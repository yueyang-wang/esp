pub const config = @import("build_config").config;

pub const pins = .{
    .wifi = .{
        .ssid = @as([]const u8, "espz-test-ap"),
        .password = @as([]const u8, "espz1234"),
        .listen_interval = @as(u16, 3),
    },
    .wifi_ap = .{
        .ssid = @as([]const u8, "espz-test-ap"),
        .password = @as([]const u8, "espz1234"),
        .channel = @as(u8, 6),
        .max_connection = @as(u8, 4),
        .hidden = false,
    },
};
