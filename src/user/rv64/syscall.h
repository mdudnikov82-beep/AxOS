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

/* gfx_draw_text(x, y, str, bgra) — 8x8 bitmap font, 8px advance/char,
 * no line wrapping (split multi-line text yourself). */
static inline void gfx_draw_text(unsigned int x, unsigned int y,
                                 const char *str, unsigned int bgra) {
    __syscall4(SYS_GFX_DRAWTEXT, x, y, (long)str, bgra);
}

/* mouse_state(&x, &y, &buttons) — 1 if a mouse device is present, 0 if not
 * (in which case x/y/buttons are left untouched). buttons: bit0=left,
 * bit1=right, bit2=middle. */
static inline int mouse_state(unsigned int *x, unsigned int *y, unsigned int *buttons) {
    unsigned long v = (unsigned long)__syscall0(SYS_MOUSE_STATE);
    if (v == (unsigned long)-1) return 0;  /* no device */
    if (x)       *x       = (unsigned int)((v >> 32) & 0xFFFF);
    if (y)       *y       = (unsigned int)((v >> 16) & 0xFFFF);
    if (buttons) *buttons = (unsigned int)(v & 0xFF);
    return 1;
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
