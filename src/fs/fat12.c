// =================================================================
//  Драйвер FAT12 для AxOS (том на build/disk.img, доступ через IDE)
// =================================================================
//
// fat12_init() читает FAT12-том (128 секторов = 64 КБ, LBA 0-127 на
// build/disk.img) через ide_read_sector в RAM по адресу 0x20000. Дальше
// весь модуль работает с этой RAM-копией как с обычным FAT12-томом: BPB ->
// таблица FAT -> корневая директория -> цепочки кластеров с данными
// файлов - в точности как раньше, когда копию грузил загрузчик из
// встроенного в образ раздела. fat12_write() после успешного изменения
// зовёт fat12_flush(), которая пишет всю RAM-копию обратно через
// ide_write_sector - изменения переживают перезапуск QEMU.

#include "ide.h"

#define FAT12_BASE 0x20000
#define FAT12_TOTAL_SECTORS 128 // 64 КБ / 512 = TOTAL_SECTORS в make_fat12.py

extern void print_string(char* str);
extern void print_uint(unsigned long val);

// Boot Parameter Block FAT12-тома (см. tools/make_fat12.py)
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

// Запись корневой директории (32 байта)
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

static struct fat12_bpb* bpb = (struct fat12_bpb*)FAT12_BASE;

// 1, если fat12_init() успешно загрузил валидный FAT12-том в RAM.
// Публичные функции отказывают, пока том не загружен - иначе поля BPB
// нулевые, и деление на bytes_per_sector/sectors_per_cluster вызовет #DE.
static int fat12_ready = 0;

// Защита от записи. По умолчанию диск заблокирован (только чтение) -
// команды "unlock"/"lock" в shell переключают это состояние через
// fat12_set_locked(). fat12_write() отказывает, пока диск заблокирован.
static int fat12_locked = 1;

void fat12_set_locked(int locked) {
    fat12_locked = locked;
}

int fat12_is_locked() {
    return fat12_locked;
}

int fat12_is_ready() {
    return fat12_ready;
}

// Загружает FAT12-том (LBA 0-127 на build/disk.img) через IDE в RAM по
// FAT12_BASE. Возвращает 1, если все 128 секторов прочитаны и BPB похож на
// валидный FAT12-том (bytes_per_sector == размеру сектора IDE), иначе 0.
int fat12_init() {
    for (unsigned int lba = 0; lba < FAT12_TOTAL_SECTORS; lba++) {
        unsigned char* dst = (unsigned char*)FAT12_BASE + lba * IDE_SECTOR_SIZE;
        if (!ide_read_sector(lba, dst)) {
            fat12_ready = 0;
            return 0;
        }
    }

    if (bpb->bytes_per_sector != IDE_SECTOR_SIZE) {
        fat12_ready = 0;
        return 0;
    }

    fat12_ready = 1;
    return 1;
}

// Записывает RAM-копию FAT12-тома обратно на build/disk.img (LBA 0-127),
// делая изменения от fat12_write() персистентными между запусками QEMU.
static void fat12_flush() {
    for (unsigned int lba = 0; lba < FAT12_TOTAL_SECTORS; lba++) {
        unsigned char* src = (unsigned char*)FAT12_BASE + lba * IDE_SECTOR_SIZE;
        ide_write_sector(lba, src);
    }
}

// Возвращает значение 12-битной записи FAT для кластера cluster
static unsigned int fat12_get_entry(unsigned int cluster) {
    unsigned char* fat = (unsigned char*)FAT12_BASE + (unsigned int)bpb->reserved_sectors * bpb->bytes_per_sector;
    unsigned int offset = cluster + cluster / 2; // cluster * 1.5
    unsigned int value = fat[offset] | (fat[offset + 1] << 8);

    if (cluster & 1) {
        return value >> 4;
    } else {
        return value & 0x0FFF;
    }
}

// Начало корневой директории, в байтах от FAT12_BASE
static unsigned int fat12_root_dir_offset() {
    return ((unsigned int)bpb->reserved_sectors + (unsigned int)bpb->num_fats * bpb->sectors_per_fat) * bpb->bytes_per_sector;
}

// Начало области данных (кластер 2), в байтах от FAT12_BASE
static unsigned int fat12_data_offset() {
    unsigned int root_dir_sectors = (bpb->root_entries * 32) / bpb->bytes_per_sector;
    return fat12_root_dir_offset() + root_dir_sectors * bpb->bytes_per_sector;
}

// Сравнивает n байт двух блоков памяти
static int mem_eq(char* a, char* b, int n) {
    for (int i = 0; i < n; i++) {
        if (a[i] != b[i]) return 0;
    }
    return 1;
}

