#ifndef IDE_H
#define IDE_H

#define IDE_SECTOR_SIZE 512

// Читает один сектор (lba) с первичного ATA-диска (primary master, LBA28)
// в buffer (512 байт). Возвращает 1 при успехе, 0 при ошибке (нет
// устройства, таймаут, ERR-бит).
int ide_read_sector(unsigned int lba, unsigned char* buffer);

// Записывает один сектор (lba) на первичный ATA-диск (primary master,
// LBA28) из buffer (512 байт) и сбрасывает кэш контроллера (CACHE FLUSH).
// Возвращает 1 при успехе, 0 при ошибке.
int ide_write_sector(unsigned int lba, unsigned char* buffer);

// Выполняет команду IDENTIFY DEVICE и копирует строку модели устройства
// (обрезанную по пробелам, с '\0') в model (буфер не менее 41 байта).
// Возвращает 1 при успехе, 0 если устройство не отвечает.
int ide_identify(char* model);

#endif
