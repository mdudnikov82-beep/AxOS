// Демонстрационная программа: загружается командой "run CRASH.BIN" и
// проверяет принудительное завершение задачи (kill при page fault, см.
// paging.c::page_fault_handler_main). Пишет по адресу 0x200000 - вне
// своего окна 0x100000-0x108000, где приватный Page Directory этой
// задачи (paging_create_user_directory) сбрасывает PAGE_USER. Из ring3
// это вызывает #PF; ядро убивает только эту задачу, остальные (shell,
// heartbeat, ring3demo) продолжают работать.
#include "syscall.h"

static void sys_print(char* msg) {
    __asm__ volatile(
        "mov $0x01, %%ah\n" // SYS_PRINT_STRING
        "mov %0, %%esi\n"
        "int $0x80\n"
        :: "r"(msg) : "eax", "esi"
    );
}

void user_main() {
    sys_print("CRASH.BIN: about to access forbidden memory at 0x200000...\n");

    volatile unsigned int* bad = (unsigned int*)0x200000;
    *bad = 0xDEADBEEF;

    sys_print("CRASH.BIN: this should never print.\n");
}
