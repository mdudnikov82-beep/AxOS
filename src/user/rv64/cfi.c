#include "syscall.h"

/* Software CFI (Control Flow Integrity) - backward-edge shadow stack.
 * Mirrors src/libaxiom/src/cfi.c (x86), rewritten for RV64's frame
 * layout: x86's version reads the exiting function's return address via
 * an EBP chain ((%ebp) -> that ebp+4); RV64 has no EBP, so this walks
 * the s0 (frame pointer) chain instead. With -fno-omit-frame-pointer, a
 * function's prologue always saves -8(s0)=own ra, -16(s0)=caller's s0.
 * At the point __cyg_profile_func_exit runs (called FROM the exiting
 * function foo's epilogue, itself a fresh frame), -16(our own s0) =
 * foo's s0, and -8(that) = foo's actual saved return address - the same
 * two-step dereference x86 does, just RV64-shaped.
 *
 * MUST be its own translation unit, compiled WITHOUT
 * -finstrument-functions (unlike everything else in this directory,
 * which is header-only) - otherwise __cyg_profile_func_enter/exit would
 * instrument themselves into infinite recursion. See build_riscv.bat.
 *
 * Requires -fno-omit-frame-pointer on BOTH this file (so its own s0
 * reliably captures the caller's s0) and whatever file gets
 * -finstrument-functions applied (so ITS functions have a valid
 * saved-ra slot for us to read). */

#define CFI_DEPTH 256
static unsigned long __cfi_shadow[CFI_DEPTH];   /* static - not on the single-page user stack */
static unsigned int  __cfi_top = 0;

__attribute__((no_instrument_function))
void __cyg_profile_func_enter(void *this_fn, void *call_site) {
    (void)this_fn;
    if (__cfi_top < CFI_DEPTH) __cfi_shadow[__cfi_top++] = (unsigned long)call_site;
}

__attribute__((no_instrument_function))
void __cyg_profile_func_exit(void *this_fn, void *call_site) {
    (void)this_fn; (void)call_site;
    if (__cfi_top == 0) return;
    unsigned long expected = __cfi_shadow[--__cfi_top];

    register unsigned long cur_s0 __asm__("s0");
    unsigned long foo_s0 = *(unsigned long *)(cur_s0 - 16);
    unsigned long actual  = *(unsigned long *)(foo_s0 - 8);

    if (actual != expected) {
        puts_rv("\033[31m*** CFI: return address hijacked! ***\033[0m\r\n");
        exit(139);   /* distinct code, matches malloc.h's heap_abort() convention */
    }
}
