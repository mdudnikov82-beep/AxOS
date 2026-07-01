// =================================================================
//  Paging: identity-mapping + защита кода ядра от записи
// =================================================================
//
// Отображаем первые 4 МБ виртуальной памяти 1:1 на физическую (этого
// достаточно: ядро, FAT12-раздел, стек и видеопамять все лежат внутри
// этого диапазона). Страницы, целиком занятые секцией .text ядра,
// помечаются как read-only — после включения CR0.WP даже код ring0
// не сможет записать в них (случайно или намеренно).

#include "paging.h"
#include "tasking.h"

#define PAGE_PRESENT 0x1
#define PAGE_RW      0x2
#define PAGE_USER    0x4
#define PAGE_SIZE    0x1000

// Каталог страниц и таблица страниц размещаются по фиксированным физическим
// адресам в свободной области между стеком (растёт вниз от 0x90000) и
// видеопамятью (0xA0000), а не как статические массивы в .bss. Так размер
// kernel.bin не растёт на 8 КБ и не выходит за пределы региона, который
// boot.asm грузит с диска. См. PAGE_DIRECTORY/PAGE_TABLE в paging.h.

extern void print_string(char* str);
extern char _text_end[]; // GCC: __text_end из kernel.ld

void init_paging() {
    unsigned int text_end = (unsigned int)_text_end & ~(PAGE_SIZE - 1);
    unsigned int* page_table = PAGE_TABLE;
    unsigned int* page_directory = PAGE_DIRECTORY;

    for (unsigned int i = 0; i < 1024; i++) {
        unsigned int addr = i * PAGE_SIZE;
        unsigned int flags = PAGE_PRESENT | PAGE_USER;

        // Страница целиком внутри .text (от 0x1000 до конца кода ядра) -> только чтение
        if (!(addr >= 0x1000 && addr + PAGE_SIZE <= text_end)) {
            flags |= PAGE_RW;
        }

        page_table[i] = addr | flags;
    }

    // Guard page: стек ядра начинается в 0x90000 и растёт вниз.
    // Страница 0x8C000 помечается NOT PRESENT — overflow глубже 16 КБ
    // вызывает #PF и останавливает систему, вместо того чтобы молча
    // затереть данные кучи (0x70000-0x90000).
    page_table[0x8C] = 0;

    page_directory[0] = ((unsigned int)page_table) | PAGE_PRESENT | PAGE_RW | PAGE_USER;
    for (unsigned int i = 1; i < 1024; i++) {
        page_directory[i] = 0;
    }

    __asm__ volatile(
        "mov %0, %%cr3\n"
        "mov %%cr0, %%eax\n"
        "or $0x80010000, %%eax\n" // бит 31 (PG) + бит 16 (WP)
        "mov %%eax, %%cr0\n"
        :: "r"(page_directory) : "eax"
    );
}

unsigned int paging_create_user_directory(int user_slot_index, unsigned int phys_slot_base) {
    unsigned int* src_table = PAGE_TABLE;
    unsigned int* dst_table = (unsigned int*)(PT_POOL_BASE + (unsigned int)user_slot_index * PAGE_SIZE);
    unsigned int* dst_dir   = (unsigned int*)(PD_POOL_BASE + (unsigned int)user_slot_index * PAGE_SIZE);

    // Копия глобальной PT, но без PAGE_USER - ring3 этой задачи по
    // умолчанию не видит ничего (kernel-only).
    for (unsigned int i = 0; i < 1024; i++) {
        dst_table[i] = src_table[i] & ~(unsigned int)PAGE_USER;
    }

    // Окно 0x100000-0x108000 -> физический слот этой задачи, PRESENT|RW|USER.
    unsigned int first_page = USER_WINDOW_BASE / PAGE_SIZE;
    for (unsigned int i = 0; i < USER_WINDOW_PAGES; i++) {
        unsigned int addr = phys_slot_base + i * PAGE_SIZE;
        dst_table[first_page + i] = addr | PAGE_PRESENT | PAGE_RW | PAGE_USER;
    }

    dst_dir[0] = ((unsigned int)dst_table) | PAGE_PRESENT | PAGE_RW | PAGE_USER;
    for (unsigned int i = 1; i < 1024; i++) {
        dst_dir[i] = 0;
    }

    return (unsigned int)dst_dir;
}

static void print_hex(unsigned int val) {
    char hex_digits[] = "0123456789ABCDEF";
    char buf[9];
    buf[8] = '\0';
    for (int i = 7; i >= 0; i--) {
        buf[i] = hex_digits[val & 0xF];
        val >>= 4;
    }
    print_string(buf);
}

// Индексы в кадре pusha (idt.asm): после pusha (8 dword) и кода ошибки CPU
// кладёт EIP, затем CS.
#define PF_FRAME_EIP 9
#define PF_FRAME_CS  10

// Вызывается из idt.asm при исключении #14. CR2 содержит адрес,
// обращение к которому вызвало сбой. frame - указатель на сохранённые
// pusha-регистры (idt.asm передаёт esp сразу после pusha).
void page_fault_handler_main(unsigned int faulting_address, unsigned int* frame) {
    unsigned int cs = frame[PF_FRAME_CS];

    // Ring3-fault изолированной run-задачи - убиваем только её, а не всю
    // систему: помечаем на удаление (schedule() реапнет на следующем
    // тике) и перенаправляем EIP на безопасный "jmp $" в её собственном
    // окне (USER_SPIN_ADDR, записан при создании задачи в tasking.c).
    if ((cs & 3) == 3 && task_current_is_isolated()) {
        print_string("\n\033[33m*** PAGE FAULT in '"); // жёлтый - предупреждение, не фатально
        print_string(task_current_name());
        print_string("' at 0x");
        print_hex(faulting_address);
        print_string(" - task killed ***\033[0m\n");

        task_mark_current_exiting();
        frame[PF_FRAME_EIP] = USER_SPIN_ADDR;
        return;
    }

    // Fault в ring0 (баг ядра) или у встроенной демо-задачи без изоляции
    // (ring3demo/usermode) - как раньше, останавливаем всю систему.
    print_string("\n\033[31m*** PAGE FAULT at 0x"); // красный - фатально, система встала
    print_hex(faulting_address);
    print_string(" ***\nSystem halted.\033[0m\n");

    while (1) {
        __asm__("hlt");
    }
}
