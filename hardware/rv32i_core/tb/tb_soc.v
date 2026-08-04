// SoC-level testbench: one shared clk/reset drives all 12 cores in
// soc_top at once (scaled up from the earlier 3P+3E version - just more
// core instantiations, shared_bus.v itself needed no changes), proving
// they all run concurrently rather than being separately-simulated
// instances. Each core runs its own INDEPENDENT private-memory-only
// program (no shared-bus traffic here - that cross-core-communication
// proof lives in tb_shared_soc.v instead). Waits for all_halted (not
// just any one core - a slow core shouldn't let a fast one's premature
// halt end the run), then checks each core's own tohost value
// independently.
`timescale 1ns/1ps

`ifndef P0_INSTR_HEX
`define P0_INSTR_HEX "sw/hazard_test.hex"
`endif
`ifndef P1_INSTR_HEX
`define P1_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P2_INSTR_HEX
`define P2_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P3_INSTR_HEX
`define P3_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P4_INSTR_HEX
`define P4_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P5_INSTR_HEX
`define P5_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E0_INSTR_HEX
`define E0_INSTR_HEX "sw/test_basic.hex"
`endif
`ifndef E1_INSTR_HEX
`define E1_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E2_INSTR_HEX
`define E2_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E3_INSTR_HEX
`define E3_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E4_INSTR_HEX
`define E4_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E5_INSTR_HEX
`define E5_INSTR_HEX "sw/test1.hex"
`endif

module tb_soc;
    reg clk;
    reg reset;
    wire p0_halted, p1_halted, p2_halted, p3_halted, p4_halted, p5_halted, e0_halted, e1_halted, e2_halted, e3_halted, e4_halted, e5_halted, all_halted;
    wire [31:0] p0_tohost, p1_tohost, p2_tohost, p3_tohost, p4_tohost, p5_tohost, e0_tohost, e1_tohost, e2_tohost, e3_tohost, e4_tohost, e5_tohost;

    integer expect_p0, expect_p1, expect_p2, expect_p3, expect_p4, expect_p5, expect_e0, expect_e1, expect_e2, expect_e3, expect_e4, expect_e5;
    integer max_cycles;
    integer cycle_count;
    integer any_fail;

    soc_top #(
        .INSTR_MEM_WORDS(1024),
        .P0_INSTR_HEX(`P0_INSTR_HEX), .P1_INSTR_HEX(`P1_INSTR_HEX), .P2_INSTR_HEX(`P2_INSTR_HEX), .P3_INSTR_HEX(`P3_INSTR_HEX), .P4_INSTR_HEX(`P4_INSTR_HEX), .P5_INSTR_HEX(`P5_INSTR_HEX), .E0_INSTR_HEX(`E0_INSTR_HEX), .E1_INSTR_HEX(`E1_INSTR_HEX), .E2_INSTR_HEX(`E2_INSTR_HEX), .E3_INSTR_HEX(`E3_INSTR_HEX), .E4_INSTR_HEX(`E4_INSTR_HEX), .E5_INSTR_HEX(`E5_INSTR_HEX),
        .DATA_MEM_BYTES(8192)
    ) dut (
        .clk(clk), .reset(reset),
        .p0_halted(p0_halted), .p0_tohost(p0_tohost),
        .p1_halted(p1_halted), .p1_tohost(p1_tohost),
        .p2_halted(p2_halted), .p2_tohost(p2_tohost),
        .p3_halted(p3_halted), .p3_tohost(p3_tohost),
        .p4_halted(p4_halted), .p4_tohost(p4_tohost),
        .p5_halted(p5_halted), .p5_tohost(p5_tohost),
        .e0_halted(e0_halted), .e0_tohost(e0_tohost),
        .e1_halted(e1_halted), .e1_tohost(e1_tohost),
        .e2_halted(e2_halted), .e2_tohost(e2_tohost),
        .e3_halted(e3_halted), .e3_tohost(e3_tohost),
        .e4_halted(e4_halted), .e4_tohost(e4_tohost),
        .e5_halted(e5_halted), .e5_tohost(e5_tohost),
        .all_halted(all_halted)
    );

    always #5 clk = ~clk;

    task check_core(input [31:0] got, input [31:0] expected, input [24*8-1:0] name);
        begin
            $display("%0s: tohost=%0d (0x%h)", name, got, got);
            if (got === expected) begin
                $display("PASS: %0s matches expected value %0d", name, expected);
            end else begin
                $display("FAIL: %0s tohost=%0d, expected=%0d", name, got, expected);
                any_fail = 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_soc.vcd");
        $dumpvars(0, tb_soc);

        if (!$value$plusargs("EXPECT_P0_TOHOST=%d", expect_p0)) expect_p0 = 119;
        if (!$value$plusargs("EXPECT_P1_TOHOST=%d", expect_p1)) expect_p1 = 42;
        if (!$value$plusargs("EXPECT_P2_TOHOST=%d", expect_p2)) expect_p2 = 42;
        if (!$value$plusargs("EXPECT_P3_TOHOST=%d", expect_p3)) expect_p3 = 42;
        if (!$value$plusargs("EXPECT_P4_TOHOST=%d", expect_p4)) expect_p4 = 42;
        if (!$value$plusargs("EXPECT_P5_TOHOST=%d", expect_p5)) expect_p5 = 42;
        if (!$value$plusargs("EXPECT_E0_TOHOST=%d", expect_e0)) expect_e0 = 110;
        if (!$value$plusargs("EXPECT_E1_TOHOST=%d", expect_e1)) expect_e1 = 42;
        if (!$value$plusargs("EXPECT_E2_TOHOST=%d", expect_e2)) expect_e2 = 42;
        if (!$value$plusargs("EXPECT_E3_TOHOST=%d", expect_e3)) expect_e3 = 42;
        if (!$value$plusargs("EXPECT_E4_TOHOST=%d", expect_e4)) expect_e4 = 42;
        if (!$value$plusargs("EXPECT_E5_TOHOST=%d", expect_e5)) expect_e5 = 42;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 300;

        clk = 0;
        reset = 1;
        cycle_count = 0;
        any_fail = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        while (!all_halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!all_halted) begin
            $display("FAIL: not all 12 cores halted within %0d cycles (p0=%b p1=%b p2=%b p3=%b p4=%b p5=%b e0=%b e1=%b e2=%b e3=%b e4=%b e5=%b)",
                      max_cycles, p0_halted, p1_halted, p2_halted, p3_halted, p4_halted, p5_halted, e0_halted, e1_halted, e2_halted, e3_halted, e4_halted, e5_halted);
        end else begin
            $display("All 12 cores halted after %0d cycles.", cycle_count);
            check_core(p0_tohost, expect_p0, "p0-core (pipelined)");
            check_core(p1_tohost, expect_p1, "p1-core (pipelined)");
            check_core(p2_tohost, expect_p2, "p2-core (pipelined)");
            check_core(p3_tohost, expect_p3, "p3-core (pipelined)");
            check_core(p4_tohost, expect_p4, "p4-core (pipelined)");
            check_core(p5_tohost, expect_p5, "p5-core (pipelined)");
            check_core(e0_tohost, expect_e0, "e0-core (single-cycle)");
            check_core(e1_tohost, expect_e1, "e1-core (single-cycle)");
            check_core(e2_tohost, expect_e2, "e2-core (single-cycle)");
            check_core(e3_tohost, expect_e3, "e3-core (single-cycle)");
            check_core(e4_tohost, expect_e4, "e4-core (single-cycle)");
            check_core(e5_tohost, expect_e5, "e5-core (single-cycle)");
            if (!any_fail) $display("PASS: all 12 cores matched their expected values");
        end

        $finish;
    end
endmodule
