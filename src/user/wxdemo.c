#include "axiom.h"

// W^X демо: проверяем, что страницы кода non-writable, а стек non-executable.
//
// Использование:
//   wxdemo write   → попытка записи в страницу кода → PAGE FAULT (task killed)
//   wxdemo exec    → попытка выполнения кода со стека → PAGE FAULT (NX violation)
//   wxdemo         → подсказка

static void test_write(void) {
    ax_print("[W^X write] Attempting write to code page...\n");
    // Пишем по адресу самой функции - код должен быть read-only (R/W=0).
    volatile unsigned char* ptr = (volatile unsigned char*)(unsigned int)test_write;
    *ptr = 0x00;
    // Если дошли сюда - W^X не работает.
    ax_print("[W^X write] FAIL: code page was writable!\n");
}

static void test_exec(void) {
    ax_print("[W^X exec] Attempting execute from data page (heap)...\n");
    // Стек живёт в spin-странице (последняя страница окна, всегда RW+X),
    // поэтому для надёжного теста NX берём буфер из кучи - она лежит
    // в страницах данных (RW+NX). Попытка выполнить код оттуда должна
    // вызвать #PF (NX/XD нарушение).
    unsigned char* buf = (unsigned char*)ax_malloc(8);
    if (!buf) { ax_print("[W^X exec] malloc failed\n"); return; }
    buf[0] = 0xC3; // RET
    typedef void (*fn_t)(void);
    fn_t f = (fn_t)(void*)buf;
    f();
    // Если дошли сюда - NX не работает (или не поддерживается ЦП).
    ax_print("[W^X exec] FAIL: data page was executable (NX not active)!\n");
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;
    if (argc < 2) {
        ax_print("Usage: wxdemo write|exec\n");
        ax_print("  write - write to code page  (expect: PAGE FAULT)\n");
        ax_print("  exec  - execute from data page (expect: PAGE FAULT if NX)\n");
        return 0;
    }
    if (argv[1][0] == 'w') test_write();
    else if (argv[1][0] == 'e') test_exec();
    else ax_print("Unknown test. Use 'write' or 'exec'.\n");
    return 0;
}
