// FSQRT.S on the pipelined P-core (see sw/asm_fp_sqrt_pipe_race_test.py
// for the exact program and rationale). Mirrors tb_cpu_fp_div_pipe.v:
// bus_grant is driven procedurally, denied for a window covering both
// the older shared store's arrival in EX/MEM and FSQRT.S's entire
// computation - GRANT_DENY_CYCLES=0 exercises the plain cross-check
// (must match the E-core exactly), a nonzero value deliberately forces
// fp_sqrt's DONE cycle to land while EX/MEM is still occupied by that
// unrelated, older, stuck instruction - the exact race the
// fpu_sqrt_result_ready_r buffer exists to survive.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/fp_sqrt_pipe_race_test.hex"
`endif

module tb_cpu_pipelined_fp_sqrt;
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
        $dumpfile("tb_cpu_pipelined_fp_sqrt.vcd");
        $dumpvars(0, tb_cpu_pipelined_fp_sqrt);

        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 1068827891; // 0x3fb504f3 = sqrt(2.0)
        // fp_sqrt.v takes 26 cycles start-to-done (25 iterations +
        // settle) - far shorter than FDIV.S's ~51. 62 is deliberately
        // tight, not generous headroom, mirroring tb_cpu_fp_div_pipe.v's
        // own reasoning: measured 57 cycles for the correct (buffered)
        // capture on this exact race program vs 68 for a deliberately-
        // reintroduced naive version that drops the fsqrt_capture guard
        // (fpu_sqrt_result_ready_r wrongly clears without the value
        // ever actually landing in EX/MEM, so fp_sqrt restarts once) -
        // this bound is what turns that restart into an actual test
        // FAILURE instead of a quietly-passing extra ~11 wasted cycles.
        // Confirmed both ways before locking this in.
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 62;
        if (!$value$plusargs("GRANT_DENY_CYCLES=%d", grant_deny_cycles)) grant_deny_cycles = 50;

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
            $display("FAIL: core never halted within %0d cycles (infinite loop, ECALL never reached, or FSQRT result lost to the race)", max_cycles);
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
