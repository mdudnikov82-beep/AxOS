#!/usr/bin/env python3
# Headless smoke-test for AxOS/RV64: boots rv64build/out/kernel.elf +
# rv64build/disk.img in QEMU and checks that the AxSH prompt came up
# cleanly. Unlike x86 (VGA text buffer via the QEMU monitor), RISC-V
# AxSH reads/writes the real serial UART directly, so this connects to
# QEMU's serial port over TCP and reads the live text stream instead of
# polling a monitor snapshot.

import os
import socket
import subprocess
import sys
import time

QEMU_CANDIDATES = [
    r"C:\Program Files\qemu\qemu-system-riscv64.exe",
    "qemu-system-riscv64",
]

KERNEL = os.path.join("rv64build", "out", "kernel.elf")
DISK_IMAGE = os.path.join("rv64build", "disk.img")
SERIAL_PORT = 55594
BOOT_TIMEOUT_SEC = 60


def find_qemu():
    for c in QEMU_CANDIDATES:
        if os.path.isfile(c):
            return c
    return QEMU_CANDIDATES[-1]


def launch_qemu():
    qemu = find_qemu()
    args = [
        qemu, "-M", "virt", "-bios", "default", "-kernel", KERNEL,
        "-display", "none",
        "-serial", f"tcp:127.0.0.1:{SERIAL_PORT},server,nowait",
        "-device", "virtio-gpu-device",
        "-device", "virtio-keyboard-device",
        "-device", "virtio-tablet-device",
    ]
    if os.path.isfile(DISK_IMAGE):
        args += [
            "-drive", f"file={DISK_IMAGE},if=none,id=hd0,format=raw",
            "-device", "virtio-blk-device,drive=hd0",
        ]
    return subprocess.Popen(args)


def main():
    if not os.path.isfile(KERNEL):
        print(f"FAIL: {KERNEL} not found - did the build step run?")
        return 1
    if not os.path.isfile(DISK_IMAGE):
        print(f"FAIL: {DISK_IMAGE} not found - did the build step run?")
        return 1

    proc = launch_qemu()
    buf = ""
    try:
        sock = None
        for _ in range(30):
            try:
                sock = socket.create_connection(("127.0.0.1", SERIAL_PORT), timeout=5)
                break
            except OSError:
                time.sleep(1)
        if sock is None:
            print("FAIL: could not connect to QEMU serial port")
            return 1

        sock.settimeout(2)
        deadline = time.time() + BOOT_TIMEOUT_SEC
        while time.time() < deadline:
            try:
                d = sock.recv(4096)
                if d:
                    buf += d.decode(errors="replace")
            except socket.timeout:
                pass
            if "AxOS>" in buf or "[TRAP] kernel halted" in buf:
                break
        sock.close()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    print("--- serial output (tail) ---")
    print(buf[-2000:])
    print("----------------------------")

    ok = True
    if "AxOS>" not in buf:
        print("FAIL: AxSH prompt 'AxOS>' not found")
        ok = False
    if "[TRAP] kernel halted" in buf:
        print("FAIL: kernel halted on an unhandled trap")
        ok = False

    if ok:
        print("OK: AxOS/RV64 booted to the AxSH prompt")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
