#ifndef VIRTIO_NET_H
#define VIRTIO_NET_H

// virtio-net поверх LEGACY PCI-транспорта (I/O-порты, до virtio 1.0) -
// требует QEMU `-device virtio-net-pci,disable-legacy=off` (или просто
// `-netdev user,id=net0 -device virtio-net-pci,netdev=net0` - QEMU по
// умолчанию делает virtio-net-pci "transitional", legacy-режим доступен
// без дополнительных флагов). Даёт только приём/отправку сырых Ethernet-
// кадров, как и RISC-V версия этого драйвера (src/arch/riscv64/
// virtio_net.c) - ни ARP, ни IPv4 тут нет, это отдельный (userspace) слой.

int virtio_net_init(void);
int virtio_net_ready(void);

// MAC-адрес устройства (6 байт), считанный из config space при инициализации.
void virtio_net_get_mac(unsigned char mac[6]);

// Отправляет один Ethernet-кадр (без virtio_net_hdr - драйвер добавляет
// его сам). Возвращает 0 при успехе, -1 при ошибке/устройство не готово.
int virtio_net_send(const void* frame, unsigned int len);

// Неблокирующий приём: если есть готовый кадр, копирует его (без
// virtio_net_hdr) в buf и возвращает его длину; иначе возвращает 0 сразу.
// Кадр длиннее max_len отбрасывается (как будто не приходил).
unsigned int virtio_net_recv(void* buf, unsigned int max_len);

#endif
