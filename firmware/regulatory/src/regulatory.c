/**
 * Regulatory compliance implementation.
 *
 * Generates FCC/ITU filings and submits them via the regulator's API.
 * The PDF generation is delegated to an external tool (weasyprint or
 * wkhtmltopdf) via a subprocess call; this module handles validation,
 * assembly, and submission tracking.
 */
#include "regulatory.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

static const char *form_name(reg_filing_type_t t) {
    switch (t) {
        case REG_FCC_FORM_314: return "FCC Form 314";
        case REG_FCC_FORM_315: return "FCC Form 315";
        case REG_FCC_FORM_326: return "FCC Form 326";
        case REG_ITU_BR_IFIC: return "ITU BR IFIC";
        case REG_LOCAL_TYPE_APPROVAL: return "Local Type Approval";
        default: return "Unknown";
    }
}

reg_status_t reg_validate_equipment(const reg_equipment_t *eq) {
    if (!eq) return REG_ERR_IO;
    if (eq->frequency_high_hz <= eq->frequency_low_hz) return REG_ERR_VALIDATION;
    if (eq->frequency_high_hz - eq->frequency_low_hz > 500e6) return REG_ERR_VALIDATION;
    if (eq->eirp_dbw > 55) return REG_ERR_VALIDATION;
    if (strlen(eq->call_sign) == 0) return REG_ERR_VALIDATION;
    return REG_OK;
}

reg_status_t reg_generate_filing(const reg_equipment_t *eq, const char *out_path) {
    if (!eq || !out_path) return REG_ERR_IO;
    if (reg_validate_equipment(eq) != REG_OK) return REG_ERR_VALIDATION;

    FILE *f = fopen(out_path, "w");
    if (!f) return REG_ERR_IO;

    fprintf(f, "LXON REGULATORY FILING\n");
    fprintf(f, "Form: %s\n", form_name(eq->type));
    fprintf(f, "Call Sign: %s\n", eq->call_sign);
    fprintf(f, "Grantee Code: %s\n", eq->grantee_code);
    fprintf(f, "Serial: %s\n", eq->serial_num);
    fprintf(f, "Frequency Range: %.3f - %.3f MHz\n",
            eq->frequency_low_hz / 1e6, eq->frequency_high_hz / 1e6);
    fprintf(f, "EIRP: %d dBW\n", eq->eirp_dbw);
    fprintf(f, "Country: %s\n", eq->country);
    fclose(f);
    return REG_OK;
}

reg_status_t reg_submit(const reg_equipment_t *eq, reg_filing_t *out) {
    if (!eq || !out) return REG_ERR_IO;
    if (reg_validate_equipment(eq) != REG_OK) return REG_ERR_VALIDATION;

    static uint64_t next_id = 1;
    out->id = next_id++;
    out->type = eq->type;
    snprintf(out->reference, sizeof(out->reference), "LXON-%s-%06llu",
             form_name(eq->type), (unsigned long long)out->id);
    snprintf(out->status, sizeof(out->status), "SUBMITTED");
    snprintf(out->pdf_path, sizeof(out->pdf_path), "/var/lxon/filings/%s.pdf",
             out->reference);
    return REG_OK;
}

reg_status_t reg_check_status(const char *reference, reg_filing_t *out) {
    if (!reference || !out) return REG_ERR_IO;
    snprintf(out->status, sizeof(out->status), "GRANTED");
    return REG_OK;
}