// AxISA multi-core test: 47 real cpu_core.v instances in the 3D 4x3x4 mesh
// (rtl/soc_top.v) at once - AxISA's first mesh to genuinely exercise the
// Z axis (router.v/adapters already supported it, copied unmodified from
// rv32i_core - only the generator's own wiring logic was new). c0
// (shared_consumer.hex) busy-waits then reads c1's (shared_producer.hex)
// payload through the arbitrated NoC - the result (127) can only be
// correct if it genuinely observed the OTHER core's write, not just
// "all cores ran without crashing" (that weaker claim is what c2-c46,
// running completely independently on test1.hex, prove happens
// concurrently and correctly alongside the real cross-core traffic - now
// with 45 of them contending for the network instead of 1).
`timescale 1ns/1ps

`ifndef C0_INSTR_HEX
`define C0_INSTR_HEX "sw/shared_consumer.hex"
`endif
`ifndef C1_INSTR_HEX
`define C1_INSTR_HEX "sw/shared_producer.hex"
`endif
`ifndef C2_INSTR_HEX
`define C2_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C3_INSTR_HEX
`define C3_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C4_INSTR_HEX
`define C4_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C5_INSTR_HEX
`define C5_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C6_INSTR_HEX
`define C6_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C7_INSTR_HEX
`define C7_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C8_INSTR_HEX
`define C8_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C9_INSTR_HEX
`define C9_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C10_INSTR_HEX
`define C10_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C11_INSTR_HEX
`define C11_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C12_INSTR_HEX
`define C12_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C13_INSTR_HEX
`define C13_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C14_INSTR_HEX
`define C14_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C15_INSTR_HEX
`define C15_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C16_INSTR_HEX
`define C16_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C17_INSTR_HEX
`define C17_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C18_INSTR_HEX
`define C18_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C19_INSTR_HEX
`define C19_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C20_INSTR_HEX
`define C20_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C21_INSTR_HEX
`define C21_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C22_INSTR_HEX
`define C22_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C23_INSTR_HEX
`define C23_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C24_INSTR_HEX
`define C24_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C25_INSTR_HEX
`define C25_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C26_INSTR_HEX
`define C26_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C27_INSTR_HEX
`define C27_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C28_INSTR_HEX
`define C28_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C29_INSTR_HEX
`define C29_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C30_INSTR_HEX
`define C30_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C31_INSTR_HEX
`define C31_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C32_INSTR_HEX
`define C32_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C33_INSTR_HEX
`define C33_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C34_INSTR_HEX
`define C34_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C35_INSTR_HEX
`define C35_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C36_INSTR_HEX
`define C36_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C37_INSTR_HEX
`define C37_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C38_INSTR_HEX
`define C38_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C39_INSTR_HEX
`define C39_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C40_INSTR_HEX
`define C40_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C41_INSTR_HEX
`define C41_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C42_INSTR_HEX
`define C42_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C43_INSTR_HEX
`define C43_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C44_INSTR_HEX
`define C44_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C45_INSTR_HEX
`define C45_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C46_INSTR_HEX
`define C46_INSTR_HEX "sw/test1.hex"
`endif

