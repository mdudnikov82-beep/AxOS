// SoC-level testbench: one shared clk/reset drives all 24 cores in
// soc_top at once (scaled up from the earlier 6P+6E NoC mesh version - just more
// core instantiations; soc_top.v itself is a bigger mesh, but this
// testbench only ever sees the same external port/param shape), proving
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
`ifndef P6_INSTR_HEX
`define P6_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P7_INSTR_HEX
`define P7_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P8_INSTR_HEX
`define P8_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P9_INSTR_HEX
`define P9_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P10_INSTR_HEX
`define P10_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P11_INSTR_HEX
`define P11_INSTR_HEX "sw/test1.hex"
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
`ifndef E6_INSTR_HEX
`define E6_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E7_INSTR_HEX
`define E7_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E8_INSTR_HEX
`define E8_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E9_INSTR_HEX
`define E9_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E10_INSTR_HEX
`define E10_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E11_INSTR_HEX
`define E11_INSTR_HEX "sw/test1.hex"
`endif

module tb_soc;
    reg clk;
    reg reset;
    wire p0_halted, p1_halted, p2_halted, p3_halted, p4_halted, p5_halted, p6_halted, p7_halted, p8_halted, p9_halted, p10_halted, p11_halted, e0_halted, e1_halted, e2_halted, e3_halted, e4_halted, e5_halted, e6_halted, e7_halted, e8_halted, e9_halted, e10_halted, e11_halted, all_halted;
    wire [31:0] p0_tohost, p1_tohost, p2_tohost, p3_tohost, p4_tohost, p5_tohost, p6_tohost, p7_tohost, p8_tohost, p9_tohost, p10_tohost, p11_tohost, e0_tohost, e1_tohost, e2_tohost, e3_tohost, e4_tohost, e5_tohost, e6_tohost, e7_tohost, e8_tohost, e9_tohost, e10_tohost, e11_tohost;

    integer expect_p0, expect_p1, expect_p2, expect_p3, expect_p4, expect_p5, expect_p6, expect_p7, expect_p8, expect_p9, expect_p10, expect_p11, expect_e0, expect_e1, expect_e2, expect_e3, expect_e4, expect_e5, expect_e6, expect_e7, expect_e8, expect_e9, expect_e10, expect_e11;
    integer max_cycles;
    integer cycle_count;
    integer any_fail;

    soc_top #(
        .INSTR_MEM_WORDS(1024),
        .P0_INSTR_HEX(`P0_INSTR_HEX), .P1_INSTR_HEX(`P1_INSTR_HEX), .P2_INSTR_HEX(`P2_INSTR_HEX), .P3_INSTR_HEX(`P3_INSTR_HEX), .P4_INSTR_HEX(`P4_INSTR_HEX), .P5_INSTR_HEX(`P5_INSTR_HEX), .P6_INSTR_HEX(`P6_INSTR_HEX), .P7_INSTR_HEX(`P7_INSTR_HEX), .P8_INSTR_HEX(`P8_INSTR_HEX), .P9_INSTR_HEX(`P9_INSTR_HEX), .P10_INSTR_HEX(`P10_INSTR_HEX), .P11_INSTR_HEX(`P11_INSTR_HEX), .E0_INSTR_HEX(`E0_INSTR_HEX), .E1_INSTR_HEX(`E1_INSTR_HEX), .E2_INSTR_HEX(`E2_INSTR_HEX), .E3_INSTR_HEX(`E3_INSTR_HEX), .E4_INSTR_HEX(`E4_INSTR_HEX), .E5_INSTR_HEX(`E5_INSTR_HEX), .E6_INSTR_HEX(`E6_INSTR_HEX), .E7_INSTR_HEX(`E7_INSTR_HEX), .E8_INSTR_HEX(`E8_INSTR_HEX), .E9_INSTR_HEX(`E9_INSTR_HEX), .E10_INSTR_HEX(`E10_INSTR_HEX), .E11_INSTR_HEX(`E11_INSTR_HEX),
        .DATA_MEM_BYTES(8192)
    ) dut (
        .clk(clk), .reset(reset),
        .p0_halted(p0_halted), .p0_tohost(p0_tohost),
        .p1_halted(p1_halted), .p1_tohost(p1_tohost),
        .p2_halted(p2_halted), .p2_tohost(p2_tohost),
        .p3_halted(p3_halted), .p3_tohost(p3_tohost),
        .p4_halted(p4_halted), .p4_tohost(p4_tohost),
        .p5_halted(p5_halted), .p5_tohost(p5_tohost),
        .p6_halted(p6_halted), .p6_tohost(p6_tohost),
        .p7_halted(p7_halted), .p7_tohost(p7_tohost),
        .p8_halted(p8_halted), .p8_tohost(p8_tohost),
        .p9_halted(p9_halted), .p9_tohost(p9_tohost),
        .p10_halted(p10_halted), .p10_tohost(p10_tohost),
        .p11_halted(p11_halted), .p11_tohost(p11_tohost),
        .e0_halted(e0_halted), .e0_tohost(e0_tohost),
        .e1_halted(e1_halted), .e1_tohost(e1_tohost),
        .e2_halted(e2_halted), .e2_tohost(e2_tohost),
        .e3_halted(e3_halted), .e3_tohost(e3_tohost),
        .e4_halted(e4_halted), .e4_tohost(e4_tohost),
        .e5_halted(e5_halted), .e5_tohost(e5_tohost),
        .e6_halted(e6_halted), .e6_tohost(e6_tohost),
        .e7_halted(e7_halted), .e7_tohost(e7_tohost),
        .e8_halted(e8_halted), .e8_tohost(e8_tohost),
        .e9_halted(e9_halted), .e9_tohost(e9_tohost),
        .e10_halted(e10_halted), .e10_tohost(e10_tohost),
        .e11_halted(e11_halted), .e11_tohost(e11_tohost),
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
        if (!$value$plusargs("EXPECT_P6_TOHOST=%d", expect_p6)) expect_p6 = 42;
        if (!$value$plusargs("EXPECT_P7_TOHOST=%d", expect_p7)) expect_p7 = 42;
        if (!$value$plusargs("EXPECT_P8_TOHOST=%d", expect_p8)) expect_p8 = 42;
        if (!$value$plusargs("EXPECT_P9_TOHOST=%d", expect_p9)) expect_p9 = 42;
        if (!$value$plusargs("EXPECT_P10_TOHOST=%d", expect_p10)) expect_p10 = 42;
        if (!$value$plusargs("EXPECT_P11_TOHOST=%d", expect_p11)) expect_p11 = 42;
        if (!$value$plusargs("EXPECT_E0_TOHOST=%d", expect_e0)) expect_e0 = 110;
        if (!$value$plusargs("EXPECT_E1_TOHOST=%d", expect_e1)) expect_e1 = 42;
        if (!$value$plusargs("EXPECT_E2_TOHOST=%d", expect_e2)) expect_e2 = 42;
        if (!$value$plusargs("EXPECT_E3_TOHOST=%d", expect_e3)) expect_e3 = 42;
        if (!$value$plusargs("EXPECT_E4_TOHOST=%d", expect_e4)) expect_e4 = 42;
        if (!$value$plusargs("EXPECT_E5_TOHOST=%d", expect_e5)) expect_e5 = 42;
        if (!$value$plusargs("EXPECT_E6_TOHOST=%d", expect_e6)) expect_e6 = 42;
        if (!$value$plusargs("EXPECT_E7_TOHOST=%d", expect_e7)) expect_e7 = 42;
        if (!$value$plusargs("EXPECT_E8_TOHOST=%d", expect_e8)) expect_e8 = 42;
        if (!$value$plusargs("EXPECT_E9_TOHOST=%d", expect_e9)) expect_e9 = 42;
        if (!$value$plusargs("EXPECT_E10_TOHOST=%d", expect_e10)) expect_e10 = 42;
        if (!$value$plusargs("EXPECT_E11_TOHOST=%d", expect_e11)) expect_e11 = 42;
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
            $display("FAIL: not all 24 cores halted within %0d cycles (p0=%b p1=%b p2=%b p3=%b p4=%b p5=%b p6=%b p7=%b p8=%b p9=%b p10=%b p11=%b e0=%b e1=%b e2=%b e3=%b e4=%b e5=%b e6=%b e7=%b e8=%b e9=%b e10=%b e11=%b)",
                      max_cycles, p0_halted, p1_halted, p2_halted, p3_halted, p4_halted, p5_halted, p6_halted, p7_halted, p8_halted, p9_halted, p10_halted, p11_halted, e0_halted, e1_halted, e2_halted, e3_halted, e4_halted, e5_halted, e6_halted, e7_halted, e8_halted, e9_halted, e10_halted, e11_halted);
        end else begin
            $display("All 24 cores halted after %0d cycles.", cycle_count);
            check_core(p0_tohost, expect_p0, "p0-core (pipelined)");
            check_core(p1_tohost, expect_p1, "p1-core (pipelined)");
            check_core(p2_tohost, expect_p2, "p2-core (pipelined)");
            check_core(p3_tohost, expect_p3, "p3-core (pipelined)");
            check_core(p4_tohost, expect_p4, "p4-core (pipelined)");
            check_core(p5_tohost, expect_p5, "p5-core (pipelined)");
            check_core(p6_tohost, expect_p6, "p6-core (pipelined)");
            check_core(p7_tohost, expect_p7, "p7-core (pipelined)");
            check_core(p8_tohost, expect_p8, "p8-core (pipelined)");
            check_core(p9_tohost, expect_p9, "p9-core (pipelined)");
            check_core(p10_tohost, expect_p10, "p10-core (pipelined)");
            check_core(p11_tohost, expect_p11, "p11-core (pipelined)");
            check_core(e0_tohost, expect_e0, "e0-core (single-cycle)");
            check_core(e1_tohost, expect_e1, "e1-core (single-cycle)");
            check_core(e2_tohost, expect_e2, "e2-core (single-cycle)");
            check_core(e3_tohost, expect_e3, "e3-core (single-cycle)");
            check_core(e4_tohost, expect_e4, "e4-core (single-cycle)");
            check_core(e5_tohost, expect_e5, "e5-core (single-cycle)");
            check_core(e6_tohost, expect_e6, "e6-core (single-cycle)");
            check_core(e7_tohost, expect_e7, "e7-core (single-cycle)");
            check_core(e8_tohost, expect_e8, "e8-core (single-cycle)");
            check_core(e9_tohost, expect_e9, "e9-core (single-cycle)");
            check_core(e10_tohost, expect_e10, "e10-core (single-cycle)");
            check_core(e11_tohost, expect_e11, "e11-core (single-cycle)");
            if (!any_fail) $display("PASS: all 24 cores matched their expected values");
        end

        $finish;
    end
endmodule
