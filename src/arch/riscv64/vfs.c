#include "vfs.h"
#include "fat12.h"

static const vfs_driver_t fat12_driver = {
    .init     = fat12_init,
    .is_ready = fat12_is_ready,
    .list     = fat12_list,
    .load     = fat12_load,
    .write    = fat12_write,
    .delete   = fat12_delete,
    .readdir  = fat12_readdir,
};

const vfs_driver_t *vfs_root = &fat12_driver;

int          vfs_init(void)      { return vfs_root ? vfs_root->init() : 0; }
int          vfs_is_ready(void)  { return vfs_root ? vfs_root->is_ready() : 0; }
void         vfs_list(void)      { if (vfs_root) vfs_root->list(); }

unsigned int vfs_load(char *filename, unsigned char *buffer, unsigned int max_size) {
    return vfs_root ? vfs_root->load(filename, buffer, max_size) : 0;
}
int vfs_write(char *filename, unsigned char *data, unsigned int size) {
    return vfs_root ? vfs_root->write(filename, data, size) : 0;
}
int vfs_delete(char *filename) {
    return vfs_root ? vfs_root->delete(filename) : -1;
}
int vfs_readdir(unsigned int index, char *name_buf, unsigned int *size_out) {
    return vfs_root ? vfs_root->readdir(index, name_buf, size_out) : 0;
}
