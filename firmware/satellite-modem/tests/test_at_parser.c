#include "at_parser.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>

int main(void) {
    char line1[] = "OK\r\n";
    char line2[] = "ERROR\r\n";
    char line3[] = "+SBDIX: 0,100,0,50\r\n";

    assert(at_strip_eol(line1) == 2);
    assert(strcmp(line1, "OK") == 0);

    assert(at_strip_eol(line2) == 5);
    assert(strcmp(line2, "ERROR") == 0);

    assert(at_strip_eol(line3) == 18);

    assert(at_starts_with(line3, "+SBDIX") == 1);
    assert(at_starts_with(line3, "AT") == 0);

    printf("at_parser tests passed\n");
    return 0;
}