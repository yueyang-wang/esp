const std = @import("std");
const esp_event = @import("../esp_event/event.zig");

pub const Handle = ?*anyopaque;
pub const EventBase = esp_event.EventBase;
pub const EventHandler = esp_event.EventHandler;

const esp_ok: i32 = 0;
const esp_err_no_mem: i32 = 0x101;
const esp_err_invalid_arg: i32 = 0x102;
const esp_err_invalid_state: i32 = 0x103;

pub const IpEvent = enum(i32) {
    sta_got_ip = 0,
    sta_lost_ip = 1,
    ap_sta_ip_assigned = 2,
};

pub const IpInfo = extern struct {
    ip: u32 = 0,
    netmask: u32 = 0,
    gw: u32 = 0,
};

pub const DnsType = enum(u32) {
    main = 0,
    backup = 1,
    fallback = 2,
};

pub const DnsInfo = extern struct {
    ip: u32 = 0,
};

pub const Error = error{
    OutOfMemory,
    InvalidArgument,
    InvalidState,
    NetifFailed,
};

extern fn espz_netif_runtime_init() i32;
extern fn espz_netif_runtime_deinit() i32;
extern fn espz_netif_create_default_wifi_sta() Handle;
extern fn espz_netif_create_default_wifi_ap() Handle;
extern fn espz_netif_destroy_default_wifi(netif: Handle) i32;
extern fn espz_netif_get_handle_from_ifkey(if_key: [*:0]const u8) Handle;
extern fn espz_netif_get_ip_info(netif: Handle, ip_info: *IpInfo) i32;
extern fn espz_netif_set_ip_info(netif: Handle, ip_info: *const IpInfo) i32;
extern fn espz_netif_get_dns_info(netif: Handle, dns_type: u32, dns: *DnsInfo) i32;
extern fn espz_netif_set_dns_info(netif: Handle, dns_type: u32, dns: *const DnsInfo) i32;
extern fn espz_netif_is_up(netif: Handle) i32;
extern fn espz_netif_set_default(netif: Handle) void;
extern fn espz_netif_get_impl_name(netif: Handle, name: [*]u8) i32;
extern fn espz_netif_get_nr_of_ifs() i32;
extern fn espz_netif_next(netif: Handle) Handle;
extern fn espz_netif_dhcpc_get_status(netif: Handle, status: *u32) i32;
extern fn espz_netif_dhcpc_start(netif: Handle) i32;
extern fn espz_netif_dhcpc_stop(netif: Handle) i32;
extern fn espz_netif_set_hostname(netif: Handle, hostname: [*]const u8, hostname_len: u8) i32;
extern const IP_EVENT: EventBase;

pub fn init() Error!void {
    try check(espz_netif_runtime_init());
}

pub fn deinit() Error!void {
    try check(espz_netif_runtime_deinit());
}

pub fn createDefaultWifiSta() Error!Handle {
    const netif = espz_netif_create_default_wifi_sta();
    if (netif == null) return error.OutOfMemory;
    return netif;
}

pub fn createDefaultWifiAp() Error!Handle {
    const netif = espz_netif_create_default_wifi_ap();
    if (netif == null) return error.OutOfMemory;
    return netif;
}

pub fn destroyDefaultWifi(netif: Handle) Error!void {
    try check(espz_netif_destroy_default_wifi(netif));
}

pub fn getHandleFromIfKey(if_key: [*:0]const u8) Handle {
    return espz_netif_get_handle_from_ifkey(if_key);
}

pub fn registerIpEventHandler(event: IpEvent, handler: EventHandler, arg: ?*anyopaque) Error!void {
    esp_event.registerDefault(IP_EVENT, @intFromEnum(event), handler, arg) catch |err| return mapEventError(err);
}

pub fn unregisterIpEventHandler(event: IpEvent, handler: EventHandler) Error!void {
    esp_event.unregisterDefault(IP_EVENT, @intFromEnum(event), handler) catch |err| return mapEventError(err);
}

pub fn isIpEventBase(event_base: EventBase) bool {
    return event_base == IP_EVENT;
}

pub fn getIpInfo(netif: Handle) Error!IpInfo {
    var info = IpInfo{};
    try check(espz_netif_get_ip_info(netif, &info));
    return info;
}

pub fn setIpInfo(netif: Handle, info: *const IpInfo) Error!void {
    try check(espz_netif_set_ip_info(netif, info));
}

pub fn getDnsInfo(netif: Handle, dns_type: DnsType) Error![4]u8 {
    var dns = DnsInfo{};
    try check(espz_netif_get_dns_info(netif, @intFromEnum(dns_type), &dns));
    return ip4ToBytes(dns.ip);
}

pub fn setDnsInfo(netif: Handle, dns_type: DnsType, addr: [4]u8) Error!void {
    const dns = DnsInfo{ .ip = ip4FromBytes(addr) };
    try check(espz_netif_set_dns_info(netif, @intFromEnum(dns_type), &dns));
}

pub fn isUp(netif: Handle) bool {
    return espz_netif_is_up(netif) != 0;
}

pub fn setDefaultNetif(netif: Handle) void {
    espz_netif_set_default(netif);
}

pub fn getImplName(netif: Handle) Error![16]u8 {
    var buf: [16]u8 = std.mem.zeroes([16]u8);
    try check(espz_netif_get_impl_name(netif, &buf));
    return buf;
}

pub fn getNumberOfIfs() u32 {
    const n = espz_netif_get_nr_of_ifs();
    if (n < 0) return 0;
    return @intCast(n);
}

pub fn nextNetif(netif: Handle) Handle {
    return espz_netif_next(netif);
}

pub fn isDhcpClient(netif: Handle) Error!bool {
    var status: u32 = 0;
    try check(espz_netif_dhcpc_get_status(netif, &status));
    return status == 1;
}

pub fn startDhcpClient(netif: Handle) Error!void {
    try check(espz_netif_dhcpc_start(netif));
}

pub fn stopDhcpClient(netif: Handle) Error!void {
    try check(espz_netif_dhcpc_stop(netif));
}

pub fn setHostname(netif: Handle, hostname: []const u8) Error!void {
    if (hostname.len == 0 or hostname.len > 63) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, hostname, 0) != null) return error.InvalidArgument;
    try check(espz_netif_set_hostname(netif, hostname.ptr, @intCast(hostname.len)));
}

pub fn ip4ToBytes(addr: u32) [4]u8 {
    return .{
        @truncate(addr),
        @truncate(addr >> 8),
        @truncate(addr >> 16),
        @truncate(addr >> 24),
    };
}

pub fn ip4FromBytes(b: [4]u8) u32 {
    return @as(u32, b[0]) | (@as(u32, b[1]) << 8) | (@as(u32, b[2]) << 16) | (@as(u32, b[3]) << 24);
}

fn check(result: i32) Error!void {
    switch (result) {
        esp_ok => return,
        esp_err_no_mem => return error.OutOfMemory,
        esp_err_invalid_arg => return error.InvalidArgument,
        esp_err_invalid_state => return error.InvalidState,
        else => return error.NetifFailed,
    }
}

fn mapEventError(err: esp_event.Error) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidArgument => error.InvalidArgument,
        error.InvalidState => error.InvalidState,
        error.NotFound, error.EspIdfFailure => error.NetifFailed,
    };
}
