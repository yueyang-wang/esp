const std = @import("std");
const hal_wifi = @import("embed").hal.wifi;
const runtime_io = @import("embed").runtime.io;

const esp_event = @import("../component/esp_event/event.zig");
const EspNetif = @import("../component/esp_netif/netif.zig");
const esp_wifi = @import("../component/esp_wifi/wifi.zig");
const EspWiFi = esp_wifi.WiFi;
const freertos_queue = @import("../component/freertos/queue.zig");
const runtime_impl = @import("../runtime/io.zig");

const max_pending_scan: usize = 16;
const event_queue_depth: u32 = 32;
const private_loop_task_name: [*:0]const u8 = "espz_wifi_evt";
const private_loop_task_priority: u32 = 5;
const private_loop_task_stack_size: u32 = 3072;
const EventQueue = freertos_queue.Queue(hal_wifi.WifiEvent);

pub const Driver = struct {
    wifi: EspWiFi,
    sta_netif: EspNetif.Handle,
    ap_netif: EspNetif.Handle,
    private_loop: esp_event.EventLoop,
    io: *runtime_impl.IO,
    event_queue: EventQueue,
    event_read_fd: runtime_io.fd_t,
    event_write_fd: runtime_io.fd_t,
    bridge_registered: bool = false,
    connected: bool = false,
    connecting: bool = false,
    ap_running: bool = false,
    disconnect_requested: bool = false,
    current_ssid: [32]u8 = [_]u8{0} ** 32,
    current_ssid_len: u8 = 0,
    current_bssid: [6]u8 = [_]u8{0} ** 6,
    has_current_bssid: bool = false,
    current_channel: ?u8 = null,
    tx_power: ?i8 = null,
    country_code: [2]u8 = "01".*,
    power_save: hal_wifi.PowerSaveMode = .none,
    roaming_cfg: hal_wifi.RoamingConfig = .{},
    rssi_threshold: i8 = -127,

    pub fn init() hal_wifi.Error!Driver {
        EspNetif.init() catch |err| return mapNetifError(err);
        errdefer EspNetif.deinit() catch {};

        const sta_netif = EspNetif.createDefaultWifiSta() catch |err| return mapNetifError(err);
        errdefer EspNetif.destroyDefaultWifi(sta_netif) catch {};

        const ap_netif = EspNetif.createDefaultWifiAp() catch |err| return mapNetifError(err);
        errdefer EspNetif.destroyDefaultWifi(ap_netif) catch {};

        const wifi = EspWiFi.init() catch |err| return mapInitError(err);
        errdefer {
            var copy = wifi;
            copy.deinit() catch {};
        }

        const io = runtime_impl.acquireGlobal() catch return error.WifiError;
        errdefer runtime_impl.releaseGlobal();

        var event_queue = EventQueue.init(event_queue_depth) catch return error.WifiError;
        errdefer event_queue.deinit();

        const event_channel = io.createChannel() catch return error.WifiError;
        errdefer io.closeChannel(event_channel.read_fd);

        const private_loop = esp_event.EventLoop.create(.{
            .queue_size = @intCast(event_queue_depth),
            .task_name = private_loop_task_name,
            .task_priority = private_loop_task_priority,
            .task_stack_size = private_loop_task_stack_size,
            .task_core_id = esp_event.no_affinity,
        }) catch |err| return mapOpError(err);
        errdefer {
            var loop = private_loop;
            loop.delete() catch {};
        }

        return .{
            .wifi = wifi,
            .sta_netif = sta_netif,
            .ap_netif = ap_netif,
            .private_loop = private_loop,
            .io = io,
            .event_queue = event_queue,
            .event_read_fd = event_channel.read_fd,
            .event_write_fd = event_channel.write_fd,
        };
    }

    pub fn deinit(self: *Driver) void {
        if (self.bridge_registered) {
            self.wifi.event_handler.unregisterAny(&self.wifi, forwardWifiEventToPrivateLoop) catch {};
            self.private_loop.unregisterAny(esp_wifi.getWifiEventBase(), handlePrivateWifiEvent) catch {};
            self.bridge_registered = false;
        }
        self.private_loop.delete() catch {};
        self.io.closeChannel(self.event_read_fd);
        self.event_queue.deinit();
        runtime_impl.releaseGlobal();
        self.wifi.deinit() catch {};
        EspNetif.destroyDefaultWifi(self.ap_netif) catch {};
        EspNetif.destroyDefaultWifi(self.sta_netif) catch {};
        EspNetif.deinit() catch {};
    }

    pub fn connect(self: *Driver, ssid: []const u8, password: []const u8) void {
        self.connectWithConfig(.{
            .ssid = ssid,
            .password = password,
        });
    }

    pub fn connectWithConfig(self: *Driver, cfg: hal_wifi.ConnectConfig) void {
        self.ensureBridge() catch return self.emitConnectionFailure(.unknown);

        self.connected = false;
        self.connecting = true;
        self.disconnect_requested = false;
        self.ap_running = false;
        self.current_channel = if (cfg.channel_hint == 0) null else cfg.channel_hint;
        self.has_current_bssid = false;
        setSsid(self, cfg.ssid);

        self.wifi.startSta(.{
            .ssid = cfg.ssid,
            .password = cfg.password,
        }) catch return self.emitConnectionFailure(.unknown);
        self.wifi.connectSta() catch return self.emitConnectionFailure(.unknown);
    }

    pub fn reconnect(self: *Driver) void {
        if (self.current_ssid_len == 0) return;
        self.ensureBridge() catch return self.emitConnectionFailure(.unknown);

        self.connecting = true;
        self.disconnect_requested = false;
        self.wifi.connectSta() catch return self.emitConnectionFailure(.unknown);
    }

    pub fn disconnect(self: *Driver) void {
        self.disconnect_requested = true;
        self.connecting = false;
        self.wifi.disconnectSta() catch {
            self.disconnect_requested = false;
            self.queueEvent(.{ .disconnected = .user_request });
            return;
        };
    }

    pub fn isConnected(self: *const Driver) bool {
        return self.connected;
    }

    pub fn eventFd(self: *const Driver) i32 {
        const mutable = @constCast(self);
        mutable.ensureBridge() catch return -1;
        return self.event_read_fd;
    }

    pub fn readEvents(self: *Driver, out: []hal_wifi.WifiEvent) hal_wifi.Error!usize {
        if (out.len == 0) return 0;

        var wake_buf: [32]u8 = undefined;
        while ((self.io.readChannel(self.event_read_fd, wake_buf[0..]) catch 0) > 0) {}

        var count: usize = 0;
        while (count < out.len) : (count += 1) {
            out[count] = self.event_queue.receive(0) catch break;
        }

        if (count == out.len and self.event_queue.waiting() > 0) {
            self.signalWake();
        }

        return count;
    }

    pub fn getRssi(_: *const Driver) ?i8 {
        return null;
    }

    pub fn getMac(self: *const Driver) ?hal_wifi.Mac {
        var copy = self.*;
        return copy.wifi.getStaMac() catch null;
    }

    pub fn getChannel(self: *const Driver) ?u8 {
        return self.current_channel;
    }

    pub fn getSsid(self: *const Driver) ?[]const u8 {
        if (self.current_ssid_len == 0) return null;
        return self.current_ssid[0..self.current_ssid_len];
    }

    pub fn getBssid(self: *const Driver) ?hal_wifi.Mac {
        if (!self.has_current_bssid) return null;
        return self.current_bssid;
    }

    pub fn getPhyMode(_: *const Driver) ?hal_wifi.PhyMode {
        return null;
    }

    pub fn scanStart(self: *Driver, cfg: hal_wifi.ScanConfig) hal_wifi.Error!void {
        try self.ensureBridge();
        self.wifi.startAsyncScan(.{
            .channel = cfg.channel,
            .show_hidden = cfg.show_hidden,
        }) catch |err| return mapOpError(err);
    }

    pub fn setPowerSave(self: *Driver, mode: hal_wifi.PowerSaveMode) void {
        self.power_save = mode;
        self.wifi.setPowerSave(switch (mode) {
            .none => .none,
            .min_modem => .min_modem,
            .max_modem => .max_modem,
        }) catch {};
    }

    pub fn getPowerSave(self: *const Driver) hal_wifi.PowerSaveMode {
        return self.power_save;
    }

    pub fn setRoaming(self: *Driver, cfg: hal_wifi.RoamingConfig) void {
        self.roaming_cfg = cfg;
    }

    pub fn setRssiThreshold(self: *Driver, rssi: i8) void {
        self.rssi_threshold = rssi;
    }

    pub fn setTxPower(self: *Driver, power: i8) void {
        self.tx_power = power;
        self.wifi.setMaxTxPower(power) catch {};
    }

    pub fn getTxPower(self: *const Driver) ?i8 {
        return self.tx_power;
    }

    pub fn startAp(self: *Driver, cfg: hal_wifi.ApConfig) hal_wifi.Error!void {
        try self.ensureBridge();
        self.wifi.startAp(.{
            .ssid = cfg.ssid,
            .password = cfg.password,
            .channel = cfg.channel,
            .max_connection = cfg.max_connections,
            .hidden = cfg.hidden,
        }) catch |err| return mapOpError(err);
        self.ap_running = true;
    }

    pub fn stopAp(self: *Driver) void {
        self.wifi.stopAp() catch {};
        self.ap_running = false;
    }

    pub fn isApRunning(self: *const Driver) bool {
        return self.ap_running;
    }

    pub fn getStaList(_: *const Driver) []const hal_wifi.StaInfo {
        return &[_]hal_wifi.StaInfo{};
    }

    pub fn deauthSta(_: *Driver, _: hal_wifi.Mac) void {}

    pub fn setProtocol(self: *Driver, proto: hal_wifi.Protocol) void {
        var mask: u8 = 0;
        if (proto.b) mask |= 1 << 0;
        if (proto.g) mask |= 1 << 1;
        if (proto.n) mask |= 1 << 2;
        if (proto.lr) mask |= 1 << 3;
        self.wifi.setProtocolMask(.sta, mask) catch {};
    }

    pub fn setBandwidth(self: *Driver, bw: hal_wifi.Bandwidth) void {
        self.wifi.setBandwidth(.sta, switch (bw) {
            .bw_20 => .ht20,
            .bw_40 => .ht40,
        }) catch {};
    }

    pub fn setCountryCode(self: *Driver, code: [2]u8) void {
        self.country_code = code;
    }

    pub fn getCountryCode(self: *const Driver) [2]u8 {
        return self.country_code;
    }

    fn ensureBridge(self: *Driver) hal_wifi.Error!void {
        if (self.bridge_registered) return;
        self.private_loop.registerAny(esp_wifi.getWifiEventBase(), handlePrivateWifiEvent, self) catch |err| return mapOpError(err);
        errdefer self.private_loop.unregisterAny(esp_wifi.getWifiEventBase(), handlePrivateWifiEvent) catch {};

        self.wifi.event_handler.registerAny(&self.wifi, forwardWifiEventToPrivateLoop, self) catch |err| return mapOpError(err);
        self.bridge_registered = true;
    }

    fn emitConnectionFailure(self: *Driver, reason: hal_wifi.FailReason) void {
        self.connecting = false;
        self.connected = false;
        self.queueEvent(.{ .connection_failed = reason });
    }

    fn queueEvent(self: *Driver, event: hal_wifi.WifiEvent) void {
        self.event_queue.send(&event, 0) catch return;
        self.signalWake();
    }

    fn signalWake(self: *Driver) void {
        const signal = [_]u8{1};
        _ = self.io.writeChannel(self.event_write_fd, &signal) catch {};
    }
};

