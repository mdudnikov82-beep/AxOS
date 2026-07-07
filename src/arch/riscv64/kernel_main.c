#include "drivers/uart.h"
#include "paging.h"
#include "pmem.h"
#include "heap.h"
#include "virtio_blk.h"
#include "virtio_gpu.h"
#include "virtio_input.h"
#include "console.h"
#include "vfs.h"
#include "syscall.h"
#include "elf_loader.h"
#include "proc.h"

// ---- RISC-V CSR helpers ----
#define csr_read(csr)           ({ unsigned long v; __asm__ volatile("csrr %0," #csr : "=r"(v)); v; })
#define csr_write(csr, val)     __asm__ volatile("csrw " #csr ", %0" :: "rK"(val))
#define csr_set(csr, bits)      __asm__ volatile("csrs " #csr ", %0" :: "rK"(bits))

// ---- Текущее время: S-mode читает через CSR time (shadow of mtime) ----
static inline unsigned long read_time(void) {
    unsigned long t;
    __asm__ volatile("csrr %0, time" : "=r"(t));
    return t;
}

// ---- scause коды ----
#define CAUSE_INTERRUPT      (1UL << 63)
#define CAUSE_SUPERVISOR_TIMER   (CAUSE_INTERRUPT | 5UL)
#define CAUSE_ILLEGAL_INSTR  2UL
#define CAUSE_LOAD_FAULT     5UL
#define CAUSE_STORE_FAULT    7UL
#define CAUSE_ECALL_U        8UL
#define CAUSE_ECALL_S        9UL
#define CAUSE_INSTR_PAGE_FAULT  12UL
#define CAUSE_LOAD_PAGE_FAULT   13UL
#define CAUSE_STORE_PAGE_FAULT  15UL

static unsigned long tick_count = 0;
static const unsigned long TIMER_INTERVAL = 1000000UL;   // ~100 мс при 10 МГц

// SBI_SET_TIMER: EID=0x54494D45 ("TIME"), FID=0
// Устанавливает следующее срабатывание таймера
static void sbi_set_timer(unsigned long stime_value) {
    register unsigned long a7 __asm__("a7") = 0x54494D45UL;
    register unsigned long a6 __asm__("a6") = 0;
    register unsigned long a0 __asm__("a0") = stime_value;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a6), "r"(a7));
}

static void timer_init(void) {
    sbi_set_timer(read_time() + TIMER_INTERVAL);
    csr_set(sie, 1 << 5);  // STIE = Supervisor Timer Interrupt Enable
}

// ---- Обработчик trap'ов — вызывается из entry.S ----
void trap_handler(unsigned long cause, unsigned long epc,
                  unsigned long tval, unsigned long sp) {
    if (cause == CAUSE_ECALL_U || cause == CAUSE_ECALL_S) {
        syscall_dispatch((unsigned long *)sp, epc);
        return;
    }

    if (cause == CAUSE_SUPERVISOR_TIMER) {
        tick_count++;
        sbi_set_timer(read_time() + TIMER_INTERVAL);

        /* Preempt only when the interrupt came from U-mode (sstatus.SPP=0).
         * If SPP=1 the kernel itself is running (e.g. spinning in sys_read)
         * and touching the trap frame would corrupt the kernel stack. */
        unsigned long sstatus_v;
        __asm__ volatile("csrr %0, sstatus" : "=r"(sstatus_v));
        if (!(sstatus_v & (1UL << 8))) {   /* SPP=0 → came from U-mode */
            schedule((unsigned long *)sp, epc);
        }
        return;
    }

    /* Fault isolation: a page/access/illegal-instruction fault caused by a
     * U-mode process (bad pointer, W^X violation, NX violation, ...) must
     * kill only that process, not the whole kernel. Only a fault while the
     * KERNEL itself was running (SPP=1) is treated as fatal below. */
    if (cause == CAUSE_ILLEGAL_INSTR  || cause == CAUSE_LOAD_FAULT  ||
        cause == CAUSE_STORE_FAULT    || cause == CAUSE_INSTR_PAGE_FAULT ||
        cause == CAUSE_LOAD_PAGE_FAULT || cause == CAUSE_STORE_PAGE_FAULT) {

        unsigned long sstatus_v;
        __asm__ volatile("csrr %0, sstatus" : "=r"(sstatus_v));
        if (!(sstatus_v & (1UL << 8)) && current_pid >= 0) {   /* SPP=0 → U-mode */
            uart_puts("\r\n[fault] pid=");
            uart_putc('0' + (char)(current_pid & 0xF));
            uart_puts(" cause=0x");
            for (int s = 60; s >= 0; s -= 4)
                uart_putc("0123456789abcdef"[(cause >> s) & 0xF]);
            uart_puts(" epc=0x");
            for (int s = 60; s >= 0; s -= 4)
                uart_putc("0123456789abcdef"[(epc >> s) & 0xF]);
            uart_puts(" tval=0x");
            for (int s = 60; s >= 0; s -= 4)
                uart_putc("0123456789abcdef"[(tval >> s) & 0xF]);
            uart_puts(" — process killed\r\n");

            int epid = current_pid;
            procs[epid].state     = PROC_ZOMBIE;
            procs[epid].exit_code = -1;
            for (int i = 0; i < MAX_PROCS; i++) {
                if (procs[i].state == PROC_WAITING && procs[i].wait_pid == epid) {
                    procs[i].state     = PROC_RUNNABLE;
                    procs[i].regs[10]  = (unsigned long)-1UL;  /* a0 = wait() result */
                    procs[epid].state  = PROC_UNUSED;  /* collected synchronously */
                }
            }
            schedule((unsigned long *)sp, epc);
            return;
        }
        /* SPP=1: the kernel itself faulted — fall through, this is fatal. */
    }

    // Неожиданный trap — печатаем и зависаем
    uart_puts("\r\n[TRAP] cause=0x");
    // Печатаем cause как hex
    for (int s = 60; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[(cause >> s) & 0xF]);
    uart_puts(" epc=0x");
    for (int s = 60; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[(epc >> s) & 0xF]);
    uart_puts(" tval=0x");
    for (int s = 60; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[(tval >> s) & 0xF]);
    uart_puts("\r\n[TRAP] kernel halted.\r\n");
    while (1) __asm__ volatile("wfi");
}

