// Демонстрационная программа: загружается командой "run EXIT.BIN" и
// проверяет добровольное завершение задачи (SYS_EXIT). В отличие от
// hello.c, user_main() здесь ВОЗВРАЩАЕТСЯ - start.asm после этого
// выполняет SYS_EXIT, и schedule() убирает задачу из кольца (ps) на
// следующем тике, освобождая её слот run для повторного использования.
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
    sys_print("EXIT.BIN: running, about to exit via SYS_EXIT...\n");
}
