#!/usr/bin/env python3
# Regression test for AxOS/RV64: boots rv64build/out/kernel.elf +
# rv64build/disk.img in QEMU, then runs a small battery of test ELF
# programs via AxSH's "run" command and checks their output/exit codes:
#   - FORKTEST.ELF   - fork()/process model
#   - SCDEMO.ELF ok  - seccomp syscall filtering ("[seccomp ok] ALL PASS")
#   - MTETEST.ELF    - heap allocator + software MTE tagging ("all checks passed")
# Same serial-console approach as smoke_test_riscv.py (RISC-V AxSH reads/
# writes the real UART, not a VGA text buffer) and the same -S/monitor/
# cont startup (avoids the "server,nowait" discards-output-before-connect
# race that broke the plain smoke test on a fresh CI runner) and explicit
# UTF-8 stdout (the ANSI-escaped serial stream isn't always cp1252-safe).

import os
import socket
import subprocess
import sys
import time

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

QEMU_CANDIDATES = [
    r"C:\Program Files\qemu\qemu-system-riscv64.exe",
    "qemu-system-riscv64",
]

KERNEL = os.path.join("rv64build", "out", "kernel.elf")
DISK_IMAGE = os.path.join("rv64build", "disk.img")
SERIAL_PORT = 55596
MONITOR_PORT = 55597
BOOT_TIMEOUT_SEC = 60
CMD_TIMEOUT_SEC = 20


def find_qemu():
    for c in QEMU_CANDIDATES:
        if os.path.isfile(c):
            return c
    return QEMU_CANDIDATES[-1]


def launch_qemu():
    qemu = find_qemu()
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


def read_until(sock, buf, needles, timeout, start=0):
    # Only checks buf[0][start:] for the needles - callers waiting for a
    # marker that may already exist earlier in the accumulated transcript
    # (e.g. "AxOS>", already seen once at boot) must pass the offset where
    # THIS wait began, or it would return true immediately on stale data.
    sock.settimeout(1)
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            d = sock.recv(4096)
            if d:
                buf[0] += d.decode(errors="replace")
        except socket.timeout:
            pass
        if any(n in buf[0][start:] for n in needles):
            return True
    return False


def main():
    if not os.path.isfile(KERNEL) or not os.path.isfile(DISK_IMAGE):
        print("FAIL: build artifacts not found - did the build step run?")
        return 1

    proc = launch_qemu()
    buf = [""]
    results = []
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

        if not read_until(sock, buf, ["AxOS>"], BOOT_TIMEOUT_SEC):
            print("FAIL: AxSH prompt not found within boot timeout")
            print(buf[0][-2000:])
            return 1
        print("boot OK")

        # Precisely slicing each command's own output turned out fragile -
        # a trailing exit-code digit (or, for a longer-running program, a
        # chunk of its own output) can land in a TCP segment that arrives
        # just after the naive "prompt reappeared" cutoff, splitting a
        # single logical line/marker across what looked like two commands'
        # captured slices. Simpler and robust: just pace through each
        # command (waiting for the prompt mostly to avoid overlapping
        # input), then check the WHOLE accumulated transcript for each
        # program's known-good marker strings at the end - each marker is
        # distinctive enough that a false positive from a different test
        # isn't a real concern here.
        commands = ["run FORKTEST.ELF", "run SCDEMO.ELF ok", "run MTETEST.ELF"]
        for cmd in commands:
            # AxSH's own input handling needs a brief moment after the
            # prompt reappears - sending the next command in the same
            # instant it's detected can race the shell still settling
            # back into its read loop. Also, sending the whole command in
            # one sendall() burst can drop characters mid-string (seen
            # live: "run MTETEST.ELF" arrived as just "ru") - same class
            # of keystroke-loss bug already found and fixed for x86's
            # send_text() this session. Type it one character at a time
            # with a small delay instead.
            time.sleep(0.5)
            start = len(buf[0])
            for ch in cmd + "\r\n":
                sock.sendall(ch.encode())
                time.sleep(0.05)
            if not read_until(sock, buf, ["AxOS>"], CMD_TIMEOUT_SEC, start=start):
                print(f"WARN: prompt didn't reappear in time after '{cmd}' - continuing anyway")

        sock.close()
        msock.close()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    print("--- full serial transcript ---")
    print(buf[0])
    print("-------------------------------")

    checks = [
        ("forktest: I am the PARENT", "fork() - parent branch ran"),
        ("forktest: I am the CHILD", "fork() - child branch ran"),
        ("[seccomp ok] ALL PASS", "seccomp syscall filtering"),
        ("mtetest: all checks passed", "heap allocator + software MTE tagging"),
    ]
    ok = True
    for marker, label in checks:
        if marker in buf[0]:
            print(f"OK: {label}")
        else:
            print(f"FAIL: {label} - marker not found: {marker!r}")
            ok = False

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
