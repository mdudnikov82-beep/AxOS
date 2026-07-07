#pragma once

#define MAX_PROCS    4

#define PROC_UNUSED   0
#define PROC_RUNNABLE 1
#define PROC_RUNNING  2
#define PROC_WAITING  3   /* waiting for a child to exit */
#define PROC_ZOMBIE   4   /* exited; waiting for parent to collect */

/* One entry per process.  frame[N] = register xN (1-indexed). */
typedef struct {
    int           state;
    int           pid;
    int           wait_pid;     /* target pid when PROC_WAITING */
    int           exit_code;
    char          name[13];     /* up to 12 chars + NUL */
    unsigned long regs[32];     /* saved user registers x0..x31 */
    unsigned long sepc;         /* saved user program counter */
    unsigned long *pagetable;   /* physical address of sv39 root (L2) */
    unsigned long heap_brk;     /* current end of the heap (VA, page-aligned) */
} proc_t;

extern proc_t procs[MAX_PROCS];
extern int    current_pid;      /* -1 = kernel idle */

void  proc_init(void);

/* Allocate a process slot, fill PCB, return pid (>=0) or -1 */
int   proc_create(const char *name, unsigned long entry,
                  unsigned long *pt, unsigned long usp);

/* Called from the trap handler with the live trap frame and saved PC.
 * Saves current process (if RUNNING), picks next RUNNABLE, loads its
 * context into frame and switches satp.  On return entry.S does sret. */
void  schedule(unsigned long *frame, unsigned long sepc);
