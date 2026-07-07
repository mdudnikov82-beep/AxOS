#pragma once

// Инициализирует FAT12-том: загружает все сектора через VirtIO в RAM.
// Возвращает 1 при успехе, 0 при ошибке (нет диска, неверный BPB).
int fat12_init(void);

int fat12_is_ready(void);

// Выводит листинг корневой директории через uart_puts.
void fat12_list(void);

// Читает файл filename в buffer (макс. max_size байт).
// Возвращает фактический размер или 0 если файл не найден.
unsigned int fat12_load(char *filename, unsigned char *buffer, unsigned int max_size);

// Записывает data (size байт) в файл filename; создаёт если не существует.
// Возвращает 1 при успехе.
int fat12_write(char *filename, unsigned char *data, unsigned int size);

// Удаляет файл. 1 = удалён, 0 = нет тома, -1 = не найден.
int fat12_delete(char *filename);

// Возвращает запись корневого каталога по индексу (0-based, пропуская удалённые).
// name_buf: минимум 13 байт (формат "NAME.EXT\0").
// size_out: куда записать размер файла (можно NULL).
// Возвращает 1 если запись найдена, 0 если индекс за пределами.
int fat12_readdir(unsigned int index, char *name_buf, unsigned int *size_out);
