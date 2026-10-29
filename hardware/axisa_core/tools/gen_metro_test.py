# Generates the METRO tests for AxISA v2.2 step 2 (the Metropolis step).
# Run from hardware/axisa_core.
#
#   sw/metro_test.axasm + tb/tb_metro.v: WEIGHT = min(1, exp(-dS)) bit-exact
#     against a binary32 reference model of docs/ISA.md's exact order (NOT
#     the RTL), its accuracy against math.exp, the ACCEPT rate for w = 1,
#     0, 1/4 and 3/4, and the cycle counts.
#   sw/metro_chain.axasm + tb/tb_metro_chain.v: a real Markov chain. One
#     link of a lattice square can be any of 8 SU(3) matrices; the program
#     measures each square's plaquette with PLAQ, then runs Metropolis at
#     beta = 6.0 and histograms where the chain is. The histogram must
#     match Boltzmann's exp(-S) = exp(-beta (1 - P)), within a tolerance
#     taken from 400 simulated chains, not guessed.
#
# The polynomial for 2^-t is fitted here too, and the RTL's constants must
# match (checked against rtl/cpu_core.v below).
import math
import random
import re
import struct
import sys

sys.path.insert(0, 'sw')
sys.path.insert(0, 'tools')
from gen_plaq_test import su3, matmul, dag, r32, ref_plaq, plaq64, bits, f32  # noqa: E402 (also regenerates the PLAQ test)


def fbits(b):
    return struct.unpack('<f', struct.pack('<I', b))[0]


# ---- the reference model -------------------------------------------------
LOG2E = f32(1 / math.log(2))
C = [1.0, fbits(0xBF317216), fbits(0x3E75FD5C), fbits(0xBD634A03),
     fbits(0x3C1CF011), fbits(0xBAA70867), fbits(0x38E4607B)]


def ref_weight(p_old, p_new, beta):
    d = f32(p_old - p_new)
    x = f32(beta * d)
    if x <= 0:
        return 1.0
    y = f32(x * LOG2E)
    if y >= 128:
        return 0.0
    n = int(y)                      # exact: y = n + t, both representable
    t = y - n
    q = C[6]
    for k in range(5, -1, -1):
        q = f32(f32(q * t) + C[k])
    qb = bits(q)
    e = (qb >> 23) & 0xFF
    return fbits(((e - n) << 23) | (qb & 0x7FFFFF)) if e > n else 0.0


# the polynomial really is 2^-t to 1.8e-7, and the RTL uses these constants
worst = max(abs(ref_weight(f32(i / 4096 * math.log(2)), 0.0, 1.0) / math.exp(-f32(i / 4096 * math.log(2))) - 1) for i in range(1, 4096))
assert worst < 1e-6, worst
rtl = open('rtl/cpu_core.v', encoding='utf-8').read()
for c in C[1:]:
    assert f"32'h{bits(c):08X}" in rtl, f"RTL lacks coefficient {bits(c):08X}"
assert f"32'h{bits(LOG2E):08X}" in rtl


def load32(reg, v):
    """reg = 32-bit word v, in 5 in-bank instructions (11+11+10 bits)."""
    z = reg[0] + "0"
    return [f"ADDI {reg}, {z}, {v >> 21}", f"SLLI {reg}, {reg}, 11", f"ORI {reg}, {reg}, {(v >> 10) & 0x7FF}",
            f"SLLI {reg}, {reg}, 10", f"ORI {reg}, {reg}, {v & 0x3FF}"]


def tb_from_gluon(name, hexname, header, max_cycles):
    tb = open('tb/tb_gluon.v', encoding='utf-8').read()
    tb = header + "`timescale 1ns/1ps\n" + tb[tb.index('`ifndef INSTR_HEX'):]
    tb = tb.replace('sw/gluon_test.hex', f'sw/{hexname}.hex').replace('module tb_gluon;', f'module tb_{name};')
    assert 'max_cycles = 200;' in tb
    return tb.replace('max_cycles = 200;', f'max_cycles = {max_cycles};')


def set_checks(tb, lines, tag):
    a = tb.index("            check(tohost_value, 32'd2"); b = tb.index('        end\n\n        if (errors == 0)')
    tb = tb[:a] + "\n".join(lines) + "\n" + tb[b:]
    return tb.replace('ALL AXISA GLUON TESTS PASSED', f'ALL AXISA {tag} TESTS PASSED').replace('AXISA GLUON TEST(S) FAILED', f'AXISA {tag} TEST(S) FAILED')


