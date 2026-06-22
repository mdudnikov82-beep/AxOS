#!/usr/bin/env python3
# Regression test for the ELF32 program loader (src/kernel/elf.c, run/
# SYS_EXEC in kernel.c). smoke_test.py/regression_test.py never call
# do_exec() directly - selftest.c (kernel-side "selftest" command) only
# exercises heap/paging/FAT12 - so the loader is only covered INCIDENTALLY,
# because AxSH itself (SH.BIN) is loaded through the exact same "run "
# path at boot. That catches "the loader is completely broken" but not
# subtler regressions (argv passing, the kernel-shell "run " path
# specifically, as opposed to AxSH's ax_exec/SYS_EXEC path).
#
# This test exercises both code paths with a program that takes argv
# (ECHO.BIN) and checks the echoed text actually appears on screen:
#   1. AxSH's "echo <args>" -> ax_exec()/SYS_EXEC -> do_exec()
#   2. kernel shell's "run ECHO.BIN <args>" -> execute_command()'s own
#      copy of the same loading logic

import os
import socket
import subprocess
import sys
import time

IMAGE = os.path.join("build", "os-image.bin")
DISK_IMAGE = os.path.join("build", "disk.img")
MONITOR_PORT = 55592
DUMP_FILE = "vga_dump_exec.bin"
BOOT_WAIT_SEC = 10

QEMU_CANDIDATES = [
    r"C:\Program Files\qemu\qemu-system-i386.exe",
    "qemu-system-i386",
]

KEY_NAMES = {
    " ": "spc",
    ".": "dot",
    "-": "minus",
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
        key = KEY_NAMES.get(ch, ch.lower())
        sock.sendall(f"sendkey {key}\n".encode())
        time.sleep(0.05)


def dump_screen(sock):
    sock.sendall(f"pmemsave 0xb8000 4000 {DUMP_FILE}\n".encode())
    for _ in range(20):
        if os.path.isfile(DUMP_FILE):
            break
        time.sleep(0.1)
    time.sleep(0.3)
    if not os.path.isfile(DUMP_FILE):
        return ""
    with open(DUMP_FILE, "rb") as f:
        data = f.read()
    os.remove(DUMP_FILE)
    return "\n".join(decode_vga(data))


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

    ok = True
    screen_axsh = ""
    screen_run = ""
    try:
        time.sleep(BOOT_WAIT_SEC)

        sock = socket.create_connection(("127.0.0.1", MONITOR_PORT), timeout=10)
        sock.recv(4096)  # monitor banner

        # 1) AxSH path: ax_exec()/SYS_EXEC -> do_exec()
        send_text(sock, "echo axsh-exec-path-ok")
        sock.sendall(b"sendkey ret\n")
        time.sleep(1.5)
        screen_axsh = dump_screen(sock)

        # 2) kernel-shell path: execute_command()'s own "run " branch
        send_text(sock, "exit")
        sock.sendall(b"sendkey ret\n")
        time.sleep(1.5)
        send_text(sock, "run ECHO.BIN run-path-ok")
        sock.sendall(b"sendkey ret\n")
        time.sleep(1.5)
        screen_run = dump_screen(sock)

        sock.sendall(b"quit\n")
        time.sleep(1)
        sock.close()
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    if not screen_axsh or not screen_run:
        print("FAIL: VGA dump was not created (QEMU may have failed to boot)")
        return 1

    print("--- AxSH (ax_exec/SYS_EXEC path) ---")
    print(screen_axsh)
    print("--- kernel shell ('run ' path) ---")
    print(screen_run)
    print("------------------------------------")

    if "axsh-exec-path-ok" not in screen_axsh:
        print("FAIL: AxSH 'echo axsh-exec-path-ok' did not echo back")
        ok = False
    if "run-path-ok" not in screen_run:
        print("FAIL: kernel shell 'run ECHO.BIN run-path-ok' did not echo back")
        ok = False
    if "Not a valid AxOS ELF executable" in screen_run:
        print("FAIL: ECHO.BIN was rejected as an invalid ELF")
        ok = False
    if "PAGE FAULT" in screen_axsh or "PAGE FAULT" in screen_run:
        print("FAIL: '*** PAGE FAULT ***' detected")
        ok = False

    if ok:
        print("OK: ELF loader works on both the AxSH (ax_exec) and kernel-shell (run) paths")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
