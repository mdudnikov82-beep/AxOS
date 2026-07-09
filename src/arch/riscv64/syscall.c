#include "syscall.h"
#include "drivers/uart.h"
#include "heap.h"
#include "vfs.h"
#include "pmem.h"
#include "proc.h"
#include "elf_loader.h"
#include "paging.h"
#include "virtio_gpu.h"
#include "virtio_input.h"
#include "virtio_net.h"
#include "console.h"

/* Register indices in the trap frame (sd xN, N*8(sp)) */
#define REG_A0  10
#define REG_A1  11
#define REG_A2  12
#define REG_A3  13
#define REG_A4  14
#define REG_A5  15
#define REG_A7  17

static void put_udec(unsigned long v) {
    char b[20]; int i = 0;
    if (!v) { uart_putc('0'); return; }
    while (v) { b[i++] = '0' + (v % 10); v /= 10; }
    for (int j = i-1; j >= 0; j--) uart_putc(b[j]);
}

static char uart_getc_poll(void) {
    volatile unsigned char *u = (volatile unsigned char *)0x10000000UL;
    while (!(u[5] & 0x01));
    return (char)u[0];
}

/* ---- File descriptor table ----
 * fd 0 = stdin  (UART RX)
 * fd 1 = stdout (UART TX)
 * fd 2 = stderr (UART TX)
 * fd 3+ = FAT12 files */
#define MAX_FDS      8
#define FD_FILE_BASE 3

typedef struct {
    int           used;
    char          name[13];
    unsigned char *buf;
    unsigned int  size;
    unsigned int  pos;
} fd_entry_t;

static fd_entry_t fds[MAX_FDS];

/* ---- Syscall implementations ---- */

static long sys_write(unsigned long fd, const char *buf, unsigned long len) {
    if (fd == 1 || fd == 2) {
        for (unsigned long i = 0; i < len; i++) uart_putc(buf[i]);
        /* Mirror stdout/stderr onto the graphical console too — every
         * program's normal write(1, ...) output shows up on screen, not
         * just over serial, with no changes needed on the program's side. */
        console_write(buf, len);
        return (long)len;
    }
    return -1;
}

static long sys_read(unsigned long fd, char *buf, unsigned long len) {
    if (fd == 0) {
        unsigned long i = 0;
        while (i < len) {
            char c = uart_getc_poll();
            buf[i++] = c;
            if (c == '\r' || c == '\n') break;
        }
        return (long)i;
    }
    if (fd >= FD_FILE_BASE && fd < MAX_FDS && fds[fd].used) {
        unsigned long avail = (unsigned long)(fds[fd].size - fds[fd].pos);
        if (avail > len) avail = len;
        for (unsigned long i = 0; i < avail; i++)
            buf[i] = (char)fds[fd].buf[fds[fd].pos + i];
        fds[fd].pos += (unsigned int)avail;
        return (long)avail;
    }
    return -1;
}

static long sys_open(const char *path, unsigned long flags) {
    (void)flags;
    for (int i = FD_FILE_BASE; i < MAX_FDS; i++) {
        if (fds[i].used) continue;

        /* Allocate 8 pages (32 KB) directly from bump allocator.
         * This avoids the kmalloc recursion issue for large buffers. */
        unsigned int maxsz = 8 * (unsigned int)PAGE_SIZE;
        unsigned char *buf = (unsigned char *)alloc_page();
        if (!buf) return -1;
        for (int p = 1; p < 8; p++) {
            if (!alloc_page()) return -1;
        }

        unsigned int sz = vfs_load((char *)path, buf, maxsz);
        if (!sz) return -1;  /* file not found */

        int j = 0;
        for (; path[j] && j < 12; j++) fds[i].name[j] = path[j];
        fds[i].name[j] = '\0';
        fds[i].buf  = buf;
        fds[i].size = sz;
        fds[i].pos  = 0;
        fds[i].used = 1;
        return i;
    }
    return -1;
}

/* SBI_SYSTEM_RESET: EID=0x53525354 ("SRST"), FID=0.
 * reset_type: 0=shutdown, 1=cold reboot, 2=warm reboot. reset_reason: 0=none.
 * On success this call never returns. */
