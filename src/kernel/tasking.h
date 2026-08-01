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
// entry_vaddr - точка входа (EIP), которую сообщил ELF-загрузчик
// (struct elf_load_result.entry, см. elf.h) - на практике сегодня всегда
// совпадает с USER_WINDOW_BASE (любая программа линкуется с этого адреса,
// см. src/user/user.ld), но теперь это решается данными из файла, а не
// зашитой константой.
// wx_delta     = ASLR delta в байтах (elf_load_result.aslr_delta)
// wx_data_off  = flat offset начала .bss (elf_load_result.wx_data_offset; 0=нет W^X)
void task_create_user_isolated(char* name, unsigned int phys_slot_base, int user_slot_index,
                               int argc, unsigned int argv_vaddr, unsigned int entry_vaddr,
                               unsigned int wx_delta, unsigned int wx_data_off);

// Создаёт задачу-потомка как КЛОН текущей задачи в момент вызова SYS_FORK
// (kernel.c::sys_fork_impl) - в отличие от task_create_user_isolated
// (фабрикует свежий кадр с точкой входа ELF), эта функция копирует
// ЖИВОЙ регистровый кадр родителя (parent_rsp - указывает на кадр,
// сохранённый syscalls.asm перед вызовом sys_fork_impl, тот же формат,
// что и task_t.rsp) - потомок продолжит выполнение ровно с той же точки
// (после int 0x80 самого fork()), но с RAX=0 (свой кадр правится здесь),
// пока родитель получает pid потомка (пишет sys_fork_impl отдельно, в
// СВОЙ, родительский кадр). Физическая память слота уже должна быть
// скопирована ДО вызова (см. sys_fork_impl) - здесь только клонирование
// регистров + создание task_t. wx_delta/wx_data_off - те же значения,
// которыми была построена директория родителя (см. slot_wx_delta/
// slot_wx_data_off, kernel.c) - скопированная память имеет тот же
// W^X-макет. Возвращает pid потомка (>=0) или -1 при нехватке памяти
// под kstack/task_t (слот в этом случае НЕ помечается занятым - это
// делает вызывающий, sys_fork_impl, только после успеха).
int task_fork_current(unsigned long long parent_rsp, unsigned int child_phys_base,
                      int child_slot_index, unsigned int wx_delta, unsigned int wx_data_off);

// Вызывается из idt.asm при каждом IRQ0: сохраняет rsp текущей задачи,
// переключается на следующую по кольцу и возвращает её rsp. Если
// текущая задача помечена exiting (task_mark_current_exiting) - убирает
// её из кольца и освобождает её ресурсы (см. tasking.c).
unsigned long long schedule(unsigned long long current_rsp);

// Печатает список задач (id, имя, число тиков) - используется командой `ps`.
void print_task_list();

// Возвращает 1 если текущая задача уже помечена на завершение.
int task_current_is_exiting(void);

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

// user_slot_index текущей задачи, или -1 если задача не изолирована.
// Используется SYS_SBRK для поиска heap break этой задачи.
int task_current_slot_index();

// Находит изолированную задачу с user_slot_index == slot и помечает её
// exiting (exit_code = -1 - аварийное завершение). Используется для
// Ctrl+C из shell (kernel.c::keyboard_handler_main).
void task_kill_by_slot(int slot);

// Находит изолированную (user_slot_index >= 0) задачу с id == pid и
// помечает её exiting (exit_code = -1). Ring0/builtin задачи (shell,
// heartbeat) так не убить - у них user_slot_index == -1. Возвращает 1
// если задача найдена и убита, 0 если нет такого pid или задача не
// изолирована. Используется SYS_KILL (kernel.c) для команды "kill <pid>".
int task_kill_by_pid(int pid);

// Записывает exit_code ТЕКУЩЕЙ задачи (она сообщает о своём коде выхода
// сама - см. SYS_EXIT, kernel.c). No-op, если планировщик не
// инициализирован. Значение подхватывается on_task_exit() (kernel.c) в
// момент реального реапа задачи в schedule() - см. комментарий там.
void task_set_current_exit_code(int code);

