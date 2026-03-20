# esp_event

Sdkconfig binding for the ESP-IDF `esp_event` component.

## ESP-IDF component

Maps to [`esp_event`](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/api-reference/system/esp_event.html).

## Module boundary

Provides:

- typed sdkconfig definitions for the event loop library, including loop profiling, ISR posting, and system event queue/task sizing;
- runtime Zig bindings for `esp_event` loop creation, deletion, dispatch, and handler registration.

This module owns generic `esp_event` runtime APIs. Component-specific event IDs and payload structs should stay with their owning component.

## Dependencies

No runtime dependencies.
