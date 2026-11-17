/**
 * PQ signing for embedded firmware.
 *
 * Uses PQClean's reference ML-DSA-65 implementation (C). The API is
 * deliberately small: generate, sign, verify, and free.
 *
 * Benchmarks (ARM Cortex-M4 @ 168 MHz, from pqm4):
 *   - keygen:  ~10M cycles (~60 ms)
 *   - sign:    ~10.7M cycles (~64 ms) — highly variable due to rejection sampling
 *   - verify:  ~2.3M cycles (~14 ms)
 *
 * On Cortex-M0+ (RP2040 @ 133 MHz):
 *   - sign: 169–1150 ms (99th percentile)
 *   - verify: ~30 ms
 *
 * For POS use, budget ~200 ms per tap for signing.
 */
#ifndef LXON_PQ_SIGN_H
#define LXON_PQ_SIGN_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MLDSA65_PUBKEY_BYTES 1952
#define MLDSA65_SECKEY_BYTES 4032
#define MLDSA65_SIG_BYTES    3309

typedef enum {
    PQ_OK = 0,
    PQ_ERR_KEYGEN,
    PQ_ERR_SIGN,
    PQ_ERR_VERIFY,
    PQ_ERR_BUFFER,
} pq_status_t;

typedef struct {
    uint8_t pubkey[MLDSA65_PUBKEY_BYTES];
    uint8_t seckey[MLDSA65_SECKEY_BYTES];
} mldsa65_keypair_t;

pq_status_t pq_keygen(mldsa65_keypair_t *kp);

/**
 * Sign a message.
 * @param sig  Must be at least MLDSA65_SIG_BYTES
 */
pq_status_t pq_sign(
    const uint8_t *seckey,
    const uint8_t *message,
    size_t msg_len,
    uint8_t *sig,
    size_t *sig_len);

pq_status_t pq_verify(
    const uint8_t *pubkey,
    const uint8_t *message,
    size_t msg_len,
    const uint8_t *sig,
    size_t sig_len);

/** Zero out secret key material. */
void pq_wipe(mldsa65_keypair_t *kp);

#ifdef __cplusplus
}
#endif

#endif