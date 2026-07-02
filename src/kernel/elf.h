#ifndef ELF_H
#define ELF_H

// Минимальный ELF32-парсер для пользовательских программ ("run"/SYS_EXEC).
// Понимает РОВНО то подмножество ELF, которое сама же ОС производит
// (tools/make_elf.py - один PT_LOAD, без секций, без релокаций/динамики,
// без PT_INTERP/PT_DYNAMIC). Это не полноценный ELF-загрузчик - см.
// README про обнаруженный баг binutils BFD при PE->ELF конвертации,
// из-за которого реальный toolchain-сгенерированный ELF здесь не
// используется: формат целиком контролируется самой ОС.

// Результат разбора - один на вызов elf_load (на сегодня всегда ровно
// один PT_LOAD-сегмент, но поле считает максимум по всем найденным).
struct elf_load_result {
    unsigned int entry;          // e_entry + aslr_delta (виртуальный адрес точки входа)
    unsigned int max_vaddr_end;  // max(p_vaddr + p_memsz) + aslr_delta, округлённый
                                  // вверх до кратного 16 байт - начальный heap break
    unsigned int aslr_delta;     // случайное смещение кода (0 если нет .reloc в ELF)
    unsigned int wx_data_offset; // смещение в плоском бинарнике первого writable байта
                                  // (.bss); 0 = нет W^X-информации (из PT_AXOS_WX).
};

// Коды ошибок - каждая причина отказа отдельная, не одно общее "не ELF":
// тот же принцип, что уже применён к mkdir/write/rm (не молчать о причине
// отказа, см. README).
#define ELF_OK              0
#define ELF_ERR_BAD_MAGIC   -1  // нет 0x7F 'E' 'L' 'F'
#define ELF_ERR_BAD_CLASS   -2  // не ELFCLASS32 (32-битный)
#define ELF_ERR_BAD_DATA    -3  // не ELFDATA2LSB (little-endian)
#define ELF_ERR_BAD_MACHINE -4  // не EM_386
#define ELF_ERR_BAD_TYPE    -5  // не ET_EXEC
#define ELF_ERR_BAD_PHNUM   -6  // e_phnum == 0 или больше ELF_MAX_PHNUM
#define ELF_ERR_TRUNCATED   -7  // заголовки/сегмент выходят за staging_size
#define ELF_ERR_BOUNDS      -8  // сегмент/entry целят за пределы окна задачи
#define ELF_ERR_NOT_LOAD    -9  // нет ни одного PT_LOAD-сегмента

// Разбирает ELF-образ, целиком лежащий в staging_buf (staging_size байт -
// результат vfs_read() в буфер ядра, см. kernel.c: vfs_read/fat12_load не
// умеют читать "со смещения", поэтому файл сначала читается целиком, а
// нужный кусок (по Program Header) копируется отдельно).
//
// Для каждого PT_LOAD-сегмента копирует p_filesz байт по физическому
// адресу phys_slot_base + (p_vaddr - load_base_vaddr) и зануляет
// [p_filesz, p_memsz) внутри сегмента (общий случай настоящего bss -
// сегодня для существующих программ memsz всегда == filesz, см.
// make_elf.py, но код не предполагает этого специально).
//
// load_base_vaddr - виртуальный адрес, соответствующий phys_slot_base
// (USER_WINDOW_BASE, 0x100000) - используется, чтобы пересчитать p_vaddr
// в смещение внутри слота. max_segment_end_offset - верхняя граница (в
// байтах от начала слота), которую не должен пересекать ни один сегмент
// и точка входа - вызывающая сторона передаёт USER_ARGS_OFFSET (0x7C00),
// чтобы программа не могла залезть в зону argv.
//
// Возвращает ELF_OK (0) и заполняет *out, либо один из ELF_ERR_* кодов
// (out не трогается при ошибке).
int elf_load(unsigned char* staging_buf, unsigned int staging_size,
             unsigned char* phys_slot_base, unsigned int load_base_vaddr,
             unsigned int max_segment_end_offset,
             struct elf_load_result* out);

#endif
