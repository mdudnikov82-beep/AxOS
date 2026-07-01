// =================================================================
//  Драйвер PCI (config space mechanism #1, порты 0xCF8/0xCFC)
// =================================================================
//
// CONFIG_ADDRESS (0xCF8) принимает 32-битное "адресное слово": бит31=1
// (enable), биты23-16=bus, биты15-11=device, биты10-8=function,
// биты7-0=offset (всегда выровненный на 4, младшие 2 бита игнорируются
// контроллером). Запись туда, затем чтение CONFIG_DATA (0xCFC) отдаёт
// 4 байта конфигурационного пространства устройства начиная с offset.
//
// Несуществующее устройство возвращает vendor ID 0xFFFF при чтении
// offset 0 - это единственный надёжный признак "тут никого нет", раз
// шина не подтверждает транзакции явным образом.

#include "pci.h"

static unsigned int port_long_in(unsigned short port) {
    unsigned int result;
    __asm__ volatile("inl %%dx, %%eax" : "=a"(result) : "d"(port));
    return result;
}

static void port_long_out(unsigned short port, unsigned int data) {
    __asm__ volatile("outl %%eax, %%dx" : : "a"(data), "d"(port));
}

#define PCI_CONFIG_ADDRESS 0xCF8
#define PCI_CONFIG_DATA    0xCFC

static unsigned int pci_config_read32(unsigned char bus, unsigned char device,
                                       unsigned char function, unsigned char offset) {
    unsigned int address = 0x80000000u
                          | ((unsigned int)bus << 16)
                          | ((unsigned int)device << 11)
                          | ((unsigned int)function << 8)
                          | (offset & 0xFC);
    port_long_out(PCI_CONFIG_ADDRESS, address);
    return port_long_in(PCI_CONFIG_DATA);
}

static unsigned short pci_config_read16(unsigned char bus, unsigned char device,
                                         unsigned char function, unsigned char offset) {
    unsigned int dword = pci_config_read32(bus, device, function, (unsigned char)(offset & 0xFC));
    return (unsigned short)(dword >> ((offset & 2) * 8));
}

static unsigned char pci_config_read8(unsigned char bus, unsigned char device,
                                       unsigned char function, unsigned char offset) {
    unsigned int dword = pci_config_read32(bus, device, function, (unsigned char)(offset & 0xFC));
    return (unsigned char)(dword >> ((offset & 3) * 8));
}

static void scan_bus(unsigned char bus, struct pci_device* out, unsigned int max, unsigned int* count);

// Один device/function слот. Бридж (класс 0x06, подкласс 0x04) сообщает
// в своём же конфиг-пространстве (offset 0x19) номер вторичной шины за
// ним - рекурсивно сканируем её, иначе устройства за любым мостом (а в
// машинах QEMU с q35/PCIe это норма, не редкость) остались бы невидимы.
static void scan_function(unsigned char bus, unsigned char device, unsigned char function,
                           struct pci_device* out, unsigned int max, unsigned int* count) {
    unsigned short vendor = pci_config_read16(bus, device, function, 0x00);
    if (vendor == 0xFFFF) return;

    unsigned short dev_id   = pci_config_read16(bus, device, function, 0x02);
    unsigned char  subclass = pci_config_read8(bus, device, function, 0x0A);
    unsigned char  class_c  = pci_config_read8(bus, device, function, 0x0B);

    if (*count < max) {
        struct pci_device* d = &out[*count];
        d->bus = bus;
        d->device = device;
        d->function = function;
        d->vendor_id = vendor;
        d->device_id = dev_id;
        d->class_code = class_c;
        d->subclass = subclass;
    }
    (*count)++;

    if (class_c == 0x06 && subclass == 0x04) {
        unsigned char secondary_bus = pci_config_read8(bus, device, function, 0x19);
        scan_bus(secondary_bus, out, max, count);
    }
}

static void scan_bus(unsigned char bus, struct pci_device* out, unsigned int max, unsigned int* count) {
    for (unsigned int device = 0; device < 32; device++) {
        unsigned short vendor = pci_config_read16(bus, (unsigned char)device, 0, 0x00);
        if (vendor == 0xFFFF) continue;

        // Бит 7 байта Header Type (offset 0x0E) функции 0 = устройство
        // многофункциональное - только тогда стоит проверять function 1-7
        // (опрашивать их у обычных устройств не запрещено, но почти
        // всегда впустую - они тоже вернут 0xFFFF, просто лишние 7 чтений
        // конфиг-пространства на каждый слот).
        unsigned char header0 = pci_config_read8(bus, (unsigned char)device, 0, 0x0E);
        unsigned int max_function = (header0 & 0x80) ? 8 : 1;

        for (unsigned int function = 0; function < max_function; function++) {
            scan_function(bus, (unsigned char)device, (unsigned char)function, out, max, count);
        }
    }
}

unsigned int pci_scan(struct pci_device* out, unsigned int max) {
    unsigned int count = 0;
    scan_bus(0, out, max, &count);
    return count;
}

// Только базовый (top-level) класс - подклассы PCI исчисляются сотнями
// комбинаций, не оправдывающими статическую таблицу в этом freestanding-
// окружении; для деталей по конкретному устройству есть vendor:device ID
// и настоящий "lspci -nn" на хосте.
static const struct { unsigned char code; const char* name; } PCI_CLASS_NAMES[] = {
    { 0x00, "Unclassified" },
    { 0x01, "Mass storage controller" },
    { 0x02, "Network controller" },
    { 0x03, "Display controller" },
    { 0x04, "Multimedia controller" },
    { 0x05, "Memory controller" },
    { 0x06, "Bridge" },
    { 0x07, "Communication controller" },
    { 0x08, "Generic system peripheral" },
    { 0x09, "Input device controller" },
    { 0x0A, "Docking station" },
    { 0x0B, "Processor" },
    { 0x0C, "Serial bus controller" },
    { 0x0D, "Wireless controller" },
    { 0x0E, "Intelligent controller" },
    { 0x0F, "Satellite communication controller" },
    { 0x10, "Encryption controller" },
    { 0x11, "Signal processing controller" },
};
#define PCI_CLASS_NAME_COUNT (int)(sizeof(PCI_CLASS_NAMES) / sizeof(PCI_CLASS_NAMES[0]))

const char* pci_class_name(unsigned char class_code) {
    for (int i = 0; i < PCI_CLASS_NAME_COUNT; i++) {
        if (PCI_CLASS_NAMES[i].code == class_code) return PCI_CLASS_NAMES[i].name;
    }
    return "Unknown";
}
