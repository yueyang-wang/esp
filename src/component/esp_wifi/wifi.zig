const std = @import("std");
const esp_event = @import("../esp_event/event.zig");

pub const EspError = i32;
pub const esp_ok: EspError = 0;

const esp_err_no_mem: EspError = 0x101;
const esp_err_invalid_arg: EspError = 0x102;
const esp_err_invalid_state: EspError = 0x103;
const esp_err_not_found: EspError = 0x105;
const esp_err_invalid_size: EspError = 0x106;

pub const Error = error{
    NotInitialized,
    AlreadyInitialized,
    InvalidState,
    InvalidArgument,
    OutOfMemory,
    NotFound,
    BufferTooSmall,
    EspIdfFailure,
};

pub const EventBase = esp_event.EventBase;
pub const EventHandler = esp_event.EventHandler;

pub const WifiEvent = enum(i32) {
    scan_done = 1,
    sta_connected = 4,
    sta_disconnected = 5,
    ap_start = 14,
};

pub const ScanType = enum(c_int) {
    active = 0,
    passive = 1,
};

pub const SecondChannel = enum(c_int) {
    none = 0,
    above = 1,
    below = 2,
};

pub const AuthMode = enum(c_int) {
    open = 0,
    wep = 1,
    wpa_psk = 2,
    wpa2_psk = 3,
    wpa_wpa2_psk = 4,
    enterprise = 5,
    wpa2_enterprise = 6,
    wpa3_psk = 7,
    wpa2_wpa3_psk = 8,
    wapi_psk = 9,
    owe = 10,
    wpa3_ent_192 = 11,
    wpa3_ext_psk = 12,
    wpa3_ext_psk_mixed_mode = 13,
    dpp = 14,
};

pub const CipherType = enum(c_int) {
    none = 0,
    wep40 = 1,
    wep104 = 2,
    tkip = 3,
    ccmp = 4,
    tkip_ccmp = 5,
    aes_cmac128 = 6,
    sms4 = 7,
    gcmp = 8,
    gcmp256 = 9,
    aes_gmac128 = 10,
    aes_gmac256 = 11,
    unknown = 12,
};

pub const Antenna = enum(c_int) {
    ant0 = 0,
    ant1 = 1,
    auto = 2,
};

pub const CountryPolicy = enum(c_int) {
    auto = 0,
    manual = 1,
};

pub const RawBandwidth = c_int;

pub const ActiveScanTime = extern struct {
    min: u32,
    max: u32,
};

pub const ScanTime = extern struct {
    active: ActiveScanTime,
    passive: u32,
};

pub const ScanChannelBitmap = extern struct {
    ghz_2_channels: u16,
    ghz_5_channels: u32,
};

pub const RawScanConfig = extern struct {
    ssid: ?[*]u8,
    bssid: ?[*]u8,
    channel: u8,
    show_hidden: bool,
    scan_type: ScanType,
    scan_time: ScanTime,
    home_chan_dwell_time: u8,
    channel_bitmap: ScanChannelBitmap,
};

pub const Country = extern struct {
    cc: [3]u8,
    schan: u8,
    nchan: u8,
    max_tx_power: i8,
    policy: CountryPolicy,
};

pub const HeApInfo = extern struct {
    bss_color_info: u8,
    bssid_index: u8,
};

pub const ApRecord = extern struct {
    bssid: [6]u8,
    ssid: [33]u8,
    primary: u8,
    second: SecondChannel,
    rssi: i8,
    authmode: AuthMode,
    pairwise_cipher: CipherType,
    group_cipher: CipherType,
    ant: Antenna,
    phy_flags: u32,
    country: Country,
    he_ap: HeApInfo,
    bandwidth: RawBandwidth,
    vht_ch_freq1: u8,
    vht_ch_freq2: u8,
};

pub const StaScanDoneEvent = extern struct {
    status: u32,
    number: u8,
    scan_id: u8,
};

pub const StaDisconnectedEvent = extern struct {
    ssid: [32]u8,
    ssid_len: u8,
    bssid: [6]u8,
    reason: u8,
    rssi: i8,
};

