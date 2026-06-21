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
//
// --- Усиление (в духе hardened_malloc/GrapheneOS, но по средствам
// учебной ОС без MMU-гранулярных guard-страниц) ---
// 1. magic в заголовке: free() отказывается работать с указателем,
//    чей заголовок не похож на "выделенный нами блок" (чужой/мусорный
//    указатель), и явно детектирует double-free, вместо того чтобы
//    тихо повторно влинковать уже свободный блок в список (именно так
//    double-free обычно превращается в управляемую запись по
//    произвольному адресу в классических аллокаторах).
// 2. canary сразу после пользовательских данных: linear-overflow,
//    который раньше тихо переписывал заголовок СЛЕДУЮЩЕГО блока,
//    теперь детектируется в free() ДО того, как испорченный заголовок
//    успеет что-то сломать.
//
// Зануление данных при free() (как у hardened_malloc) сюда сознательно
// НЕ добавлено: tasking.c::schedule() освобождает кадровый стек задачи,
// реально выполняющейся НА ЭТОМ ЖЕ стеке в момент вызова free() (ESP0/CR3
// переключаются позже) - запись в этот блок здесь означает запись под
// собственным текущим кадром вызовов. malloc()/free() здесь читают
// заголовки и канарейку, но никогда не пишут в чужую "полезную область".
//
// Это не криптографическая защита (canary - фиксированное значение, не
// рандомизированное per-boot) и не ловит все классы багов (например,
// чтение/запись ДО начала блока), но даёт громкий, детерминированный
// отказ вместо тихой порчи кучи - на этом этапе важнее первое.

extern void print_string(char* str);

#define HEAP_START 0x40000  /* must be > FAT12_BASE + FAT12_TOTAL_SECTORS*512 = 0x3FFFF */
#define HEAP_END   0x90000
#define HEAP_SIZE  (HEAP_END - HEAP_START)

// Видны только тут, размер блока подбирался не под "осмысленное" слово -
// случайный указатель/мусор с шансом 1/2^32 совпадёт, но это не криптография,
// а защита от типичных багов (double-free, переполнение), не от атакующего,
// который уже читает память ядра.
#define HEAP_MAGIC_ALLOC 0x4C41434Bu // "KCAL" - блок выделен, под пользователем
#define HEAP_MAGIC_FREE  0x46524545u // "EERF" - блок свободен (в списке/после free())

#define CANARY_SIZE  4
#define CANARY_VALUE 0xACACACACu

typedef struct block_header {
    unsigned int size;          // размер полезной области (без заголовка), байт
    int free;                   // 1 - блок свободен, 0 - занят
    struct block_header* next;  // следующий блок в списке (или NULL)
    unsigned int magic;         // HEAP_MAGIC_ALLOC/HEAP_MAGIC_FREE - см. комментарий выше
} block_header_t;

#define HEADER_SIZE (sizeof(block_header_t))

// Минимальный полезный размер блока при разбиении: если остаток после
// выделения меньше HEADER_SIZE + MIN_BLOCK_SIZE, блок не разбивается -
// избегаем "блоков-крошек", в которые ничего не влезет.
#define MIN_BLOCK_SIZE 16

// Выравнивание размера запроса malloc() до кратного 4 байт.
#define ALIGN4(x) (((x) + 3) & ~3)

static block_header_t* heap_head = (block_header_t*)HEAP_START;

static void heap_corrupted(char* why) {
    print_string("\n*** HEAP CORRUPTION: ");
    print_string(why);
    print_string(" ***\nSystem halted.\n");
    while (1) {
        __asm__("hlt");
    }
}

// --- Критическая секция ---
// malloc()/free() не реентерабельны: они мутируют общий связный список
// heap_head шаг за шагом (без атомарности отдельных записей). Сегодня
// от реентерабельного вызова их спасает только то, что IDT[0x80] и
// IRQ0 (idt.asm) - оба interrupt gate (type_attr оканчивается на E),
// и CPU сам обнуляет IF на входе: пока ядро внутри malloc()/free()
// (в т.ч. вызванных из schedule() при реапе задачи - kernel.c:62,
// tasking.c:251), таймер физически не может прервать и вызвать
// schedule()->free() повторно на той же куче.
//
// ВНИМАНИЕ: это неявное соглашение. Если когда-нибудь в пути от int 0x80
// до malloc()/free() появится sti() (как уже сделано в sleep_ms(),
// kernel.c:173, просто пока не на одном пути с кучей) - получим гонку
// и порчу heap_head. ENTER/LEAVE_CRITICAL ниже защищают явно: сохраняют
// и восстанавливают реальный IF, а не включают прерывания "вслепую" -
// безусловный sti в конце free(), вызванного из глубины schedule()
// (до его iret, idt.asm:50-55), мог бы включить прерывания раньше
// времени и впустить вложенное прерывание в недопереключённый планировщик.
#define ENTER_CRITICAL(flags) \
    __asm__ volatile("pushfl\n\tpopl %0\n\tcli" : "=r"(flags) :: "memory")