// Блокирует ТЕКУЩУЮ задачу на ms миллисекунд - настоящий блок (задача
// снимается с ротации планировщика), не busy-wait. Используется SYS_SLEEP
// (kernel.c); фактическое переключение происходит в syscalls.asm сразу
// после возврата из syscall_dispatch - см. task_current_wants_resched.
void task_sleep_current(unsigned long ms);

// 1, если текущая задача только что запросила немедленное переключение
// (сейчас единственная причина - task_sleep_current только что усыпила
// её). syscalls.asm вызывает это сразу после syscall_dispatch: если 1 -
// вместо обычного возврата к вызывающей задаче делает тот же обмен RSP
// через schedule(), что и timer_interrupt_handler (idt.asm).
int task_current_wants_resched(void);

// Блокирует ТЕКУЩУЮ задачу до тех пор, пока pipe_id не станет "готов"
// (см. pipe_ready, kernel.c) - настоящая читающая задача pipe'а (SYS_FREAD
// на "PIPE:N", см. kernel.c) снимается с ротации так же, как и спящая -
// та же машинерия task_current_wants_resched/syscalls.asm её пробуждает.
void task_wait_pipe_current(int pipe_id);

// Заполняет поля pid, name, ticks, slot, level для задачи с порядковым
// номером index. Возвращает 1 если найдена, 0 если index >= числа задач
// в кольце.
int task_get_info(unsigned int index, int* pid_out, char* name_out,
                  unsigned int* ticks_out, int* slot_out, unsigned int* level_out);

// MLS (Multi-Level Security) уровень чувствительности текущей задачи -
// s0..s15, как в "level" компоненте контекста SELinux (user:role:type:level).
// Новые задачи стартуют на s0 (task_current_mls_level() == 0).
// task_set_current_mls_level (SYS_SET_LEVEL, kernel.c) - изолированная
// задача может через него только ПОНИЗИТЬ себе уровень, никогда поднять
// (раньше самоподъём был вообще ничем не ограничен - любая confined-задача
// могла поднять себя до s15 и обойти "no read up" целиком). Единственный
// способ поднять уровень ВЫШЕ 0 - task_set_mls_level_for_slot() ниже,
// которым доверенный (unconfined) kernel-shell назначает НАЧАЛЬНЫЙ
// уровень новой задаче ДО того, как она получит CPU в первый раз - см.
// execute_command()'s "runlevel <N> <file>" в kernel.c.
unsigned int task_current_mls_level();
void task_set_current_mls_level(unsigned int level);

// Устанавливает НАЧАЛЬНЫЙ MLS-уровень задачи по её user_slot_index -
// доверенная (unconfined) операция, вызывать ТОЛЬКО из kernel-shell'а
// сразу после task_create_user_isolated(), до первого переключения на
// эту задачу. No-op, если слот не найден.
void task_set_mls_level_for_slot(int slot, unsigned int level);

// xorshift32 ГПСЧ, общий для ASLR стека и кучи. Сид = timer_ticks,
// обновляется при каждом вызове.
unsigned int aslr_next_random(void);

// Seccomp-фильтр: 64-битная маска разрешённых syscall'ов (бит N = syscall N OK).
// 0 = фильтр не установлен (все syscall'ы разрешены).
// task_set_syscall_mask применяет AND с текущей маской — только сужение.
// task_syscall_allowed возвращает 1 если syscall разрешён (или фильтр не установлен).
void task_set_syscall_mask(unsigned long long mask);
unsigned long long task_get_syscall_mask(void);
int task_syscall_allowed(unsigned char num);

// Приоритет = сколько последовательных таймерных тиков задача держит CPU
// за один заход в кольцо планировщика (weighted round-robin, 1..10,
// по умолчанию 3 - см. PRIORITY_DEFAULT в tasking.c). Не строгие уровни:
// низкоприоритетная задача не голодает вечно, просто реже получает ход.
void task_set_priority(int pid, int priority);

#endif