pub const StaConnectedEvent = extern struct {
    ssid: [32]u8,
    ssid_len: u8,
    bssid: [6]u8,
    channel: u8,
    authmode: AuthMode,
    aid: u16,
};

pub const ApStaConnectedEvent = extern struct {
    mac: [6]u8,
    aid: u8,
    is_mesh_child: bool,
};

pub const ApStaDisconnectedEvent = extern struct {
    mac: [6]u8,
    aid: u8,
    is_mesh_child: bool,
    reason: u16,
};

const CStaConfig = extern struct {
    ssid: ?[*]const u8,
    ssid_len: u8,
    password: ?[*]const u8,
    password_len: u8,
    listen_interval: u16,
};

const CApConfig = extern struct {
    ssid: ?[*]const u8,
    ssid_len: u8,
    password: ?[*]const u8,
    password_len: u8,
    channel: u8,
    max_connection: u8,
    hidden: bool,
};

pub const CScanConfig = extern struct {
    channel: u8,
    show_hidden: bool,
    block_until_done: bool,
    max_results: u16,
};

pub const CScanRecord = extern struct {
    ssid: [32]u8,
    rssi: i8,
    channel: u8,
    authmode: u8,
};

extern fn espz_wifi_runtime_init() EspError;
extern fn espz_wifi_runtime_deinit() EspError;

extern fn espz_wifi_set_mode(mode: u8) EspError;
extern fn espz_wifi_start() EspError;
extern fn espz_wifi_stop() EspError;
extern fn espz_wifi_connect() EspError;
extern fn espz_wifi_disconnect() EspError;

extern fn espz_wifi_set_sta_config(cfg: *const CStaConfig) EspError;
extern fn espz_wifi_set_ap_config(cfg: *const CApConfig) EspError;

pub extern fn espz_wifi_scan(
    cfg: *const CScanConfig,
    out_records: [*]CScanRecord,
    out_cap: u16,
    out_count: *u16,
) EspError;
extern fn espz_wifi_get_sta_mac(out: *[6]u8) EspError;

extern fn espz_wifi_set_power_save(ps: u8) EspError;
extern fn espz_wifi_get_power_save(out_ps: *u8) EspError;
extern fn espz_wifi_set_max_tx_power(quarter_dbm: i8) EspError;

extern fn espz_wifi_set_protocol_mask(mode: u8, mask: u8) EspError;
extern fn espz_wifi_set_bandwidth(mode: u8, bw: u8) EspError;
extern fn espz_wifi_set_channel(primary: u8, second: u8) EspError;

extern const WIFI_EVENT: EventBase;
extern fn esp_wifi_scan_start(config: *const RawScanConfig, block: bool) EspError;
extern fn esp_wifi_scan_get_ap_records(number: *u16, ap_records: [*]ApRecord) EspError;

pub fn isWifiEventBase(event_base: EventBase) bool {
    return event_base == WIFI_EVENT;
}

pub fn getWifiEventBase() EventBase {
    return WIFI_EVENT;
}

pub const WifiEventRegistration = struct {
    event: ?WifiEvent = null,
    handler: EventHandler,
    arg: ?*anyopaque = null,
};

