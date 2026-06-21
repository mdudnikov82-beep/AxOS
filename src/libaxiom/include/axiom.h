#ifndef AXIOM_H
#define AXIOM_H

#include "syscalls.h"

// Базовые syscall-обёртки (реализованы в syscalls.asm)
void         ax_print(char* msg);
void         ax_clear(void);
char         ax_readkey(void);
void         ax_writefile(char* name, unsigned char* data, unsigned int size);
unsigned int ax_readfile(char* name, unsigned char* buf, unsigned int max);
void         ax_exit(void);

// Удалить файл с диска. Диск должен быть разблокирован.
// Возвращает 1 при успехе, 0 если файл не найден или диск заблокирован.
int ax_unlink(char* filename);

// Создать директорию. Диск должен быть разблокирован.
// Возвращает 1 при успехе, 0 если имя занято, нет места, или диск заблокирован.
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
int  ax_exec(char* cmdline);                        // запустить программу, вернуть slot или -1/-2
int  ax_exec_redir(char* cmdline, char* outfile);   // то же + перенаправить stdout в файл
int  ax_task_alive(int slot);      // 1 = ещё работает, 0 = завершена
void ax_shell_claim(int claim);    // 1 = захватить клавиатуру, 0 = вернуть ядру
void ax_set_foreground(int slot);  // slot >= 0: Ctrl+C убьёт эту задачу; -1: сброс

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

// Перечисление файлов (обёртка над SYS_READDIR)
// Заполняет *a и возвращает a->result (1 = есть запись, 0 = конец)
int ax_readdir(struct readdir_args* a);

// Список задач (обёртка над SYS_PS)
// Заполняет *e и возвращает e->result (1 = запись найдена, 0 = конец)
int ax_ps(struct ps_entry* e);

// Динамическая память (sbrk + malloc/free)
void* ax_sbrk(int increment);           // сдвинуть heap break; (void*)-1 при ошибке
void* ax_malloc(unsigned int size);     // выделить size байт или NULL
void  ax_free(void* ptr);               // освободить блок

// Уровень stdio (реализован в stdio.c)
void ax_putchar(char c);
void ax_print_uint(unsigned int n);
int  ax_readline(char* buf, int max);  // блокирующее чтение строки с клавиатуры
void ax_printf(const char* fmt, ...);  // %s %d %u %x %c %%

#endif
