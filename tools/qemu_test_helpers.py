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

# qemu-system-i386 emulates a 32-bit-only CPU by default (no long mode
# support at all) - AxOS's kernel is x86-64 and enters long mode during
# boot.asm's protected-mode-to-long-mode transition. Booting under plain
# qemu-system-i386 makes that transition's far jump into the 64-bit code
# segment raise #GP (the CPU architecturally can't honor it), cascading
# into a double fault then triple fault within the first few instructions
# of long-mode setup - QEMU exits near-instantly (clean exit 0, since
# -no-reboot converts the guest reset into a process exit) with no visible
# error, which looks exactly like "QEMU never started" from the test
# script's side. Verified live: qemu-system-x86_64 -cpu Broadwell boots
# the identical image/disk to the real AxSH banner with no other changes.
QEMU_CANDIDATES = [
    r"C:\Program Files\qemu\qemu-system-x86_64.exe",
    "qemu-system-x86_64",
]
QEMU_CPU = "Broadwell"

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
    # 0.05s was too fast once tests actually reached AxSH's prompt (only
    # possible after fixing the QEMU CPU/binary above) - characters were
    # being silently dropped mid-command ("echo axsh-exec-path-ok" typed
    # as "ech xsh-xc-ah-ok", "exit" as "xt"), a real HMP-sendkey/guest-
    # keyboard-IRQ race, not random - confirmed reproducible across
    # repeated runs with different characters dropped each time.
    for ch in text:
        key = KEY_NAMES.get(ch, ch.lower())
        sock.sendall(f"sendkey {key}\n".encode())
        time.sleep(0.15)


def launch_qemu(image, disk_image, monitor_port):
    qemu = find_qemu()
    args = [
        qemu,
        "-cpu", QEMU_CPU,
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


def connect_monitor(monitor_port, timeout=30):
    """Retries for up to `timeout` seconds total (was a single connect()
    attempt) - QEMU's monitor listener isn't always up immediately after
    Popen returns. A fixed 2s sleep before the one attempt worked locally
    but produced an immediate ConnectionRefusedError on a fresh GitHub
    Actions runner (colder/slower VM, possibly extra antivirus-scan
    latency on a just-installed qemu.exe) - only surfaced once actually
    tested in that environment, not locally."""
    deadline = time.time() + timeout
    last_err = None
    while time.time() < deadline:
        try:
            sock = socket.create_connection(("127.0.0.1", monitor_port), timeout=2)
            sock.recv(4096)  # monitor banner
            return sock
        except OSError as e:
            last_err = e
            time.sleep(0.5)
    raise last_err


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


def wait_for_text(sock, dump_file, needles, timeout=60, poll_interval=2):
    """Опрашивает экран, пока не появится любая строка из needles, или не
    истечёт timeout. Раньше каждый тест делал один фиксированный
    time.sleep(BOOT_WAIT_SEC) перед первым dump_screen - ок на локальной
    машине с аппаратным ускорением QEMU (KVM/HAXM), но GitHub Actions
    Windows runner-ы его не дают, так что QEMU там работает в чистой
    программной эмуляции (TCG) и грузится заметно дольше: на CI 10
    секунд не хватало даже на загрузочный баннер - VGA-экран приходил
    полностью пустым. Поллинг переживает разную скорость хоста, в
    отличие от угаданной константы."""
    deadline = time.time() + timeout
    screen = ""
    while time.time() < deadline:
        screen = dump_screen(sock, dump_file)
        if any(n in screen for n in needles):
            return screen
        time.sleep(poll_interval)
    return screen
