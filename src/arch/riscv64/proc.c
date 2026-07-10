#include "proc.h"
#include "paging.h"
#include "drivers/uart.h"

proc_t procs[MAX_PROCS];
int    current_pid = -1;

void proc_init(void) {
    for (int i = 0; i < MAX_PROCS; i++) {
        procs[i].state          = PROC_UNUSED;
        procs[i].pid            = i;
        procs[i].wait_pid       = -1;
        procs[i].wake_tick      = 0;
        procs[i].stdout_pipe_id = -1;
        procs[i].stdin_pipe_id  = -1;
    }
}

int proc_create(const char *name, unsigned long entry,
                unsigned long *pt, unsigned long usp) {
    for (int i = 0; i < MAX_PROCS; i++) {
        if (procs[i].state != PROC_UNUSED) continue;

        procs[i].state          = PROC_RUNNABLE;
        procs[i].exit_code      = 0;
        procs[i].wait_pid       = -1;
        procs[i].wake_tick      = 0;
        procs[i].stdout_pipe_id = -1;
        procs[i].stdin_pipe_id  = -1;
        procs[i].syscall_mask   = 0;
        procs[i].pagetable   = pt;
        procs[i].priority    = PRIORITY_DEFAULT;
        procs[i].slice_left  = PRIORITY_DEFAULT;
        procs[i].ticks       = 0;

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

/* Round-robin scheduler, weighted by priority.
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
 *
 * Priority = how many consecutive timer ticks a process keeps the CPU per
 * turn (see PRIORITY_* in proc.h). Only genuine timer-tick preemption
 * (state still RUNNING when we get here) is subject to slice counting -
 * every other caller (SYS_EXIT, page-fault kill, the non-blocking-stdin
 * yield-and-retry in syscall.c) already transitioned the state away from
 * RUNNING *before* calling schedule(), specifically to hand the CPU to
 * someone else right now - so they always fall through to the rotation
 * below instead of being eligible for "keep running the same one" below.
 */
void schedule(unsigned long *frame, unsigned long sepc) {
    int start = (current_pid >= 0) ? current_pid : 0;

    if (current_pid >= 0 && procs[current_pid].state == PROC_RUNNING) {
        /* Only genuine timer-tick preemption reaches here (see comment
         * above) - counts as one more tick of CPU time for this process. */
        procs[current_pid].ticks++;

        /* Still has time left in this turn - just resume it, no switch. */
        if (--procs[current_pid].slice_left > 0) {
            return;
        }
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

    current_pid          = next;
    procs[next].state    = PROC_RUNNING;
    procs[next].slice_left = procs[next].priority; /* fresh turn for the new task */

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

/* Sets a process's scheduler priority (clamped). No-op for an unused slot
 * or an out-of-range pid. Takes effect on that process's NEXT turn - we
 * don't retroactively extend/shrink a turn already in progress. */
void proc_set_priority(int pid, int priority) {
    if (pid < 0 || pid >= MAX_PROCS) return;
    if (procs[pid].state == PROC_UNUSED) return;
    if (priority < PRIORITY_MIN) priority = PRIORITY_MIN;
    if (priority > PRIORITY_MAX) priority = PRIORITY_MAX;
    procs[pid].priority = priority;
}

extern int pipe_ready(int pipe_id); // syscall.c - 1 если у pipe'а есть данные или писатель закрылся

/* Promotes any PROC_SLEEPING process whose wake_tick has passed, or any
 * PROC_WAITING_PIPE process whose pipe is ready (see pipe_ready(),
 * syscall.c), back to PROC_RUNNABLE - see proc.h. Must run every timer
 * tick unconditionally (kernel_main.c calls this before the SPP-gated
 * reschedule check) - neither a sleeper nor a pipe-blocked reader gets
 * its own turn back on its own to notice the condition changed. */
void proc_wake_sleepers(void) {
    unsigned long now;
    __asm__ volatile("csrr %0, time" : "=r"(now));
    for (int i = 0; i < MAX_PROCS; i++) {
        if (procs[i].state == PROC_SLEEPING && now >= procs[i].wake_tick) {
            procs[i].state = PROC_RUNNABLE;
        }
        if (procs[i].state == PROC_WAITING_PIPE && pipe_ready(procs[i].stdin_pipe_id)) {
            procs[i].state = PROC_RUNNABLE;
        }
    }
}
