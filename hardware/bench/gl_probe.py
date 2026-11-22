# Gate-level helpers for the energy testbench, found by the flip-flops' Q
# nets in the netlist (OpenLane keeps the RTL register names on them).
# Usage: python3 gl_probe.py <netlist.v> <tb module> <probe.v> <init.v>
#
# init.v - zeroes the register-bank flip-flops (R/G/B/N) during reset, by
#   forcing their D input from the end of the program load until reset is
#   released (an earlier release would let a reset-time clock edge load
#   the cell's real, possibly X, D again).
#   Why: on silicon a register powers up as some 0s and 1s and the
#   programs' own `ANDI x, x, 0` clears it. In gate-level simulation it
#   powers up as X, and the cell models are X-pessimistic: in CI run
#   45048114403 the clear left bits X in most color registers, so the
#   programs' results came out X in simulation only. The VCD starts
#   at reset release, after this, and programs A and B get the same
#   treatment, so it does not touch the energy of U psi.
# probe.v - the X spy: every cycle after reset, the PC and which of these
#   registers hold an X bit (used with PROBE=1).
import collections
import re
import sys

nl_path, tb, probe_out, init_out = sys.argv[1:5]
nl = open(nl_path).read()
SPY = [r'core\.pc', r'core\.pc_r', r'core\.tohost_r', r'core\.halted_r'] + \
      [rf'core\.{b}_bank\.regs\[\d\]' for b in 'rgbn']
INIT = [rf'core\.{b}_bank\.regs\[\d\]' for b in 'rgbn']


def split(net):
    """'\\a.b[2] [5]' or '\\a.b[2][5] ' -> (base, bit, verilog reference)"""
    m = re.match(r'^(\\\S+)\s*(?:\[(\d+)\])?$', net)
    if not m:
        return None
    name, bit = m.group(1), m.group(2)
    ref = name + ' ' + (f'[{bit}]' if bit is not None else '')
    if bit is None:
        mm = re.match(r'^(.*)\[(\d+)\]$', name)
        return (mm.group(1), int(mm.group(2)), ref) if mm else (name, 0, ref)
    return name, int(bit), ref


spy = collections.defaultdict(dict)
init = []                                  # (instance, cell type)
for cell, inst, pins in re.findall(r'(sky130_fd_sc_hd__\w+)\s+(\\\S+|\w+)\s*\((.*?)\);', nl, re.S):
    q = re.search(r'\.Q\(\s*([^()]*?)\s*\)', pins)
    if not q:
        continue
    s = split(q.group(1))
    if not s:
        continue
    base, bit, ref = s
    if any(re.fullmatch(r'\\' + w, base) for w in SPY):
        spy[base][bit] = ref
    if any(re.fullmatch(r'\\' + w, base) for w in INIT):
        init.append((inst + ' ' if inst.startswith('\\') else inst, cell))   # escaped names end in a space

# ---- init.v ----
L = ["`timescale 1ns/1ps", "module gl_init;", "    initial begin",
     f"        @(negedge {tb}.we);   // program loaded, reset still held"]
for inst, cell in init:
    L.append(f"        force {tb}.dut.{inst}.D = 1'b0;")
    if 'edfxtp' in cell:
        L.append(f"        force {tb}.dut.{inst}.DE = 1'b1;")
L.append(f"        @(negedge {tb}.reset);")
for inst, cell in init:
    L.append(f"        release {tb}.dut.{inst}.D;")
    if 'edfxtp' in cell:
        L.append(f"        release {tb}.dut.{inst}.DE;")
L += [f"        $display(\"GL-INIT: {len(init)} register flip-flops zeroed during reset\");",
      "    end", "endmodule"]
open(init_out, 'w').write("\n".join(L) + "\n")

# ---- probe.v ----
cat = {}
for base, bits in sorted(spy.items()):
    cat[base] = "{" + ", ".join(f"{tb}.dut.{bits[b]}" for b in sorted(bits, reverse=True)) + "}"
pc = cat.get(r'\core.pc', cat.get(r'\core.pc_r', "32'b0"))
L = ["`timescale 1ns/1ps", "module gl_probe;",
     f"    always @(posedge {tb}.clk) if (!{tb}.reset) begin",
     f"        #1 $display(\"PROBE c=%0d pc=%h X:" + "%s" * len(cat) + f"\", {tb}.cycle_count, {pc}, " +
     ", ".join(f'((^{c} === 1\'bx) ? " {b[1:]}" : "")' for b, c in cat.items()) + ");",
     "    end", "endmodule"]
open(probe_out, 'w').write("\n".join(L) + "\n")
print(f"gl_probe: init {len(init)} flip-flops ({collections.Counter(c for _, c in init)}); "
      f"spy {len(cat)} registers: " + ", ".join(f"{b[1:]}({len(spy[b])}b)" for b in cat))
