/**
 * Minimal AT command parser used by the Iridium 9603 driver.
 */
#include "at_parser.h"
#include <string.h>

size_t at_strip_eol(char *line) {
    if (!line) return 0;
    size_t len = strlen(line);
    while (len > 0 && (line[len - 1] == '\r' || line[len - 1] == '\n')) {
        line[--len] = '\0';
    }
    return len;
}

int at_starts_with(const char *line, const char *prefix) {
    if (!line || !prefix) return 0;
    size_t n = strlen(prefix);
    return strncmp(line, prefix, n) == 0;
}