/**
 * Iridium 9603 SBD driver implementation.
 */
#include "iridium.h"
#include "at_parser.h"
#include <string.h>
#include <stdio.h>

#define IRIDIUM_TIMEOUT_MS 10000
#define IRIDIUM_LINE_MAX 256

static iridium_status_t send_at(iridium_t *ir, const char *cmd, char *resp, size_t resp_max) {
    size_t cmd_len = strlen(cmd);
    if (ir->hal.uart_write((const uint8_t *)cmd, cmd_len, ir->hal.ctx) < 0)
        return IRIDIUM_ERR_UART;

    // Read until OK or ERROR or timeout
    size_t total = 0;
    uint32_t deadline = IRIDIUM_TIMEOUT_MS;
    while (total < resp_max - 1) {
        uint8_t chunk[64];
        int n = ir->hal.uart_read(chunk, sizeof(chunk), 500, ir->hal.ctx);
        if (n < 0) return IRIDIUM_ERR_UART;
        if (n == 0) { if ((deadline -= 500) == 0) return IRIDIUM_ERR_TIMEOUT; continue; }
        if (total + n >= resp_max) n = resp_max - total - 1;
        memcpy(resp + total, chunk, n);
        total += n;
        resp[total] = '\0';
        if (strstr(resp, "OK\r")) return IRIDIUM_OK;
        if (strstr(resp, "ERROR\r")) return IRIDIUM_ERR_AT;
    }
    return IRIDIUM_ERR_TIMEOUT;
}

iridium_status_t iridium_init(iridium_t *ir, const iridium_hal_t *hal) {
    memset(ir, 0, sizeof(*ir));
    ir->hal = *hal;
    ir->mo_status = -1;
    ir->mt_status = -1;
    return IRIDIUM_OK;
}

iridium_status_t iridium_check(iridium_t *ir) {
    char resp[IRIDIUM_LINE_MAX];
    return send_at(ir, "AT\r", resp, sizeof(resp));
}

iridium_status_t iridium_clear_buffers(iridium_t *ir) {
    char resp[IRIDIUM_LINE_MAX];
    iridium_status_t s = send_at(ir, "AT+SBDD0\r", resp, sizeof(resp));
    if (s != IRIDIUM_OK) return s;
    return send_at(ir, "AT+SBDD1\r", resp, sizeof(resp));
}

iridium_status_t iridium_send(iridium_t *ir, const uint8_t *data, size_t len) {
    if (len == 0 || len > 340) return IRIDIUM_ERR_BUFFER_TOO_SMALL;

    // 1. Clear MO buffer
    char resp[IRIDIUM_LINE_MAX];
    iridium_status_t s = send_at(ir, "AT+SBDD0\r", resp, sizeof(resp));
    if (s != IRIDIUM_OK) return s;

    // 2. Write data (ASCII-safe for now; binary needs base64)
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "AT+SBDWT=%.*s\r", (int)len, (const char *)data);
    s = send_at(ir, cmd, resp, sizeof(resp));
    if (s != IRIDIUM_OK) return s;

    // 3. Initiate SBD session
    s = send_at(ir, "AT+SBDIX\r", resp, sizeof(resp));
    if (s != IRIDIUM_OK) return s;

    // 4. Parse +SBDIX: <MO_status>,<MO_len>,<MT_status>,<MT_len>,...
    int mo_stat, mo_len, mt_stat, mt_len;
    if (sscanf(resp, "+SBDIX: %d,%d,%d,%d", &mo_stat, &mo_len, &mt_stat, &mt_len) != 4)
        return IRIDIUM_ERR_SBD;

    ir->mo_status = mo_stat;
    ir->mo_len = mo_len;
    ir->mt_status = mt_stat;
    ir->mt_len = mt_len;

    if (mo_stat < 0 || mo_stat > 4) return IRIDIUM_ERR_NO_NETWORK;
    return IRIDIUM_OK;
}

iridium_status_t iridium_recv(iridium_t *ir, uint8_t *buf, size_t max, size_t *out_len) {
    char resp[512];
    iridium_status_t s = send_at(ir, "AT+SBDRT\r", resp, sizeof(resp));
    if (s != IRIDIUM_OK) return s;

    // Response format: +SBDRT:\r\n<data>\r\nOK
    char *start = strstr(resp, "+SBDRT:");
    if (!start) { *out_len = 0; return IRIDIUM_OK; }
    start += 7;
    while (*start == '\r' || *start == '\n') start++;
    char *end = strstr(start, "\r\nOK");
    if (!end) end = start + strlen(start);
    size_t n = (size_t)(end - start);
    if (n > max) n = max;
    memcpy(buf, start, n);
    *out_len = n;
    return IRIDIUM_OK;
}