fn forwardWifiEventToPrivateLoop(arg: ?*anyopaque, event_base: esp_wifi.EventBase, event_id: i32, event_data: ?*anyopaque) callconv(.c) void {
    const self: *Driver = @ptrCast(@alignCast(arg orelse return));
    const event_data_size = wifiEventDataSize(event_id, event_data);
    self.private_loop.post(event_base, event_id, if (event_data) |data| data else null, event_data_size, 0) catch {};
}

fn handlePrivateWifiEvent(arg: ?*anyopaque, event_base: esp_wifi.EventBase, event_id: i32, event_data: ?*anyopaque) callconv(.c) void {
    const self: *Driver = @ptrCast(@alignCast(arg orelse return));
    if (!esp_wifi.isWifiEventBase(event_base)) return;

    switch (event_id) {
        @intFromEnum(esp_wifi.WifiEvent.scan_done) => {
            var success = true;
            if (event_data) |raw| {
                const scan_done: *const esp_wifi.StaScanDoneEvent = @ptrCast(@alignCast(raw));
                success = scan_done.status == 0;
            }

            if (success) {
                var records: [max_pending_scan]esp_wifi.ApRecord = undefined;
                const used = self.wifi.getApRecordsInto(records[0..]) catch &[_]esp_wifi.ApRecord{};
                for (used) |record| {
                    self.queueEvent(.{ .scan_result = apInfoFromRecord(record) });
                }
            }

            self.queueEvent(.{ .scan_done = .{ .success = success } });
        },
        @intFromEnum(esp_wifi.WifiEvent.sta_connected) => {
            self.connecting = false;
            self.connected = true;
            self.disconnect_requested = false;

            if (event_data) |raw| {
                const connected: *const esp_wifi.StaConnectedEvent = @ptrCast(@alignCast(raw));
                self.current_channel = connected.channel;
                self.current_bssid = connected.bssid;
                self.has_current_bssid = true;
            }

            self.queueEvent(.{ .connected = {} });
        },
        @intFromEnum(esp_wifi.WifiEvent.sta_disconnected) => {
            self.connected = false;
            self.has_current_bssid = false;

            const raw_reason: u8 = if (event_data) |raw| blk: {
                const disconnected: *const esp_wifi.StaDisconnectedEvent = @ptrCast(@alignCast(raw));
                break :blk disconnected.reason;
            } else 0;

            if (self.disconnect_requested) {
                self.disconnect_requested = false;
                self.connecting = false;
                self.queueEvent(.{ .disconnected = .user_request });
                return;
            }

            const disconnect_reason = mapDisconnectReason(raw_reason);
            if (self.connecting) {
                self.connecting = false;
                self.queueEvent(.{ .connection_failed = mapFailReason(raw_reason, disconnect_reason) });
            } else {
                self.queueEvent(.{ .disconnected = disconnect_reason });
            }
        },
        @intFromEnum(esp_wifi.WifiEvent.ap_start) => {
            self.ap_running = true;
        },
        else => {},
    }
}

