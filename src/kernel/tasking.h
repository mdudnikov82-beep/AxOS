#ifndef TASKING_H
#define TASKING_H

// Простой кооперативно-вытесняющий (preemptive) round-robin планировщик
// для задач ring0 в общем адресном пространстве (без отдельных page
// directory на задачу - это будущий шаг). Переключение происходит в
// обработчике таймера (IRQ0, см. idt.asm) каждые 10 мс.

// Создаёт task0 - запись для текущего потока выполнения (kernel_main/shell).
// Вызывается один раз при старте ядра, после init_heap().
void init_tasking();

// Создаёт новую задачу: функция entry будет выполняться на собственном
// стеке (TASK_STACK_SIZE байт, из malloc), который никогда не возвращается
// (задача не должна делать return - только бесконечный цикл).
void task_create(char* name, void (*entry)(void));

// Создаёт ring3-задачу: entry выполняется с CPL=3 на собственном
// пользовательском стеке; у задачи также есть отдельный стек ядра
// (используется как TSS.ESP0 при прерываниях/syscall из этой задачи).
void task_create_user(char* name, void (*entry)(void));

// Создаёт изолированную ring3-задачу для команды "run" (kernel.c):
// у задачи свой Page Directory (paging_create_user_directory), в котором
// виртуальное окно 0x100000-0x108000 переотображено на физический слот
// phys_slot_base..+0x8000 - код, данные и стек задачи (ESP стартует с
// 0x108000) живут только в этом окне. user_slot_index (0..
// USER_PROGRAM_SLOTS-1) выбирает пару PD/PT из пула paging.h.
// argc/argv_vaddr - аргументы командной строки: kernel.c записывает блок
// argv[] в phys_slot_base+USER_ARGS_OFFSET; argv_vaddr - его виртуальный
// адрес (0x107C00). Задача получает argc в EBX, argv_vaddr в ECX при старте.
void task_create_user_isolated(char* name, unsigned int phys_slot_base, int user_slot_index,
                               int argc, unsigned int argv_vaddr);

// Вызывается из idt.asm при каждом IRQ0: сохраняет esp текущей задачи,
// переключается на следующую по кольцу и возвращает её esp. Если
// текущая задача помечена exiting (task_mark_current_exiting) - убирает
// её из кольца и освобождает её ресурсы (см. tasking.c).
unsigned int schedule(unsigned int current_esp);

// Печатает список задач (id, имя, число тиков) - используется командой `ps`.
void print_task_list();

// Помечает текущую задачу на завершение: schedule() уберёт её из кольца
// на следующем тике, освободит её kernel-стек/task_t и (если изолирована)
// её слот run (через on_task_exit, kernel.c). Используется SYS_EXIT
// (kernel.c) и killом изолированной задачи при page fault (paging.c).
// No-op, если планировщик ещё не инициализирован (current_task == 0).
void task_mark_current_exiting();

// true, если текущая задача изолирована (создана через
// task_create_user_isolated, имеет приватный page_directory и
// user_slot_index >= 0). Используется paging.c, чтобы решить - убить
// только эту задачу при page fault или останавливать всю систему.
int task_current_is_isolated();

// Имя текущей задачи (для сообщений вида "task killed").
char* task_current_name();

// Находит изолированную задачу с user_slot_index == slot и помечает её
// exiting. Используется для Ctrl+C из shell (kernel.c::keyboard_handler_main).
void task_kill_by_slot(int slot);

#endif
