#ifndef AXIOM_H
#define AXIOM_H

#include "syscalls.h"

// Базовые syscall-обёртки (реализованы в syscalls.asm)
void         ax_print(char* msg);
void         ax_clear(void);
char         ax_readkey(void);
// Возвращает 1 при успехе, 0 если диск не готов/заблокирован или нет места.
int          ax_writefile(char* name, unsigned char* data, unsigned int size);
unsigned int ax_readfile(char* name, unsigned char* buf, unsigned int max);
void         ax_exit(int code);

// Удалить файл с диска. Диск должен быть разблокирован.
// Возвращает 1 при успехе, 0 если диск не готов/заблокирован,
// AX_UNLINK_NOTFOUND если файла с таким именем нет.
int ax_unlink(char* filename);

// Создать директорию. Диск должен быть разблокирован.
// Возвращает 1 при успехе, 0 если диск не готов/заблокирован,
// AX_MKDIR_EXISTS если имя занято, AX_MKDIR_NOSPACE если нет места.
int ax_mkdir(char* dirname);

// Разблокировать (locked=0) или заблокировать (locked=1) файловую систему.
void ax_disk_lock(int locked);

// Низкоуровневый доступ к IDE-диску напрямую, минуя FAT12 (для диагностики -
// см. disktool.c). model/buf - буферы вызывающего; ядро только пишет в них.
int ax_disk_identify(char* model);                              // model >= 41 байт; 1=успех, 0=нет диска
int ax_disk_read_sector(unsigned int lba, unsigned char* buf);   // buf >= 512 байт (IDE_SECTOR_SIZE)
int ax_disk_write_sector(unsigned int lba, unsigned char* buf);  // buf >= 512 байт

// fd-based file API
int  ax_open(char* name, int flags);          // возвращает fd или -1
int  ax_fread(int fd, void* buf, unsigned int n);   // возвращает прочитанные байты
int  ax_fwrite(int fd, const void* buf, unsigned int n); // возвращает записанные байты
void ax_close(int fd);

// Управление процессами
int  ax_exec(char* cmdline);                        // запустить программу, вернуть slot или -1 (не найден) / -2 (нет слотов) / -3 (не валидный ELF)
int  ax_exec_redir(char* cmdline, char* outfile);   // то же + перенаправить stdout в файл
int  ax_task_alive(int slot);      // 1 = ещё работает, 0 = завершена
// Код выхода последней задачи, завершившейся в этом слоте (см.
// SYS_LAST_EXIT_CODE). Спрашивать сразу после того, как ax_task_alive
// впервые вернул 0 для этого слота.
int  ax_exit_code(int slot);
void ax_shell_claim(int claim);    // 1 = захватить клавиатуру, 0 = вернуть ядру
void ax_set_foreground(int slot);  // slot >= 0: Ctrl+C убьёт эту задачу; -1: сброс
// Убить изолированную задачу по pid (см. SYS_KILL). Возвращает 0
// (убита) или -1 (нет такого pid / не изолированная задача).
int  ax_kill(int pid);

// Клонирует текущую (изолированную) задачу - физическая память слота
// копируется целиком, оба процесса продолжают выполнение с этой же
// точки. Возвращает 0 в потомке, pid потомка (>0) в родителе, -1 при
// ошибке (нет свободных слотов, вызов не из изолированной задачи).
// Открытые fd и активный редирект вывода НЕ наследуются - потомок
// стартует с чистого листа по обоим пунктам (см. SYS_FORK).
int  ax_fork(void);

// Системное время
unsigned int ax_get_ticks(void);         // тики с момента загрузки (100 Гц)
void         ax_sleep_ms(unsigned int ms); // sleep ms миллисекунд (другие задачи получают CPU)

// Текущее время RTC (CMOS). year - две последние цифры (без "20" спереди).
void ax_get_datetime(struct datetime_args* a);

// Перезагружает систему через контроллер клавиатуры (8042). Не возвращается.
void ax_reboot(void);

// Текущая позиция курсора мыши (сетка 80x25) и нажатые кнопки.
void ax_get_mouse(struct mouse_args* a);

