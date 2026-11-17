#include "astrocast.h"
#include <string.h>
#include <math.h>

#define ASTROCAST_SYNC 0xA5
#define ASTROCAST_MAX_USER 160

static uint16_t crc16_ccitt(const uint8_t *data, size_t len) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= (uint16_t)data[i] << 8;
        for (int j = 0; j < 8; j++)
            crc = (crc & 0x8000) ? (crc << 1) ^ 0x1021 : crc << 1;
    }
    return crc;
}

astrocast_status_t astrocast_init(astrocast_t *ac, const astrocast_hal_t *hal) {
    memset(ac, 0, sizeof(*ac));
    ac->hal = *hal;
    return ASTROCAST_OK;
}

astrocast_status_t astrocast_send(
    astrocast_t *ac,
    double lat_deg,
    double lon_deg,
    const uint8_t *data,
    size_t len)
{
    if (len > ASTROCAST_MAX_USER) return ASTROCAST_ERR_TOO_LARGE;

    uint8_t frame[256];
    size_t off = 0;

    // Header: sync, flags, seq_hi, seq_lo, len_hi, len_lo
    uint8_t flags = 0;
    if (!isnan(lat_deg) && !isnan(lon_deg)) flags |= 0x01; // geo included

    frame[off++] = ASTROCAST_SYNC;
    frame[off++] = flags;
    frame[off++] = (uint8_t)(ac->next_seq >> 8);
    frame[off++] = (uint8_t)(ac->next_seq & 0xFF);

    // Optional geolocation (int32 * 1e7)
    if (flags & 0x01) {
        int32_t lat = (int32_t)(lat_deg * 1e7);
        int32_t lon = (int32_t)(lon_deg * 1e7);
        memcpy(&frame[off], &lat, 4); off += 4;
        memcpy(&frame[off], &lon, 4); off += 4;
    }

    memcpy(&frame[off], data, len); off += len;

    // Append CRC16 over header+payload
    uint16_t crc = crc16_ccitt(frame, off);
    frame[off++] = (uint8_t)(crc >> 8);
    frame[off++] = (uint8_t)(crc & 0xFF);

    int w = ac->hal.uart_write(frame, off, ac->hal.ctx);
    if (w < 0) return ASTROCAST_ERR_UART;

    ac->next_seq++;
    return ASTROCAST_OK;
}

astrocast_status_t astrocast_recv(
    astrocast_t *ac,
    uint8_t *buf,
    size_t max,
    size_t *out_len)
{
    // Downlink command is 8 or 40 bytes user data.
    uint8_t frame[128];
    int n = ac->hal.uart_read(frame, sizeof(frame), 30000, ac->hal.ctx);
    if (n < 0) return ASTROCAST_ERR_UART;
    if (n == 0) { *out_len = 0; return ASTROCAST_OK; }
    if (n < 6 || frame[0] != ASTROCAST_SYNC) return ASTROCAST_ERR_PROTO;

    size_t payload_off = (frame[1] & 0x01) ? 12 : 4;
    if ((size_t)n < payload_off + 2) return ASTROCAST_ERR_PROTO;
    size_t data_len = (size_t)n - payload_off - 2;
    if (data_len > max) data_len = max;
    memcpy(buf, frame + payload_off, data_len);
    *out_len = data_len;

    ac->last_ack_seq = ((uint32_t)frame[2] << 8) | frame[3];
    return ASTROCAST_OK;
}