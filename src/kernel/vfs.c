// =================================================================
//  VFS: тонкий слой перенаправления к драйверу файловой системы
// =================================================================
//
// Минимальная VFS - один глобальный корень (vfs_root), привязанный к
// FAT12-драйверу через vtable (vfs_driver_t). kernel.c и selftest.c
// обращаются только к vfs_*, не зная, что под капотом работает FAT12.

#include "../fs/fat12.h"
#include "vfs.h"
#include "screen.h"

static vfs_driver_t fat12_driver = {
    fat12_init, fat12_is_ready, fat12_is_locked, fat12_set_locked,
    fat12_list, fat12_readdir, fat12_cat, fat12_load, fat12_write, fat12_delete, fat12_mkdir
};

static vfs_driver_t* vfs_root = &fat12_driver;

int vfs_init(void) {
    // 1. Проверка указателя
    if (vfs_root == 0) {
        print_string("CRITICAL: vfs_root is NULL!\n");
        return 0;
    }
    
    // 2. Проверка метода init
    if (vfs_root->init == 0) {
        print_string("CRITICAL: vfs_root->init is NULL!\n");
        return 0;
    }

    // 3. Безопасный вызов
    return vfs_root->init();
}
int vfs_is_ready(void) { return vfs_root->is_ready(); }
int vfs_is_locked(void) { return vfs_root->is_locked(); }
void vfs_set_locked(int locked) { vfs_root->set_locked(locked); }
void vfs_list(void) { vfs_root->list(); }
int vfs_readdir(unsigned int index, char* name_out, unsigned int* size_out, int* is_dir_out) {
    return vfs_root->readdir(index, name_out, size_out, is_dir_out);
}
int vfs_cat(char* filename) { return vfs_root->cat(filename); }

unsigned int vfs_read(char* filename, unsigned char* buffer, unsigned int max_size) {
    return vfs_root->read(filename, buffer, max_size);
}

int vfs_write(char* filename, unsigned char* data, unsigned int size) {
    return vfs_root->write(filename, data, size);
}

int vfs_delete(char* filename) {
    return vfs_root->delete(filename);
}

int vfs_mkdir(char* dirname) {
    return vfs_root->mkdir(dirname);
}
