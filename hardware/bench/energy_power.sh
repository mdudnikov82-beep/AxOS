#!/usr/bin/env bash
# Energy of one U psi on a synthesized core (CI only: needs the OpenLane run,
# the sky130 PDK under ~/.volare, iverilog and nix). Usage, from the repo root:
#   bash hardware/bench/energy_power.sh axisa hardware/axisa_core/asic
#   bash hardware/bench/energy_power.sh rv32i hardware/rv32i_core/asic
# Runs energy programs A (setup) and B (setup + U psi) on the gate-level
# netlist, measures each run's average power with OpenROAD report_power and
# its own VCD (typical corner, 100 ns clock), and prints E = P x run time
# for both and E(B) - E(A), the energy of U psi itself.
set -euo pipefail
CORE=$1
ASIC=$(cd "$2" && pwd)
BENCH=$(cd "$(dirname "$0")" && pwd)
python3 "$BENCH/gen_bench_energy.py" > /dev/null
E="$BENCH/energy"

RUN_DIR=$(ls -td "$ASIC"/runs/RUN_* | head -1)
NETLIST=$(find "$RUN_DIR/final/nl" -name '*.v' | head -1)
SDC=$(find "$RUN_DIR/final/sdc" -name '*.sdc' | head -1)
SPEF=$(find "$RUN_DIR/final/spef" -name '*.spef' | head -1)
LIB=$(find "$HOME/.volare" -iname 'sky130_fd_sc_hd__tt_025C_1v80.lib' | head -1)
TECH_LEF=$(find "$HOME/.volare" -iname 'sky130_fd_sc_hd__nom.tlef' | head -1)
CELL_LEF=$(find "$HOME/.volare" -iname 'sky130_fd_sc_hd.lef' | head -1)
PRIMITIVES=$(find "$HOME/.volare" -iname 'primitives.v' -path '*sky130_fd_sc_hd*' | head -1)
CELLS=$(find "$HOME/.volare" -iname 'sky130_fd_sc_hd.v' | head -1)
for v in NETLIST SDC SPEF LIB TECH_LEF CELL_LEF PRIMITIVES CELLS; do
    echo "$v=${!v}"
    [ -n "${!v}" ] || { echo "missing $v"; exit 1; }
done

cd "$E"
iverilog -o "gl_$CORE.vvp" -g2012 -DFUNCTIONAL -DSIM -DGL -DUNIT_DELAY="#1" \
    "$PRIMITIVES" "$CELLS" "$NETLIST" "tb_energy_$CORE.v"

declare -A P CYC
for PROG in A B; do
    EXP=$(grep "^${CORE}_${PROG} " expect.txt | cut -d' ' -f2)
    vvp "gl_$CORE.vvp" +HEX="${CORE}_${PROG}.hex" +EXPECT="$EXP" +VCD="${CORE}_${PROG}.vcd" | tee "sim_${CORE}_${PROG}.log"
    grep -q "ENERGY-RUN PASS" "sim_${CORE}_${PROG}.log" || { echo "gate-level run $PROG failed"; exit 1; }
    CYC[$PROG]=$(grep -o 'cycles=[0-9]*' "sim_${CORE}_${PROG}.log" | cut -d= -f2)
    cat > "power_${PROG}.tcl" <<TCL
read_lef $TECH_LEF
read_lef $CELL_LEF
read_liberty $LIB
read_verilog $NETLIST
link_design cpu_core_top
read_sdc $SDC
read_spef $SPEF
read_vcd -scope tb_energy_$CORE/dut ${CORE}_${PROG}.vcd
report_power
TCL
    nix run --accept-flake-config github:efabless/openlane2#openroad -- \
        -exit -no_init "power_${PROG}.tcl" 2>&1 | tee "power_${CORE}_${PROG}.log"
    # Group  Internal  Switching  Leakage  Total  -> the Total row's 4th number (watts)
    P[$PROG]=$(grep -E '^Total ' "power_${CORE}_${PROG}.log" | head -1 | awk '{print $5}')
done

python3 - "$CORE" "${P[A]}" "${CYC[A]}" "${P[B]}" "${CYC[B]}" <<'PY'
import sys
core, pa, ca, pb, cb = sys.argv[1], float(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5])
T = 100e-9
ea, eb = pa * ca * T, pb * cb * T
print(f"ENERGY {core}: A {ca} cycles {pa * 1e3:.3f} mW {ea * 1e9:.3f} nJ | "
      f"B {cb} cycles {pb * 1e3:.3f} mW {eb * 1e9:.3f} nJ | "
      f"U psi = B - A: {cb - ca} cycles, {(eb - ea) * 1e9:.3f} nJ")
PY
