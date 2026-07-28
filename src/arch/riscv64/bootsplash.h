#pragma once

/* Google Pixel-style boot splash: the "AxOS" logo assembles letter by
 * letter, pulses a couple times, then "Powered by AxOS" fades in
 * underneath. Runs once from kernel_main.c right after virtio_gpu_init()
 * succeeds, entirely before proc_init()/the scheduler exist - pure
 * busy-wait pacing (own CSR `time` read), no syscalls/interrupts
 * involved. No-op if the GPU isn't available. */
void boot_splash_show(void);
