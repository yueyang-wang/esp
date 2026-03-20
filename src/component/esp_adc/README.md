# esp_adc

Maps to ESP-IDF component: `esp_adc`.

## Boundary

Provides Zig wrappers for ADC oneshot mode: init and read raw values. Does not cover continuous mode, calibration, attenuation config, or ADC2 on Wi‑Fi cores.

## Runtime API

- `Oneshot.init(unit, channel)` — create oneshot ADC handle
- `Oneshot.read()` — read raw ADC value
- `check(EspError)` — convert ESP-IDF result to Zig error

## Dependencies

- ESP-IDF: `esp_adc`
- No other espz modules

## Test Baseline

The component-owned compile test includes an ELF layout golden at `test/board/compile/golden/elf_layout.readelf.txt`. It captures the loadable section and program-header layout of `esp_adc_test.elf` for the `board/compile` profile.
