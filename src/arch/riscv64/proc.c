#include "proc.h"
#include "paging.h"
#include "drivers/uart.h"

proc_t procs[MAX_PROCS];
int    current_pid = -1;

void proc_init(void) {
    for (int i = 0; i < MAX_PROCS; i++) {
        procs[i].state    = PROC_UNUSED;
        procs[i].pid      = i;
        procs[i].wait_pid = -1;
    }
}

int proc_create(const char *name, unsigned long entry,
                unsigned long *pt, unsigned long usp) {
    for (int i = 0; i < MAX_PROCS; i++) {
        if (procs[i].state != PROC_UNUSED) continue;

        procs[i].state     = PROC_RUNNABLE;
        procs[i].exit_code = 0;
        procs[i].wait_pid  = -1;
        procs[i].pagetable = pt;

        int k = 0;
        while (name[k] && k < 12) { procs[i].name[k] = name[k]; k++; }
        procs[i].name[k] = '\0';

        for (int r = 0; r < 32; r++) procs[i].regs[r] = 0;
        procs[i].regs[2] = usp;  /* x2 = sp */
        procs[i].sepc    = entry;

        return i;
    }
    return -1;
}

/* Round-robin scheduler.
 *
 * Called with:
 *   frame  – pointer to the current trap frame on the kernel stack
 *            (frame[N] = register xN, as stored by entry.S)
 *   sepc   – program counter of the interrupted/yielding/exiting process
 *
 * If the current process is still RUNNING (preemption), we save its state
 * and mark it RUNNABLE before searching for the next slot.  Callers that
 * already transitioned the process to WAITING/ZOMBIE should save state
 * themselves *before* calling schedule().
 */
void schedule(unsigned long *frame, unsigned long sepc) {
    int start = (current_pid >= 0) ? current_pid : 0;

    /* Save state only for preemption (state == RUNNING). */
    if (current_pid >= 0 && procs[current_pid].state == PROC_RUNNING) {
        procs[current_pid].state = PROC_RUNNABLE;
        for (int r = 1; r < 32; r++)
            procs[current_pid].regs[r] = frame[r];
        procs[current_pid].sepc = sepc;
    }

    /* Find next RUNNABLE slot (round-robin, wraps around). */
    int next = -1;
    for (int i = 1; i <= MAX_PROCS; i++) {
        int idx = (start + i) % MAX_PROCS;
        if (procs[idx].state == PROC_RUNNABLE) { next = idx; break; }
    }

    if (next < 0) {
        /* Nothing to run — idle until the next interrupt. */
        current_pid = -1;
        __asm__ volatile("wfi");
        return;
    }

    current_pid       = next;
    procs[next].state = PROC_RUNNING;

    /* Restore next process's registers into the trap frame.
     * entry.S will lw/ld them on the return path and do sret. */
    for (int r = 1; r < 32; r++)
        frame[r] = procs[next].regs[r];
    frame[0] = 0;  /* x0 is hardwired zero */

    /* Switch page table and set next process's PC. */
    unsigned long satp_val = MAKE_SATP((unsigned long)procs[next].pagetable);
    __asm__ volatile(
        "csrw sepc, %1\n"
        "csrw satp, %0\n"
        "sfence.vma\n"
        :: "r"(satp_val), "r"(procs[next].sepc) : "memory"
    );
}
