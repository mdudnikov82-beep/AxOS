#!/usr/bin/env python3
# Оборачивает плоский бинарник пользовательской программы (выход
# существующего "objcopy -O binary" в build.bat) в минимальный, полностью
# самодельный ELF32 (ET_EXEC, один PT_LOAD + опциональный PT_AXOS_RELOC).
#
# Линкер (w64devkit/bin/ld.exe) поддерживает только PE-формат вывода.
# Конвертация через "objcopy -O elf32-i386" даёт битый p_vaddr (проверено
# вручную - 0xffd00000 вместо 0x100000), поэтому ELF-заголовок пишем сами.
#
# Code ASLR: если рядом с <input.bin> есть <input.exe>, парсим из него
# секцию .reloc (PE base relocation table) и добавляем в ELF кастомный
# сегмент PT_AXOS_RELOC с таблицей смещений в плоском бинарнике - ядро
# применяет их при загрузке, прибавляя случайный delta к каждому
# абсолютному адресу в коде (elf.c: elf_load с ASLR-поддержкой).
#
# Использование: python make_elf.py <input.bin> <output.elf>
# PE-файл ищется автоматически как input.exe рядом с input.bin.

import struct
import sys
import os

LOAD_ADDR = 0x100000

EHDR_SIZE = 52
PHDR_SIZE = 32

ET_EXEC = 2
EM_386  = 3
PT_LOAD = 1
PF_R = 4
PF_W = 2
PF_X = 1

PT_AXOS_RELOC = 0x6A584953
PT_AXOS_WX    = 0x6A584955  # W^X boundary: один uint32 = flat offset первого writable байта

IMAGE_SCN_MEM_EXECUTE = 0x20000000
IMAGE_SCN_MEM_WRITE   = 0x80000000


def find_wx_boundary(pe_bytes, flat_size):
    """Возвращает flat offset первой записываемой секции (.bss), 0 если не найдено.
    Определяется по флагу IMAGE_SCN_MEM_WRITE без IMAGE_SCN_MEM_EXECUTE."""
    if len(pe_bytes) < 20:
        return 0
    machine = struct.unpack_from('<H', pe_bytes, 0)[0]
    if machine != 0x014C:
        return 0
    num_sections  = struct.unpack_from('<H', pe_bytes, 2)[0]
    optional_size = struct.unpack_from('<H', pe_bytes, 16)[0]
    opt_offset = 20
    if optional_size < 2 or opt_offset + optional_size > len(pe_bytes):
        return 0
    magic = struct.unpack_from('<H', pe_bytes, opt_offset)[0]
    if magic != 0x010B:
        return 0
    section_table_off = opt_offset + optional_size

    # Первый проход: минимальный VA (база плоского бинарника).
    lowest_va = 0xFFFFFFFF
    for i in range(num_sections):
        off = section_table_off + i * 40
        if off + 40 > len(pe_bytes):
            break
        sec_va = struct.unpack_from('<I', pe_bytes, off + 12)[0]
        if sec_va < lowest_va:
            lowest_va = sec_va

    # Второй проход: найти наименьший flat offset секции с W (без X).
    boundary = None
    for i in range(num_sections):
        off = section_table_off + i * 40
        if off + 40 > len(pe_bytes):
            break
        sec_va    = struct.unpack_from('<I', pe_bytes, off + 12)[0]
        sec_chars = struct.unpack_from('<I', pe_bytes, off + 36)[0]
        if (sec_chars & IMAGE_SCN_MEM_WRITE) and not (sec_chars & IMAGE_SCN_MEM_EXECUTE):
            flat_off = (sec_va - lowest_va) & 0xFFFFFFFF
            if flat_off < flat_size:
                if boundary is None or flat_off < boundary:
                    boundary = flat_off

    return boundary if boundary is not None else 0


