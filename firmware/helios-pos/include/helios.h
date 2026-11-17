/**
 * Helios POS firmware — ESP32-S3 + secure element + PQ signing.
 *
 * Helios is the LXON point-of-sale / point-of-sale-adjacent validator
 * terminal. It runs on an ESP32-S3, talks to an ATECC608A secure element
 * for key storage, and signs telemetry with ML-DSA-65 (PQClean).
 *
 * Architecture:
 *   - ESP32-S3 @ 240 MHz (dual-core)
 *   - ATECC608A (Microchip) — secure key storage, ECDSA, SHA-256
 *   - PQClean ml-dsa-65 reference — PQ signing in software
 *   - Wi-Fi / Ethernet uplink to LXON gateway
 *
 * Power budget:
 *   - Sign (ML-DSA-65): ~200 ms @ 240 MHz (~48M cycles)
 *   - Verify (ML-DSA-65): ~30 ms
 *   - Secure element keygen: ~50 ms
 *
 * Reference: https://www.microchip.com/en-us/product/ATECC608A
 */
#ifndef LXON_HELIOS_H
#define LXON_HELIOS_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HELIOS_PUBKEY_BYTES 1952
#define HELIOS_SECKEY_BYTES 4032
#define HELIOS_SIG_BYTES    3309

typedef enum {
    HELIOS_OK = 0,
    HELIOS_ERR_SE,
    HELIOS_ERR_PQ,
    HELIOS_ERR_UART,
    HELIOS_ERR_TIMEOUT,
    HELIOS_ERR_BAD_SIG,
} helios_status_t;

typedef struct {
    uint8_t pubkey[HELIOS_PUBKEY_BYTES];
    uint8_t seckey[HELIOS_SECKEY_BYTES];
} helios_keypair_t;

/** Provision the secure element and derive the PQ keypair. */
helios_status_t helios_provision(helios_keypair_t *kp);

/** Sign telemetry with ML-DSA-65. */
helios_status_t helios_sign(
    const uint8_t *seckey,
    const uint8_t *message,
    size_t msg_len,
    uint8_t *sig,
    size_t *sig_len);

/** Verify an inbound anchor signature. */
helios_status_t helios_verify(
    const uint8_t *pubkey,
    const uint8_t *message,
    size_t msg_len,
    const uint8_t *sig,
    size_t sig_len);

/** Wipe all secret material from RAM. */
void helios_wipe(helios_keypair_t *kp);

#ifdef __cplusplus
}
#endif

#endif