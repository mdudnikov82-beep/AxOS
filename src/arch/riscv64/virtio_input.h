#pragma once

// VirtIO-input (tablet mode: абсолютные координаты, а не relative-mouse
// дельты — так проще, не нужна аккумуляция/ускорение) по MMIO на QEMU virt.
// Требует `-device virtio-tablet-device` в командной строке QEMU.

int virtio_input_init(void);
int virtio_input_ready(void);

// Дренирует накопленные события ввода и возвращает упакованное состояние:
//   бит [47:32] = x (0..GPU_FB_WIDTH-1, уже отмасштабировано под экран)
//   бит [31:16] = y (0..GPU_FB_HEIGHT-1)
//   бит [7:0]   = кнопки (бит0=левая, бит1=правая, бит2=средняя)
unsigned long virtio_input_state(void);
