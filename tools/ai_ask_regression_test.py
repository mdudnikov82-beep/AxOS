#!/usr/bin/env python3
# Regression test for "ai ask" (src/user/ai.c) - the Q&A REPL added on top
# of the XOR/boolean-function MLP demo. Without this, the dispatch in
# main() that routes "ai ask" away from parse_bits() (and the keyword
# lookup in find_answer()/QA_DB) is only covered by manual QEMU testing -
# a regression there (e.g. "ask" falling through to the "invalid pattern"
# path, or a keyword match breaking) would go unnoticed until someone
# happens to run it by hand.
#
# Exercises three things: an exact keyword match ("what is axos"), a
# substring match inside a single bare keyword ("xor"), the no-match
# fallback, and a clean "exit" back to the AxSH prompt.

import os
import subprocess
import sys
import time

from qemu_test_helpers import connect_monitor, dump_screen, launch_qemu, send_text, wait_for_text

IMAGE = os.path.join("build", "os-image.bin")
DISK_IMAGE = os.path.join("build", "disk.img")
MONITOR_PORT = 55593
DUMP_FILE = "vga_dump_ai_ask.bin"
BOOT_TIMEOUT_SEC = 60
POLL_INTERVAL_SEC = 1
MAX_WAIT_SEC = 30


def unwrapped(screen):
    """VGA text mode hard-wraps at column 80, splitting a long answer
    mid-word across two dumped lines (e.g. "...(Minsky/Paper" / "t) -
    ..."). Dropping the newlines reconstructs the original unwrapped text
    so substring checks below don't land exactly on a wrap boundary."""
    return screen.replace("\n", "")


def wait_for(sock, needles, max_wait=MAX_WAIT_SEC):
    """Sleep-and-poll until any of `needles` shows up on screen, like
    regression_test.py's selftest wait - avoids a fixed sleep that's
    either too short (flaky) or too long (slow) for QEMU/host speed."""
    waited = 0.0
    screen = ""
    while waited < max_wait:
        time.sleep(POLL_INTERVAL_SEC)
        waited += POLL_INTERVAL_SEC
        screen = dump_screen(sock, DUMP_FILE)
        if any(n in unwrapped(screen) for n in needles):
            break
    return screen


def main():
    if not os.path.isfile(IMAGE):
        print(f"FAIL: {IMAGE} not found - did the build step run?")
        return 1

    proc = launch_qemu(IMAGE, DISK_IMAGE, MONITOR_PORT)

    ok = True
    screen_banner = screen_q1 = screen_q2 = screen_fallback = screen_exit = ""
    try:
        time.sleep(2)  # let QEMU's own host-side monitor server come up

        sock = connect_monitor(MONITOR_PORT)
        wait_for_text(sock, DUMP_FILE, ["AxSH v0.1"], timeout=BOOT_TIMEOUT_SEC)

        send_text(sock, "ai ask")
        sock.sendall(b"sendkey ret\n")
        screen_banner = wait_for(sock, ["ask me something"])

        # exact keyword match (the whole question is a stored keyword)
        send_text(sock, "what is axos")
        sock.sendall(b"sendkey ret\n")
        screen_q1 = wait_for(sock, ["32-bit x86 OS"])

        # substring match: a single bare keyword, not a full question
        send_text(sock, "xor")
        sock.sendall(b"sendkey ret\n")
        screen_q2 = wait_for(sock, ["Minsky/Papert"])

        # no keyword matches anything in QA_DB -> default fallback
        send_text(sock, "what is the meaning of life")
        sock.sendall(b"sendkey ret\n")
        screen_fallback = wait_for(sock, ["don't know that one yet"])

        send_text(sock, "exit")
        sock.sendall(b"sendkey ret\n")
        time.sleep(3)
        screen_exit = dump_screen(sock, DUMP_FILE)

        sock.sendall(b"quit\n")
        time.sleep(1)
        sock.close()
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    if not screen_banner:
        print("FAIL: VGA dump was not created (QEMU may have failed to boot)")
        return 1

    print("--- after 'ai ask' ---")
    print(screen_banner)
    print("--- after 'what is axos' ---")
    print(screen_q1)
    print("--- after 'xor' ---")
    print(screen_q2)
    print("--- after unknown question ---")
    print(screen_fallback)
    print("--- after 'exit' ---")
    print(screen_exit)

    if "ask me something" not in unwrapped(screen_banner):
        print("FAIL: 'ai ask' banner did not appear")
        ok = False
    if "32-bit x86 OS" not in unwrapped(screen_q1):
        print("FAIL: 'what is axos' did not get the expected answer")
        ok = False
    if "Minsky/Papert" not in unwrapped(screen_q2):
        print("FAIL: bare keyword 'xor' did not get the expected answer")
        ok = False
    if "don't know that one yet" not in unwrapped(screen_fallback):
        print("FAIL: an unmatched question did not get the default fallback")
        ok = False
    if "$" not in screen_exit:
        print("FAIL: 'exit' did not return to the AxSH prompt")
        ok = False
    for name, screen in (("banner", screen_banner), ("q1", screen_q1),
                          ("q2", screen_q2), ("fallback", screen_fallback),
                          ("exit", screen_exit)):
        if "PAGE FAULT" in screen:
            print(f"FAIL: '*** PAGE FAULT ***' detected after {name}")
            ok = False

    if ok:
        print("OK: 'ai ask' answers known questions, falls back on unknown ones, and exits cleanly")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
