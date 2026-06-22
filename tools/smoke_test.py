#!/usr/bin/env python3
# Headless smoke-test for AxOS: boots build/os-image.bin in QEMU, grabs the
# VGA text buffer through the QEMU monitor and checks that the shell prompt
# came up cleanly (and that there was no page fault / crash).

import os
import subprocess
import sys
import time

from qemu_test_helpers import connect_monitor, dump_screen, launch_qemu

IMAGE = os.path.join("build", "os-image.bin")
DISK_IMAGE = os.path.join("build", "disk.img")
MONITOR_PORT = 55590
DUMP_FILE = "vga_dump.bin"
BOOT_WAIT_SEC = 10


def main():
    if not os.path.isfile(IMAGE):
        print(f"FAIL: {IMAGE} not found - did the build step run?")
        return 1

    proc = launch_qemu(IMAGE, DISK_IMAGE, MONITOR_PORT)

    try:
        time.sleep(BOOT_WAIT_SEC)

        sock = connect_monitor(MONITOR_PORT)
        screen = dump_screen(sock, DUMP_FILE, settle_sec=1)
        sock.sendall(b"quit\n")
        time.sleep(1)
        sock.close()
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    if not screen:
        print("FAIL: VGA dump was not created (QEMU may have failed to boot)")
        return 1

    print("--- VGA screen ---")
    print(screen)
    print("------------------")

    ok = True
    if "Welcome to AxOS!" not in screen:
        print("FAIL: boot banner 'Welcome to AxOS!' not found")
        ok = False
    if "AxSH v0.1" not in screen:
        print("FAIL: 'AxSH v0.1' (userspace shell banner) not found")
        ok = False
    if "PAGE FAULT" in screen:
        print("FAIL: '*** PAGE FAULT ***' detected")
        ok = False

    if ok:
        print("OK: AxOS booted to the AxSH prompt")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
