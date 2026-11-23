# Where the clock goes: OpenSTA's worst setup paths (max.rpt), grouped by
# start/end REGISTER - the final netlist names the anonymous flip-flops by
# their Q nets. Also prints the single worst path with those names, so
# the critical path can be read without downloading the run.
# Usage: python3 worst_paths.py <final/nl/*.nl.v> <max.rpt> [paths to list]
import collections
import re
import sys

nl = open(sys.argv[1]).read()
txt = open(sys.argv[2]).read()
n_show = int(sys.argv[3]) if len(sys.argv) > 3 else 25

q = {}                                       # instance -> its Q net (register name)
for m in re.finditer(r'sky130_fd_sc_hd__\w+\s+(\\\S+|\w+)\s*\((.*?)\);', nl, re.S):
    mm = re.search(r'\.Q\(\s*([^()]*?)\s*\)', m.group(2))
    if mm:
        q[m.group(1)] = mm.group(1).strip()


def reg(inst, bits=False):
    name = q.get(inst, inst).lstrip('\\')
    return name if bits else re.sub(r'\s*\[\d+\]\s*$', '[]', name)   # drop the bit index only


blocks = re.split(r'(?m)^Startpoint: ', txt)[1:]
paths = []
for b in blocks:
    sp = b.split()[0]
    ep = re.search(r'^Endpoint: (\S+)', b, re.M)
    sl = re.search(r'^\s*([-\d.]+)\s+slack', b, re.M)
    if ep and sl:
        paths.append((sp, ep.group(1), float(sl.group(1)), b))
if not paths:
    sys.exit("no paths in " + sys.argv[2])

sp, ep, sl, b = paths[0]
print(f"WORST slack {sl:.2f} ns: {reg(sp, True)} -> {reg(ep, True)}")
print(f"{len(paths)} paths, slack {paths[0][2]:.2f} .. {paths[-1][2]:.2f} ns")
print("\nby register (paths, worst slack):")
grp = collections.OrderedDict()
for sp, ep, sl, _ in paths:
    k = (reg(sp), reg(ep))
    n, w = grp.get(k, (0, sl))
    grp[k] = (n + 1, min(w, sl))
for (a, e), (n, w) in sorted(grp.items(), key=lambda kv: kv[1][1])[:n_show]:
    print(f"{n:5d} {w:8.2f}  {a:40s} -> {e}")

print("\nworst path, cell by cell (instance -> register name where it is a flip-flop):")
for line in b.splitlines():
    if re.search(r'slack|data arrival|required|\(net\)', line) or '/' in line:
        line = re.sub(r'(\\\S+|_\d+_)/', lambda m: (reg(m.group(1), True) + '/') if m.group(1) in q else m.group(0), line)
        print(line.rstrip())
