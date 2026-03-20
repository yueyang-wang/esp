const esp = @import("esp");
const board = @import("board");

const rom = esp.component.esp_rom;
const freertos = esp.component.freertos;
const esp_adc = esp.component.esp_adc;

const battery = board.pins.battery_adc;

fn rawToMilliVolts(raw: i32) u32 {
    const sensed_mv: u32 = @intCast(@divTrunc(raw * 3300, 4095));
    return sensed_mv * battery.divider_num / battery.divider_den;
}

export fn zig_esp_main() callconv(.c) void {
    _ = rom.esp_rom_printf("esp_adc_test: starting\n");

    var adc = esp_adc.Oneshot.init(@intCast(battery.unit), @intCast(battery.channel)) catch {
        _ = rom.esp_rom_printf("esp_adc_test: oneshot init failed\n");
        while (true) freertos.delay(1000);
    };
    defer adc.deinit() catch {};

    while (true) {
        const raw = adc.read() catch {
            _ = rom.esp_rom_printf("esp_adc_test: read failed\n");
            freertos.delay(1000);
            continue;
        };
        const mv = rawToMilliVolts(raw);
        _ = rom.esp_rom_printf("esp_adc_test: raw=%d approx_mv=%u\n", raw, mv);
        freertos.delay(1000);
    }
}
