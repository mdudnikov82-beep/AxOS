// =================================================================
//  Heap allocator: kmalloc/kfree поверх g_kheap_base..+KHEAP_SIZE
// =================================================================
//
// Раньше куча жила в 128КБ (0x70000-0x90000), зажатых между FAT12-образом
// и стеком ядра, внутри тех же первых 4МБ, которые init_paging()
// identity-map'ит с самого начала. С 2026-07 куча переехала в отдельный
// регион (32МБ, KHEAP_SIZE) сразу после этих 4МБ - init_paging() добавляет
// туда ещё 2МБ huge pages (kernel-only, NX), которые раньше стояли
// занулёнными (not present), хотя сама 4-уровневая 64-битная адресация уже
// была на месте. 128КБ на практике хватало впритык (task-структуры,
// ELF-стейджинг и т.п. постоянно жались друг к другу); 32МБ - это
// фактическое использование того адресного пространства, которое
// long-mode paging уже предоставлял, а не расширение самой архитектуры.
//
// KASLR-lite: базовый адрес (g_kheap_base) больше не константа - init_paging()
// (paging.c) выбирает его случайно при каждой загрузке, см. комментарий у
// g_kheap_base в paging.h.
//
// Структура данных - классический связный список блоков. Перед
// каждым выделенным/свободным блоком лежит заголовок block_header_t.
// malloc() ищет первый достаточно большой свободный блок (first-fit),
// при избытке места разбивает его на два. free() помечает блок
// свободным и сливает его с соседними свободными блоками в списке
// (coalescing).
//
// --- Усиление (в духе hardened_malloc/GrapheneOS) ---
//
// Настоящий ARM MTE здесь невозможен: это аппаратная фича (4-битный тег
// на каждые 16 байт RAM, CPU сам проверяет тег при каждом обращении
// через TBI - игнорирование верхних битов адреса при трансляции). x86
// ничего подобного не имеет: закодировать тег в старших битах указателя,
// как делает ARM, сломало бы КАЖДЫЙ вызов malloc() в kernel.c/tasking.c
// (все они используют результат как обычный 64-битный адрес без "снятия"
// тега, аппаратно это на ARM делает MMU, программно тут - никто).
//
// Поэтому "тег" и "карантин" ниже - software-only аналог, проверяемый
// только malloc()/free() (а не на каждом обращении к памяти), но ловящий
// тот же класс багов (use-after-free, double-free, переполнение):
//
// 1. magic в заголовке: free() отказывается работать с указателем,
//    чей заголовок не похож на "выделенный нами блок" (чужой/мусорный
//    указатель), и явно детектирует double-free, вместо того чтобы
//    тихо повторно влинковать уже свободный блок в список.
// 2. tag (полные 64 бита, "цвет" блока, по аналогии с MTE, но шире - см.
//    тот же приём в src/user/rv64/malloc.h) - случайное число, назначаемое
//    блоку при ВЫХОДЕ из карантина обратно в free-list. Канарейка
//    вычисляется из тега (tagged_canary) - поэтому совпадает только пока
//    тег в заголовке не менялся. Изначально здесь было 4 бита (как
//    настоящий ARM MTE); в long mode x86-64 родная ширина регистра/ALU -
//    64 бита, так же как на RV64, так что расширение до полного machine
//    word ничего не стоит (одно сравнение вместо одного сравнения) и
//    делает коллизию поколений при use-after-free 1-в-2^64 вместо 1-в-16.
// 3. canary сразу после пользовательских данных, завязанная на tag:
//    linear-overflow, который раньше тихо переписывал заголовок
//    СЛЕДУЮЩЕГО блока, теперь детектируется в free() ДО того, как
//    испорченный заголовок успеет что-то сломать.
// 3b. left redzone (RZONE_SIZE байт фиксированного паттерна МЕЖДУ
//    заголовком и пользовательскими данными, по образцу src/user/rv64/
//    malloc.h) - underflow (запись ДО начала блока, например отрицательный
//    индекс) раньше тихо портил block_header_t ЭТОГО ЖЕ блока (size/next/
//    magic/tag), теперь тоже детектируется в free(). Канарейка (п.3) этот
//    случай не ловит - она стоит только с ПРАВОЙ стороны.
// 4. Карантин: free() не отдаёт блок обратно в free-list немедленно, а
//    кладёт его в маленькое кольцо (QUARANTINE_CAPACITY последних
//    free()). malloc() не видит блок, пока он в карантине - случайный
//    use-after-free, прилетевший вскоре после free(), с большой
//    вероятностью попадёт в блок, который ещё НИКТО не успел
//    переиспользовать (и magic/tag там ещё старые - см. ниже). Только
//    когда кольцо переполняется, самый старый блок "отравляется"
//    (фиксированным паттерном) и наконец возвращается в free-list.
//
//    Отравление откладывается до момента вытеснения из карантина (а не
//    делается сразу в free()) НЕ просто для попугать UAF дольше - это
//    структурно необходимо: tasking.c::schedule() освобождает кадровый
//    стек ЗАДАЧИ, ВЫПОЛНЯЮЩЕЙСЯ ПРЯМО СЕЙЧАС НА ЭТОМ ЖЕ СТЕКЕ (ESP0/CR3
//    переключаются только после free()). Запись в блок непосредственно
//    в free() означала бы запись под собственным текущим кадром вызовов
//    (адреса возврата свежей kstack) - именно так это и обнаружилось:
//    triple fault на каждом выходе изолированной run-задачи. Отравление
//    при вытеснении (на стороне СЛЕДУЮЩЕГО free(), не текущего) этой
//    проблемы не имеет: блок, который вытесняется, к этому моменту уже
//    не может быть чьим-то активным стеком (в карантине, free()=0, его
//    физически не мог получить malloc() для новой задачи).
//
// Это не криптографическая защита (тег - не секрет, если атакующий уже
// читает память ядра) и не ловит все классы багов (например, произвольное
// чтение до/после блока, не задевающее redzone/canary), но даёт громкий,
// детерминированный отказ вместо тихой порчи кучи, и не даёт типичному UAF
// "сразу" попасть в свежую запись.