// Разбирает имя файла "name.ext" в формат 8.3 (заглавные буквы, пробелы-заполнители)
static void parse_83(char* input, char* name, char* ext) {
    for (int i = 0; i < 8; i++) name[i] = ' ';
    for (int i = 0; i < 3; i++) ext[i] = ' ';

    int i = 0, ni = 0;
    while (input[i] != '\0' && input[i] != '.' && ni < 8) {
        char c = input[i];
        if (c >= 'a' && c <= 'z') c -= 32;
        name[ni++] = c;
        i++;
    }

    if (input[i] == '.') {
        i++;
        int ei = 0;
        while (input[i] != '\0' && ei < 3) {
            char c = input[i];
            if (c >= 'a' && c <= 'z') c -= 32;
            ext[ei++] = c;
            i++;
        }
    }
}

// Записывает значение value в 12-битную запись FAT для кластера cluster
// (read-modify-write пары байт, см. set_fat_entry в tools/make_fat12.py)
static void fat12_set_entry(unsigned int cluster, unsigned int value) {
    unsigned char* fat = (unsigned char*)FAT12_BASE + (unsigned int)bpb->reserved_sectors * bpb->bytes_per_sector;
    unsigned int offset = cluster + cluster / 2;

    if (cluster & 1) {
        fat[offset]     = (fat[offset] & 0x0F) | ((value & 0x0F) << 4);
        fat[offset + 1] = (value >> 4) & 0xFF;
    } else {
        fat[offset]     = value & 0xFF;
        fat[offset + 1] = (fat[offset + 1] & 0xF0) | ((value >> 8) & 0x0F);
    }
}

// Общее количество кластеров данных. Валидные номера кластеров: 2..total+1
static unsigned int fat12_total_clusters() {
    unsigned int root_dir_sectors = (bpb->root_entries * 32) / bpb->bytes_per_sector;
    unsigned int data_sectors = bpb->total_sectors - bpb->reserved_sectors
        - (unsigned int)bpb->num_fats * bpb->sectors_per_fat - root_dir_sectors;
    return data_sectors / bpb->sectors_per_cluster;
}

// Освобождает цепочку кластеров, начиная с start_cluster (обнуляет FAT-записи)
static void fat12_free_chain(unsigned int start_cluster) {
    unsigned int cluster = start_cluster;
    while (cluster >= 2 && cluster < 0xFF8) {
        unsigned int next = fat12_get_entry(cluster);
        fat12_set_entry(cluster, 0);
        cluster = next;
    }
}

// Выделяет цепочку из num_clusters свободных кластеров, связывая их в FAT.
// Возвращает номер первого кластера цепочки или 0, если свободных
// кластеров не хватило (уже выделенное освобождается обратно).
static unsigned int fat12_alloc_chain(unsigned int num_clusters) {
    if (num_clusters == 0) return 0;

    unsigned int total = fat12_total_clusters();
    unsigned int first = 0;
    unsigned int prev = 0;
    unsigned int allocated = 0;

    for (unsigned int c = 2; c <= total + 1 && allocated < num_clusters; c++) {
        if (fat12_get_entry(c) == 0) {
            if (prev != 0) {
                fat12_set_entry(prev, c);
            } else {
                first = c;
            }
            prev = c;
            allocated++;
        }
    }

    if (allocated < num_clusters) {
        if (first != 0) fat12_free_chain(first);
        return 0;
    }

    fat12_set_entry(prev, 0xFFF); // конец цепочки
    return first;
}

// Копирует data (size байт) по кластерам цепочки, начиная с start_cluster
// (зеркало fat12_read_file, но запись)
static void fat12_write_chain_data(unsigned int start_cluster, unsigned char* data, unsigned int size) {
    unsigned int cluster_size = (unsigned int)bpb->sectors_per_cluster * bpb->bytes_per_sector;
    unsigned char* data_area = (unsigned char*)FAT12_BASE + fat12_data_offset();

    unsigned int cluster = start_cluster;
    unsigned int written = 0;

    while (cluster >= 2 && cluster < 0xFF8 && written < size) {
        unsigned int chunk = cluster_size;
        if (chunk > size - written) chunk = size - written;

        unsigned char* dst = data_area + (cluster - 2) * cluster_size;
        for (unsigned int i = 0; i < chunk; i++) {
            dst[i] = data[written + i];
        }

        written += chunk;
        cluster = fat12_get_entry(cluster);
    }
}

// Ищет первую свободную запись корневой директории (удалённую или конец)
static struct fat12_dir_entry* fat12_find_free_entry() {
    struct fat12_dir_entry* entries = (struct fat12_dir_entry*)((unsigned char*)FAT12_BASE + fat12_root_dir_offset());

    for (int i = 0; i < bpb->root_entries; i++) {
        unsigned char first = (unsigned char)entries[i].name[0];
        if (first == 0x00 || first == 0xE5) return &entries[i];
    }

    return 0;
}

// Ищет файл в корневой директории по имени в формате 8.3
static struct fat12_dir_entry* fat12_find(char* name, char* ext) {
    struct fat12_dir_entry* entries = (struct fat12_dir_entry*)((unsigned char*)FAT12_BASE + fat12_root_dir_offset());

