/**
 * UART HAL abstraction.
 *
 * Provides a thin wrapper around a platform UART so the satellite
 * modem drivers can be unit-tested on the host with a fake HAL.
 */
#ifndef LXON_UART_HAL_H
#define LXON_UART_HAL_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int (*uart_write)(const uint8_t *data, size_t len, void *ctx);
    int (*uart_read)(uint8_t *buf, size_t max, uint32_t timeout_ms, void *ctx);
    void *ctx;
} uart_hal_t;

int uart_hal_init(uart_hal_t *hal, const uart_hal_t *impl, void *ctx);
int uart_hal_write(uart_hal_t *hal, const uint8_t *data, size_t len);
int uart_hal_read(uart_hal_t *hal, uint8_t *buf, size_t max, uint32_t timeout_ms);
void uart_hal_flush(uart_hal_t *hal);

#ifdef __cplusplus
}
#endif

#endif