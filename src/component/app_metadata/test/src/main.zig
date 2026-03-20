const esp = @import("esp");

const rom = esp.component.esp_rom;
const freertos = esp.component.freertos;
const ota = esp.component.app_metadata.ota;

fn logState(label: [*:0]const u8, partition: ota.PartitionHandle) void {
    const state = ota.getPartitionState(partition) catch {
        _ = rom.esp_rom_printf("%s: state unavailable\n", label);
        return;
    };
    _ = rom.esp_rom_printf("%s: state=%u\n", label, @intFromEnum(state));
}

export fn zig_esp_main() callconv(.c) void {
    _ = rom.esp_rom_printf("app_metadata_test: starting\n");

    ota.markValid() catch {
        _ = rom.esp_rom_printf("app_metadata_test: markValid failed (normal on first boot)\n");
    };

    const running = ota.getRunningPartition() catch {
        _ = rom.esp_rom_printf("app_metadata_test: running partition unavailable\n");
        while (true) freertos.delay(1000);
    };
    _ = rom.esp_rom_printf("app_metadata_test: running partition ok\n");
    logState("running", running);

    const next = ota.getNextUpdatePartition() catch {
        _ = rom.esp_rom_printf("app_metadata_test: next update partition unavailable\n");
        while (true) freertos.delay(1000);
    };
    _ = rom.esp_rom_printf("app_metadata_test: next update partition ok\n");
    logState("next", next);

    while (true) {
        freertos.delay(1000);
        _ = rom.esp_rom_printf("app_metadata_test: heartbeat\n");
    }
}
