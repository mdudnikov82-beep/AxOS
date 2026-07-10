// =================================================================
//  Tasking: простой preemptive round-robin планировщик (ring0)
// =================================================================
//
// Каждая задача - функция C, выполняющаяся на собственном стеке
// (TASK_STACK_SIZE байт, из malloc). Переключение происходит в
// обработчике таймера (IRQ0, idt.asm): после pusha CPU+ассемблер
// оставляют на стеке задачи кадр [EFLAGS][CS][EIP] + 8 регистров
// (в порядке pusha: EAX,ECX,EDX,EBX,ESP*,EBP,ESI,EDI, ESP* не
// используется popa). schedule() меняет esp текущей задачи на esp
// следующей - после этого общий popa+iret в idt.asm резюмирует её.
//
// Новая задача получает такой же фабрикованный кадр на своём
// стеке - для неё popa+iret действует как "запуск" с адреса entry.

#include "heap.h"
#include "tss.h"
#include "paging.h"

#define TASK_STACK_SIZE 4096
// 4096, а не меньше: если IRQ (клавиатура/таймер) застаёт ring3-задачу
// "текущей", весь обработчик прерывания (включая, например, fat12_cat()
// с её локальным буфером ~2KB) выполняется на ЭТОМ стеке (ESP0 = он же).
#define KSTACK_SIZE 4096
#define MAX_NAME_LEN 16

// Селекторы из gdt.asm (ring3 = младшие 2 бита селектора = 11b).
// USER_CODE32_SEG = 0x20 (gdt_user_code, L=0 D=1 → 32-бит compat)
// USER_DATA_SEG   = 0x28 (gdt_user_data)
// CODE64_SEG      = 0x18 (gdt_code64, L=1 D=0 → ядро 64-бит)
// DATA_SEG        = 0x10 (gdt_data)
#define CODE64_SEG      0x18
#define DATA_SEG        0x10
#define USER_CODE32_SEG 0x20
#define USER_DATA_SEG   0x28

// Приоритет = сколько ПОСЛЕДОВАТЕЛЬНЫХ таймерных тиков задача держит CPU
// за один заход в кольцо, прежде чем schedule() перейдёт к следующей -
// weighted round-robin, не строгие уровни (низкий приоритет не голодает
// вечно, просто получает управление реже/на более короткое время). Раньше
// это было жёстко "1 тик на задачу всегда"; PRIORITY_DEFAULT=3 - более
// крупная гранулярность по умолчанию, а не полный возврат к "1".
#define PRIORITY_MIN     1
#define PRIORITY_MAX     10
#define PRIORITY_DEFAULT 3

typedef struct task {
    unsigned long long rsp;             // сохранённый RSP (указывает на GPR-кадр)
    unsigned long long kernel_stack_top; // RSP0 этой задачи (для ring3->ring0)
    unsigned long long page_directory;   // CR3 этой задачи (PML4)
    int id;
    char name[MAX_NAME_LEN];
    unsigned long ticks;
    int user_slot_index; // -1 для task0/heartbeat/ring3demo; 0..3 для run-задач (kernel.c)
    int exiting;         // 1 - schedule() уберёт задачу из кольца на следующем тике
    unsigned int mls_level;          // MLS-уровень чувствительности (s0..s15)
    unsigned long long syscall_mask; // seccomp: бит N = syscall N разрешён; 0 = нет фильтра
    int priority;         // 1..10, см. PRIORITY_* выше
    int slice_left;       // сколько тиков ещё осталось в текущем заходе
    int exit_code;        // код выхода - см. task_set_current_exit_code/SYS_EXIT
    int sleeping;          // 1 - задача заблокирована в SYS_SLEEP, снята с ротации
    unsigned long long wake_tick; // timer_ticks, при котором проснуться (валиден только если sleeping)
    int waiting_pipe;      // >= 0 - заблокирована в SYS_FREAD на "PIPE:N", снята с ротации так же, как sleeping
    struct task* next;
} task_t;

