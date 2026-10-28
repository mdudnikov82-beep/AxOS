#!/usr/bin/env python3
# AxISA simulation suite - the single source of truth for which tests
# exist, run both locally (run_sim.bat is now a thin wrapper around this)
# and in CI (.github/workflows/axisa-sim.yml, ubuntu-latest + apt iverilog).
# It used to live only in run_sim.bat, which no CI job ran - that is how
# QMEASURE taking opcode 10000 silently broke trap_illegal for weeks.
#
# Usage:
#   python run_sim.py            all fast tests (everything except the mesh)
#   python run_sim.py --mesh     ONLY a generated 1023-core 8x8x16 mesh (several minutes)
#   python run_sim.py --all      fast tests, then the mesh
#   python run_sim.py qmeasure   only tests whose name contains "qmeasure"
#
# Finds iverilog/vvp on PATH, falling back to C:\iverilog\bin (the local
# Windows install run_sim.bat always used).

import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

CORE = [
    "rtl/alu.v", "rtl/regbank.v", "rtl/instr_mem.v", "rtl/data_mem.v",
    "rtl/control_unit.v", "rtl/fp_addsub.v", "rtl/fp_mul.v", "rtl/fp_sqrt.v",
    "rtl/fp_div.v", "rtl/lfsr.v", "rtl/cpu_core.v", "rtl/mmu.v",
]
NOC = ["rtl/shared_mem_backing.v", "rtl/router.v",
       "rtl/noc_core_adapter.v", "rtl/noc_mem_adapter.v"]


def T(name, tb, expect, ok, asm=(), src=CORE, plusargs=(), defines=(), cwd="."):
    return dict(name=name, tb=tb, expect=expect, ok=ok, asm=asm, src=src,
                plusargs=plusargs, defines=defines, cwd=cwd)


def axasm(stem):
    return ["sw/axasm.py", f"sw/{stem}.axasm", f"sw/{stem}.hex"]


