# esp_wifi package

## 对应 ESP-IDF component

- `esp_wifi`

## 模块职责

- 提供 `esp_wifi` 的 sdkconfig 强类型映射（`config.zig`）。
- 提供单一 Zig 运行时入口结构：`WiFi`（定义于 `wifi.zig`，由 `root.zig` 导出）。
- 通过 `c_helper.c/.h` 封装复杂 C 结构（含 bit-field/union 细节），避免在 Zig 侧直接拼装 `wifi_config_t`。

## 对外 API 约束

外部调用方应只通过 `idf.esp_wifi.WiFi` 操作 Wi-Fi（加上 `config` 用于 sdkconfig 生成）。

`WiFi` 结构内包含：

- 类型：`Mode` / `PowerSave` / `Bandwidth`
- 配置：`StaConfig` / `ApConfig` / `ScanConfig` / `IpConfig`
- 数据：`ScanRecord`

核心方法（节选）：

- 生命周期：`init` / `deinit` / `start` / `stop`
- STA/AP：`startSta` / `configureSta` / `connectSta` / `disconnectSta` / `startAp` / `configureAp`
- 扫描：`scan`
- 事件与低层辅助：`registerAnyWifiEventHandler` / `registerWifiEventHandler` / `startAsyncScan` / `getApRecordsInto`
- 功耗与链路：`setPowerSave` / `getPowerSave` / `setMaxTxPower`
- PHY 参数：`setProtocolMask` / `setBandwidth` / `setChannel`

## Zig + C helper 分层

- `wifi.zig`：
  - 统一对外 API；
  - 输入校验与错误映射（`esp_err_t` -> Zig error）；
  - 资源状态跟踪（initialized/started/mode）；
  - 仅暴露 `esp_wifi` 本体能力，不混入 `esp_netif` 的 IP/DHCP 事件与配置。
- `c_helper.c/.h`：
  - 负责调用 ESP-IDF 原生 API；
  - 处理 `wifi_config_t` 等复杂字段写入；
  - 提供稳定 ABI 给 Zig 外部函数声明。

## 边界

- 本模块是 binding/runtime 封装层，不包含应用层联网业务状态机。
- 示例业务流程请放在 `examples/`；模块内部只保留可复用 Wi-Fi 能力。
