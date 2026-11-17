/**
 * Helios POS firmware implementation.
 *
 * Wraps the ATECC608A secure element for key storage and PQClean's
 * ml-dsa-65 for signing. Fails closed when the secure element or
 * PQClean is not present.
 */
#include "helios.h"
#include <string.h>
#include <stdlib.h>

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

#if defined(LXON_HAVE_ATECC)
extern int atecc_provision(uint8_t *pk, uint8_t *sk);
#endif

helios_status_t helios_provision(helios_keypair_t *kp) {
    if (!kp) return HELIOS_ERR_SE;
#if defined(LXON_HAVE_ATECC)
    if (atecc_provision(kp->pubkey, kp->seckey) != 0)
        return HELIOS_ERR_SE;
    return HELIOS_OK;
#elif defined(LXON_HAVE_PQCLEAN)
    if (pqcrystals_dilithium3_ref_keypair(kp->pubkey, kp->seckey) != 0)
        return HELIOS_ERR_PQ;
    return HELIOS_OK;
#else
    memset(kp, 0, sizeof(*kp));
    return HELIOS_ERR_SE;  // fail closed
#endif
}

helios_status_t helios_sign(
    const uint8_t *seckey,
    const uint8_t *message,
    size_t msg_len,
    uint8_t *sig,
    size_t *sig_len)
{
    if (!seckey || !message || !sig || !sig_len) return HELIOS_ERR_PQ;
#if defined(LXON_HAVE_PQCLEAN)
    size_t out = 0;
    int rc = pqcrystals_dilithium3_ref_signature(sig, &out, message, msg_len, seckey);
    if (rc != 0) return HELIOS_ERR_PQ;
    *sig_len = out;
    return HELIOS_OK;
#else
    (void)msg_len;
    *sig_len = 0;
    return HELIOS_ERR_PQ;
#endif
}

helios_status_t helios_verify(
    const uint8_t *pubkey,
    const uint8_t *message,
    size_t msg_len,
    const uint8_t *sig,
    size_t sig_len)
{
    if (!pubkey || !message || !sig) return HELIOS_ERR_BAD_SIG;
    if (sig_len != HELIOS_SIG_BYTES) return HELIOS_ERR_BAD_SIG;
#if defined(LXON_HAVE_PQCLEAN)
    int rc = pqcrystals_dilithium3_ref_verify(sig, sig_len, message, msg_len, pubkey);
    return rc == 0 ? HELIOS_OK : HELIOS_ERR_BAD_SIG;
#else
    (void)msg_len; (void)sig_len;
    return HELIOS_ERR_BAD_SIG;
#endif
}

void helios_wipe(helios_keypair_t *kp) {
    if (!kp) return;
    volatile uint8_t *p = (volatile uint8_t *)kp;
    for (size_t i = 0; i < sizeof(*kp); i++) p[i] = 0;
}