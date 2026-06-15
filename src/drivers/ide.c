// =================================================================
//  PIO-драйвер ATA/IDE (primary bus, master, LBA28)
// =================================================================
//
// Без DMA и прерываний - чтение/запись через порты 0x1F0-0x1F7 с
// поллингом статус-регистра. Достаточно для одного диска в QEMU
// (build/disk.img, см. build.bat/run.bat) - настоящий диск, в отличие
// от встроенного в образ FAT12 RAM-диска (fat12.c).

#define IDE_REG_DATA       0x1F0
#define IDE_REG_SECCOUNT   0x1F2
#define IDE_REG_LBA_LOW    0x1F3
#define IDE_REG_LBA_MID    0x1F4
#define IDE_REG_LBA_HIGH   0x1F5
#define IDE_REG_DRIVE_HEAD 0x1F6
#define IDE_REG_STATUS     0x1F7
#define IDE_REG_COMMAND    0x1F7

#define IDE_STATUS_ERR 0x01
#define IDE_STATUS_DRQ 0x08
#define IDE_STATUS_BSY 0x80

#define IDE_CMD_READ_SECTORS  0x20
#define IDE_CMD_WRITE_SECTORS 0x30
#define IDE_CMD_CACHE_FLUSH   0xE7
#define IDE_CMD_IDENTIFY      0xEC

#define IDE_WAIT_LIMIT 100000

static unsigned char port_byte_in(unsigned short port) {
    unsigned char result;
    __asm__ volatile("inb %%dx, %%al" : "=a"(result) : "d"(port));
    return result;
}

static void port_byte_out(unsigned short port, unsigned char data) {
    __asm__ volatile("outb %%al, %%dx" : : "a"(data), "d"(port));
}

static unsigned short port_word_in(unsigned short port) {
    unsigned short result;
    __asm__ volatile("inw %%dx, %%ax" : "=a"(result) : "d"(port));
    return result;
}

static void port_word_out(unsigned short port, unsigned short data) {
    __asm__ volatile("outw %%ax, %%dx" : : "a"(data), "d"(port));
}

// Ждёт, пока контроллер очистит BSY. Возвращает 0, если устройство не
// отвечает (статус 0xFF) или BSY не сбросился за IDE_WAIT_LIMIT попыток.
static int ide_wait_ready() {
    unsigned char status = port_byte_in(IDE_REG_STATUS);
    if (status == 0xFF) return 0; // нет контроллера/устройства

    for (unsigned int i = 0; i < IDE_WAIT_LIMIT; i++) {
        status = port_byte_in(IDE_REG_STATUS);
        if (!(status & IDE_STATUS_BSY)) return 1;
    }
    return 0; // таймаут
}

// Ждёт готовности данных (BSY=0, DRQ=1). Возвращает 0 при ERR или таймауте.
static int ide_wait_data() {
    for (unsigned int i = 0; i < IDE_WAIT_LIMIT; i++) {
        unsigned char status = port_byte_in(IDE_REG_STATUS);
        if (status & IDE_STATUS_ERR) return 0;
        if (!(status & IDE_STATUS_BSY) && (status & IDE_STATUS_DRQ)) return 1;
    }
    return 0; // таймаут
}

static void ide_select_lba(unsigned int lba) {
    port_byte_out(IDE_REG_DRIVE_HEAD, 0xE0 | ((lba >> 24) & 0x0F)); // master, LBA mode
    port_byte_out(IDE_REG_SECCOUNT, 1);
    port_byte_out(IDE_REG_LBA_LOW, lba & 0xFF);
    port_byte_out(IDE_REG_LBA_MID, (lba >> 8) & 0xFF);
    port_byte_out(IDE_REG_LBA_HIGH, (lba >> 16) & 0xFF);
}

int ide_read_sector(unsigned int lba, unsigned char* buffer) {
    if (!ide_wait_ready()) return 0;

    ide_select_lba(lba);
    port_byte_out(IDE_REG_COMMAND, IDE_CMD_READ_SECTORS);

    if (!ide_wait_data()) return 0;

    for (int i = 0; i < 256; i++) {
        unsigned short word = port_word_in(IDE_REG_DATA);
        buffer[i * 2]     = word & 0xFF;
        buffer[i * 2 + 1] = (word >> 8) & 0xFF;
    }

    return 1;
}

int ide_write_sector(unsigned int lba, unsigned char* buffer) {
    if (!ide_wait_ready()) return 0;

    ide_select_lba(lba);
    port_byte_out(IDE_REG_COMMAND, IDE_CMD_WRITE_SECTORS);

    if (!ide_wait_data()) return 0;

    for (int i = 0; i < 256; i++) {
        unsigned short word = buffer[i * 2] | (buffer[i * 2 + 1] << 8);
        port_word_out(IDE_REG_DATA, word);
    }

    port_byte_out(IDE_REG_COMMAND, IDE_CMD_CACHE_FLUSH);
    return ide_wait_ready();
}

int ide_identify(char* model) {
    if (!ide_wait_ready()) return 0;

    port_byte_out(IDE_REG_DRIVE_HEAD, 0xE0);
    port_byte_out(IDE_REG_SECCOUNT, 0);
    port_byte_out(IDE_REG_LBA_LOW, 0);
    port_byte_out(IDE_REG_LBA_MID, 0);
    port_byte_out(IDE_REG_LBA_HIGH, 0);
    port_byte_out(IDE_REG_COMMAND, IDE_CMD_IDENTIFY);

    if (port_byte_in(IDE_REG_STATUS) == 0) return 0; // нет устройства
    if (!ide_wait_data()) return 0;

    unsigned short data[256];
    for (int i = 0; i < 256; i++) {
        data[i] = port_word_in(IDE_REG_DATA);
    }

    // Слова 27-46 ответа IDENTIFY - модель устройства (40 символов ASCII,
    // байты в каждом слове в обратном порядке).
    int p = 0;
    for (int i = 27; i <= 46; i++) {
        model[p++] = (char)((data[i] >> 8) & 0xFF);
        model[p++] = (char)(data[i] & 0xFF);
    }
    model[p] = '\0';

    while (p > 0 && model[p - 1] == ' ') {
        model[--p] = '\0';
    }

    return 1;
}
