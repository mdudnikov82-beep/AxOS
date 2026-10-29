# Generates sw/plaq_test.axasm + tb/tb_plaq.v for AxISA v2.2 (PLAQ, the
# lattice-QCD plaquette). Run from hardware/axisa_core.
#
# P = (1/3) Re Tr(U1 U2 U3^dag U4^dag) for the 4 links around one square
# of the lattice. The links are real SU(3) elements (products of
# exp(i*theta*lambda_k), checked unitary with det 1 in float64), rounded
# to binary32. The expected words come from a binary32 reference model
# that follows docs/ISA.md's exact order - NOT from the RTL. (Rounding
# each binary32 op through a Python double is exact: double has >= 2*24+2
# bits, so double rounding is innocuous for +, -, *.)
import cmath
import math
import struct
import sys

sys.path.insert(0, 'sw')
from asm_test1 import plaq


def f32(x):
    return struct.unpack('<f', struct.pack('<f', x))[0]


def bits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def dag(m):
    return [[m[j][i].conjugate() for j in range(3)] for i in range(3)]


def expl(k, t):
    """exp(i t lambda_k) for the Gell-Mann matrix lambda_k."""
    c, s = math.cos(t), math.sin(t)
    m = [[1 + 0j, 0j, 0j], [0j, 1 + 0j, 0j], [0j, 0j, 1 + 0j]]
    if k == 1:   m[0][0], m[0][1], m[1][0], m[1][1] = c, 1j * s, 1j * s, c
    elif k == 2: m[0][0], m[0][1], m[1][0], m[1][1] = c, s, -s, c
    elif k == 4: m[0][0], m[0][2], m[2][0], m[2][2] = c, 1j * s, 1j * s, c
    elif k == 5: m[0][0], m[0][2], m[2][0], m[2][2] = c, s, -s, c
    elif k == 6: m[1][1], m[1][2], m[2][1], m[2][2] = c, 1j * s, 1j * s, c
    elif k == 7: m[1][1], m[1][2], m[2][1], m[2][2] = c, s, -s, c
    elif k == 3: m[0][0], m[1][1] = cmath.exp(1j * t), cmath.exp(-1j * t)
    elif k == 8:
        r = t / math.sqrt(3)
        m[0][0], m[1][1], m[2][2] = cmath.exp(1j * r), cmath.exp(1j * r), cmath.exp(-2j * r)
    return [[complex(z) for z in row] for row in m]


def su3(*gens):
    """A float64 SU(3) element - checked, not assumed."""
    m = [[1 + 0j, 0j, 0j], [0j, 1 + 0j, 0j], [0j, 0j, 1 + 0j]]
    for k, t in gens:
        m = matmul(m, expl(k, t))
    uu = matmul(m, dag(m))
    assert all(abs(uu[i][j] - (i == j)) < 1e-12 for i in range(3) for j in range(3))
    det = (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
           + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))
    assert abs(det - 1) < 1e-12
    return m


def r32(m):
    return [[complex(f32(z.real), f32(z.imag)) for z in row] for row in m]


def term(a, b, c, d):
    """(a+bi)(c+di) the way the FPU does it."""
    return f32(f32(a * c) - f32(b * d)), f32(f32(a * d) + f32(b * c))


def ref_plaq(u1, u2, u3, u4):
    """docs/ISA.md's exact binary32 order: Tr M = sum_k (M e_k)_k."""
    tr = 0.0
    for k in range(3):
        # conj(a + bi) is a sign flip of the Im word
        v = [(u4[k][j].real, -u4[k][j].imag) for j in range(3)]                       # U4^dag e_k
        for elem in (lambda i, j: (u3[j][i].real, -u3[j][i].imag),                    # U3^dag
                     lambda i, j: (u2[i][j].real, u2[i][j].imag)):                    # U2
            w = []
            for i in range(3):
                acc_re = acc_im = 0.0
                for j in range(3):
                    t_re, t_im = term(*elem(i, j), *v[j])
                    acc_re, acc_im = f32(acc_re + t_re), f32(acc_im + t_im)
                w.append((acc_re, acc_im))
            v = w
        for j in range(3):                                                             # Re (U1 v)_k
            t_re, _ = term(u1[k][j].real, u1[k][j].imag, *v[j])
            tr = f32(tr + t_re)
    return f32(tr * f32(1 / 3))


