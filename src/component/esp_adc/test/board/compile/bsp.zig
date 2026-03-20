pub const config = @import("build_config").config;

pub const pins = .{
    .battery_adc = .{
        .unit = @as(u8, 0),
        .channel = @as(u8, 9),
        .empty_mv = @as(u32, 3300),
        .full_mv = @as(u32, 4200),
        .divider_num = @as(u32, 2),
        .divider_den = @as(u32, 1),
    },
};
