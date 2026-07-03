// =================================================================
//  Минимальный ELF32-загрузчик пользовательских программ с code ASLR
// =================================================================
//
// Понимает только то подмножество ELF, которое сама ОС производит
// (tools/make_elf.py). Поддерживает два типа сегментов:
//
//  PT_LOAD         - код программы (загружается в слот + delta)
//  PT_AXOS_RELOC   - таблица смещений для code ASLR (тип 0x6A584953)
//
// Code ASLR: если ELF содержит PT_AXOS_RELOC, загрузчик:
//  1) выбирает случайный delta (кратный 16, от 0 до свободного места)
//  2) копирует код в phys_slot_base + delta (вместо phys_slot_base + 0)
//  3) патчит каждый абсолютный адрес: *(u32*)(phys_slot_base+delta+off) += delta
//  4) возвращает entry = e_entry + delta, aslr_delta = delta
//
// Энтропия: ~(max_segment_end_offset - code_size) / 16 позиций.
// Для hello (27KB) при 63KB окне: ~2300 позиций -> ~11 бит.

#include "elf.h"
#include "tasking.h"  // aslr_next_random()
#include "paging.h"   // smap_allow / smap_deny

#define ELF_MAX_PHNUM 5

#define ELF_EHDR_SIZE 52
#define ELF_PHDR_SIZE 32