FAST_TESTS = [
    T("milestone1", "tb/tb_cpu.v", "ALL AXISA MILESTONE-1 TESTS PASSED",
      "tohost=200, all 4 register banks verified independently",
      asm=[["sw/asm_test1.py", "sw/test1.hex"]]),
    T("milestone2", "tb/tb_cpu2.v", "ALL AXISA MILESTONE-2 TESTS PASSED",
      "tohost=332 - chained BARYON+MESON+GLUON+LOAD/STORE+JAL",
      asm=[["sw/asm_test2.py", "sw/test2.hex"]]),
    T("collider", "tb/tb_run.v", "PASS: tohost matches expected value",
      "tohost=28 - backward-branch loop, BARYON collisions, STORE/LOAD",
      asm=[["sw/axasm.py", "sw/demo_collider.axasm", "sw/collider.hex"]],
      plusargs=["+EXPECT_TOHOST=28"], defines=['INSTR_HEX="sw/collider.hex"']),
    T("noc_link", "tb/tb_noc_link.v", "ALL AXISA NOC LINK TESTS PASSED",
      "router + adapters bus protocol", src=NOC),
    T("noc_single", "tb/tb_noc_single.v", "ALL AXISA NOC SINGLE-CORE TESTS PASSED",
      "tohost=99 - STORE then LOAD round trip through the NoC",
      asm=[axasm("noc_single_test")], src=CORE + NOC),
    T("uart_shell", "tb/tb_uart_shell.v", "ALL AXISA UART SHELL TESTS PASSED",
      '"hi" recognized - prompt+echo+"OK" byte-exact', asm=[axasm("mini_shell")]),
    T("uart_shell_nomatch", "tb/tb_uart_shell_nomatch.v",
      "ALL AXISA UART SHELL NOMATCH TESTS PASSED",
      '"xy" correctly NOT recognized', asm=[axasm("mini_shell")]),
    # Run from tinytapeout/ so the wrapper's INSTR_INIT_FILE("../sw/...")
    # resolves the same way it does under OpenLane (see run_sim.bat history).
    T("tt_um", "../tb/tb_tt_um_axisa_core.v", "ALL AXISA TT_UM WRAPPER TESTS PASSED",
      "3 round trips through the 24-pin tt_um interface",
      asm=[axasm("mini_shell_loop")],
      src=["../" + s for s in CORE] + ["tt_um_axisa_core.v"], cwd="tinytapeout"),
    T("gluon", "tb/tb_gluon.v", "ALL AXISA GLUON TESTS PASSED",
      "v2.0: all 8 gluons, both color round trips, traceless L3/L8, 2 color-rule traps",
      asm=[axasm("gluon_test")]),
    T("hadron_combine", "tb/tb_hadron_combine.v", "ALL AXISA HADRON-COMBINE TESTS PASSED",
      "v2.0: BARYON MAJ/EPS, ANTI + MESON SINGLET, 4 illegal combines",
      asm=[axasm("hadron_combine_test")]),
    T("hadrons", "tb/tb_hadrons.v", "ALL AXISA HADRONS TESTS PASSED",
      "v2.0: QN of 8 baryons (p, n, Delta++, Omega-, Lambda...) + 6 mesons, 7 illegal",
      asm=[axasm("hadrons_test")]),
    T("string", "tb/tb_string.v", "ALL AXISA STRING TESTS PASSED",
      "v2.0: STRING results + per-instruction cycle counts, string breaking, illegal N",
      asm=[axasm("string_test")]),
    T("trap_irq_string_0", "tb/tb_trap_irq_string.v", "ALL AXISA TRAP-IRQ-STRING TESTS PASSED",
      "IRQ on STRING's first cycle deferred until it commits, EPC=0x28",
      asm=[axasm("trap_irq_string")], plusargs=["+IRQ_PHASE=0"]),
    T("trap_irq_string_1", "tb/tb_trap_irq_string.v", "ALL AXISA TRAP-IRQ-STRING TESTS PASSED",
      "IRQ on STRING's mid-stall deferred until it commits, EPC=0x28",
      asm=[axasm("trap_irq_string")], plusargs=["+IRQ_PHASE=1"]),
    T("trap_irq_string_2", "tb/tb_trap_irq_string.v", "ALL AXISA TRAP-IRQ-STRING TESTS PASSED",
      "IRQ on STRING's terminal cycle deferred until it commits, EPC=0x28",
      asm=[axasm("trap_irq_string")], plusargs=["+IRQ_PHASE=2"]),
    T("su3mul", "tb/tb_su3mul.v", "ALL AXISA SU3MUL TESTS PASSED",
      "v2.0: bit-exact U*psi for real SU(3) matrices, chained + in place, 4 traps, 79 cycles",
      asm=[axasm("su3mul_test")]),
    T("trap_irq_su3mul_0", "tb/tb_trap_irq_su3mul.v", "ALL AXISA TRAP-IRQ-SU3MUL TESTS PASSED",
      "IRQ on SU3MUL's first cycle deferred until it finishes, EPC=0x28",
      asm=[axasm("trap_irq_su3mul")], plusargs=["+IRQ_PHASE=0"]),
    T("trap_irq_su3mul_1", "tb/tb_trap_irq_su3mul.v", "ALL AXISA TRAP-IRQ-SU3MUL TESTS PASSED",
      "IRQ on SU3MUL's mid-sequence deferred until it finishes, EPC=0x28",
      asm=[axasm("trap_irq_su3mul")], plusargs=["+IRQ_PHASE=1"]),
    T("trap_irq_su3mul_2", "tb/tb_trap_irq_su3mul.v", "ALL AXISA TRAP-IRQ-SU3MUL TESTS PASSED",
      "IRQ on SU3MUL's terminal write-back cycle deferred until it finishes, EPC=0x28",
      asm=[axasm("trap_irq_su3mul")], plusargs=["+IRQ_PHASE=2"]),
    T("mte", "tb/tb_mte.v", "ALL AXISA MTE TESTS PASSED",
      "v2.1: memory tagging - overflow + use-after-free caught, LDG, UART untagged, 8 traps",
      asm=[axasm("mte_test")]),
    T("mte_mmu", "tb/tb_mte_mmu.v", "ALL AXISA MTE-MMU TESTS PASSED",
      "v2.1: tag check uses the translated PHYSICAL granule in user mode",
      asm=[axasm("mte_mmu_test")]),
    T("trap_illegal", "tb/tb_trap_illegal.v", "ALL AXISA TRAP-ILLEGAL TESTS PASSED",
      "tohost=88, CAUSE/EPC captured, R/G/B/N survived", asm=[axasm("trap_illegal")]),
    T("trap_syscall", "tb/tb_trap_syscall.v", "ALL AXISA TRAP-SYSCALL TESTS PASSED",
      "tohost=110, SYSCALL cause=1, PRIV_VIOLATION cause=3", asm=[axasm("trap_syscall")]),
    T("trap_irq", "tb/tb_trap_irq.v", "ALL AXISA TRAP-IRQ TESTS PASSED",
      "tohost=42, IRQ preempted a spin loop", asm=[axasm("trap_irq")]),
    T("trap_irq_squash", "tb/tb_trap_irq_squash.v", "ALL AXISA TRAP-IRQ-SQUASH TESTS PASSED",
      "IRQ on a post-branch squash cycle - EPC=0x28", asm=[axasm("trap_irq")]),
    T("trap_irq_stall", "tb/tb_trap_irq_stall.v", "ALL AXISA TRAP-IRQ-STALL TESTS PASSED",
      "IRQ mid-mem_stall deferred until the STORE completed", asm=[axasm("trap_irq_stall")]),
    T("qcnot", "tb/tb_qcnot.v", "ALL AXISA QCNOT TESTS PASSED",
      "amp1<->amp3 swap byte-exact", asm=[axasm("qcnot_test")]),
    T("qhad", "tb/tb_qhad.v", "ALL AXISA QHAD TESTS PASSED",
      "Hadamard on |00>: both amplitudes = 1/sqrt(2)", asm=[axasm("qhad_test")]),
    T("trap_irq_qhad", "tb/tb_trap_irq_qhad.v", "ALL AXISA TRAP-IRQ-QHAD TESTS PASSED",
      "IRQ on QHAD's terminal cycle deferred, EPC=0x28", asm=[axasm("trap_irq_qhad")]),
    T("qmeasure_p1", "tb/tb_qmeasure_p1.v", "ALL AXISA QMEASURE P1 TESTS PASSED",
      "P0=1.0: outcome forced 0", asm=[axasm("qmeasure_test_p1")]),
    T("qmeasure_p0", "tb/tb_qmeasure_p0.v", "ALL AXISA QMEASURE P0 TESTS PASSED",
      "P0=0.0: outcome forced 1", asm=[axasm("qmeasure_test_p0")]),
    T("qmeasure_5050", "tb/tb_qmeasure_5050.v", "ALL AXISA QMEASURE 5050 TESTS PASSED",
      "real 50/50 branch: invariants hold", asm=[axasm("qmeasure_test_5050")]),
    T("trap_irq_qmeasure", "tb/tb_trap_irq_qmeasure.v",
      "ALL AXISA TRAP-IRQ-QMEASURE TESTS PASSED",
      "IRQ on QMEASURE's terminal cycle deferred, EPC=0x28", asm=[axasm("trap_irq_qmeasure")]),
    T("mmu", "tb/tb_mmu.v", "ALL AXISA MMU TESTS PASSED",
      "tohost=342, translated STORE/LOAD + recoverable page fault", asm=[axasm("mmu_test")]),
]