static void sbi_system_reset(unsigned long reset_type, unsigned long reset_reason) {
    register unsigned long a7 __asm__("a7") = 0x53525354UL;
    register unsigned long a6 __asm__("a6") = 0;
    register unsigned long a0 __asm__("a0") = reset_type;
    register unsigned long a1 __asm__("a1") = reset_reason;
    __asm__ volatile("ecall" : "+r"(a0), "+r"(a1) : "r"(a6), "r"(a7));
}

static long sys_writefile(const char *path, const char *buf, unsigned long len) {
    return (long)vfs_write((char *)path, (unsigned char *)buf, (unsigned int)len);
}

static long sys_unlink(const char *path) {
    return (long)vfs_delete((char *)path);
}

static long sys_close(unsigned long fd) {
    if (fd >= FD_FILE_BASE && fd < MAX_FDS && fds[fd].used) {
        /* Buffer came from bump allocator — not individually freeable.
         * Just clear the slot so it can be reused. */
        fds[fd].buf  = 0;
        fds[fd].used = 0;
        return 0;
    }
    return -1;
}

/* ---- SMAP-equivalent: sstatus.SUM scoped to syscall handling only ----
 * SUM=1 lets S-mode load/store through PTE_U pages (needed since syscall
 * args are raw pointers into the calling process's user space). Keeping it
 * off outside this window means a stray kernel dereference of a leftover
 * user pointer (timer ISR, fault handler, ...) still faults instead of
 * silently succeeding. */
static inline void user_access_enable(void) {
    __asm__ volatile("csrs sstatus, %0" :: "r"(1UL << 18));
}
static inline void user_access_disable(void) {
    __asm__ volatile("csrc sstatus, %0" :: "r"(1UL << 18));
}

/* ---- User pointer validation ----
 * SUM only lets S-mode touch PTE_U pages — it does NOT stop the kernel
 * from touching its OWN non-U memory (kernel RAM, MMIO) on a process's
 * behalf. Without this check, a process could pass a kernel address as
 * e.g. write()'s buffer and use the kernel's own dereference to read (or,
 * via read()/readdir(), WRITE) arbitrary kernel memory — the MMU never
 * sees a user-mode access at all, so it can't fault on it. Every syscall
 * argument that's a pointer into the caller's own memory must be checked
 * against the user VA window (see elf_loader.h) before use. */
static int user_range_ok(unsigned long ptr, unsigned long len) {
    if (ptr < USER_VA_BASE || ptr >= USER_VA_TOP) return 0;
    if (len > USER_VA_TOP - ptr) return 0;
    return 1;
}

/* Generous fixed bound for a NUL-terminated path/string argument — the
 * real length isn't known before a safe read, so this just proves the
 * worst case (a non-terminated buffer of this size) still fits entirely
 * inside user space. */
#define USER_MAX_STRING 256UL
static int user_string_ok(unsigned long ptr) {
    return user_range_ok(ptr, USER_MAX_STRING);
}

/* ---- Kernel-side dispatch ---- */

