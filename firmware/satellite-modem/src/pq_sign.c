#include "pq_sign.h"
#include <string.h>
#include <stdlib.h>

/**
 * Production build links against PQClean's ml-dsa-65.
 * The scaffold below fails closed when PQClean is not present.
 */
#if defined(LXON_HAVE_PQCLEAN)
extern int pqcrystals_dilithium3_ref_keypair(uint8_t *pk, uint8_t *sk);
extern int pqcrystals_dilithium3_ref_signature(
    uint8_t *sig, size_t *siglen,
    const uint8_t *m, size_t mlen,
    const uint8_t *sk);
extern int pqcrystals_dilithium3_ref_verify(
    const uint8_t *sig, size_t siglen,
    const uint8_t *m, size_t mlen,
    const uint8_t *pk);
#endif

pq_status_t pq_keygen(mldsa65_keypair_t *kp) {
    if (!kp) return PQ_ERR_KEYGEN;
#if defined(LXON_HAVE_PQCLEAN)
    if (pqcrystals_dilithium3_ref_keypair(kp->pubkey, kp->seckey) != 0)
        return PQ_ERR_KEYGEN;
    return PQ_OK;
#else
    memset(kp, 0, sizeof(*kp));
    return PQ_ERR_KEYGEN;  // fail closed — no PQClean linked
#endif
}

pq_status_t pq_sign(
    const uint8_t *seckey,
    const uint8_t *message,
    size_t msg_len,
    uint8_t *sig,
    size_t *sig_len)
{
    if (!seckey || !message || !sig || !sig_len) return PQ_ERR_SIGN;
#if defined(LXON_HAVE_PQCLEAN)
    size_t out = 0;
    int rc = pqcrystals_dilithium3_ref_signature(sig, &out, message, msg_len, seckey);
    if (rc != 0) return PQ_ERR_SIGN;
    *sig_len = out;
    return PQ_OK;
#else
    (void)msg_len;
    *sig_len = 0;
    return PQ_ERR_SIGN;
#endif
}

pq_status_t pq_verify(
    const uint8_t *pubkey,
    const uint8_t *message,
    size_t msg_len,
    const uint8_t *sig,
    size_t sig_len)
{
    if (!pubkey || !message || !sig) return PQ_ERR_VERIFY;
#if defined(LXON_HAVE_PQCLEAN)
    int rc = pqcrystals_dilithium3_ref_verify(sig, sig_len, message, msg_len, pubkey);
    return rc == 0 ? PQ_OK : PQ_ERR_VERIFY;
#else
    (void)msg_len; (void)sig_len;
    return PQ_ERR_VERIFY;
#endif
}

void pq_wipe(mldsa65_keypair_t *kp) {
    if (!kp) return;
    volatile uint8_t *p = (volatile uint8_t *)kp;
    for (size_t i = 0; i < sizeof(*kp); i++) p[i] = 0;
}