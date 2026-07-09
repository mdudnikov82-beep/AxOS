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

/* Раньше стек всегда сидел ровно на фиксированном 0x7F000000
 * (детерминированный адрес каждую загрузку). Теперь стек каждого
 * процесса - своя случайная страница внутри [USER_HEAP_CEILING,
 * USER_VA_TOP) (см. pick_stack_va() в elf_loader.c) - ASLR, реальный
 * адрес хранится в proc_t.stack_va, не в константе. USER_HEAP_CEILING -
 * жёсткий потолок роста кучи (SYS_SBRK в syscall.c), ФИКСИРОВАННЫЙ
 * независимо от того, куда конкретно уехал стек у этого процесса - проще
 * и безопаснее, чем сверяться с фактическим stack_va при каждом sbrk().
 * Зазор [USER_HEAP_CEILING, USER_VA_TOP) - 32МБ, из них под стек ASLR
 * реально используется ~[0, 0x1FFF000) 4КБ-выровненных стартов (страница
 * должна поместиться до USER_VA_TOP) - ~13 бит энтропии. */
#define USER_HEAP_CEILING 0x7E000000UL

/* Load an ELF64 RISC-V executable from FAT12, create a PCB, and return
 * the new process's pid (>=0).  Returns -1 on error.
 * Does NOT jump to U-mode; call jump_to_umode() separately for the first process. */
int elf_load(const char *filename);

/* Switch to U-mode via sret.  Never returns.
 * Caller must switch satp to the process's page table BEFORE calling this. */
void jump_to_umode(unsigned long entry, unsigned long usp);