def plaq64(u1, u2, u3, u4):
    m = matmul(matmul(matmul(u1, u2), dag(u3)), dag(u4))
    return (m[0][0] + m[1][1] + m[2][2]).real / 3


IDENT = su3()
A = su3((1, 0.7), (4, -0.4), (6, 1.1), (3, 0.3), (8, -0.9))
B = su3((2, 0.5), (5, 1.3), (7, -0.8), (8, 0.6))
C = su3((3, 1.9), (6, -0.6), (1, 0.45), (7, 1.2))
D = su3((5, -1.4), (8, 2.1), (2, 0.35), (4, 0.9))
# a "warm" square: links close to 1, like a lattice at large beta
W = [su3((1, 0.08), (5, -0.05)), su3((3, 0.06), (7, 0.04)),
     su3((2, -0.07), (8, 0.05)), su3((4, 0.03), (6, -0.09))]

# a gauge transformation g(x) at the square's 4 corners x, x+mu, x+mu+nu, x+nu:
# U_mu(x) -> g(x) U_mu(x) g(x+mu)^dag, ... The plaquette must not change.
g0, g1, g2, g3 = su3((1, 1.3), (8, 0.4)), su3((5, -0.9), (3, 0.7)), su3((7, 2.2), (4, -0.3)), su3((6, 0.5), (2, 1.6))
GAUGED = [matmul(matmul(g0, A), dag(g1)), matmul(matmul(g1, B), dag(g2)),
          matmul(matmul(g3, C), dag(g2)), matmul(matmul(g0, D), dag(g3))]

LAST = 0x1000 - 288                      # 0xEE0: the highest legal base (ends at 0xFFF)
SQUARES = [   # base, links (float64), note
    (0x400, [IDENT] * 4, "cold lattice: every link = 1, P = 1 exactly"),
    (0x600, [A, B, C, D], "hot square: 4 dense random SU(3) links"),
    (0x800, GAUGED, "the same square after a gauge transformation"),
    (0xA00, W, "warm square: links near 1"),
    (LAST, [A, A, A, A], "U1 = U2 = U3 = U4 at the highest legal base: P = 1 up to rounding"),
]
results = []
for base, links, note in SQUARES:
    l32 = [r32(u) for u in links]
    p = ref_plaq(*l32)
    p64 = plaq64(*links)
    assert -1 / 2 - 1e-6 <= p64 <= 1 + 1e-12, "SU(3): -1/2 <= P <= 1"
    assert abs(p - p64) < 1e-5, (note, p, p64)
    results.append(p)
    print(f"0x{base:03X}  P = {p:+.7f} (0x{bits(p):08X})  float64 {p64:+.9f}  {note}")
assert results[0] == 1.0
assert abs(plaq64(*SQUARES[1][1]) - plaq64(*GAUGED)) < 1e-12, "gauge invariance (float64)"
assert abs(results[1] - results[2]) < 1e-5
assert results[3] > 0.98 and abs(results[1]) < 0.5

asm = ["""# AxISA v2.2 (see docs/ISA.md's PLAQ section): the plaquette
# P = (1/3) Re Tr(U1 U2 U3^dag U4^dag) of one lattice square. GENERATED by
# tools/gen_plaq_test.py - the expected bits in tb/tb_plaq.v come from its
# binary32 reference model. The testbench preloads the links into data
# memory (as a lattice loader would). Each P is STOREd to 0x300 + 4*i.
"""]
for i, (base, links, note) in enumerate(SQUARES):
    asm.append(f"# {note}")
    asm.append(f"    ADDI N1, N0, 0x{base:X}")
    if i == 3:
        asm.append("    PLAQ N1, N1               # nd == ns: the base is read before nd is written")
        asm.append(f"    STORE N1, N0, 0x{0x300 + 4 * i:X}")
    else:
        asm.append("    PLAQ N2, N1")
        asm.append(f"    STORE N2, N0, 0x{0x300 + 4 * i:X}")
