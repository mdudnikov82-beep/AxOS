#include "syscall.h"
#include "malloc.h"

#define CHECK(cond, msg) do { \
    if (cond) puts_rv("  OK: " msg "\r\n"); \
    else { puts_rv("  FAIL: " msg "\r\n"); fail = 1; } \
} while (0)

int main(void) {
    int fail = 0;
    puts_rv("mtetest: software MTE (shadow memory + generation tags)\r\n\r\n");

    char *p = (char *)malloc(64);
    CHECK(p != 0, "malloc(64) succeeded");
    CHECK(mte_check(p, 64), "fresh block is live (mte_check)");

    unsigned long tag = mte_tag(p);
    CHECK(tag != 0, "fresh block has a nonzero generation tag");
    CHECK(mte_check_tag(p, tag, 64), "mte_check_tag matches own tag");

    for (int i = 0; i < 64; i++) p[i] = (char)i;
    int rw_ok = 1;
    for (int i = 0; i < 64; i++) if (p[i] != (char)i) { rw_ok = 0; break; }
    CHECK(rw_ok, "write/read through the block");

    free(p);
    CHECK(!mte_check(p, 64), "freed block is no longer live");
    CHECK(mte_tag(p) == 0, "freed block reports tag 0");
    CHECK(!mte_check_tag(p, tag, 64), "stale tag rejected after free()");

    /* Drain the quarantine (8 slots) with same-size allocations so `p`
     * gets evicted back to the real free list and its address reused. */
    void *drain[8];
    for (int i = 0; i < 8; i++) drain[i] = malloc(64);
    for (int i = 0; i < 8; i++) free(drain[i]);

    char *p2 = (char *)malloc(64);
    CHECK(p2 != 0, "malloc(64) after quarantine drain succeeded");
    CHECK(p2 == p, "address was recycled (expected, once out of quarantine)");

    unsigned long tag2 = mte_tag(p2);
    CHECK(tag2 != 0 && tag2 != tag,
          "new generation got a DIFFERENT tag than the old one");
    CHECK(!mte_check_tag(p, tag, 64),
          "old pointer + old tag still rejected (use-after-free caught)");
    CHECK(mte_check_tag(p2, tag2, 64), "new pointer + new tag accepted");

    free(p2);
    puts_rv(fail ? "\r\nmtetest: SOME CHECKS FAILED\r\n" : "\r\nmtetest: all checks passed\r\n");
    exit(fail);
    return fail;
}
