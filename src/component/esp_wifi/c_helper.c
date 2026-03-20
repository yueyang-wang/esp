#include <stdlib.h>
#include <string.h>

#include "esp_err.h"
#include "esp_wifi.h"
#include "nvs_flash.h"

#include "c_helper.h"

static bool s_runtime_initialized = false;

static esp_err_t init_nvs_storage(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    return err;
}

static esp_err_t mode_to_wifi_mode(uint8_t mode, wifi_mode_t *out)
{
    switch (mode) {
    case 1:
        *out = WIFI_MODE_STA;
        return ESP_OK;
    case 2:
        *out = WIFI_MODE_AP;
        return ESP_OK;
    case 3:
        *out = WIFI_MODE_APSTA;
        return ESP_OK;
    default:
        return ESP_ERR_INVALID_ARG;
    }
}

static esp_err_t mode_to_wifi_interface(uint8_t mode, wifi_interface_t *out)
{
    switch (mode) {
    case 1:
        *out = WIFI_IF_STA;
        return ESP_OK;
    case 2:
        *out = WIFI_IF_AP;
        return ESP_OK;
    default:
        return ESP_ERR_INVALID_ARG;
    }
}

static esp_err_t ensure_runtime_initialized(void)
{
    return s_runtime_initialized ? ESP_OK : ESP_ERR_INVALID_STATE;
}

