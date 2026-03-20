#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "esp_event.h"
#include "esp_netif.h"
#include "esp_wifi_default.h"

int32_t espz_netif_runtime_init(void)
{
    esp_err_t err = esp_netif_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return (int32_t)err;
    }

    err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return (int32_t)err;
    }

    return ESP_OK;
}

int32_t espz_netif_runtime_deinit(void)
{
    esp_err_t err = esp_event_loop_delete_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return (int32_t)err;
    }

    err = esp_netif_deinit();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return (int32_t)err;
    }

    return ESP_OK;
}

esp_netif_t *espz_netif_create_default_wifi_sta(void)
{
    return esp_netif_create_default_wifi_sta();
}

esp_netif_t *espz_netif_create_default_wifi_ap(void)
{
    return esp_netif_create_default_wifi_ap();
}

int32_t espz_netif_destroy_default_wifi(void *netif)
{
    if (netif == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    esp_err_t err = esp_wifi_clear_default_wifi_driver_and_handlers(netif);
    if (err != ESP_OK) {
        return (int32_t)err;
    }

    esp_netif_destroy((esp_netif_t *)netif);
    return ESP_OK;
}

esp_netif_t *espz_netif_get_handle_from_ifkey(const char *if_key)
{
    return esp_netif_get_handle_from_ifkey(if_key);
}

int32_t espz_netif_get_ip_info(esp_netif_t *netif, esp_netif_ip_info_t *ip_info)
{
    return (int32_t)esp_netif_get_ip_info(netif, ip_info);
}

int32_t espz_netif_set_ip_info(esp_netif_t *netif, const esp_netif_ip_info_t *ip_info)
{
    return (int32_t)esp_netif_set_ip_info(netif, ip_info);
}

int32_t espz_netif_get_dns_info(esp_netif_t *netif, uint32_t dns_type, esp_netif_dns_info_t *dns)
{
    return (int32_t)esp_netif_get_dns_info(netif, (esp_netif_dns_type_t)dns_type, dns);
}

int32_t espz_netif_set_dns_info(esp_netif_t *netif, uint32_t dns_type, const esp_netif_dns_info_t *dns)
{
    return (int32_t)esp_netif_set_dns_info(netif, (esp_netif_dns_type_t)dns_type, dns);
}

int32_t espz_netif_is_up(esp_netif_t *netif)
{
    return esp_netif_is_netif_up(netif) ? 1 : 0;
}

void espz_netif_set_default(esp_netif_t *netif)
{
    esp_netif_set_default_netif(netif);
}

int32_t espz_netif_get_impl_name(esp_netif_t *netif, char *name)
{
    return (int32_t)esp_netif_get_netif_impl_name(netif, name);
}

int32_t espz_netif_get_nr_of_ifs(void)
{
    return (int32_t)esp_netif_get_nr_of_ifs();
}

esp_netif_t *espz_netif_next(esp_netif_t *netif)
{
    return esp_netif_next(netif);
}

int32_t espz_netif_dhcpc_get_status(esp_netif_t *netif, uint32_t *status)
{
    esp_netif_dhcp_status_t s;
    esp_err_t err = esp_netif_dhcpc_get_status(netif, &s);
    if (err != ESP_OK) return (int32_t)err;
    *status = (uint32_t)s;
    return 0;
}

int32_t espz_netif_dhcpc_start(esp_netif_t *netif)
{
    return (int32_t)esp_netif_dhcpc_start(netif);
}

int32_t espz_netif_dhcpc_stop(esp_netif_t *netif)
{
    return (int32_t)esp_netif_dhcpc_stop(netif);
}

int32_t espz_netif_set_hostname(esp_netif_t *netif, const uint8_t *hostname, uint8_t hostname_len)
{
    if (netif == NULL || hostname == NULL || hostname_len == 0 || hostname_len > 63) {
        return ESP_ERR_INVALID_ARG;
    }

    char host_buf[64] = {0};
    memcpy(host_buf, hostname, hostname_len);
    host_buf[hostname_len] = '\0';
    return (int32_t)esp_netif_set_hostname(netif, host_buf);
}
