#pragma once

// VirtIO-net по MMIO на QEMU virt. Требует
// `-netdev user,id=net0 -device virtio-net-device,netdev=net0` в командной
// строке QEMU. Драйвер даёт только приём/отправку сырых Ethernet-кадров —
// ARP/IPv4/ICMP и выше строятся поверх этого в userspace/следующим слоем
// ядра, здесь их нет.

int virtio_net_init(void);
int virtio_net_ready(void);

// MAC-адрес устройства (6 байт), считанный из config space при инициализации.
void virtio_net_get_mac(unsigned char mac[6]);

// Отправляет один Ethernet-кадр (без virtio_net_hdr — драйвер добавляет его
// сам). len — длина кадра в байтах (обычно 14 байт заголовка + payload,
// максимум ~1514). Возвращает 0 при успехе, -1 при ошибке/устройство не готово.
int virtio_net_send(const void *frame, unsigned int len);

// Неблокирующий приём: если есть готовый кадр, копирует его (без
// virtio_net_hdr) в buf и возвращает его длину; если кадров нет — возвращает
// 0 сразу (не ждёт). max_len — размер buf; кадр длиннее max_len отбрасывается
// (и функция вернёт 0 для этого кадра, как будто он не приходил).
unsigned int virtio_net_recv(void *buf, unsigned int max_len);
