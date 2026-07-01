#include "axiom.h"

// Намеренно портит свой адрес возврата через inline-asm.
// CFI должен поймать это в __cyg_profile_func_exit ДО ret.
static void vuln(void) {
    ax_print("vuln: corrupting return address with 0xDEADBEEF...\n");
    __asm__ volatile (
        "movl %%ebp, %%eax\n"
        "movl $0xDEADBEEF, 4(%%eax)\n"
        ::: "eax", "memory"
    );
    ax_print("vuln: done. CFI exit hook should fire before ret.\n");
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;
    ax_print("CFI demo: calling vuln() which corrupts its own return addr\n");
    ax_print("Expected: CFI hijack message, NOT 'returned from vuln'\n");
    vuln();
    ax_print("ERROR: returned from vuln — CFI did NOT fire!\n");
    return 1;
}
