# Writes a gate-level "X spy" for the energy testbench: every cycle after
# reset it prints the PC and which architectural registers hold an X bit,
# so the first instruction that makes a value unknown can be read off the
# log. Register bits are found by their flip-flop Q nets in the netlist
# (OpenLane keeps the RTL register names on them).
# Usage: python3 gl_probe.py <netlist.v> <tb module> <out.v>
import collections
import re
import sys

nl = open(sys.argv[1]).read()
tb, out = sys.argv[2], sys.argv[3]
WANT = [r'core\.pc', r'core\.tohost_r', r'core\.halted_r'] + \
       [rf'core\.{b}_bank\.regs\[\d\]' for b in 'rgbn']

groups = collections.defaultdict(dict)   # base name -> {bit: verilog reference}
for net in re.findall(r'\.Q\(\s*([^()]*?)\s*\)', nl):
    m = re.match(r'^(\\\S+)\s*(?:\[(\d+)\])?$', net)
    if not m:
        continue
    name, bit = m.group(1), m.group(2)
    if bit is None:                       # the index may be part of the escaped name
        mm = re.match(r'^(.*)\[(\d+)\]$', name)
        base, bit = (mm.group(1), int(mm.group(2))) if mm else (name, 0)
    else:
        base, bit = name, int(bit)
    ref = name + ' ' + (f'[{m.group(2)}]' if m.group(2) is not None else '')
    if any(re.fullmatch(r'\\' + w, base) for w in WANT):
        groups[base][bit] = ref

L = ["`timescale 1ns/1ps", "module gl_probe;"]
cat = {}
for base, bits in sorted(groups.items()):
    refs = [f"{tb}.dut.{bits[b]}" for b in sorted(bits, reverse=True)]
    cat[base] = "{" + ", ".join(refs) + "}"
names = [b[1:] for b in cat]
pc = cat.get(r'\core.pc', "32'b0")
L.append(f"    always @(posedge {tb}.clk) if (!{tb}.reset) begin")
L.append(f"        #1 $display(\"PROBE c=%0d pc=%h X:" + "%s" * len(cat) + f"\", {tb}.cycle_count, {pc}, " +
         ", ".join(f'((^{c} === 1\'bx) ? " {b[1:]}" : "")' for b, c in cat.items()) + ");")
L.append("    end")
L.append("endmodule")
open(out, 'w').write("\n".join(L) + "\n")
print(f"gl_probe: {len(cat)} registers: " + ", ".join(f"{n}({len(groups[chr(92) + n])}b)" for n in names))
