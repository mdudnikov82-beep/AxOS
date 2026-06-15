// Демонстрационная пользовательская программа: загружается с FAT12-диска
// командой "run HELLO.BIN" и выполняется в ring3. Показывает все
// доступные ring3-syscall'ы (см. syscall.h): печать строки, запись и
// чтение файла, неблокирующее чтение клавиатуры.
#include "syscall.h"

static void sys_print(char* msg) {
    __asm__ volatile(
        "mov $0x01, %%ah\n" // SYS_PRINT_STRING
        "mov %0, %%esi\n"
        "int $0x80\n"
        :: "r"(msg) : "eax", "esi"
    );
}

static void sys_readkey(char* out) {
    __asm__ volatile(
        "mov $0x03, %%ah\n" // SYS_READ_KEY
        "mov %0, %%esi\n"
        "int $0x80\n"
        :: "r"(out) : "eax", "esi"
    );
}

static void sys_writefile(struct write_file_args* a) {
    __asm__ volatile(
        "mov $0x04, %%ah\n" // SYS_WRITE_FILE
        "mov %0, %%esi\n"
        "int $0x80\n"
        :: "r"(a) : "eax", "esi"
    );
}

static void sys_readfile(struct read_file_args* a) {
    __asm__ volatile(
        "mov $0x05, %%ah\n" // SYS_READ_FILE
        "mov %0, %%esi\n"
        "int $0x80\n"
        :: "r"(a) : "eax", "esi"
    );
}

void user_main() {
    sys_print("Hello from HELLO.BIN, loaded from FAT12 and run in ring3!\n");

    // Записываем файл из ring3 через SYS_WRITE_FILE...
    char* msg = "Written from ring3 via SYS_WRITE_FILE!\n";
    unsigned int len = 0;
    while (msg[len] != '\0') len++;

    struct write_file_args wargs = { "RING3.TXT", (unsigned char*)msg, len };
    sys_writefile(&wargs);

    // ...и читаем обратно через SYS_READ_FILE.
    char buf[128];
    struct read_file_args rargs = { "RING3.TXT", (unsigned char*)buf, sizeof(buf) - 1, 0 };
    sys_readfile(&rargs);
    buf[rargs.out_size] = '\0';
    sys_print(buf);

    // Дальше - эхо набираемых символов через неблокирующий SYS_READ_KEY.
    while (1) {
        char key = 0;
        sys_readkey(&key);
        if (key != 0 && key != '\n' && key != '\b') {
            char s[2] = {key, '\0'};
            sys_print(s);
        }
    }
}
