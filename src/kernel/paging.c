// =================================================================
//  Paging: 4-level (PML4) + W^X (Write XOR Execute)
// =================================================================
//
// boot.asm устанавливает временные 2МБ huge pages (PML4→PDPT→PD).
// init_paging() заменяет PD[0] (huge page) на PT0 (4КБ-страницы),
// настраивает NX/SMEP/SMAP и включает WP в CR0.
//
// Структура (после init_paging):
//   CR3 → PML4 (0x9C000) → PDPT (0x9D000) → PD (0x9E000)
//   PD[0] → PT0 (0x9F000): 4КБ-страницы VA 0..2МБ
//   PD[1]/[2] = 2МБ huge pages: VA 2..6МБ (ядро-only)
//   PD[g_kheap_pd_index..+KHEAP_PAGES-1] = 2МБ huge pages: куча ядра
//   (KASLR, индекс случайный каждую загрузку, см. g_kheap_base comment
//   ниже) - тот же PDPT[0]/PML4[0] уже покрывают этот диапазон.
//   PD[g_pool_pd_index] = 2МБ huge page: пул приватных таблиц
//   изолированных задач (тоже KASLR, отдельный диапазон, не пересекается
//   с диапазоном кандидатов кучи по построению)
//
// W^X: бит 63 PTE = XD (Execute-Disable) при EFER.NXE=1.

#include "paging.h"
#include "tasking.h"

#define PAE_P    (1ULL)
#define PAE_RW   (1ULL << 1)
#define PAE_USER (1ULL << 2)
#define PAE_PS   (1ULL << 7)   // Page Size (1 = 2МБ/1ГБ huge page)
#define PAE_XD   (1ULL << 63)  // Execute-Disable (NX)

#define PAGE_SIZE 0x1000u

typedef unsigned long long pae_t;

extern void print_string(char* str);
extern char _text_end[];

static int g_nx   = 0;
static int g_smep = 0;
static int g_smap = 0;

unsigned long long g_kheap_base;     // set once, randomly, below - see paging.h
static unsigned int g_kheap_pd_index;
unsigned long long g_pool_base;      // set once, randomly, below - see paging.h
static unsigned int g_pool_pd_index;

// RDRAND (CPUID.1:ECX[30]), если проц поддерживает - иначе RDTSC. Раньше
// сид был ТОЛЬКО RDTSC (предсказуемее для соседней VM/атакующего с точным
// таймингом) - RDRAND, где есть, даёт настоящую аппаратную энтропию.
// RDTSC-фоллбэк оставлен по той же причине, что и раньше: init_paging()
// исполняется до init_idt(), тикового счётчика (timer_ticks) ещё нет.
static unsigned long long early_random64(void) {
    unsigned int max_basic = 0, ecx1 = 0;
    __asm__ volatile("cpuid" : "=a"(max_basic) : "a"(0u) : "ebx", "ecx", "edx");
    if (max_basic >= 1u) {
        unsigned int eax1, ebx1, edx1;
        __asm__ volatile("cpuid" : "=a"(eax1), "=b"(ebx1), "=c"(ecx1), "=d"(edx1) : "a"(1u));
    }
    if ((ecx1 >> 30) & 1u) {
        unsigned long long val = 0;
        unsigned char ok = 0;
        for (int tries = 0; tries < 10 && !ok; tries++) {
            __asm__ volatile("rdrand %0\n\tsetc %1" : "=r"(val), "=qm"(ok));
        }
        if (ok) return val;
    }
    unsigned int lo, hi;
    __asm__ volatile("rdtsc" : "=a"(lo), "=d"(hi));
    return ((unsigned long long)hi << 32) | lo;
}