// Играет тон freq Гц в течение duration_ms мс через системный динамик,
// затем выключает его (блокирующий вызов - другие задачи получают CPU).
// freq=0 - тишина (пауза между нотами).
void ax_beep(unsigned int freq, unsigned int duration_ms);

// Буфер обмена: общий слот в ядре, переживает завершение задач.
// ax_clipboard_set копирует size байт (максимум CLIPBOARD_MAX_SIZE) из data.
// ax_clipboard_get копирует в buf не больше max байт, возвращает фактический размер.
void         ax_clipboard_set(unsigned char* data, unsigned int size);
unsigned int ax_clipboard_get(unsigned char* buf, unsigned int max);

// MLS-уровень (s0..s15) вызывающей задачи - самодекларация, см.
// SYS_SET_LEVEL (src/user/syscall.h). Буфер обмена не отдаст содержимое
// задаче с уровнем ниже уровня, на котором его последний раз заполнили.
void ax_set_level(unsigned int level);

// Перечисление файлов (обёртка над SYS_READDIR)
// Заполняет *a и возвращает a->result (1 = есть запись, 0 = конец)
int ax_readdir(struct readdir_args* a);

// Список задач (обёртка над SYS_PS)
// Заполняет *e и возвращает e->result (1 = запись найдена, 0 = конец)
int ax_ps(struct ps_entry* e);

// Меняет приоритет (1..10, зажимается ядром) задачи по pid - сколько
// последовательных таймерных тиков она держит CPU за один заход
// планировщика (weighted round-robin, см. task_set_priority в tasking.c).
// Любая задача может менять приоритет любой другой (включая себя).
void ax_set_priority(int pid, int priority);

// Список PCI-устройств (обёртка над SYS_PCI_GET_DEVICE), см. lspci.c.
// d->index - вход (0-based); заполняет остальные поля *d, возвращает
// d->result (1 = запись найдена, 0 = конец списка).
int ax_pci_get_device(struct pci_device_args* d);

// virtio-net (SYS_NET_MAC/SEND/RECV) - сырой доступ к Ethernet-кадрам,
// см. src/drivers/virtio_net.c. Без флага QEMU `-device virtio-net-pci`
// ax_net_mac() просто вернёт 0 (нет NIC), остальные два безобидно -1/0.
int          ax_net_mac(unsigned char* mac);              // mac[6]; 1=найден NIC, 0=нет
int          ax_net_send(const void* frame, unsigned int len);   // 0=ок, -1=ошибка/нет NIC
unsigned int ax_net_recv(void* buf, unsigned int max_len);        // байт скопировано, 0=ничего/нет NIC

// Динамическая память (sbrk + malloc/free + shadow memory)
void* ax_sbrk(int increment);           // сдвинуть heap break; (void*)-1 при ошибке
void* ax_malloc(unsigned int size);     // выделить size байт или NULL
void  ax_free(void* ptr);               // освободить блок

// Shadow + Memory Tagging API (144-битный составной тег поколения - см.
// src/kernel/heap.c за обоснованием ширины/компромисса скорости):
// ax_check      — 1 если [ptr,ptr+size) в состоянии OK (любой тег).
// ax_alloc_tag  — тег текущего поколения блока (нулевой tag144_t = freed/не выделен).
// ax_check_tag  — 1 если OK И тег совпадает; ловит UAF после переиспользования.
// ax_handle      — снимок (addr, тег) в "проверяемую ссылку" (software TBI stand-in).
// ax_resolve     — указатель, если поколение всё ещё текущее; иначе 0.
typedef struct {
    unsigned long long lo;
    unsigned long long mid;
    unsigned short      hi;   // используются только младшие 16 бит
} __attribute__((packed)) tag144_t;

static inline tag144_t tag144_zero(void) {
    tag144_t t; t.lo = 0; t.mid = 0; t.hi = 0; return t;
}
static inline int tag144_is_zero(tag144_t t) {
    return !t.lo && !t.mid && !t.hi;
}
static inline int tag144_eq(tag144_t a, tag144_t b) {
    return a.lo == b.lo && a.mid == b.mid && a.hi == b.hi;
}

