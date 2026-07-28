#pragma once

/* AxOS/RV64 user-mode syscall interface.
 * Include this in user programs compiled for riscv64 (or rv32 with adjustments).
 * Convention: a7=nr, a0-a5=args, a0=return value. */

#define SYS_WRITE    1
#define SYS_READ     2
#define SYS_EXIT     3
#define SYS_SBRK     4
#define SYS_GETTIME  5
#define SYS_OPEN     6
#define SYS_CLOSE    7
#define SYS_READDIR  8
#define SYS_GETPID   9
#define SYS_EXEC    10
#define SYS_WAIT    11
#define SYS_YIELD   12
#define SYS_PS      13
#define SYS_KILL    14
#define SYS_WRITEFILE 15
#define SYS_UNLINK  16
#define SYS_POWER   17
#define SYS_GFX_INFO      18
#define SYS_GFX_PUTPIXEL  19
#define SYS_GFX_FILLRECT  20
#define SYS_GFX_FLUSH     21
#define SYS_GFX_DRAWTEXT  22
#define SYS_MOUSE_STATE   23
#define SYS_GFX_GETPIXEL  24
#define SYS_SET_PRIORITY  25
#define SYS_NET_MAC       26
#define SYS_NET_SEND      27
#define SYS_NET_RECV      28
#define SYS_SLEEP         29
#define SYS_EXEC_PIPE     30
#define SYS_FORK          31
#define SYS_SECCOMP       32
#define SYS_SET_LEVEL     33
#define SYS_KBD_GETC      34
#define SYS_WIN_SET_RECT  35
#define SYS_PS_INFO       36
#define SYS_WIN_SET_BASE  37
#define SYS_SOUND_BEEP    38
#define SYS_WIN_SET_TOPMOST 39
#define SYS_WIN_FOCUS       40

static inline long __syscall0(long nr) {
    register long _nr  __asm__("a7") = nr;
    register long _a0  __asm__("a0");
    __asm__ volatile("ecall" : "=r"(_a0) : "r"(_nr) : "memory");
    return _a0;
}

static inline long __syscall1(long nr, long a0) {
    register long _nr  __asm__("a7") = nr;
    register long _a0  __asm__("a0") = a0;
    __asm__ volatile("ecall" : "+r"(_a0) : "r"(_nr) : "memory");
    return _a0;
}

static inline long __syscall2(long nr, long a0, long a1) {
    register long _nr  __asm__("a7") = nr;
    register long _a0  __asm__("a0") = a0;
    register long _a1  __asm__("a1") = a1;
    __asm__ volatile("ecall" : "+r"(_a0) : "r"(_nr), "r"(_a1) : "memory");
    return _a0;
}

static inline long __syscall3(long nr, long a0, long a1, long a2) {
    register long _nr  __asm__("a7") = nr;
    register long _a0  __asm__("a0") = a0;
    register long _a1  __asm__("a1") = a1;
    register long _a2  __asm__("a2") = a2;
    __asm__ volatile("ecall" : "+r"(_a0) : "r"(_nr), "r"(_a1), "r"(_a2) : "memory");
    return _a0;
}

static inline long __syscall4(long nr, long a0, long a1, long a2, long a3) {
    register long _nr  __asm__("a7") = nr;
    register long _a0  __asm__("a0") = a0;
    register long _a1  __asm__("a1") = a1;
    register long _a2  __asm__("a2") = a2;
    register long _a3  __asm__("a3") = a3;
    __asm__ volatile("ecall" : "+r"(_a0) : "r"(_nr), "r"(_a1), "r"(_a2), "r"(_a3) : "memory");
    return _a0;
}

static inline long __syscall5(long nr, long a0, long a1, long a2, long a3, long a4) {
    register long _nr  __asm__("a7") = nr;
    register long _a0  __asm__("a0") = a0;
    register long _a1  __asm__("a1") = a1;
    register long _a2  __asm__("a2") = a2;
    register long _a3  __asm__("a3") = a3;
    register long _a4  __asm__("a4") = a4;
    __asm__ volatile("ecall" : "+r"(_a0)
                     : "r"(_nr), "r"(_a1), "r"(_a2), "r"(_a3), "r"(_a4) : "memory");
    return _a0;
}

/* High-level wrappers */

static inline long write(int fd, const void *buf, long len) {
    return __syscall3(SYS_WRITE, fd, (long)buf, len);
}

