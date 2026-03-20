const std = @import("std");

pub const EspError = i32;
pub const esp_ok: EspError = 0;

const esp_err_no_mem: EspError = 0x101;
const esp_err_invalid_arg: EspError = 0x102;
const esp_err_invalid_state: EspError = 0x103;
const esp_err_not_found: EspError = 0x105;

pub const Error = error{
    OutOfMemory,
    InvalidArgument,
    InvalidState,
    NotFound,
    EspIdfFailure,
};

pub const EventBase = [*c]const u8;
pub const EventLoopHandle = ?*anyopaque;
pub const EventHandler = *const fn (?*anyopaque, EventBase, i32, ?*anyopaque) callconv(.c) void;

pub const any_base: EventBase = null;
pub const any_id: i32 = -1;
pub const no_affinity: i32 = -1;

pub const LoopArgs = extern struct {
    queue_size: i32,
    task_name: ?[*:0]const u8,
    task_priority: u32,
    task_stack_size: u32,
    task_core_id: i32,
};

extern fn esp_event_loop_create(event_loop_args: *const LoopArgs, event_loop: *EventLoopHandle) EspError;
extern fn esp_event_loop_delete(event_loop: EventLoopHandle) EspError;
extern fn esp_event_loop_create_default() EspError;
extern fn esp_event_loop_delete_default() EspError;
extern fn esp_event_loop_run(event_loop: EventLoopHandle, ticks_to_run: u32) EspError;
extern fn esp_event_handler_register(
    event_base: EventBase,
    event_id: i32,
    event_handler: EventHandler,
    event_handler_arg: ?*anyopaque,
) EspError;
extern fn esp_event_handler_unregister(
    event_base: EventBase,
    event_id: i32,
    event_handler: EventHandler,
) EspError;
extern fn esp_event_handler_register_with(
    event_loop: EventLoopHandle,
    event_base: EventBase,
    event_id: i32,
    event_handler: EventHandler,
    event_handler_arg: ?*anyopaque,
) EspError;
extern fn esp_event_handler_unregister_with(
    event_loop: EventLoopHandle,
    event_base: EventBase,
    event_id: i32,
    event_handler: EventHandler,
) EspError;
extern fn esp_event_post_to(
    event_loop: EventLoopHandle,
    event_base: EventBase,
    event_id: i32,
    event_data: ?*const anyopaque,
    event_data_size: usize,
    ticks_to_wait: u32,
) EspError;

pub const EventLoop = struct {
    handle: EventLoopHandle,

    pub fn create(args: LoopArgs) Error!EventLoop {
        var handle: EventLoopHandle = null;
        try check(esp_event_loop_create(&args, &handle));
        return .{ .handle = handle };
    }

    pub fn createDefault() Error!void {
        try check(esp_event_loop_create_default());
    }

    pub fn deleteDefault() Error!void {
        try check(esp_event_loop_delete_default());
    }

    pub fn delete(self: *EventLoop) Error!void {
        try self.requireHandle();
        try check(esp_event_loop_delete(self.handle));
        self.handle = null;
    }

    pub fn run(self: *EventLoop, ticks_to_run: u32) Error!void {
        try self.requireHandle();
        try check(esp_event_loop_run(self.handle, ticks_to_run));
    }

    pub fn register(self: *EventLoop, event_base: EventBase, event_id: i32, handler: EventHandler, arg: ?*anyopaque) Error!void {
        try self.requireHandle();
        try check(esp_event_handler_register_with(self.handle, event_base, event_id, handler, arg));
    }

    pub fn unregister(self: *EventLoop, event_base: EventBase, event_id: i32, handler: EventHandler) Error!void {
        try self.requireHandle();
        try check(esp_event_handler_unregister_with(self.handle, event_base, event_id, handler));
    }

    pub fn registerAny(self: *EventLoop, event_base: EventBase, handler: EventHandler, arg: ?*anyopaque) Error!void {
        try self.register(event_base, any_id, handler, arg);
    }

    pub fn unregisterAny(self: *EventLoop, event_base: EventBase, handler: EventHandler) Error!void {
        try self.unregister(event_base, any_id, handler);
    }

    pub fn post(self: *EventLoop, event_base: EventBase, event_id: i32, event_data: ?*const anyopaque, event_data_size: usize, ticks_to_wait: u32) Error!void {
        try self.requireHandle();
        try check(esp_event_post_to(self.handle, event_base, event_id, event_data, event_data_size, ticks_to_wait));
    }

    pub fn requireHandle(self: *const EventLoop) Error!void {
        if (self.handle == null) return error.InvalidState;
    }
};

pub fn registerDefault(event_base: EventBase, event_id: i32, handler: EventHandler, arg: ?*anyopaque) Error!void {
    try check(esp_event_handler_register(event_base, event_id, handler, arg));
}

pub fn unregisterDefault(event_base: EventBase, event_id: i32, handler: EventHandler) Error!void {
    try check(esp_event_handler_unregister(event_base, event_id, handler));
}

pub fn registerDefaultAny(event_base: EventBase, handler: EventHandler, arg: ?*anyopaque) Error!void {
    try registerDefault(event_base, any_id, handler, arg);
}

pub fn unregisterDefaultAny(event_base: EventBase, handler: EventHandler) Error!void {
    try unregisterDefault(event_base, any_id, handler);
}

fn check(result: EspError) Error!void {
    switch (result) {
        esp_ok => return,
        esp_err_no_mem => return error.OutOfMemory,
        esp_err_invalid_arg => return error.InvalidArgument,
        esp_err_invalid_state => return error.InvalidState,
        esp_err_not_found => return error.NotFound,
        else => return error.EspIdfFailure,
    }
}

test "check maps esp_event error codes" {
    try check(esp_ok);
    try std.testing.expectError(error.OutOfMemory, check(esp_err_no_mem));
    try std.testing.expectError(error.InvalidArgument, check(esp_err_invalid_arg));
    try std.testing.expectError(error.InvalidState, check(esp_err_invalid_state));
    try std.testing.expectError(error.NotFound, check(esp_err_not_found));
}