int32_t espz_wifi_runtime_init(void)
{
    if (s_runtime_initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    esp_err_t err = init_nvs_storage();
    if (err != ESP_OK) {
        return err;
    }

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    err = esp_wifi_init(&cfg);
    if (err != ESP_OK) {
        return err;
    }

    s_runtime_initialized = true;
    return ESP_OK;
}

int32_t espz_wifi_runtime_deinit(void)
{
    if (!s_runtime_initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    (void)esp_wifi_stop();

    esp_err_t err = esp_wifi_deinit();
    if (err != ESP_OK && err != ESP_ERR_WIFI_NOT_INIT) {
        return err;
    }

    s_runtime_initialized = false;
    return ESP_OK;
}

int32_t espz_wifi_set_mode(uint8_t mode)
{
    esp_err_t err = ensure_runtime_initialized();
    if (err != ESP_OK) {
        return err;
    }

    wifi_mode_t wifi_mode = WIFI_MODE_NULL;
    err = mode_to_wifi_mode(mode, &wifi_mode);
    if (err != ESP_OK) {
        return err;
    }
    return esp_wifi_set_mode(wifi_mode);
}

int32_t espz_wifi_start(void)
{
    esp_err_t err = ensure_runtime_initialized();
    if (err != ESP_OK) {
        return err;
    }
    return esp_wifi_start();
}

int32_t espz_wifi_stop(void)
{
    esp_err_t err = ensure_runtime_initialized();
    if (err != ESP_OK) {
        return err;
    }
    return esp_wifi_stop();
}

int32_t espz_wifi_connect(void)
{
    esp_err_t err = ensure_runtime_initialized();
    if (err != ESP_OK) {
        return err;
    }
    return esp_wifi_connect();
}

int32_t espz_wifi_disconnect(void)
{
    esp_err_t err = ensure_runtime_initialized();
    if (err != ESP_OK) {
        return err;
    }
    return esp_wifi_disconnect();
}

int32_t espz_wifi_set_sta_config(const espz_wifi_sta_config_t *cfg)
{
    esp_err_t err = ensure_runtime_initialized();
    if (err != ESP_OK) {
        return err;
    }

    if (cfg == NULL || cfg->ssid == NULL || cfg->ssid_len == 0 || cfg->ssid_len > 32 || cfg->password_len > 64) {
        return ESP_ERR_INVALID_ARG;
    }
    if (cfg->password_len > 0 && cfg->password_len < 8) {
        return ESP_ERR_INVALID_ARG;
    }

    wifi_config_t sta_cfg = {0};
    memcpy(sta_cfg.sta.ssid, cfg->ssid, cfg->ssid_len);
    if (cfg->password != NULL && cfg->password_len > 0) {
        memcpy(sta_cfg.sta.password, cfg->password, cfg->password_len);
    }
    sta_cfg.sta.listen_interval = cfg->listen_interval;

    return esp_wifi_set_config(WIFI_IF_STA, &sta_cfg);
}

int32_t espz_wifi_set_ap_config(const espz_wifi_ap_config_t *cfg)
{
    esp_err_t err = ensure_runtime_initialized();
    if (err != ESP_OK) {
        return err;
    }

    if (cfg == NULL || cfg->ssid == NULL || cfg->ssid_len == 0 || cfg->ssid_len > 32 || cfg->password_len > 63) {
        return ESP_ERR_INVALID_ARG;
    }
    if (cfg->password_len > 0 && cfg->password_len < 8) {
        return ESP_ERR_INVALID_ARG;
    }
    if (cfg->max_connection == 0) {
        return ESP_ERR_INVALID_ARG;
    }

    wifi_config_t ap_cfg = {0};
    memcpy(ap_cfg.ap.ssid, cfg->ssid, cfg->ssid_len);
    ap_cfg.ap.ssid_len = cfg->ssid_len;
    ap_cfg.ap.channel = cfg->channel;
    ap_cfg.ap.max_connection = cfg->max_connection;
    ap_cfg.ap.ssid_hidden = cfg->hidden ? 1 : 0;

    if (cfg->password_len == 0) {
        ap_cfg.ap.authmode = WIFI_AUTH_OPEN;
    } else {
        memcpy(ap_cfg.ap.password, cfg->password, cfg->password_len);
        ap_cfg.ap.authmode = WIFI_AUTH_WPA2_PSK;
    }

    return esp_wifi_set_config(WIFI_IF_AP, &ap_cfg);
}

int32_t espz_wifi_scan(
    const espz_wifi_scan_config_t *cfg,
    espz_wifi_scan_record_t *out_records,
    uint16_t out_cap,
    uint16_t *out_count)
{
    esp_err_t err = ensure_runtime_initialized();
    if (err != ESP_OK) {
        return err;
    }

    if (cfg == NULL || out_records == NULL || out_count == NULL || out_cap == 0) {
        return ESP_ERR_INVALID_ARG;
    }

    wifi_scan_config_t scan_cfg = {0};
    scan_cfg.channel = cfg->channel;
    scan_cfg.show_hidden = cfg->show_hidden;

    err = esp_wifi_scan_start(&scan_cfg, cfg->block_until_done);
    if (err != ESP_OK) {
        return err;
    }

    uint16_t ap_num = 0;
    err = esp_wifi_scan_get_ap_num(&ap_num);
    if (err != ESP_OK) {
        return err;
    }

    uint16_t fetch_num = ap_num;
    if (cfg->max_results > 0 && fetch_num > cfg->max_results) {
        fetch_num = cfg->max_results;
    }
    if (fetch_num > out_cap) {
        fetch_num = out_cap;
    }

    *out_count = 0;
    if (fetch_num == 0) {
        return ESP_OK;
    }

    wifi_ap_record_t *records = calloc(fetch_num, sizeof(wifi_ap_record_t));
    if (records == NULL) {
        return ESP_ERR_NO_MEM;
    }

    uint16_t requested = fetch_num;
    err = esp_wifi_scan_get_ap_records(&requested, records);
    if (err == ESP_OK) {
        for (uint16_t i = 0; i < requested; ++i) {
            memset(out_records[i].ssid, 0, sizeof(out_records[i].ssid));
            size_t ssid_len = strnlen((const char *)records[i].ssid, sizeof(records[i].ssid));
            if (ssid_len > sizeof(out_records[i].ssid)) {
                ssid_len = sizeof(out_records[i].ssid);
            }
            memcpy(out_records[i].ssid, records[i].ssid, ssid_len);
            out_records[i].rssi = records[i].rssi;
            out_records[i].channel = records[i].primary;
            out_records[i].authmode = (uint8_t)records[i].authmode;
        }
        *out_count = requested;
    }

    free(records);
    return err;
}

int32_t espz_wifi_set_power_save(uint8_t ps)
{
    if (ensure_runtime_initialized() != ESP_OK) {
        return ESP_ERR_INVALID_STATE;
    }

    wifi_ps_type_t idf_ps;
    switch (ps) {
    case 0:
        idf_ps = WIFI_PS_NONE;
        break;
    case 1:
        idf_ps = WIFI_PS_MIN_MODEM;
        break;
    case 2:
        idf_ps = WIFI_PS_MAX_MODEM;
        break;
    default:
        return ESP_ERR_INVALID_ARG;
    }

    return esp_wifi_set_ps(idf_ps);
}

int32_t espz_wifi_get_power_save(uint8_t *out_ps)
{
    if (ensure_runtime_initialized() != ESP_OK) {
        return ESP_ERR_INVALID_STATE;
    }
    if (out_ps == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    wifi_ps_type_t idf_ps = WIFI_PS_NONE;
    esp_err_t err = esp_wifi_get_ps(&idf_ps);
    if (err != ESP_OK) {
        return err;
    }

    switch (idf_ps) {
    case WIFI_PS_NONE:
        *out_ps = 0;
        break;
    case WIFI_PS_MIN_MODEM:
        *out_ps = 1;
        break;
    case WIFI_PS_MAX_MODEM:
        *out_ps = 2;
        break;
    default:
        return ESP_ERR_INVALID_STATE;
    }

    return ESP_OK;
}

int32_t espz_wifi_set_max_tx_power(int8_t quarter_dbm)
{
    if (ensure_runtime_initialized() != ESP_OK) {
        return ESP_ERR_INVALID_STATE;
    }
    return esp_wifi_set_max_tx_power(quarter_dbm);
}

int32_t espz_wifi_set_protocol_mask(uint8_t mode, uint8_t mask)
{
    if (ensure_runtime_initialized() != ESP_OK) {
        return ESP_ERR_INVALID_STATE;
    }

    wifi_interface_t ifx = WIFI_IF_STA;
    esp_err_t err = mode_to_wifi_interface(mode, &ifx);
    if (err != ESP_OK) {
        return err;
    }
    return esp_wifi_set_protocol(ifx, mask);
}

int32_t espz_wifi_set_bandwidth(uint8_t mode, uint8_t bw)
{
    if (ensure_runtime_initialized() != ESP_OK) {
        return ESP_ERR_INVALID_STATE;
    }

    wifi_interface_t ifx = WIFI_IF_STA;
    esp_err_t err = mode_to_wifi_interface(mode, &ifx);
    if (err != ESP_OK) {
        return err;
    }

    wifi_bandwidth_t bandwidth;
    switch (bw) {
    case 0:
        bandwidth = WIFI_BW_HT20;
        break;
    case 1:
        bandwidth = WIFI_BW_HT40;
        break;
    default:
        return ESP_ERR_INVALID_ARG;
    }
    return esp_wifi_set_bandwidth(ifx, bandwidth);
}

int32_t espz_wifi_set_channel(uint8_t primary, uint8_t second)
{
    if (ensure_runtime_initialized() != ESP_OK) {
        return ESP_ERR_INVALID_STATE;
    }
    if (primary == 0 || primary > 14) {
        return ESP_ERR_INVALID_ARG;
    }

    wifi_second_chan_t second_chan;
    switch (second) {
    case 0:
        second_chan = WIFI_SECOND_CHAN_NONE;
        break;
    case 1:
        second_chan = WIFI_SECOND_CHAN_ABOVE;
        break;
    case 2:
        second_chan = WIFI_SECOND_CHAN_BELOW;
        break;
    default:
        return ESP_ERR_INVALID_ARG;
    }
    return esp_wifi_set_channel(primary, second_chan);
}

int32_t espz_wifi_get_sta_mac(uint8_t out_mac[6])
{
    if (out_mac == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    return esp_wifi_get_mac(WIFI_IF_STA, out_mac);
}