static inline long read(int fd, void *buf, long len) {
    return __syscall3(SYS_READ, fd, (long)buf, len);
}

static inline void exit(int code) {
    __syscall1(SYS_EXIT, code);
    __builtin_unreachable();
}

static inline long sbrk(long n) {
    return __syscall1(SYS_SBRK, n);
}

static inline long gettime(void) {
    return __syscall0(SYS_GETTIME);
}

static inline int open(const char *path, int flags) {
    return (int)__syscall3(SYS_OPEN, (long)path, flags, 0);
}

static inline int close(int fd) {
    return (int)__syscall1(SYS_CLOSE, fd);
}

/* readdir(index, name_buf[13], &size) → 1 if found, 0 if done */
static inline int readdir(unsigned int index, char *name_buf, unsigned int *size_out) {
    return (int)__syscall3(SYS_READDIR, (long)index, (long)name_buf, (long)size_out);
}

static inline int getpid(void) {
    return (int)__syscall0(SYS_GETPID);
}

/* fork() → 0 in the child, new pid (>0) in the parent, -1 on error
 * (no free process slot, or OOM copying the address space). Both
 * processes continue executing right after this call, with independent
 * copies of the whole address space - open fds and any active pipe
 * redirect are NOT inherited by the child. */
static inline int fork(void) {
    return (int)__syscall0(SYS_FORK);
}

/* exec(path) → new pid (≥0) or -1 on error.
 * The new process is immediately RUNNABLE; call wait(pid) to block until it exits.
 * path may be "FILENAME.ELF arg1 arg2..." - argv[1..] reach the new
 * process's main(int argc, char **argv). */
static inline int exec(const char *path) {
    return (int)__syscall1(SYS_EXEC, (long)path);
}

/* exec_pipe(cmdline, stdout_pipe_id, stdin_pipe_id) → new pid or -1.
 * stdout_pipe_id >= 0: the new process's write(1/2,...) goes to that
 * pipe instead of UART (and resets the pipe fresh - only ever pass this
 * for the WRITER side of a pipe). stdin_pipe_id >= 0: its read(0,...)
 * blocks on that pipe instead of polling UART (READER side - the writer
 * must already be running, same pipe id). Pass -1 for whichever side
 * doesn't apply. */
static inline int exec_pipe(const char *cmdline, int stdout_pipe_id, int stdin_pipe_id) {
    return (int)__syscall3(SYS_EXEC_PIPE, (long)cmdline, stdout_pipe_id, stdin_pipe_id);
}

/* wait(pid) → exit code of the process; blocks until it exits. */
static inline int wait(int pid) {
    return (int)__syscall1(SYS_WAIT, (long)pid);
}

/* yield() → voluntarily give up the CPU for one scheduling round. */
static inline void yield(void) {
    __syscall0(SYS_YIELD);
}

/* ps() → print the process table to stdout (kernel writes to UART). */
static inline void ps(void) {
    __syscall0(SYS_PS);
}

static inline int kill(int pid) {
    return (int)__syscall1(SYS_KILL, (long)pid);
}

/* seccomp(mask) → 0 (narrows the calling process's syscall filter; the
 * first call sets it directly, every call after only narrows it - a
 * filter can never be widened once installed, matching x86's
 * ax_seccomp()). Unlike x86 (32-bit ABI, needs a lo/hi split) the whole
 * 64-bit mask fits in one a0 register natively here. */
static inline long seccomp(unsigned long mask) {
    return __syscall1(SYS_SECCOMP, (long)mask);
}

