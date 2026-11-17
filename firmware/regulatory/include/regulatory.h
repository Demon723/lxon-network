/**
 * FCC/ITU filing automation.
 *
 * LXON satellite ground stations and Helios POS terminals must file
 * regulatory paperwork with the FCC (US), ITU (international), and
 * local telecom authorities. This module automates the repetitive
 * parts: form generation, attachment assembly, and submission tracking.
 *
 * Supported forms:
 *   - FCC Form 314 / 315 (license modification / assignment)
 *   - FCC Form 326 (international filing)
 *   - ITU BR IFIC (space network filing)
 *   - Local type approval (per-country)
 */
#ifndef LXON_REGULATORY_H
#define LXON_REGULATORY_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    REG_OK = 0,
    REG_ERR_IO,
    REG_ERR_VALIDATION,
    REG_ERR_DUPLICATE,
    REG_ERR_UNSUPPORTED,
} reg_status_t;

typedef enum {
    REG_FCC_FORM_314,
    REG_FCC_FORM_315,
    REG_FCC_FORM_326,
    REG_ITU_BR_IFIC,
    REG_LOCAL_TYPE_APPROVAL,
} reg_filing_type_t;

typedef struct {
    reg_filing_type_t type;
    char call_sign[16];
    char grantee_code[8];
    char serial_num[64];
    uint64_t frequency_low_hz;
    uint64_t frequency_high_hz;
    int32_t eirp_dbw;
    char country[3];
} reg_equipment_t;

typedef struct {
    uint64_t id;
    reg_filing_type_t type;
    char reference[64];
    char status[32];
    char pdf_path[256];
} reg_filing_t;

/** Validate an equipment record against the relevant form's rules. */
reg_status_t reg_validate_equipment(const reg_equipment_t *eq);

/** Generate the filing PDF for an equipment record. */
reg_status_t reg_generate_filing(const reg_equipment_t *eq, const char *out_path);

/** Submit a filing to the regulator's API. Returns the filing reference. */
reg_status_t reg_submit(const reg_equipment_t *eq, reg_filing_t *out);

/** Check the status of a previously submitted filing. */
reg_status_t reg_check_status(const char *reference, reg_filing_t *out);

#ifdef __cplusplus
}
#endif

#endif