// KASLR: какой PD-слот занимает куча ядра (KHEAP_PAGES=16 huge pages
// подряд).
//
// ВАЖНО (реальный вывод из отладки этой самой функции): куча ОСТАЁТСЯ
// identity-mapped (VA==PA) - разводить их было соблазнительно ради куда
// большей энтропии (адрес куда угодно в 64-битном пространстве, не
// только в первых N МБ реальной RAM), но за одну сессию отладки нашёлся
// реальный double fault при переключении задач (schedule() падает на
// чтении current_task->rsp - сам current_task живёт в этой же куче),
// причину которого не удалось надёжно локализовать в разумное время.
// Раз identity-mapping требует VA==PA, реальный потолок энтропии здесь
// - это просто "сколько 2МБ-выровненных стартов помещается в РЕАЛЬНОЙ
// физической RAM" - гнаться за "настоящим 64-битным" адресом означало
// бы либо разводить VA/PA (см. риск выше), либо расширять RAM за
// пределы прежнего умолчания. Выбрали второе - подняли QEMU RAM 128МБ
// -> 512МБ (run.bat/qemu_test_helpers.py/ansi_test.py/interactive_test.py
// - ДЕРЖАТЬ В СИНХРОНЕ с диапазонами ниже: индекс PD-слота, не
// подкреплённый реальной физической страницей, читает/пишет в никуда)
// и расширили диапазоны кандидатов пропорционально - тот же безопасный
// identity-map код, просто больше физической памяти для него.
//
// РЕАЛЬНЫЙ БАГ, найденный и исправленный при этом расширении (жил в
// коде и ДО расширения RAM, не связан с ним впрямую): старый диапазон
// [3,48) описывал только СТАРТ кучи, не её след - куча 16 страниц
// шириной, так что старт из верхней трети диапазона (33..47) реально
// оканчивался В [48,63), т.е. ВНУТРИ заявленной "непересекающейся" зоны
// пула [48,64)! Комментарий утверждал "без пересечения", но это было
// верно только для start<=32 - при start в [33,47] (треть кандидатов)
// куча и пул могли физически naложиться на один и тот же 2МБ фрейм,
// если пул ТОЖЕ случайно попадал в перекрытие (грубая оценка - ~1/6
// шанс коллизии на загрузку, не редкий крайний случай). Тихая порча
// памяти кучи или таблиц пула, которую было бы крайне трудно
// диагностировать. Исправлено ниже: диапазон СТАРТА кучи теперь сам
// зарезервирован так, чтобы КУЧА ЦЕЛИКОМ (start+KHEAP_PAGES) никогда не
// заходила в зону пула, а не просто "старт не в зоне пула".
//
// Зоны для RAM=512МБ (256 слотов по 2МБ, индексы 0..255):
//   [0,3)     - фиксировано (PT0 identity + 2 keрнел-only huge pages)
//   [3,223)   - зона кучи (220 слотов) - старт кучи ограничен так, чтобы
//               start+KHEAP_PAGES <= 223 (край зоны), т.е. start в
//               [3,207] - 205 реальных кандидатов старта.
//   [223,255) - зона пула (32 слота), пул - одна страница, старт в
//               [223,254] - 32 кандидата, гарантированно не пересекается
//               с кучей по построению (обе зоны disjoint).
//   [255,256) - небольшой запас у самого верха RAM, не используется.
#define KHEAP_ZONE_FLOOR   3u
#define KHEAP_ZONE_CEILING 223u   // куча целиком должна уместиться до этого индекса
#define KPOOL_ZONE_FLOOR   223u
#define KPOOL_ZONE_CEILING 255u
static unsigned int kheap_pick_pd_index(void) {
    unsigned int span = KHEAP_ZONE_CEILING - KHEAP_ZONE_FLOOR - KHEAP_PAGES + 1u; // 205
    return KHEAP_ZONE_FLOOR + (unsigned int)(early_random64() % (unsigned long long)span);
}

// Пул изолированных задач - одна страница, весь диапазон [223,255) можно
// использовать как кандидатов старта (disjoint от кучи по построению).
static unsigned int kpool_pick_pd_index(void) {
    unsigned int span = KPOOL_ZONE_CEILING - KPOOL_ZONE_FLOOR; // 32
    return KPOOL_ZONE_FLOOR + (unsigned int)(early_random64() % (unsigned long long)span);
}