#include "paging.h"   // g_kheap_base / KHEAP_SIZE

extern void print_string(char* str);
extern volatile unsigned long timer_ticks; // kernel.c, IRQ0 (100 Гц) - энтропия для тега

// Only needed to print the (now randomized) heap base at init_heap() -
// same approach as kcfi.c's own local hex helper.
static void print_hex32(unsigned int val) {
    const char hx[16] = "0123456789ABCDEF";
    char buf[9]; buf[8] = 0;
    for (int i = 7; i >= 0; i--) { buf[i] = hx[val & 0xF]; val >>= 4; }
    print_string(buf);
}

// g_kheap_base - НЕ константа времени компиляции (KASLR-lite, см. paging.h) -
// выбирается случайно в init_paging(), которая должна отработать раньше
// init_heap(). Эти макросы поэтому нельзя использовать в статических
// инициализаторах (heap_head ниже стартует с 0, а не с HEAP_START).
#define HEAP_START (g_kheap_base)
#define HEAP_SIZE  KHEAP_SIZE
#define HEAP_END   (HEAP_START + HEAP_SIZE)

// Видны только тут, размер блока подбирался не под "осмысленное" слово -
// случайный указатель/мусор с шансом 1/2^32 совпадёт, но это не криптография,
// а защита от типичных багов (double-free, переполнение), не от атакующего,
// который уже читает память ядра.
#define HEAP_MAGIC_ALLOC      0x4C41434Bu // "KCAL" - блок выделен, под пользователем
#define HEAP_MAGIC_QUARANTINE 0x51524E54u // "QRNT" - свободен, но ещё не виден malloc()
#define HEAP_MAGIC_FREE       0x46524545u // "EERF" - свободен и виден malloc()

#define CANARY_SIZE  8
#define CANARY_BASE  0xACACACACACACACACull

// Левый redzone: фиксированный паттерн между заголовком и данными -
// underflow затирает его раньше, чем добирается до самого заголовка.
#define RZONE_SIZE  8
#define RZONE_BYTE  0xBEu

// Полный 64-битный "цвет" блока (по аналогии с тегами ARM MTE, но шире и
// без аппаратной проверки - см. комментарий в начале файла). Канарейка
// строится из него, так что подмена тега в заголовке (или просто другой
// блок того же адреса, но другого "поколения") меняет ожидаемое значение
// канарейки.

// Карантин: последние QUARANTINE_CAPACITY освобождённых блоков, ещё не
// видимые malloc() (magic == HEAP_MAGIC_QUARANTINE, free == 0). Кольцевой
// буфер: quarantine_pos - индекс СЛЕДУЮЩЕГО слота для записи; если
// заполнен, в нём как раз самый старый блок - его и вытесняем.
#define QUARANTINE_CAPACITY 8

