/**
 * SBD framing helpers.
 */
#ifndef LXON_SBD_FRAMING_H
#define LXON_SBD_FRAMING_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Wrap a raw payload as an SBD text message. Returns length or 0 on error. */
size_t sbd_frame_text(const uint8_t *raw, size_t raw_len, uint8_t *out, size_t out_max);

/** Parse a +SBDIX response line. Returns 0 on success, -1 on failure. */
int sbd_parse_status(const char *resp, int *mo_stat, int *mo_len, int *mt_stat, int *mt_len);

#ifdef __cplusplus
}
#endif

#endif