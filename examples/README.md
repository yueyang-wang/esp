# Examples

示例目录只保留面向用户的 runnable demo；component 自己的 smoke test 和 compile/run test 已迁到 `src/component/<module>/test/`。

每个示例的构建、烧录、监控与运行结果都写在该示例自己的 `README.md` 中。

当前示例：

- `aec_7210_8311/`：ES7210+ES8311 音频回声消除（AEC+MASE+NS+AGC）演示。
- `aec_7210_8311_loopback/`：ES7210+ES8311 实时 AEC 回环测试示例。
- `lcd_battery/`：SZP 板卡 LCD 电量条显示示例。

说明：

- 示例的 SDK 配置由 Zig 聚合生成，不依赖 `sdkconfig.defaults`；常用工作流步骤为 `zig build generate-sdkconfig`、`zig build build`、`zig build flash`、`zig build monitor` 与 `zig build flash-monitor`。
- 统一使用 `-Dbuild_config=board/<name>/build_config.zig` 与 `-Dbsp=board/<name>/bsp.zig` 选择板级配置与运行时 BSP。
- 示例级 board 目录统一采用拆分结构：`build_config.zig` 负责 build-time sdkconfig/profile，`bsp.zig` 负责运行时板级导出，例如 `pins`、外设接线与 helper。
