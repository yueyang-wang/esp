const esp_idf = @import("esp_idf");

pub const board = .{
    .name = @as([]const u8, "board.h106"),
    .chip = @as([]const u8, "esp32s3"),
    .target_arch = @as([]const u8, "xtensa"),
    .target_arch_config_flag = @as([]const u8, "CONFIG_IDF_TARGET_ARCH_XTENSA"),
    .target_config_flag = @as([]const u8, "CONFIG_IDF_TARGET_ESP32S3"),
};

pub const partition_table = esp_idf.PartitionTable.make(.{
    .entries = &.{
        .{ .name = "nvs", .kind = .data, .subtype = .nvs, .size = 0x6000 },
        .{ .name = "otadata", .kind = .data, .subtype = .ota, .size = 0x2000 },
        .{ .name = "phy_init", .kind = .data, .subtype = .phy, .size = 0x1000 },
        .{ .name = "ota_0", .kind = .app, .subtype = .ota_0, .size = 0x500000 },
        .{ .name = "ota_1", .kind = .app, .subtype = .ota_1, .size = 0x500000 },
        .{
            .name = "data_0",
            .kind = .data,
            .subtype = .spiffs,
            .size = 0x200000,
        },
        .{
            .name = "data_1",
            .kind = .data,
            .subtype = .spiffs,
            .size = 0x200000,
        },
        .{
            .name = "tmp",
            .kind = .data,
            .subtype = .spiffs,
            .size = 0x40000,
            .data = esp_idf.PartitionTable.data.spiffs("partitions/spiffs"),
        },
        .{
            .name = "coredump",
            .kind = .data,
            .subtype = .{ .custom_name = "coredump" },
            .size = 0x10000,
        },
    },
});

pub const config = esp_idf.SdkConfig.make(.{
    .esptool_py = .{
        .esptoolpy_flashsize = "16MB",
        .esptoolpy_flashsize_16mb = true,
        .esptoolpy_flashsize_2mb = false,
    },
    .esp_system = .{
        .esp_default_cpu_freq_mhz = 240,
        .esp_default_cpu_freq_mhz_80 = false,
        .esp_default_cpu_freq_mhz_160 = false,
        .esp_default_cpu_freq_mhz_240 = true,
        .main_task_stack_size = 4096,
        .task_wdt_timeout_s = 30,
        .task_wdt_check_idle_task_cpu1 = false,
    },
    .esp_psram = .{
        .spiram = true,
        .spiram_mode_quad = false,
        .spiram_mode_oct = true,
        .spiram_speed_80m = true,
        .spiram_speed_40m = false,
        .spiram_speed_120m = false,
    },
    .lwip = .{
        .lwip_ppp_support = true,
    },
    .espcoredump = .{
        .esp_coredump_enable_to_flash = true,
        .esp_coredump_enable_to_none = false,
    },
});
