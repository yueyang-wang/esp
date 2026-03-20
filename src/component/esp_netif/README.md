# esp_netif

Runtime and sdkconfig binding for the ESP-IDF `esp_netif` component.

## ESP-IDF component

Maps to [`esp_netif`](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/api-reference/network/esp_netif.html).

## Module boundary

Provides:

- sdkconfig bindings for the network interface abstraction layer;
- runtime helpers for `esp_netif_init()` and default Wi-Fi STA/AP netif lifecycle;
- IP-layer event helpers for `IP_EVENT`;
- netif-owned operations such as hostname, DHCP client, and IPv4/DNS accessors.

This module owns IP/DHCP concerns. Wi-Fi driver bindings should stay in `esp_wifi`.
