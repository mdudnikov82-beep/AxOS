#!/usr/bin/env python3
# Оборачивает плоский бинарник пользовательской программы (выход
# существующего "objcopy -O binary" в build.bat) в минимальный, полностью
# самодельный ELF32 (ET_EXEC, ровно один PT_LOAD). Линкер этого проекта
# (w64devkit/bin/ld.exe) поддерживает только PE-формат вывода - emulation
# elf_i386 в нём отсутствует. Конвертация уже слинкованного PE-бинарника
# через "objcopy -O elf32-i386" тоже не подходит: на практике она даёт
# корректные e_entry/magic/class/machine, но БИТЫЙ p_vaddr в Program
# Header (проверено вручную - struct.unpack по сырым байтам заголовка
# показал 0xffd00000 вместо ожидаемых ~0x100000) - известный класс багов
# binutils BFD при конвертации PE->ELF с нестандартным image base.
# Поэтому пишем заголовок сами - корректность тогда тривиальна, как и у
# tools/make_fat12.py, который точно так же вручную собирает FAT12.
#
# Использование: python make_elf.py <input.bin> <output.elf>

import struct
import sys

# Должно совпадать с USER_PROGRAM_BASE/USER_WINDOW_BASE в src/kernel/
# kernel.c/paging.h и с ". = 0x100000;" в src/user/user.ld.
LOAD_ADDR = 0x100000

EHDR_SIZE = 52
PHDR_SIZE = 32

ET_EXEC = 2
EM_386 = 3
PT_LOAD = 1
PF_R = 4
PF_W = 2
PF_X = 1


def build_elf(flat_bin: bytes) -> bytes:
    filesz = memsz = len(flat_bin)
    p_offset = EHDR_SIZE + PHDR_SIZE  # 84 - сразу после Ehdr+Phdr

    ehdr = bytearray(EHDR_SIZE)
    ehdr[0:4] = b'\x7fELF'
    ehdr[4] = 1  # EI_CLASS = ELFCLASS32
    ehdr[5] = 1  # EI_DATA = ELFDATA2LSB
    ehdr[6] = 1  # EI_VERSION = EV_CURRENT
    # ehdr[7:16] - EI_PAD, остаётся нулём
    struct.pack_into(
        '<HHIIIIIHHHHHH', ehdr, 16,
        ET_EXEC,        # e_type
        EM_386,         # e_machine
        1,              # e_version
        LOAD_ADDR,      # e_entry
        EHDR_SIZE,      # e_phoff - таблица Program Header сразу после Ehdr
        0,              # e_shoff - секций нет, грузим только по Program Header
        0,              # e_flags
        EHDR_SIZE,      # e_ehsize
        PHDR_SIZE,      # e_phentsize
        1,              # e_phnum - ровно один PT_LOAD
        0,              # e_shentsize
        0,              # e_shnum
        0,              # e_shstrndx
    )

    phdr = bytearray(PHDR_SIZE)
    struct.pack_into(
        '<IIIIIIII', phdr, 0,
        PT_LOAD,                # p_type
        p_offset,               # p_offset
        LOAD_ADDR,              # p_vaddr
        LOAD_ADDR,              # p_paddr
        filesz,                 # p_filesz
        memsz,                  # p_memsz - сегодня == filesz (.bss уже
                                 # зашит нулями в плоский бинарник самим
                                 # objcopy); ядро всё равно зануляет
                                 # [filesz, memsz) для общности
        PF_R | PF_W | PF_X,     # p_flags
        0x1000,                 # p_align
    )

    return bytes(ehdr) + bytes(phdr) + flat_bin


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: make_elf.py <input.bin> <output.elf>")

    with open(sys.argv[1], 'rb') as f:
        flat_bin = f.read()

    with open(sys.argv[2], 'wb') as f:
        f.write(build_elf(flat_bin))


if __name__ == '__main__':
    main()
