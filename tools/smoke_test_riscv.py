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
MONITOR_PORT = 55595
BOOT_TIMEOUT_SEC = 60


def find_qemu():
    for c in QEMU_CANDIDATES:
        if os.path.isfile(c):
            return c
    return QEMU_CANDIDATES[-1]


def launch_qemu():
    qemu = find_qemu()
    # -S: start with the guest CPU PAUSED. "-serial ...,server,nowait"
    # silently DISCARDS anything the guest writes to the UART before a
    # client connects - a plain "retry connect() in a loop" race worked
    # locally but lost the entire boot transcript on the CI runner
    # (presumably different relative timing between QEMU's socket-bind
    # and the guest actually starting to execute). Connecting the serial
    # AND monitor sockets first, then explicitly resuming via the
    # monitor's "cont", guarantees nothing written before that point can
    # ever be missed - same fix already used successfully elsewhere this
    # session for an identical class of flake.
    args = [
        qemu, "-M", "virt", "-bios", "default", "-kernel", KERNEL,
        "-display", "none", "-S",
        "-serial", f"tcp:127.0.0.1:{SERIAL_PORT},server,nowait",
        "-monitor", f"tcp:127.0.0.1:{MONITOR_PORT},server,nowait",
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


def connect_retry(port, timeout=5, attempts=30, delay=1):
    for _ in range(attempts):
        try:
            return socket.create_connection(("127.0.0.1", port), timeout=timeout)
        except OSError:
            time.sleep(delay)
    return None


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
        sock = connect_retry(SERIAL_PORT)
        if sock is None:
            print("FAIL: could not connect to QEMU serial port")
            return 1

        msock = connect_retry(MONITOR_PORT)
        if msock is None:
            print("FAIL: could not connect to QEMU monitor port")
            return 1
        time.sleep(0.3)
        msock.recv(4096)  # drain the "(qemu)" banner
        msock.sendall(b"cont\n")  # both sockets connected - safe to let the guest CPU run now

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
        msock.close()
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
