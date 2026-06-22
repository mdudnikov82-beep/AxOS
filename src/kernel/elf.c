// =================================================================
//  Минимальный ELF32-загрузчик пользовательских программ
// =================================================================
//
// См. elf.h - понимает только то подмножество ELF, которое сама ОС
// производит (tools/make_elf.py). Поля читаются прямыми указателями
// (без memcpy/структур) - и генератор (Python на x86), и потребитель
// (сам x86) little-endian, так что это безопасно и соответствует стилю
// остального ядра (нет libc).

#include "elf.h"

// На сегодня программам нужен 1 PT_LOAD; 4 - щедрый, но не безумный
// потолок (защита от integer-overflow при e_phnum * sizeof(Elf32_Phdr)
// и от лишней работы на испорченный/враждебный файл).
#define ELF_MAX_PHNUM 4

#define ELF_EHDR_SIZE 52
#define ELF_PHDR_SIZE 32

#define PT_LOAD 1
#define ET_EXEC 2
#define EM_386  3

static unsigned int read_u32(unsigned char* p) {
    return (unsigned int)p[0] | ((unsigned int)p[1] << 8) |
           ((unsigned int)p[2] << 16) | ((unsigned int)p[3] << 24);
}

static unsigned short read_u16(unsigned char* p) {
    return (unsigned short)((unsigned int)p[0] | ((unsigned int)p[1] << 8));
}

int elf_load(unsigned char* staging_buf, unsigned int staging_size,
             unsigned char* phys_slot_base, unsigned int load_base_vaddr,
             unsigned int max_segment_end_offset,
             struct elf_load_result* out) {
    if (staging_size < ELF_EHDR_SIZE) return ELF_ERR_TRUNCATED;

    unsigned char* e = staging_buf;
    if (e[0] != 0x7F || e[1] != 'E' || e[2] != 'L' || e[3] != 'F')
        return ELF_ERR_BAD_MAGIC;
    if (e[4] != 1) return ELF_ERR_BAD_CLASS;  // ELFCLASS32
    if (e[5] != 1) return ELF_ERR_BAD_DATA;   // ELFDATA2LSB

    unsigned short e_type    = read_u16(e + 16);
    unsigned short e_machine = read_u16(e + 18);
    unsigned int   e_entry   = read_u32(e + 24);
    unsigned int   e_phoff   = read_u32(e + 28);
    unsigned short e_phnum   = read_u16(e + 44);

    if (e_type != ET_EXEC)  return ELF_ERR_BAD_TYPE;
    if (e_machine != EM_386) return ELF_ERR_BAD_MACHINE;
    if (e_phnum == 0 || e_phnum > ELF_MAX_PHNUM) return ELF_ERR_BAD_PHNUM;

    // e_phoff + e_phnum*ELF_PHDR_SIZE не должно выйти за staging_size -
    // иначе мы прочитаем мусор за пределами того, что реально было
    // прочитано с диска.
    unsigned int phtab_bytes = (unsigned int)e_phnum * ELF_PHDR_SIZE;
    if (e_phoff > staging_size || phtab_bytes > staging_size - e_phoff)
        return ELF_ERR_TRUNCATED;

    unsigned int max_end = 0;
    int found_load = 0;

    for (unsigned short i = 0; i < e_phnum; i++) {
        unsigned char* ph = staging_buf + e_phoff + (unsigned int)i * ELF_PHDR_SIZE;
        unsigned int p_type = read_u32(ph + 0);
        if (p_type != PT_LOAD) continue;

        unsigned int p_offset = read_u32(ph + 4);
        unsigned int p_vaddr  = read_u32(ph + 8);
        unsigned int p_filesz = read_u32(ph + 16);
        unsigned int p_memsz  = read_u32(ph + 20);

        // memsz < filesz - всегда некорректный ELF (сегмент не может
        // "сжиматься" в памяти относительно файла).
        if (p_memsz < p_filesz) return ELF_ERR_BOUNDS;

        // Сегмент должен лежать целиком внутри того, что реально было
        // прочитано в staging_buf.
        if (p_offset > staging_size || p_filesz > staging_size - p_offset)
            return ELF_ERR_TRUNCATED;

        // p_vaddr не ниже окна задачи, и весь сегмент (vaddr+memsz) не
        // выходит за max_segment_end_offset - это и не даёт сегменту
        // залезть в зону argv (вызывающая сторона передаёт
        // USER_ARGS_OFFSET) или вообще за пределы окна задачи.
        if (p_vaddr < load_base_vaddr) return ELF_ERR_BOUNDS;
        unsigned int seg_off = p_vaddr - load_base_vaddr;
        if (seg_off > max_segment_end_offset ||
            p_memsz > max_segment_end_offset - seg_off)
            return ELF_ERR_BOUNDS;

        unsigned char* dst = phys_slot_base + seg_off;
        unsigned char* src = staging_buf + p_offset;
        for (unsigned int b = 0; b < p_filesz; b++) dst[b] = src[b];
        for (unsigned int b = p_filesz; b < p_memsz; b++) dst[b] = 0;

        unsigned int seg_end = seg_off + p_memsz;
        if (seg_end > max_end) max_end = seg_end;
        found_load = 1;
    }

    if (!found_load) return ELF_ERR_NOT_LOAD;

    // Точка входа тоже должна указывать внутрь того же окна, а не
    // куда попало (испорченный/враждебный e_entry иначе мог бы запустить
    // ring3-код за пределами легального диапазона программы).
    if (e_entry < load_base_vaddr ||
        e_entry - load_base_vaddr >= max_segment_end_offset)
        return ELF_ERR_BOUNDS;

    out->entry = e_entry;
    out->max_vaddr_end = (max_end + 15u) & ~15u;
    return ELF_OK;
}
