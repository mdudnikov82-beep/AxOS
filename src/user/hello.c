// Демонстрационная пользовательская программа: загружается с FAT12-диска
// командой "run HELLO.BIN" и выполняется в ring3. Печатает строку через
// системный вызов int 0x80 (AH=0x01 - sys_print_string, см. kernel.c),
// затем крутится в бесконечном цикле, как usermode_demo.
void user_main() {
    char* msg = "Hello from HELLO.BIN, loaded from FAT12 and run in ring3!\n";

    __asm__ volatile(
        "mov $0x01, %%ah\n"
        "mov %0, %%esi\n"
        "int $0x80\n"
        :: "r"(msg) : "eax", "esi"
    );

    while (1) {
    }
}
