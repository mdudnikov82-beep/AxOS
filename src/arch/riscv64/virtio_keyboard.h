#pragma once

// VirtIO-keyboard (same virtio,input MMIO class as virtio_input.c's
// tablet, DEVICE_ID=18 — discriminated from it by EV_ABS support: a
// real keyboard reports zero absolute axes, the tablet reports
// ABS_X/ABS_Y). Requires `-device virtio-keyboard-device` in the QEMU
// command line.

int virtio_keyboard_init(void);
int virtio_keyboard_ready(void);

// Drains any pending virtqueue events and returns the next translated
// ASCII character from the internal FIFO, or -1 if none pending / no
// device (never returns 0 — untranslatable keys are never enqueued).
int virtio_keyboard_getc(void);
