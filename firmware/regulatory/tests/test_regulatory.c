#include "regulatory.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    reg_equipment_t eq = {
        .type = REG_FCC_FORM_314,
        .call_sign = "LXON-99",
        .grantee_code = "ABC",
        .serial_num = "SN001",
        .frequency_low_hz = 1626e6,
        .frequency_high_hz = 1660e6,
        .eirp_dbw = 50,
        .country = "US",
    };
    assert(reg_validate_equipment(&eq) == REG_OK);

    /* Bad frequency range */
    eq.frequency_low_hz = 2000e6;
    eq.frequency_high_hz = 1000e6;
    assert(reg_validate_equipment(&eq) == REG_ERR_VALIDATION);

    reg_filing_t filing;
    eq.frequency_low_hz = 1626e6;
    eq.frequency_high_hz = 1660e6;
    assert(reg_submit(&eq, &filing) == REG_OK);
    assert(strlen(filing.reference) > 0);

    printf("regulatory tests passed\n");
    return 0;
}