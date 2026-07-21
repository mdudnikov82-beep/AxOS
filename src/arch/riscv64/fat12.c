#include "fat12.h"
#include "virtio_blk.h"
#include "pmem.h"
#include "drivers/uart.h"

// FAT12-драйвер для AxOS/RV64.
// Кешируем весь том в RAM (2048 сект. × 512 = 1 МБ).
// I/O через virtio_blk — меняем только два места по сравнению с x86-версией.

#define FAT12_TOTAL_SECTORS 2048

// ---- Структуры BPB и директории (packed, идентичны x86-версии) ----
struct fat12_bpb {
    unsigned char  jmp[3];
    char           oem[8];
    unsigned short bytes_per_sector;
    unsigned char  sectors_per_cluster;
    unsigned short reserved_sectors;
    unsigned char  num_fats;
    unsigned short root_entries;
    unsigned short total_sectors;
    unsigned char  media_descriptor;
    unsigned short sectors_per_fat;
} __attribute__((packed));

struct fat12_dir_entry {
    char           name[8];
    char           ext[3];
    unsigned char  attr;
    unsigned char  reserved[10];
    unsigned short time;
    unsigned short date;
    unsigned short start_cluster;
    unsigned int   file_size;
} __attribute__((packed));

// ---- Состояние драйвера ----
static unsigned char        *ram   = 0;   // RAM-кэш всего тома (1 МБ)
static struct fat12_bpb     *bpb   = 0;
static int                   ready = 0;

// ---- Вспомогательные функции ----
static void put_dec(unsigned long v) {
    char b[20]; int i = 0;
    if (!v) { uart_putc('0'); return; }
    while (v) { b[i++] = '0' + (v % 10); v /= 10; }
    for (int j = i-1; j >= 0; j--) uart_putc(b[j]);
}

static int mem_eq(const char *a, const char *b, int n) {
    for (int i = 0; i < n; i++) if (a[i] != b[i]) return 0;
    return 1;
}

static void parse_83(const char *in, char *name, char *ext) {
    for (int i = 0; i < 8; i++) name[i] = ' ';
    for (int i = 0; i < 3; i++) ext[i]  = ' ';
    int i = 0, ni = 0;
    while (in[i] && in[i] != '.' && ni < 8) {
        char c = in[i]; if (c >= 'a' && c <= 'z') c -= 32;
        name[ni++] = c; i++;
    }
    if (in[i] == '.') {
        i++; int ei = 0;
        while (in[i] && ei < 3) {
            char c = in[i]; if (c >= 'a' && c <= 'z') c -= 32;
            ext[ei++] = c; i++;
        }
    }
}

// ---- FAT-операции ----
static unsigned char *fat_ptr(void) {
    return ram + (unsigned int)bpb->reserved_sectors * bpb->bytes_per_sector;
}

static unsigned int fat12_root_dir_offset(void) {
    return ((unsigned int)bpb->reserved_sectors
           + (unsigned int)bpb->num_fats * bpb->sectors_per_fat)
           * bpb->bytes_per_sector;
}

static unsigned int fat12_data_offset(void) {
    unsigned int rds = ((unsigned int)bpb->root_entries * 32) / bpb->bytes_per_sector;
    return fat12_root_dir_offset() + rds * bpb->bytes_per_sector;
}

static unsigned int fat_get(unsigned int cluster) {
    unsigned char *fat = fat_ptr();
    unsigned int off = cluster + cluster / 2;
    unsigned int v = fat[off] | ((unsigned int)fat[off+1] << 8);
    return (cluster & 1) ? (v >> 4) : (v & 0x0FFF);
}

static void fat_set(unsigned int cluster, unsigned int value) {
    unsigned char *fat = fat_ptr();
    unsigned int off = cluster + cluster / 2;
    if (cluster & 1) {
        fat[off]   = (fat[off]   & 0x0F) | ((value & 0x0F) << 4);
        fat[off+1] = (value >> 4) & 0xFF;
    } else {
        fat[off]   = value & 0xFF;
        fat[off+1] = (fat[off+1] & 0xF0) | ((value >> 8) & 0x0F);
    }
}

