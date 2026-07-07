#!/usr/bin/env python3
"""
Создаёт FAT12-образ диска для AxOS/RV64.
Параметры идентичны make_fat12.py (TOTAL_SECTORS=2048, 1 МБ).
Файлы берутся из fs/rv64/ (если есть) или создаются тестовые.
Записывается в C:/axos_build/rv64build/disk.img.
"""
import os, struct, sys

SECTOR_SIZE        = 512
TOTAL_SECTORS      = 2048        # 1 МБ — должно совпадать с fat12.c
RESERVED_SECTORS   = 1
NUM_FATS           = 1
ROOT_ENTRIES       = 64
SECTORS_PER_FAT    = 6
SECTORS_PER_CLUSTER= 1
CLUSTER_SIZE       = SECTOR_SIZE * SECTORS_PER_CLUSTER
ROOT_DIR_SECTORS   = (ROOT_ENTRIES * 32) // SECTOR_SIZE
DATA_SECTORS       = TOTAL_SECTORS - RESERVED_SECTORS - NUM_FATS * SECTORS_PER_FAT - ROOT_DIR_SECTORS

def set_fat(fat, idx, val):
    off = (idx * 3) // 2
    if idx % 2 == 0:
        fat[off]   = val & 0xFF
        fat[off+1] = (fat[off+1] & 0xF0) | ((val >> 8) & 0x0F)
    else:
        fat[off]   = (fat[off] & 0x0F) | ((val & 0x0F) << 4)
        fat[off+1] = (val >> 4) & 0xFF

def to_83(fname):
    base, _, ext = fname.upper().partition('.')
    return base[:8].ljust(8).encode(), ext[:3].ljust(3).encode()

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    # Смотрим в <root>/fs/rv64/ (git-дерево) и в C:\axos_build\rv64build\fs\rv64\
    rv64_fs_candidates = [
        os.path.join(root, 'fs', 'rv64'),
        r'C:\axos_build\rv64build\fs\rv64',
    ]
    rv64_fs = next((p for p in rv64_fs_candidates if os.path.isdir(p)), None)
    out = r'C:\axos_build\rv64build\disk.img'

    image = bytearray(SECTOR_SIZE * TOTAL_SECTORS)

    # BPB
    bpb = bytearray(SECTOR_SIZE)
    bpb[0:3] = b'\xEB\x3C\x90'
    bpb[3:11]= b'AXOSRV64'
    struct.pack_into('<H', bpb, 11, SECTOR_SIZE)
    bpb[13]  = SECTORS_PER_CLUSTER
    struct.pack_into('<H', bpb, 14, RESERVED_SECTORS)
    bpb[16]  = NUM_FATS
    struct.pack_into('<H', bpb, 17, ROOT_ENTRIES)
    struct.pack_into('<H', bpb, 19, TOTAL_SECTORS)
    bpb[21]  = 0xF0
    struct.pack_into('<H', bpb, 22, SECTORS_PER_FAT)
    struct.pack_into('<H', bpb, 24, 18)
    struct.pack_into('<H', bpb, 26, 2)
    bpb[38]  = 0x29
    struct.pack_into('<I', bpb, 39, 0xA703B064)  # volume ID
    bpb[43:54] = b'AXOS RV64  '
    bpb[54:62] = b'FAT12   '
    bpb[510] = 0x55; bpb[511] = 0xAA
    image[0:SECTOR_SIZE] = bpb

    fat  = bytearray(SECTOR_SIZE * SECTORS_PER_FAT)
    fat[0] = 0xF0; fat[1] = 0xFF; fat[2] = 0xFF   # FAT[0] и FAT[1] зарезервированы

    root_dir = bytearray(SECTOR_SIZE * ROOT_DIR_SECTORS)
    data_area= bytearray(SECTOR_SIZE * DATA_SECTORS)

    # Файлы: сначала ищем fs/rv64/, потом создаём тестовые
    files = []
    if rv64_fs and os.path.isdir(rv64_fs):
        for fname in sorted(os.listdir(rv64_fs)):
            path = os.path.join(rv64_fs, fname)
            if os.path.isfile(path):
                with open(path, 'rb') as f:
                    files.append((fname, f.read()))
                print(f'  from fs/rv64/{fname}')

    if not files:
        # Тестовые файлы прямо в скрипте
        files = [
            ('HELLO.TXT',  b'Hello from AxOS/RV64 FAT12 filesystem!\nThis file was loaded from VirtIO disk.\n'),
            ('README.TXT', b'AxOS - RISC-V 64-bit OS kernel\nFAT12 driver test - read and write OK\n'),
            ('VERSION.TXT',b'AxOS/RV64 v0.2  FAT12+VirtIO+sv39\n'),
        ]
        print('  using built-in test files')

    next_cluster = 2
    for idx, (fname, data) in enumerate(files):
        nc = max(1, (len(data) + CLUSTER_SIZE - 1) // CLUSTER_SIZE)
        if next_cluster - 2 + nc > DATA_SECTORS:
            sys.exit(f'No space for {fname}')
        start = next_cluster
        for c in range(nc):
            cl = next_cluster + c
            chunk = data[c*CLUSTER_SIZE:(c+1)*CLUSTER_SIZE]
            base  = (cl - 2) * CLUSTER_SIZE
            data_area[base:base+len(chunk)] = chunk
            set_fat(fat, cl, 0xFFF if c == nc-1 else cl+1)
        next_cluster += nc

        n83, e83 = to_83(fname)
        off = idx * 32
        root_dir[off:off+8]  = n83
        root_dir[off+8:off+11] = e83
        root_dir[off+11] = 0x20
        struct.pack_into('<H', root_dir, off+26, start)
        struct.pack_into('<I', root_dir, off+28, len(data))
        print(f'  + {fname}: {len(data)} B, cluster {start}')

    fat_off  = SECTOR_SIZE * RESERVED_SECTORS
    root_off = fat_off + len(fat)
    data_off = root_off + len(root_dir)
    image[fat_off :fat_off +len(fat)]      = fat
    image[root_off:root_off+len(root_dir)] = root_dir
    image[data_off:data_off+len(data_area)]= data_area

    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'wb') as f:
        f.write(image)
    print(f'Written: {out} ({len(image)} bytes, {TOTAL_SECTORS} sectors)')

if __name__ == '__main__':
    main()
