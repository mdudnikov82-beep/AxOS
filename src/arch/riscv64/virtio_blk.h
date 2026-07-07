#pragma once

#define SECTOR_SIZE 512UL

// Инициализирует VirtIO-blk по MMIO-адресу 0x10001000 (QEMU virt).
// Возвращает 0 при успехе, -1 если устройство не найдено или инициализация
// провалилась.
int virtio_blk_init(void);

// Читает один сектор (512 байт) по номеру sector в buf.
// buf должен быть выровнен хотя бы на 1 байт (любой указатель); buf += 512.
int virtio_blk_read(unsigned long sector, void *buf);

// Записывает один сектор из buf на диск.
int virtio_blk_write(unsigned long sector, const void *buf);

// Ёмкость диска в секторах.
unsigned long virtio_blk_capacity(void);