static unsigned int total_clusters(void) {
    unsigned int rds = ((unsigned int)bpb->root_entries * 32) / bpb->bytes_per_sector;
    unsigned int data = bpb->total_sectors - bpb->reserved_sectors
                      - (unsigned int)bpb->num_fats * bpb->sectors_per_fat - rds;
    return data / bpb->sectors_per_cluster;
}

static void free_chain(unsigned int cluster) {
    while (cluster >= 2 && cluster < 0xFF8) {
        unsigned int next = fat_get(cluster);
        fat_set(cluster, 0);
        cluster = next;
    }
}

static unsigned int alloc_chain(unsigned int n) {
    if (!n) return 0;
    unsigned int tc = total_clusters();
    unsigned int first = 0, prev = 0, got = 0;
    for (unsigned int c = 2; c <= tc + 1 && got < n; c++) {
        if (fat_get(c) == 0) {
            if (prev) fat_set(prev, c); else first = c;
            prev = c; got++;
        }
    }
    if (got < n) { if (first) free_chain(first); return 0; }
    fat_set(prev, 0xFFF);
    return first;
}

// ---- Поиск в корневой директории ----
static struct fat12_dir_entry *find_entry(const char *name, const char *ext) {
    struct fat12_dir_entry *entries =
        (struct fat12_dir_entry *)(ram + fat12_root_dir_offset());
    for (int i = 0; i < bpb->root_entries; i++) {
        if (entries[i].name[0] == 0x00) break;
        if ((unsigned char)entries[i].name[0] == 0xE5) continue;
        if (mem_eq(entries[i].name, name, 8) && mem_eq(entries[i].ext, ext, 3))
            return &entries[i];
    }
    return 0;
}

static struct fat12_dir_entry *find_free_entry(void) {
    struct fat12_dir_entry *entries =
        (struct fat12_dir_entry *)(ram + fat12_root_dir_offset());
    for (int i = 0; i < bpb->root_entries; i++) {
        unsigned char f = (unsigned char)entries[i].name[0];
        if (f == 0x00 || f == 0xE5) return &entries[i];
    }
    return 0;
}

// ---- Flush: write a range of sectors back to disk ----
static void fat12_flush_range(unsigned int lba_start, unsigned int lba_end) {
    for (unsigned int lba = lba_start; lba < lba_end && lba < FAT12_TOTAL_SECTORS; lba++) {
        virtio_blk_write(lba, ram + lba * SECTOR_SIZE);
    }
}

// ---- Публичный API ----

int fat12_init(void) {
    if (!virtio_blk_capacity()) return 0;

    // Выделяем 1 МБ RAM (256 страниц по 4 КБ — смежные из bump-аллокатора)
    unsigned int pages = (FAT12_TOTAL_SECTORS * SECTOR_SIZE + PAGE_SIZE - 1) / PAGE_SIZE;
    ram = (unsigned char *)alloc_page();
    if (!ram) { uart_puts("[fat12] OOM\r\n"); return 0; }
    for (unsigned int i = 1; i < pages; i++) {
        if (!alloc_page()) { uart_puts("[fat12] OOM\r\n"); return 0; }
    }

    uart_puts("[fat12] loading ");
    put_dec(FAT12_TOTAL_SECTORS);
    uart_puts(" sectors into RAM...\r\n");

    for (unsigned int lba = 0; lba < FAT12_TOTAL_SECTORS; lba++) {
        if (virtio_blk_read(lba, ram + lba * SECTOR_SIZE) != 0) {
            uart_puts("[fat12] read error at sector ");
            put_dec(lba);
            uart_puts("\r\n");
            ready = 0;
            return 0;
        }
    }

    bpb = (struct fat12_bpb *)ram;
    if (bpb->bytes_per_sector != SECTOR_SIZE) {
        uart_puts("[fat12] bad BPB (bps=");
        put_dec(bpb->bytes_per_sector);
        uart_puts(")\r\n");
        ready = 0;
        return 0;
    }

    ready = 1;
    uart_puts("[fat12] volume ready: ");
    put_dec(bpb->total_sectors);
    uart_puts(" sectors, root_entries=");
    put_dec(bpb->root_entries);
    uart_puts("\r\n");
    return 1;
}

