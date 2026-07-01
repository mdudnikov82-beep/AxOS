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

#endif
