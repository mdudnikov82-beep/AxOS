#ifndef VFS_H
#define VFS_H

// Таблица функций драйвера файловой системы (vtable). Сигнатуры — точное
// зеркало публичного API src/fs/fat12.c.
typedef struct vfs_driver {
    int (*init)(void);
    int (*is_ready)(void);
    int (*is_locked)(void);
    void (*set_locked)(int locked);
    void (*list)(void);
    int (*cat)(char* filename);
    unsigned int (*read)(char* filename, unsigned char* buffer, unsigned int max_size);
    int (*write)(char* filename, unsigned char* data, unsigned int size);
} vfs_driver_t;

// Минимальная VFS: один глобальный корень (vfs_root), привязанный к FAT12.
// Без путей и mount-point'ов - имена файлов передаются как есть ("name.ext").
int vfs_init(void);
int vfs_is_ready(void);
int vfs_is_locked(void);
void vfs_set_locked(int locked);
void vfs_list(void);
int vfs_cat(char* filename);
unsigned int vfs_read(char* filename, unsigned char* buffer, unsigned int max_size);
int vfs_write(char* filename, unsigned char* data, unsigned int size);

#endif