int fat12_is_ready(void) { return ready; }

void fat12_list(void) {
    if (!ready) { uart_puts("[fat12] not ready\r\n"); return; }
    struct fat12_dir_entry *entries =
        (struct fat12_dir_entry *)(ram + fat12_root_dir_offset());
    int count = 0;
    for (int i = 0; i < bpb->root_entries; i++) {
        if (entries[i].name[0] == 0x00) break;
        if ((unsigned char)entries[i].name[0] == 0xE5) continue;
        if (entries[i].attr & 0x08) continue;  // volume label

        // Печатаем имя в формате 8.3
        char buf[13]; int p = 0;
        for (int j = 0; j < 8 && entries[i].name[j] != ' '; j++)
            buf[p++] = entries[i].name[j];
        if (entries[i].ext[0] != ' ') {
            buf[p++] = '.';
            for (int j = 0; j < 3 && entries[i].ext[j] != ' '; j++)
                buf[p++] = entries[i].ext[j];
        }
        buf[p] = '\0';

        uart_puts("  ");
        uart_puts(buf);
        uart_puts("  (");
        put_dec(entries[i].file_size);
        uart_puts(" bytes)\r\n");
        count++;
    }
    if (!count) uart_puts("  (empty)\r\n");
}

unsigned int fat12_load(char *filename, unsigned char *buffer, unsigned int max_size) {
    if (!ready) return 0;
    char name[8], ext[3];
    parse_83(filename, name, ext);
    struct fat12_dir_entry *entry = find_entry(name, ext);
    if (!entry) return 0;

    unsigned int csz = (unsigned int)bpb->sectors_per_cluster * bpb->bytes_per_sector;
    unsigned char *data_area = ram + fat12_data_offset();
    unsigned int cluster = entry->start_cluster;
    unsigned int rem = entry->file_size, total_read = 0;

    while (cluster >= 2 && cluster < 0xFF8 && rem > 0 && total_read < max_size) {
        unsigned int chunk = csz;
        if (chunk > rem) chunk = rem;
        if (chunk > max_size - total_read) chunk = max_size - total_read;
        unsigned char *src = data_area + (cluster - 2) * csz;
        for (unsigned int i = 0; i < chunk; i++)
            buffer[total_read + i] = src[i];
        total_read += chunk;
        rem -= chunk;
        cluster = fat_get(cluster);
    }
    return total_read;
}

/* Write ordering is deliberately "data before metadata", the standard
 * lighter alternative to full journaling: allocate a FRESH cluster
 * chain (old_cluster's clusters are still marked used in the FAT at
 * this point, so alloc_chain() can't land on them), write + flush its
 * data FIRST, only THEN free the old chain and flush the FAT, and
 * commit the directory entry LAST - the smallest possible final write,
 * with every cluster it could reference already durably on disk. A
 * crash at any point before that final flush leaves the OLD file (if
 * any) completely intact rather than a directory entry pointing at
 * not-yet-written data. Found this matters the hard way: the previous
 * FAT-then-dir-then-data order let many repeated QEMU force-kills
 * during one heavy live-testing session (dozens of boots, each
 * rewriting BOOT.LOG) garble root-directory entries after enough
 * repetitions - see project_axsnake_highscore memory for the repro. */
