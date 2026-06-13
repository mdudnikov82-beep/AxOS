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

#define TASK_STACK_SIZE 4096
#define MAX_NAME_LEN 16

typedef struct task {
    unsigned int esp;
    int id;
    char name[MAX_NAME_LEN];
    unsigned long ticks;
    struct task* next;
} task_t;

extern void print_string(char* str);
extern void print_uint(unsigned long val);

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
    task0.next = &task0;

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

    // Вставляем новую задачу сразу после текущей в кольце
    new_task->next = current_task->next;
    current_task->next = new_task;
}

unsigned int schedule(unsigned int current_esp) {
    if (!current_task) return current_esp; // tasking ещё не инициализирован

    // Кадр прерывания: [pusha x8][EIP][CS][EFLAGS]{[ESP][SS]] - CS лежит
    // по смещению +36 от esp независимо от того, было ли переключение
    // привилегий (ring3->ring0 добавляет ESP/SS ПОСЛЕ EFLAGS, не сдвигая
    // более ранние поля). Если прерванный код выполнялся в ring3
    // (usermode-демо), не переключаем задачу в этом тике: совместное
    // использование ESP0 из TSS планировщиком и ring3->ring0 переходом
    // приводит к порче стека task0 и тройному сбою.
    unsigned int cs = *(unsigned int*)(current_esp + 36);
    if ((cs & 0x3) == 3) return current_esp;

    current_task->esp = current_esp;
    current_task->ticks++;
    current_task = current_task->next;
    return current_task->esp;
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
