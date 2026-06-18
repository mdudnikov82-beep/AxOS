#!/usr/bin/env python3
# Smoke test for the ANSI parser in screen.c: boots AxOS, types ANSI escape
# sequences through the real "echo" shell builtin (which just calls
# print_string on its argument with no special-casing), and dumps the VGA
# buffer (char + attribute byte) to confirm colors/clear actually happened -
# not just that text printed.

import os
import socket
import subprocess
import time

IMAGE = os.path.join("build", "os-image.bin")
DISK_IMAGE = os.path.join("build", "disk.img")
MONITOR_PORT = 55592
DUMP_FILE = "vga_dump_ansi.bin"

QEMU_CANDIDATES = [
    r"C:\Program Files\qemu\qemu-system-i386.exe",
    "qemu-system-i386",
]

KEYMAP = {
    ' ': 'spc', '\n': 'ret', '\x1b': 'esc',
    '[': 'bracket_left', ']': 'bracket_right',
}


def find_qemu():
    for c in QEMU_CANDIDATES:
        if os.path.isfile(c):
            return c
    return QEMU_CANDIDATES[-1]


def decode_vga(data):
    rows = []
    for row in range(25):
        chars = ""
        attrs = []
        for col in range(80):
            ch = data[(row * 80 + col) * 2]
            attr = data[(row * 80 + col) * 2 + 1]
            chars += chr(ch) if 32 <= ch < 127 else (" " if ch == 0 else ".")
            if ch != 0:
                attrs.append(attr)
        rows.append((chars.rstrip(), attrs))
    return rows


def sendkey_str(sock, text):
    for c in text:
        if c in KEYMAP:
            key = KEYMAP[c]
        elif c.isalpha() and c.isupper():
            key = f"shift-{c.lower()}"  # ANSI final bytes are case-sensitive (e.g. "J" vs "j")
        else:
            key = c.lower()
        sock.sendall(f"sendkey {key}\n".encode())
        time.sleep(0.35)


def dump(sock, label):
    if os.path.isfile(DUMP_FILE):
        os.remove(DUMP_FILE)
    sock.sendall(f"pmemsave 0xb8000 4000 {DUMP_FILE}\n".encode())
    for _ in range(20):
        if os.path.isfile(DUMP_FILE):
            break
        time.sleep(0.2)
    with open(DUMP_FILE, "rb") as f:
        data = f.read()
    os.remove(DUMP_FILE)
    print(f"--- {label} ---")
    for text, attrs in decode_vga(data):
        if text.strip():
            print(f"{text!r:90} attrs={attrs}")
    print()


def main():
    qemu = find_qemu()
    args = [
        qemu,
        "-drive", f"format=raw,file={IMAGE},if=floppy",
        "-drive", f"format=raw,file={DISK_IMAGE},if=ide,index=0,media=disk",
        "-boot", "a",
        "-display", "none",
        "-monitor", f"tcp:127.0.0.1:{MONITOR_PORT},server,nowait",
        "-no-reboot",
    ]
    proc = subprocess.Popen(args)

    try:
        time.sleep(4)
        sock = socket.create_connection(("127.0.0.1", MONITOR_PORT), timeout=10)
        sock.recv(4096)

        dump(sock, "after boot")

        # AUTOSTART=shell boots straight into AxSH (userspace shell), which
        # claims the keyboard from kernel_shell - "exit" hands it back so we
        # can reach "echo" (a kernel_shell builtin) at the "AxOS>" prompt.
        sendkey_str(sock, "exit\n")
        time.sleep(1)

        sendkey_str(sock, "echo \x1b[31mRED\x1b[0m \x1b[32mGREEN\x1b[0m \x1b[34mBLUE\x1b[0m\n")
        time.sleep(1)
        dump(sock, "after echo with \\033[31m/32m/34m/0m")

        sendkey_str(sock, "echo \x1b[2J\n")
        time.sleep(1)
        dump(sock, "after echo with \\033[2J")

        sock.sendall(b"quit\n")
        time.sleep(1)
        sock.close()
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


if __name__ == "__main__":
    main()
