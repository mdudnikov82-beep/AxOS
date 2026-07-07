#pragma once

// VFS: тонкая прослойка между ядром/syscall'ами и конкретным драйвером ФС
// (сейчас — единственный backend, FAT12). Смысл не в новой функциональности
// сегодня, а в развязке: kernel_main.c/syscall.c зовут vfs_*, не fat12_*
// напрямую, так что вторая ФС (когда понадобится) подключается заменой
// vfs_root, без правки вызывающего кода. Прямой порт идеи с x86-стороны
// (src/kernel/vfs.c) — там тот же приём с одним зарегистрированным backend'ом.
//
// Всё ещё плоско: один корень, без путей/точек монтирования — ровно то,
// что умеет сама FAT12 на RV64.

typedef struct {
    int          (*init)(void);
    int          (*is_ready)(void);
    void         (*list)(void);
    unsigned int (*load)(char *filename, unsigned char *buffer, unsigned int max_size);
    int          (*write)(char *filename, unsigned char *data, unsigned int size);
    int          (*delete)(char *filename);
    int          (*readdir)(unsigned int index, char *name_buf, unsigned int *size_out);
} vfs_driver_t;

extern const vfs_driver_t *vfs_root;

int          vfs_init(void);
int          vfs_is_ready(void);
void         vfs_list(void);
unsigned int vfs_load(char *filename, unsigned char *buffer, unsigned int max_size);
int          vfs_write(char *filename, unsigned char *data, unsigned int size);
int          vfs_delete(char *filename);
int          vfs_readdir(unsigned int index, char *name_buf, unsigned int *size_out);