# CI-sized mesh, generated fresh into a temp dir. The committed
# rtl/soc_top.v is the 22x11x19 (4597-core) scale record, which no longer
# fits a GitHub runner's RAM since the core grew (FPU, QHAD/QCNOT,
# fp_div/fp_sqrt/QMEASURE) - the runner gets shut down mid-compile. Use
# .github/workflows/axisa-mesh.yml for big-mesh experiments instead.
MESH_DIMS = ("8", "8", "16")  # 1023 cores + 1 memory node
MESH_DIR = os.path.join(tempfile.gettempdir(), "axisa_mesh_%sx%sx%s" % MESH_DIMS)
MESH_SOC = os.path.join(MESH_DIR, "soc_top.v")
MESH_TB = os.path.join(MESH_DIR, "tb_soc.v")

MESH_TESTS = [
    T("mesh_1023", MESH_TB, "PASS: cross-core communication verified",
      "c0=127, c1=77, c2-c1022=200 - 1023 cores, real X+Y+Z routing",
      asm=[axasm("shared_producer"), axasm("shared_consumer"),
           ["sw/asm_test1.py", "sw/test1.hex"],
           ["tools/gen_soc_top.py", *MESH_DIMS, MESH_SOC],
           ["tools/gen_tb_soc.py", *MESH_DIMS, MESH_TB]],
      src=CORE + NOC + [MESH_SOC]),
]


