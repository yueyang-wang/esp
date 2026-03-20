# ESP

Zig-first ESP-IDF bindings for writing ESP32 firmware in pure Zig.

[中文 README](./README.zh-CN.md)

## Table Of Contents
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Repository layout](#repository-layout)
- [Core concepts](#core-concepts)
- [Common commands](#common-commands)
- [Build options](#build-options)

## Prerequisites

- Zig: use the Xtensa-capable fork from [embed-zig/esp-zig-bootstrap](https://github.com/embed-zig/esp-zig-bootstrap)
- ESP-IDF v5.x

Recommended:

```bash
cd examples/lcd_battery
zig build idf-build \
  -Dbuild_config=board/esp32s3_szp/build_config.zig \
  -Dbsp=board/esp32s3_szp/bsp.zig \
  -Desp_idf=/path/to/esp-idf
```

Or use the environment manually:

```bash
export ESP_IDF=/path/to/esp-idf
source "$ESP_IDF/export.sh"
```

## Quick start

```bash
cd examples/lcd_battery
zig build flash-monitor \
  -Dbuild_config=board/esp32s3_szp/build_config.zig \
  -Dbsp=board/esp32s3_szp/bsp.zig \
  -Dport=/dev/cu.usbmodem1301 \
  -Desp_idf="$ESP_IDF" \
  -Dtimeout=15
```

## Repository layout

```text
.
├── build.zig
├── src/
│   ├── esp_mod.zig          # root Zig API: esp.component / esp.hal / esp.runtime
│   ├── idf_mod.zig          # root IDF helpers: sdkconfig / partition / build
│   ├── component/           # 1:1 ESP-IDF component bindings
│   ├── hal/                 # board-facing hardware abstractions
│   ├── runtime/             # reusable runtime helpers
│   └── idf/                 # build, sdkconfig, partition integration
├── test/
│   ├── convention_checks.zig
│   └── runners/            # component/example discovery and execution
└── examples/
    ├── aec_7210_8311/
    ├── aec_7210_8311_loopback/
    └── lcd_battery/
```

## Core concepts

### Component bindings

Each directory under `src/component/` maps to one ESP-IDF component.

- `esp_mod.zig`: runtime Zig API
- `idf_mod.zig`: build metadata and sdkconfig export
- `sdkconfig.zig`: owned config surface
- `c_helper.c` / `c_helper.h`: optional thin C shims

### Firmware examples and tests

Runnable demos live under `examples/<app>/` and usually contain:

- `build.zig`
- `board/`
- `src/main.zig`

Component-owned test apps live under `src/component/<module>/test/` with the same `build.zig` / `board/` / `src/main.zig` shape.

Both examples and component test apps require `-Dbuild_config=...` and `-Dbsp=...`.

### Build flow

`zig build` drives the whole pipeline:

1. Generate sdkconfig and partition data from board config
2. Scaffold a temporary IDF project
3. Build Zig firmware as a static library
4. Run `idf.py build`
5. Optionally flash and monitor

## Common commands

```bash
zig build
zig build test
zig build component-compile
zig build example-compile
zig build -l
```

Build one runnable example:

```bash
cd examples/lcd_battery
zig build build \
  -Dbuild_config=board/esp32s3_szp/build_config.zig \
  -Dbsp=board/esp32s3_szp/bsp.zig
```

Build one component-owned test app:

```bash
cd src/component/esp_system/test
zig build build \
  -Dbuild_config=board/compile/build_config.zig \
  -Dbsp=board/compile/bsp.zig
```

Example workflow commands:

```bash
zig build <app>-configure -Dbuild_config=<path> -Dbsp=<path> -Desp_idf=/path/to/esp-idf
zig build <app>-idf-build -Dbuild_config=<path> -Dbsp=<path> -Desp_idf=/path/to/esp-idf
zig build <app>-flash -Dbuild_config=<path> -Dbsp=<path> -Dport=/dev/cu.xxx -Desp_idf=/path/to/esp-idf
zig build <app>-monitor -Dbuild_config=<path> -Dbsp=<path> -Dport=/dev/cu.xxx -Desp_idf=/path/to/esp-idf
zig build <app>-flash-monitor -Dbuild_config=<path> -Dbsp=<path> -Dport=/dev/cu.xxx -Desp_idf=/path/to/esp-idf
```

## Build options

Common options:

- `-Dbuild_config=<path>`: required board config file
- `-Dbsp=<path>`: required board BSP file
- `-Dbuild_dir=<dir>`: generated build output directory
- `-Desp_idf=<path>`: ESP-IDF root
- `-Dport=<serial>`: serial port for flash and monitor
- monitor baud: read from `build_config` / generated sdkconfig, not from a `-D` option
- `-Dtimeout=<seconds>`: auto-exit monitor after N seconds
