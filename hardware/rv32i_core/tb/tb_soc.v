// SoC-level testbench: one shared clk/reset drives BOTH cores in
// soc_top at once, proving they genuinely run concurrently rather
// than just being two separately-simulated instances. Waits for
// both_halted (not just either core alone - a slow core shouldn't
// let a fast one's premature halt end the run), then checks each
// core's own tohost value independently.
`timescale 1ns/1ps

`ifndef P_INSTR_HEX
`define P_INSTR_HEX "sw/hazard_test.hex"
`endif
`ifndef E_INSTR_HEX
`define E_INSTR_HEX "sw/test_basic.hex"
`endif

module tb_soc;
    reg clk;
    reg reset;
    wire p_halted, e_halted, both_halted;
    wire [31:0] p_tohost, e_tohost;

    integer expect_p_tohost, expect_e_tohost;
    integer max_cycles;
    integer cycle_count;
    integer trace_enabled;
    integer p_fail, e_fail;

    soc_top #(
        .INSTR_MEM_WORDS(1024),
        .P_INSTR_HEX(`P_INSTR_HEX),
        .E_INSTR_HEX(`E_INSTR_HEX),
        .DATA_MEM_BYTES(8192)
    ) dut (
        .clk(clk), .reset(reset),
        .p_halted(p_halted), .p_tohost(p_tohost),
        .e_halted(e_halted), .e_tohost(e_tohost),
        .both_halted(both_halted)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_soc.vcd");
        $dumpvars(0, tb_soc);

        if (!$value$plusargs("EXPECT_P_TOHOST=%d", expect_p_tohost)) expect_p_tohost = 119;
        if (!$value$plusargs("EXPECT_E_TOHOST=%d", expect_e_tohost)) expect_e_tohost = 110;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 300;
        trace_enabled = $test$plusargs("TRACE");

        clk = 0;
        reset = 1;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        if (trace_enabled) begin
            $display("cyc | P: pc       halted | E: pc       halted");
            $display("----+---------------------+---------------------");
        end

        while (!both_halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (trace_enabled) begin
                $display("%3d | P: %h  %b     | E: %h  %b",
                         cycle_count, dut.p_core.pc, p_halted,
                         dut.e_core.pc, e_halted);
            end
        end

        if (!both_halted) begin
            $display("FAIL: not both cores halted within %0d cycles (P halted=%b, E halted=%b)",
                      max_cycles, p_halted, e_halted);
        end else begin
            $display("Both cores halted after %0d cycles.", cycle_count);

            p_fail = 0;
            $display("P-core (pipelined): tohost=%0d (0x%h)", p_tohost, p_tohost);
            if (p_tohost === expect_p_tohost) begin
                $display("PASS: P-core tohost matches expected value %0d", expect_p_tohost);
            end else begin
                $display("FAIL: P-core tohost=%0d, expected=%0d", p_tohost, expect_p_tohost);
                p_fail = 1;
            end

            e_fail = 0;
            $display("E-core (single-cycle): tohost=%0d (0x%h)", e_tohost, e_tohost);
            if (e_tohost === expect_e_tohost) begin
                $display("PASS: E-core tohost matches expected value %0d", expect_e_tohost);
            end else begin
                $display("FAIL: E-core tohost=%0d, expected=%0d", e_tohost, expect_e_tohost);
                e_fail = 1;
            end

            if (!p_fail && !e_fail) $display("PASS: both cores matched their expected values");
        end

        $finish;
    end
endmodule
