const embed = @import("embed");
const binding = @import("binding.zig");
const sync = @import("sync");

const Handle = binding.Handle;
const pd_true = binding.pd_true;
const poll_ticks: u32 = 1;

pub const Error = error{
    CreateFailed,
    InvalidCapacity,
};

pub const SendResult = sync.channel.SendResult;
pub const RecvResult = sync.channel.RecvResult;

pub fn Channel(comptime T: type) type {
    comptime {
        if (@sizeOf(T) == 0) @compileError("freertos.Channel does not support zero-sized element types");
    }

    return struct {
        queue: Handle = null,
        state_lock: Handle = null,
        send_lock: Handle = null,
        ack: Handle = null,
        capacity: usize,
        closed: bool = false,
        recv_waiters: u32 = 0,

        const Self = @This();

        pub fn init(allocator: embed.mem.Allocator, capacity: usize) anyerror!Self {
            _ = allocator;
            if (capacity > embed.math.maxInt(u32)) return error.InvalidCapacity;

            var self = Self{
                .capacity = capacity,
            };
            errdefer self.deinit();

            const queue_len: u32 = if (capacity == 0) 1 else @intCast(capacity);
            self.queue = binding.espz_queue_create(queue_len, @sizeOf(T)) orelse
                return error.CreateFailed;
            self.state_lock = binding.espz_semaphore_create_mutex() orelse
                return error.CreateFailed;

            if (capacity == 0) {
                self.send_lock = binding.espz_semaphore_create_mutex() orelse
                    return error.CreateFailed;
                self.ack = binding.espz_semaphore_create_binary() orelse
                    return error.CreateFailed;
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.close();
            deleteSemaphore(&self.ack);
            deleteSemaphore(&self.send_lock);
            deleteSemaphore(&self.state_lock);
            deleteQueue(&self.queue);
        }

        pub fn close(self: *Self) void {
            if (self.state_lock == null) return;
            self.lock();
            self.closed = true;
            self.unlock();
        }

        pub fn send(self: *Self, value: T) anyerror!SendResult() {
            return if (self.capacity == 0)
                self.sendUnbuffered(value)
            else
                self.sendBuffered(value);
        }

        pub fn recv(self: *Self) anyerror!RecvResult(T) {
            return if (self.capacity == 0)
                self.recvUnbuffered()
            else
                self.recvBuffered();
        }

        pub fn recvTimeout(self: *Self, timeout_ms: u32) anyerror!RecvResult(T) {
            const timeout_ticks = msToTicks(timeout_ms);
            return if (self.capacity == 0)
                self.recvUnbufferedTimeout(timeout_ticks)
            else
                self.recvBufferedTimeout(timeout_ticks);
        }

        fn sendBuffered(self: *Self, value: T) SendResult() {
            var item = value;
            while (true) {
                if (self.isClosed()) return .{ .ok = false };
                if (binding.espz_queue_send(self.queue, @ptrCast(&item), poll_ticks) == pd_true) {
                    return .{ .ok = true };
                }
            }
        }

        fn recvBuffered(self: *Self) RecvResult(T) {
            while (true) {
                var item: T = undefined;
                if (binding.espz_queue_receive(self.queue, @ptrCast(&item), poll_ticks) == pd_true) {
                    return .{ .value = item, .ok = true };
                }
                if (self.isClosedAndEmpty()) {
                    return .{ .value = undefined, .ok = false };
                }
            }
        }

        fn sendUnbuffered(self: *Self, value: T) SendResult() {
            const send_lock = self.send_lock orelse unreachable;
            lockSemaphore(send_lock);
            defer _ = binding.espz_semaphore_give(send_lock);

            var item = value;
            while (true) {
                if (self.isClosed()) return .{ .ok = false };
                if (self.hasWaitingReceiver()) {
                    if (binding.espz_queue_send(self.queue, @ptrCast(&item), poll_ticks) == pd_true) {
                        break;
                    }
                } else {
                    pause();
                }
            }

            const ack = self.ack orelse unreachable;
            while (true) {
                if (binding.espz_semaphore_take(ack, poll_ticks) == pd_true) {
                    return .{ .ok = true };
                }
                if (self.isClosed() and binding.espz_queue_messages_waiting(self.queue) == 0) {
                    return .{ .ok = false };
                }
            }
        }

        fn recvBufferedTimeout(self: *Self, timeout_ticks: u32) RecvResult(T) {
            var remaining: u32 = timeout_ticks;
            while (true) {
                var item: T = undefined;
                const wait = @min(poll_ticks, remaining);
                if (binding.espz_queue_receive(self.queue, @ptrCast(&item), wait) == pd_true) {
                    return .{ .value = item, .ok = true };
                }
                if (self.isClosedAndEmpty()) {
                    return .{ .value = undefined, .ok = false };
                }
                if (remaining <= poll_ticks) {
                    return .{ .value = undefined, .ok = false };
                }
                remaining -= poll_ticks;
            }
        }

        fn recvUnbufferedTimeout(self: *Self, timeout_ticks: u32) RecvResult(T) {
            var remaining: u32 = timeout_ticks;
            while (true) {
                self.lock();
                self.recv_waiters += 1;
                self.unlock();

                var item: T = undefined;
                const wait = @min(poll_ticks, remaining);
                const received = binding.espz_queue_receive(self.queue, @ptrCast(&item), wait) == pd_true;

                self.lock();
                if (self.recv_waiters != 0) self.recv_waiters -= 1;
                const closed = self.closed;
                const empty = binding.espz_queue_messages_waiting(self.queue) == 0;
                self.unlock();

                if (received) {
                    _ = binding.espz_semaphore_give(self.ack);
                    return .{ .value = item, .ok = true };
                }
                if (closed and empty) {
                    return .{ .value = undefined, .ok = false };
                }
                if (remaining <= poll_ticks) {
                    return .{ .value = undefined, .ok = false };
                }
                remaining -= poll_ticks;
            }
        }

        fn recvUnbuffered(self: *Self) RecvResult(T) {
            while (true) {
                self.lock();
                self.recv_waiters += 1;
                self.unlock();

                var item: T = undefined;
                const received = binding.espz_queue_receive(self.queue, @ptrCast(&item), poll_ticks) == pd_true;

                self.lock();
                if (self.recv_waiters != 0) self.recv_waiters -= 1;
                const closed = self.closed;
                const empty = binding.espz_queue_messages_waiting(self.queue) == 0;
                self.unlock();

                if (received) {
                    _ = binding.espz_semaphore_give(self.ack);
                    return .{ .value = item, .ok = true };
                }
                if (closed and empty) {
                    return .{ .value = undefined, .ok = false };
                }
            }
        }

        fn hasWaitingReceiver(self: *Self) bool {
            self.lock();
            defer self.unlock();
            return self.recv_waiters != 0 and !self.closed;
        }

        fn isClosed(self: *Self) bool {
            self.lock();
            defer self.unlock();
            return self.closed;
        }

        fn isClosedAndEmpty(self: *Self) bool {
            self.lock();
            defer self.unlock();
            return self.closed and binding.espz_queue_messages_waiting(self.queue) == 0;
        }

        fn lock(self: *Self) void {
            lockSemaphore(self.state_lock);
        }

        fn unlock(self: *Self) void {
            _ = binding.espz_semaphore_give(self.state_lock);
        }
    };
}

fn msToTicks(ms: u32) u32 {
    const hz: u64 = binding.espz_freertos_tick_rate_hz();
    if (hz == 0) return ms;
    const ticks = ((@as(u64, ms) * hz) + 999) / 1000;
    return @intCast(@min(ticks, @as(u64, embed.math.maxInt(u32))));
}

fn lockSemaphore(handle: Handle) void {
    while (binding.espz_semaphore_take(handle, binding.max_delay) != pd_true) {}
}

fn pause() void {
    binding.espz_freertos_task_delay(poll_ticks);
}

fn deleteSemaphore(handle: *Handle) void {
    if (handle.*) |value| {
        binding.espz_semaphore_delete(value);
        handle.* = null;
    }
}

fn deleteQueue(handle: *Handle) void {
    if (handle.*) |value| {
        binding.espz_queue_delete(value);
        handle.* = null;
    }
}