// Диапазон MLS-уровня - как s0..s15 в настоящей политике SELinux MLS.
#define MLS_LEVEL_MAX 15

extern void print_string(char* str);
extern void print_uint(unsigned long val);
extern void on_task_exit(int user_slot_index, int exit_code); // kernel.c - освобождает слот run-задачи, сохраняет exit_code
extern int pipe_ready(int pipe_id); // kernel.c - 1 если у pipe'а есть данные или писатель закрылся
extern volatile unsigned long timer_ticks; // kernel.c, IRQ0 (100 Гц)

// --- "ASLR-подобный" разброс начального стека изолированных run-задач ---
// Настоящий ASLR (рандомизация базы кода/данных) здесь не сделать без
// position-independent кода: программы линкуются (user.ld) на фиксированный
// 0x100000, абсолютные ссылки в их коде это предполагают (см. README,
// "Изоляция памяти"). Зато можно рандомизировать, ГДЕ внутри окна стартует
// стек - exploit, рассчитанный на точный фиксированный USER_STACK_TOP,
// промахивается. xorshift32, не криптографический ГПСЧ - тут не нужно
// сопротивление атакующему, который уже читает память ядра, только разброс
// "угадываемого по умолчанию" адреса между запусками.
static unsigned int aslr_prng_state = 0;

unsigned int aslr_next_random() {
    if (aslr_prng_state == 0) {
        aslr_prng_state = (unsigned int)timer_ticks ^ 0x9E3779B9u;
        if (aslr_prng_state == 0) aslr_prng_state = 0x9E3779B9u; // xorshift не переживает state==0
    }
    aslr_prng_state ^= (unsigned int)timer_ticks; // свежая энтропия на каждый запуск
    aslr_prng_state ^= aslr_prng_state << 13;
    aslr_prng_state ^= aslr_prng_state >> 17;
    aslr_prng_state ^= aslr_prng_state << 5;
    return aslr_prng_state;
}

// task0 - текущий поток выполнения (kernel_main/shell). Его esp
// записывается лениво, при первом переключении из schedule().
static task_t task0;
static task_t* current_task = 0;
static int next_id = 0;

