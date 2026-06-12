#!/usr/bin/env python3
# Генерирует образ FAT12-раздела (64 КБ = 128 секторов) из файлов в fs/.
# Этот раздел грузится загрузчиком (boot.asm) в RAM по адресу 0x20000,
# а kernel читает его через src/fs/fat12.c.

import os
import struct
import sys

SECTOR_SIZE = 512
TOTAL_SECTORS = 128
RESERVED_SECTORS = 1
NUM_FATS = 1
ROOT_ENTRIES = 16
SECTORS_PER_FAT = 1
SECTORS_PER_CLUSTER = 1
CLUSTER_SIZE = SECTOR_SIZE * SECTORS_PER_CLUSTER

ROOT_DIR_SECTORS = (ROOT_ENTRIES * 32) // SECTOR_SIZE
DATA_SECTORS = TOTAL_SECTORS - RESERVED_SECTORS - NUM_FATS * SECTORS_PER_FAT - ROOT_DIR_SECTORS


def set_fat_entry(fat, index, value):
    offset = (index * 3) // 2
    if index % 2 == 0:
        fat[offset] = value & 0xFF
        fat[offset + 1] = (fat[offset + 1] & 0xF0) | ((value >> 8) & 0x0F)
    else:
        fat[offset] = (fat[offset] & 0x0F) | ((value & 0x0F) << 4)
        fat[offset + 1] = (value >> 4) & 0xFF


def to_83(fname):
    base, _, ext = fname.upper().partition('.')
    base = base[:8].ljust(8)
    ext = ext[:3].ljust(3)
    return base.encode('ascii'), ext.encode('ascii')


def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    fs_dir = os.path.join(root_dir, 'fs')
    out_path = os.path.join(root_dir, 'build', 'fat12.bin')

    image = bytearray(SECTOR_SIZE * TOTAL_SECTORS)

    # --- Загрузочный сектор / BPB ---
    bpb = bytearray(SECTOR_SIZE)
    bpb[0:3] = b'\xEB\x3C\x90'
    bpb[3:11] = b'AXOS1.0 '
    struct.pack_into('<H', bpb, 11, SECTOR_SIZE)
    bpb[13] = SECTORS_PER_CLUSTER
    struct.pack_into('<H', bpb, 14, RESERVED_SECTORS)
    bpb[16] = NUM_FATS
    struct.pack_into('<H', bpb, 17, ROOT_ENTRIES)
    struct.pack_into('<H', bpb, 19, TOTAL_SECTORS)
    bpb[21] = 0xF0  # media descriptor
    struct.pack_into('<H', bpb, 22, SECTORS_PER_FAT)
    struct.pack_into('<H', bpb, 24, 18)  # sectors per track
    struct.pack_into('<H', bpb, 26, 2)   # heads
    struct.pack_into('<I', bpb, 28, 0)   # hidden sectors
    struct.pack_into('<I', bpb, 32, 0)   # total sectors (32-bit, не используется)
    bpb[36] = 0      # drive number
    bpb[37] = 0      # reserved
    bpb[38] = 0x29   # extended boot signature
    struct.pack_into('<I', bpb, 39, 0x12345678)  # volume id
    bpb[43:54] = b'AXOS FS    '
    bpb[54:62] = b'FAT12   '
    bpb[510] = 0x55
    bpb[511] = 0xAA
    image[0:SECTOR_SIZE] = bpb

    # --- FAT ---
    fat = bytearray(SECTOR_SIZE * SECTORS_PER_FAT)
    fat[0] = 0xF0
    fat[1] = 0xFF
    fat[2] = 0xFF

    # --- Корневая директория и область данных ---
    root_dir_bytes = bytearray(SECTOR_SIZE * ROOT_DIR_SECTORS)
    data_area = bytearray(SECTOR_SIZE * DATA_SECTORS)

    files = []
    if os.path.isdir(fs_dir):
        for fname in sorted(os.listdir(fs_dir)):
            path = os.path.join(fs_dir, fname)
            if os.path.isfile(path):
                with open(path, 'rb') as f:
                    files.append((fname, f.read()))

    if len(files) > ROOT_ENTRIES:
        sys.exit(f"Слишком много файлов в fs/ (максимум {ROOT_ENTRIES})")

    next_cluster = 2
    for idx, (fname, data) in enumerate(files):
        num_clusters = max(1, (len(data) + CLUSTER_SIZE - 1) // CLUSTER_SIZE)
        if next_cluster - 2 + num_clusters > DATA_SECTORS // SECTORS_PER_CLUSTER:
            sys.exit(f"Файл {fname} не помещается в FAT12-раздел (не хватает кластеров)")

        start_cluster = next_cluster
        for c in range(num_clusters):
            cluster = next_cluster + c
            chunk = data[c * CLUSTER_SIZE:(c + 1) * CLUSTER_SIZE]
            base = (cluster - 2) * CLUSTER_SIZE
            data_area[base:base + len(chunk)] = chunk
            if c == num_clusters - 1:
                set_fat_entry(fat, cluster, 0xFFF)  # конец цепочки
            else:
                set_fat_entry(fat, cluster, cluster + 1)
        next_cluster += num_clusters

        name83, ext83 = to_83(fname)
        entry_off = idx * 32
        root_dir_bytes[entry_off:entry_off + 8] = name83
        root_dir_bytes[entry_off + 8:entry_off + 11] = ext83
        root_dir_bytes[entry_off + 11] = 0x20  # атрибут: archive
        struct.pack_into('<H', root_dir_bytes, entry_off + 26, start_cluster)
        struct.pack_into('<I', root_dir_bytes, entry_off + 28, len(data))

        print(f"  + {fname}: {len(data)} bytes, cluster {start_cluster}")

    fat_off = SECTOR_SIZE * RESERVED_SECTORS
    root_off = fat_off + len(fat)
    data_off = root_off + len(root_dir_bytes)

    image[fat_off:fat_off + len(fat)] = fat
    image[root_off:root_off + len(root_dir_bytes)] = root_dir_bytes
    image[data_off:data_off + len(data_area)] = data_area

    assert len(image) == SECTOR_SIZE * TOTAL_SECTORS

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'wb') as f:
        f.write(image)

    print(f"FAT12-раздел создан: {out_path} ({len(image)} bytes)")


if __name__ == '__main__':
    main()
