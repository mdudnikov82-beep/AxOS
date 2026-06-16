#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    ax_printf("=== malloc_test ===\n");
    ax_printf("initial brk: %x\n\n", (unsigned int)ax_sbrk(0));

    // Аллокация трёх блоков
    void* p1 = ax_malloc(1024);
    void* p2 = ax_malloc(2048);
    void* p3 = ax_malloc(512);
    ax_printf("p1 (1024): %x\n", (unsigned int)p1);
    ax_printf("p2 (2048): %x\n", (unsigned int)p2);
    ax_printf("p3 ( 512): %x\n", (unsigned int)p3);
    ax_printf("brk after: %x\n\n", (unsigned int)ax_sbrk(0));

    // Записываем в выделенную память и читаем обратно
    if (p1) {
        unsigned char* b = (unsigned char*)p1;
        for (unsigned int i = 0; i < 16; i++) b[i] = (unsigned char)i;
        unsigned int ok = 1;
        for (unsigned int i = 0; i < 16; i++) if (b[i] != (unsigned char)i) { ok = 0; break; }
        ax_printf("write/read p1: %s\n\n", ok ? "OK" : "FAIL");
    }

    // free p1, затем malloc того же размера — должен вернуть тот же адрес
    ax_free(p1);
    void* p4 = ax_malloc(1024);
    ax_printf("free p1, malloc(1024) again: %x\n", (unsigned int)p4);
    ax_printf("reuse: %s\n\n", (p4 == p1) ? "YES (free-list works)" : "NO");

    // Освобождаем всё
    ax_free(p2);
    ax_free(p3);
    ax_free(p4);
    ax_printf("all freed.\n");
    return 0;
}
