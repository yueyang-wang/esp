const esp = @import("esp");

const rom = esp.component.esp_rom;
const freertos = esp.component.freertos;
const heap = esp.component.heap;
const esp_sr = esp.component.esp_sr;

export fn zig_esp_main() callconv(.c) void {
    _ = rom.esp_rom_printf("esp_sr_test: starting\n");
    _ = rom.esp_rom_printf(
        "heap: free=%u internal=%u\n",
        heap.freeHeapSize(),
        heap.freeInternalHeapSize(),
    );

    var aec = esp_sr.Aec.init(.{
        .sample_rate = 16_000,
        .filter_length = 4,
        .channel_num = 1,
        .mode = .voip_high_perf,
    }) catch {
        _ = rom.esp_rom_printf("esp_sr_test: AEC init failed\n");
        while (true) freertos.delay(1000);
    };
    defer aec.deinit();

    var ns = esp_sr.Ns.init(.{
        .frame_length = .ms10,
        .mode = .medium,
        .sample_rate = 16_000,
    }) catch {
        _ = rom.esp_rom_printf("esp_sr_test: NS init failed\n");
        while (true) freertos.delay(1000);
    };
    defer ns.deinit();

    var agc = esp_sr.Agc.init(.{
        .mode = .mode_2,
        .sample_rate = 16_000,
        .gain_db = 15,
        .limiter_enable = true,
        .target_level_dbfs = -3,
    }) catch {
        _ = rom.esp_rom_printf("esp_sr_test: AGC init failed\n");
        while (true) freertos.delay(1000);
    };
    defer agc.deinit();

    const chunk = aec.getChunksize() catch 0;
    _ = rom.esp_rom_printf("esp_sr_test: AEC chunk=%d\n", chunk);
    _ = rom.esp_rom_printf("esp_sr_test: NS/AGC initialized\n");

    while (true) {
        freertos.delay(1000);
    }
}
