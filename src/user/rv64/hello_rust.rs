// AxOS/RV64 — первая программа на Rust. Никакого нового рантайма/загрузчика
// не потребовалось: та же crt0.S (`call main`, потом sys_exit(0)) и тот же
// user_rv64.ld, что и у C-программ — просто нужно, чтобы Rust-объектник
// экспортировал символ `main` с той же (extern "C") сигнатурой. Сисколлы —
// голый `ecall` через inline asm, копия соглашения из syscall.h (a7=nr,
// a0..a2=args, a0=ret).
#![no_std]
#![no_main]

use core::arch::asm;
use core::panic::PanicInfo;

const SYS_WRITE: i64 = 1;
const SYS_GETTIME: i64 = 5;

#[inline(always)]
unsafe fn syscall0(nr: i64) -> i64 {
    let ret: i64;
    asm!("ecall", in("a7") nr, lateout("a0") ret, options(nostack));
    ret
}

#[inline(always)]
unsafe fn syscall3(nr: i64, a0: i64, a1: i64, a2: i64) -> i64 {
    let mut ret = a0;
    asm!(
        "ecall",
        inlateout("a0") ret,
        in("a1") a1,
        in("a2") a2,
        in("a7") nr,
        options(nostack)
    );
    ret
}

fn write(fd: i64, buf: &[u8]) -> i64 {
    unsafe { syscall3(SYS_WRITE, fd, buf.as_ptr() as i64, buf.len() as i64) }
}

fn gettime() -> i64 {
    unsafe { syscall0(SYS_GETTIME) }
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    write(1, b"Hello from Rust!\r\n");
    write(1, b"AxOS/RV64: rustc + riscv64imac-unknown-none-elf works.\r\n");

    write(1, b"Timer value: ");
    let mut buf = [0u8; 24];
    let mut i = 0usize;
    let mut n = gettime() as u64;
    // get_unchecked(_mut) instead of buf[i]: plain indexing inserts a
    // bounds check that calls core::panicking::panic_bounds_check on
    // failure, which needs Rust's full panic-formatting machinery to
    // resolve - not present in this freestanding build (no build-std,
    // no eh_personality). i is always < 24 by construction (u64::MAX is
    // 20 decimal digits + 2 for \r\n), so the check is genuinely
    // redundant here - same "trust the invariant, don't validate what
    // can't happen" approach the rest of this codebase already takes.
    unsafe {
        if n == 0 {
            *buf.get_unchecked_mut(i) = b'0';
            i += 1;
        } else {
            while n > 0 {
                *buf.get_unchecked_mut(i) = b'0' + (n % 10) as u8;
                n /= 10;
                i += 1;
            }
        }
        buf.get_unchecked_mut(..i).reverse();
        *buf.get_unchecked_mut(i) = b'\r';
        i += 1;
        *buf.get_unchecked_mut(i) = b'\n';
        i += 1;
        write(1, buf.get_unchecked(..i));
    }

    0
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}
