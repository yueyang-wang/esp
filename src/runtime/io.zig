const std = @import("std");
const freertos_task = @import("../component/freertos/task.zig");
const freertos_sync = @import("../component/freertos/sync.zig");
const freertos_queue = @import("../component/freertos/queue.zig");
const runtime = @import("embed").runtime;

const fd_t = runtime.io.fd_t;
const Channel = runtime.io.Channel;

pub const IO = struct {
    pub const ReadyCallback = runtime.io.ReadyCallback;
    pub const Config = struct {
        tick_rate_hz: u32 = 100,
        event_queue_depth: u32 = 128,
        channel_queue_depth: u32 = 64,
    };

    const EventKind = enum { read_ready, write_ready };
    const Event = struct {
        kind: EventKind,
        fd: fd_t,
    };

    const WatchEntry = struct {
        read: ?ReadyCallback = null,
        write: ?ReadyCallback = null,
    };

    const ChannelEntry = struct {
        queue: freertos_queue.Queue([1]u8),
        peer_fd: fd_t,
        owns_queue: bool,
    };

    allocator: std.mem.Allocator,
    watchers: std.AutoHashMap(fd_t, WatchEntry),
    events: freertos_queue.Queue(Event),
    wake_sem: freertos_sync.Semaphore,
    wait_set: freertos_queue.QueueSet,
    tick_rate_hz: u32,
    channels: std.AutoHashMap(fd_t, ChannelEntry),
    next_vfd: fd_t = -1,
    channel_queue_depth: u32,

    pub fn init(allocator: std.mem.Allocator) anyerror!@This() {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: Config) anyerror!@This() {
        if (config.tick_rate_hz == 0) return error.InvalidArgument;
        if (config.event_queue_depth == 0) return error.InvalidArgument;
        if (config.event_queue_depth == std.math.maxInt(u32)) return error.InvalidArgument;

        const q = try freertos_queue.Queue(Event).init(config.event_queue_depth);
        errdefer {
            var qq = q;
            qq.deinit();
        }

        var wake_sem = freertos_sync.Semaphore.initBinary(false) catch return error.InitFailed;
        errdefer wake_sem.deinit();

        var wait_set = try freertos_queue.QueueSet.init(config.event_queue_depth + 1);
        errdefer wait_set.deinit();

        try wait_set.addMember(q.rawHandle());
        errdefer _ = wait_set.removeMember(q.rawHandle()) catch {};

        try wait_set.addMember(wake_sem.rawHandle());
        errdefer _ = wait_set.removeMember(wake_sem.rawHandle()) catch {};

        return .{
            .allocator = allocator,
            .watchers = std.AutoHashMap(fd_t, WatchEntry).init(allocator),
            .events = q,
            .wake_sem = wake_sem,
            .wait_set = wait_set,
            .tick_rate_hz = config.tick_rate_hz,
            .channels = std.AutoHashMap(fd_t, ChannelEntry).init(allocator),
            .channel_queue_depth = config.channel_queue_depth,
        };
    }

    pub fn deinit(self: *@This()) void {
        var ch_it = self.channels.iterator();
        while (ch_it.next()) |entry| {
            var e = entry.value_ptr.*;
            if (!e.owns_queue) continue;
            e.queue.deinit();
        }
        self.channels.deinit();
        self.watchers.deinit();
        _ = self.wait_set.removeMember(self.events.rawHandle()) catch {};
        _ = self.wait_set.removeMember(self.wake_sem.rawHandle()) catch {};
        self.wait_set.deinit();
        self.wake_sem.deinit();
        self.events.deinit();
    }

    pub fn registerRead(self: *@This(), fd: fd_t, cb: ReadyCallback) anyerror!void {
        var gop = try self.watchers.getOrPut(fd);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        gop.value_ptr.read = cb;
    }

    pub fn registerWrite(self: *@This(), fd: fd_t, cb: ReadyCallback) anyerror!void {
        var gop = try self.watchers.getOrPut(fd);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        gop.value_ptr.write = cb;
    }

    pub fn unregister(self: *@This(), fd: fd_t) void {
        _ = self.watchers.remove(fd);
    }

    pub fn poll(self: *@This(), timeout_ms: i32) usize {
        const wait_ticks = self.timeoutMsToTicks(timeout_ms);
        const selected = self.wait_set.select(wait_ticks) orelse return 0;

        if (selected == self.wake_sem.rawHandle()) {
            self.drainWake();
            return self.drainReadyEvents();
        }
        if (selected == self.events.rawHandle()) {
            const first = self.events.receive(0) catch return 0;
            return self.dispatchEvent(first) + self.drainReadyEvents();
        }
        return 0;
    }

    pub fn wake(self: *@This()) void {
        _ = self.wake_sem.give();
    }

    pub fn createChannel(self: *@This()) anyerror!Channel {
        const read_fd = self.next_vfd;
        self.next_vfd -= 1;
        const write_fd = self.next_vfd;
        self.next_vfd -= 1;

        const q = try freertos_queue.Queue([1]u8).init(self.channel_queue_depth);
        errdefer {
            var qq = q;
            qq.deinit();
        }

        try self.channels.put(read_fd, .{
            .queue = q,
            .peer_fd = write_fd,
            .owns_queue = true,
        });
        errdefer _ = self.channels.remove(read_fd);

        try self.channels.put(write_fd, .{
            .queue = q,
            .peer_fd = read_fd,
            .owns_queue = false,
        });

        return .{ .read_fd = read_fd, .write_fd = write_fd };
    }

    pub fn readChannel(self: *@This(), fd: fd_t, buf: []u8) anyerror!usize {
        const entry = self.channels.getPtr(fd) orelse return error.InvalidArgument;
        var n: usize = 0;
        while (n < buf.len) {
            if (entry.queue.receive(0)) |b| {
                buf[n] = b[0];
                n += 1;
            } else |_| {
                break;
            }
        }
        return n;
    }

    pub fn writeChannel(self: *@This(), fd: fd_t, data: []const u8) anyerror!usize {
        const entry = self.channels.getPtr(fd) orelse return error.InvalidArgument;
        var n: usize = 0;
        while (n < data.len) {
            const byte = [1]u8{data[n]};
            entry.queue.send(&byte, 0) catch break;
            n += 1;
        }
        if (n > 0) {
            const read_fd = fd + 1;
            self.notifyReadReady(read_fd);
        }
        return n;
    }

    pub fn closeChannel(self: *@This(), fd: fd_t) void {
        if (self.channels.fetchRemove(fd)) |kv| {
            const entry = kv.value;
            _ = self.watchers.remove(fd);

            const peer = self.channels.fetchRemove(entry.peer_fd);
            if (peer) |peer_kv| {
                _ = self.watchers.remove(peer_kv.key);
            }

            if (entry.owns_queue) {
                var q = entry.queue;
                q.deinit();
            } else if (peer) |peer_kv| {
                var q = peer_kv.value.queue;
                q.deinit();
            }
        }
    }

    pub fn notifyReadReady(self: *@This(), fd: fd_t) void {
        self.pushEvent(.{ .kind = .read_ready, .fd = fd });
    }

    pub fn notifyWriteReady(self: *@This(), fd: fd_t) void {
        self.pushEvent(.{ .kind = .write_ready, .fd = fd });
    }

    fn drainReadyEvents(self: *@This()) usize {
        var callbacks_called: usize = 0;
        while (true) {
            const ev = self.events.receive(0) catch break;
            callbacks_called += self.dispatchEvent(ev);
        }
        return callbacks_called;
    }

    fn dispatchEvent(self: *@This(), ev: Event) usize {
        const watch = self.watchers.get(ev.fd) orelse return 0;
        return switch (ev.kind) {
            .read_ready => blk: {
                if (watch.read) |cb| {
                    cb.callback(cb.ptr, ev.fd);
                    break :blk 1;
                }
                break :blk 0;
            },
            .write_ready => blk: {
                if (watch.write) |cb| {
                    cb.callback(cb.ptr, ev.fd);
                    break :blk 1;
                }
                break :blk 0;
            },
        };
    }

    fn pushEvent(self: *@This(), ev: Event) void {
        self.events.send(&ev, 0) catch |err| switch (err) {
            error.QueueFull => {},
            else => {},
        };
    }

    fn drainWake(self: *@This()) void {
        while (self.wake_sem.take(0)) {}
    }

    fn timeoutMsToTicks(self: *const @This(), timeout_ms: i32) u32 {
        if (timeout_ms < 0) return std.math.maxInt(u32);
        if (timeout_ms == 0) return 0;
        const ms: u32 = @intCast(timeout_ms);
        return freertos_task.msToTicks(ms, self.tick_rate_hz);
    }
};

var global_io_storage: ?IO = null;
var global_io_ref_count: usize = 0;

pub fn acquireGlobal() anyerror!*IO {
    if (global_io_storage == null) {
        global_io_storage = try IO.init(std.heap.c_allocator);
    }
    global_io_ref_count += 1;
    return &global_io_storage.?;
}

pub fn global() ?*IO {
    if (global_io_storage == null) return null;
    return &global_io_storage.?;
}

pub fn releaseGlobal() void {
    if (global_io_ref_count == 0) return;
    global_io_ref_count -= 1;
    if (global_io_ref_count != 0) return;
    if (global_io_storage) |*io| {
        io.deinit();
        global_io_storage = null;
    }
}