typedef struct block_header {
    unsigned int size;          // размер полезной области (без заголовка), байт
    int free;                   // 1 - блок свободен И виден malloc() (не в карантине)
    struct block_header* next;  // следующий блок в списке (или NULL)
    unsigned int magic;         // HEAP_MAGIC_* - см. комментарий выше
    unsigned long long tag;     // 64-битный "цвет" текущего поколения блока
} block_header_t;

#define HEADER_SIZE (sizeof(block_header_t))

// Минимальный полезный размер блока при разбиении: если остаток после
// выделения меньше HEADER_SIZE + MIN_BLOCK_SIZE, блок не разбивается -
// избегаем "блоков-крошек", в которые ничего не влезет.
#define MIN_BLOCK_SIZE 16

// Выравнивание размера запроса malloc() до кратного 8 байт - CANARY_SIZE
// теперь тоже 8 (полный 64-битный тег), выравнивание держит канарейку на
// естественной границе слова вместо произвольного 4-байтного смещения.
#define ALIGN8(x) (((x) + 7) & ~7)

// 0, not HEAP_START: HEAP_START now depends on the runtime g_kheap_base
// (KASLR-lite), which C won't accept in a static initializer anyway -
// init_heap() sets the real value before anything can call kmalloc/kfree.
static block_header_t* heap_head = 0;

static block_header_t* quarantine[QUARANTINE_CAPACITY];
static unsigned int quarantine_count = 0;
static unsigned int quarantine_pos = 0;

static unsigned long long tag_prng_state = 0;

// xorshift64 - не криптографический ГПСЧ, нужен только разброс тегов
// между поколениями одного и того же адреса блока, не сопротивление
// атакующему, который уже читает память ядра. Канонические сдвиги для
// 64-битного слова (13, 7, 17) - не та тройка (13, 17, 5), что была тут
// для 32-битной версии: она подобрана под 32 бита и на 64 давала бы
// более слабую/короткую последовательность.
static unsigned long long next_tag() {
    if (tag_prng_state == 0) {
        tag_prng_state = (unsigned long long)timer_ticks ^ 0x9E3779B97F4A7C15ull;
        if (tag_prng_state == 0) tag_prng_state = 0x9E3779B97F4A7C15ull;
    }
    tag_prng_state ^= (unsigned long long)timer_ticks;
    tag_prng_state ^= tag_prng_state << 13;
    tag_prng_state ^= tag_prng_state >> 7;
    tag_prng_state ^= tag_prng_state << 17;
    return tag_prng_state ? tag_prng_state : 1ull;
}

// Канарейка зависит от tag блока напрямую (XOR с базовым паттерном) -
// больше не нужно "размножать" по байтам, как для 4-битного тега: тег уже
// занимает все 64 бита. Старый указатель, переживший free() и повторную
// выдачу того же адреса с НОВЫМ тегом, при попытке write затирает память
// по старому смещению, но не предъявляет верную канарейку нового
// поколения при следующем легитимном free() этого блока.
static unsigned long long tagged_canary(unsigned long long tag) {
    return CANARY_BASE ^ tag;
}

static void heap_corrupted(char* why) {
    print_string("\n\033[31m*** HEAP CORRUPTION: "); // красный - фатально
    print_string(why);
    print_string(" ***\nSystem halted.\033[0m\n");
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
    __asm__ volatile("pushfq\n\tpopq %0\n\tcli" : "=r"(flags) :: "memory")
#define LEAVE_CRITICAL(flags) \
    __asm__ volatile("pushq %0\n\tpopfq" :: "r"(flags) : "memory", "cc")

void init_heap() {
    heap_head = (block_header_t*)HEAP_START;
    heap_head->size = (unsigned int)(HEAP_SIZE - HEADER_SIZE);
    heap_head->free = 1;
    heap_head->next = 0;
    heap_head->magic = HEAP_MAGIC_FREE;
    heap_head->tag = 0;

    quarantine_count = 0;
    quarantine_pos = 0;

    print_string("[heap] kmalloc arena: 32MB at 0x");
    print_hex32((unsigned int)HEAP_START);   // was a hardcoded "0x400000" - wrong since KASLR-lite
    print_string("\n");
}

void* malloc(unsigned int size) {
    if (size == 0) return 0;
    size = ALIGN8(size);

    // Сколько физически нужно отрезать от свободного блока: левый
    // redzone + данные + канарейка сразу после них (см. комментарий в
    // начале файла).
    unsigned int reserved = RZONE_SIZE + size + CANARY_SIZE;

    unsigned long long flags;
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
                new_block->tag = 0;
                new_block->next = current->next;

                current->size = reserved;
                current->next = new_block;
            }

            // current->size теперь либо `reserved` (блок разбили), либо
            // исходный (больший) размер свободного блока (не разбили -
            // "хвост" по-прежнему часть этого же блока, как и в исходном
            // алгоритме). Канарейка - ВСЕГДА у фактической границы блока
            // (current->size), а не у запрошенного size: иначе free(),
            // зная только current->size, проверял(/занулял) бы неверную
            // длину в неразбитом случае и затирал заголовок СЛЕДУЮЩЕГО
            // блока вместо своей же "слабины".
            current->free = 0;
            current->magic = HEAP_MAGIC_ALLOC;
            current->tag = next_tag();

            unsigned char* lzone = (unsigned char*)current + HEADER_SIZE;
            for (unsigned int i = 0; i < RZONE_SIZE; i++) lzone[i] = RZONE_BYTE;

            result = (void*)(lzone + RZONE_SIZE);
            *(unsigned long long*)((unsigned char*)result + (current->size - RZONE_SIZE - CANARY_SIZE)) =
                tagged_canary(current->tag);
            break;
        }

        current = current->next;
    }

    LEAVE_CRITICAL(flags);
    return result;
}