// ---- Точка входа ядра ----
void kernel_main(unsigned long hart_id, unsigned long dtb) {
    (void)dtb;

    uart_init();
    uart_puts("\r\n");
    uart_puts("  AxOS/RV64  —  RISC-V kernel\r\n");
    uart_puts("  hart: ");
    uart_putc('0' + (char)(hart_id & 0xF));
    uart_puts("  sepc=");
    unsigned long sepc = csr_read(sepc);
    for (int s = 28; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[(sepc >> s) & 0xF]);
    uart_puts("\r\n");

    uart_puts("[kernel] trap handler installed\r\n");
    paging_init();

    // RAM: 128 MB на QEMU virt, 0x80000000..0x87FFFFFF
    // _kernel_end — символ из linker script, конец образа ядра вместе со стеком
    extern char _kernel_end[];
    pmem_init((unsigned long)_kernel_end, 0x88000000UL);
    heap_init();

    // Smoke test: выделяем несколько объектов и сразу освобождаем
    void *a = kmalloc(64);
    void *b = kmalloc(128);
    void *c = kmalloc(32);
    uart_puts("[heap] test alloc: a=0x");
    for (int s = 28; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[((unsigned long)a >> s) & 0xF]);
    uart_puts("  b=0x");
    for (int s = 28; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[((unsigned long)b >> s) & 0xF]);
    uart_puts("  c=0x");
    for (int s = 28; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[((unsigned long)c >> s) & 0xF]);
    uart_puts("\r\n");
    kfree(b);
    void *b2 = kmalloc(64);   // должен переиспользовать блок b или его часть
    uart_puts("[heap] after free(b), kmalloc(64) -> b2=0x");
    for (int s = 28; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[((unsigned long)b2 >> s) & 0xF]);
    uart_puts("\r\n");
    kfree(a); kfree(b2); kfree(c);

    // VirtIO блочное устройство
    if (virtio_blk_init() == 0) {
        // Читаем сектор 0 и печатаем первые 64 байта как ASCII
        char *sector_buf = (char *)kmalloc(SECTOR_SIZE);
        if (sector_buf && virtio_blk_read(0, sector_buf) == 0) {
            uart_puts("[virtio] sector 0: \"");
            for (int i = 0; i < 64; i++) {
                char c = sector_buf[i];
                if (c == 0) break;
                if (c >= 0x20 && c < 0x7F) uart_putc(c); else uart_putc('.');
            }
            uart_puts("\"\r\n");

            /* Тест записи: сектор 2047 (конец диска, вне FAT12 FS).
             * Сектор 1 — это FAT, писать туда нельзя — испортит FS. */
            char *wbuf = (char *)kmalloc(SECTOR_SIZE);
            if (wbuf) {
                const char *msg = "AxOS/RV64 wrote this sector!";
                for (int i = 0; i < (int)SECTOR_SIZE; i++)
                    wbuf[i] = (msg[i] ? msg[i] : 0);
                if (virtio_blk_write(2047, wbuf) == 0) {
                    char *rbuf = (char *)kmalloc(SECTOR_SIZE);
                    if (rbuf && virtio_blk_read(2047, rbuf) == 0) {
                        uart_puts("[virtio] readback s2047: \"");
                        for (int i = 0; i < 32; i++) {
                            char c = rbuf[i];
                            if (c == 0) break;
                            if (c >= 0x20 && c < 0x7F) uart_putc(c);
                        }
                        uart_puts("\"\r\n");
                    }
                    kfree(rbuf);
                }
                kfree(wbuf);
            }
        }
        kfree(sector_buf);
    }

    // VirtIO-GPU: тестовая картинка — 8 вертикальных цветных полос
    // (классический TV test pattern), чтобы проверить, что весь путь
    // create/attach/scanout/flush реально доходит до экрана.
    if (virtio_gpu_init() == 0) {
        unsigned int *px = (unsigned int *)virtio_gpu_fb();
        /* B8G8R8A8_UNORM: byte order in memory is B,G,R,A. On this
         * little-endian machine a plain 32-bit store's low byte lands at
         * the lowest address, so BGRA(r,g,b,a) = (a<<24)|(r<<16)|(g<<8)|b
         * puts b/g/r/a exactly where the format name says. */
        #define BGRA(r, g, b, a) \
            (((unsigned int)(a) << 24) | ((unsigned int)(r) << 16) | \
             ((unsigned int)(g) << 8)  |  (unsigned int)(b))
        static const unsigned int bars[8] = {
            BGRA(255, 255, 255, 255), /* white   */
            BGRA(255, 255,   0, 255), /* yellow  */
            BGRA(  0, 255, 255, 255), /* cyan    */
            BGRA(  0, 255,   0, 255), /* green   */
            BGRA(255,   0, 255, 255), /* magenta */
            BGRA(255,   0,   0, 255), /* red     */
            BGRA(  0,   0, 255, 255), /* blue    */
            BGRA(  0,   0,   0, 255), /* black   */
        };
        #undef BGRA
        unsigned int bar_w = GPU_FB_WIDTH / 8;
        for (unsigned int y = 0; y < GPU_FB_HEIGHT; y++) {
            for (unsigned int x = 0; x < GPU_FB_WIDTH; x++) {
                px[y * GPU_FB_WIDTH + x] = bars[x / bar_w < 8 ? x / bar_w : 7];
            }
        }
        if (virtio_gpu_flush() == 0) {
            uart_puts("[gpu] test pattern flushed to display\r\n");
        }
    }

    // VirtIO-input (tablet mode) — мышь/курсор для paint-программ и т.п.
    // Требует -device virtio-tablet-device; если его нет, просто не
    // находится и virtio_input_ready() всегда возвращает 0 (SYS_MOUSE_STATE
    // тогда безобидно отдаёт 0 вызывающему).
    virtio_input_init();

    // Файловая система (через VFS — см. vfs.c; сегодня единственный
    // backend это FAT12, но kernel_main.c больше не знает об этом напрямую)
    if (vfs_init()) {
        uart_puts("[fat12] directory listing:\r\n");
        vfs_list();

        // Читаем файл HELLO.TXT
        char *fbuf = (char *)kmalloc(1024);
        if (fbuf) {
            unsigned int sz = vfs_load("HELLO.TXT", (unsigned char *)fbuf, 1023);
            if (sz) {
                fbuf[sz] = '\0';
                uart_puts("[fat12] HELLO.TXT:\r\n");
                uart_puts(fbuf);
            }
            kfree(fbuf);
        }

        // Тест записи: создаём новый файл через VFS
        const char *wdata = "Written by AxOS/RV64 kernel at boot!\n";
        unsigned int wlen = 0;
        while (wdata[wlen]) wlen++;
        if (vfs_write("BOOT.LOG", (unsigned char *)wdata, wlen))
            uart_puts("[fat12] BOOT.LOG written OK\r\n");
    }

    /* Must run after pmem_init()/heap_init() (needs alloc_page()) and
     * before the first paging_create_user_pt() call below (which copies
     * root_pt[2] by value into every new process's page table). */
    paging_harden_kernel();

    /* Blank the screen and reset the graphical console right before AxSH
     * starts — sys_write() mirrors every subsequent stdout/stderr write
     * onto it, so from here on the shell's actual output shows up on the
     * display, not just the boot log (which stays UART-only). */
    console_init();

    /* MUST happen before jump_to_umode() below: that call never returns
     * (sret straight into the first process), so anything placed after it
     * in this function is dead code that never runs on the normal boot
     * path. Timer interrupts (and therefore ALL timer-tick preemption -
     * see schedule() in proc.c) were silently never enabled at all until
     * this was moved here, because timer_init() used to sit AFTER
     * jump_to_umode(). Every process, forever, only ever got the CPU via
     * voluntary yield()/blocking-read retries (both synchronous ecalls,
     * which trap regardless of sie/sstatus.SIE) - a process that never
     * calls either (e.g. a pure compute loop) could never be preempted at
     * all and would hang the whole system. */
    timer_init();
    uart_puts("[kernel] timer armed (100ms interval)\r\n");
    csr_set(sstatus, 1 << 1);   // sstatus.SIE=1 - enable interrupts globally

    /* Init process table and load the first user process. */
    if (vfs_is_ready()) {
        proc_init();

        int pid0 = elf_load("AXSH.ELF");
        if (pid0 < 0) {
            uart_puts("[kernel] AXSH.ELF not found, trying HELLO.ELF\r\n");
            pid0 = elf_load("HELLO.ELF");
        }

        if (pid0 < 0) {
            uart_puts("[kernel] no user program found\r\n");
        } else {
            current_pid          = pid0;
            procs[pid0].state    = PROC_RUNNING;

            /* Switch to the first process's page table before sret. */
            unsigned long satp_val =
                MAKE_SATP((unsigned long)procs[pid0].pagetable);
            __asm__ volatile(
                "csrw satp, %0\n"
                "sfence.vma\n"
                :: "r"(satp_val) : "memory"
            );

            jump_to_umode(procs[pid0].sepc, procs[pid0].regs[2]);
            /* unreachable */
        }
    }

    /* Syscall self-test: ECALL from S-mode (cause=9) goes through dispatch */
    uart_puts("[syscall] self-test...\r\n");
    {
        /* SYS_WRITE: write "  hello via ecall!\r\n" to fd=1 */
        const char *msg = "  hello via ecall!\r\n";
        unsigned long mlen = 20;
        register unsigned long _nr  __asm__("a7") = SYS_WRITE;
        register unsigned long _a0  __asm__("a0") = 1;
        register unsigned long _a1  __asm__("a1") = (unsigned long)msg;
        register unsigned long _a2  __asm__("a2") = mlen;
        long ret;
        __asm__ volatile("ecall" : "+r"(_a0) : "r"(_nr), "r"(_a1), "r"(_a2));
        ret = (long)_a0;
        uart_puts("[syscall] write ret=");
        if (ret < 0) { uart_putc('-'); ret = -ret; }
        {
            unsigned long n = (unsigned long)ret;
            char b[20]; int i = 0;
            if (!n) uart_putc('0');
            else { while (n) { b[i++] = '0' + (n % 10); n /= 10; }
                   for (int j = i-1; j >= 0; j--) uart_putc(b[j]); }
        }
        uart_puts("\r\n");

        /* SYS_GETTIME */
        register unsigned long _tnr __asm__("a7") = SYS_GETTIME;
        register unsigned long _ta0 __asm__("a0");
        __asm__ volatile("ecall" : "=r"(_ta0) : "r"(_tnr));
        uart_puts("[syscall] gettime=");
        {
            unsigned long n = _ta0;
            char b[24]; int i = 0;
            if (!n) uart_putc('0');
            else { while (n) { b[i++] = '0' + (n % 10); n /= 10; }
                   for (int j = i-1; j >= 0; j--) uart_putc(b[j]); }
        }
        uart_puts("\r\n");
    }

    /* Only reached if no process could be loaded above (timer_init()
     * and the sstatus.SIE enable already happened earlier in this
     * function, before jump_to_umode()). Nothing left to schedule -
     * just idle. */
    uart_puts("[kernel] no process running — idling.\r\n");
    while (1) __asm__ volatile("wfi");
}