static void copy_name(char* dst, char* src) {
    int i = 0;
    while (src[i] != '\0' && i < MAX_NAME_LEN - 1) {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

void init_tasking() {
    task0.rsp = 0;
    task0.id = next_id++;
    copy_name(task0.name, "shell");
    task0.ticks = 0;
    task0.page_directory = PAGE_DIRECTORY;
    task0.user_slot_index = -1;
    task0.exiting = 0;
    task0.mls_level = 0;
    task0.syscall_mask = 0;
    task0.priority = PRIORITY_DEFAULT;
    task0.slice_left = PRIORITY_DEFAULT;
    task0.exit_code = 0;
    task0.sleeping = 0;
    task0.wake_tick = 0;
    task0.waiting_pipe = -1;
    task0.next = &task0;

    unsigned char* kstack = (unsigned char*)malloc(KSTACK_SIZE);
    task0.kernel_stack_top = (unsigned long long)(kstack + KSTACK_SIZE);
    tss_set_rsp0(task0.kernel_stack_top);

    current_task = &task0;
}

void task_create(char* name, void (*entry)(void)) {
    unsigned char* stack_mem = (unsigned char*)malloc(TASK_STACK_SIZE);
    if (!stack_mem) return;

    task_t* new_task = (task_t*)malloc(sizeof(task_t));
    if (!new_task) return;

    // Строим 64-битный iretq-кадр на стеке задачи.
    // В 64-бит режиме CPU всегда кладёт SS, RSP, RFLAGS, CS, RIP (5×8=40Б),
    // idt.asm добавляет 15 GPR (15×8=120Б). Итого 20 слотов = 160Б.
    // Порядок push (высокий→низкий адрес): SS, RSP, RFLAGS, CS, RIP,
    //   R15, R14..R8, RBP, RDI, RSI, RDX, RCX, RBX, RAX.
    unsigned long long* sp = (unsigned long long*)(stack_mem + TASK_STACK_SIZE);
    *(--sp) = DATA_SEG;                          // SS
    *(--sp) = (unsigned long long)(stack_mem + TASK_STACK_SIZE); // RSP (execution stack)
    *(--sp) = 0x202ULL;                          // RFLAGS: IF=1
    *(--sp) = CODE64_SEG;                        // CS
    *(--sp) = (unsigned long long)entry;         // RIP
    *(--sp) = 0; // R15
    *(--sp) = 0; // R14
    *(--sp) = 0; // R13
    *(--sp) = 0; // R12
    *(--sp) = 0; // R11
    *(--sp) = 0; // R10
    *(--sp) = 0; // R9
    *(--sp) = 0; // R8
    *(--sp) = 0; // RBP
    *(--sp) = 0; // RDI
    *(--sp) = 0; // RSI
    *(--sp) = 0; // RDX
    *(--sp) = 0; // RCX
    *(--sp) = 0; // RBX
    *(--sp) = 0; // RAX

    new_task->rsp = (unsigned long long)sp;
    new_task->id = next_id++;
    copy_name(new_task->name, name);
    new_task->ticks = 0;
    new_task->page_directory = PAGE_DIRECTORY;
    new_task->user_slot_index = -1;
    new_task->exiting = 0;
    new_task->mls_level = 0;
    new_task->syscall_mask = 0;
    new_task->priority = PRIORITY_DEFAULT;
    new_task->slice_left = PRIORITY_DEFAULT;
    new_task->exit_code = 0;
    new_task->sleeping = 0;
    new_task->wake_tick = 0;
    new_task->waiting_pipe = -1;

    unsigned char* kstack = (unsigned char*)malloc(KSTACK_SIZE);
    new_task->kernel_stack_top = (unsigned long long)(kstack + KSTACK_SIZE);

    new_task->next = current_task->next;
    current_task->next = new_task;
}

void task_create_user(char* name, void (*entry)(void)) {
    unsigned char* user_stack = (unsigned char*)malloc(TASK_STACK_SIZE);
    unsigned char* kstack = (unsigned char*)malloc(KSTACK_SIZE);
    if (!user_stack || !kstack) return;

    task_t* new_task = (task_t*)malloc(sizeof(task_t));
    if (!new_task) return;

    unsigned long long user_stack_top = (unsigned long long)(user_stack + TASK_STACK_SIZE);

    // Кадр ring3→ring0 на kstack: iretq переключит в 32-бит compat.
    unsigned long long* sp = (unsigned long long*)(kstack + KSTACK_SIZE);
    *(--sp) = (unsigned long long)(USER_DATA_SEG | 3);    // SS
    *(--sp) = user_stack_top;                              // RSP (user stack)
    *(--sp) = 0x202ULL;                                   // RFLAGS
    *(--sp) = (unsigned long long)(USER_CODE32_SEG | 3);  // CS (compat)
    *(--sp) = (unsigned long long)entry;                   // RIP
    *(--sp) = 0; // R15
    *(--sp) = 0; *(--sp) = 0; *(--sp) = 0; *(--sp) = 0;
    *(--sp) = 0; *(--sp) = 0; *(--sp) = 0; *(--sp) = 0;
    *(--sp) = 0; // RBP
    *(--sp) = 0; // RDI
    *(--sp) = 0; // RSI
    *(--sp) = 0; // RDX
    *(--sp) = 0; // RCX
    *(--sp) = 0; // RBX
    *(--sp) = 0; // RAX

    new_task->rsp = (unsigned long long)sp;
    new_task->kernel_stack_top = (unsigned long long)(kstack + KSTACK_SIZE);
    new_task->id = next_id++;
    copy_name(new_task->name, name);
    new_task->ticks = 0;
    new_task->page_directory = PAGE_DIRECTORY;
    new_task->user_slot_index = -1;
    new_task->exiting = 0;
    new_task->mls_level = 0;
    new_task->syscall_mask = 0;
    new_task->priority = PRIORITY_DEFAULT;
    new_task->slice_left = PRIORITY_DEFAULT;
    new_task->exit_code = 0;
    new_task->sleeping = 0;
    new_task->wake_tick = 0;
    new_task->waiting_pipe = -1;

    new_task->next = current_task->next;
    current_task->next = new_task;
}

// Виртуальные адреса окна 0x100000-0x108000 - см. USER_WINDOW_* (paging.h)
// и paging_create_user_directory.
#define USER_WINDOW_TOP (USER_WINDOW_BASE + USER_WINDOW_SIZE)

// Начальный ESP задачи - на 16 байт ниже верха окна, а не сам верх:
// стек растёт вниз, и первый push (адрес возврата из "call _user_main"
// в start.asm) попадёт в [ESP-4]. Если ESP = USER_WINDOW_TOP, этот push
// затирает USER_SPIN_ADDR (последние 2 байта окна) ещё до первого page
// fault - kill-путь в paging.c перенаправляет EIP туда, находит там не
// "jmp $", а данные со стека задачи, и снова падает. 16-байтовый зазор
// оставляет USER_SPIN_ADDR выше начального ESP - туда стек никогда не
// дорастёт (растёт вниз).
#define USER_STACK_TOP (USER_WINDOW_TOP - 16)

// Случайный сдвиг ESP вниз от USER_STACK_TOP, кратный 16 байт (сохраняет
// выравнивание стека). USER_STACK_TOP=0x10FFF0, USER_ARGS_VADDR=0x10F800 →
// зазор 0x7F0=2032 байта. При сдвиге до 1024 и типичном росте стека ~512
// минимальный адрес стека ≈ 0x10F9F0 > 0x10F800 → безопасно.
// 1024/16+1 = 65 позиций → ~6 бит энтропии (было 5 позиций → ~2 бита).
#define STACK_ASLR_MAX_SHIFT 1024

void task_create_user_isolated(char* name, unsigned int phys_slot_base, int user_slot_index,
                               int argc, unsigned int argv_vaddr, unsigned int entry_vaddr,
                               unsigned int wx_delta, unsigned int wx_data_off) {
    unsigned char* kstack = (unsigned char*)malloc(KSTACK_SIZE);
    if (!kstack) return;

    task_t* new_task = (task_t*)malloc(sizeof(task_t));
    if (!new_task) return;

    unsigned int stack_shift = (aslr_next_random() % (STACK_ASLR_MAX_SHIFT / 16 + 1)) * 16;
    unsigned int stack_top = USER_STACK_TOP - stack_shift;

    // Кадр ring3→ring0 на kstack: iretq переключит в 32-бит compat mode.
    // RSP будет восстановлен из поля RSP_old кадра → user stack.
    // В 32-бит compat: EBX = argc (нижние 32 бит RBX), ECX = argv_vaddr.
    unsigned long long* sp = (unsigned long long*)(kstack + KSTACK_SIZE);
    *(--sp) = (unsigned long long)(USER_DATA_SEG | 3);    // SS
    *(--sp) = (unsigned long long)stack_top;               // RSP (user stack, 32-бит)
    *(--sp) = 0x202ULL;                                   // RFLAGS: IF=1
    *(--sp) = (unsigned long long)(USER_CODE32_SEG | 3);  // CS (32-бит compat, DPL=3)
    *(--sp) = (unsigned long long)entry_vaddr;             // RIP (32-бит точка входа)
    *(--sp) = 0; // R15
    *(--sp) = 0; // R14
    *(--sp) = 0; // R13
    *(--sp) = 0; // R12
    *(--sp) = 0; // R11
    *(--sp) = 0; // R10
    *(--sp) = 0; // R9
    *(--sp) = 0; // R8
    *(--sp) = 0; // RBP
    *(--sp) = 0; // RDI
    *(--sp) = 0; // RSI
    *(--sp) = 0; // RDX
    *(--sp) = (unsigned long long)argv_vaddr;              // RCX → ECX = argv_vaddr
    *(--sp) = (unsigned long long)(unsigned int)argc;      // RBX → EBX = argc
    *(--sp) = 0; // RAX

    new_task->rsp = (unsigned long long)sp;
    new_task->kernel_stack_top = (unsigned long long)(kstack + KSTACK_SIZE);
    new_task->id = next_id++;
    copy_name(new_task->name, name);
    new_task->ticks = 0;
    new_task->page_directory = paging_create_user_directory(
        user_slot_index, phys_slot_base, wx_delta, wx_data_off);
    new_task->user_slot_index = user_slot_index;
    new_task->exiting = 0;
    new_task->mls_level = 0; // s0 по умолчанию - поднимается самой задачей через SYS_SET_LEVEL
    new_task->syscall_mask = 0; // нет фильтра - задача устанавливает свой через SYS_SECCOMP
    new_task->priority = PRIORITY_DEFAULT;
    new_task->slice_left = PRIORITY_DEFAULT;
    new_task->exit_code = 0;
    new_task->sleeping = 0;
    new_task->wake_tick = 0;
    new_task->waiting_pipe = -1;

    // "jmp $" (EB FE) в последние 2 байта окна задачи - см. USER_SPIN_ADDR
    // (paging.h). Сюда page_fault_handler_main перенаправляет EIP этой
    // задачи при killе: безопасный адрес внутри СВОЕГО окна (PRESENT|RW|
    // USER), задача крутится здесь до реапа в schedule(). Пишем по
    // физическому адресу - ядро сейчас работает на текущем (не приватном)
    // PD, где этот адрес identity-mapped.
    unsigned char* spin = (unsigned char*)(phys_slot_base + USER_WINDOW_SIZE - 2);
    spin[0] = 0xEB; // jmp
    spin[1] = 0xFE; // -2 (на себя)

    new_task->next = current_task->next;
    current_task->next = new_task;
}

unsigned long long schedule(unsigned long long current_rsp) {
    if (!current_task) return current_rsp;

    // Будим просроченных спящих ДО всего остального - иначе задача,
    // проспавшая своё время, никогда сама не попросит проснуться (в
    // отличие от busy-wait цикла, которым это раньше было). Должно
    // выполняться на каждом заходе в schedule(), не только когда сама
    // dying - спящая: иначе спящая задача, оставшаяся единственной не
    // текущей в кольце, не проснётся, пока текущая не отдаст тик по
    // другой причине.
    {
        task_t* t = current_task;
        do {
            if (t->sleeping && timer_ticks >= t->wake_tick) t->sleeping = 0;
            if (t->waiting_pipe >= 0 && pipe_ready(t->waiting_pipe)) t->waiting_pipe = -1;
            t = t->next;
        } while (t != current_task);
    }

    current_task->rsp = current_rsp;
    current_task->ticks++;

    task_t* dying = current_task;

    // Приоритет = тайм-слайс: если задача не выходит, не спит и не ждёт
    // pipe - у неё ещё остались тики в текущем заходе - просто отдаём ей
    // следующий тик без переключения (без смены CR3/TSS.ESP0 - дёшево).
    // Заблокированная задача никогда не сохраняет остаток слайса -
    // task_sleep_current()/task_wait_pipe_current() уже попросили
    // немедленное переключение (см. syscalls.asm), а если задача всё же
    // дошла досюда через обычный таймерный тик - всё равно нельзя
    // оставлять ей CPU.
    if (!dying->exiting && !dying->sleeping && dying->waiting_pipe < 0 && --dying->slice_left > 0) {
        return dying->rsp;
    }

    unsigned long long prev_page_directory = dying->page_directory;

    // immediate_next - ТОПОЛОГИЯ кольца вокруг dying, не выбор "кому
    // отдать CPU". Unlink ниже должен обойти РОВНО dying, ни больше -
    // раньше здесь ошибочно использовалась одна и та же переменная и для
    // топологии, и для выбора следующей (пропускающего спящих), из-за
    // чего pred->next = next при выходе задачи мог по пути "проглотить"
    // и любую спящую задачу, случайно пропущенную тем же поиском -
    // молча вышибало её из кольца (не освобождая память - утечка задачи,
    // она просто переставала быть видна ps/schedule() навсегда). Поймано
    // живым тестом: фоновые sleep.bin+top.bin оба бесследно исчезали.
    task_t* immediate_next = dying->next;

    if (dying->exiting) {
        task_t* pred = immediate_next;
        while (pred->next != dying) pred = pred->next;
        pred->next = immediate_next;

        if (dying->user_slot_index >= 0)
            on_task_exit(dying->user_slot_index, dying->exit_code);

        free((void*)(unsigned long long)(dying->kernel_stack_top - KSTACK_SIZE));
        free(dying);
    }

    // Кому отдать CPU - заблокированные (спящие или ждущие pipe)
    // пропускаются (не участвуют в ротации, пока не разблокируются - см.
    // скан вверху функции). Граница цикла - полный оборот обратно к
    // immediate_next (НЕ dying - тот уже мог быть освобождён выше,
    // сравнивать/бояться разыменовать нельзя), на случай (недостижимого
    // на практике - task0 никогда не блокируется и всегда в кольце)
    // сценария "заблокированы все остальные".
    task_t* next = immediate_next;
    while (next->sleeping || next->waiting_pipe >= 0) {
        task_t* candidate = next->next;
        if (candidate == immediate_next) break; // полный круг, никто не разблокировался
        next = candidate;
    }

    next->slice_left = next->priority; // новой текущей задаче - полный тайм-слайс
    current_task = next;

    tss_set_rsp0(current_task->kernel_stack_top);

    if (current_task->page_directory != prev_page_directory) {
        __asm__ volatile("mov %0, %%cr3" :: "r"(current_task->page_directory));
    }

    return current_task->rsp;
}

// Устанавливает приоритет (1..10, см. PRIORITY_MIN/MAX) задачи по id.
// Не меняет slice_left задачи "на лету", если это уже текущая задача -
// новое значение начнёт применяться с её СЛЕДУЮЩЕГО захода (иначе можно
// было бы удлинить уже начатый слайс задним числом).
void task_set_priority(int pid, int priority) {
    if (!current_task) return;
    if (priority < PRIORITY_MIN) priority = PRIORITY_MIN;
    if (priority > PRIORITY_MAX) priority = PRIORITY_MAX;

    task_t* t = current_task;
    do {
        if (t->id == pid) { t->priority = priority; return; }
        t = t->next;
    } while (t != current_task);
}

// Помечает текущую задачу на завершение - см. tasking.h.
void task_mark_current_exiting() {
    if (current_task) {
        current_task->exiting = 1;
    }
}

int task_current_is_exiting(void) {
    return current_task ? current_task->exiting : 0;
}

// true, если текущая задача изолирована (см. tasking.h).
int task_current_is_isolated() {
    return current_task && current_task->user_slot_index >= 0;
}

// Имя текущей задачи (см. tasking.h).
char* task_current_name() {
    return current_task->name;
}

void print_task_list() {
    if (!current_task) {
        print_string("Tasking not initialized.\n");
        return;
    }

    task_t* t = current_task;
    do {
        print_string("[");
        print_uint((unsigned long)t->id);
        print_string("] ");
        print_string(t->name);
        print_string(": ");
        print_uint(t->ticks);
        print_string(" ticks\n");
        t = t->next;
    } while (t != current_task);
}

// Возвращает user_slot_index текущей задачи (-1 если не изолирована).
int task_current_slot_index() {
    if (!current_task) return -1;
    return current_task->user_slot_index;
}

// MLS-уровень текущей задачи (см. tasking.h, SYS_SET_LEVEL в kernel.c).
unsigned int task_current_mls_level() {
    return current_task ? current_task->mls_level : 0;
}

// Устанавливает MLS-уровень ТЕКУЩЕЙ задачи (она поднимает себе уровень
// сама - см. SYS_SET_LEVEL, kernel.c). Зажимаем в [0, MLS_LEVEL_MAX] -
// не self-DoS через переполнение при дальнейших сравнениях уровней.
void task_set_current_mls_level(unsigned int level) {
    if (!current_task) return;
    if (level > MLS_LEVEL_MAX) level = MLS_LEVEL_MAX;
    current_task->mls_level = level;
}

// Заполняет информацию о задаче с порядковым номером index (см. tasking.h).
int task_get_info(unsigned int index, int* pid_out, char* name_out,
                  unsigned int* ticks_out, int* slot_out, unsigned int* level_out) {
    if (!current_task) return 0;
    task_t* t = current_task;
    unsigned int i = 0;
    do {
        if (i == index) {
            *pid_out = t->id;
            int j;
            for (j = 0; t->name[j] && j < MAX_NAME_LEN - 1; j++)
                name_out[j] = t->name[j];
            name_out[j] = '\0';
            *ticks_out = (unsigned int)t->ticks;
            *slot_out = t->user_slot_index;
            *level_out = t->mls_level;
            return 1;
        }
        i++;
        t = t->next;
    } while (t != current_task);
    return 0;
}

// Ищет изолированную задачу по слоту и помечает её exiting.
// Вызывается из keyboard_handler_main при Ctrl+C.
void task_kill_by_slot(int slot) {
    if (slot < 0 || !current_task) return;
    task_t* t = current_task;
    do {
        if (t->user_slot_index == slot) {
            t->exiting = 1;
            t->exit_code = -1; // kill = аварийное завершение
            return;
        }
        t = t->next;
    } while (t != current_task);
}

// Ищет изолированную задачу по pid и помечает её exiting - см. tasking.h.
// Используется SYS_KILL (kernel.c, команда "kill <pid>" в sh.c).
int task_kill_by_pid(int pid) {
    if (!current_task) return 0;
    task_t* t = current_task;
    do {
        if (t->id == pid && t->user_slot_index >= 0) {
            t->exiting = 1;
            t->exit_code = -1;
            return 1;
        }
        t = t->next;
    } while (t != current_task);
    return 0;
}

// Записывает exit_code текущей задачи - см. tasking.h.
void task_set_current_exit_code(int code) {
    if (current_task) current_task->exit_code = code;
}

// Блокирует текущую задачу на ms миллисекунд - см. tasking.h. Сама по
// себе НЕ переключает задачу (schedule() не вызывается отсюда) - только
// помечает её; фактический обмен RSP делает syscalls.asm сразу после
// возврата из syscall_dispatch, тем же способом, что и
// timer_interrupt_handler (idt.asm) - см. task_current_wants_resched.
void task_sleep_current(unsigned long ms) {
    if (!current_task) return;
    current_task->sleeping = 1;
    current_task->wake_tick = timer_ticks + (unsigned long long)(ms / 10);
}

// Блокирует текущую задачу на чтении pipe_id - см. tasking.h. Тот же
// приём, что и task_sleep_current: сама не переключает, только
// помечает - см. task_current_wants_resched.
void task_wait_pipe_current(int pipe_id) {
    if (!current_task) return;
    current_task->waiting_pipe = pipe_id;
}

// 1, если текущая задача только что запросила немедленное переключение -
// см. tasking.h.
int task_current_wants_resched(void) {
    return current_task && (current_task->sleeping || current_task->waiting_pipe >= 0);
}

// Seccomp: устанавливает/сужает маску разрешённых syscall'ов текущей задачи.
// Если маска ещё не установлена (0) - ставим напрямую.
// Если уже установлена - применяем AND (только сужение, как в Linux).
void task_set_syscall_mask(unsigned long long mask) {
    if (!current_task) return;
    if (current_task->syscall_mask == 0)
        current_task->syscall_mask = mask;
    else
        current_task->syscall_mask &= mask;
}

unsigned long long task_get_syscall_mask(void) {
    return current_task ? current_task->syscall_mask : 0;
}

// 1 если syscall разрешён: фильтр не установлен (mask==0) ИЛИ бит num установлен.
int task_syscall_allowed(unsigned char num) {
    if (!current_task) return 1;
    unsigned long long mask = current_task->syscall_mask;
    if (mask == 0) return 1;
    return (mask >> num) & 1;
}
