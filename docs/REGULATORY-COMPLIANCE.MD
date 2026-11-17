# Regulatory Compliance

LXON satellite ground stations and Helios POS terminals must file
regulatory paperwork with the FCC (US), ITU (international), and local
telecom authorities.

## Supported filings

| Form | Authority | Purpose |
|------|-----------|---------|
| FCC Form 314 | FCC | License modification |
| FCC Form 315 | FCC | Assignment of license |
| FCC Form 326 | FCC | International filing |
| ITU BR IFIC | ITU | Space network filing |
| Local type approval | Per-country | Device certification |

## Firmware

`firmware/regulatory/` implements validation, PDF generation, and
submission tracking.

## Validation rules

- Frequency range: 0–500 MHz span
- EIRP: <= 55 dBW
- Call sign: required
- Country: ISO 3166-1 alpha-3

## Submission flow

1. `reg_validate_equipment` — validate the record.
2. `reg_generate_filing` — write the PDF.
3. `reg_submit` — submit via regulator API, returns a reference.
4. `reg_check_status` — poll for grant/denial.

## Governance

Filing templates and grantee codes are configured by governance.
Never file without governance approval.