#define PT_LOAD       1
#define PT_AXOS_RELOC 0x6A584953u
#define PT_AXOS_WX    0x6A584955u  // W^X boundary: один uint32 = flat offset начала .bss
#define ET_EXEC       2
#define EM_386        3

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
    if (e[4] != 1) return ELF_ERR_BAD_CLASS;
    if (e[5] != 1) return ELF_ERR_BAD_DATA;

    unsigned short e_type    = read_u16(e + 16);
    unsigned short e_machine = read_u16(e + 18);
    unsigned int   e_entry   = read_u32(e + 24);
    unsigned int   e_phoff   = read_u32(e + 28);
    unsigned short e_phnum   = read_u16(e + 44);

    if (e_type != ET_EXEC)   return ELF_ERR_BAD_TYPE;
    if (e_machine != EM_386) return ELF_ERR_BAD_MACHINE;
    if (e_phnum == 0 || e_phnum > ELF_MAX_PHNUM) return ELF_ERR_BAD_PHNUM;

    unsigned int phtab_bytes = (unsigned int)e_phnum * ELF_PHDR_SIZE;
    if (e_phoff > staging_size || phtab_bytes > staging_size - e_phoff)
        return ELF_ERR_TRUNCATED;

    // ---------------------------------------------------------------
    // Проход 1: найти PT_AXOS_RELOC и суммарный размер кода без delta.
    // ---------------------------------------------------------------
    unsigned char* reloc_data  = 0;
    unsigned int   reloc_count = 0;
    unsigned int   code_max_end = 0;
    unsigned int   wx_data_off  = 0;  // flat offset начала .bss (0 = нет)
    int found_load = 0;

    for (unsigned short i = 0; i < e_phnum; i++) {
        unsigned char* ph = staging_buf + e_phoff + (unsigned int)i * ELF_PHDR_SIZE;
        unsigned int p_type = read_u32(ph + 0);

        if (p_type == PT_AXOS_RELOC) {
            unsigned int p_offset = read_u32(ph + 4);
            unsigned int p_filesz = read_u32(ph + 16);
            if (p_offset <= staging_size && p_filesz >= 4u &&
                p_filesz <= staging_size - p_offset) {
                reloc_data  = staging_buf + p_offset;
                reloc_count = read_u32(reloc_data);
                if (reloc_count > (p_filesz - 4u) / 4u)
                    reloc_count = 0;
            }
            continue;
        }

        if (p_type == PT_AXOS_WX) {
            unsigned int p_offset = read_u32(ph + 4);
            unsigned int p_filesz = read_u32(ph + 16);
            if (p_offset <= staging_size && p_filesz >= 4u &&
                p_filesz <= staging_size - p_offset) {
                wx_data_off = read_u32(staging_buf + p_offset);
            }
            continue;
        }

        if (p_type != PT_LOAD) continue;

        unsigned int p_vaddr  = read_u32(ph + 8);
        unsigned int p_filesz = read_u32(ph + 16);
        unsigned int p_memsz  = read_u32(ph + 20);

        if (p_memsz < p_filesz) return ELF_ERR_BOUNDS;
        if (p_vaddr < load_base_vaddr) return ELF_ERR_BOUNDS;

        unsigned int seg_off = p_vaddr - load_base_vaddr;
        if (seg_off > max_segment_end_offset ||
            p_memsz > max_segment_end_offset - seg_off)
            return ELF_ERR_BOUNDS;

        unsigned int seg_end = seg_off + p_memsz;
        if (seg_end > code_max_end) code_max_end = seg_end;
        found_load = 1;
    }

    if (!found_load) return ELF_ERR_NOT_LOAD;

    // ---------------------------------------------------------------
    // Вычисляем ASLR delta (кратна странице; ограничена свободным местом).
    // delta выбирается так, чтобы (delta + wx_data_off) % PAGE_SIZE == 0 —
    // тогда граница code/data всегда совпадает с границей страницы.
    // ---------------------------------------------------------------
    unsigned int delta = 0;
    if (reloc_count > 0 && code_max_end < max_segment_end_offset) {
        const unsigned int PAGE = 0x1000u;
        // Сколько нужно добавить к delta, чтобы (delta+wx_data_off) % PAGE == 0
        unsigned int align_fix = 0;
        if (wx_data_off > 0) {
            unsigned int mod = wx_data_off & (PAGE - 1u);
            if (mod != 0) align_fix = PAGE - mod;
        }
        unsigned int available = max_segment_end_offset - code_max_end;
        if (available > align_fix) {
            unsigned int slots = (available - align_fix) / PAGE;
            delta = align_fix + (slots > 0 ? (aslr_next_random() % slots) * PAGE : 0u);
        }
    }

    // ---------------------------------------------------------------
    // Проход 2: копировать PT_LOAD со смещением delta.
    // ---------------------------------------------------------------
    unsigned int max_end = 0;

    for (unsigned short i = 0; i < e_phnum; i++) {
        unsigned char* ph = staging_buf + e_phoff + (unsigned int)i * ELF_PHDR_SIZE;
        unsigned int p_type = read_u32(ph + 0);
        if (p_type != PT_LOAD) continue;

        unsigned int p_offset = read_u32(ph + 4);
        unsigned int p_vaddr  = read_u32(ph + 8);
        unsigned int p_filesz = read_u32(ph + 16);
        unsigned int p_memsz  = read_u32(ph + 20);

        if (p_offset > staging_size || p_filesz > staging_size - p_offset)
            return ELF_ERR_TRUNCATED;

        unsigned int seg_off   = p_vaddr - load_base_vaddr;
        unsigned int seg_off_d = seg_off + delta;

        if (seg_off_d > max_segment_end_offset ||
            p_memsz > max_segment_end_offset - seg_off_d)
            return ELF_ERR_BOUNDS;

        unsigned char* dst = phys_slot_base + seg_off_d;
        unsigned char* src = staging_buf + p_offset;
        for (unsigned int b = 0; b < p_filesz; b++) dst[b] = src[b];
        for (unsigned int b = p_filesz; b < p_memsz; b++) dst[b] = 0;

        unsigned int seg_end = seg_off_d + p_memsz;
        if (seg_end > max_end) max_end = seg_end;
    }

    // ---------------------------------------------------------------
    // Применяем релокации: каждый 32-битный абсолютный адрес += delta.
    // off - смещение в плоском бинарнике (относительно начала PT_LOAD).
    // ---------------------------------------------------------------
    if (delta > 0 && reloc_count > 0) {
        unsigned char* offsets_ptr = reloc_data + 4;
        for (unsigned int i = 0; i < reloc_count; i++) {
            unsigned int off = read_u32(offsets_ptr + i * 4u);
            if (off + 4u <= code_max_end) {
                unsigned int* patch = (unsigned int*)(phys_slot_base + delta + off);
                *patch += delta;
            }
        }
    }

    unsigned int entry_d = e_entry + delta;
    if (entry_d < load_base_vaddr ||
        entry_d - load_base_vaddr >= max_segment_end_offset)
        return ELF_ERR_BOUNDS;

    out->entry          = entry_d;
    out->max_vaddr_end  = (max_end + 15u) & ~15u;
    out->aslr_delta     = delta;
    out->wx_data_offset = wx_data_off;
    return ELF_OK;
}