fn wifiEventDataSize(event_id: i32, event_data: ?*anyopaque) usize {
    if (event_data == null) return 0;

    return switch (event_id) {
        @intFromEnum(esp_wifi.WifiEvent.scan_done) => @sizeOf(esp_wifi.StaScanDoneEvent),
        @intFromEnum(esp_wifi.WifiEvent.sta_connected) => @sizeOf(esp_wifi.StaConnectedEvent),
        @intFromEnum(esp_wifi.WifiEvent.sta_disconnected) => @sizeOf(esp_wifi.StaDisconnectedEvent),
        else => 0,
    };
}

fn setSsid(self: *Driver, ssid: []const u8) void {
    const n = @min(ssid.len, self.current_ssid.len);
    @memset(self.current_ssid[0..], 0);
    @memcpy(self.current_ssid[0..n], ssid[0..n]);
    self.current_ssid_len = @intCast(n);
}

fn apInfoFromRecord(record: esp_wifi.ApRecord) hal_wifi.ApInfo {
    var ssid_len: usize = 0;
    while (ssid_len < record.ssid.len and record.ssid[ssid_len] != 0) : (ssid_len += 1) {}

    var out: hal_wifi.ApInfo = .{
        .ssid = [_]u8{0} ** 32,
        .ssid_len = @intCast(@min(ssid_len, 32)),
        .bssid = record.bssid,
        .channel = record.primary,
        .rssi = record.rssi,
        .auth_mode = mapAuthMode(@intFromEnum(record.authmode)),
    };
    @memcpy(out.ssid[0..out.ssid_len], record.ssid[0..out.ssid_len]);
    return out;
}

