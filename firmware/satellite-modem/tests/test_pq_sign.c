#include "pq_sign.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    mldsa65_keypair_t kp;
    /* Without PQClean linked, keygen fails closed */
    pq_status_t s = pq_keygen(&kp);
    assert(s == PQ_ERR_KEYGEN);

    /* Signing with empty key must fail */
    uint8_t sig[MLDSA65_SIG_BYTES];
    size_t sig_len = 0;
    s = pq_sign(kp.seckey, (const uint8_t *)"hello", 5, sig, &sig_len);
    assert(s == PQ_ERR_SIGN);

    printf("pq_sign tests passed (fail-closed)\n");
    return 0;
}