void init_paging() {
    pae_t* pml4 = GLOBAL_PML4;
    pae_t* pdpt = GLOBAL_PDPT;
    pae_t* pd   = GLOBAL_PD;
    pae_t* pt0  = GLOBAL_PT0;

    // Проверяем поддержку NX через CPUID.80000001H:EDX[20].
    unsigned int max_ext = 0, edx_ext = 0;
    __asm__ volatile("cpuid" : "=a"(max_ext) : "a"(0x80000000u) : "ebx", "ecx", "edx");
    if (max_ext >= 0x80000001u)
        __asm__ volatile("cpuid" : "=d"(edx_ext) : "a"(0x80000001u) : "ebx", "ecx");
    g_nx = (edx_ext >> 20) & 1;

    // Проверяем поддержку SMEP (CR4[20]) и SMAP (CR4[21]) через CPUID.07H:EBX.
    unsigned int max_basic = 0, ebx7 = 0;
    __asm__ volatile("cpuid" : "=a"(max_basic) : "a"(0u) : "ebx", "ecx", "edx");
    if (max_basic >= 7u) {
        unsigned int eax7, ecx7, edx7;
        __asm__ volatile("cpuid"
            : "=a"(eax7), "=b"(ebx7), "=c"(ecx7), "=d"(edx7)
            : "a"(7u), "c"(0u));
        g_smep = (ebx7 >> 7) & 1;
        g_smap = (ebx7 >> 20) & 1;
    }

    unsigned int text_end = (unsigned int)(unsigned long long)_text_end & ~(PAGE_SIZE - 1u);

    // PT0: 4КБ-страницы для VA 0x000000-0x1FFFFF (512 страниц).
    for (unsigned int i = 0; i < 512; i++) {
        unsigned int addr = i * PAGE_SIZE;
        pae_t flags = PAE_P;

        int in_user_window = (addr >= USER_WINDOW_BASE &&
                              addr <  USER_WINDOW_BASE + USER_WINDOW_SIZE);
        if (in_user_window) {
            flags |= PAE_USER | PAE_RW;
        } else {
            int is_text = (addr >= 0x1000 && addr + PAGE_SIZE <= text_end);
            if (!is_text) flags |= PAE_RW;
        }

        pt0[i] = (pae_t)addr | flags;
    }

    // Guard page: стек ядра растёт вниз от 0x90000; overflow → #PF → halt.
    pt0[0x8C] = 0;

    // PD[0] → PT0 (0-2МБ, USER=1 нужен для ring3 walk к USER_WINDOW).
    // Заменяет boot-huge-page тонкой 4КБ-таблицей.
    pd[0] = (pae_t)pt0 | PAE_P | PAE_RW | PAE_USER;
    // PD[1] = 2МБ huge page для 2-4МБ (ядро-only, без USER).
    pae_t pd1_flags = PAE_P | PAE_RW | PAE_PS;
    if (g_nx) pd1_flags |= PAE_XD;
    pd[1] = 0x200000ULL | pd1_flags;
    // PD[2] = 2МБ huge page для 4-6МБ (те же флаги, ядро-only) - FAT12
    // выросла до 2МБ (см. FAT12_BASE/FAT12_TOTAL_SECTORS в fat12.c) и
    // теперь занимает [0x300000, 0x500000) - пересекает границу старых
    // первых 4МБ, так что этот диапазон тоже должен быть фиксированным,
    // а не кандидатом кучи (см. новый floor=3 в kheap_pick_pd_index).
    pd[2] = 0x400000ULL | pd1_flags;

    // PD[g_kheap_pd_index..+KHEAP_PAGES-1]: куча ядра (см. g_kheap_base
    // comment above) - те же флаги, что и PD[1]/[2] (ядро-only, NX):
    // чистые данные, никогда не код. Zero the rest of the PD FIRST (from
    // index 3 - PD[2] уже занята выше): the heap's start index is
    // random, not always right after the fixed region, so a fixed
    // "zero everything past the fixed region" tail loop no longer covers
    // entries between PD[3] and wherever the heap actually landed.
    for (unsigned int i = 3; i < 512; i++) pd[i] = 0;

    g_kheap_pd_index = kheap_pick_pd_index();
    g_kheap_base = (unsigned long long)g_kheap_pd_index * 0x200000ULL;

    pae_t kheap_flags = PAE_P | PAE_RW | PAE_PS;
    if (g_nx) kheap_flags |= PAE_XD;
    for (unsigned int i = 0; i < KHEAP_PAGES; i++)
        pd[g_kheap_pd_index + i] = (pae_t)(g_kheap_base + i * 0x200000ULL) | kheap_flags;

    // PD[g_pool_pd_index]: isolated-task PML4/PDPT/PD/PT pool (see
    // g_pool_base comment in paging.h) - one huge page, same kernel-only
    // NX flags as the heap (pure data, never code).
    g_pool_pd_index = kpool_pick_pd_index();
    g_pool_base = (unsigned long long)g_pool_pd_index * 0x200000ULL;
    pd[g_pool_pd_index] = (pae_t)g_pool_base | kheap_flags;

    // PDPT и PML4 уже настроены boot.asm; проверяем/обновляем флаги.
    // boot ставил US=1 на оба, что нам и нужно.
    pdpt[0] = (pae_t)pd | PAE_P | PAE_RW | PAE_USER;
    for (unsigned int i = 1; i < 512; i++) pdpt[i] = 0;

    pml4[0] = (pae_t)pdpt | PAE_P | PAE_RW | PAE_USER;
    for (unsigned int i = 1; i < 512; i++) pml4[i] = 0;

    // CR4: добавляем SMEP (бит 20) и SMAP (бит 21). PAE (бит 5) уже set boot.
    unsigned long long cr4_add = 0;
    if (g_smep) cr4_add |= 0x100000ULL;
    if (g_smap) cr4_add |= 0x200000ULL;
    if (cr4_add) {
        __asm__ volatile(
            "mov %%cr4, %%rax\n"
            "or %0, %%rax\n"
            "mov %%rax, %%cr4\n"
            :: "r"(cr4_add) : "rax"
        );
    }
    if (g_smap) __asm__ volatile(".byte 0x0F,0x01,0xCA"); // clac: SMAP активна

    // EFER.NXE (бит 11) — если поддерживается.
    if (g_nx) {
        __asm__ volatile(
            "mov $0xC0000080, %%ecx\n"
            "rdmsr\n"
            "or $0x800, %%eax\n"
            "wrmsr\n"
            ::: "eax", "ecx", "edx"
        );
    }

    // Перезагружаем CR3 (TLB flush) и устанавливаем CR0.WP (бит 16).
    // CR0.PG уже = 1 (boot.asm). WP запрещает ring0 писать в read-only страницы.
    __asm__ volatile(
        "mov %0, %%cr3\n"
        "mov %%cr0, %%rax\n"
        "or $0x10000, %%rax\n"
        "mov %%rax, %%cr0\n"
        :: "r"((unsigned long long)pml4) : "rax"
    );

    print_string("[paging] NX=");
    print_string(g_nx   ? "on" : "off");
    print_string(" SMEP=");
    print_string(g_smep ? "on" : "off");
    print_string(" SMAP=");
    print_string(g_smap ? "on" : "off");
    print_string("\n");
    print_string("[paging] kheap: 32MB mapped (2MB huge pages, NX)\n");
}

