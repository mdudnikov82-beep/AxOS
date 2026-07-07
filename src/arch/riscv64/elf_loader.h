#pragma once

/* The entire user address space is one sv39 gigapage slot, L2[1]
 * (paging_create_user_pt leaves it for the ELF loader to fill in).
 * Anything outside [USER_VA_BASE, USER_VA_TOP) is either MMIO (L2[0]) or
 * the kernel's own identity-mapped RAM (L2[2]) — both are live, and after
 * paging_harden_kernel() the kernel-RAM slot is a *shared* page-table
 * sub-tree copied into every process, so letting a pointer or an ELF
 * segment land there is a cross-process/kernel corruption path, not just
 * an out-of-bounds access. */
#define USER_VA_BASE    0x40000000UL
#define USER_VA_TOP     0x80000000UL

/* Top of the per-process user stack page; the heap must never grow into it. */
#define USER_STACK_VA   0x7F000000UL

/* Load an ELF64 RISC-V executable from FAT12, create a PCB, and return
 * the new process's pid (>=0).  Returns -1 on error.
 * Does NOT jump to U-mode; call jump_to_umode() separately for the first process. */
int elf_load(const char *filename);

/* Switch to U-mode via sret.  Never returns.
 * Caller must switch satp to the process's page table BEFORE calling this. */
void jump_to_umode(unsigned long entry, unsigned long usp);
