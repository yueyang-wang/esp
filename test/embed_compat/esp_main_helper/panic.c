#include "esp_log.h"
#include <stddef.h>

void espz_log_panic(const char *msg, size_t len) {
    ESP_LOGE("zig-panic", "%.*s", (int)len, msg);
}