def find_tool(name):
    p = shutil.which(name)
    if p:
        return p
    win = os.path.join(r"C:\iverilog\bin", name + ".exe")
    if os.path.exists(win):
        return win
    sys.exit(f"ERROR: {name} not found on PATH or in C:\\iverilog\\bin")


def check_illegal_opcode_is_free():
    # trap_illegal.axasm needs a genuinely reserved opcode, but every new
    # instruction claims the lowest free one - exactly the one this test
    # tends to use (happened with QCNOT, then QMEASURE). Fail loudly here
    # instead of with an opaque "core never halted".
    cu = open(os.path.join(HERE, "rtl/control_unit.v"), encoding="utf-8").read()
    used = {int(b, 2): n for n, b in re.findall(r"localparam\s+(OP_\w+)\s*=\s*5'b([01]{5})", cu)}
    asm = open(os.path.join(HERE, "sw/trap_illegal.axasm"), encoding="utf-8").read()
    words = re.findall(r"^\s*\.word\s+(0x[0-9a-fA-F]+)", asm, re.M)
    if len(used) < 10 or len(words) != 1:
        sys.exit("ERROR: opcode guard could not parse control_unit.v / trap_illegal.axasm")
    op = int(words[0], 16) >> 27
    if op in used:
        free = sorted(set(range(32)) - set(used))
        sys.exit(f"ERROR: trap_illegal.axasm's .word {words[0]} has opcode {op:05b}, "
                 f"which is now {used[op]} in control_unit.v - pick a free one "
                 f"(free: {', '.join(f'{f:05b}' for f in free)})")
    print(f"opcode guard: trap_illegal uses {op:05b}, not claimed by any OP_* - OK")


def run_test(t, iverilog, vvp, outdir):
    cwd = os.path.join(HERE, t["cwd"])
    for a in t["asm"]:
        r = subprocess.run([sys.executable, *a], cwd=HERE, capture_output=True, text=True)
        if r.returncode != 0:
            return False, f"assembler failed: {' '.join(a)}\n{r.stdout}{r.stderr}"
    out = os.path.join(outdir, f"out_{t['name']}.vvp")
    cmd = [iverilog, "-o", out, *[f"-D{d}" for d in t["defines"]], *t["src"], t["tb"]]
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        return False, f"iverilog failed:\n{r.stdout}{r.stderr}"
    r = subprocess.run([vvp, out, *t["plusargs"]], cwd=cwd, capture_output=True, text=True)
    if t["expect"] not in r.stdout:
        return False, r.stdout + r.stderr
    return True, ""


def main():
    args = sys.argv[1:]
    if "--mesh" in args:
        tests = MESH_TESTS
    elif "--all" in args:
        tests = FAST_TESTS + MESH_TESTS
    else:
        tests = FAST_TESTS
    filters = [a for a in args if not a.startswith("--")]
    if filters:
        tests = [t for t in tests if any(f in t["name"] for f in filters)]
        if not tests:
            sys.exit(f"ERROR: no test matches {filters}")

    iverilog, vvp = find_tool("iverilog"), find_tool("vvp")
    check_illegal_opcode_is_free()
    if any(t in MESH_TESTS for t in tests):
        os.makedirs(MESH_DIR, exist_ok=True)
    outdir = HERE  # out_*.vvp are gitignored, same place run_sim.bat put them

    failed = []
    for t in tests:
        print(f"===== {t['name']} =====", flush=True)
        ok, log = run_test(t, iverilog, vvp, outdir)
        if ok:
            print(f"  OK ({t['ok']})", flush=True)
        else:
            print(f"  FAILED: {t['name']}\n{log}", flush=True)
            failed.append(t["name"])

    print()
    if failed:
        print(f"===== {len(failed)} SIMULATION(S) FAILED: {', '.join(failed)} =====")
        sys.exit(1)
    print(f"===== ALL {len(tests)} SIMULATIONS PASSED =====")


if __name__ == "__main__":
    main()