#define SC_BIT(n) (1UL << (unsigned)(n))
#define SC_WRITE        SC_BIT(SYS_WRITE)
#define SC_READ         SC_BIT(SYS_READ)
#define SC_EXIT         SC_BIT(SYS_EXIT)
#define SC_SBRK         SC_BIT(SYS_SBRK)
#define SC_GETTIME      SC_BIT(SYS_GETTIME)
#define SC_OPEN         SC_BIT(SYS_OPEN)
#define SC_CLOSE        SC_BIT(SYS_CLOSE)
#define SC_READDIR      SC_BIT(SYS_READDIR)
#define SC_GETPID       SC_BIT(SYS_GETPID)
#define SC_EXEC         SC_BIT(SYS_EXEC)
#define SC_WAIT         SC_BIT(SYS_WAIT)
#define SC_YIELD        SC_BIT(SYS_YIELD)
#define SC_PS           SC_BIT(SYS_PS)
#define SC_KILL         SC_BIT(SYS_KILL)
#define SC_WRITEFILE    SC_BIT(SYS_WRITEFILE)
#define SC_UNLINK       SC_BIT(SYS_UNLINK)
#define SC_POWER        SC_BIT(SYS_POWER)
#define SC_GFX_INFO     SC_BIT(SYS_GFX_INFO)
#define SC_GFX_PUTPIXEL SC_BIT(SYS_GFX_PUTPIXEL)
#define SC_GFX_FILLRECT SC_BIT(SYS_GFX_FILLRECT)
#define SC_GFX_FLUSH    SC_BIT(SYS_GFX_FLUSH)
#define SC_GFX_DRAWTEXT SC_BIT(SYS_GFX_DRAWTEXT)
#define SC_MOUSE_STATE  SC_BIT(SYS_MOUSE_STATE)
#define SC_GFX_GETPIXEL SC_BIT(SYS_GFX_GETPIXEL)
#define SC_SET_PRIORITY SC_BIT(SYS_SET_PRIORITY)
#define SC_NET_MAC      SC_BIT(SYS_NET_MAC)
#define SC_NET_SEND     SC_BIT(SYS_NET_SEND)
#define SC_NET_RECV     SC_BIT(SYS_NET_RECV)
#define SC_SLEEP        SC_BIT(SYS_SLEEP)
#define SC_EXEC_PIPE    SC_BIT(SYS_EXEC_PIPE)
#define SC_FORK         SC_BIT(SYS_FORK)
#define SC_SET_LEVEL    SC_BIT(SYS_SET_LEVEL)
#define SC_PS_INFO      SC_BIT(SYS_PS_INFO)

/* Baseline "can still talk to the user and exit cleanly" group -
 * mirrors x86's AX_SC_STDIO. */
#define SC_STDIO (SC_WRITE | SC_READ | SC_EXIT | SC_SBRK | SC_GETTIME | SC_SLEEP)

/* set_level(level) → 0 (raises the calling process's own MLS
 * sensitivity level 0..15, clamped by the kernel; "no read up" gate -
 * see mls_dominates() in syscall.c, currently applied to ps()). */
static inline long set_level(unsigned int level) {
    return __syscall1(SYS_SET_LEVEL, (long)level);
}

/* set_priority(pid, priority) - priority clamped to [1,10] by the kernel;
 * how many consecutive timer ticks that process keeps the CPU per turn
 * through the round-robin ring (weighted round-robin, see proc.c). */
static inline void set_priority(int pid, int priority) {
    __syscall2(SYS_SET_PRIORITY, (long)pid, (long)priority);
}

/* writefile(path, buf, len) -> 1 ok / 0 err (creates or overwrites) */
static inline int writefile(const char *path, const void *buf, long len) {
    return (int)__syscall3(SYS_WRITEFILE, (long)path, (long)buf, len);
}

/* unlink(path) -> 1 ok / -1 not found / 0 err */
static inline int unlink(const char *path) {
    return (int)__syscall1(SYS_UNLINK, (long)path);
}

/* shutdown()/reboot() never return on success. */
static inline void shutdown(void) {
    __syscall1(SYS_POWER, 0);
}
static inline void reboot(void) {
    __syscall1(SYS_POWER, 1);
}

/* sleep_ms(n) — real block via SYS_SLEEP: the kernel marks this process
 * PROC_SLEEPING and switches to something else, waking it again once its
 * deadline (CSR `time`, 10 MHz on QEMU virt) has passed. Not a busy-wait
 * loop - see proc_wake_sleepers() (proc.c) and SYS_SLEEP (syscall.c). */
static inline void sleep_ms(unsigned long ms) {
    __syscall1(SYS_SLEEP, (long)ms);
}

/* B8G8R8A8_UNORM packing: byte order in memory is B,G,R,A. On this
 * little-endian machine, gfx_rgb(r,g,b) = (0xFF<<24)|(r<<16)|(g<<8)|b puts
 * b/g/r/0xFF exactly where the format name says (opaque alpha). */
static inline unsigned int gfx_rgb(unsigned int r, unsigned int g, unsigned int b) {
    return (0xFFu << 24) | (r << 16) | (g << 8) | b;
}

