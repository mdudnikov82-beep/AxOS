#include "syscall.h"

/* MLS demo - raises this process's own sensitivity level, then sleeps
 * long enough for a lower-level observer's `ps` to see it redacted
 * (name -> "<hidden>", ticks -> 0) instead of skipped entirely.
 *
 * Usage: run MLSTEST.ELF & , then `ps` from AxSH (default level 0). */

int main(void) {
    puts_rv("mlstest: raising to MLS level 5...\r\n");
    set_level(5);
    puts_rv("mlstest: level raised, sleeping so 'ps' can observe...\r\n");
    sleep_ms(5000);
    puts_rv("mlstest: done\r\n");
    return 0;
}