#define LEAVE_CRITICAL(flags) \
    __asm__ volatile("pushl %0\n\tpopfl" :: "r"(flags) : "memory", "cc")

void init_heap() {
    heap_head = (block_header_t*)HEAP_START;
    heap_head->size = HEAP_SIZE - HEADER_SIZE;
    heap_head->free = 1;
    heap_head->next = 0;
    heap_head->magic = HEAP_MAGIC_FREE;
}

void* malloc(unsigned int size) {
    if (size == 0) return 0;
    size = ALIGN4(size);

    // Сколько физически нужно отрезать от свободного блока: данные +
    // канарейка сразу после них (см. комментарий в начале файла).
    unsigned int reserved = size + CANARY_SIZE;

    unsigned long flags;
    ENTER_CRITICAL(flags);

    void* result = 0;
    block_header_t* current = heap_head;

    while (current) {
        if (current->free && current->size >= reserved) {
            unsigned int remaining = current->size - reserved;
            if (remaining >= HEADER_SIZE + MIN_BLOCK_SIZE) {
                block_header_t* new_block =
                    (block_header_t*)((unsigned char*)current + HEADER_SIZE + reserved);
                new_block->size = remaining - HEADER_SIZE;
                new_block->free = 1;
                new_block->magic = HEAP_MAGIC_FREE;
                new_block->next = current->next;

                current->size = reserved;
                current->next = new_block;
            }

            // current->size теперь либо `reserved` (блок разбили), либо
            // исходный (больший) размер свободного блока (не разбили -
            // "хвост" по-прежнему часть этого же блока, как и в исходном
            // алгоритме). Канарейка - ВСЕГДА у фактической границы блока
            // (current->size), а не у запрошенного size: иначе free(),
            // зная только current->size, занулял(/проверял) бы неверную
            // длину в неразбитом случае и затирал заголовок СЛЕДУЮЩЕГО
            // блока вместо своей же "слабины".
            current->free = 0;
            current->magic = HEAP_MAGIC_ALLOC;
            result = (void*)((unsigned char*)current + HEADER_SIZE);
            *(unsigned int*)((unsigned char*)result + (current->size - CANARY_SIZE)) = CANARY_VALUE;
            break;
        }

        current = current->next;
    }

    LEAVE_CRITICAL(flags);
    return result;
}

void free(void* ptr) {
    if (!ptr) return;

    unsigned long flags;
    ENTER_CRITICAL(flags);

    block_header_t* block = (block_header_t*)((unsigned char*)ptr - HEADER_SIZE);

    // Чужой/мусорный указатель или double-free - не трогаем список (тихая
    // порча связного списка кучи отсюда обычно расползается намного дальше
    // места первоначальной ошибки и её куда сложнее диагностировать).
    if (block->magic == HEAP_MAGIC_FREE) {
        heap_corrupted("double free()");
    }
    if (block->magic != HEAP_MAGIC_ALLOC) {
        heap_corrupted("free() on invalid/foreign pointer");
    }

    unsigned int user_size = block->size - CANARY_SIZE;
    unsigned int canary = *(unsigned int*)((unsigned char*)ptr + user_size);
    if (canary != CANARY_VALUE) {
        heap_corrupted("buffer overflow (canary)");
    }

    // НЕ зануляем пользовательские данные здесь, как делают многие
    // hardened-аллокаторы: free(dying->kernel_stack_top - KSTACK_SIZE)
    // освобождает кадровый стек ЗАДАЧИ, ВЫПОЛНЯЮЩЕЙСЯ ПРЯМО СЕЙЧАС на этом
    // же стеке (schedule() в tasking.c реапит её до переключения ESP0/CR3 -
    // см. комментарий там) - запись в этот блок здесь означает запись под
    // собственным текущим кадром вызовов (адреса возврата, локальные
    // переменные ЭТОГО free()), что и обнаружилось triple fault'ом при
    // проверке. Магия+канарейка достаточно, т.к. они только ЧИТАЮТ.

    block->free = 1;
    block->magic = HEAP_MAGIC_FREE;

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

    LEAVE_CRITICAL(flags);
}
