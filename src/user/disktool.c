#include "axiom.h"

#define IDE_SECTOR_SIZE 512

static unsigned int parse_uint(const char* s) {
    unsigned int v = 0;
    while (*s >= '0' && *s <= '9') v = v * 10 + (unsigned int)(*s++ - '0');
    return v;
}

static void hex_dump(unsigned char* buf, unsigned int size) {
    for (unsigned int i = 0; i < size; i++) {
        ax_printf("%02x ", buf[i]);
        if ((i + 1) % 16 == 0) ax_putchar('\n');
    }
    if (size % 16 != 0) ax_putchar('\n');
}

int main(int argc, char** argv) {
    if (argc < 2) {
        ax_print("Usage: disktool info | disktool read <lba> | disktool write <lba> <text>\n");
        return 1;
    }

    if (argv[1][0] == 'i') { // info
        char model[41];
        if (ax_disk_identify(model)) {
            ax_print("\033[32mIDE primary master:\033[0m ");
            ax_print(model);
            ax_putchar('\n');
        } else {
            ax_print("\033[31mNo IDE drive found.\033[0m\n");
        }
        return 0;
    }

    if (argv[1][0] == 'r') { // read <lba>
        if (argc < 3) { ax_print("Usage: disktool read <lba>\n"); return 1; }
        unsigned int lba = parse_uint(argv[2]);
        unsigned char buf[IDE_SECTOR_SIZE];
        if (ax_disk_read_sector(lba, buf)) {
            hex_dump(buf, 128);
        } else {
            ax_print("\033[31mDisk read failed (no IDE drive?).\033[0m\n");
        }
        return 0;
    }

    if (argv[1][0] == 'w') { // write <lba> <text...>
        if (argc < 3) { ax_print("Usage: disktool write <lba> <text>\n"); return 1; }
        unsigned int lba = parse_uint(argv[2]);

        unsigned char buf[IDE_SECTOR_SIZE];
        for (unsigned int i = 0; i < IDE_SECTOR_SIZE; i++) buf[i] = 0;

        unsigned int len = 0;
        for (int a = 3; a < argc && len < IDE_SECTOR_SIZE; a++) {
            char* s = argv[a];
            while (*s && len < IDE_SECTOR_SIZE) buf[len++] = (unsigned char)*s++;
            if (a < argc - 1 && len < IDE_SECTOR_SIZE) buf[len++] = ' ';
        }

        if (ax_disk_write_sector(lba, buf)) {
            ax_print("\033[32mWritten.\033[0m\n");
        } else {
            ax_print("\033[31mDisk write failed (no IDE drive?).\033[0m\n");
        }
        return 0;
    }

    ax_print("Unknown subcommand. Usage: disktool info | read <lba> | write <lba> <text>\n");
    return 1;
}
