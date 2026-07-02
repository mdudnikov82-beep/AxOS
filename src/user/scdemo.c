#include "axiom.h"

// Seccomp демо: проверяем что фильтр syscall'ов убивает задачу
// при попытке вызвать запрещённый syscall.
//
// Использование:
//   scdemo exec   → STDIO-фильтр + ax_exec          → killed (seccomp)
//   scdemo disk   → STDIO-фильтр + ax_disk_read_sector → killed (seccomp)
//   scdemo ok     → STDIO-фильтр + ax_print/ticks   → PASS (разрешено)
//   scdemo        → подсказка

static void test_exec(void) {
    ax_print("[seccomp exec] Installing STDIO-only filter...\n");
    ax_seccomp(AX_SC_STDIO);
    ax_print("[seccomp exec] Filter active. Attempting ax_exec...\n");
    // Ядро должно напечатать "[seccomp] forbidden 0x0B" и убить задачу.
    // Если не убило — ax_exit() есть в AX_SC_STDIO, поэтому мы корректно завершимся.
    ax_exec("HELLO.BIN");
    ax_exit();
}

static void test_disk(void) {
    ax_print("[seccomp disk] Installing STDIO-only filter...\n");
    ax_seccomp(AX_SC_STDIO);
    ax_print("[seccomp disk] Filter active. Attempting ax_disk_read_sector...\n");
    // Ядро должно напечатать "[seccomp] forbidden 0x19" и убить задачу.
    unsigned char buf[512];
    ax_disk_read_sector(0, buf);
    ax_exit();
}

static void test_ok(void) {
    ax_print("[seccomp ok] Installing STDIO-only filter...\n");
    ax_seccomp(AX_SC_STDIO);
    ax_print("[seccomp ok] Filter active.\n");
    // ax_print = 0x01, ax_get_ticks = 0x0F — оба в AX_SC_STDIO
    ax_print("[seccomp ok] ax_print: PASS\n");
    ax_print("[seccomp ok] ax_get_ticks: ");
    ax_print_uint(ax_get_ticks());
    ax_print(" ticks - PASS\n");
    // Пробуем сузить маску ещё раз (AND) - только print + exit
    ax_seccomp(AX_SC_PRINT | AX_SC_EXIT | AX_SC_SBRK);
    ax_print("[seccomp ok] Narrowed to PRINT+EXIT only - still alive: PASS\n");
    ax_print("[seccomp ok] ALL PASS\n");
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;
    if (argc < 2) {
        ax_print("Usage: scdemo exec|disk|ok\n");
        ax_print("  exec - ax_exec after STDIO filter    (expect: killed)\n");
        ax_print("  disk - ax_disk_read after STDIO filter (expect: killed)\n");
        ax_print("  ok   - allowed calls after filter    (expect: PASS)\n");
        return 0;
    }
    if      (argv[1][0] == 'e') test_exec();
    else if (argv[1][0] == 'd') test_disk();
    else if (argv[1][0] == 'o') test_ok();
    else ax_print("Unknown test. Use exec, disk, or ok.\n");
    return 0;
}
