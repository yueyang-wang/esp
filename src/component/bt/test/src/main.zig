const esp = @import("esp");

const bt = esp.component.bt;
const freertos = esp.component.freertos;
const esp_rom = esp.component.esp_rom;
const nvs_flash = esp.component.nvs_flash;
const newlib = esp.component.newlib;
const heap = esp.component.heap;

export fn zig_esp_main() callconv(.c) void {
    run() catch {
        esp_rom.printf("FATAL: unrecoverable error\n", .{});
        newlib.abort();
    };
}

fn run() !void {
    esp_rom.printf("bt_test: starting\n", .{});
    _ = esp_rom.esp_rom_printf("heap: free=%u min_free=%u\n", heap.freeHeapSize(), heap.minimumFreeHeapSize());

    nvs_flash.init() catch {
        esp_rom.printf("nvs_flash: init failed, erasing...\n", .{});
        try nvs_flash.erase();
        try nvs_flash.init();
    };
    esp_rom.printf("nvs_flash: ok\n", .{});

    try bt.controller.init();
    try bt.controller.enable(.ble);
    esp_rom.printf("bt controller: initialized and enabled\n", .{});

    const callbacks: bt.VHci.HciCallbacks = .{
        .on_writable = onWritable,
        .on_readable = onReadable,
    };
    try bt.VHci.registerCallbacks(&callbacks);
    esp_rom.printf("bt_vhci: callbacks registered\n", .{});

    const reset_cmd = [_]u8{ 0x01, 0x03, 0x0C, 0x00 };
    const result = bt.VHci.tryWrite(reset_cmd[0..].ptr, @intCast(reset_cmd.len));
    switch (result) {
        .ok => esp_rom.printf("bt_vhci: HCI Reset sent ok\n", .{}),
        .would_block => esp_rom.printf("bt_vhci: tryWrite would_block\n", .{}),
        .invalid_length => esp_rom.printf("bt_vhci: tryWrite invalid_length\n", .{}),
    }

    while (true) {
        freertos.delay(1000);
    }
}

fn onWritable() callconv(.c) void {
    esp_rom.printf("bt_vhci: callback writable\n", .{});
}

fn onReadable(data: [*]u8, len: u16) callconv(.c) c_int {
    _ = data;
    _ = len;
    esp_rom.printf("bt_vhci: callback readable\n", .{});
    return 0;
}
