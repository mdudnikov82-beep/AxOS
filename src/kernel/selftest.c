// =================================================================
//  Регрессионные тесты: heap, paging, FAT12 (команда shell "selftest")
// =================================================================
//
// "Кнопка проверить всё" перед дальнейшими изменениями (VFS и т.д.):
// прогоняет существующий тест кучи (memtest_demo из kernel.c), проверяет
// биты CR0 и записи таблицы страниц после init_paging(), и читает/пишет
// FAT12-том на build/disk.img (если он подключён).

#include "../fs/fat12.h"

#define PAGE_PRESENT 0x1
#define PAGE_RW      0x2
// Тот же физический адрес таблицы страниц, что и в paging.c.
#define PAGE_TABLE   ((unsigned int*)0x9D000)

extern void print_string(char* str);
extern int memtest_demo();

static int buf_eq(unsigned char* a, unsigned char* b, unsigned int len) {
    for (unsigned int i = 0; i < len; i++) {
        if (a[i] != b[i]) return 0;
    }
    return 1;
}

static int test_paging() {
    unsigned int cr0;
    __asm__ volatile("mov %%cr0, %0" : "=r"(cr0));

    if ((cr0 & 0x80010000) != 0x80010000) {
        print_string("Paging: FAIL (CR0.PG/WP not set)\n");
        return 0;
    }

    unsigned int* page_table = PAGE_TABLE;

    // Страница 0x1000 (.text ядра) должна быть PRESENT и read-only.
    unsigned int text_pte = page_table[1];
    if (!(text_pte & PAGE_PRESENT) || (text_pte & PAGE_RW)) {
        print_string("Paging: FAIL (.text page not read-only)\n");
        return 0;
    }

    // Страница 0x30000 (начало кучи) должна быть PRESENT и доступна на запись.
    unsigned int heap_pte = page_table[0x30];
    if (!(heap_pte & PAGE_PRESENT) || !(heap_pte & PAGE_RW)) {
        print_string("Paging: FAIL (heap page not writable)\n");
        return 0;
    }

    print_string("Paging: PASS\n");
    return 1;
}

// Буферы для многокластерного теста — static -> .bss, не увеличивают
// размер kernel.bin.
static unsigned char fat12_test_buf[1100];
static unsigned char fat12_test_readback[1100];

static int test_fat12() {
    if (!fat12_is_ready()) {
        print_string("FAT12: SKIP (disk not ready)\n");
        return 1;
    }

    int was_locked = fat12_is_locked();
    fat12_set_locked(0);
    int ok = 1;

    // Тест 1: один кластер.
    char* msg = "AxOS selftest\n";
    unsigned int msg_len = 14;
    if (!fat12_write("SELFTST.TXT", (unsigned char*)msg, msg_len)) {
        print_string("  FAIL: fat12_write (single cluster) failed\n");
        ok = 0;
    } else {
        unsigned char readback[32];
        unsigned int read_len = fat12_load("SELFTST.TXT", readback, sizeof(readback));
        if (read_len != msg_len || !buf_eq(readback, (unsigned char*)msg, msg_len)) {
            print_string("  FAIL: single-cluster read-back mismatch\n");
            ok = 0;
        }
    }

    // Тест 2: несколько кластеров (форсирует free+realloc цепочки кластеров).
    for (unsigned int i = 0; i < sizeof(fat12_test_buf); i++) {
        fat12_test_buf[i] = (unsigned char)(i & 0xFF);
    }
    if (!fat12_write("SELFTST.TXT", fat12_test_buf, sizeof(fat12_test_buf))) {
        print_string("  FAIL: fat12_write (multi-cluster) failed\n");
        ok = 0;
    } else {
        unsigned int read_len = fat12_load("SELFTST.TXT", fat12_test_readback, sizeof(fat12_test_readback));
        if (read_len != sizeof(fat12_test_buf) || !buf_eq(fat12_test_readback, fat12_test_buf, sizeof(fat12_test_buf))) {
            print_string("  FAIL: multi-cluster read-back mismatch\n");
            ok = 0;
        }
    }

    // Тест 3: запись должна отказывать, пока диск заблокирован.
    fat12_set_locked(1);
    if (fat12_write("SELFTST.TXT", (unsigned char*)msg, msg_len)) {
        print_string("  FAIL: fat12_write succeeded while disk locked\n");
        ok = 0;
    }

    fat12_set_locked(was_locked);

    if (ok) {
        print_string("FAT12: PASS\n");
    } else {
        print_string("FAT12: FAIL\n");
    }
    return ok;
}

void run_self_tests() {
    print_string("\n--- Self-test ---\n");

    int heap_ok = memtest_demo();
    int paging_ok = test_paging();
    int fat12_ok = test_fat12();

    if (heap_ok && paging_ok && fat12_ok) {
        print_string("SELFTEST: ALL PASS\n");
    } else {
        print_string("SELFTEST: FAILED\n");
    }
}
