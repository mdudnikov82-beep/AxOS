#pragma once

/* Syscall numbers — shared between kernel dispatch and user ecall wrappers */
#define SYS_WRITE    1   /* write(fd, buf, len) -> bytes */
#define SYS_READ     2   /* read(fd, buf, len)  -> bytes */
#define SYS_EXIT     3   /* exit(code) */
#define SYS_SBRK     4   /* sbrk(n) -> base addr */
#define SYS_GETTIME  5   /* gettime() -> CSR time */
#define SYS_OPEN     6   /* open(path, flags) -> fd */
#define SYS_CLOSE    7   /* close(fd) */
#define SYS_READDIR  8   /* readdir(idx, name_buf, size_out) -> 1/0 */
#define SYS_GETPID   9   /* getpid() -> current pid */
#define SYS_EXEC    10   /* exec(path) -> new pid (foreground: call wait()) */
#define SYS_WAIT    11   /* wait(pid) -> exit_code (blocks until done) */
#define SYS_YIELD   12   /* yield() -> 0 (voluntarily give up CPU) */
#define SYS_PS      13   /* ps() -> 0 (print process table to stdout) */
#define SYS_KILL    14   /* kill(pid) -> 0 ok / -1 err */
#define SYS_WRITEFILE 15 /* writefile(path, buf, len) -> 1 ok / 0 err */
#define SYS_UNLINK  16   /* unlink(path) -> 1 ok / -1 not found / 0 err */
#define SYS_POWER   17   /* power(mode) -> does not return (0=shutdown, 1=reboot) */
#define SYS_GFX_INFO      18  /* gfx_info() -> (width<<32)|height, or -1 if no GPU */
#define SYS_GFX_PUTPIXEL  19  /* gfx_putpixel(x, y, bgra) -> 0/-1 */
#define SYS_GFX_FILLRECT  20  /* gfx_fill_rect(x, y, w, h, bgra) -> 0/-1 */
#define SYS_GFX_FLUSH     21  /* gfx_flush() -> 0/-1 */
#define SYS_GFX_DRAWTEXT  22  /* gfx_draw_text(x, y, str, bgra) -> 0/-1 */
#define SYS_MOUSE_STATE   23  /* mouse_state() -> packed x/y/buttons, or 0 if no device */
#define SYS_GFX_GETPIXEL  24  /* gfx_getpixel(x, y) -> bgra, or 0 if out of bounds/no GPU */
#define SYS_SET_PRIORITY  25  /* set_priority(pid, priority) -> 0 (priority clamped to [1,10]) */
#define SYS_NET_MAC       26  /* net_mac() -> packed 6-byte MAC in low 48 bits, or -1 if no device */
#define SYS_NET_SEND      27  /* net_send(buf, len) -> 0 ok / -1 err (raw Ethernet frame, no header) */
#define SYS_NET_RECV      28  /* net_recv(buf, max_len) -> bytes copied, 0 if none pending/no device */
#define SYS_SLEEP         29  /* sleep_ms(ms) -> 0 (real block via PROC_SLEEPING, not a busy-loop) */
#define SYS_EXEC_PIPE     30  /* exec_pipe(cmdline, stdout_pipe_id, stdin_pipe_id) -> new pid or -1 */
#define SYS_FORK          31  /* fork() -> 0 in the child, new pid in the parent, -1 on error */
#define SYS_SECCOMP       32  /* seccomp(mask) -> 0 (narrows the calling process's syscall filter; first call sets it) */
#define SYS_SET_LEVEL     33  /* set_level(level) -> 0 (raises the calling process's own MLS sensitivity level, clamped [0,15]) */
#define SYS_KBD_GETC      34  /* kbd_getc() -> next ASCII char from the keyboard, or -1 if none pending/no device */
#define SYS_WIN_SET_RECT  35  /* win_set_rect(x,y,w,h) -> 0 (upserts the calling process's window rect + z-order, see SYS_MOUSE_STATE) */
#define SYS_PS_INFO       36  /* ps_info(index, ps_entry_t *out) -> 1 (out filled) / 0 (index out of range, end of list) */

/* Mirrored byte-for-byte in src/user/rv64/syscall.h - same toolchain/ABI
 * compiles both sides, so field order/padding always match. */
typedef struct {
    int           pid;
    char          name[13];
    int           state;
    int           priority;
    unsigned long ticks;
} ps_entry_t;

/* Kernel-side entry point.
 * frame[] = saved registers from trap_entry (sd xN, N*8(sp)):
 *   frame[10]=a0  frame[11]=a1  frame[12]=a2
 *   frame[13]=a3  frame[14]=a4  frame[15]=a5
 *   frame[17]=a7  (syscall number)
 * On return, frame[10] holds the return value; sepc is advanced by 4. */
void syscall_dispatch(unsigned long *frame, unsigned long sepc);