/* gfx_info(): fills *w/*h with the framebuffer size. Returns 0 if no GPU. */
static inline int gfx_info(unsigned int *w, unsigned int *h) {
    long v = __syscall0(SYS_GFX_INFO);
    if (v < 0) return 0;
    if (w) *w = (unsigned int)((unsigned long)v >> 32);
    if (h) *h = (unsigned int)((unsigned long)v & 0xFFFFFFFFu);
    return 1;
}

/* gfx_putpixel(x, y, bgra) — bgra from gfx_rgb(). No-op if out of bounds. */
static inline void gfx_putpixel(unsigned int x, unsigned int y, unsigned int bgra) {
    __syscall3(SYS_GFX_PUTPIXEL, x, y, bgra);
}

/* gfx_fill_rect(x, y, w, h, bgra) — clipped to the framebuffer. */
static inline void gfx_fill_rect(unsigned int x, unsigned int y,
                                 unsigned int w, unsigned int h, unsigned int bgra) {
    __syscall5(SYS_GFX_FILLRECT, x, y, w, h, bgra);
}

/* gfx_flush() — pushes the framebuffer to the actual display. */
static inline int gfx_flush(void) {
    return (int)__syscall0(SYS_GFX_FLUSH);
}

/* gfx_getpixel(x, y) — reads back one pixel (BGRA), 0 if out of bounds.
 * For software cursor save/restore. */
static inline unsigned int gfx_getpixel(unsigned int x, unsigned int y) {
    return (unsigned int)__syscall2(SYS_GFX_GETPIXEL, x, y);
}

/* gfx_draw_text(x, y, str, bgra) — 8x8 bitmap font rendered at 2x
 * (16x16 on screen), 16px advance/char, no line wrapping (split
 * multi-line text yourself). */
static inline void gfx_draw_text(unsigned int x, unsigned int y,
                                 const char *str, unsigned int bgra) {
    __syscall4(SYS_GFX_DRAWTEXT, x, y, (long)str, bgra);
}

/* mouse_state(&x, &y, &buttons, &focused, &wheel) — 1 if a mouse device
 * is present, 0 if not (in which case x/y/buttons/focused/wheel are
 * left untouched). buttons: bit0=left, bit1=right, bit2=middle. focused
 * (NULL-able, like the others): 1 if THIS process currently owns the
 * active click - always 1 for a process that never called
 * win_set_rect() (e.g. AxDesk), and among registered windows, only
 * whichever one the last button-down landed on, until the next press
 * (see the kernel's SYS_MOUSE_STATE handler). Apps that draw a window
 * (window.h users) should AND this into their own click-handling
 * conditions so an overlapping window underneath doesn't also react.
 * wheel (NULL-able): scroll delta since THIS process's last poll,
 * positive = scroll up, negative = scroll down, saturating at -64..+63
 * per poll (plenty for a fast scroll between two frames) - each
 * process gets its OWN delta from a shared monotonic counter, so one
 * process polling often (e.g. AxDesk, always running) can't consume
 * the wheel motion before a different, less-frequently-polling process
 * sees it. Pass NULL/0 if the caller has no scrollable content. */
static inline int mouse_state(unsigned int *x, unsigned int *y, unsigned int *buttons,
                              unsigned int *focused, int *wheel) {
    unsigned long v = (unsigned long)__syscall0(SYS_MOUSE_STATE);
    if (v == (unsigned long)-1) return 0;  /* no device */
    if (x)       *x       = (unsigned int)((v >> 32) & 0xFFFF);
    if (y)       *y       = (unsigned int)((v >> 16) & 0xFFFF);
    if (buttons) *buttons = (unsigned int)(v & 0xFF);
    if (focused) *focused = (unsigned int)((v >> 8) & 1);
    if (wheel) {
        int w = (int)((v >> 9) & 0x7F);
        if (w & 0x40) w -= 128;   /* sign-extend the 7-bit field */
        *wheel = w;
    }
    return 1;
}

/* win_set_rect(x,y,w,h) — registers/updates the calling process's
 * on-screen window rectangle with the kernel's click-ownership tracker
 * (see SYS_MOUSE_STATE). Called by window_init()/window_move() in
 * window.h - most GUI apps never need to call this directly. */
static inline int win_set_rect(int x, int y, int w, int h) {
    return (int)__syscall4(SYS_WIN_SET_RECT, x, y, w, h);
}