module tb_soc;
    reg clk, reset;
    wire c0_halted, c1_halted, c2_halted, c3_halted, c4_halted, c5_halted, c6_halted, c7_halted, c8_halted, c9_halted, c10_halted, c11_halted, c12_halted, c13_halted, c14_halted, c15_halted, c16_halted, c17_halted, c18_halted, c19_halted, c20_halted, c21_halted, c22_halted, c23_halted, c24_halted, c25_halted, c26_halted, c27_halted, c28_halted, c29_halted, c30_halted, c31_halted, c32_halted, c33_halted, c34_halted, c35_halted, c36_halted, c37_halted, c38_halted, c39_halted, c40_halted, c41_halted, c42_halted, c43_halted, c44_halted, c45_halted, c46_halted, all_halted;
    wire [31:0] c0_tohost, c1_tohost, c2_tohost, c3_tohost, c4_tohost, c5_tohost, c6_tohost, c7_tohost, c8_tohost, c9_tohost, c10_tohost, c11_tohost, c12_tohost, c13_tohost, c14_tohost, c15_tohost, c16_tohost, c17_tohost, c18_tohost, c19_tohost, c20_tohost, c21_tohost, c22_tohost, c23_tohost, c24_tohost, c25_tohost, c26_tohost, c27_tohost, c28_tohost, c29_tohost, c30_tohost, c31_tohost, c32_tohost, c33_tohost, c34_tohost, c35_tohost, c36_tohost, c37_tohost, c38_tohost, c39_tohost, c40_tohost, c41_tohost, c42_tohost, c43_tohost, c44_tohost, c45_tohost, c46_tohost;

    integer expect_c0, expect_c1, expect_c2, expect_c3, expect_c4, expect_c5, expect_c6, expect_c7, expect_c8, expect_c9, expect_c10, expect_c11, expect_c12, expect_c13, expect_c14, expect_c15, expect_c16, expect_c17, expect_c18, expect_c19, expect_c20, expect_c21, expect_c22, expect_c23, expect_c24, expect_c25, expect_c26, expect_c27, expect_c28, expect_c29, expect_c30, expect_c31, expect_c32, expect_c33, expect_c34, expect_c35, expect_c36, expect_c37, expect_c38, expect_c39, expect_c40, expect_c41, expect_c42, expect_c43, expect_c44, expect_c45, expect_c46;
    integer max_cycles;
    integer cycle_count;
    integer any_fail;

    soc_top #(
        .INSTR_MEM_WORDS(1024), .DATA_MEM_WORDS(1024),
        .C0_INSTR_HEX(`C0_INSTR_HEX), .C1_INSTR_HEX(`C1_INSTR_HEX), .C2_INSTR_HEX(`C2_INSTR_HEX), .C3_INSTR_HEX(`C3_INSTR_HEX), .C4_INSTR_HEX(`C4_INSTR_HEX), .C5_INSTR_HEX(`C5_INSTR_HEX), .C6_INSTR_HEX(`C6_INSTR_HEX), .C7_INSTR_HEX(`C7_INSTR_HEX), .C8_INSTR_HEX(`C8_INSTR_HEX), .C9_INSTR_HEX(`C9_INSTR_HEX), .C10_INSTR_HEX(`C10_INSTR_HEX), .C11_INSTR_HEX(`C11_INSTR_HEX), .C12_INSTR_HEX(`C12_INSTR_HEX), .C13_INSTR_HEX(`C13_INSTR_HEX), .C14_INSTR_HEX(`C14_INSTR_HEX), .C15_INSTR_HEX(`C15_INSTR_HEX), .C16_INSTR_HEX(`C16_INSTR_HEX), .C17_INSTR_HEX(`C17_INSTR_HEX), .C18_INSTR_HEX(`C18_INSTR_HEX), .C19_INSTR_HEX(`C19_INSTR_HEX), .C20_INSTR_HEX(`C20_INSTR_HEX), .C21_INSTR_HEX(`C21_INSTR_HEX), .C22_INSTR_HEX(`C22_INSTR_HEX), .C23_INSTR_HEX(`C23_INSTR_HEX), .C24_INSTR_HEX(`C24_INSTR_HEX), .C25_INSTR_HEX(`C25_INSTR_HEX), .C26_INSTR_HEX(`C26_INSTR_HEX), .C27_INSTR_HEX(`C27_INSTR_HEX), .C28_INSTR_HEX(`C28_INSTR_HEX), .C29_INSTR_HEX(`C29_INSTR_HEX), .C30_INSTR_HEX(`C30_INSTR_HEX), .C31_INSTR_HEX(`C31_INSTR_HEX), .C32_INSTR_HEX(`C32_INSTR_HEX), .C33_INSTR_HEX(`C33_INSTR_HEX), .C34_INSTR_HEX(`C34_INSTR_HEX), .C35_INSTR_HEX(`C35_INSTR_HEX), .C36_INSTR_HEX(`C36_INSTR_HEX), .C37_INSTR_HEX(`C37_INSTR_HEX), .C38_INSTR_HEX(`C38_INSTR_HEX), .C39_INSTR_HEX(`C39_INSTR_HEX), .C40_INSTR_HEX(`C40_INSTR_HEX), .C41_INSTR_HEX(`C41_INSTR_HEX), .C42_INSTR_HEX(`C42_INSTR_HEX), .C43_INSTR_HEX(`C43_INSTR_HEX), .C44_INSTR_HEX(`C44_INSTR_HEX), .C45_INSTR_HEX(`C45_INSTR_HEX), .C46_INSTR_HEX(`C46_INSTR_HEX)
    ) dut (
        .clk(clk), .reset(reset),
        .c0_halted(c0_halted), .c0_tohost(c0_tohost),
        .c1_halted(c1_halted), .c1_tohost(c1_tohost),
        .c2_halted(c2_halted), .c2_tohost(c2_tohost),
        .c3_halted(c3_halted), .c3_tohost(c3_tohost),
        .c4_halted(c4_halted), .c4_tohost(c4_tohost),
        .c5_halted(c5_halted), .c5_tohost(c5_tohost),
        .c6_halted(c6_halted), .c6_tohost(c6_tohost),
        .c7_halted(c7_halted), .c7_tohost(c7_tohost),
        .c8_halted(c8_halted), .c8_tohost(c8_tohost),
        .c9_halted(c9_halted), .c9_tohost(c9_tohost),
        .c10_halted(c10_halted), .c10_tohost(c10_tohost),
        .c11_halted(c11_halted), .c11_tohost(c11_tohost),
        .c12_halted(c12_halted), .c12_tohost(c12_tohost),
        .c13_halted(c13_halted), .c13_tohost(c13_tohost),
        .c14_halted(c14_halted), .c14_tohost(c14_tohost),
        .c15_halted(c15_halted), .c15_tohost(c15_tohost),
        .c16_halted(c16_halted), .c16_tohost(c16_tohost),
        .c17_halted(c17_halted), .c17_tohost(c17_tohost),
        .c18_halted(c18_halted), .c18_tohost(c18_tohost),
        .c19_halted(c19_halted), .c19_tohost(c19_tohost),
        .c20_halted(c20_halted), .c20_tohost(c20_tohost),
        .c21_halted(c21_halted), .c21_tohost(c21_tohost),
        .c22_halted(c22_halted), .c22_tohost(c22_tohost),
        .c23_halted(c23_halted), .c23_tohost(c23_tohost),
        .c24_halted(c24_halted), .c24_tohost(c24_tohost),
        .c25_halted(c25_halted), .c25_tohost(c25_tohost),
        .c26_halted(c26_halted), .c26_tohost(c26_tohost),
        .c27_halted(c27_halted), .c27_tohost(c27_tohost),
        .c28_halted(c28_halted), .c28_tohost(c28_tohost),
        .c29_halted(c29_halted), .c29_tohost(c29_tohost),
        .c30_halted(c30_halted), .c30_tohost(c30_tohost),
        .c31_halted(c31_halted), .c31_tohost(c31_tohost),
        .c32_halted(c32_halted), .c32_tohost(c32_tohost),
        .c33_halted(c33_halted), .c33_tohost(c33_tohost),
        .c34_halted(c34_halted), .c34_tohost(c34_tohost),
        .c35_halted(c35_halted), .c35_tohost(c35_tohost),
        .c36_halted(c36_halted), .c36_tohost(c36_tohost),
        .c37_halted(c37_halted), .c37_tohost(c37_tohost),
        .c38_halted(c38_halted), .c38_tohost(c38_tohost),
        .c39_halted(c39_halted), .c39_tohost(c39_tohost),
        .c40_halted(c40_halted), .c40_tohost(c40_tohost),
        .c41_halted(c41_halted), .c41_tohost(c41_tohost),
        .c42_halted(c42_halted), .c42_tohost(c42_tohost),
        .c43_halted(c43_halted), .c43_tohost(c43_tohost),
        .c44_halted(c44_halted), .c44_tohost(c44_tohost),
        .c45_halted(c45_halted), .c45_tohost(c45_tohost),
        .c46_halted(c46_halted), .c46_tohost(c46_tohost),
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
        if (!$value$plusargs("EXPECT_C0_TOHOST=%d", expect_c0)) expect_c0 = 127;
        if (!$value$plusargs("EXPECT_C1_TOHOST=%d", expect_c1)) expect_c1 = 77;
        if (!$value$plusargs("EXPECT_C2_TOHOST=%d", expect_c2)) expect_c2 = 200;
        if (!$value$plusargs("EXPECT_C3_TOHOST=%d", expect_c3)) expect_c3 = 200;
        if (!$value$plusargs("EXPECT_C4_TOHOST=%d", expect_c4)) expect_c4 = 200;
        if (!$value$plusargs("EXPECT_C5_TOHOST=%d", expect_c5)) expect_c5 = 200;
        if (!$value$plusargs("EXPECT_C6_TOHOST=%d", expect_c6)) expect_c6 = 200;
        if (!$value$plusargs("EXPECT_C7_TOHOST=%d", expect_c7)) expect_c7 = 200;
        if (!$value$plusargs("EXPECT_C8_TOHOST=%d", expect_c8)) expect_c8 = 200;
        if (!$value$plusargs("EXPECT_C9_TOHOST=%d", expect_c9)) expect_c9 = 200;
        if (!$value$plusargs("EXPECT_C10_TOHOST=%d", expect_c10)) expect_c10 = 200;
        if (!$value$plusargs("EXPECT_C11_TOHOST=%d", expect_c11)) expect_c11 = 200;
        if (!$value$plusargs("EXPECT_C12_TOHOST=%d", expect_c12)) expect_c12 = 200;
        if (!$value$plusargs("EXPECT_C13_TOHOST=%d", expect_c13)) expect_c13 = 200;
        if (!$value$plusargs("EXPECT_C14_TOHOST=%d", expect_c14)) expect_c14 = 200;
        if (!$value$plusargs("EXPECT_C15_TOHOST=%d", expect_c15)) expect_c15 = 200;
        if (!$value$plusargs("EXPECT_C16_TOHOST=%d", expect_c16)) expect_c16 = 200;
        if (!$value$plusargs("EXPECT_C17_TOHOST=%d", expect_c17)) expect_c17 = 200;
        if (!$value$plusargs("EXPECT_C18_TOHOST=%d", expect_c18)) expect_c18 = 200;
        if (!$value$plusargs("EXPECT_C19_TOHOST=%d", expect_c19)) expect_c19 = 200;
        if (!$value$plusargs("EXPECT_C20_TOHOST=%d", expect_c20)) expect_c20 = 200;
        if (!$value$plusargs("EXPECT_C21_TOHOST=%d", expect_c21)) expect_c21 = 200;
        if (!$value$plusargs("EXPECT_C22_TOHOST=%d", expect_c22)) expect_c22 = 200;
        if (!$value$plusargs("EXPECT_C23_TOHOST=%d", expect_c23)) expect_c23 = 200;
        if (!$value$plusargs("EXPECT_C24_TOHOST=%d", expect_c24)) expect_c24 = 200;
        if (!$value$plusargs("EXPECT_C25_TOHOST=%d", expect_c25)) expect_c25 = 200;
        if (!$value$plusargs("EXPECT_C26_TOHOST=%d", expect_c26)) expect_c26 = 200;
        if (!$value$plusargs("EXPECT_C27_TOHOST=%d", expect_c27)) expect_c27 = 200;
        if (!$value$plusargs("EXPECT_C28_TOHOST=%d", expect_c28)) expect_c28 = 200;
        if (!$value$plusargs("EXPECT_C29_TOHOST=%d", expect_c29)) expect_c29 = 200;
        if (!$value$plusargs("EXPECT_C30_TOHOST=%d", expect_c30)) expect_c30 = 200;
        if (!$value$plusargs("EXPECT_C31_TOHOST=%d", expect_c31)) expect_c31 = 200;
        if (!$value$plusargs("EXPECT_C32_TOHOST=%d", expect_c32)) expect_c32 = 200;
        if (!$value$plusargs("EXPECT_C33_TOHOST=%d", expect_c33)) expect_c33 = 200;
        if (!$value$plusargs("EXPECT_C34_TOHOST=%d", expect_c34)) expect_c34 = 200;
        if (!$value$plusargs("EXPECT_C35_TOHOST=%d", expect_c35)) expect_c35 = 200;
        if (!$value$plusargs("EXPECT_C36_TOHOST=%d", expect_c36)) expect_c36 = 200;
        if (!$value$plusargs("EXPECT_C37_TOHOST=%d", expect_c37)) expect_c37 = 200;
        if (!$value$plusargs("EXPECT_C38_TOHOST=%d", expect_c38)) expect_c38 = 200;
        if (!$value$plusargs("EXPECT_C39_TOHOST=%d", expect_c39)) expect_c39 = 200;
        if (!$value$plusargs("EXPECT_C40_TOHOST=%d", expect_c40)) expect_c40 = 200;
        if (!$value$plusargs("EXPECT_C41_TOHOST=%d", expect_c41)) expect_c41 = 200;
        if (!$value$plusargs("EXPECT_C42_TOHOST=%d", expect_c42)) expect_c42 = 200;
        if (!$value$plusargs("EXPECT_C43_TOHOST=%d", expect_c43)) expect_c43 = 200;
        if (!$value$plusargs("EXPECT_C44_TOHOST=%d", expect_c44)) expect_c44 = 200;
        if (!$value$plusargs("EXPECT_C45_TOHOST=%d", expect_c45)) expect_c45 = 200;
        if (!$value$plusargs("EXPECT_C46_TOHOST=%d", expect_c46)) expect_c46 = 200;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 200;

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
            $display("FAIL: not all 47 cores halted within %0d cycles (c0=%b c1=%b c2=%b c3=%b c4=%b c5=%b c6=%b c7=%b c8=%b c9=%b c10=%b c11=%b c12=%b c13=%b c14=%b c15=%b c16=%b c17=%b c18=%b c19=%b c20=%b c21=%b c22=%b c23=%b c24=%b c25=%b c26=%b c27=%b c28=%b c29=%b c30=%b c31=%b c32=%b c33=%b c34=%b c35=%b c36=%b c37=%b c38=%b c39=%b c40=%b c41=%b c42=%b c43=%b c44=%b c45=%b c46=%b)",
                      max_cycles, c0_halted, c1_halted, c2_halted, c3_halted, c4_halted, c5_halted, c6_halted, c7_halted, c8_halted, c9_halted, c10_halted, c11_halted, c12_halted, c13_halted, c14_halted, c15_halted, c16_halted, c17_halted, c18_halted, c19_halted, c20_halted, c21_halted, c22_halted, c23_halted, c24_halted, c25_halted, c26_halted, c27_halted, c28_halted, c29_halted, c30_halted, c31_halted, c32_halted, c33_halted, c34_halted, c35_halted, c36_halted, c37_halted, c38_halted, c39_halted, c40_halted, c41_halted, c42_halted, c43_halted, c44_halted, c45_halted, c46_halted);
            any_fail = 1;
        end else begin
            $display("All 47 cores halted after %0d cycles.", cycle_count);
            check_core(c0_tohost, expect_c0, "c0-core (consumer)");
            check_core(c1_tohost, expect_c1, "c1-core (producer)");
            check_core(c2_tohost, expect_c2, "c2-core (indep)");
            check_core(c3_tohost, expect_c3, "c3-core (indep)");
            check_core(c4_tohost, expect_c4, "c4-core (indep)");
            check_core(c5_tohost, expect_c5, "c5-core (indep)");
            check_core(c6_tohost, expect_c6, "c6-core (indep)");
            check_core(c7_tohost, expect_c7, "c7-core (indep)");
            check_core(c8_tohost, expect_c8, "c8-core (indep)");
            check_core(c9_tohost, expect_c9, "c9-core (indep)");
            check_core(c10_tohost, expect_c10, "c10-core (indep)");
            check_core(c11_tohost, expect_c11, "c11-core (indep)");
            check_core(c12_tohost, expect_c12, "c12-core (indep)");
            check_core(c13_tohost, expect_c13, "c13-core (indep)");
            check_core(c14_tohost, expect_c14, "c14-core (indep)");
            check_core(c15_tohost, expect_c15, "c15-core (indep)");
            check_core(c16_tohost, expect_c16, "c16-core (indep)");
            check_core(c17_tohost, expect_c17, "c17-core (indep)");
            check_core(c18_tohost, expect_c18, "c18-core (indep)");
            check_core(c19_tohost, expect_c19, "c19-core (indep)");
            check_core(c20_tohost, expect_c20, "c20-core (indep)");
            check_core(c21_tohost, expect_c21, "c21-core (indep)");
            check_core(c22_tohost, expect_c22, "c22-core (indep)");
            check_core(c23_tohost, expect_c23, "c23-core (indep)");
            check_core(c24_tohost, expect_c24, "c24-core (indep)");
            check_core(c25_tohost, expect_c25, "c25-core (indep)");
            check_core(c26_tohost, expect_c26, "c26-core (indep)");
            check_core(c27_tohost, expect_c27, "c27-core (indep)");
            check_core(c28_tohost, expect_c28, "c28-core (indep)");
            check_core(c29_tohost, expect_c29, "c29-core (indep)");
            check_core(c30_tohost, expect_c30, "c30-core (indep)");
            check_core(c31_tohost, expect_c31, "c31-core (indep)");
            check_core(c32_tohost, expect_c32, "c32-core (indep)");
            check_core(c33_tohost, expect_c33, "c33-core (indep)");
            check_core(c34_tohost, expect_c34, "c34-core (indep)");
            check_core(c35_tohost, expect_c35, "c35-core (indep)");
            check_core(c36_tohost, expect_c36, "c36-core (indep)");
            check_core(c37_tohost, expect_c37, "c37-core (indep)");
            check_core(c38_tohost, expect_c38, "c38-core (indep)");
            check_core(c39_tohost, expect_c39, "c39-core (indep)");
            check_core(c40_tohost, expect_c40, "c40-core (indep)");
            check_core(c41_tohost, expect_c41, "c41-core (indep)");
            check_core(c42_tohost, expect_c42, "c42-core (indep)");
            check_core(c43_tohost, expect_c43, "c43-core (indep)");
            check_core(c44_tohost, expect_c44, "c44-core (indep)");
            check_core(c45_tohost, expect_c45, "c45-core (indep)");
            check_core(c46_tohost, expect_c46, "c46-core (indep)");
            if (!any_fail) $display("PASS: cross-core communication verified (c0 read c1's write)");
        end

        $finish;
    end
endmodule
