const embed = @import("embed");
const binding = @import("binding.zig");
const heap_binding = @import("../heap/binding.zig");
const PacketMutex = @import("Mutex.zig");

pub const Mutex = @import("thread/Mutex.zig");
pub const Condition = @import("thread/Condition.zig");
pub const RwLock = @import("thread/RwLock.zig");

const CoreId = i32;
const Handle = binding.Handle;
const pd_true = binding.pd_true;
const no_affinity: CoreId = 0x7fff_ffff;
const max_u32: usize = 0xffff_ffff;
const ns_per_s: u64 = 1_000_000_000;
const max_u64: u64 = ~@as(u64, 0);

pub const Id = usize;
pub const max_name_len: usize = 15;
pub const default_stack_size: usize = 2048;

shared: *Shared,

const Self = @This();

const Shared = struct {
    lock: PacketMutex,
    done: Handle,
    state: State = .running_joinable,
    handle: Handle = null,
    destroy_fn: *const fn (*Shared) void,
};

const State = enum {
    running_joinable,
    running_detached,
    finished_pending_join,
    finished_detached,
};

pub fn spawn(config: anytype, comptime f: anytype, args: anytype) embed.Thread.SpawnError!Self {
    const Packet = SpawnPacket(@TypeOf(args), f);
    const raw = heap_binding.espz_heap_caps_malloc(
        @sizeOf(Packet),
        defaultInternalCaps(),
    ) orelse return error.OutOfMemory;
    const packet: *Packet = @ptrCast(@alignCast(raw));
    errdefer heap_binding.espz_heap_caps_free(raw);

    const lock = PacketMutex.init() catch return error.SystemResources;
    errdefer {
        var cleanup = lock;
        cleanup.deinit();
    }

    const done = binding.espz_semaphore_create_binary() orelse return error.SystemResources;
    errdefer binding.espz_semaphore_delete(done);

    packet.* = .{
        .shared = .{
            .lock = lock,
            .done = done,
            .destroy_fn = &Packet.destroy,
        },
        .args = args,
    };

    const stack_size = stackSizeToU32(config.stack_size) catch return error.SystemResources;
    const core_id = if (config.core_id) |cpu| cpu else no_affinity;

    var handle: Handle = null;
    if (binding.espz_freertos_thread_spawn(
        &Packet.entry,
        config.name,
        stack_size,
        packet,
        config.priority,
        &handle,
        core_id,
    ) != binding.pd_true) {
        return error.SystemResources;
    }

    packet.shared.handle = handle;
    return .{ .shared = &packet.shared };
}

pub fn join(self: Self) void {
    while (binding.espz_semaphore_take(self.shared.done, binding.max_delay) != pd_true) {}

    self.shared.lock.lock();
    self.shared.state = .finished_detached;
    self.shared.lock.unlock();

    self.shared.destroy_fn(self.shared);
}

pub fn detach(self: Self) void {
    var destroy_now = false;

    self.shared.lock.lock();
    switch (self.shared.state) {
        .running_joinable => self.shared.state = .running_detached,
        .finished_pending_join => {
            self.shared.state = .finished_detached;
            destroy_now = true;
        },
        .running_detached, .finished_detached => {},
    }
    self.shared.lock.unlock();

    if (destroy_now) {
        self.shared.destroy_fn(self.shared);
    }
}

pub fn yield() embed.Thread.YieldError!void {
    binding.espz_freertos_thread_yield();
}

pub fn sleep(ns: u64) void {
    const ticks = nsToTicksCeil(ns);
    sleepTicks(ticks);
}

pub fn sleepTicks(ticks: u32) void {
    if (ticks == 0) return;
    binding.espz_freertos_task_delay(ticks);
}

pub fn getCpuCount() embed.Thread.CpuCountError!usize {
    const count = binding.espz_freertos_cpu_count();
    if (count == 0) return error.Unsupported;
    return count;
}

pub fn getCurrentId() Id {
    const handle = binding.espz_freertos_current_task_handle() orelse
        @panic("freertos.Thread.getCurrentId: current task handle unavailable");
    return @intFromPtr(handle);
}

pub fn setName(name: []const u8) embed.Thread.SetNameError!void {
    if (name.len > max_name_len) return error.NameTooLong;
    return error.Unsupported;
}

pub fn getName(buf: *[max_name_len:0]u8) embed.Thread.GetNameError!?[]const u8 {
    const current_name = embed.mem.sliceTo(binding.espz_freertos_current_task_name(), 0);
    if (current_name.len == 0) return null;

    const len = @min(current_name.len, max_name_len);
    @memcpy(buf[0..len], current_name[0..len]);
    buf[len] = 0;
    return buf[0..len];
}

fn defaultInternalCaps() u32 {
    return heap_binding.espz_heap_malloc_cap_internal() | heap_binding.espz_heap_malloc_cap_8bit();
}

fn nsToTicksCeil(timeout_ns: u64) u32 {
    if (timeout_ns == 0) return 0;

    const tick_rate_hz = binding.espz_freertos_tick_rate_hz();
    if (tick_rate_hz == 0) return binding.max_delay;

    const tick_ns = ns_per_s / tick_rate_hz;
    if (tick_ns == 0) return binding.max_delay;

    const extra = tick_ns - 1;
    if (timeout_ns > max_u64 - extra) return binding.max_delay;
    const adjusted = timeout_ns + extra;
    const ticks = adjusted / tick_ns;
    if (ticks > binding.max_delay) return binding.max_delay;
    return @intCast(ticks);
}

fn stackSizeToU32(size: usize) error{InvalidStackSize}!u32 {
    if (size == 0 or size > max_u32) return error.InvalidStackSize;
    return @intCast(size);
}

fn SpawnPacket(comptime Args: type, comptime f: anytype) type {
    return struct {
        shared: Shared,
        args: Args,

        const Packet = @This();

        fn entry(ctx: ?*anyopaque) callconv(.c) void {
            const packet: *Packet = @ptrCast(@alignCast(ctx.?));
            invokeTask(packet.args);
            packet.finish();
            binding.espz_freertos_task_delete(null);
            unreachable;
        }

        fn invokeTask(args: Args) void {
            const ReturnType = @typeInfo(@TypeOf(f)).@"fn".return_type orelse void;
            if (comptime @typeInfo(ReturnType) == .error_union) {
                if (@call(.auto, f, args)) |_| {} else |_| {}
            } else {
                _ = @call(.auto, f, args);
            }
        }

        fn finish(packet: *Packet) void {
            var destroy_now = false;

            packet.shared.lock.lock();
            switch (packet.shared.state) {
                .running_joinable => packet.shared.state = .finished_pending_join,
                .running_detached => {
                    packet.shared.state = .finished_detached;
                    destroy_now = true;
                },
                .finished_pending_join, .finished_detached => {},
            }
            packet.shared.lock.unlock();

            if (destroy_now) {
                Packet.destroy(&packet.shared);
            } else {
                _ = binding.espz_semaphore_give(packet.shared.done);
            }
        }

        fn destroy(shared: *Shared) void {
            const packet: *Packet = @fieldParentPtr("shared", shared);
            binding.espz_semaphore_delete(packet.shared.done);
            packet.shared.lock.deinit();
            heap_binding.espz_heap_caps_free(packet);
        }
    };
}
