/**
 * Astrocast Astronode S driver.
 *
 * Astrocast uses L-band (1626.5–1660.5 MHz uplink) via a constellation
 * of nanosatellites. Messages are 0–160 bytes of user data + 8 bytes of
 * geolocation. Latency is 5–7 hours average (store-and-forward).
 *
 * The Astronode S module speaks a binary protocol over UART (115200).
 * Message format:
 *   - Header: 4 bytes (sync + length + checksum)
 *   - Geolocation: 8 bytes (int32 lat*1e7 || int32 lon*1e7) — optional
 *   - User data: 0–160 bytes
 *
 * Reference: https://docs.astrocast.com/docs/iot-network/protocol
 */
#ifndef LXON_ASTROCAST_H
#define LXON_ASTROCAST_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ASTROCAST_OK = 0,
    ASTROCAST_ERR_TIMEOUT,
    ASTROCAST_ERR_PROTO,
    ASTROCAST_ERR_UART,
    ASTROCAST_ERR_NO_SAT,
    ASTROCAST_ERR_TOO_LARGE,
} astrocast_status_t;

typedef struct {
    int (*uart_write)(const uint8_t *data, size_t len, void *ctx);
    int (*uart_read)(uint8_t *buf, size_t max, uint32_t timeout_ms, void *ctx);
    void *ctx;
} astrocast_hal_t;

typedef struct {
    astrocast_hal_t hal;
    uint32_t last_ack_seq;
    uint16_t next_seq;
} astrocast_t;

astrocast_status_t astrocast_init(astrocast_t *ac, const astrocast_hal_t *hal);

/**
 * Send a message with optional geolocation.
 * @param lat_deg   Latitude in degrees (-90..90); pass NAN to omit
 * @param lon_deg   Longitude in degrees (-180..180)
 * @param data      User payload (0..160 bytes)
 */
astrocast_status_t astrocast_send(
    astrocast_t *ac,
    double lat_deg,
    double lon_deg,
    const uint8_t *data,
    size_t len);

/** Poll for a downlink command (8 or 40 bytes). */
astrocast_status_t astrocast_recv(
    astrocast_t *ac,
    uint8_t *buf,
    size_t max,
    size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif