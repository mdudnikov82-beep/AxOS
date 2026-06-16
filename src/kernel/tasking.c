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
#define USER_CODE_SEG 0x18
#define USER_DATA_SEG 0x20

typedef struct task {
    unsigned int esp;
    unsigned int kernel_stack_top; // ESP0 этой задачи (для ring3->ring0)
    unsigned int page_directory;   // CR3 этой задачи (PAGE_DIRECTORY или приватный PD)
    int id;
    char name[MAX_NAME_LEN];
    unsigned long ticks;
    int user_slot_index; // -1 для task0/heartbeat/ring3demo; 0..3 для run-задач (kernel.c)
    int exiting;         // 1 - schedule() уберёт задачу из кольца на следующем тике
    struct task* next;
} task_t;

extern void print_string(char* str);
extern void print_uint(unsigned long val);
extern void on_task_exit(int user_slot_index); // kernel.c - освобождает слот run-задачи

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
    task0.esp = 0;
    task0.id = next_id++;
    copy_name(task0.name, "shell");
    task0.ticks = 0;
    task0.page_directory = (unsigned int)PAGE_DIRECTORY;
    task0.user_slot_index = -1;
    task0.exiting = 0;
    task0.next = &task0;

    // Отдельный стек ядра для task0: НЕ совпадает с её "живым" стеком
    // (растущим вниз от 0x90000), поэтому ring3->ring0 переходы (когда
    // task0 уходит в ring3 через usermode) не затирают его.
    unsigned char* kstack = (unsigned char*)malloc(KSTACK_SIZE);
    task0.kernel_stack_top = (unsigned int)(kstack + KSTACK_SIZE);
    tss_set_esp0(task0.kernel_stack_top);

    current_task = &task0;
}

void task_create(char* name, void (*entry)(void)) {
    unsigned char* stack_mem = (unsigned char*)malloc(TASK_STACK_SIZE);
    if (!stack_mem) return;

    task_t* new_task = (task_t*)malloc(sizeof(task_t));
    if (!new_task) return;

    // Фабрикуем кадр [EFLAGS][CS][EIP] + 8 "регистров" pusha (все 0),
    // считая от верхушки стека вниз - см. комментарий в начале файла.
    unsigned int* sp = (unsigned int*)(stack_mem + TASK_STACK_SIZE);
    *(--sp) = 0x202;            // EFLAGS: IF=1
    *(--sp) = 0x08;             // CS: сегмент кода ядра (CODE_SEG в gdt.asm)
    *(--sp) = (unsigned int)entry; // EIP
    *(--sp) = 0; // EAX
    *(--sp) = 0; // ECX
    *(--sp) = 0; // EDX
    *(--sp) = 0; // EBX
    *(--sp) = 0; // ESP - игнорируется popa
    *(--sp) = 0; // EBP
    *(--sp) = 0; // ESI
    *(--sp) = 0; // EDI

    new_task->esp = (unsigned int)sp;
    new_task->id = next_id++;
    copy_name(new_task->name, name);
    new_task->ticks = 0;
    new_task->page_directory = (unsigned int)PAGE_DIRECTORY;
    new_task->user_slot_index = -1;
    new_task->exiting = 0;

    // Свой стек ядра (ESP0) для единообразия - schedule() обновляет
    // TSS.ESP0 для каждой задачи, даже если она остаётся в ring0.
    unsigned char* kstack = (unsigned char*)malloc(KSTACK_SIZE);
    new_task->kernel_stack_top = (unsigned int)(kstack + KSTACK_SIZE);

    // Вставляем новую задачу сразу после текущей в кольце
    new_task->next = current_task->next;
    current_task->next = new_task;
}

void task_create_user(char* name, void (*entry)(void)) {
    unsigned char* user_stack = (unsigned char*)malloc(TASK_STACK_SIZE);
    unsigned char* kstack = (unsigned char*)malloc(KSTACK_SIZE);
    if (!user_stack || !kstack) return;

    task_t* new_task = (task_t*)malloc(sizeof(task_t));
    if (!new_task) return;

    unsigned int user_stack_top = (unsigned int)(user_stack + TASK_STACK_SIZE);

    // Фабрикуем кадр ring3->ring0 на стеке ядра задачи: [pusha x8 (0)]
    // [EIP=entry][CS=USER_CODE_SEG|3][EFLAGS=0x202][ESP=user_stack_top]
    // [SS=USER_DATA_SEG|3] - popa+iret в idt.asm "запустит" задачу прямо
    // в ring3 (5-словный iret из-за CS с CPL=3).
    unsigned int* sp = (unsigned int*)(kstack + KSTACK_SIZE);
    *(--sp) = USER_DATA_SEG | 3;   // SS
    *(--sp) = user_stack_top;      // ESP
    *(--sp) = 0x202;               // EFLAGS: IF=1
    *(--sp) = USER_CODE_SEG | 3;   // CS
    *(--sp) = (unsigned int)entry; // EIP
    *(--sp) = 0; // EAX
    *(--sp) = 0; // ECX
    *(--sp) = 0; // EDX
    *(--sp) = 0; // EBX
    *(--sp) = 0; // ESP - игнорируется popa
    *(--sp) = 0; // EBP
    *(--sp) = 0; // ESI
    *(--sp) = 0; // EDI

    new_task->esp = (unsigned int)sp;
    new_task->kernel_stack_top = (unsigned int)(kstack + KSTACK_SIZE);
    new_task->id = next_id++;
    copy_name(new_task->name, name);
    new_task->ticks = 0;
    new_task->page_directory = (unsigned int)PAGE_DIRECTORY;
    new_task->user_slot_index = -1;
    new_task->exiting = 0;

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

void task_create_user_isolated(char* name, unsigned int phys_slot_base, int user_slot_index,
                               int argc, unsigned int argv_vaddr) {
    unsigned char* kstack = (unsigned char*)malloc(KSTACK_SIZE);
    if (!kstack) return;

    task_t* new_task = (task_t*)malloc(sizeof(task_t));
    if (!new_task) return;

    // Кадр ring3->ring0, как в task_create_user, но EIP/ESP - виртуальные
    // адреса окна 0x100000-0x108000 (одинаковые для любой задачи: окно
    // переотображается на физический слот этой задачи в её приватном PD).
    unsigned int* sp = (unsigned int*)(kstack + KSTACK_SIZE);
    *(--sp) = USER_DATA_SEG | 3;     // SS
    *(--sp) = USER_STACK_TOP;        // ESP: ниже верха окна (см. USER_STACK_TOP)
    *(--sp) = 0x202;                 // EFLAGS: IF=1
    *(--sp) = USER_CODE_SEG | 3;     // CS
    *(--sp) = USER_WINDOW_BASE;        // EIP: начало окна (_start crt0)
    *(--sp) = 0;                       // EAX
    *(--sp) = argv_vaddr;              // ECX = virtual ptr to argv[] array (0x107C00)
    *(--sp) = 0;                       // EDX
    *(--sp) = (unsigned int)argc;      // EBX = argc
    *(--sp) = 0; // ESP - игнорируется popa
    *(--sp) = 0; // EBP
    *(--sp) = 0; // ESI
    *(--sp) = 0; // EDI

    new_task->esp = (unsigned int)sp;
    new_task->kernel_stack_top = (unsigned int)(kstack + KSTACK_SIZE);
    new_task->id = next_id++;
    copy_name(new_task->name, name);
    new_task->ticks = 0;
    new_task->page_directory = paging_create_user_directory(user_slot_index, phys_slot_base);
    new_task->user_slot_index = user_slot_index;
    new_task->exiting = 0;

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

unsigned int schedule(unsigned int current_esp) {
    if (!current_task) return current_esp; // tasking ещё не инициализирован

    current_task->esp = current_esp;
    current_task->ticks++;

    task_t* dying = current_task;
    unsigned int prev_page_directory = dying->page_directory;
    task_t* next = dying->next;

    // Задача помечена на завершение (SYS_EXIT - kernel.c, или page fault
    // в ring3 - paging.c) - убираем её из кольца и освобождаем ресурсы.
    // exiting выставляется ТОЛЬКО у задач с user_slot_index >= 0 (run);
    // task0/heartbeat/ring3demo никогда не завершаются, так что кольцо
    // никогда не опустеет (pred ниже всегда найдётся).
    if (dying->exiting) {
        task_t* pred = next;
        while (pred->next != dying) pred = pred->next;
        pred->next = next;

        if (dying->user_slot_index >= 0) {
            on_task_exit(dying->user_slot_index);
        }

        free((void*)(dying->kernel_stack_top - KSTACK_SIZE));
        free(dying);
    }

    current_task = next;

    // У каждой задачи свой стек для ring3->ring0 переходов (IRQ/syscall
    // во время выполнения этой задачи) - без этого общий ESP0 пересекался
    // бы с "живым" стеком задачи, которая ушла в ring3 (см. tss.c).
    tss_set_esp0(current_task->kernel_stack_top);

    // Изолированные задачи (task_create_user_isolated) имеют свой
    // page_directory - переключаем CR3, только если он изменился
    // (иначе лишний flush TLB на каждый тик для не-изолированных задач).
    if (current_task->page_directory != prev_page_directory) {
        __asm__ volatile("mov %0, %%cr3" :: "r"(current_task->page_directory));
    }

    return current_task->esp;
}

// Помечает текущую задачу на завершение - см. tasking.h.
void task_mark_current_exiting() {
    if (current_task) {
        current_task->exiting = 1;
    }
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
