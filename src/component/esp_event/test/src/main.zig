const esp = @import("esp");

const rom = esp.component.esp_rom;
const freertos = esp.component.freertos;
const esp_event = esp.component.esp_event;

const test_event_base: [:0]const u8 = "esp_event_test";

fn testEventHandler(arg: ?*anyopaque, event_base: esp_event.event.EventBase, event_id: i32, event_data: ?*anyopaque) callconv(.c) void {
    _ = event_base;
    _ = event_data;

    const counter_ptr: *u32 = @ptrCast(@alignCast(arg.?));
    counter_ptr.* +%= 1;
    _ = rom.esp_rom_printf("esp_event_test: handler fired id=%ld count=%u\n", event_id, counter_ptr.*);
}

export fn zig_esp_main() callconv(.c) void {
    _ = rom.esp_rom_printf("esp_event_test: starting\n");

    var loop = esp_event.EventLoop.create(.{
        .queue_size = 4,
        .task_name = null,
        .task_priority = 0,
        .task_stack_size = 0,
        .task_core_id = esp_event.event.no_affinity,
    }) catch {
        _ = rom.esp_rom_printf("esp_event_test: loop create failed\n");
        while (true) freertos.delay(1000);
    };
    defer loop.delete() catch {};

    var handled_count: u32 = 0;
    loop.register(@ptrCast(test_event_base.ptr), 7, &testEventHandler, &handled_count) catch {
        _ = rom.esp_rom_printf("esp_event_test: register failed\n");
        while (true) freertos.delay(1000);
    };
    defer loop.unregister(@ptrCast(test_event_base.ptr), 7, &testEventHandler) catch {};

    _ = rom.esp_rom_printf("esp_event_test: private loop ready\n");

    while (true) {
        loop.run(0) catch {
            _ = rom.esp_rom_printf("esp_event_test: loop run failed\n");
        };
        _ = rom.esp_rom_printf("esp_event_test: heartbeat handled=%u\n", handled_count);
        freertos.delay(1000);
    }
}