fn mapAuthMode(raw: u8) hal_wifi.AuthMode {
    return switch (raw) {
        0 => .open,
        1 => .wep,
        2 => .wpa_psk,
        3 => .wpa2_psk,
        4 => .wpa_wpa2_psk,
        5 => .wpa2_enterprise,
        6 => .wpa3_psk,
        7 => .wpa2_wpa3_psk,
        8 => .wpa3_enterprise,
        else => .open,
    };
}

fn mapDisconnectReason(raw: u8) hal_wifi.DisconnectReason {
    return switch (raw) {
        2, 202 => .auth_failed,
        201, 210, 211, 212 => .ap_not_found,
        200, 203, 204, 205 => .connection_lost,
        else => .unknown,
    };
}

fn mapFailReason(raw: u8, disconnect_reason: hal_wifi.DisconnectReason) hal_wifi.FailReason {
    return switch (disconnect_reason) {
        .auth_failed => .auth_failed,
        .ap_not_found => .ap_not_found,
        .connection_lost => switch (raw) {
            200, 204 => .timeout,
            else => .unknown,
        },
        else => .unknown,
    };
}

fn mapInitError(err: anyerror) hal_wifi.Error {
    return switch (err) {
        error.InvalidArgument => error.InvalidConfig,
        error.InvalidState => error.Busy,
        else => error.WifiError,
    };
}

fn mapNetifError(err: anyerror) hal_wifi.Error {
    return switch (err) {
        error.InvalidArgument => error.InvalidConfig,
        error.InvalidState => error.Busy,
        else => error.WifiError,
    };
}

fn mapOpError(err: anyerror) hal_wifi.Error {
    return switch (err) {
        error.InvalidArgument => error.InvalidConfig,
        error.InvalidState => error.Busy,
        error.NotFound => error.Timeout,
        else => error.WifiError,
    };
}
