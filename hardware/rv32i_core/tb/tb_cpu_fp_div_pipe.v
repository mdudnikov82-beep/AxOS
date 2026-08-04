// FDIV.S on the pipelined P-core (see sw/asm_fp_div_pipe_race_test.py for
// the exact program and rationale). Unlike tb_cpu_fp_div.v (E-core,
// bus_grant tied high - there's no pipeline for mem_stall/fpu_div_stall
// to ever overlap), THIS testbench drives bus_grant procedurally: denied
// for a long window covering both the older shared store's arrival in
// EX/MEM and FDIV.S's entire ~50-cycle computation, deliberately forcing
// fp_div's DONE cycle to land while EX/MEM is still occupied by that
// unrelated, older, stuck instruction. This is the exact race a design
// review caught before any RTL was written - the fpu_div_result_ready_r
// buffer in cpu_core_pipelined.v exists specifically to survive it.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/fp_div_pipe_race_test.hex"
`endif

module tb_cpu_fp_div_pipe;
    reg clk;
    reg reset;
    reg bus_grant;
    wire halted;
    wire [31:0] tohost_value;

    integer expect_tohost;
    integer max_cycles;
    integer cycle_count;
    integer grant_deny_cycles;

    cpu_core_pipelined #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX), .DATA_MEM_BYTES(8192)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value),
        .bus_grant(bus_grant), .bus_read_data(32'b0)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_cpu_fp_div_pipe.vcd");
        $dumpvars(0, tb_cpu_fp_div_pipe);

        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 1080033280; // 0x40600000 = 3.5
        // 115 is deliberately tight, not just generous headroom: measured
        // 107 cycles for the correct (buffered) capture on the adversarial
        // race program below vs. 118 for a deliberately-reintroduced naive
        // version that loses the completed division to mem_stall and
        // restarts once (see project_rv32i_fdiv_pcore_race_fix.md) - this
        // bound is what turns that restart into an actual test FAILURE
        // instead of a quietly-passing extra ~51 wasted cycles. Confirmed
        // both ways (fixed passes at 107, naive times out) before locking
        // this in - a real regression guard, not an assumed one. The
        // no-contention cross-check run (GRANT_DENY_CYCLES=0) finishes far
        // under this too, so one bound comfortably covers both invocations.
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 115;
        // fp_div.v takes ~51 cycles start-to-done (TOTAL_ITERS=49 + start
        // + settle). The shared store sits a handful of instructions
        // ahead of FDIV.S in the program, so denying grant for the first
        // 100 cycles comfortably spans BOTH its own arrival in EX/MEM and
        // FDIV.S's entire computation, guaranteeing the done-cycle/
        // mem_stall overlap without needing to hit an exact single cycle.
        if (!$value$plusargs("GRANT_DENY_CYCLES=%d", grant_deny_cycles)) grant_deny_cycles = 100;

        clk = 0;
        reset = 1;
        bus_grant = 0;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            bus_grant = (cycle_count >= grant_deny_cycles);
        end

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles (infinite loop, ECALL never reached, or FDIV result lost to the race)", max_cycles);
        end else begin
            $display("Halted after %0d cycles. tohost=%0d (0x%h)", cycle_count, tohost_value, tohost_value);
            if (tohost_value === expect_tohost) begin
                $display("PASS: tohost matches expected value %0d", expect_tohost);
            end else begin
                $display("FAIL: tohost=%0d, expected=%0d", tohost_value, expect_tohost);
            end
        end

        $finish;
    end
endmodule
