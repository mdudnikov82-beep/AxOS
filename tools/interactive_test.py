#!/usr/bin/env python3
# Ad-hoc interactive smoke test: boots AxOS, types commands into the booted
# shell via the QEMU monitor's "sendkey", and dumps the VGA text buffer
# after each command so we can see what actually happened (crash, freeze,
# garbled output, etc.) instead of guessing.

import os
import socket
import subprocess
import sys
import time

IMAGE = os.path.join("build", "os-image.bin")
DISK_IMAGE = os.path.join("build", "disk.img")
MONITOR_PORT = 55591
DUMP_FILE = "vga_dump2.bin"

# qemu-system-i386 has no long mode by default - see qemu_test_helpers.py's
# QEMU_CANDIDATES comment for the full story (real triple fault on boot).
QEMU_CANDIDATES = [
    r"C:\Program Files\qemu\qemu-system-x86_64.exe",
    "qemu-system-x86_64",
]
QEMU_CPU = "Broadwell"

KEYMAP = {
    ' ': 'spc', '\n': 'ret', '.': 'dot', '/': 'slash', '-': 'minus',
}

# Символы, набираемые через Shift на US-раскладке: QEMU sendkey принимает
# комбинацию "shift-<base>" как один press/release обоих клавиш.
SHIFT_MAP = {
    '_': 'minus', '&': '7', '!': '1', '@': '2', '#': '3', '$': '4',
    '%': '5', '^': '6', '*': '8', '(': '9', ')': '0', '+': 'equal',
}

def find_qemu():
    for c in QEMU_CANDIDATES:
        if os.path.isfile(c):
            return c
    return QEMU_CANDIDATES[-1]


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


def sendkey_str(sock, text):
    for c in text:
        if c in SHIFT_MAP:
            key = f"shift-{SHIFT_MAP[c]}"
        else:
            key = KEYMAP.get(c, c.lower())
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
    print("\n".join(decode_vga(data)))
    print()


def main():
    qemu = find_qemu()
    args = [
        qemu,
        "-cpu", QEMU_CPU,
        "-drive", f"format=raw,file={IMAGE},if=floppy",
        "-drive", f"format=raw,file={DISK_IMAGE},if=ide,index=0,media=disk",
        "-boot", "a",
        "-display", "none",
        "-monitor", f"tcp:127.0.0.1:{MONITOR_PORT},server,nowait",
        "-no-reboot",
        "-d", "guest_errors,int",
        "-D", "qemu_log.txt",
    ]
    proc = subprocess.Popen(args)

    try:
        time.sleep(4)
        sock = socket.create_connection(("127.0.0.1", MONITOR_PORT), timeout=10)
        sock.recv(4096)

        dump(sock, "after boot")

        for label, cmd, extra_wait in [
            ("after unlock", "unlock\n", 0),
            ("launch sleep in background", "sleep &\n", 0),
            ("prompt returned immediately?", "ps\n", 0),
            ("ps again 1.5s later (still sleeping?)", "ps\n", 1.5),
            ("ps after ~4s total (background should have exited)", "ps\n", 2.5),
            ("launch top in background, then ls", "top &\n", 0.5),
            ("confirm shell still responsive after launching top bg", "ls\n", 0),
            ("ps with top still looping in background", "ps\n", 1.5),
        ]:
            sendkey_str(sock, cmd)
            time.sleep(1 + extra_wait)
            dump(sock, label)
            alive = proc.poll() is None
            print(f"QEMU process alive: {alive}")
            if not alive:
                break

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
