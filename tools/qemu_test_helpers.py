#!/usr/bin/env python3
# Общий код для headless-тестов AxOS в QEMU (smoke_test.py, regression_test.py,
# exec_regression_test.py) - до этого файла каждый тест нёс свою копию
# find_qemu()/decode_vga()/QEMU_CANDIDATES (и send_text()/KEY_NAMES в двух
# из трёх), которые расходились по мелочам. Конкретно из-за этого
# exec_regression_test.py при первом запуске тихо терял argv-строки:
# его собственная send_text() не приводила буквы к нижнему регистру (а
# QEMU monitor "sendkey" понимает только нижний регистр) и не знала про
# "-" - обе вещи уже были решены в более старой копии, но по-другому и не
# везде. Один общий модуль - один источник истины для этих деталей.

import os
import socket
import subprocess
import time

QEMU_CANDIDATES = [
    r"C:\Program Files\qemu\qemu-system-i386.exe",
    "qemu-system-i386",
]

# Имена клавиш QEMU monitor "sendkey" для символов, у которых имя клавиши
# не совпадает с самим символом. Всё остальное - send_text() переводит в
# нижний регистр и шлёт как есть (QEMU не знает имён клавиш в верхнем
# регистре - "E" как имя клавиши не существует, нужен либо "e", либо
# "shift-e").
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


def launch_qemu(image, disk_image, monitor_port):
    qemu = find_qemu()
    args = [
        qemu,
        "-drive", f"format=raw,file={image},if=floppy",
    ]
    if os.path.isfile(disk_image):
        args += ["-drive", f"format=raw,file={disk_image},if=ide,index=0,media=disk"]
    args += [
        "-boot", "a",
        "-display", "none",
        "-monitor", f"tcp:127.0.0.1:{monitor_port},server,nowait",
        "-no-reboot",
    ]
    return subprocess.Popen(args)


def connect_monitor(monitor_port, timeout=10):
    sock = socket.create_connection(("127.0.0.1", monitor_port), timeout=timeout)
    sock.recv(4096)  # monitor banner
    return sock


def dump_screen(sock, dump_file="vga_dump.bin", settle_sec=0.3):
    """Снимает VGA text buffer через monitor "pmemsave" и возвращает
    декодированный экран (см. decode_vga). Ждёт появления файла (QEMU
    пишет его асинхронно) вместо фиксированного sleep."""
    sock.sendall(f"pmemsave 0xb8000 4000 {dump_file}\n".encode())
    for _ in range(20):
        if os.path.isfile(dump_file):
            break
        time.sleep(0.1)
    time.sleep(settle_sec)
    if not os.path.isfile(dump_file):
        return ""
    with open(dump_file, "rb") as f:
        data = f.read()
    os.remove(dump_file)
    return "\n".join(decode_vga(data))
