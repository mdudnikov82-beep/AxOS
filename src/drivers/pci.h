#ifndef PCI_H
#define PCI_H

struct pci_device {
    unsigned char  bus;
    unsigned char  device;
    unsigned char  function;
    unsigned short vendor_id;
    unsigned short device_id;
    unsigned char  class_code;
    unsigned char  subclass;
};

// Сканирует PCI-шину начиная с шины 0 (mechanism #1, порты 0xCF8/0xCFC),
// рекурсивно проходя мосты PCI-PCI, и заполняет out найденными
// устройствами (не больше max). Возвращает фактическое число найденных
// устройств (может быть больше max - лишние просто не записываются).
unsigned int pci_scan(struct pci_device* out, unsigned int max);

// Человекочитаемое имя базового класса устройства (см. таблицу в pci.c).
// "Unknown" для кодов, которых нет в таблице.
const char* pci_class_name(unsigned char class_code);

// Читает/пишет 32 бита конфигурационного пространства PCI-устройства по
// смещению offset (округляется вниз до кратного 4 контроллером). Нужны
// драйверам конкретных устройств (virtio-net-pci и т.п.) для чтения BAR0
// (offset 0x10+) и включения bus mastering/IO space в Command-регистре
// (offset 0x04) - то, что pci_scan() сам не делает (ему для перечисления
// хватает vendor/device/class/subclass).
unsigned int pci_config_read32(unsigned char bus, unsigned char device,
                                unsigned char function, unsigned char offset);
void pci_config_write32(unsigned char bus, unsigned char device,
                         unsigned char function, unsigned char offset,
                         unsigned int value);

#endif