pub const WifiEventHandler = struct {
    pub fn any(_: WifiEventHandler, handler: EventHandler, arg: ?*anyopaque) WifiEventRegistration {
        return .{
            .event = null,
            .handler = handler,
            .arg = arg,
        };
    }

    pub fn forEvent(_: WifiEventHandler, event: WifiEvent, handler: EventHandler, arg: ?*anyopaque) WifiEventRegistration {
        return .{
            .event = event,
            .handler = handler,
            .arg = arg,
        };
    }

    pub fn register(self: WifiEventHandler, wifi: *WiFi, registration: WifiEventRegistration) Error!void {
        _ = self;
        try wifi.requireInitialized();
        if (registration.event) |event| {
            esp_event.registerDefault(WIFI_EVENT, @intFromEnum(event), registration.handler, registration.arg) catch |err| return mapEventError(err);
            return;
        }
        esp_event.registerDefaultAny(WIFI_EVENT, registration.handler, registration.arg) catch |err| return mapEventError(err);
    }

    pub fn unregister(self: WifiEventHandler, wifi: *WiFi, registration: WifiEventRegistration) Error!void {
        _ = self;
        try wifi.requireInitialized();
        if (registration.event) |event| {
            esp_event.unregisterDefault(WIFI_EVENT, @intFromEnum(event), registration.handler) catch |err| return mapEventError(err);
            return;
        }
        esp_event.unregisterDefaultAny(WIFI_EVENT, registration.handler) catch |err| return mapEventError(err);
    }

    pub fn registerAny(self: WifiEventHandler, wifi: *WiFi, handler: EventHandler, arg: ?*anyopaque) Error!void {
        try self.register(wifi, self.any(handler, arg));
    }

    pub fn unregisterAny(self: WifiEventHandler, wifi: *WiFi, handler: EventHandler) Error!void {
        try self.unregister(wifi, self.any(handler, null));
    }

    pub fn registerEvent(self: WifiEventHandler, wifi: *WiFi, event: WifiEvent, handler: EventHandler, arg: ?*anyopaque) Error!void {
        try self.register(wifi, self.forEvent(event, handler, arg));
    }

    pub fn unregisterEvent(self: WifiEventHandler, wifi: *WiFi, event: WifiEvent, handler: EventHandler) Error!void {
        try self.unregister(wifi, self.forEvent(event, handler, null));
    }
};

