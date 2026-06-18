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

QEMU_CANDIDATES = [
    r"C:\Program Files\qemu\qemu-system-i386.exe",
    "qemu-system-i386",
]

KEYMAP = {
    ' ': 'spc', '\n': 'ret', '.': 'dot', '/': 'slash', '-': 'minus',
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
        key = KEYMAP.get(c, c.lower())
        sock.sendall(f"sendkey {key}\n".encode())
        sock.recv(4096)
        time.sleep(0.12)


def dump(sock, label):
    sock.sendall(f"pmemsave 0xb8000 4000 {DUMP_FILE}\n".encode())
    time.sleep(0.5)
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

        for label, cmd in [
            ("after unlock", "unlock\n"),
            ("after ls", "ls\n"),
            ("after mkdir TESTDIR", "mkdir TESTDIR\n"),
            ("after ls (should show TESTDIR)", "ls\n"),
            ("after cd TESTDIR", "cd TESTDIR\n"),
            ("after ls inside TESTDIR", "ls\n"),
            ("after cd ..", "cd ..\n"),
            ("after rm HELLO.BIN", "rm HELLO.BIN\n"),
            ("after ls (HELLO.BIN gone?)", "ls\n"),
        ]:
            sendkey_str(sock, cmd)
            time.sleep(1)
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
