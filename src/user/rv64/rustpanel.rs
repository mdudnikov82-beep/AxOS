// AxOS/RV64 — RustPanel: a real (if deliberately simple) Rust GUI
// program. Unlike hello_rust.rs's pure text demo, this draws to the
// framebuffer and reads the mouse — but ONLY via the raw gfx_*/
// mouse_state syscalls, not window.h/gfx_ui.h's helpers (window_init,
// ui_round_window, drag/resize, rounded corners+shadow...). Those are
// all `static` C functions with no exported symbol - nothing for a
// separately-compiled Rust object file to link against. Reimplementing
// that whole chrome toolkit in Rust would be its own big project; this
// stays honest about the scope instead: a flat, fixed-position panel,
// no title bar, no drag, no close button, no resize. Kill it from
// AxTaskMgr or `kill <pid>` in AxSH.
//
// Still a genuinely real program: live uptime display + a clickable
// button with a persistent counter, proving gfx_fill_rect/gfx_draw_text/
// gfx_flush/mouse_state/sleep_ms all work correctly called from Rust,
// not just write()/gettime() like the first demo.
#![no_std]
#![no_main]

use core::arch::asm;
use core::panic::PanicInfo;

const SYS_GETTIME: i64 = 5;
const SYS_GFX_INFO: i64 = 18;
const SYS_GFX_FILLRECT: i64 = 20;
const SYS_GFX_FLUSH: i64 = 21;
const SYS_GFX_DRAWTEXT: i64 = 22;
const SYS_MOUSE_STATE: i64 = 23;
const SYS_SLEEP: i64 = 29;

#[inline(always)]
unsafe fn syscall0(nr: i64) -> i64 {
    let ret: i64;
    asm!("ecall", in("a7") nr, lateout("a0") ret, options(nostack));
    ret
}

#[inline(always)]
unsafe fn syscall1(nr: i64, a0: i64) -> i64 {
    let mut ret = a0;
    asm!("ecall", inlateout("a0") ret, in("a7") nr, options(nostack));
    ret
}

#[inline(always)]
unsafe fn syscall4(nr: i64, a0: i64, a1: i64, a2: i64, a3: i64) -> i64 {
    let mut ret = a0;
    asm!(
        "ecall",
        inlateout("a0") ret,
        in("a1") a1,
        in("a2") a2,
        in("a3") a3,
        in("a7") nr,
        options(nostack)
    );
    ret
}

#[inline(always)]
unsafe fn syscall5(nr: i64, a0: i64, a1: i64, a2: i64, a3: i64, a4: i64) -> i64 {
    let mut ret = a0;
    asm!(
        "ecall",
        inlateout("a0") ret,
        in("a1") a1,
        in("a2") a2,
        in("a3") a3,
        in("a4") a4,
        in("a7") nr,
        options(nostack)
    );
    ret
}

fn gettime() -> i64 {
    unsafe { syscall0(SYS_GETTIME) }
}

fn sleep_ms(ms: i64) {
    unsafe {
        syscall1(SYS_SLEEP, ms);
    }
}

/// Returns None if no GPU, else Some((width, height)).
fn gfx_info() -> Option<(u32, u32)> {
    let v = unsafe { syscall0(SYS_GFX_INFO) };
    if v < 0 {
        return None;
    }
    let v = v as u64;
    Some(((v >> 32) as u32, (v & 0xFFFF_FFFF) as u32))
}

fn gfx_rgb(r: u32, g: u32, b: u32) -> u32 {
    (0xFFu32 << 24) | (r << 16) | (g << 8) | b
}

fn gfx_fill_rect(x: u32, y: u32, w: u32, h: u32, bgra: u32) {
    unsafe {
        syscall5(SYS_GFX_FILLRECT, x as i64, y as i64, w as i64, h as i64, bgra as i64);
    }
}

/// `s` MUST be NUL-terminated - the syscall takes a bare pointer (no
/// length argument, matching the C wrapper's `gfx_draw_text(x,y,str,bgra)`
/// signature exactly), so the kernel just reads bytes until it hits a
/// 0x00. Rust byte-string literals (`b"..."`) are NOT NUL-terminated
/// like C string literals are - `b"RustPanel"` is exactly 9 bytes with
/// whatever happens to follow it in .rodata right after, no implicit
/// terminator. Found live: an un-terminated title literal read straight
/// into the next literal's bytes, rendering "RustPanelClick" as one
/// string. Every literal passed here must end in an explicit `\0`; the
/// dynamically-built buffers below are fine as-is since they're
/// zero-initialized arrays and never written past their real content.
fn gfx_draw_text(x: u32, y: u32, s: &[u8], bgra: u32) {
    unsafe {
        syscall4(SYS_GFX_DRAWTEXT, x as i64, y as i64, s.as_ptr() as i64, bgra as i64);
    }
}

