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
import subprocess
import sys
import time

from qemu_test_helpers import connect_monitor, dump_screen, launch_qemu, send_text, wait_for_text

IMAGE = os.path.join("build", "os-image.bin")
DISK_IMAGE = os.path.join("build", "disk.img")
MONITOR_PORT = 55591
DUMP_FILE = "vga_dump_selftest.bin"
BOOT_TIMEOUT_SEC = 60
TEST_POLL_INTERVAL_SEC = 3
# 90s was cutting it close - a real (non-hung) run under qemu-system-x86_64
# -cpu Broadwell (the fixed CPU/binary, see qemu_test_helpers.py) measured
# ~65-70s just for the FAT12 sub-test's two full fat12_flush() round trips
# (128 IDE sector writes each) once actually timed end-to-end, on top of
# boot + exit + selftest startup - confirmed via a longer manual watch that
# it reaches "SELFTEST: ALL PASS" cleanly, just later than 90s allowed.
TEST_MAX_WAIT_SEC = 150


def main():
    if not os.path.isfile(IMAGE):
        print(f"FAIL: {IMAGE} not found - did the build step run?")
        return 1

    proc = launch_qemu(IMAGE, DISK_IMAGE, MONITOR_PORT)

    try:
        time.sleep(2)  # let QEMU's own host-side monitor server come up

        sock = connect_monitor(MONITOR_PORT)
        wait_for_text(sock, DUMP_FILE, ["AxSH v0.1"], timeout=BOOT_TIMEOUT_SEC)
        # AxSH's own keyboard handling needs a moment after the banner
        # appears - sending input immediately can drop/garble the first
        # few characters (seen intermittently: "ai ask" -> "a ask").
        time.sleep(1)

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
            screen = dump_screen(sock, DUMP_FILE)
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
