#!/usr/bin/env python3
"""
Assembles a flat RV32IM test binary for AxOS rv32i interpreter.
Tests: MUL, DIV, REM, DIVU, DIV-by-zero edge case.
Usage: python tools/make_rvtest.py
Output: build/rvtest.bin  +  fs/RVTEST.RV
"""
import struct, os

def u(v): return v & 0xFFFFFFFF
z=0; t0=5; t1=6; t2=7; t3=28; a0=10; a7=17

# Instruction encoders
def I_(op, rd, rs1, f3, imm):
    return u((( imm & 0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def R_(rd, rs1, rs2, f3, f7):
    return u((f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|0x33)
def B_(f3, rs1, rs2, off):
    o = off & 0x1FFF
    return u((((o>>12)&1)<<31)|(((o>>5)&63)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|
             (((o>>1)&15)<<8)|(((o>>11)&1)<<7)|0x63)
def J_(rd, off):
    o = off & 0x1FFFFF
    return u((((o>>20)&1)<<31)|(((o>>1)&0x3FF)<<21)|(((o>>11)&1)<<20)|
             (((o>>12)&0xFF)<<12)|(rd<<7)|0x6F)
def LUI_(rd, hi20): return u(((hi20 & 0xFFFFF)<<12)|(rd<<7)|0x37)
ECALL_ = 0x73

# ---- Two-pass assembler ----
words   = []
labels  = {}
fixups  = []  # (word_idx, kind, f3, rs1, rs2, label)

def LBL(n):  labels[n] = len(words)
def W(v):    words.append(u(v))

def LI(rd, v):
    """Load 12-bit immediate (must be -2048..2047)."""
    W(I_(0x13, rd, z, 0, v))

def LA(rd, addr):
    """Load VM address (0..2047) into rd."""
    W(I_(0x13, rd, z, 0, addr))

def MUL(rd,r1,r2): W(R_(rd,r1,r2,0,1))
def DIV(rd,r1,r2): W(R_(rd,r1,r2,4,1))
def DIVU(rd,r1,r2): W(R_(rd,r1,r2,5,1))
def REM(rd,r1,r2): W(R_(rd,r1,r2,6,1))
def MULH(rd,r1,r2): W(R_(rd,r1,r2,1,1))

def BEQ(rs1, rs2, lbl):
    fixups.append((len(words), 'B', 0, rs1, rs2, lbl)); words.append(0)

def J(lbl):
    fixups.append((len(words), 'J', 0, 0, 0, lbl)); words.append(0)

def ECALL(): W(ECALL_)

# ---- String table (must be defined before code so offsets are known) ----
DATA_OFF = 0x140  # 320 bytes — code fits in 0x00..0x13F

_sdata = b""
soff   = {}
def S(k, txt):
    global _sdata
    soff[k] = DATA_OFF + len(_sdata)
    _sdata += txt.encode() + b'\x00'

S("hdr",    "RV32IM test\n")
S("mul_ok", "MUL 6x7=42 OK\n")
S("mul_no", "MUL FAIL\n")
S("div_ok", "DIV 100/4=25 OK\n")
S("div_no", "DIV FAIL\n")
S("rem_ok", "REM 17%5=2 OK\n")
S("rem_no", "REM FAIL\n")
S("du_ok",  "DIVU 255/3=85 OK\n")
S("du_no",  "DIVU FAIL\n")
S("dbz_ok", "DIV/0=-1 OK\n")
S("dbz_no", "DIV/0 FAIL\n")
S("mh_ok",  "MULH OK\n")
S("mh_no",  "MULH FAIL\n")
S("done",   "All done!\n")

assert all(v < 2048 for v in soff.values()), "String addr exceeds addi range"

# ---- Program ----

# Print header
LI(a7, 4); LA(a0, soff["hdr"]); ECALL()

def test(name, op_fn, v1, v2, expected):
    """Emit: load v1→t0, v2→t1, op t2=t0 op t1, compare to expected, print ok/no."""
    LI(t0, v1); LI(t1, v2)
    op_fn(t2, t0, t1)
    LI(t3, expected)
    BEQ(t2, t3, name + "_ok")
    LI(a7, 4); LA(a0, soff[name + "_no"]); ECALL()
    J("done")
    LBL(name + "_ok")
    LI(a7, 4); LA(a0, soff[name + "_ok"]); ECALL()

test("mul", MUL,  6, 7,   42)
test("div", DIV,  100, 4, 25)
test("rem", REM,  17, 5,  2)
test("du",  DIVU, 255, 3, 85)

# DIV by zero: DIV(t2, 1, 0) → t2 must equal 0xFFFFFFFF = -1 as signed
LI(t0, 1); LI(t1, 0)
DIV(t2, t0, t1)
LI(t3, -1)          # -1 == 0xFFFFFFFF, fits in addi imm12
BEQ(t2, t3, "dbz_ok")
LI(a7, 4); LA(a0, soff["dbz_no"]); ECALL()
J("done")
LBL("dbz_ok")
LI(a7, 4); LA(a0, soff["dbz_ok"]); ECALL()

# MULH: (-1) * (-1) upper word → 0 (product = 1 = 0x00000001_FFFFFFFF... no)
# Actually: MULH (signed): (-1) * 2 = -2 = 0xFFFFFFFE, upper word = 0xFFFFFFFF
LI(t0, -1); LI(t1, 2)
MULH(t2, t0, t1)
LI(t3, -1)          # upper word of (-2) = 0xFFFFFFFF = -1
BEQ(t2, t3, "mh_ok")
LI(a7, 4); LA(a0, soff["mh_no"]); ECALL()
J("done")
LBL("mh_ok")
LI(a7, 4); LA(a0, soff["mh_ok"]); ECALL()

# Done
LBL("done")
LI(a7, 4); LA(a0, soff["done"]); ECALL()
LI(a7, 10); ECALL()

# ---- Resolve fixups ----
for idx, kind, f3, rs1, rs2, lbl in fixups:
    pc     = idx * 4
    target = labels[lbl] * 4
    off    = target - pc
    if kind == 'B': words[idx] = B_(f3, rs1, rs2, off)
    else:           words[idx] = J_(0, off)

# ---- Assemble ----
code_bytes = struct.pack(f'<{len(words)}I', *words)
code_size  = len(code_bytes)
assert code_size <= DATA_OFF, f"Code overflow: {code_size} > {DATA_OFF}"

binary = code_bytes + b'\x00' * (DATA_OFF - code_size) + _sdata
print(f"Code:  {code_size} bytes ({len(words)} instructions)")
print(f"Data:  {len(_sdata)} bytes at offset 0x{DATA_OFF:x}")
print(f"Total: {len(binary)} bytes")

os.makedirs("build", exist_ok=True)
os.makedirs("fs", exist_ok=True)
with open("build/rvtest.bin", "wb") as f: f.write(binary)
with open("fs/RVTEST.RV",    "wb") as f: f.write(binary)
print("Written: build/rvtest.bin, fs/RVTEST.RV")