# ---- test 1: WEIGHT bit-exact, ACCEPT rates, timing -----------------------
random.seed(2026)
LN2 = math.log(2)
W_CASES = [   # (p_old, p_new, beta, note)
    (0.5, 0.9, 6.0, "dS < 0: the new plaquette is better -> 1"),
    (0.7, 0.7, 6.0, "dS = 0 -> 1"),
    (0.7, 0.1, 0.0, "beta = 0 (infinite temperature) -> 1"),
    (0.9, 0.89999, 6.0, "tiny dS: y < 1, n = 0"),
    (LN2, 0.0, 1.0, "dS = ln 2 -> 1/2"),
    (1.0, 0.0, 1.0, "dS = 1 -> 1/e"),
    (0.95, 0.4, 6.0, "beta = 6: dS = 3.3"),
    (5.5, 0.0, 1.0, "dS = 5.5"),
    (20.0, 0.0, 1.0, "dS = 20"),
    (87.0, 0.0, 1.0, "dS = 87: still a normal float"),
    (88.5, 0.0, 1.0, "dS = 88.5: y > 127, w would be subnormal -> 0"),
    (100.0, 0.0, 1.0, "dS = 100: y >= 128 -> 0"),
]
for _ in range(24):
    W_CASES.append((random.uniform(-0.5, 1.0), random.uniform(-0.5, 1.0), random.choice([1.0, 2.5, 5.7, 6.0, 30.0]), "random"))
W_CASES = [(f32(a), f32(b), f32(be), note) for a, b, be, note in W_CASES]
w_res = []
for a, b, be, note in W_CASES:
    w = ref_weight(a, b, be)
    exact = min(1.0, math.exp(-be * (a - b)))
    if w != 0.0 and exact > 1.2e-38:
        x = f32(be * f32(a - b))
        # y = fl(x log2 e) is rounded, so the relative error grows with x
        assert abs(w / min(1.0, math.exp(-x)) - 1) < 2e-7 + 1.2e-7 * max(x, 0.0), (note, w, exact)
    w_res.append(w)
assert w_res[0] == w_res[1] == w_res[2] == 1.0 and w_res[10] == w_res[11] == 0.0
assert abs(w_res[4] - 0.5) < 1e-7

RATES = [   # (p_old, beta, expected w, note) with p_new = 0
    (-0.5, 1.0, "w = 1: always accept"),
    (200.0, 1.0, "w = 0: never accept, even when r = 0 (the testbench forces the LFSR to 0)"),
    (math.log(4), 1.0, "w = 1/4"),
    (math.log(4 / 3), 1.0, "w = 3/4"),
]
DRAWS = 2000
WBASE, RBASE = 0x300, 0x400

asm = ["""# AxISA v2.2 step 2 (see docs/ISA.md's METRO section): the Metropolis
# step. GENERATED by tools/gen_metro_test.py - the expected WEIGHT bits
# in tb/tb_metro.v come from its binary32 reference model. Results are
# STOREd: weights to 0x300 + 4*i, accept counts to 0x400 + 4*i.
"""]
for i, (a, b, be, note) in enumerate(W_CASES):
    asm.append(f"# WEIGHT: {note}")
    asm += ["    " + x for x in load32("N1", bits(a)) + load32("N2", bits(b)) + load32("N3", bits(be))]
    if i == len(W_CASES) - 1:   # nd == beta: nd is written only on the last cycle
        asm += ["    METRO WEIGHT, N3, N1, N2, N3   # nd == beta", f"    STORE N3, N0, 0x{WBASE + 4 * i:X}"]
    else:
        asm += ["    METRO WEIGHT, N4, N1, N2, N3", f"    STORE N4, N0, 0x{WBASE + 4 * i:X}"]
