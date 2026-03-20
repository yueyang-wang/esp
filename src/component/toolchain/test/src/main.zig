const esp = @import("esp");

const rom = esp.component.esp_rom;
const freertos = esp.component.freertos;

export fn iram_fast_function() linksection(".iram1") callconv(.c) void {
    iram_counter +%= 1;
}

export var iram_counter: u32 linksection(".dram0.data") = 0;
export const rodata_magic: u32 linksection(".rodata") = 0x5A5A5A5A;
export var noinit_boot_count: u32 linksection(".noinit") = undefined;

fn noinline_helper(x: u32) callconv(.c) u32 {
    @setRuntimeSafety(false);
    return x *% 31 +% 7;
}

export fn zig_exported_callback() callconv(.c) void {
    _ = rom.esp_rom_printf("toolchain_test: callback reached\n");
}

export fn zig_esp_main() callconv(.c) void {
    _ = rom.esp_rom_printf("toolchain_test: starting\n");
    _ = rom.esp_rom_printf("iram_fast_function @ %p\n", @as(*const anyopaque, @ptrCast(&iram_fast_function)));
    _ = rom.esp_rom_printf("iram_counter @ %p = %u\n", @as(*const anyopaque, @ptrCast(&iram_counter)), iram_counter);
    _ = rom.esp_rom_printf("rodata_magic @ %p = 0x%X\n", @as(*const anyopaque, @ptrCast(&rodata_magic)), rodata_magic);

    noinit_boot_count +%= 1;
    _ = rom.esp_rom_printf("noinit_boot_count @ %p = %u\n", @as(*const anyopaque, @ptrCast(&noinit_boot_count)), noinit_boot_count);
    _ = rom.esp_rom_printf("noinline_helper(100) = %u\n", noinline_helper(100));

    zig_exported_callback();

    while (true) {
        freertos.delay(1000);
    }
}
