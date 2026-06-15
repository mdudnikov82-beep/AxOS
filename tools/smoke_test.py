#!/usr/bin/env python3
# Headless smoke-test for AxOS: boots build/os-image.bin in QEMU, grabs the
# VGA text buffer through the QEMU monitor and checks that the shell prompt
# came up cleanly (and that there was no page fault / crash).

import os
import socket
import subprocess
import sys
import time

IMAGE = os.path.join("build", "os-image.bin")
DISK_IMAGE = os.path.join("build", "disk.img")
MONITOR_PORT = 55590
DUMP_FILE = "vga_dump.bin"
BOOT_WAIT_SEC = 10

QEMU_CANDIDATES = [
    r"C:\Program Files\qemu\qemu-system-i386.exe",
    "qemu-system-i386",
]


def find_qemu():
    for candidate in QEMU_CANDIDATES:
        if os.path.isfile(candidate):
            return candidate
    return QEMU_CANDIDATES[-1]  # rely on PATH


def decode_vga(data):
    rows = []
    for row in range(25):
        line = ""
        for col in range(80):
            ch = data[(row * 80 + col) * 2]
            if ch == 0:
                line += " "
            elif 32 <= ch < 127:
                line += chr(ch)
            else:
                line += "."
        rows.append(line.rstrip())
    return rows


def main():
    if not os.path.isfile(IMAGE):
        print(f"FAIL: {IMAGE} not found - did the build step run?")
        return 1

    qemu = find_qemu()
    args = [
        qemu,
        "-drive", f"format=raw,file={IMAGE},if=floppy",
    ]
    if os.path.isfile(DISK_IMAGE):
        args += ["-drive", f"format=raw,file={DISK_IMAGE},if=ide,index=0,media=disk"]
    args += [
        "-boot", "a",
        "-display", "none",
        "-monitor", f"tcp:127.0.0.1:{MONITOR_PORT},server,nowait",
        "-no-reboot",
    ]
    proc = subprocess.Popen(args)

    try:
        time.sleep(BOOT_WAIT_SEC)

        sock = socket.create_connection(("127.0.0.1", MONITOR_PORT), timeout=10)
        sock.recv(4096)  # monitor banner
        sock.sendall(f"pmemsave 0xb8000 4000 {DUMP_FILE}\n".encode())
        time.sleep(1)
        sock.sendall(b"quit\n")
        time.sleep(1)
        sock.close()
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    if not os.path.isfile(DUMP_FILE):
        print("FAIL: VGA dump was not created (QEMU may have failed to boot)")
        return 1

    with open(DUMP_FILE, "rb") as f:
        data = f.read()
    os.remove(DUMP_FILE)

    rows = decode_vga(data)
    screen = "\n".join(rows)
    print("--- VGA screen ---")
    print(screen)
    print("------------------")

    ok = True
    if "AxOS v0.5" not in screen:
        print("FAIL: boot banner 'AxOS v0.5' not found")
        ok = False
    if "AxOS>" not in screen:
        print("FAIL: shell prompt 'AxOS>' not found")
        ok = False
    if "PAGE FAULT" in screen:
        print("FAIL: '*** PAGE FAULT ***' detected")
        ok = False

    if ok:
        print("OK: AxOS booted to the shell prompt")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