for i, (a, be, note) in enumerate(RATES):
    asm.append(f"# ACCEPT x {DRAWS}: {note}")
    asm += ["    " + x for x in load32("N1", bits(f32(a))) + load32("N3", bits(f32(be)))]
    asm += [f"    ADDI N6, N0, {DRAWS}", "    ADDI N7, N0, 0",
            f"rate{i}:",
            "    METRO ACCEPT, N4, N1, N0, N3",
            "    ADD N7, N7, N4",
            "    ADDI N6, N6, -1",
            f"    BNE N6, N0, rate{i}",
            f"    STORE N7, N0, 0x{RBASE + 4 * i:X}"]
asm.append("    HALT N0")
open('sw/metro_test.axasm', 'w', encoding='utf-8').write("\n".join(asm) + "\n")

tb = tb_from_gluon('metro', 'metro_test', """// AxISA v2.2 step 2 (see sw/metro_test.axasm and docs/ISA.md's METRO
// section): bit-exact Boltzmann weights, accept rates, cycle counts.
// GENERATED by tools/gen_metro_test.py.
""", 200000)
tb = tb.replace("    always #5 clk = ~clk;", """    always #5 clk = ~clk;

    // cycles each METRO keeps is_metro high, by kind
    integer lat [0:8191];
    integer n_lat, cur;
    initial begin n_lat = 0; cur = 0; end
    always @(posedge clk) begin
        if (!reset && dut.is_metro) cur = cur + 1;
        else if (cur != 0) begin
            if (n_lat < 8192) lat[n_lat] = cur;
            n_lat = n_lat + 1;
            cur = 0;
        end
    end""")
lines = ["            check(tohost_value, 32'd0, \"tohost\");"]
for i, ((a, b, be, note), w) in enumerate(zip(W_CASES, w_res)):
    lines.append(f"            check(dut.dmem.mem[{(WBASE + 4 * i) // 4}], 32'h{bits(w):08X}, \"w #{i} ({w:.6g})\");")
sigma_lines = []
for i, (a, be, note) in enumerate(RATES):
    w = ref_weight(f32(a), 0.0, f32(be))
    mean = DRAWS * w
    tol = max(1, int(4.5 * math.sqrt(DRAWS * w * (1 - w)) + 0.999))
    lo, hi = max(0, int(mean - tol)), min(DRAWS, int(math.ceil(mean + tol)))
    if w == 0.0:
        lo = hi = 0   # r = 0 is forced: accept means r < w strictly
    sigma_lines.append(f"            in_range(dut.dmem.mem[{(RBASE + 4 * i) // 4}], {lo}, {hi}, \"accepts of {DRAWS}, w = {w:.4f}\");")
lines += sigma_lines
lines.append(f"            check(n_lat, {len(W_CASES) + len(RATES) * DRAWS}, \"METRO instructions seen\");")
FORCE = f"""
    // The w = 0 loop runs with the LFSR forced to 0, so r = +0 exactly:
    // r < w must still say no. From rate 0's stored count until rate 2's
    // P_old (ln 4) is loaded.
    initial begin
        wait (dut.dmem.mem[{RBASE // 4}] == {DRAWS});
        force dut.lfsr_q = 32'h0;
        wait (dut.n_bank.regs[1] === 32'h{bits(f32(math.log(4))):08X});
        release dut.lfsr_q;
    end
"""
for i, (a, b, be, note) in enumerate(W_CASES):
    x = f32(be * f32(a - b))
    cyc = 5 if x <= 0 else 6 if f32(x * LOG2E) >= 128 else 19
    lines.append(f"            check(lat[{i}], {cyc}, \"cycles of WEIGHT #{i}\");")
lines.append(f"            check(lat[{len(W_CASES)}], 6, \"cycles of ACCEPT, dS <= 0\");")
lines.append(f"            check(lat[{len(W_CASES) + DRAWS}], 7, \"cycles of ACCEPT, w = 0\");")
lines.append(f"            check(lat[{len(W_CASES) + 2 * DRAWS}], 20, \"cycles of ACCEPT, full path\");")
tb = set_checks(tb, lines, 'METRO')
tb = tb.replace("    task check(", FORCE + "\n    task check(", 1)
tb = tb.replace("    initial begin\n        errors = 0;", """    task in_range(input [31:0] got, input [31:0] lo, input [31:0] hi, input [48*8-1:0] name);
        begin
            if (got < lo || got > hi) begin
                $display("FAIL: %0s got=%0d expected %0d..%0d", name, got, lo, hi);
                errors = errors + 1;
            end else
                $display("PASS: %0s = %0d (allowed %0d..%0d)", name, got, lo, hi);
        end
    endtask

    initial begin
        errors = 0;""", 1)