int          ax_check(void* ptr, unsigned int size);
tag144_t     ax_alloc_tag(void* ptr);
int          ax_check_tag(void* ptr, tag144_t expected_tag, unsigned int size);
typedef struct { void* addr; tag144_t tag; } ax_handle_t;
ax_handle_t  ax_handle(void* ptr);
void*        ax_resolve(ax_handle_t h, unsigned int size);

// Уровень stdio (реализован в stdio.c)
void ax_putchar(char c);
void ax_print_uint(unsigned int n);
int  ax_readline(char* buf, int max);  // блокирующее чтение строки с клавиатуры
void ax_printf(const char* fmt, ...);  // %s %d %u %x %c %%

// =================================================================
//  Seccomp: фильтрация syscall'ов (SYS_SECCOMP 0x23)
// =================================================================
//
// ax_seccomp(mask) — установить/сузить маску разрешённых syscall'ов.
// Бит N в mask = syscall 0x00+N разрешён.
// После первого вызова маска только сужается (AND); расширить нельзя.
// SYS_SECCOMP (бит 0x23) всегда разрешён ядром — это позволяет
// программе сузить маску несколько раз подряд.
//
// Готовые профили (можно комбинировать через |):
//   AX_SC_PRINT   — только вывод на экран (print, clear)
//   AX_SC_STDIO   — ввод/вывод + выход + память
//   AX_SC_FILES   — + файловые операции
//   AX_SC_EXEC    — + запуск программ
//   AX_SC_ALL     — все syscall'ы (отключить фильтр нельзя)
//
// Пример использования в начале main():
//   ax_seccomp(AX_SC_STDIO);   // разрешить только ввод/вывод/exit/sbrk
//   ax_seccomp(AX_SC_STDIO | AX_SC_FILES);  // + файлы

// Бит для одного syscall'а по номеру:
#define AX_SC_BIT(n) (1ULL << (unsigned)(n))