def parse_pe_relocations(pe_bytes, flat_size):
    # w64devkit ld -m i386pe выдаёт сырой COFF без DOS MZ-заголовка.
    # COFF header начинается на байте 0, Machine(0:2) = 0x014C (i386).
    # DataDirectory[5] (BaseReloc) пуст, но секция '.reloc' присутствует.
    # Ищем '.reloc' по имени напрямую в таблице секций.
    #
    # IMAGE_BASE=0x400000 (PE default), VMA .text=0x100000 (линкер-скрипт).
    # VirtualAddress секций = VMA - IMAGE_BASE = 0xFFD00000 (uint32 wrap).
    # flat_off = (RVA - lowest_section_VA) & 0xFFFFFFFF - корректно при wrap.
    if len(pe_bytes) < 20:
        return []

    machine = struct.unpack_from('<H', pe_bytes, 0)[0]
    if machine != 0x014C:
        return []

    num_sections  = struct.unpack_from('<H', pe_bytes, 2)[0]
    optional_size = struct.unpack_from('<H', pe_bytes, 16)[0]

    opt_offset = 20
    if optional_size < 2 or opt_offset + optional_size > len(pe_bytes):
        return []

    magic = struct.unpack_from('<H', pe_bytes, opt_offset)[0]
    if magic != 0x010B:
        return []

    section_table_off = opt_offset + optional_size
    lowest_va  = 0xFFFFFFFF
    reloc_foff = 0
    reloc_fsize = 0

    for i in range(num_sections):
        off = section_table_off + i * 40
        if off + 40 > len(pe_bytes):
            break
        sec_va   = struct.unpack_from('<I', pe_bytes, off + 12)[0]
        sec_foff = struct.unpack_from('<I', pe_bytes, off + 20)[0]
        sec_fsz  = struct.unpack_from('<I', pe_bytes, off + 16)[0]
        sec_name = pe_bytes[off:off + 8].rstrip(b'\x00')

        if sec_va < lowest_va:
            lowest_va = sec_va

        if sec_name == b'.reloc' and sec_foff != 0 and sec_fsz != 0:
            reloc_foff  = sec_foff
            reloc_fsize = sec_fsz

    if reloc_foff == 0 or reloc_foff + reloc_fsize > len(pe_bytes):
        return []

    reloc_data = pe_bytes[reloc_foff:reloc_foff + reloc_fsize]

    offsets = []
    pos = 0
    while pos + 8 <= len(reloc_data):
        block_va   = struct.unpack_from('<I', reloc_data, pos)[0]
        block_size = struct.unpack_from('<I', reloc_data, pos + 4)[0]
        if block_size < 8:
            break

        num_entries = (block_size - 8) // 2
        for j in range(num_entries):
            entry = struct.unpack_from('<H', reloc_data, pos + 8 + j * 2)[0]
            if (entry >> 12) != 3:
                continue
            rva = (block_va + (entry & 0x0FFF)) & 0xFFFFFFFF
            flat_off = (rva - lowest_va) & 0xFFFFFFFF
            if flat_off + 4 <= flat_size:
                offsets.append(flat_off)

        pos += block_size

    return offsets


def build_elf(flat_bin, reloc_offsets, wx_boundary=0):
    reloc_count = len(reloc_offsets)
    has_reloc   = reloc_count > 0
    has_wx      = wx_boundary > 0
    e_phnum     = 1 + (1 if has_reloc else 0) + (1 if has_wx else 0)

    reloc_table  = struct.pack('<I', reloc_count)
    reloc_table += b''.join(struct.pack('<I', o) for o in reloc_offsets)
    wx_table     = struct.pack('<I', wx_boundary) if has_wx else b''

    # Компоновка файла: [ELF header] [PHDRs] [reloc data] [wx data] [flat binary]
    headers_size = EHDR_SIZE + PHDR_SIZE * e_phnum
    reloc_foff   = headers_size
    wx_foff      = reloc_foff + (len(reloc_table) if has_reloc else 0)
    code_foff    = wx_foff + len(wx_table)

    filesz = memsz = len(flat_bin)

    ehdr = bytearray(EHDR_SIZE)
    ehdr[0:4] = b'\x7fELF'
    ehdr[4] = 1; ehdr[5] = 1; ehdr[6] = 1
    struct.pack_into('<HHIIIIIHHHHHH', ehdr, 16,
        ET_EXEC, EM_386, 1, LOAD_ADDR, EHDR_SIZE, 0, 0,
        EHDR_SIZE, PHDR_SIZE, e_phnum, 0, 0, 0)

    def make_phdr(p_type, p_offset, p_vaddr, p_filesz, p_flags, p_align):
        ph = bytearray(PHDR_SIZE)
        struct.pack_into('<IIIIIIII', ph, 0,
            p_type, p_offset, p_vaddr, p_vaddr, p_filesz, p_filesz, p_flags, p_align)
        return bytes(ph)

    result = bytes(ehdr)
    result += make_phdr(PT_LOAD,       code_foff, LOAD_ADDR, filesz, PF_R|PF_W|PF_X, 0x1000)
    if has_reloc:
        result += make_phdr(PT_AXOS_RELOC, reloc_foff, 0, len(reloc_table), 0, 4)
    if has_wx:
        result += make_phdr(PT_AXOS_WX,    wx_foff,    0, 4,                0, 4)
    if has_reloc:
        result += reloc_table
    result += wx_table
    result += flat_bin
    return result


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: make_elf.py <input.bin> <output.elf>")

    bin_path = sys.argv[1]
    out_path = sys.argv[2]

    with open(bin_path, 'rb') as f:
        flat_bin = f.read()

    pe_path = os.path.splitext(bin_path)[0] + '.exe'
    reloc_offsets = []
    wx_boundary   = 0
    if os.path.exists(pe_path):
        with open(pe_path, 'rb') as f:
            pe_bytes = f.read()
        reloc_offsets = parse_pe_relocations(pe_bytes, len(flat_bin))
        wx_boundary   = find_wx_boundary(pe_bytes, len(flat_bin))
        if reloc_offsets:
            print(f"  code ASLR: {len(reloc_offsets)} relocations from {os.path.basename(pe_path)}")
        else:
            print(f"  code ASLR: no relocations found in {os.path.basename(pe_path)}")
        if wx_boundary:
            print(f"  W^X boundary: flat offset 0x{wx_boundary:X} (data starts at page {wx_boundary // 0x1000})")

    with open(out_path, 'wb') as f:
        f.write(build_elf(flat_bin, reloc_offsets, wx_boundary))


if __name__ == '__main__':
    main()
