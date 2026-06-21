#!/usr/bin/env python3
# Regression test for AxOS: boots build/os-image.bin (+ build/disk.img) in
# QEMU. AUTOSTART=shell (fs/STARTUP.CFG) hands the keyboard to AxSH
# (sh.bin) on boot, so the kernel-level "selftest" command (kernel.c) is
# unreachable until "exit" hands the console back to the ring0 shell
# (AxOS> prompt) - see sh.c's ax_shell_claim(0) on exit. Then types
# "selftest" and polls until the heap/paging/FAT12 self-test reports
# "SELFTEST: ALL PASS" - the FAT12 sub-test does two full fat12_flush()
# round-trips (128 IDE sector writes each) and can take anywhere from a
# few seconds to ~40s depending on QEMU/host speed, so we poll instead of
# sleeping a fixed amount.

import os
import socket
import subprocess
import sys
import time

IMAGE = os.path.join("build", "os-image.bin")
DISK_IMAGE = os.path.join("build", "disk.img")
MONITOR_PORT = 55591
DUMP_FILE = "vga_dump_selftest.bin"
BOOT_WAIT_SEC = 10
TEST_POLL_INTERVAL_SEC = 3
TEST_MAX_WAIT_SEC = 90

QEMU_CANDIDATES = [
    r"C:\Program Files\qemu\qemu-system-i386.exe",
    "qemu-system-i386",
]

# Карта символов команды "selftest" на имена клавиш QEMU monitor "sendkey".
KEY_NAMES = {
    " ": "spc",
    ".": "dot",
}


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


def send_text(sock, text):
    for ch in text:
        key = KEY_NAMES.get(ch, ch)
        sock.sendall(f"sendkey {key}\n".encode())
        time.sleep(0.05)


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

        # "exit" hands the keyboard from AxSH back to the kernel shell
        # (AUTOSTART=shell auto-launches AxSH on boot - see module docstring).
        send_text(sock, "exit")
        sock.sendall(b"sendkey ret\n")
        time.sleep(1.5)

        send_text(sock, "selftest")
        sock.sendall(b"sendkey ret\n")

        screen = ""
        waited = 0.0
        while waited < TEST_MAX_WAIT_SEC:
            time.sleep(TEST_POLL_INTERVAL_SEC)
            waited += TEST_POLL_INTERVAL_SEC
            sock.sendall(f"pmemsave 0xb8000 4000 {DUMP_FILE}\n".encode())
            time.sleep(0.3)
            if not os.path.isfile(DUMP_FILE):
                continue
            with open(DUMP_FILE, "rb") as f:
                data = f.read()
            os.remove(DUMP_FILE)
            screen = "\n".join(decode_vga(data))
            if "SELFTEST: ALL PASS" in screen or "SELFTEST: FAILED" in screen:
                break

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
    if "SELFTEST: ALL PASS" not in screen:
        print("FAIL: 'SELFTEST: ALL PASS' not found")
        ok = False
    if "SELFTEST: FAILED" in screen:
        print("FAIL: 'SELFTEST: FAILED' detected")
        ok = False
    if "PAGE FAULT" in screen:
        print("FAIL: '*** PAGE FAULT ***' detected")
        ok = False

    if ok:
        print("OK: self-test passed (SELFTEST: ALL PASS)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