void smap_allow(void) {
    if (g_smap) __asm__ volatile(".byte 0x0F,0x01,0xCB" ::: "memory"); // stac
}

void smap_deny(void) {
    if (g_smap) __asm__ volatile(".byte 0x0F,0x01,0xCA" ::: "memory"); // clac
}


unsigned long long paging_create_user_directory(int user_slot_index,
                                                 unsigned int phys_slot_base,
                                                 unsigned int wx_delta,
                                                 unsigned int wx_data_off) {
    // Пул: каждый слот (0..3) получает по одной 4КБ-странице на уровень,
    // внутри случайной (KASLR-lite, см. g_pool_base в paging.h) 2МБ huge
    // page вместо старых фиксированных адресов.
    unsigned long long slot_off = (unsigned long long)user_slot_index * PAGE_SIZE;
    pae_t* dst_pml4 = (pae_t*)(g_pool_base + POOL_PML4_OFF + slot_off);
    pae_t* dst_pdpt = (pae_t*)(g_pool_base + POOL_PDPT_OFF + slot_off);
    pae_t* dst_pd   = (pae_t*)(g_pool_base + POOL_PD_OFF   + slot_off);
    pae_t* dst_pt   = (pae_t*)(g_pool_base + POOL_PT_OFF   + slot_off);

    // Копируем GLOBAL_PT0 в dst_pt, убирая USER (ring3 не видит ядро).
    pae_t* src_pt = GLOBAL_PT0;
    for (unsigned int i = 0; i < 512; i++)
        dst_pt[i] = src_pt[i] & ~PAE_USER;

    // Переотображаем USER_WINDOW на физический слот задачи.
    unsigned int first_page = USER_WINDOW_BASE / PAGE_SIZE; // = 0x100
    unsigned int data_start = wx_delta + wx_data_off;
    int has_boundary = (wx_data_off > 0);

    for (unsigned int i = 0; i < USER_WINDOW_PAGES; i++) {
        unsigned int phys = phys_slot_base + i * PAGE_SIZE;
        pae_t entry = (pae_t)phys | PAE_P | PAE_USER;

        int is_spin = (i == USER_WINDOW_PAGES - 1u);

        if (!has_boundary || is_spin) {
            entry |= PAE_RW;
        } else {
            // ВАЖНО: data_start ДОЛЖЕН быть выровнен на страницу к этому
            // моменту (гарантируется линковкой user.ld - явный ALIGN(4096)
            // перед .data/.bss, см. коммент там) - если граница попадёт
            // НА СЕРЕДИНУ страницы, эта страница вынужденно получит ОДНО
            // из двух: либо R+X (код) - тогда легитимные ЗАПИСЫВАЕМЫЕ
            // данные этой же страницы (например tcp_rx) сломаются, либо
            // RW+NX (данные) - тогда легитимный КОД в начале этой же
            // страницы сломается (реальный краш, пойманный вживую дважды
            // с обоими вариантами - см. память project_fin_rto_backoff).
            // PAE не умеет разные права внутри одной физической страницы,
            // так что единственное настоящее решение - гарантировать
            // выравнивание на этапе линковки, а не выбирать здесь.
            unsigned int byte_end = i * PAGE_SIZE + PAGE_SIZE - 1u;
            if (byte_end < data_start) {
                // Код: R+X (без PAE_RW)
            } else {
                // Данные: RW + NX
                entry |= PAE_RW;
                if (g_nx) entry |= PAE_XD;
            }
        }

        dst_pt[first_page + i] = entry;
    }

    // dst_pd: [0] → dst_pt (0-2МБ с USER), [1]/[2] = 2МБ huge pages
    // ядра-only (2-6МБ, покрывает выросшую до 2МБ FAT12 - см. init_paging),
    // [g_kheap_pd_index..+KHEAP_PAGES-1] = куча ядра (те же huge pages,
    // что в GLOBAL_PD - копируем ПО ЗНАЧЕНИЮ из GLOBAL_PD на текущем
    // случайном индексе, а не пересчитываем адрес заново, так что этот
    // код не должен ничего знать про то, КАК был выбран индекс).
    // Без этого: как только CR3 переключается на приватные таблицы этой
    // задачи, ЛЮБОЙ код ядра (обработчики прерываний, syscall'ы), который
    // исполняется, пока эта задача активна, и трогает kmalloc/kfree -
    // получает #PF "not present" на первом же обращении к куче за
    // пределами первых 4МБ (её там просто нет - см. комментарий у
    // GLOBAL_PD в paging.h).
    pae_t pd1 = GLOBAL_PD[1] & ~PAE_USER;
    pae_t pd2 = GLOBAL_PD[2] & ~PAE_USER;   // FAT12 теперь занимает и это (см. init_paging)
    for (unsigned int i = 3; i < 512; i++) dst_pd[i] = 0;
    dst_pd[0] = (pae_t)dst_pt | PAE_P | PAE_RW | PAE_USER;
    dst_pd[1] = pd1;
    dst_pd[2] = pd2;
    for (unsigned int i = 0; i < KHEAP_PAGES; i++)
        dst_pd[g_kheap_pd_index + i] = GLOBAL_PD[g_kheap_pd_index + i] & ~PAE_USER;

    // Пул тоже больше не часть первых 2МБ (см. g_pool_base в paging.h) -
    // без этой записи ЛЮБОЙ следующий run() (например, изнутри SH.BIN,
    // которая сама изолированная задача) поймал бы #PF в этой же функции
    // при попытке записать в dst_pml4/pdpt/pd/pt СЛЕДУЮЩЕЙ создаваемой
    // задачи, работая уже под CR3 этой задачи. Самоссылочно (dst_pd сам
    // живёт внутри пула, чью запись мы тут копируем) - это нормально: мы
    // просто пишем в память по текущему (ещё активному, вызывающему) CR3,
    // а не под CR3 задачи, которую только что создаём.
    dst_pd[g_pool_pd_index] = GLOBAL_PD[g_pool_pd_index] & ~PAE_USER;

    // dst_pdpt: [0] → dst_pd.
    dst_pdpt[0] = (pae_t)dst_pd | PAE_P | PAE_RW | PAE_USER;
    for (unsigned int i = 1; i < 512; i++) dst_pdpt[i] = 0;

    // dst_pml4: [0] → dst_pdpt.
    dst_pml4[0] = (pae_t)dst_pdpt | PAE_P | PAE_RW | PAE_USER;
    for (unsigned int i = 1; i < 512; i++) dst_pml4[i] = 0;

    return (unsigned long long)dst_pml4;
}