pub const WiFi = struct {
    pub const Mode = enum(u8) {
        sta = 1,
        ap = 2,
        apsta = 3,
    };

    pub const PowerSave = enum(u8) {
        none = 0,
        min_modem = 1,
        max_modem = 2,
    };

    pub const Bandwidth = enum(u8) {
        ht20 = 0,
        ht40 = 1,
    };

    pub const StaConfig = struct {
        ssid: []const u8,
        password: []const u8 = "",
        listen_interval: u16 = 0,
    };

    pub const ApConfig = struct {
        ssid: []const u8,
        password: []const u8 = "",
        channel: u8 = 6,
        max_connection: u8 = 4,
        hidden: bool = false,
    };

    pub const ScanConfig = struct {
        channel: u8 = 0,
        show_hidden: bool = false,
        block_until_done: bool = true,
        max_results: u16 = 12,
    };

    pub const ScanRecord = struct {
        ssid: [32]u8,
        rssi: i8,
        channel: u8,
        authmode: u8,
    };

    event_handler: WifiEventHandler = .{},
    initialized: bool = false,
    started: bool = false,
    mode: ?Mode = null,

    pub fn init() Error!WiFi {
        try check(espz_wifi_runtime_init());
        return .{ .initialized = true };
    }

    pub fn deinit(self: *WiFi) Error!void {
        try self.requireInitialized();
        if (self.started) {
            try self.stop();
        }
        try check(espz_wifi_runtime_deinit());
        self.* = .{};
    }

    pub fn start(self: *WiFi) Error!void {
        try self.requireInitialized();
        if (self.started) return;
        try check(espz_wifi_start());
        self.started = true;
    }

    pub fn stop(self: *WiFi) Error!void {
        try self.requireInitialized();
        if (!self.started) return;
        try check(espz_wifi_stop());
        self.started = false;
    }

    pub fn setMode(self: *WiFi, mode: Mode) Error!void {
        try self.requireInitialized();
        try check(espz_wifi_set_mode(@intFromEnum(mode)));
        self.mode = mode;
    }

    pub fn startSta(self: *WiFi, cfg: StaConfig) Error!void {
        try self.setMode(.sta);
        try self.configureSta(cfg);
        try self.start();
    }

    pub fn configureSta(self: *WiFi, cfg: StaConfig) Error!void {
        try self.requireInitialized();
        try validateStaConfig(cfg);

        const c_cfg: CStaConfig = .{
            .ssid = cfg.ssid.ptr,
            .ssid_len = @intCast(cfg.ssid.len),
            .password = if (cfg.password.len == 0) null else cfg.password.ptr,
            .password_len = @intCast(cfg.password.len),
            .listen_interval = cfg.listen_interval,
        };
        try check(espz_wifi_set_sta_config(&c_cfg));
    }

    pub fn connectSta(self: *WiFi) Error!void {
        try self.requireInitialized();
        if (self.mode != .sta and self.mode != .apsta) {
            return error.InvalidState;
        }
        try check(espz_wifi_connect());
    }

    pub fn disconnectSta(self: *WiFi) Error!void {
        try self.requireInitialized();
        try check(espz_wifi_disconnect());
    }

    pub fn startAp(self: *WiFi, cfg: ApConfig) Error!void {
        try self.setMode(.ap);
        try self.configureAp(cfg);
        try self.start();
    }

    pub fn configureAp(self: *WiFi, cfg: ApConfig) Error!void {
        try self.requireInitialized();
        try validateApConfig(cfg);

        const c_cfg: CApConfig = .{
            .ssid = cfg.ssid.ptr,
            .ssid_len = @intCast(cfg.ssid.len),
            .password = if (cfg.password.len == 0) null else cfg.password.ptr,
            .password_len = @intCast(cfg.password.len),
            .channel = cfg.channel,
            .max_connection = cfg.max_connection,
            .hidden = cfg.hidden,
        };
        try check(espz_wifi_set_ap_config(&c_cfg));
    }

    pub fn stopAp(self: *WiFi) Error!void {
        try self.stop();
    }

    pub fn scan(self: *WiFi, cfg: ScanConfig, allocator: std.mem.Allocator) Error![]ScanRecord {
        try self.requireInitialized();
        const cap: u16 = if (cfg.max_results == 0) 1 else cfg.max_results;

        const c_cfg: CScanConfig = .{
            .channel = cfg.channel,
            .show_hidden = cfg.show_hidden,
            .block_until_done = cfg.block_until_done,
            .max_results = cap,
        };

        const tmp_records = try allocator.alloc(CScanRecord, cap);
        defer allocator.free(tmp_records);

        var out_count: u16 = 0;
        try check(espz_wifi_scan(&c_cfg, tmp_records.ptr, cap, &out_count));

        const count: usize = out_count;
        const records = try allocator.alloc(ScanRecord, count);
        errdefer allocator.free(records);

        for (records, 0..) |*item, idx| {
            item.* = .{
                .ssid = tmp_records[idx].ssid,
                .rssi = tmp_records[idx].rssi,
                .channel = tmp_records[idx].channel,
                .authmode = tmp_records[idx].authmode,
            };
        }
        return records;
    }

    pub fn startRawScan(self: *WiFi, cfg: *const RawScanConfig, block: bool) Error!void {
        try self.requireInitialized();
        try check(esp_wifi_scan_start(cfg, block));
    }

    pub fn startAsyncScan(self: *WiFi, cfg: ScanConfig) Error!void {
        try self.requireInitialized();
        var raw = std.mem.zeroes(RawScanConfig);
        raw.channel = cfg.channel;
        raw.show_hidden = cfg.show_hidden;
        raw.scan_type = .active;
        try self.startRawScan(&raw, false);
    }

    pub fn getApRecordsInto(self: *WiFi, records: []ApRecord) Error![]ApRecord {
        try self.requireInitialized();
        if (records.len == 0) return error.InvalidArgument;
        var count: u16 = @intCast(records.len);
        try check(esp_wifi_scan_get_ap_records(&count, records.ptr));
        return records[0..count];
    }

    pub fn getStaMac(self: *WiFi) Error![6]u8 {
        try self.requireInitialized();
        var mac: [6]u8 = undefined;
        try check(espz_wifi_get_sta_mac(&mac));
        return mac;
    }

    pub fn setPowerSave(self: *WiFi, ps: PowerSave) Error!void {
        try self.requireInitialized();
        try check(espz_wifi_set_power_save(@intFromEnum(ps)));
    }

    pub fn getPowerSave(self: *WiFi) Error!PowerSave {
        try self.requireInitialized();
        var ps: u8 = 0;
        try check(espz_wifi_get_power_save(&ps));
        return std.meta.intToEnum(PowerSave, ps) catch error.EspIdfFailure;
    }

    pub fn setMaxTxPower(self: *WiFi, quarter_dbm: i8) Error!void {
        try self.requireInitialized();
        try check(espz_wifi_set_max_tx_power(quarter_dbm));
    }

    pub fn setProtocolMask(self: *WiFi, mode: Mode, mask: u8) Error!void {
        try self.requireInitialized();
        if (mode == .apsta) return error.InvalidArgument;
        try check(espz_wifi_set_protocol_mask(@intFromEnum(mode), mask));
    }

    pub fn setBandwidth(self: *WiFi, mode: Mode, bw: Bandwidth) Error!void {
        try self.requireInitialized();
        if (mode == .apsta) return error.InvalidArgument;
        try check(espz_wifi_set_bandwidth(@intFromEnum(mode), @intFromEnum(bw)));
    }

    pub fn setChannel(self: *WiFi, primary: u8, second: u8) Error!void {
        try self.requireInitialized();
        if (primary == 0 or primary > 14) return error.InvalidArgument;
        if (second > 2) return error.InvalidArgument;
        try check(espz_wifi_set_channel(primary, second));
    }

    fn requireInitialized(self: *const WiFi) Error!void {
        if (!self.initialized) return error.NotInitialized;
    }
};

