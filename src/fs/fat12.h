#ifndef FAT12_H
#define FAT12_H

// Выводит список файлов корневой директории FAT12-раздела
void fat12_list();

// Печатает содержимое файла (имя в формате "name.ext", регистр не важен)
// Возвращает 1, если файл найден, 0 - если нет
int fat12_cat(char* filename);

// Загружает файл filename (имя в формате "name.ext", регистр не важен)
// в buffer (макс. max_size байт). Возвращает размер файла в байтах,
// или 0, если файл не найден.
unsigned int fat12_load(char* filename, unsigned char* buffer, unsigned int max_size);

// Создаёт или перезаписывает файл filename (имя в формате "name.ext")
// содержимым data (size байт). Возвращает 1 при успехе, 0 если диск
// заблокирован (см. fat12_set_locked) или корневая директория/место
// на диске заняты.
int fat12_write(char* filename, unsigned char* data, unsigned int size);

// Включает (1) или отключает (0) защиту FAT12-диска от записи.
// По умолчанию диск заблокирован (fat12_write всегда возвращает 0).
void fat12_set_locked(int locked);

// Возвращает 1, если диск заблокирован от записи, иначе 0.
int fat12_is_locked();

#endif
