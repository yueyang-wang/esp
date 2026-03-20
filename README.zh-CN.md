# ESP

面向 Zig 优先的 ESP-IDF 绑定，用纯 Zig 编写 ESP32 固件。

[English README](./README.md)

## 目录
- [前置要求](#前置要求)
- [快速开始](#快速开始)
- [仓库结构](#仓库结构)
- [核心概念](#核心概念)
- [常用命令](#常用命令)
- [构建选项](#构建选项)

## 前置要求

- Zig：使用支持 Xtensa 的 fork，[embed-zig/esp-zig-bootstrap](https://github.com/embed-zig/esp-zig-bootstrap)
- ESP-IDF v5.x

推荐写法：

```bash
cd examples/lcd_battery
zig build idf-build \
  -Dbuild_config=board/esp32s3_szp/build_config.zig \
  -Dbsp=board/esp32s3_szp/bsp.zig \
  -Desp_idf=/path/to/esp-idf
```

或者手动设置环境：

```bash
export ESP_IDF=/path/to/esp-idf
source "$ESP_IDF/export.sh"
```

## 快速开始

```bash
cd examples/lcd_battery
zig build flash-monitor \
  -Dbuild_config=board/esp32s3_szp/build_config.zig \
  -Dbsp=board/esp32s3_szp/bsp.zig \
  -Dport=/dev/cu.usbmodem1301 \
  -Desp_idf="$ESP_IDF" \
  -Dtimeout=15
```

## 仓库结构

```text
.
├── build.zig
├── src/
│   ├── esp_mod.zig          # 顶层 Zig API：esp.component / esp.hal / esp.runtime
│   ├── idf_mod.zig          # 顶层 IDF 辅助入口：sdkconfig / partition / build
│   ├── component/           # 与 ESP-IDF 组件 1:1 对齐的绑定
│   ├── hal/                 # 面向板级的硬件抽象
│   ├── runtime/             # 可复用运行时辅助
│   └── idf/                 # build、sdkconfig、partition 集成
├── test/
│   ├── convention_checks.zig
│   └── runners/            # component/example 的扫描与执行逻辑
└── examples/
    ├── aec_7210_8311/
    ├── aec_7210_8311_loopback/
    └── lcd_battery/
```

## 核心概念

### 组件绑定

`src/component/` 下的每个目录都对应一个 ESP-IDF 组件。

- `esp_mod.zig`：运行时 Zig API
- `idf_mod.zig`：构建元数据和 sdkconfig 导出
- `sdkconfig.zig`：该组件自维护的配置面
- `c_helper.c` / `c_helper.h`：可选的薄 C shim

### 固件示例与测试

面向用户的可运行示例位于 `examples/<app>/` 下，通常包含：

- `build.zig`
- `board/`
- `src/main.zig`

component 自己维护的测试 app 位于 `src/component/<module>/test/`，目录形态同样是 `build.zig` / `board/` / `src/main.zig`。

无论是 example 还是 component test app，构建时都必须同时传入 `-Dbuild_config=...` 和 `-Dbsp=...`。

### 构建流程

`zig build` 负责驱动整个流程：

1. 从板级配置生成 sdkconfig 和 partition 数据
2. 脚手架生成临时 IDF 工程
3. 把 Zig 固件编译为静态库
4. 运行 `idf.py build`
5. 按需执行烧录和串口监视

## 常用命令

```bash
zig build
zig build test
zig build component-compile
zig build example-compile
zig build -l
```

构建单个可运行示例：

```bash
cd examples/lcd_battery
zig build build \
  -Dbuild_config=board/esp32s3_szp/build_config.zig \
  -Dbsp=board/esp32s3_szp/bsp.zig
```

构建单个 component 自带测试 app：

```bash
cd src/component/esp_system/test
zig build build \
  -Dbuild_config=board/compile/build_config.zig \
  -Dbsp=board/compile/bsp.zig
```

示例工作流命令：

```bash
zig build <app>-configure -Dbuild_config=<path> -Dbsp=<path> -Desp_idf=/path/to/esp-idf
zig build <app>-idf-build -Dbuild_config=<path> -Dbsp=<path> -Desp_idf=/path/to/esp-idf
zig build <app>-flash -Dbuild_config=<path> -Dbsp=<path> -Dport=/dev/cu.xxx -Desp_idf=/path/to/esp-idf
zig build <app>-monitor -Dbuild_config=<path> -Dbsp=<path> -Dport=/dev/cu.xxx -Desp_idf=/path/to/esp-idf
zig build <app>-flash-monitor -Dbuild_config=<path> -Dbsp=<path> -Dport=/dev/cu.xxx -Desp_idf=/path/to/esp-idf
```

## 构建选项

常用选项：

- `-Dbuild_config=<path>`：必填，板级配置文件
- `-Dbsp=<path>`：必填，板级 BSP 文件
- `-Dbuild_dir=<dir>`：生成产物目录
- `-Desp_idf=<path>`：ESP-IDF 根目录
- `-Dport=<serial>`：烧录和监视使用的串口
- 串口监视波特率：从 `build_config` / 生成后的 sdkconfig 读取，不提供 `-D` 选项
- `-Dtimeout=<seconds>`：串口监视在 N 秒后自动退出
