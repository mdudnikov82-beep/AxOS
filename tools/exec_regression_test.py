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
import subprocess
import sys
import time

from qemu_test_helpers import connect_monitor, dump_screen, launch_qemu, send_text

IMAGE = os.path.join("build", "os-image.bin")
DISK_IMAGE = os.path.join("build", "disk.img")
MONITOR_PORT = 55592
DUMP_FILE = "vga_dump_exec.bin"
BOOT_WAIT_SEC = 10


def main():
    if not os.path.isfile(IMAGE):
        print(f"FAIL: {IMAGE} not found - did the build step run?")
        return 1

    proc = launch_qemu(IMAGE, DISK_IMAGE, MONITOR_PORT)

    ok = True
    screen_axsh = ""
    screen_run = ""
    try:
        time.sleep(BOOT_WAIT_SEC)

        sock = connect_monitor(MONITOR_PORT)

        # 1) AxSH path: ax_exec()/SYS_EXEC -> do_exec()
        send_text(sock, "echo axsh-exec-path-ok")
        sock.sendall(b"sendkey ret\n")
        time.sleep(1.5)
        screen_axsh = dump_screen(sock, DUMP_FILE)

        # 2) kernel-shell path: execute_command()'s own "run " branch
        send_text(sock, "exit")
        sock.sendall(b"sendkey ret\n")
        time.sleep(1.5)
        send_text(sock, "run ECHO.BIN run-path-ok")
        sock.sendall(b"sendkey ret\n")
        time.sleep(1.5)
        screen_run = dump_screen(sock, DUMP_FILE)

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