void syscall_dispatch(unsigned long *frame, unsigned long sepc) {
    unsigned long nr   = frame[REG_A7];
    unsigned long arg0 = frame[REG_A0];
    unsigned long arg1 = frame[REG_A1];
    unsigned long arg2 = frame[REG_A2];
    long ret = -38; /* ENOSYS */

    user_access_enable();

    switch (nr) {

    case SYS_WRITE:
        if (!user_range_ok(arg1, arg2)) { ret = -1; break; }
        ret = sys_write(arg0, (const char *)arg1, arg2);
        break;

    case SYS_READ:
        if (!user_range_ok(arg1, arg2)) { ret = -1; break; }
        if (arg0 == 0) {
            /* Non-blocking stdin: if no char is ready, yield CPU and retry
             * the same ecall (sepc NOT advanced).  On the next scheduling
             * turn the process re-executes the ecall and checks again.
             * This lets background processes run while the shell waits. */
            volatile unsigned char *uart_lsr =
                (volatile unsigned char *)(0x10000000UL + 5);
            if (!(*uart_lsr & 0x01)) {
                for (int r = 1; r < 32; r++)
                    procs[current_pid].regs[r] = frame[r];
                procs[current_pid].sepc  = sepc;   /* retry ecall */
                procs[current_pid].state = PROC_RUNNABLE;
                schedule(frame, sepc);
                user_access_disable();
                return;
            }
            ret = sys_read(arg0, (char *)arg1, arg2);
        } else {
            ret = sys_read(arg0, (char *)arg1, arg2);
        }
        break;

    case SYS_EXIT: {
        /* Mark zombie, wake up any process waiting on us, then schedule. */
        int epid = current_pid;
        procs[epid].state     = PROC_ZOMBIE;
        procs[epid].exit_code = (int)arg0;
        for (int i = 0; i < MAX_PROCS; i++) {
            if (procs[i].state == PROC_WAITING && procs[i].wait_pid == epid) {
                procs[i].state        = PROC_RUNNABLE;
                procs[i].regs[REG_A0] = arg0;  /* wait() return = exit code */
                /* Collected synchronously — free the slot now instead of
                 * leaking it as a zombie forever (no SYS_WAIT will come
                 * along later to do it, since it already "happened"). */
                procs[epid].state     = PROC_UNUSED;
            }
        }
        /* schedule() switches to the next RUNNABLE process (or idles via its
         * own wfi if none exist) and updates frame/sepc/satp in place. */
        schedule(frame, sepc);
        user_access_disable();
        return;
    }

    case SYS_SBRK: {
        /* Grows the CALLING process's own heap, mapping fresh pages into
         * its page table as PTE_USER_RW (no X — the heap must never be
         * executable). Returns the *previous* break (classic sbrk), or -1.
         * sbrk(0) just queries the current break without allocating. */
        long n = (long)arg0;
        unsigned long old_brk = procs[current_pid].heap_brk;

        if (n == 0) { ret = (long)old_brk; break; }
        if (n < 0)  { ret = -1; break; }  /* shrinking isn't supported */

        unsigned int pages = ((unsigned int)n + PAGE_SIZE - 1) / PAGE_SIZE;
        unsigned long new_brk = old_brk + (unsigned long)pages * PAGE_SIZE;

        /* Фиксированный потолок (USER_HEAP_CEILING), НЕ фактический
         * stack_va этого процесса - стек теперь ASLR (см. elf_loader.c),
         * сверяться с реальным его адресом на каждый sbrk() сложнее и не
         * даёт ничего сверх того, что уже даёт единый жёсткий потолок:
         * весь диапазон [USER_HEAP_CEILING, USER_VA_TOP) зарезервирован
         * под возможные позиции стека, кучи там в принципе быть не может. */
        if (new_brk > USER_HEAP_CEILING) { ret = -1; break; }  /* would hit the stack's reserved range */

        int ok = 1;
        for (unsigned int i = 0; i < pages; i++) {
            void *phys = alloc_page();
            if (!phys) { ok = 0; break; }
            map_page_4k_pt(procs[current_pid].pagetable,
                          old_brk + (unsigned long)i * PAGE_SIZE,
                          (unsigned long)phys, PTE_USER_RW);
        }

        if (!ok) { ret = -1; break; }
        procs[current_pid].heap_brk = new_brk;
        ret = (long)old_brk;
        break;
    }

    case SYS_GETTIME: {
        unsigned long t;
        __asm__ volatile("csrr %0, time" : "=r"(t));
        ret = (long)t;
        break;
    }

    case SYS_OPEN:
        if (!user_string_ok(arg0)) { ret = -1; break; }
        ret = sys_open((const char *)arg0, arg1);
        break;

    case SYS_CLOSE:
        ret = sys_close(arg0);
        break;

    case SYS_WRITEFILE:
        if (!user_string_ok(arg0) || !user_range_ok(arg1, arg2)) { ret = -1; break; }
        ret = sys_writefile((const char *)arg0, (const char *)arg1, arg2);
        break;

    case SYS_UNLINK:
        if (!user_string_ok(arg0)) { ret = -1; break; }
        ret = sys_unlink((const char *)arg0);
        break;

    case SYS_POWER: {
        /* If some other process is blocked in wait() on us, we're a
         * nested shell (started via foreground `run AXSH.ELF`) — exit
         * normally instead of powering off the whole machine, so control
         * returns to the parent. Only actually reset when nobody is
         * waiting on us (we're the top-level shell). */
        int waiter = -1;
        for (int i = 0; i < MAX_PROCS; i++) {
            if (procs[i].state == PROC_WAITING && procs[i].wait_pid == current_pid) {
                waiter = i;
                break;
            }
        }
        if (waiter >= 0) {
            int epid = current_pid;
            procs[epid].state     = PROC_ZOMBIE;
            procs[epid].exit_code = (int)arg0;
            procs[waiter].state        = PROC_RUNNABLE;
            procs[waiter].regs[REG_A0] = arg0;
            procs[epid].state          = PROC_UNUSED;  /* collected synchronously */
            schedule(frame, sepc);
            user_access_disable();
            return;
        }

        sbi_system_reset(arg0 ? 1UL : 0UL, 0UL);
        /* Only reached if the SBI call failed to reset the machine. */
        uart_puts("[power] SBI system reset failed\r\n");
        ret = -1;
        break;
    }

    case SYS_GFX_INFO:
        ret = virtio_gpu_ready()
            ? (long)(((unsigned long)GPU_FB_WIDTH << 32) | (unsigned long)GPU_FB_HEIGHT)
            : -1;
        break;

    case SYS_GFX_PUTPIXEL:
        if (!virtio_gpu_ready()) { ret = -1; break; }
        virtio_gpu_putpixel((unsigned int)arg0, (unsigned int)arg1, (unsigned int)arg2);
        ret = 0;
        break;

    case SYS_GFX_FILLRECT: {
        if (!virtio_gpu_ready()) { ret = -1; break; }
        unsigned long arg3 = frame[REG_A3];
        unsigned long arg4 = frame[REG_A4];
        virtio_gpu_fill_rect((unsigned int)arg0, (unsigned int)arg1,
                             (unsigned int)arg2, (unsigned int)arg3, (unsigned int)arg4);
        ret = 0;
        break;
    }

    case SYS_GFX_FLUSH:
        ret = virtio_gpu_flush();
        break;

    case SYS_GFX_DRAWTEXT: {
        if (!virtio_gpu_ready()) { ret = -1; break; }
        if (!user_string_ok(arg2)) { ret = -1; break; }
        unsigned long arg3 = frame[REG_A3];
        virtio_gpu_draw_text((unsigned int)arg0, (unsigned int)arg1,
                             (const char *)arg2, (unsigned int)arg3);
        ret = 0;
        break;
    }

    case SYS_GFX_GETPIXEL:
        ret = virtio_gpu_ready()
            ? (long)virtio_gpu_getpixel((unsigned int)arg0, (unsigned int)arg1)
            : 0;
        break;

    case SYS_MOUSE_STATE: {
        /* -1 sentinel for "no device" — a real packed state always has
         * bits [63:48] clear, so it can never collide with -1 (all bits
         * set), unlike 0 which IS a legitimately reachable state
         * (x=0,y=0,no buttons). */
        if (!virtio_input_ready()) { ret = -1; break; }
        unsigned long st = virtio_input_state();
        /* Move the hardware cursor to match, so every caller of
         * mouse_state() gets a visible pointer for free — no extra
         * syscall needed on the program's side. */
        virtio_gpu_cursor_move((unsigned int)((st >> 32) & 0xFFFF),
                               (unsigned int)((st >> 16) & 0xFFFF));
        ret = (long)st;
        break;
    }

    case SYS_READDIR:
        /* name_buf: fat12_readdir's documented contract is >=13 bytes.
         * size_out may legitimately be NULL — only range-check it if set. */
        if (!user_range_ok(arg1, 13) ||
            (arg2 != 0 && !user_range_ok(arg2, sizeof(unsigned int)))) {
            ret = 0; break;
        }
        ret = (long)vfs_readdir((unsigned int)arg0,
                                (char *)arg1,
                                (unsigned int *)arg2);
        break;

    case SYS_GETPID:
        ret = (long)current_pid;
        break;

    case SYS_EXEC:
        /* Load ELF, create process, return new pid. */
        if (!user_string_ok(arg0)) { ret = -1; break; }
        ret = (long)elf_load((const char *)arg0);
        break;

    case SYS_WAIT: {
        int wpid = (int)arg0;
        if (wpid < 0 || wpid >= MAX_PROCS) { ret = -1; break; }

        if (procs[wpid].state == PROC_ZOMBIE) {
            /* Already exited: collect and return. */
            ret = (long)procs[wpid].exit_code;
            procs[wpid].state = PROC_UNUSED;
            break;
        }
        if (procs[wpid].state == PROC_UNUSED) { ret = -1; break; }

        /* Block current process until target exits. */
        for (int r = 1; r < 32; r++) procs[current_pid].regs[r] = frame[r];
        procs[current_pid].sepc         = sepc + 4;  /* resume after ecall */
        procs[current_pid].regs[REG_A0] = 0;          /* overwritten on wake */
        procs[current_pid].state        = PROC_WAITING;
        procs[current_pid].wait_pid     = wpid;
        schedule(frame, sepc + 4);
        user_access_disable();
        return;  /* frame now holds next process's state; skip sepc+4 */
    }

    case SYS_YIELD:
        /* Voluntarily give up the CPU.  schedule() saves state.
         *
         * Force slice_left to 0 first: schedule() sees state==RUNNING
         * here (we haven't touched it) and would normally treat that as
         * ordinary timer-tick preemption, which - now that priority gives
         * a process multiple consecutive ticks per turn (see proc.c) -
         * could otherwise just decrement the remaining slice and resume
         * THIS SAME process instead of actually switching. An explicit
         * yield() must always hand off the CPU, priority or not. */
        procs[current_pid].slice_left = 0;
        frame[REG_A0] = 0;  /* yield() returns 0 */
        schedule(frame, sepc + 4);
        user_access_disable();
        return;  /* frame already updated; skip the write below */

    case SYS_KILL: {
        int kpid = (int)arg0;
        if (kpid < 0 || kpid >= MAX_PROCS ||
            procs[kpid].state == PROC_UNUSED) { ret = -1; break; }
        procs[kpid].state     = PROC_ZOMBIE;
        procs[kpid].exit_code = -1;
        for (int i = 0; i < MAX_PROCS; i++) {
            if (procs[i].state == PROC_WAITING && procs[i].wait_pid == kpid) {
                procs[i].state        = PROC_RUNNABLE;
                procs[i].regs[REG_A0] = (unsigned long)-1UL;
                procs[kpid].state     = PROC_UNUSED;  /* collected synchronously */
            }
        }
        ret = 0;
        break;
    }

    case SYS_PS: {
        static const char *stnames[] =
            {"unused", "runnable", "running", "waiting", "zombie"};
        uart_puts("PID  STATE     NAME          PRIO  TICKS\r\n");
        for (int i = 0; i < MAX_PROCS; i++) {
            if (procs[i].state == PROC_UNUSED) continue;
            uart_putc('0' + i);
            uart_puts("    ");
            const char *st = stnames[procs[i].state];
            uart_puts(st);
            /* pad to 10 chars */
            for (int k = 0; st[k]; k++);
            for (int p = 0; stnames[procs[i].state][p]; p++);
            uart_puts("   ");
            uart_puts(procs[i].name);
            uart_puts("  ");
            put_udec((unsigned long)procs[i].priority);
            uart_puts("     ");
            put_udec(procs[i].ticks);
            uart_puts("\r\n");
        }
        ret = 0;
        break;
    }

    case SYS_SET_PRIORITY:
        proc_set_priority((int)arg0, (int)arg1);
        ret = 0;
        break;

    case SYS_NET_MAC: {
        if (!virtio_net_ready()) { ret = -1; break; }
        unsigned char m[6];
        virtio_net_get_mac(m);
        unsigned long packed = 0;
        for (int i = 0; i < 6; i++) packed = (packed << 8) | m[i];
        ret = (long)packed;
        break;
    }

    case SYS_NET_SEND:
        if (!virtio_net_ready()) { ret = -1; break; }
        if (!user_range_ok(arg0, arg1)) { ret = -1; break; }
        ret = virtio_net_send((const void *)arg0, (unsigned int)arg1);
        break;

    case SYS_NET_RECV:
        if (!virtio_net_ready()) { ret = 0; break; }
        if (!user_range_ok(arg0, arg1)) { ret = 0; break; }
        ret = (long)virtio_net_recv((void *)arg0, (unsigned int)arg1);
        break;

    default:
        uart_puts("[syscall] ENOSYS nr=");
        put_udec(nr);
        uart_puts("\r\n");
        break;
    }

    user_access_disable();
    frame[REG_A0] = (unsigned long)ret;
    __asm__ volatile("csrw sepc, %0" :: "r"(sepc + 4));
}
