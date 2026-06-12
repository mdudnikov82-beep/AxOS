// =================================================================
//  Heap allocator: kmalloc/kfree поверх региона 0x30000-0x90000
// =================================================================
//
// Регион 0x30000-0x90000 (384 КБ) свободен: выше FAT12-образа
// (0x20000-0x30000) и ниже стека ядра (растёт вниз от 0x90000).
// Он identity-mapped и доступен на запись (init_paging помечает
// read-only только страницы внутри .text).
//
// Структура данных - классический связный список блоков. Перед
// каждым выделенным/свободным блоком лежит заголовок block_header_t.
// malloc() ищет первый достаточно большой свободный блок (first-fit),
// при избытке места разбивает его на два. free() помечает блок
// свободным и сливает его с соседними свободными блоками в списке
// (coalescing).

#define HEAP_START 0x30000
#define HEAP_END   0x90000
#define HEAP_SIZE  (HEAP_END - HEAP_START)

typedef struct block_header {
    unsigned int size;          // размер полезной области (без заголовка), байт
    int free;                   // 1 - блок свободен, 0 - занят
    struct block_header* next;  // следующий блок в списке (или NULL)
} block_header_t;

#define HEADER_SIZE (sizeof(block_header_t))

// Минимальный полезный размер блока при разбиении: если остаток после
// выделения меньше HEADER_SIZE + MIN_BLOCK_SIZE, блок не разбивается -
// избегаем "блоков-крошек", в которые ничего не влезет.
#define MIN_BLOCK_SIZE 16

// Выравнивание размера запроса malloc() до кратного 4 байт.
#define ALIGN4(x) (((x) + 3) & ~3)

static block_header_t* heap_head = (block_header_t*)HEAP_START;

void init_heap() {
    heap_head = (block_header_t*)HEAP_START;
    heap_head->size = HEAP_SIZE - HEADER_SIZE;
    heap_head->free = 1;
    heap_head->next = 0;
}

void* malloc(unsigned int size) {
    if (size == 0) return 0;
    size = ALIGN4(size);

    block_header_t* current = heap_head;

    while (current) {
        if (current->free && current->size >= size) {
            unsigned int remaining = current->size - size;
            if (remaining >= HEADER_SIZE + MIN_BLOCK_SIZE) {
                block_header_t* new_block =
                    (block_header_t*)((unsigned char*)current + HEADER_SIZE + size);
                new_block->size = remaining - HEADER_SIZE;
                new_block->free = 1;
                new_block->next = current->next;

                current->size = size;
                current->next = new_block;
            }

            current->free = 0;
            return (void*)((unsigned char*)current + HEADER_SIZE);
        }

        current = current->next;
    }

    return 0;
}

void free(void* ptr) {
    if (!ptr) return;

    block_header_t* block = (block_header_t*)((unsigned char*)ptr - HEADER_SIZE);
    block->free = 1;

    // Слияние со следующим блоком, если он тоже свободен
    if (block->next && block->next->free) {
        block->size += HEADER_SIZE + block->next->size;
        block->next = block->next->next;
    }

    // Поиск предшественника block и слияние, если он свободен
    block_header_t* current = heap_head;
    while (current && current->next != block) {
        current = current->next;
    }
    if (current && current->free) {
        current->size += HEADER_SIZE + block->size;
        current->next = block->next;
    }
}
