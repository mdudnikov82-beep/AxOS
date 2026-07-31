#include "syscall.h"

/* Тест code-ASLR (см. project_riscv_code_aslr в памяти): проверяет ОБЕ
 * половины фикса - что программа реально грузится по разным адресам от
 * запуска к запуску (&main меняется), И что относительные к базовому
 * адресу указатели (function-pointer и string-pointer таблицы, ровно то,
 * что производит R_RISCV_64 под -mcmodel=medany) после сдвига остаются
 * КОРРЕКТНЫМИ, а не просто "адрес другой, но всё сломано". */

static void greet_a(void) { puts_rv("  fn_table[0] -> greet_a() called correctly\r\n"); }
static void greet_b(void) { puts_rv("  fn_table[1] -> greet_b() called correctly\r\n"); }
static void greet_c(void) { puts_rv("  fn_table[2] -> greet_c() called correctly\r\n"); }

typedef void (*fn_t)(void);
static const fn_t fn_table[3] = { greet_a, greet_b, greet_c };

static const char *msg_table[3] = {
    "  msg_table[0]: hello",
    "  msg_table[1]: from",
    "  msg_table[2]: ASLRTEST",
};

static void print_hex(unsigned long v) {
    char buf[16];
    for (int i = 15; i >= 0; i--) { buf[i] = "0123456789abcdef"[v & 0xF]; v >>= 4; }
    write(1, buf, 16);
}

int main(void) {
    puts_rv("aslrtest: &main = 0x");
    print_hex((unsigned long)&main);
    puts_rv("\r\n");

    puts_rv("aslrtest: calling through fn_table[] (R_RISCV_64 code-pointer fixup):\r\n");
    for (int i = 0; i < 3; i++) fn_table[i]();

    puts_rv("aslrtest: reading through msg_table[] (R_RISCV_64 data-pointer fixup):\r\n");
    for (int i = 0; i < 3; i++) { puts_rv(msg_table[i]); puts_rv("\r\n"); }

    puts_rv("aslrtest: fn_table[] itself lives at 0x");
    print_hex((unsigned long)fn_table);
    puts_rv("\r\n");

    exit(0);
    return 0;
}
