/**
 * Minimal AT command parser used by the Iridium 9603 driver.
 *
 * Splits a raw modem response into lines and strips trailing \r\n.
 * Used by iridium.c to detect OK/ERROR/+SBDIX tokens.
 */
#ifndef LXON_AT_PARSER_H
#define LXON_AT_PARSER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Strip trailing \r\n from a line. Returns new length. */
size_t at_strip_eol(char *line);

/** Return non-zero if line starts with the given prefix (case-insensitive). */
int at_starts_with(const char *line, const char *prefix);

#ifdef __cplusplus
}
#endif

#endif