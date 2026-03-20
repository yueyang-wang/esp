const esp = @import("esp");
const board = @import("board");

const rom = esp.component.esp_rom;
const freertos = esp.component.freertos;
const led_strip = esp.component.led_strip;

const strip_pins = board.pins.led_strip;

export fn zig_esp_main() callconv(.c) void {
    _ = rom.esp_rom_printf(
        "led_strip_test: initializing on GPIO %d, %u LEDs\n",
        strip_pins.gpio,
        strip_pins.max_leds,
    );

    const strip = led_strip.LedStrip.initRmt(.{
        .gpio_num = strip_pins.gpio,
        .max_leds = strip_pins.max_leds,
    }, .{}) catch {
        _ = rom.esp_rom_printf("led_strip_test: init failed\n");
        return;
    };

    _ = rom.esp_rom_printf("led_strip_test: init ok, starting color cycle\n");
    strip.clear() catch {};

    var hue: u16 = 0;
    while (true) {
        strip.setPixelHsv(0, hue, 255, 25) catch {};
        strip.refresh() catch {};

        hue += 5;
        if (hue >= 360) hue = 0;
        freertos.delay(50);
    }
}