asm += [
    "# illegal: misaligned base",
    "    ADDI N1, N0, 0x602",
    "    PLAQ N2, N1",
    "# illegal: the 4 links would run into the UART window",
    f"    ADDI N1, N0, 0x{LAST + 4:X}",
    "    PLAQ N2, N1",
    """# user mode: PLAQ reads physical memory, so it is kernel-only
    ADDI N1, N0, 0
    MTSMODE N1               # saved_mode = user
    ADDI N1, N0, user_code
    MTEPC N1
    RFT
user_code:
    ADDI N1, N0, 0x600
    PLAQ N2, N1              # must trap: privilege violation (CAUSE 3)
    HALT N7                  # tohost = traps taken (expect 3)

.org 0x200
handler:
    MFCAUSE N3
    ADD N6, N6, N3           # n6 = sum of causes (expect 0+0+3 = 3)
    ADDI N7, N7, 1           # n7 = trap count
    MFEPC N5
    ADDI N5, N5, 4           # skip the trapping instruction
    MTEPC N5
    RFT
"""]
text = "\n".join(asm)
words = 0
for line in text.splitlines():
    code = line.split('#', 1)[0].strip()
    if code.startswith('user_code:'):
        break
    if code and not code.endswith(':'):
        words += 1
assert 4 * words < 0x200
text = text.replace("ADDI N1, N0, user_code", f"ADDI N1, N0, 0x{4 * words:X}   # = user_code")
open('sw/plaq_test.axasm', 'w', encoding='utf-8').write(text)

tb = open('tb/tb_gluon.v', encoding='utf-8').read()
tb = """// AxISA v2.2 (see sw/plaq_test.axasm and docs/ISA.md's PLAQ section):
// bit-exact lattice plaquettes - cold, hot, gauge-transformed, warm and
// U1=U2=U3=U4 squares, nd == ns, 3 traps, and 913 cycles per PLAQ.
// GENERATED by tools/gen_plaq_test.py.
`timescale 1ns/1ps
""" + tb[tb.index('`ifndef INSTR_HEX'):]
tb = tb.replace('sw/gluon_test.hex', 'sw/plaq_test.hex').replace('module tb_gluon;', 'module tb_plaq;')
assert 'max_cycles = 200;' in tb
tb = tb.replace('max_cycles = 200;', 'max_cycles = 5000;')
preload = []
for base, links, _ in SQUARES:
    for m, u in enumerate(r32(x) for x in links):
        for i in range(3):
            for j in range(3):
                w = (base + 72 * m) // 4 + 2 * (3 * i + j)
                preload.append(f"        dut.dmem.mem[{w}] = 32'h{bits(u[i][j].real):08X};")
                preload.append(f"        dut.dmem.mem[{w + 1}] = 32'h{bits(u[i][j].imag):08X};")
tb = tb.replace("    always #5 clk = ~clk;", """    always #5 clk = ~clk;

    // cycles each PLAQ keeps is_plaq high (the trapping ones count 1)
    integer lat [0:15];
    integer n_lat, cur;
    initial begin n_lat = 0; cur = 0; end
    always @(posedge clk) begin
        if (!reset && dut.is_plaq) cur = cur + 1;
        else if (cur != 0) begin
            if (n_lat < 16) lat[n_lat] = cur;
            n_lat = n_lat + 1;
            cur = 0;
        end
    end""")
tb = tb.replace("        reset = 0;\n", "        // lattice loader: the link matrices of 5 squares\n" + "\n".join(preload) + "\n        reset = 0;\n", 1)
a = tb.index("            check(tohost_value, 32'd2"); b = tb.index('        end\n\n        if (errors == 0)')
lines = ["            check(tohost_value, 32'd3, \"tohost (n7 = traps taken)\");",
         "            check(dut.n_bank.regs[6], 32'd3, \"n6 (causes 0+0+3: 2 ILLEGAL, 1 PRIV)\");"]
for i, (p, (base, _, _)) in enumerate(zip(results, SQUARES)):
    lines.append(f"            check(dut.dmem.mem[{(0x300 + 4 * i) // 4}], 32'h{bits(p):08X}, \"P of square 0x{base:03X} ({p:+.6f})\");")
n_ok = len(SQUARES)
lines.append(f"            check(n_lat, {n_ok + 3}, \"PLAQ instructions seen\");")
for k in range(n_ok):
    lines.append(f"            check(lat[{k}], 913, \"cycles of legal PLAQ #{k}\");")
for k in range(3):
    lines.append(f"            check(lat[{n_ok + k}], 1, \"cycles of trapping PLAQ #{k}\");")
tb = tb[:a] + "\n".join(lines) + "\n" + tb[b:]
tb = tb.replace('ALL AXISA GLUON TESTS PASSED', 'ALL AXISA PLAQ TESTS PASSED').replace('AXISA GLUON TEST(S) FAILED', 'AXISA PLAQ TEST(S) FAILED')
open('tb/tb_plaq.v', 'w', encoding='utf-8').write(tb)
