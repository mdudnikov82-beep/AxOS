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

#endif