open('tb/tb_metro.v', 'w', encoding='utf-8').write(tb)

# ---- test 2: a Markov chain that must sample Boltzmann's distribution ----
BETA = 6.0
U2 = su3((2, 0.5), (5, 1.3), (7, -0.8), (8, 0.6))
U3 = su3((3, 1.9), (6, -0.6), (1, 0.45), (7, 1.2))
U4 = su3((5, -1.4), (8, 2.1), (2, 0.35), (4, 0.9))
V = matmul(matmul(U2, dag(U3)), dag(U4))          # P(U1) = (1/3) Re Tr(U1 V)
K = 8
CANDS = [matmul(su3((3, 0.23 * m), (1, 0.11 * m), (6, -0.07 * m)), dag(V)) for m in range(K)]
SQ = [0x400 + 0x120 * m for m in range(K)]       # 8 squares of 288 bytes: 0x400..0xCFF
P = [ref_plaq(r32(c), r32(U2), r32(U3), r32(U4)) for c in CANDS]
for c, p in zip(CANDS, P):
    assert abs(p - plaq64(c, U2, U3, U4)) < 1e-5
assert P[0] > 0.9999 and min(P) < 0.4
pi = [math.exp(-BETA * (1 - p)) for p in P]
pi = [x / sum(pi) for x in pi]
STEPS = 3000
COIN_W = ref_weight(f32(LN2), 0.0, 1.0)


def chain(rng):
    m, hist = 0, [0] * K
    for _ in range(STEPS):
        m2 = (m + (1 if rng.random() < COIN_W else -1)) % K
        if rng.random() < ref_weight(P[m], P[m2], BETA):
            m = m2
        hist[m] += 1
    return hist


rng = random.Random(7)
runs = [chain(rng) for _ in range(400)]
TOL = []
for m in range(K):
    dev = sorted(abs(h[m] - STEPS * pi[m]) for h in runs)
    TOL.append(int(1.5 * dev[-1]) + 5)           # 1.5x the worst of 400 chains
mean_hist = [sum(h[m] for h in runs) / len(runs) for m in range(K)]

T_P, T_HIST, T_CONST = 0x300, 0x340, 0x380      # P table, histogram, constants
asm = [f"""# AxISA v2.2 step 2: a real Metropolis Markov chain on the processor.
# GENERATED by tools/gen_metro_test.py. One link U1 of a lattice square
# can be any of {K} SU(3) matrices (the testbench preloads the {K} squares
# [C_m, U2, U3, U4] at 0x400 + 0x120*m). The program measures every
# square's plaquette with PLAQ into a table, then runs {STEPS} Metropolis
# steps at beta = {BETA}: propose m' = m +- 1 (mod {K}) with a fair coin,
# accept with METRO, count where the chain is. Detailed balance makes the
# histogram Boltzmann's exp(-beta (1 - P_m)) - tb/tb_metro_chain.v checks.
#
# n1 = 4*m   n2 = P_m   n6 = steps left   n3/n4/n5/n7 = scratch
# constants: 0x{T_CONST:X} = ln 2, +4 = 1.0, +8 = beta
"""]
for m in range(K):
    asm += [f"    ADDI N1, N0, 0x{SQ[m]:X}", "    PLAQ N2, N1", f"    STORE N2, N0, 0x{T_P + 4 * m:X}"]
asm += [f"""    ADDI N1, N0, 0               # start in square 0
    LOAD N2, N0, 0x{T_P:X}
    ADDI N6, N0, {STEPS}
step:
    LOAD N3, N0, 0x{T_CONST:X}       # coin: dS = 1.0 * (ln 2 - 0), w = 1/2
    LOAD N4, N0, 0x{T_CONST + 4:X}
    METRO ACCEPT, N5, N3, N0, N4
    ADDI N7, N1, 4               # heads: m + 1
    BNE N5, N0, picked
    ADDI N7, N1, -4              # tails: m - 1
picked:
    ANDI N7, N7, 0x1C            # mod {K}
    LOAD N3, N7, 0x{T_P:X}          # P_new
    LOAD N4, N0, 0x{T_CONST + 8:X}       # beta
    METRO ACCEPT, N5, N2, N3, N4
    BEQ N5, N0, stay
    ADDI N1, N7, 0               # accepted: move
    ADDI N2, N3, 0
stay:
    LOAD N3, N1, 0x{T_HIST:X}
    ADDI N3, N3, 1
    STORE N3, N1, 0x{T_HIST:X}
    ADDI N6, N6, -1
    BNE N6, N0, step
    HALT N0
"""]
open('sw/metro_chain.axasm', 'w', encoding='utf-8').write("\n".join(asm))