fn gfx_flush() {
    unsafe {
        syscall0(SYS_GFX_FLUSH);
    }
}

/// (x, y, buttons, focused) - None if no mouse device.
fn mouse_state() -> Option<(u32, u32, u32, u32)> {
    let v = unsafe { syscall0(SYS_MOUSE_STATE) };
    if v == -1 {
        return None;
    }
    let v = v as u64;
    let x = ((v >> 32) & 0xFFFF) as u32;
    let y = ((v >> 16) & 0xFFFF) as u32;
    let buttons = (v & 0xFF) as u32;
    let focused = ((v >> 8) & 1) as u32;
    Some((x, y, buttons, focused))
}

const PANEL_X: u32 = 500;
const PANEL_Y: u32 = 420;
const PANEL_W: u32 = 260;
const PANEL_H: u32 = 150;
const BTN_X: u32 = PANEL_X + 20;
const BTN_Y: u32 = PANEL_Y + 90;
const BTN_W: u32 = 220;
const BTN_H: u32 = 36;

/// Appends "<prefix><decimal v>" to `buf` starting at `*pos`, advancing
/// `*pos`. get_unchecked(_mut) instead of plain indexing - see
/// hello_rust.rs's comment: bounds-checked indexing needs panic
/// machinery this freestanding build doesn't have; every call site below
/// sizes `buf` generously enough by construction that this never
/// actually goes out of bounds.
fn append_line(buf: &mut [u8], pos: &mut usize, prefix: &[u8], v: u64) {
    unsafe {
        for &c in prefix {
            *buf.get_unchecked_mut(*pos) = c;
            *pos += 1;
        }
        if v == 0 {
            *buf.get_unchecked_mut(*pos) = b'0';
            *pos += 1;
            return;
        }
        let mut tmp = [0u8; 20];
        let mut t = 0usize;
        let mut n = v;
        while n > 0 {
            *tmp.get_unchecked_mut(t) = b'0' + (n % 10) as u8;
            n /= 10;
            t += 1;
        }
        while t > 0 {
            t -= 1;
            *buf.get_unchecked_mut(*pos) = *tmp.get_unchecked(t);
            *pos += 1;
        }
    }
}

fn render(clicks: u32) {
    let bg = gfx_rgb(15, 15, 30);
    let border = gfx_rgb(222, 165, 32); // warm orange accent - "made in Rust"
    gfx_fill_rect(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, border);
    gfx_fill_rect(PANEL_X + 2, PANEL_Y + 2, PANEL_W - 4, PANEL_H - 4, bg);

    gfx_draw_text(PANEL_X + 10, PANEL_Y + 8, b"RustPanel\0", gfx_rgb(255, 200, 120));

    let secs = (gettime() / 10_000_000) as u64;
    let mut line = [0u8; 40];
    let mut n = 0usize;
    append_line(&mut line, &mut n, b"Uptime: ", secs);
    unsafe {
        *line.get_unchecked_mut(n) = b's';
    }
    n += 1;
    gfx_draw_text(PANEL_X + 10, PANEL_Y + 34, unsafe { line.get_unchecked(..n) }, gfx_rgb(200, 200, 200));

    let mut cline = [0u8; 32];
    let mut cn = 0usize;
    append_line(&mut cline, &mut cn, b"Clicks: ", clicks as u64);
    gfx_draw_text(PANEL_X + 10, PANEL_Y + 56, unsafe { cline.get_unchecked(..cn) }, gfx_rgb(120, 220, 120));

    gfx_fill_rect(BTN_X, BTN_Y, BTN_W, BTN_H, gfx_rgb(0, 140, 0));
    gfx_draw_text(BTN_X + BTN_W / 2 - 5 * 16 / 2, BTN_Y + BTN_H / 2 - 8, b"Click\0", gfx_rgb(255, 255, 255));
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    if gfx_info().is_none() {
        return 1;
    }

    let mut clicks: u32 = 0;
    let mut prev_left = 0u32;
    render(clicks);
    gfx_flush();

    loop {
        if let Some((mx, my, buttons, focused)) = mouse_state() {
            let left = buttons & 1;
            if left != 0 && prev_left == 0 && focused != 0
                && mx >= BTN_X && mx < BTN_X + BTN_W
                && my >= BTN_Y && my < BTN_Y + BTN_H
            {
                clicks += 1;
            }
            prev_left = left;
        }

        render(clicks);
        gfx_flush();
        sleep_ms(100);
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}
