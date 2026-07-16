#!/usr/bin/env python3
"""
Конвертирует один или несколько .bmp файлов в C-заголовок с сырыми
байтами файла в виде static const массивов - для gfx_shell.c (x86).
Иконки рабочего стола встраиваются прямо в бинарник на этапе сборки,
а не читаются из файла как на RISC-V-стороне (см. src/user/rv64/bmp.h)
- этот путь проще и не требует рантайм-доступа к диску специально ради
маленьких статичных значков, даже несмотря на то что с этой сессии
gfx_shell.c умеет читать FAT12 read-only для другой фичи (AxFiles).

Использование:
    python tools/bmp_to_c.py <output.h> <file1.bmp> <name1> [<file2.bmp> <name2> ...]

Каждая пара (file, name) даёт в выходном заголовке:
    static const unsigned char <name>_data[] = { ... };
    static const unsigned int  <name>_size = N;

Декодирует их src/kernel/bmp.h (тот же по формату декодер, что и на
RISC-V-стороне, только читает готовый массив в памяти, а не файл).
"""
import sys


def main():
    if len(sys.argv) < 4 or (len(sys.argv) - 2) % 2 != 0:
        print("usage: bmp_to_c.py <output.h> <file1.bmp> <name1> [<file2.bmp> <name2> ...]")
        return 1

    out_path = sys.argv[1]
    pairs = sys.argv[2:]

    lines = ["#pragma once", "", "/* Автосгенерировано tools/bmp_to_c.py - не редактировать руками. */", ""]

    for i in range(0, len(pairs), 2):
        bmp_path, name = pairs[i], pairs[i + 1]
        with open(bmp_path, "rb") as f:
            data = f.read()

        lines.append(f"static const unsigned char {name}_data[] = {{")
        for off in range(0, len(data), 16):
            chunk = data[off:off + 16]
            lines.append("    " + ",".join(f"0x{b:02X}" for b in chunk) + ",")
        lines.append("};")
        lines.append(f"static const unsigned int {name}_size = {len(data)}u;")
        lines.append("")

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"Wrote {out_path}: {(len(pairs)//2)} icon(s) embedded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