int fat12_write(char *filename, unsigned char *data, unsigned int size) {
    if (!ready) return 0;
    char name[8], ext[3];
    parse_83(filename, name, ext);

    struct fat12_dir_entry *entry = find_entry(name, ext);
    int is_new = !entry;
    if (is_new) {
        entry = find_free_entry();
        if (!entry) return 0;
    }
    unsigned int old_cluster = is_new ? 0 : entry->start_cluster;

    unsigned int fat_start    = bpb->reserved_sectors;
    unsigned int fat_end      = fat_start + (unsigned int)bpb->num_fats * bpb->sectors_per_fat;
    unsigned int root_start   = fat_end;
    unsigned int root_sectors = ((unsigned int)bpb->root_entries * 32) / bpb->bytes_per_sector;
    unsigned int root_end     = root_start + root_sectors;

    unsigned int new_cluster = 0;
    if (size) {
        unsigned int csz = (unsigned int)bpb->sectors_per_cluster * bpb->bytes_per_sector;
        unsigned int nc = (size + csz - 1) / csz;
        new_cluster = alloc_chain(nc);
        if (!new_cluster) return 0;

        unsigned char *data_area = ram + fat12_data_offset();
        unsigned int cluster = new_cluster, written = 0;
        while (cluster >= 2 && cluster < 0xFF8 && written < size) {
            unsigned int chunk = csz;
            if (chunk > size - written) chunk = size - written;
            unsigned char *dst = data_area + (cluster - 2) * csz;
            for (unsigned int i = 0; i < chunk; i++) dst[i] = data[written + i];
            written += chunk;
            cluster = fat_get(cluster);
        }

        /* Step 1: new data, durably on disk before anything references it. */
        unsigned int cl = new_cluster;
        while (cl >= 2 && cl < 0xFF8) {
            unsigned int data_lba = root_end + (cl - 2) * bpb->sectors_per_cluster;
            fat12_flush_range(data_lba, data_lba + bpb->sectors_per_cluster);
            cl = fat_get(cl);
        }
    }

    /* Step 2: free the old chain (now that the new one's data is safe)
     * and flush the FAT once, covering both the new chain's entries
     * (already set by alloc_chain()) and the old chain's now-freed ones. */
    if (old_cluster) free_chain(old_cluster);
    fat12_flush_range(fat_start, fat_end);

    /* Step 3: commit - the directory entry is the last, smallest write. */
    if (is_new) {
        for (int i = 0; i < 8; i++) entry->name[i] = name[i];
        for (int i = 0; i < 3; i++) entry->ext[i]  = ext[i];
        entry->attr = 0x20;
        for (int i = 0; i < 10; i++) entry->reserved[i] = 0;
        entry->time = 0; entry->date = 0;
    }
    entry->start_cluster = (unsigned short)new_cluster;
    entry->file_size = size;
    fat12_flush_range(root_start, root_end);

    return 1;
}

int fat12_readdir(unsigned int index, char *name_buf, unsigned int *size_out) {
    if (!ready) return 0;
    struct fat12_dir_entry *entries =
        (struct fat12_dir_entry *)(ram + fat12_root_dir_offset());
    unsigned int count = 0;
    for (int i = 0; i < bpb->root_entries; i++) {
        if (entries[i].name[0] == 0x00) break;
        if ((unsigned char)entries[i].name[0] == 0xE5) continue;
        if (entries[i].attr & 0x08) continue; /* volume label */
        if (count == index) {
            int p = 0;
            for (int j = 0; j < 8 && entries[i].name[j] != ' '; j++)
                name_buf[p++] = entries[i].name[j];
            if (entries[i].ext[0] != ' ') {
                name_buf[p++] = '.';
                for (int j = 0; j < 3 && entries[i].ext[j] != ' '; j++)
                    name_buf[p++] = entries[i].ext[j];
            }
            name_buf[p] = '\0';
            if (size_out) *size_out = entries[i].file_size;
            return 1;
        }
        count++;
    }
    return 0;
}

int fat12_delete(char *filename) {
    if (!ready) return 0;
    char name[8], ext[3];
    parse_83(filename, name, ext);
    struct fat12_dir_entry *entry = find_entry(name, ext);
    if (!entry) return -1;
    if (entry->start_cluster) free_chain(entry->start_cluster);
    entry->name[0] = (char)0xE5;
    {
        unsigned int fat_start  = bpb->reserved_sectors;
        unsigned int fat_end    = fat_start + (unsigned int)bpb->num_fats * bpb->sectors_per_fat;
        unsigned int root_start = fat_end;
        unsigned int root_end   = root_start + ((unsigned int)bpb->root_entries * 32) / bpb->bytes_per_sector;
        fat12_flush_range(fat_start, fat_end);
        fat12_flush_range(root_start, root_end);
    }
    return 1;
}