/* win_set_base() — marks the calling process as the compositor's base
 * (backdrop) layer: always painted first, exempt from click/keyboard
 * focus arbitration (see SYS_MOUSE_STATE/SYS_KBD_GETC). AxDesk only —
 * call once, right after win_set_rect(0,0,screen_w,screen_h). */
static inline int win_set_base(void) {
    return (int)__syscall0(SYS_WIN_SET_BASE);
}

/* win_set_topmost() — marks the calling process as the compositor's
 * always-on-top layer: always painted last (composite_screen()'s final
 * pass), always wins clicks in its own rect regardless of any other
 * window's z-order, exempt from keyboard focus arbitration. AxTaskbar
 * only — call once, right after win_set_rect(). */
static inline int win_set_topmost(void) {
    return (int)__syscall0(SYS_WIN_SET_TOPMOST);
}

/* win_focus(pid) -> 0 ok / -1 err (pid out of range, not a registered
 * non-backdrop window, or not alive). Brings another process's window
 * to front - used by AxTaskbar's open-window buttons. */
static inline int win_focus(int pid) {
    return (int)__syscall1(SYS_WIN_FOCUS, (long)pid);
}

/* sound_beep(freq_hz, duration_ms) -> 0 ok / -1 err (no audio device,
 * or the device doesn't support S16 samples @ 44100/48000 Hz).
 * Synthesizes a synchronous square-wave tone via virtio-sound - blocks
 * for roughly duration_ms while it plays, same style as every other
 * blocking I/O call in this codebase. */
static inline int sound_beep(unsigned int freq_hz, unsigned int duration_ms) {
    return (int)__syscall2(SYS_SOUND_BEEP, (long)freq_hz, (long)duration_ms);
}

/* ps_info(index, &out) -> 1 if procs[index] is in use (out filled), 0 if
 * unused/out of range. Same {pid,name,state,priority,ticks} data as ps()'s
 * UART text dump, but returned as a struct so a framebuffer GUI app (no
 * visible console) can actually read it - one process slot per call, loop
 * index 0..MAX_PROCS-1 (see proc.h on the kernel side; there's no
 * user-visible MAX_PROCS constant, AxTaskMgr hardcodes the current value). */
typedef struct {
    int           pid;
    char          name[13];
    int           state;
    int           priority;
    unsigned long ticks;
    int           win_registered;  /* appended fields - see SYS_WIN_SET_RECT/SYS_PS_INFO. Unconditional
                                     * (not MLS-redacted like name/ticks) - AxTaskbar uses this + win_is_base
                                     * to filter down to "processes with an open, non-backdrop window". */
    int           win_is_base;
} ps_entry_t;

static inline int ps_info(unsigned int index, ps_entry_t *out) {
    return (int)__syscall2(SYS_PS_INFO, (long)index, (long)out);
}

/* kbd_getc() -> next ASCII char from the keyboard, or -1 if none
 * pending / no device. Non-blocking - call in a loop to drain
 * everything typed since the last poll (real key events, incl. shift,
 * see virtio_keyboard.c). */
static inline int kbd_getc(void) {
    return (int)__syscall0(SYS_KBD_GETC);
}

/* net_mac(mac[6]) -> 1 if a NIC is present (mac filled in), 0 if not. */
static inline int net_mac(unsigned char mac[6]) {
    long v = __syscall0(SYS_NET_MAC);
    if (v < 0) return 0;
    unsigned long packed = (unsigned long)v;
    for (int i = 0; i < 6; i++) mac[5 - i] = (unsigned char)(packed >> (i * 8));
    return 1;
}

/* net_send(frame, len) -> 0 ok / -1 err. Raw Ethernet frame, no virtio header
 * (the kernel driver adds/strips that). */
static inline int net_send(const void *frame, unsigned int len) {
    return (int)__syscall2(SYS_NET_SEND, (long)frame, (long)len);
}

/* net_recv(buf, max_len) -> bytes copied, 0 if nothing pending right now
 * (non-blocking - call it in a poll loop). */
static inline unsigned int net_recv(void *buf, unsigned int max_len) {
    return (unsigned int)__syscall2(SYS_NET_RECV, (long)buf, (long)max_len);
}

/* Convenience: write a NUL-terminated string to stdout */
static inline void puts_rv(const char *s) {
    long len = 0;
    while (s[len]) len++;
    write(1, s, len);
}

/* Convenience: read exactly one character from stdin */
static inline char getchar_rv(void) {
    char c;
    read(0, &c, 1);
    return c;
}
