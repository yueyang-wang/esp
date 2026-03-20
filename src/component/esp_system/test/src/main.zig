const esp = @import("esp");

const rom = esp.component.esp_rom;
const freertos = esp.component.freertos;
const heap = esp.component.heap;

export fn zig_esp_main() callconv(.c) void {
    _ = rom.esp_rom_printf("esp_system_test: booted\n");
    _ = rom.esp_rom_printf(
        "heap: free=%u min_free=%u internal=%u\n",
        heap.freeHeapSize(),
        heap.minimumFreeHeapSize(),
        heap.freeInternalHeapSize(),
    );

    while (true) {
        _ = rom.esp_rom_printf("esp_system_test: heartbeat\n");
        freertos.delay(200);
    }
}