static void print_hex(unsigned int val) {
    char hex_digits[] = "0123456789ABCDEF";
    char buf[9]; buf[8] = '\0';
    for (int i = 7; i >= 0; i--) { buf[i] = hex_digits[val & 0xF]; val >>= 4; }
    print_string(buf);
}

// Индексы в 64-битном кадре исключения #PF.
// Кадр (от RSP = нижнего адреса):
//   [0..14]  = RAX..R15  (15 GPR из SAVE_REGS в idt.asm)
//   [15]     = Error code (CPU-pushed)
//   [16]     = RIP
//   [17]     = CS
//   [18]     = RFLAGS
//   [19]     = RSP_old
//   [20]     = SS
#define PF_FRAME_ERR 15
#define PF_FRAME_RIP 16
#define PF_FRAME_CS  17

void page_fault_handler_main(unsigned long long faulting_address,
                              unsigned long long* frame) {
    unsigned long long cs = frame[PF_FRAME_CS];

    if ((cs & 3) == 3 && task_current_is_isolated()) {
        unsigned long long err = frame[PF_FRAME_ERR];
        print_string("\n\033[33m*** PAGE FAULT in '");
        print_string(task_current_name());
        print_string("' at 0x");
        print_hex((unsigned int)faulting_address);
        if (err & (1ULL << 4))
            print_string(" [NX execute violation]");
        else if (err & (1ULL << 1))
            print_string(" [W^X write violation]");
        print_string(" - task killed ***\033[0m\n");
        task_set_current_exit_code(-1); // аварийное завершение - как и kill
        task_mark_current_exiting();
        frame[PF_FRAME_RIP] = USER_SPIN_ADDR;
        return;
    }

    unsigned long long rip  = frame[PF_FRAME_RIP];
    unsigned long long err2 = frame[PF_FRAME_ERR];
    int is_kernel_exec_fault = (err2 & (1ULL << 4)) && !(err2 & (1ULL << 2));
    int is_smap_fault = (err2 & 1ULL) && !(err2 & (1ULL << 2)) && !(err2 & (1ULL << 4))
                     && (faulting_address >= USER_WINDOW_BASE)
                     && (faulting_address <  USER_WINDOW_BASE + USER_WINDOW_SIZE);
    if (is_kernel_exec_fault) {
        print_string("\n\033[41;37m[SMEP/NX] kernel exec fault addr=0x");
        print_hex((unsigned int)faulting_address);
        print_string(" rip=0x");
        print_hex((unsigned int)rip);
        print_string("\033[0m\n");
    } else if (is_smap_fault) {
        print_string("\n\033[41;37m[SMAP] kernel data access to user page addr=0x");
        print_hex((unsigned int)faulting_address);
        print_string(" rip=0x");
        print_hex((unsigned int)rip);
        print_string(" (missing stac?)\033[0m\n");
    } else {
        print_string("\n\033[31m*** PAGE FAULT at 0x");
        print_hex((unsigned int)faulting_address);
        print_string(" from RIP=0x");
        print_hex((unsigned int)rip);
        print_string(" cs=0x");
        print_hex((unsigned int)cs);
        print_string(" ***\033[0m\n");
    }
    print_string("System halted.\n");
    while (1) { __asm__("hlt"); }
}
