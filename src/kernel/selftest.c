// =================================================================
//  Регрессионные тесты: heap, paging, FAT12 (команда shell "selftest")
// =================================================================
//
// "Кнопка проверить всё" перед дальнейшими изменениями:
// прогоняет существующий тест кучи (memtest_demo из kernel.c), проверяет
// биты CR0 и записи таблицы страниц после init_paging(), и читает/пишет
// FAT12-том на build/disk.img (если он подключён) через VFS-интерфейс.

#include "vfs.h"
#include "paging.h"

extern void print_string(char* str);
extern int memtest_demo();

static int buf_eq(unsigned char* a, unsigned char* b, unsigned int len) {
    for (unsigned int i = 0; i < len; i++) {
        if (a[i] != b[i]) return 0;
    }
    return 1;
}

static int test_paging() {
    unsigned long long cr0, cr4;
    __asm__ volatile("mov %%cr0, %0" : "=r"(cr0));
    __asm__ volatile("mov %%cr4, %0" : "=r"(cr4));

    if ((cr0 & 0x80010000) != 0x80010000) {
        print_string("\033[31mPaging: FAIL (CR0.PG/WP not set)\033[0m\n");
        return 0;
    }
    if (!(cr4 & 0x20)) {
        print_string("\033[31mPaging: FAIL (CR4.PAE not set)\033[0m\n");
        return 0;
    }

    // GLOBAL_PT0 (0x9F000) покрывает VA 0..2МБ, запись i = PTE для VA i*4КБ.
    // PT0[1] → VA 0x1000 (.text ядра): PRESENT, read-only (R/W=0).
    //
    // ИСПРАВЛЕНО: этот тест раньше молча всегда проваливался - читал
    // 0x9E000 (это GLOBAL_PD, не GLOBAL_PT0!) под именем PAE_PT0. Адрес
    // был верным ДО перехода на 4-уровневую адресацию (PML4→PDPT→PD→PT0),
    // которая вставила лишний уровень и сдвинула PT0 на 0x9F000 - этот
    // файл тогда не поправили. PD[1] (то, что реально читалось) - 2МБ
    // huge page с RW=1 (данные ядра), поэтому "не read-only" срабатывало
    // всегда, независимо от реального состояния .text.
    unsigned long long text_pte = GLOBAL_PT0[1];
    if (!(text_pte & 1) || (text_pte & 2)) {
        print_string("\033[31mPaging: FAIL (.text page not read-only)\033[0m\n");
        return 0;
    }

    // Куча ядра теперь живёт за отдельной случайной PML4->PDPT->PD цепочкой
    // (настоящий 64-битный KASLR, см. paging.h/paging.c), а не в GLOBAL_PD -
    // g_kheap_base больше не "PD-индекс × 2МБ", а полноценный 4-уровневый
    // виртуальный адрес. Раскладываем его на индексы ТЕМ ЖЕ способом, каким
    // это делает сам MMU (9+9+9 бит), и обходим таблицы по-настоящему -
    // не полагаемся на знание, КАК paging.c выбрал индексы, только на
    // формат самого адреса.
    unsigned long long va = g_kheap_base;
    unsigned int kheap_pml4_idx = (unsigned int)((va >> 39) & 0x1FFULL);
    unsigned int kheap_pdpt_idx = (unsigned int)((va >> 30) & 0x1FFULL);
    unsigned int kheap_pd_idx   = (unsigned int)((va >> 21) & 0x1FFULL);

    unsigned long long pml4e = GLOBAL_PML4[kheap_pml4_idx];
    if (!(pml4e & 1)) {
        print_string("\033[31mPaging: FAIL (heap PML4 entry not present)\033[0m\n");
        return 0;
    }
    unsigned long long* kheap_pdpt = (unsigned long long*)(pml4e & ~0xFFFULL);
    unsigned long long pdpte = kheap_pdpt[kheap_pdpt_idx];
    if (!(pdpte & 1)) {
        print_string("\033[31mPaging: FAIL (heap PDPT entry not present)\033[0m\n");
        return 0;
    }
    unsigned long long* kheap_pd = (unsigned long long*)(pdpte & ~0xFFFULL);
    unsigned long long heap_pde = kheap_pd[kheap_pd_idx];
    if (!(heap_pde & 1) || !(heap_pde & 2)) {
        print_string("\033[31mPaging: FAIL (heap page not writable)\033[0m\n");
        return 0;
    }

    print_string("\033[32mPaging: PASS (PAE+W^X)\033[0m\n");
    return 1;
}

// Буферы для многокластерного теста — static -> .bss, не увеличивают
// размер kernel.bin.
static unsigned char fat12_test_buf[1100];
static unsigned char fat12_test_readback[1100];

static int test_fat12() {
    if (!vfs_is_ready()) {
        print_string("\033[33mFAT12: SKIP (disk not ready)\033[0m\n");
        return 1;
    }

    int was_locked = vfs_is_locked();
    vfs_set_locked(0);
    int ok = 1;

    // Тест 1: один кластер.
    char* msg = "AxOS selftest\n";
    unsigned int msg_len = 14;
    if (!vfs_write("SELFTST.TXT", (unsigned char*)msg, msg_len)) {
        print_string("\033[31m  FAIL: vfs_write (single cluster) failed\033[0m\n");
        ok = 0;
    } else {
        unsigned char readback[32];
        unsigned int read_len = vfs_read("SELFTST.TXT", readback, sizeof(readback));
        if (read_len != msg_len || !buf_eq(readback, (unsigned char*)msg, msg_len)) {
            print_string("\033[31m  FAIL: single-cluster read-back mismatch\033[0m\n");
            ok = 0;
        }
    }

    // Тест 2: несколько кластеров (форсирует free+realloc цепочки кластеров).
    for (unsigned int i = 0; i < sizeof(fat12_test_buf); i++) {
        fat12_test_buf[i] = (unsigned char)(i & 0xFF);
    }
    if (!vfs_write("SELFTST.TXT", fat12_test_buf, sizeof(fat12_test_buf))) {
        print_string("\033[31m  FAIL: vfs_write (multi-cluster) failed\033[0m\n");
        ok = 0;
    } else {
        unsigned int read_len = vfs_read("SELFTST.TXT", fat12_test_readback, sizeof(fat12_test_readback));
        if (read_len != sizeof(fat12_test_buf) || !buf_eq(fat12_test_readback, fat12_test_buf, sizeof(fat12_test_buf))) {
            print_string("\033[31m  FAIL: multi-cluster read-back mismatch\033[0m\n");
            ok = 0;
        }
    }

    // Тест 3: запись должна отказывать, пока диск заблокирован.
    vfs_set_locked(1);
    if (vfs_write("SELFTST.TXT", (unsigned char*)msg, msg_len)) {
        print_string("\033[31m  FAIL: vfs_write succeeded while disk locked\033[0m\n");
        ok = 0;
    }

    vfs_set_locked(was_locked);

    if (ok) {
        print_string("\033[32mFAT12: PASS\033[0m\n");
    } else {
        print_string("\033[31mFAT12: FAIL\033[0m\n");
    }
    return ok;
}

void run_self_tests() {
    print_string("\n\033[36m--- Self-test ---\033[0m\n");

    int heap_ok = memtest_demo();
    int paging_ok = test_paging();
    int fat12_ok = test_fat12();

    if (heap_ok && paging_ok && fat12_ok) {
        print_string("\033[32mSELFTEST: ALL PASS\033[0m\n");
    } else {
        print_string("\033[31mSELFTEST: FAILED\033[0m\n");
    }
}
