/**
 * SBD framing helpers.
 *
 * Wraps a raw payload in the Iridium SBD text format expected by
 * AT+SBDWT. Binary payloads must be base64-encoded before calling
 * `sbd_frame_text`.
 */
#include "sbd_framing.h"
#include <string.h>
#include <stdio.h>

size_t sbd_frame_text(const uint8_t *raw, size_t raw_len, uint8_t *out, size_t out_max) {
    if (!raw || !out) return 0;
    if (out_max < raw_len + 1) return 0;
    memcpy(out, raw, raw_len);
    out[raw_len] = '\0';
    return raw_len;
}

int sbd_parse_status(const char *resp, int *mo_stat, int *mo_len, int *mt_stat, int *mt_len) {
    return sscanf(resp, "+SBDIX: %d,%d,%d,%d", mo_stat, mo_len, mt_stat, mt_len) == 4 ? 0 : -1;
}