// Возвращает block в обычный free-list: слияние с соседями + отравление
// данных. Вызывается ТОЛЬКО при вытеснении из карантина (см. quarantine_push) -
// никогда напрямую из free() на свежеосвобождённом блоке (см. комментарий
// в начале файла про активный стек задачи).
static void release_from_quarantine(block_header_t* block) {
    unsigned int user_size = block->size - RZONE_SIZE - CANARY_SIZE;
    unsigned char* data = (unsigned char*)block + HEADER_SIZE + RZONE_SIZE;
    for (unsigned int i = 0; i < user_size; i++) {
        data[i] = 0xDD; // "мёртвые" данные - явный, узнаваемый паттерн, не 0
    }

    block->free = 1;
    block->magic = HEAP_MAGIC_FREE;
    block->tag = 0;

    if (block->next && block->next->free) {
        block->size += HEADER_SIZE + block->next->size;
        block->next = block->next->next;
    }

    block_header_t* current = heap_head;
    while (current && current->next != block) {
        current = current->next;
    }
    if (current && current->free) {
        current->size += HEADER_SIZE + block->size;
        current->next = block->next;
    }
}

static void quarantine_push(block_header_t* block) {
    if (quarantine_count == QUARANTINE_CAPACITY) {
        // Кольцо заполнено - quarantine_pos указывает на самый старый
        // элемент (следующий слот для перезаписи в кольцевом FIFO).
        release_from_quarantine(quarantine[quarantine_pos]);
    } else {
        quarantine_count++;
    }
    quarantine[quarantine_pos] = block;
    quarantine_pos = (quarantine_pos + 1) % QUARANTINE_CAPACITY;
}

void free(void* ptr) {
    if (!ptr) return;

    unsigned long long flags;
    ENTER_CRITICAL(flags);

    block_header_t* block = (block_header_t*)((unsigned char*)ptr - RZONE_SIZE - HEADER_SIZE);

    // Чужой/мусорный указатель или double-free (в т.ч. на блок, который
    // уже в карантине) - не трогаем список (тихая порча связного списка
    // кучи отсюда обычно расползается намного дальше места первоначальной
    // ошибки и её куда сложнее диагностировать).
    if (block->magic == HEAP_MAGIC_FREE || block->magic == HEAP_MAGIC_QUARANTINE) {
        heap_corrupted("double free()");
    }
    if (block->magic != HEAP_MAGIC_ALLOC) {
        heap_corrupted("free() on invalid/foreign pointer");
    }

    unsigned char* lzone = (unsigned char*)block + HEADER_SIZE;
    for (unsigned int i = 0; i < RZONE_SIZE; i++) {
        if (lzone[i] != RZONE_BYTE) heap_corrupted("buffer underflow (left redzone)");
    }

    unsigned int user_size = block->size - RZONE_SIZE - CANARY_SIZE;
    unsigned long long canary = *(unsigned long long*)((unsigned char*)ptr + user_size);
    if (canary != tagged_canary(block->tag)) {
        heap_corrupted("buffer overflow (canary)");
    }

    // В карантин, а не сразу в free-list - см. комментарий в начале файла.
    // НЕ трогаем данные блока здесь (только что прочитанная канарейка -
    // последнее чтение, дальше до release_from_quarantine ничего не пишем).
    block->magic = HEAP_MAGIC_QUARANTINE;
    quarantine_push(block);

    LEAVE_CRITICAL(flags);
}
