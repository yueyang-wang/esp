const std = @import("std");
const esp = @import("esp");

const esp_netif = esp.component.esp_netif;
const esp_wifi = esp.component.esp_wifi;
const rom = esp.component.esp_rom;
const newlib = esp.component.newlib;
const freertos = esp.component.freertos;
const heap = esp.component.heap;

const WiFi = esp_wifi.WiFi;
const EventBase = esp_wifi.wifi.EventBase;
const WifiEvent = esp_wifi.wifi.WifiEvent;
const IpEvent = esp_netif.netif.IpEvent;
const ApRecord = esp_wifi.wifi.ApRecord;
const StaScanDoneEvent = esp_wifi.wifi.StaScanDoneEvent;
const StaDisconnectedEvent = esp_wifi.wifi.StaDisconnectedEvent;

fn wifiCheck(result: esp_wifi.wifi.Error!void) void {
    result catch {
        _ = rom.esp_rom_printf("FATAL WiFi error\n");
        newlib.abort();
    };
}

fn printSsid(ssid: anytype) void {
    const ssid_info = @typeInfo(@TypeOf(ssid));
    const ssid_len = switch (ssid_info) {
        .array => |info| info.len,
        else => @compileError("ssid must be an array"),
    };

    var len: usize = 0;
    while (len < ssid_len and ssid[len] != 0) : (len += 1) {}
    var buf: [33]u8 = undefined;
    const copy_len = @min(len, buf.len - 1);
    @memcpy(buf[0..copy_len], ssid[0..copy_len]);
    buf[copy_len] = 0;
    _ = rom.esp_rom_printf("  %-24s", @as([*:0]const u8, @ptrCast(&buf)));
}

fn logWifiError(what: [*:0]const u8, err: anyerror) void {
    const name = @errorName(err);
    _ = rom.esp_rom_printf("%s failed: %.*s\n", what, @as(c_int, @intCast(name.len)), name.ptr);
}

fn printScanResults(wifi: *WiFi) void {
    var records: [16]ApRecord = undefined;
    const used = wifi.getApRecordsInto(records[0..]) catch |err| {
        logWifiError("esp_wifi_scan_get_ap_records", err);
        return;
    };

    _ = rom.esp_rom_printf("esp_wifi_test: found %u networks:\n", @as(c_uint, @intCast(used.len)));
    for (used) |record| {
        printSsid(record.ssid);
        _ = rom.esp_rom_printf(
            "rssi=%d ch=%u auth=%u\n",
            @as(c_int, record.rssi),
            @as(c_uint, record.primary),
            @as(c_uint, @intCast(@intFromEnum(record.authmode))),
        );
    }
}

fn wifiEventHandler(
    arg: ?*anyopaque,
    event_base: EventBase,
    event_id: i32,
    event_data: ?*anyopaque,
) callconv(.c) void {
    const wifi_ptr: ?*WiFi = if (arg) |ptr| @ptrCast(@alignCast(ptr)) else null;
    if (esp_wifi.wifi.isWifiEventBase(event_base)) switch (event_id) {
        @intFromEnum(WifiEvent.scan_done) => {
            if (event_data) |raw| {
                const scan_done: *const StaScanDoneEvent = @ptrCast(@alignCast(raw));
                _ = rom.esp_rom_printf(
                    "esp_wifi_test: async scan done status=%d count=%u\n",
                    @as(c_uint, scan_done.status),
                    @as(c_uint, scan_done.number),
                );
            } else {
                _ = rom.esp_rom_printf("esp_wifi_test: async scan done\n");
            }
            if (wifi_ptr) |wifi| printScanResults(wifi);
        },
        @intFromEnum(WifiEvent.sta_connected) => {
            _ = rom.esp_rom_printf("esp_wifi_test: STA connected\n");
        },
        @intFromEnum(WifiEvent.sta_disconnected) => {
            if (event_data) |raw| {
                const disconnected: *const StaDisconnectedEvent = @ptrCast(@alignCast(raw));
                _ = rom.esp_rom_printf(
                    "esp_wifi_test: STA connection failed/disconnected reason=%u\n",
                    @as(c_uint, disconnected.reason),
                );
            } else {
                _ = rom.esp_rom_printf("esp_wifi_test: STA connection failed/disconnected\n");
            }
        },
        @intFromEnum(WifiEvent.ap_start) => {
            _ = rom.esp_rom_printf("esp_wifi_test: AP started\n");
        },
        else => {},
    } else if (esp_netif.netif.isIpEventBase(event_base) and event_id == @intFromEnum(IpEvent.sta_got_ip)) {
        _ = rom.esp_rom_printf("esp_wifi_test: STA got IP\n");
    }
}

fn registerEventHandlers(wifi: *WiFi) void {
    wifi.event_handler.registerAny(wifi, wifiEventHandler, wifi) catch |err| {
        logWifiError("esp_event_handler_register(WIFI_EVENT)", err);
        newlib.abort();
    };

    esp_netif.netif.registerIpEventHandler(.sta_got_ip, wifiEventHandler, wifi) catch |err| {
        logWifiError("esp_event_handler_register(IP_EVENT)", err);
        newlib.abort();
    };
}

fn startAsyncScan(wifi: *WiFi) void {
    wifi.startAsyncScan(.{
        .channel = 0,
        .show_hidden = true,
    }) catch |err| {
        logWifiError("esp_wifi_scan_start", err);
        return;
    };
    _ = rom.esp_rom_printf("esp_wifi_test: async scan started\n");
}

export fn zig_esp_main() callconv(.c) void {
    _ = rom.esp_rom_printf("esp_wifi_test: starting\n");
    _ = rom.esp_rom_printf("heap: free=%u min_free=%u\n", heap.freeHeapSize(), heap.minimumFreeHeapSize());

    esp_netif.netif.init() catch {
        _ = rom.esp_rom_printf("FATAL: netif init failed\n");
        newlib.abort();
    };
    _ = esp_netif.netif.createDefaultWifiSta() catch {
        _ = rom.esp_rom_printf("FATAL: createDefaultWifiSta failed\n");
        newlib.abort();
    };
    _ = esp_netif.netif.createDefaultWifiAp() catch {
        _ = rom.esp_rom_printf("FATAL: createDefaultWifiAp failed\n");
        newlib.abort();
    };

    var wifi = WiFi.init() catch {
        _ = rom.esp_rom_printf("FATAL: WiFi init failed\n");
        newlib.abort();
    };

    registerEventHandlers(&wifi);

    wifiCheck(wifi.setMode(.apsta));
    wifi.configureSta(.{
        .ssid = "example_wifi",
        .password = "example_password",
    }) catch {
        _ = rom.esp_rom_printf("FATAL: configureSta failed\n");
        newlib.abort();
    };
    wifi.configureAp(.{
        .ssid = "example_ap",
        .password = "",
        .channel = 6,
        .max_connection = 4,
        .hidden = false,
    }) catch {
        _ = rom.esp_rom_printf("FATAL: configureAp failed\n");
        newlib.abort();
    };

    wifiCheck(wifi.start());
    _ = rom.esp_rom_printf("esp_wifi_test: AP configured ssid=example_ap channel=6\n");

    startAsyncScan(&wifi);

    _ = rom.esp_rom_printf("esp_wifi_test: connecting to example_wifi ...\n");
    wifiCheck(wifi.connectSta());

    while (true) {
        freertos.delay(1000);
    }
}