fn check(result: EspError) Error!void {
    switch (result) {
        esp_ok => return,
        esp_err_no_mem => return error.OutOfMemory,
        esp_err_invalid_arg => return error.InvalidArgument,
        esp_err_invalid_state => return error.InvalidState,
        esp_err_not_found => return error.NotFound,
        esp_err_invalid_size => return error.BufferTooSmall,
        else => return error.EspIdfFailure,
    }
}

fn mapEventError(err: esp_event.Error) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidArgument => error.InvalidArgument,
        error.InvalidState => error.InvalidState,
        error.NotFound => error.NotFound,
        error.EspIdfFailure => error.EspIdfFailure,
    };
}

fn validateStaConfig(cfg: WiFi.StaConfig) Error!void {
    if (cfg.ssid.len == 0 or cfg.ssid.len > 32) return error.InvalidArgument;
    if (cfg.password.len > 64) return error.InvalidArgument;
    if (cfg.password.len > 0 and cfg.password.len < 8) return error.InvalidArgument;
}

fn validateApConfig(cfg: WiFi.ApConfig) Error!void {
    if (cfg.ssid.len == 0 or cfg.ssid.len > 32) return error.InvalidArgument;
    if (cfg.password.len > 63) return error.InvalidArgument;
    if (cfg.password.len > 0 and cfg.password.len < 8) return error.InvalidArgument;
    if (cfg.channel > 14) return error.InvalidArgument;
    if (cfg.max_connection == 0) return error.InvalidArgument;
}

test "check maps common esp-idf error codes" {
    try check(esp_ok);
    try std.testing.expectError(error.OutOfMemory, check(esp_err_no_mem));
    try std.testing.expectError(error.InvalidArgument, check(esp_err_invalid_arg));
    try std.testing.expectError(error.InvalidState, check(esp_err_invalid_state));
    try std.testing.expectError(error.NotFound, check(esp_err_not_found));
    try std.testing.expectError(error.BufferTooSmall, check(esp_err_invalid_size));
}

test "validateStaConfig enforces ssid and password constraints" {
    try validateStaConfig(.{ .ssid = "ssid", .password = "password" });
    try std.testing.expectError(error.InvalidArgument, validateStaConfig(.{ .ssid = "", .password = "password" }));
    try std.testing.expectError(error.InvalidArgument, validateStaConfig(.{ .ssid = "ok", .password = "short" }));
}

test "validateApConfig enforces range and password policy" {
    try validateApConfig(.{ .ssid = "espz-ap", .password = "", .channel = 6, .max_connection = 4 });
    try std.testing.expectError(error.InvalidArgument, validateApConfig(.{ .ssid = "", .password = "", .channel = 6, .max_connection = 4 }));
    try std.testing.expectError(error.InvalidArgument, validateApConfig(.{ .ssid = "espz-ap", .password = "short", .channel = 6, .max_connection = 4 }));
    try std.testing.expectError(error.InvalidArgument, validateApConfig(.{ .ssid = "espz-ap", .password = "", .channel = 15, .max_connection = 4 }));
    try std.testing.expectError(error.InvalidArgument, validateApConfig(.{ .ssid = "espz-ap", .password = "", .channel = 6, .max_connection = 0 }));
}