// Индивидуальные биты (совпадают с SYS_* номерами из syscalls.asm):
#define AX_SC_PRINT        AX_SC_BIT(0x01)  // ax_print
#define AX_SC_CLEAR        AX_SC_BIT(0x02)  // ax_clear
#define AX_SC_READKEY      AX_SC_BIT(0x03)  // ax_readkey
#define AX_SC_WRITEFILE    AX_SC_BIT(0x04)  // ax_writefile
#define AX_SC_READFILE     AX_SC_BIT(0x05)  // ax_readfile
#define AX_SC_EXIT         AX_SC_BIT(0x06)  // ax_exit
#define AX_SC_OPEN         AX_SC_BIT(0x07)  // ax_open
#define AX_SC_FREAD        AX_SC_BIT(0x08)  // ax_fread
#define AX_SC_FWRITE       AX_SC_BIT(0x09)  // ax_fwrite
#define AX_SC_CLOSE        AX_SC_BIT(0x0A)  // ax_close
#define AX_SC_EXEC         AX_SC_BIT(0x0B)  // ax_exec
#define AX_SC_TASK_ALIVE   AX_SC_BIT(0x0C)  // ax_task_alive
#define AX_SC_SHELL_CLAIM  AX_SC_BIT(0x0D)  // ax_shell_claim
#define AX_SC_FOREGROUND   AX_SC_BIT(0x0E)  // ax_set_foreground
#define AX_SC_GET_TICKS    AX_SC_BIT(0x0F)  // ax_get_ticks
#define AX_SC_SLEEP        AX_SC_BIT(0x10)  // ax_sleep_ms
#define AX_SC_READDIR      AX_SC_BIT(0x11)  // ax_readdir
#define AX_SC_SBRK         AX_SC_BIT(0x12)  // ax_sbrk (нужен malloc)
#define AX_SC_PS           AX_SC_BIT(0x13)  // ax_ps
#define AX_SC_EXEC_REDIR   AX_SC_BIT(0x14)  // ax_exec_redir
#define AX_SC_UNLINK       AX_SC_BIT(0x15)  // ax_unlink
#define AX_SC_MKDIR        AX_SC_BIT(0x16)  // ax_mkdir
#define AX_SC_FS_LOCK      AX_SC_BIT(0x17)  // ax_disk_lock
#define AX_SC_DISK_ID      AX_SC_BIT(0x18)  // ax_disk_identify
#define AX_SC_DISK_READ    AX_SC_BIT(0x19)  // ax_disk_read_sector
#define AX_SC_DISK_WRITE   AX_SC_BIT(0x1A)  // ax_disk_write_sector
#define AX_SC_DATETIME     AX_SC_BIT(0x1B)  // ax_get_datetime
#define AX_SC_REBOOT       AX_SC_BIT(0x1C)  // ax_reboot
#define AX_SC_MOUSE        AX_SC_BIT(0x1D)  // ax_get_mouse
#define AX_SC_BEEP         AX_SC_BIT(0x1E)  // ax_beep
#define AX_SC_CLIP_SET     AX_SC_BIT(0x1F)  // ax_clipboard_set
#define AX_SC_CLIP_GET     AX_SC_BIT(0x20)  // ax_clipboard_get
#define AX_SC_SET_LEVEL    AX_SC_BIT(0x21)  // ax_set_level
#define AX_SC_PCI          AX_SC_BIT(0x22)  // ax_pci_get_device
// 0x23 = SYS_SECCOMP — всегда разрешён ядром, бит здесь для явного включения
#define AX_SC_SET_PRIORITY AX_SC_BIT(0x24)  // ax_set_priority
#define AX_SC_NET_MAC      AX_SC_BIT(0x25)  // ax_net_mac
#define AX_SC_NET_SEND     AX_SC_BIT(0x26)  // ax_net_send
#define AX_SC_NET_RECV     AX_SC_BIT(0x27)  // ax_net_recv
#define AX_SC_LAST_EXIT_CODE AX_SC_BIT(0x28)  // ax_exit_code
#define AX_SC_KILL         AX_SC_BIT(0x29)  // ax_kill
#define AX_SC_FORK         AX_SC_BIT(0x2A)  // ax_fork

// Готовые профили:
#define AX_SC_PRINT_ONLY  (AX_SC_PRINT | AX_SC_CLEAR | AX_SC_EXIT | AX_SC_SBRK)
#define AX_SC_STDIO       (AX_SC_PRINT | AX_SC_CLEAR | AX_SC_READKEY | \
                           AX_SC_EXIT  | AX_SC_SBRK  | AX_SC_GET_TICKS | AX_SC_SLEEP)
#define AX_SC_FILES       (AX_SC_WRITEFILE | AX_SC_READFILE | AX_SC_OPEN | \
                           AX_SC_FREAD     | AX_SC_FWRITE   | AX_SC_CLOSE | \
                           AX_SC_READDIR   | AX_SC_UNLINK   | AX_SC_MKDIR)
// AX_SC_KILL/AX_SC_FORK сознательно НЕ входят сюда (как и AX_SC_REBOOT) -
// ни убийство произвольной задачи по pid, ни клонирование себя не
// относятся к обычному жизненному циклу "запустить и дождаться",
// включаются явно, если действительно нужно.
#define AX_SC_EXEC_MASK   (AX_SC_EXEC | AX_SC_EXEC_REDIR | AX_SC_TASK_ALIVE | \
                           AX_SC_LAST_EXIT_CODE | \
                           AX_SC_SHELL_CLAIM | AX_SC_FOREGROUND)
#define AX_SC_ALL         (~0ULL)

// Установить/сузить seccomp-маску (lo = биты 0-31, hi = биты 32-63).
// Обычно вызывается через макрос ax_seccomp(mask).
void ax_seccomp_raw(unsigned int mask_lo, unsigned int mask_hi);

// Удобный макрос: принимает unsigned long long напрямую.
#define ax_seccomp(mask) \
    ax_seccomp_raw((unsigned int)((unsigned long long)(mask)), \
                   (unsigned int)((unsigned long long)(mask) >> 32))

#endif
