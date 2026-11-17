#include "helios.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    helios_keypair_t kp;
    /* Without PQClean linked, provision fails closed */
    helios_status_t s = helios_provision(&kp);
    assert(s != HELIOS_OK);

    /* Signing with empty key must fail */
    uint8_t sig[HELIOS_SIG_BYTES];
    size_t sig_len = 0;
    s = helios_sign(kp.seckey, (const uint8_t *)"hello", 5, sig, &sig_len);
    assert(s != HELIOS_OK);

    printf("helios tests passed (fail-closed)\n");
    return 0;
}