    for (int i = 0; i < bpb->root_entries; i++) {
        if (entries[i].name[0] == 0x00) break;        // конец директории
        if ((unsigned char)entries[i].name[0] == 0xE5) continue; // удалённый файл

        if (mem_eq(entries[i].name, name, 8) && mem_eq(entries[i].ext, ext, 3)) {
            return &entries[i];
        }
    }

    return 0;
}

// Читает содержимое файла по цепочке кластеров в buffer (макс. max_size байт)
// Возвращает количество прочитанных байт
static unsigned int fat12_read_file(struct fat12_dir_entry* entry, unsigned char* buffer, unsigned int max_size) {
    unsigned int cluster_size = (unsigned int)bpb->sectors_per_cluster * bpb->bytes_per_sector;
    unsigned char* data_area = (unsigned char*)FAT12_BASE + fat12_data_offset();

    unsigned int cluster = entry->start_cluster;
    unsigned int remaining = entry->file_size;
    unsigned int total_read = 0;

    while (cluster >= 2 && cluster < 0xFF8 && remaining > 0 && total_read < max_size) {
        unsigned int chunk = cluster_size;
        if (chunk > remaining) chunk = remaining;
        if (chunk > max_size - total_read) chunk = max_size - total_read;

        unsigned char* src = data_area + (cluster - 2) * cluster_size;
        for (unsigned int i = 0; i < chunk; i++) {
            buffer[total_read + i] = src[i];
        }

        total_read += chunk;
        remaining -= chunk;
        cluster = fat12_get_entry(cluster);
    }

    return total_read;
}

void fat12_list() {
    if (!fat12_ready) return;

    struct fat12_dir_entry* entries = (struct fat12_dir_entry*)((unsigned char*)FAT12_BASE + fat12_root_dir_offset());

    for (int i = 0; i < bpb->root_entries; i++) {
        if (entries[i].name[0] == 0x00) break;
        if ((unsigned char)entries[i].name[0] == 0xE5) continue;

        char buf[13];
        int p = 0;
        for (int j = 0; j < 8 && entries[i].name[j] != ' '; j++) buf[p++] = entries[i].name[j];
        if (entries[i].ext[0] != ' ') {
            buf[p++] = '.';
            for (int j = 0; j < 3 && entries[i].ext[j] != ' '; j++) buf[p++] = entries[i].ext[j];
        }
        buf[p] = '\0';

        print_string(buf);
        print_string("  (");
        print_uint(entries[i].file_size);
        print_string(" bytes)\n");
    }
}

int fat12_cat(char* filename) {
    if (!fat12_ready) return 0;

    char name[8], ext[3];
    parse_83(filename, name, ext);

    struct fat12_dir_entry* entry = fat12_find(name, ext);
    if (!entry) return 0;

    unsigned char buf[2048];
    unsigned int max = sizeof(buf) - 1;
    unsigned int size = fat12_read_file(entry, buf, max);
    buf[size] = '\0';

    print_string((char*)buf);
    return 1;
}

unsigned int fat12_load(char* filename, unsigned char* buffer, unsigned int max_size) {
    if (!fat12_ready) return 0;

    char name[8], ext[3];
    parse_83(filename, name, ext);

    struct fat12_dir_entry* entry = fat12_find(name, ext);
    if (!entry) return 0;

    return fat12_read_file(entry, buffer, max_size);
}

int fat12_write(char* filename, unsigned char* data, unsigned int size) {
    if (!fat12_ready) return 0;
    if (fat12_locked) return 0;

    char name[8], ext[3];
    parse_83(filename, name, ext);

    struct fat12_dir_entry* entry = fat12_find(name, ext);
    if (!entry) {
        entry = fat12_find_free_entry();
        if (!entry) return 0; // корневая директория полна

        for (int i = 0; i < 8; i++) entry->name[i] = name[i];
        for (int i = 0; i < 3; i++) entry->ext[i] = ext[i];
        entry->attr = 0x20; // ARCHIVE
        for (int i = 0; i < 10; i++) entry->reserved[i] = 0;
        entry->time = 0;
        entry->date = 0;
    } else if (entry->start_cluster != 0) {
        fat12_free_chain(entry->start_cluster);
    }

    entry->start_cluster = 0;
    entry->file_size = 0;

    if (size == 0) {
        fat12_flush();
        return 1;
    }

    unsigned int cluster_size = (unsigned int)bpb->sectors_per_cluster * bpb->bytes_per_sector;
    unsigned int num_clusters = (size + cluster_size - 1) / cluster_size;

    unsigned int start = fat12_alloc_chain(num_clusters);
    if (!start) return 0; // не хватило места на диске

    fat12_write_chain_data(start, data, size);

    entry->start_cluster = start;
    entry->file_size = size;
    fat12_flush();
    return 1;
}
