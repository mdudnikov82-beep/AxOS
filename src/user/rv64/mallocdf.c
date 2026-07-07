#include "syscall.h"
#include "malloc.h"

/* Deliberately double-frees a block. A naive allocator would silently
 * corrupt its free list; this one must detect it and exit(139) instead —
 * proving the process gets killed cleanly rather than the heap rotting. */
int main(void) {
    puts_rv("mallocdf: allocating, then free()-ing twice on purpose...\r\n");

    void *p = malloc(48);
    if (!p) { puts_rv("mallocdf: malloc failed\r\n"); exit(1); }

    free(p);
    puts_rv("mallocdf: first free() OK\r\n");

    free(p);  /* must trigger heap_abort() and never return */

    puts_rv("mallocdf: FAIL - double free() was not caught!\r\n");
    exit(1);
    return 1;
}