tb = tb_from_gluon('metro_chain', 'metro_chain', f"""// AxISA v2.2 step 2 (see sw/metro_chain.axasm): a Metropolis chain at
// beta = {BETA} over {K} candidate links must sample Boltzmann's distribution.
// GENERATED by tools/gen_metro_test.py.
""", 400000)
preload = [f"        dut.dmem.mem[{T_CONST // 4}] = 32'h{bits(f32(LN2)):08X};",
           f"        dut.dmem.mem[{T_CONST // 4 + 1}] = 32'h{bits(1.0):08X};",
           f"        dut.dmem.mem[{T_CONST // 4 + 2}] = 32'h{bits(f32(BETA)):08X};"]
for base, c in zip(SQ, CANDS):
    for mi, u in enumerate([r32(c), r32(U2), r32(U3), r32(U4)]):
        for i in range(3):
            for j in range(3):
                w = (base + 72 * mi) // 4 + 2 * (3 * i + j)
                preload.append(f"        dut.dmem.mem[{w}] = 32'h{bits(u[i][j].real):08X};")
                preload.append(f"        dut.dmem.mem[{w + 1}] = 32'h{bits(u[i][j].imag):08X};")
tb = tb.replace("        reset = 0;\n", "        // the 8 candidate squares and the constants\n" + "\n".join(preload) + "\n        reset = 0;\n", 1)
lines = ["            check(tohost_value, 32'd0, \"tohost\");"]
for m in range(K):
    lines.append(f"            check(dut.dmem.mem[{(T_P + 4 * m) // 4}], 32'h{bits(P[m]):08X}, \"P of candidate {m} ({P[m]:.6f})\");")
total = []
for m in range(K):
    mean = STEPS * pi[m]
    lo, hi = max(0, int(mean - TOL[m])), int(math.ceil(mean + TOL[m]))
    lines.append(f"            in_range(dut.dmem.mem[{(T_HIST + 4 * m) // 4}], {lo}, {hi}, \"visits to {m} (Boltzmann {mean:.0f})\");")
lines.append(f"            check(dut.dmem.mem[{T_HIST // 4}] + dut.dmem.mem[{T_HIST // 4 + 1}] + dut.dmem.mem[{T_HIST // 4 + 2}] + dut.dmem.mem[{T_HIST // 4 + 3}] + "
             f"dut.dmem.mem[{T_HIST // 4 + 4}] + dut.dmem.mem[{T_HIST // 4 + 5}] + dut.dmem.mem[{T_HIST // 4 + 6}] + dut.dmem.mem[{T_HIST // 4 + 7}], {STEPS}, \"visits in total\");")
tb = set_checks(tb, lines, 'METRO-CHAIN')
tb = tb.replace("    initial begin\n        errors = 0;", """    task in_range(input [31:0] got, input [31:0] lo, input [31:0] hi, input [48*8-1:0] name);
        begin
            if (got < lo || got > hi) begin
                $display("FAIL: %0s got=%0d expected %0d..%0d", name, got, lo, hi);
                errors = errors + 1;
            end else
                $display("PASS: %0s = %0d (allowed %0d..%0d)", name, got, lo, hi);
        end
    endtask

    initial begin
        errors = 0;""", 1)
open('tb/tb_metro_chain.v', 'w', encoding='utf-8').write(tb)

print("weights:", " ".join(f"{w:.4g}" for w in w_res[:12]))
print("P_m:      ", " ".join(f"{p:.4f}" for p in P))
print("Boltzmann:", " ".join(f"{STEPS * x:6.0f}" for x in pi))
print("mean 400: ", " ".join(f"{x:6.0f}" for x in mean_hist))
print("tolerance:", " ".join(f"{t:6d}" for t in TOL))
