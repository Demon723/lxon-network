/**
 * Iridium 9603 SBD driver.
 *
 * The Iridium 9603 is a Short Burst Data (SBD) transceiver. It speaks
 * an AT command set over UART at 19200 baud (default), 3.3V logic.
 *
 * Reference: https://cdn-shop.adafruit.com/product-files/4521/RockBLOCK-9603-Data-Sheet-Small.pdf
 *
 * Command flow (simplified):
 *   AT          → ready check
 *   AT+SBDIX    → initiate SBD session (talk to satellites)
 *   AT+SBDWT    → write text message into outbound buffer
 *   AT+SBDD0    → clear MO buffer
 *   AT+SBDD1    → clear MT buffer
 *   AT+SBDRT    → read MT buffer as text
 *   AT+CGMI     → get manufacturer
 *
 * The 9603 buffers messages; +SBDIX returns the MO/MT status codes and
 * the number of bytes transferred.
 */
#ifndef LXON_IRIDIUM_H
#define LXON_IRIDIUM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    IRIDIUM_OK = 0,
    IRIDIUM_ERR_TIMEOUT,
    IRIDIUM_ERR_AT,
    IRIDIUM_ERR_SBD,
    IRIDIUM_ERR_UART,
    IRIDIUM_ERR_NO_NETWORK,
    IRIDIUM_ERR_BUFFER_TOO_SMALL,
} iridium_status_t;

typedef struct {
    int (*uart_write)(const uint8_t *data, size_t len, void *ctx);
    int (*uart_read)(uint8_t *buf, size_t max, uint32_t timeout_ms, void *ctx);
    void *ctx;
} iridium_hal_t;

typedef struct {
    iridium_hal_t hal;
    int mo_status;    // +SBDIX MO status
    int mt_status;    // +SBDIX MT status
    int mo_len;       // bytes sent
    int mt_len;       // bytes received
} iridium_t;

iridium_status_t iridium_init(iridium_t *ir, const iridium_hal_t *hal);
iridium_status_t iridium_check(iridium_t *ir);
iridium_status_t iridium_send(iridium_t *ir, const uint8_t *data, size_t len);
iridium_status_t iridium_recv(iridium_t *ir, uint8_t *buf, size_t max, size_t *out_len);
iridium_status_t iridium_clear_buffers(iridium_t *ir);

#ifdef __cplusplus
}
#endif

#endif