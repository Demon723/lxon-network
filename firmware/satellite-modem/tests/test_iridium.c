#include "iridium.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>

/* Fake UART with a response queue for host testing.
 * Each write of an AT command pops the next queued response. */
#define QUEUE_SIZE 8
static char queue[QUEUE_SIZE][512];
static size_t queue_len[QUEUE_SIZE];
static int queue_head = 0;
static int queue_tail = 0;

static int fake_write(const uint8_t *data, size_t len, void *ctx) {
    (void)ctx; (void)data; (void)len;
    return (int)len;
}
static int fake_read(uint8_t *buf, size_t max, uint32_t timeout_ms, void *ctx) {
    (void)timeout_ms; (void)ctx;
    if (queue_head == queue_tail) return 0;
    size_t n = queue_len[queue_head];
    if (n > max) n = max;
    memcpy(buf, queue[queue_head], n);
    queue_head++;
    return (int)n;
}

static void queue_resp(const char *s) {
    size_t n = strlen(s);
    if (n >= sizeof(queue[0])) n = sizeof(queue[0]) - 1;
    memcpy(queue[queue_tail], s, n);
    queue_len[queue_tail] = n;
    queue_tail++;
}

static void reset_queue(void) {
    queue_head = queue_tail = 0;
}

int main(void) {
    iridium_t ir;
    iridium_hal_t hal = { .uart_write = fake_write, .uart_read = fake_read, .ctx = NULL };
    assert(iridium_init(&ir, &hal) == IRIDIUM_OK);

    reset_queue();
    queue_resp("AT\r\r\nOK\r\n");
    assert(iridium_check(&ir) == IRIDIUM_OK);

    /* clear_buffers issues two AT commands (SBDD0 then SBDD1). */
    reset_queue();
    queue_resp("AT+SBDD0\r\r\nOK\r\n");
    queue_resp("AT+SBDD1\r\r\nOK\r\n");
    assert(iridium_clear_buffers(&ir) == IRIDIUM_OK);

    printf("iridium tests passed\n");
    return 0;
}