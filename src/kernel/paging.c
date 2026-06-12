// =================================================================
//  Paging: identity-mapping + защита кода ядра от записи
// =================================================================
//
// Отображаем первые 4 МБ виртуальной памяти 1:1 на физическую (этого
// достаточно: ядро, FAT12-раздел, стек и видеопамять все лежат внутри
// этого диапазона). Страницы, целиком занятые секцией .text ядра,
// помечаются как read-only — после включения CR0.WP даже код ring0
// не сможет записать в них (случайно или намеренно).

#define PAGE_PRESENT 0x1
#define PAGE_RW      0x2
#define PAGE_USER    0x4
#define PAGE_SIZE    0x1000

// Каталог страниц и таблица страниц размещаются по фиксированным физическим
// адресам в свободной области между стеком (растёт вниз от 0x90000) и
// видеопамятью (0xA0000), а не как статические массивы в .bss. Так размер
// kernel.bin не растёт на 8 КБ и не выходит за пределы региона, который
// boot.asm грузит с диска.
#define PAGE_DIRECTORY ((unsigned int*)0x9C000)
#define PAGE_TABLE     ((unsigned int*)0x9D000)

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

// Вызывается из idt.asm при исключении #14. CR2 содержит адрес,
// обращение к которому вызвало сбой.
void page_fault_handler_main(unsigned int faulting_address) {
    print_string("\n*** PAGE FAULT at 0x");
    print_hex(faulting_address);
    print_string(" ***\nSystem halted.\n");

    while (1) {
        __asm__("hlt");
    }
}
