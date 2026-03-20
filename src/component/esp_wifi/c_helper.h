#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef struct espz_wifi_sta_config {
    const uint8_t *ssid;
    uint8_t ssid_len;
    const uint8_t *password;
    uint8_t password_len;
    uint16_t listen_interval;
} espz_wifi_sta_config_t;

typedef struct espz_wifi_ap_config {
    const uint8_t *ssid;
    uint8_t ssid_len;
    const uint8_t *password;
    uint8_t password_len;
    uint8_t channel;
    uint8_t max_connection;
    bool hidden;
} espz_wifi_ap_config_t;

typedef struct espz_wifi_scan_config {
    uint8_t channel;
    bool show_hidden;
    bool block_until_done;
    uint16_t max_results;
} espz_wifi_scan_config_t;

typedef struct espz_wifi_scan_record {
    uint8_t ssid[32];
    int8_t rssi;
    uint8_t channel;
    uint8_t authmode;
} espz_wifi_scan_record_t;

int32_t espz_wifi_runtime_init(void);
int32_t espz_wifi_runtime_deinit(void);

int32_t espz_wifi_set_mode(uint8_t mode);
int32_t espz_wifi_start(void);
int32_t espz_wifi_stop(void);
int32_t espz_wifi_connect(void);
int32_t espz_wifi_disconnect(void);

int32_t espz_wifi_set_sta_config(const espz_wifi_sta_config_t *cfg);
int32_t espz_wifi_set_ap_config(const espz_wifi_ap_config_t *cfg);

int32_t espz_wifi_scan(
    const espz_wifi_scan_config_t *cfg,
    espz_wifi_scan_record_t *out_records,
    uint16_t out_cap,
    uint16_t *out_count);
int32_t espz_wifi_get_sta_mac(uint8_t out_mac[6]);

int32_t espz_wifi_set_power_save(uint8_t ps);
int32_t espz_wifi_get_power_save(uint8_t *out_ps);
int32_t espz_wifi_set_max_tx_power(int8_t quarter_dbm);

int32_t espz_wifi_set_protocol_mask(uint8_t mode, uint8_t mask);
int32_t espz_wifi_set_bandwidth(uint8_t mode, uint8_t bw);
int32_t espz_wifi_set_channel(uint8_t primary, uint8_t second);
