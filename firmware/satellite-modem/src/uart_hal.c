/**
 * UART HAL abstraction.
 *
 * Provides a thin wrapper around a platform UART so the satellite
 * modem drivers can be unit-tested on the host with a fake HAL.
 */
#include "uart_hal.h"
#include <string.h>

int uart_hal_init(uart_hal_t *hal, const uart_hal_t *impl, void *ctx) {
    if (!hal || !impl) return -1;
    *hal = *impl;
    hal->ctx = ctx;
    return 0;
}

int uart_hal_write(uart_hal_t *hal, const uint8_t *data, size_t len) {
    if (!hal || !hal->uart_write) return -1;
    return hal->uart_write(data, len, hal->ctx);
}

int uart_hal_read(uart_hal_t *hal, uint8_t *buf, size_t max, uint32_t timeout_ms) {
    if (!hal || !hal->uart_read) return -1;
    return hal->uart_read(buf, max, timeout_ms, hal->ctx);
}

void uart_hal_flush(uart_hal_t *hal) {
    (void)hal;
}